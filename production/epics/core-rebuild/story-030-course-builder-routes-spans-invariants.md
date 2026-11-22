# Story 030: CourseBuilder: routes, spans, respawn and grid checks

> **Epic**: Core Rebuild (Phase A)
> **Status**: Ready
> **Layer**: Core
> **Type**: Logic
> **Estimate**: M
> **Manifest Version**: N/A (no control manifest yet)
> **Last Updated**: not started (set by /dev-story)

## Context

**GDD**: `design/gdd/course-data.md` (§8 Acceptance Criteria)
**Requirement**: Course Data AC2, AC6 to AC9; ADR-0004 §14, §13
**Roadmap step**: `architecture.md` Phase A Sequencing step 4 (roadmap item 023: Course Data + mesh `track_check`). Epic story numbers are not roadmap item numbers.

**ADR Governing Implementation**: ADR-0004: Course Data Format (Accepted)
**ADR Decision Summary**: A binary `CourseData` `.res` (checkpoint gates with group ids and next links plus key groups for laps, routes with baked per-sample and span tables, item-box, respawn and 12 grid poses, oriented `areas`) is built by a `@tool` `CourseBuilder` in `src/core/course/` from a neutral `CourseAuthoring` plus a `CollisionQuery`; per-kart `CourseProgress` runs a sector cursor in O(1) amortised time and handles junctions, shortcuts, wrong-way driving and off-course flight; bots read only routes and tables, never `CollisionQuery`; mirror swaps every left/right field.

**ADR Version**: ADR-0004 2026-11-22

**Engine**: Godot 4.8-beta3 | **Risk**: HIGH
**Engine Notes**: The `.res` round trip and cache identity are VERIFIED by probe (`prototypes/collision-spike/out/probe_adr45_*`). Scripts the baker touches are `@tool` and loaded by `preload("res://...")` path, not `class_name` (ADR-0005 NV-7).

---

## Acceptance Criteria

*Each criterion cites its source (GDD AC id, ADR Validation Criteria, or `architecture.md`).*

- [ ] **Routes and spans.** Routes are sampled at `sample_spacing_m`; `PAD` and `RAMP` spans come from surface kinds and `HAZARD` spans from areas (ADR-0004 §14, Validation Criteria).
- [ ] **Structure.** A line FAILs unless there is exactly one closed `main` route, gate 0 is in group 0, and there are exactly 12 grid poses, slots 0 ... 11 (Course Data AC2).
- [ ] **Respawn invariants.** Lines FAIL when a respawn's `s` exceeds the `gate_s` of a gate using it, lies across the line from its gates, or sits in a hazard, a mover's swept volume, on a pad or on a ramp; when a gate in a `min_speed` branch run-up uses a respawn off `main`; and when, on a route with a `DROP` or `OPEN_EDGE` span, a gate is more than 40 m from its respawn (Course Data AC6, AC7, AC8).
- [ ] **Grid invariants.** Lines FAIL unless every grid pose is behind gate 0 on road ground, at least 2 × the largest kart radius + margin from the others, and the first corner (first gate turning > 15° from gate 0) is at least 60 m after the line (Course Data AC9). Each line above is watched failing on a broken fixture.

---

## Implementation Notes

- Lateral wall sweeps derive `WALL_OPENING` / `OPEN_EDGE` (no wall `opening` field, ADR-0002 v5.1).

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 035: running these checks from `track_check` on a baked track.

---

## Files

*Planned; `/dev-story` replaces this list with the files it changed.*

- `src/core/course/course_builder.gd` (routes, spans, invariants)
- `tests/unit/course/course_builder_routes_test.gd` (new)

---

## QA Test Cases

*N/A — QL-STORY-READY not run in this autonomous drafting pass; implement against the Acceptance Criteria above.*

---

## Test Evidence

**Story Type**: Logic
**Required evidence**: `tests/unit/course/course_builder_routes_test.gd` — must exist and pass, with at least one test per acceptance criterion (`qa.level: full`)
**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: `production/epics/core-rebuild/story-029-course-builder-gates-and-keys.md`
- Unlocks: `production/epics/core-rebuild/story-031-course-progress-cursor.md`, `production/epics/core-rebuild/story-036-pipeline-pins-and-schema.md`
