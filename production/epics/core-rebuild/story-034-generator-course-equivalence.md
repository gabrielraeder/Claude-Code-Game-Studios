# Story 034: Generator-course equivalence oracle

> **Epic**: Core Rebuild (Phase A)
> **Status**: Blocked — BLOCKED: ADR-0004 is Proposed (owner acceptance pending); ADR-0001 §9 amendment (ADR-0004 §15, legacy extractor) pending owner approval — nothing in ADR-0004 §15 may be implemented until it is approved
> **Layer**: Core
> **Type**: Integration
> **Estimate**: M
> **Manifest Version**: N/A (no control manifest yet)
> **Last Updated**: not started (set by /dev-story)

## Context

**GDD**: `design/gdd/course-data.md` (§8 Acceptance Criteria)
**Requirement**: ADR-0004 §15 (consumer 1) and Validation Criteria (equivalence); Course Data AC1, AC10
**Roadmap step**: `architecture.md` Phase A Sequencing step 4 (roadmap item 023: Course Data + mesh `track_check`). Epic story numbers are not roadmap item numbers.

**ADR Governing Implementation**: ADR-0004: Course Data Format (Proposed)
**ADR Decision Summary**: A binary `CourseData` `.res` (checkpoint gates with group ids and next links plus key groups for laps, routes with baked per-sample and span tables, item-box, respawn and 12 grid poses, oriented `areas`) is built by a `@tool` `CourseBuilder` in `src/core/course/` from a neutral `CourseAuthoring` plus a `CollisionQuery`; per-kart `CourseProgress` runs a sector cursor in O(1) amortised time and handles junctions, shortcuts, wrong-way driving and off-course flight; bots read only routes and tables, never `CollisionQuery`; mirror swaps every left/right field.

**ADR Version**: ADR-0004 2026-11-22

**Engine**: Godot 4.8-beta3 | **Risk**: HIGH
**Engine Notes**: The `.res` round trip and cache identity are VERIFIED by probe (`prototypes/collision-spike/out/probe_adr45_*`). Scripts the baker touches are `@tool` and loaded by `preload("res://...")` path, not `class_name` (ADR-0005 NV-7).

---

## Acceptance Criteria

*Each criterion cites its source (GDD AC id, ADR Validation Criteria, or `architecture.md`).*

- [ ] **Consumer 1, course half.** `tools/legacy_test_bake.gd` produces a `CourseAuthoring` from the extractor JSON and calls `CourseBuilder`; Castle Circuit and Dungeon Depths build with no FAIL and no NOT_ASSESSED line (ADR-0004 §15; Course Data AC1).
- [ ] **Equivalence.** On the generator-baked course, `CourseProgress.s` follows the golden traces' `track_s` within a tolerance this story sets and records, and lap counts match exactly (ADR-0004 Validation Criteria).
- [ ] **Three laps.** The story-025 pilot driving the main line for 3 laps gets `lap` 1, 2, 3, 4 at the four crossings, `rejected_crossings = 0`, and `distance` never decreases (Course Data AC10).

---

## Implementation Notes

- Do not start until the owner approves the ADR-0001 §9 amendment (ADR-0004 §15).
- Golden CSV columns: `x`, `z`, `height`, `track_s`, `lap`.

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 042: the Blender bootstrap of the same tracks.

---

## Files

*Planned; `/dev-story` replaces this list with the files it changed.*

- `tools/legacy_test_bake.gd` (course half)
- `tests/integration/course/generator_course_equivalence_test.gd` (new)
- `production/qa/evidence/core-rebuild-story-034/` (equivalence report)

---

## QA Test Cases

*N/A — QL-STORY-READY not run in this autonomous drafting pass; implement against the Acceptance Criteria above.*

---

## Test Evidence

**Story Type**: Integration
**Required evidence**: `tests/integration/course/generator_course_equivalence_test.gd` — must exist and pass; run outputs and reports retained in `production/qa/evidence/core-rebuild-story-034/`
**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: `production/epics/core-rebuild/story-008-legacy-extractor-and-test-mesh.md`, `production/epics/core-rebuild/story-026-parity-run-rebuilt-kart.md`, `production/epics/core-rebuild/story-033-race-ranking-and-progress-budget.md`; owner approval of the ADR-0001 §9 amendment (ADR-0004 §15)
- Unlocks: `production/epics/core-rebuild/story-035-mesh-track-check.md`
