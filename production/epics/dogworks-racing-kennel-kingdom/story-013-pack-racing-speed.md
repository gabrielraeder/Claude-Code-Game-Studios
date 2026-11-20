# Story 013: Pack-racing speed: drafting, biscuits, jousting straight, vehicle routes

> **Epic**: Dogworks Racing: Kennel Kingdom
> **Status**: Ready
> **Layer**: Core
> **Type**: Logic
> **Estimate**: M
> **Build step**: core
> **Manifest Version**: N/A (minimal — no control manifest)
> **Last Updated**: —

## Context

**GDD**: `design/game-brief.md` and `design/references/track-features-catalog.md` (features #19, #32, #33, #35)
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

- [ ] Slipstream: driving close behind another kart charges a draft boost, shown with wind lines.
- [ ] Gold biscuits on the track raise top speed a little each (capped) and some are lost on a hit (story 004).
- [ ] The Jousting Lists straight (Castle Circuit): bumping a rival there gives both karts a short boost.
- [ ] Vehicle-gated routes: an alley only the war-bike fits through, and a fence only the armored cart can ram open.
- [ ] Online: every feature here follows the catalog's sync rule (Local, Clock or Cosmetic where possible; one host or owner Event only for shared world state; never shared kart-pushed physics objects), and the 12-racer stress test stays clean (all PCs agree, 0 errors).
- [ ] `tools/track_check.gd` passes on both tracks, with checks added for this story's features; retained screenshots of each feature, and the user signs off.

---

## Implementation Notes

- Uses story 001's bump response and story 006's vehicle classes.
- Starts after story 007 (the first version is finished first, in order).

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 014: air features.

---

## Files

- `src/track/`, `src/vehicle/`, `src/main.gd`, `assets/tracks/*/`, `tools/track_check.gd` (planned; `/dev-story` lists the real files)

---

## QA Test Cases

*N/A — no qa-lead specs at this tier; implement against the Acceptance Criteria above*

---

## Test Evidence

**Story Type**: Logic
**Required evidence**: a documented playtest or integration test (waived at qa.level minimal) + retained screenshots of each feature
**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: `story-004-items.md`, `story-006-racers-and-vehicles.md`
- Unlocks: None
