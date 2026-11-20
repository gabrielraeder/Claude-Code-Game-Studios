# Story 003: Two tracks with shortcuts

> **Epic**: Dogworks Racing: Kennel Kingdom
> **Status**: In Progress
> **Layer**: Core
> **Type**: Visual/Feel
> **Estimate**: L
> **Build step**: core
> **Manifest Version**: N/A (minimal — no control manifest)
> **Last Updated**: 2026-11-19

## Context

**GDD**: `design/game-brief.md`
**Requirement**: Brief MVP feature 4

**ADR Governing Implementation**: N/A (minimal — no ADRs)
**ADR Decision Summary**: N/A (minimal — no ADRs)
**ADR Version**: N/A (minimal — no ADRs)

**Engine**: Godot 4.8-beta3 | **Risk**: HIGH
**Engine Notes**: none (no ADR engine-compatibility analysis at minimal)

**Control Manifest Rules (this layer)**: N/A (minimal — no control manifest)

---

## Acceptance Criteria

*From the brief's Goal & fail state and Features item 4:*

- [ ] Castle Circuit: a looping 3D track with a centerline, walls, start grid, lap counting and 3 laps, and a storybook-medieval look (castle stone, grass, parchment-colored banners).
- [ ] Castle Circuit has 2 shortcuts: the drawbridge and the secret passage. Each is faster than the main line only if taken well (a skill cost, such as a drift boost or a narrow gap).
- [ ] Dungeon Depths: a second track with dark stone, torchlight and lava glow, and 2 shortcuts: a mine-cart rail and a lava-gap jump.
- [ ] Both tracks are wide enough for 12 karts side by side at the start, with a 12-slot grid.
- [ ] Wall clamping and lap and progress tracking work on both tracks without cutting corners.
- [ ] The track is chosen by data (a track resource), so the lobby can pick it (story 007).
- [ ] Each track's character reads in a retained screenshot (the user signs off on the look).

*Added after the user saw the first Castle Circuit (2026-11-19): "the track is a lot simple, should be way more complex".*

- [ ] **Richer layout (both tracks, still flat):** lap length, corner count and variety (hairpins, sweepers, S-bends, chicanes), road width changes, split roads and themed zones per lap follow `design/references/track-design-reference.md` (patterns studied from Mario Kart, Sonic Racing and other kart racers; layouts and looks stay original, nothing copied).
- [ ] **Denser scenery:** each zone of a lap has its own landmark and props (castle walls, village streets, keep, moat, banners, crowds as simple low-poly shapes), so the track reads as a place, not a road in a field, and still runs smoothly with 12 racers.
- [ ] `tools/track_check.gd` passes on both tracks (laps, grid, shortcut rewards, no skipped checkpoints) and the 12-racer stress test stays clean.

---

## Implementation Notes

- Build Castle Circuit first and play it before starting Dungeon Depths (the brief's Build order puts Dungeon Depths after items, bots and racers; do it last in this story, or ask to split it out).
- Reference only: the prototype's Catmull-Rom centerline and window search. Shortcuts need checkpoints so lap progress cannot be skipped by cutting the track.
- Placeholder art is acceptable; the look follows the brief.

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 004: item boxes' behavior (the boxes' spots can be placed here).
- Story 007: track-select UI.
- More than 2 tracks.

---

## Files

- `src/track/` (centerline, checkpoints, track resource)
- `assets/tracks/castle_circuit/`, `assets/tracks/dungeon_depths/`
- `production/qa/evidence/story-003-tracks-evidence.md`

---

## QA Test Cases

*N/A — no qa-lead specs at this tier; implement against the Acceptance Criteria above*

---

## Test Evidence

**Story Type**: Visual/Feel
**Required evidence**: a retained screenshot in `production/qa/evidence/` + sign-off in `production/qa/evidence/story-003-tracks-evidence.md`
**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: `story-001-driving-and-drift.md`
- Unlocks: `story-004-items.md`, `story-005-tougher-bots.md`, `story-007-race-flow-hud-sound.md`
