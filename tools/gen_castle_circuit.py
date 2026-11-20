#!/usr/bin/env python3
"""Layout generator for Castle Circuit (story 003). Authoring aid, not run by the game.
Builds the centerline from a rounded polygon, computes the shortcut branches in main-loop
distance, and writes assets/tracks/castle_circuit/castle_circuit.tres and castle_theme.tres.
Re-run after edits:  python tools/gen_castle_circuit.py
"""
import math, os

SPP = 4


def sub(a, b): return (a[0] - b[0], a[1] - b[1])
def add(a, b): return (a[0] + b[0], a[1] + b[1])
def mul(a, k): return (a[0] * k, a[1] * k)
def dot(a, b): return a[0] * b[0] + a[1] * b[1]
def ln(a): return math.hypot(a[0], a[1])


def norm(a):
    l = ln(a)
    return (a[0] / l, a[1] / l)


def rot(a, phi):
    c, s = math.cos(phi), math.sin(phi)
    return (a[0] * c - a[1] * s, a[0] * s + a[1] * c)


# ---- main loop: rounded polygon, heading east on top (x right, z down, clockwise on screen)
verts = []  # (point, fillet radius, tag)
verts.append(((-120, 0), 40, "nw"))
verts.append(((120, 0), 22, "gate"))
d = norm(sub((-120, 330), (120, 0)))
n = (-d[1], d[0])
base = add((120, 0), mul(d, 215))
verts.append((add(add(base, mul(d, -22)), mul(n, 17)), 22, "chic1"))
verts.append((add(add(base, mul(d, 22)), mul(n, -17)), 22, "chic2"))
verts.append(((-120, 330), 50, "sweep"))
verts.append(((-120, 132), 14, "na"))  # drawbridge notch (the moat bay) on the west edge
verts.append(((-168, 132), 14, "nb"))
verts.append(((-168, 62), 14, "nc"))
verts.append(((-120, 62), 14, "nd"))


def build():
    nv = len(verts)
    arcs = {}
    first = []
    for i in range(nv):
        v, r, tag = verts[i]
        a = verts[i - 1][0]
        b = verts[(i + 1) % nv][0]
        d1 = norm(sub(v, a))
        d2 = norm(sub(b, v))
        cr = d1[0] * d2[1] - d1[1] * d2[0]
        theta = math.acos(max(-1, min(1, dot(d1, d2))))
        sign = 1 if cr > 0 else -1
        t = r * math.tan(theta / 2)
        p1 = sub(v, mul(d1, t))
        center = add(p1, mul(rot(d1, sign * math.pi / 2), r))
        m = max(2, int(math.ceil(r * theta / 5.0)))
        pts = []
        for k in range(m + 1):
            dk = rot(d1, sign * theta * k / m)
            pts.append(sub(center, mul(rot(dk, sign * math.pi / 2), r)))
        arcs[tag] = (pts, center, r, theta)
        first.append(pts)
    ctrl = []
    tags = []
    for i in range(nv):
        pts = first[i]
        for j, p in enumerate(pts):
            ctrl.append(p)
            tags.append("arc")
        nxt = first[(i + 1) % nv][0]
        last = pts[-1]
        forced = [(0.0, 0.0)] if verts[i][2] == "nw" else []
        seg = [last] + forced + [nxt]
        for q in range(len(seg) - 1):
            L = ln(sub(seg[q + 1], seg[q]))
            c = max(1, int(math.ceil(L / 6.0)))
            for k in range(1, c):
                ctrl.append(add(seg[q], mul(sub(seg[q + 1], seg[q]), k / c)))
                tags.append("fill")
            if q < len(seg) - 2:
                ctrl.append(seg[q + 1])
                tags.append("line")
    idx = tags.index("line")
    return ctrl[idx:] + ctrl[:idx], arcs


def cr_pt(p0, p1, p2, p3, t):
    t2 = t * t
    t3 = t2 * t
    return tuple(0.5 * ((2 * p1[i]) + (-p0[i] + p2[i]) * t + (2 * p0[i] - 5 * p1[i] + 4 * p2[i] - p3[i]) * t2
                        + (-p0[i] + 3 * p1[i] - 3 * p2[i] + p3[i]) * t3) for i in (0, 1))


