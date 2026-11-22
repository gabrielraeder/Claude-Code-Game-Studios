# Story 068: RaceSim skeleton: stages, buffers, stage timers, slot roles

> **Epic**: Core Rebuild (Phase A)
> **Status**: Ready
> **Layer**: Foundation
> **Type**: Logic
> **Estimate**: M
> **Manifest Version**: N/A (no control manifest yet)
> **Last Updated**: not started (set by /dev-story)

## Context

**GDD**: N/A (tick boundary; no GDD system of its own). It carries the tick order of `design/gdd/kart-physics.md` through ADR-0003 §4.
**Requirement**: ADR-0007 Migration Plan step 3; ADR-0007 §3 (stage table, slot roles, race flow calls, double buffers and caller contract, inputs and rules, stage timing); ADR-0007 Validation Criteria (heap flat over 600 `RaceSim` ticks; stage out of order refused; static grep)
**Roadmap step**: `architecture.md` Phase A Sequencing, before step 3 (ADR-0007 Ordering Note: the `RaceSim` skeleton comes before story 009 and story 012). The sequencing table gains this row through the ADR-0007 §12 amendment, which has not been made yet. Epic story numbers are not roadmap item numbers.

**ADR Governing Implementation**: ADR-0007: Native Simulation Core (C++ via GDExtension) (Accepted); tick order from ADR-0003 §4 and ADR-0006 (Accepted)
**ADR Decision Summary**: One C++17 GDExtension, `dogworks_core`, owns everything that runs per tick in the simulation. The native `RaceSim` owns all simulation state and runs eight stage calls per tick, in ADR-0003 §4 order, refusing any call out of order in debug and release builds. The GDScript composition root does the network I/O between the calls but owns no state. Outputs (snapshots, progress, the event pair and stage timers) are double-buffered packed arrays, A on even ticks and B on odd, so a held array is a never-corrupted copy-on-write snapshot. Slot roles (local, bot, remote) are fixed at setup; `place` and `hold` run between ticks only. `RaceSim` is built by the bound static `create(setup_packed)` factory, and every bound method guards on a `built` flag.

**ADR Version**: ADR-0007 2026-11-22

**Engine**: Godot 4.8-beta3 | **Risk**: HIGH
**Engine Notes**: Packed arrays are copy-on-write: a returned array is a reference-counted alias, and C++ writing through `ptrw()` while GDScript holds it detaches it (the holder keeps the old data and native pays a full copy). A packed argument that C++ writes through `ptrw()` also detaches, so there are no output-parameter packed arrays. GDExtension class constants are integer-only, so `SIM_DT` is a C++ `constexpr` and `begin_tick` takes the tick number, not a time. `OBJECT_COUNT` cannot see packed arrays; measure the heap with `OS.get_static_memory_usage()` or a native allocation counter. Each crossing costs about 0.2 µs (spike).

---

## Acceptance Criteria

*Each criterion cites its source (ADR-0007 section, Verification Required n, or Validation Criteria).*

