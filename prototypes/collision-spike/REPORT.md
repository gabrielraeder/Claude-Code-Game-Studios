<!-- PROTOTYPE - NOT FOR PRODUCTION -->
# Collision spike: report for ADR-0002 (collision backend) and ADR-0005 (Blender track pipeline)

- **Date:** 2026-11-22.
- **Machine:** AMD Ryzen 7 7800X3D, 16 threads, Windows 11.
- **Engine:** `C:/Godot/Godot_v4.8-beta3_win64_console.exe` (4.8.beta3.official.c51ff06e8), run headless. This is the editor binary, a debug build; a release template was not measured.
- **Blender:** 5.3.0 (glTF I/O v5.3.43).
- **Project:** standalone, at `prototypes/collision-spike/`; `project.godot` sets `physics/3d/physics_engine="Jolt Physics"`.
- **Raw outputs:** `out/`.

Everything here was observed unless it is marked **UNVERIFIED**. (Written by the spike agent; saved and spot-checked against `out/bench_log.txt` and `out/q5_mirror.txt` by the main session.)

## Q1. Jolt `face_index`, its setting, and the `_into` API

- **Setting:** `physics/jolt_physics_3d/queries/enable_ray_cast_face_index`, **default `false`**.
  - Off: `face_index` is -1 in the Dictionary, and `collider_face_index` is -1 in the `_into` result.
  - On: it is the triangle index in `set_faces()` order. The face_index → surface lookup matched the per-shape backend on all 92,160 rays.
  - Changed at runtime with `set_setting`, it only took effect from the next frame (mechanism UNVERIFIED). Pin it in `project.godot`.
- **Related settings:** `physics/jolt_physics_3d/queries/use_enhanced_internal_edge_removal=false` and `.../collisions/active_edge_threshold=0.8727`.
- **Signatures (from ClassDB at runtime):**
  - `intersect_ray_into(PhysicsRayQueryParameters3D, PhysicsIntersectRayResult3D) -> bool`
  - `cast_motion_into(PhysicsShapeQueryParameters3D, PhysicsCastMotionResult3D) -> bool`
  - `intersect_point_into`, `intersect_shape_into`, `collide_shape_into` and `get_rest_info_into`, each taking (params, result) and returning a bool.
- **Result classes:** RefCounted, created with `.new()`, getters only.
  - `PhysicsIntersectRayResult3D`: position, normal, collider_rid, collider_id, collider, collider_shape, collider_face_index.
  - `PhysicsCastMotionResult3D`: safe_fraction and unsafe_fraction only (**no normal or point**).
  - `PhysicsGetRestInfoResult3D`: point, normal, collider_rid, collider_id, collider_shape, collider_velocity (**no face index**).
- **`cast_motion` and `cast_motion_into`** return true only on a hit. They **ignore an overlap that already exists at the start**; only `get_rest_info` and `collide_shape` report it.
- **Winding:**
  - The front of a triangle (a, b, c) faces along `(c-a)×(b-a)`.
  - With `ConcavePolygonShape3D.backface_collision=false` (the default), back faces are never hit, even though `hit_back_faces` defaults to true.
  - With `backface_collision=true`, a back-face hit reports the normal flipped.

## Q2. Querying headless, outside `_physics_process`

- Server-created bodies (`PhysicsServer3D.body_create` in a private space with `space_create` + `space_set_active(true)`) answer rays in the same call, with no physics frame in between.
- The whole Q3 bench (about 130k queries per pass) runs in `_initialize()` on a space that is never stepped, and its results are correct.
- A `StaticBody3D` added in `_initialize()` misses because it is not inside the tree yet. Added in `_process`, it answers immediately.
- A moved node body is seen at its old pose until the next frame. Static track geometry is unaffected.
- **Verdict:** yes. A RefCounted `CollisionQuery` can own a private space with no nodes. QQ-04 is resolved.

## Q3. Cost per tick: 12 karts × (4 rays + 1 sweep)

**Track:** generated deterministically (`scripts/track_gen.gd`):
- a 1200 m lemniscate loop with a 14 m road and 8 m of off-road on each side;
- 1.5 m walls;
- up to 12° of banking;
- a two-level crossover (8 m);
- a ramp.

