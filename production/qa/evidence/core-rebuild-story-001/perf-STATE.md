# Per-system perf breakdown — working state (performance-analyst, 2026-11-22)

Task: per-system ms/tick of the frozen 2.5D game, 12 karts (autopilot + 11 bots), Castle Circuit,
seed 1001 -> report perf-per-system.md. Rule: src/legacy unchanged in git (check `git status src/legacy`).

## Steps
- [x] 1. tools/profile_tick.gd: SceneTree wrapper; disables Main._physics_process during NET_RACE and runs a
      timed replica of Main._net_tick (stages + per-kart drive/sim split); --trace-out for fidelity check.
- [x] 2. Fidelity: --fixed-fps 60 trace vs golden/bots_castle_circuit.csv (compare_traces.py) IDENTICAL.
- [x] 3. Real-time runs x2 (no --fixed-fps), CSVs in perf/per_system_*.csv.
- [x] 4. GDScript profiler run (-d, EngineDebugger.profiler_enable("scripts")) for hot functions.
- [x] 5. Export templates check: NONE installed (%APPDATA%/Godot/export_templates is empty), 2026-11-22.
- [x] 6. Report perf-per-system.md; git status src/legacy empty.

## Notes
- 1-2: tools/profile_tick.gd written; fixed-fps replica trace IDENTICAL to golden (35316 rows), replica ran every tick -> perf/per_system/fidelity-compare.txt
- 3: stages_run1/2.csv (+proc_run1/2, noreplica_run1) in perf/per_system/; tick med 3.49/3.51 p95 6.39/6.37; separate 38%, bot drive 23%, sim 23%, contacts 7%; proc frame 3.0 ms med
- 4: scriptprof_raw.log (fixed-fps, -d). Path.nearest 57% of script self time (full scans of branches in TrackModel.query; camera excess_at full scans 10/frame = ~89% of _process). _on_tick_end self 13.6 s is an artifact (profiler enabled inside it) - excluded.
- 6: perf-per-system.md written; git status src/legacy empty. DONE.
