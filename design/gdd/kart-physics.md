# Kart Physics — Design Document

---
**Status**: Reverse-Documented (Draft, pending owner review)
**Source**: `src/legacy/vehicle/kart_sim.gd` (`tick` integration and sink branch, `_constrain_to_track`, `_wall_contact`, `_ride_surface`, `_take_off`, `_land`, `_fell_off`, `_start_sinking`, `_respawn`, `_snap_to_surface`, `resolve_kart_contact`, `apply_received_bump`, `_take_bump`, `levels_apart`, `push_apart`, `clamp_to_walls`, `separate_for_display`, `_push_off_body`, `_mover_stop`); `src/legacy/main.gd` (`_resolve_kart_contacts`, `_separate_karts`, `_push_of`, `_on_bump_received`, lines 540-611); `assets/data/vehicles/armored_cart.tres`; `assets/data/vehicles/war_bike.tres`; `assets/data/net/net_config.tres` (`bot_push_mult`, `contact_passes`); `assets/tracks/castle_circuit/castle_circuit.tres`, `assets/tracks/dungeon_depths/dungeon_depths.tres` (`wall_drag_mult`, respawn fields)
**Rebuild contract**: `docs/architecture/adr-0003-kart-physics-model.md` (v3, Proposed) — the source of truth for this document; `docs/architecture/adr-0001-simulation-conventions-and-code-layout.md` §3 (orientation, per-body gravity), §5 (tick); `docs/architecture/adr-0002-collision-backend-and-surface-attributes.md` (v5, Proposed: `CollisionQuery`, `GroundHit`, `WallHit`, movers)
**Date**: 2026-11-22
**Verified By**: pending owner review
**Implementation Status**: Implemented in the frozen 2.5D game as part of `KartSim`; to be built fresh as `KartBody` + `KartContactSolver` in `src/core/kart/` (story 022)
**Systems index**: row 6 (Kart Physics)
---

> **Provenance — reverse-documented.**
> Reverse-documented from `src/legacy` at commit HEAD (`59614ff`) on 2026-11-22, against ADR-0003 v3.
> Every number in this document is copied from the code, a data file or ADR-0003, and the source is
> named next to it. Derived numbers (examples, settle times, equilibria) show their arithmetic. Where
> the *reason* for a rule or value had to be inferred from the code, it is marked **INTENT UNKNOWN**.
> Where ADR-0003 is silent and this document fills the gap, the rule is marked **[inferred — confirm]**.
> Nothing marked "proposal" is adopted; those items are listed in **Open decisions for the owner**.
>
> **What this document is for.** It states the physical behaviour of the kart body — how it meets
> walls, the ground, the air, other karts and moving platforms — as the design the rebuilt core must
> match (ADR-0003 parity rule), and records where the 3D rebuild deliberately departs from the frozen
> 2.5D kart. **The control law (speed, steering, grip choice, drift, boost, surfaces, tricks) is in
> `design/gdd/driving-and-drift.md` and is not repeated here.**

---

## Summary

Kart Physics is the kart's body: it takes the control law's `KartIntent` each tick and moves the kart
through the world — it slides along walls and loses speed when it hits them, rides the ground on one
damped spring, takes off at lips and lands with an impact, tilts its up toward the ground normal,
carries the kart on moving platforms, and resolves kart-vs-kart bumps with the frozen
owner-authoritative model. On the new core it is `KartBody` and `KartContactSolver` (Core layer,
`src/core/kart/`), and it publishes the `KartSnapshot` that Driving, presentation, the network and
ghosts all read.

---

## 1. Overview

Each simulation tick (`SIM_DT = 1/60 s`, ADR-0001 §5), the body receives a `KartIntent` (yaw rate,
target speed along the heading, grip, hop) from Driving & Drift. It turns the heading, adds slope
gravity to the commanded speed, swings its velocity toward the heading at the given grip, and proposes
a move. A sphere sweep against the wall layer slides that move along walls (at most 3 sweeps), pushes
the kart out if it starts a tick inside a wall, and applies the frozen wall response: a glancing
contact scrapes speed off, a steep one is an impact that costs up to 60% (Cart) or 70% (Bike) of speed.
Two to four rays then find the ground; a single spring holds the kart at ride height, and when the
ground drops away the kart flies ballistically under its own gravity vector until it lands. The up
vector eases toward the ground normal (or against gravity in the air), so banks and slopes tilt the
kart physically. After every kart has moved, a contact solver finds touching karts using course
distance, splits separation and knock by push weight, costs speed on impact, and sends the other PC
its share when the other kart is remote. Standing on a moving platform carries the kart by the
platform's exact pose change. The body knows nothing of drift, boost, surfaces or the network.

---

## 2. Player Fantasy

*A heavy armoured cart that feels planted: it hugs the road over crests, thumps down off a jump,
scrapes along a castle wall with sparks instead of stopping dead, and when a friend's war bike
slams into its flank the bike is the one that goes flying.*

- **Primary MDA aesthetics:** **Sensation** (game-concept rank 3: speed, impacts, landings — the body
  is what makes a hit or a landing physical) and **Challenge** (rank 2: walls punish a missed line in
  proportion to the mistake — a graze costs a little, a head-on costs most of the speed).
- **Secondary aesthetic: Fellowship.** Bumping friends is the most direct physical interaction in an
  online race. It must read as fair on every PC.
- **Competence (SDT):** wall cost scales with the angle of incidence (§4.5-4.6), so the player can read
  *why* they lost speed and how to lose less next lap. No wall-stuck interval is allowed (parity gate).
- **Autonomy (SDT):** the two vehicles are an **asymmetric balance**: the Cart pushes harder
  (`bump_push_mult` 1.5 vs 0.7) and loses little speed in a bump (10% vs 40% at full strength); the
  Bike accelerates faster and drifts tighter (driving-and-drift.md §3.2) but is "knocked harder"
  (brief). Choosing a vehicle is choosing how you want to meet the pack.
- **Pillar 1 — Online with friends first:** each PC simulates only its own karts; a bump against a
  remote kart is felt locally at once and by the other kart's owner on its next tick, and the max-merge
  dedup guarantees a contact both PCs detect is felt once (§3.1.7). Every rule is deterministic.
- **Pillar 2 — Drift is the skill:** the body never decides feel. Walls slow but do not trap
  (slide loop, turnback — Open decision P2), so the cost of a bad drift line is speed, not a stall.
- **Pillar 3 — Mario Kart-grade quality:** real 3D meshes, slopes, banks, decks and moving platforms,
  with the frozen feel as the floor (ADR-0003 parity rule).

---

## 3. Detailed Design

`SIM_DT = 1/60 s` (ADR-0001 §5). "Up plane" means the plane perpendicular to the body's `up`.
Vehicle numbers are given as **Cart / Bike** (`armored_cart.tres` / `war_bike.tres`).

### 3.1 Core Mechanics

#### 3.1.1 Ownership boundary (ADR-0003 §1, §3)

- The body reads **only** `KartIntent` from Driving: `yaw_rate`, `target_speed`, `grip`, `hop`, plus
  `steer` and `throttle` passed through to the snapshot. It never reads `DriveState`, `DriverInput`
  or `SurfaceType`.
- The body **owns**: integration, slope gravity, wall queries and wall response, the wall-slide grip
  clamp, ground queries, suspension, takeoff, air, landing, up smoothing and the basis, knock, overlap
  push-out, kart-vs-kart contact, platform carry, and the `KartSnapshot`.
- **Speed has one integrator.** Driving computes `target_speed` from `snapshot.speed` (driving-and-drift.md
  §3.3 item 3). The body adds slope gravity and then applies wall and bump losses to `speed`. Every
  physics loss is read by the next `drive()`, as in the frozen kart (`_take_bump` and `_wall_contact`
  write `speed`; the next `tick` reads it).

#### 3.1.2 Body state and orientation (ADR-0003 §2; ADR-0001 §3)

- Orientation is a `Basis` (−Z heading, +Y up). A scalar yaw is **derived only** (`yaw_derived()`, for
  HUD and minimap), never stored.
- Gravity is a **per-body vector**, default `−world_up × air_gravity` (20.0 / 20.0 m/s²). Anti-gravity
  (ADR-0009) changes only this vector and the up target. `Vector3.DOWN` never appears in the body.
- `velocity` is the driving velocity relative to the support. `knock` (bump knock and mover shove) is
  kept separately on the up plane, so grip cannot cancel a shove at once (frozen comment, `kart_sim.gd:162`).
- Full field list: ADR-0003 §2 (`position`, `basis`, `gravity`, `velocity`, `speed`, `knock`,
  `pending_push`, `ground_normal`, `ride_offset`, `ride_velocity`, `grounded`, `air_time`,
  `hop_airborne`, `support_id`, `support_velocity`, `surface_id`, `last_heading`, `wall_cooldown`,
  `wall_slide_time`, `bump_cooldown`, `pair_bump_mag`, `pair_bump_timer`, `events`, `tick`).

#### 3.1.3 Per-tick step order (ADR-0003 §4)

For tick *n*, per kart simulated on this PC, in `RacerRegistry` slot order:

