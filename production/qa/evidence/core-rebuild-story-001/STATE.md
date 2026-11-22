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
- [ ] 5. Commit steps 1-4
- [ ] 6. Tag v0.11-2.5d on that commit
- [ ] 7a. Move commit (git mv src/** -> src/legacy/**, sidecars with them; data classes -> src/data/)
- [ ] 7b. Path commit (scripted res://src/ rewrite) + closed-set check + --import cache rebuild
- [ ] 8. Regression + trace compare after the move (regression-after.txt), tick settings pinned, 4.8 greps
- [ ] 9. Windowed launch from moved main scene, race started, screenshot kept here

## Notes
- 1: tools/capture_traces.gd (SceneTree wrapper, -s, --fixed-fps 60), tools/capture_all_traces.sh OUTDIR (6 runs, seed 1001, port 24690), tools/compare_traces.py GOLDEN NEW [--tol f=v]. golden/ captured; repro-before/ captured; repro-before-compare.txt = IDENTICAL x6, no tolerance needed. ~2 min per full capture.
- 2: tools/regression.sh [outdir] (CHECKS= subset env). Before-move output: regression-before.txt (parts 1+2, all 8 PASS). Full run ~10 min (track_check ~2 min/track).
- 3: perf-baseline.md (median 3.4 ms, p95 6.3 ms per tick, 12 karts, Ryzen 7 7800X3D, headless). capture_traces.gd --perf-out= mode, CSVs in perf/.
- 4: gdUnit4 v6.2.3 (github.com/godot-gdunit-labs/gdUnit4, where MikeSchulze/gdUnit4 redirects; README lists 4.8.dev7) in addons/gdUnit4, plugin NOT enabled in project.godot (CLI needs no plugin). tests/unit/data/item_set_roll_test.gd 2/2 PASS via commands.test (gdunit4-example-run.txt). Duplicate trace CSVs in repro-before/ and regression-before-part2/traces/ left untracked (identical to golden).
