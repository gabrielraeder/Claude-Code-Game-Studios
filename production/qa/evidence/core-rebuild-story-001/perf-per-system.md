# Per-system tick cost — frozen 2.5D build (core-rebuild story 001)

**Purpose:** input for the technical director's per-system budget for the rebuild (logged decision 2026-11-22).
**What:** host milliseconds per physics tick, split by system, 12 karts (host autopilot + 11 bots), Castle Circuit,
1 lap, race seed 1001, real time (no `--fixed-fps`), headless. 2,942 race ticks per run (tick 0 dropped, as in
`perf-baseline.md`).
**Build:** frozen game at 740379e (tree unchanged: `git status src/legacy` empty), Godot 4.8.beta3.official.c51ff06e8
editor binary (debug build), 2026-11-22. **Machine:** the owner's PC (Ryzen 7 7800X3D, 31 GB, RTX 5070, Windows 11).
Headless: no rendering cost anywhere in this file.

## Method

`tools/profile_tick.gd` (new, measurement only) is a SceneTree wrapper like `tools/capture_traces.gd`. It loads the
real main scene. During `NET_RACE` it switches Main's own `_physics_process` off and runs a line-for-line copy of
`Main._net_tick` / `_tick_owned` from the tool, calling the same objects in the same order with a
`Time.get_ticks_usec()` stamp between calls. `KartDriver.drive` and `KartSim.tick` are timed separately per kart.

Fidelity and overhead checks:

| Check | Result |
|---|---|
| Replica trace (`--fixed-fps 60 --trace-out`) vs `golden/bots_castle_circuit.csv` | **IDENTICAL**, 35,316 rows (`perf/per_system/fidelity-compare.txt`) |
| Replica ran on every race tick | 2,943 / 2,943 |
| Sum of the stages vs the replica total (mean) | 3.945 vs 3.971 ms, 0.026 ms unattributed |
| Bracketed `tick_ms` with the replica vs without it (`--replica=0`) vs `perf-baseline.md` | median 3.494 / 3.507 vs 3.486 vs 3.447 / 3.429 ms (within run-to-run noise) |

Hot functions come from a separate run with the GDScript profiler (`-d`, `EngineDebugger.profiler_enable("scripts")`,
`--fixed-fps 60`, same race). The profiler inflates time (×1.40 on the tick, and more on functions called very
often), so its numbers are used for **shares within a stage**, never as milliseconds. One row is an artifact and is
excluded: `_on_tick_end` self 13.6 s comes from the profiler being switched on inside that call.

Commands (port 24690):

```
godot --headless --path . -s res://tools/profile_tick.gd -- --perf-out=<csv> --proc-out=<csv> \
  --host --port=24690 --players=1 --bots=11 --autopilot --quit-after-race --laps=1 --track=castle_circuit --race-seed=1001
# fidelity: add --fixed-fps 60 before --path and --trace-out=<csv>; overhead A/B: --replica=0
# hot functions: godot --headless -d --fixed-fps 60 ... -- --profile-scripts ...  (< /dev/null)
```

## Results: per system, ms per tick (2 runs)

Share = the stage's mean / the mean tick (3.98 ms). Medians and p95s do not add up; the means do.

