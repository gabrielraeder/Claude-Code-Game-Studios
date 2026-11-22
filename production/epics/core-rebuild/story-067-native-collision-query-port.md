# Story 067: CollisionQuery port to C++ with the GDScript oracle

> **Epic**: Core Rebuild (Phase A)
> **Status**: Ready
> **Layer**: Foundation
> **Type**: Logic
> **Estimate**: L
> **Manifest Version**: N/A (no control manifest yet)
> **Last Updated**: not started (set by /dev-story)

## Context

**GDD**: `design/gdd/track-collision-and-surfaces.md` (§8 Acceptance Criteria)
**Requirement**: ADR-0007 Migration Plan step 2; ADR-0007 §5 (test changes, parity tolerances); ADR-0007 Validation Criteria (native bench, 200 tests, parity); Track Collision AC-20; TD-012 (`docs/tech-debt-register.md`)
**Roadmap step**: `architecture.md` Phase A Sequencing, between steps 2 and 3 (ADR-0007 Ordering Note: the CollisionQuery port follows the toolchain story and gates every other native port). The sequencing table gains this row through the ADR-0007 §12 amendment, which has not been made yet. Epic story numbers are not roadmap item numbers.

**ADR Governing Implementation**: ADR-0007: Native Simulation Core (C++ via GDExtension) (Accepted); behaviour contract ADR-0002: Collision Backend and Surface Attributes (Accepted)
**ADR Decision Summary**: One C++17 GDExtension, `dogworks_core`, owns everything that runs per tick in the simulation, collision queries first. The native `CollisionQuery`, `QueryCursor`, `GroundHit` and `WallHit` keep ADR-0002's behaviour; only the call surface changes: `CollisionQuery` is built by the bound static `create(packed)`, paired with `validate_packed(packed)`, from `TrackCollisionData.pack_native()` plain data, and every bound method guards on a `built` flag. Native code never reads a GDScript script property, and per-tick code never allocates, creates RIDs or builds `String`/`Variant`/`Dictionary` values. The GDScript collision code moves to `tests/oracle/collision/` as a frozen `Oracle*` parity oracle, and the native class is the only implementation under `src/`.

**ADR Version**: ADR-0007 2026-11-22; ADR-0002 2026-11-22

**Engine**: Godot 4.8-beta3 | **Risk**: HIGH
**Engine Notes**: Use the 4.8 `PhysicsDirectSpaceState3D` `*_into` methods and their result classes, bound in godot-cpp from the 4.8-beta3 dump; no Dictionary query forms. Jolt 5.6.0 is pinned; `face_index` needs the project setting the story-006 load check tests for. `physics/3d/run_on_separate_thread=false` stays pinned and asserted. A native class and a GDScript `class_name` with the same name clash ("hides a native class"), and a stale `.godot/global_script_class_cache.cfg` can mask the error, so re-run `--import` after the rename. Spike evidence: `prototypes/native-spike/REPORT.md` (Q2 RID ownership, Q3 speed, Q4 determinism).

---

## Acceptance Criteria

*Each criterion cites its source (ADR-0007 section, Verification Required n, Validation Criteria, or the GDD AC id).*