ctrl, arcs = build()
N = len(ctrl)
pts = []
for i in range(N):
    for k in range(SPP):
        pts.append(cr_pt(ctrl[(i - 1) % N], ctrl[i], ctrl[(i + 1) % N], ctrl[(i + 2) % N], k / SPP))
cum = [0.0]
for i in range(len(pts)):
    cum.append(cum[-1] + ln(sub(pts[(i + 1) % len(pts)], pts[i])))
LENGTH = cum[-1]


def point_at(s):
    s %= LENGTH
    lo = 0
    for i in range(len(pts)):
        if cum[i] <= s:
            lo = i
        else:
            break
    a = pts[lo]
    b = pts[(lo + 1) % len(pts)]
    f = (s - cum[lo]) / (cum[lo + 1] - cum[lo])
    return (a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f)


def s_of_z_on_west(z):
    for i in range(len(pts)):
        if abs(pts[i][0] + 120) < 0.5 and abs(pts[i][1] - z) < 2.5:
            return cum[i] + (pts[i][1] - z)  # heading north: z decreases along s
    raise SystemExit("no west point at z=%s" % z)


def find_s(p):
    best = (1e9, 0)
    for i in range(len(pts)):
        dd = ln(sub(pts[i], p))
        if dd < best[0]:
            best = (dd, cum[i])
    return best[1]


s_in_b = s_of_z_on_west(170.0)
s_out_b = s_of_z_on_west(42.0)
bridge_ctrl = [(-120, 170), (-117, 150), (-112, 128), (-108, 105), (-110, 80), (-116, 58), (-120, 42)]
sw_pts, sw_c, sw_r, sw_theta = arcs["sweep"]
sa = find_s(sw_pts[0])
sb = find_s(sw_pts[-1])
LEAD = 24.0
s_in_p = sa - LEAD
s_out_p = sb + LEAD
A = point_at(s_in_p)
B = point_at(s_out_p)
ab = sub(B, A)
abn = norm(ab)
nn = (-abn[1], abn[0])
passage_ctrl = [A, add(add(A, mul(ab, 0.30)), mul(nn, 5.5)), add(add(A, mul(ab, 0.68)), mul(nn, -5.5)), B]


def branch_len(c):
    n_ = len(c)
    out = []
    for i in range(n_ - 1):
        p0 = c[i - 1] if i > 0 else (2 * c[0][0] - c[1][0], 2 * c[0][1] - c[1][1])
        p3 = c[i + 2] if i + 2 < n_ else (2 * c[-1][0] - c[-2][0], 2 * c[-1][1] - c[-2][1])
        for k in range(12):
            out.append(cr_pt(p0, c[i], c[i + 1], p3, k / 12))
    out.append(c[-1])
    return sum(ln(sub(out[i + 1], out[i])) for i in range(len(out) - 1))


Lb = branch_len(bridge_ctrl)
Lp = branch_len(passage_ctrl)
print("main length %.1f, control points %d" % (LENGTH, N))
print("bridge s %.1f..%.1f (main %.1f m) branch %.1f m ratio %.2f saves %.1f m" % (s_in_b, s_out_b, s_out_b - s_in_b, Lb, (s_out_b - s_in_b) / Lb, s_out_b - s_in_b - Lb))
print("passage s %.1f..%.1f (main %.1f m) branch %.1f m ratio %.2f saves %.1f m" % (s_in_p, s_out_p, s_out_p - s_in_p, Lp, (s_out_p - s_in_p) / Lp, s_out_p - s_in_p - Lp))

