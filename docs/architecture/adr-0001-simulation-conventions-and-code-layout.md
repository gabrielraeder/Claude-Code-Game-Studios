# ADR-0001: Simulation Conventions and Code Layout

## Status
Accepted (owner, 2026-11-21)

## Date
2026-11-21

## Last Verified
2026-11-21

## Decision Makers
Claude (autonomous mode, owner-authorized) drafted it. godot-specialist validated it (v1, findings applied) and technical-director reviewed it (TD-ADR v1: CONCERNS, applied in v2; TD-ADR v2: CONCERNS, four one-line fixes applied in v3; the TD said no further gate pass is needed). Acceptance needs the owner's confirmation.

## Summary
The rebuilt core (Mario Kart architecture, `docs/architecture/architecture.md`) needs one set of conventions that every system agrees on before any code is written. This ADR fixes:
- **Axes and units:** Godot Y-up, -Z forward, metres.
- **Blender:** a fixed rule for the forward axis of karts and pose empties.
- **Orientation:** a re-orthonormalised `Basis` whose up follows the smoothed ground normal, with a per-body gravity vector.
- **Banking:** physical, not visual.
- **Clock:** the synced race time is authoritative, and the 60 Hz tick follows it with a defined catch-up policy.
- **Determinism:** a fixed step order and one seeded random stream per consumer.
- **Interpolation:** our own, with a teleport flag.
- **Mirror mode:** a proper reflection at track load.
- **Precision:** stated bounds.
- **Code layout:** the frozen 2.5D game moves to `src/legacy/`, shared data classes go to `src/data/`, and ported classes get new names.

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.8-beta3 |
| **Domain** | Core |
| **Layer** | Foundation |
| **Knowledge Risk** | HIGH (4.8 is post-cutoff and pre-release) |
| **References Consulted** | `docs/engine-reference/godot/VERSION.md`, `breaking-changes.md` (4.7 → 4.8), `modules/physics.md`, `current-best-practices.md`. godot-specialist runs on the installed 4.8-beta3 (scratch project, 2026-11-21) |
| **Post-Cutoff APIs Used** | None used. `physics/common/physics_interpolation` (3D in 4.4, moved to SceneTree in 4.5) is pinned explicitly to `false` and not otherwise used |
| **Verified on 4.8-beta3** (the fraction API is verified but not used, §8) | All three keys exist with defaults 60 / 8 / false: `physics/common/physics_ticks_per_second`, `max_physics_steps_per_frame`, `physics_interpolation`. `Engine.get_physics_interpolation_fraction()` varies between ticks in `_process` with interpolation off (0.0, 0.473, 0.531, 0.864). `Basis(Quaternion)` round-trips and `Quaternion.slerp` behaves as expected |
| **Verification Required** | (1) In the ADR-0005 spike, check that a Blender-authored asymmetric object lands as this ADR's rule says: an object facing Blender +Y lands as Godot -Z; a kart authored facing -Y lands as +Z and is turned by the kart scene. (2) Check that `physics/common/physics_jitter_fix` exists in 4.8 and can be pinned to 0.0. (3) In the freeze story, check that a move of a script together with its `.uid` sidecar keeps every `uid://` reference resolving |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | None (first ADR of the rebuild) |
| **Enables** | ADR-0002 collision backend, ADR-0003 kart physics model, ADR-0004 course data, ADR-0005 Blender track pipeline, ADR-0006 network snapshot, ADR-0007 asset pipeline |
| **Blocks** | Every Phase A rebuild story: freeze-and-oracle's folder move, 022, 023, 024, 025 |
| **Ordering Note** | Must be Accepted before the freeze-and-oracle story moves the frozen code. ADR-0002 and ADR-0004 must each expose the mirror operation that section 7 defines. ADR-0006 must implement the clock rule (section 5) and the wire rules (sections 2 and 8). |

## Context

### Problem Statement
The owner chose to rebuild the core on Mario Kart's architecture (2026-11-21). The 2.5D game stays frozen as the playable build and the reference.

The frozen code uses planar conventions:
- `KartSim.position` is a `Vector2 (x, z)`.
- `yaw` 0 faces -Z.
- Height is a separate float.
- Banking is visual only.

Collision, kart physics, course data, the Blender pipeline and the network snapshot each need 3D conventions, and they must agree with each other. Otherwise every seam converts between them and drifts.

