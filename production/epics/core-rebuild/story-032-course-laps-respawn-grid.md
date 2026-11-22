# Story 032: CourseProgress lap rule, respawn and grid

> **Epic**: Core Rebuild (Phase A)
> **Status**: Ready
> **Layer**: Core
> **Type**: Logic
> **Estimate**: M
> **Manifest Version**: N/A (no control manifest yet)
> **Last Updated**: not started (set by /dev-story)

## Context

**GDD**: `design/gdd/course-data.md` (§8 Acceptance Criteria)
**Requirement**: Course Data AC13; ADR-0004 Validation Criteria (lap rule, `relocate`, respawn, grid)
**Roadmap step**: `architecture.md` Phase A Sequencing step 4 (roadmap item 023: Course Data + mesh `track_check`). Epic story numbers are not roadmap item numbers.

**ADR Governing Implementation**: ADR-0004: Course Data Format (Proposed)
**ADR Decision Summary**: A binary `CourseData` `.res` (checkpoint gates with group ids and next links plus key groups for laps, routes with baked per-sample and span tables, item-box, respawn and 12 grid poses, oriented `areas`) is built by a `@tool` `CourseBuilder` in `src/core/course/` from a neutral `CourseAuthoring` plus a `CollisionQuery`; per-kart `CourseProgress` runs a sector cursor in O(1) amortised time and handles junctions, shortcuts, wrong-way driving and off-course flight; bots read only routes and tables, never `CollisionQuery`; mirror swaps every left/right field.

**ADR Version**: ADR-0004 2026-11-22

**Engine**: Godot 4.8-beta3 | **Risk**: HIGH
**Engine Notes**: The `.res` round trip and cache identity are VERIFIED by probe (`prototypes/collision-spike/out/probe_adr45_*`). Scripts the baker touches are `@tool` and loaded by `preload("res://...")` path, not `class_name` (ADR-0005 NV-7).

---

## Acceptance Criteria

*Each criterion cites its source (GDD AC id, ADR Validation Criteria, or `architecture.md`).*

- [ ] **Lap rule.** Every frozen `LapCounter` case is ported: forward laps; reversing over the line and back (no extra lap); an illegal cut missing a key group (refused, `rejected_crossings` +1, recoverable); a legal shortcut crossing the shared key groups (counted); invalid wraps undone by reversing (ADR-0004 Validation Criteria).
- [ ] **Reverse over the line.** `lap` goes n -> n - 1 -> n, `max_lap` is unchanged, and no new lap is emitted (Course Data AC13).
- [ ] **Respawn and relocate.** The respawn pose is never ahead of `safe_gate`, the fallback is on main, `lap` is unchanged, and `relocate` keeps the key state (ADR-0004 Validation Criteria).
- [ ] **Grid.** The 12 grid karts start at lap 0, and the first crossing gives lap 1 (ADR-0004 Validation Criteria).

---

## Implementation Notes

- Read `src/legacy/test_track/lap_counter.gd` as reference only; nothing imported.

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 051: Lap & Position and Fall & Respawn on a real track.

---

## Files

*Planned; `/dev-story` replaces this list with the files it changed.*

- `src/core/course/course_progress.gd` (laps, respawn)
- `tests/unit/course/course_laps_respawn_test.gd` (new)

---

## QA Test Cases

*N/A — QL-STORY-READY not run in this autonomous drafting pass; implement against the Acceptance Criteria above.*

---

## Test Evidence

**Story Type**: Logic
**Required evidence**: `tests/unit/course/course_laps_respawn_test.gd` — must exist and pass, with at least one test per acceptance criterion (`qa.level: full`)
**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: `production/epics/core-rebuild/story-031-course-progress-cursor.md`
- Unlocks: `production/epics/core-rebuild/story-033-race-ranking-and-progress-budget.md`, `production/epics/core-rebuild/story-050-castle-race-clock-registry-tick.md`