- [ ] **Native classes, ADR-0002 behaviour.** `CollisionQuery`, `QueryCursor`, `GroundHit` and `WallHit` are native classes in `native/src/collision/`, one class per file pair, with doc comments on every class and bound method. `cast_ground(cursor, origin, dir, max_dist, t, hit) -> bool` and `sweep_walls(cursor, from, to, radius, t, wall_hit) -> bool` keep the ADR-0002 signatures and semantics. Results and base types are registered before the classes that use them, after `DogworksCore` (ADR-0007 §1, §4 Registration and Layout; Key Interfaces).
- [ ] **Factory and validation.** `CollisionQuery.create(packed)` and `CollisionQuery.validate_packed(packed) -> String` call the same C++ validation function: an empty string means valid, otherwise the message names the key. `create` returns null on failure and fails loudly (`ERR_FAIL_NULL`) when the physics server is missing. `.new()` gives an unbuilt object whose every bound method refuses with `ERR_FAIL_COND`, with a test per bound method. `GroundHit`, `WallHit` and `QueryCursor` are built with `.new()` and no arguments. `CollisionBootCheck.checked_query` stays the single GDScript construction site, calls `validate_packed` then `create`, and fills `CheckedQuery.problem` as today (ADR-0007 §4 Construction pattern; Verification Required 2).
- [ ] **Packed data in, no script reads.** `TrackCollisionData` (and each other Resource the native setup consumes, such as the mover, surface and wall-attribute data) gets a `pack_native()` returning packed arrays plus a flat Dictionary of fixed-key scalars, with an integer schema version that both sides assert. A GDScript unit test per Resource pins the packed schema (keys, types, order, units). Native setup checks every key and Variant type and refuses with the key's name on a missing or wrong-typed key, shown by one negative test per key class. Native code never calls `Object::get` on a script property (ADR-0007 §2).
- [ ] **RID teardown.** Constructors create no RIDs; all server work happens in `create()`. One static helper frees bodies, then shapes, then the space, and is called from both `dispose()` and the destructor. Every RID-freeing destructor checks `g_servers_alive` and skips when it is cleared. Destructor and dispose tests replace the GDScript `NOTIFICATION_PREDELETE` tests. A query still alive at quit exits with code 0 and no RID errors (ADR-0007 §4 RID ownership and teardown; §5 Test changes).
- [ ] **Oracle moved and frozen; no name clash.** The GDScript `CollisionQuery`, `QueryCursor`, `GroundHit` and `WallHit` move, in the same change that registers the native classes, to `tests/oracle/collision/` as `OracleCollisionQuery`, `OracleQueryCursor`, `OracleGroundHit` and `OracleWallHit`. No `class_name` under `src/` or `tests/` matches a native class name. `--import` is re-run after the move. A `tools/core_greps.sh` check, fed the native class list from `ClassDB` in a headless run, fails when any `class_name` under `src/` or `tests/` matches a native class name, shown by a negative run. The oracle file headers state that it is frozen at port time (ADR-0007 §5).
- [ ] **Suite re-targeted.** The 200 existing collision tests run against the native classes and pass. Where a test compared bit-exact floats against GDScript-computed expectations, a tolerance is written in the test with its reason. About 286 `.new(` sites across the four classes are reviewed: those passing arguments move to the factory, and the no-argument `GroundHit`, `WallHit` and `QueryCursor` calls stay. The reviewed count is recorded (ADR-0007 §5 Test changes, "The existing collision suite"; Validation Criteria).
- [ ] **Source scans move to `core_greps.sh`.** The two GDScript-source scan tests for `*_create(` (`collision_mover_edge_cases_test.gd`'s SCANNED list and the scan in `collision_movers_test.gd`) are replaced by `tools/core_greps.sh` rules that scan `native/`. Each rule is shown failing on a planted violation (ADR-0007 §5 Test changes).
- [ ] **Parity with the oracle.** New parity tests compare native against `Oracle*` on the story-005 and story-007 fixtures and on the bench mesh. Surface ids, wall-attribute ids, hit/miss and `started_inside` are exact, except inside the band where oracle clearance or penetration depth is below 1e-4 m. Those cases are excluded from the exact check, counted, and the excluded count is printed in the test output. Ray distances are within 1e-5 m, sweep fractions within 1e-3, and normals within 1e-4 rad. A tolerance is never widened silently: any change is written into the test with its reason (ADR-0007 §5 Parity tests; Risks "A float difference"; Validation Criteria).
- [ ] **Static rules for native per-tick code.** `tools/core_greps.sh` extends to `native/` and fails, each shown by a negative run, on: Dictionary query forms; `CollisionQuery` construction outside `CollisionBootCheck`; `*_create(` in per-tick methods; and `memnew`, `new` or `String`/`Variant`/`Dictionary` construction in per-tick methods (ADR-0007 Migration Plan step 2; Implementation Guidelines; Validation Criteria "A static grep finds no `memnew`/`new`/`*_create(`").
- [ ] **No allocation in the tick.** Over 600 benchmark ticks, `Performance.OBJECT_COUNT` is unchanged and `OS.get_static_memory_usage()` (or the native allocation counter) does not grow, and a `--verbose` run reports no RID leak at exit (ADR-0007 §4 "No allocation after build"; Implementation Guidelines; story 007 AC "No allocation").
- [ ] **Budget gate, TD-012 closes.** `tools/bench_collision.sh` runs on the native `CollisionQuery` with the §8 `--bench` build swapped in, and restored after. Every story-007 layout and section, including the TD-012 worst case (12 karts in reach of 5 spinning solid movers), is ≤ 300 µs p95 on the owner's PC. The re-measured per-crossing cost and crossing count are reported. TD-012 is marked resolved in `docs/tech-debt-register.md` with the measured numbers. A miss fails the story (ADR-0007 §10 Pass line; Validation Criteria; Migration Plan step 2; Track Collision AC-20).
- [ ] **Castle target.** The realistic Castle layout is reported against the 150 µs p95 target. If it misses 150 µs but passes 300 µs, the technical-director's decision on whether it stands is recorded in the evidence before the story closes (ADR-0007 §10; Validation Criteria).

---

## Implementation Notes

- **Implementer:** `godot-gdextension-specialist` with a turn budget per run and a `STATE.md` checkpoint in `production/qa/evidence/core-rebuild-story-067/` (ADR-0007 Implementation Guidelines; Risks "An agent turn budget").
- **Gate for every other native port:** no other native story (068 and on) starts implementation until the budget criterion passes (ADR-0007 Risks "Unproven projection").
- **The port is a translation, not a redesign.** Story 007's optimisations (solid-slot list, pose cache per `t`, lazy omega, overlap pass first, Newton sweep, fail-closed Newton cap, touch rule, unsafe-point retry of 0.001 m) carry over, as ADR-0002 behaviour. A change in behaviour shows up as a parity failure and is investigated, not absorbed.
- **Projection to beat:** about 110–170 µs p95 in the worst layout (ADR-0007 §10). It is a projection, not a measurement.
- **Fresh-clone re-check.** Re-run the story-066 fresh-clone import check with an import-time call to the native `CollisionQuery` (ADR-0007 Verification Required 6), since `CourseBuilder` will use it.
- **Moving files out of `src/` deletes them there.** The move of the four GDScript classes to `tests/oracle/collision/` is a file deletion under `src/`, so it is asked of the owner when the story reaches it (CLAUDE.md: file deletions are asked every time). Use `git mv` so history follows.
- **What stays GDScript:** `TrackCollisionData`, `MoverDef`, `SurfaceSet`/`SurfaceType`, `WallAttr`/`WallAttrSet` and `CollisionBootCheck` (ADR-0007 §1 table).
- Every native test suite calls the story-066 shared hash-check helper in `before()`.

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 066: the toolchain, the hashes and `--check`.
- Story 068: `RaceSim` and the per-stage boundary; collision is called per object in this story.
- Story 012: kart body and drive budget.
- Story 008: the generator-baked Castle mesh re-run of the bench (added when story 008 lands).
- The ADR-0002 §12 amendment text (implementation language, `create(packed)`, Key Interfaces).

---

## Files (planned)

- `native/src/collision/collision_query.{h,cpp}`, `query_cursor.{h,cpp}`, `ground_hit.{h,cpp}`, `wall_hit.{h,cpp}` (new); `native/src/register_types.cpp` (edited)
- `src/core/collision/collision_query.gd`, `query_cursor.gd`, `ground_hit.gd`, `wall_hit.gd` (moved to `tests/oracle/collision/oracle_*.gd`, renamed, plus `.uid`)
- `src/core/collision/track_collision_data.gd`, `mover_def.gd`, `wall_attr_set.gd` and the surface set (`pack_native()`); `src/core/collision/collision_boot_check.gd` (factory calls)
- `tests/unit/collision/*_test.gd` (re-targeted), `collision_fixtures.gd`; new parity and pack-schema tests (plus `.uid`)
- `tools/core_greps.sh` (native rules, name-clash check), `tools/bench_collision.gd`, `tools/bench_collision.sh` (native run)
- `docs/tech-debt-register.md` (TD-012 resolved)
- `production/qa/evidence/core-rebuild-story-067/` (STATE.md, bench report and runs, parity output with excluded counts, gdUnit4 log, negative grep runs)

## QA Test Cases

*N/A — QL-STORY-READY not run in this autonomous drafting pass; implement against the Acceptance Criteria above.*

---

## Test Evidence

**Story Type**: Logic
**Required evidence**: automated unit tests in `tests/unit/collision/` (re-targeted suite, parity and pack-schema tests), all passing; the native bench report and runs retained in `production/qa/evidence/core-rebuild-story-067/`
**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: `production/epics/core-rebuild/story-066-native-toolchain.md`
- Unlocks: `production/epics/core-rebuild/story-068-racesim-skeleton.md`
