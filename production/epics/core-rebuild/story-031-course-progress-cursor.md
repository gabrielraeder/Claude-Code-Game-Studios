# Story 031: CourseProgress sector cursor, smoothing, wrong way and off course

> **Epic**: Core Rebuild (Phase A)
> **Status**: Ready
> **Layer**: Core
> **Type**: Logic
> **Estimate**: M
> **Manifest Version**: N/A (no control manifest yet)
> **Last Updated**: not started (set by /dev-story)

## Context

**GDD**: `design/gdd/course-data.md` (§8 Acceptance Criteria)
**Requirement**: ADR-0004 Validation Criteria (sectors, smoothing, wrong way, off course)
**Roadmap step**: `architecture.md` Phase A Sequencing step 4 (roadmap item 023: Course Data + mesh `track_check`). Epic story numbers are not roadmap item numbers.

**ADR Governing Implementation**: ADR-0004: Course Data Format (Accepted)
**ADR Decision Summary**: A binary `CourseData` `.res` (checkpoint gates with group ids and next links plus key groups for laps, routes with baked per-sample and span tables, item-box, respawn and 12 grid poses, oriented `areas`) is built by a `@tool` `CourseBuilder` in `src/core/course/` from a neutral `CourseAuthoring` plus a `CollisionQuery`; per-kart `CourseProgress` runs a sector cursor in O(1) amortised time and handles junctions, shortcuts, wrong-way driving and off-course flight; bots read only routes and tables, never `CollisionQuery`; mirror swaps every left/right field.

**ADR Version**: ADR-0004 2026-11-22

**Engine**: Godot 4.8-beta3 | **Risk**: HIGH
**Engine Notes**: The `.res` round trip and cache identity are VERIFIED by probe (`prototypes/collision-spike/out/probe_adr45_*`). Scripts the baker touches are `@tool` and loaded by `preload("res://...")` path, not `class_name` (ADR-0005 NV-7).

---

## Acceptance Criteria

*Each criterion cites its source (GDD AC id, ADR Validation Criteria, or `architecture.md`).*

- [ ] **Sectors.** The fraction is monotone along a sector, and `s` is continuous at a fork and at a merge (ADR-0004 Validation Criteria).
- [ ] **Smoothing.** `distance` never changes by more than `progress_rate_cap × moved + progress_slack` except on a snap event, and is continuous across a valid line crossing (ADR-0004 Validation Criteria).
- [ ] **Wrong way.** Set after `wrong_way_distance` of backward travel and cleared after `wrong_way_clear` (ADR-0004 Validation Criteria).
- [ ] **Off course.** Progress is held and no gate is credited during a full search; full searches are staggered by slot (ADR-0004 Validation Criteria and Benchmark).

---

## Implementation Notes

- O(1) amortised sector cursor; no per-call scan of a whole route (`architecture.md` rule).

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 032: laps, respawn and grid.
- Story 033: benchmark.

---

## Files

*Planned; `/dev-story` replaces this list with the files it changed.*

- `src/core/course/course_progress.gd`, `src/core/course/route_cursor.gd` (new)
- `tests/unit/course/course_progress_test.gd` (new)

---

## QA Test Cases

*N/A — QL-STORY-READY not run in this autonomous drafting pass; implement against the Acceptance Criteria above.*

---

## Test Evidence

**Story Type**: Logic
**Required evidence**: `tests/unit/course/course_progress_test.gd` — must exist and pass, with at least one test per acceptance criterion (`qa.level: full`)
**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: `production/epics/core-rebuild/story-030-course-builder-routes-spans-invariants.md`
- Unlocks: `production/epics/core-rebuild/story-032-course-laps-respawn-grid.md`
