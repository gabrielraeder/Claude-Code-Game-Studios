# Story 055: Castle: bot race bar and tick budget

> **Epic**: Core Rebuild (Phase A)
> **Status**: Ready
> **Layer**: Feature
> **Type**: Integration
> **Estimate**: S
> **Manifest Version**: N/A (no control manifest yet)
> **Last Updated**: not started (set by /dev-story)

## Context

**GDD**: `design/gdd/course-data.md` (§8 Acceptance Criteria)
**Requirement**: Course Data AC17; `architecture.md` Performance Budgets (bots 0.8 ms; whole tick 2.0 ms)
**Roadmap step**: `architecture.md` Phase A Sequencing step 6 (roadmap item 025: Castle Circuit rebuilt). Epic story numbers are not roadmap item numbers.

**ADR Governing Implementation**: ADR-0004: Course Data Format (Accepted)
**ADR Decision Summary**: A binary `CourseData` `.res` (checkpoint gates with group ids and next links plus key groups for laps, routes with baked per-sample and span tables, item-box, respawn and 12 grid poses, oriented `areas`) is built by a `@tool` `CourseBuilder` in `src/core/course/` from a neutral `CourseAuthoring` plus a `CollisionQuery`; per-kart `CourseProgress` runs a sector cursor in O(1) amortised time and handles junctions, shortcuts, wrong-way driving and off-course flight; bots read only routes and tables, never `CollisionQuery`; mirror swaps every left/right field.

**ADR Version**: ADR-0004 2026-11-22

**Engine**: Godot 4.8-beta3 | **Risk**: HIGH
**Engine Notes**: The `.res` round trip and cache identity are VERIFIED by probe (`prototypes/collision-spike/out/probe_adr45_*`). Scripts the baker touches are `@tool` and loaded by `preload("res://...")` path, not `class_name` (ADR-0005 NV-7).

---

## Acceptance Criteria

*Each criterion cites its source (GDD AC id, ADR Validation Criteria, or `architecture.md`).*

- [ ] **Bot bar.** 11 bots, 5 races on Castle Circuit: 11/11 finish, 0 stuck, 0 shortcut mis-entries (Course Data AC17, the story-009 bar); a new-core equivalent of `bot_race_test.sh` passes.
- [ ] **Budget.** With stage timing in the style of `tools/profile_tick.gd`, bots (11) <= 0.8 ms p95 and the whole simulation tick <= 2.0 ms p95 on the owner's PC, debug build as upper bound; every budget row is reported (`architecture.md` Performance Budgets).

---

## Implementation Notes

- Report into `production/qa/evidence/core-rebuild-story-055/`.

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 060: the A2 online run.

---

## Files

*Planned; `/dev-story` replaces this list with the files it changed.*

- `tools/profile_tick_core.gd` (new)
- `tests/integration/ai/castle_bot_race_test.gd` (new)
- `production/qa/evidence/core-rebuild-story-055/` (races, profile)

---

## QA Test Cases

*N/A — QL-STORY-READY not run in this autonomous drafting pass; implement against the Acceptance Criteria above.*

---

## Test Evidence

**Story Type**: Integration
**Required evidence**: `tests/integration/ai/castle_bot_race_test.gd` — must exist and pass; run outputs and reports retained in `production/qa/evidence/core-rebuild-story-055/`
**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: `production/epics/core-rebuild/story-052-castle-features-and-hazards.md`, `production/epics/core-rebuild/story-053-castle-items.md`, `production/epics/core-rebuild/story-054-castle-bots-on-routes.md`
- Unlocks: `production/epics/core-rebuild/story-056-castle-network-switch.md`
