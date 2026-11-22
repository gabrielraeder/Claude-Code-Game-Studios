# Story 028: CourseData schema, tuning, build settings and mirror

> **Epic**: Core Rebuild (Phase A)
> **Status**: Ready
> **Layer**: Core
> **Type**: Logic
> **Estimate**: M
> **Manifest Version**: N/A (no control manifest yet)
> **Last Updated**: not started (set by /dev-story)

## Context

**GDD**: `design/gdd/course-data.md` (§8 Acceptance Criteria)
**Requirement**: ADR-0004 Summary and Migration Plan step 1; ADR-0004 Validation Criteria (mirror, grep)
**Roadmap step**: `architecture.md` Phase A Sequencing step 4 (roadmap item 023: Course Data + mesh `track_check`). Epic story numbers are not roadmap item numbers.

**ADR Governing Implementation**: ADR-0004: Course Data Format (Proposed)
**ADR Decision Summary**: A binary `CourseData` `.res` (checkpoint gates with group ids and next links plus key groups for laps, routes with baked per-sample and span tables, item-box, respawn and 12 grid poses, oriented `areas`) is built by a `@tool` `CourseBuilder` in `src/core/course/` from a neutral `CourseAuthoring` plus a `CollisionQuery`; per-kart `CourseProgress` runs a sector cursor in O(1) amortised time and handles junctions, shortcuts, wrong-way driving and off-course flight; bots read only routes and tables, never `CollisionQuery`; mirror swaps every left/right field.

**ADR Version**: ADR-0004 2026-11-22

**Engine**: Godot 4.8-beta3 | **Risk**: HIGH
**Engine Notes**: The `.res` round trip and cache identity are VERIFIED by probe (`prototypes/collision-spike/out/probe_adr45_*`). Scripts the baker touches are `@tool` and loaded by `preload("res://...")` path, not `class_name` (ADR-0005 NV-7).

---

## Acceptance Criteria

*Each criterion cites its source (GDD AC id, ADR Validation Criteria, or `architecture.md`).*

- [ ] **Schema.** `CourseData`, `CourseRoute`, `RouteSample`, `RouteLocation`, `CourseGate` and `CourseTuning` exist as `@tool` resources in `src/core/course/` with doc comments, holding gates with group ids and next links, key groups, routes with per-sample and span tables, item-box, respawn and 12 grid poses and oriented `areas` (ADR-0004 Summary).
- [ ] **Data instances.** `assets/data/core/course_tuning.tres` and `assets/data/core/course_build_settings.tres` (`sample_spacing_m`, `fork_merge_tolerance_m`, lateral scan range, ground-cast limits, gate-sector tolerances) exist with `##` comments (ADR-0004 §14).
- [ ] **Mirror.** `mirrored()` swaps `half_left`/`half_right`, `clear_*`, edge nibbles, span sides and lane order, and leaves the source untouched (ADR-0004 Validation Criteria).
- [ ] **Grep.** `tools/core_greps.sh` finds no `src/legacy/` reference under `src/core/course/` and no `CollisionQuery` reference under `src/ai/` (ADR-0004 Validation Criteria).

---

## Implementation Notes

- Unit tests build fixture courses in code, no file I/O (ADR-0004 Validation Criteria).
- Course Data stays separate from collision (architecture Principle 4).

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 029-030: `CourseBuilder`.
- Story 031-032: `CourseProgress`.

---

## Files

*Planned; `/dev-story` replaces this list with the files it changed.*

- `src/core/course/course_data.gd`, `course_route.gd`, `route_sample.gd`, `route_location.gd`, `course_gate.gd`, `course_tuning.gd`, `course_build_settings.gd` (new)
- `assets/data/core/course_tuning.tres`, `assets/data/core/course_build_settings.tres` (new)
- `tools/core_greps.sh` (course rules)
- `tests/unit/course/course_data_schema_test.gd`, `tests/unit/course/course_fixtures.gd` (new)

---

## QA Test Cases

*N/A — QL-STORY-READY not run in this autonomous drafting pass; implement against the Acceptance Criteria above.*

---

## Test Evidence

**Story Type**: Logic
**Required evidence**: `tests/unit/course/course_data_schema_test.gd`, `tests/unit/course/course_fixtures.gd` — must exist and pass, with at least one test per acceptance criterion (`qa.level: full`)
**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: `production/epics/core-rebuild/story-006-collision-load-checks-and-mirror.md`
- Unlocks: `production/epics/core-rebuild/story-029-course-builder-gates-and-keys.md`
