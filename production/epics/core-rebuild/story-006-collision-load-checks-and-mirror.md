# Story 006: Collision load checks, mirror and boundary greps

> **Epic**: Core Rebuild (Phase A)
> **Status**: Complete
> **Layer**: Foundation
> **Type**: Logic
> **Estimate**: S
> **Manifest Version**: N/A (no control manifest yet)
> **Last Updated**: 2026-11-22

## Context

**GDD**: `design/gdd/track-collision-and-surfaces.md` (§8 Acceptance Criteria)
**Requirement**: Track Collision AC-17, AC-18; ADR-0002 Validation Criteria (mirror, face-index load check, Dictionary grep); ADR-0001 §7 (mirror is a reflection at track load)
**Roadmap step**: `architecture.md` Phase A Sequencing step 2-3 (spike follow-through; roadmap item 022 implements `CollisionQuery`, ADR-0002 Migration Plan). Epic story numbers are not roadmap item numbers.

**ADR Governing Implementation**: ADR-0002: Collision Backend and Surface Attributes (Proposed); ADR-0001: Simulation Conventions and Code Layout (Accepted)
**ADR Decision Summary**:
- ADR-0002: Jolt, used only through `PhysicsServer3D`: a RefCounted `CollisionQuery` owns a private space and server-created shapes and bodies, freed in a fixed order; ground is one concave shape whose surface id comes from the triangle `face_index`; walls are one body with one shape per wall attribute on their own layer; queries use the 4.8 non-allocating `_into` methods; moving colliders are evaluated analytically from keyframed pose curves. Budget: collision <= 0.3 ms p95 per tick for 12 karts (spike: 0.06 ms median).
- ADR-0001: Godot Y-up, -Z forward, metres; the synced race time is authoritative and the 60 Hz tick follows it with a defined catch-up policy; a fixed step order and one seeded random stream per consumer; our own interpolation with a teleport flag; mirror mode is a proper reflection at track load; the frozen 2.5D game lives in `src/legacy/`, shared data classes in `src/data/`, new code in new folders.

**ADR Version**: ADR-0002 2026-11-22; ADR-0001 2026-11-21

**Engine**: Godot 4.8-beta3 | **Risk**: HIGH
**Engine Notes**: Jolt 5.6.0 in 4.8. Unit tests are valid only once the main project pins Jolt. `face_index` needs the project setting the load check tests for. Use the 4.8 `_into` query methods (non-allocating); no Dictionary query forms in per-tick code. Probe evidence: `prototypes/collision-spike/out/probe_adr2.txt`. Tick settings are pinned (`physics_ticks_per_second=60`, `max_physics_steps_per_frame=8`, `physics_interpolation=false`). Since 4.4 every script has a `.uid` sidecar. 4.8: strings can no longer be comments; a script can no longer inherit its own inner classes.

---

## Acceptance Criteria

*Each criterion cites its source (GDD AC id, ADR Validation Criteria, or `architecture.md`).*

- [x] **Face-index load check.** Building a query fails with a named reason when the face-index setting is off; the test sets the setting, awaits a frame, builds a new query, then restores the setting (Track Collision AC-18; ADR-0002 Validation Criteria).
- [x] **Mirror.** A mirrored fixture returns mirrored hit points (x -> -x) with the same surface and wall-attr ids, and `mirrored()` leaves the source resource unchanged (compared before and after) (Track Collision AC-17; ADR-0001 §7).
- [x] **Boot asserts.** Loading refuses, with a named reason, a `TrackCollisionData` whose surface or wall-attr id is not in the core registries, and a project whose physics engine or tick settings differ from ADR-0001 §5 / ADR-0002.
- [x] **Grep.** `tools/core_greps.sh` (new, prints one PASS/FAIL line per rule, exits non-zero on a failure) finds no Dictionary query forms in per-tick code under `src/core/` and `src/gameplay/` (ADR-0002 Validation Criteria), and is wired into `tools/regression.sh`.

---

## Implementation Notes

> **From the story 005 review (LP):** put a `MoverDef.mirrored()` next to its fields (keys map quaternion (x, y, z, w) to (x, -y, -z, w), positions x -> -x, ids copied) and test it by walking `get_property_list()` over every `@export` field so a future field cannot be silently dropped. The load-time `probe_point` cast takes a `t`: specify the probe time (t = 0) and the authoring rule that no solid mover stands over the probe point at that time. Degenerate exact-centre normals (fixed RIGHT) are not mirror-symmetric: keep them out of mirror-equivalence tests.

> **Note from story 003 review (LP):** the id load check must be a blocking assert (a face with `SURFACE_NONE` = -1 would otherwise reach Driving), and the probe cast at `probe_point` must run on every load, including an empty query (bad data builds no geometry and only `push_error`s). Consider a `has_geometry()` accessor for a precise boot message.
> **Note from story 003 engine check:** add a save/load round-trip test of `TrackCollisionData` to a binary `.res` (typed `Array[PackedVector3Array]` and `Array[MoverDef]`), comparing the arrays after reload; ADR-0005 bakes these.

