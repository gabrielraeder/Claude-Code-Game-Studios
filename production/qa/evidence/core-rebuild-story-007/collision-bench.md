# Collision benchmark: core-rebuild story 007

Track Collision AC-20; ADR-0002 Performance Implications; `architecture.md` Performance Budgets
(track collision queries <= 0.3 ms p95 per tick, 12 karts). Date: 2026-11-22.
Scope note (owner, 2026-11-22): the hot core moves to C++ (GDExtension). This GDScript
`CollisionQuery` is the reference oracle for that port, and the story 007 tests are the port's
acceptance tests.

## Machine and build

- **Machine:** AMD Ryzen 7 7800X3D, RTX 5070, Windows 11.
- **Build:** Godot 4.8-beta3 debug editor binary (`C:/Godot/Godot_v4.8-beta3_win64_console.exe`,
  4.8.beta3.official.c51ff06e8), `--headless`. This is accepted as an **upper bound**, because the
  4.8 export templates are not installed, so no release export could be measured.
- **Physics:** Jolt (project pin); private inactive space; 60 ticks/s, real-time paced.
- **Other load:** a separate Godot editor process (not started by this run) was open during the
  runs and was left alone. Its share of the noise is not measured.

## What is timed

- `tools/bench_collision.gd` is a SceneTree script. A Hook node's `_physics_process` runs one timed
  block per tick (`Time.get_ticks_usec()` around it). The block covers 12 karts. For each kart:
  - 4 `cast_ground` probes;
  - 3 `sweep_walls` calls (all 3 always run). Each one runs its unconditional rest check at
    `from`, so the block holds ADR-0002's "3 sweeps, 4 rays and the rest check".
- On top of the karts, the block calls `mover_pose` once per mover.
- The kart inputs are computed before the block. Tick time t = n x SIM_DT.
- **Query:** built through `CollisionBootCheck.checked_query(data, surfaces, walls, 5.0)`.
- **Mesh:** `tools/bench_track_fixture.gd`, built deterministically in code: **48,006 ground +
  4,800 wall triangles**. It is a 1,200 m figure-eight with:
  - a two-level crossover (8 m bridge);
  - banking up to 12 deg;
  - 14 m of road, then 8 m of grass or sand each side;
  - two wall attributes (standard on the left, rough on the right);
  - a 10 m trick ramp.
- **No branch:** the fixture has no branch. The **crossover stands in for one** in the "at least 4
  sections including any branch" criterion.
- **Sections:** all 12 karts are in one section at a time, for 300 timed ticks per section, after
  60 untimed warm-up ticks. Each kart weaves into the walls.

| Section | Arc length (m) | Notes |
|---|---|---|
| curve | 1170-1230 | banked |
| climb | 130-190 | bridge approach |
| crossover | 280-320 and 880-920 | 6 karts per level |
| movers | 570-630 | worst layout: 596-604 and a 5 m weave |
| ramp | 950-990 | 2.5 m weave |

- **Layouts:**
  - `castle`: after the frozen Castle Circuit's hazards (read-only, from
    `assets/tracks/castle_circuit/castle_circuit.tres`):
    - a drawbridge: a solid box deck 5 x 0.4 x 18 m, raised 78 deg over [12, 20) s of 20 s;
    - a portcullis: a solid box 4.5 x 2.6 x 0.6 m that drops 2.8 m over [3.5, 9.0) s of 20 s;
    - 3 **non-solid** rolling barrels (frozen `solid_body = false`).
  - `worst` (TD-012): 5 spinning boxes 16 x 1 x 0.6 m, two at kart height and three 5 cm over the
    sweep sphere. All 12 karts stay within their reach.
  - `static`: no movers.

## Commands

```
bash tools/bench_collision.sh production/qa/evidence/core-rebuild-story-007/runs <label> 3 castle worst static
C:/Godot/Godot_v4.8-beta3_win64_console.exe --headless --path . -s res://tools/bench_collision.gd -- --layout=castle --out=PATH.txt
C:/Godot/Godot_v4.8-beta3_win64_console.exe --headless --path . -s res://tools/bench_collision.gd -- --layout=castle --stages --out=PATH.txt
```

- Every configuration ran 3 times, as separate processes, one at a time.
- The figures below are the **median of the 3 run medians / median of the 3 run p95s**, in
  microseconds per tick.
