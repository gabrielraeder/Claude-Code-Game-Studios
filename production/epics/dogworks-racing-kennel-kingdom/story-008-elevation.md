# Story 008: Track elevation: hills, jumps, banking and a crossover

> **Epic**: Dogworks Racing: Kennel Kingdom
> **Status**: Ready
> **Layer**: Core
> **Type**: Visual/Feel
> **Estimate**: L
> **Build step**: core
> **Manifest Version**: N/A (minimal — no control manifest)
> **Last Updated**: —

## Context

**GDD**: `design/game-brief.md`
**Requirement**: Brief MVP feature 4 (tracks: elevation, added by the user 2026-11-19)

**ADR Governing Implementation**: N/A (minimal — no ADRs)
**ADR Decision Summary**: N/A (minimal — no ADRs)
**ADR Version**: N/A (minimal — no ADRs)

**Engine**: Godot 4.8-beta3 | **Risk**: HIGH
**Engine Notes**: none (no ADR engine-compatibility analysis at minimal)

**Control Manifest Rules (this layer)**: N/A (minimal — no control manifest)

---

## Acceptance Criteria

*From the brief's Features item 4 and the user's request ("should be way more complex", use Mario Kart, Sonic and other kart racers as examples; patterns only, nothing copied):*

- [ ] Karts drive on a track with height: hills and dips, banked corners, and at least one crossover (the road passes over or under itself).
- [ ] Jumps: a ramp launches a kart into the air, it lands and drives on; a well-timed jump can pay a small boost, as in the genre.
- [ ] Driving, drift, boosts, walls, kart bumping, item hits (story 004) and the online sync all work with height (karts on a bridge and under it never collide; remote karts are drawn at the right height).
- [ ] Falling off the track (off a jump or a ledge) puts the kart back on the road after a short delay, with brief immunity (the user's notes, section 7.4).
- [ ] Castle Circuit and Dungeon Depths each gain elevation where it suits them (castle ramparts, a climb to the keep, a drop into the dungeon), following `design/references/track-design-reference.md`.
- [ ] `tools/track_check.gd` covers height (no falling through the road, a crossover never mixes levels) and the 12-racer stress test stays clean.

---

## Implementation Notes

- The driving model is flat today (2D XZ-plane kinematics). This story adds height: a height profile per road and per branch, vertical velocity for jumps, gravity and landing; track queries must tell stacked roads apart at a crossover.
- The user's notes (`C:\rea\reverse-engineer\docs\design\01-veiculos-e-fisica.md`, sections 3.8 and 7.4) give air-control and respawn numbers.

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 009: moving hazards.
- Flying or underwater vehicle modes.

---

## Files

- `src/track/`, `src/test_track/` (height profile, stacked-road queries), `src/vehicle/kart_sim.gd` (vertical motion, jumps, respawn)
- `assets/tracks/castle_circuit/`, `assets/tracks/dungeon_depths/`
- `tools/track_check.gd`

---

## QA Test Cases

*N/A — no qa-lead specs at this tier; implement against the Acceptance Criteria above*

---

## Test Evidence

**Story Type**: Visual/Feel
**Required evidence**: a retained screenshot in `production/qa/evidence/` + sign-off in `production/qa/evidence/story-008-elevation-evidence.md`
**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: `story-003-tracks-and-shortcuts.md`
- Unlocks: `story-009-moving-hazards.md`
