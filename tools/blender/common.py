"""Shared helpers for the Dogworks Racing Blender model scripts (story 006).

Run through headless Blender, e.g.
  blender --background --python tools/blender/make_vehicles.py

Authoring convention: all model code is written in *glTF space* (x right, y up,
z BACK; the vehicle drives toward -z) with real metres.  MB converts to Blender
space (Z up, +Y forward) on the way in, so the glTF exporter (+Y up) gives the
exact axes the Godot side expects.  Every object has identity rotation/scale.
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Euler, Matrix, Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
VEH_DIR = os.path.join(ROOT, "assets", "vehicles")
CHAR_DIR = os.path.join(ROOT, "assets", "characters")
EVID_DIR = os.path.join(ROOT, "production", "qa", "evidence", "story-006-racers", "models")

# art bible section 4 palette
PAL = {
    "paint": "#E8452C",
    "trim": "#F6EBD0",
    "iron": "#5C6068",
    "wood": "#8A5A33",
    "dark": "#2A1E26",
    "eye": "#F6EBD0",
}

# glTF-space -> Blender-space (proper rotation, det = +1)
C = Matrix(((1, 0, 0, 0), (0, 0, -1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))


def G(v):
    v = Vector(v)
    return Vector((v.x, -v.z, v.y))


def _lin(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def hex_to_lin(h):
    h = h.lstrip("#")
    return tuple(_lin(int(h[i:i + 2], 16) / 255.0) for i in (0, 2, 4)) + (1.0,)


def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


_MATS = {}


def mat(name, hexcol=None):
    """Flat-colour material (no textures, rough, non-metal)."""
    if name in _MATS and _MATS[name].name in bpy.data.materials:
        return _MATS[name]
    hexcol = hexcol or PAL[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = hex_to_lin(hexcol)
    bsdf.inputs["Roughness"].default_value = 0.8
    bsdf.inputs["Metallic"].default_value = 0.0
    m.diffuse_color = hex_to_lin(hexcol)
    _MATS[name] = m
    return m


def clear_mats():
    _MATS.clear()


def P_for_axis(axis):
    """Maps a primitive whose axis/poles are local Z onto my-space axis."""
    if axis == "z":
        return Matrix.Identity(4)
    if axis == "y":
        return Matrix(((1, 0, 0, 0), (0, 0, 1, 0), (0, -1, 0, 0), (0, 0, 0, 1)))
    if axis == "x":
        return Matrix(((0, 0, 1, 0), (1, 0, 0, 0), (0, 1, 0, 0), (0, 0, 0, 1)))
    raise ValueError(axis)


class Scene:
    """Collects objects of one asset; parents expressed in glTF-space world positions."""

    def __init__(self):
        self.coll = bpy.context.scene.collection

    def empty(self, name, pos=(0, 0, 0), parent=None):
        o = bpy.data.objects.new(name, None)
        o.empty_display_type = "PLAIN_AXES"
        o.empty_display_size = 0.1
        self.coll.objects.link(o)
        o["_world"] = tuple(pos)
        if parent is not None:
            o.parent = parent
            o.location = G(Vector(pos) - Vector(parent["_world"]))
        else:
            o.location = G(pos)
        return o


class MB:
    """Mesh builder: world-space (glTF axes) primitives -> one object with N material slots."""

    def __init__(self, scene, name, origin=(0, 0, 0), parent=None):
        self.scene, self.name, self.parent = scene, name, parent
        self.origin = Vector(origin)
        self.bm = bmesh.new()
        self.slots = []

    # -- internals
    def _slot(self, matname):
        if matname not in self.slots:
            self.slots.append(matname)
        return self.slots.index(matname)

    def _M(self, c, rot, scale, P):
        T = Matrix.Translation(Vector(c) - self.origin)
        R = Euler([math.radians(a) for a in rot], "XYZ").to_matrix().to_4x4()
        S = Matrix.Diagonal(Vector((scale[0], scale[1], scale[2], 1.0)))
        return C @ T @ R @ S @ P

    def _tag(self, matname, smooth, existing_f, existing_v=None):
        idx = self._slot(matname)
        new = [f for f in self.bm.faces if f not in existing_f]
        for f in new:
            f.material_index = idx
            f.smooth = smooth
        bmesh.ops.recalc_face_normals(self.bm, faces=new)
        return new

    # -- primitives (all my-space)
    def box(self, c, size, m, rot=(0, 0, 0), smooth=False):
        ex = set(self.bm.faces)
        bmesh.ops.create_cube(self.bm, size=1.0, matrix=self._M(c, rot, size, Matrix.Identity(4)))
        self._tag(m, smooth, ex)

    def sph(self, c, radii, m, rot=(0, 0, 0), seg=(10, 7), axis="y", smooth=True):
        if isinstance(radii, (int, float)):
            radii = (radii, radii, radii)
        ex = set(self.bm.faces)
        bmesh.ops.create_uvsphere(self.bm, u_segments=seg[0], v_segments=seg[1], radius=1.0,
                                  matrix=self._M(c, rot, radii, P_for_axis(axis)))
        self._tag(m, smooth, ex)

    def cyl(self, c, r1, r2, h, m, axis="y", seg=12, rot=(0, 0, 0), scale=(1, 1, 1), smooth=False):
        """r1 at the -axis end, r2 at the +axis end (r2=0 gives a cone)."""
        ex = set(self.bm.faces)
        bmesh.ops.create_cone(self.bm, cap_ends=True, cap_tris=False, segments=seg,
                              radius1=r1, radius2=r2, depth=h,
                              matrix=self._M(c, rot, scale, P_for_axis(axis)))
        self._tag(m, smooth, ex)

    def dome(self, c, radii, cut, m, rot=(0, 0, 0), seg=(12, 8), smooth=True):
        """Upper part of an ellipsoid above local-y fraction `cut` (-1..1), capped flat."""
        ex = set(self.bm.faces)
        exv = set(self.bm.verts)
        bmesh.ops.create_uvsphere(self.bm, u_segments=seg[0], v_segments=seg[1], radius=1.0,
                                  matrix=Matrix.Identity(4))
        newv = [v for v in self.bm.verts if v not in exv]
        newe = [e for e in self.bm.edges if all(v in newv for v in e.verts)]
        newf = [f for f in self.bm.faces if f not in ex]
        bmesh.ops.bisect_plane(self.bm, geom=newv + newe + newf, plane_co=(0, 0, cut),
                               plane_no=(0, 0, 1), clear_inner=True)
        bnd = [e for e in self.bm.edges if e.is_boundary]
        bmesh.ops.holes_fill(self.bm, edges=bnd, sides=0)
        newv = [v for v in self.bm.verts if v not in exv]
        bmesh.ops.transform(self.bm, matrix=self._M(c, rot, radii, P_for_axis("y")), verts=newv)
        self._tag(m, smooth, ex)

    def prism(self, bottom, top, m, smooth=False):
        """Convex prism from two equal-length point loops (my-space)."""
        ex = set(self.bm.faces)
        vb = [self.bm.verts.new(G(Vector(p) - self.origin)) for p in bottom]
        vt = [self.bm.verts.new(G(Vector(p) - self.origin)) for p in top]
        self.bm.faces.new(vb)
        self.bm.faces.new(vt)
        n = len(vb)
        for i in range(n):
            j = (i + 1) % n
            self.bm.faces.new((vb[i], vb[j], vt[j], vt[i]))
        self._tag(m, smooth, ex)

    def beam(self, p0, p1, s0, s1, m, roll=0.0):
        """Tapered square beam from p0 to p1; s0/s1 = (width, thickness) at each end."""
        p0, p1 = Vector(p0), Vector(p1)
        d = (p1 - p0).normalized()
        up = Vector((0, 1, 0)) if abs(d.y) < 0.95 else Vector((1, 0, 0))
        right = d.cross(up).normalized()
        up2 = right.cross(d).normalized()
        if roll:
            q = Matrix.Rotation(math.radians(roll), 3, d)
            right, up2 = q @ right, q @ up2

        def loop(p, s):
            w, t = s[0] / 2, s[1] / 2
            return [p - right * w - up2 * t, p + right * w - up2 * t,
                    p + right * w + up2 * t, p - right * w + up2 * t]
        self.prism(loop(p0, s0), loop(p1, s1), m)

    def poly(self, pts_plan, y0, y1, m, top_scale=1.0, plane="xz"):
        """Extrude a convex plan polygon. plane='xz': points (x,z), extruded y0..y1,
        top scaled about centroid.  plane='zy': points (z,y), extruded in x from -y0..+y0
        (y0 = half width), top_scale narrows the x width at the far side."""
        if plane == "xz":
            cx = sum(p[0] for p in pts_plan) / len(pts_plan)
            cz = sum(p[1] for p in pts_plan) / len(pts_plan)
            b = [(x, y0, z) for x, z in pts_plan]
            t = [(cx + (x - cx) * top_scale, y1, cz + (z - cz) * top_scale) for x, z in pts_plan]
            self.prism(b, t, m)
        else:
            hw, hw2 = y0, y1
            b = [(-hw, y, z) for z, y in pts_plan]
            t = [(hw2, y, z) for z, y in pts_plan]
            self.prism(b, t, m)

    # -- finish
    def build(self):
        me = bpy.data.meshes.new(self.name)
        self.bm.to_mesh(me)
        self.bm.free()
        for s in self.slots:
            me.materials.append(_MATS[s] if s in _MATS else mat(s))
        me.update()
        o = bpy.data.objects.new(self.name, me)
        self.scene.coll.objects.link(o)
        o["_world"] = tuple(self.origin)
        if self.parent is not None:
            o.parent = self.parent
            o.location = G(self.origin - Vector(self.parent["_world"]))
        else:
            o.location = G(self.origin)
        return o


def tri_count(objs):
    n = 0
    for o in objs:
        if o.type == "MESH":
            n += sum(len(p.vertices) - 2 for p in o.data.polygons)
    return n


def export_glb(path, scene_objs=None):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    for o in bpy.data.objects:
        if "_world" in o:
            del o["_world"]  # keep custom props out of the glTF extras
    bpy.ops.export_scene.gltf(
        filepath=path, export_format="GLB", use_selection=False, export_apply=True,
        export_yup=True, export_materials="EXPORT", export_cameras=False,
        export_lights=False, export_extras=False, export_texcoords=False,
        export_normals=True, export_animations=False, export_skins=False,
    )
    print("EXPORTED", path)