- Raw files are in `runs/`: `<label>-<layout>-<n>.txt|.log` and `<label>-aggregate.txt`. The
  labels are `baseline`, `opt1`, `opt2`, `opt3` (split helpers), `opt3inline` (castle only) and
  `opt3final` (the final code). The stage runs are `stages-<layout>.txt` (opt2) and
  `stages-opt3-<layout>.txt`.

## Results (final code = opt3final)

| Layout | Median | p95 | curve p95 | climb p95 | crossover p95 | movers p95 | ramp p95 |
|---|---|---|---|---|---|---|---|
| **castle** (realistic) | **237** | **281** | 259 | 257 | 259 | **292** | 243 |
| **worst** (TD-012) | 262 | **868** | 289 | 281 | 288 | **898** | 269 |
| static | 171 | 190 | 193 | 190 | 197 | 182 | 177 |

- **Castle: met at the limit, inside measurement noise.**
  - Its worst section is the movers section, at 292 µs p95 (the 3 runs gave 291 / 295 / 292).
  - The same code measured 296 in the opt3inline set, and the opt3 split variant measured 303.
  - Run-to-run spread is about ±5 µs, so the margin to 300 is noise-sized. This is not a met
    budget with margin.
- **Worst case: not met** (868 / 898 µs).

## Before and after

| Step | castle med / p95 | castle movers p95 | worst med / p95 | worst movers p95 | static med / p95 |
|---|---|---|---|---|---|
| baseline (story 005 code) | 308 / 381 | 398 | 391 / 1445 | 1489 | 195 / 214 |
| opt1 | 262 / 303 | 317 | 324 / 869 | 900 | 198 / 224 |
| opt2 | 238 / 283 | 294 | 265 / 864 | 893 | 172 / 193 |
| opt3, split helpers (review fixes) | 242 / 291 | 303 | 269 / 898 | 927 | 172 / 191 |
| opt3inline (castle only) | 237 / 282 | 296 | n/a | n/a | n/a |
| **opt3final** (review fixes, inline) | **237 / 281** | **292** | **262 / 868** | **898** | **171 / 190** |

**opt1** changed these things:
- a solid-mover slot list;
- a pose and inverse cache per mover, keyed by t;
- angular velocity computed lazily;
- an overlap pass before any mover sweep;
- Newton's method from the start of the motion, plus bisection, replacing the golden-section
  search.

**opt2** changed these things:
- the path-sphere cull is inlined;
- the mover passes are skipped when there are no solid movers;
- the query masks are set once in `QueryCursor`.

**opt3** applied the review correctness fixes:
- the Newton cap fails closed;
- the touch rule needs the end itself in contact;
- the unsafe-point retry;
- two semantics-identical trims, made before the owner dropped item 5: no motion reset at
  `sweep_walls` entry, and `cast_ground` reads `out.point` instead of re-reading
  `result.position`.

The opt3 split into helper functions cost +7 µs p95 (+2.4%) on the castle movers section. That is
over the 2% limit, so the final code keeps `_test_movers_for_sweep` and `_sweep_local` as one
function each, with a `# perf waiver (story 007)` comment. There was no regression from the
correctness fixes: opt3final is within noise of opt2 on every layout.

## Per-stage breakdown (opt3, `--stages`, one run per layout, µs median / p95 per tick)

| Stage | castle curve | castle movers | worst curve | worst movers | static curve |
|---|---|---|---|---|---|
| CollisionQuery `cast_ground` x 48 | 93 / 111 | 109 / 120 | 107 / 123 | 440 / 453 | 69 / 75 |
| CollisionQuery `sweep_walls` x 36 | 104 / 118 | 121 / 135 | 114 / 129 | 353 / 391 | 79 / 93 |
| `mover_pose`, **cache hits only** (the main block already evaluated every mover at this t) | 3 / 3 | 3 / 3 | 3 / 3 | 3 / 3 | 0 / 1 |
| raw `intersect_ray_into` x 48 | 27 / 32 | 27 / 28 | 27 / 31 | 25 / 27 | 27 / 31 |
| raw `get_rest_info_into` at from x 36 | 16 / 18 | 16 / 17 | 15 / 17 | 12 / 13 | 16 / 18 |
| raw `cast_motion_into` x 36 | 22 / 33 | 23 / 28 | 22 / 33 | 16 / 16 | 23 / 33 |
| raw `get_rest_info_into` at to x 36 | 15 / 17 | 15 / 16 | 15 / 17 | 12 / 12 | 15 / 17 |

