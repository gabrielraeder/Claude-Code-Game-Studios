# Story 029: CourseBuilder: gates, key groups and defaults

> **Epic**: Core Rebuild (Phase A)
> **Status**: Blocked — BLOCKED: ADR-0004 is Proposed (owner acceptance pending)
> **Layer**: Core
> **Type**: Logic
> **Estimate**: M
> **Manifest Version**: N/A (no control manifest yet)
> **Last Updated**: not started (set by /dev-story)

## Context

**GDD**: `design/gdd/course-data.md` (§8 Acceptance Criteria)
**Requirement**: Course Data AC3; ADR-0004 §14 and Validation Criteria (builder tests)
**Roadmap step**: `architecture.md` Phase A Sequencing step 4 (roadmap item 023: Course Data + mesh `track_check`). Epic story numbers are not roadmap item numbers.

**ADR Governing Implementation**: ADR-0004: Course Data Format (Proposed)
**ADR Decision Summary**: A binary `CourseData` `.res` (checkpoint gates with group ids and next links plus key groups for laps, routes with baked per-sample and span tables, item-box, respawn and 12 grid poses, oriented `areas`) is built by a `@tool` `CourseBuilder` in `src/core/course/` from a neutral `CourseAuthoring` plus a `CollisionQuery`; per-kart `CourseProgress` runs a sector cursor in O(1) amortised time and handles junctions, shortcuts, wrong-way driving and off-course flight; bots read only routes and tables, never `CollisionQuery`; mirror swaps every left/right field.

**ADR Version**: ADR-0004 2026-11-22

**Engine**: Godot 4.8-beta3 | **Risk**: HIGH
**Engine Notes**: The `.res` round trip and cache identity are VERIFIED by probe (`prototypes/collision-spike/out/probe_adr45_*`). Scripts the baker touches are `@tool` and loaded by `preload("res://...")` path, not `class_name` (ADR-0005 NV-7).

---

## Acceptance Criteria

*Each criterion cites its source (GDD AC id, ADR Validation Criteria, or `architecture.md`).*

- [ ] **Gate lift and defaults.** The gate lift puts the quad centre half a height above the authored origin; the default `next` wraps; the default respawn is behind the gate (ADR-0004 Validation Criteria).
- [ ] **Key groups.** A disagreeing `kk_key` in a group FAILs; the key-coverage line PASSes on a legal fixture and FAILs on a copy with one shortcut gate's `kk_key` removed (Course Data AC3; ADR-0004).
- [ ] **Check lines.** Each §13 check line this story owns is watched failing on a broken `CourseAuthoring`; a missing input gives NOT_ASSESSED, never PASS (ADR-0004 Validation Criteria).
- [ ] **Boundary.** `CourseBuilder.BUILDER_VERSION` is a `const`; grep finds no `TrackImportLimits` or `src/pipeline/` reference in `src/core/course/` (ADR-0004 §14).

---

## Implementation Notes

- `CourseBuilder` is `@tool` and takes a `CourseAuthoring` plus a `CollisionQuery` and the `CourseBuildSettings` passed in; it never loads pipeline classes.
- Every check emits PASS / WARN / FAIL / NOT_ASSESSED lines.

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 030: routes, spans, respawn and grid invariants.

---

## Files

*Planned; `/dev-story` replaces this list with the files it changed.*

- `src/core/course/course_builder.gd`, `src/core/course/course_authoring.gd` (new)
- `tests/unit/course/course_builder_gates_test.gd` (new)

---

## QA Test Cases

*N/A — QL-STORY-READY not run in this autonomous drafting pass; implement against the Acceptance Criteria above.*

---

## Test Evidence

**Story Type**: Logic
**Required evidence**: `tests/unit/course/course_builder_gates_test.gd` — must exist and pass, with at least one test per acceptance criterion (`qa.level: full`)
**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: `production/epics/core-rebuild/story-028-course-data-schema-and-mirror.md`
- Unlocks: `production/epics/core-rebuild/story-030-course-builder-routes-spans-invariants.md`
