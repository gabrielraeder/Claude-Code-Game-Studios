# ADR-0003: Kart Physics Model

## Status
Proposed

## Date
2026-11-22

## Last Verified
2026-11-22

## Decision Makers
Drafted by engine-programmer (subagent, orchestrated run) from ADR-0001, ADR-0002 v3, ADR-0004, the amended performance budgets in `architecture.md`, the per-system profile of the frozen tick, and the frozen kart (`src/legacy/vehicle/kart_sim.gd`, read for feel only). Not yet reviewed by godot-specialist or technical-director (TD-ADR). Acceptance needs the owner's confirmation.

## Summary
The rebuilt 3D core needs a kart body that drives on Blender meshes through Track Collision (ADR-0002), keeps the frozen kart's arcade feel, runs headless and deterministically inside 0.3 ms per tick for 12 karts, and leaves feel decisions (drift, boost, surfaces) to Driving & Drift. This ADR chooses a **custom kinematic `KartBody` (RefCounted)** in Core, driven each tick by a `KartIntent` that the Gameplay-layer **`DriveState` control law** produces. It fixes the body state, the per-tick step order (wall slide loop capped at 3 sweeps with bounded overlap push-out, then 2 to 4 ground rays, a single damped ride spring, up from a smoothed normal), kart-vs-kart contact behind a course-distance broadphase, moving platforms through `collider_velocity`, and a lap-time parity rule against the golden traces. `CharacterBody3D` and `RigidBody3D` on Jolt are rejected.

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.8-beta3 (Jolt Physics 5.6.0 through ADR-0002) |
| **Domain** | Physics |
| **Layer** | Core |
| **Knowledge Risk** | HIGH (post-cutoff, pre-release engine). This ADR's own code is mostly plain GDScript math (`Vector3`, `Basis`, `Quaternion`). Every engine physics call goes through ADR-0002's `CollisionQuery`. |
| **References Consulted** | `docs/engine-reference/godot/VERSION.md`. ADR-0001 §3, §5, §6, §8. ADR-0002 v3 (its "Verified on 4.8-beta3" list). `production/qa/evidence/core-rebuild-story-001/perf-per-system.md`. **Not read for this draft:** `docs/engine-reference/godot/modules/physics.md`. The rejection reasons for `CharacterBody3D` and `RigidBody3D` below have not been checked against it (see Risks). |
| **Post-Cutoff APIs Used** | None directly. Used indirectly through `CollisionQuery`: `intersect_ray_into`, `cast_motion_into`, `get_rest_info_into` (4.8, verified by ADR-0002). |
| **Verification Required** | (1) What `get_rest_info_into` returns for a sphere that starts inside a one-sided wall triangle: is the point on the wall surface, and does the normal point toward the kart? The push-out depth formula depends on it. (2) How `CollisionQuery.sweep_walls` fills `WallHit` when `started_inside` is true and the cast also hits (whose rest result goes in point and normal). (3) The cost of the full step for 12 karts, measured in a release export (see Performance Implications). (4) That `Basis` built from three orthonormal columns stays orthonormal to 1e-5 over a 10-minute race with no extra `orthonormalized()` call. |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | ADR-0001 (Accepted): axes, `Basis` orientation, per-body gravity, `SIM_DT`, tick time `t = n × SIM_DT`, slot step order, RNG streams, teleport flag, `assets/data/core/` forks. ADR-0002 (Proposed, must be Accepted first): `CollisionQuery`, `GroundHit`, `WallHit` (`started_inside`, `collider_velocity`), `QueryCursor`, `mover_pose`. ADR-0004 (Proposed, must be Accepted first): `CourseProgress.s` / `distance` for the kart-pair broadphase. |
| **Enables** | ADR-0006 (network snapshot for 3D: encodes the `KartSnapshot` fields defined here). ADR-0009 (anti-gravity and wall-riding: changes only the per-body gravity and the up target). ADR-0010 (ghosts record `KartSnapshot` streams). |
| **Blocks** | Story 022 (kart physics on the mesh). The Driving & Drift migration story. Fall & Respawn, Track Features (ramps, cannons) and Track Hazards (mover hits) on the new core. |
| **Ordering Note** | ADR-0002 hands three choices to this ADR: overlap resolution, the sweep shape and radius, and the slide-loop cap. They are decided in §5 and §6 below. The per-system budget amendment to `architecture.md` (2026-11-22) has landed: kart physics and driving 0.3 ms, kart-vs-kart contact 0.2 ms, p95 for 12 karts. |

## Context

### Problem Statement
The frozen kart (`KartSim`) is a 2.5D kinematic model on the XZ plane. It uses a height spring and asks a spline `TrackModel` for road, walls and decks. The rebuild drives on triangle meshes baked from Blender (ADR-0005), with real 3D slopes, banks, decks and loops. Later, anti-gravity (ADR-0009) is added.

The kart body must decide five things each tick:
- how to move;
- what it stands on;
- how it meets walls and other karts;
- how it rides moving platforms;
- how it flies and lands.

It must also keep the feel the owner tuned over stories 001-011. Story 022 cannot start until these choices are fixed, and Driving & Drift cannot be migrated until its boundary with the body (`KartIntent`) is fixed.

### Constraints
- Architecture Principle 1: simulation objects are `RefCounted`, independent of the SceneTree, and testable headless.
- ADR-0001: fixed `SIM_DT` with catch-up ticks; same-machine determinism; slot step order; pairs i < j; no global RNG; no stored scalar yaw; no hard-coded `Vector3.DOWN`.
- ADR-0002: all geometry through `CollisionQuery` on a private, inactive Jolt space. Up to 3 sweeps per kart per tick fit its budget. Jolt casts ignore start overlaps. Steep ground never blocks a kart (walls are a separate layer).
- Engine code (`src/core/`) must never depend on gameplay code (`src/gameplay/`).
- New code must not reference `src/legacy/` or read a frozen `.tres` instance.
- `VehicleStats` (`src/data/`) may change only additively.

