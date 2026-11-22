# Story 033: Race ranking, progress determinism and benchmark

> **Epic**: Core Rebuild (Phase A)
> **Status**: Ready
> **Layer**: Feature
> **Type**: Integration
> **Estimate**: S
> **Manifest Version**: N/A (no control manifest yet)
> **Last Updated**: not started (set by /dev-story)

## Context

**GDD**: `design/gdd/course-data.md` (§8 Acceptance Criteria)
**Requirement**: ADR-0004 Validation Criteria (determinism, benchmark incl. 12-off-course case); `architecture.md` Performance Budgets (race logic, lap/progress, net send 0.15 ms)
**Roadmap step**: `architecture.md` Phase A Sequencing step 4 (roadmap item 023: Course Data + mesh `track_check`). Epic story numbers are not roadmap item numbers.

**ADR Governing Implementation**: ADR-0004: Course Data Format (Proposed)
**ADR Decision Summary**: A binary `CourseData` `.res` (checkpoint gates with group ids and next links plus key groups for laps, routes with baked per-sample and span tables, item-box, respawn and 12 grid poses, oriented `areas`) is built by a `@tool` `CourseBuilder` in `src/core/course/` from a neutral `CourseAuthoring` plus a `CollisionQuery`; per-kart `CourseProgress` runs a sector cursor in O(1) amortised time and handles junctions, shortcuts, wrong-way driving and off-course flight; bots read only routes and tables, never `CollisionQuery`; mirror swaps every left/right field.

**ADR Version**: ADR-0004 2026-11-22

**Engine**: Godot 4.8-beta3 | **Risk**: HIGH
**Engine Notes**: The `.res` round trip and cache identity are VERIFIED by probe (`prototypes/collision-spike/out/probe_adr45_*`). Scripts the baker touches are `@tool` and loaded by `preload("res://...")` path, not `class_name` (ADR-0005 NV-7).

---

## Acceptance Criteria

*Each criterion cites its source (GDD AC id, ADR Validation Criteria, or `architecture.md`).*

- [ ] **Ranking.** `RaceRanking` orders karts by finish, then lap, then `distance`, with a deterministic tie-break by slot; unit tests cover ties, a finished kart and a wrong-way kart.
- [ ] **Determinism.** Two runs give identical progress traces (ADR-0004 Validation Criteria).
- [ ] **Benchmark.** 12 karts' `progress` and 11 bots' route reads in a running tree, including the case of all 12 off course with staggered searches, stay inside the race-logic row (0.15 ms p95, together with net send) on the owner's PC, debug build as upper bound; report retained (ADR-0004 Benchmark; `architecture.md`).

---

## Implementation Notes

- `RaceRanking` belongs to Lap & Position (Feature layer) and reads `CourseProgress` only.

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 051: the ranking shown in a race.

---

## Files

*Planned; `/dev-story` replaces this list with the files it changed.*

- `src/gameplay/race/race_ranking.gd` (new)
- `tests/unit/race/race_ranking_test.gd`, `tests/integration/course/course_progress_bench_test.gd` (new)
- `tools/bench_course.gd` (new)
- `production/qa/evidence/core-rebuild-story-033/` (bench report)

---

## QA Test Cases

*N/A — QL-STORY-READY not run in this autonomous drafting pass; implement against the Acceptance Criteria above.*

---

## Test Evidence

**Story Type**: Integration
**Required evidence**: `tests/unit/race/race_ranking_test.gd`, `tests/integration/course/course_progress_bench_test.gd` — must exist and pass; run outputs and reports retained in `production/qa/evidence/core-rebuild-story-033/`
**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: `production/epics/core-rebuild/story-032-course-laps-respawn-grid.md`
- Unlocks: `production/epics/core-rebuild/story-034-generator-course-equivalence.md`
