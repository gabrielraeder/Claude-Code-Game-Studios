# Story 057: Castle: HUD, minimap and race flow port

> **Epic**: Core Rebuild (Phase A)
> **Status**: Ready
> **Layer**: Presentation
> **Type**: UI
> **Estimate**: M
> **Manifest Version**: N/A (no control manifest yet)
> **Last Updated**: not started (set by /dev-story)

## Context

**GDD**: `design/gdd/systems-index.md` rows Race HUD & Minimap, Race Flow & Lobby (no system GDD yet)
**Requirement**: `architecture.md` Phase A Sequencing step 6 (HUD and race flow ported); Performance Budgets (HUD, minimap, audio 0.5 ms per frame)
**Roadmap step**: `architecture.md` Phase A Sequencing step 6 (roadmap item 025: Castle Circuit rebuilt). Epic story numbers are not roadmap item numbers.

**ADR Governing Implementation**: ADR-0004: Course Data Format (Accepted)
**ADR Decision Summary**: A binary `CourseData` `.res` (checkpoint gates with group ids and next links plus key groups for laps, routes with baked per-sample and span tables, item-box, respawn and 12 grid poses, oriented `areas`) is built by a `@tool` `CourseBuilder` in `src/core/course/` from a neutral `CourseAuthoring` plus a `CollisionQuery`; per-kart `CourseProgress` runs a sector cursor in O(1) amortised time and handles junctions, shortcuts, wrong-way driving and off-course flight; bots read only routes and tables, never `CollisionQuery`; mirror swaps every left/right field.

**ADR Version**: ADR-0004 2026-11-22

**Engine**: Godot 4.8-beta3 | **Risk**: HIGH
**Engine Notes**: The `.res` round trip and cache identity are VERIFIED by probe (`prototypes/collision-spike/out/probe_adr45_*`). Scripts the baker touches are `@tool` and loaded by `preload("res://...")` path, not `class_name` (ADR-0005 NV-7).

---

## Acceptance Criteria

*Each criterion cites its source (GDD AC id, ADR Validation Criteria, or `architecture.md`).*

- [ ] **HUD.** Lap, position, item and timer read the new core (`RaceRanking`, `CourseProgress`, Items); the minimap draws from `CourseData` routes, with no per-frame track scan.
- [ ] **Race flow.** Countdown, start, finish and results run on the new core for Castle Circuit, offline and online.
- [ ] **Budget.** HUD, minimap and audio together <= 0.5 ms p95 per rendered frame (`architecture.md` Performance Budgets).
- [ ] **Screenshots.** A retained screenshot of each screen touched (lobby, countdown, race HUD, results) in `production/qa/evidence/core-rebuild-story-057/`.

---

## Implementation Notes

- `UiTheme` is shared data in `src/data/`; port layouts, do not redesign them.

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 059: race audio.

---

## Files

*Planned; `/dev-story` replaces this list with the files it changed.*

- `src/presentation/hud/race_hud.gd`, `src/presentation/hud/minimap.gd`, `src/gameplay/race/race_flow.gd` (new)
- `production/qa/evidence/core-rebuild-story-057/` (screenshots)

---

## QA Test Cases

*N/A — QL-STORY-READY not run in this autonomous drafting pass; implement against the Acceptance Criteria above.*

---

## Test Evidence

**Story Type**: UI
**Required evidence**: a retained screenshot of each screen touched, in `production/qa/evidence/core-rebuild-story-057/`
**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: `production/epics/core-rebuild/story-056-castle-network-switch.md`
- Unlocks: `production/epics/core-rebuild/story-060-checkpoint-a2-castle-online.md`
