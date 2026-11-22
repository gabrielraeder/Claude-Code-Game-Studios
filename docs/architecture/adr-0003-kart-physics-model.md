# ADR-0003: Kart Physics Model

## Status
Proposed

## Date
2026-11-22

## Last Verified
2026-11-22

## Decision Makers
Drafted by engine-programmer (subagent, orchestrated run) from ADR-0001, ADR-0002 v5, ADR-0004, the amended performance budgets in `architecture.md`, the per-system profile of the frozen tick, and the frozen kart. The frozen sources were read for feel and for the network contact model only, never imported: `src/legacy/vehicle/kart_sim.gd`, `src/legacy/main.gd` (contacts, around lines 540-610).

This is **v2**, after the technical-director review (TD-ADR):
- **v1 CONCERNS applied:**
  - bump-loss ordering;
  - the owner-authoritative remote contact;
  - the parity noise floor;
  - the rotating-platform carry;
  - hop through the spring;
  - the step-up contract with ADR-0005;
  - housekeeping.
- **The TD approved both v1 deviations from the brief:**
  - the wall sweep runs before the ground cast;
  - the overlap push-out runs inside the slide loop.

The **godot-specialist** findings are folded into this same v2. Its probes ran on 4.8-beta3 and are kept in `prototypes/collision-spike/out/probe_adr3_{rest,math,api}.txt`:
- B1: `sweep_walls` returns at once on `started_inside` (ADR-0002 amendment);
- B2: the wall-top guard;
- S1: depth from the raw rest normal;
- S2: pose-delta carry;
- S3: unswept moves;
- S4: units for the safe fraction;
- S5: hop through `ride_velocity`;
- the verified engine facts and the minor items.

Acceptance needs the owner's confirmation.

## Summary
The rebuilt 3D core needs a kart body with these properties:
- it drives on Blender meshes through Track Collision (ADR-0002);
- it keeps the frozen kart's arcade feel and its owner-authoritative bump model;
- it runs headless and deterministically within 0.3 ms per tick for 12 karts;
- it leaves feel decisions (drift, boost, surfaces) to Driving & Drift.

This ADR chooses a **custom kinematic `KartBody` (RefCounted)** in Core. Each tick, the Gameplay-layer **`DriveState` control law** gives it a `KartIntent`. The ADR fixes:
- the body state;
- the per-tick step order: a wall slide loop capped at 3 sweeps with bounded overlap push-out, then 2 to 4 ground rays, a single damped ride spring, and up from a smoothed normal;
- kart-vs-kart contact behind a course-distance broadphase, with the snapshot written after contact;
- moving platforms carried by pose delta;
- a lap-time parity rule measured above the harness's own noise floor.

`CharacterBody3D` and `RigidBody3D` on Jolt are rejected.

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.8-beta3 (Jolt Physics 5.6.0, through ADR-0002) |
| **Domain** | Physics |
| **Layer** | Core |
| **Knowledge Risk** | HIGH (post-cutoff, pre-release engine). This ADR's own code is mostly plain GDScript math (`Vector3`, `Basis`, `Quaternion`). Every engine physics call goes through ADR-0002's `CollisionQuery`. |
| **References Consulted** | `docs/engine-reference/godot/VERSION.md`. ADR-0001 §3, §5, §6, §8. ADR-0002 v5 (its "Verified on 4.8-beta3" list). `production/qa/evidence/core-rebuild-story-001/perf-per-system.md`. `docs/engine-reference/godot/modules/physics.md` was read by the godot-specialist and holds nothing on these points. godot-specialist probes on 4.8-beta3: `prototypes/collision-spike/out/probe_adr3_rest.txt`, `probe_adr3_math.txt`, `probe_adr3_api.txt` |
| **Post-Cutoff APIs Used** | None directly. Used indirectly through `CollisionQuery`: `intersect_ray_into`, `cast_motion_into`, `get_rest_info_into` (4.8, verified by ADR-0002). |
| **Verified on 4.8-beta3 (godot-specialist probes)** | (1) Rest geometry is exact for face and edge contacts: the point lies on the surface within 4.8e-6 and the depth is right within 6.7e-6. At an inner corner, rest returns only the deepest contact, so a corner takes 2 push-out sweeps. (2) `PhysicsGetRestInfoResult3D` has no depth field, so depth is computed (§6). (3) The cast is blind from an overlapped start (probe F), so `sweep_walls` returns at once on `started_inside` (ADR-0002 v5 amendment). (4) A `Basis` rebuilt from up and heading stays orthonormal without `orthonormalized()` (3.6e-7 over 36k ticks), and `basis.y` equals `up` exactly. (5) No per-space step method exists (ClassDB). (6) `Geometry3D.get_closest_points_between_segments` allocates (88 B per call). The GDScript helper is allocation-free. `get_closest_point_to_segment` returns a `Vector3` and does not allocate. (7) Debug-build costs: up slerp plus basis rebuild 0.41 µs per kart; contact about 0.4 µs per pair (about 6 µs for fewer than 15 pairs). |
| **Verification Required** | (1) The cost of body + `drive()` for 12 karts, measured in story 022's first slice. (2) How often the wall-top guard (§6) fires on real tracks, counted by story 022. |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | ADR-0001 (Accepted): axes, `Basis` orientation, per-body gravity, `SIM_DT`, tick time `t = n × SIM_DT`, slot step order, RNG streams, teleport flag, `assets/data/core/` forks. ADR-0002 v5 (Proposed, must be Accepted first): `CollisionQuery`, `GroundHit`, `WallHit` (`started_inside`, `collider_velocity`), `QueryCursor`, `mover_pose`. ADR-0004 (Proposed, must be Accepted first): `CourseProgress.s` / `distance` for the broadphase. ADR-0005 (Proposed): the generator bake path for the parity harness's meshes, and the step-up rule in `track_check` (§5). |
| **Enables** | ADR-0006 (network snapshot for 3D: encodes the `KartSnapshot` fields defined here and carries `distance` for the remote broadphase). ADR-0009 (anti-gravity and wall-riding: changes only the per-body gravity and the up target). ADR-0010 (ghosts record `KartSnapshot` streams). |
| **Blocks** | Story 022 (kart physics on the mesh). The Driving & Drift migration story. Fall & Respawn, Track Features (ramps, cannons) and Track Hazards (mover hits) on the new core. |
| **Ordering Note** | ADR-0002 hands three choices to this ADR: overlap resolution, the sweep shape and radius, and the slide-loop cap. They are decided in §5 and §6. The per-system budget amendment to `architecture.md` (2026-11-22) has landed: kart physics and driving 0.3 ms, kart-vs-kart contact 0.2 ms, p95 for 12 karts. **Requirement on ADR-0005:** `track_check` must enforce the step-up rule of §5. |

## Context

### Problem Statement
The frozen kart (`KartSim`) is a 2.5D kinematic model on the XZ plane. It uses a height spring and asks a spline `TrackModel` for road, walls and decks. The rebuild drives on triangle meshes baked from Blender (ADR-0005), with real 3D slopes, banks, decks and loops. Anti-gravity (ADR-0009) comes later.

The kart body must decide five things each tick:
- how to move;
- what it stands on;
- how it meets walls and other karts, including karts owned by other PCs;
- how it rides moving platforms;
- how it flies and lands.

It must also keep the feel the owner tuned over stories 001-011. Story 022 cannot start until these choices are fixed, and Driving & Drift cannot be migrated until its boundary with the body (`KartIntent`) is fixed.

