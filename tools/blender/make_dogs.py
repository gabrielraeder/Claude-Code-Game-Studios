"""The eight knight-dog racers (story 006).
Regenerate:  blender --background --python tools/blender/make_dogs.py
Writes assets/characters/char_dog_<slug>.glb (8 files).

Dog space (glTF axes): origin = hip/seat point, faces -z, +y up.  Head is an Empty
at the neck; HeadMesh/Helmet/Ear_L/Ear_R are its children.  Ear_L is the dog's
left = -x (the dog faces -z, so its right hand is +x).
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common as cm  # noqa: E402
from mathutils import Euler, Vector  # noqa: E402

V = Vector
HEAD_C = V((0, 0.86, -0.02))     # head centre
NECK = V((0, 0.60, -0.02))       # Head empty (pivot for bob / tilt)

# ---- per-dog data -----------------------------------------------------------
# mw/mh = muzzle half width/height, L = muzzle length, nose = nose radius
DOGS = {
    "mascot": dict(fur="#E0602F", fur2="#FFF6E6", armor="#7D838D", tabard="#E8452C", eye="#F2C41F",
                   head=(0.27, 0.25, 0.26), L=0.22, mw=0.10, mh=0.09, nose=0.05, cheeks=True,
                   ears="point", helm="knight", tail="bushy", emblem="trim"),
    "sunny": dict(fur="#E2A94B", fur2="#F6DFA6", armor="#7D838D", tabard="#F2C14E", eye=None,
                  head=(0.27, 0.25, 0.26), L=0.26, mw=0.105, mh=0.09, nose=0.055, cheeks=False,
                  ears="floppy", helm="kettle", tail="plume", emblem="trim"),
    "bolt": dict(fur="#3A3036", fur2="#C27A3F", armor="#5C6068", tabard="#2F6FDB", eye=None,
                 head=(0.25, 0.25, 0.27), L=0.34, mw=0.085, mh=0.075, nose=0.05, cheeks=False,
                 ears="tall", helm="horned", tail="thin", emblem="trim"),
    "fern": dict(fur="#E39A4A", fur2="#FFF1DC", armor="#7D838D", tabard="#1FA37A", eye=None,
                 head=(0.28, 0.25, 0.25), L=0.18, mw=0.10, mh=0.085, nose=0.05, cheeks=True,
                 ears="round", helm="hood", tail="nub", emblem="trim"),
    "violet": dict(fur="#B9B4C4", fur2="#DAD6E3", armor="#8E94A0", tabard="#8E44C9", eye=None,
                   head=(0.25, 0.25, 0.26), L=0.30, mw=0.08, mh=0.075, nose=0.045, cheeks=False,
                   ears="tuft", helm="plumed", tail="pom", emblem="trim"),
    "frost": dict(fur="#F4F6F8", fur2="#D5E0EB", armor="#A9B8C9", tabard="#F2F2F2", eye=None,
                  head=(0.28, 0.25, 0.26), L=0.20, mw=0.10, mh=0.085, nose=0.05, cheeks=True,
                  ears="smallround", helm="crown", tail="bushy", emblem="armor"),
    "cinder": dict(fur="#3A3F4B", fur2="#6B7180", armor="#7D838D", tabard="#3A3F4B", eye=None,
                   head=(0.30, 0.25, 0.26), L=0.18, mw=0.15, mh=0.09, nose=0.06, cheeks=False,
                   ears="bat", helm="flat", tail="nub", emblem="trim"),
    "skye": dict(fur="#8B4A2B", fur2="#C4814F", armor="#7D838D", tabard="#7CC4F5", eye=None,
                 head=(0.24, 0.24, 0.25), L=0.42, mw=0.075, mh=0.07, nose=0.045, cheeks=False,
                 ears="long", helm="feather", tail="thin", emblem="trim"),
}


def limb(mb, base, rx, rz, h, r1, r2, m, scale=(1, 1, 1), seg=8):
    """Cone/cylinder starting at `base`, pointing along +y rotated by (rx, rz) degrees.
    Returns the tip position so chains can be built."""
    d = Euler((math.radians(rx), 0, math.radians(rz)), "XYZ").to_matrix() @ V((0, 1, 0))
    mb.cyl(base + d * h / 2, r1, r2, h, m, axis="y", seg=seg, rot=(rx, 0, rz), scale=scale)
    return base + d * h


def merid(c, rot_x, radii, phi):
    """Point on the x=0 meridian of an ellipsoid dome tilted by rot_x; phi from the top, + toward back."""
    p = V((0, radii[1] * math.cos(math.radians(phi)), radii[2] * math.sin(math.radians(phi))))
    return c + Euler((math.radians(rot_x), 0, 0), "XYZ").to_matrix() @ p


def ridge(mb, c, rot_x, radii, phis, w, t, m, push=1.0):
    pts = [merid(c, rot_x, tuple(r * push for r in radii), p) for p in phis]
    for a, b in zip(pts, pts[1:]):
        mb.beam(a, b, (w, t), (w, t), m)


# ---- ears (origin = ear base) ------------------------------------------------
def ear(sc, head, s, cfg):
    kind = cfg["ears"]
    name = "Ear_L" if s < 0 else "Ear_R"
    if kind == "point":
        base = V((s * 0.18, 1.02, -0.02))
    elif kind == "tall":
        base = V((s * 0.12, 1.04, 0.0))
    elif kind in ("floppy", "long"):
        base = V((s * 0.24, 0.98, 0.0))
    elif kind == "round":
        base = V((s * 0.23, 1.04, 0.0))
    elif kind == "bat":
        base = V((s * 0.21, 1.06, 0.0))
    elif kind == "tuft":
        base = V((s * 0.26, 0.97, 0.0))
    else:  # smallround
        base = V((s * 0.235, 1.03, 0.02))
    mb = cm.MB(sc, name, origin=base, parent=head)
    if kind == "point":
        limb(mb, base, 0, -s * 16, 0.52, 0.13, 0.0, "fur", scale=(1, 1, 0.6))
        limb(mb, base + V((0, 0.0, -0.035)), 0, -s * 16, 0.42, 0.085, 0.0, "fur2", scale=(1, 1, 0.5))
    elif kind == "tall":
        limb(mb, base, 0, -s * 7, 0.56, 0.095, 0.0, "fur", scale=(1, 1, 0.55), seg=6)
        limb(mb, base + V((0, 0, -0.03)), 0, -s * 7, 0.42, 0.055, 0.0, "fur2", scale=(1, 1, 0.5), seg=6)
    elif kind == "floppy":
        mb.sph(base + V((s * 0.06, -0.16, 0)), (0.085, 0.21, 0.13), "fur", rot=(0, 0, s * 14), seg=(8, 6))
        mb.sph(base + V((s * 0.095, -0.30, 0)), (0.07, 0.10, 0.11), "fur2", rot=(0, 0, s * 14), seg=(8, 5))
    elif kind == "long":
        mb.sph(base + V((s * 0.07, -0.25, 0.0)), (0.075, 0.28, 0.12), "fur", rot=(0, 0, s * 7), seg=(8, 7))
        mb.sph(base + V((s * 0.09, -0.46, 0.0)), (0.065, 0.10, 0.10), "fur2", rot=(0, 0, s * 7), seg=(8, 5))
    elif kind == "round":
        mb.sph(base + V((s * 0.07, 0.20, 0)), (0.19, 0.23, 0.06), "fur", rot=(0, 0, -s * 14), seg=(10, 7))
        mb.sph(base + V((s * 0.07, 0.19, -0.045)), (0.13, 0.16, 0.04), "fur2", rot=(0, 0, -s * 14), seg=(8, 6))
    elif kind == "bat":
        tip = limb(mb, base, 0, -s * 22, 0.42, 0.18, 0.09, "fur", scale=(1, 1, 0.38), seg=8)
        mb.sph(tip, (0.09, 0.07, 0.035), "fur", rot=(0, 0, -s * 22), seg=(8, 4))
        limb(mb, base + V((0, 0, -0.025)), 0, -s * 22, 0.32, 0.12, 0.05, "fur2", scale=(1, 1, 0.3), seg=8)
    elif kind == "tuft":
        mb.sph(base + V((s * 0.02, 0.0, 0)), 0.14, "fur", seg=(7, 5))
        mb.sph(base + V((s * 0.04, -0.17, 0)), 0.115, "fur2", seg=(7, 5))
    else:  # smallround
        mb.sph(base + V((s * 0.02, 0.05, 0)), (0.105, 0.115, 0.06), "fur", seg=(8, 5))
        mb.sph(base + V((s * 0.02, 0.05, -0.035)), (0.065, 0.075, 0.03), "fur2", seg=(6, 4))
    return mb.build()


# ---- helmets (origin = neck) --------------------------------------------------
def helmet(sc, head, cfg):
    kind = cfg["helm"]
    mb = cm.MB(sc, "Helmet", origin=NECK, parent=head)
    if kind == "knight":      # rounded knight's helmet, visor flipped up (logo style)
        c, rx, r = V((0, 0.97, 0.02)), 18, (0.315, 0.31, 0.325)
        mb.dome(c, r, -0.12, "armor", rot=(rx, 0, 0))
        ridge(mb, c, rx, r, [-62, -30, 0, 30, 62], 0.075, 0.09, "tabard", push=1.0)
        mb.box(V((0, 1.20, -0.215)), (0.27, 0.045, 0.12), "armor", rot=(-38, 0, 0))   # raised visor
        mb.box(V((0, 1.135, -0.265)), (0.27, 0.05, 0.05), "trim")                   # hinge / brow band
    elif kind == "kettle":    # wide-brim kettle hat
        mb.cyl(V((0, 1.015, 0)), 0.50, 0.50, 0.05, "armor", axis="y", seg=16, rot=(-4, 0, 0))
        mb.dome(V((0, 1.03, 0.0)), (0.30, 0.28, 0.30), 0.0, "armor", rot=(-4, 0, 0))
        mb.cyl(V((0, 1.06, 0)), 0.30, 0.30, 0.06, "tabard", axis="y", seg=16)
    elif kind == "horned":    # horned helm
        c, rx, r = V((0, 0.97, 0.03)), 16, (0.285, 0.27, 0.30)
        mb.dome(c, r, -0.10, "armor", rot=(rx, 0, 0))
        mb.box(V((0, 1.02, -0.27)), (0.07, 0.19, 0.06), "armor", rot=(10, 0, 0))     # nasal bar
        for s in (-1, 1):
            tip = limb(mb, V((s * 0.24, 1.02, 0.03)), 0, -s * 60, 0.22, 0.075, 0.055, "trim", seg=8)
            limb(mb, tip, 0, -s * 15, 0.26, 0.055, 0.0, "trim", seg=8)
    elif kind == "hood":      # cloth hood + chain-mail band
        c, rx, r = V((0, 0.94, 0.03)), 10, (0.32, 0.31, 0.33)
        mb.dome(c, r, -0.20, "tabard", rot=(rx, 0, 0))
        mb.cyl(V((0, 1.02, 0.0)), 0.29, 0.29, 0.07, "armor", axis="y", seg=14, rot=(10, 0, 0))
        mb.sph(V((0, 0.76, 0.27)), (0.22, 0.24, 0.15), "tabard", seg=(10, 6))         # hood drape
    elif kind == "plumed":    # small plumed helm on a head puff
        mb.sph(V((0, 1.12, 0.0)), (0.25, 0.20, 0.25), "fur", seg=(9, 6))              # head puff
        mb.dome(V((0, 1.20, 0.0)), (0.205, 0.15, 0.205), -0.1, "armor", rot=(8, 0, 0))
        mb.cyl(V((0, 1.20, 0.0)), 0.215, 0.215, 0.04, "trim", axis="y", seg=12, rot=(8, 0, 0))
        tip = limb(mb, V((0, 1.30, 0.03)), 10, 0, 0.36, 0.10, 0.09, "tabard", scale=(0.9, 1, 1), seg=8)
        tip = limb(mb, tip, 30, 0, 0.36, 0.09, 0.05, "tabard", scale=(0.9, 1, 1), seg=8)
        mb.sph(tip + V((0, 0.03, 0.04)), (0.045, 0.07, 0.08), "tabard", seg=(8, 5))
    elif kind == "crown":     # crown-helm
        mb.cyl(V((0, 1.02, 0.0)), 0.245, 0.265, 0.09, "armor", axis="y", seg=14)
        for i in range(6):
            a = math.radians(i * 60)
            p = V((math.sin(a) * 0.255, 1.065, -math.cos(a) * 0.255))
            tip = limb(mb, p, 0, 0, 0.27, 0.06, 0.03, "armor", seg=6)
            mb.sph(tip, 0.045, "tabard", seg=(6, 4))
        mb.cyl(V((0, 1.0, 0.0)), 0.25, 0.27, 0.035, "trim", axis="y", seg=14)
    elif kind == "flat":      # flat-topped bucket helm
        mb.cyl(V((0, 1.075, 0.0)), 0.315, 0.305, 0.20, "armor", axis="y", seg=14, scale=(1.0, 1, 0.92))
        mb.cyl(V((0, 0.985, -0.005)), 0.325, 0.325, 0.035, "trim", axis="y", seg=14, scale=(1.0, 1, 0.92))
        mb.box(V((0, 1.20, -0.02)), (0.40, 0.035, 0.16), "tabard")
    elif kind == "feather":   # rounded helm + feather
        c, rx, r = V((0, 0.965, 0.02)), 16, (0.29, 0.28, 0.30)
        mb.dome(c, r, -0.12, "armor", rot=(rx, 0, 0))
        mb.box(V((0, 1.10, -0.255)), (0.28, 0.06, 0.07), "trim")
        mb.sph(V((0.12, 1.20, 0.08)), 0.055, "trim", seg=(8, 5))
        f0 = V((0.12, 1.22, 0.08))
        limb(mb, f0, 24, -10, 0.55, 0.10, 0.0, "tabard", scale=(0.4, 1, 1), seg=8)
        limb(mb, f0 + V((0.01, 0.02, 0.0)), 40, -18, 0.40, 0.075, 0.0, "tabard", scale=(0.4, 1, 1), seg=8)
    return mb.build()


# ---- tail ---------------------------------------------------------------------
def tail(sc, root, cfg):
    base = V((0, 0.10, 0.27))
    mb = cm.MB(sc, "Tail", origin=base, parent=root)
    k = cfg["tail"]
    if k == "bushy":
        mb.sph(base + V((0, 0.17, 0.17)), (0.12, 0.19, 0.14), "fur", rot=(-30, 0, 0), seg=(8, 6))
        mb.sph(base + V((0, 0.27, 0.22)), (0.085, 0.10, 0.09), "fur2", rot=(-30, 0, 0), seg=(8, 5))
    elif k == "plume":
        mb.sph(base + V((0, 0.12, 0.2)), (0.07, 0.22, 0.08), "fur", rot=(-50, 0, 0), seg=(8, 6))
        mb.sph(base + V((0, 0.20, 0.30)), (0.06, 0.12, 0.07), "fur2", rot=(-50, 0, 0), seg=(8, 5))
    elif k == "thin":
        limb(mb, base, 55, 0, 0.42, 0.06, 0.02, "fur", seg=6)
    elif k == "pom":
        limb(mb, base, 45, 0, 0.18, 0.05, 0.04, "fur", seg=6)
        mb.sph(base + V((0, 0.17, 0.2)), 0.12, "fur2", seg=(8, 6))
    else:  # nub
        mb.sph(base + V((0, 0.05, 0.08)), 0.08, "fur", seg=(8, 5))
    return mb.build()


def make_dog(slug):
    cfg = DOGS[slug]
    cm.reset_scene()
    cm.clear_mats()
    cm.mat("fur", cfg["fur"])
    cm.mat("fur2", cfg["fur2"])
    cm.mat("armor", cfg["armor"])
    cm.mat("tabard", cfg["tabard"])
    cm.mat("eye", cfg["eye"] or "#F6EBD0")
    cm.mat("trim", "#F6EBD0")
    cm.mat("dark", "#2A1E26")
    sc = cm.Scene()
    root = sc.empty("Dog")

    # ---- body (hip origin, torso, arms, paws, pauldrons, gorget)
    b = cm.MB(sc, "Body", parent=root)
    b.sph(V((0, 0.28, 0.0)), (0.31, 0.34, 0.28), "tabard", seg=(10, 7))
    for s in (-1, 1):
        b.sph(V((s * 0.20, 0.0, -0.02)), (0.17, 0.17, 0.20), "fur", seg=(7, 4))          # haunches
        b.beam(V((s * 0.27, 0.46, -0.05)), V((s * 0.22, 0.25, -0.50)), (0.13, 0.13), (0.12, 0.12), "fur")
        b.sph(V((s * 0.22, 0.22, -0.55)), (0.10, 0.09, 0.11), "fur2", seg=(6, 4))        # mitten paw
        b.sph(V((s * 0.30, 0.52, -0.03)), 0.115, "armor", seg=(6, 4))                    # pauldron
    emb = "trim" if cfg["emblem"] == "trim" else "armor"
    b.cyl(V((0, 0.36, -0.262)), 0.095, 0.095, 0.05, emb, axis="z", seg=10)               # chest emblem
    b.cyl(V((0, 0.585, -0.02)), 0.25, 0.22, 0.11, "armor", axis="y", seg=10)             # gorget
    b.build()
    tail(sc, root, cfg)

    # ---- head
    head = sc.empty("Head", NECK, root)
    hx, hy, hz = cfg["head"]
    h = cm.MB(sc, "HeadMesh", origin=NECK, parent=head)
    h.sph(HEAD_C, (hx, hy, hz), "fur", seg=(12, 8))
    L, mw, mh = cfg["L"], cfg["mw"], cfg["mh"]
    mz = -0.12 - L / 2
    h.sph(V((0, 0.80, mz)), (mw, mh, L / 2), "fur2", seg=(8, 6))                        # muzzle
    h.sph(V((0, 0.835, -0.12 - L + 0.015)), (cfg["nose"] * 1.2, cfg["nose"], cfg["nose"]), "dark", seg=(6, 4))
    if cfg["cheeks"]:
        for s in (-1, 1):
            h.sph(V((s * 0.15, 0.79, -0.15)), (0.115, 0.10, 0.10), "fur2", seg=(6, 4))
    for s in (-1, 1):                                                                  # big eyes with highlights
        e = V((s * 0.115, 0.905, -0.235))
        h.sph(e, (0.078, 0.088, 0.045), "eye", seg=(8, 5))
        h.sph(e + V((-s * 0.004, -0.004, -0.028)), (0.047, 0.058, 0.022), "dark", seg=(7, 4))
        h.sph(e + V((-s * 0.022, 0.026, -0.044)), (0.02, 0.022, 0.012), "trim", seg=(5, 3))
    h.build()
    helmet(sc, head, cfg)
    ear(sc, head, -1, cfg)
    ear(sc, head, 1, cfg)

    path = os.path.join(cm.CHAR_DIR, f"char_dog_{slug}.glb")
    import bpy
    print("TRIS", slug, cm.tri_count(list(bpy.data.objects)))
    cm.export_glb(path)


if __name__ == "__main__":
    only = [a for a in sys.argv[sys.argv.index("--") + 1:]] if "--" in sys.argv else list(DOGS)
    for slug in only:
        make_dog(slug)