The new code also needs a place to live. That place must avoid the frozen code's 79 global `class_name`s and must fit the project's path-scoped coding rules.

### Constraints
- **Online model:** owner-authoritative. Same-machine reproducibility is required; cross-machine bit-exactness is not (architecture, Data Flow 3).
- **Frozen game:** it must keep compiling and running from HEAD until checkpoint A3. It is the regression oracle and the owner's playable build.
- **Class names:** GDScript `class_name`s are global.
- **Tuning values:** they live in `.tres` (`.claude/rules/tuning-values.md`). The frozen game's `.tres` values are part of the oracle.

### Requirements
- One coordinate convention end to end: Blender → glTF → import → runtime → wire.
- An orientation that works on walls and loops. Anti-gravity is approved for Alpha.
- A tick that tests, traces and bots can reproduce, and that tracks the synced race time.
- Smooth rendering at any display rate from a 60 Hz simulation.
- Mirror mode (approved for Grand Prix) without a second set of track data.

## Decision

### 1. Axes, units, precision
- **World axes:** Godot's convention. **+Y up, -Z forward, +X right.** A body with an identity basis faces -Z, which matches the frozen kart's yaw 0.
- **Units:** metres, seconds, radians, m/s, rad/s. If mass is ever used (ADR-0003 decides), the unit is kg.
- **Precision:**
  - Scalar `float` in GDScript is 64-bit.
  - `Vector3`, `Basis`, `Quaternion` and `Transform3D` are **32-bit** in standard builds.
  - Track geometry must lie within **±2 km of the origin**. The import step checks this.
  - Times and the tick counter are scalars (`float` / `int`).

### 2. Blender conventions
- **Authoring units:** Blender is Z-up, 1 unit = 1 m. Transforms are applied before export, and the glTF exporter uses **+Y Up**.
- **The mapping:** the exporter maps Blender (x, y, z) to glTF/Godot (x, z, -y). **Blender +Y becomes Godot -Z (forward).**
- **Tracks:** track geometry has no front, so it is imported as is. The importer never rescales or rotates a whole track. A file that would need it is rejected with a message.
- **Pose empties:** grid slots, respawns, checkpoint gates, item boxes and route points point their **local +Y axis along the direction of travel**. Use an arrows or single-arrow empty with +Y forward. Each therefore lands as a Godot pose facing -Z.
- **Kart and character models** (ADR-0007):
  - They are authored facing **Blender -Y**, the Blender "front" norm, so they arrive facing Godot **+Z** (glTF front).
  - The kart visual scene turns the model's child node **180° about Y**, once.
  - Simulation code never knows about this rotation.

### 3. Orientation
- **Storage:** a body's orientation is a **`Basis`** in `BodyState`.
- **Orthonormalisation:** the basis is re-orthonormalised after every tick's integration (`orthonormalized()`).
- **Up vector:** the body's up follows the ground normal under it, smoothed at a rate that is a tuning value (`.tres`).
- **Gravity:** a **per-body vector**. It is world down by default and the surface's inverse normal under anti-gravity (ADR-0009). Simulation code never hard-codes `Vector3.DOWN`.
- **In the air:** up eases toward minus the body's gravity vector.
- **Heading:** the basis' -Z projected on the plane of up. If that projection is degenerate (length below an epsilon), the last valid heading is used.
- **Yaw:** a scalar `yaw` is **derived only**, for the minimap, the HUD and the legacy adapter. It is never stored as state.
- **Steering:** it rotates the basis about its own up.

### 4. Banking
- **Physical:** a banked road tilts the kart because its up follows the road's normal.
- **Presentation:** it may add **cosmetic lean** (body roll in drifts and turns) in the kart's visual node only. That lean never feeds back into the simulation.

### 5. Tick and clock
- **Pinned settings** in `project.godot`:
  - `physics/common/physics_ticks_per_second = 60`
  - `physics/common/max_physics_steps_per_frame = 8`
  - `physics/common/physics_interpolation = false`
  - `physics/common/physics_jitter_fix = 0.0` (Verification Required 2)
