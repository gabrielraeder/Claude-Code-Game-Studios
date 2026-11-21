# Story 006: Eight knight-dog racers and two vehicles

> **Epic**: Dogworks Racing: Kennel Kingdom
> **Status**: Complete
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

- `assets/characters/char_dog_{mascot,sunny,bolt,fern,violet,frost,cinder,skye}.glb` (new: the 8 dog models)
- `assets/vehicles/veh_cart_armored.glb`, `assets/vehicles/veh_bike_war.glb` (new: the vehicle models)
- `tools/blender/common.py`, `make_dogs.py`, `make_vehicles.py`, `render_previews.py` (new: model and preview scripts)
- `assets/data/vehicles/war_bike.tres`, `war_bike_notes.md`, `vehicle_set.tres` (new); `armored_cart.tres` (model block, pennant 1.45x)
- `assets/data/racers/racer_set.tres` (new: 8 racers and the pennant style)
- `assets/data/net/net_config.tres`, `src/net/net_config.gd` (art-bible slot colours, loadout_wait)
- `assets/data/ai/bot_set.tres`, `src/ai/bot_set.gd`, `src/ai/bot_driver.gd` (no drift start near open edges)
- `src/vehicle/racer_def.gd`, `racer_set.gd`, `vehicle_set.gd`, `pennant_style.gd`, `pennant.gd`, `spatial_vehicle_pennant_flag.gdshader`, `model_batcher.gd` (new)
- `src/vehicle/kart_visual.gd`, `vehicle_stats.gd`, `vehicle_visual_stats.gd` (model pipeline, wheels, rider motion, colours)
- `src/main.gd`, `src/net/net_session.gd`, `src/net/kart_wire.gd` (loadouts, sync, VERSION bump, netlog perf columns)
- `src/debug/debug_options.gd`, `src/debug/lineup_showcase.gd` (--racer, --vehicle, --lineup)
- `production/qa/evidence/story-006-racers-evidence.md`, `production/qa/evidence/story-006-racers/`

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

## Completion Notes
**Completed**: 2026-11-20
**Criteria**: 8/9 passing (racer colours on the minimap: they read on the 12-kart grid; the minimap itself is built in story 007)
**Deviations**: None. The item-box and on-road-scenery bug fixes (stories 003/004) were committed together with this story because they touch the same files; KartWire VERSION is now 5, so every PC needs this build.
**Test Evidence**: production/qa/evidence/story-006-racers-evidence.md (screenshots, net, lap, bot and fps runs, sign-off ticked); waived test files at qa.level minimal
**Reviewed by**: self, no independent review (engine check by godot-gdscript-specialist: findings fixed)

## Calls beyond the design
- Models are Blender-scripted .glb files; 8 racers named Sir Dogworks, Sunny, Bolt, Fern, Violet, Frost, Cinder, Skye with their breeds, colours and helmets · `tools/blender/`, `assets/characters/`, `assets/data/racers/racer_set.tres` · kept 2026-11-20 (owner plans to improve design and graphics later, story 010)
- Cart pennant pole 1.45x vehicle height, flag yawed 55 deg, unlit flag · `assets/data/vehicles/armored_cart.tres`, `src/vehicle/pennant_style.gd` · kept 2026-11-20
- War-bike: +30% accel, tighter turn and drift, drift charge 0.7/1.5/2.4 s, -4% top speed, knocked harder · `assets/data/vehicles/war_bike.tres` (reasons in `war_bike_notes.md`) · kept 2026-11-20
- Bots: dog = slot % 8, vehicle drawn from the race seed; no drift start near an unwalled edge · `src/main.gd`, `assets/data/ai/bot_set.tres` · kept 2026-11-20
- Host waits up to 3 s for each client's loadout; racer and vehicle chosen with --racer / --vehicle until story 007 · `assets/data/net/net_config.tres`, `src/debug/debug_options.gd` · kept 2026-11-20
