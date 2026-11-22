# Story 011 evidence: surfaces and off-road zones

Story: `production/epics/dogworks-racing-kennel-kingdom/story-011-surfaces-and-off-road.md`.

Built in three parts. Each part has a `STATE.md` with every step and number, under `production/qa/evidence/story-011-surfaces/part1..part3/` (logs in `runs/`):

- part 1: the surface system and the test track `test_surfaces`;
- part 2: zones on Castle Circuit and Dungeon Depths, bots, track_check (18), visual language;
- part 3: the network spike investigation, screenshots and this document.

## Surface table

Values from `assets/data/surfaces/surface_set.tres`. The cap is `max_speed_frac` x the cart's top speed of 26.0 m/s. Every kind has `boost_ignores = true`: a boost lifts the cap while it lasts.

| Kind | Cap frac (cap) | Drag 1/s | Grip | Steer | Drift | Decel | Tail s | Bump | Effect | Ground / pattern |
|---|---|---|---|---|---|---|---|---|---|---|
| grass | 0.55 (14.3 m/s) | 0.6 | 0.80 | 0.90 | no | 14 | 0 | - | dust puffs | green (0.435,0.627,0.353), brown speckle (0.451,0.361,0.224) |
| sand | 0.50 (13.0) | 0.8 | 0.70 | 0.85 | no | 16 | 0 | - | dust puffs | sand (0.788,0.682,0.463), darker speckle |
| mud | 0.40 (10.4) | 1.1 | 0.45 | 0.75 | no | 20 | 0 | - | mud puffs | brown (0.420,0.290,0.196), dark speckle |
| rubble | 0.60 (15.6) | 0.7 | 0.75 | 0.90 | no | 18 | 0 | yaw 1.1, h 0.06 | gravel puffs | grey (0.522,0.490,0.439), dark speckle |
| shallows | 0.75 (19.5) | 0.3 | 0.85 | 0.90 | yes | 12 | 0 | - | splash | pale cyan (0.373,0.647,0.753), wave dashes (stripe) |
| slick (on road) | 1.0 (none) | 0 | 0.35 | 1.00 | yes | 14 | 0.6 | - | none | slate (0.243,0.290,0.388) overlay, alpha 0.55, gloss 0.9, streaks |

## Zones per track

The s ranges are main-loop distances, from the generators and the part 2 runs. Size is the polygon's bounding box and area. Height is the ground height range of the polygon's vertices.

### Castle Circuit

| Zone | Kind | s range | Side | Size | Height (m) | Notes |
|---|---|---|---|---|---|---|
| tourney_turf | grass | curb opening s21-111, cut route 24.45 -> 110.37 | inside sweep1 | 27.0 x 47.8 m, 530 m2 | 0.14-0.84 | boost-cut, chord fence |
| kennel_yard | mud | ~s1086-1120, outside the hairpin2 exit | -1 | 29.8 x 11.5 m, 247 m2 | 0.00-0.61 | end fence tapered back to the road (YARD_TAPER 8) |
| moat_shallows | shallows | peels off s175.3, merges s284.6, off-road s177.8-281.1 (72.1 m) | lens side, beside the drawbridge | 58.1 x 33.3 m, 355 m2 | 0.00 | ford route 171.25 -> 290.57; 14 openings of 6 m |
| ale_spill | slick | s576-585 on the split main lane | on road | 10.2 x 7.9 m, 50 m2 | 4.50 | no fence |

### Dungeon Depths

| Zone | Kind | s range | Side | Size | Height (m) | Notes |
|---|---|---|---|---|---|---|
| cave_rubble_in | rubble | s300-326 | +1, 8 m deep | 20.3 x 20.2 m, 159 m2 | 0.52-1.06 | |
| cave_rubble_out | rubble | s460.1-480.3 | -1, 7 m deep | 14.0 x 13.5 m, 90 m2 | 1.07-2.27 | far edge tapered (SIDE_TAPER 7) |
| cinder_cut | sand | s899.2-973.8 inside forge90 (chord 47.3 vs road 74.5 m), route 897.23 -> 977.77 | inside | 34.4 x 33.2 m, 523 m2 | 5.34-7.00 | boost-cut, 8.9 m clear of the lava gap |
| cistern_slime | slick | s51.4-67.4, inside half of chic1 | on road | 8.6 x 15.6 m, 86 m2 | 6.45-7.05 | no fence |