### Requirements
- Same feel as the frozen kart, held to the parity rule in Validation Criteria:
  - acceleration to a cap that boosts never exceed;
  - grip lerp, which gives the drift slide;
  - wall scrape and wall impact;
  - bump knock;
  - ride spring, takeoff and landing;
  - slope gravity along the road only.
- Variable up vector: banks, ramps, loops later.
- Moving platforms and moving obstacles.
- Kart physics and driving together within 0.3 ms p95 per tick, and kart-vs-kart contact within 0.2 ms p95, for 12 karts.
- Bounded allocation, zero in steady state.
- A `KartSnapshot` per tick for presentation, network (ADR-0006) and ghosts.

## Decision

### 1. Model: custom kinematic body plus a control law
- **`KartBody`** (`src/core/kart/`, `RefCounted`, Core) owns physical state and the step:
  - integration;
  - ground and wall queries;
  - suspension, air and landing;
  - overlap resolution;
  - wall response;
  - knock;
  - contacts.
- **`DriveState`** plus the **`drive()` control law** (`src/gameplay/driving/`, Gameplay) owns every feel decision:
  - steering curve;
  - drift start, lock and end;
  - drift tiers and charge;
  - boost and the speed cap;
  - start boost and stall;
  - spin and hit slowdowns;
  - surface effects and slick tails;
  - air yaw control;
  - trick arming and the trick boost.
- **The boundary is one Core-owned type, `KartIntent`.** Driving writes it and the body reads it. The body never reads `DriveState`, `DriverInput` or `SurfaceType`. Driving never calls `CollisionQuery`; it reads `KartSnapshot` only.
- **Speed ownership:**
  - Driving computes the commanded signed speed along the heading for this tick, `target_speed`. It starts from last tick's `snapshot.speed`, which already includes wall and bump losses. It applies throttle, brake, coast, the cap, overspeed decay, surface drag, spin drag and slowdown: the frozen `_update_speed` minus slope gravity.
  - The body adds slope gravity and applies wall and bump losses. The result is the new `speed`.
  - This keeps one integrator of speed per tick and lets physics losses feed back next tick, as in the frozen kart.

### 2. `BodyState` fields (inside `KartBody`)

| Field | Type | Meaning |
|---|---|---|
| `position` | `Vector3` | Ride point: the kart origin at ride height above the contact plane |
| `basis` | `Basis` | -Z heading, +Y up. Rebuilt every tick from `up` and heading (§4), so it is orthonormal and up is exact |
| `gravity` | `Vector3` | Per body (ADR-0001 §3). Default `-world_up × air_gravity`. ADR-0009 changes it |
| `velocity` | `Vector3` | World velocity relative to the support, excluding `knock` and the platform velocity |
| `speed` | `float` | Signed speed along the heading (what Driving reads) |
| `knock` | `Vector3` | Bump knock on the up plane. Decays at `bump_knock_decay` and is capped at `bump_knock_max` |
| `pending_push` | `Vector3` | Kart-vs-kart separation decided last tick, swept with this tick's motion (§7) |
| `ground_normal` | `Vector3` | Smoothed contact normal (the up target when grounded) |
| `ride_offset`, `ride_velocity` | `float` | Spring state along up: gap above ride height and its rate |
| `grounded` | `bool` | |
| `air_time` | `float` | |
| `support_id` | `int` | `GroundHit.collider_id`: 0 = static, otherwise a mover id |
| `support_velocity` | `Vector3` | Point velocity of the support at the contact |
| `surface_id` | `int` | Majority surface of the ground hits; ties go to the lowest probe index; kept while airborne |
| `last_heading` | `Vector3` | Fallback for a degenerate heading projection (ADR-0001 §3) |
| `wall_cooldown`, `wall_slide_time` | `float` | Frozen wall-impact timers |
| `bump_cooldown` | `float` | |
| `pair_bump_mag`, `pair_bump_timer` | `PackedFloat32Array` | One entry per racer slot (sized from `RacerRegistry` capacity at race start), replacing the frozen per-tick `Dictionary` |
| `events` | `int` bit flags + payload floats | This tick's took-off, landed (airtime, impact), wall hit (hard, angle), bumped (strength), depenetrated, teleported |
| `tick` | `int` | Last stepped tick |

The scalar yaw is derived only (`yaw_derived()`), as ADR-0001 requires.

### 3. `KartIntent` (Core type, written by Driving each tick)
| Field | Meaning |
|---|---|
| `yaw_rate` | rad/s about the body's up. Ground or air rate; Driving chooses it from `snapshot.grounded` |
| `target_speed` | m/s, signed, along the heading (§1) |
| `grip` | 1/s lateral grip rate. The body lerps the velocity toward `heading × speed` at `clamp(grip × dt, 0, 1)` (frozen model). Driving applies drift grip, surface `grip_mult` and bank gain. The body clamps it to `wall_slide_grip` while `wall_slide_time > 0`, because that is wall physics |
| `hop` | bool. Default effect: none on the body except that `hop_speed` (new `VehicleStats` field, default **0.0** for parity) is added along up when grounded. The frozen hop is visual and only arms the trick window, which stays in Driving |
| `steer`, `throttle` | Pass-through for the snapshot (audio and visuals) |

**DriveState persistence.**
- `DriveState` is one object per racer. It lives as long as the race and is owned by the racer's controller in Gameplay.
- It holds:
  - drift state, direction, time and tier;
  - boost, spin, stall and slowdown timers;
  - slick tail;
  - air yaw rate;
  - the since-hop timer and the trick-pending flag;
  - the previous drift button;
  - the start-boost level.
- It is reset by the respawn and start events only.
- Boost pads, trick boost on landing and surface changes enter through `drive()`'s inputs:
  - the pad test result;
  - `snapshot.events` (landed, airtime);
  - `snapshot.surface_id`, looked up in the core `SurfaceSet` (ADR-0002).
