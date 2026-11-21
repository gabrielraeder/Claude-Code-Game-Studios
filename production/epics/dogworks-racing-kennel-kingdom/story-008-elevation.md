# Story 008: Track elevation: hills, jumps, banking and a crossover

> **Epic**: Dogworks Racing: Kennel Kingdom
> **Status**: In Progress
> **Layer**: Core
> **Type**: Visual/Feel
> **Estimate**: L
> **Build step**: core
> **Manifest Version**: N/A (minimal — no control manifest)
> **Last Updated**: 2026-11-21

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

- [ ] **The road surface tilts, not only climbs** (the user: "in these games it's not always a plane, it often changes the angle, for example following the curves"): corners are banked into the turn, some bends are off-camber, roads crest and dip, and the tilt changes smoothly along the track. The kart sits on and leans with the surface, steers and drifts correctly on a bank, and the camera rolls slightly with it.
- [ ] Karts drive on a track with height: hills and dips, and at least one crossover (the road passes over or under itself).
- [ ] Jumps: a ramp launches a kart into the air, it lands and drives on; a well-timed jump can pay a small boost, as in the genre.
- [ ] Driving, drift, boosts, walls, kart bumping, item hits (story 004) and the online sync all work with height (karts on a bridge and under it never collide; remote karts are drawn at the right height).
- [ ] Falling off the track (off a jump or a ledge) puts the kart back on the road after a short delay, with brief immunity (the user's notes, section 7.4).
- [ ] Both tracks are rebuilt with banking and elevation as part of the improved tracks: Castle Circuit and Dungeon Depths each gain elevation where it suits them (castle ramparts, a climb to the keep, a drop into the dungeon), following `design/references/track-design-reference.md`.
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

- `tools/gen_castle_circuit.py`, `tools/gen_dungeon_depths.py`, `tools/elevation_profile.py` (new) → `assets/tracks/castle_circuit/`, `assets/tracks/dungeon_depths/` (regenerated with heights, banks, ramps, the barbican spiral)
- `assets/tracks/test_elevation/` (new verification track), `src/track/track_library.gd`
- `src/test_track/track_data.gd`, `track_model.gd`, `track_mesh.gd`, `chase_camera.gd`, `material_prewarm.gd` (new)
- `src/track/track_ramp.gd` (new), `track_branch.gd`, `track_hazard.gd`, `track_theme.gd`, `track_scenery.gd`
- `src/vehicle/kart_sim.gd`, `vehicle_stats.gd`, `kart_visual.gd`, `vehicle_visual_stats.gd`; `assets/data/vehicles/armored_cart.tres`, `war_bike.tres`
- `src/net/kart_wire.gd` (VERSION 9), `src/net/remote_kart.gd`
- `src/items/item_manager.gd`, `item_set.gd`; `src/ai/bot_driver.gd`, `bot_set.gd`, `assets/data/ai/bot_set.tres`
- `src/main.gd`, `src/debug/autopilot_driver.gd`, `debug_harness.gd`, `debug_options.gd`
- `tools/track_check.gd` (height checks, bot mode fixed), `tools/scenery_road_audit.gd`, `tools/elevation_probe.gd`, `tools/level_probe.gd`, `tools/item_level_probe.gd` (new)
- `production/qa/evidence/story-008-elevation-evidence.md`, `production/qa/evidence/story-008-elevation/`

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
