"""Preview renders for story 006 (Workbench, flat colours).
Regenerate:  blender --background --python tools/blender/render_previews.py
Reads the exported .glb files (so it also proves they import) and writes PNGs to
production/qa/evidence/story-006-racers/models/.
"""
import math
import os
import sys

import bpy
import numpy as np
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common as cm  # noqa: E402

SLUGS = ["mascot", "sunny", "bolt", "fern", "violet", "frost", "cinder", "skye"]
VEHS = ["cart_armored", "bike_war"]
OUT = cm.EVID_DIR
TMP = os.path.join(OUT, "_tiles")


def fresh(bg=(0.93, 0.89, 0.80)):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_WORKBENCH"
    sc.view_settings.view_transform = "Standard"
    sc.display.render_aa = "8"
    w = bpy.data.worlds.new("w")
    w.color = bg
    sc.world = w
    sh = sc.display.shading
    sh.light = "STUDIO"
    sh.color_type = "MATERIAL"
    sh.show_object_outline = True
    sh.object_outline_color = (0.165, 0.118, 0.149)
    sh.show_specular_highlight = False
    sc.render.film_transparent = False
    return sc


def silhouette_mode(sc):
    sh = sc.display.shading
    sh.light = "FLAT"
    sh.color_type = "SINGLE"
    sh.single_color = (0.22, 0.22, 0.24)
    sh.show_object_outline = False
    sc.world.color = (1, 1, 1)
    sc.display.render_aa = "OFF"


def load(path):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    new = [o for o in bpy.data.objects if o not in before]
    roots = [o for o in new if o.parent is None and o.type == "EMPTY"]
    for o in new:
        if o.type == "MESH":
            for m in o.data.materials:
                bsdf = m.node_tree.nodes.get("Principled BSDF") if m and m.node_tree else None
                if bsdf:
                    m.diffuse_color = bsdf.inputs["Base Color"].default_value
    return roots[0], new


def find(objs, name):
    for o in objs:
        if o.name == name or o.name.startswith(name + "."):
            return o
    return None


def camera(sc, target, dist, az, el, lens=45, ortho=None):
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    sc.collection.objects.link(cam)
    cam.data.lens = lens
    cam.data.clip_end = 200
    a, e = math.radians(az), math.radians(el)
    # az 0 = camera in front of the model (+Y blender), 180 = behind, 90 = model's left (+X?)
    d = Vector((math.sin(a) * math.cos(e), math.cos(a) * math.cos(e), math.sin(e)))
    t = Vector(target)
    cam.location = t + d * dist
    cam.rotation_euler = (t - cam.location).to_track_quat("-Z", "Y").to_euler()
    if ortho:
        cam.data.type = "ORTHO"
        cam.data.ortho_scale = ortho
    sc.camera = cam
    return cam


def label(sc, cam, text, size=0.075):
    cu = bpy.data.curves.new("t", "FONT")
    cu.body = text
    cu.size = size
    cu.align_x = "CENTER"
    o = bpy.data.objects.new("lbl", cu)
    sc.collection.objects.link(o)
    o.parent = cam
    o.location = (0, -0.34, -1.4)  # lower part of the frame
    cm.clear_mats()
    o.data.materials.append(cm.mat("dark"))
    o.visible_shadow = False


def render(sc, path, w, h):
    sc.render.resolution_x, sc.render.resolution_y = w, h
    sc.render.resolution_percentage = 100
    sc.render.image_settings.file_format = "PNG"
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)


def seat_of(objs):
    return find(objs, "Seat").matrix_world.translation.copy()


def place(dog_root, seat):
    dog_root.location = seat


def view_model(path, out, az=35, el=22, dist=None, target=None, size=(640, 520), text=None,
               silh=False, res=None, lens=45):
    sc = fresh()
    if silh:
        silhouette_mode(sc)
    root, objs = load(path)
    tgt = target or (0, 0, 0.7)
    cam = camera(sc, tgt, dist or 6.0, az, el, lens=lens)
    if text and not silh:
        label(sc, cam, text)
    render(sc, out, *(res or size))


def combo(slug, veh, out, az=180, el=25, silh=False, res=(480, 400), text=None, dist=6.2):
    sc = fresh()
    if silh:
        silhouette_mode(sc)
    vroot, vobjs = load(os.path.join(cm.VEH_DIR, f"veh_{veh}.glb"))
    droot, dobjs = load(os.path.join(cm.CHAR_DIR, f"char_dog_{slug}.glb"))
    droot.location = seat_of(vobjs)
    bpy.context.view_layer.update()
    cam = camera(sc, (0, 0, 0.95), dist, az, el, lens=45)
    if text and not silh:
        label(sc, cam, text)
    render(sc, out, *res)


