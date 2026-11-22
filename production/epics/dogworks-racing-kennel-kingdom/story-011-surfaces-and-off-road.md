# Story 011: Surfaces and off-road

> **Epic**: Dogworks Racing: Kennel Kingdom
> **Status**: Complete
> **Layer**: Core
> **Type**: Visual/Feel
> **Estimate**: M
> **Build step**: core
> **Manifest Version**: N/A (minimal — no control manifest)
> **Last Updated**: 2026-11-21

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

- `src/track/surface_type.gd`, `surface_set.gd`, `track_surface.gd`, `track_wall_opening.gd` (new: surface data, zones, wall openings)
- `src/track/track_library.gd`, `track_mover.gd`, `track_ramp.gd`, `track_scenery.gd`, `track_theme.gd`, `hazard_manager.gd`, `mover_view.gd` (zones beside hazards, warn ring, scenery guard for zones)
- `src/test_track/track_data.gd`, `track_model.gd`, `track_mesh.gd` (zone grid, re-acquire, zone escape, zone ground and fences)
- `src/vehicle/kart_sim.gd`, `kart_visual.gd` (caps, drag, grip, slick tail, puffs)
- `src/ai/bot_driver.gd`, `bot_set.gd`, `assets/data/ai/bot_set.tres` (bots avoid or take zones)
- `src/audio/race_sound.gd`, `assets/data/audio/audio_set.tres` (surface sounds)
- `src/main.gd`, `src/debug/debug_options.gd`, `autopilot_driver.gd` (remote surface sampling, --auto-cut, --auto-boost, [surface] log)
- `assets/data/surfaces/surface_set.tres` (surface values)
- `tools/gen_castle_circuit.py`, `tools/gen_dungeon_depths.py`, `tools/gen_test_surfaces.py` → `assets/tracks/castle_circuit/`, `assets/tracks/dungeon_depths/`, `assets/tracks/test_surfaces/`
- `tools/track_check.gd` (surface checks), `tools/surface_probe.gd` (new)
- `production/qa/evidence/story-011-surfaces-and-off-road-evidence.md`, `production/qa/evidence/story-011-surfaces/`

## QA Test Cases

*N/A — no qa-lead specs at this tier; implement against the Acceptance Criteria above*

---

## Test Evidence

**Story Type**: Visual/Feel
**Required evidence**: retained screenshots in `production/qa/evidence/` + sign-off in `production/qa/evidence/story-011-surfaces-and-off-road-evidence.md`
**Status**: [x] Created (evidence doc and screenshots, sign-off approved 2026-11-21)

---

## Dependencies

- Depends on: `story-007-race-flow-hud-sound.md`
- Unlocks: `story-013-pack-racing-speed.md`

## Completion Notes
**Completed**: 2026-11-21
**Criteria**: 7/7 passing (1-4 and 6 accepted by the owner on the scripted runs and screenshots; 5 and 7 by track_check ALL PASS on both tracks, retained screenshots and the owner's look and feel sign-off)
**Deviations**: Advisory, logged as tech debt TD-004..TD-010 (`docs/tech-debt-register.md`): slick tail survives another surface and a respawn (TD-004, fix follows as its own commit); zone/opening checks, zone_escape cap and per-tick road search (TD-005, 006, 008: replaced by story 022 mesh collision); look values as consts (TD-007); no Dungeon puddle, no 12-PC or Dungeon 2-peer run (TD-009: puddle goes into story 025); respawn counted as prediction error (TD-010). QA lead GAPS: War Horn through off-road untested (tested with the TD-004 fix). Built at rigor minimal before the switch to standard: no GDD or ADR for this system.
**Test Evidence**: production/qa/evidence/story-011-surfaces-and-off-road-evidence.md (sign-off approved), production/qa/evidence/story-011-surfaces/part1..part3; Visual/Feel, no unit test required
**Reviewed by**: lead-programmer (LP-CODE-REVIEW: CONCERNS, accepted and logged); qa-lead (QL-TEST-COVERAGE: GAPS, advisory)

## Calls beyond the design
- Speed caps as a share of top speed: grass .55, sand .50, mud .40, rubble .60, shallows .75; slick grip .35 with a 0.6 s tail · `assets/data/surfaces/surface_set.tres` · kept 2026-11-21
- A boost lifts the cap on every off-road kind · `assets/data/surfaces/surface_set.tres` (`boost_ignores`) · kept 2026-11-21
- The moat ford is a safe detour (+0.61 s against the road), not a shortcut; turf and cinder cuts pay only with a boost (turf +0.65 s plain, -0.38 s boosted) · `tools/gen_castle_circuit.py`, `tools/gen_dungeon_depths.py` · kept 2026-11-21
- Zones: Castle turf cut, moat ford, village ale slick, kennel-yard mud; Dungeon cave rubble (two), cinder cut, cistern slime · the two generators · kept 2026-11-21
- Rubble gives a light bump (yaw 1.1, height 0.06); shallows allow drifting, grass, sand, mud and rubble end a drift · `assets/data/surfaces/surface_set.tres` · kept 2026-11-21
- Bots take a cut by personality (Shortcut Hunter most, Careful least) and steer around slicks · `src/ai/bot_driver.gd`, `assets/data/ai/bot_set.tres` · kept 2026-11-21
- The zone polygon is the boundary, with striped fences on its outer edges; a wall opening only removes the wall · `src/test_track/track_model.gd`, `track_mesh.gd` · kept 2026-11-21
