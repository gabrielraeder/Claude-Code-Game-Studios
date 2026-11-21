# Story 009: Moving track hazards

> **Epic**: Dogworks Racing: Kennel Kingdom
> **Status**: In Progress
> **Layer**: Core
> **Type**: Integration
> **Estimate**: L
> **Build step**: core
> **Manifest Version**: N/A (minimal — no control manifest)
> **Last Updated**: 2026-11-21

## Context

**GDD**: `design/game-brief.md`
**Requirement**: Brief MVP feature 4 (tracks: moving hazards, added by the user 2026-11-19)

**ADR Governing Implementation**: N/A (minimal — no ADRs)
**ADR Decision Summary**: N/A (minimal — no ADRs)
**ADR Version**: N/A (minimal — no ADRs)

**Engine**: Godot 4.8-beta3 | **Risk**: HIGH
**Engine Notes**: none (no ADR engine-compatibility analysis at minimal)

**Control Manifest Rules (this layer)**: N/A (minimal — no control manifest)

---

## Acceptance Criteria

*From the brief's Features item 4 and the user's request ("should be way more complex", use Mario Kart, Sonic and other kart racers as examples; patterns only, nothing copied):*

- [ ] Castle Circuit's drawbridge rises and lowers on a timer: while raised, the shortcut is closed and a kart that tries it is stopped at the edge (or falls into the moat and is put back on the road).
- [ ] At least two more moving hazards across the two tracks, for example rolling barrels down a village street and a portcullis gate on a timer; Dungeon Depths gets lava bursts or a moving mine cart.
- [ ] Hazards are synchronized online: every PC sees each hazard in the same state at the same race time.
- [ ] A hazard hit uses the hit-slowdown profiles from story 001 and the victim-decides rule from story 004.
- [ ] Bots (story 005) know about hazards at a basic level (wait for the drawbridge, avoid barrels).
- [ ] Hazard timings and positions live in the track data; `tools/track_check.gd` checks that a hazard never blocks the main road completely.

---

## Implementation Notes

- Timed hazards can be pure functions of the synced race time, so every PC agrees without sending extra messages.

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 008: elevation (hazards that need height come after it).

---

## Files

- `src/track/track_mover.gd`, `hazard_manager.gd`, `mover_view.gd` (new: hazard data, runtime, visuals)
- `src/test_track/track_data.gd`, `track_mesh.gd`, `src/track/track_branch.gd`
- `src/vehicle/kart_sim.gd`, `kart_visual.gd` (hazard hits, stop, push-off, scorch puff)
- `src/ai/bot_driver.gd`, `bot_set.gd`, `bot_personality.gd`, `bot_context.gd`, `assets/data/ai/bot_set.tres` (gate timing, barrel lanes, cart meeting)
- `src/items/item_manager.gd` (HIT log keeps the item id)
- `src/main.gd`, `src/debug/debug_options.gd`, `debug_harness.gd`, `autopilot_driver.gd`
- `tools/gen_castle_circuit.py`, `tools/gen_dungeon_depths.py` → `assets/tracks/castle_circuit/`, `assets/tracks/dungeon_depths/`
- `assets/data/audio/audio_set.tres` (hazard sound events, existing wavs)
- `tools/track_check.gd` (check 17), `tools/hazard_compare.py` (new)
- `production/qa/evidence/story-009-moving-hazards-evidence.md`, `production/qa/evidence/story-009-moving-hazards/`

---

## QA Test Cases

*N/A — no qa-lead specs at this tier; implement against the Acceptance Criteria above*

---

## Test Evidence

**Story Type**: Integration
**Required evidence**: `tests/integration/hazards/` OR a documented playtest (waived at qa.level minimal) + a retained screenshot of each hazard
**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: `story-003-tracks-and-shortcuts.md`, `story-004-items.md`, `story-008-elevation.md`
- Unlocks: None