### Constraints
- Architecture Principle 1: simulation objects are `RefCounted`, independent of the SceneTree, and testable headless.
- ADR-0001: fixed `SIM_DT` with catch-up ticks; same-machine determinism; slot step order; pairs i < j; no global RNG; no stored scalar yaw; no hard-coded `Vector3.DOWN`.
- ADR-0002: all geometry goes through `CollisionQuery` on a private, inactive Jolt space. Up to 3 sweeps per kart per tick fit its budget. Jolt casts ignore start overlaps. Steep ground never blocks a kart: walls are a separate layer.
- Each PC simulates its own karts; remote karts are interpolated, never simulated (`architecture.md` Data Flow 3).
- Engine code (`src/core/`) must never depend on gameplay code (`src/gameplay/`) or networking code (`src/networking/`).
- New code must not reference `src/legacy/` or read a frozen `.tres` instance.
- `VehicleStats` (`src/data/`) may change only additively.

### Requirements
- Same feel as the frozen kart, held to the parity rule in Validation Criteria:
  - acceleration to a cap that boosts never exceed;
  - grip lerp, which gives the drift slide;
  - wall scrape and wall impact;
  - bump knock with the speed loss read on the next tick;
  - the owner-authoritative remote bump;
  - ride spring, takeoff and landing;
  - slope gravity along the road only.
- Variable up vector: banks, ramps, and loops later.
- Moving and rotating platforms; moving obstacles.
- Budgets, p95 for 12 karts: kart physics and driving 0.3 ms per tick; kart-vs-kart contact 0.2 ms per tick.
- Bounded allocation, zero in steady state.
- A `KartSnapshot` per tick for presentation, the network (ADR-0006) and ghosts.

## Decision

### 1. Model: custom kinematic body plus a control law
- **`KartBody`** (`src/core/kart/`, `RefCounted`, Core) owns the physical state and the step:
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
  - Driving computes the commanded signed speed along the heading for this tick, `target_speed`. It starts from `snapshot.speed`, which already includes this tick's received bumps (§4 step 1) and last tick's wall and local bump losses. It applies throttle, brake, coast, the cap, overspeed decay, surface drag, spin drag and slowdown: the frozen `_update_speed` minus slope gravity.
  - The body adds slope gravity and applies wall and bump losses. The result is the new `speed`.
  - One integrator of speed per tick, and every physics loss is read by the next `drive()`, as in the frozen kart (`_take_bump` lands the loss on `speed`, and the next tick reads it).

### 2. `BodyState` fields (inside `KartBody`)

| Field | Type | Meaning |
|---|---|---|
| `position` | `Vector3` | Ride point: the kart origin at ride height above the contact plane |
| `basis` | `Basis` | -Z heading, +Y up. Rebuilt every tick from `up` and heading (§4), so it is orthonormal and up is exact |
| `gravity` | `Vector3` | Per body (ADR-0001 §3). Default `-world_up × air_gravity`. ADR-0009 changes it |
| `velocity` | `Vector3` | Driving velocity relative to the support, excluding `knock` and the support's motion |
| `speed` | `float` | Signed speed along the heading (what Driving reads) |
| `knock` | `Vector3` | Bump knock and mover shove on the up plane. Decays at `bump_knock_decay` and is capped at `bump_knock_max` |
| `pending_push` | `Vector3` | Kart-vs-kart separation decided last tick, swept with this tick's motion (§7) |
| `ground_normal` | `Vector3` | Smoothed contact normal (the up target when grounded) |
| `ride_offset`, `ride_velocity` | `float` | Spring state along up: gap above ride height, and its rate |
| `grounded` | `bool` | |
| `air_time` | `float` | |
| `hop_airborne` | `bool` | This flight started from a hop alone (§3), so it never counts as trick airtime |
| `support_id` | `int` | `GroundHit.collider_id`: 0 = static, otherwise a mover id |
| `support_velocity` | `Vector3` | Point velocity of the support at the contact (landing impact, momentum on leaving) |
| `surface_id` | `int` | Majority surface of the ground hits; ties go to the lowest probe index; kept while airborne. Starts at 0 (road) |
| `last_heading` | `Vector3` | Fallback for a degenerate heading projection (ADR-0001 §3) |
| `wall_cooldown`, `wall_slide_time` | `float` | Frozen wall-impact timers |
| `bump_cooldown` | `float` | Gates the speed loss and the `bumped` signal, as in the frozen kart |
| `pair_bump_mag`, `pair_bump_timer` | `PackedFloat32Array` | One entry per racer slot (sized from `RacerRegistry` capacity at race start). The max-merge dedup memory (§7), replacing the frozen `Dictionary` |
| `events` | `int` bit flags + payload floats | Accumulated from the start of tick n (received events) through contact. Bits: took-off, landed (airtime, impact), wall hit (hard, angle), bumped (strength), depenetrated, teleported. Cleared only after the end-of-tick snapshot is written (§4) |
| `tick` | `int` | Last stepped tick |

The scalar yaw is derived only (`yaw_derived()`), as ADR-0001 requires.

### 3. `KartIntent` (Core type, written by Driving each tick)
| Field | Meaning |
|---|---|
| `yaw_rate` | rad/s about the body's up. Ground or air rate; Driving chooses it from `snapshot.grounded` |
| `target_speed` | m/s, signed, along the heading (§1) |
| `grip` | 1/s lateral grip rate. The body lerps the velocity toward `heading × speed` at `clamp(grip × dt, 0, 1)` (frozen model). Driving applies drift grip, surface `grip_mult` and bank gain. The body clamps it to `wall_slide_grip` while `wall_slide_time > 0`, because that is wall physics |
| `hop` | bool. When grounded, the body adds `hop_speed` (new `VehicleStats` field) to `ride_velocity`, so any takeoff goes through the normal `air_takeoff_gap` path (§5). **`hop_speed` stays 0.0 (visual hop only) through parity.** A physical hop is the owner's decision after the A1 sign-off. If it is enabled, a flight that a hop alone started (`hop_airborne`) never counts as trick airtime. The trick window stays in Driving |
| `steer`, `throttle` | Pass-through to the snapshot, for audio and visuals |

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
  - `snapshot.events` (landed, airtime, `hop_airborne`);
  - `snapshot.surface_id`, looked up in the core `SurfaceSet` (ADR-0002).
- `drive()` keeps the architecture signature, with the surface resolved by the caller: `drive(state, input, snap, stats, surface, dt, out)`.

### 4. Per-tick step order
**Choice for bump-loss ordering:** the final snapshot is written **after contact**, and it is **refreshed after the queued remote events are applied**. With this, `drive()` always reads the body's current speed, and no bump loss (local or remote) or `bumped` bit is lost. Driving keeps reading `KartSnapshot` only.

For tick n, for each racer simulated on this PC, in `RacerRegistry` slot order (ADR-0001 §6):

1. **Received events.**
   - Remote `KartEvent`s queued since the last tick are applied through `apply_event` (§7, §8). This is the frozen `apply_received_bump`: a max-merge knock, and the speed loss behind `bump_cooldown`.
   - Then `snapshot(snap)` is **refreshed**. It now carries the reduced `speed` and the `bumped` bit.
