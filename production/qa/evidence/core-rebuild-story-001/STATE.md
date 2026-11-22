# Story core-rebuild-001 — working state

Story: production/epics/core-rebuild/story-001-freeze-and-oracle.md
Resume rule: do the first unticked step; notes under each step say what exists.

## Steps

- [x] 1a. tools/capture_traces.gd (per-tick trace recorder wrapping the real main scene)
- [x] 1b. tools/compare_traces.py (IDENTICAL or first diverging tick/kart/field)
- [x] 1c. Golden capture A -> golden/ ; capture B -> repro/ ; compare A vs B
- [x] 2. tools/regression.sh green on the frozen game (output saved: regression-before.txt)
- [x] 3. Perf baseline (perf-baseline.md)
- [x] 4. gdUnit4 into addons/gdUnit4, tests/unit, tests/integration, example test passes via commands.test
- [x] 5. Commit steps 1-4
- [x] 6. Tag v0.11-2.5d on that commit
- [x] 7a. Move commit (git mv src/** -> src/legacy/**, sidecars with them; data classes -> src/data/)
- [x] 7b. Path commit (scripted res://src/ rewrite) + closed-set check + --import cache rebuild
- [x] 8. Regression + trace compare after the move (regression-after.txt), tick settings pinned, 4.8 greps
- [x] 9. Windowed launch from moved main scene, race started, screenshot kept here

## Notes
- 1: tools/capture_traces.gd (SceneTree wrapper, -s, --fixed-fps 60), tools/capture_all_traces.sh OUTDIR (6 runs, seed 1001, port 24690), tools/compare_traces.py GOLDEN NEW [--tol f=v]. golden/ captured; repro-before/ captured; repro-before-compare.txt = IDENTICAL x6, no tolerance needed. ~2 min per full capture.
- 2: tools/regression.sh [outdir] (CHECKS= subset env). Before-move output: regression-before.txt (parts 1+2, all 8 PASS). Full run ~10 min (track_check ~2 min/track).
- 3: perf-baseline.md (median 3.4 ms, p95 6.3 ms per tick, 12 karts, Ryzen 7 7800X3D, headless). capture_traces.gd --perf-out= mode, CSVs in perf/.
- 4: gdUnit4 v6.2.3 (github.com/godot-gdunit-labs/gdUnit4, where MikeSchulze/gdUnit4 redirects; README lists 4.8.dev7) in addons/gdUnit4, plugin NOT enabled in project.godot (CLI needs no plugin). tests/unit/data/item_set_roll_test.gd 2/2 PASS via commands.test (gdunit4-example-run.txt). Duplicate trace CSVs in repro-before/ and regression-before-part2/traces/ left untracked (identical to golden).
- 5: commit 3e7e71e. 6: annotated tag v0.11-2.5d -> 3e7e71e (not pushed).
- 7a: move commit 1f8a99d (164 R100 renames; map scripts/move_map.tsv; empty old src/<system>/ dirs rmdir'd).
- 7b: scripts/rewrite_src_paths.py rewrote 25 files (path-rewrite.txt, 0 leftovers, uid= untouched); check_data_closure.py CLOSED (data-closure.txt; fixed its comment-stripping regex first); --import clean (import-after-move.txt); headless load no uid warnings (load-after-move.txt).
- 8 (in progress): regression-after-part2.txt all PASS, traces IDENTICAL x6 vs golden; godot48-greps.txt clean (one """ = shader string, not a comment; 0 self-inner inheritance). Next: regression-after-part1 (track_check), then probe keys + pin tick settings, re-run traces with settings pinned.
- 8: regression-after.txt all 8 PASS (traces IDENTICAL). Tick settings pinned in project.godot [physics] (all 4 keys exist in 4.8-beta3; only jitter_fix changes, 0.5 -> 0.0); tick-settings-pinned.txt; with pins: regression-pinned-traces.txt IDENTICAL x6, regression-pinned-shell.txt 4 PASS.
- 9: windowed launch from run/main_scene (res://src/legacy/main.tscn), --autopilot castle_circuit, 8 shots in screenshots/ (drive_t10.png = race at 0:09.22, LAP 1/1); windowed-launch.txt has no errors. STORY STEPS DONE.