- **Boot assertion:** the composition root **asserts** `Engine.physics_ticks_per_second == 60` and `Engine.max_physics_steps_per_frame == 8` at boot. The editor may strip default values when it re-saves `project.godot`, so a changed setting must fail loudly.
- **Fixed step:** the simulation runs in the composition root's `_physics_process` and steps every sim object with **`const SIM_DT: float = 1.0 / 60.0`**, never with `delta`.
- **The synced race time is authoritative.** Each PC computes a **target tick** = `floor(synced_race_time / SIM_DT)`. ADR-0006 owns clock sync and the start.
  - On each `_physics_process` call, the sim runs ticks until its local tick count reaches the target tick, at most `catch_up_ticks_max` per call (a `NetConfig` tuning value).
  - **Behind by more than `resync_ticks` after catch-up** (for example after a long hitch): the local tick jumps to the target. The own kart holds its state through the skipped ticks. That is a visible stall, accepted after a hitch, and the snapshot carries the teleport flag (section 8).
  - **Ahead of target** (the local clock runs fast): the sim waits; that call steps zero ticks.
- **Time inside a tick:** everything the simulation evaluates during tick *n* (collision queries, moving-collider poses, hazard states, timers) uses **`t = n × SIM_DT`**, never the continuous synced time. Each tick of a catch-up run therefore sees its own time. The continuous synced time is for **presentation only**: interpolation, the remote buffer, the HUD clock.
- **Pure functions of time:** hazards, track dynamics and the race-state timers are pure functions of time. The simulation evaluates them at the tick time (`n × SIM_DT`, which follows the synced clock) and presentation at the continuous synced time, so neither drifts from the host.

### 6. Determinism
- **Step order:** every tick steps bodies in **`RacerRegistry` slot order**. Pairwise kart contact runs over pairs (i, j) with i < j in slot order.
- **Randomness:** simulation code draws from **one `RandomNumberGenerator` stream per consumer**. Each stream is seeded from `hash([race_seed, racer_slot, system_id])`.
  - The race seed is a 64-bit `int` chosen by the host and sent in the race config.
  - The global `randf`, `randi` and `randomize` are forbidden in simulation code.
- **The aim:** same inputs and same seed give the same run on one machine. Cross-machine bit-exactness is not required.

### 7. Mirror mode
- **When:** mirror is applied **once at track load** to the baked `TrackPackage`. Nothing in the per-tick code knows about it.
- **Positions:** negate X in every position and route point.
- **Directions:** negate the X component of every normal and direction.
- **Rotations:** every rotation or pose basis B becomes **M·B·M** with M = diag(-1, 1, 1). Negating X alone would make a reflection (det = -1).
- **Moving colliders:** their pose curves are mirrored the same way, so their rotation senses flip.
- **Signed lateral data swaps sign or side:** lane indices, left/right half widths, wall sides, and anything authored as left or right.
- **Triangles:** winding is flipped.
- **Unchanged:** checkpoint and route order.
- **Ownership:**
  - The track loader (`src/pipeline/`) calls a `mirrored()` operation that Track Collision (ADR-0002) and Course Data (ADR-0004) each expose.
  - The track's visual root is mirrored with `scale.x = -1`. Text on signs reads reversed, which is accepted for now.
- **Race config:** the mirror flag is part of the synced race config. Wire coordinates are always in the loaded, mirrored frame.
- **Steering input** is never inverted.

### 8. Interpolation and snapshots
- **Engine physics interpolation** is off. The game interpolates itself, because sim objects are `RefCounted`, not physics nodes.
- **Own kart and host bots:** visuals draw between the previous and the current tick's snapshot. The fraction comes **from the synced clock**: `clamp((synced_now − current_tick × SIM_DT) / SIM_DT, 0, 1)`. `Engine.get_physics_interpolation_fraction()` is not used: it counts engine ticks, so it would step back on a "wait" call and skip on a catch-up call. Position is lerped; orientation is slerped through quaternions.
  - This costs **one tick (~16.7 ms) of visual latency**, which is accepted.
- **Remote karts:** snapshots are buffered and drawn at `synced_now − view_delay` (now is the synced race time), with the 30 Hz send rate and an adaptive delay of 0.05-0.35 s from `NetConfig`.
  - Position is lerped and orientation slerped between the two snapshots around that time.
  - **Extrapolation is capped by time** (`NetConfig`). Remote karts never run collision queries.
