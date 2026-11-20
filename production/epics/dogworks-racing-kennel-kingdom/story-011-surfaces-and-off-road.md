# Story 011: Surfaces and off-road

> **Epic**: Dogworks Racing: Kennel Kingdom
> **Status**: Ready
> **Layer**: Core
> **Type**: Visual/Feel
> **Estimate**: M
> **Build step**: core
> **Manifest Version**: N/A (minimal — no control manifest)
> **Last Updated**: —

## Context

**GDD**: `design/game-brief.md` and `design/references/track-features-catalog.md` (features #1, #2, #3, #4, #45)
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

- [ ] Off-road surfaces beside the road slow karts by type (grass, sand, mud, rubble), with values in data per surface.
- [ ] A boost (drift boost, pad or War Horn) carries a kart through off-road at speed, so cutting a corner is a risk/reward choice.
- [ ] Shallow water and puddles (moat shallows, dungeon puddles) slow karts slightly and splash.
- [ ] Slick surfaces (wet stone, spilled oil) reduce grip briefly.
- [ ] One visual language for track features (art bible Section 4): boosts, ramps, off-road, slick and hazards each look the same everywhere.
- [ ] Online: every feature here follows the catalog's sync rule (Local, Clock or Cosmetic where possible; one host or owner Event only for shared world state; never shared kart-pushed physics objects), and the 12-racer stress test stays clean (all PCs agree, 0 errors).
- [ ] `tools/track_check.gd` passes on both tracks, with checks added for this story's features; retained screenshots of each feature, and the user signs off.

---

## Implementation Notes

- Can start right after 007 on the flat tracks.
- Starts after story 007 (the first version is finished first, in order).

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 008: ramps and height.
- Story 014: tricks.

---

## Files

- `src/track/`, `src/vehicle/`, `src/main.gd`, `assets/tracks/*/`, `tools/track_check.gd` (planned; `/dev-story` lists the real files)

---

## QA Test Cases

*N/A — no qa-lead specs at this tier; implement against the Acceptance Criteria above*

---

## Test Evidence

**Story Type**: Visual/Feel
**Required evidence**: retained screenshots in `production/qa/evidence/` + sign-off in `production/qa/evidence/story-011-surfaces-and-off-road-evidence.md`
**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: `story-007-race-flow-hud-sound.md`
- Unlocks: `story-013-pack-racing-speed.md`