2. **Intent.** The controller calls `drive()` with that snapshot and writes the `KartIntent`.
3. **Integrate.**
   1. Rotate the heading about `up` by `yaw_rate × dt`.
   2. When grounded:
      - set `speed = target_speed + slope_gravity × ĝ·heading × dt`, where ĝ is the unit gravity and the heading lies on the up plane (frozen slope term; lateral slope adds nothing);
      - lerp `velocity` toward `heading × speed` by grip;
      - remove the velocity component along up.
   3. When airborne: `velocity += gravity × dt`. There is no grip, throttle or drag (frozen).
   4. The motion is `(velocity + knock) × dt + pending_push + carry`. Here `carry` is the support's pose-delta displacement when the kart stands on a mover (§9), or `support_velocity × dt` for one tick after leaving it; otherwise 0.
4. **Wall sweep slide loop** (§5). A sphere is swept from the current to the proposed point. Up to `slide_max_sweeps` (**3**) sweeps run, and the `started_inside` overlap resolution happens inside the loop (§6).
5. **Ground cast** (2 to 4 rays, §5) at the resolved point.
6. **Suspension, air and landing** (§5). The moves after the sweep are **not swept**: the ride spring's move along up, the landing snap and the up slerp. An overlap they create is resolved on the next tick as `started_inside`, by the unconditional rest check at `from` (ADR-0002) and §6. Story 022 counts `started_inside` by cause (wall start, mover, unswept move).
7. **Up and basis.**
   - Smooth the up: `up = up.slerp(target, 1 − exp(−up_smoothing × dt))`.
     - When grounded, the target is `ground_normal`.
     - In the air, the target is `−gravity.normalized()` and the rate is `air_up_smoothing`.
     - **Antiparallel guard:** if `up.dot(target) < UP_ANTIPARALLEL_DOT` (a named const, −0.9999), the slerp axis is undefined. Instead, `up` is rotated about the heading axis by the same fraction of π.
   - Rebuild the basis (keeps up exact; plain Gram-Schmidt would keep X):
     - `heading = (−basis.z − up × (−basis.z·up))`, normalised. If its length is below `HEADING_EPSILON`, use `last_heading`.
     - `z = −heading`
     - `x = up.cross(z)`
     - `basis = Basis(x, up, z)`
8. **Timers and knock decay.** Wall and bump cooldowns, the pair timers, and `knock *= exp(−bump_knock_decay × dt)`.
9. **Pre-contact snapshot.** `snapshot(snap)`. Contact and progress read this snapshot.

After every simulated kart has stepped:

10. **Course progress.** `CourseData.progress` runs per kart, in slot order (ADR-0004).
11. **Kart-vs-kart contact** (§7).
    - It reads only pre-contact snapshots: local karts from step 9, remote karts from the sampled remote poses.
    - The results therefore do not depend on pair order.
    - It writes speed loss, knock, `pending_push` and the `bumped` bit into the local bodies.
12. **End-of-tick snapshot.** `snapshot(snap)` again, for every simulated kart. Then `events` is cleared. Presentation, `SnapshotCodec` (ADR-0006) and ghosts copy this snapshot.
13. **Same-tick local effects.**
    - Hazard hit tests (the victim decides) and pad tests run on the end-of-tick snapshot.
    - A spin or sink starts this tick, which matches the frozen behaviour (`architecture.md` Data Flow 1).
    - Their effects reach Driving through `DriveState` and the next `drive()`.

**Deviations from the brief's suggested order (approved by the TD in TD-ADR v1):**
- **Walls are swept before the ground cast.** If rays are cast at the point before the slide, a kart pressed against a wall reads the ground on the other side of it (a lower road, a drop, or nothing). That gives false takeoffs and wrong surface ids.
- **The push-out runs inside the slide loop** (§6), not as a pass after it. The cast ignores a start overlap, so it would carry the kart deeper first.

### 5. Queries, suspension, air
- **Sweep shape:**
  - a **sphere** of radius `VehicleStats.radius` (cart 1.0 m, bike 0.85 m, as in the frozen wall clamp);
  - centred at `position + up × sweep_center_height` (new field, default = the radius);
  - one `SphereShape3D` per `QueryCursor` (ADR-0002).
  - Walls are on their own layer, so the sphere never catches the ground.