1. **Received events** (`apply_event`): remote bumps (max-merge knock, speed loss behind
   `bump_cooldown`), respawn, launch, hold. Then the snapshot is **refreshed** so `drive()` sees them.
2. **Intent:** the controller calls `drive()` (Driving & Drift) and gets the `KartIntent`.
3. **Integrate** (§3.1.4).
4. **Wall sweep slide loop** with overlap push-out (§3.1.5, §3.1.6).
5. **Ground cast** at the resolved point (§3.1.8).
6. **Suspension, air, landing** (§3.1.8, §3.1.9). These moves are **not swept**.
7. **Up smoothing and basis rebuild** (§3.1.10).
8. **Timers and knock decay** (`wall_cooldown`, `bump_cooldown`, pair timers, `wall_slide_time`; §4.13).
9. **Pre-contact snapshot.**

After every simulated kart has stepped: 10. course progress (ADR-0004); 11. kart-vs-kart contact
(§3.1.11); 12. **end-of-tick snapshot**, then `events` cleared; 13. same-tick local effects (hazard and
pad tests; the controller copies took-off and landed events into `DriveState` — the **only** path by
which air events reach Driving).

**Why walls before ground** (TD-approved deviation): rays cast before the slide would read the ground
on the far side of a wall and cause false takeoffs and wrong surface ids.

#### 3.1.4 Integration (ADR-0003 §4 step 3; frozen `tick` lines 575-588, `_update_speed` line 618)

1. Rotate the heading about `up` by `yaw_rate × dt`.
2. **Grounded:**
   - `speed = target_speed + slope_gravity × (ĝ · heading) × dt` (§4.1). Only the component along the
     heading counts; a bank adds no sideways force (frozen comment, `kart_sim.gd:615-616`).
   - Effective grip `= min(intent.grip, wall_slide_grip)` while `wall_slide_time > 0`, otherwise
     `intent.grip` (frozen `kart_sim.gd:585-586`; `wall_slide_grip` 2.2 / 2.2).
   - `velocity` lerps toward `heading × speed` by `clamp(grip × dt, 0, 1)` (§4.2), then loses its
     component along `up`.
3. **Airborne:** `velocity += gravity × dt`. No grip, throttle, brake or drag (frozen comment,
   `kart_sim.gd:551`). Driving still supplies the air yaw rate.
4. **Proposed motion** `= (velocity + knock) × dt + pending_push + carry` (§4.3). `pending_push` is last
   tick's kart-vs-kart separation; `carry` is the platform pose delta (§3.1.12), else 0.

#### 3.1.5 Walls: slide loop and wall response (ADR-0003 §5; frozen `_constrain_to_track`, `_wall_contact`)

**Shape.** A sphere of radius `radius` (1.0 / 0.85 m, the frozen wall clamp radius, `kart_sim.gd:712`),
centred at `position + up × sweep_center_height` (default = `radius`). Walls are on their own collision
layer (ADR-0002), so the sphere never catches the ground.

**Slide loop** (at most `slide_max_sweeps` = 3 sweeps per tick):
1. Sweep from `from` to `to`.
2. **Hit with `0 ≤ fraction < 1`:** advance along the motion by `max(fraction × L − wall_skin, 0)`
   (`wall_skin` 0.02 m; L = remaining motion length). Take the wall normal **projected onto the up plane
   and normalised** (a wall never lifts or presses the kart). Remove the into-wall component from the
   remaining motion — relative to the wall's `collider_velocity` for movers — and sweep the remainder.
3. **Touch** (`fraction == 1.0`, `started_inside = false`, ADR-0002 amendment): move the full motion,
   no slide; the wall response runs as a scrape if this is the first contact this tick; velocity loses
   its into-wall component.
4. **`started_inside`:** overlap resolution (§3.1.6), inside the loop.
5. **Cap reached:** the remaining motion is dropped; the kart stays at the last safe point.

**Wall response** — runs on the **first** wall contact each tick only (ADR-0003 §5 step 3):
1. **Incidence angle** θ (degrees) between the velocity and the wall tangent (§4.4). The frozen kart
   computes it only when the velocity points into the wall (`into_wall > 0`, `kart_sim.gd:729`).
2. **Impact** when `θ ≥ wall_impact_threshold_angle` (25° / 25°) **and** `wall_cooldown ≤ 0`:
   - `speed *= 1 − wall_impact_max_speed_loss × t`, with `t` from §4.5 (max loss 0.6 / 0.7);
   - `wall_slide_time = wall_impact_slide_time` (0.25 / 0.25 s) — the grip clamp of §3.1.4;
   - `wall_cooldown = wall_hit_cooldown` (0.5 / 0.5 s);
   - event: wall hit, hard, angle θ.
   - Note: ADR-0003 says "above" the threshold; the frozen test is `>=` (`kart_sim.gd:1038`). This
     document keeps `>=` for parity.
3. **Otherwise scrape:** `speed *= 1 − wall_friction_drag × mult(θ) × scrape_drag × dt` (§4.6), where
   `scrape_drag` is the `WallAttrSet` entry for the hit's `wall_attr` (ADR-0002; replaces the frozen
   per-track `wall_drag_mult`, 2.0 on both shipped tracks — Open decision P7). Event: wall hit, soft.
4. **Velocity into the wall:** removed, plus a bounce (Open decision **P1**). The frozen kart reflects
   it with the per-vehicle `bump_knockback` (1.4 / 1.9): `velocity −= n × into × bump_knockback`, so
   the Cart rebounds at 0.4× and the Bike at 0.9× the into-wall speed (§4.7). ADR-0003 instead takes the
   bounce from the wall attribute.