- **Teleport flag:** every snapshot carries one, for respawns, cannon launches and clock resyncs. On a teleport, visuals **snap** instead of interpolating, and `NetStats` excludes the jump from prediction error (TD-010).
- **Wire quaternions:** a quaternion on the wire uses a canonical sign (w ≥ 0). It is taken from a basis that has just been orthonormalised.

### 9. Code layout
- **The move (freeze story).** The frozen 2.5D code moves from `src/` to **`src/legacy/`**, keeping its class names, in three steps:
  1. **Move commit:** `git mv` of each script **together with its `.gd.uid` sidecar**, and of each imported asset with its `.import`. No content edits.
  2. **Path commit:** a script updates every plain `res://src/...` reference across the repo:
     - `ext_resource path=` (the `uid=` is kept);
     - `preload`/`load` strings;
     - `project.godot` entries, including `application/run/main_scene` → `res://src/legacy/main.tscn`;
     - `.cfg`/`.json`, tools and tests.

     Then the `.godot/` cache is rebuilt (`--import`).
  3. **Oracle re-run:** the golden traces and `tools/regression.sh` must reproduce exactly.
- **Shared data class scripts.** These are frozen `Resource` classes used by both games: `VehicleStats`, `VehicleVisualStats`, `SurfaceSet`, `SurfaceType`, `ItemDef`, `ItemSet`, `RacerDef`, `RacerSet`, `BotPersonality`, `NetConfig`, `AudioEventDef`, `AudioSet`, `UiTheme`, `HitSlowdownProfile` and `PennantStyle` (referenced by `RacerSet`).
  - In the same move they go to **`src/data/`**, not `src/legacy/`, so retiring legacy never deletes them.
  - They may change **only additively**: new fields with defaults. No existing field may change its meaning or units.
  - The shared set must be **closed under the types it references**: the freeze story checks that no `src/data/` script references a class left in `src/legacy/`.
- **Shared data instances.** The new core **never reads a frozen `.tres` instance**. Values the new core uses come from its own instances under **`assets/data/core/`**, forked from the frozen ones when first needed. Retuning for the 3D kart therefore never changes the frozen game or its oracle.
- **New code** lives in rule-aligned folders:

| Folder | Holds | Coding rule that applies |
|---|---|---|
| `src/core/collision/`, `course/`, `kart/`, `race/` | Track Collision, Course Data, Kart Physics, Race Session & Clock | `engine-code.md` |
| `src/gameplay/` (`driving/`, `items/`, `hazards/`, `features/`, `lap/`, `respawn/`, `flow/`) | Feature systems | `gameplay-code.md` |
| `src/game/` | The new composition root and its scene | `gameplay-code.md` |
| `src/networking/` | Network Session & Sync (ported, revised) | `network-code.md` |
| `src/ai/` | CPU Racers (rebuilt) | `ai-code.md` |
| `src/ui/` | HUD, menus (ported) | `ui-code.md` |
| `src/data/` | Shared data class scripts (moved there at the freeze) | `tuning-values.md` + general rules |
| `src/audio/`, `src/input/`, `src/camera/`, `src/visuals/` | Presentation and input (ported) | general rules |
| `src/pipeline/` | Editor-time import step and track loader (including mirror) | general rules |
| `src/debug/` | Debug harness for the new core | general rules |
| `tests/unit/<system>/`, `tests/integration/<system>/` | gdUnit4 tests | `test-standards.md` |

- **Class names.**
  - A new or ported class **never reuses a frozen `class_name`**; the frozen classes keep their names in `src/legacy/`.
  - A ported module gets a name for its role in the new core. Examples:
    - `NetSession` → `NetLink`
    - `KartWire` → `SnapshotCodec`
    - `RemoteKart` → `RemoteKartView`
    - `NetStats` → `NetMetrics`
    - `KartInput` → `DriverInput`
    - `TrackHazard` (frozen data) → `HazardEffect` (the new contract)

    ADRs and `architecture.md` use these names.
  - The only names both games share are the `src/data/` classes listed above.
- **New code must not reference `src/legacy/`.** The exceptions are the regression tools that run the frozen game.
- **Main scene.** `run/main_scene` stays the frozen `res://src/legacy/main.tscn` until A3. Tests and tools launch the new core's scene by path.
- **Blender sources:**
  - `.blend` files live in **`art_src/`** with a `.gdignore`, so Godot never imports them.
  - Godot's built-in `.blend` import is turned off (`filesystem/import/blender/enabled = false`, ADR-0005).
  - Only exported `.glb` files live under `assets/`.