**Reading:**
- **Jolt itself:** the raw calls the static set needs total about 80 µs median (about 95 µs p95).
- **GDScript wrapper cost:** about 0.9 µs per `cast_ground` and about 0.7 µs per `sweep_walls`.
- **Per-solid-mover cost:**
  - **out of reach:** about 15-25 µs per solid mover per tick (12 karts x 7 queries of cull). In
    the worst layout's far sections, the 5 far movers add about 73 µs over static. In castle's
    far sections, the 2 far movers add about 49 µs.
  - **in reach of all 12 karts:** about 130 µs per solid mover per tick, about 1.5 µs per
    query-mover pair. In the worst layout's movers section, the 5 movers add about 646 µs over
    static (stages: (440 + 353) - (69 + 78)).

## Allocation check

- **The evidence:**
  - `Performance.OBJECT_COUNT` (with `OBJECT_RESOURCE_COUNT`, `OBJECT_NODE_COUNT` and
    `OBJECT_ORPHAN_NODE_COUNT`) was unchanged between timed tick 0, timed tick 600 and the end
    (tick 1500) in every bench run: 27 for baseline, opt1 and opt2, and 21 for opt3 and opt3final.
    The query's `owned_rids().size()` (6) was also unchanged.
  - The static scan `test_no_server_create_calls_outside_build_functions`
    (`tests/unit/collision/collision_mover_edge_cases_test.gd`) shows that no
    `PhysicsServer3D.*_create(` or `RenderingServer.*_create(` call exists in
    `collision_query.gd` or `query_cursor.gd` outside `_init`, `_make_concave_shape` and
    `_make_static_body`. So no query method can create a server object.
  - The `--verbose` run (`rid-leak-check.log`) printed no RID leak report at exit.
- **What could not be read:** the server RID count itself. Godot 4.8-beta3 has no API for it
  (ClassDB probe).
- **Dropped:** the `PhysicsServer3D.get_process_info` counters. They are always 0 in an inactive
  space, so they show nothing.
- **Reported, not gated:** `MEMORY_STATIC` drifts by about 100-250 bytes per 600 ticks. It is not
  an Object and not a RID.

## Unsafe-point fallback (QL finding, fixed in opt3)

- **Symptom:** every baseline / opt1 / opt2 log printed `sweep_walls: no rest contact at the unsafe
  point; reporting a blocking hit with WALL_ATTR_NONE`. Each such hit reported the wrong wall
  attribute.
- **Captured input** (bench mesh, curve section, tick 167, kart 10, sweep 0, radius 1):
  - `from (213.37308, -0.99377036, -13.371248)`, `to (213.40935, -1.0054376, -12.961111)`;
  - Jolt cast result: safe 0.25, unsafe 0.2539.
- **Cause (Jolt, 4.8-beta3):** a rest check exactly at the unsafe point finds no contact.
  - One 0.00001 m further along the motion still finds none; one 0.0001 m further finds the right
    wall (shape 1).
  - The same 22 nearby wall triangles on their own do not reproduce it. It depends on the whole
    mesh.
  - In a 1,500-tick probe, 1 of 127 unsafe-point checks was affected.
- **Fix:** when the rest check at the unsafe point is empty, `_write_blocked_hit` retries once
  `UNSAFE_RETRY_LENGTH` (0.001 m) further along the motion. Only if both are empty does it keep
  the old WALL_ATTR_NONE fallback.
- **Test:** `collision_unsafe_point_retry_test.gd` uses this input on the bench mesh. It was
  watched failing without the retry (`mutation-no-unsafe-retry.log`, exit 100).
- **Result:** 0 opt3 / opt3final logs contain the warning (9 baseline logs did).

## Criteria

| Criterion | Result |
|---|---|
| Budget <= 0.3 ms p95 | **castle (realistic): met at the limit, inside measurement noise** (281 whole block; worst section 292). **TD-012 worst case: not met** (868 / 898). |
| Flat per section (>= 4 sections incl. branch) | 5 sections; the crossover stands in for a branch. castle: all <= 300. worst: the movers section (898) is over; the other sections are within the budget on the run median, with single runs up to 311. |
| No allocation | met (OBJECT_COUNT, the static `*_create` scan, `--verbose` exit; the server RID count is unreadable) |
| Record | this file |

## Generator-baked Castle mesh

PLACEHOLDER: a re-run on the generator-baked Castle mesh is added here when story 008 lands.
