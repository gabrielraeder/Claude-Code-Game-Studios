# Story 004 evidence: five medieval items

Raw logs, summaries and screenshots are in `production/qa/evidence/story-004-items/`.
Tools: `tools/item_net_test.sh` (3-PC race), `tools/item_log_check.py` (spin/hit matching),
`tools/item_odds_check.gd`, `tools/net_stress_test.sh`, `tools/bump_test.sh`.

## 3-PC races (host + 2 clients, autopilot, headless, UDP 24690, 2 laps)

Host refills spill, client1 stone, client2 falcon every 3 s (`--give-item`, `--item-interval=3`).
Natural item boxes also feed the karts.

| Run (dir) | Hits (blocked) | Spins | Spin without hit | Hit without spin | Cross-PC hit lists | Errors |
|---|---|---|---|---|---|---|
| online-castle (first build) | 41 | n/a (spin lines added later) | n/a | n/a | identical on 3 PCs | 0 |
| online-dungeon | 50 (1 blocked) | n/a | n/a | n/a | identical | 0 |
| online2-castle | 16 (1) | 15 per PC | 0 | 0 | identical | 1 enet send error at teardown (see below) |
| online3-dungeon | 32 (0) | 32 per PC | 0 | 0 | identical | 0 |
| online-shield-castle (host always shielded) | 6 (3 blocked) | 3 per PC | 0 | 0 | identical | 0 |
| online-shots3-castle (host cycles all 5 items) | 33 (6 blocked) | 27 per PC | 0 | 0 | identical | 0 |
| lag-castle (--lag=80 --jitter=30 --loss=5) | 18 | n/a | n/a | n/a | identical | 0 |
| lag-spin-castle (--lag=80 --jitter=30 --loss=5, rtt ~200 ms) | 30 (2 blocked) | 28 per PC | 0 | 0 | identical | 0 |

- A hit line carries item seq, victim and the victim PC's race time; per-PC logged times differ by 0.01-0.02 s.
- Spin duration (SPINEND lines): 1.07-1.13 s, median 1.10 s (stats.spin_time).
- Stone hits happened after 0, 1, 2, 3 and 4 bounces (DECIDE lines). Stones also end on the bounce limit (`END stone (bounces)`).
- Falcon: hits and misses both occur (e.g. shots3: 14 falcon hits, 4 `END falcon (missed)`).
- Shield: blocked hits break the shield with `blocked=1`; the victim does not spin (spins = hits - blocked).
- Open: `online2-castle/host.log` has one `ERROR: Unable to send packet on channel 0, max channels: 0`
  right after a finished client left (teardown). It did not recur in the other runs.

## Odds (2,000 rolls per group, `odds-check.txt`)

Places 1-2: horn 24.9, stone 7.1, spill 36.0, falcon 0.0, shield 32.0 (%).
Places 5-8: horn 30.3, stone 26.8, spill 9.0, falcon 25.5, shield 8.4.
Places 11-12: horn 40.0, stone 25.5, spill 0.7, falcon 33.5, shield 0.5.

## 12-racer runs

- `stress12` (headless): all 12 PCs agree on lead changes; places 1..12 distinct with finish times in place order; 0 errors; host 425 kB/s, clients about 38.6 kB/s.
- `stress12-windowed2` (host windowed, 11 clients headless): places 1..12 agree (77.33 to 82.42 s), 0 errors, host 407.5 kB/s, clients 36.9 kB/s. Host fps: min 59, median 60 (vsync cap), max 60. Headless clients 143-145.

## Bump test, 6 bots (`bump-6bots.txt`)

host: pen_max 0.038 m, deep_frames 0; client: pen_max 0.000 m, deep_frames 0; errors host,client: 0 0.

## Screenshots (shots-final2, windowed host = kart 0)

Files are named `item_<kind>_<n>_<text>.png`. Opened and checked in /dev-story, 2026-11-20:
- `item_roulette_0_box1_owner0.png`: the HUD slot shows "?" during the roulette; pink "?" boxes on the road.
- `item_horn_0_horn_kart0.png`: an orange flame cone behind the kart and a full boost bar.
- `item_stone_0_spawn_seq1_owner0.png`, `item_bounce_0_seq1_n1.png`: a grey stone with an orange eye; the falcon's red target ring around the targeted kart.
- `item_slick_ahead_0_seq200023.png`: a green slick with bubbles on the road ahead; the falcon, a blue cross shape.
- `item_shield_break_0_victim0_itemfalcon.png`: the clear shield bubble with a ring and cream puffs as it breaks.
- `item_hit_2_victim2_itemstone.png`: the stone hit, seen from the firer.
All item shapes are placeholders; art is story 007.

## Engine check (godot-gdscript-specialist, 2026-11-20)

- No deprecated or changed 4.5-4.8 API found in item_manager.gd, item_set.gd, item_set.tres, the net_session.gd item RPCs.
- Fixed: `ItemManager.reset()` now frees hit puffs and horn flames and clears spin and slick records (a restart could reach a freed racer).
- Open: `rpc_box_taken` and `rpc_item_hit` are `any_peer`, so a modified client could fake a pickup or a hit. Fine among friends.

## Falcon range

Falcon targets the kart one place ahead. A target more than `lose_range` (140 m) ahead ends the falcon at launch (`END falcon (missed)` at the USE time), seen in lag-spin-castle when the 2nd kart was ~16 s behind the leader.