| System (stages) | Median run 1 / 2 | p95 run 1 / 2 | Mean | Share |
|---|---|---|---|---|
| **Kart contacts**: `_resolve_kart_contacts` + `_separate_karts` + `_measure_contacts` | 1.483 / 1.494 | 3.676 / 3.655 | 1.88 | **47.3 %** |
| … of which `_separate_karts` (3 push-apart passes + `clamp_to_walls` ×12 per pass) | 1.114 / 1.127 | 3.305 / 3.268 | 1.52 | 38.2 % |
| … of which `_resolve_kart_contacts` (132 ordered pairs) | 0.281 / 0.282 | 0.317 / 0.322 | 0.27 | 6.9 % |
| … of which `_measure_contacts` (debug stats) | 0.090 / 0.091 | 0.104 / 0.105 | 0.09 | 2.2 % |
| **Bot decisions**: `BotDriver.drive` ×11 | 0.953 / 0.942 | 1.105 / 1.107 | 0.93 | **23.3 %** |
| **Kart sim**: `KartSim.tick` ×12 (+ start sequence) | 0.807 / 0.817 | 1.504 / 1.496 | 0.93 | **23.3 %** |
| Items: `ItemManager.update` | 0.108 / 0.109 | 0.136 / 0.141 | 0.12 | 2.9 % |
| Race logic: laps, rank keys, `RaceRanking`, finish check | 0.033 / 0.033 | 0.039 / 0.040 | 0.03 | 0.8 % |
| Net: `KartWire.pack` + `send_state` at 30 Hz (no clients: no receive path) | 0.023 / 0.024 | 0.048 / 0.049 | 0.02 | 0.6 % |
| Autopilot (host's driver) | 0.019 / 0.019 | 0.024 / 0.024 | 0.02 | 0.5 % |
| Hazards: `HazardManager.update` + trace | 0.011 / 0.011 | 0.015 / 0.016 | 0.01 | 0.3 % |
| Debug logs (`_net_log_tick`, surface log) | 0.002 / 0.002 | 0.003 / 0.004 | 0.00 | 0.1 % |
| **Whole tick** (`tick_ms`) | **3.494 / 3.507** | **6.393 / 6.367** | 3.98 | 100 % |
| Scope of the 3 ms budget (bots + autopilot + sim + kart contacts) | 3.272 / 3.278 | 6.177 / 6.144 | 3.76 | 94.4 % |

Per kart: `KartSim.tick` median of the slowest kart per tick 0.09 ms (p95 0.26). One bot's decision, median of the
slowest bot per tick, 0.10 ms (p95 0.14).

Outside the tick (per `_process` frame, headless; 7,104 frames per run):

| Measure | Median | p95 | Mean |
|---|---|---|---|
| All `_process` work in a frame (bracketed) | 3.00 | 3.18 | 3.00 |
| … `KartVisual._process` ×12 (its own counter) | 0.135 | 0.152 | 0.136 |
| … `ChaseCamera._process` (≈ 90 % of the profiled `_process` time) | ≈ 2.7 (est.) | — | — |

Physics-step overhead beyond the game's nodes (the engine monitor aligned one tick later, minus `tick_ms`) is about
1.0-1.4 ms median and 4.0 ms p95. It is unattributed: it covers the physics server step, transform notifications and
frames with two ticks. It is kept for reference only.

## What dominates: track queries

**Track geometry queries (`TrackModel.query` → `Path.nearest`) are the hot path.** `Path.nearest` alone is 57 % of
all GDScript self time in the profiled race (track_model.gd: 73 %). Inside the tick, `TrackModel.query` is ~43 % of
the profiled tick time:

- **`_separate_karts` → `clamp_to_walls`**: 36 queries per tick (3 passes × 12 karts), 73 % of the separation
  stage. The kart-pair push itself (`push_apart`, 198 calls per tick, plus `levels_apart` and `_push_of`) is the rest.
- **`KartSim._constrain_to_track`**: 92 % of `KartSim.tick`. About half of it is the track query. About 39 % is
  `_mover_hit` → `HazardManager.hit_test` (kart vs moving hazard, through `position_at`, `progress_at` and
  `is_active`). The kart dynamics themselves (speed, steer, drift, boost, surfaces) are under ~10 % of the sim stage,
  about 0.1 ms for 12 karts.
- **Why p95 is double the median:** `TrackModel.query` does a full, unwindowed scan, `bp.nearest(p, -1, 0)`, of
  every branch whose bounding box contains the kart. Branches are open roads, so the hint window is never used.
  In ticks 600-1600 (race 10-27 s, the branch section) the separation median rises from 1.0 to 2.8 ms and the sim
  median from 0.75 to 1.4 ms, while the bot cost stays flat (0.92-1.07 ms). The tick median there is 5.9 ms.
- **Camera (not in the tick):** `ChaseCamera._keep_inside_corridor` calls `TrackModel.excess_at` 10 times a frame,
  and each call fully scans the main road and every branch (`nearest(p, -1, 0)`). That is ~2.7 ms per frame on the
  owner's PC, 20 times the cost of all 12 kart visuals.

Bot decisions (profiled shares of `BotDriver._drive`): `_scan_traffic` 15 %, `_rubber` 15 %, `_barrel_lane` 14 %
(hazard timing through `HazardManager.travelers_between`), `_zone_open_sides` 4 %, `_route_branch` 4 %. The
remaining ~45 % is spread over native math and track lookups under the profiler's per-function floor. Bots cost
~0.02 ms per tick during the countdown (ticks 0-300) and 0.92-1.07 ms after it.

Kart-pair work is O(n²): 132 ordered `resolve_kart_contact` pairs and 198 `push_apart` calls per tick at 12 karts.
No broadphase.

## Proposed per-system budget for the rebuild (owner's PC, p95 per tick, 12 karts)

This is a proposal for the technical director, who sets the budgets. It keeps the architecture's ≤ 3 ms for kart
simulation + collision + bot decisions and measures it at **p95** (the worst-case host).

| System | Proposed p95 | Frozen build today | Rationale |
|---|---|---|---|
| Kart physics (integration, drift, boost, surfaces, start), excluding queries | 0.4 ms | ~0.1 ms (est.) | Room for mesh-contact response; ~0.03 ms per kart |
| Track collision queries (≤ 4 ground casts + ≤ 1 wall sweep per kart) | 0.8 ms | ~1.7 ms mean, ~3.5+ ms p95 (est.: ~43 % of the tick) | ≤ 60 queries per tick, cost independent of track section (no full scans) |
| Kart-kart contact (broadphase, resolve, separation, re-clamp of moved karts only) | 0.3 ms | 1.88 mean / 3.67 p95 (includes 36 re-clamp queries) | 66 pairs behind a route-distance broadphase |
| Kart vs hazard / mover tests | 0.2 ms | ~0.35 ms (est.: ~39 % of sim) | |
| Bot decisions (11 bots, ≈ 0.09 ms each) | 1.0 ms | 0.93 mean / 1.11 p95 | Today's cost; MK-level bots (items) will need it |
| Reserve | 0.3 ms | — | |
| **Subtotal (the 3 ms scope)** | **3.0 ms** | 3.76 mean / 6.16 p95 | |
| Items | 0.3 ms | 0.14 p95 | Grows with the MK item set |
| Hazard / mover update | 0.1 ms | 0.02 p95 | |
| Race logic (laps, ranking, finish) | 0.1 ms | 0.04 p95 | |
| Net (host pack/send to 11 clients, receive, remote karts) | 0.3 ms | 0.05 p95, no clients | Not yet measured with clients |
| Debug logging | 0 in release | 0.004 | Behind debug flags |
| **Whole tick** | **≤ 3.8 ms** | 6.38 p95 | |
| Per frame, outside the tick: camera | ≤ 0.3 ms | ~2.7 ms | No full-road scans per frame |
| Per frame: kart visual sync (12 karts) | ≤ 0.5 ms | 0.14 ms headless | |
| Per frame: HUD, minimap, audio | ≤ 0.5 ms | ~0.3 ms (est.) | |

**Scaling to the minimum CPU (Ryzen 5 2600 / i5-8400): an estimate, not a measurement.** GDScript runs on one
thread, so single-thread speed decides. Recalled public single-thread benchmark ratios (not checked in this session)
put the 7800X3D about 1.6-1.8× ahead. Its large L3 cache probably helps interpreter-bound code more than synthetic
benchmarks show, so the estimate here is **1.7-2.2×**:

- The proposed 3.0 ms becomes ~5-6.6 ms on the minimum CPU, and the 3.8 ms whole tick ~6.5-8.4 ms. That leaves
  ~8 ms of a 16.6 ms frame for presentation and render submission.
- The frozen build as host of 12 on the minimum CPU (est.): tick median ~6-7.7 ms, p95 ~11-14 ms, plus ~4.6-6 ms
  of camera per frame. At p95 it would likely miss 60 fps.

**Conflict to resolve (technical director):** `docs/architecture/architecture.md` says both "≤ 3 ms per tick … on
the owner's PC" (Performance Budgets) and "the minimum CPU is the one the budget is measured against" (Target
Hardware). If the 3 ms applies to the minimum CPU, the owner's-PC targets above shrink to ~1.4-1.8 ms for the
3 ms scope. Measure on a real minimum-spec machine before release (QQ-06).

## Limits of this measurement

- **No release-like measure:** no export templates are installed for 4.8-beta3 (`%APPDATA%/Godot/export_templates/`
  is empty; nothing was downloaded). All numbers come from the editor (debug) binary, whose GDScript runs with
  debug checks. A release template would likely be somewhat faster, by an unknown amount, so treat these figures as
  an upper bound.
- Headless: no GPU or render cost. One track, one seed, no remote clients (the receive / `RemoteKart` path is 0 here).
- The countdown is included (ticks 0-300, where bots cost ~0). From tick 300 on: median 3.56 / 3.58 ms, p95 6.43 /
  6.39 ms.
- Shared PC: the two runs agree within 0.02 ms (median) and 0.03 ms (p95).

## Files (`perf/per_system/`)

`stages_run1.csv`, `stages_run2.csv` (per-tick stages), `proc_run1.csv`, `proc_run2.csv` (per-frame `_process` and
`KartVisual` cost), `noreplica_run1.csv` (overhead A/B), `fidelity-compare.txt`, `fidelity_fixedfps.log`,
`scriptprof_raw.log` (GDScript profiler; the ACCUMULATED table is at the end), `scriptprof_stages.csv`, and a `.log`
beside each run.
