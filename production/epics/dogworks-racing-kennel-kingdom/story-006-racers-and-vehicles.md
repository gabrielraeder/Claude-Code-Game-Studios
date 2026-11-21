# Story 006: Eight knight-dog racers and two vehicles

> **Epic**: Dogworks Racing: Kennel Kingdom
> **Status**: In Progress
> **Layer**: Core
> **Type**: Visual/Feel
> **Estimate**: L
> **Build step**: core
> **Manifest Version**: N/A (minimal — no control manifest)
> **Last Updated**: 2026-11-20

## Context

**GDD**: `design/game-brief.md`
**Requirement**: Brief MVP feature 6

**ADR Governing Implementation**: N/A (minimal — no ADRs)
**ADR Decision Summary**: N/A (minimal — no ADRs)
**ADR Version**: N/A (minimal — no ADRs)

**Engine**: Godot 4.8-beta3 | **Risk**: HIGH
**Engine Notes**: none (no ADR engine-compatibility analysis at minimal)

**Control Manifest Rules (this layer)**: N/A (minimal — no control manifest)

---

## Acceptance Criteria

*From the brief's Goal & fail state and Features item 6:*

- [ ] The Dogworks mascot (red-and-white dog in a knight's helmet, from the DogworksTV logo) is a racer, built as a low-poly 3D model first.
- [ ] 7 more original knight dogs exist, of different breeds and colors, each clearly different at a glance from the chase camera.
- [ ] Two vehicle types: armored cart (steady, wide drifts, barely knocked by bumps) and war-bike (faster acceleration, tighter drifts, knocked harder). Handling differences come from vehicle data (story 001), not special-case code.
- [ ] Each vehicle flies its racer's pennant, and racer colors read on the minimap and in a 12-racer grid.
- [ ] Any racer can use any vehicle, and the choice is synced online so every PC shows the right model.
- [ ] A race with both vehicle types: the user judges the bike and cart to feel different.
- [ ] No Nintendo IP: no characters, names or look borrowed from Mario Kart.

---

## Implementation Notes

- Look: bright storybook-medieval low-poly, in the logo's bold style. Mascot red-orange and cream white.
- The vehicle choice is a lobby field; the picker UI is story 007.
- Placeholder models are acceptable first; the mascot comes first, then the war-bike's handling, then the other 7 dogs.

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 007: racer and vehicle pick screen.
- More vehicle types, kart parts, a garage, and character animation beyond basics.

---

## Files

- `assets/characters/` (dog models), `assets/vehicles/`
- `assets/data/vehicles/` (war-bike data)
- `src/vehicle/` (model swap and pennant)
- `production/qa/evidence/story-006-racers-evidence.md`

---

## QA Test Cases

*N/A — no qa-lead specs at this tier; implement against the Acceptance Criteria above*

---

## Test Evidence

**Story Type**: Visual/Feel
**Required evidence**: a retained screenshot in `production/qa/evidence/` + sign-off in `production/qa/evidence/story-006-racers-evidence.md`
**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: `story-001-driving-and-drift.md`
- Unlocks: `story-007-race-flow-hud-sound.md`
