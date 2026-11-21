# Story 006 fps regression hunt (progress note)

Goal: race fps min >= 59 (race_time > 0) on seeds 2661212103 and 4110477659, like baseline c49683f.
Command: `HOST_WINDOWED=1 QUIT=150 HOST_EXTRA="--race-seed=<seed>" bash tools/bot_race_test.sh <out> castle_circuit 11 3 0`

## Step 0 - reading the existing logs (no run yet)
- win-final-mine/host.log contains 20 `[debug] screenshot ...` lines (countdown, start_go, spark_tier1/2,
  drive_t03, bump_1/2, item_roulette, drive_t10, item_hit_*, drive_t20, ...): that run had `--shots=`
  in its args. win-baseline-c49683f/host.log has NO screenshot lines. Screenshot = viewport
  get_image() (GPU readback) + save_png on the main thread.
- The dip seconds (-2, 3, 4, 5, 11, 29..119) line up with screenshot times. Hypothesis H1: the
  "regression" is the screenshots, not the story-006 visuals. To be measured.

## Step 1 - instrumentation (main.gd netlog columns, KartVisual cost)
- main.gd: new netlog columns primitives, frame_max_ms (worst real frame, ticks between _process
  calls), proc_max_ms / phys_max_ms (worst Performance.TIME_PROCESS / TIME_PHYSICS_PROCESS in the
  second), visual_us (sum of all KartVisual._process time in the second, KartVisual.take_cost_usec()).
- Parse checks ok.

## Step 2 - runs (current tree, one Godot at a time)
| run | shots | fps min/p5/med (race>0) | worst frame ms (race>0) | visual_us/s med |
|---|---|---|---|---|
| perf-cur-s266 (visual_us not yet wired) | no | 59/60/60 | 25.3 | - |
| perf-cur-s266-b | no | 59/60/60 | 27.7 | 6790 (= 0.11 ms/frame, 12 karts) |
| perf-cur-s266-shots (`--shots=` added) | 20 | 54/58/60 | 113.0 | ~6600 |
- With --shots the win-final-mine pattern comes back exactly (58 at 2-3 s, 56 at 4, 54 at 5, 54 at 11,
  57-58 at 21-119); every dip second has a 70-113 ms frame = one screenshot (get_image + save_png).
- Without --shots the current tree already meets the goal on seed 2661212103.
- KartVisual per-frame work is 0.11 ms/frame for all 12 karts: not the cause.
- Race-start sample (-2): `[net] built 12 karts in ~71 ms` -> one ~89 ms frame (countdown, not race).

## Step 3 - baseline worktree (c49683f + the same netlog columns, scratch) and seed 2
| run | shots | fps min/p5/med (race>0) | worst frame ms (race>0) | race-start frame (-2) |
|---|---|---|---|---|
| perf-base-s266 | no | 59/60/60 | 24.3 | 33.4 ms |
| perf-base-s266-shots | 21 | 55/58/60 | 113.5 | - |
| perf-cur-s411 | no | 59/60/60 | 25.9 | 89.0 ms (built 12 karts in 70.5 ms) |
- Baseline WITH --shots dips the same way (57 at 2-3 s, 56 at 11, 56 at 29, 55 at 67): the dips are the
  screenshots, in both trees. Not a story-006 regression. Coordinator agreed the old comparison was unfair.
- Only real story-006 difference found: the race-start frame (kart build) 33 -> ~89 ms, during the countdown.

## Step 4 - race-start build (71 ms in one frame, 3 s before GO)
Temporary phase timers (perf-phase1/2, removed again) over the 11 karts built at race start:
pennant pole mesh 34.2 ms, vehicle glb instantiate 9.1, dog glb instantiate 8.6, spark+flame meshes 4.8,
dog finds 1.4, paint copies 1.3, rest < 1. Pole mesh is cached per length, but every vehicle+dog pair
has its own pole length (9 misses). Windowed micro-benchmark: creating a CylinderMesh/SphereMesh and
reading its arrays costs 0.25-0.6 ms each windowed (10 us headless); the GDScript append is 20 us.
Fix plan (no look change): pole = unit-height cylinder arrays + finial arrays made ONCE per style
(prewarmed), scaled in y per length (same vertices; side normals do not depend on height when
top = bottom radius); spark sphere and flame cone meshes cached by their sizes (shared, never edited).

Fix coded (pennant.gd _pole_parts + stretched cylinder, prewarmed; kart_visual.gd _spark_mesh/_flame_mesh
cache, prewarmed). Headless check (scratch script): new pole vs old CylinderMesh(height L) pole for
L = 1.37, 2.0, 2.613, 3.9 -> 91/91 verts, 348/348 indices, max vertex diff 0, max normal diff 0.
Parse checks ok. Next: perf-fix-s266, perf-fix-s411, lineup-v7.

## Step 5 - verification (no --shots)
- perf-fix-s266: built 12 karts in 35.8 ms (was ~71), race-start frame 50.5 ms (was ~89). Race fps
  min 57 / p5 60 / med 60, worst frame 36.4 ms: three 57 samples at 61, 117, 128 s, each after a
  ~30 ms process frame, at times that never dipped in perf-cur-s266/-b (same seed, same deterministic
  race, identical summary). No per-frame code changed (only build-time mesh creation). Treated as
  suspected machine noise (VS Code etc. running); one rerun of s266 planned after s411.
- perf-fix-s411: built 38.7 ms, race-start frame 53.7 ms; race fps min 56 / p5 59 / med 60, worst 42.8 ms:
  recurring 33-43 ms frames (process 28-33 ms) at 21-61 s, absent in perf-cur-s411 (worst 25.9).
  A/B to separate fix vs machine: pre-fix files (backup in session scratchpad, fixed copies saved as
  pennant.fix.gd / kart_visual.fix.gd there) temporarily back in place -> perf-ab-prefix-s411.
- perf-ab-prefix-s411 (PRE-fix code, run right after): race fps min 56, worst 37.7 ms, the same
  30 ms process spikes (58-62, 75-77, 109-110 s) at different times than perf-fix-s411. So the spikes
  are machine-side (appeared after ~20:00 runs), not the fix. Fixed files restored (verified).
Next: parse checks, lineup-v7, report (coordinator: no extra runs, another Godot job is queued).
- Parse checks after restore: kart_visual.gd, pennant.gd, main.gd all ok (exit 0).
- lineup-v7 rendered (log perf-lineup-v7.log, no errors). Viewed slots12_chase (v7 vs v6b: same poles,
  finials, flag colours and patterns) and close34_bike_mascot (pole, gold finial, red swallowtail, dog,
  shadows as before). Byte compare v7 vs v6b: 12 of 40 PNGs identical, 28 differ (flag wave is
  TIME-driven); no visible difference in the two viewed. Look check: PASS.
DONE. Report delivered to coordinator.
