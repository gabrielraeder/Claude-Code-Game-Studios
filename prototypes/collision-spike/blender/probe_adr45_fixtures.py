# PROTOTYPE - NOT FOR PRODUCTION. ADR-0005 probes NV-2/3/4/8/14 + per-surface materials.
# Run: blender --background --factory-startup --python blender/probe_adr45_fixtures.py -- <out.glb> [<copy.glb> ...]
# Builds the four ADR-0005 collections, exports with the ADR-0005 §3 flag set (every flag explicit),
# and copies the GLB to every further path given.
import sys
import shutil
import struct
import bpy

ARGS = sys.argv[sys.argv.index("--") + 1:]
OUT = ARGS[0]

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.unit_settings.system = 'METRIC'
scene.unit_settings.scale_length = 1.0

def f32(v):
    return struct.unpack("f", struct.pack("f", v))[0]

cols = {}
for n in ("Ground", "Walls", "Visual", "Course"):
    c = bpy.data.collections.new(n)
    scene.collection.children.link(c)
    cols[n] = c

def mat(name):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    return m

def mesh_obj(name, col, verts, faces, mats, face_mats):
    me = bpy.data.meshes.new(name + "_mesh")
    me.from_pydata(verts, [], faces)
    for m in mats:
        me.materials.append(mat(m))
    for i, fm in enumerate(face_mats):
        me.polygons[i].material_index = fm
    me.update()
    o = bpy.data.objects.new(name, me)
    cols[col].objects.link(o)
    return o

FAR_X0, FAR_X1, FAR_Y0, FAR_Y1, FAR_Z = 1995.123457, 1999.987654, 1900.5, 1910.25, 3.333333
NEG_X0, NEG_X1, NEG_Y0, NEG_Y1 = -1999.987654, -1995.5, -1999.75, -1990.0
road_verts = [
    (-7, 0, 0), (7, 0, 0), (7, 40, 0), (-7, 40, 0),                 # A road (0..3)
    (-12, 0, 0), (-7, 0, 0), (-7, 40, 0), (-12, 40, 0),             # B grass (4..7)
    (FAR_X0, FAR_Y0, FAR_Z), (FAR_X1, FAR_Y0, FAR_Z), (FAR_X1, FAR_Y1, FAR_Z), (FAR_X0, FAR_Y1, FAR_Z),  # C far road
    (NEG_X0, NEG_Y0, 0), (NEG_X1, NEG_Y0, 0), (NEG_X1, NEG_Y1, 0), (NEG_X0, NEG_Y1, 0),                 # D far grass
]
road = mesh_obj("Road", "Ground", road_verts,
                [(0, 1, 2, 3), (4, 5, 6, 7), (8, 9, 10, 11), (12, 13, 14, 15)],
                ["surf_road", "surf_grass"], [0, 1, 0, 1])
wall = mesh_obj("Barrier-col", "Walls", [(7, 0, 1.5), (7, 40, 1.5), (7, 40, 0), (7, 0, 0)], [(0, 1, 2, 3)], ["wall_stone"], [0])
neg = mesh_obj("NegRoad", "Ground", [(0, 0, 0), (2, 0, 0), (2, 2, 0), (0, 2, 0)], [(0, 1, 2, 3)], ["surf_road"], [0])
neg.location = (20.0, 0.0, 0.0)
neg.scale = (-1.0, 1.0, 1.0)
for nm in ("Prop-noimp", "Box-colonly", "Thing-rigid", "Plain"):
    o = mesh_obj(nm, "Visual", [(0, 0, 0), (1, 0, 0), (1, 1, 0), (0, 1, 0)], [(0, 1, 2, 3)], ["vis_prop"], [0])
    o.location = (30.0, 5.0 * len(nm), 0.0)

KEYS = ";".join("%d,%.6f,%.6f,%.6f,0,0,0,1" % (i, i * 0.5, -i * 0.25, 1.0) for i in range(1300))
KEYS = KEYS[:40000]
KEYS_LEN = len(KEYS)
track = bpy.data.objects.new("Track", None)
track.empty_display_type = 'ARROWS'
cols["Course"].objects.link(track)
track["kk_type"] = "track"
track["kk_schema"] = 1
track["kk_keys"] = KEYS
track["kk_float"] = 1.5
track["kk_bool"] = True
cp = bpy.data.objects.new("CP_0", None)
cp.empty_display_type = 'ARROWS'
cp.location = (0.0, 10.0, 0.0)
cols["Course"].objects.link(cp)
cp["kk_type"] = "checkpoint"
cp["kk_index"] = 0
# a scratch collection that must NOT be exported (selection-based export)
scratch = bpy.data.collections.new("_scratch")
scene.collection.children.link(scratch)
s = bpy.data.objects.new("ScratchEmpty", None)
scratch.objects.link(s)

# Road and Walls already have identity transforms (built in place)
print("BLENDER kk_keys len=%d head=%s tail=%s" % (KEYS_LEN, KEYS[:24], KEYS[-24:]))
print("BLENDER far quad float32 x0=%.9g x1=%.9g y0=%.9g y1=%.9g z=%.9g" % (f32(FAR_X0), f32(FAR_X1), f32(FAR_Y0), f32(FAR_Y1), f32(FAR_Z)))
print("BLENDER neg-scale det=%.3f" % neg.matrix_world.determinant())
for c in bpy.data.collections:
    print("BLENDER collection %s objects=%s" % (c.name, [o.name for o in c.objects]))

bpy.ops.object.select_all(action='DESELECT')
for n in ("Ground", "Walls", "Visual", "Course"):
    for o in cols[n].objects:
        o.select_set(True)
tmp = OUT + ".tmp.glb"
bpy.ops.export_scene.gltf(
    filepath=tmp,
    export_format='GLB', export_yup=True, export_extras=True, export_apply=True,
    use_selection=True,
    export_animations=False, export_skins=False, export_morph=False,
    export_cameras=False, export_lights=False,
    export_materials='EXPORT', export_texcoords=True, export_normals=True,
    export_hierarchy_full_collections=False)
import os
os.replace(tmp, OUT)
print("EXPORTED", OUT)
for extra in ARGS[1:]:
    shutil.copyfile(OUT, extra)
    print("COPIED", extra)