- `drive()` keeps the architecture signature, with the surface resolved by the caller: `drive(state, input, snap, stats, surface, dt, out)`.

### 4. Per-tick step order (`KartBody.step`)
For each racer simulated on this PC, in `RacerRegistry` slot order (ADR-0001 §6):

1. **Next-tick events.** Remote `KartEvent`s queued since last tick are applied first, through `apply_event` (§8).
2. **Intent.** The controller calls `drive()` with last tick's snapshot and writes the `KartIntent`.
3. **Integrate.**
   1. Rotate the heading about `up` by `yaw_rate × dt`, plus the support's yaw rate when on a mover (§9).
   2. When grounded:
      - set `speed = target_speed + slope_gravity × ĝ·heading × dt`, where ĝ is the unit gravity and the heading lies on the up plane (frozen slope term; lateral slope adds nothing);
      - lerp `velocity` toward `heading × speed` by grip;
      - remove the velocity component along up.
   3. When airborne: `velocity += gravity × dt`. There is no grip, throttle or drag (frozen).
   4. The motion is `(velocity + knock + support_velocity) × dt + pending_push + hop`.
4. **Wall sweep slide loop** (§5). A sphere is swept from the current to the proposed point. Up to `slide_max_sweeps` (**3**) sweeps run, and the `started_inside` overlap resolution happens inside the loop (§6).
5. **Ground cast** (2 to 4 rays, §5) at the resolved point.
6. **Suspension, air and landing** (§5).
7. **Up and basis.**
   - Smooth the up: `up = up.slerp(target, 1 − exp(−up_smoothing × dt))`.
     - When grounded, the target is `ground_normal`.
     - In the air, the target is `−gravity.normalized()` and the rate is `air_up_smoothing`.
   - Rebuild the basis (keeps up exact; plain Gram-Schmidt would keep X):
     - `heading = (−basis.z − up × (−basis.z·up))`, normalised. If its length is below `HEADING_EPSILON`, use `last_heading`.
     - `z = −heading`
     - `x = up.cross(z)`
     - `basis = Basis(x, up, z)`
8. **Timers and knock decay.** Wall and bump cooldowns, the pair timers, and `knock *= exp(−bump_knock_decay × dt)`.
9. **Snapshot.** `snapshot(out)` writes `KartSnapshot` for this tick.

After every simulated kart has stepped:

10. **Course progress.** `CourseData.progress` runs per kart, in slot order (ADR-0004).
11. **Kart-vs-kart contact** (§7). It uses the progress from step 10 for the broadphase.
12. **Same-tick local effects.**
    - Hazard hit tests (the victim decides) and pad tests run on the new snapshot.
    - A spin or sink starts this tick, which matches the frozen behaviour (`architecture.md` Data Flow 1).

**Deviation from the brief's suggested order:** walls are swept **before** the ground cast, not after. If rays are cast at the un-slid proposed point, a kart pressed against a wall reads the ground on the other side of it. That can be a lower road behind the wall, a drop, or nothing, which causes false takeoffs and wrong surface ids. Sweeping first means the rays always sample the ground where the kart actually ends the tick. The cost is the same. The sweep sphere's height uses last tick's ground, which is accurate to one tick of ride motion.

### 5. Queries, suspension, air
- **Sweep shape:**
  - a **sphere** of radius `VehicleStats.radius` (cart 1.0 m, bike 0.85 m, as in the frozen wall clamp);
  - centred at `position + up × sweep_center_height` (new field, default = the radius);
  - one `SphereShape3D` per `QueryCursor` (ADR-0002).
  - Walls are on their own layer, so the sphere never catches the ground.
  - A capsule is deferred (see Alternatives).
- **Slide loop:**
  1. Sweep from `from` to `to`.
  2. On a hit:
     - move to `fraction` minus `wall_skin` (new `KartPhysicsConfig` field, default 0.02 m);
     - take the wall normal projected onto the up plane, normalised (a wall never lifts or presses the kart);
     - remove the normal component from the remaining motion, measured relative to the wall's `collider_velocity` for movers;
     - sweep the remainder.
  3. The **first** contact each tick runs the frozen wall response on `speed` and `velocity`:
     - the angle between the velocity and the wall tangent;
     - impact above `wall_impact_threshold_angle` when the cooldown allows: speed loss, `wall_slide_time`;
     - otherwise scrape drag, scaled by the `WallAttrSet` entry for `wall_attr` (ADR-0002);
     - optional bounce, from the wall attribute.
     The remaining motion and the velocity both lose their into-wall component.
  4. When the cap is reached, the remaining motion is dropped and the kart stays at the last safe point. Worst case 3 sweeps, as ADR-0002 budgets.
- **Ground rays:**
  - **4 rays at the wheel contact points.** These are a new per-vehicle field `ground_probe_points: PackedVector3Array` in kart-local metres. The default is the 4 wheel positions of `VehicleVisualStats` (±0.75, −0.7 / 0.75).
  - A vehicle may list **2 or 3** (the war bike: 2 on the centre line, plus a centre ray if testing shows rocking). Fewer rays cost less.
  - Each ray starts `probe_lift` above the probe point along up and is cast along `−up`, with `max_dist = probe_lift + air_takeoff_gap + ride_snap_margin`.
  - From the hits:
    - **contact height** = the mean hit offset along up;
    - **contact normal** = the normalised sum of the hit normals;
    - **surface id** = the majority;
    - **support** = the collider id and point velocity of the hit nearest the centre of mass (ties go to the lower probe index).
