# Story 009 evidence: moving track hazards

Built in three parts. Each part has a `STATE.md` with every step and number, under `production/qa/evidence/story-009-moving-hazards/part1..part3/` (logs in `runs/`).

## Design

- Every hazard is a pure function of the synced race time, so every PC shows the same state without extra network messages.
- A hit is decided on the victim's PC, using the story 001 hit-slowdown profiles.
- Hazard data lives in the track data, written by the generators.

## The hazards

| Track | Hazard | Numbers |
|---|---|---|
| Castle | Drawbridge on a timer | 20 s cycle, raised 43% of the time, 1.5 s warning (lantern and horn). A kart reaching the raised deck sinks and respawns on the main road. |
| Castle | 3 rolling barrels on the market drop | 10 s cycle, 9 m/s, lanes ±2.6 and 0 m, waiting visibly 1.5 s at the top. Spin hit (medium profile). At least 4.1 m of road is always free. |
| Castle | Portcullis in the secret passage | 20 s cycle, closed 29.5%. Stops karts. Never closed together with the drawbridge (2.75 s apart at least). |
| Dungeon | 3 lava bursts (2 on the shore, 1 by the bridge) | 7.5 s cycle, bubbling warning dome, never more than one erupting. At least 6.7 m of road is always free. Spin hit with scorch puff. |
| Dungeon | Mine cart on the mine-rail shortcut | Shuttles over 18 m in its own lane on a widened rail (3.3 m free beside it). Solid: spin plus a push to the free lane. The shortcut still saves 1.32 s. |

## Results

- **track_check:** Castle and Dungeon ALL PASS, rerun after the last change. Check (17) covers:
  - the main road is never fully blocked;
  - open and closed fractions are within the data limits;
  - the free gaps listed above.
- **Forced autopilot runs:** each hit spins 1.1 s and recovers to full speed. The portcullis stops the kart, and it passes when the gate rises. A kart that finds the raised drawbridge sinks and respawns.
- **Bots** (all races: 11/11 finished, 0 stuck, 0 sinks):

  | Track | Races | Hazard hits on bots | Shortcut use |
  |---|---|---|---|
  | Castle | 5 | barrel hits 4–13 per race | drawbridge timed: 13 entries, 10 skips, 0 mis-entries |
  | Dungeon | 4 | 1 in total (the cart) | mine rail entered ~18 times per race; careful bots skip when the cart would meet them |
  | Castle (recheck after part 3) | 2 | barrel hits 4 and 7 | — |

- **Network:**
  - 2-PC hazard comparison: 0 phase or blocked mismatches on both tracks.
  - Max gate angle difference 1.4°. Barrel position within 0.15 m, cart within 0.11 m.
  - Item hits identical on 3 PCs.
  - A logging bug was found and fixed: when one spill hit two karts, the second HIT line lost its item name. It dates from story 004.
- **Frame rate:** windowed host plus 11 bots, no screenshots. Min 59–60 on every run on both tracks.

## Screenshots (opened and checked)

| What | File |
|---|---|
| Drawbridge down, kart crossing | `part1/shots_down/at_s215.png` |
| Drawbridge raised, kart sinks at the edge, red lanterns | `part1/shots_up/moat_sink.png` |
| Barrels rolling down the market street | `part2/shots_off6/at_s470.png` |
| Portcullis down stopping the kart, red lanterns | `part2/shots_off0/hazard_portcullis_t028.png` |
| Lava burst erupting beside the road | `part3/shots_shore/at_s343.png` |
| Kart spun by the mine cart on the rail | `part3/shots_cart/hazard_mine_cart_t019.png` |

## Not verified

- The hazard sounds (reused existing wavs) have not been heard.
- Fairness of the drawbridge for a human player:
  - open, the shortcut saves 1.09 s;
  - meeting it raised costs about 3.8 s;
  - blind use loses, by design. A 13 s down / 7 s up cycle was suggested as fairer.
