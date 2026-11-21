# Exit crash investigation — STATE

## Step 0 (started 2026-11-21)
- Task: host segfaults on exit after race end (009 p2+, 011 p1). Find root cause in src/, fix, verify.
- Nothing done yet.

## Step 1 — reproduced + bisected
- Repro: `--headless --path . -- --host --port=24690 --players=1 --bots=3 --autopilot --laps=1 --track=castle_circuit --quit-after=5` -> exit 139 at HEAD (repro/castle_headless_q5.log). Race end not needed. No CrashHandler output, even with --verbose (crash is late in shutdown).
- Worktrees (scratchpad, not removed): .../scratchpad/wt_3558678, wt_c5dd866, wt_a64f2d8 (with .godot copied).
- quit-after=8: 3558678 exit 0, c5dd866 exit 0, a64f2d8 exit 139 => introduced by a64f2d8 (009 part 2). Logs in bisect/.

## Step 2 — narrowed (coordinator asked to narrow inside a64f2d8: done)
- HEAD, other tracks (bots=3, quit-after=5): dungeon_depths, test_elevation, test_surfaces all exit 139.
- castle with --bots=0: exit 0 => bot-related.
- a64f2d8 added in BotDriver._drive: `sim.mover_hit.connect(func(mi): print(... sim.track_s ...))`.
  The lambda captures `sim` (KartSim, RefCounted) and is stored in sim's own signal => RefCounted
  cycle KartSim -> Callable -> KartSim; each bot's sim (+ hazard_manager, stats, ...) is never freed
  and is torn down in an undefined order at engine shutdown -> segfault after the scripts are gone.
- Experiment worktree .../scratchpad/wt_head_exp (HEAD, only that connect disabled): exit 0.
- Next: fix in src/ai/bot_driver.gd (no strong capture of sim), verify.

## Step 3 — fix applied (main tree)
- src/ai/bot_driver.gd: lambda capturing `sim` -> `sim.mover_hit.connect(_on_mover_hit.bind(weakref(sim)))`
  + new `_on_mover_hit(mover_index, sim_ref: WeakRef)` (same pattern as race_sound.gd watch_owned).
- Parse check exit 0 (verify/parse_bot_driver.log). castle bots=3 quit-after=5: exit 0.
- Next: full verify matrix (verify/).
- Headless verify (quit-after=60, bots=3, laps=1): castle x3 exit 0/0/0, dungeon_depths 0, test_elevation 0, test_surfaces 0; ERROR count 0 in all (verify/*_headless*.log).
- track_check "N resources still in use at exit": predates a64f2d8 (story 003/007/008/009p1 logs), tool script (-s, no bots) => NOT the same cause; not in scope to edit tools/ (tool does not crash).
- Next: windowed runs, bot_race_test.sh, item_net_test.sh.
- Windowed verify (_win64.exe, quit-after=60): castle x3 exit 0/0/0, dungeon 0, test_elevation 0, test_surfaces 0; ERROR 0.
- bot_race_test.sh (QUIT=60 SCALE=4, castle 11 bots 1 lap 1 client): tool exit 0, no Segmentation fault, ERROR 0 host+client (bot_race_castle/).
- item_net_test.sh castle 1: tool exit 0, host vs client1/client2 IDENTICAL (24 hits), ERROR 0 (item_net/).
- track_check --verbose (track_check/castle_verbose.log): exit 0; the 1 "resource still in use" is res://tools/track_check.gd itself
  (GDScript refcount 60) with 21 leaked RefCounted/WeakRef instances held by the -s tool script. Pre-existing (story 003+), no crash,
  tools/ out of scope (tool does not crash) -> reported, not changed.

## DONE — all verification passed. Fix uncommitted in src/ai/bot_driver.gd (no commit made).