def tile_sheet(paths, cols, out, scale=1):
    imgs = []
    for p in paths:
        im = bpy.data.images.load(p)
        w, h = im.size
        a = np.array(im.pixels[:], dtype=np.float32).reshape(h, w, 4)
        imgs.append(a)
    h, w = imgs[0].shape[:2]
    rows = (len(imgs) + cols - 1) // cols
    sheet = np.ones((rows * h, cols * w, 4), dtype=np.float32)
    for i, a in enumerate(imgs):
        r, c = divmod(i, cols)
        # image rows are bottom-up; place row 0 at the top
        y0 = (rows - 1 - r) * h
        sheet[y0:y0 + h, c * w:(c + 1) * w] = a
    if scale > 1:
        sheet = np.repeat(np.repeat(sheet, scale, axis=0), scale, axis=1)
    img = bpy.data.images.new("sheet", sheet.shape[1], sheet.shape[0], alpha=True)
    img.pixels = sheet.ravel().tolist()
    img.filepath_raw = out
    img.file_format = "PNG"
    img.save()


def main():
    os.makedirs(TMP, exist_ok=True)
    # 1. 3/4 view per model
    for v in VEHS:
        view_model(os.path.join(cm.VEH_DIR, f"veh_{v}.glb"), os.path.join(OUT, f"veh_{v}_front34.png"),
                   az=35, el=22, dist=6.5, target=(0, 0, 0.6), text=f"veh_{v}")
        view_model(os.path.join(cm.VEH_DIR, f"veh_{v}.glb"), os.path.join(OUT, f"veh_{v}_rear34.png"),
                   az=145, el=25, dist=6.5, target=(0, 0, 0.6), text=f"veh_{v} (rear)")
    for s in SLUGS:
        view_model(os.path.join(cm.CHAR_DIR, f"char_dog_{s}.glb"), os.path.join(OUT, f"char_dog_{s}_front34.png"),
                   az=30, el=12, dist=4.2, target=(0, 0, 0.65), size=(520, 520), text=f"char_dog_{s}",
                   lens=50)
    # 2. chase-camera view of each dog on each vehicle
    for v in VEHS:
        tiles = []
        for s in SLUGS:
            p = os.path.join(TMP, f"chase_{v}_{s}.png")
            combo(s, v, p, text=f"{s} / {v}")
            tiles.append(p)
        tile_sheet(tiles, 4, os.path.join(OUT, f"chase_{v}_all_dogs.png"))
    # 3. line-up
    sc = fresh()
    for i, s in enumerate(SLUGS):
        r, _ = load(os.path.join(cm.CHAR_DIR, f"char_dog_{s}.glb"))
        r.location = ((i - 3.5) * 1.15, 0, 0)
    camera(sc, (0, 0, 0.8), 14.0, 0, 6, lens=50)
    render(sc, os.path.join(OUT, "dog_lineup.png"), 1800, 520)
    # 4. 64 px silhouette sheet (grey, flat)
    sil = []
    k = 0

    def sp():
        nonlocal k
        k += 1
        return os.path.join(TMP, f"sil_{k:02d}.png")
    for v in VEHS:
        for az, el in ((180, 25), (90, 5), (0, 25)):
            p = sp()
            view_model(os.path.join(cm.VEH_DIR, f"veh_{v}.glb"), p, az=az, el=el, dist=6.5,
                       target=(0, 0, 0.6), silh=True, res=(64, 64))
            sil.append(p)
    # pad row 1 to 8 columns with the dog-on-vehicle references
    for v in VEHS:
        p = sp()
        combo("mascot", v, p, silh=True, res=(64, 64), dist=6.5)
        sil.append(p)
    for s in SLUGS:  # dogs on the cart, chase cam
        p = sp()
        combo(s, "cart_armored", p, silh=True, res=(64, 64), dist=6.5)
        sil.append(p)
    for s in SLUGS:  # dogs on the bike, chase cam
        p = sp()
        combo(s, "bike_war", p, silh=True, res=(64, 64), dist=6.5)
        sil.append(p)
    for s in SLUGS:  # dogs alone, front, ~ same scale as in-race
        p = sp()
        view_model(os.path.join(cm.CHAR_DIR, f"char_dog_{s}.glb"), p, az=0, el=8, dist=3.6,
                   target=(0, 0, 0.6), silh=True, res=(64, 64))
        sil.append(p)
    tile_sheet(sil, 8, os.path.join(OUT, "silhouettes_64px.png"))
    tile_sheet(sil, 8, os.path.join(OUT, "silhouettes_64px_x4.png"), scale=4)
    for f in os.listdir(TMP):
        os.remove(os.path.join(TMP, f))
    os.rmdir(TMP)


if __name__ == "__main__":
    main()
