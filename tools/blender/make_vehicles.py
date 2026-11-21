"""Armored cart + war-bike (story 006).
Regenerate:  blender --background --python tools/blender/make_vehicles.py
Writes assets/vehicles/veh_cart_armored.glb and veh_bike_war.glb.
glTF-space authoring (x right, y up, z back, vehicle drives to -z), see common.py.
Dog contract shared by both: Seat = dog hip origin; the dog's paws rest at
Seat + (+-0.22, +0.22, -0.55) so the dash / handlebar sits exactly there.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common as cm  # noqa: E402
from mathutils import Vector  # noqa: E402

WHEEL_R = 0.35


def wheel(sc, root, name, centre, width, outward):
    """Separate mesh, origin at the wheel centre so Godot can spin it about X."""
    mb = cm.MB(sc, name, origin=centre, parent=root)
    c = Vector(centre)
    mb.cyl(c, WHEEL_R, WHEEL_R, width, "dark", axis="x", seg=14)
    mb.cyl(c, 0.27, 0.27, width + 0.04, "wood", axis="x", seg=14)
    mb.cyl(c, 0.10, 0.10, width + 0.08, "iron", axis="x", seg=8)
    xo = c + Vector((outward * (width / 2 + 0.03), 0, 0))
    mb.box(xo, (0.05, 0.52, 0.09), "iron")
    mb.box(xo, (0.05, 0.09, 0.52), "iron")
    return mb.build()


def side_panel(mb, xi, xo, prof, m):
    mb.prism([(xi, y, z) for z, y in prof], [(xo, y, z) for z, y in prof], m)


def make_cart():
    cm.reset_scene()
    cm.clear_mats()
    for n in ("paint", "trim", "iron", "wood", "dark"):
        cm.mat(n)
    sc = cm.Scene()
    root = sc.empty("Vehicle")
    sc.empty("Seat", (0, 0.62, 0.25), root)
    sc.empty("PennantMount", (0, 1.06, 1.1), root)

    b = cm.MB(sc, "Body", parent=root)
    # wooden chassis: wide trapezoid, narrow nose
    b.poly([(-0.45, -1.25), (0.45, -1.25), (0.6, -0.5), (0.6, 1.2), (-0.6, 1.2), (-0.6, -0.5)],
           0.22, 0.52, "wood", top_scale=0.94)
    # paint hood (big panel) and cockpit side/rear panels
    b.poly([(-0.42, -1.2), (0.42, -1.2), (0.56, -0.5), (-0.56, -0.5)], 0.5, 0.7, "paint", top_scale=0.92)
    prof = [(-0.2, 0.5), (1.15, 0.5), (1.15, 1.0), (0.5, 1.0), (-0.2, 0.8)]
    side_panel(b, 0.38, 0.64, prof, "paint")
    side_panel(b, -0.38, -0.64, prof, "paint")
    b.box((0, 0.78, 1.05), (1.28, 0.56, 0.2), "paint")
    # dash (paws rest on top at y 0.74), wood with an iron cap
    b.box((0, 0.62, -0.30), (0.92, 0.24, 0.42), "wood")
    b.box((0, 0.745, -0.30), (0.96, 0.05, 0.46), "iron")
    # bolted iron plates: side plates, rear bumper, wheel fenders
    for s in (-1, 1):
        b.box((s * 0.64, 0.37, 0.02), (0.07, 0.30, 0.62), "iron")
        b.box((s * 0.79, 0.79, -0.70), (0.30, 0.10, 0.66), "iron")
        b.box((s * 0.79, 0.79, 0.75), (0.30, 0.10, 0.66), "iron")
    b.box((0, 0.40, 1.28), (1.0, 0.22, 0.10), "iron")
    # nose shield: iron rim, paint face, paw crest in trim
    b.cyl((0, 0.60, -1.30), 0.41, 0.41, 0.12, "iron", axis="z", seg=16)
    b.cyl((0, 0.60, -1.355), 0.33, 0.33, 0.05, "paint", axis="z", seg=16)
    cz = -1.40
    b.cyl((0, 0.53, cz), 0.115, 0.115, 0.05, "trim", axis="z", seg=10)
    for dx, dy in ((-0.17, 0.12), (-0.075, 0.2), (0.075, 0.2), (0.17, 0.12)):
        b.cyl((dx, 0.53 + dy, cz), 0.06, 0.06, 0.05, "trim", axis="z", seg=8)
    # pennant socket
    b.cyl((0, 1.0, 1.1), 0.07, 0.07, 0.12, "iron", axis="y", seg=8)
    b.build()

    for nm, x, z in (("Wheel_FL", -0.75, -0.7), ("Wheel_FR", 0.75, -0.7),
                     ("Wheel_RL", -0.75, 0.75), ("Wheel_RR", 0.75, 0.75)):
        wheel(sc, root, nm, (x, WHEEL_R, z), 0.26, 1 if x > 0 else -1)
    print("TRIS cart", cm.tri_count(bpy_objs()))
    cm.export_glb(os.path.join(cm.VEH_DIR, "veh_cart_armored.glb"))


def bpy_objs():
    import bpy
    return list(bpy.data.objects)


def make_bike():
    cm.reset_scene()
    cm.clear_mats()
    for n in ("paint", "trim", "iron", "wood", "dark"):
        cm.mat(n)
    sc = cm.Scene()
    root = sc.empty("Vehicle")
    sc.empty("Seat", (0, 0.95, 0.2), root)
    sc.empty("PennantMount", (0, 1.32, 1.1), root)

    b = cm.MB(sc, "Body", parent=root)
    # tall narrow wedge hull (paint), iron belly, wood saddle, tail fin
    b.poly([(-0.55, 0.42), (-0.55, 0.64), (0.0, 0.74), (0.55, 0.78), (0.65, 0.55), (0.45, 0.42)],
           0.17, 0.17, "paint", plane="zy")
    b.poly([(-0.5, 0.30), (-0.5, 0.45), (0.4, 0.45), (0.4, 0.30)], 0.11, 0.11, "iron", plane="zy")
    b.poly([(-0.15, 0.72), (-0.15, 0.83), (0.05, 0.88), (0.55, 0.88), (0.6, 0.80), (0.55, 0.72)],
           0.22, 0.22, "wood", plane="zy")
    b.poly([(0.45, 0.78), (0.5, 1.1), (1.1, 1.32), (1.15, 1.18), (0.95, 0.78)],
           0.08, 0.08, "paint", plane="zy")
    b.cyl((0, 1.28, 1.1), 0.07, 0.07, 0.1, "iron", axis="y", seg=8)
    # swing arms and fork
    for s in (-1, 1):
        b.beam((s * 0.15, 0.55, 0.45), (s * 0.15, 0.35, 0.85), (0.07, 0.09), (0.07, 0.09), "iron")
        b.beam((s * 0.15, 0.35, -0.9), (s * 0.15, 0.78, -0.62), (0.07, 0.09), (0.07, 0.09), "iron")
    b.build()

    # horse-head prow in plate armour
    pm = Vector((0, 0.7, -0.5))
    pr = cm.MB(sc, "Prow", origin=pm, parent=root)
    n0, n1 = Vector((0, 0.7, -0.5)), Vector((0, 1.3, -0.84))
    pr.beam(n0, n1, (0.34, 0.30), (0.26, 0.26), "iron")
    dn = (n1 - n0).normalized()
    right = dn.cross(Vector((0, 1, 0))).normalized()
    up2 = right.cross(dn).normalized()
    pr.beam(n0 + up2 * 0.18 + dn * 0.05, n1 + up2 * 0.18, (0.09, 0.07), (0.09, 0.07), "paint")  # mane crest
    h0, h1 = Vector((0, 1.36, -0.78)), Vector((0, 1.10, -1.24))
    pr.beam(h0, h1, (0.30, 0.36), (0.18, 0.20), "iron")
    dh = (h1 - h0).normalized()
    rh = dh.cross(Vector((0, 1, 0))).normalized()
    uh = rh.cross(dh).normalized()
    pr.beam(h0 + uh * 0.20 - dh * 0.0, h1 + uh * 0.11, (0.11, 0.05), (0.09, 0.05), "trim")  # chanfron
    for s in (-1, 1):
        pr.cyl((s * 0.11, 1.55, -0.70), 0.07, 0.0, 0.26, "iron", axis="y", seg=6,
               rot=(-15, 0, s * -8))
    pr.build()

    # handlebar (reins bar) where the paws land: Seat + (0, 0.22, -0.55)
    hb = Vector((0, 1.17, -0.35))
    h = cm.MB(sc, "Handlebar", origin=hb, parent=root)
    h.box(hb, (0.62, 0.07, 0.07), "iron")
    for s in (-1, 1):
        h.cyl(hb + Vector((s * 0.30, 0, 0)), 0.055, 0.055, 0.16, "dark", axis="x", seg=8)
    h.beam(Vector((0, 1.02, -0.72)), hb, (0.08, 0.08), (0.08, 0.08), "iron")
    h.build()

    wheel(sc, root, "Wheel_F", (0, WHEEL_R, -0.9), 0.20, 1)
    wheel(sc, root, "Wheel_R", (0, WHEEL_R, 0.85), 0.20, 1)
    print("TRIS bike", cm.tri_count(bpy_objs()))
    cm.export_glb(os.path.join(cm.VEH_DIR, "veh_bike_war.glb"))


if __name__ == "__main__":
    make_cart()
    make_bike()