## Results

### Part 1 (surface system, `test_surfaces`)

- Every speed settles at its cap in the main game, headless autopilot:
  - grass 14.3, sand 13.0, mud 10.4, rubble 15.6, shallows 19.5 m/s;
  - a boosted cut keeps 35.1 m/s across grass, and the cap returns when the boost ends.
- A drift ends on grass (`surface_drift_ends = 1`).
- track_check castle and dungeon were unchanged at that point: ALL PASS, 59 / 59.
- bot_race_test castle: 0 ERROR, 0 stuck.
- item_net castle: IDENTICAL, 23 hits on the host and both clients.
- fps (windowed, host + 11 bots, `test_surfaces`): min 59, median 60, worst frame 26.3 / 26.9 ms, draw calls max 372 / 353, 11/11 finished.

### Part 2 (Castle and Dungeon zones)

- **Caps reached (headless autopilot):**

  | Track | Zone | Result |
  |---|---|---|
  | Castle | turf, plain | 35 -> 14.2 m/s (cap 14.3) |
  | Castle | turf, boosted | 35.1 m/s across, boost 1.22 -> 0.15 |
  | Castle | ale slick | grip 0.35, 0.6 s tail |
  | Castle | ford, bridge raised | cap 19.5, 0 sinks |
  | Castle | kennel yard | cap 10.4 |
  | Dungeon | slime | grip 0.35 |
  | Dungeon | cinder, boosted | 35.1 m/s |
  | Dungeon | cinder, drift boost | cap 13 at the end |
  | Dungeon | rubble_out | 25 -> 12.7 m/s (cap 15.6) |

- **Boost-cut gains (track_check final, against the road):**
  - Castle turf: unboosted +0.65 s (slower), boosted with 1.6 s -0.38 s (faster).
  - Dungeon cinder: unboosted +0.80 s, boosted -0.25 s.
- **Ford:** lap 1 takes 44.28 s against 43.67 s by road (+0.61 s) with the drawbridge held up, 0 sinks. The ford is a safe detour, not a shortcut.
- **track_check final:** Castle ALL PASS (72 PASS), Dungeon ALL PASS (71 PASS). Check (18) covers:
  - placement;
  - open edges at the openings;
  - fences hold 40 starts;
  - a free line past the slick;
  - the routes.

  (16) and (17) pass.
- **Bots, final code:**
  - Castle 2 races: 11/11 x2, 0 stuck, 0 sinks, 1 boost-cut (Careful, turf, boost 0.87), 3 off-road (1 bump-caused).
  - Dungeon 2 races: 11/11 x2, 0 sinks, 1 stuck (Shortcut Hunter, crusher hairpin s536, 2.73 s, not a zone), 3 cinder cuts, 5 off-road (wanderers clipping forge90 while boosted).
  - Village lane taken 55/55 when planned, 52/55 plans (slick preference).
- **item_net, 1 lap:** Castle IDENTICAL x2 (27 hits), Dungeon IDENTICAL x2 (22 hits), 0 ERROR.
- **2-peer Castle:**
  - rc 0/0, 0 ERROR or WARNING.
  - `pred_err` max, host / client: 0.527 / 0.597 m (`peer_castle`) and 0.369 / 9.668 m (`peer_castle2`). The 9.668 m is explained below.
- **Exit check** (host + 3 bots, quit after 8 s): Castle rc 0, Dungeon rc 0, 0 ERROR.
- **fps** (windowed, host + 11 bots, 1 lap):

  | Track | min | median | worst frame | draw calls max |
  |---|---|---|---|---|
  | Castle | 60 / 59 | 60 | 31.0 / 29.6 ms | 576 / 602 |
  | Dungeon | 59 / 59 | 60 | 30.4 / 31.8 ms | 348 / 301 |

  0 ERROR, 0 segfault, 11/11 finished.