5. **Knock into the wall:** removed (frozen: "A wall stops the part of a bump knock that drives into
   it", `kart_sim.gd:726-727`). ADR-0003 is silent on knock; **[inferred — confirm]**: the body removes
   `max(knock · n_h, 0)` along `n_h` on every wall contact, not only the first.
6. **Turnback** (frozen, `kart_sim.gd:734-741`, `1039-1040`): while touching or while
   `wall_slide_time > 0`, and only when `speed > 0`, the heading turns toward the track direction at
   `lerp(wall_turnback_min_rate, wall_turnback_max_rate, clamp(θ / wall_impact_max_angle, 0, 1))`
   (30-90 °/s, §4.8). **ADR-0003 does not carry this rule.** Open decision **P2**.

#### 3.1.6 Overlap resolution (`started_inside`) (ADR-0003 §6)

`sweep_walls` returns at once with `fraction = 0` when the sphere starts inside a wall or a mover (the
cast is blind from an overlapped start, probe F). Definitions: c = sphere centre, p = `hit.point`,
n = **raw** rest normal, `n_h` = n projected onto the up plane, r = sweep radius.

1. **Wall-top guard (checked first):** if `|n_h| < WALL_NORMAL_MIN` (0.3, a named const) or
   `|c − p| < CONTACT_POINT_EPSILON` (1e-4 m): no horizontal push-out and no wall response this sweep;
   set `depenetrated` with the guard cause; continue with the remaining motion. The ground cast or Fall
   & Respawn handles a kart over a wall top.
2. **Push-out otherwise:** depth `d = r − (c − p) · n`; move `from` along `n̂_h` by
   `min(d / (n · n̂_h) + wall_skin, max_depenetration_per_tick)` (§4.9; cap 0.25 m); remove the
   velocity's into-wall component; set `depenetrated`; retry. The retry counts against the 3-sweep cap.
   An inner corner takes 2 push-out sweeps (rest returns only the deepest contact).
3. **A mover that moved into the kart:** the same push-out, and the into-kart part of the mover's
   `collider_velocity` is added to **`knock`** (capped at `bump_knock_max`), not to `velocity`. Whether
   the hit also spins the kart is Track Hazards' call.
4. A kart whose centre is fully behind a one-sided wall is not seen (`backface_collision = false`);
   Fall & Respawn recovers it through `CourseProgress` route `outside`.

#### 3.1.7 Knock (ADR-0003 §2, §4 step 8; frozen `kart_sim.gd:588-589`, `_take_bump`)

- `knock` is added to the motion each tick (§3.1.4 step 4), decays as `knock *= exp(−bump_knock_decay × dt)`
  (6.0 / 6.0 1/s), and its length is capped at `bump_knock_max` (16.0 / 22.0 m/s) whenever it is added
  to ("Pile-ups add several bumps at once: cap the total so a kart is never launched", `kart_sim.gd:442`).
- Sources: kart-vs-kart bumps (§3.1.11), received bump events, mover shoves (§3.1.6).

#### 3.1.8 Ground and suspension (ADR-0003 §5; frozen `_ride_surface`)

**Ground rays.** One ray per entry of `ground_probe_points` (kart-local metres; new field):
- Cart default: the four wheel positions of `VehicleVisualStats` — x = ±0.75 (`wheel_offset_x`),
  z = −0.7 (front, `wheel_front_z`) and 0.75 (rear, `wheel_rear_z`).
- Bike: `wheel_offset_x = 0.0`, so 2 rays on the centre line at z = −0.7 and 0.75; a centre ray is
  added if testing shows rocking (ADR-0003 §5).
- Each ray starts `probe_lift` (0.5 m) above its probe point along up and is cast along −up, max
  distance `probe_lift + air_takeoff_gap + ride_snap_margin` = 0.5 + 0.45 + 0.3 = **1.25 m**.
- From the hits: **contact height** = mean hit offset along up; **contact normal** = normalised sum of
  hit normals (the `ground_normal` up target); **surface id** = majority, ties to the lowest probe index,
  kept while airborne, starts at 0 (road); **support** = collider id and point velocity of the hit
  nearest the centre of mass, ties to the lower probe index.

**Step-up contract (with ADR-0005).** The maximum step-up height is `probe_lift` (0.5 m). Anything a
kart must not climb — a rise taller than 0.5 m, or ground steeper than the drivable limit — **must be
on the wall layer**; ADR-0005's `track_check` enforces it on every baked track.

**Ride spring** (one damped spring along up; decision in ADR-0003 §5, values frozen):
- `ride_offset` (gap above the contact plane) follows the plane through `ride_spring` 900 and
  `ride_damping` 42, with the contact plane's own rate as feed-forward, clamped to
  `±ride_max_target_speed` (30 m/s) (§4.10). "So a steady climb has no lag" (frozen comment,
  `kart_sim.gd:865`).
- Clamped to `[0, ride_max_gap]` = [0, 0.3 m]: the surface is a hard floor, and the kart never floats
  more than 0.3 m above it. At the floor clamp the rate becomes `max(rate, target_rate)`; at the
  ceiling clamp `min(rate, target_rate)` (frozen `kart_sim.gd:901-906`).
- Pitch and roll come only from the smoothed normal (§3.1.10). No per-wheel springs.
- The feed-forward `target_rate` on the mesh is **[inferred — confirm]**: the change of contact height
  along up since last tick over `dt` (the frozen `(target − _surface_target) / dt`).

#### 3.1.9 Takeoff, air and landing (ADR-0003 §5; frozen `_ride_surface`, `_take_off`, `_land`)

- **Takeoff** when grounded and either no ray hits, or the gap above the new contact plane exceeds
  `air_takeoff_gap` (0.45 / 0.45 m). The kart keeps its velocity (the climb rate at the lip). On a mover,
  the support's point velocity is folded into `velocity` **once** (no carry afterwards). Event: took-off.
- Because the grounded gap is clamped at 0.3 m, a takeoff needs the support to drop away by more than
  0.45 m relative to the kart in one tick — a ramp lip, a ledge, a deck edge — not a gentle crest
  (frozen behaviour: the kart is held to the road over crests).
- **Air:** ballistic under `gravity` (§4.11); `air_time += dt`; up eases toward `−gravity.normalized()`
  at `air_up_smoothing`.
- **Landing** when airborne and the gap reaches ≤ 0: snap to the plane; impact speed = into-ground
  speed relative to the support (frozen `impact = max(target_v − vertical_velocity, 0)`,
  `kart_sim.gd:923`); on a mover, subtract the up-plane part of `support_velocity` from `velocity`;
  remove the velocity component along the new up; **then** `speed = velocity · heading`. Event: landed
  (airtime, impact, `hop_airborne`). The trick boost is paid by Driving (driving-and-drift.md §3.1.10).
- **Hop** (`intent.hop`): when grounded, add `hop_speed` to `ride_velocity`, so any takeoff goes
  through the normal `air_takeoff_gap` path. **`hop_speed` = 0.0 through parity** (visual hop only).
  A flight started by a hop alone sets `hop_airborne`; how "alone" is detected is **[inferred — confirm]**
  (a takeoff by gap with rays still hitting, within the hop's rise). Physical hop: Open decision **D2**
  (driving-and-drift.md) — see P9 for a blocking gap.

#### 3.1.10 Up smoothing and basis (ADR-0003 §4 step 7; ADR-0001 §3)

- `up = up.slerp(target, 1 − exp(−rate × dt))` (§4.12). Grounded: target = `ground_normal`, rate =
  `up_smoothing` (14). Airborne: target = `−gravity.normalized()`, rate = `air_up_smoothing` (5). The
  defaults are the frozen *visual* `surface_tilt_smoothing` 14 and `tilt_smoothing` 5; banking is now
  physical (ADR-0001 §4).
- **Antiparallel guard:** if `up · target < UP_ANTIPARALLEL_DOT` (−0.9999), rotate `up` about the heading
  axis by the same fraction of π instead.
- **Basis rebuild every tick:** heading = −basis.z projected onto the up plane, normalised (if shorter
  than `HEADING_EPSILON` 1e-4, use `last_heading`); `z = −heading`, `x = up × z`, `basis = Basis(x, up, z)`.
  This keeps up exact and the basis orthonormal (verified 3.6e-7 over 36k ticks), which satisfies
  ADR-0001 §3's orthonormality rule without calling `orthonormalized()`.

#### 3.1.11 Kart-vs-kart contact (ADR-0003 §7; frozen `resolve_kart_contact`, `_take_bump`, `main.gd:540-611`)

**Shape.** Each kart is a segment of half-length `bump_half_length` (0.5 / 0.65 m) along its heading,
inflated by `bump_radius` (0.85 / 0.6 m). Closest points between segments come from an allocation-free
helper. Contact when the closest-point distance is below the sum of the two radii.

**Vertical gate.** No contact if the separation along up exceeds `bump_max_height_diff` (1.2 / 1.2 m) —
a bridge over a road, a kart flying over another. Frozen uses the **smaller of the two karts' values**
(`levels_apart`, `kart_sim.gd:326`); ADR-0003 says kart i's. Open decision **P8**.

**Which pairs.**
- Only pairs with **at least one kart simulated on this PC**. Two remote karts are skipped; the frozen
  50/50 display-only push and the "draw the remote aside" pass (`main.gd:582-595`) are dropped.
- Sinking or respawning karts are skipped (frozen `main.gd:542, 545`).
- **Broadphase on course distance:** karts sorted by `distance mod lap length` (remote: from their
  snapshot); candidates within `2 × max(bump_half_length + bump_radius) + broadphase_margin` (§4.17);
  wraps at the lap end; karts with invalid progress test against all; a course flagged
  `self_crossing` (ADR-0004) uses all pairs.
- Pairs `(i, j)`, i < j, resolved in ascending order against **pre-contact** snapshots only.

**Remote pose.** A remote kart is tested at the interpolated pose `RemoteKartView` draws, sampled at
`n × SIM_DT − view_delay`. `KartSnapshot.velocity` is total world velocity (`velocity + knock + carry`),
so the closing speed matches the frozen `velocity + knock` term.

**Push weights.** Weight = `bump_push_mult` (1.5 / 0.7), times `bot_push_mult` (0.35, `net_config.tres:31`)
when that kart is a bot and the other is not (frozen `_push_of`). The bot flag comes from `RacerRegistry`.

**Both karts simulated here** (§4.14-4.15):
- **Separation:** each kart's `pending_push` gets its weight share of the overlap; it is swept with the
  next tick's motion, **never written to `position`**, so a shove cannot push a kart through a wall.
  (Replaces the frozen 3-pass `_separate_karts` with wall re-clamps, `contact_passes = 3`.) Cost: an
  overlap lasts at most one tick.
- **Knock**, only when closing: each kart takes its share of `closing × (1 + bump_restitution)` along
  the contact normal; strength = `closing / bump_full_impact_speed` (10.0 / 10.0 m/s), clamped to [0, 1].
- **Speed loss** `speed *= 1 − bump_speed_loss × strength` (0.1 / 0.4), behind each kart's own
  `bump_cooldown` (0.3 / 0.3 s), which also gates the `bumped` bit.

**Against a kart another PC owns:**
- The local kart takes the **full separation** into its own `pending_push`, and only its **share** of
  the knock.
- The other kart's share of the knock and the strength go to its owner as a reliable `KartEvent` bump,
  applied at the **start of the owner's next tick** (§3.1.3 step 1). Frozen rule kept: local hits apply
  in the same tick, events from other PCs on the next tick.

**Dedup: max-merge per other slot** (§4.16). `pair_bump_mag[slot]` holds the largest knock magnitude
felt from that kart within `bump_cooldown`; a new impulse of magnitude m adds only the part above it.
This applies to local contacts and received events alike, so a contact both PCs detect is felt once at
its larger size. Pair memory expires when its timer (reset to `bump_cooldown` on each merge) runs out.

#### 3.1.12 Moving platforms and moving walls (ADR-0003 §9, §6)

- **Grounded on a mover:** carried by the platform's **pose delta**
  `D = mover_pose(id, t) × mover_pose(id, t − SIM_DT).affine_inverse()`. Position: `carry = D × position − position`,
  added to the swept motion (a platform cannot carry the kart through a wall). Heading: rotated by
  `D.basis` and re-projected in the basis rebuild. On a rotating mover, `velocity` is also rotated by
  `D.basis`, so it stays fixed relative to the platform.
- `support_velocity` (point velocity at the contact) is used for the landing impact and for the
  momentum kept on leaving (folded into `velocity` once at takeoff). **No carry after leaving.**
- **Moving walls:** the slide loop works relative to `WallHit.collider_velocity`; a mover's shove goes
  into `knock` (§3.1.6).
- Frozen mover behaviours with no ADR-0003 counterpart (solid mine cart `_push_off_body` with
  free-lane escape; portcullis `_mover_stop` rebound at `stop_rebound`) belong to Track Hazards; see
  Follow-Up Work.

#### 3.1.13 Events, teleports and the sink/fall hooks (ADR-0003 §8; frozen `tick` sink branch, `_start_sinking`, `_respawn`)

- `apply_event` runs at the start of a tick only and is followed by a snapshot refresh:
  - **bump** → max-merge knock, speed loss, `bumped` bit;
  - **respawn** (pose) → sets `teleported`; clears `velocity`, `knock`, `pending_push`, the spring
    state, the support and the pair memory;
  - **launch** (velocity, cannons) → sets `teleported`;
  - **hold** (clock resync) → sets `teleported`; clears the same state as respawn.
- Spin and hit effects go to `DriveState`, never to the body.
- **Frozen sink and fall** (`kart_sim.gd:502-520`, `986-999`): entering a hazard zeroes `speed`,
  `velocity` and `knock` every tick for `respawn_sink_time` (1.00 s on both shipped tracks); a fall off
  the track instead keeps falling under `air_gravity` to `ground_y` for `fall_respawn_delay`; then the
  kart respawns `respawn_back_off` (4.00 m) behind its last safe point at `respawn_speed_frac`
  (0.2609, ≈ 6.78 m/s for the Cart: 0.2609 × 26.0) with `respawn_immunity_time` (3.00 s). **Detection,
  timing and placement belong to Fall & Respawn** (row 12). The body supplies `place()`, the respawn
  event, `grounded`, `support_id` and `CourseProgress` inputs. **How the body is frozen while sinking is
  not specified by ADR-0003** — Open decision **P6**.

### 3.2 State and Data

**`KartSnapshot`** — the contract the systems index asks this GDD to define (Circular Dependencies:
"Kart Physics' GDD must define that snapshot"). Written three times per tick (refresh, pre-contact,
end of tick); ADR-0006 owns the wire encoding.

| Field | Meaning | Written by |
|---|---|---|
| `tick` | last stepped tick | body |
| `position`, `basis` | ride point, orientation | body |
| `velocity` | **total** world velocity: driving + knock + platform carry | body |
| `speed` | signed speed along heading, after wall and bump losses | body |
| `grounded`, `surface_id`, `support_id`, `air_time`, `hop_airborne` | ground state | body |
| `events` + `land_airtime`, `land_impact`, `wall_angle`, `bump_strength` | took-off, landed, wall hit (hard, angle), bumped, depenetrated (with cause), teleported | body |
| `moved` | length of this tick's actual displacement, 0 on teleport (input to `CourseData.progress`) | body |
| `teleported` | respawn, launch, resync hold | body |
| `distance` | course distance (local: `CourseProgress`; remote: wire), for the broadphase | composition root |
| `steer`, `throttle` | pass-through from `KartIntent` (`throttle` = throttle − brake in [−1, 1], ADR-0003 v4) | body |
| `drift_state`, `boost`, `spin`, `sinking` | copied in from `DriveState` | controller |

**Vehicle values — physics fields** (`assets/data/vehicles/*.tres`, forked unchanged to
`assets/data/core/vehicles/` per ADR-0003 §10):

| Field | Armored Cart | War Bike | Unit | Used in |
|---|---|---|---|---|
| `radius` | 1.0 | 0.85 | m | wall sweep sphere |
| `bump_knockback` | 1.4 | 1.9 | — | frozen wall/mover rebound (P1) |
| `bump_half_length` | 0.5 | 0.65 | m | contact segment |
| `bump_radius` | 0.85 | 0.6 | m | contact inflation |
| `bump_push_mult` | 1.5 | 0.7 | — | push weight |
| `bump_speed_loss` | 0.1 | 0.4 | — | speed loss at strength 1 |
| `bump_full_impact_speed` | 10.0 | 10.0 | m/s | strength = 1 |
| `bump_restitution` | 0.4 | 0.7 | — | knock multiplier `1 + e` |
| `bump_cooldown` | 0.3 | 0.3 | s | speed-loss gate, pair memory |
| `bump_knock_max` | 16.0 | 22.0 | m/s | knock cap |
| `bump_knock_decay` | 6.0 | 6.0 | 1/s | knock decay |
| `bump_max_height_diff` | 1.2 | 1.2 | m | vertical gate |
| `wall_hit_cooldown` | 0.5 | 0.5 | s | impact gate |
| `wall_friction_drag` | 0.8 | 0.8 | 1/s | scrape drag |
| `wall_scrape_min_angle` | 10.0 | 10.0 | ° | scrape band low |
| `wall_scrape_max_angle` | 40.0 | 40.0 | ° | scrape band high |
| `wall_scrape_friction_mult` | 0.45 | 0.45 | — | scrape band drag |
| `wall_impact_threshold_angle` | 25.0 | 25.0 | ° | impact vs scrape |
| `wall_impact_min_angle` | 15.0 | 15.0 | ° | impact loss ramp start |
| `wall_impact_max_angle` | 85.0 | 85.0 | ° | impact loss ramp end; turnback ramp |
| `wall_impact_max_speed_loss` | 0.6 | 0.7 | — | impact loss at ramp end |
| `wall_impact_slide_time` | 0.25 | 0.25 | s | grip clamp duration |
| `wall_slide_grip` | 2.2 | 2.2 | 1/s | grip clamp |
| `wall_turnback_min_rate` | 30.0 | 30.0 | °/s | turnback (P2) |
| `wall_turnback_max_rate` | 90.0 | 90.0 | °/s | turnback (P2) |
| `ride_spring` | 900.0 | 900.0 | 1/s² | ride spring |
| `ride_damping` | 42.0 | 42.0 | 1/s | ride spring |
| `ride_max_target_speed` | 30.0 | 30.0 | m/s | feed-forward clamp |
| `ride_max_gap` | 0.3 | 0.3 | m | spring ceiling |
| `slope_gravity` | 1.5 | 1.5 | m/s² | slope term |
| `air_gravity` | 20.0 | 20.0 | m/s² | default gravity magnitude |
| `air_takeoff_gap` | 0.45 | 0.45 | m | takeoff threshold |

**New per-vehicle fields** (additive, ADR-0003 §10): `ground_probe_points` (Cart 4 wheel points, Bike
2), `probe_lift` 0.5 m, `ride_snap_margin` 0.3 m, `sweep_center_height` = `radius`, `up_smoothing` 14,
`air_up_smoothing` 5, `hop_speed` 0.0.

**`KartPhysicsConfig`** (`assets/data/core/kart_physics.tres`, global, no per-vehicle feel values):
`slide_max_sweeps` 3 (asserted ≤ 3 at load), `wall_skin` 0.02 m, `max_depenetration_per_tick` 0.25 m,
`broadphase_margin` 2.0 m, `bot_push_mult` 0.35.

**Named consts (numeric guards, not tuning):** `HEADING_EPSILON` 1e-4, `WALL_NORMAL_MIN` 0.3,
`CONTACT_POINT_EPSILON` 1e-4 m, `UP_ANTIPARALLEL_DOT` −0.9999.

**Wall attributes** (`WallAttrSet`, `assets/data/core/`, ADR-0002): scrape drag, bounce, opening per
stable wall-attribute id.

### 3.3 Integration Points — what changes from the frozen kart

1. **2.5D spline → 3D mesh.** Frozen walls are a lateral clamp against a spline (`q.wall_offset − radius`);
   new walls are a sphere sweep on a wall layer. Frozen ground is one spline height; new ground is
   2-4 rays.
2. **Separation is deferred.** Frozen wrote `position` in 3 passes with wall re-clamps (1.52 ms of a
   1.88 ms contact cost, ADR-0003 Performance); new separation goes through `pending_push`.
3. **Contact pairs.** Frozen resolved every ordered pair from each owned kart's side (`main.gd:541-553`),
   each kart computing its own impulse with closing recomputed after the first kart's knock changed;
   new resolves each unordered pair once, i < j (Open decision P4).
4. **Up is physical.** Frozen tilt was visual; new up is a body state driven by the ground normal.
5. **Surface zone edges** (story 011, `zone_escape`) that held the kart where no wall existed become
   wall-layer geometry or ground on the mesh; nothing in the body replaces them.

---

## 4. Formulas

Examples use `dt = 1/60 s` and Cart values unless stated.

### 4.1 Slope gravity (grounded)

`speed = target_speed + slope_gravity × (ĝ · ĥ) × dt`

| Variable | Meaning | Range |
|---|---|---|
| `ĝ` | unit gravity vector | unit |
| `ĥ` | heading on the up plane | unit |
| `ĝ · ĥ` | sin of the slope along the heading; > 0 downhill | [−1, 1] |
| `slope_gravity` | 1.5 m/s² (both) | ≥ 0 |

Frozen form: `speed −= slope_gravity × sin(atan(slope)) × (forward · tangent) × dt` (`kart_sim.gd:618`).
Example: 10° uphill: 1.5 × sin 10° = 0.260 m/s² of deceleration, 0.00434 m/s per tick — small against
`accel` 14 m/s². INTENT UNKNOWN why it is ~15% of real gravity; it reads as an arcade choice.

### 4.2 Grip lerp (body application only)

`velocity ← lerp(velocity, ĥ × speed, clamp(g × dt, 0, 1))`, `g = min(intent.grip, wall_slide_grip)`
while `wall_slide_time > 0`, else `intent.grip`. The value of `intent.grip` is Driving's
(driving-and-drift.md §4.5). Example: road grip 9 → 0.15 per tick; wall-slide clamp 2.2 → 0.0367 per
tick for 0.25 s (15 ticks), which is the post-impact slide.

### 4.3 Proposed motion

`M = (velocity + knock) × dt + pending_push + carry`. Example: 26 m/s straight, no knock: 0.433 m per tick.

### 4.4 Wall incidence angle

`θ = degrees(asin(clamp(v_into / max(|v|, ε), 0, 1)))`, `v_into = velocity · n_out` (> 0 into the wall),
`ε` = frozen `EPSILON`. θ = 0 is parallel to the wall, 90 head-on (`kart_sim.gd:731`).

### 4.5 Wall impact loss

`t = clamp((θ − wall_impact_min_angle) / (wall_impact_max_angle − wall_impact_min_angle), 0, 1)`
`speed ← speed × (1 − wall_impact_max_speed_loss × t)`, only if `θ ≥ 25°` and `wall_cooldown ≤ 0`.

| θ | t | Cart loss (× 0.6) | Bike loss (× 0.7) | Cart 20 m/s → |
|---|---|---|---|---|
| 25° (threshold) | 10/70 = 0.1429 | 8.57% | 10.0% | 18.29 |
| 45° | 30/70 = 0.4286 | 25.7% | 30.0% | 14.86 |
| 85°-90° | 1.0 | 60% | 70% | 8.00 (Bike 6.00) |

Note the impact ramp starts at 15° but impacts begin at 25°, so the smallest impact already costs
8.6% / 10%. INTENT UNKNOWN (likely to make a hard hit feel distinct from a scrape).

### 4.6 Wall scrape drag

`speed ← speed × (1 − wall_friction_drag × mult(θ) × W × dt)`, `W` = wall attribute scrape drag
(frozen per-track `wall_drag_mult` = 2.0, P7).

`mult(θ)` = 1.0 outside [10°, 40°]; inside: `fade = 0` for θ ≤ 25°, else `(θ − 25) / (40 − 25)`;
`mult = lerp(0.45, 1.0, clamp(fade, 0, 1))` (`kart_sim.gd:1048-1054`).

| θ | mult | Per-tick factor (W = 2) | Per second |
|---|---|---|---|
| 5° | 1.0 | 1 − 0.8 × 1 × 2 / 60 = 0.97333 | × 0.198 |
| 15° | 0.45 | 1 − 0.012 = 0.988 | × 0.485 |
| 32.5° (on cooldown) | 0.725 | 1 − 0.01933 = 0.98067 | × 0.310 |

"Per second" is the compounded factor if the kart stayed in contact for 60 ticks with no throttle; in
play, Driving re-accelerates each tick and contact is usually intermittent (the rebound, §4.7). The
full drag below 10° (more than in the 10-25° band) is **INTENT UNKNOWN** — Open decision P3.

### 4.7 Wall rebound (frozen)

`velocity ← velocity − n_out × v_into × bump_knockback` ⇒ new into-wall component `(1 − k) × v_into`:
Cart k = 1.4 → −0.4 × v_into; Bike k = 1.9 → −0.9 × v_into. Example: Cart hitting at 10 m/s into the
wall leaves at 4 m/s away from it. ADR-0003: into-wall component removed (k = 1) plus a wall-attribute
bounce (P1).

### 4.8 Turnback rate (frozen, P2)

`ω_turn = radians(lerp(30, 90, clamp(θ / 85, 0, 1)))` per second, step clamped to the angle remaining.
θ = 15° → 40.6 °/s; θ = 85°+ → 90 °/s.

### 4.9 Overlap push-out

`d = r − (c − p) · n`; `s = min(d / (n · n̂_h) + wall_skin, max_depenetration_per_tick)`, applied only
if `|n_h| ≥ 0.3` (normal at least 17.46° from up: asin 0.3).

| Case | n · n̂_h | d | s |
|---|---|---|---|
| vertical wall, 0.3 m inside | 1.0 | 0.3 | min(0.32, 0.25) = 0.25; next tick 0.05 + 0.02 = 0.07 → clear in 2 ticks |
| 45° sloped wall | 0.7071 | 0.1 | 0.1 / 0.7071 + 0.02 = 0.161 |

The cap 0.25 m per tick equals 15 m/s (0.25 × 60), below the Cart's 26 m/s.

### 4.10 Ride spring

`a = ride_spring × (0 − ride_offset) + ride_damping × (target_rate − ride_velocity)`;
`ride_velocity += a × dt`; `ride_offset += ride_velocity × dt`; clamp to [0, `ride_max_gap`] (§3.1.8).

Derived: ω = √900 = 30 rad/s (4.77 Hz); damping ratio ζ = 42 / (2 × 30) = **0.70**; 2% settle ≈
4 / (ζω) = 4 / 21 = **0.19 s** (≈ 11-12 ticks); ω × dt = 0.5 (stable for semi-implicit Euler, which
needs < 2). Underdamped overshoot ≈ exp(−ζπ / √(1 − ζ²)) = exp(−3.08) ≈ 4.6%, cut off at the floor
clamp. INTENT UNKNOWN for the choice of ζ = 0.7, a textbook near-critical value.

### 4.11 Air and takeoff

- Takeoff: no ray hit, or `gap > air_takeoff_gap` (0.45 m). Ray length 1.25 m (§3.1.8).
- Ballistic: `velocity += gravity × dt`, |gravity| = 20 m/s².
- Airtime returning to launch height with launch vertical speed `v_up`: `T = 2 × v_up / 20 = v_up / 10`.
- Example: lip of a 10° ramp at 26 m/s: `v_up` = 26 × sin 10° = 4.515 m/s → T = 0.452 s, ≈ 11.6 m
  (26 × cos 10° × 0.452). Driving's `trick_min_airtime` 0.25 s needs `v_up ≥ 2.5` m/s on a level
  landing: a ramp of at least asin(2.5 / 26) = 5.5° at top speed.
- Example: a 1 m drop off a flat ledge: T = √(2 × 1 / 20) = 0.316 s; impact = 20 × 0.316 = 6.32 m/s.

### 4.12 Up smoothing

`α = 1 − exp(−rate × dt)`: ground (14) α = 1 − e^(−0.2333) = **0.2082** per tick (time constant 71 ms;
95% in 3 / 14 = 0.21 s); air (5) α = 1 − e^(−0.0833) = **0.0800** per tick (200 ms; 95% in 0.6 s).
Example: flat onto a 30° bank: up moves 6.25° on the first tick.

### 4.13 Knock decay and cap

`knock ← knock × exp(−bump_knock_decay × dt)` = × 0.9048 per tick (`exp(−0.1)`); half-life ln 2 / 6 =
**0.116 s** (≈ 7 ticks). `|knock| ≤ bump_knock_max` (16 / 22 m/s) after every addition.
Displacement from a knock k0 until it fades: k0 / 6, e.g. 7 m/s → 1.17 m.

### 4.14 Bump: share, closing, strength

| Variable | Definition |
|---|---|
| `w_a`, `w_b` | push weights: `bump_push_mult`, × 0.35 for a bot against a human |
| `share_a` | `w_b / max(w_a + w_b, 0.0001)` — the part of the effect kart a takes |
| `n` | unit contact normal on the up plane, pointing from b to a |
| `closing` | `(v_a − v_b) · n`, total velocities; contact only if `< 0` |
| `strength` | `clamp(−closing / bump_full_impact_speed, 0, 1)` |
| separation | `overlap = (r_a + r_b) − dist`; a takes `overlap × share_a` (both local) or `overlap × 1` (b remote) |
| knock to a | `−n × closing × share_a × (1 + e)` |
| knock to b | `n × closing × (1 − share_a) × (1 + e)` |
| speed loss | `speed ← speed × (1 − bump_speed_loss × strength)`, if `bump_cooldown ≤ 0` |

Which kart's `e` (`bump_restitution`) applies to each side is Open decision **P4** (frozen: each local
kart uses its own; for a remote victim, the resolving kart's).

Examples (each kart's own `e`):

| Pair | closing | share | knock a / b | speed factor a / b |
|---|---|---|---|---|
| Cart vs Cart, head-on 20 + 20 m/s | −40 | 0.5 / 0.5 | 40 × 0.5 × 1.4 = 28 → capped **16** / 16 | 0.90 / 0.90 |
| Cart vs Bike, side, 8 m/s | −8 | 0.318 / 0.682 (0.7/2.2, 1.5/2.2) | 8 × 0.318 × 1.4 = 3.56 / 8 × 0.682 × 1.7 = 9.27 | 0.92 / 0.68 (Bike 24 → 16.3 m/s) |
| Human Cart vs bot Cart, 8 m/s | −8 | human 0.259 (0.525/2.025) / bot 0.741 | 2.90 / 8.30 | 0.92 / 0.92 |

### 4.15 Separation example

Two Carts with closest-point distance 1.5 m (contact at 0.85 + 0.85 = 1.7): overlap 0.2 m. Both local:
0.1 m each into `pending_push`. Against a remote Cart: the local kart takes 0.2 m.

### 4.16 Max-merge dedup

`already = pair_bump_mag[from]`, `m = |impulse|`. If `m > already`: `knock += impulse × (m − already) / m`,
cap, `pair_bump_mag[from] = m`, `pair_bump_timer[from] = bump_cooldown`. Example (ADR-0003): the same
contact reported locally (m = 3) then by event (m = 5) adds 3 then 2 along the impulse — total 5, not 8.

### 4.17 Broadphase window

`W_bp = 2 × max_k(bump_half_length_k + bump_radius_k) + broadphase_margin`. Cart 0.5 + 0.85 = 1.35;
Bike 0.65 + 0.6 = 1.25. Any race with a Cart: 2 × 1.35 + 2.0 = **4.7 m**; Bikes only: 4.5 m.

### 4.18 Platform carry error avoided

Point velocity × dt drifts outward by about `r (ω dt)² / 2` per tick. At r = 5 m, ω = 1 rad/s:
5 × (1/60)² / 2 = 6.94e-4 m per tick, ≈ 0.42 m over 600 ticks (first order). The pose delta is exact;
the acceptance bound is 1 mm over 600 ticks (AC-16).

---

## 5. Edge Cases

| # | Situation | Outcome |
|---|---|---|
| E-1 | `dt = 0` | No motion, no decay, no timer change; the spring's feed-forward must guard the divide (frozen: `target_v = 0` when `dt ≤ 0`, `kart_sim.gd:878`). |
| E-2 | Wall contact at near-zero velocity | θ uses `max(|v|, ε)`; with `v_into ≤ 0` there is no wall response (frozen requires `into_wall > 0`). Only the slide applies. |
| E-3 | Head-on wall at θ ≥ 85° | Maximum loss (Cart 60%, Bike 70%), slide grip for 0.25 s, cooldown 0.5 s, turnback at 90 °/s (if P2 keeps it). |
| E-4 | Second steep hit within 0.5 s | No impact; scrape with `mult = 1` above 40° (`kart_sim.gd:1049`). |
| E-5 | Graze below 10° | Scrape at full `mult = 1` — more drag than the 10-25° band. INTENT UNKNOWN (P3). |
| E-6 | Two walls in one tick (corner) | Response runs on the first contact only; later sweeps only slide. An inner-corner overlap takes 2 push-out sweeps. |
| E-7 | Slide loop exhausts 3 sweeps | Remaining motion dropped; kart stays at the last safe point; the next tick continues. Counted in story 022. |
| E-8 | Clear cast, rest hit at `to` (touch) | Full move, no slide, scrape response if first contact, into-wall velocity removed. |
| E-9 | Kart over a wall top (`|n_h| < 0.3`) | No horizontal push, no wall response; `depenetrated` with guard cause; ground cast or Fall & Respawn takes over. |
| E-10 | Kart tunnelled behind a one-sided wall | Not detected by the body; Fall & Respawn via route `outside`. Story 022 counts occurrences. |
| E-11 | Mover moving into the kart faster than 15 m/s | Push-out capped at 0.25 m per tick, so the kart may stay inside for several ticks; the shove in `knock` (capped) moves it out; hazards usually also spin it. Story 022 tests the fastest planned mover. |
| E-12 | Overlap created by an unswept move (spring, landing snap, up slerp) | Resolved next tick as `started_inside`; counted by cause. |
| E-13 | No ground ray hits while grounded | Takeoff (ballistic). |
| E-14 | Ground step taller than `probe_lift` (0.5 m) | Must not exist: `track_check` (ADR-0005) requires it on the wall layer. If it slips through, the kart is neither stopped nor climbs correctly. |
| E-15 | Surface-id tie among probes (2-2 Cart, 1-1 Bike) | Lowest probe index wins (Bike: the front probe if listed first — **[inferred — confirm]** probe ordering front-first). |
| E-16 | Crest or kink with no drop | No takeoff: the gap clamp (0.3) < takeoff gap (0.45) holds the kart to the road (frozen). Risk on the mesh: up-smoothing lag on a sharp crest (ADR-0003 Risks). |
| E-17 | Landing on a moving platform | Up-plane part of `support_velocity` subtracted before `speed` is taken; carry resumes. No double count (AC-15). |
| E-18 | Leaving a moving platform | Support velocity folded into `velocity` once; no carry term afterwards. |
| E-19 | Up target exactly opposite to up | Antiparallel guard rotates about the heading; no NaN (AC-12). |
| E-20 | Heading parallel to up (degenerate projection) | `last_heading` is used. |
| E-21 | Pile-up (several bumps in one tick) | Knock capped at 16 / 22 m/s; each other slot max-merged separately; speed loss once per `bump_cooldown`. |
| E-22 | Two karts exactly coincident (`dist < 0.0001`) | Normal falls back to `(pos_a − pos_b)` normalised, then to the heading's perpendicular (frozen `kart_sim.gd:416-418`). |
| E-23 | Kart on a bridge above another | Separation along up > 1.2 m → no contact. |
| E-24 | Bot vs bot, human vs human | No `bot_push_mult` (only bot against non-bot). |
| E-25 | Two remote karts overlapping on screen | Skipped; may look overlapped (frozen display push dropped). A display-only offset in `RemoteKartView` may be added after A1; it must never feed the simulation. |
| E-26 | Bump event received for a sinking or respawning kart | Sinking: skipped by the solver; a received event's knock and speed are cleared by the sink freeze (frozen behaviour, depends on P6). Respawn clears pair memory. |
| E-27 | Remote kart's `distance` stale or at a junction | 2 m broadphase margin; invalid progress tests against all; story 022 brute-force cross-check requires zero misses. |
| E-28 | Figure-eight course (self-crossing at the same height) | All-pairs fallback via the ADR-0004 `self_crossing` flag. |
| E-29 | Reversing into a wall | Impact and scrape still apply (θ uses velocity); frozen turnback requires `speed > 0`, so none while reversing. |
| E-30 | Physical hop with the current spring clamp | With `hop_speed > 0`, the grounded clamp at 0.3 m (< 0.45 takeoff gap) cancels the hop before it can take off — see P9. Unreachable through parity (`hop_speed = 0`). |
| E-31 | **Degenerate: ramming** | The Cart loses ≤ 10% speed and pushes 1.5 vs 0.7; the Bike loses up to 40%. A Cart driver can trade 10% to cost a Bike 40%. This is the designed asymmetry ("knocked harder"), but if ramming beats racing the line it becomes a dominant strategy (Sirlin: degenerate, not mastery). Playtest check AC-X3. |
| E-32 | **Degenerate: wall-riding** | Not profitable on the shipped tracks: pinned at θ < 10° the drag rate is 0.8 × 2 = 1.6 /s, i.e. 41.6 m/s² of deceleration at 26 m/s vs `accel` 14. If Driving's acceleration is a constant `accel` below the cap, the pinned equilibrium is 14 / 1.6 = 8.75 m/s. A future low-drag wall attribute could change this; `track_check` or design review should flag `scrape_drag` < 1. |

---

## 6. Dependencies

Each system below must name this document in its own GDD when that GDD is written; this list is the
bidirectional record until then.

| System | Direction | Contract |
|---|---|---|
| **Driving & Drift** (row 9, `design/gdd/driving-and-drift.md`) | both | Consumes `KartIntent` (`yaw_rate`, `target_speed` without slope gravity, `grip` without the wall clamp, `hop`, `steer`, `throttle`). Provides `KartSnapshot` (`speed` after losses, `grounded`, `surface_id`, `air_time`, bumped bit). Air events reach Driving only through the controller's step-13 copy into `DriveState`. That document's §6 already lists this one. |
| **Track Collision & Surface Attributes** (row 5, ADR-0002 v5) | consumes | `CollisionQuery` (`cast_ground`, `sweep_walls`, `mover_pose`, `mover_point_velocity`), `GroundHit`, `WallHit` (`fraction`, `started_inside`, `collider_velocity`), `QueryCursor`, `WallAttrSet` (scrape drag, bounce, opening). Requirement on it: `started_inside` returns at once; touch reported as `fraction = 1.0`. |
| **Course Data** (ADR-0004) | both | Consumes `CourseProgress.distance` (broadphase) and the `self_crossing` flag. Provides `KartSnapshot.moved` for `CourseData.progress`. |
| **Blender Track Pipeline** (ADR-0005) | consumed by | Requirement: `track_check` enforces the step-up contract (`probe_lift` 0.5 m) and wall-layer placement. |
| **Simulation conventions** (ADR-0001) | consumes | `SIM_DT`, tick time `t = n × SIM_DT`, `Basis` orientation, per-body gravity, slot order, teleport flag, `assets/data/core/` forks. |
| **Network Session & Sync** (ADR-0006) | both | Provides `KartSnapshot` (§3.2) for encoding; consumes bump, respawn, launch and hold `KartEvent`s on the reliable channel. The body never references `src/networking/`. |
| **Input & Bindings** (row 21b) | none directly | Listed as a Kart Physics dependency in the systems index; the body never reads input — it arrives through Driving's `KartIntent`. |
| **Fall & Respawn** (row 12) | consumed by | Body provides `place()`, the respawn event, `teleported`, `grounded`, `support_id`, `depenetrated` guard events. Fall & Respawn owns detection, timings (`respawn_sink_time` 1.00 s etc.) and the sink freeze (P6). |
| **Track Features** (row 13) | consumed by | Ramps through rays, spring, takeoff and landing; cannons through the `launch` event. Boost pads go through Driving. |
| **Track Hazards** (row 14) | consumed by | Mover pose-delta carry, moving walls, mover shove into `knock`. Hazards decide spin and sink effects. |
| **Air Tricks** (row 26) | consumed by | Air state, airtime, impact, `hop_airborne`. |
| **Anti-Gravity & Wall-Riding** (row 27, ADR-0009) | consumed by | Changes only per-body `gravity` and the up target. |
| **Items & Item Boxes** (row 15) | consumed by | Kart pose and velocity for hit tests; spins go to `DriveState`, not the body. |
| **Chase Camera** (row 18), **Kart & Dog Presentation** | consumed by | `KartSnapshot` pose, up, events (land squash, wall sparks); cosmetic lean stays in presentation (ADR-0001 §4). |
| **Race Audio** | consumed by | Wall hit (hard/soft, angle), bump strength, landing impact events. |
| **Time Trials & Ghosts** (ADR-0010) | consumed by | `KartSnapshot` streams. |
| **CPU Racers** | consumed by | Bots are bodies like any other; `bot_push_mult` and the bot flag from `RacerRegistry`. |

---

## 7. Tuning Knobs

No `@export_range` exists on `VehicleStats`, so numeric safe ranges are **NOT SOURCED**; the ranges
below are the structural bounds the rules need to stay valid, and anything tighter is a playtest
decision. Defaults are the values in §3.2. Category: **F** feel, **C** curve, **G** gate.

| Knob | Cat. | Affects | Structural safe range | Why |
|---|---|---|---|---|
| `radius`, `sweep_center_height` | F | wall clearance, how close to walls the kart drives | > 0; `wall_skin` < `radius` | sphere must be non-degenerate |
| `wall_impact_threshold_angle` | G | what counts as a crash | in [`wall_scrape_min_angle`, `wall_scrape_max_angle`] | the scrape fade formula assumes it |
| `wall_impact_min_angle`, `wall_impact_max_angle` | C | impact loss ramp | min < max ≤ 90 | divisor; θ never exceeds 90 |
| `wall_impact_max_speed_loss` | C | crash cost | [0, 1] | > 1 reverses speed |
| `wall_hit_cooldown` | G | repeated crash cost | ≥ 0 | |
| `wall_impact_slide_time`, `wall_slide_grip` | F | post-crash slide | time ≥ 0; grip ≤ road `grip` (9) | a higher clamp is no clamp |
| `wall_friction_drag`, `wall_scrape_friction_mult` | F | scrape cost | drag × mult × scrape_drag × dt < 1 | ≥ 1 zeroes or reverses speed in a tick |
| `wall_scrape_min/max_angle` | F | scrape band | 0 ≤ min ≤ threshold ≤ max ≤ 90 | |
| `wall_turnback_min/max_rate` | F | how walls straighten the kart (P2) | ≥ 0, min ≤ max | |
| `bump_knockback` | F | wall/mover rebound (P1) | [1, 2] | < 1 leaves into-wall velocity; > 2 rebounds faster than it hit |
| `WallAttr` scrape drag / bounce | F | per-wall feel | scrape drag ≥ 0 (see E-32); bounce [0, 1] | |
| `ride_spring` | F | ride stiffness | > 0 and √spring × dt < 2 (spring < 14,400) | semi-implicit Euler stability |
| `ride_damping` | F | ride settle | (0, 2√spring] = (0, 60] for ζ ≤ 1 | > critical feels sluggish |
| `ride_max_gap` | G | crest hold | (0, `air_takeoff_gap`) | ≥ takeoff gap changes when karts fly |
| `ride_max_target_speed` | F | climb feed-forward clamp | > 0 | |
| `air_takeoff_gap` | G | what launches the kart | > `ride_max_gap` | |
| `air_gravity` | C | airtime and jump distance (§4.11) | > 0 | |
| `slope_gravity` | F | hills | [0, `accel`) | ≥ `accel` makes steep slopes unclimbable at full throttle |
| `probe_lift` | G | max step-up | must equal the value `track_check` enforces | step-up contract |
| `ride_snap_margin` | G | ray reach | ≥ 0 | |
| `ground_probe_points` | F | stance, rocking | 2-4 points | ADR-0002 budget (4 rays) |
| `up_smoothing`, `air_up_smoothing` | F | tilt response | > 0; above 60 the per-tick fraction is near 1 | |
| `hop_speed` | F | physical hop | **0.0 through parity** | D2, P9 |
| `bump_half_length`, `bump_radius` | F | contact size | > 0; broadphase uses their max | |
| `bump_push_mult` | C | who gets pushed | > 0 | 0 divides by the 0.0001 guard |
| `bump_speed_loss` | C | bump cost | [0, 1] | |
| `bump_full_impact_speed` | C | strength scaling | > 0 | divisor |
| `bump_restitution` | F | bump knock | [0, 1] | |
| `bump_cooldown` | G | repeat-bump cost, dedup window | ≥ 0 | |
| `bump_knock_max` | C | launch cap | > 0 | |
| `bump_knock_decay` | F | how long a shove lasts | > 0 | |
| `bump_max_height_diff` | G | bridges and jumps | > 0, below the smallest deck clearance on any track | |
| `slide_max_sweeps` | G | wall slide quality vs cost | 1-3 (asserted ≤ 3) | ADR-0002 budget |
| `wall_skin` | F | wall gap | > 0, ≪ `radius` | |
| `max_depenetration_per_tick` | F | push-out speed | > 0; ≥ fastest mover speed × `SIM_DT` | E-11 |
| `broadphase_margin` | G | missed-contact risk | ≥ 0 | zero misses is the gate |
| `bot_push_mult` | C | bots bullying humans | [0, 1] | |

All knobs live in data (`assets/data/core/…`), never as literals in `src/core/kart/`
(`.claude/rules/tuning-values.md`). The named consts in §3.2 are numeric guards, not knobs.

---

## 8. Acceptance Criteria

Functional criteria are gdUnit4 tests in `tests/unit/kart/` against `KartBody` / `KartContactSolver`
with the forked Cart and Bike data, fixture meshes, a stub `KartIntent`, and `dt = 1/60`, unless
stated. "± 1 tick" allows float accumulation. These extend ADR-0003's Validation Criteria with numbers.

**Integration and slope**
- AC-1: On flat ground, `speed` after the step equals `intent.target_speed` exactly. On a 10° uphill,
  it equals `target_speed − 0.00434` m/s ± 1e-5 per tick (Cart and Bike).

**Walls**
- AC-2: Cart at 20 m/s into a vertical wall at 90°, cooldown clear → `speed` 8.00 ± 0.01, `wall_slide_time`
  0.25 s, `wall_cooldown` 0.5 s, hard wall-hit event; Bike → 6.00 ± 0.01.
- AC-3: Cart at 20 m/s at 25.0° → 18.29 ± 0.01 (impact); at 24.9° → scrape: × (1 − 0.8 × 0.45 × W / 60)
  with the fixture wall's scrape drag W.
- AC-4: A second 90° hit 0.4 s after the first → no speed impact loss (scrape only); at 0.5 s → impact.
- AC-5: For 0.25 s after an impact, the grip applied is ≤ 2.2 even when `intent.grip` = 9.
- AC-6: The slide loop never runs more than 3 sweeps (counter), and a clear cast with a rest hit at
  `to` moves the full motion with no slide.
- AC-7: A sphere started 0.3 m inside a vertical wall, a 45° sloped wall and an edge is pushed out by at
  most 0.25 m per tick and is clear within 2 ticks; an inner corner clears in 2 push-out sweeps.
- AC-8: A kart over a wall top (`|n_h| < 0.3`) gets no horizontal push and no wall response, and has
  `depenetrated` set with the guard cause; no division by `n · n̂_h` occurs.
- AC-9: Bounce and turnback match whatever P1 and P2 decide; until then, the test asserts the frozen
  rebound (Cart −0.4 × v_into, Bike −0.9 × v_into) behind a flag.

**Ground, air, up**
- AC-10: A 0.2 m step down at rest: `ride_offset` within 0.004 m of 0 by 0.25 s, never below 0, never
  above 0.3.
- AC-11: A 0.46 m drop in one tick → took-off event; a 0.44 m drop → no takeoff. Launched with 5 m/s
  along up onto level ground: landed after 0.50 s ± 1 tick with impact 5.0 ± 0.2 m/s and `airtime`
  reported; `speed` after landing = velocity · heading.
- AC-12: Up guard: a target exactly opposite to up produces no NaN and an orthonormal basis.
- AC-13: On a 30° bank, the first tick moves up 6.25° ± 0.05° toward the normal; after settling, `basis.y`
  equals the smoothed normal within 1e-4, and `basis` is orthonormal within 1e-5 after 36,000 ticks.
- AC-14: A ramp lip at 26 m/s takes off, and the landing reports airtime and impact.

**Platforms**
- AC-15: Leaving a moving platform and landing back on it with no input: speed relative to the platform
  unchanged within 1e-3.
- AC-16: Parked on a platform rotating at 1 rad/s, 5 m from the axis: radius kept within 1 mm over 600
  ticks and heading turns with the platform. Translating platform: zero relative drift.
- AC-17: A mover moving into the kart sets `started_inside`, and the shove lands in `knock` (capped at
  16 / 22), not in `velocity`.

**Contact**
- AC-18: Two local Carts head-on at 20 m/s each: knock magnitude 16.0 each (capped), speed × 0.90.
- AC-19: Cart vs Bike side contact, closing 8 m/s, both local: Cart speed × 0.92, Bike × 0.68; Cart
  takes 0.318 and Bike 0.682 of the separation in `pending_push`; no `position` write during contact.
- AC-20: Human Cart vs bot Cart: the human takes 0.259 of the separation; bot vs bot: 0.5.
- AC-21: Karts 1.19 m apart along up touch; 1.21 m apart never touch.
- AC-22: Local kart vs remote kart: the local kart takes the full separation and only its knock share;
  exactly one `KartEvent` is produced; a pair of two remote karts is skipped.
- AC-23: Max-merge: magnitude 3 locally then 5 by event from the same slot → total added knock
  magnitude 5 (not 8, not 3); after `bump_cooldown` (0.3 s) the pair memory is clear.
- AC-24: Bump ordering: after a local contact and after a received bump event, the next `drive()` reads
  the reduced `speed`, and the `bumped` bit is in the end-of-tick snapshot.
- AC-25: Broadphase window is 4.7 m with a Cart in the race; it finds the same pairs as brute force
  over a 12-kart race (zero misses).

**Boundary, determinism, budget**
- AC-26: Two runs with the same inputs (offline, host-bot, and recorded remote events replayed at their
  ticks) give bit-identical `KartSnapshot` streams on one machine.
- AC-27: Grep: no `src/legacy`, `src/gameplay`, `src/networking`, `Vector3.DOWN`, `randf`, `randi` or
  `delta` in `src/core/kart/`; no `Dictionary(` or `Geometry3D.get_closest_points_between_segments` in
  per-tick paths; no numeric tuning literal other than 0/1/−1 and the named consts of §3.2.
- AC-28 (story 022 benchmark): 12 karts on the owner's PC: body + `drive()` ≤ 0.3 ms p95; contact
  ≤ 0.2 ms p95 (debug build accepted as an upper bound until 4.8 export templates exist).

**Parity and feel** (integration; ADR-0003 Validation Criteria; harness and tolerances shared with
driving-and-drift.md AC-P1/AC-P2, not repeated here)
- AC-P1: Physics parity items of the shared gate: takeoff, landing and lap counts exact; no interval
  with speed < 2 m/s for more than 1 s after the start (wall-stuck) on any solo trace. Tolerances:
  Open decision **D3** (driving-and-drift.md).
- AC-X1 (experiential, owner A1 sign-off): the owner drives both vehicles on the baked Castle Circuit
  and signs off that wall scrapes and crashes, landings and bumps feel like the frozen game. Retained
  screenshots of a wall impact and a landing per vehicle in `production/qa/evidence/`.
- AC-X2 (experiential, 4-PC test, story 022): bump counts per PC agree, and no tester reports a bump
  felt twice or a bump that "did nothing" on their screen.
- AC-X3 (experiential, playtest): ramming a Bike with a Cart is tried deliberately on Castle Circuit;
  the owner judges whether ramming beats racing the line, and records the call (E-31).

---

## Open decisions for the owner

| ID | Decision | Options | Recommendation |
|---|---|---|---|
| **P1** | **Wall rebound** | A. frozen per-vehicle `bump_knockback` (Cart 0.4×, Bike 0.9× rebound); B. ADR-0003: remove the into-wall velocity, bounce only from the wall attribute; C. both: vehicle term × wall-attribute bounce (default 1.0) | **C** — keeps parity and the Bike's lively feel, and still lets a track mark a padded or bouncy wall. Needs an ADR-0003 amendment (technical director). |
| **P2** | **Wall turnback** (frozen: heading turned toward the track direction at 30-90 °/s while touching or sliding) | A. drop it (slide + grip only); B. body turns the heading toward the wall tangent nearest the heading; C. Driving applies it from a snapshot wall field | **B (proposal)** — it is wall physics like the slide-grip clamp, and the wall tangent replaces the spline tangent the mesh does not have. Without it, the "no wall-stuck" parity gate is at risk. Needs an ADR-0003 amendment. |
| P3 | Full scrape drag below 10° (more than 10-25°) | keep (frozen); make `mult = 0.45` from 0° | Keep through parity; revisit at A1. INTENT UNKNOWN. |
| **P4** | **Which `bump_restitution` applies** in a pair, and single vs ordered pair resolution | A. each kart its own `e` (frozen local behaviour), one resolution per pair i < j (ADR-0003); B. resolver's `e` for both (frozen remote behaviour) | **A** — symmetric, and it gives the same answer whichever PC resolves. The frozen ordered-pair double resolution is dropped (ADR-0003); the owner confirms bump feel at A1. |
| P5 | `>=` vs "above" at the impact threshold | `>=` (frozen); `>` (ADR-0003 wording) | `>=`, for parity; ADR-0003 text fix. |
| **P6** | **Body while sinking / falling** (frozen: speed, velocity, knock zeroed every tick; a fall keeps falling to `ground_y`) | A. controller sends a `hold` each tick; B. a `frozen` body mode set by Fall & Respawn; C. a "sink" event that parks the body until respawn | Decide in the Fall & Respawn GDD; **B** looks simplest (no per-tick events, one flag in the snapshot already exists: `sinking`). Needs an ADR-0003 amendment. |
| P7 | Frozen per-track `wall_drag_mult` (2.0 on both tracks) on the new core | per `WallAttr` scrape drag (2.0 for the migrated tracks' wall attributes); drop it | Per `WallAttr`, set to 2.0 for Castle Circuit and Dungeon Depths walls, so parity holds. |
| P8 | Vertical contact gate: whose `bump_max_height_diff` | the smaller of the two (frozen); kart i's (ADR-0003 wording) | Smaller of the two — symmetric and frozen. |
| **P9** | **Physical hop cannot take off through the spring** | the grounded clamp at `ride_max_gap` 0.3 m (< `air_takeoff_gap` 0.45) cancels any `hop_speed`; options: skip the ceiling clamp on a hop tick; take off directly when `ride_velocity` exceeds a threshold; keep hop visual | No action through parity (`hop_speed = 0`). Raise with the technical director before **D2** is decided: ADR-0003's own test "a hop lifts through `ride_velocity` and takes off past `air_takeoff_gap`" is unreachable as written. |
| D2 | Physical hop after A1 | see `design/gdd/driving-and-drift.md` Open decisions | Owned there; blocked on P9. |
| D3 | Parity tolerances | see `design/gdd/driving-and-drift.md` Open decisions | Owned there; this GDD's AC-P1 uses the same gate. |

---

## Open Questions and Follow-Up Work

### Flagged Follow-Up Work
- **Cross-doc inconsistency (driving-and-drift.md):** its §3.3 item 5 says landing, airtime and
  `hop_airborne` reach `drive()` "through `snapshot.events`", and its header cites ADR-0003 v2. ADR-0003
  v3 §4 step 13 makes the controller's copy into `DriveState` the **only** path (`events` is cleared
  after the end-of-tick snapshot). That document should be updated to v3 wording.
- ADR-0003 amendments requested by P1, P2, P5, P6, P8, P9 (technical director).
- Frozen mover behaviours with no ADR-0003 counterpart — solid traveling body pushed out to the free
  lane with `bump_knockback` rebound and `spin_min_speed` gate (`_push_off_body`), portcullis stop with
  `stop_rebound` speed reversal (`_mover_stop`) — must be specified in the Track Hazards GDD.
- The `hop_airborne` detection rule (§3.1.9) and the ride spring's feed-forward on the mesh (§3.1.8)
  are **[inferred — confirm]** with the engine-programmer in story 022.
- Story 022 counts: wall-top guard firings, `started_inside` by cause, slide-cap exhaustion, tunnelling.
- When Fall & Respawn, Track Features, Track Hazards, Air Tricks, Network Session and Chase Camera GDDs
  are written, each must reference this document (Dependencies are bidirectional).

## Version History

| Date | Change | By |
|---|---|---|
| 2026-11-22 | First draft, reverse-documented from `src/legacy` at `59614ff` against ADR-0003 v3 | game-designer (orchestrated run) |