- **Suspension (decision: a single damped spring, not a fixed ride height and not per-wheel springs):**
  - The ride offset along up follows the contact plane through the frozen spring:
    - `ride_spring` 900, `ride_damping` 42;
    - target velocity clamped to `ride_max_target_speed`;
    - clamped between 0 (never below the support) and `ride_max_gap` 0.3.
  - It gives the frozen landing settle and the crest float.
  - Pitch and roll come only from the smoothed normal. There is no per-wheel compression.
  - A fixed ride height snaps on every step change and loses the landing feel. Per-wheel springs would add pitch dynamics the owner has not tuned, and jitter at 60 Hz.
- **Takeoff:** the kart leaves the ground when no ray hits, or when the gap above the contact plane exceeds `air_takeoff_gap` (0.45). The body keeps its full velocity, including the support's velocity, which is inherited when leaving a platform. The took-off event is set.
- **Landing:**
  - When airborne and the gap reaches 0 or less, the kart snaps to the plane.
  - The impact speed is the into-ground speed relative to the support.
  - The velocity component along the new up is removed, and `speed` = velocity·heading.
  - The landed event carries airtime and impact. Driving pays the trick boost from it.
- **Up smoothing:**
  - `up_smoothing` (ground) and `air_up_smoothing` are new per-vehicle fields.
  - Defaults are the frozen visual `surface_tilt_smoothing` 14 / `tilt_smoothing` 5. Physics now uses them: banking is physical (ADR-0001 §4).

### 6. Overlap resolution (`started_inside`)
- `sweep_walls` reports `started_inside` from its unconditional rest check at `from` (ADR-0002). Inside the slide loop, such a sweep result triggers a push-out.
- **Push-out:**
  - depth `d = radius − (centre − hit.point)·n`, where n is the rest normal projected onto the up plane;
  - `from` moves along n by `min(d + wall_skin, max_depenetration_per_tick)`;
  - `max_depenetration_per_tick` is a new `KartPhysicsConfig` field, default 0.25 m, which is 15 m/s and below the cart's max speed;
  - the velocity loses its into-wall component;
  - the loop retries from the corrected point. The retry counts against the 3-sweep cap.
  - A deeper overlap keeps being pushed on following ticks.
- **Movers that move into the kart:** the same push-out applies. In addition, the into-kart component of the mover's `collider_velocity` is added to `velocity`, so a swinging hammer shoves the kart instead of trapping it. Whether the hit also spins the kart is Track Hazards' call (`HazardEffect`).
- A kart whose centre has passed fully behind a one-sided wall is not seen by the rest check (`backface_collision = false`). That case is left to Fall & Respawn, through `CourseProgress` and route `outside`. Story 022 measures how often it happens.

### 7. Kart-vs-kart contact
- **Shape:** each kart is a segment of half-length `bump_half_length` along its heading, inflated by `bump_radius` (the frozen model in 3D). Closest points between segments come from an allocation-free helper in `src/core/kart/`. `Geometry3D.get_closest_points_between_segments` returns a new `PackedVector3Array` per call, so it is not used per tick.
- **Vertical gate:** if `|d·up_i| > bump_max_height_diff`, there is no contact (decks, jumps). The contact normal is projected onto the up plane of kart i.
- **Broadphase on course distance:**
  1. Each tick, a preallocated slot list is insertion-sorted by `CourseProgress.s`, taken modulo the lap length. The list is nearly sorted from tick to tick, so this is O(n).
  2. Pairs are candidates when their Δs is at most `2 × max(bump_half_length + bump_radius) + broadphase_margin`. The new `KartPhysicsConfig` field `broadphase_margin` defaults to 2.0 m. The list wraps at the lap end.
  3. Karts whose progress is invalid (off course, flying, or relocated this tick) are tested against all others.
  4. Candidate pair keys `(i, j)` with i < j are sorted ascending and resolved in that order, for determinism (ADR-0001 §6).
  5. Sinking or respawning karts are skipped.
- **Resolution (same tick, for karts simulated here):**
  - **Separation:** the push is split by `bump_push_mult` share, as in the frozen kart. It is **not** applied to `position` now. It is stored in `pending_push` and swept with the next tick's motion (§4 step 3), so a shove can never push a kart into or through a wall.
    - This replaces the frozen `_separate_karts`, which made 3 passes and ran `clamp_to_walls` 12 times per pass: 38% of the frozen tick.
    - The cost is an overlap that lasts at most one tick (16.7 ms), within the bump radius.
  - **Closing speed:**
    - when the karts are closing, the knock impulse is `n × closing × share × (1 + bump_restitution)`;
    - the strength is `closing / bump_full_impact_speed`;
    - the speed loss is `bump_speed_loss × strength` behind `bump_cooldown`;
    - the per-slot pair memory stops a contact from being felt twice.
  - Because the push is deferred, results within a tick do not depend on pair order. The ordered pass still fixes the order of the knock-cap clamps and the cooldown gates.
- **Remote karts** (interpolated from snapshots, never simulated):
  - the local kart resolves against the remote `KartSnapshot` the same tick and takes only its own share;
  - the remote's share is sent as a reliable `KartEvent` bump;
  - the remote's owner applies it at the **start of its next tick** (§4 step 1). Its pair memory dedups it against a contact it detected itself.

  This keeps the frozen same-tick / next-tick rule: local hits apply in the same tick, events from other PCs apply next tick.

### 8. Events and teleports
- `apply_event(e: KartEvent)` covers:
  - bump (impulse, strength, from slot);
  - respawn (pose);
  - launch (velocity, for cannons);
  - spin and hit effects (forwarded to Driving by the controller, not the body);
  - hold, for a clock resync.
- **Respawn, launch and resync hold** set `teleported` in the next snapshot (ADR-0001 §8). Respawn and resync hold also clear `velocity`, `knock`, `pending_push`, the spring state and the support.

### 9. Moving platforms
- **While grounded on a mover:**
  - `support_velocity` = `GroundHit.collider_velocity`, the point velocity, which is rotation-aware (ADR-0002 v3);
  - it is added to the motion every tick, so the kart is carried.
