# Story 008 evidence: elevation, banking, jumps and a crossover

Built in five parts. Each part has a `STATE.md` with every step under `production/qa/evidence/story-008-elevation/part1..part5/`; the owner's crossover decision is in `crossover-decision.md`.

## Screenshots (opened and checked)

| What | File |
|---|---|
| Banked turn, camera rolled, outer wall high (test track) | `part1/at_s385.png` |
| Raised banked road on supports (side) | `part1/side_s392.png` |
| Kart in the air off a ramp, shadow detached | `part2/shots_jump/jump_air.png` |
| Overpass seen from the lower road | `part2/shots_side/side_s1437.png`, `part3/shots_drive/at_s1226.png` |
| Item boxes and pads on their own level, water under the bridge | `part3/shots_drive/at_s1226.png` |
| Castle with elevation, overview | `part4/castle_overview2/overview.png` |
| Dungeon descent | `part4/dungeon_drive/at_s170.png` |
| Castle barbican spiral, overview | `part5/overview2/overview.png` |
| Crossing from above: the road over the gate | `part5/side2/side_s431_d30_l16.png` |
| Gate from below: deck, portcullis, bones, paw crest | `part5/side2/side_s431_d40_l3.png` |
| Climbing the spiral, chase camera | `part5/drive2/at_s392.png` |

## Results

- **track_check:** ALL PASS on Castle Circuit and Dungeon Depths, rerun after the last change. The height checks are new:
  - grounded karts never more than 0.05 m under the surface (castle −0.043, dungeon −0.035);
  - every landing on the road;
  - grade 8.7% at most, bank 15° at most;
  - 0 mixed levels, 0 decks cutting another;
  - the castle crossover exists (16 samples over a road below).
- **Bot check:** the bot mode, broken since story 005, is fixed and runs.
- **Castle crossover numbers:**
  - lap 1,145 m (limit widened to 1,200 m by the owner);
  - spiral s 339–418 (R16, 280°, 0.4 → 6.5 m);
  - crossing: lower road s 325 at 0.0 m, upper s 431 at 7.0 m, clearance 6.4 m;
  - shortcut saves: drawbridge 1.09 s, passage 1.17 s.
- **Bots on Castle with the spiral:** 5 races, 11/11 finished, spreads 7–10%, 0 sinks. One stuck event of 2.7 s at the hairpin 1 exit; not at the spiral or the gate.
- **Bots on Dungeon:** 4 races, 11/11 finished, 0 stuck, 0 self-caused sinks.
- **Levels:**
  - boxes and pads act on their own level only;
  - a bridge over water is safe, falling into it sinks;
  - a spill on the deck does not hit karts below;
  - a falcon with no target passes over karts below; one aimed at a kart on the deck hits it.
- **Network:**
  - item hits identical on all 3 PCs (Castle and Dungeon);
  - remote kart height agrees within 0.06 m at display time, including on the spiral and under the deck;
  - KartWire VERSION 9.
- **Frame rate:** windowed host plus 11 bots, no screenshots. Min 59 on every final run (Castle with the spiral 59/60, Dungeon 59/59), worst frame about 27 ms. Part 3 saw one 248 ms frame, since addressed by the material prewarm; it has not come back.
- **Scenery audit:** 0 props on the road on both tracks.

## Not verified

- **Feel of banks, jumps and the spiral:** needs the owner's play.
- **Prewarm with a cold shader cache:** not tested on its own (A/B).

## Sign-off (Visual/Feel)

- [ ] Approved: look (elevation, banks, ramps, the barbican spiral and gate deck read well)
- [ ] Approved: feel (banks, jumps and the spiral drive well)
