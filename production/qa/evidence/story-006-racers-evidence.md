# Story 006 evidence: eight knight-dog racers and two vehicles

Everything is in `production/qa/evidence/story-006-racers/`: `models/` (Blender renders), `shots/` (in-engine), `code-runs/` (logs).
Models are regenerated with `tools/blender/make_vehicles.py`, `make_dogs.py` and `render_previews.py` (headless Blender 5.3).

## Screenshots (opened and checked)

- `models/dog_lineup.png`: the 8 dogs from the front. Each has a different ear, head or helmet silhouette: pointed ears with a crest helm (mascot), brimmed kettle hat (Sunny), horns (Bolt), round ears with a hood (Fern), a tall plume (Violet), a crown (Frost), bat ears with a flat helm (Cinder), long ears with a feather (Skye).
- `models/chase_cart_armored_all_dogs.png`, `models/chase_bike_war_all_dogs.png`: every dog on each vehicle from behind and above. The cart is a wide low trapezoid; the bike is a narrow strip with the rider upright.
- `shots/lineup-v4/chase_cart_mascot.png`: the mascot's helmet and ears show above the cart from the chase camera, with the pennant above them (pole raised to 1.45x after `lineup-v3`, where the flag hid the head).
- `shots/lineup-v4/row_cart_chase.png`: the 8 dogs on carts in a row, each in its slot colour with its own pennant pattern.
- `shots/lineup-v3/chase_bike_violet.png`: Violet on the bike, the checker pennant high above the rider.
- `shots/grid12/grid.png`: 12 karts on the Castle grid, carts and bikes mixed, each slot colour and pennant readable.
- `shots/win-models-castle/drive_t03.png`: a real race at speed. Sunny on a cart, the mascot's cart ahead, and Fern on a bike all read clearly.

## Online loadout sync

- `code-runs/net2peer-fix/`: host (defaults) + client (`--vehicle=bike --racer=3`) + 4 bots. Both PCs print identical `[loadout]` lines for all 6 karts, 0 ERROR and 0 WARNING. The host waits up to `loadout_wait` (3 s) for every client's choice, and each PC applies the loadout the host announces. The timeout path (a client that never sends one) was not run.

## Cart and bike handling (data only: `assets/data/vehicles/war_bike.tres`, reasons in `war_bike_notes.md`)

Autopilot, 3 laps (`code-runs/lap-*`):

| Track | Cart laps (s) | Bike laps (s) |
|---|---|---|
| Castle Circuit | 38.0, 38.0, 38.1 | 36.4, 36.6, 42.6 (knocked in lap 3) |
| Dungeon Depths | 37.6, 38.1, 37.8 | 38.0, 38.3, 38.1 |

The owner played both on 2026-11-20: "um pouco diferente sim, no momento ok".

## Bots on mixed vehicles

- `code-runs/bots-mixed/`: the first batch found bots drifting into the Castle moat after the corner at s≈145 (4 self-caused sinks in 3 races, 2 of them bikes).
- Fix: no drift start near an unwalled edge, and an earlier drift abort (`assets/data/ai/bot_set.tres`).
- `code-runs/bots-mixed-fix-run3/`: 8 races (5 Castle, 3 Dungeon), 0 to 8 bikes per race. All 11 bots finished every race, 0 self-caused sinks, 0 stuck, 0 errors.

## Frame rate (windowed host + 11 bots, Castle, no screenshots; `code-runs/quiet-final-*`)

| Seed | fps min / p5 / median | Worst race frame | Kart build at the countdown |
|---|---|---|---|
| 2661212103 | 59 / 60 / 60 | 25.3 ms | 53 ms (12 karts built in 38 ms) |
| 4110477659 | 59 / 60 / 60 | 25.0 ms | 50.5 ms (36 ms) |

- The same command on the code before this story (commit c49683f, `code-runs/win-baseline-c49683f`) gives 59 / 60 / 60.
- Runs with `--shots` dip to 54-56 in both the old and new code: each screenshot costs a 70-113 ms frame. Use them for pictures, not fps (`code-runs/PERF.md`).

## Not verified

- **Racer colours on the minimap:** there is no minimap yet; it is built in story 007. Colours do reach the grid and the karts.
- **Model triangle counts:** reported by the model agent (dog plus vehicle 1,856 to 2,940, against a 4,000 limit). I did not re-measure them in the engine.

## Sign-off (Visual/Feel)

- [ ] Approved: art (dogs, vehicles, pennants read at a glance from the chase camera)
- [ ] Approved: feel (cart and bike drive differently)
