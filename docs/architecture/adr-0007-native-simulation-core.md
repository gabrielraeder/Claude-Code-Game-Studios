# ADR-0007: Native Simulation Core (C++ via GDExtension)

## Status
Accepted (owner, 2026-11-22)

## Date
2026-11-22

## Last Verified
2026-11-22 (against `prototypes/native-spike/REPORT.md`, Godot 4.8-beta3, godot-cpp `7fd5c4bc`)

v2, 2026-11-22: technical-director review applied; owner decisions on the boundary (per-stage `RaceSim` calls), items (fully native) and numbering (asset pipeline ADR becomes ADR-0011). Not re-measured: no new numbers were taken for v2, and the performance range in §10 is a projection.

v2.1, 2026-11-22: second review round applied. `SIM_DT` binding, bench build, hash marker and list, stage order (progress stays inside `step_bodies()`), `hold`, factory contract, event pair, buffer contract and the editor-panel hash checks are changed; Verification Required 11 (inactive space) is removed. Still not re-measured.

## Decision Makers
Owner (scope: "C++ já", 2026-11-22; "tudo agora", and DLLs built rather than committed, 2026-11-22; boundary, items and numbering, 2026-11-22); main session (draft); godot-specialist and technical-director (review).

## Summary
In GDScript, the per-tick simulation does not fit its budgets. In story 007 the moving-collider maths alone took 868 µs p95 against 300 µs for all collision, and the GDScript wrapper around Jolt cost about as much as Jolt itself. This ADR moves the whole per-tick simulation into one C++ GDExtension, `dogworks_core`:
- collision queries;
- the kart body and drive control law;
- kart contacts;
- course progress, route sampling and ranking;
- respawn and hazard effects;
- items (use, effects, items in flight);
- CPU racers (including their item decisions).

The rule for the split: **C++ owns everything that runs per tick in the simulation; GDScript owns everything else.** GDScript keeps data resources, import-time tools, networking, race flow, input, UI and presentation.

The module contracts of ADR-0002 to ADR-0004 keep their behaviour. Their call surface changes where it must (§3, §12): native classes cannot take Resources or constructor arguments, and the per-tick path runs through `RaceSim` stage calls.

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.8-beta3 (4.8.beta3.official.c51ff06e8) |
| **Domain** | Core |
| **Layer** | Foundation |
| **Knowledge Risk** | HIGH. The engine is a post-cutoff pre-release, and the GDExtension API can change between 4.8 betas and stable. |
| **References Consulted** | `docs/engine-reference/godot/VERSION.md`, `breaking-changes.md`, `current-best-practices.md` (`_into` query methods); `prototypes/native-spike/REPORT.md` and `out/` |
| **Post-Cutoff APIs Used** | The 4.8 `PhysicsDirectSpaceState3D` `*_into` methods and their result classes (bound in godot-cpp from the 4.8-beta3 dump); `--dump-gdextension-interface-json` |
| **Verification Required** | Proved by the toolchain story **before the port starts** (items 1–9). Items 10–11 come later. See the list below. |

**Verification Required:**
1. gdUnit4 drives a `dogworks_core` class (spike: UNVERIFIED). gdUnit4 `mock()`/`spy()` on native classes is UNVERIFIED (to be proved in the toolchain story) and is expected not to work, so tests drive the real class.
2. **Construction and typed calls.** A native class takes **no `.new()` arguments** (a GDExtension class is built by `ClassDB` with none). So:
   - the bound static factory `CollisionQuery.create(packed)` (it returns a `Ref`) and `validate_packed(packed)` are callable from typed GDScript, and the result assigns to a typed local;
   - `.new()` stays callable and gives an empty, unbuilt object whose bound methods all refuse with `ERR_FAIL_COND` (§4);
   - `.new()` with no arguments is the normal construction for the classes that need none (`GroundHit`, `WallHit`, `QueryCursor`);
   - the ptrcall cost per crossing is re-measured from typed code, for scalar, `Vector3` and packed-array arguments.
