# Story 001: Driving and 3-tier drift boost

> **Epic**: Dogworks Racing: Kennel Kingdom
> **Status**: In Progress
> **Layer**: Core
> **Type**: Visual/Feel
> **Estimate**: M
> **Build step**: core
> **Manifest Version**: N/A (minimal — no control manifest)
> **Last Updated**: 2026-11-19

## Context

**GDD**: `design/game-brief.md`
**Requirement**: Brief MVP feature 1

**ADR Governing Implementation**: N/A (minimal — no ADRs)
**ADR Decision Summary**: N/A (minimal — no ADRs)
**ADR Version**: N/A (minimal — no ADRs)

**Engine**: Godot 4.8-beta3 | **Risk**: HIGH
**Engine Notes**: none (no ADR engine-compatibility analysis at minimal)

**Control Manifest Rules (this layer)**: N/A (minimal — no control manifest)

---

## Acceptance Criteria

*From the brief's Goal & fail state and Features item 1:*

- [ ] A cart accelerates, brakes and steers on a flat test loop, in the production code root (`src/`), written fresh (never imported from `prototypes/`).
- [ ] Hold-to-drift charges 3 tiers (about 0.9 / 1.9 / 3.0 s), with visible spark colors per tier; releasing gives a boost of about 0.7 / 1.1 / 1.6 s. Values live in data files, not hardcoded.
- [ ] Boosts never push speed past the cap through stacking (the prototype's 213 km/h bug stays fixed).
- [ ] Vehicle stats (top speed, acceleration, steering, drift tightness, bump knock-back) are one data resource per vehicle type, so the war-bike can be added later without code changes.
- [ ] Keyboard (WASD/arrows, Space drift, E item) and controller (triggers, left stick, RB drift, LB item) both drive the cart.
- [ ] Menus are reachable and usable from the controller too.
- [ ] Reversing over the start line does not count a lap, and 3 laps with a lap timer work on the test loop.
- [ ] Drift feel is at least as good as prototype 1 (the user judged it "good enough" there): the user plays it and signs off.

---

## Implementation Notes

- Reference only: `prototypes/kart-concept/kart.gd` (XZ-plane kinematic model, `max_lap` fix, acceleration cap at max speed).
- Production code is rewritten to production standards: doc comments on public APIs, typed GDScript, dependency injection over singletons.
- Design the kart so a remote copy can be driven by interpolated network state (story 002): input and simulation separate from the visuals.

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 002: networking.
- Story 003: real tracks.
- Story 004: items.
- Story 006: war-bike handling values and racer models.

---

## Files

- `src/debug/autopilot_driver.gd`
- `src/debug/debug_harness.gd`
- `src/debug/debug_options.gd`
- `src/input/input_actions.gd`
- `src/input/player_input_driver.gd`
- `src/main.gd`
- `src/main.tscn`
- `src/test_track/chase_camera.gd`
- `src/test_track/lap_counter.gd`
- `src/test_track/test_loop.tres`
- `src/test_track/track_data.gd`
- `src/test_track/track_mesh.gd`
- `src/test_track/track_model.gd`
- `src/ui/pause_menu.gd`
- `src/ui/race_hud.gd`
- `src/vehicle/kart_driver.gd`
- `src/vehicle/kart_input.gd`
- `src/vehicle/kart_sim.gd`
- `src/vehicle/kart_visual.gd`
- `src/vehicle/vehicle_stats.gd`
- `assets/data/vehicles/armored_cart.tres`
- `project.godot` (name + main scene; approved deviation)
- `production/qa/evidence/story-001-driving-and-drift/` (screenshots, run CSVs, stamp.txt)

## QA Test Cases

*N/A — no qa-lead specs at this tier; implement against the Acceptance Criteria above*

---

## Test Evidence

**Story Type**: Visual/Feel
**Required evidence**: a retained screenshot in `production/qa/evidence/` + sign-off in `production/qa/evidence/story-001-driving-evidence.md`
**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: None
- Unlocks: `story-002-online-multiplayer.md`, `story-003-tracks-and-shortcuts.md`, `story-006-racers-and-vehicles.md`