- **Rotating platforms:** `GroundHit` carries no angular velocity. The body's heading is turned by the support's yaw about up, taken from `q.mover_pose(id, t)` against `q.mover_pose(id, t − SIM_DT)`. That is two calls to the single evaluator; no system keeps its own copy (ADR-0002).
- **Leaving a mover:** the support velocity is folded into `velocity` once, so the kart keeps the platform's momentum.
- **Moving walls:** the slide loop works relative to `WallHit.collider_velocity` (§5, §6).

### 10. Tuning data
- **Instances:**
  - Per-vehicle values come from **new instances** of `VehicleStats`, forked into `assets/data/core/vehicles/armored_cart.tres` and `war_bike.tres` (ADR-0001 §9). The frozen `assets/data/vehicles/*.tres` are never read.
  - The fork copies every existing value unchanged, which is the parity baseline.
- **New per-vehicle fields** are added **additively** to `VehicleStats`, each with a `##` doc comment and a default that equals the intended value:
  - `ground_probe_points`;
  - `probe_lift`, 0.5 m;
  - `ride_snap_margin`, 0.3 m;
  - `sweep_center_height`;
  - `up_smoothing`, 14;
  - `air_up_smoothing`, 5;
  - `hop_speed`, 0.
- **New global values** go in a new `KartPhysicsConfig` Resource (`src/core/kart/`), instance `assets/data/core/kart_physics.tres`:
  - `slide_max_sweeps`, 3, asserted at most 3 at load because of ADR-0002's budget;
  - `wall_skin`, 0.02 m;
  - `max_depenetration_per_tick`, 0.25 m;
  - `broadphase_margin`, 2.0 m.
- `HEADING_EPSILON` (1e-4) is a named `const`: it is a numeric guard, not tuning.
- The `WallAttrSet` and `SurfaceSet` instances (ADR-0002) live in `assets/data/core/`.

### Architecture Diagram

```
DriverInput ─┐
KartSnapshot(n-1) ─┼─▶ drive(DriveState, ..., stats, SurfaceSet[surface_id]) ──▶ KartIntent {yaw_rate, target_speed, grip, hop}
pad / landed / surface ┘          (src/gameplay/driving, Gameplay)                     │
                                                                                     ▼
KartEvent queue (remote, n-1) ─▶ apply_event ─▶ KartBody.step(SIM_DT, intent, CollisionQuery, cursor, t = n·SIM_DT)   (src/core/kart, Core)
                                   integrate ─▶ sweep_walls ×≤3 (+ push-out on started_inside) ─▶ cast_ground ×2..4
                                   ─▶ ride spring / air / landing ─▶ up slerp + basis rebuild ─▶ snapshot(out)
                                                                                     │
all karts stepped ─▶ CourseData.progress ─▶ sort by s ─▶ candidate pairs (i<j) ─▶ resolve_contact
                                                         │ local: knock + pending_push (swept next tick)
                                                         └ remote: own share now, KartEvent to owner (next tick)
                 ─▶ hazard / pad tests (same tick) ─▶ presentation, SnapshotCodec (ADR-0006), ghosts
```

### Key Interfaces

Each `class_name` lives in its own file. The Core types are in `src/core/kart/`; `DriveState` is in `src/gameplay/driving/`.

```gdscript
class_name KartIntent extends RefCounted        # Core-owned; written by Driving, read by KartBody
var yaw_rate: float; var target_speed: float; var grip: float; var hop: bool
var steer: float; var throttle: float            # pass-through to the snapshot

class_name KartSnapshot extends RefCounted      # plain data; ADR-0006 owns its wire encoding
var tick: int; var position: Vector3; var velocity: Vector3; var basis: Basis
var grounded: bool; var surface_id: int; var support_id: int; var speed: float
var drift_state: int; var boost: float; var spin: float; var sinking: bool   # copied in from DriveState by the controller
var steer: float; var accel: float; var air_time: float
var events: int; var land_airtime: float; var land_impact: float; var wall_angle: float; var bump_strength: float
var teleported: bool

class_name KartBody extends RefCounted
func _init(stats: VehicleStats, config: KartPhysicsConfig, slot: int, slot_capacity: int) -> void
func place(pose: Transform3D, gravity: Vector3) -> void          # grid / respawn; sets teleported
func step(dt: float, intent: KartIntent, q: CollisionQuery, cursor: QueryCursor, t: float) -> void
func resolve_contact(other: KartSnapshot, other_shape: KartContactShape, other_push: float,
        my_push: float, out: ContactResult) -> bool               # same-tick; returns the other's share in out
func apply_event(e: KartEvent) -> void                           # start of tick only
func snapshot(out: KartSnapshot) -> void
func heading() -> Vector3
func yaw_derived() -> float                                      # HUD / minimap only

class_name KartContactShape extends RefCounted  # half_length, radius, max_height_diff (from VehicleStats)
class_name ContactResult extends RefCounted     # impulse_for_other: Vector3, strength: float
class_name KartEvent extends RefCounted         # kind, from_slot, impulse/velocity: Vector3, strength, pose: Transform3D
class_name KartContactSolver extends RefCounted # broadphase on CourseProgress.s; preallocated lists; resolve_all(bodies, snaps, progress)
class_name KartPhysicsConfig extends Resource   # slide_max_sweeps, wall_skin, max_depenetration_per_tick, broadphase_margin

# Gameplay (src/gameplay/driving/)
class_name DriveState extends RefCounted
static func drive(state: DriveState, input: DriverInput, snap: KartSnapshot, stats: VehicleStats,
        surface: SurfaceType, dt: float, out: KartIntent) -> void
```