It comes in two sizes: 48,006 triangles and 153,606 triangles.

**Queries:** 4 wheel rays per kart and one sphere sweep (r 0.6). The sweep is `cast_motion_into`, then `get_rest_info_into` at the unsafe point, plus a rest check at `to` when the cast is clear.

**Timing:** 120 warm-up ticks, then 1800 timed ticks. Each configuration ran in 3 processes, and the table shows the median of the three run medians.

**Backends:**
- **(a)** one ground shape, with surface = `table[face_index]`;
- **(b)** one shape per surface id;
- **(c)** a pure-GDScript XZ grid. Its wall test is face interiors only, so it serves as a cost proxy.

**Variants:** `into` uses the 4.8 `_into` methods with reused result objects; `dict` uses the Dictionary API.

| Config | Tris | Median ms/tick | p95 | Rays only | Sweeps only | Setup ms |
|---|---|---|---|---|---|---|
| (a) face, into | 48k | **0.059** | 0.064 | 0.038 | 0.014 | 27 |
| (a) face, dict | 48k | 0.102 | 0.110 | 0.077 | 0.018 | 27 |
| (b) shape, into | 48k | 0.068 | 0.073 | 0.047 | 0.014 | 38 |
| (c) grid, 1 m cells | 48k | 0.136 | 0.154 | 0.121 | 0.010 | 76 |
| (c) grid, 4 m cells | 48k | 0.276 | 0.312 | 0.255 | 0.014 | 53 |
| (a) face, into | 154k | **0.060** | 0.068 | 0.040 | 0.014 | 90 |
| (a) face, dict | 154k | 0.105 | 0.115 | 0.080 | 0.018 | 90 |
| (b) shape, into | 154k | 0.071 | 0.077 | 0.050 | 0.015 | 132 |
| (c) grid, 1 m cells | 154k | 0.186 | 0.213 | 0.172 | 0.012 | 196 |
| (c) grid, 4 m cells | 154k | 0.603 | 0.692 | 0.574 | 0.021 | 159 |

The full table, with the 2 m grid and the face-index setting variants, is in `out/bench_log.txt`.

- **Per query:**
  - (a) into: about 0.8 µs per ray and 1.2 µs per sweep. Jolt's cost stays flat as triangle count grows.
  - (a) dict: about 1.6 µs per ray.
  - (c) grid: 2.5-3.6 µs per ray, growing with triangles per cell.
- **Cross-check (92,160 rays):**
  - (b) against (a): 0 surface mismatches, max |dy| 4e-5 m, identical wall contacts.
  - (c) against (a): 0-1 surface mismatches (on an edge).
  - The grid misses 5-7% of wall contacts, the edge and vertex cases it does not model.
  - The crossover was exercised: 9,663 upper-deck hits, and the backends agree on them.
- **Allocations:**
  - Neither variant shows net growth in `OBJECT_COUNT` or static memory.
  - The Dictionary API is about 1.8× slower.
  - Zero allocation at the C++ level is UNVERIFIED. Jolt mesh memory is UNVERIFIED, because the static-memory counter does not see it.
  - The grid's arrays take 3.7-8.5 MB with 1 m cells.
- **Verdict:** every backend is far under budget. Jolt (a) costs about 0.06 ms/tick at either size, about 2% of the 3 ms sim budget. QQ-01 and QQ-02 are resolved.

## Q4. Blender → glTF → Godot

**Blender side** (`blender/build_track_piece.py`; Z up, travel along +Y). The script builds:
- a road with grass on the left only, a ramp at the far end and walls facing inward;
- materials `surf_road`, `surf_grass`, `surf_wall` and `surf_ramp`;
- empties `CP_0`, `Respawn_0` (rotated 30° about Z) and `Grid_0`, carrying `kk_*` custom properties;
- asymmetric markers.

It exports with `export_format='GLB', export_yup=True, export_extras=True, export_apply=True`.

**Godot side:** the import goes through `import_script/path="res://scripts/post_import.gd"` with `--import`. It is compared with runtime `GLTFDocument`.