### Part 3: the 9.668 m prediction-error spike in `peer_castle2`

- **Which kart and when:** kart 0, the host's kart, which is a remote kart on the client.
  - At host t=6.53, s170.5, while side by side with the client's kart, the host's query moved onto the drawbridge approach (path 1).
  - The kart left that 2.5 m deck at t=6.57, sank in the moat, and respawned at t=7.67 on the approach again.
  - It sank again and respawned at t=9.47, s166.5. That respawn jumps from (23.58, 114.53) to (22.40, 105.12): 9.48 m, plus 7.5 m/s x 1/30 s, which is about the 9.668 m measured.
- **Why it shows as a prediction error:** `RemoteKart.push_snapshot` -> `NetStats.record_error` compares the velocity prediction with the next snapshot and has no teleport exclusion. A respawn jump therefore counts as an error.
  - The drawn kart is not affected: `update_view` already shows a teleport as a jump.
  - No zone code runs on remote karts: they are only interpolated, with no zone_escape and no zone height.
- **Not story 011:** the same host-autopilot moat fall and respawn pair at s~171 (t=7.53 s171.4, then t=9.73 s164) is in older logs:
  - story-008 part5 bots castle_circuit-1..3;
  - story-009 part1/part2 bots;
  - exit-crash `bot_race_castle`.
- **Rerun of the same command** (`part3/runs/peer_castle2_rerun`):
  - the bump-dependent fall did not recur;
  - client mud cap 10.4 reached again;
  - client `pred_err` avg 0.023, max 0.397 m;
  - host avg 0.024, max 0.966 m (in the t=11-12 window, kart bumps, before any zone);
  - 0 ERROR, rc 0/0.
- **No code fix.** Possible follow-up, outside story 011: exclude teleport-sized jumps from `record_error`, with the same reach rule as `update_view`.

### Part 3: client `--auto-cut` "did not trigger"

- `AutopilotDriver` now prints `[auto] CUT start` and `CUT done`; these are debug-only lines.
- A rerun (`part3/runs/peer_cut_repro2`) shows that the cut does trigger on the client: start at s24.9, lat 3.8; done at s103.1.
- The host's identical autopilot drives beside it, on the inside: host lat 5.4-7.4, client lat 3.9-5.7, over s26-86, 1.4-1.6 m apart, in contact (speeds flicker 32-35 m/s). The host boxes the client out of the turf until it is past the middle of the chord.
- From the same grid lateral, -2.5, alone (a scratch probe), the cut enters the grass by s34.
- **Verdict:** harmless, a debug-harness artefact of two identical autopilots side by side. It is not a client-only or gameplay problem. In `peer_castle2` the client did drive into the kennel-yard mud and reached cap 10.4.
- `peer_cut_repro2`: client `pred_err` max 0.587 m, 0 ERROR, rc 0/0.

## Visual language

| Meaning | Look | Where set |
|---|---|---|
| Boost pad | cyan #22E6E0 with white chevrons | TrackTheme defaults; the Dungeon theme was regenerated |
| Ramp | red (0.78, 0.25, 0.17) and cream | TrackRamp defaults and both generators |
| Off-road | brown speckle (0.451, 0.361, 0.224) on the zone ground, fences at its edges | SurfaceType pattern |
| Slick | slate overlay, glossy, with light streaks | SurfaceType slick: gloss 0.9, alpha 0.55 |
| Shallows | pale cyan with white wave dashes | SurfaceType shallows: stripe pattern |
| Incoming hazard | pulsing ember warn ring, only in WARNING, at the gate deck start, the barrel waiting spot or the vent | TrackMover warn_ring: pad 0.5, width 0.35, glow 3, pulse_grow 0.12, `color_warn` |

The table is also a `##` doc in `src/track/surface_set.gd`.

## Screenshots (opened and checked)

All under `production/qa/evidence/story-011-surfaces/part3/`, windowed, Godot 4.8-beta3.

