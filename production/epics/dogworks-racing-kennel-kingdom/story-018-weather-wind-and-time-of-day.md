# Story 018: Weather, wind and time of day

> **Epic**: Dogworks Racing: Kennel Kingdom
> **Status**: Ready
> **Layer**: Presentation
> **Type**: Visual/Feel
> **Estimate**: M
> **Build step**: core
> **Manifest Version**: N/A (minimal — no control manifest)
> **Last Updated**: —

## Context

**GDD**: `design/game-brief.md` and `design/references/track-features-catalog.md` (features #36, #37, #38)
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

- [ ] Wind gusts push karts sideways in exposed places (the ramparts, the bridge), shown by blowing banners and leaves.
- [ ] Track variants: Castle Circuit at sunset and at night (torch-lit) and in rain (wet, slicker stone); the host picks one in the lobby.
- [ ] Darkness rule: dark areas keep light pools on the racing line and track edges (art bible Section 2).
- [ ] Online: every feature here follows the catalog's sync rule (Local, Clock or Cosmetic where possible; one host or owner Event only for shared world state; never shared kart-pushed physics objects), and the 12-racer stress test stays clean (all PCs agree, 0 errors).
- [ ] `tools/track_check.gd` passes on both tracks, with checks added for this story's features; retained screenshots of each feature, and the user signs off.

---

## Implementation Notes

- After the graphics pass (010), which sets the lighting pipeline.
- Starts after story 007 (the first version is finished first, in order).

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 016: set pieces.

---

## Files

- `src/track/`, `src/vehicle/`, `src/main.gd`, `assets/tracks/*/`, `tools/track_check.gd` (planned; `/dev-story` lists the real files)

---

## QA Test Cases

*N/A — no qa-lead specs at this tier; implement against the Acceptance Criteria above*

---

## Test Evidence

**Story Type**: Visual/Feel
**Required evidence**: retained screenshots in `production/qa/evidence/` + sign-off in `production/qa/evidence/story-018-weather-wind-and-time-of-day-evidence.md`
**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: `story-010-graphics-pass.md`
- Unlocks: None