Usage example (doc-comment form, the composition root's tick):
```gdscript
## for slot in registry.slots_simulated_here():          # slot order
##     body.apply_queued_events()
##     DriveState.drive(drive_states[slot], inputs[slot], snaps[slot], stats[slot], surface_set.get_type(snaps[slot].surface_id), SIM_DT, intents[slot])
##     bodies[slot].step(SIM_DT, intents[slot], query, cursors[slot], tick * SIM_DT)
##     bodies[slot].snapshot(snaps[slot])
## course.progress(...) per slot; contact_solver.resolve_all(...)
```

### Implementation Guidelines
- `KartBody` **must** be `RefCounted`, own no nodes, and run headless with no SceneTree physics frame.
- `src/core/kart/` **must never** reference `src/gameplay/`, `DriveState`, `DriverInput`, `SurfaceType` or `src/legacy/`. `KartIntent` is the only input from Driving.
- Driving **must never** call `CollisionQuery` or mutate `KartBody`. It reads `KartSnapshot` and writes `KartIntent` only.
- `step` **must** use the `dt` passed in (always `SIM_DT`) and the tick time `t` passed in for every query and mover pose. It **must never** read `delta`, the wall clock or a global RNG.
- The basis **must** be rebuilt every tick from `up` and the projected heading, keeping up exact. A stored scalar yaw is forbidden.
- Gravity **must** come from the body's `gravity` field. `Vector3.DOWN` **must never** appear in `src/core/kart/`.
- The slide loop **must** stop at `slide_max_sweeps`, and that value **must** be asserted at most 3 at load.
- On `started_inside`, the push-out **must** be along the rest normal projected onto the up plane, and **must** be capped at `max_depenetration_per_tick` per tick.
- Kart-vs-kart separation **must** go through `pending_push` and the next tick's swept motion. It **must never** write `position` directly.
- Contact pairs **must** be resolved with i < j, in ascending pair order, after every kart has stepped and progress is updated.
- Remote bump events **must** be applied only at the start of the owner's next tick.
- Per-tick code **must** allocate nothing in steady state:
  - no `Dictionary` per pair;
  - no `PackedVector3Array` from `Geometry3D` per call;
  - no `new()` of results;
  - per-slot arrays are preallocated at race start.
- Every tuning value **must** come from the forked `VehicleStats` instance or `KartPhysicsConfig` under `assets/data/core/`. New `VehicleStats` fields **must** be additive, with defaults.
- Mover poses **must** be read only through `CollisionQuery.mover_pose` / `mover_point_velocity`.
- A respawn, launch or resync hold **must** set `teleported` in the snapshot.

## Alternatives Considered

### Alternative 1: `CharacterBody3D` with `move_and_slide`
- **Description:** each kart is a `CharacterBody3D` node. It uses `up_direction` from the ground normal, `floor_snap_length`, and the engine's slide and platform-velocity handling.
- **Pros:** slide, floor snap and platform carry come built in. It is well documented up to 4.3.
- **Cons:**
  - It is a node: it ties the simulation to the SceneTree, against Principle 1 and the headless tests.
  - It moves through the World3D's space. ADR-0002's `CollisionQuery` uses a private server space, and its movers are analytic, not bodies. `move_and_slide` sees neither.
  - Its contact results are `KinematicCollision3D` objects, allocated per collision, with no `face_index` surface lookup.
  - Its floor, wall and ceiling classification and its snap are engine-tuned and opaque. They are known to jitter on trimesh edges in 4.x (from memory; not checked against the 4.8 reference).
  - ADR-0001's catch-up ticks need several steps per `_physics_process`. A node moved there is seen by queries only on the next frame (spike Q2).
  - The frozen feel would have to be rebuilt on top of its velocity model.
- **Rejection Reason:** it breaks Principle 1 and ADR-0002's private-space design, and it hides the slide, snap and overlap policy that ADR-0002 hands to this ADR.

### Alternative 2: `RigidBody3D` (or `VehicleBody3D`) on Jolt
- **Description:** a dynamic body with forces for drive and grip and raycast wheels, stepped by the Jolt solver.
- **Pros:** physically plausible tumbling, stacking and kart-kart response come for free.
- **Cons:**
  - Arcade control by force is hard to match to a direct yaw-rate and speed-cap law. Drift lock, caps and instant boost feel would all fight the solver.
  - Godot exposes no per-space manual step from GDScript (unverified for 4.8). The body would advance on the engine's physics frame, not on ADR-0001's target-tick catch-up.
  - The private inactive space would have to become an active, stepped space.
  - Solver contact between karts replaces the tuned bump model.
  - Feel parity with the golden traces would be a tuning project with no bound.
  - Remote karts are never simulated anyway, so physical realism gains nothing online.
- **Rejection Reason:** it breaks ADR-0001's tick ownership, makes parity with the frozen feel unbounded, and buys realism the arcade design does not want.

### Alternative 3: Fixed ride height (no spring)
- **Description:** the kart is set at ride height above the contact plane every tick.
- **Pros:** simplest. There is no oscillation.
- **Cons:** it snaps on steps and kerbs, the frozen landing settle is lost, and crest float (the lead-in to small hops) is lost.
- **Rejection Reason:** feel parity. The frozen spring costs a few multiplies per kart.

### Alternative 4: Per-wheel springs
- **Description:** four suspension springs, each with its own compression, which together give pitch and roll.
- **Pros:** richer body motion.
- **Cons:** 4× the state. Pitch dynamics the owner has never tuned. Jitter risk at 60 Hz on triangle seams. Cosmetic lean is already in presentation (ADR-0001 §4).
- **Rejection Reason:** no feel requirement needs it. It can come back as a Presentation-only effect.

### Alternative 5: Ground cast before the wall sweep (the brief's suggested order)
- **Rejection Reason:** rays at the un-slid point read the ground past a wall (§4). Same cost, worse result.

### Alternative 6: Capsule sweep along the heading
- **Rejection Reason:** deferred. A sphere matches the frozen radial wall clamp and costs least. A capsule is reconsidered if story 022 shows the nose clipping walls in tight hairpins.

### Alternative 7: All 66 pairs, no broadphase
- **Rejection Reason:** this stays the fallback. Its worst case is near the frozen 0.28 ms for 132 ordered pairs, over the 0.2 ms budget. The broadphase cuts the typical count to under 15 pairs.

## Consequences

### Positive
- The feel stays where the owner tuned it. Driving's control law carries over nearly line for line, and only the geometry path is new.
- Clean layering: Core physics knows nothing about drift, boost or surfaces, and gameplay knows nothing about collision.
- The frozen tick's dominant costs disappear:
  - spline scans are replaced by ADR-0002 queries;
  - the 3-pass `_separate_karts` with wall re-clamps is replaced by a deferred, swept push.
- Every collision path is bounded: at most 3 sweeps and 4 rays per kart per tick.
- Anti-gravity (ADR-0009) only changes `gravity` and the up target.

### Negative
- All slide, snap and depenetration policy is ours to maintain, and edge cases (corners, seams, thin decks) are ours to find.
- Kart-kart overlap persists for up to one tick.
- One-sided walls mean a fully tunnelled kart is not pushed back. It is recovered by respawn.
- `VehicleStats` grows by 7 fields that the frozen game ignores.

## Risks
- **NEEDS VERIFICATION, rest-info geometry.** The push-out depth formula assumes that `get_rest_info_into` gives a point on the wall and a normal pointing toward the kart for a start overlap with a one-sided triangle. Mitigation: a unit test in story 022 with a sphere placed 0.3 m into a fixture wall. If the assumption fails, `CollisionQuery` must expose the depth in `WallHit` (an additive ADR-0002 change).
- **NEEDS VERIFICATION, `WallHit` content when `started_inside` and a cast hit both occur** (which rest check fills point and normal). Mitigation: settle it with ADR-0002's implementer before the slide loop is coded.
- **NEEDS VERIFICATION, engine-reference check.** `docs/engine-reference/godot/modules/physics.md` was not read for this draft. These claims come from memory or the ADR-0002 spike and must be checked against it before Acceptance (godot-specialist review):
  - the trimesh jitter of `CharacterBody3D`;
  - that there is no per-space manual step;
  - the allocation of `Geometry3D` closest points.
- **Broadphase misses.** `CourseProgress.s` can lag at junctions (ADR-0004 smoothing caps the rate of change of `s`), and parallel branches share s values. Mitigation:
  - the 2 m margin;
  - karts with invalid progress are tested against all;
  - a debug check in story 022 runs brute force alongside the broadphase and counts misses. Zero misses is the gate.
- **Depenetration cap too low for fast movers.** A hammer faster than 15 m/s could stay inside the kart across ticks. Mitigation: the mover velocity shove (§6), and hazards usually spin the kart. Story 022 tests the fastest planned mover.
- **Up smoothing on loops and sharp crests.** The slerp can lag a fast change of normal, which causes a takeoff at a crest. That may be wanted, as frozen crest float, or may be a bug in loops. Mitigation: tune `up_smoothing` per vehicle. ADR-0009 revisits loops.
- **Parity fails because of geometry, not physics.** The generator-baked mesh differs from the spline: triangulated banks and wall facets. Mitigation: the parity harness drives a trace-following pilot (Validation Criteria), so the driver is held constant and only the body and the geometry differ.
- **Budget.** 12 × (4 rays + 3 sweeps) is about 0.1 ms of collision, inside ADR-0002's 0.3 ms. GDScript body math is estimated at 10-15 µs per kart (unmeasured), inside the 0.3 ms. Mitigation: story 022 measures it in a release export.

## GDD Requirements Addressed

| GDD System | Requirement | How This ADR Addresses It |
|------------|-------------|--------------------------|
| systems-index.md row 6: Kart Physics | Mesh collision; body, contact, kart-vs-kart bumps, variable up vector | Custom kinematic `KartBody` on `CollisionQuery`; wall slide loop and overlap push-out; course-distance broadphase contact; up from the smoothed ground normal with an exact-up basis |
| systems-index.md row 9: Driving & Drift | Control law, drift, boost, surface grip and caps | `DriveState.drive()` owns them all; `KartIntent` (`yaw_rate`, `target_speed`, `grip`, `hop`) is the only boundary |
| systems-index.md row 13: Track Features | Boost pads via Driving; ramps, jumps, cannons via Physics | Pads are same-tick tests feeding `drive()`; ramps through the ground rays, spring, takeoff and landing; cannons through the `launch` event with teleport |
| systems-index.md row 14: Track Hazards | Dynamic colliders | Movers through `collider_velocity` (ground and wall), `started_inside` shove, platform yaw from `mover_pose` |
| systems-index.md row 12: Fall & Respawn | Respawn on the new core | `respawn` event, teleport flag; tunnelled karts left to respawn |
| systems-index.md row 26: Air Tricks | Air state and landing | Air state, airtime and impact in the snapshot events; the trick boost stays in Driving |
| systems-index.md row 27: Anti-Gravity & Wall-Riding | Variable up | Per-body gravity and up target only (ADR-0009) |
| architecture.md Performance Budgets (amended 2026-11-22) | Kart physics and driving 0.3 ms; contact 0.2 ms p95 for 12 | Bounded queries, zero-allocation step, broadphase (Performance Implications) |

No system GDD exists yet. This table cites `design/gdd/systems-index.md` rows and `architecture.md`. The GDD sync check is **NOT ASSESSED**: there are no GDDs to compare names against.

## Performance Implications
- **CPU, kart physics and driving (budget 0.3 ms p95, 12 karts):**
  - The frozen body dynamics measured about 0.1 ms. That is the share of `KartSim.tick` outside the track queries (`perf-per-system.md`; `KartSim.tick` in total is 0.81 ms median, mostly `TrackModel.query`).
  - The new step adds the basis rebuild and the slerp, a few µs per kart.
  - Its queries are charged to ADR-0002's row: about 4 × 0.8 + 3 × 1.6 µs per kart, so ≤ 0.1 ms for 12 in the worst case.
  - Estimate: 0.1-0.2 ms. Unmeasured.
- **CPU, kart-vs-kart contact (budget 0.2 ms p95):** the frozen contacts cost 1.88 ms mean (47% of the tick), of which 1.52 ms was the separation passes with wall re-clamps. The new design has no re-clamps, one pass and under 15 candidate pairs typically. Estimate < 0.05 ms. Unmeasured.
- **Memory:** about 1 KB per kart. The per-slot pair arrays are 2 × 12 floats. Nothing is allocated per tick.
- **Load time:** none beyond loading two `.tres` files.
- **Network:** none here. The `KartSnapshot` fields are encoded by ADR-0006, and bump events reuse the reliable channel.

## Migration Plan
- The frozen `KartSim` stays untouched in `src/legacy/`. The new code is written fresh.
- `DriveState.drive()` is a port of the frozen control law into `src/gameplay/driving/`:
  - drift block, steering curve and air yaw from `tick()`;
  - `_update_speed` without slope gravity;
  - `_update_surface`;
  - `_end_drift`;
  - the start and slowdown functions.
  It is re-typed against `KartSnapshot` and `KartIntent`. The port is a re-implementation; nothing is imported from `src/legacy/`.
- Order:
  1. Fork the vehicle `.tres` files into `assets/data/core/vehicles/` and add the `VehicleStats` fields with their defaults.
  2. Build `KartBody` with its unit tests on fixture meshes (story 022).
  3. Build `DriveState` and its tests (the Driving migration story).
  4. Build the contact solver.
  5. Build the parity harness.

## Validation Criteria
- **Unit tests (gdUnit4, `tests/unit/kart/`, `tests/unit/driving/`):**
  - flat-ground acceleration reaches `max_speed` and never exceeds the cap under boost;
  - a 90° wall hit loses `wall_impact_max_speed_loss`, and a 15° graze scrapes;
  - a sphere started 0.3 m inside a wall is pushed out by at most `max_depenetration_per_tick` per tick and is clear within 2 ticks;
  - the slide loop never runs more than 3 sweeps (counter);
  - a ramp lip at 26 m/s takes off, and the landing reports airtime and impact;
  - on a 30° bank, the basis' up equals the smoothed normal within 1e-4, and `basis` is orthonormal within 1e-5 after 36,000 ticks;
  - on a translating platform the kart is carried with zero relative drift, and on a rotating platform its heading turns with it;
  - a mover moving into the kart sets `started_inside` and shoves it;
  - kart pair: a head-on contact gives symmetric knock, the pair is not felt twice within `bump_cooldown`, and karts 2 m apart vertically never touch;
  - the broadphase finds the same pairs as brute force over a 12-kart race (zero misses);
  - determinism: two runs with the same inputs give bit-identical `KartSnapshot` streams on one machine.
- **Parity rule against the frozen kart** (`production/qa/evidence/core-rebuild-story-001/golden/`). This is not bit-identical; it uses stated tolerances.
  - **Setup:** a mesh baked by the generator path (ADR-0005) from the same track (Castle Circuit, Dungeon Depths). A trace-following pilot steers along each golden trace's `x, z, height` path and replays its `drifting` / `drift_dir` and throttle timing, so the driver is held constant.
  - **Gate, solo traces** (cart and bike on both tracks, 4 runs). For each lap:
    - lap time within **±2%** of the golden time (for example Castle Circuit cart 42.27 s → 41.42-43.11 s);
    - top speed within ±3%;
    - drift boosts paid at each tier: equal counts ±1;
    - takeoff and landing count equal at the same jumps;
    - no wall-stuck interval (speed < 2 m/s for more than 1 s after the start);
    - lap count exact.
  - **Advisory, bot traces** (`bots_*.csv`): the race finish spread is reported. Bots are rebuilt, so this does not gate.
  - **Owner A1 sign-off on feel:** the owner drives cart and bike on the baked Castle Circuit and signs off. The tolerances above are proposed; the owner may change them at sign-off.
- **Benchmark (story 022):** 12 karts in a running tree, release export, owner's PC. Kart physics and driving ≤ 0.3 ms p95. Contact ≤ 0.2 ms p95.
- **Grep:**
  - no `src/legacy` or `src/gameplay` reference under `src/core/kart/`;
  - no `Vector3.DOWN`, `randf`, `randi` or `delta` in `src/core/kart/`;
  - no `Dictionary(` or `Geometry3D.` in the per-tick paths.

## Related
- ADR-0001 Simulation conventions (depends on: §3 orientation, §5 tick, §6 determinism, §8 teleport and interpolation, §9 data forks)
- ADR-0002 Collision backend (depends on: `CollisionQuery`, `WallHit.started_inside`, `collider_velocity`; this ADR decides the overlap resolution, the sweep shape and radius, and the slide cap ADR-0002 delegated)
- ADR-0004 Course data (depends on: `CourseProgress.s` for the broadphase; respawn poses)
- ADR-0006 Network snapshot for 3D (enabled: encodes `KartSnapshot`; bump `KartEvent` on the reliable channel)
- ADR-0009 Anti-gravity and wall-riding (enabled: per-body gravity and up target)
- `docs/architecture/architecture.md` (API Boundaries: Kart Physics, Driving & Drift; Data Flow 1-3; Performance Budgets amended 2026-11-22)
- `design/gdd/systems-index.md` rows 6, 9, 12, 13, 14, 26, 27
- `production/qa/evidence/core-rebuild-story-001/perf-per-system.md`, `golden/`
- Frozen reference (feel only, never imported): `src/legacy/vehicle/kart_sim.gd`, `assets/data/vehicles/armored_cart.tres`, `war_bike.tres`
