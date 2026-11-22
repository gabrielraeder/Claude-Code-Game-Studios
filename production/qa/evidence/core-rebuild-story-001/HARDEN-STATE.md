# Story 001 oracle hardening (after LP-CODE-REVIEW CONCERNS) - progress

- 2026-11-22: read all target files; starting edits (fixes 1-10). Evidence folder: harden/.
- Done (edited, syntax/offline checked): fix 1 (regression.sh CHECKS validation, run count, PASS/PARTIAL PASS RESULT),
  2 (track_check needs `== ALL PASS ==` + script-error scan), 3 (capture_traces.gd 0 rows -> exit 1, no file;
  proven by harden/neg-zero-ticks.log, exit=1; capture_all_traces.sh header-only fails; compare_traces.py golden
  0 rows fails), 4 (compare --expect, WARN new-only, torn rows, --tol checks; regression passes --expect 6),
  5 (item_net .hits >= 1 line each), 6 (check_data_closure exit 2 on missing/empty/<15), 7 (SCRIPT_ERRORS +2
  patterns, trace logs scanned), 8 (net_stress lead divergence -> WARN TD-011 + warnings=n; places 1..4,
  summaries, errors still FAIL; parser checked on full-run-2 (agree=2 -> WARN) and rerun-1 (agree=1)).
- Remaining: 9 (profile_tick.gd comments), 10 (weighted test; seed 42, odds [1,2,1], 12 rolls ->
  0,1,1,0,2,0,2,0,0,2,0,0 computed with ItemSet.roll on 4.8-beta3), negatives, full run, gdUnit4.
- Fixes 9, 10 done. gdUnit4: 3 test cases, 0 failures, exit 0 (harden/gdunit4.txt).
- Negatives done (harden/neg-*.txt): CHECKS typo exit 2 (no outdir made); header-only golden DIVERGED exit 1;
  --expect 6 with 5 files DIVERGED exit 1; closure on empty dir exit 2; --tol -1 / unknown field exit 2;
  new-only csv WARN (exit 0); 0-tick capture exit 1 (neg-zero-ticks.log).
- Full run started (background: a full run takes ~12 min, over the 10-min foreground cap) -> harden/full, log harden/full.txt.
- Full run done: RESULT PASS (6/6 checks) warnings=0, exit 0 (harden/full.txt, harden/full/). No Godot left running.
  All 10 fixes and all evidence complete. Nothing committed.
