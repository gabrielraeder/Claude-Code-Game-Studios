# Story 054: Castle: CPU racers on routes and spans

> **Epic**: Core Rebuild (Phase A)
> **Status**: Ready
> **Layer**: Feature
> **Type**: Integration
> **Estimate**: M
> **Manifest Version**: N/A (no control manifest yet)
> **Last Updated**: not started (set by /dev-story)

## Context

**GDD**: `design/gdd/course-data.md` (§8 Acceptance Criteria)
**Requirement**: ADR-0004 Summary (bots read only routes and tables) and Migration Plan step 3 (bots rebuilt, replacing every frozen reference in the §6 table); Course Data AC17 (shortcut entries)
**Roadmap step**: `architecture.md` Phase A Sequencing step 6 (roadmap item 025: Castle Circuit rebuilt). Epic story numbers are not roadmap item numbers.

**ADR Governing Implementation**: ADR-0004: Course Data Format (Accepted)
**ADR Decision Summary**: A binary `CourseData` `.res` (checkpoint gates with group ids and next links plus key groups for laps, routes with baked per-sample and span tables, item-box, respawn and 12 grid poses, oriented `areas`) is built by a `@tool` `CourseBuilder` in `src/core/course/` from a neutral `CourseAuthoring` plus a `CollisionQuery`; per-kart `CourseProgress` runs a sector cursor in O(1) amortised time and handles junctions, shortcuts, wrong-way driving and off-course flight; bots read only routes and tables, never `CollisionQuery`; mirror swaps every left/right field.

**ADR Version**: ADR-0004 2026-11-22

**Engine**: Godot 4.8-beta3 | **Risk**: HIGH
**Engine Notes**: The `.res` round trip and cache identity are VERIFIED by probe (`prototypes/collision-spike/out/probe_adr45_*`). Scripts the baker touches are `@tool` and loaded by `preload("res://...")` path, not `class_name` (ADR-0005 NV-7).

---

## Acceptance Criteria

*Each criterion cites its source (GDD AC id, ADR Validation Criteria, or `architecture.md`).*

- [ ] **Routes only.** CPU Racers in `src/ai/` drive from routes, sample tables and spans and replace every frozen reference listed in ADR-0004 §6; `tools/core_greps.sh` finds no `CollisionQuery` reference under `src/ai/` (ADR-0004).
- [ ] **Same kart.** Bots produce driver inputs for the same `DriveState` / `KartBody` path as humans, and `bot_push_mult` applies in contact (Kart Physics AC-20).
- [ ] **Shortcuts.** Over a scripted 11-bot race, bots enter shortcuts only by the span rules: 0 shortcut mis-entries (Course Data AC17, entry part).

---

## Implementation Notes

- Read the frozen `bot_driver.gd` as reference only; `BotPersonality` is shared data.

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 055: the 5-race bar and the bot budget.

---

## Files

*Planned; `/dev-story` replaces this list with the files it changed.*

- `src/ai/bot_driver.gd` (new)
- `tests/integration/ai/castle_bots_test.gd`, `tests/unit/ai/bot_route_following_test.gd` (new)

---

## QA Test Cases

*N/A — QL-STORY-READY not run in this autonomous drafting pass; implement against the Acceptance Criteria above.*

---

## Test Evidence

**Story Type**: Integration
**Required evidence**: `tests/integration/ai/castle_bots_test.gd`, `tests/unit/ai/bot_route_following_test.gd` — must exist and pass; run outputs and reports retained in `production/qa/evidence/core-rebuild-story-054/`
**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: `production/epics/core-rebuild/story-051-castle-laps-ranking-respawn.md`
- Unlocks: `production/epics/core-rebuild/story-055-castle-bot-race-and-budget.md`
