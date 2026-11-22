# Dogworks Racing: Kennel Kingdom — Master Architecture

## Document Status
- Version: 2
- Last Updated: 2026-11-21
- Engine: Godot 4.8-beta3 (GDScript, Forward+). **3D physics backend not pinned** in `project.godot` (no `physics/3d/physics_engine` key; the shipped game uses no 3D physics). Pinning it is part of ADR-0002.
- GDDs Covered: `design/gdd/game-concept.md` only. **No per-system GDDs exist yet** (`design/gdd/systems-index.md` lists 41 systems, 0 designed). This document is the blueprint the system GDDs are written against; it is revised when the Phase A GDDs are approved.
- ADRs Referenced: none exist yet (see Required ADRs).
- **Owner decision 2026-11-21: rebuild the core in this repository** (not a gradual migration, not a separate project). The 2.5D game is frozen at a git tag as the playable build and the reference.
- TD-ARCHITECTURE: 2026-11-21 — REVISED after CONCERNS (v1 → v2: KartBody/snapshot split, ADR-0001 conventions, coexistence decided, moving-collider ownership, collision options, pipeline contract, performance budgets, test harness, ADR order)
- LP-FEASIBILITY: 2026-11-21 — REVISED after CONCERNS (v1 → v2: where the old kart's mixed concerns go, regression oracle, query cursor and bounded allocation, CourseData for real consumers, Phase A sequencing)

> **Basis.** Stories 001-011 built the game (~19,300 lines of GDScript) on a 2.5D kinematic model: a planar `KartSim` (Vector2 + height layer) on a spline `TrackModel`. Measured on 2026-11-21, about 11-12k of those lines depend on that model (kart, track model and generators, bot line logic, the track side of items, laps, much of `main.gd`). The owner approved Mario Kart's architecture (kart physics against collision meshes with per-triangle surface attributes, like MK's KCL; separate course data, like MK's KMP; Blender pipelines) and then chose to **rebuild the core** rather than migrate it: a migration would spend most of its effort on adapters and version coexistence that exist only during the transition. **Today** in this document means the frozen 2.5D code; **target** means the rebuilt core, confirmed by the ADRs below.

## Rebuild Strategy

- **Freeze.** Tag the current main as `v0.11-2.5d` (after the regression capture below). That build stays playable (wire VERSION 9) for the owner's friends session and is the feel and lap-time reference.
- **Capture the oracle first.** Golden traces of the shipped kart (per-tick position, height, speed, drift state; lap times) for scripted autopilot and bot runs on both tracks, the 12-kart ms-per-tick baseline, and the item/net/bump test outputs. These are what the new core is compared with.
- **Rebuild from scratch:** collision, course data, kart body and driving, track import (Blender), race clock and racer registry, lap and position, fall and respawn, track features and hazards on colliders, bots on routes, the track side of items, the composition root. Written test-first (gdUnit4), in the new layout ADR-0001 fixes.
- **Port after review, file by file:** network session and handshake (`src/net/`, wire format revised), input and bindings, audio director and events, menus, HUD and UI theme, item rules and data, vehicle/racer/surface/bot-personality data (`.tres`), the debug harness patterns and test scripts. A ported file is read, fitted to the new contracts and covered by a test; it is never copied blind.
- **Retire, don't delete:** the old 2.5D modules stay in git history and the tag. They are moved out of the way (deleting them is an owner-approved step) only when the new composition root boots.

## Engine Knowledge Gap Summary

Godot 4.8-beta3 is pre-release; the LLM's knowledge stops near 4.3.

| Domain | Risk | What matters here |
|---|---|---|
| Physics | HIGH | Jolt is the default for new projects since 4.6 (this project has not pinned a backend); Jolt 5.6.0 in 4.8. `intersect_ray_into` / `cast_motion_into` (non-allocating, 4.8) exist but **their signatures are not sourceable**. Whether a ray hit returns a triangle index (`face_index`) under Jolt is **unverified** (lead, from memory: historically behind a project setting that is off by default). Querying a direct space state outside the physics frame or in a headless `SceneTree` loop is unverified. |
| Networking | HIGH | MultiplayerAPI / ENet changes in 4.8 are "not sourceable", not "none". The game uses `SceneMultiplayer` + ENet with an auth handshake and its own packed snapshots, not Spawner/Synchronizer. |
| Rendering | HIGH | Blender → glTF import, materials and shaders for tracks and rigged dogs: check `modules/rendering.md` before the pipeline ADRs. |
| Animation | HIGH | Rigged dogs: skeleton and animation import; 4.8 turns bone-follower FTI off by default and renames `BoneSpreader3D`. |
| GDScript | HIGH | 4.8: a script can no longer inherit its own inner classes; strings no longer serve as comments. |
| Blender 5.3 Python API (`bpy`) | HIGH | Post-cutoff too. Exporter calls are checked against Blender's docs or a run of the installed Blender, never assumed. |
| Input, Audio, UI | MEDIUM | The shipped code works on 4.8-beta3; 4.8 changes joypad focus and menu input defaults. |

Rule for every ADR: a claim about a post-cutoff API is checked against `docs/engine-reference/godot/` or a run on the installed editor (`4.8.beta3.official.c51ff06e8`), and is marked `NEEDS VERIFICATION` when neither is possible.

## Architecture Principles

1. **Simulation is separate from the scene tree.** Kart state and rules live in `RefCounted` objects stepped on a fixed tick; nodes only draw and listen. Every Core and Feature module can be stepped by a headless test.
2. **Owner-authoritative, clock-driven.** Each PC simulates its own kart; the host owns bots and shared events; shared world state (hazards, track dynamics) is a pure function of the synced race time, never of physics bodies pushed by karts. (Pillar 1.)
3. **Content is data; the engine owns its formats.** Tuning values live in `.tres` (`.claude/rules/tuning-values.md`). Track Collision and Course Data own their runtime formats; Blender writes glTF only and a Godot import step builds the runtime resources.
4. **One seam per question.** "What is under or around the kart": Track Collision. "Where is the line, the next checkpoint, the respawn": Course Data. "How does the kart move": Kart Physics (body) and Driving & Drift (control law). No system reaches past a seam.
5. **Test first, compare with the reference.** Logic is covered by gdUnit4 tests; physics is compared with the frozen kart's golden traces; anything a player sees is launched, observed and kept as a screenshot.

## System Layer Map

Layers follow `design/gdd/systems-index.md`, which is the authority for each system's layer. Platform (Godot, Jolt, ENet, Windows, Blender) is not code this project writes.

```
┌────────────────────────────────────────────────────────────────────┐
│ PRESENTATION  Race HUD & Minimap · Menus & Lobby UI · Race Audio ·  │
│               Kart & Dog Presentation · Track Art & Scenery ·       │
│               Spectate & Broadcast · Chase Camera                   │
├────────────────────────────────────────────────────────────────────┤
│ FEATURE       Driving & Drift · Roster · Lap & Position · Fall &    │
│               Respawn · Track Features · Track Hazards · Items ·    │
│               CPU Racers · Race Flow & Lobby · (Alpha and later     │
│               modes)                                                │
├────────────────────────────────────────────────────────────────────┤
│ CORE          Kart Physics · Course Data · Race Session & Clock ·   │
│               Blender Track Pipeline (tool-layer producer)          │
├────────────────────────────────────────────────────────────────────┤
│ FOUNDATION    Track Collision & Surface Attributes · Network Session │
│               & Sync · Input & Bindings · Settings & Local Save ·    │
│               Room Codes & Relay · Blender Asset Pipeline (tool)     │
├────────────────────────────────────────────────────────────────────┤
│ PLATFORM      Godot 4.8 · Jolt 5.6.0 · ENet · Windows · Blender 5.3  │
└────────────────────────────────────────────────────────────────────┘
```

## Module Ownership

Folder layout and class names of the rebuilt core are fixed by ADR-0001 (ported modules get new role names, e.g. NetLink, SnapshotCodec, RemoteKartView, NetMetrics, DriverInput; shared data classes move to `src/data/`); "today" names the frozen file a module learns from or ports.

### Foundation

| Module | Owns | Exposes | Consumes | Engine APIs |
|---|---|---|---|---|
| **Track Collision & Surface Attributes** (rebuilt; learns from `track_model.gd`, `track_surface.gd`) | The static collision geometry, per-triangle floor attributes and per-wall attributes (drag, opening), moving colliders' shapes **and pose curves** (pure functions of race time, addressed by id), surface data (`SurfaceSet` `.tres`, ported) | `CollisionQuery` | race time (a parameter) | ADR-0002 choice: engine ray/shape casts on `ConcavePolygonShape3D`, per-surface shapes, or an own triangle grid. 4.8 `_into` variants NEEDS VERIFICATION |
| **Network Session & Sync** (ported from `src/net/`) | Connection lifecycle, version handshake, the snapshot wire format (new VERSION 10), remote-kart interpolation, `NetMetrics` (with teleport exclusion, TD-010) | `NetLink` signals, `SnapshotCodec.pack/unpack`, `RemoteKartView` | the `KartSnapshot` contract | `SceneMultiplayer`, `ENetMultiplayerPeer`, `@rpc` |
| **Input & Bindings** (ported) | Actions, rebinding, per-PC saved bindings | `DriverInput` | — | `Input`, `InputMap` |
| **Settings & Local Save** (ported) | Per-PC config files | typed reads | — | `ConfigFile` |
| **Room Codes & Relay** (new, story 021) | Code ↔ host address, relay fallback | `Rendezvous.resolve(code)` | Network Session | ADR-0008 |

### Core

| Module | Owns | Exposes | Consumes |
|---|---|---|---|
| **Kart Physics** (rebuilt) | `BodyState` (position, velocity, orientation as a `Basis`, grounded, air state); integration on a fixed tick; ground contact, walls, ramps, take-off and landing; **kart-vs-kart contact** (pairwise against another kart's snapshot, local or remote); `KartIntent` (the type); the snapshot and event contract | `KartBody`, `KartSnapshot`, `KartEvent` | `CollisionQuery`, a `KartIntent` per tick |
| **Course Data** (rebuilt) | Checkpoints with groups (branches and shortcuts share a group), routes (main, branches, enemy lines, item lines) with baked tables (half width, surface runs, slick spans, lanes, hazards ahead), item boxes, respawn poses, start grid, per-kart `Progress` | `CourseData` queries | built by the import step; validated against Track Collision by the mesh `track_check` (authoring time, not runtime) |
| **Race Session & Synced Clock** (rebuilt; today `race_time` in `main.gd` + `NetSession.race_clock`) | The shared race clock, race states, the racer registry (humans and bots alike) | `RaceClock`, `RacerRegistry` | Network Session |
| **Blender Track Pipeline** (new) | Authoring conventions, the exporter (glTF + custom properties + empties), the Godot editor-time import step that builds the baked resources | exporter script; baked `TrackPackage` (collision + `CourseData` + theme) | formats of Track Collision and Course Data |

### Feature

| Module | Owns | Consumes |
|---|---|---|
| **Driving & Drift** (rebuilt, tuning ported from `VehicleStats`) | `DriveState` (speed, drift tier and timers, boost, spin, stall, slowdown, slick tail, hop) and the control law: acceleration, steering, drift, mini-turbo, pad boost, surface grip and speed caps (the effect; the data is Track Collision's) | `KartSnapshot`, surface id, `VehicleStats`, `SurfaceSet` |
| **Vehicles & Racers Roster** (data ported) | Vehicle and racer data, placeholder models | `VehicleStats` schema |
| **Lap & Position** (rebuilt) | Laps, ranking | `CourseData` progress, `RaceClock` |
| **Fall & Respawn** (rebuilt) | Fall detection, sink (including a hazard's sink), respawn rule | `CourseData` respawn poses, Kart Physics |
| **Track Features** (rebuilt) | Boost pads (through Driving), ramps, jumps, cannons (through Physics) | Kart Physics, Track Collision, Course Data |
| **Track Hazards** (rebuilt, timings ported) | Each hazard's gameplay effect (spin, stop, sink, push-off) keyed by collider id; warnings; hits decided on the victim's PC | `RaceClock`, Track Collision (pose curves by id), Fall & Respawn |
| **Items** (rules and data ported, track side rebuilt) | The item contract, boxes, odds, projectiles, victim-confirmed hits | Kart Physics, `CollisionQuery`, Course Data (item routes, boxes), `RacerRegistry`, Network Session |
| **CPU Racers** (rebuilt; personalities ported as data) | Route following, lane and overtaking choices, item and hazard decisions | Course Data routes and tables (never `CollisionQuery`), Driving & Drift, Items, Track Hazards |
| **Race Flow & Lobby** (ported and extended) | Lobby, picks, track choice, countdown, results, one-press rematch with running tally, post-finish spectating | Race Session, Lap & Position, Roster |

### Presentation

HUD, menus, audio, camera, kart visuals and track art read state and signals and own no gameplay data. Spectate & Broadcast reads Race Flow, Lap & Position and the item event stream. Visual-only tilt (banking presentation) is allowed here only if ADR-0001 says banking is presentation.

### Dependency picture

```
 Presentation ──▶ Feature ──▶ Core ──▶ Foundation
 Kart Physics ──▶ CollisionQuery (Track Collision)
 Network ◀── KartSnapshot / KartEvent ──▶ Kart Physics
 Course Data ··· validated against ··· Track Collision (authoring time only)
 Blender ──glTF──▶ import step ──▶ Track Collision + Course Data resources (pipelines never own a runtime format)
 Track Hazards ──effect by collider id──▶ (Track Collision owns the pose curve)
```

## Data Flow

**1. Tick (60 Hz `_physics_process`, pinned by ADR-0001).**

```
DriverInput ──▶ Driving & Drift.drive(DriveState, input, snapshot, stats, surface) ──▶ KartIntent
KartIntent + CollisionQuery ──▶ KartBody.step ──▶ KartSnapshot
KartSnapshot ──▶ Course Data progress ──▶ Lap & Position
            ──▶ hazard hit test (victim decides) ──▶ same-tick effect (spin/stop/sink)
            ──▶ pad test ──▶ Driving (boost)
            ──▶ Network: pack and send (30 Hz)
Render frame: own kart interpolates previous→current tick; remote karts are buffered at now − view delay.
```
All on the main thread. A hit or sink detected this tick takes effect this tick (as in the frozen kart, which also skips the pad check on that tick); only events from other PCs (bumps, item hits) apply at the start of the owner's next tick.

**2. Events.** Signals for one-to-many notifications; a connection that captures a RefCounted emitter uses `WeakRef` (`.claude/rules/godot-refcount.md`). Network events are RPCs on the `SceneMultiplayer` session: reliable for hits and item use; snapshots `unreliable_ordered` on channel 1 at `NetConfig.send_hz` (30 Hz), drawn with an adaptive view delay of 0.05-0.35 s.

**3. Online.** Each PC simulates its own kart and sends snapshots; remote karts are interpolated, never simulated. The host also simulates all bots and decides shared events. Hazards, track dynamics and the race clock are computed locally from the synced race time.
**Determinism requirement:** fixed tick and same-machine reproducibility (same inputs → same run) for tests, trace comparison and host bots. **Not** bit-exact across machines. Ghosts record snapshot streams, never inputs.

**4. Save/load.** Per-PC settings and bindings only; time-trial ghosts (Alpha) add one file type.

**5. Initialisation.** A composition root (no autoloads, as today) builds in order: Input → Settings → Network Session (host/join, handshake, version check) → track package load (baked resources) → Race Session (clock sync, grid from Course Data) → racers and vehicles → countdown. A track that fails validation fails loudly.

**6. Content (authoring).** Blender scene → exporter → `.glb` with custom properties on objects and empties (surface tags, wall flags, checkpoints, routes, respawns, item boxes, grid) → Godot editor-time import (`EditorScenePostImport`, also run headless with `--import`) → baked `TrackPackage` → mesh `track_check` (laps, checkpoints, respawns on collision, routes inside the road, hazards never block the road, 12-kart grid). The rigged-asset pipeline (dogs, karts, props) follows the same shape with its own checks.

## API Boundaries

GDScript pseudo-signatures; the ADRs fix the exact types. All are `RefCounted` or `Resource`, never nodes.

### CollisionQuery (Track Collision)

```gdscript
class_name CollisionQuery extends RefCounted
func cast_ground(cursor: QueryCursor, origin: Vector3, up: Vector3, max_dist: float, t: float, out: GroundHit) -> bool
func sweep_walls(cursor: QueryCursor, from: Vector3, to: Vector3, radius: float, t: float, out: WallHit) -> bool
```
- `GroundHit`: point, normal, **surface id, collider id** (0 = static), floor drag. `WallHit`: point, normal, wall attributes. Results are written into caller-owned objects.
- `QueryCursor` is per kart (a cache of the last cell or triangle).
- Moving colliders are tested analytically in each collider's local frame from its pose curve at `t`; the static geometry goes through the ADR-0002 backend.
- Guarantees: **bounded** allocation per call (zero only if the 4.8 `_into` variants or the own grid allow it); results independent of call order; no dependency on the physics frame if ADR-0002 chooses the own grid (to be verified otherwise).

### Kart Physics

```gdscript
class_name KartSnapshot extends RefCounted   # plain data
var tick: int; var position: Vector3; var velocity: Vector3; var basis: Basis
var grounded: bool; var surface_id: int
var speed: float; var drift_state: int; var boost: float; var spin: float; var sinking: bool
var steer: float; var accel: float          # for audio and visuals
class_name KartIntent extends RefCounted     # Core-owned type, produced by Driving & Drift
var yaw_rate: float; var target_speed: float; var grip: float; var hop: bool
class_name KartBody extends RefCounted
func step(dt: float, intent: KartIntent, q: CollisionQuery, cursor: QueryCursor, t: float) -> void
func resolve_contact(other: KartSnapshot, other_push: float) -> void
func apply_event(e: KartEvent) -> void
func snapshot(out: KartSnapshot) -> void
```
- `step` is deterministic given state; it mutates state.
- Kart Physics never references the network; `SnapshotCodec` alone serialises a snapshot (VERSION 10). The frozen 2.5D build stays on VERSION 9; the two never play together (the handshake refuses), which is correct.

### Driving & Drift

```gdscript
class_name DriveState extends RefCounted
func drive(state: DriveState, input: DriverInput, snap: KartSnapshot, stats: VehicleStats, surface: SurfaceType, dt: float, out: KartIntent) -> void
```

### CourseData

```gdscript
class_name CourseData extends Resource
func checkpoint(index: int) -> Checkpoint
func progress(p: Progress, position: Vector3, moved: float) -> void
func route(kind: StringName, lane: int) -> Route
func route_sample(r: Route, s: float, out: RouteSample) -> void   # position, tangent, half width, surface run ahead, hazards ahead
func item_box_pose(i: int) -> Transform3D
func respawn_pose(p: Progress) -> Transform3D
func grid_pose(slot: int) -> Transform3D
```
Bots read routes and baked tables only.

### Hazards and items

`HazardEffect.effect_at(collider_id, t) -> HazardOutcome` (pure); a hit is decided on the victim's PC. Item use is an event resolved by the owner and confirmed by the victim; projectiles use `CollisionQuery`; homing targets come from `RacerRegistry`.

### Tool layer

Blender writes **only glTF** (meshes, custom properties, empties). The Godot import step owns the conversion and refuses a file that fails the schema check, saying why.

## ADR Audit

ADR-0001 (simulation conventions and code layout) is Accepted (owner, 2026-11-21); ADR-0002…0010 remain to be written. At `standard` rigor, Foundation and Core ADRs are required before the stories that depend on them. Stories 001-011 (built at `minimal`) have none; their behaviour is the reference the rebuilt systems' GDDs document.

Technical Requirements Baseline: **deferred** (no system GDD exists to extract from). Provisional `TR-[system]-NNN` IDs are created as each GDD is approved and registered by `/architecture-review`; until then the ADRs cite the systems-index rows and this document.

## Required ADRs

**Before the rebuild's first code (order matters):**

1. **ADR-0001 Simulation conventions and code layout:** folder layout of the rebuilt core; axes and units (Godot Y-up, -Z forward, metres; Blender Z-up exported to glTF +Y-up, scale applied); orientation as a `Basis` with up following a smoothed ground normal; banking physical or presentation-only; tick model (pin `physics_ticks_per_second=60` and `max_physics_steps_per_frame`), 30 Hz send rate, view delay; interpolation (own kart lerp+slerp between ticks, remote buffered with slerp, engine physics interpolation off); mirror per ADR-0001 §7 (M·B·M, side swaps, winding flip).
2. **ADR-0002 Collision backend and surface attributes:** (a) engine casts on one `ConcavePolygonShape3D` with `face_index` (verify under Jolt); (b) one shape per surface id (shape index gives the surface); (c) an own XZ grid of triangles per cell in a `RefCounted` (no SceneTree, per-triangle ids, decks by y); (d) a GDExtension BVH if speed demands it. Pin the 3D physics backend and check it at boot. Decided by a measured spike on a mesh baked from today's generator output.
3. **ADR-0003 Kart physics model:** custom kinematic `KartBody` + `DriveState` (recommended) vs `CharacterBody3D` vs `RigidBody3D` on Jolt; parity rule against the golden traces (tolerances stated).
4. **ADR-0004 Course data format:** checkpoint groups, routes and baked tables, item boxes, respawn, grid.
5. **ADR-0005 Blender track pipeline:** conventions, custom properties, editor-time import to baked resources (recommended) vs runtime `GLTFDocument`, validation hook; its round-trip prototype runs with ADR-0002's spike.
6. **ADR-0006 Network snapshot for 3D:** `KartSnapshot` layout, VERSION 10, inbound event set, remote interpolation on 3D. Needed before checkpoint A2 (the online race).

**Before the relevant system:** ADR-0007 Blender asset pipeline (rigged dogs, karts, props; before 027); ADR-0008 room codes and relay (before 021); ADR-0009 anti-gravity and wall-riding; ADR-0010 time-trial ghost format.

**Deferred to implementation:** per-feature visual techniques, audio bus layout.

## Performance Budgets

**Amended 2026-11-22** (logged decision: amend before ADR-0003). Basis: the per-system profile of the frozen 2.5D tick (`production/qa/evidence/core-rebuild-story-001/perf-per-system.md`, tool `tools/profile_tick.gd`). On the owner's PC, headless, debug editor build, 12 karts:
- the whole tick is 3.5 ms median and 6.4 ms p95;
- track queries (`Path.nearest` full scans) are about 43% of it;
- kart contacts are 47%, mostly wall-clamp re-queries;
- bots are 0.95 ms median;
- kart dynamics are about 0.1 ms;
- per frame, the chase camera costs 2.7 ms of scans.

The rebuild removes the dominant cost: Jolt collision measured 0.06 ms per tick for 12 karts (ADR-0002).

**How budgets are measured.** p95 per tick:
- on the **owner's PC** (Ryzen 7 7800X3D), which is the reference machine;
- 12 karts (1 human or autopilot + 11 bots);
- Castle Circuit and the heaviest track of each cup;
- a **release export** once export templates are installed (none for 4.8-beta3 today; until then the debug build is an upper bound);
- with `tools/profile_tick.gd`-style stage timing.

**Minimum CPU** (i5-8400 / Ryzen 5 2600 class) is estimated at about 2× slower (unverified estimate). The owner-PC budgets below are set so the minimum CPU stays inside a 60 fps frame with rendering.

| Simulation stage (per tick, host, 12 karts) | Budget p95 |
|---|---|
| Track collision queries (ADR-0002) | 0.3 ms |
| Kart physics and driving (12 bodies) | 0.3 ms |
| Kart-vs-kart contact (broadphase on route distance) | 0.2 ms |
| Hazards and movers (effects; collision part is in the first row) | 0.1 ms |
| Bots (11) | 0.8 ms |
| Items | 0.15 ms |
| Race logic, lap/progress, net send | 0.15 ms |
| **Whole simulation tick** | **≤ 2.0 ms** (≈ 4 ms on the minimum CPU, estimate) |

| Presentation (per rendered frame) | Budget p95 |
|---|---|
| Chase camera (no per-frame track scans; reads Course Data or collision once) | 0.3 ms |
| Kart visuals (12) | 0.5 ms |
| HUD, minimap, audio | 0.5 ms |

Plus the frame rules from `.claude/docs/technical-preferences.md`: 60 fps, 16.6 ms, ≤ 2000 draw calls, 2 GB.

- **Rule:** no simulation or camera query may scan a whole route or the whole track per call. Each call's cost must stay the same on every track section (the frozen game's p95 doubled in its branch section because of full scans).
- **Bandwidth (estimate, verify with `NetMetrics`):** ~84 B × 30 Hz ≈ 2.5 KB/s per kart; ~30 KB/s down per client; ~330 KB/s host upload for 12 before overhead.
- **Tools:** the mesh `track_check` samples instead of re-running the ~120,000 single-kart ticks of today's infield check.

## Target Hardware

Proposed 2026-11-21 from market research (Sonic Racing CrossWorlds' official Steam specs, Garfield Kart 2's, the October 2026 Steam Hardware Survey, Switch 2 GPU comparisons); to be confirmed by measurement on real hardware before release.

| Tier | Target | GPU | CPU | RAM |
|---|---|---|---|---|
| **Minimum** | 1080p, low-medium, 60 fps, as host of 12 racers | GTX 1650 / RX 580 / Intel Arc A380, 4 GB VRAM | 6 cores, Intel i5-8400 / Ryzen 5 2600 | 8 GB |
| **Recommended** | 1080p high (or 1440p), 60 fps | GTX 1660 Super / RTX 2060 / RX 6600 | Intel i5-10400 / Ryzen 5 3600 | 16 GB |
| **Development reference** | the owner's PC (high-end) | — | — | — |

- The host's CPU matters as much as the GPU: it simulates 12 karts and 11 bots in GDScript every tick (budget ≤ 3 ms/tick above), so the minimum CPU is the one the budget is measured against.
- Renderer stays Forward+. Intel integrated graphics (the owner's laptop) is below the minimum for Forward+ at this look; Godot's docs point to the Compatibility renderer for integrated GPUs. **Owner, 2026-11-21: the laptop is not a target**; no Compatibility-renderer path is planned.

## Test Harness and Regression Oracle

Today there is no `tests/` folder and no gdUnit4; evidence is `tools/track_check.gd` and hand-run shell scripts. The rebuild is test-first:

- `/test-setup`: gdUnit4, `tests/unit/` and `tests/integration/` per system, CI command from `project.yaml`.
- Golden traces and the perf baseline of the frozen build under `production/qa/evidence/`.
- `tools/regression.sh`: one command for `track_check`, the shell tests and the trace comparison, with pass/fail lines.
- A mesh `track_check` and a spline-vs-mesh equivalence check (height, surface, wall offset over ~100k samples of one track baked from the generator).

## Phase A Sequencing (rebuild)

| Step | Work | Checkpoint |
|---|---|---|
| 0 | Friends play session on the 2.5D build (owner, any time before step 4 closes) | — |
| 1 | **Story: freeze and oracle.** Golden traces, perf baseline, `tools/regression.sh`, `/test-setup`; tag `v0.11-2.5d` | — |
| 2 | **Spike:** collision backend + Blender round-trip on a generator-baked mesh (ADR-0002, ADR-0005 prototypes) | ADR-0001..0003 Accepted |
| 3 | **022: Kart Physics + Driving & Drift** rebuilt test-first; one kart on the baked test mesh; traces compared with the frozen kart | **A1** owner signs drift parity |
| 4 | **023: Course Data** + mesh `track_check` | — |
| 5 | **024: Blender track pipeline** end to end (a test track authored in Blender) | — |
| 6 | **025: Castle Circuit rebuilt on the new core**, split into stories: race clock and registry, lap and respawn; features and hazards; items; bots; network (ADR-0006); HUD, camera, audio, visuals and race flow ported | **A2** Castle online with bots |
| 7 | **Dungeon Depths rebuilt**; the composition root switches; old 2.5D modules retired (owner-approved) | **A3** |
| 8 | 021 room codes, then 027 Blender asset pipeline (Vertical Slice) | — |

## Open Questions

| ID | Question | Resolved by |
|---|---|---|
| QQ-01 | Does a Jolt ray hit return `face_index`, behind which setting? | ADR-0002 spike on 4.8-beta3 |
| QQ-02 | Which backend meets ≤ 3 ms/tick for 12 karts? | ADR-0002 spike, measured |
| QQ-03 | Does the rebuilt kart match the frozen kart's feel and lap times within tolerance? | Step 3 traces, then A1 (owner) |
| QQ-04 | Can a space state be queried outside the physics frame / headless? (Moot if the own grid wins.) | ADR-0002 spike |
| QQ-05 | ~~Number of cups/tracks~~ **Resolved 2026-11-21:** full vision 3 cups / 12 tracks; MVP 1 cup / 4 tracks | Owner |
| QQ-06 | ~~A named minimum-spec PC~~ **Proposed 2026-11-21** (market research, see Target Hardware); laptop (Intel iGPU) not a target (owner) | Owner |
| QQ-07 | Re-pin when Godot 4.8 stable ships | `/setup-engine refresh` at stable |
