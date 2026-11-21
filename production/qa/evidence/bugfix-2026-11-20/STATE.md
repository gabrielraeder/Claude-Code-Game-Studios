# Bugfix 2026-11-20 — state (survives a turn limit)

Bugs: (1) item boxes do not break when a kart already holding an item drives through;
(2) scenery inside the drivable area with no collision (Castle market stalls, Dungeon pillar hall).

## Progress
- [x] Bug 1: read code — root cause: item_manager.gd only calls _try_pickup / bot grant when the kart has no item and no roulette; a holding kart never touches the box
- [x] Bug 1: fix — item_manager.gd (every free box in reach breaks; wants_item only when no item/no roulette; _grant(wants) item -1 = broken; per-box ask + retry box_ask_retry in ItemSet/item_set.tres; debug_box_check SEEN/PASSED_FREE log lines, set by main.gd for --autopilot), net_session.gd, kart_wire.gd VERSION 4->5. Parse 0. Checker: tools/box_log_check.py
- [x] Bug 1: solo test — DONE (+ hostonly_castle_7bots: 15 BOX, 9 item + 6 broken incl. bot kart 3 broken-while-holding, PASSED_FREE 0): items-solo/solo_castle_noitem (6 BOX: 1 item + 5 broken, PASSED_FREE 0), solo_castle_holding_shield (6 broken, 0 missed), solo_dungeon_noitem (8: 1 item + 7 broken, 0 missed). RUNNING: hostonly_castle_7bots.log (bots)
- [x] Bug 1: 2-peer test — items-2peer-castle-noforce (16 BOX: 9 item + 7 broken; client kart 1 got spill then broke boxes 4, 8 while holding), items-2peer-castle-holding (18: 13 + 5; host kart 0 holding shield broke 3), items-2peer-dungeon-noforce (12: 5 + 7); every run PASSED_FREE 0 on both PCs, BOX lists IDENTICAL host vs client, 0 errors. box-summary.txt per dir.
- [x] Bug 2: audit tool written — tools/scenery_road_audit.gd (+ prop tags in track_scenery.gd, no placement change)
- [x] Bug 2: audit BEFORE run, saved — scenery-audit-before.txt: castle 150 on-road (gardens hedges 86 [oriented along the normal, 2.3 m into road], village_house 31 [up to 1.06 m into village_lane near s 529-536], moat_posts 16 [open moat edge], passage arches 5 [12.5 m into keep plaza], tourney grandstand 4, barrels 4, trebuchet 2, gate towers 2); dungeon 33 (pillar_hall 24 [base 1.4 m into lanes], cavern stalagmite 3, cavern_rocks 2, cellar 2 [lava_gap], mine posts 2 [mine_rail]) + 150 FLAT rail sleepers. STALLS ARE CLEAR (0.7-0.9 m off the walls) — not the culprit.
- [x] Bug 2: fix — guard + prop groups in every composite builder; hedges along t; moat posts flat studs (0.27 m); pillars: lanes touch (8.2 m apart, walls 4.0/4.3, no island) so all 12 columns moved just outside the outer lane walls (shrink path exists but no room anywhere); passage arches: _arch_distance start bug fixed (> → >=) + arch moved inward until columns clear + gap +margin; tapestry raised above clear height. Per track: Castle 47 props moved, 0 shrunk, 2 left out (gardens); Dungeon 20 moved (12 pillars), 0 shrunk, 4 left out (cellar column 1, cavern rock 1, mine posts 2).
- [x] Bug 2: audit AFTER run, saved — scenery-audit-after.txt: 0 on road at kart height on all 3 tracks; FLAT listed: 16 moat studs (castle), 150 rail sleepers/rails (dungeon); overhead counted per tag (lowest bottoms 2.5-3.6 m)
- [x] Screenshots taken (windowed) and opened: shots/castle-village-lane/at_s523,at_s530 and shots/castle-main/at_s524,at_s532 (houses behind the walls on both sides), shots/castle-main/at_s742,at_s800 (gardens: hedges are low rows behind the wall), shots/castle-stalls/at_s488 (island beyond the left wall; stalls are low and not clearly visible from the chase cam), shots/dungeon-main/at_s245 + shots/dungeon-hall-left/at_s258 (pillars stand outside the outer lane walls; the three lanes are one open floor)
- [x] Report delivered (handback)

## Notes
- Scenery build time with the guard: castle 315 ms, dungeon 224 ms (headless, once per race load).
- Parse check of all 8 changed .gd: exit 0 (parse-check.txt).
- Bug 2 fix plan: TrackScenery road guard in _add: RoadGrid (cell index of road segments) + prop groups (_begin_prop/_end_prop): a group whose kart-height footprint is within scenery_road_margin of the corridor is nudged away (<= scenery_max_nudge) else dropped whole; flat (<= scenery_flat_height) and overhead (>= scenery_clear_height) pieces exempt. Specific: hedges orientation t, moat posts flattened, pillars shrink-to-fit, passage arches moved inward.
- TrackTheme.scenery_road_margin = 0.3 added (theme .gd + both theme .tres); placement not changed yet.
- Solo races have no bots (bots only when hosting); bot box test = --host --players=1 --bots=N.
- Solo run 1 (castle, no forced item): 6 BOX events, 1 with item then 5 broken item=none, PASSED_FREE 0.