| Question | Editor import | Runtime GLTFDocument |
|---|---|---|
| Custom properties | Yes, as node meta `extras` (a Dictionary). **Integers arrive as float**; bools and strings are kept | Same (also in `GLTFState.json`) |
| Material names | Yes, `resource_name` = `surf_road` etc. Blender exports `doubleSided:true` → `cull_mode=2` | Same |
| Blender +Y → Godot -Z | Yes. Marker tip at Blender local (0, 2, 0) → Godot (0, 0, -2); world (5, 20, 1) → (5, 1, -20) | Same |
| Empties keep transforms | Yes. `CP_0` lands at (0, 0, -10) facing -Z; `Respawn_0` lands at (2, 0.5, -5), forward (-0.5, 0, -0.866) | Same |
| 1 unit = 1 m | Yes | Same |
| `Mesh.get_faces()` winding | Godot-front: up normals on road and ramp, inward normals on walls | Same |
| Post-import meta persists | Yes (`set_meta` in `_post_import` survives into the saved `.scn`) | n/a |

**Gotchas:**
- A wrong vertex order produced outward-facing walls, which are invisible to one-sided Jolt. The importer must check that wall normals face the route.
- `export_extras` defaults to False in Blender 5.3.
- `SINGLE_ARROW` empties are believed to point along local +Z (UNVERIFIED). Use `ARROWS`.
- Never apply transforms to pose empties.

## Q5. Mirror (ADR-0001 §7)

| Variant | Rays hit on both | Normal ≠ M·n | Walls both / one side |
|---|---|---|---|
| Jolt, winding flipped | **4000/4000** | 0 | 698 / 0 |
| Jolt, NOT flipped | **0** (all mirrored rays miss) | — | 371 (wrong normals) / 627 |
| Grid, flipped | 4000/4000 | 0 | 994 / 0 |
| Grid, NOT flipped | 0 | — | 0 / 994 |

- **Pose bases:** max |det(M·B·M) − 1| = 2.4e-7, and forward(M·B·M) = M·forward(B). A naive M·B has det −1.
- **Verdict:** §7 is correct. Forgetting the winding flip fails silently: every ground ray falls through.
- **Wall contacts, 698 vs 994:** the gap is a semantic one, not a mirror bug.
  - Jolt ignores an overlap that exists at the start of a sweep.
  - So a kart that already overlaps a one-sided wall can tunnel out.
  - Mitigations, both UNVERIFIED: walls with `backface_collision=true`, or resolving the overlap before the sweep (ADR-0003).

## Recommendations

**ADR-0002 → backend (a).**
- **Jolt and the surface id:** one `ConcavePolygonShape3D` for the static ground, with the surface id taken from `face_index`.
- **Pin the face-index setting:** `enable_ray_cast_face_index=true`, pinned in `project.godot` and asserted at boot.
- **Query API:** the `_into` methods with reused params and result objects.
- **No nodes:** a private PhysicsServer3D space, owned by the RefCounted `CollisionQuery`.
- **Walls:** a separate shape on their own layer. `get_rest_info` has no face index, so give walls one shape per wall-attribute id.
- **Sweep:** `cast_motion_into` → `get_rest_info_into`, plus a rest check at `to`. Measure `backface_collision` for walls before deciding it.
- **Fallback:** (b), documented.
- **Drop (c).**
- **Track-load checks:** a known point casts to the known surface with up normal, and wall normals face the route.

**ADR-0005 → editor-time import as the main path.**
- **The import script:** an `EditorScenePostImport`, which also runs headless with `--import`. It bakes the TrackPackage (triangles from `get_faces()`, surface ids from material names, poses from empties) and validates at import (±2 km, wall normals, required empties).
- **Runtime `GLTFDocument`:** it gives identical data. Keep it for user or mod tracks.
- **Metadata conventions:** `kk_*` properties are read from `get_meta("extras")`, numbers always cast with `int()`; materials named `surf_<id>`; export with `export_extras=True`; `ARROWS` empties; transforms applied to meshes only.

## Not done / next

- A release-template build.
- Jolt memory.
- Walls with `backface_collision=true` against tunnelling.
- A wall-attribute lookup.
- The `SINGLE_ARROW` axis.
- Overlap resolution, which belongs to ADR-0003.
