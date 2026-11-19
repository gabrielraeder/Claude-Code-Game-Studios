# Story 001: Driving and 3-tier drift boost

> **Epic**: Dogworks Racing: Kennel Kingdom
> **Status**: Complete
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
- [ ] Drift feel is at least as good as prototype 1 (the user judged it "good enough" there): the user plays it and signs off. *(signed off 2026-11-19)*

*Added at `/story-done` 2026-11-19 (user's decisions on the AI's own calls):*

- [ ] R no longer restarts the race. Restart stays in the pause menu and on the finish screen (Start / A).
- [ ] The race starts with a 3-2-1 countdown (visual numbers; the war-horn sound is story 007). While it counts down the kart is held, and pressing accelerate at the right moment gives a start boost (3 levels by timing, higher for a better start; pressing too early gives a short penalty). Timing windows and boost levels live in the vehicle data file. Start-boost durations follow the user's notes: levels 1 / 2 / 3 last 1.4 / 1.7 / 2.0 s.
- [ ] The wall and bump response is parameterised in `VehicleStats`, as a light scrape versus a hard impact by angle, plus a hit-slowdown profile (deceleration, duration, minimum speed), using the numbers in the user's notes at `C:\rea\reverse-engineer\docs\design\01-veiculos-e-fisica.md`:
  - **Wall scrape:** at 10–40°, grip ×0.45.
  - **Wall impact:** at 15–85°, loses up to 60% speed and slides 0.25 s.
  - **Turn-back:** the wall turns the car back toward the track at 30–90 °/s.
  - **Hit-slowdown profiles:** light / medium / heavy last 0.3 / 0.3 / 0.6 s, with minimum speeds 60 / 44 / 32 mph.
  - **Scaling:** times, angles and percentages are used directly. Speeds and decelerations are scaled as a share of top speed (their car tops at 115 mph, ours at `max_speed`).
  - **Hit immunity:** 0.6 s after a hit.
  - Only the profile data is needed here; story 004 applies the hit profiles to items.
- [ ] Every visual constant in `kart_visual.gd` (and the chase camera's numbers) moves to data, in a visual section of the vehicle data file (or a sibling resource), using the user's notes where a number exists:
  - **Drift hop:** lasts 0.4 s (the notes' drift entry time).
  - **Drift body angle:** 25° / 45° / 55° (min / default / max). *Changed after play (2026-11-19): the user found 45° turned too far at once; it is now 15° / 23° / 30° and eases in over about 0.4 s. The notes' angles describe the car against its path, which the physics already produces, so they are not added again as a body twist.*
  - **Body lean:** limits from the notes' weight transfer (20 forward / 30 sideways).
  - **Wheel visual radius:** 0.35.
  - **No-number values:** the flame size, the spark pulse and the camera keep their current values, now as data.
  - **Drift tiers are unchanged:** 0.9 / 1.9 / 3.0 s, as signed off. The notes' 1.8 / 4.4 / 7.0 s are not used unless the user asks.
  - The user re-checks the look after this change.

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
- `src/vehicle/hit_slowdown_profile.gd`
- `src/vehicle/kart_driver.gd`
- `src/vehicle/kart_input.gd`
- `src/vehicle/kart_sim.gd`
- `src/vehicle/kart_visual.gd`
- `src/vehicle/start_sequence.gd`
- `src/vehicle/vehicle_stats.gd`
- `src/vehicle/vehicle_visual_stats.gd`
- `assets/data/vehicles/armored_cart.tres`
- `project.godot` (name + main scene; approved deviation)
- `production/qa/evidence/story-001-driving-and-drift/` (round 1 and round2/ screenshots, run CSVs, stamp.txt)

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

## Completion Notes
**Completed**: 2026-11-19
**Criteria**: 12/12 passing (no deferred items)
**Deviations**: ADVISORY — the placeholder cart's block sizes are literals in `src/vehicle/kart_visual.gd` (logged as TD-001; story 006 replaces the model). OUT OF SCOPE — `project.godot` name and main scene (approved).
**Test Evidence**: waived at qa.level minimal; retained screenshots and sign-off in `production/qa/evidence/story-001-driving-and-drift/` and `production/qa/evidence/story-001-driving-evidence.md`
**Reviewed by**: self, no independent review

## Calls beyond the design
- Start button opens the pause menu; the start menu shows at launch (`src/main.gd`, `src/ui/pause_menu.gd`) · kept 2026-11-19
- Kart visuals and camera are smoothed between physics steps (`src/vehicle/kart_visual.gd`, `src/test_track/chase_camera.gd`) · kept 2026-11-19
- Start boost windows 0.15 / 0.35 / 0.6 s before GO, stall 1.0 s, start messages and green "GO!" (`assets/data/vehicles/armored_cart.tres`, `src/ui/race_hud.gd`) · kept 2026-11-19
- Wall scrape below 25° and impact from 25°, slide grip 2.2, turn-back rate by angle, 1.4 bounce on every wall contact (`src/vehicle/kart_sim.gd`, `armored_cart.tres`) · kept 2026-11-19
- Hit slowdown read as a share of top speed lost per second (`src/vehicle/hit_slowdown_profile.gd`) · kept 2026-11-19
- Body lean 4° pitch / 6° roll; drift body twist 15° / 23° / 30° easing in over about 0.4 s (`armored_cart.tres`) · kept 2026-11-19