- **Slide loop:**
  1. Sweep from `from` to `to`.
  2. On a hit:
     - move along the motion by `max(safe_fraction × L − wall_skin, 0)` metres, where L is the length of the remaining motion and `wall_skin` defaults to 0.02 m;
     - take the wall normal projected onto the up plane, normalised (a wall never lifts or presses the kart);
     - remove the normal component from the remaining motion, measured relative to the wall's `collider_velocity` for movers;
     - sweep the remainder.
  3. The **first** contact each tick runs the frozen wall response on `speed` and `velocity`:
     - the angle between the velocity and the wall tangent;
     - impact above `wall_impact_threshold_angle` when the cooldown allows: speed loss, `wall_slide_time`;
     - otherwise scrape drag, scaled by the `WallAttrSet` entry for `wall_attr` (ADR-0002);
     - optional bounce, from the wall attribute.
     The remaining motion and the velocity both lose their into-wall component.
  4. **A hit reported at `to` when the cast was clear** (ADR-0002's rest check at `to`) is a **touch**:
     - the kart moves the full motion;
     - there is no slide;
     - the wall response runs as a scrape, if this is the first contact this tick;
     - the velocity loses its into-wall component.
  5. When the cap is reached, the remaining motion is dropped and the kart stays at the last safe point. Worst case 3 sweeps, as ADR-0002 budgets.
- **Ground rays:**
  - **4 rays at the wheel contact points.** These are a new per-vehicle field `ground_probe_points: PackedVector3Array` in kart-local metres. The default is the 4 wheel positions of `VehicleVisualStats` (±0.75, −0.7 / 0.75).
  - A vehicle may list **2 or 3** (the war bike: 2 on the centre line, plus a centre ray if testing shows rocking).
  - Each ray starts `probe_lift` above the probe point along up and is cast along `−up`, with `max_dist = probe_lift + air_takeoff_gap + ride_snap_margin`.
  - From the hits:
    - **contact height** = the mean hit offset along up;
    - **contact normal** = the normalised sum of the hit normals;
    - **surface id** = the majority;
    - **support** = the collider id and point velocity of the hit nearest the centre of mass (ties go to the lower probe index).
- **Step-up contract with ADR-0005:**
  - The **maximum step-up height is `probe_lift`** (default 0.5 m).
  - Anything a kart must not climb, whether a rise taller than `probe_lift` or ground steeper than the drivable limit, **must be on the wall layer**.
  - **ADR-0005's `track_check` must enforce this** on every baked track. This is a requirement on ADR-0005.
  - A ground step taller than `probe_lift` is invisible to the rays from below and is not swept. Without the check, it would either be climbed through or tunnelled.
- **Suspension (decision: a single damped spring; not a fixed ride height, not per-wheel springs):**
  - The ride offset along up follows the contact plane through the frozen spring:
    - `ride_spring` 900, `ride_damping` 42;
    - target velocity clamped to `ride_max_target_speed`;
    - clamped between 0 (never below the support) and `ride_max_gap` 0.3.
  - Pitch and roll come only from the smoothed normal.
- **Takeoff:**
  - The kart leaves the ground when no ray hits, or when the gap above the contact plane exceeds `air_takeoff_gap` (0.45). A hop takes the same path, through `ride_velocity` (§3).
  - On a mover, the support's point velocity is folded into `velocity` once, so the kart keeps the platform's momentum.
  - The took-off event is set.
- **Landing:**
  - When airborne and the gap reaches 0 or less, the kart snaps to the plane.
  - The impact speed is the into-ground speed relative to the support.
  - The velocity component along the new up is removed, and `speed` = velocity·heading.
  - The landed event carries airtime, impact and `hop_airborne`. Driving pays the trick boost from it.
- **Up smoothing:**
  - `up_smoothing` (ground) and `air_up_smoothing` are new per-vehicle fields.
  - Defaults are the frozen visual `surface_tilt_smoothing` 14 / `tilt_smoothing` 5. Physics now uses them: banking is physical (ADR-0001 §4).

### 6. Overlap resolution (`started_inside`)
- **Contract (ADR-0002 v5 amendment, quoted from the coordinator's brief):** "When `started_inside` is set (by the rest check at `from` or by the analytic mover overlap), `sweep_walls` returns true at once. Point, normal, wall_attr, collider_id and collider_velocity come from the overlap, `fraction` = 0, and no cast runs. When a static wall and a mover both overlap, the deeper one wins." The reason is probe F: the cast is blind from an overlapped start.
- Inside the slide loop, such a result triggers a push-out. Definitions: c = sphere centre, p = `hit.point`, n = raw rest normal, `n_h` = n projected onto the up plane, r = sweep radius.
- **Wall-top guard (checked first):**
  - It applies if `|n_h| < WALL_NORMAL_MIN` (a named const, 0.3) or `|c − p| < 1e-4`.
  - Then there is no horizontal push-out and no wall response on this sweep. The kart is over a wall top, and the ground cast or Fall & Respawn handles it.
  - The `depenetrated` event is still set, with a guard cause, so story 022 can count it.
  - The loop goes on with the remaining motion.
- **Push-out (otherwise):**
  - depth `d = r − (c − p)·n`, using the **raw** rest normal;
  - `from` moves along `n_h.normalized()` by `min(d / (n·n̂_h) + wall_skin, max_depenetration_per_tick)`, where n̂_h is the unit `n_h`. The division turns the depth along n into the horizontal distance that clears it, which is right on sloped walls and edges (probe C). The cap defaults to 0.25 m, which is 15 m/s, below the cart's max speed;
  - the velocity loses its into-wall component;
  - the `depenetrated` event is set;
  - the loop retries from the corrected point. The retry counts against the 3-sweep cap.
  - Rest reports only the deepest contact (verified), so an inner corner takes 2 push-out sweeps. A deeper overlap keeps being pushed on following ticks.
- **Movers that move into the kart:**
  - the same push-out applies;
  - the into-kart component of the mover's `collider_velocity` is added to **`knock`**, not `velocity`, and is capped at `bump_knock_max`, so a swinging hammer shoves the kart and the shove fades like a bump instead of becoming driving speed.
  - Whether the hit also spins the kart is Track Hazards' call (`HazardEffect`).
- A kart whose centre has passed fully behind a one-sided wall is not seen by the rest check (`backface_collision = false`). That case is left to Fall & Respawn, through `CourseProgress` and route `outside`. Story 022 measures how often it happens.

### 7. Kart-vs-kart contact
This section ports the frozen owner-authoritative model (`main.gd` `_resolve_kart_contacts`, `_separate_karts`, `_push_of`, `_on_bump_received`; `kart_sim.gd` `resolve_kart_contact`, `_take_bump`) into 3D.

- **Shape:** each kart is a segment of half-length `bump_half_length` along its heading, inflated by `bump_radius`.
  - Closest points between segments come from an allocation-free helper in `src/core/kart/`.
  - **Vertical gate:** if `|d·up_i| > bump_max_height_diff`, there is no contact (decks, jumps).
  - The contact normal is projected onto the up plane of kart i.
- **Which pairs:**
  - A pair is resolved only if **at least one kart is simulated on this PC**. Pairs of two remote karts are skipped.
  - **The frozen 50/50 display-only push between two remote karts is dropped.** So is the display-only pass that drew a remote kart aside from an own kart pinned against a wall.
    - Neither ever moved simulation state: each owner moves its own kart through the bump message.
    - If the owner sees remote karts overlapping after A1, a display-only offset may be added later in `RemoteKartView` (Presentation). It must never feed back into the simulation.
- **Broadphase on course distance:**
  1. The sort key is `distance` modulo the lap length:
     - for local karts, from their `CourseProgress`;
     - for remote karts, from the `distance` in their latest snapshot (ADR-0004 / ADR-0006).
  2. A preallocated slot list is insertion-sorted by that key each tick. The list is nearly sorted from tick to tick, so this is O(n).
  3. Pairs are candidates when their key difference is at most `2 × max(bump_half_length + bump_radius) + broadphase_margin` (2.0 m). The list wraps at the lap end.
  4. Karts with invalid progress (off course, flying, or relocated this tick) are tested against all others.
  5. Candidate pair keys `(i, j)` with i < j are sorted ascending and resolved in that order, for determinism (ADR-0001 §6).
  6. Sinking or respawning karts are skipped.
- **Remote pose:**
  - A remote kart is tested at the **interpolated pose that `RemoteKartView` draws, sampled at the tick**: its buffer evaluated at `n × SIM_DT − view_delay`.
  - The composition root writes that sample into a `KartSnapshot` and passes it in. Core never references `src/networking/`.
  - `KartSnapshot.velocity` is the **total world velocity** (`velocity + knock + carry velocity`). That makes local and remote snapshots comparable, and the closing speed matches the frozen `velocity + knock` term.
- **Push weights:**
  - The push weight of a kart is its `bump_push_mult`.
  - It is multiplied by `KartPhysicsConfig.bot_push_mult` (**0.35**, forked from the frozen `assets/data/net/net_config.tres`) when that kart is a bot and the other is not: bots push humans less (frozen `_push_of`).
  - The bot/human flag comes from `RacerRegistry` and is passed in by the contact solver. The body does not know it.
- **Both karts simulated here:**
  - **Separation:** split by weight share (`share = other_push / (my_push + other_push)`), stored in each kart's `pending_push`, and swept with the next tick's motion (§4 step 3).
    - It is never written to `position`, so a shove cannot push a kart into or through a wall.
    - This replaces the frozen 3-pass `_separate_karts` with its wall re-clamps, which was 38% of the frozen tick.
    - The cost is an overlap that lasts at most one tick (16.7 ms).
  - **Knock, when the karts are closing:**
    - kart i takes `−n × closing × share × (1 + bump_restitution)`;
    - kart j takes the rest;
    - strength is `closing / bump_full_impact_speed`;
    - the speed loss `bump_speed_loss × strength` applies behind each kart's `bump_cooldown`.
- **Against a kart another PC owns:**
  - (a) The local kart takes the **full separation** into its own `pending_push`. Only the **knock** is split by share.
  - The other kart's share of the knock (`n × closing × (1 − share) × (1 + bump_restitution)`) and the strength go to its owner as a reliable `KartEvent` bump. The owner applies it at the **start of its next tick** (§4 step 1).
  - This keeps the frozen rule: local hits apply in the same tick, events from other PCs apply on the next tick.
- **Dedup: the frozen max-merge, not first-wins.**
  - For each other kart's slot, `pair_bump_mag` holds the largest knock magnitude felt from that kart within `bump_cooldown`.
  - A new impulse of magnitude m adds only the part above it: `knock += impulse × (m − already) / m`, then `pair_bump_mag = m` and the pair timer is reset.
  - This applies to local contacts and to received events alike, so a contact both PCs detect is felt once at its larger size.
  - The total knock stays capped at `bump_knock_max`.

### 8. Events and teleports
- `apply_event(e: KartEvent)` runs at the start of a tick only (§4 step 1) and is followed by a snapshot refresh. It covers:
  - bump (impulse, strength, from slot) → max-merge knock, speed loss, `bumped` bit;
  - respawn (pose);
  - launch (velocity, for cannons);
  - hold, for a clock resync.
- Spin and hit effects go to `DriveState` through the controller, not to the body.
- **Respawn, launch and resync hold** set `teleported` in the next snapshot (ADR-0001 §8). Respawn and resync hold also clear `velocity`, `knock`, `pending_push`, the spring state, the support and the pair memory.

### 9. Moving platforms
- **While grounded on a mover**, the kart is carried by the **platform's pose delta**, not by point velocity × dt.
  - `D = mover_pose(id, t) × mover_pose(id, t − SIM_DT).affine_inverse()`.
  - Position: `position = D × position`. It is applied as `carry = D × position − position` inside the swept motion (§4 step 3), so the result is identical when no wall intervenes, and a platform cannot carry the kart through a wall.
  - Heading: rotated by `D.basis` and re-projected onto the up plane in the basis rebuild (§4 step 7). The yaw therefore comes from the same delta.
  - Point velocity × dt would follow the tangent and drift outward by about r(ω dt)²/2 per tick, and that error compounds. The pose delta is exact for any rigid motion of the platform.
- Both poses come from `CollisionQuery.mover_pose`, the single evaluator (ADR-0002).
- `support_velocity` (the point velocity from `GroundHit.collider_velocity`) is still used:
  - for the landing impact;
  - for the momentum kept on leaving: it is folded into `velocity` once at takeoff (§5).
- **Moving walls:** the slide loop works relative to `WallHit.collider_velocity` (§5). A mover's shove goes into `knock` (§6).

### 10. Tuning data
- **Instances:**
  - Per-vehicle values come from **new instances** of `VehicleStats`, forked into `assets/data/core/vehicles/armored_cart.tres` and `war_bike.tres` (ADR-0001 §9). The frozen `assets/data/vehicles/*.tres` are never read.
  - The fork copies every existing value unchanged, which is the parity baseline.
- **New per-vehicle fields** are added **additively** to `VehicleStats`, each with a `##` doc comment:
  - `ground_probe_points`;
  - `probe_lift`, 0.5 m (also the maximum step-up, §5);
  - `ride_snap_margin`, 0.3 m;
  - `sweep_center_height`, the radius;
  - `up_smoothing`, 14;
  - `air_up_smoothing`, 5;
  - `hop_speed`, 0.
- **New global values** go in a new `KartPhysicsConfig` Resource (`src/core/kart/`), instance `assets/data/core/kart_physics.tres`:
  - `slide_max_sweeps`, 3, asserted at most 3 at load (ADR-0002 budget);
  - `wall_skin`, 0.02 m;
  - `max_depenetration_per_tick`, 0.25 m;
  - `broadphase_margin`, 2.0 m;
  - `bot_push_mult`, 0.35, forked from the frozen `NetConfig`.
- **Rule: `KartPhysicsConfig` holds no per-vehicle feel values.** Anything that could differ between the cart and the bike belongs in `VehicleStats`.
- `HEADING_EPSILON` (1e-4) is a named `const`: it is a numeric guard, not tuning.
- The `WallAttrSet` and `SurfaceSet` instances (ADR-0002) live in `assets/data/core/`.

### Architecture Diagram

```
tick n:
KartEvent queue (remote) ─▶ apply_event (max-merge knock, speed loss) ─▶ snapshot refresh
snapshot ─┬─▶ drive(DriveState, input, snap, stats, SurfaceSet[surface_id]) ──▶ KartIntent   (src/gameplay/driving)
pad/landed┘                                                                        │
                                                                                   ▼
KartBody.step(SIM_DT, intent, CollisionQuery, cursor, t = n·SIM_DT)   (src/core/kart)
   integrate (+pending_push, +platform pose-delta carry) ─▶ sweep_walls ×≤3 (+ push-out on started_inside)
   ─▶ cast_ground ×2..4 ─▶ ride spring / air / landing (not swept) ─▶ up slerp + basis rebuild ─▶ pre-contact snapshot
                                                                                   │
all stepped ─▶ CourseData.progress ─▶ sort by distance mod lap (remote: snapshot distance)
            ─▶ pairs (i<j, ≥1 simulated here) vs pre-contact / sampled remote snapshots
               │ both local: split push into pending_push, split knock, speed loss
               └ vs remote: full push here, split knock, KartEvent(bump) to owner → its tick n+1
            ─▶ end-of-tick snapshot (events cleared) ─▶ hazard / pad tests ─▶ presentation, SnapshotCodec, ghosts
```

### Key Interfaces

Each `class_name` lives in its own file. The Core types are in `src/core/kart/`; `DriveState` is in `src/gameplay/driving/`.

```gdscript
class_name KartIntent extends RefCounted        # Core-owned; written by Driving, read by KartBody
var yaw_rate: float; var target_speed: float; var grip: float; var hop: bool
var steer: float; var throttle: float            # pass-through to the snapshot

class_name KartSnapshot extends RefCounted      # plain data; ADR-0006 owns its wire encoding
var tick: int; var position: Vector3; var basis: Basis
var velocity: Vector3                            # TOTAL world velocity: driving + knock + platform carry
var grounded: bool; var surface_id: int; var support_id: int; var speed: float
var drift_state: int; var boost: float; var spin: float; var sinking: bool   # copied in from DriveState by the controller
var steer: float; var accel: float; var air_time: float; var hop_airborne: bool
var events: int; var land_airtime: float; var land_impact: float; var wall_angle: float; var bump_strength: float
var distance: float                              # from CourseProgress (local) or the wire (remote), for the broadphase
var teleported: bool

class_name KartBody extends RefCounted
func _init(stats: VehicleStats, config: KartPhysicsConfig, slot: int, slot_capacity: int) -> void
func place(pose: Transform3D, gravity: Vector3) -> void          # grid / respawn; sets teleported
func apply_event(e: KartEvent) -> void                           # start of tick only; caller refreshes the snapshot after
func step(dt: float, intent: KartIntent, q: CollisionQuery, cursor: QueryCursor, t: float) -> void
func take_contact(push: Vector3, knock_impulse: Vector3, strength: float, from_slot: int) -> void   # max-merge; called by the solver
func snapshot(out: KartSnapshot) -> void
func heading() -> Vector3
func yaw_derived() -> float                                      # HUD / minimap only

class_name KartContactShape extends RefCounted  # half_length, radius, max_height_diff, push_mult (from VehicleStats)
class_name KartContactSolver extends RefCounted # broadphase + pair resolution; preallocated lists
func resolve_all(bodies: Array[KartBody], snaps: Array[KartSnapshot], shapes: Array[KartContactShape],
        simulated_here: PackedByteArray, is_bot: PackedByteArray, out_events: Array[KartEvent]) -> int   # returns the event count
class_name KartEvent extends RefCounted         # kind, from_slot, to_slot, impulse/velocity: Vector3, strength, pose: Transform3D
class_name KartPhysicsConfig extends Resource   # slide_max_sweeps, wall_skin, max_depenetration_per_tick, broadphase_margin, bot_push_mult

# Gameplay (src/gameplay/driving/)
class_name DriveState extends RefCounted
static func drive(state: DriveState, input: DriverInput, snap: KartSnapshot, stats: VehicleStats,
        surface: SurfaceType, dt: float, out: KartIntent) -> void
```

Usage example (doc-comment form, the composition root's tick):
```gdscript
## for slot in registry.slots_simulated_here():                       # slot order
##     for e in inbox.take(slot): bodies[slot].apply_event(e)
##     bodies[slot].snapshot(snaps[slot])                                # refresh: drive() sees received bumps
##     DriveState.drive(drive_states[slot], inputs[slot], snaps[slot], stats[slot],
##             surface_set.get_type(snaps[slot].surface_id), SIM_DT, intents[slot])
##     bodies[slot].step(SIM_DT, intents[slot], query, cursors[slot], tick * SIM_DT)
##     bodies[slot].snapshot(snaps[slot])                                # pre-contact
## course.progress(...) per slot; remote_views.sample_into(snaps, tick * SIM_DT - view_delay)
## var n_ev := contact_solver.resolve_all(bodies, snaps, shapes, simulated_here, is_bot, out_events)
## for slot in registry.slots_simulated_here(): bodies[slot].snapshot(snaps[slot])   # end of tick
## net.send_bumps(out_events, n_ev); hazards / pads on snaps
```

### Implementation Guidelines
- `KartBody` **must** be `RefCounted`, own no nodes, and run headless with no SceneTree physics frame.
- `src/core/kart/` **must never** reference any of these:
  - `src/gameplay/`, `src/networking/` or `src/legacy/`;
  - `DriveState`, `DriverInput` or `SurfaceType`.
  `KartIntent` is the only input from Driving, and remote karts arrive as `KartSnapshot`s.
- Driving **must never** call `CollisionQuery` or mutate `KartBody`. It reads `KartSnapshot` and writes `KartIntent` only.
- The snapshot **must** be refreshed after `apply_event` and before `drive()`. The end-of-tick snapshot **must** be written after contact, and `events` **must** be cleared only after it.
- `step` **must** use the `dt` passed in (always `SIM_DT`) and the tick time `t` passed in for every query and mover pose. It **must never** read `delta`, the wall clock or a global RNG.
- The basis **must** be rebuilt every tick from `up` and the projected heading, keeping up exact. A stored scalar yaw is forbidden.
- Gravity **must** come from the body's `gravity` field. `Vector3.DOWN` **must never** appear in `src/core/kart/`.
- The slide loop **must** stop at `slide_max_sweeps`, and that value **must** be asserted at most 3 at load.
- On `started_inside`, the push-out:
  - **must** compute depth from the raw rest normal;
  - **must** push along its up-plane projection by `d / (n·n̂_h) + wall_skin`;
  - **must** be capped at `max_depenetration_per_tick` per tick.
- A mover's shove **must** go into `knock`.
- When `|n_h| < WALL_NORMAL_MIN` or `|c − p| < 1e-4`, the loop **must** skip the horizontal push-out and the wall response for that sweep, and **must** set the `depenetrated` event with the guard cause. It **must never** divide by `n·n̂_h` in that case.
- The slerp of up **must** use the antiparallel guard (`UP_ANTIPARALLEL_DOT`).
- A clear cast with a rest hit at `to` **must** be treated as a touch with no slide.
- Kart-vs-kart separation **must** go through `pending_push` and the next tick's swept motion. It **must never** write `position` directly.
- Against a kart another PC owns, the local kart **must** take the full separation and only its share of the knock. The rest **must** be sent as a `KartEvent` and applied only at the start of the owner's next tick.
- Pairs with no kart simulated on this PC **must** be skipped.
- Bump dedup **must** be the max-merge per other slot.
- Contact pairs **must** be resolved with i < j, in ascending pair order, against pre-contact snapshots only.
- Platform carry **must** use the mover's pose delta, never point velocity × dt.
- Per-tick code **must** allocate nothing in steady state:
  - no `Dictionary` per pair;
  - no `Geometry3D` helper that returns a packed array;
  - no `new()` of results or events (`KartEvent`s come from a preallocated pool);
  - per-slot arrays are preallocated at race start.
- Every tuning value **must** come from the forked `VehicleStats` instance or `KartPhysicsConfig` under `assets/data/core/`. `KartPhysicsConfig` **must never** hold per-vehicle feel values. New `VehicleStats` fields **must** be additive, with defaults.
- A respawn, launch or resync hold **must** set `teleported` in the snapshot.

## Alternatives Considered

Each rejection stands on Principle 1, ADR-0001's tick ownership and feel parity. The engine facts cited below as supporting reasons were verified by the godot-specialist probes on 4.8-beta3. One from-memory claim, `CharacterBody3D` trimesh jitter, could not be verified and was removed.

### Alternative 1: `CharacterBody3D` with `move_and_slide`
- **Description:** each kart is a `CharacterBody3D` node. It uses `up_direction` from the ground normal, `floor_snap_length`, and the engine's slide and platform-velocity handling.
- **Pros:** slide, floor snap and platform carry come built in.
- **Cons:**
  - It is a node: it ties the simulation to the SceneTree, against Principle 1 and the headless tests.
  - It moves through the World3D's space. ADR-0002's `CollisionQuery` uses a private server space, and its movers are analytic, not bodies. `move_and_slide` sees neither.
  - A node moved during ADR-0001's catch-up ticks is seen by queries only on the next frame (spike Q2).
  - Its slide, snap and overlap policy is opaque, and ADR-0002 hands that policy to this ADR.
- **Rejection Reason:** Principle 1 and ADR-0002's private-space design.

### Alternative 2: `RigidBody3D` (or `VehicleBody3D`) on Jolt
- **Description:** a dynamic body with forces for drive and grip and raycast wheels, stepped by the Jolt solver.
- **Pros:** physically plausible tumbling, stacking and kart-kart response come for free.
- **Cons:**
  - Arcade control by force fights a direct yaw-rate and speed-cap law, and feel parity becomes an unbounded tuning job.
  - The body advances on the engine's physics step, not on ADR-0001's target-tick catch-up. Supporting, verified (ClassDB, 4.8-beta3): no per-space step method exists.
  - The private inactive space would have to become an active, stepped space.
  - Solver contact replaces the tuned owner-authoritative bump model.
  - Remote karts are never simulated anyway.
- **Rejection Reason:** ADR-0001's tick ownership and feel parity.

### Alternative 3: Fixed ride height (no spring)
- **Rejection Reason:** feel parity. It snaps on steps and kerbs, and the frozen landing settle and crest float are lost.

### Alternative 4: Per-wheel springs
- **Rejection Reason:** no feel requirement needs it. It costs 4× the state and adds pitch dynamics the owner has never tuned, with a jitter risk at 60 Hz on triangle seams. Cosmetic lean is already handled in presentation (ADR-0001 §4).

### Alternative 5: Ground cast before the wall sweep (the brief's suggested order)
- **Rejection Reason:** rays at the point before the slide read the ground past a wall (§4). The TD approved the deviation.

### Alternative 6: Capsule sweep along the heading
- **Rejection Reason:** deferred. A sphere matches the frozen radial wall clamp and costs the least. A capsule is reconsidered if story 022 shows the nose clipping walls in tight hairpins.

### Alternative 7: All 66 pairs, no broadphase
- **Rejection Reason:** this stays the fallback. Its worst case is near the frozen 0.28 ms for 132 ordered pairs, which is over the 0.2 ms budget.

### Alternative 8: Platform carry by point velocity × dt
- **Rejection Reason:** it drifts outward by about r(ω dt)²/2 per tick on a rotating platform, and the error compounds. The pose delta is exact (§9).

## Consequences

### Positive
- The feel and the network bump model stay where the owner tuned them. Driving's control law and the owner-authoritative contact carry over nearly line for line; only the geometry path is new.
- Clean layering: Core physics knows nothing about drift, boost, surfaces or the network. Gameplay knows nothing about collision.
- The frozen tick's dominant costs disappear:
  - spline scans are replaced by ADR-0002 queries;
  - the 3-pass separation with wall re-clamps is replaced by a deferred, swept push.
- Every collision path is bounded: at most 3 sweeps and 4 rays per kart per tick.
- Anti-gravity (ADR-0009) only changes `gravity` and the up target.

### Negative
- All slide, snap and depenetration policy is ours to maintain, and edge cases (corners, seams, thin decks) are ours to find.
- Kart-kart overlap persists for up to one tick. Two remote karts may overlap on screen, because the frozen display-only push is dropped.
- One-sided walls mean a fully tunnelled kart is not pushed back. It is recovered by respawn.
- `VehicleStats` grows by 7 fields that the frozen game ignores.
- The snapshot is written three times per tick (refresh, pre-contact, end of tick). Each write is a few field copies.
- Track authoring is bound by the step-up contract, enforced by ADR-0005's `track_check`.

## Risks
- **Closed: rest-info geometry and `WallHit` content.** The probes verified rest geometry for faces and edges (`probe_adr3_rest.txt`). The ADR-0002 v5 amendment fixes `WallHit` on `started_inside` (§6). Remaining risk: the wall-top guard fires, so the kart is neither pushed nor slowed by that wall. Mitigation: ground or Fall & Respawn takes over, and story 022 counts the `depenetrated` guard events per track.
- **Broadphase misses.** Course distance can lag at junctions (ADR-0004 smoothing caps how fast `s` changes), parallel branches share values, and a remote kart's wire `distance` is up to one send interval old. Mitigation:
  - the 2 m margin;
  - karts with invalid progress are tested against all;
  - a debug check in story 022 runs brute force alongside the broadphase and counts misses. Zero misses is the gate.
- **Remote pose latency.** A remote kart is tested where it is drawn (`view_delay` in the past), as in the frozen game. Its owner sees the contact at a different moment. The max-merge dedup and the next-tick event keep that from being felt twice. Mitigation: the 4-PC test in story 022 compares bump counts per PC.
- **Depenetration cap too low for fast movers.** A hammer faster than 15 m/s could stay inside the kart across ticks. Mitigation: the knock shove (§6), and hazards usually spin the kart. Story 022 tests the fastest planned mover.
- **Up smoothing on loops and sharp crests.** The slerp can lag a fast change of normal and cause a takeoff at a crest. Mitigation: tune `up_smoothing` per vehicle. ADR-0009 revisits loops.
- **Parity fails because of geometry, not physics.** Mitigation: the trace-following pilot holds the driver constant, and the tolerances sit above its measured noise floor (Validation Criteria).
- **Budget.** 12 × (4 rays + 3 sweeps) is about 0.1 ms of collision, inside ADR-0002's 0.3 ms. The up slerp plus basis rebuild measured 0.41 µs per kart (debug). The rest of the body math and `drive()` is unmeasured. Mitigation: story 022's first slice measures body + `drive()` against 0.3 ms.
- **Closed: from-memory engine claims.** The no-per-space-step claim and the `Geometry3D` allocation claim were verified by the probes. The `CharacterBody3D` jitter claim was removed. No rejection rested on any of them.

## GDD Requirements Addressed

| GDD System | Requirement | How This ADR Addresses It |
|------------|-------------|--------------------------|
| systems-index.md row 6: Kart Physics | Mesh collision; body, contact, kart-vs-kart bumps, variable up vector | Custom kinematic `KartBody` on `CollisionQuery`; wall slide loop and overlap push-out; course-distance broadphase with owner-authoritative contact; up from the smoothed ground normal with an exact-up basis |
| systems-index.md row 9: Driving & Drift | Control law, drift, boost, surface grip and caps | `DriveState.drive()` owns them all. `KartIntent` (`yaw_rate`, `target_speed`, `grip`, `hop`) is the only boundary. Physics losses reach it through the snapshot refresh |
| systems-index.md row 13: Track Features | Boost pads via Driving; ramps, jumps, cannons via Physics | Pads are same-tick tests feeding `drive()`. Ramps go through the ground rays, spring, takeoff and landing. Cannons use the `launch` event with teleport |
| systems-index.md row 14: Track Hazards | Dynamic colliders | Pose-delta carry on platforms, `collider_velocity` on moving walls, `started_inside` push-out with the shove into knock |
| systems-index.md row 12: Fall & Respawn | Respawn on the new core | `respawn` event, teleport flag; tunnelled karts are left to respawn |
| systems-index.md row 26: Air Tricks | Air state and landing | Air state, airtime, impact and `hop_airborne` in the snapshot events. The trick boost stays in Driving |
| systems-index.md row 27: Anti-Gravity & Wall-Riding | Variable up | Per-body gravity and up target only (ADR-0009) |
| architecture.md Data Flow 1 and 3 | Local hits apply in the same tick, remote events on the next tick; each PC simulates its own karts | §4 steps 1, 11-13; §7 remote contact |
| architecture.md Performance Budgets (amended 2026-11-22) | Kart physics and driving 0.3 ms; contact 0.2 ms p95 for 12 | Bounded queries, zero-allocation step, broadphase (Performance Implications) |

No system GDD exists yet. This table cites `design/gdd/systems-index.md` rows and `architecture.md`. The GDD sync check is **NOT ASSESSED**: there are no GDDs to compare names against.

## Performance Implications
- **CPU, kart physics and driving (budget 0.3 ms p95, 12 karts):**
  - The frozen body dynamics measured about 0.1 ms. That is the share of `KartSim.tick` outside the track queries; in total it is 0.81 ms median, mostly `TrackModel.query`.
  - The new step adds the slerp and basis rebuild (measured 0.41 µs per kart, debug) and up to two `mover_pose` calls per kart on a platform.
  - Its queries are charged to ADR-0002's row: about 4 × 0.8 + 3 × 1.6 µs per kart, so ≤ 0.1 ms for 12 in the worst case.
  - Estimate: 0.1-0.2 ms. Unmeasured; story 022's first slice measures it.
- **CPU, kart-vs-kart contact (budget 0.2 ms p95):** the frozen contacts cost 1.88 ms mean (47% of the tick), of which 1.52 ms was separation passes with wall re-clamps. The new solver has one pass, no re-clamps and under 15 candidate pairs typically. A pair costs about 0.4 µs with the allocation-free helper (debug, probe), so about 6 µs for 15 pairs. Estimate with the broadphase < 0.05 ms.
- **Memory:** about 1 KB per kart. The per-slot pair arrays are 2 × 12 floats. The `KartEvent` pool is preallocated. Nothing is allocated per tick.
- **Load time:** none beyond loading three `.tres` files.
- **Network:** bump events use the reliable channel, at the same rate as the frozen `send_bump`. The `KartSnapshot` fields, including `distance`, are encoded by ADR-0006.

## Migration Plan
- The frozen `KartSim` and `main.gd` stay untouched in `src/legacy/`. The new code is written fresh.
- `DriveState.drive()` is a re-implementation of the frozen control law in `src/gameplay/driving/`:
  - drift block, steering curve and air yaw from `tick()`;
  - `_update_speed` without slope gravity;
  - `_update_surface`;
  - `_end_drift`;
  - the start and slowdown functions.
  It is re-typed against `KartSnapshot` and `KartIntent`. Nothing is imported from `src/legacy/`.
- `KartContactSolver` re-implements `_resolve_kart_contacts`, `_push_of`, `resolve_kart_contact` and `_take_bump`, as §7 changes them.
- Order:
  1. Fork the vehicle `.tres` files and `bot_push_mult` into `assets/data/core/`, and add the `VehicleStats` fields with their defaults.
  2. Build `KartBody` with its unit tests on fixture meshes. In story 022's first slice, measure body + `drive()` against 0.3 ms.
  3. Build `DriveState` and its tests (the Driving migration story).
  4. Build the contact solver.
  5. Build the parity harness. It needs ADR-0005's generator bake path.

## Validation Criteria
- **Unit tests (gdUnit4, `tests/unit/kart/`, `tests/unit/driving/`):**
  - flat-ground acceleration reaches `max_speed` and never exceeds the cap under boost;
  - a 90° wall hit loses `wall_impact_max_speed_loss`, and a 15° graze scrapes;
  - a sphere started 0.3 m inside a wall is pushed out by at most `max_depenetration_per_tick` per tick and is clear within 2 ticks. This holds for a vertical wall, a sloped wall and an edge contact (the `d / (n·n̂_h)` formula);
  - an inner corner clears in 2 push-out sweeps;
  - a kart over a wall top (`|n_h| < WALL_NORMAL_MIN`) gets no horizontal push and no wall response, and has `depenetrated` set with the guard cause;
  - a clear cast with a rest hit at `to` moves the full motion with no slide;
  - the antiparallel up guard: a target exactly opposite to up gives no NaN and an orthonormal basis;
  - the slide loop never runs more than 3 sweeps (counter);
  - a ramp lip at 26 m/s takes off, and the landing reports airtime and impact;
  - with `hop_speed > 0` (test fixture only), a hop lifts through `ride_velocity`, takes off only past `air_takeoff_gap`, and its landing has `hop_airborne` set;
  - on a 30° bank, the basis' up equals the smoothed normal within 1e-4, and `basis` is orthonormal within 1e-5 after 36,000 ticks;
  - on a translating platform the kart is carried with zero relative drift;
  - **on a platform rotating at 1 rad/s, a parked kart 5 m from the axis keeps its radius within 1 mm over 600 ticks (10 s)**, and its heading turns with the platform;
  - a mover moving into the kart sets `started_inside`, and the shove lands in `knock`;
  - **bump ordering:** after a local contact and after a received bump event, the next `drive()` reads the reduced `speed` and the `bumped` bit is in the end-of-tick snapshot;
  - kart pair, both local:
    - weight-share separation via `pending_push`;
    - no position write during contact;
    - `bot_push_mult` reduces a bot's push on a human;
    - karts 2 m apart vertically never touch;
  - kart vs remote: the local kart takes the full separation and only its knock share, and one `KartEvent` is produced; a pair of two remote karts is skipped;
  - **max-merge dedup:** the same contact reported locally (magnitude 3) and by event (magnitude 5) adds knock of total magnitude 5, not 8 and not 3;
  - the broadphase finds the same pairs as brute force over a 12-kart race (zero misses);
  - **determinism:** two runs with the same inputs give bit-identical `KartSnapshot` streams on one machine. This covers offline runs and host-bot runs, and runs with **recorded remote events** replayed at their recorded ticks.
- **Parity rule against the frozen kart** (`production/qa/evidence/core-rebuild-story-001/golden/`). This is not bit-identical; it uses stated tolerances.
  - **Setup:**
    - A mesh baked through ADR-0005's generator path from the same track (Castle Circuit, Dungeon Depths).
    - A trace-following pilot steers along each golden trace's `x, z, height` path.
    - It replays the golden `drifting` / `drift_dir` and throttle timing **by distance travelled along the golden trace's own path**: neither by time nor by `CourseProgress.s`.
  - **Noise floor first:**
    - The same pilot is first run on the **frozen kart** (`src/legacy/`, through the regression tools that ADR-0001 allows) against its own golden traces.
    - Every tolerance below must sit **above that measured self-error**.
    - If a tolerance does not, the harness is fixed before any rebuild run counts.
  - **Gate, solo traces** (cart and bike on both tracks, 4 runs):
    - lap time within **±2%** of the golden time (for example Castle Circuit cart 42.27 s gives 41.42-43.11 s);
    - **per-checkpoint sector splits** within **±3%**;
    - top speed within **±1%**;
    - drift boosts within **±1 per tier per lap**;
    - takeoff count, landing count and lap count **exact**;
    - no wall-stuck interval (speed < 2 m/s for more than 1 s after the start).
  - **Advisory, bot traces** (`bots_*.csv`): the race finish spread is reported. Bots are rebuilt, so this does not gate.
  - **Owner A1 sign-off on feel:** the owner drives the cart and the bike on the baked Castle Circuit and signs off. **Feel decision:** the owner may move any tolerance above at that sign-off.
- **Benchmark (story 022):**
  - 12 karts, in a running tree, on the owner's PC.
  - Kart physics and driving ≤ 0.3 ms p95; contact ≤ 0.2 ms p95.
  - The target is a release export. No export templates exist for 4.8-beta3 yet, so until they do, the debug editor build is accepted as an upper bound (`architecture.md` Performance Budgets).
- **Grep:**
  - no `src/legacy`, `src/gameplay` or `src/networking` reference under `src/core/kart/`;
  - no `Vector3.DOWN`, `randf`, `randi` or `delta` in `src/core/kart/`;
  - no `Dictionary(` or `Geometry3D.get_closest_points_between_segments` in the per-tick paths. `get_closest_point_to_segment` returns a `Vector3` and is allowed.

## Related
- ADR-0001 Simulation conventions (depends on: §3 orientation, §5 tick, §6 determinism, §8 teleport and interpolation, §9 data forks)
- ADR-0002 v5 Collision backend (depends on: `CollisionQuery`, `WallHit.started_inside`, `collider_velocity`, `mover_pose`). This ADR decides the overlap resolution, the sweep shape and radius, and the slide cap that ADR-0002 delegated.
- ADR-0004 Course data (depends on: `CourseProgress.s` / `distance` for the broadphase; respawn poses)
- ADR-0005 Blender track pipeline (depends on: the generator bake path for parity meshes. Requirement on it: `track_check` enforces the step-up contract, §5)
- ADR-0006 Network snapshot for 3D (enabled: encodes `KartSnapshot` including `distance`; bump `KartEvent` on the reliable channel)
- ADR-0009 Anti-gravity and wall-riding (enabled: per-body gravity and up target)
- `docs/architecture/architecture.md` (API Boundaries: Kart Physics, Driving & Drift; Data Flow 1-3; Performance Budgets amended 2026-11-22)
- `design/gdd/systems-index.md` rows 6, 9, 12, 13, 14, 26, 27
- `production/qa/evidence/core-rebuild-story-001/perf-per-system.md`, `golden/`
- Frozen reference (feel and contact model only, never imported): `src/legacy/vehicle/kart_sim.gd`, `src/legacy/main.gd`, `assets/data/vehicles/armored_cart.tres`, `war_bike.tres`, `assets/data/net/net_config.tres`