# ---- scenery data
mid = sw_pts[len(sw_pts) // 2]
u = norm(sub(sw_c, mid))
keep = add(sw_c, mul(u, 46))
towers = [add(keep, (24 * math.cos(k * math.pi / 3), 24 * math.sin(k * math.pi / 3))) for k in range(6)]
gp, gc, gr, gth = arcs["gate"]
gate_towers = []
for k in (len(gp) // 3, 2 * len(gp) // 3):
    o = norm(sub(gp[k], gc))
    gate_towers.append(add(gp[k], mul(o, 13.5)))
cv = [v[0] for v in verts if v[2] in ("chic1", "chic2")]
cc = mul(add(cv[0], cv[1]), 0.5)
houses = []
for off in (-24, 0, 24):
    for side in (-1, 1):
        houses.append(add(add(cc, mul(d, off)), mul(n, side * 30)))
spots = [(LENGTH * (k + 0.5) / 8.0, [-4.0, 0.0, 4.0, 0.0][k % 4]) for k in range(8)]
print("keep at", keep)


def v2(lst):
    return "PackedVector2Array(" + ", ".join("%.2f, %.2f" % (p[0], p[1]) for p in lst) + ")"


PASSAGE_WALL_DRAG = float(os.environ.get("PASSAGE_WALL_DRAG", "3.0"))  # rough stone grinds a sliding kart
out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "tracks", "castle_circuit")
os.makedirs(out, exist_ok=True)
TRES = """[gd_resource type="Resource" script_class="TrackData" load_steps=6 format=3]

[ext_resource type="Script" path="res://src/test_track/track_data.gd" id="1_data"]
[ext_resource type="Script" path="res://src/track/track_branch.gd" id="2_branch"]
[ext_resource type="Resource" path="res://assets/tracks/castle_circuit/castle_theme.tres" id="3_theme"]

[sub_resource type="Resource" id="Branch_bridge"]
script = ExtResource("2_branch")
id = &"drawbridge"
type = &"drawbridge"
control_points = %s
half_width = 2.2
curb_width = 0.3
s_in = %.2f
s_out = %.2f
samples_per_segment = 12
deck_color = Color(0.55, 0.36, 0.2, 1)
deck_alt_color = Color(0.46, 0.29, 0.16, 1)
wall_color = Color(0.4, 0.26, 0.14, 1)
wall_alt_color = Color(0.5, 0.33, 0.18, 1)
wall_height = 0.6
fill_color = Color(0.2, 0.45, 0.78, 1)

[sub_resource type="Resource" id="Branch_passage"]
script = ExtResource("2_branch")
id = &"secret_passage"
type = &"secret_passage"
control_points = %s
half_width = 2.6
curb_width = 0.5
wall_drag_mult = PASSAGE_WALL_DRAG
s_in = %.2f
s_out = %.2f
samples_per_segment = 12
deck_color = Color(0.5, 0.48, 0.45, 1)
deck_alt_color = Color(0.45, 0.43, 0.4, 1)
wall_color = Color(0.58, 0.58, 0.6, 1)
wall_alt_color = Color(0.5, 0.5, 0.53, 1)
wall_height = 2.6
fill_color = Color(0, 0, 0, 0)
arch_ends = true

[resource]
script = ExtResource("1_data")
track_id = &"castle_circuit"
display_name = "Castle Circuit"
theme = ExtResource("3_theme")
branches = Array[ExtResource("2_branch")]([SubResource("Branch_bridge"), SubResource("Branch_passage")])
checkpoint_count = 8
item_box_spots = %s
control_points = %s
samples_per_segment = %d
road_half_width = 9.0
curb_width = 1.2
lap_count = 3
start_distance_behind_line = 6.0
query_window = 24
"""
with open(os.path.join(out, "castle_circuit.tres"), "w", newline="\n") as f:
    f.write((TRES % (v2(bridge_ctrl), s_in_b, s_out_b, v2(passage_ctrl), s_in_p, s_out_p, v2(spots), v2(ctrl), SPP))
            .replace("PASSAGE_WALL_DRAG", "%g" % PASSAGE_WALL_DRAG))
THEME = """[gd_resource type="Resource" script_class="TrackTheme" load_steps=2 format=3]

[ext_resource type="Script" path="res://src/track/track_theme.gd" id="1_theme"]

[resource]
script = ExtResource("1_theme")
style = &"castle"
ground_color = Color(0.3, 0.52, 0.24, 1)
ground_size = 1100.0
road_color = Color(0.4, 0.37, 0.33, 1)
curb_color_a = Color(0.9, 0.38, 0.15, 1)
curb_color_b = Color(0.95, 0.9, 0.74, 1)
wall_color_a = Color(0.62, 0.62, 0.65, 1)
wall_color_b = Color(0.5, 0.5, 0.54, 1)
wall_height = 1.1
merlon_height = 0.9
wall_thickness = 0.7
wall_stripe_segments = 1
ambient_energy = 0.55
keep_center = Vector2(%.2f, %.2f)
tower_positions = %s
gate_tower_positions = %s
house_positions = %s
"""
with open(os.path.join(out, "castle_theme.tres"), "w", newline="\n") as f:
    f.write(THEME % (keep[0], keep[1], v2(towers), v2(gate_towers), v2(houses)))
print("wrote")
