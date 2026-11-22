# PROTOTYPE - NOT FOR PRODUCTION. ADR-0005 NV-9: frame_set + matrix_world sampling, collection
# iteration, and process exit codes.
# Run: blender --background --factory-startup [--python-exit-code N] --python blender/probe_adr45_nv9.py -- <mode>
# mode: sysexit3 | raise | ok
import sys
import math
import bpy

MODE = sys.argv[sys.argv.index("--") + 1]
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.render.fps = 30
scene.frame_start = 1
scene.frame_end = 31
col = bpy.data.collections.new("Course")
scene.collection.children.link(col)
e = bpy.data.objects.new("Mover", None)
col.objects.link(e)
e.location = (0, 0, 0)
e.rotation_euler = (0, 0, 0)
e.keyframe_insert("location", frame=1)
e.keyframe_insert("rotation_euler", frame=1)
e.location = (10, 0, 0)
e.rotation_euler = (0, 0, math.radians(90))
e.keyframe_insert("location", frame=16)
e.keyframe_insert("rotation_euler", frame=16)
e.location = (0, 0, 0)
e.rotation_euler = (0, 0, 0)
e.keyframe_insert("location", frame=31)
e.keyframe_insert("rotation_euler", frame=31)
act = e.animation_data.action if e.animation_data else None
print("NV9 action=%s frame_range=%s fps=%d" % (act.name if act else None, tuple(act.frame_range) if act else None, scene.render.fps))
for f in (1, 8, 16, 24, 31):
    scene.frame_set(f)
    m = e.matrix_world
    q = m.to_quaternion()
    print("NV9 frame %d t=%.4f pos=(%.4f,%.4f,%.4f) quat(wxyz)=(%.4f,%.4f,%.4f,%.4f)" % (f, (f - 1) / scene.render.fps, m.translation.x, m.translation.y, m.translation.z, q.w, q.x, q.y, q.z))
for c in scene.collection.children_recursive:
    print("NV9 collection %s objects=%s all_objects=%s" % (c.name, [o.name for o in c.objects], [o.name for o in c.all_objects]))
print("NV9 version", bpy.app.version_string)
if MODE == "sysexit3":
    print("NV9 calling sys.exit(3)")
    sys.exit(3)
if MODE == "raise":
    print("NV9 raising RuntimeError")
    raise RuntimeError("probe failure")
print("NV9 ok")
