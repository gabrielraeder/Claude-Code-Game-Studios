# Story 005 evidence: tougher bots

Raw logs, summaries and screenshots are in `production/qa/evidence/story-005-tougher-bots/`.
Tools: `tools/bot_race_test.sh` (one race), `tools/bot_sink_batch.sh` (sequential races, one Godot at a time),
`tools/bot_log_summary.py` (per-bot summary from `[bot]` log lines), `tools/item_log_check.py` (cross-PC hits).
Debug switches: `--bot-labels`, `--bot-shots=DIR`, `--bot-stuck-test=ID`, `--bot-trace`, `--race-seed=N`.

## Final verification (/dev-story, 2026-11-20, current code)

Sequential races, 11 bots, 3 laps, host on autopilot (the "skilled player" reference), a fresh race seed each.

| Run | Seed | Bots finished | Spread (first to last bot) | Sinks (self-caused) | Stuck events |
|---|---|---|---|---|---|
| final-batch-castle/castle_circuit-1 | 3222564246 | 11/11 | 5.1% | 0 (0) | 0 |
| castle_circuit-2 | 4190580192 | 11/11 | 4.2% | 0 (0) | 0 |
| castle_circuit-3 | 3821061187 | 11/11 | 5.4% | 0 (0) | 0 |
| castle_circuit-4 | 1040541692 | 11/11 | 4.6% | 0 (0) | 0 |
| castle_circuit-5 | 4006104036 | 11/11 | 8.2% | 0 (0) | 0 |
| final-batch-dungeon/dungeon_depths-1 | 510942669 | 11/11 | 8.5% | 1 (0) | 0 |
| dungeon_depths-2 | 3184010042 | 11/11 | 6.1% | 0 (0) | 0 |
| dungeon_depths-3 | 2138629856 | 11/11 | 9.9% | 0 (0) | 0 |
| dungeon_depths-4 | 2884744013 | 11/11 | 10.7% | 2 (0) | 0 |

- No kart sank twice within 5 s in any race. 0 ERROR lines in every log.
- `final-replay-2661212103`: the seed that showed the respawn loop now gives 2 sinks, both from bumps at the open edge (s 174-178), and no loop.
- `win-final`: windowed host, 11 bots, Castle Circuit: fps min 60, median 60 (vsync cap). The earlier 50 fps runs (`win-bots`, `win-nobots`) overlapped other Godot runs on the same machine; quiet runs (`win-quiet-castle`, `win-quiet-final`, `win-final`) hold 60.
- Parse check: 46/46 scripts load.

## Literals moved to data (/dev-story, 2026-11-20, after /story-done)

- Six driving thresholds moved from `src/ai/bot_driver.gd` into `assets/data/ai/bot_set.tres` via new `BotSet` knobs: `corner_end_turn` 0.15, `corner_start_share` 0.7, `avoid_commit_side` 0.8, `follow_corridor_share` 0.8, `stone_cone_slack` 1.2. The sixth literal (`1.5` on the open-edge side) was a code, not a tuning value: now the constant `OPEN_BOTH` (2.0).
- The defaults equal the old literals, so driving is unchanged. Parse check: 6 scripts ok, exit 0.
- Regression runs (`literals-batch/`): Castle seed 4099330464: 11/11 finished, spread 9.6%, 1 sink (a bump at the drawbridge, 0 self-caused), 0 stuck. Dungeon seed 2611259781: 11/11 finished, spread 7.4%, 0 sinks, 1 stuck event: Wide Wanderer pinned at the wall at the mine-rail entrance at t=23 s, reversed and freed in 2.7 s. That is a natural stuck recovered by the recovery code (earlier runs had none). 0 ERROR lines.

## The moat sink fix (history)

- Before (`sink-castle-2`): 21 sinks in one Castle race, 14 self-caused, at the drawbridge mouth and deck.
- Causes, confirmed with `--bot-trace` on seed 2661212103 (`replay-before2-2661212103`): near a rail-less shortcut the look-ahead target sat on the other road across the water gap (main road aiming at the deck, or a kart on the deck aiming back at the main road), and after a respawn the bot kept its old sideways line. On Dungeon, slow personalities tried the lava gap under its 24 m/s gate speed.
- Fixes: a kart on a rail-less deck follows it to its end; a missed mouth is given up so the bot never aims across the gap; calm 2.5 s after a respawn; the line never leans toward an unwalled edge; crowd gate and entry/deck speeds for the drawbridge; full top speed on a gated route, gate skipped when too slow.
- Batches after the fixes: `batch2` (12 races), `batch3` (10 races), the final batch above. Remaining sinks all come from bumps or item hits.

## Other runs

- Network with 2 clients and 9 bots (`fix4-castle-net`): hit lists identical on host and both clients, 0 spins without a hit, 0 sinks.
- Parked kart on the grid (`fix4-park-dungeon`, earlier `park-dungeon`): all bots passed it, none pinned it.
- Stuck recovery, forced pin (`stuck2-castle_circuit`, `stuck2-dungeon_depths`): STUCK, reverse, STUCKEND in 2.6 s, bot rejoins the race; screenshots `shots-stuck2-castle_circuit/06_t009.png` (pinned) and `09_t012.png` (back on the road). No bot got stuck in any normal race.
- Race seed: different seeds give different shortcut plans for the same bots on the same track (`seed-castle-1` vs `seed-castle-2`).

## Screenshots (opened and checked)

- `shots-bots/05_item_horn_kart6.png`: a bot (Item Hoarder) using the War Horn, flame behind it.
- `shots-bots/08_t026.png`: Shortcut Hunter entering the drawbridge shortcut.
- `shots-bots/13_item_shield_kart5.png`: Outside Swinger with the shield bubble.
- `shots-bots/03_item_spill_kart5.png`: Apex Ace after a spill hit, bots on the drawbridge deck.
- `shots-bots/01_t010.png`: the pack after the start, personality labels on each bot.
- `shots-bots/02_t014.png`: the old bug (three bots sinking at the moat), kept as the before picture.

## Not verified

- A human playing against the bots ("tougher than prototype 1", "a skilled human can win clearly"): the autopilot reference won the races by 1-2 s; the owner judges by playing.
- Stuck recovery from a natural wall trap: forced pin in the main runs; one natural case (Wide Wanderer, Dungeon, `literals-batch`) recovered in 2.7 s. One case is not a sample.