| File | Shows |
|---|---|
| `shots_castle_A/at_s048.png`, `at_s062.png` | Turf boost-cut at 126 km/h: boost flame, grass puffs, brown speckle, chord fence on the right |
| `shots_castle_A/at_s579.png`, `at_s586.png` | Ale slick on the village lane: slate patch with a white streak, 93 km/h |
| `shots_castle_A/at_s1113.png`, `at_s1117.png` | Kennel-yard mud: 64 -> 39 km/h, brown speckled ground, mud puffs behind the wheels, yard fence |
| `shots_castle_B/at_s222.png`, `at_s245.png` | Moat shallows ford: pale cyan, wave dashes, splash puffs, striped fence posts both sides, the raised drawbridge standing up on the left, 69 km/h (cap 19.5 m/s) |
| `shots_warn_bridge/side_s250_d-58_l10.png` | Drawbridge in WARNING (hazard offset 11.2): ember warn ring at the deck start by the chains; the ford between the bridge and the road, with its fences |
| `shots_warn_bridge/side_s235_d-34_l12.png` | From above the ford: the moat sliver and the main road beyond, curb and fence |
| `shots_warn_vent/side_s345_d22_l9.png` | Dungeon lava vent `burst_shore_a` in WARNING (offset 2.3): ember ring around the glowing vent disc; the next vent bursting beyond it |
| `shots_warn/side_s345_d16_l7.png` | The same vent ACTIVE (offset 3.8): burst column, for comparison |
| `shots_dungeon_C/at_s056.png`, `at_s062.png` | Cistern slime slick: dark slate patch with lavender streaks. **Low contrast on the dark dungeon road**: readable up close, weak at a distance. Flagged for the look sign-off; not changed |
| `shots_dungeon_C/at_s925.png`, `at_s945.png` | Cinder cut, boosted, 126 km/h: sand ground with speckle, flame, dust puffs, fence toward the lava gap |
| `shots_dungeon_E2/at_s476.png` | Cave rubble (rubble_out): grey gravel speckle, gravel puffs, 55 km/h |
| `shots_dungeon_E2/at_s479.png` | The rubble's tapered end: 46 km/h, back at the curb, puffs stop |
| `shots_dungeon_D/at_s318.png` | Dungeon boost pad (cyan, streak chevrons) and the vent with its ring far ahead |
| `overview2_castle_circuit/overview.png` | Tilted overview, 55 deg: turf wedge in sweep1, ford beside the brown drawbridge in the moat lens, yard mud near the start |
| `overview2_dungeon_depths/overview.png` | Tilted overview, 55 deg: the cinder wedge (top left) reads; rubble and slime are too small and dark at this scale |

Stale or extra takes are kept, never deleted:

- `overview_*` shows the main menu over the track (run without `--autopilot`);
- `shots_dungeon_D/at_s326/334/466/472` and `shots_dungeon_E/*` are takes where the vent was too far or the kart was not yet in the rubble.

Part 1 and 2 shots: `part1/shots_*`, `part2/shots_castle_turf`, `part2/shots_castle_ford`.

No z-fighting of zone ground against the road was seen. No fence ran through a wall or a prop. Puffs were present on grass, mud, sand, rubble and shallows.

## Not verified

- The surface sounds (the `surface_splash` event and the repeats) have not been heard.
- How the surfaces feel for a human player: the cap snap, the slick tail and the rubble bump, with a pad or keyboard.
- The cistern slime's readability at racing distance on Dungeon (low contrast, see above). A brighter overlay would be a SurfaceType data change: `ground_color` / `overlay_alpha` for slick, or a per-track tint.
- Dungeon rubble and slime are hard to see in the top-down overview.
- The 9.668 m spike was not reproduced on the rerun, because the bump-dependent fall did not recur. The cause is established from the logs: the 9.48 m respawn jump, and the same fall in older stories.
- 2-peer runs were Castle only, no Dungeon 2-peer zone run.
- The stray `0.25` file at the repo root (part 2's height log) was moved to `part2/runs/peer_castle_height_log.csv`.

## Sign-off

- [x] Approved: look (zone grounds, fences, puffs, slick/shallows patterns, warn ring, visual-language colours; note the cistern slime contrast)
- [x] Approved: feel (caps, boost-cut trade-off, ford as a safe detour, slick tail, rubble bump)
