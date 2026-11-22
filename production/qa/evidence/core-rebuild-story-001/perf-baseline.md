# Performance baseline — frozen 2.5D build (core-rebuild story 001)

**What:** the host's milliseconds per physics tick, 12 karts (host autopilot + 11 bots), Castle Circuit,
1 lap, race seed 1001, real time (no `--fixed-fps`), headless. 2,942 race ticks per run (tick 0 dropped).
**Build:** frozen game at commit ab7d773 + story-001 tools, Godot 4.8.beta3.official.c51ff06e8, 2026-11-22.
**Machine:** AMD Ryzen 7 7800X3D (8 cores), 31.1 GB RAM, NVIDIA GeForce RTX 5070 (+ AMD Radeon iGPU), Windows 11 Pro.
Headless, so no rendering cost is included: this is the simulation cost only.

Command (one run):

```
godot --headless --path . -s res://tools/capture_traces.gd -- --perf-out=<csv> --host --port=24690 \
  --players=1 --bots=11 --autopilot --quit-after-race --laps=1 --track=castle_circuit --race-seed=1001
```

| Measure | Run | Median ms | p95 ms | p99 ms | Max ms | Mean ms |
|---|---|---|---|---|---|---|
| `tick_ms` (direct: first to last node of the tick) | 1 | 3.447 | 6.298 | 6.568 | 10.281 | 3.916 |
| `tick_ms` | 2 | 3.429 | 6.254 | 6.516 | 10.444 | 3.896 |
| `engine_physics_ms` (TIME_PHYSICS_PROCESS monitor) | 1 | 4.916 | 8.250 | 10.299 | 10.299 | 5.200 |
| `engine_physics_ms` | 2 | 4.963 | 7.535 | 10.463 | 10.463 | 5.056 |

**Baseline figure:** median **3.4 ms**, p95 **6.3 ms** per tick (`tick_ms`, both runs within 0.05 ms).

Notes:
- `tick_ms` is timed by two recorder nodes, physics priority -1,000,000 and +1,000,000, around every game
  node's `_physics_process` of that tick (Main's race tick, items, hazards). It excludes the engine's
  physics server step. It is the number to compare against later.
- `engine_physics_ms` is the engine monitor read during the tick, so it is the previous frame's value and
  includes the physics server and the recorder. Kept for reference only.
- Files: `perf/perf_castle_12karts.csv` (run 1), `perf/perf_castle_12karts_run2.csv` (run 2), logs beside them;
  `perf/perf_castle_12karts_monitor_only.csv` is a first run that recorded the monitor only (median 5.05, p95 8.61).
- Both runs recorded 2,943 ticks, the same count as the fixed-fps golden trace `bots_castle_circuit.csv`.
