<!-- PROTOTYPE - NOT FOR PRODUCTION -->
# Collision spike - STATE for ADR-0004 / ADR-0005 validation probes

Engine: C:/Godot/Godot_v4.8-beta3_win64_console.exe. Blender 5.3. Scripts: scripts/probe_adr45_*.gd, blender/probe_adr45_*.py. Output: out/probe_adr45_*.txt.

## Steps
- [x] 1. ADR-0004 V1/V2: binary .res round trip (typed Array[Transform3D], packed arrays, Array[custom Resource]); cache identity; NV-13 sha256
- [x] 2. Blender fixtures (suffix names, 2 km vertex, 40 KB string extra, negative scale, two materials) + NV-9 exit codes
- [x] 3. NV-3 / NV-4 / NV-11: import params written before first import; suffix hints off; compression off vs on
- [x] 4. NV-5: _post_import returning null (fresh, and over an earlier good import); --import exit code
- [x] 5. NV-6 / NV-7: ResourceSaver.save into res:// during headless _post_import; non-@tool instance methods; reimport loop
- [x] 6. NV-1: filesystem/import/blender/enabled and .gdignore
- [x] 7. Report

## Results (short)
- ADR-0004 V1/V2 VERIFIED (out/probe_adr45_res_roundtrip.txt). Plain non-@export vars are NOT saved. Fresh bakes differ across processes only in random sub-resource ids; fixed resource_scene_unique_id gives identical files (out/probe_adr45_res_determinism.txt).
- NV-3, NV-4, NV-6, NV-7, NV-8, NV-9, NV-11, NV-13 VERIFIED; NV-2 VERIFIED; NV-14 observed (det -1 node, winding flips).
- NV-5: returning null is silent: exit 0, no error line; fresh -> no .scn and retried every --import; over a good import -> old .scn kept and md5 updated (stale scene served).
- NV-1: setting exists (default true); its effect not shown headless (importer queried the Blender path with the setting false via override.cfg).
- Resource-valued meta DOES persist in the imported scene (out/probe_adr45_load_imported.txt).
- A touch of an unchanged .glb does not reimport; delete .godot/imported/<file>-<hash>.md5 to force it.
