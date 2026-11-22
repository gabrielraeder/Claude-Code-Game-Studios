<!-- PROTOTYPE - NOT FOR PRODUCTION -->
# Collision spike - STATE

Throwaway prototype for ADR-0002 (collision backend) and ADR-0005 (Blender pipeline).
Engine: C:/Godot/Godot_v4.8-beta3_win64_console.exe (4.8.beta3.official.c51ff06e8). Blender 5.3.
Machine: AMD Ryzen 7 7800X3D, 16 threads, Windows 11.

## Steps
- [x] 0. Project skeleton (project.godot pins Jolt, 60 Hz)
- [x] 1. Q1 API probe (face_index, settings, _into signatures) -> out/probe_api.txt, out/probe_query_default.txt, out/probe_query_faceindex.txt
- [x] 2. Q2 headless query outside physics frame -> out/probe_q2_node.txt (+ probe_query outputs)
- [x] 3. Q3 synthetic track generator + 3 backends + bench -> out/bench_log.txt (3 repeats each), out/compare.txt
- [x] 4. Q4 Blender round trip (editor import + runtime GLTFDocument) -> out/blender_build.txt, out/q4_post_import.txt, out/q4_runtime.txt
- [x] 5. Q5 mirror sanity -> out/q5_mirror.txt
- [~] 6. REPORT.md: the harness refused to let the subagent write REPORT.md ("return findings as text"); the full report went to the coordinator in the handback. README.md (required by the prototype rules) was written with a short summary.

## What exists
- scripts/probe_api.gd: ClassDB dump. Setting physics/jolt_physics_3d/queries/enable_ray_cast_face_index (default false). _into methods exist, result classes are RefCounted, instantiable.
- scripts/probe_query.gd: face_index -1 when setting false, = triangle index in set_faces order when true (via override.cfg). One-sided by default (backface_collision=false): back faces never hit even with hit_back_faces=true.
- scripts/probe_q2_node.gd: server bodies queryable immediately; node bodies queryable as soon as inside tree (add_child in _initialize is not inside tree yet). Runtime set_setting of face index took effect only from the next frame (mechanism unverified). Moving a node body: visible to queries only next frame.
- scripts/track_gen.gd, backend_engine.gd, backend_grid.gd, bench.gd, compare.gd, run_bench.sh (writes/removes override.cfg for the face-index setting), probe_motion.gd (cast_motion ignores initial overlap; one-sided faces invisible to shape queries from behind).
- Q3 medians (ms/tick, 12 karts x (4 rays + 1 sweep)): face_into 0.059/0.060 (50k/150k), face_dict 0.102/0.105, shape_into 0.068/0.071, shape_dict 0.112/0.115, grid c1 0.136/0.186, c2 0.169/0.289, c4 0.27/0.60.
- blender/build_track_piece.py -> import_test/track_piece.glb (+ .import with import_script/path=res://scripts/post_import.gd); scripts/scene_dump.gd, post_import.gd, q4_runtime.gd.
- Q4: extras -> node meta "extras" (Dictionary) in both editor import and runtime GLTFDocument; ints arrive as float (kk_index 0 -> 0.0); material names + material extras preserved; Blender +Y -> Godot -Z confirmed; empties keep transforms; 1 unit = 1 m; Mesh.get_faces() winding is Godot-front (rays hit with correct normals).
- scripts/q5_mirror.gd: mirror + winding flip exact on Jolt and the grid; without the flip all rays miss. Wall semantic gap: Jolt misses a sphere that starts overlapping and ends behind a one-sided wall.
- Open: REPORT.md must be saved by the coordinator from the handback text.
