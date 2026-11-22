# PROTOTYPE - NOT FOR PRODUCTION. Collision spike. Q4: builds an asymmetric track piece and exports GLB.
# Run: blender --background --factory-startup --python blender/build_track_piece.py -- <out.glb>
#
# Blender axes: Z up, travel along +Y. Road 14 m wide (x -7..7) from y=0 to y=40,
# grass on the LEFT only (x -12..-7), a ramp at the FAR end only (y 30..40), walls
# at x=-12 and x=+7. Empties: checkpoint, respawn (rotated 30 deg about Z),
# grid slot, and an asymmetric marker mesh whose tip points along local +Y.
import sys
import math
import bpy
import bmesh

OUT = sys.argv[sys.argv.index("--") + 1]
ROAD_HALF = 7.0
GRASS_W = 5.0
LENGTH = 40.0
RAMP_Y0 = 30.0
RAMP_HALF = 3.0
RAMP_H = 1.5
WALL_H = 1.5
CP_POS = (0.0, 10.0, 0.0)
RESPAWN_POS = (2.0, 5.0, 0.5)
RESPAWN_YAW_DEG = 30.0
GRID_POS = (-3.0, 2.0, 0.0)
MARKER_POS = (5.0, 20.0, 1.0)

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.unit_settings.system = 'METRIC'
scene.unit_settings.scale_length = 1.0

def material(name, color):
    m = bpy.data.materials.new(name)
    m.diffuse_color = color
    m["kk_surface"] = name.removeprefix("surf_")  # material-level custom property
    return m

mats = {n: material(n, c) for n, c in [("surf_road", (0.3, 0.3, 0.3, 1)), ("surf_grass", (0.1, 0.6, 0.1, 1)),
                                       ("surf_wall", (0.6, 0.5, 0.4, 1)), ("surf_ramp", (0.8, 0.2, 0.2, 1))]}
mat_order = ["surf_road", "surf_grass", "surf_wall", "surf_ramp"]

# --- track mesh (built with bmesh; faces get material indices) ---
me = bpy.data.meshes.new("track_piece_mesh")
obj = bpy.data.objects.new("track_piece", me)
scene.collection.objects.link(obj)
for n in mat_order:
    me.materials.append(mats[n])
bm = bmesh.new()

def quad(p0, p1, p2, p3, mat):
    vs = [bm.verts.new(p) for p in (p0, p1, p2, p3)]
    f = bm.faces.new(vs)
    f.material_index = mat_order.index(mat)
    return f

quad((-ROAD_HALF, 0, 0), (ROAD_HALF, 0, 0), (ROAD_HALF, LENGTH, 0), (-ROAD_HALF, LENGTH, 0), "surf_road")
quad((-ROAD_HALF - GRASS_W, 0, 0), (-ROAD_HALF, 0, 0), (-ROAD_HALF, LENGTH, 0), (-ROAD_HALF - GRASS_W, LENGTH, 0), "surf_grass")
# walls: vertex order chosen so the normals face inward (toward the road)
quad((-ROAD_HALF - GRASS_W, LENGTH, WALL_H), (-ROAD_HALF - GRASS_W, 0, WALL_H), (-ROAD_HALF - GRASS_W, 0, 0), (-ROAD_HALF - GRASS_W, LENGTH, 0), "surf_wall")
quad((ROAD_HALF, 0, WALL_H), (ROAD_HALF, LENGTH, WALL_H), (ROAD_HALF, LENGTH, 0), (ROAD_HALF, 0, 0), "surf_wall")
# ramp: slope from y=RAMP_Y0 (z=0.02) to y=LENGTH (z=RAMP_H)
quad((-RAMP_HALF, RAMP_Y0, 0.02), (RAMP_HALF, RAMP_Y0, 0.02), (RAMP_HALF, LENGTH, RAMP_H), (-RAMP_HALF, LENGTH, RAMP_H), "surf_ramp")
bm.normal_update()
for f in bm.faces:
    c = f.calc_center_median()
    nm = f.normal
    print("BLENDER face mat=%s center=(%.1f,%.1f,%.1f) normal=(%.2f,%.2f,%.2f)" % (mat_order[f.material_index], c.x, c.y, c.z, nm.x, nm.y, nm.z))
bm.to_mesh(me)
bm.free()
obj["kk_type"] = "track_collision"
obj["kk_version"] = 1

# --- asymmetric marker: a flat arrow whose tip is at local +Y, offset fin at local +X ---
mm = bpy.data.meshes.new("marker_mesh")
marker = bpy.data.objects.new("Marker_Asym", mm)
scene.collection.objects.link(marker)
mm.from_pydata([(0, 2.0, 0), (-0.5, 0, 0), (0.5, 0, 0), (0.5, 0, 1.0)], [], [(1, 2, 0), (2, 3, 0)])
marker.location = MARKER_POS
marker["kk_type"] = "marker"
marker["kk_note"] = "tip at local +Y, fin at local +X"

# rotated copy of the marker (90 deg about Z): tip should point along Blender -X
marker_r = marker.copy()
marker_r.name = "Marker_Rot90"
marker_r.location = (MARKER_POS[0], MARKER_POS[1] + 5.0, MARKER_POS[2])
marker_r.rotation_euler = (0.0, 0.0, math.radians(90.0))
scene.collection.objects.link(marker_r)

def empty(name, pos, yaw_deg, props):
    e = bpy.data.objects.new(name, None)
    e.empty_display_type = 'ARROWS'
    e.location = pos
    e.rotation_euler = (0.0, 0.0, math.radians(yaw_deg))
    for k, v in props.items():
        e[k] = v
    scene.collection.objects.link(e)
    return e

empty("CP_0", CP_POS, 0.0, {"kk_type": "checkpoint", "kk_index": 0, "kk_width": 14.0})
empty("Respawn_0", RESPAWN_POS, RESPAWN_YAW_DEG, {"kk_type": "respawn", "kk_index": 0, "kk_flag": True})
empty("Grid_0", GRID_POS, 0.0, {"kk_type": "grid_slot", "kk_index": 0})

# apply transforms on the track mesh only (empties and markers keep their pose by design)
bpy.ops.object.select_all(action='DESELECT')
obj.select_set(True)
bpy.context.view_layer.objects.active = obj
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

for o in scene.objects:
    print("BLENDER object %s type=%s loc=%s rot=%s props=%s" % (o.name, o.type, tuple(round(v, 3) for v in o.location),
          tuple(round(math.degrees(v), 1) for v in o.rotation_euler), {k: o[k] for k in o.keys()}))

bpy.ops.export_scene.gltf(filepath=OUT, export_format='GLB', export_yup=True, export_extras=True, export_apply=True)
print("BLENDER exported", OUT)