- Mirror is applied once at track load, never per query (ADR-0001 §7).
- Later stories append their boundary greps to `tools/core_greps.sh`; it emits observations per rule, not a verdict on the story (CLAUDE.md helper-script rule).
- Follow `.claude/rules/godot-refcount.md` for any new `connect(`.

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 040: mirror applied by `TrackLoader` at package load.
- Story 028: Course Data's mirror.

---

## Files

- `src/core/collision/collision_boot_check.gd` (new, plus `.uid`): `CollisionBootCheck` with pinned settings, `assert_boot_settings()`, `load_error()`, `checked_query()` and `CheckedQuery`
- `src/core/collision/collision_query.gd`: `has_geometry()`, `probe_error()`, `PROBE_T`, `FACE_INDEX_SETTING`
- `src/core/collision/track_collision_data.gd`: `id_error()` (split into surface / wall / mover helpers), `mirrored()`
- `src/core/collision/mover_def.gd`: `mirrored()`
- `tools/core_greps.sh` (new), `tools/regression.sh` (7 checks, `core_greps` first)
- `tests/unit/collision/collision_fixtures.gd`, `tests/unit/collision/collision_load_and_mirror_test.gd` (new, 39 tests, plus `.uid`)
- `.godot/global_script_class_cache.cfg` (rebuilt by `--import`)
- Docs: ADR-0001 §5 (boot assertion clarified), ADR-0005 (check I17), stories 040, 050, 063 (use `checked_query`, call `assert_boot_settings()`)

## QA Test Cases

*N/A — QL-STORY-READY not run in this autonomous drafting pass; implement against the Acceptance Criteria above.*

---

## Test Evidence

**Story Type**: Logic
**Required evidence**: `tests/unit/collision/collision_load_and_mirror_test.gd` — must exist and pass, with at least one test per acceptance criterion (`qa.level: full`)
**Status**: [x] Created: tests/unit/collision/collision_load_and_mirror_test.gd (39 tests; full suite 179/179, production/qa/evidence/core-rebuild-story-006/gdunit4-final.log)

---

## Dependencies

- Depends on: `production/epics/core-rebuild/story-005-collision-movers.md`
- Unlocks: `production/epics/core-rebuild/story-007-collision-benchmark.md`, `production/epics/core-rebuild/story-008-legacy-extractor-and-test-mesh.md`, `production/epics/core-rebuild/story-028-course-data-schema-and-mirror.md`

## Completion Notes
**Completed**: 2026-11-22
**Criteria**: 4/4 passing (face-index load check; mirror of ground, walls and movers with ids kept and the source unchanged; boot and load refusals with named reasons; `tools/core_greps.sh` wired into `tools/regression.sh`, now 7 checks)
**Deviations**: None. Added after review: `CollisionBootCheck.checked_query()` is the only way `src/` builds a `CollisionQuery` (grep-enforced); grep errors (exit >= 2) now FAIL instead of passing silently. Stories 040, 050 and 063 carry the rule.
**Test Evidence**: production/qa/evidence/core-rebuild-story-006/ (gdunit4-final.log 179/179, 0 orphans; parse-check-final.txt 6/6; core-greps.log; regression-core-greps-review.txt; mutation-winding, -ids, -probe, -settings, -grep, -grep-error, -checked-query logs, each caught)
**Reviewed by**: lead-programmer (LP-CODE-REVIEW: CONCERNS, fixed); qa-lead (QL-TEST-COVERAGE: GAPS, closed); godot-gdscript-specialist engine check (1 defect, fixed)
Run result: N/A — collision load checks, mirror and greps run headless inside the core; nothing reaches the screen until the Castle port (story 050+)

## Calls beyond the design
- Probe cast length is a parameter (`probe_max_drop`, tests 2.0 m); the real value comes from ADR-0005 TrackImportLimits (story 036) · kept 2026-11-22
- Probe casts straight down from `probe_point` at t = 0 and must hit static ground; a hit on a solid mover rejects the track (`CollisionQuery.probe_error`) · kept 2026-11-22
- Id check also rejects a wall-attr id shared by two wall shapes and an unregistered `probe_surface_id`; registry entries outside 0..255 are ignored (`TrackCollisionData.id_error`) · kept 2026-11-22
- Boot settings also check `physics_jitter_fix = 0.0` and `run_on_separate_thread = false`; ticks and max steps read from `Engine`; `assert_boot_settings()` returns the problem so a release build can refuse to start (`collision_boot_check.gd`) · kept 2026-11-22
- `has_geometry()` counts non-solid movers; the probe message says so (`collision_query.gd`) · kept 2026-11-22
- `checked_query()` returns inner class `CollisionBootCheck.CheckedQuery` (query, problem); grep forbids `CollisionQuery.new(` under `src/` outside `collision_boot_check.gd` (`tools/core_greps.sh`) · kept 2026-11-22
- Forbidden-forms grep also lists `collide_shape(` and `Physics(Ray|Point)QueryParameters3D.create(` (the Point form may not exist in 4.8; harmless) · kept 2026-11-22
- Tests restore the pinned values in `after_test()` rather than saving and restoring prior state; `mirrored()` copies packed arrays, keeps null movers null and leaves primitive extents unchanged · kept 2026-11-22
