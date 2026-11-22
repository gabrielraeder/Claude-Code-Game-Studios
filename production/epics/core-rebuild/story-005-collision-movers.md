# Story 005: Analytic moving colliders

> **Epic**: Core Rebuild (Phase A)
> **Status**: Complete
> **Layer**: Foundation
> **Type**: Logic
> **Estimate**: M
> **Manifest Version**: N/A (no control manifest yet)
> **Last Updated**: 2026-11-22

## Context

**GDD**: `design/gdd/track-collision-and-surfaces.md` (§8 Acceptance Criteria)
**Requirement**: Track Collision AC-12 to AC-15; ADR-0002 Validation Criteria (rotating mover point velocity, mover blocks or clears at t); ADR-0002 v5.1 `MoverDef.solid`
**Roadmap step**: `architecture.md` Phase A Sequencing step 2-3 (spike follow-through; roadmap item 022 implements `CollisionQuery`, ADR-0002 Migration Plan). Epic story numbers are not roadmap item numbers.

**ADR Governing Implementation**: ADR-0002: Collision Backend and Surface Attributes (Accepted)
**ADR Decision Summary**: Jolt, used only through `PhysicsServer3D`: a RefCounted `CollisionQuery` owns a private space and server-created shapes and bodies, freed in a fixed order; ground is one concave shape whose surface id comes from the triangle `face_index`; walls are one body with one shape per wall attribute on their own layer; queries use the 4.8 non-allocating `_into` methods; moving colliders are evaluated analytically from keyframed pose curves. Budget: collision <= 0.3 ms p95 per tick for 12 karts (spike: 0.06 ms median).

**ADR Version**: ADR-0002 2026-11-22

**Engine**: Godot 4.8-beta3 | **Risk**: HIGH
**Engine Notes**: Jolt 5.6.0 in 4.8. Unit tests are valid only once the main project pins Jolt. `face_index` needs the project setting the load check tests for. Use the 4.8 `_into` query methods (non-allocating); no Dictionary query forms in per-tick code. Probe evidence: `prototypes/collision-spike/out/probe_adr2.txt`.

---

## Acceptance Criteria

*Each criterion cites its source (GDD AC id, ADR Validation Criteria, or `architecture.md`).*

- [x] **Pose curve.** A box mover keyed 0 -> 10 m along +X over 2 s: `mover_pose(id, 1.0)` origin x = 5.0 +/- 1e-4, and `mover_pose(id, period + 1.0)` equals `mover_pose(id, 1.0)`; a mover blocks or clears at time t as its curve says (Track Collision AC-12; ADR-0002 Validation Criteria).
- [x] **Point velocity.** A mover rotating 90° about +Y in 1 s: `mover_point_velocity` at 2 m from the axis has magnitude π/2 × 2 = 3.1416 +/- 0.001 m/s, and a sweep hit on it reports that velocity at the contact (Track Collision AC-13).
- [x] **Mover overlap.** A mover that moves into a stationary kart's sphere sets `started_inside`; with a static wall and a mover both overlapping, the deeper one wins; a mover with `solid = false` never blocks (Track Collision AC-14; ADR-0002 v5/v5.1).
- [x] **One evaluator.** Simulation and presentation calls at the same `t` return bit-identical poses; grep finds no pose interpolation of `key_pos` outside `src/core/collision/` (Track Collision AC-15).

---

## Implementation Notes

> **Note from story 003 review (LP):** add mover checks to `TrackCollisionData.layout_error()` (or a sibling) before evaluation: `id >= 1` and unique, `period > 0`, key arrays of equal length with ascending `key_t` in `[0, period)`, extents valid for the shape. The mover test in `cast_ground` must keep writing all `GroundHit` fields on a hit (nearest wins) and leave `out` untouched on a miss; rename `_t` to `t`.

- Movers are evaluated analytically from keyframed pose curves; no physics body is stepped (ADR-0002 Summary).
- Time comes from the caller (synced race time per ADR-0001 §5); never read a clock inside the query.

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 021: carrying a kart on a platform.
- Story 052: re-authoring the Castle hazards on movers.

---

## Files

- `src/core/collision/mover_def.gd`, `track_collision_data.gd`, `collision_query.gd`, `ground_hit.gd`, `wall_hit.gd`
- `tests/unit/collision/collision_movers_test.gd` (new), `collision_fixtures.gd`, `collision_query_ground_test.gd` (one fixture made valid)

---

## QA Test Cases

*N/A — QL-STORY-READY not run in this autonomous drafting pass; implement against the Acceptance Criteria above.*

---

## Test Evidence

**Story Type**: Logic
**Required evidence**: `tests/unit/collision/collision_movers_test.gd` — must exist and pass, with at least one test per acceptance criterion (`qa.level: full`)
**Status**: [x] Created: tests/unit/collision/collision_movers_test.gd (60 tests; suite 140/140, production/qa/evidence/core-rebuild-story-005/gdunit4-final.log; mutation-wrap/t/rot logs)

---

## Dependencies

- Depends on: `production/epics/core-rebuild/story-004-collision-query-walls.md`
- Unlocks: `production/epics/core-rebuild/story-006-collision-load-checks-and-mirror.md`, `production/epics/core-rebuild/story-021-kart-moving-platforms.md`

## Completion Notes
**Completed**: 2026-11-22
**Criteria**: 4/4 passing (gdUnit4 140/140; mutations wrap/t/rot fail their target tests; parse check clean; no regression needed)
**Deviations**: Worst-case cost 0.63 ms median / 1.08 ms p95 per tick (12 karts near 5 spinning movers) exceeds the 0.3 ms collision budget: logged TD-012, measured and optimised in story 007. `MoverDef` gained `surface_id` / `wall_attr_id` (defaults road / standard; GDD C13 values still the owner's). `FORMAT_VERSION` kept at 1 (nothing baked yet).
**Test Evidence**: tests/unit/collision/collision_movers_test.gd; production/qa/evidence/core-rebuild-story-005/ (gdunit4-final.log, parse-check-final.txt, mutation-*.log)
**Reviewed by**: lead-programmer (LP-CODE-REVIEW: CONCERNS, revised); qa-lead (QL-TEST-COVERAGE: GAPS, closed); godot-gdscript-specialist engine check (wrap bug found and fixed)

## Calls beyond the design
- Shapes centred on the pose origin; loop segment from the last key back to the first; at least 2 keys · `mover_def.gd`, `collision_query.gd` · kept 2026-11-22
- A mover is frozen at pose(t) for the whole query; static geometry wins exact ties · `collision_query.gd` · kept 2026-11-22
- Mover tops report the mover's `surface_id` (default 0 road) and walls its `wall_attr_id` (default 0 standard) · `mover_def.gd` · kept 2026-11-22 (C13 values open)
- Analytic sweep by golden-section + bisection, 0.1 mm tolerance, 64-step cap; sphere culling · `collision_query.gd` · kept 2026-11-22 (optimisation in story 007)