- **Hotfixes to the frozen game** (for example before the friends session):
  - only with the owner's approval;
  - then the oracle is re-run;
  - each fix is tagged `v0.11.x`.
- **Freeze-story checks:**
  - grep the frozen code for `"""..."""` comment blocks and for inner classes that extend their own script's inner classes (both are 4.8 breaks), and fix any found as a hotfix;
  - commit every `.uid` sidecar.

### Architecture Diagram

```
Blender (Z-up, m; empties +Y = travel; karts face -Y) ──glTF +Y up──▶ src/pipeline import ──▶ TrackPackage
                                                                        │ mirror? M·B·M, swap sides, flip winding (once)
synced race time ──▶ target tick = floor(t / SIM_DT) ──▶ catch-up ≤ cap / resync
                                                                        ▼
_physics_process ──▶ step bodies in slot order (SIM_DT) ──▶ Basis re-orthonormalised, gravity per body
                         │ per-consumer RNG streams
_process ── fraction ──▶ visuals: lerp + slerp (own, 1 tick late) │ buffered at now − delay (remote) │ snap on teleport
```

### Key Interfaces

```gdscript
const SIM_DT: float = 1.0 / 60.0        ## fixed tick length; the sim never reads delta
# BodyState (ADR-0003 owns the full type)
var position: Vector3
var basis: Basis                         # -Z = heading, Y = up; re-orthonormalised every tick keeping up exact (ADR-0003 rebuilds it from up and heading; plain Gram-Schmidt keeps X)
var gravity: Vector3                     # per body; never Vector3.DOWN hard-coded in sim code
func heading() -> Vector3                # -basis.z on the up plane; last valid heading if degenerate
func yaw_derived() -> float              # HUD/minimap/legacy only
# Snapshot (ADR-0006 owns the full type)
var teleported: bool                     # visuals snap, NetMetrics skips it
# Mirror (ADR-0002 / ADR-0004 implement)
func mirrored() -> TrackCollisionData    # and CourseData.mirrored()
```

### Implementation Guidelines
- Simulation code **must** step with `SIM_DT`, never `delta`, and **must** follow the target tick derived from the synced race time.
- Simulation code **must never** call the global `randf`, `randi` or `randomize`. It **must** use its own seeded per-consumer stream.
- Bodies **must** be stepped in `RacerRegistry` slot order, and contact pairs taken with i < j.
- Orientation **must** be a `Basis`, re-orthonormalised every tick. A stored scalar yaw in new code is forbidden.
- Simulation code **must never** hard-code `Vector3.DOWN`. Gravity is per body.
- Visual-only lean **must never** be written back into simulation state.
- Mirror **must** be applied only at track load, as M·B·M plus side swaps plus a winding flip.
- Track geometry **must** stay within ±2 km of the origin.
- New code **must not** reuse a frozen `class_name`, **must not** read a frozen `.tres` instance, and **must not** reference `src/legacy/`.
- Shared data classes in `src/data/` **must** change only additively.
- The composition root **must** assert the pinned tick settings at boot.

## Alternatives Considered

### Alternative 1: Up vector + scalar yaw
- **Description**: Store `up: Vector3` and `yaw: float`, like the frozen kart plus a tilt.
- **Pros**: Close to the frozen code; easy to read.
- **Cons**: Ambiguous on walls and loops; every system rebuilds the basis.
- **Rejection Reason**: It breaks with anti-gravity, which is approved.

### Alternative 2: Engine physics interpolation (SceneTree, 4.5+)
- **Description**: Turn on `physics_interpolation` and let nodes interpolate.
- **Pros**: No interpolation code of our own.
- **Cons**: The sim is `RefCounted`, not physics nodes. Remote karts need a buffer anyway.
- **Rejection Reason**: It does not fit Principle 1 or the online model.

### Alternative 3: Keep the frozen code in place, new code beside it
- **Description**: No `src/legacy/` move.
- **Pros**: No move commit.
- **Cons**: Frozen and new files mixed in `src/ai/`, `src/ui/` and `src/items/`; rule-scoped folders would cover frozen code.
- **Rejection Reason**: The move is mechanical and checked against the oracle, and it keeps every folder single-purpose.

