# Story 019: Track traffic, triggered traps, flyovers and boost rings

> **Epic**: Dogworks Racing: Kennel Kingdom
> **Status**: Ready
> **Layer**: Core
> **Type**: Integration
> **Estimate**: M
> **Build step**: core
> **Manifest Version**: N/A (minimal — no control manifest)
> **Last Updated**: —

## Context

**GDD**: `design/game-brief.md` and `design/references/track-features-catalog.md` (features #24, #26, #34, #41)
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

- [ ] Traffic along the road: merchant carts in the village and ore carts in the mine move on clock-driven paths.
- [ ] Player-triggered traps: driving over a lever drops a portcullis or tips a cauldron on the karts behind (one Event, telegraphed).
- [ ] Flyovers: a falcon or griffin flies over and drops item crates on the road (clock-driven).
- [ ] Moving boost rings or gates that pay a boost only when hit at the right moment.
- [ ] Online: every feature here follows the catalog's sync rule (Local, Clock or Cosmetic where possible; one host or owner Event only for shared world state; never shared kart-pushed physics objects), and the 12-racer stress test stays clean (all PCs agree, 0 errors).
- [ ] `tools/track_check.gd` passes on both tracks, with checks added for this story's features; retained screenshots of each feature, and the user signs off.

---

## Implementation Notes

- Builds on story 009's hazard timers.
- Starts after story 007 (the first version is finished first, in order).

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 015: lap changes.

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

- Depends on: `story-009-moving-hazards.md`, `story-004-items.md`
- Unlocks: None
