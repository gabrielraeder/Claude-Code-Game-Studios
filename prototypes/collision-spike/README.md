<!-- PROTOTYPE - NOT FOR PRODUCTION -->
# Collision spike (ADR-0002 collision backend, ADR-0005 Blender track pipeline)

## Hypothesis
- A Jolt-backed track-collision query meets the budget with room to spare: 12 karts × (4 ground rays + 1 wall sweep) per tick, well under 1 ms.
- It can be queried headless and outside `_physics_process`, and it can return a per-triangle surface id.
- A Blender → glTF → Godot pipeline keeps the custom properties, material names and ADR-0001 axes.

## How to run
- **Engine:** `C:/Godot/Godot_v4.8-beta3_win64_console.exe`, with `--headless --path prototypes/collision-spike`.
- **Q1/Q2:** `-s res://scripts/probe_api.gd`, `probe_query.gd`, `probe_q2_node.gd`, `probe_motion.gd`.
- **Q3:**
  - `bash scripts/run_bench.sh` runs the full matrix and writes `out/bench_log.txt`.
  - It writes and removes `override.cfg` to switch the face-index setting.
  - `-s res://scripts/compare.gd -- ref=<tag> other=<tag>` compares two runs.
- **Q4:**
  - `blender --background --factory-startup --python blender/build_track_piece.py -- <abs path>/import_test/track_piece.glb`
  - then `godot --headless --path . --import` (the post-import script is set in `import_test/track_piece.glb.import`)
  - then `-s res://scripts/q4_runtime.gd`
- **Q5:** `-s res://scripts/q5_mirror.gd`. It needs the face-index setting, so put an `override.cfg` with `[physics] jolt_physics_3d/queries/enable_ray_cast_face_index=true` in this folder first.

## Status
Concluded on 2026-11-22. All five questions were measured. The raw outputs are in `out/`.

## Findings (short)
- **Q1:** `face_index` needs `physics/jolt_physics_3d/queries/enable_ray_cast_face_index` (default `false`).
  - With it on, `face_index` is the index in `set_faces()` order.
  - The 4.8 `*_into(params, result) -> bool` methods exist, with RefCounted result classes.
  - Concave faces are one-sided by default.
  - `cast_motion` ignores starting overlaps.
- **Q2:** server-created bodies in a private space are queryable immediately, headless and outside the physics frame.
- **Q3** (median ms/tick, 48k / 154k triangles):

  | Backend | 48k | 154k |
  |---|---|---|
  | Jolt face_index + `_into` | 0.059 | 0.060 |
  | Jolt per-surface shapes | 0.068 | 0.071 |
  | Jolt + Dictionary API | 0.10 | 0.11 |
  | GDScript grid, 1 m cells | 0.136 | 0.186 |

- **Q4:**
  - Blender custom properties arrive as node meta `extras`, but integers come back as float.
  - Material names and material extras are kept.
  - Blender +Y lands as Godot −Z.
  - Empties keep their transforms, and 1 unit = 1 m.
  - Both the editor import and runtime `GLTFDocument` give the same result.
- **Q5:** the ADR-0001 §7 mirror is exact when the winding is flipped. Without the flip, every ray falls through.

The full write-up went to the coordinator as text, because the agent was not allowed to write a REPORT.md file.