3. Hot reload of a rebuilt debug DLL in the GUI editor.
4. **Exit safety.** A native object still alive at quit, including one held by a GDScript static var, ends with exit code 0 and no RID errors.
5. **Packed-array reuse (§3).** Over 600 ticks, with the caller refreshing its references every tick (so the previous tick's arrays are still held while it does), the heap does not grow. A second run with a consumer that holds one array for the whole run costs one copy for that array and then stays flat. Measure with `OS.get_static_memory_usage()` or a native allocation counter. `OBJECT_COUNT` cannot see packed arrays, so it is not the measure.
6. **Fresh-clone import order (§7).** On a clone with no `.godot/`, after `tools/build_native.sh`, the extension loads during the **very first** `--import` scan, before `.godot/extension_list.cfg` exists, and `CourseBuilder` (an import-time script) can call the native `CollisionQuery`.
7. **Stale-DLL guard (§7).** The regex search finds exactly one marker match in each DLL, and the marker survives the linker (it is referenced from a bound function). The boot check's FileAccess source-hash recompute costs under 100 ms in the editor (UNVERIFIED budget; the story records the measured value).
8. **Bench DLL (§8).** UNVERIFIED, to be proved in the toolchain story. The bench DLL (release flags, built with `use_hot_reload=yes`) loads when copied over the debug DLL name, through the `windows.debug.*` entry, and a test run refuses it while `bench.lock` exists.
9. **Static call (§4, §7).** UNVERIFIED, to be proved in the toolchain story. `ClassDB.class_call_static` works on a method bound with `bind_static_method`; the boot check needs it for `DogworksCore.sim_hz()`. If it does not, the boot check reads the value another way and this ADR is amended.
10. Later: export with the `template_release` DLL once 4.8 export templates are installed.
11. Later: each re-pin re-dumps the API and rebuilds.

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | ADR-0001 (conventions, determinism, layout; amended here), ADR-0002 (collision contract; implementation language and call surface amended here), ADR-0003 (kart contract and tick order; amended here), ADR-0004 (course contract; amended here), ADR-0005 (track pipeline; import order amended here), ADR-0006 (network snapshot and tick order; the boundary is built around it). All are Accepted. |
| **Enables** | Closing TD-012; the native port of CollisionQuery; the `RaceSim` skeleton; writing the kart, drive, course and later stories natively |
| **Blocks** | The native-toolchain, CollisionQuery-port and `RaceSim`-skeleton stories (new). The implementation of the epic stories listed in the Migration Plan: 009–024, 028–035, 041, 043–048, 050–055. Story 008 is not blocked (see Migration Plan). |
| **Ordering Note** | Toolchain story first, then the CollisionQuery port, which must pass the existing collision suite and parity tests, then the `RaceSim` skeleton story. Only then story 009 (data and kart types) and story 012. |

## Context

### Problem Statement
Story 007 measured the GDScript `CollisionQuery`, debug editor build, 12 karts:

| Layout | Median | p95 |
|---|---|---|
| Realistic Castle | 237 µs | 281 µs |
| 12 karts in reach of 5 spinning solid movers | 262 µs | 868 µs |

The budget for all collision is 300 µs p95.
- **Optimisation is spent.** After three passes, the lead-programmer review estimated that the remaining levers stop near 650 µs.
- **The static floor is GDScript.** The static path costs 170–190 µs, where the raw Jolt calls cost about 95–100 µs.
- **The rest of the tick is not built yet.** Kart physics (0.3 ms), contact (0.2 ms), bots (0.8 ms) and items (0.15 ms) will add the same kind of overhead.
- **The spike numbers** (`prototypes/native-spike/`), same inputs:

  | Path | GDScript p95 | C++ p95 |
  |---|---|---|
  | Mover maths | 574 µs | 27 µs per call, 13 µs batched (22–49x) |
  | Static Jolt path | 84 µs | 58 µs batched |

- **Timing.** The owner chose to pay the toolchain cost now ("C++ já"), before the kart physics exists, so no kart code is written twice ("tudo agora é vantagem para depois").

### Constraints
- Windows x86-64 only (the owner's PC and the friends' PCs; see `architecture.md` Target Hardware). MSVC 14.44 (VS 2022 Build Tools) is installed. No CI exists.
- The engine is a pre-release beta. The GDExtension API is taken from the pinned binary's own dump, not from a godot-cpp release branch.
- The frozen 2.5D game (`src/legacy/`) and its oracle stay untouched.
- Tuning values stay data (`.claude/rules/tuning-values.md`). No gameplay value may be hard-coded in C++.
- **Determinism (ADR-0001 §6):** the same inputs and seed must give the same run on one machine. Cross-machine bit equality is not required: networking is owner-authoritative (ADR-0006).

### Requirements
- **Budgets:** the whole simulation tick ≤ 2.0 ms p95 for 12 karts. Collision ≤ 0.3 ms p95 in every layout story 007 measured, including the worst case.
- **No per-tick allocation** in native code (heap or RID) and no per-tick Resource property reads.
- **A fresh clone builds with one command,** and a stale DLL can never run silently.
- **Tests:** module behaviour stays testable from gdUnit4 (`tests/unit/<system>/`).

## Decision

### 0. The rule for the split
**C++ owns everything that runs per tick in the simulation. GDScript owns everything else.** A GDScript system that profiles as hot moves native through an amendment to this ADR. It never moves silently.

Why this line and not "everything native":
- Godot's scene editor, `@rpc`, `@tool` import plugins and UI are designed around GDScript. Native code there means a second binding layer for no gain.
- The gain from native code is in per-tick loops (the spike: 22–49x on mover maths). Outside them, a call runs a few times per frame or per race, and GDScript is fast enough.

### 1. One native module owns the per-tick simulation
A single GDExtension library, **`dogworks_core`**, implements every system that runs each simulation tick.

| System (ADR) | Native classes (names kept from the ADRs) | Stays GDScript |
|---|---|---|
| Track Collision (ADR-0002) | `CollisionQuery`, `GroundHit`, `WallHit`, `QueryCursor` | `TrackCollisionData`, `MoverDef`, `SurfaceSet`/`SurfaceType`, `WallAttr`/`WallAttrSet` (Resources, packed at setup); `CollisionBootCheck` |
| Kart Physics (ADR-0003) | `KartBody`, `KartContactSolver`, `KartContactShape`, `KartIntent` (internal), `KartSnapshot`, `KartEvent` | `KartPhysicsConfig` and the vehicle Resources |
| Driving & Drift (ADR-0003) | `DriveState` and its control law | `VehicleStats` (core fork), slowdown profiles |
| Course runtime (ADR-0004) | `CourseRuntime` (`progress`, `relocate`, `route_sample`, `lane_offset`, `spans_ahead`, `along_for_s`, `respawn_pose`), `CourseProgress`, `RouteCursor`, ranking | `CourseData` (keeps `mirrored()`, `validate_load()` and tool-only accessors), `CourseRoute`, `CourseGate`, `CourseTuning` (Resources); `CourseBuilder` and `CourseAuthoring` (import time) |
| Fall & Respawn, Track Hazards, Track Features | The per-tick rule and effect code | Hazard and feature data |
| Items | Item use, effects on `DriveState`, items in flight (motion, hit tests, boxes) | `ItemSet` data (packed), the odds roll at pickup, the network hit confirmation, item UI |
| CPU Racers | The per-tick route following, lane and decision code, **including bot item decisions** | `BotPersonality` data |
| Race tick | `RaceSim`: owns all simulation state, runs the stages of §3 in ADR-0003/0006 order and slot order, and asserts the order | `RaceClock`/`ClockSync`, `RacerRegistry` setup, race flow |

**GDScript also keeps:**
- networking (`NetLink`, `SnapshotCodec`, `NetEventCodec`, `RemoteKartView`, `RemoteKartSet`, `NetMetrics`);
- input (`DriverInput`), UI, camera, visuals, audio;
- the Blender import pipeline and track loader;
- debug, tools and the composition root.

**Items, the split (owner, 2026-11-22):**
- Native owns item use, the effects on `DriveState`, items in flight and bot item decisions.
- GDScript keeps the `ItemSet` data (packed at setup), the **odds roll at pickup** (it is sent to native as a `pickup` event), the **network hit confirmation** (events in and out) and the UI.
- **Pickup latency:** the odds roll runs in GDScript after `end_tick`, so an item from a box reaches the kart one tick after it touches the box (the `pickup` event is applied by `apply_events` on the next tick).

**Camera, HUD and tools** that need route or progress data call `CourseRuntime`. There is one route-sampling implementation, in native code. `CourseBuilder`'s import-time baking is never reused at run time.

### 2. Data in GDScript Resources, packed once in GDScript
Native code **never reads a GDScript script property**. With `Object::get("field")`, a renamed or missing field silently returns a null Variant, which becomes 0 in C++ (godot-specialist review). For tuning data that failure is unacceptable.
- **Each GDScript Resource that native code consumes gets a `pack_native()` method.** It returns plain data: packed arrays plus a flat `Dictionary` of scalars with fixed keys.
  - A GDScript unit test per Resource pins the packed schema: keys, types, order and units.
  - Native setup takes that plain data and checks every key and `Variant` type with `ERR_FAIL_*`, so a missing or wrong-typed key refuses the load and names the key.
  - The schema version is an integer in the packed data, and both sides assert it.
- **Native signatures** take `Dictionary`/packed arrays (or `Ref<Resource>` only as an opaque handle). GDScript script classes do not exist in C++, so they cannot appear in bound signatures.
- **Packing happens at build or track load only.** Per-tick code never reads a Resource, a `Dictionary` or a `Variant` container; the copied values live in plain C++ structs.
- **Tuning values stay in `.tres`,** and `tuning-values.md` keeps applying.
- **Runtime changes** to a Resource (for example in a debug panel) apply through an explicit `reload_config(packed)`. Native objects do not poll for changes.
- **No GDScript reference at module init.** Native code never touches a script class in `initialize_module`, because global script classes are not loaded at that level.
- **Rule for what crosses the boundary:**
  - Resources go only to setup and configure calls, and only as their packed form.
  - Per-tick calls take no Resource. The surface is passed **by id**, and driver input is a native value or a packed row.
  - `DriveState.drive(...)` therefore changes: the ADR-0003 signature takes `DriverInput`, `VehicleStats` and `SurfaceType` parameters. In native it takes a driver-input row and a surface id, and the stats are bound at configure time (§12, amendment).

### 3. Boundary: per-stage `RaceSim` calls, packed buffers
**`RaceSim` (native) owns all simulation state and asserts the stage order.** The GDScript composition root does the network I/O between the calls, following ADR-0003 §4 tick order and ADR-0006. It does not own state and cannot reorder the stages: a call out of order is refused with an error (`ERR_FAIL`) in debug and release builds.

**Stage calls, per tick, in this order** (8 calls; each crossing costs about 0.2 µs):

| # | Call | Inputs | Outputs / effect | ADR-0003 §4 step |
|---|---|---|---|---|
| 1 | `begin_tick(tick: int)` | the tick number only. Native computes `t = tick × SIM_DT` (§4, `SIM_DT`) | Applies the pending `hold` mask and resets per-tick scratch. | start |
| 2 | `apply_events(headers: PackedInt32Array, payload: PackedFloat32Array)` | Received events, decoded by `NetEventCodec`, in the event pair type (below): header rows of slot and kind, and a float payload. Includes `pickup` (item id from the GDScript odds roll) and item hit confirmations. | Applies each through `apply_event` (max-merge knock, speed loss); refreshes the snapshots of the slots hit. | 1 |
| 3 | `step_drive(driver_input_packed: PackedFloat32Array)` | One row per **local** slot: steer, throttle, brake, drift, hop, item-use. Raw driver input, **not** `KartIntent` (internal now). | Runs `drive()` for local slots and the bot decisions for **bot** slots; item use and bot item decisions here. Rows for **held** slots still reach `DriveState`'s start logic (start boost). | 2 |
| 4 | `step_bodies()` | none | Integrates every simulated body (local and bot): wall slide, ground cast, suspension, basis, timers; writes the pre-contact snapshot; then **`CourseProgress` updates for that slot** (`moved`, `safe`), per slot after each body step. Held slots do not integrate. | 3–10 |
| 5 | `set_remote(remote_snaps_packed: PackedFloat32Array, contact_eligible_mask: int)` | Remote karts' sampled poses from `RemoteKartSet.sample_into` (SIM cursor), and the mask of remote slots eligible for contact. | Stores the remote poses for this tick (copied into native structs; the array is not kept). | 11 (inputs) |
| 6 | `step_contact()` | none | Kart-vs-kart contact in ascending (i, j) pair order against pre-contact snapshots (the broadphase sorts by `CourseProgress` distance, ADR-0003 §7); writes knock, speed loss, `pending_push`, `bumped`; then the end-of-tick snapshot. | 11–12 |
| 7 | `step_progress_items_hazards()` | none | Ranking, laps, respawn (including respawn placement), items in flight (motion, hits), hazard and pad tests, same-tick local effects. `CourseProgress` itself was already updated in stage 4. | 13 |
| 8 | `end_tick()` | none | Swaps the output buffers (snapshots, events, progress, stage timers), clears the working event buffer, closes the stage timers. | 12 (end) |

**Order kept.** The stages follow ADR-0003 §4. Progress runs before contact because the contact broadphase sorts by `CourseProgress` distance (ADR-0003 §7), so `CourseProgress` updates inside `step_bodies()`.

**Network I/O around the calls** (composition root, GDScript; ADR-0006):
- before call 1: pull decoded inbox events from `NetLink`;
- between calls 4 and 5: `RemoteKartSet.sample_into` produces the remote poses;
- after call 8: `snapshots()` and the event pair feed `SnapshotCodec` and `NetEventCodec` for sending, and `progress()` feeds the HUD and ranking. The GDScript odds roll for any item pickup in the events runs here, and its result goes in as a `pickup` event on the next tick;
- **the teleport epoch stays with ADR-0006's GDScript sender**, which bumps it when a snapshot has `teleported`. Native code only sets `teleported` in the snapshot.

**Slot roles.** Set at `RaceSim.setup` (`slot_roles` packed) and never changed mid-race, except through race flow:
- **local:** a body stepped from `driver_input_packed` rows, on this PC;
- **bot:** a body stepped from native bot decisions, on the host only (ADR-0006: the host owns bots);
- **remote:** no body; the pose comes in through `set_remote`. A remote slot takes part in contact only when its bit is set in `contact_eligible_mask`.

**Race flow calls** (between ticks, never inside a tick):
- `place(slot, pose_packed)` for the start grid and debug only; it marks the snapshot `teleported`. Respawn placement is native code in stage 7, not a `place` call;
- `hold(slot_mask: int)` for the countdown and the resync hold: the pose is held and the body does not integrate, but driver rows still reach `DriveState`'s start logic, for the start boost (Driving & Drift §3.1.9 and AC-16);
- FROZEN stays with Fall & Respawn only (ADR-0003 §8). `hold` is not the FROZEN state.

**Outputs are double-buffered in C++.** Packed arrays are copy-on-write: a returned array is a reference-counted alias, not a live view. If GDScript still holds it when C++ writes through `ptrw()`, the buffer detaches, which detaches it: the holder keeps an intact copy of the old data (never corrupted), and native pays a full copy (godot-specialist review). So:
- `snapshots()` returns `KartSnapshot` fields per slot, `progress()` the progress values and `stage_usec()` the stage timers. The events come as a pair (below).
- Each comes from buffer A on even ticks and buffer B on odd ticks, so the buffer GDScript may still hold is never the one being written. **`stage_usec()` is double-buffered too.**
- **Caller contract:** a held array is a copy-on-write snapshot of its tick and is never corrupted. A consumer that refreshes its reference every tick never causes a detach. A consumer that keeps an array longer pays one copy per held array. A consumer never writes through a returned array, and never passes a returned array back in as an input.
- **Events are a pair:** `event_headers() -> PackedInt32Array` (rows of slot, kind, payload offset) and `event_payload() -> PackedFloat32Array`, double-buffered like the rest. Capacity is fixed at setup, `event_count() -> int` gives the rows used, and on overflow the extra events are dropped and `events_overflowed() -> bool` is set until the next `end_tick()`. The exact layout is fixed by the `RaceSim` story.
- Per-slot accessors (`snapshot_position(slot)`, `snapshot_basis(slot)` and so on) serve consumers that need one kart, without element-by-element VM reads of the whole array.

**Inputs and rules:**
- C++ reads the caller's input arrays through `ptr()` and never stores them as members.
- **No output-parameter packed arrays.** A packed argument that C++ writes through `ptrw()` detaches, so the caller never sees the writes.
- **One caller, one phase.** The stage calls come from one place only: the composition root's physics tick, on the main thread.
- **Per-object APIs stay bound** for **unit tests**, tools and one-off calls that are not part of the tick order (the camera's ground read through `CollisionQuery`). Their semantics are the ones ADR-0002 to ADR-0004 define, with the call-surface changes of §2 and §12.
- **Tests that depend on tick order go through `RaceSim`:** contact, determinism, the parity harness (025–026) and the budget stories. Per-object calls are for unit tests only.
- **No per-query boundary crossings inside a GDScript loop over karts.** The spike measured about 0.17 µs per crossing.
- **Stage timing.** `RaceSim` records native per-stage timers into a preallocated array. `RaceSim.stage_usec() -> PackedFloat64Array` returns the last tick's microseconds per stage (one element per call above). The array is double-buffered like the other outputs. The timers are always on; reading them allocates nothing in the tick.

### 4. Implementation rules (C++)
- **Language and engine API:** C++17, godot-cpp at a pinned commit. Engine types are used where they cross the boundary or call the engine.
- **Scalars are `double`,** as GDScript `float` is. Race time, speeds, rates, angles and tuning values are all `double`. **Vectors and bases stay godot-cpp float32 types** (`Vector3`, `Basis`, `Quaternion`, `Transform3D`), so results match the engine's layout. This restates ADR-0001 §1 for native code (§12, amendment: all scalars are double).
- **`SIM_DT`: one value, two constants.** GDExtension class constants are integer-only, so a float cannot be bound.
  - GDScript keeps `const SIM_DT: float = 1.0 / 60.0`, as ADR-0001 §5 has it. No GDScript const may read a native symbol, because a script that names a native type must load after the boot check.
  - C++ has `constexpr int SIM_HZ = 60` and `constexpr double SIM_DT = 1.0 / SIM_HZ`, and binds a static `DogworksCore.sim_hz() -> int`.
  - `native_boot_check.gd` asserts, through `ClassDB.class_call_static` (UNVERIFIED, Verification Required 9), that `sim_hz() * SIM_DT == 1.0` and that `sim_hz()` equals `physics_ticks_per_second`.
  - No time value crosses the boundary: `begin_tick(tick)` takes the tick, and native computes `t = tick * SIM_DT`.
- **No allocation after build:** no `new`, no container growth, no `String`/`Variant` creation and no RID creation in per-tick paths. Containers are sized when a track loads or a race is set up.
- **RID ownership and teardown** follow ADR-0002 and `.claude/rules/godot-refcount.md`:
  - A RefCounted owner frees bodies, then shapes, then the space, through one static helper called from both `dispose()` and its destructor.
  - **`dispose()` is mandatory.** The composition root and every test teardown call it.
  - **Servers-alive flag.** godot-cpp caches singleton pointers, so `get_singleton() != nullptr` does not prove the server still exists. A module-level `g_servers_alive` flag is set in `initialize_module(SCENE)` and cleared in `uninitialize_module(SCENE)`, and every RID-freeing destructor checks it and skips when it is cleared.
  - **Guarded construction.** `create()` fails loudly (`ERR_FAIL_NULL`) and returns null when the server is missing. Constructors touch no server.
  - **Leaks crash.** A GDScript leak of a native object is no longer a warning but a crash on exit (exit code 139). The exit-code-0 check from `godot-refcount.md` is part of the toolchain story.
- **Construction pattern: a bound static factory.**
  - A native class that needs arguments is built through `Class.create(packed) -> Class`, bound as a static method. `.new()` takes no arguments, so none of these classes is built with `.new(args)`.
  - `create()` calls the **same C++ validation function** that `Class.validate_packed(packed) -> String` binds (empty string = valid, otherwise the message that names the key), so the two cannot disagree. It returns a `Ref<Class>` built with `instantiate()`, and **null on failure**.
  - **`.new()` stays callable** (the engine allows it) and gives an empty, unbuilt object. So every bound method guards on a `built` flag with `ERR_FAIL_COND`.
  - **Constructors create no RIDs.** All server work (spaces, shapes, bodies) happens in `create()`.
  - **No autoload names a native type.** An autoload loads before the boot check can run.
  - `CollisionBootCheck.checked_query` stays the single GDScript construction site for `CollisionQuery`. It calls `validate_packed`, then `create`, and fills `CheckedQuery.problem` as today.
  - **Why this and not a result object:** a native result class is one more registered type, with its own lifetime and teardown rules, for a message the GDScript caller can already get from `validate_packed`. The pattern also matches `CollisionBootCheck.checked_query`, so call sites and the "no construction outside `CollisionBootCheck`" grep keep their shape. A null return with no reason would lose the key name, so the pair is needed.
  - `RaceSim.create(setup_packed)` and `KartBody.create(...)` follow the same pattern.
- **Physics thread.** Native queries run on the main thread inside the physics tick only, never from a worker thread or a `WorkerThreadPool` task. `physics/3d/run_on_separate_thread=false` is pinned, and the boot check asserts it (story 006 already does).
- **Registration:**
  - `GDREGISTER_CLASS` at `MODULE_INITIALIZATION_LEVEL_SCENE`; static methods are bound with `ClassDB::bind_static_method`.
  - Not `GDREGISTER_RUNTIME_CLASS`: editor-time `@tool` code (the import pipeline, `CollisionBootCheck`) must be able to use the classes.
  - `GDREGISTER_ABSTRACT_CLASS` for non-instantiable bases. Bases and the result types are registered before the classes whose APIs use them, and `DogworksCore` is registered first.
  - No static initialisers that call engine APIs.
- **Determinism:**
  - **Float flags.** Build with MSVC `/fp:precise`, no `/fp:fast`, and an SSE2 baseline (no `/arch:AVX2`, so no FMA contraction can occur).
  - **The CRT.** It is statically linked (`/MT`, godot-cpp's `use_static_cpp=True`, pinned).
  - **Pinned command line.** The real compiler command line is dumped into the toolchain story's evidence.
  - **Known limit: transcendentals are not bit-identical across CPUs.** The UCRT dispatches `sin`, `cos` and `atan2` to FMA3 variants on capable CPUs, and the engine's copy of the maths can differ from the extension's. The spike's one-ulp `slerp` differences likely come from this (UNVERIFIED). ADR-0001 §6 asks only for same-machine determinism, so this is accepted. If cross-machine equality is ever needed: `_set_FMA3_enable(0)` at init and own polynomial trig, by amendment.
  - Every loop runs in slot or data order. Iteration order never depends on a hash container.
  - **Randomness:**
    - One godot-cpp `RandomNumberGenerator` instance per consumer, created at setup (never per tick), seeded with the same `Array.hash()` formula as ADR-0001 §6. GDScript computes each seed and passes it in the setup data, so one formula serves both sides. We do not write our own PCG32.
    - **Forbidden in per-tick code:** `rand()`, anything from `<random>`, `std::random_device`, the global `randf`, and iteration over unordered containers.
  - **Golden traces are never compared across PCs.** Same-seed traces are compared only on the machine that made them, and the debug and release DLLs must give the same trace hash (Validation Criteria).
- **Errors:** `ERR_FAIL_*` / `push_error` at load-time boundaries; asserts in debug builds only. Per-tick paths never print. The stage-order assert of §3 is not debug-only.
- **Layout:** one subfolder per system under `native/src/` (`collision/`, `kart/`, `drive/`, `course/`, `items/`, `ai/`, `race/`) and one class per file pair. Every class and public method has a doc comment, and bound methods carry their GDScript-facing docs.
- **Coding standards:** a new rule file `.claude/rules/native-code.md` (written by the toolchain story) carries these rules for `native/**`.
- **Knowledge file:** the toolchain story writes `docs/engine-reference/godot/godot-cpp.md`, covering:
  - the pinned commit;
  - registration and binding, static methods included;
  - properties and `Ref<>`;
  - no constructor arguments;
  - packed-array copy-on-write;
  - destructor and RID rules;
  - `ERR_FAIL_*`.
- **Who writes it:** native stories go to `godot-gdextension-specialist`.

### 5. Single source of truth, and the GDScript oracle
- When a system goes native, the native class is its **only** implementation under `src/`.
- **Class names never clash.** A native class and a GDScript global `class_name` with the same name conflict ("hides a native class"), and a stale `.godot/global_script_class_cache.cfg` can mask the error.
  - The story that registers a native class removes or renames, in the same change, every GDScript `class_name` with that name in `src/` and `tests/`. That covers every name in the §1 table: today's collision classes, and any `KartSnapshot`, `KartIntent`, `KartEvent`, `DriveState`, `CourseProgress` or `RouteCursor` that exists as a GDScript class by then.
  - After the change it re-runs `--import`.
  - A check in `tools/core_greps.sh` fails when any `class_name` under `src/` or `tests/` matches a native class name (the list comes from `ClassDB` in a headless run).
- **The existing GDScript collision code** (`CollisionQuery`, `QueryCursor`, `GroundHit`, `WallHit`) moves to `tests/oracle/collision/`, renamed `OracleCollisionQuery` etc. (no `class_name` clash with the native classes). There it serves as a parity oracle.
- **The oracle is frozen at port time.** A later ADR-0002 change updates the native code only, and the parity cases it affects are retired, with the reason written in the test.
- **Parity tests,** native against oracle on the story-005/007 fixtures and the bench mesh:
  - surface ids, wall-attribute ids, hit/miss and `started_inside` are **exact**, **except** inside a stated band near the decision boundary: oracle clearance or penetration depth below 1e-4 m. A case inside the band is excluded from the exact check and counted, and the **excluded count is reported** in the test output;
  - ray distances are within 1e-5 m;
  - sweep fractions are within 1e-3 (spike max difference 4.5e-4);
  - normals are within 1e-4 rad.

  The spike traced the differences to one-ulp pose `slerp` differences.
- **Test changes the port makes** (listed so the port story is sized):
  - about **286 `.new(` sites** across the four collision classes are reviewed. Those that pass arguments move to the factory (§4); `GroundHit`, `WallHit` and `QueryCursor` calls with no arguments stay;
  - the two GDScript-source scan tests for `*_create(` (`collision_mover_edge_cases_test.gd`'s SCANNED list and `collision_movers_test.gd`) cannot read C++ and move to `tools/core_greps.sh`, which scans `native/`;
  - destructor and dispose tests replace the GDScript `NOTIFICATION_PREDELETE` tests (the PREDELETE static-helper rule no longer applies to native classes).
- **The existing collision suite** (200 tests) is re-targeted at the native class, except where a test compares bit-exact floats against GDScript-computed expectations. There a tolerance is written with its reason.
- **Kart physics and later systems have no GDScript oracle.** Their parity is checked against the frozen game's golden traces (epic stories 025–026), run through `RaceSim`.

### 6. Folder layout and build
```
native/                      .gdignore (Godot never scans it)
  SConstruct                 builds dogworks_core (debug, release and bench variants), /fp:precise, pinned flags
  src/<system>/*.h|*.cpp     C++ sources
  src/register_types.cpp
  GODOT_CPP_COMMIT           pinned godot-cpp commit (committed)
  godot-cpp/                 fetched at that commit by the build script (gitignored, .gdignore); about 500 MB
  api/                       extension_api.json + gdextension_interface.{h,json} dumped from the pinned editor (gitignored)
  .venv/                     SCons venv (gitignored, .gdignore)
  obj/                       object files, one variant folder per DLL (debug, release, bench); the generated build_marker.cpp
                             (SConstruct variant_dir; never next to sources; gitignored, .gdignore)
addons/dogworks_core/
  dogworks_core.gdextension  committed; entry_symbol = "dogworks_core_init", compatibility_minimum = "4.8",
                             no compatibility_maximum, reloadable = true (file-level; the release DLL is built
                             without hot reload, stated explicitly in SConstruct)
  plugin.cfg, plugin.gd      @tool EditorPlugin: runs the source-hash check at editor start (§7)
  bin/                       built DLLs, debug PDB kept beside the debug DLL, build_hash.txt, and bench.lock
                             while a bench copy is swapped in (gitignored)
src/core/native_boot_check.gd   no native types; checks the extension is loaded (§7)
tools/build_native.sh        one command: venv + godot-cpp fetch + API dump + vcvars64 + scons (debug, release and bench variants); --check; --bench; bench restore
tools/build_native.bat       the MSVC environment wrapper it calls (bash cannot source vcvars)
tests/unit/<system>/         gdUnit4 tests against the native classes
tests/oracle/collision/      the GDScript oracle (moved)
```

### 7. DLLs are built, not committed (owner, 2026-11-22)
- **One command per clone.** A fresh clone runs `tools/build_native.sh` once: about 90 s cold, about 8 s incremental. The scripts set explicit timeouts for the cold build (a default tool timeout would cut it).
- **Fresh-clone import order.** `CourseBuilder` runs at import and needs the native `CollisionQuery`. So a clean clone runs `tools/build_native.sh` **before** the first `--import`, never after. Verification Required 6 proves the extension loads during the first scan. ADR-0005 and story 041 (fresh-clone import) are amended for this at acceptance.
- **Two hashes, one DLL each:**
  - **Source hash (SH):** sha256 over a list of `relative path`, NUL, `sha256(file bytes)` for `native/src/**`, `native/SConstruct`, `tools/build_native.sh`, `tools/build_native.bat`, `addons/dogworks_core/dogworks_core.gdextension` and `native/GODOT_CPP_COMMIT`.
    - **Bytes, CRLF-safe:** it hashes raw file bytes (`FileAccess.get_sha256` does the same), so these files are pinned `eol=lf` in `.gitattributes`, and a CRLF checkout cannot change the hash.
    - **One list, one order:** the file list is sorted in byte order (`LC_ALL=C` in bash; the GDScript side sorts the ASCII paths the same way). The bash side and `FileAccess` read the same committed list definition, which the toolchain story names.
    - **Excluded:** generated files and `native/obj/`.
  - **Full hash (FH):** sha256 over SH, the sha256 of the API dump, the MSVC version string and the target (`debug`, `release` or `bench`). There is **one FH per DLL**.
- **How the hash is stored and read:**
  - SCons generates one file, `native/obj/build_marker.cpp`, holding a single literal `DOGWORKS_BUILD:<target>:<SH>:<FH>:END`, parsed by offsets. A bound function references it, so the linker keeps it. `DogworksCore.build_hash()` and `DogworksCore.source_hash()` return the parts.
  - **The marker is compiled only in that file.** It is never passed as a `CPPDEFINES` value on the shared environment, because that would force a full rebuild whenever a hash changes.
  - The build also writes both values per DLL to `addons/dogworks_core/bin/build_hash.txt`.
  - **`--check` reads the DLL by counting regex matches of the full marker pattern in its bytes.** It fails unless the pattern appears **exactly once**, and when the hashes differ from the ones it recomputes.
  - **Why a binary search and not a headless Godot call:** it starts no Godot process, so it takes milliseconds, loads nothing (a headless run would lock the DLL, §7 below) and works before any extension loads, including on a clone whose build just finished. The cost is the marker-survives-the-linker risk, covered by Verification Required 7.
- **Stale-DLL guard, two layers:**
  - `tools/build_native.sh --check` recomputes SH and FH and compares both with `build_hash.txt` and with the marker in each DLL. A mismatch is FAIL. `--check` also FAILs while `bench.lock` exists, or when the marker target in the debug slot is `bench` (§8).
  - `tools/regression.sh` and the test command run `--check` first, so a stale DLL fails loudly. Wiring it into the test command changes `project.yaml` `commands.test`, which is a config change the owner approves at acceptance.
  - **Boot refusal moves out of `CollisionBootCheck`.** `CollisionBootCheck` and every script that names a native type fail to parse when the extension is missing, so they cannot report it. The "extension not loaded" refusal lives in `src/core/native_boot_check.gd`, which names no native type. It checks `ClassDB.class_exists("DogworksCore")` **before any native-typed script loads**, and then makes the `sim_hz()` assert of §4. The composition root's entry script has no native types either: it calls the check, and only then loads the race scripts with `load()`.
  - **The editor-panel gap is closed, not accepted.** gdUnit4 started from the editor panel does not run `--check`. In editor builds only (`OS.has_feature("editor")`), one shared function recomputes SH with `FileAccess` over the same file list and compares it with `DogworksCore.source_hash()`. Three callers run it:
    - `native_boot_check.gd` at boot;
    - an `@tool` EditorPlugin in `addons/dogworks_core/`, at editor start, so an editor opened on a stale DLL says so before any panel run;
    - a shared test helper, called in `before()` by every native-test suite. A `core_greps.sh` rule fails when a suite under `tests/unit/` touches a native class and does not call the helper.

    A mismatch refuses and names `tools/build_native.sh`. FH is not recomputed there (it needs MSVC and the API dump), so a compiler change alone is caught by `--check` only. That is accepted.
  - **Exports skip the hash check,** because they carry no `native/` sources.
- **Locked DLL.** A running game, a headless `--import` or a gdUnit4 run loads the original DLL and locks it; only the editor's reloadable copy (`~…dll`) leaves it free. So:
  - `tools/build_native.sh` refuses to build when a Godot process holds the DLL, and names the process;
  - it links to a temporary name and renames on success;
  - it runs `--check` after the build;
  - tests and benchmarks never run during a rebuild.
- **Hot reload is for the editor only.** A rebuild recreates native instances in the editor process: only bound properties survive, and caches and RIDs are rebuilt. A game started from the editor runs in its own process and never live-patches.
- **Old commits.** Checking out an old commit means rebuilding; the hashes make a forgotten rebuild visible.

### 8. Export, and benches on the release build
- An export needs the `template_release` DLL and the 4.8 export templates; neither is in place today (templates not installed).
- **Export checks:**
  - the `.gdextension` `[libraries]` lists `windows.release.x86_64`;
  - the export filter includes `*.gdextension` and the DLL;
  - `tools/build_native.sh --check` runs before every export, because a gitignored DLL that does not exist at export time is silently left out.
- The export story verifies that the DLL ships and loads.
- **Benches measure the release-flag build.** The editor picks the `windows.debug.*` entry, so the release code never loads by itself.
  - SCons always builds the debug and release DLLs under their normal names, each with its own `obj/` variant folder, so a normal build never touches a swapped file. The bench copy is the release-flag DLL built with `use_hot_reload=yes` (its own variant folder), so the editor can load it through the debug slot (UNVERIFIED, Verification Required 8). The release DLL that ships in an export is still built without hot reload.
  - **`tools/build_native.sh --bench`** refuses to run while any Godot process, **including an editor**, is open. It then backs up the debug DLL, copies the bench DLL over the debug name, and writes `addons/dogworks_core/bin/bench.lock`.
  - **Restore** copies the backup back and removes `bench.lock`. It **never rebuilds**: SCons cannot restore a file that was swapped under a target name.
  - **`--check` fails** while `bench.lock` exists or when the marker target in the debug slot is `bench`. The test command runs `--check` first, so a test run cannot start on a bench DLL.
  - **Why a swap and not a bench-only `.gdextension` variant:** a second `.gdextension` registers the same class names a second time (a clash), and Godot reads only the entries in `extension_list.cfg`, so the editor would load both or neither.
  - The result is an upper bound, as `architecture.md` already says: a debug editor build plus an optimised extension.

### 9. Engine upgrade procedure
On every re-pin (`/setup-engine refresh`, including 4.8-beta3 → 4.8 stable, and the API re-dump at 4.8 RC):
1. Re-dump the API from the new editor binary.
2. Move `GODOT_CPP_COMMIT` if godot-cpp needs it.
3. Rebuild debug and release.
4. Update `compatibility_minimum`.
5. Run the full gdUnit4 suite, the parity tests, `tools/bench_collision.sh` and `tools/regression.sh`.

A failed rebuild blocks the re-pin.

### 10. Performance projection
**Collision, worst layout (12 karts in reach of 5 spinning solid movers): about 110–170 µs p95** native, against 868 µs in GDScript. It is a projection from separate measurements, not a measurement of the whole path.
- **Low end, about 110 µs:** the spike's batched mover maths, 13 µs, plus the raw Jolt cost, about 95–100 µs (story 007).
- **High end, about 170 µs:** the spike's 27 µs per call, plus 100 µs Jolt, plus about 14 µs for per-query crossings from GDScript (84 crossings × 0.17 µs, measured in the spike; the port bench measures them again), plus about 30 µs of allowance for what no measurement covers (result writes, the real fixture instead of the spike's synthetic layout). The allowance is a judgement, not a number from a run.
- **Pass line: 300 µs p95** in every story-007 layout. A miss fails the port story.
- **Castle (realistic layout): 150 µs p95 is a target, not a pass line.** If the port misses it but passes 300 µs, the technical-director decides whether it stands. The v1 text treated 150 µs as a pass line.
- The whole tick stays under 2.0 ms p95; each story re-measures its own stage with `RaceSim.stage_usec()`.

### Architecture Diagram
```
 GDScript                                           C++ (dogworks_core)
 ─────────────────────────────────────────          ───────────────────────────────────────────
 NetLink inbox ──decoded events──▶ apply_events()
 composition root ── begin_tick(tick) ───────────────▶ RaceSim (owns all state, asserts stage order)
 DriverInput ──driver rows (PackedFloat32Array)──▶ step_drive() ──▶ DriveState, bot decisions, item use
                                                    step_bodies() ──▶ KartBody ──▶ CollisionQuery ──▶ PhysicsServer3D (Jolt, _into); then CourseProgress per slot
 RemoteKartSet.sample_into ──remote poses + mask──▶ set_remote()
                                                    step_contact() ──▶ KartContactSolver
                                                    step_progress_items_hazards() ──▶ ranking, laps, respawn, items in flight, hazards
                                                    end_tick()  (swap buffers)
 SnapshotCodec / NetEventCodec / HUD / camera ◀──snapshots(), event pair, progress(), stage_usec() (double-buffered)
 Resources (.tres) ──pack_native(), copied once at setup──▶ create(packed) / configure(packed)
 tests (gdUnit4) ──per-object bound APIs (unit) / RaceSim stages (order-dependent)──▶ native classes
 tests/oracle/collision (GDScript) ──parity──▶ CollisionQuery (native)
```

### Key Interfaces
```gdscript
# Construction: a bound static factory. No .new() arguments on native classes.
var packed: Dictionary = data.pack_native()                      # TrackCollisionData -> plain data
var problem: String = CollisionQuery.validate_packed(packed)     # "" when valid
var q: CollisionQuery = CollisionQuery.create(packed)            # null on failure (CollisionBootCheck.checked_query wraps both)
var cursor := QueryCursor.new()                                  # no arguments: .new() is fine
var hit := GroundHit.new()

# Per-object calls (unit tests, one-off calls). Real ADR-0002 signatures, as in collision_query.gd:
q.cast_ground(cursor, origin, dir, max_dist, t, hit) -> bool
q.sweep_walls(cursor, from, to, radius, t, wall_hit) -> bool

# Production tick: per-stage RaceSim calls (the composition root does network I/O between them).
var sim: RaceSim = RaceSim.create(setup_packed)                  # slot roles, packed Resources, per-consumer seeds
sim.begin_tick(tick)                                            # native computes t = tick * SIM_DT
sim.apply_events(inbox_headers, inbox_payload)                   # the event pair: PackedInt32Array, PackedFloat32Array
sim.step_drive(driver_rows)                                      # PackedFloat32Array, one row per local slot
sim.step_bodies()
sim.set_remote(remote_snaps_packed, contact_eligible_mask)
sim.step_contact()
sim.step_progress_items_hazards()
sim.end_tick()
var snaps: PackedFloat32Array = sim.snapshots()                  # double-buffered; a held copy is never corrupted (§3)
var event_headers: PackedInt32Array = sim.event_headers()        # with event_payload(), event_count(), events_overflowed()
var progress: PackedFloat32Array = sim.progress()
var usec: PackedFloat64Array = sim.stage_usec()                  # last tick, per stage

# Race flow, between ticks:
sim.place(slot, pose_packed)                                     # start grid and debug only
sim.hold(slot_mask)                                              # countdown and resync hold

# Runtime course queries (camera, HUD, tools, native code): one implementation.
var course: CourseRuntime = CourseRuntime.create(course_data.pack_native())

DogworksCore.sim_hz() -> int                                     # static; 60. SIM_DT stays a GDScript const (§4)
DogworksCore.build_hash() -> String                              # stale-DLL guard
DogworksCore.source_hash() -> String                             # compared with the FileAccess recompute in editor builds
```
The exact `RaceSim` buffer layouts (fields per slot, driver-row columns, event encoding) are fixed by the story that builds `RaceSim`, and recorded in ADR-0003's Key Interfaces as an amendment. The stage list, parameters and outputs above are binding.

### Implementation Guidelines
- Per-tick native code **must never** allocate, create RIDs, read Resource properties, or build `String`/`Variant`/`Dictionary` values.
- GDScript **must never** loop over karts calling native per-kart methods in the production tick. It calls the eight `RaceSim` stages.
- Native code **must never** read a GDScript script property.
- Every bound native method **must** guard on the `built` flag. No autoload **may** name a native type.
- `src/` **must never** contain a second implementation of a native system. The GDScript oracle lives only under `tests/oracle/`.
- A native class **keeps** the behaviour that ADR-0002 to ADR-0004 define. A change to its call surface goes through the amendments of §12.
- Tuning values **must** stay in `.tres`. Debug-only constants may be named `constexpr` in C++.
- Native code **must** step in slot order, seed randomness per consumer from setup, and be built with the pinned float flags.
- `tools/build_native.sh --check` **must** pass before tests or regression run.
- `native/`, `native/godot-cpp/` and `native/.venv/` **must** carry `.gdignore`. Godot imports `.obj` files as models, and the spike segfaulted when it scanned godot-cpp.
- Native stories **go to** `godot-gdextension-specialist`.
- Tests that depend on tick order **go through** `RaceSim`.

## Alternatives Considered

### Alternative 1: Stay in GDScript with a track-design cap
- **Description:** Keep GDScript. Cap solid movers in reach at 2 per 60 m stretch; port later if a profile demands it.
- **Pros:** No toolchain; fastest iteration.
- **Cons:**
  - The cap constrains Mario Kart-grade track design permanently.
  - The worst case stays at 868 µs.
  - Kart, contact, bots and items will hit the same overhead, and porting them later means writing them twice.
- **Rejection Reason:** The owner chose to pay the cost now (2026-11-22). Technically, the GDScript VM executes the mover maths as bytecode with a boxed `Variant` per operation, which is where the 22–49x gap comes from, and a cap does not change the per-operation cost of the rest of the tick.

### Alternative 2: Native collision only
- **Description:** Port `CollisionQuery`; keep kart physics, contact, bots and items in GDScript until a profile says otherwise.
- **Pros:** Smallest C++ surface; GDScript iteration on the control law.
- **Cons:**
  - Per-query boundary crossings from GDScript karts: about 84 crossings per tick, about 14 µs measured.
  - Bots (0.8 ms budget) and contact remain GDScript-bound.
  - Kart code would likely be ported later anyway.
- **Rejection Reason:** The owner chose the whole tick ("tudo agora"). Technically, the crossings are cheap but the data is not: every `KartSnapshot` would be written in C++ and read back as GDScript objects, and the hot bot and contact loops would still run in the VM at the cost the spike measured.

### Alternative 3: Solid movers as Jolt kinematic bodies
- **Description:** Pose each solid mover's body at t before the queries and let Jolt sweep against it.
- **Pros:** No C++ toolchain; Jolt does the mover maths.
- **Cons:**
  - Amends ADR-0002's analytic, t-addressable movers. Per-query re-posing for arbitrary t (rewind, prediction) is costly and unverified.
  - It leaves the GDScript wrapper overhead and the rest of the tick untouched.
- **Rejection Reason:** It solves one row of the budget, not the tick.

### Alternative 4: Commit the built DLLs
- **Description:** Keep the debug and release DLLs in git.
- **Pros:** Any checkout runs without a toolchain, old commits included.
- **Cons:** About 800 KB of history per rebuild; a DLL can silently disagree with its sources.
- **Rejection Reason:** Owner chose build-not-commit (2026-11-22). The two hashes cover the stale case. Technically, git cannot diff a binary, so a reviewer cannot tell whether a committed DLL matches the sources next to it, and the history grows by a full DLL each time any C++ line changes.

### Alternative 5: A C++ unit-test framework (doctest or Catch2) instead of gdUnit4
- **Description:** Test native code in C++ directly.
- **Pros:** Faster tests; tests private internals.
- **Cons:** Two test runners and a second CI path; tests would not exercise the bound API the game uses.
- **Rejection Reason:** gdUnit4 against the bound API keeps one runner, and the existing 200 collision tests carry over. A C++ test target may be added later for internals, by amendment.

### Alternative 6: Native classes per system, tick loop in GDScript, one batched call per stage
- **Description:** Each system is a native class (`KartBodySet`, `ContactSolver`, `CourseRuntime`, bots), each with batched calls over all karts. The composition root in GDScript owns the tick order and the state handoff between them.
- **Pros:** The tick order stays in GDScript, which is easy to read and change; each class is testable alone.
- **Cons:**
  - Every handoff between systems is a packed array through GDScript, with the copy-on-write and double-buffer rules of §3 repeated at each one.
  - Nothing enforces the order: a wrong call order is a silent behaviour bug, not an error.
  - State is split across objects, so a snapshot of "the whole sim" (resync, ghosts, determinism traces) needs every object visited.
- **Rejection Reason:** The chosen per-stage `RaceSim` calls are close to this: the stages are batched calls and GDScript does network I/O between them. The difference is that **`RaceSim` owns the state and the order**. The stages share native state without handoff arrays, and a stage called out of order is refused. The owner decided this on 2026-11-22.

## Consequences

### Positive
- TD-012 is expected to close: spike mover maths at 13 µs batched against 574 µs in GDScript.
- Kart, contact, bots and items are written once, in the language they will ship in.
- Eight boundary crossings per tick, all with packed data, remove per-call overhead from the tick.
- One state owner and a checked stage order make the tick reproducible and testable as a whole.
- One route-sampling implementation (`CourseRuntime`) serves the tick, camera, HUD and tools.
- The budgets in `architecture.md` gain large headroom for Mario Kart-grade content (more karts in contact, more movers, richer bots).

### Negative
- **A second language and a build step.** Contributors and agents need MSVC, a venv and an 8–90 s build. A cold build takes about 90 s, so the scripts set explicit timeouts. Every fresh clone and old checkout must build. godot-cpp takes about 500 MB on disk.
- **Slower behaviour iteration:** a rebuild per change, about 8 s incremental. Data tuning in `.tres` is unaffected.
- **Debugging crosses two languages.**
  - **The Godot profiler cannot see native code.** Its function list shows `RaceSim` stage calls as one line each. Native profiling uses the VS profiler or ETW, and the stage timers of §3.
  - **A native fault takes down the editor or the test runner.** Mitigation: PDBs are kept beside the DLLs, and a headless crash-repro script is part of the toolchain story.
- **Every engine re-pin needs a rebuild** and a re-test (§9). A beta API change can block a re-pin. The API is re-dumped at 4.8 RC.
- **ADR-0006 rework.** The tick order, the remote-pose input and the event flow of ADR-0006 and its stories (043–048) are reshaped around the stage calls.
- **Fresh-clone import order.** A clean clone must build before its first import (§7). A step in the wrong order fails import in a way that looks like a project error.
- **The GDScript collision code becomes test-only** (oracle), and its 1,100 lines must be kept in step only as long as parity tests use it. It is frozen at port time (§5).
- **Many docs and stories are amended** (Migration Plan). Until each amendment lands, the old text disagrees with this ADR.
- **Windows-only builds.** Other platforms need their own toolchain and a story.

## Risks
- **The GDExtension API changes between 4.8-beta3 and stable.** Mitigation: the API is dumped from the pinned binary, and the §9 procedure re-validates on each re-pin.
- **Unverified gdUnit4-to-native testing, typed factory calls or hot reload.** Mitigation: Verification Required items 1–3. The toolchain story proves them before the port starts, and if gdUnit4 cannot drive native classes, this ADR is amended before story 009.
- **A float difference between the oracle and native beyond tolerance** in a case the spike did not cover. Mitigation: parity failures are investigated, never widened silently. A tolerance change is written into the test with its reason. The band near the decision boundary is reported, not hidden (§5).
- **A native crash during tests** kills the runner. Mitigation: debug-build asserts at load boundaries; RID-order rules from ADR-0002; the game and tests run in their own processes, never in an editor with unsaved work; the debug PDB sits beside the DLL so crashes are symbolicated; a headless crash-repro script.
- **Unproven projection.** The §10 range is built from separate measurements and a judged allowance. Mitigation: the native `tools/bench_collision.sh` run in the CollisionQuery port is a gate before any other native port starts.
- **Copy-on-write packed arrays and name clashes** silently cost a copy per tick, or fail at parse time. Mitigation: §3 double-buffering, Verification Required 5 and the §5 name check, each with a test in the stories that introduce them.
- **Unexplained headless hang.** In the spike, `--path . --quit` hung once in a project with no main scene. Mitigation: toolchain CLI commands use `--headless --quit-after` with a scene, and the toolchain story records the cause.
- **A stale DLL in a long-running editor session.** Mitigation: `reloadable = true` plus the debug-build FileAccess source-hash check (§7).
- **A bench DLL left in the debug slot.** Mitigation: `bench.lock`, the `bench` marker and `--check`; `--bench` refuses to run while Godot is open (§8).
- **Delivery risk: knowledge sits with few agents.** Mitigation: the `godot-cpp.md` reference and `native-code.md` rule file (§4); native stories go to `godot-gdextension-specialist`.
- **An agent turn budget** is too small for C++ work plus builds. Mitigation: stories are cut smaller, and implementers keep STATE.md checkpoints, as now.

## GDD Requirements Addressed

| GDD System | Requirement | How This ADR Addresses It |
|------------|-------------|--------------------------|
| track-collision-and-surfaces.md | AC-20: collision ≤ 0.3 ms p95 for 12 karts | Native CollisionQuery; projected 110–170 µs p95 in the worst story-007 layout (§10), pass line 300 µs |
| kart-physics.md | Kart physics and contact within the 0.3 + 0.2 ms budgets; deterministic step | Native KartBody and contact solver behind `RaceSim` stages, slot-order stepping, pinned float flags |
| driving-and-drift.md | Control law per tick for 12 karts; tuning as data | Native DriveState reading packed `.tres` data once; values stay data |
| course-data.md | Per-tick progress with flat cost per section | Native `CourseRuntime` and `CourseProgress`, sized at load |

## Performance Implications
- **CPU:**
  - Collision is projected at about 110–170 µs p95 in the worst story-007 layout, against 868 µs (§10). Castle: target 150 µs.
  - The whole tick is expected well under 2.0 ms. Each story re-measures its stage with `RaceSim.stage_usec()`.
- **Memory:** about 0.4 MB per DLL. Native per-track structures are sized at load. The output buffers are allocated twice at setup and reused (§3).
- **Load Time:** packing Resources and copying them into structs at track load is negligible next to the Jolt shape build (ADR-0002).
- **Network:** none. Snapshot content is unchanged (ADR-0006).

## Migration Plan
1. **New story, native toolchain:**
   - `native/` skeleton, `tools/build_native.sh`/`.bat` with `--check`, `--bench` (and restore) and the two hashes;
   - the `.gdextension`, a `DogworksCore` class (with `sim_hz()`), the `.gdignore` files, `src/core/native_boot_check.gd`, the `@tool` hash-check EditorPlugin, the shared test helper with its `core_greps.sh` rule, and `.gitattributes` `eol=lf` for the hashed files;
   - `.claude/rules/native-code.md` and `docs/engine-reference/godot/godot-cpp.md`;
   - prove Verification Required items 1–9;
   - wire `--check` into `tools/regression.sh` and, owner-approved, `commands.test`;
   - a headless crash-repro script.
2. **New story, CollisionQuery port:**
   - native `CollisionQuery` (with `create`/`validate_packed`), `QueryCursor`, `GroundHit`, `WallHit`;
   - the GDScript versions move to `tests/oracle/collision/` as `Oracle*`, frozen;
   - the 200-test suite is re-targeted, the §5 test changes are made, and parity tests are added;
   - `tools/bench_collision.sh` is re-run, and TD-012 closes when the worst case is ≤ 300 µs p95;
   - `tools/core_greps.sh` rules are extended to `native/`: no Dictionary query forms; no `CollisionQuery` construction outside `CollisionBootCheck`; no `*_create(` in per-tick methods.
3. **New story, `RaceSim` skeleton, before story 012:** the eight stages with their asserts, the double buffers, the stage timers (`stage_usec()`), slot roles, `place`/`hold`, and empty stage bodies that later stories fill.
4. **Epic stories, native.** Each story file gets an Implementation Note pointing here when it starts.
   - **Implemented natively, criteria unchanged:** 009–011, 013–022, 031–032, 051–054.
   - **Criteria updated** (not edited now; listed for the owner and producer):
     - **008** legacy extractor and test mesh: a GDScript tool over the frozen game plus a generator-baked mesh. It reads no native simulation class, so it runs **before** the port and is not blocked. Confirm when the story starts.
     - **012, 024, 033, 055** (budgets): each "three hottest functions" criterion uses a native profiler (VS profiler or ETW) and `RaceSim.stage_usec()`, because the Godot profiler cannot see native code.
     - **012:** first-slice budget runs through `RaceSim` stages.
     - **023** (remote contact), **024** (determinism): through `RaceSim` and `set_remote`.
     - **025–026** parity harness: through `RaceSim`.
     - **028–030** (CourseData schema, CourseBuilder): `pack_native()`, `CourseRuntime`, and the builder's import-time baking not reused at run time.
     - **033–035** (ranking, generator equivalence, mesh track check): `CourseRuntime` and the native `CollisionQuery`.
     - **041** (fresh-clone import): build before first import.
     - **043–048** (codec, events, clock, remote view, net metrics, `NetLink`): events in and out as packed rows, `RemoteKartSet` feeding `set_remote`.
     - **050** (race clock, registry, tick order): the composition root calls the stages.
     - **055** (bot race and budget): native profiler, `stage_usec()`.
5. **§12 Amendments, to make at acceptance** ("§12" in this ADR means this step; none made now; the ADRs, stories, registry and config below are listed, not edited by this revision):
   - **ADR-0001:** §1, all scalars are `double`; §5, `SIM_DT` stays `const SIM_DT: float = 1.0 / 60.0` in GDScript, native has `constexpr double SIM_DT = 1.0 / SIM_HZ` with `SIM_HZ = 60`, and the boot check asserts they agree through `DogworksCore.sim_hz()` (class constants are integer-only, and no GDScript const may read a native symbol, because of load order); §6, native randomness (§4); §9, the `native/` and `addons/dogworks_core/` rows.
   - **ADR-0002:** implementation language native; construction through `create(packed)`; Key Interfaces; Alternative 5's rejection reason superseded for implementation, not backend.
   - **ADR-0003:** Key Interfaces (no `.new(args)`, `drive(...)` takes a driver-input row and a surface id, `KartIntent` internal, stats bound at configure); §4 tick order restated as `RaceSim` stages (order unchanged; `CourseProgress` updates inside `step_bodies()`); FROZEN stays with Fall & Respawn, and `hold` covers the countdown and resync; the event pair and buffer layouts.
   - **ADR-0004:** the runtime methods `progress`, `relocate`, `route_sample`, `lane_offset`, `spans_ahead`, `along_for_s` and `respawn_pose` move to native `CourseRuntime`; `CourseData` keeps `mirrored()`, `validate_load()` and tool-only accessors; §1's packed-array rationale (a packed array on `CourseData` served the GDScript tick, where here the runtime copy is native); Key Interfaces.
   - **ADR-0005:** import order (native build before first `--import`); `CourseBuilder` uses the native `CollisionQuery`.
   - **ADR-0006:** the tick order and remote-pose input follow the stage calls; remote events and the host's bots go through `apply_events`, `set_remote`, `snapshots()` and the event pair; the teleport epoch stays with the GDScript sender.
   - **`architecture.md`:** Module Ownership (a "native" column), API Boundaries, Data Flow, Target Hardware (it says GDScript), Required ADRs and ADR Audit numbering, Phase A Sequencing (the toolchain, port and `RaceSim`-skeleton stories).
   - **`docs/registry/architecture.yaml`:**
     - a new `api_decisions` entry for the stage-call boundary;
     - forbidden patterns: per-kart native calls in a GDScript tick loop; per-tick Resource reads in native code; committed DLLs; GDScript script-property reads from C++;
     - `global_random_in_simulation` extended to native code;
     - `referenced_by` on `collision_query` and `kart_snapshot_and_events`.
   - **Config, owner approves:** `project.yaml` `engine.language`, specialists for `native/**` (`godot-gdextension-specialist`), and `commands.test`; the CLAUDE.md Technology Stack line; the EPIC.md header "(GDScript)".
   - **Correction, owner-approved 2026-11-22:** `project.yaml` `engine.language` **stays `"GDScript"`**, with a comment. That key selects the GDScript or C# specialist, so changing it would break specialist routing. Native code is routed through the `specialists` entry for `native/**`. `commands.test` gets the `--check` prefix **in the toolchain story**, once `tools/build_native.sh` exists.
   - **Applied 2026-11-22:** the amendments to ADR-0001 to ADR-0006, `architecture.md` and `docs/registry/architecture.yaml` are made, each as a dated "Amended 2026-11-22 (ADR-0007)" block. The registry supersedes `global_random_in_simulation` with a new entry and adds the `native_simulation_boundary` decision and four forbidden patterns. Stories are not edited here; a producer drafts them.
   - **Numbering:** the asset pipeline ADR, reserved as ADR-0007 elsewhere, is **ADR-0011**. ADR-0008 (room codes), ADR-0009 (anti-gravity) and ADR-0010 (ghost format) are already used in the docs, so the next free number was taken. The references in ADR-0001, ADR-0005 and `architecture.md` are already renumbered.

## Validation Criteria
- `tools/bench_collision.sh` on the native CollisionQuery, with the §8 `--bench` build: the worst layout is ≤ 300 µs p95. Castle ≤ 150 µs p95 is a target; a miss goes to the technical-director.
- The 200 collision tests pass against the native class, and the parity tests pass within the §5 tolerances, with the excluded-count of the boundary band reported.
- `tools/build_native.sh --check` fails on a deliberately stale DLL, on a `bench` DLL in the debug slot and while `bench.lock` exists, shown by negative runs. Boot refuses a missing extension (through `native_boot_check.gd`) and, in an editor build, a source-hash mismatch; the EditorPlugin and the test helper report the same mismatch.
- gdUnit4 drives a native class, `CollisionQuery.create` works from typed code, and a rebuilt debug DLL hot-reloads in the GUI editor (toolchain story evidence).
- **Heap flat:** over 600 `RaceSim` ticks with the caller refreshing its references every tick, the static memory (`OS.get_static_memory_usage()` or the native allocation counter) does not grow. A static grep finds no `memnew`/`new`/`*_create(` in per-tick native methods.
- A stage called out of order is refused (negative test per stage).
- **Determinism:** same-seed runs give identical trace hashes across 3 processes, and the debug and release DLLs give the same trace hash on the same machine. Traces are never compared across PCs.
- A fresh clone, in the documented order (build, then first import), imports `CourseBuilder` output with no error.

## Related
- Amends **ADR-0001** §1, §5, §6 and §9.
- Amends **ADR-0002** (implementation language and call surface; the backend decision stands; supersedes Alternative 5's rejection reason).
- Amends **ADR-0003** (Key Interfaces, `drive(...)` signature, tick order as stages) and **ADR-0004** (runtime methods move to `CourseRuntime`; §1 rationale).
- Amends **ADR-0005** (import order) and **ADR-0006** (tick order and event flow follow the stage calls).
- The asset pipeline ADR is **ADR-0011** (not this ADR).
- Evidence: `prototypes/native-spike/REPORT.md`, `production/qa/evidence/core-rebuild-story-007/collision-bench.md`.
- Tech debt: TD-012 (`docs/tech-debt-register.md`).
