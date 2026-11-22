# Story 007: Collision benchmark (<= 0.3 ms p95, 12 karts)

> **Epic**: Core Rebuild (Phase A)
> **Status**: Complete
> **Layer**: Foundation
> **Type**: Integration
> **Estimate**: S
> **Manifest Version**: N/A (no control manifest yet)
> **Last Updated**: 2026-11-22

## Context

**GDD**: `design/gdd/track-collision-and-surfaces.md` (§8 Acceptance Criteria)
**Requirement**: Track Collision AC-20; ADR-0002 Validation Criteria (benchmark); `architecture.md` Performance Budgets (track collision queries 0.3 ms p95)
**Roadmap step**: `architecture.md` Phase A Sequencing step 2-3 (spike follow-through; roadmap item 022 implements `CollisionQuery`, ADR-0002 Migration Plan). Epic story numbers are not roadmap item numbers.

**ADR Governing Implementation**: ADR-0002: Collision Backend and Surface Attributes (Accepted)
**ADR Decision Summary**: Jolt, used only through `PhysicsServer3D`: a RefCounted `CollisionQuery` owns a private space and server-created shapes and bodies, freed in a fixed order; ground is one concave shape whose surface id comes from the triangle `face_index`; walls are one body with one shape per wall attribute on their own layer; queries use the 4.8 non-allocating `_into` methods; moving colliders are evaluated analytically from keyframed pose curves. Budget: collision <= 0.3 ms p95 per tick for 12 karts (spike: 0.06 ms median).

**ADR Version**: ADR-0002 2026-11-22

**Engine**: Godot 4.8-beta3 | **Risk**: HIGH
**Engine Notes**: Jolt 5.6.0 in 4.8. Unit tests are valid only once the main project pins Jolt. `face_index` needs the project setting the load check tests for. Use the 4.8 `_into` query methods (non-allocating); no Dictionary query forms in per-tick code. Probe evidence: `prototypes/collision-spike/out/probe_adr2.txt`.

---

## Acceptance Criteria

*Each criterion cites its source (GDD AC id, ADR Validation Criteria, or `architecture.md`).*

- [x] **Budget.** In a running tree, from `_physics_process`, 12 karts' worst-case query set per tick (3 wall sweeps, 4 ground rays and the rest check each, ADR-0002 Performance Implications) on a mesh of at least 48k triangles costs <= 0.3 ms p95 on the owner's PC; release export when 4.8 export templates exist, the debug editor build accepted as an upper bound until then (Track Collision AC-20; `architecture.md` Performance Budgets).
- [x] **Flat per section.** The p95 is reported per track section (at least 4 sections including any branch) and no section exceeds the budget (`architecture.md` rule: no query scans a whole route or track).
- [x] **No allocation.** `Performance.OBJECT_COUNT` is unchanged across 600 benchmark ticks; no server `*_create` call is reachable from per-tick methods (static test); a `--verbose` run reports no RID leak at exit. (Reworded 2026-11-22, owner-approved: Godot 4.8-beta3 exposes no server RID count.)
- [x] **Record.** `production/qa/evidence/core-rebuild-story-007/collision-bench.md` records machine, build, median and p95, and the command; a re-run on the generator-baked Castle mesh is added when story 008 lands.

---

## Implementation Notes