### Alternative 4: Local tick count as the clock
- **Description**: Race time = local tick count × `SIM_DT`, with no target.
- **Rejection Reason**: It drifts from the host after hitches, which breaks Principle 2 (shared world state follows the synced time).

### Alternative 5: Karts authored facing Blender +Y
- **Description**: No 180° turn in the kart scene.
- **Rejection Reason**: It goes against Blender's front-view norm that artists and the existing `tools/blender/` scripts use. One fixed turn in one scene is cheaper than an authoring rule everyone must remember.

## Consequences

### Positive
- Every Phase A ADR and GDD starts from one convention, so no seam converts axes.
- Anti-gravity and loops are possible without changing the state model.
- Reproducible ticks, ordered stepping and per-consumer random streams make traces, tests and host bots comparable. Adding a random call in one system does not shift the others.
- Clocks cannot drift, because time-driven systems read the synced time.
- Clean folders, so the coding rules apply to the code they were written for.

### Negative
- A one-time move of the frozen code (two commits plus a cache rebuild).
- Interpolation code of our own (lerp + slerp + teleport snap) and one tick of visual latency.
- Forked `.tres` instances for the new core: two places hold similar values until A3.
- Mirrored text reads reversed until signs get mirror-safe variants.

## Risks
- **The `src/legacy/` move breaks a reference.** Mitigation: sidecars move with their files, then the scripted path commit, then the cache rebuild. Golden traces and `tools/regression.sh` must reproduce exactly.
- **glTF axis surprise** (an asset arrives rotated). Mitigation: the ADR-0005 spike checks an asymmetric test object and a pose empty.
- **The editor strips pinned default settings.** Mitigation: the boot assertion.
- **A long hitch causes a resync stall for the own kart.** Accepted: it is rare, it is visible as a pause, and it is flagged for visuals and metrics.

## GDD Requirements Addressed

| GDD System | Requirement | How This ADR Addresses It |
|------------|-------------|--------------------------|
| game-concept.md (no system GDDs yet) | Online with friends first (Pillar 1): consistent online play for 12 | Synced-time authority, fixed tick, ordered stepping, seeded streams, one orientation format on the wire |
| systems-index.md: Anti-Gravity & Wall-Riding | Variable up vector from day one | `Basis` orientation; gravity per body |
| systems-index.md: Grand Prix & Speed Classes | Mirror mode | Section 7 |
| systems-index.md: Blender Track / Asset Pipeline | One coordinate convention from Blender | Section 2 |
| systems-index.md: Time Trials & Ghosts | Ghosts as snapshot streams | Teleport flag and canonical wire quaternion (section 8) |

## Performance Implications
- **CPU**: Negligible: basis maths and orthonormalisation per body per tick, slerp per visual per frame.
- **Memory**: Negligible.
- **Load Time**: Mirror adds one pass over the track data at load.
- **Network**: Orientation on the wire as a compressed canonical quaternion (ADR-0006).

## Migration Plan
The freeze-and-oracle story runs these steps in order:
1. Capture the golden traces.
2. Tag `v0.11-2.5d`.
3. Move commit (scripts with `.uid`, assets with `.import`).
4. Path commit (all `res://src/` references, `main_scene`).
5. `--import`.
6. Re-run the oracle; it must match.
7. Pin the project settings.
8. Run the 4.8 break greps.

New code starts in the new folders from story 022 on.

## Validation Criteria
- After the move, `tools/regression.sh` and the golden traces reproduce exactly, and no `uid` warning appears on load.
- In the ADR-0005 spike, an object facing Blender +Y and a pose empty with +Y along travel both arrive facing Godot -Z, +Y up, at 1:1 scale. A kart model facing Blender -Y faces -Z after the kart scene's turn.
- A headless run of the new core twice with the same inputs and seed produces identical traces.
- With an artificial 0.5 s hitch, the race clock and hazards stay on the synced time and the own kart resyncs with the teleport flag.

## Related
- `docs/architecture/architecture.md` (Rebuild Strategy, Data Flow, API Boundaries, Required ADRs item 1). Its ported class names follow section 9.
- Enables ADR-0002 … ADR-0007.
