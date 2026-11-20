# Story 015: Lap evolution: the track changes on laps 2 and 3

> **Epic**: Dogworks Racing: Kennel Kingdom
> **Status**: Ready
> **Layer**: Core
> **Type**: Integration
> **Estimate**: L
> **Build step**: core
> **Manifest Version**: N/A (minimal — no control manifest)
> **Last Updated**: —

## Context

**GDD**: `design/game-brief.md` and `design/references/track-features-catalog.md` (features #6, #16, #17, #28, #40, #43)
**Requirement**: Track features after the first version (added by the user 2026-11-20: "finish all 7, then these new features"; compare with Mario Kart, Sonic Racing, Crash Team Racing; patterns only, nothing copied)

**ADR Governing Implementation**: N/A (minimal — no ADRs)
**ADR Decision Summary**: N/A (minimal — no ADRs)
**ADR Version**: N/A (minimal — no ADRs)

**Engine**: Godot 4.8-beta3 | **Risk**: HIGH
**Engine Notes**: none (no ADR engine-compatibility analysis at minimal)

**Control Manifest Rules (this layer)**: N/A (minimal — no control manifest)

---

## Acceptance Criteria

*From the features catalog (`design/references/track-features-catalog.md`) and the art bible (`design/art/art-bible.md`):*

- [ ] Lap stages: when the leader crosses the line, the host announces the next stage and every PC changes the track at the same race time (a route opens, a gate closes, a bridge falls).
- [ ] Crumbling flagstones in Dungeon Depths sink stage by stage, opening or closing lines.
- [ ] The leader rings a bell to pick the next lap's route (if time allows).
- [ ] A siege breach on Castle Circuit: a wall is battered open on screen and becomes a new route; a destructible fence opens a shortcut.
- [ ] A herald's callouts announce track changes (text and sound).
- [ ] Online: every feature here follows the catalog's sync rule (Local, Clock or Cosmetic where possible; one host or owner Event only for shared world state; never shared kart-pushed physics objects), and the 12-racer stress test stays clean (all PCs agree, 0 errors).
- [ ] `tools/track_check.gd` passes on both tracks, with checks added for this story's features; retained screenshots of each feature, and the user signs off.

---

## Implementation Notes

- Lap changes trigger on the leader's crossing, announced by the host (catalog sync rule), so all PCs see the same track.
- Starts after story 007 (the first version is finished first, in order).

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 016: background set pieces.

---

## Files

- `src/track/`, `src/vehicle/`, `src/main.gd`, `assets/tracks/*/`, `tools/track_check.gd` (planned; `/dev-story` lists the real files)

---

## QA Test Cases

*N/A — no qa-lead specs at this tier; implement against the Acceptance Criteria above*

---

## Test Evidence

**Story Type**: Integration
**Required evidence**: a documented playtest or integration test (waived at qa.level minimal) + retained screenshots of each feature
**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: `story-008-elevation.md`, `story-009-moving-hazards.md`, `story-005-tougher-bots.md`
- Unlocks: `story-016-set-pieces-and-spectator-cam.md`