- [ ] **Factory and setup.** `RaceSim.create(setup_packed)` and `RaceSim.validate_packed(setup_packed) -> String` call the same C++ validation function; `create` returns null on failure. The setup data carries the schema version, slot count, `slot_roles`, per-consumer seeds and the event capacity, and a missing or wrong-typed key is refused with the key's name (a negative test per key). `.new()` gives an unbuilt object whose every bound method refuses with `ERR_FAIL_COND`, with a test per bound method. All buffers are sized in `create()` (ADR-0007 §3 Slot roles; §4 Construction pattern, `RaceSim.create`; §2).
- [ ] **The eight stages, as bound.** `begin_tick(tick: int)`, `apply_events(headers: PackedInt32Array, payload: PackedFloat32Array)`, `step_drive(driver_input_packed: PackedFloat32Array)`, `step_bodies()`, `set_remote(remote_snaps_packed: PackedFloat32Array, contact_eligible_mask: int)`, `step_contact()`, `step_progress_items_hazards()` and `end_tick()` are bound with exactly the §3 signatures. `begin_tick` computes `t = tick * SIM_DT` in native code from `constexpr double SIM_DT = 1.0 / SIM_HZ`. Stage bodies are empty hooks with a doc comment naming the stories that fill them (ADR-0007 §3 stage table; §4 `SIM_DT`; Key Interfaces "binding"; Migration Plan step 3).
- [ ] **Order asserted.** A stage called out of order is refused with `ERR_FAIL` in both the debug and the release DLL, and the simulation state is unchanged by the refused call. There is one negative test per stage, and the release-DLL case is shown by one recorded run on the release build (ADR-0007 §3 "cannot reorder the stages"; §4 Errors "not debug-only"; Validation Criteria "A stage called out of order is refused (negative test per stage)").
- [ ] **Slot roles.** `slot_roles` is fixed at `create()` and has no setter. `step_drive` takes exactly one row per local slot, in slot order, and refuses a wrong row count or width. Bot slots are marked for native decisions (empty hook). Remote slots have no body. `set_remote` copies the remote poses into native structs and keeps no reference to the array. A remote slot is contact-eligible only when its bit is set in `contact_eligible_mask`, which a test reads back through a debug accessor or the end-of-tick snapshot (ADR-0007 §3 Slot roles; Inputs and rules).
- [ ] **Race flow calls.** `place(slot, pose_packed)` and `hold(slot_mask: int)` are accepted only between `end_tick()` and the next `begin_tick()`, and refused inside a tick (negative tests). `place` marks that slot's snapshot `teleported`. A `hold` mask is applied at the next `begin_tick`: held slots skip body integration, while their driver rows still reach the `DriveState` start-logic hook. `hold` is not the FROZEN state (ADR-0007 §3 Race flow calls).
- [ ] **Double-buffered outputs.** `snapshots() -> PackedFloat32Array`, `progress() -> PackedFloat32Array`, `stage_usec() -> PackedFloat64Array`, `event_headers() -> PackedInt32Array` and `event_payload() -> PackedFloat32Array` each come from buffer A on even ticks and buffer B on odd ticks, swapped in `end_tick()`. A test holds tick N's arrays across tick N+1 and shows them intact. Per-slot accessors (`snapshot_position(slot)`, `snapshot_basis(slot)` and the rest the layout needs) return one kart's values without reading the whole array (ADR-0007 §3 "Outputs are double-buffered in C++").
- [ ] **Event pair and overflow.** Event capacity is fixed at setup; `event_count() -> int` gives the rows used. On overflow the extra events are dropped and `events_overflowed() -> bool` stays set until the next `end_tick()`, shown by a test that fills past capacity. `end_tick()` clears the working event buffer (ADR-0007 §3 "Events are a pair"; stage 8).
- [ ] **Stage timers.** `stage_usec()` returns one element per stage call (8) for the last tick, recorded by native timers into a preallocated array, always on, double-buffered, and closed in `end_tick()`. Reading it allocates nothing in the tick (ADR-0007 §3 Stage timing).
- [ ] **Caller contract.** C++ reads input arrays through `ptr()` and never stores them as members. No bound method writes through a packed argument. The caller contract (refresh each tick, never write through a returned array, never pass one back in) is written in the bound methods' docs (ADR-0007 §3 Caller contract; Inputs and rules).
- [ ] **Heap flat.** Over 600 `RaceSim` ticks with a caller that refreshes its references every tick, static memory (`OS.get_static_memory_usage()` or the native allocation counter) does not grow. A second run, with a consumer holding one output array for the whole run, costs one copy for that array and then stays flat (ADR-0007 Validation Criteria "Heap flat"; Verification Required 5).
- [ ] **No allocation in stage code.** The `tools/core_greps.sh` native rules from story 067 cover `native/src/race/`: no `memnew`, `new`, `*_create(` or `String`/`Variant`/`Dictionary` construction in any stage method, and no `rand()`, `<random>`, `std::random_device`, global `randf` or unordered-container iteration. Each is shown by a negative run (ADR-0007 Validation Criteria static grep; §4 Randomness; Implementation Guidelines).
- [ ] **Layouts fixed and recorded.** The exact layouts (fields per slot in `snapshots()` and `progress()`, the driver-row columns steer, throttle, brake, drift, hop and item-use, the event header row of slot, kind and payload offset, and the payload encoding per kind including `pickup` and item hit confirmations) are defined once as named C++ constants, mirrored by one GDScript layout file, and pinned by a test on each side. The layouts are recorded as an amendment to ADR-0003's Key Interfaces (ADR-0007 §3 "The exact layout is fixed by the `RaceSim` story"; Key Interfaces).

---

## Implementation Notes

- **Implementer:** `godot-gdextension-specialist` with a turn budget per run and a `STATE.md` checkpoint in `production/qa/evidence/core-rebuild-story-068/` (ADR-0007 Implementation Guidelines; Risks "An agent turn budget").
- **Starts only after story 067's budget criterion passes** (ADR-0007 Risks "Unproven projection").
- **Skeleton, not systems.** Stage bodies stay empty: drive (009, 011, 016–020), bodies (010, 013–015, 021), contact (022–023), progress, items and hazards (031–032, 051–053), bots (054). Each of those stories fills its hook. KartSnapshot fields that no system writes yet are zero and documented as such.
- **The ADR-0003 amendment** (layouts in Key Interfaces) edits an Accepted ADR. Draft it in the story and ask the owner before writing it.
- **Native class names:** `RaceSim` only, unless the layout needs more. Run the story-067 `class_name` clash check after registering.
- Tests that depend on tick order go through `RaceSim` from here on (ADR-0007 §3).
- Every native test suite calls the story-066 shared hash-check helper in `before()`.

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 050: the GDScript composition root that calls the stages and does the network I/O between them.
- Stories 043–048: `NetEventCodec`, `SnapshotCodec`, `RemoteKartSet.sample_into` feeding `set_remote`.
- Story 024: determinism (same-seed trace hashes across 3 processes, debug vs release DLL) through `RaceSim`.
- Story 012: the first-slice budget through the stages.
- Any stage's simulation content (see Implementation Notes).

---

## Files (planned)

- `native/src/race/race_sim.{h,cpp}` and the layout constants header (new); `native/src/register_types.cpp` (edited)
- a GDScript layout mirror under `src/core/` (new, plus `.uid`; exact name is the implementer's call)
- `tests/unit/race/` suites: factory, stage order, slot roles, race flow, buffers, events, timers, heap, layouts (new, plus `.uid`)
- `tools/core_greps.sh` (native rules extended to `native/src/race/`)
- `docs/architecture/adr-0003-kart-physics-model.md` Key Interfaces (amendment, owner-approved at the time)
- `production/qa/evidence/core-rebuild-story-068/` (STATE.md, gdUnit4 log, heap runs, release-DLL order run, negative grep runs)

## QA Test Cases

*N/A — QL-STORY-READY not run in this autonomous drafting pass; implement against the Acceptance Criteria above.*

---

## Test Evidence

**Story Type**: Logic
**Required evidence**: automated unit tests in `tests/unit/race/`, all passing; heap and release-DLL runs retained in `production/qa/evidence/core-rebuild-story-068/`
**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: `production/epics/core-rebuild/story-067-native-collision-query-port.md`
- Unlocks: `production/epics/core-rebuild/story-009-core-vehicle-data-and-kart-types.md`, `production/epics/core-rebuild/story-012-first-slice-budget.md`
