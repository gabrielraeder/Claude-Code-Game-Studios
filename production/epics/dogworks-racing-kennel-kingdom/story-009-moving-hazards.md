# Story 009: Moving track hazards

> **Epic**: Dogworks Racing: Kennel Kingdom
> **Status**: Complete
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

## Completion Notes
**Completed**: 2026-11-21
**Criteria**: 4/6 passing (deferred to the owner's play: the drawbridge on a timer, and the extra moving hazards on both tracks; both are covered by scripted runs and retained images)
**Deviations**: Built on story 008 while it was still In Progress (waiting for the owner's feel sign-off), with the owner's "Proceed anyway" on 2026-11-21. Also fixed a story 004 logging bug found by the Dungeon item test: when one spill hit two karts, the second HIT line lost its item id.
**Test Evidence**: production/qa/evidence/story-009-moving-hazards-evidence.md (scripted autopilot runs, 11 bot races, 2 and 3 PC hazard comparisons, track_check, a screenshot of each hazard); waived test files at qa.level minimal
**Reviewed by**: self, no independent review

## Calls beyond the design
- Hazards are pure functions of the synced race time, with hits decided by the victim's PC · `src/track/hazard_manager.gd`, `src/vehicle/kart_sim.gd` · kept 2026-11-21
- Castle drawbridge: 20 s cycle, rise at 12 s, 1.2 s transition, 1.5 s warning with lantern and horn, raised 43% of the time, 18 m deck; a kart on the raised deck sinks and respawns on the main road · `tools/gen_castle_circuit.py` (`castle_circuit.tres`) · kept 2026-11-21
- Barrels: 3 at 9 m/s on a 10 s cycle, lanes ±2.6 and 0, visible 1.5 s wait at the top, medium spin; portcullis closed 29.5% of a 20 s cycle, stops the kart (no sink), always out of phase with the drawbridge; bots time both with a per-personality risk (Hothead 0.8, Careful 0, Shortcut Hunter 0.9) · `tools/gen_castle_circuit.py`, `assets/data/ai/bot_set.tres` · kept 2026-11-21
- Dungeon: 3 lava bursts on a 7.5 s cycle with a bubbling warning dome, at most one up, spin with scorch puff; solid ore cart shuttling 18 m in its own lane on a rail widened to 3.25 m half width, heavy hit profile and a push to the free lane · `tools/gen_dungeon_depths.py` (`dungeon_depths.tres`) · kept 2026-11-21
- Hazard sounds reuse existing wavs (barrel roll, drawbridge, portcullis, burst, cart) · `assets/data/audio/audio_set.tres` · kept 2026-11-21