> **From story 005 (TD-012):** the analytic mover sweep measured 0.63 ms median / 1.08 ms p95 per tick with 12 karts all near 5 spinning movers (scratch benchmark). Measure a realistic layout (Castle's hazards: drawbridge, portcullis, barrels) and the worst case; if over 0.3 ms p95, replace the golden-section search with closed-form sphere-vs-capsule/cylinder/box sweeps or cut steps, and re-run. LP's candidates: cache each mover's pose and inverse per `t` (deterministic), compute omega lazily only on a hit, run an overlap pass before any mover sweep, closed-form sphere-vs-capsule/cylinder sweeps.

- Mesh: the spike's generator-baked mesh under `prototypes/collision-spike/` loaded by the tool, or a code-built fixture of comparable size; do not wait on story 008.
- Stage timing in the style of `tools/profile_tick.gd` (`Time.get_ticks_usec()` around the query block).

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 012: kart body + drive budget.
- Story 024: contact budget.

---

## Files

- `tools/bench_collision.gd`, `tools/bench_collision.sh`, `tools/bench_track_fixture.gd` (new, plus `.uid`)
- `src/core/collision/collision_query.gd` (TD-012 optimisation: solid-slot list, pose cache per t, lazy omega, overlap pass first, Newton sweep; fail-closed cap; touch rule; unsafe-point retry)
- `src/core/collision/query_cursor.gd` (mask set once; docs)
- `tests/unit/collision/collision_mover_sweep_equivalence_test.gd`, `collision_mover_edge_cases_test.gd`, `collision_unsafe_point_retry_test.gd` (new, plus `.uid`); `collision_movers_test.gd` (comments)
- `production/qa/evidence/core-rebuild-story-007/` (report, runs, logs, mutants)

## QA Test Cases

*N/A — QL-STORY-READY not run in this autonomous drafting pass; implement against the Acceptance Criteria above.*

---

## Test Evidence

**Story Type**: Integration
**Required evidence**: the integration run named in the criteria; run outputs and reports retained in `production/qa/evidence/core-rebuild-story-007/`
**Status**: [x] Created: production/qa/evidence/core-rebuild-story-007/ (collision-bench.md, runs/, gdunit4-final.log 200/200)

---

## Dependencies

- Depends on: `production/epics/core-rebuild/story-006-collision-load-checks-and-mirror.md`
- Unlocks: `production/epics/core-rebuild/story-012-first-slice-budget.md`

## Completion Notes
**Completed**: 2026-11-22
**Criteria**: 4/4 passing for the realistic layout (Castle hazards: 237 µs median / 281 µs p95, worst section 292 µs, at the limit inside measurement noise; 5 sections incl. a two-level crossover; OBJECT_COUNT unchanged, no per-tick `*_create`, no RID leak at exit; report recorded). Debug editor build as the upper bound; release re-run and the story-008 Castle mesh re-run are pending.
**Deviations**: (1) The TD-012 worst case (12 karts in reach of 5 spinning solid boxes) stays over budget at 868 µs p95 (movers section 898). The owner chose on 2026-11-22 to move the hot core to C++ (GDExtension) now; TD-012 stays open, pointed at that port. This GDScript CollisionQuery and its tests become the port's reference. (2) AC "No allocation" reworded (owner-approved): 4.8-beta3 has no server RID count. (3) Pre-existing story-004 bug fixed: on about 1 in 127 unsafe-point checks, Jolt's rest check found no contact and the sweep reported WALL_ATTR_NONE; now retried 1 mm further along the motion (`collision_unsafe_point_retry_test.gd`). (4) Two surviving mutants are documented: the Newton step floor affects performance only; a touch band of TOL to 2·TOL cannot be told apart deterministically.
**Test Evidence**: production/qa/evidence/core-rebuild-story-007/ (collision-bench.md; runs/ baseline, opt1, opt2, opt3, opt3final aggregates; gdunit4-final.log 200/200; parse-check-final.txt 8/8; core-greps-final.txt; rid-leak-check.log; mutation-*.log)
**Reviewed by**: lead-programmer (LP-CODE-REVIEW: CONCERNS, addressed); qa-lead (QL-TEST-COVERAGE: GAPS, closed); godot-gdscript-specialist engine check (no defects, 4 advisories applied)
Run result: N/A — headless collision benchmark; nothing reaches the screen

## Calls beyond the design
- Bench mesh: 1200 m lemniscate, 14 m road, 8 m off-road, 1.5 m walls, 8 m crossover bridge, banking up to 12°, ramp at s 960 (`tools/bench_track_fixture.gd`) · kept 2026-11-22
- Five sections (curve, climb, crossover, movers, ramp), 300 timed ticks each after 60 warm-up; 12 karts in one section at a time (`tools/bench_collision.gd`) · kept 2026-11-22
- Castle movers modelled from the frozen Castle (drawbridge, portcullis, 3 non-solid barrels); worst case 5 spinning 16 m boxes (`tools/bench_collision.gd`) · kept 2026-11-22
- Bench karts: sweep sphere r 1.0, 25-30 m/s, weave to the walls, 4 rays + 3 sweeps always (`tools/bench_collision.gd`) · kept 2026-11-22
- Mover touch needs the end in contact; a near-end contact with the end clear is a blocking hit (`collision_query.gd`) · kept 2026-11-22
- Newton cap fails closed (blocking hit at the safe fraction) with one push_error per query; `_newton_cap` test seam (`collision_query.gd`) · kept 2026-11-22
- Unsafe-point retry 0.001 m further along the motion (`UNSAFE_RETRY_LENGTH`, `collision_query.gd`) · kept 2026-11-22
- `_sweep_local` and `_test_movers_for_sweep` kept whole under a perf waiver (split cost +2.4%) · kept 2026-11-22
- Nearest-rank percentiles, median of 3 runs; MEMORY_STATIC reported, not gated; derived equivalence tolerances and feature-hit floors (`bench_collision.sh`, equivalence test) · kept 2026-11-22
