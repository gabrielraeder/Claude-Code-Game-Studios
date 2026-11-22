#!/usr/bin/env python3
"""Layout generator for Dungeon Depths (story 003, round 3). Authoring aid, not run by the game.

Sibling of tools/gen_castle_circuit.py (its turtle/closure/width/spline/fillet helpers are COPIED
below, not shared: they are script-level code over globals, so a common module was not cheap).
The loop is a turtle path following design/references/track-design-reference.md section 7:
five zones (Cellar Vaults, Torch Gallery, Great Cavern, Mine Works, Lava Forge), about 15 corners.
Branches: hall_left / hall_right (3-lane pillar hall, the main road is the middle lane),
mine_rail (straight through the crusher switchback, rough sleepers), lava_gap (corner cut with a
speed-gated lava strip). Writes assets/tracks/dungeon_depths/{dungeon_depths,dungeon_theme}.tres.

Re-run after edits:  python tools/gen_dungeon_depths.py   (PLOT=path.png draws a top view, NOWRITE=1)
Heading convention: 0 = +x, positive angles turn toward +z (a right turn for the driver).
Side convention: +1 is TrackModel's normal (-t.y, t.x), the inside of a right turn.
"""
import math, os
import elevation_profile as ev

SPP = 4
CP_STEP = 5.0
STEP = 0.25
WIDTH_SLOPE = 0.3
CURB = 0.9             # main curb width (wall = half width + curb); the lit rim stripe
LINE_SHIFT = 9.0

SINK_TIME = 1.0
RESPAWN_SPEED_FRAC = 30.0 / 115.0
RESPAWN_IMMUNITY = 3.0
RESPAWN_BACK_OFF = 4.0
OPEN_EDGE_REACH = 6.0
PAD_BOOST_TIME = 0.8   # dungeon pads: shorter than Castle's, so a pad is worth ~0.5 s
MINE_DRAG = float(os.environ.get("MINE_DRAG", "1.25"))        # TrackBranch.floor_drag_mult of the rail
GAP_SPEED = float(os.environ.get("GAP_SPEED", "24.0"))       # m/s needed to cross the lava gap: 0.92 x max_speed 26 (boost 35.1); a slow or crashed kart sinks
GAP_LEN = 7.0
# Story 008 part 4: the lava gap is a real jump. A low ramp ends GAP_RUNOFF meters before the strip;
# its launch is flat enough that only a kart at about the old gate speed (GAP_SPEED) carries over the
# strip; a slower one lands in the lava (the hazard still sinks any grounded kart slower than
# GAP_SPEED), a faster or boosting one clears it.
GAP_RAMP_LEN = float(os.environ.get("GAP_RAMP_LEN", "6.0"))
GAP_RAMP_LIP = float(os.environ.get("GAP_RAMP_LIP", "0.6"))
GAP_RUNOFF = float(os.environ.get("GAP_RUNOFF", "2.0"))


def S(length, hw, zone, **kw):
    return dict(kind="S", length=length, hw=hw, zone=zone, **kw)


def A(radius, angle, hw, zone, **kw):
    return dict(kind="A", radius=radius, angle=angle, hw=hw, zone=zone, **kw)


G_LEG = float(os.environ.get("G_LEG", "100"))
KINK2 = float(os.environ.get("KINK2", "-10"))
MS1 = float(os.environ.get("MS1", "8"))
FS = float(os.environ.get("FS", "32"))
MS2 = float(os.environ.get("MS2", "12"))
MR = float(os.environ.get("MR", "16"))
MH = float(os.environ.get("MH", "14"))
ML1 = float(os.environ.get("ML1", "14"))
ML3 = float(os.environ.get("ML3", "14"))
# ------------------------------------------------------------------ the lap (zones in order)
ELEMS = [
    # 1 Cellar Vaults (start): grid, 90 R, chicane between barrel racks
    S(24.0, 9.0, 'cellar', tag='after_line'),
    A(20.0, 90.0, 6.0, 'cellar', tag='cellar90', corner='90'),
    S(8.0, 6.0, 'cellar'),
    A(24.0, -32.0, 6.0, 'cellar', tag='chic1', corner='chicane'),
    S(5.0, 6.0, 'cellar'),
    A(24.0, 32.0, 6.0, 'cellar', tag='chic2'),
    S(6.0, 6.0, 'cellar'),
    # 2 Torch Gallery: S-tunnel (3 bends) then the pillar hall (3 lanes)
    A(40.0, 36.4, 5.0, 'torch', tag='gal_sweep', corner='sweeper'),
    S(6.0, 4.75, 'torch'),
    A(28.0, -45.0, 4.75, 'torch', tag='tun1', corner='S-tunnel'),
    S(6.0, 4.75, 'torch'),
    A(28.0, 55.0, 4.75, 'torch', tag='tun2'),
    S(6.0, 4.75, 'torch'),
    A(28.0, -45.0, 4.75, 'torch', tag='tun3', corner='tunnel bend'),
    S(8.0, 4.75, 'torch', tag='hall_in'),
    A(185.0, 26.0, 3.4, 'torch', tag='split', corner='kink (pillar hall)'),
    S(8.0, 4.75, 'torch', tag='hall_out'),
    # 3 Great Cavern: wide, lava shore sweeper (open edge left), hairpin around the stalagmite
    S(18.0, 11.0, 'cavern', tag='cav_in'),
    A(66.4, -60.6, 12.0, 'cavern', tag='shore', open=True, corner='sweeper (lava shore)', bank=-5.0),  # off-camber
    S(14.0, 11.0, 'cavern', tag='stal_run'),
    A(17.0, 170.0, 11.0, 'cavern', tag='stalagmite', corner='hairpin', bank=10.0),
    # 4 Mine Works: 90 R, hairpin around the ore crusher, 90 R (a bay hanging off the road; the rail runs straight past its mouth)
    S(MS1, 6.5, 'mine', tag='mine_in'),
    A(90.0, KINK2, 6.5, 'mine', tag='kink2', corner='kink', bank=-3.0),  # off-camber
    S(MS2, 6.5, 'mine', tag='rail_in'),
    A(MR, 90.0, 6.5, 'mine', tag='mine90a', corner='90', bank=10.0),
    S(ML1, 6.5, 'mine', tag='leg1'),
    A(MH, -170.0, 6.5, 'mine', tag='crusher1', corner='hairpin (crusher)', bank=12.0),
    S(ML3, 6.5, 'mine', tag='leg3'),
    A(MR, 90.0, 6.5, 'mine', tag='mine90b', corner='90', bank=10.0),
    S(14.0, 6.5, 'mine', tag='rail_out'),
    A(35.0, 33.2 - KINK2, 6.5, 'mine', tag='mine_out', corner='sweeper'),
    # 5 Lava Forge (home): bridge, S-bend through furnaces, long 90 onto the grid
    S(6.0, 6.0, 'forge'),
    S(40.0, 5.0, 'forge', tag='bridge', open=True),
    S(8.0, 7.0, 'forge'),
    A(22.0, -38.0, 7.0, 'forge', tag='forge_s1', corner='bend (furnaces)'),
    S(FS, 7.0, 'forge'),
    A(22.0, 38.0, 7.0, 'forge', tag='forge_s2'),
    S(None, 7.0, 'forge', tag='free_b'),
    A(22.0, 90.0, 8.0, 'forge', tag='forge90', corner='90 (long, onto the grid)'),
    S(None, 9.0, 'cellar', tag='free_a'),
]
SPLIT_SHIFT = float(os.environ.get("SPLIT_SHIFT", "8.2"))   # lane centerlines either side of the middle lane
SPLIT_RAMP = 18.0
SPLIT_LANE_HW = 3.4    # lane half width (3 x ~7 m lanes)


def dirv(deg):
    r = math.radians(deg)
    return (math.cos(r), math.sin(r))


def add(a, b): return (a[0] + b[0], a[1] + b[1])
def sub(a, b): return (a[0] - b[0], a[1] - b[1])
def mul(a, k): return (a[0] * k, a[1] * k)
def dot(a, b): return a[0] * b[0] + a[1] * b[1]
def ln(a): return math.hypot(a[0], a[1])
def norm(a):
    l = ln(a)
    return (a[0] / l, a[1] / l)
def nrm(t): return (-t[1], t[0])


def displacement(elems, lens):
    p = (0.0, 0.0)
    h = 0.0
    for i, e in enumerate(elems):
        if e["kind"] == "S":
            L = lens.get(i, e["length"]) or 0.0
            p = add(p, mul(dirv(h), L))
        else:
            r, a = e["radius"], e["angle"]
            sg = 1 if a > 0 else -1
            c = add(p, mul(nrm(dirv(h)), r * sg))
            h2 = h + a
            p = add(c, mul(nrm(dirv(h2)), -r * sg))
            h = h2
    return p, h


free = [i for i, e in enumerate(ELEMS) if e["kind"] == "S" and e["length"] is None]
p0, hsum = displacement(ELEMS, {free[0]: 0.0, free[1]: 0.0})
assert abs(hsum - 360.0) < 1e-6, "turning must total +360, got %s" % hsum


def heading_before(idx):
    h = 0.0
    for e in ELEMS[:idx]:
        if e["kind"] == "A":
            h += e["angle"]
    return h


da = dirv(heading_before(free[0]))
db = dirv(heading_before(free[1]))
det = da[0] * db[1] - da[1] * db[0]
la = (-p0[0] * db[1] + p0[1] * db[0]) / det
lb = (-da[0] * p0[1] + da[1] * p0[0]) / det
ELEMS[free[0]]["length"] = la
ELEMS[free[1]]["length"] = lb
if la < 0 or lb < 0:
    raise SystemExit("closure needs negative straights: %.1f %.1f" % (la, lb))

# ------------------------------------------------------------------ dense turtle samples
dense = []  # dicts: p, h, hw, elem, u (meters into element)
p = (0.0, 0.0)
h = 0.0
starts = []
for i, e in enumerate(ELEMS):
    starts.append(len(dense))
    if e["kind"] == "S":
        L = e["length"]
        n = max(1, int(round(L / STEP)))
        for k in range(n):
            dense.append(dict(p=add(p, mul(dirv(h), L * k / n)), h=h, elem=i, u=L * k / n))
        p = add(p, mul(dirv(h), L))
    else:
        r, a = e["radius"], e["angle"]
        sg = 1 if a > 0 else -1
        c = add(p, mul(nrm(dirv(h)), r * sg))
        L = r * math.radians(abs(a))
        n = max(2, int(round(L / STEP)))
        for k in range(n):
            hk = h + a * k / n
            dense.append(dict(p=add(c, mul(nrm(dirv(hk)), -r * sg)), h=hk, elem=i, u=L * k / n))
        h += a
        p = add(c, mul(nrm(dirv(h)), -r * sg))
starts.append(len(dense))
for k, dp in enumerate(dense):
    dp["s"] = k * STEP  # turtle distance (approx. the spline distance)
TURTLE_LEN = len(dense) * STEP


def elem_index(tag):
    for i, e in enumerate(ELEMS):
        if e.get("tag") == tag:
            return i
    raise KeyError(tag)


def elem_s(tag, frac=0.0):
    i = elem_index(tag)
    return dense[starts[i]]["s"] + frac * (starts[i + 1] - starts[i]) * STEP


# lane split: main lane on +side, branch lane on -side of the street
split_i = elem_index("split")
split_len = ELEMS[split_i]["radius"] * math.radians(abs(ELEMS[split_i]["angle"]))  # the hall is an arc


def split_offset(u):
    if u <= 0 or u >= split_len:
        return 0.0
    if u < SPLIT_RAMP:
        return SPLIT_SHIFT * 0.5 * (1 - math.cos(math.pi * u / SPLIT_RAMP))
    if u > split_len - SPLIT_RAMP:
        return SPLIT_SHIFT * 0.5 * (1 - math.cos(math.pi * (split_len - u) / SPLIT_RAMP))
    return SPLIT_SHIFT


for dp in dense:
    e = ELEMS[dp["elem"]]
    hw = e["hw"]
    if dp["elem"] == split_i:
        f = split_offset(dp["u"]) / SPLIT_SHIFT
        hw = hw + (SPLIT_LANE_HW - hw) * f
    dp["hw_target"] = hw

# width slope limit: hw = min_j(target_j + slope * |s_i - s_j|) (pinches kept, widenings ramp)
N = len(dense)
hw = [d_["hw_target"] for d_ in dense]
for _ in range(2):
    for k in range(1, 2 * N):
        i, j = k % N, (k - 1) % N
        hw[i] = min(hw[i], hw[j] + WIDTH_SLOPE * STEP)
    for k in range(2 * N, 0, -1):
        i, j = k % N, (k + 1) % N
        hw[i] = min(hw[i], hw[j] + WIDTH_SLOPE * STEP)
for k, dp in enumerate(dense):
    dp["hw"] = hw[k]

# ------------------------------------------------------------------ control points
cps = []
cp_hw = []
cp_turn = []
n_cp = int(round(TURTLE_LEN / CP_STEP))
for k in range(n_cp):
    idx = int(round((k * CP_STEP + LINE_SHIFT) / STEP)) % N
    dp = dense[idx]
    pt = dp["p"]
    cps.append(pt)
    cp_hw.append(dp["hw"])
    _e = ELEMS[dp["elem"]]
    cp_turn.append((_e["radius"], 1 if _e["angle"] > 0 else -1, _e.get("bank")) if _e["kind"] == "A" else (None, 0, None))


def cr_pt(p0, p1, p2, p3, t):
    t2 = t * t
    t3 = t2 * t
    return tuple(0.5 * ((2 * p1[i]) + (-p0[i] + p2[i]) * t + (2 * p0[i] - 5 * p1[i] + 4 * p2[i] - p3[i]) * t2
                        + (-p0[i] + 3 * p1[i] - 3 * p2[i] + p3[i]) * t3) for i in (0, 1))


def spline_closed(c, spp):
    n = len(c)
    out = []
    for i in range(n):
        for k in range(spp):
            out.append(cr_pt(c[(i - 1) % n], c[i], c[(i + 1) % n], c[(i + 2) % n], k / spp))
    return out


def spline_open(c, spp):
    n = len(c)
    out = []
    for i in range(n - 1):
        p0_ = c[i - 1] if i > 0 else sub(mul(c[0], 2), c[1])
        p3_ = c[i + 2] if i + 2 < n else sub(mul(c[-1], 2), c[-2])
        for k in range(spp):
            out.append(cr_pt(p0_, c[i], c[i + 1], p3_, k / spp))
    out.append(c[-1])
    return out


pts = spline_closed(cps, SPP)
pts_hw = []
for i in range(len(cps)):
    for k in range(SPP):
        pts_hw.append(cp_hw[i] + (cp_hw[(i + 1) % len(cps)] - cp_hw[i]) * k / SPP)
cum = [0.0]
for i in range(len(pts)):
    cum.append(cum[-1] + ln(sub(pts[(i + 1) % len(pts)], pts[i])))
LENGTH = cum[-1]


def seg_at(s):
    s %= LENGTH
    lo, hi = 0, len(pts) - 1
    while lo < hi:
        mid = (lo + hi + 1) >> 1
        if cum[mid] <= s:
            lo = mid
        else:
            hi = mid - 1
    return lo


def point_at(s):
    s %= LENGTH
    lo = seg_at(s)
    a = pts[lo]
    b = pts[(lo + 1) % len(pts)]
    f = (s - cum[lo]) / (cum[lo + 1] - cum[lo])
    return (a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f)


def tangent_at(s):
    return norm(sub(point_at(s + 1.0), point_at(s - 1.0)))


def normal_at(s):
    return nrm(tangent_at(s))


def hw_at(s):
    s %= LENGTH
    lo = seg_at(s)
    f = (s - cum[lo]) / (cum[lo + 1] - cum[lo])
    return pts_hw[lo] + (pts_hw[(lo + 1) % len(pts)] - pts_hw[lo]) * f


def s_of(p):
    best = (1e18, 0.0)
    for i in range(len(pts)):
        a = pts[i]
        b = pts[(i + 1) % len(pts)]
        ab = sub(b, a)
        l2 = dot(ab, ab)
        t = max(0.0, min(1.0, dot(sub(p, a), ab) / l2)) if l2 > 0 else 0.0
        q = add(a, mul(ab, t))
        dd = ln(sub(p, q))
        if dd < best[0]:
            best = (dd, cum[i] + t * math.sqrt(l2))
    return best[1]


def ts(tag, frac=0.0):
    """Main-loop spline distance of a turtle location (element tag, fraction)."""
    return s_of(dense[min(int(round(elem_s(tag, frac) / STEP)), N - 1)]["p"]) if True else 0.0


def branch_len(c, spp):
    o = spline_open(c, spp)
    return sum(ln(sub(o[i + 1], o[i])) for i in range(len(o) - 1)), o


def fillet(poly, radii, step=2.0):
    """Polyline through poly with each interior corner rounded by radii[i] (meters)."""
    out = [poly[0]]
    for i in range(1, len(poly) - 1):
        a_, v, b_ = poly[i - 1], poly[i], poly[i + 1]
        d1 = norm(sub(v, a_)); d2 = norm(sub(b_, v))
        th = math.acos(max(-1.0, min(1.0, dot(d1, d2))))
        if th < 1e-3:
            out.append(v); continue
        r = radii[i]
        t_ = r * math.tan(th / 2)
        p1 = sub(v, mul(d1, t_)); p2 = add(v, mul(d2, t_))
        sg = 1 if d1[0] * d2[1] - d1[1] * d2[0] > 0 else -1
        cen = add(p1, mul(nrm(d1), r * sg))
        m = max(2, int(math.ceil(r * th / step)))
        a0 = math.atan2(p1[1] - cen[1], p1[0] - cen[0])
        for k in range(m + 1):
            ak = a0 + sg * th * k / m
            out.append((cen[0] + r * math.cos(ak), cen[1] + r * math.sin(ak)))
    out.append(poly[-1])
    # resample evenly along the rounded polyline (no short segments for the spline)
    cl = [0.0]
    for i in range(1, len(out)):
        cl.append(cl[-1] + ln(sub(out[i], out[i - 1])))
    total_ = cl[-1]
    nseg = max(2, int(round(total_ / step)))
    dense_ = []
    j = 0
    for k in range(nseg + 1):
        d_ = total_ * k / nseg
        while j < len(out) - 2 and cl[j + 1] < d_:
            j += 1
        seg_ = cl[j + 1] - cl[j]
        f_ = (d_ - cl[j]) / seg_ if seg_ > 1e-9 else 0.0
        dense_.append(add(out[j], mul(sub(out[j + 1], out[j]), f_)))
    return dense_


# ------------------------------------------------------------------ branches
def lane_branch(sign):
    cps_, hws_ = [], []
    i0, i1 = starts[split_i], starts[split_i + 1]
    k = i0
    while k <= i1:
        if k >= i1:
            e_end = dense[i1 % N]
            cps_.append(e_end["p"]); hws_.append(e_end["hw"]); break
        dp = dense[k]
        cps_.append(add(dp["p"], mul(nrm(dirv(dp["h"])), sign * split_offset(dp["u"]))))
        hws_.append(dp["hw"])
        k += int(round(CP_STEP / STEP))
    return cps_, hws_


lane_l_cps, lane_l_hw = lane_branch(-1)
lane_r_cps, lane_r_hw = lane_branch(+1)
lane_s_in = s_of(lane_l_cps[0])
lane_s_out = s_of(lane_l_cps[-1])
Ll, _ = branch_len(lane_l_cps, 8)

# mine rail: straight through the crusher switchback (it crosses the middle leg: a level crossing)
rail_s_in = ts("rail_in", float(os.environ.get("RAIL_A", "0.3")))
rail_s_out = ts("rail_out", float(os.environ.get("RAIL_B", "0.6")))
rA, rB = point_at(rail_s_in), point_at(rail_s_out)
tA_, tB_ = tangent_at(rail_s_in), tangent_at(rail_s_out)
RAIL_D = float(os.environ.get("RAIL_D", "8.0"))
RAIL_R = float(os.environ.get("RAIL_R", "40.0"))
rail_ctrl = fillet([rA, add(rA, mul(tA_, RAIL_D)), sub(rB, mul(tB_, RAIL_D)), rB], [0, RAIL_R, RAIL_R, 0], 3.0)
Lr, rail_pts = branch_len(rail_ctrl, 8)
# Story 009 part 3: the rail is wide enough for a kart to pass the ore cart, which rides its rails
# on one side (RAIL_LANE); a cart shuttling inside a one-lane rail would always meet a kart on it.
RAIL_HW = float(os.environ.get("RAIL_HW", "3.25"))
RAIL_LANE = float(os.environ.get("RAIL_LANE", "1.75"))

# lava gap: cuts the long forge 90
fb_i = elem_index("free_b"); fa_i = elem_index("free_a")
fb_len = ELEMS[fb_i]["length"]; fa_len = ELEMS[fa_i]["length"]
GAP_D = float(os.environ.get("GAP_D", "20.0"))
GAP_R = float(os.environ.get("GAP_R", "50.0"))
GAP_U = float(os.environ.get("GAP_U", "54.0"))   # branch meters from the fork to the lava strip's center
gap_s_in = ts("free_b", max(0.0, 1.0 - G_LEG / fb_len))   # on the straight before the long 90
gap_s_out = ts("free_a", min(0.9, float(os.environ.get("GAP_B", "60")) / fa_len))
gA, gB = point_at(gap_s_in), point_at(gap_s_out)
tgA, tgB = tangent_at(gap_s_in), tangent_at(gap_s_out)
gap_ctrl = fillet([gA, add(gA, mul(tgA, GAP_D)), sub(gB, mul(tgB, GAP_D)), gB], [0, GAP_R, GAP_R, 0], 3.0)
Lg, gap_pts = branch_len(gap_ctrl, 8)
GAP_HW = 3.5
_acc = 0.0
gi = 1
while gi < len(gap_pts) - 3 and _acc < GAP_U:
    _acc += ln(sub(gap_pts[gi], gap_pts[gi - 1]))
    gi += 1
mid = gap_pts[gi]
gt = norm(sub(gap_pts[gi + 2], gap_pts[gi - 2]))
gn = nrm(gt)
gw = GAP_HW + 0.4 + 0.6
gap_poly = [add(add(mid, mul(gt, -GAP_LEN / 2)), mul(gn, gw)), add(add(mid, mul(gt, GAP_LEN / 2)), mul(gn, gw)),
            add(add(mid, mul(gt, GAP_LEN / 2)), mul(gn, -gw)), add(add(mid, mul(gt, -GAP_LEN / 2)), mul(gn, -gw))]
gap_mid_dist = min(min(ln(sub(v_, q)) - hw_at(s_of(q)) - CURB for q in pts[::2]) for v_ in gap_poly)
print("lava gap: polygon clearance to the main corridor %.1f m (must be > 1)" % gap_mid_dist)


# ------------------------------------------------------------------ lava hazards (open edges)
def edge_strip(s0, s1, side):
    ein, eout = [], []
    k = s0 - 2.0
    while k <= s1 + 2.0:
        nn_ = mul(normal_at(k), side)
        ein.append(add(point_at(k), mul(nn_, hw_at(k) + CURB - 0.3)))
        eout.append(add(point_at(k), mul(nn_, hw_at(k) + CURB + OPEN_EDGE_REACH + 1.5)))
        k += 3.0
    return ein + list(reversed(eout))


shore_s0 = ts("shore", 0.05)
shore_s1 = ts("stal_run", 0.6)
br_s0 = ts("bridge", 0.0)
br_s1 = ts("bridge", 1.0)
open_edges = [(shore_s0, shore_s1, -1), (br_s0, br_s1, 1), (br_s0, br_s1, -1)]
hazards = [["lava_shore", "lava", edge_strip(shore_s0, shore_s1, -1), 0.0, 0.0],
           ["lava_bridge_l", "lava", edge_strip(br_s0, br_s1, -1), 0.0, 0.0],
           ["lava_bridge_r", "lava", edge_strip(br_s0, br_s1, 1), 0.0, 0.0],
           ["lava_gap", "lava", gap_poly, GAP_SPEED, 0.0]]


# ------------------------------------------------------------------ pads, items
def lat_of(p, s):
    return dot(sub(p, point_at(s)), normal_at(s))


# Pads are few and modest (a pad is worth ~0.3-0.6 s): after the cavern hairpin, after the crusher
# switchback, and the "ramp" pad on the main road 8 m before the lava-gap fork (it gives the boost
# that carries a kart over the strip).
pads = [("", ts("cav_in", 0.35), 0.0, 6.0, 4.0),
        ("", ts("free_a", 0.45), 0.0, 6.0, 4.0),
        ("", gap_s_in - 8.0, 0.0, 6.0, 4.0)]
items = []
row = ts("split", 0.5)
for sgn in (-1, 0, 1):
    items.append((row, sgn * SPLIT_SHIFT))
row = ts("shore", 0.5)
for lat in (-8.0, -3.0, 3.0, 8.0):
    items.append((row, lat))
row = ts("free_b", 0.35)
for lat in (-4.5, -1.5, 1.5, 4.5):
    items.append((row, lat))

# ------------------------------------------------------------------ elevation (story 008 part 4)
# The lap starts high in the cellar vaults (TOP_H), drops down the winding torch tunnel into the
# depths (the pillar hall, the cavern and the mine works lie low, just above the lava), crosses the
# lava channel on a raised bridge and climbs back out through the forge to the grid. The lava-gap
# branch runs flat at the top and jumps its lava strip from a low ramp.
cp_s = [cum[k * SPP] for k in range(len(cps))]
TOP_H = 7.0
LOW_H = 1.0
BRIDGE_H = 2.0
H_KEYS = [
    (ts("free_b", 0.15), TOP_H), (ts("gal_sweep", 0.2), TOP_H),                          # forge top, grid, cellar
    (ts("tun1", 0.5), 5.0), (ts("tun2", 0.5), 3.2), (ts("tun3", 0.5), 1.7),             # the drop
    (ts("hall_in", 0.5), LOW_H), (ts("mine_out", 0.5), LOW_H),                           # hall, cavern, mine
    (ts("bridge", 0.0), BRIDGE_H), (ts("bridge", 1.0), BRIDGE_H),                        # lava bridge
    (ts("forge_s1", 0.5), 3.4), (ts("forge_s2", 0.5), 5.8),                              # climb out
]
FLAT = [(lane_s_in - 14.0, lane_s_in + 14.0), (lane_s_out - 14.0, lane_s_out + 14.0),
        (rail_s_in - 14.0, ts("leg1", 0.5)), (ts("leg3", 0.3), rail_s_out + 14.0),  # the rail overlaps both 90s (level crossings)
        (gap_s_in - 14.0, gap_s_in + 14.0), (gap_s_out - 14.0, gap_s_out + 14.0),
        (lane_s_in, lane_s_out), (br_s0 - 6.0, br_s1 + 6.0), (LENGTH - 70.0, 12.0)]
cp_bank = ev.banks(cp_s, LENGTH, cp_turn, FLAT)
cp_h = ev.blur(ev.piecewise(cp_s, LENGTH, H_KEYS), 3)
cp_h, bank_need = ev.lift_for_banks(cp_h, cp_bank, [w + CURB for w in cp_hw])
cp_h = [round(h, 3) for h in cp_h]
ev.report("dungeon main", cp_s, cp_h, cp_bank, LENGTH, bool(os.environ.get("PROFILE")))


def main_h(sv):
    """Main-road centerline height at spline distance sv (linear between control points)."""
    sv %= LENGTH
    k = max(i for i in range(len(cp_s)) if cp_s[i] <= sv)
    k2 = (k + 1) % len(cp_s)
    span = (cp_s[k2] - cp_s[k]) % LENGTH
    f = (sv - cp_s[k]) / span if span > 1e-9 else 0.0
    return cp_h[k] + (cp_h[k2] - cp_h[k]) * f


# The mine rail crosses the main corridor at the crusher bay's mouth (a level crossing): it runs at
# the main road's height wherever it is (that part of the main road is not banked, see FLAT).
rail_heights = [round(main_h(s_of(q)), 3) for q in rail_ctrl]
gap_h = main_h(gap_s_in)
if abs(main_h(gap_s_out) - gap_h) > 0.05:
    raise SystemExit("lava gap ends at different heights: %.2f vs %.2f" % (gap_h, main_h(gap_s_out)))
for hz in hazards:
    if hz[0] == "lava_gap":
        hz[4] = gap_h
    elif hz[0].startswith("lava_bridge"):
        hz[4] = 0.0
GAP_RAMP_AT = GAP_U - GAP_LEN / 2 - GAP_RUNOFF - GAP_RAMP_LEN
print("lava gap: branch flat at %.2f m, ramp %.1f..%.1f m (lip %.2f), strip %.1f..%.1f m" % (
    gap_h, GAP_RAMP_AT, GAP_RAMP_AT + GAP_RAMP_LEN, GAP_RAMP_LIP, GAP_U - GAP_LEN / 2, GAP_U + GAP_LEN / 2))


# ------------------------------------------------------------------ timed hazards (story 009 part 3)
def _v2(lst):
    return "PackedVector2Array(" + ", ".join("%.3f, %.3f" % (q[0], q[1]) for q in lst) + ")"


def bank_deg(sv):
    """Main-road bank (degrees, as written to TrackData.banks) at spline distance sv."""
    sv %= LENGTH
    k = max(i for i in range(len(cp_s)) if cp_s[i] <= sv)
    k2 = (k + 1) % len(cp_s)
    span = (cp_s[k2] - cp_s[k]) % LENGTH
    f = (sv - cp_s[k]) / span if span > 1e-9 else 0.0
    return cp_bank[k] + (cp_bank[k2] - cp_bank[k]) * f


def surface_h(sv, lat):
    """Main-road surface height at spline distance sv, lateral lat (TrackModel.Path.surface_y)."""
    reach = hw_at(sv) + CURB
    return main_h(sv) + max(-reach, min(reach, lat)) * math.tan(math.radians(bank_deg(sv)))


# Lava bursts: vents in the lava-side road edge (the shore's open left edge, the bridge's right
# edge). Each erupts for a short time on its own cycle; the cycles are staggered so only one is up at
# a time. The footprint (kart centres that are hit) is an octagon over the edge part of the road.
BURST_PERIOD = float(os.environ.get("BURST_PERIOD", "7.5"))
BURST_START = 3.0
BURST_ACTIVE = float(os.environ.get("BURST_ACTIVE", "1.6"))     # rise + full, s
BURST_TRANS = 0.35
BURST_WARN = float(os.environ.get("BURST_WARN", "1.5"))
# (id, main s, side, footprint radius m, vent centre in from the curb's outer edge m). The shore
# vents sit on the inside of the left-hand sweeper, where the racing line runs.
BURSTS = [("burst_shore_a", ts("shore", 0.3), -1, 4.0, 1.2), ("burst_shore_b", ts("shore", 0.72), -1, 4.0, 1.2),
          ("burst_bridge", ts("bridge", 0.55), 1, 3.0, 1.5)]
mover_subs, mover_ids = [], []
burst_report = []
for k, (bid, bs, side, BURST_R, BURST_INSET) in enumerate(BURSTS):
    n_ = normal_at(bs)
    lat_c = side * (hw_at(bs) + CURB - BURST_INSET)
    c = add(point_at(bs), mul(n_, lat_c))
    poly = [add(c, (BURST_R * math.cos(math.tau * j / 8 + math.pi / 8), BURST_R * math.sin(math.tau * j / 8 + math.pi / 8))) for j in range(8)]
    vh = surface_h(bs, lat_c)
    covered = BURST_R - (hw_at(bs) - abs(lat_c))   # metres of the road's half width reached by the footprint
    free_gap = 2 * hw_at(bs) - max(0.0, covered)
    burst_report.append("%s s=%.1f side=%+d lat=%.2f h=%.2f covers %.2f m of %.1f, free %.2f" % (bid, bs, side, lat_c, vh, covered, 2 * hw_at(bs), free_gap))
    mover_ids.append('SubResource("Mover_%s")' % bid)
    mover_subs.append("""[sub_resource type="Resource" id="Mover_%s"]
script = ExtResource("7_mover")
id = &"%s"
kind = &"burst"
period = %.2f
active_start = %.2f
active_time = %.2f
transition_time = %.2f
phase = %.3f
warning_lead = %.2f
block_progress = 0.25
path = &"main"
path_from = %.2f
path_to = %.2f
footprint = %s
footprint_y_min = %.3f
footprint_y_max = %.3f
vent_center = Vector2(%.3f, %.3f)
vent_height = %.3f
min_free_gap = 3.0
hit_effect = &"spin"
hit_profile = 1
hit_puff = &"scorch"
visual = &"burst"
warn_blink_hz = 3.0
warn_dome = 0.15
vent_radius = %.2f
column_radius = 1.6
column_height = 6.0
sound_warn = &"burst_rumble"
sound_down = &""
sound_active = &"burst_erupt"
""" % (bid, bid, BURST_PERIOD, BURST_START, BURST_ACTIVE, BURST_TRANS, BURST_PERIOD * k / len(BURSTS), BURST_WARN,
       bs - BURST_R, bs + BURST_R, _v2(poly), vh - 1.5, vh + 2.5, c[0], c[1], vh, BURST_R * 0.85))
print("bursts: period %.1f s, up %.2f s (+%.2f fall), warn %.1f s, staggered by %.2f s" % (BURST_PERIOD, BURST_ACTIVE, BURST_TRANS, BURST_WARN, BURST_PERIOD / len(BURSTS)))
for line in burst_report:
    print("  " + line)

# Mine cart: shuttles back and forth on the rail between two points where the cart (in its lane,
# with its hit circle) is clear of the main road, standing at each end; always solid. Karts pass it
# in the free lane of the widened rail.
CART_SPEED = float(os.environ.get("CART_SPEED", "5.0"))       # average m/s of a run
CART_PERIOD = float(os.environ.get("CART_PERIOD", "14.0"))
CART_WARN = 1.2
CART_HIT_R = 1.7
CART_MARGIN = 0.3      # m between the cart's hit circle and the main road's curb
_rc = [0.0]
for _i in range(1, len(rail_pts)):
    _rc.append(_rc[-1] + ln(sub(rail_pts[_i], rail_pts[_i - 1])))


def _rail_clear(i):
    a = rail_pts[max(i - 1, 0)]
    b = rail_pts[min(i + 1, len(rail_pts) - 1)]
    t_ = norm(sub(b, a))
    q = add(rail_pts[i], mul(nrm(t_), RAIL_LANE))
    sq = s_of(q)
    return ln(sub(q, point_at(sq))) - hw_at(sq) - CURB - CART_HIT_R


_clear = [_rail_clear(i) for i in range(len(rail_pts))]
_ok = [c_ > CART_MARGIN for c_ in _clear]
# the longest run of clear samples
best_run = (0, -1, -1)
i0 = None
for i, ok_ in enumerate(_ok + [False]):
    if ok_ and i0 is None:
        i0 = i
    elif not ok_ and i0 is not None:
        if _rc[i - 1] - _rc[i0] > best_run[0]:
            best_run = (_rc[i - 1] - _rc[i0], i0, i - 1)
        i0 = None
CART_FROM = _rc[best_run[1]] + 1.0
CART_TO = _rc[best_run[2]] - 1.0
cart_run = (CART_TO - CART_FROM) / CART_SPEED
assert 2 * cart_run + 2 * CART_WARN <= CART_PERIOD, "cart runs do not fit the period"
print("mine cart: rail %.1f m, hw %.2f, lane %+.2f; clear stretch %.1f..%.1f (%.1f m), run %.2f s each way, stands %.2f s, period %.1f s" % (
      _rc[-1], RAIL_HW, RAIL_LANE, CART_FROM, CART_TO, CART_TO - CART_FROM, cart_run, CART_PERIOD * 0.5 - cart_run, CART_PERIOD))
print("  rail clearance profile (along: m past main corridor + hit radius):", " ".join("%.0f:%.1f" % (_rc[i], _clear[i]) for i in range(0, len(rail_pts), 4)))
mover_ids.append('SubResource("Mover_cart")')
mover_subs.append("""[sub_resource type="Resource" id="Mover_cart"]
script = ExtResource("7_mover")
id = &"mine_cart"
kind = &"cart"
period = %.2f
active_start = 0.0
active_time = 0.0
transition_time = 0.0
phase = 0.0
warning_lead = %.2f
path = &"mine_rail"
path_from = %.2f
path_to = %.2f
speed = %.2f
motion = &"shuttle"
lane_offset = %.2f
hit_radius = %.2f
hit_height = 1.5
min_free_gap = 3.0
hit_effect = &"spin"
hit_profile = 2
solid_body = true
visual = &"cart"
body_radius = 0.65
body_color = Color(0.42, 0.28, 0.16, 1)
band_color = Color(0.2, 0.2, 0.22, 1)
cart_width = 1.3
cart_height = 0.9
cart_length = 1.9
wheel_radius = 0.3
ore_color = Color(0.3, 0.42, 0.62, 1)
sound_warn = &""
sound_down = &""
sound_active = &"cart_rumble"
""" % (CART_PERIOD, CART_WARN, CART_FROM, CART_TO, CART_SPEED, RAIL_LANE, CART_HIT_R))


# ------------------------------------------------------------------ surface zones (story 011 part 2)
# Loose rubble at the two cave mouths of the cavern, a cinder (sand) boost-cut inside the long 90 onto
# the grid after the forge, and a slime-wet flagstone patch (slick) on the inside of the cellar chicane
# under the dripping cistern. Every zone vertex carries the height of the road edge it sits on (with
# the bank); outer vertices take the height of the nearest road-edge vertex.
def edge_pt(sv, side, inset=0.3):
    """Point on the main road's curb edge on [side] at sv, [inset] meters inside the curb, and its height."""
    lat = side * (hw_at(sv) + CURB - inset)
    return add(point_at(sv), mul(normal_at(sv), lat)), surface_h(sv, lat)


def curb_run(s0, s1, side, step=3.0):
    out = []
    n = max(int(math.ceil((s1 - s0) / step)), 1)
    for k in range(n + 1):
        out.append(edge_pt(s0 + (s1 - s0) * k / n, side))
    return out


def nearest_h(p, edge):
    return min(edge, key=lambda e: ln(sub(e[0], p)))[1]


def _in_poly(p, poly):
    c = False
    j = len(poly) - 1
    for i in range(len(poly)):
        if (poly[i][1] > p[1]) != (poly[j][1] > p[1]) and \
                p[0] < (poly[j][0] - poly[i][0]) * (p[1] - poly[i][1]) / (poly[j][1] - poly[i][1]) + poly[i][0]:
            c = not c
        j = i
    return c


SURF_CHUNK = 6.0          # wall openings are cut per this many meters of road ...
SURF_DEPTH_MARGIN = 1.5   # ... as deep as the zone reaches past the curb there, plus this
surf_zones = []      # (id, kind, polygon, heights, fence)
surf_openings = []   # (s_from, s_to, side, depth)
surf_routes = {}     # id -> (route_from, route_to, boost_cut)


def zone_openings(poly, side):
    """Wall openings on [side] covering every main-road stretch the zone lies beside (sampled every 0.5 m)."""
    reach = {}
    xs = [q[0] for q in poly]
    zs = [q[1] for q in poly]
    gx = min(xs)
    while gx <= max(xs):
        gz = min(zs)
        while gz <= max(zs):
            if _in_poly((gx, gz), poly):
                sv = s_of((gx, gz))
                d = ln(sub((gx, gz), point_at(sv)))
                k = int(sv // SURF_CHUNK)
                reach[k] = max(reach.get(k, 0.0), d - hw_at(sv) - CURB)
            gz += 0.5
        gx += 0.5
    for k in sorted(reach):
        surf_openings.append((k * SURF_CHUNK, (k + 1) * SURF_CHUNK, side, max(reach[k], 0.0) + SURF_DEPTH_MARGIN))


SIDE_TAPER = float(os.environ.get("SIDE_TAPER", "7.0"))


def side_zone(zid, kind, s0, s1, side, depth):
    """A strip beside the road on [side] from s0 to s1, [depth] meters out from the curb. The far edge is
    SIDE_TAPER shorter at each end: the end fences slant back to the road (a kart running along the
    strip is steered out, not stopped head-on)."""
    inner = curb_run(s0, s1, side, 3.0)
    outer = []
    o0, o1 = s0 + SIDE_TAPER, s1 - SIDE_TAPER
    n = max(int(math.ceil((o1 - o0) / 5.0)), 1)
    for k in range(n + 1):
        sv = o1 - (o1 - o0) * k / n
        outer.append(add(point_at(sv), mul(normal_at(sv), side * (hw_at(sv) + CURB + depth))))
    poly = [e[0] for e in inner] + outer
    hs = [e[1] for e in inner] + [nearest_h(q, inner) for q in outer]
    surf_zones.append((zid, kind, poly, hs, True))
    zone_openings(poly, side)


# 1-2. Rubble at the cave mouths: entering the cavern (outside of the shore sweeper, away from the lava)
# and leaving it toward the mine (outside of the stalagmite hairpin exit, before the rail branch).
RUBBLE_A = (float(os.environ.get("RUBBLE_A0", "300.0")), float(os.environ.get("RUBBLE_A1", "326.0")), 1, 8.0)
RUBBLE_B = (ts("mine_in", 0.0) + 1.0, rail_s_in - 6.0, -1, 7.0)
side_zone("cave_rubble_in", "rubble", *RUBBLE_A)
side_zone("cave_rubble_out", "rubble", *RUBBLE_B)

# 3. Cinder cut: a sand patch inside the long 90 onto the grid (forge90), between the inner curb from
# CUT_LEAD before the corner to CUT_LEAD after it and the diagonal fence. Shorter than the road, but
# sand caps the speed: it pays only with a boost.
CUT_LEAD = float(os.environ.get("CUT_LEAD", "20.0"))
_c0 = ts("forge90", 0.0) - CUT_LEAD
_c1 = ts("forge90", 1.0) + CUT_LEAD
_cut = curb_run(_c0, _c1, 1, 3.0)
surf_zones.append(("cinder_cut", "sand", [e[0] for e in _cut], [e[1] for e in _cut], True))
zone_openings([e[0] for e in _cut], 1)
CUT_ROUTE_IN = 2.0
CUT_ROUTE_OUT = 4.0
surf_routes["cinder_cut"] = (_c0 - CUT_ROUTE_IN, _c1 + CUT_ROUTE_OUT, True)
CUT_CHORD = ln(sub(_cut[0][0], _cut[-1][0]))
_gap_clear = min(min(ln(sub(e[0], q)) for q in gap_pts) for e in _cut) - GAP_HW - 0.4
assert _gap_clear > 3.0, "cinder cut too close to the lava gap branch (%.1f m)" % _gap_clear

# 4. Slime-wet flagstones: a slick patch on the inside half of the first cellar chicane bend (chic1, a
# left: inside = -1), under the dripping cistern; the outside half stays clean.
SLIME_FROM = float(os.environ.get("SLIME_FROM", "-3.0"))   # meters from the bend start
SLIME_LEN = float(os.environ.get("SLIME_LEN", "16.0"))
SLIME_EDGE = 0.6     # meters inside the road edge
SLIME_OVER = 0.5     # meters past the centerline toward the outside
_l0 = ts("chic1", 0.0) + SLIME_FROM
_l1 = _l0 + SLIME_LEN
_slime = []
_n = 4
for _k in range(_n + 1):
    sv = _l0 + (_l1 - _l0) * _k / _n
    lat = -(hw_at(sv) - SLIME_EDGE)
    _slime.append((add(point_at(sv), mul(normal_at(sv), lat)), surface_h(sv, lat)))
for _k in range(_n + 1):
    sv = _l1 - (_l1 - _l0) * _k / _n
    _slime.append((add(point_at(sv), mul(normal_at(sv), SLIME_OVER)), surface_h(sv, SLIME_OVER)))
surf_zones.append(("cistern_slime", "slick", [e[0] for e in _slime], [e[1] for e in _slime], False))
print("surfaces: rubble in s %.1f..%.1f (+1, %.0f m), rubble out s %.1f..%.1f (-1, %.0f m); cinder cut s %.1f..%.1f chord %.1f m "
      "(road %.1f m), %.1f m clear of the lava gap; slime s %.1f..%.1f" % (
          RUBBLE_A[0], RUBBLE_A[1], RUBBLE_A[3], RUBBLE_B[0], RUBBLE_B[1], RUBBLE_B[3], _c0, _c1, CUT_CHORD, _c1 - _c0,
          _gap_clear, _l0, _l1))
for z in surf_zones:
    print("  zone %-16s %-7s %d points, h %.2f..%.2f" % (z[0], z[1], len(z[2]), min(z[3]), max(z[3])))
print("  openings:", ["%.0f%+d:%.1f" % (o[0], o[2], o[3]) for o in surf_openings])
SURF_PLOT = [(z[0], z[2]) for z in surf_zones]


# ------------------------------------------------------------------ report
print("main length %.1f m (turtle %.1f), control points %d, free straights %.1f / %.1f" % (LENGTH, TURTLE_LEN, len(cps), la, lb))
for i, e in enumerate(ELEMS):
    if e.get("corner"):
        print("  corner %-28s s=%6.1f  R=%5.1f  %+5.0f deg  hw %.1f" % (e["corner"] + (" R" if e["angle"] > 0 else " L"), ts(e["tag"]) if e.get("tag") else -1, e["radius"], e["angle"], e["hw"]))
zones_def = [("cellar", "free_a", "gal_sweep"), ("torch", "gal_sweep", "cav_in"), ("cavern", "cav_in", "mine_in"),
             ("mine", "mine_in", "bridge"), ("forge", "bridge", "free_a")]
zr = {}
for z, a_, b_ in zones_def:
    zr[z] = (ts(a_), ts(b_))
print("zones (main s):", {k: (round(v[0]), round(v[1])) for k, v in zr.items()})
print("hall lanes s %.1f..%.1f lane %.1f m" % (lane_s_in, lane_s_out, Ll))
print("mine rail s %.1f..%.1f (main %.1f m) rail %.1f m saves %.1f m" % (rail_s_in, rail_s_out, rail_s_out - rail_s_in, Lr, rail_s_out - rail_s_in - Lr))
print("lava gap s %.1f..%.1f (main %.1f m) branch %.1f m saves %.1f m" % (gap_s_in, gap_s_out, gap_s_out - gap_s_in, Lg, gap_s_out - gap_s_in - Lg))
worst = (1e9, 0, 0)
for i in range(0, len(pts), 2):
    for j in range(i + 1, len(pts), 2):
        ds = min(cum[j] - cum[i], LENGTH - (cum[j] - cum[i]))
        if ds < 70:
            continue
        d_ = ln(sub(pts[i], pts[j])) - (pts_hw[i] + pts_hw[j] + 2 * CURB)
        if d_ < worst[0]:
            worst = (d_, cum[i], cum[j])
print("loop clearance min %.1f m (s %.0f vs s %.0f)" % worst)


def center_of(tag):
    i = elem_index(tag)
    e = ELEMS[i]
    d0 = dense[starts[i]]
    return add(d0["p"], mul(nrm(dirv(d0["h"])), e["radius"] * (1 if e["angle"] > 0 else -1)))


stalagmite = center_of("stalagmite")
crusher = center_of("crusher1")
pulley = center_of("mine90b")
lake = center_of("shore")
bounds_min = (min(p_[0] for p_ in pts), min(p_[1] for p_ in pts))
bounds_max = (max(p_[0] for p_ in pts), max(p_[1] for p_ in pts))
forge_glow = (sum(p_[0] for p_ in pts) / len(pts), sum(p_[1] for p_ in pts) / len(pts))
print("anchors: stalagmite %s crusher %s pulley %s lake %s centroid %s" % tuple(str(tuple(round(v, 1) for v in q)) for q in (stalagmite, crusher, pulley, lake, forge_glow)))

PLOT = os.environ.get("PLOT")
if PLOT:
    from PIL import Image, ImageDraw
    sc = 1.4
    W = int((bounds_max[0] - bounds_min[0] + 100) * sc)
    H = int((bounds_max[1] - bounds_min[1] + 100) * sc)
    img = Image.new("RGB", (W, H), (30, 22, 28))
    dr = ImageDraw.Draw(img)
    T = lambda q: ((q[0] - bounds_min[0] + 50) * sc, (q[1] - bounds_min[1] + 50) * sc)
    dr.ellipse([T(sub(lake, (48, 48))), T(add(lake, (48, 48)))], outline=(220, 90, 20))
    for h_ in hazards:
        dr.polygon([T(q) for q in h_[2]], fill=(220, 90, 20) if h_[3] == 0 else (255, 200, 60))
    for i in range(len(pts)):
        a = pts[i]
        b = pts[(i + 1) % len(pts)]
        nn = nrm(norm(sub(b, a)))
        w = pts_hw[i]
        dr.polygon([T(add(a, mul(nn, w))), T(add(b, mul(nn, w))), T(add(b, mul(nn, -w))), T(add(a, mul(nn, -w)))], fill=(110, 100, 95))
    for pl, col, w in ((spline_open(lane_l_cps, 4), (150, 140, 120), SPLIT_LANE_HW), (spline_open(lane_r_cps, 4), (150, 140, 120), SPLIT_LANE_HW),
                       (rail_pts, (150, 100, 50), RAIL_HW), (gap_pts, (70, 130, 200), GAP_HW)):
        for i in range(len(pl) - 1):
            dr.line([T(pl[i]), T(pl[i + 1])], fill=col, width=max(1, int(2 * w * sc)))
    for s_ in range(0, int(LENGTH), 50):
        dr.text(T(point_at(s_)), str(s_), fill=(255, 255, 255))
    dr.line([T(add(point_at(0), mul(normal_at(0), 10))), T(add(point_at(0), mul(normal_at(0), -10)))], fill=(255, 255, 255), width=3)
    for q in (stalagmite, crusher, pulley, lake, forge_glow):
        dr.ellipse([T(sub(q, (3, 3))), T(add(q, (3, 3)))], fill=(230, 60, 30))
    for it in items:
        q = add(point_at(it[0]), mul(normal_at(it[0]), it[1]))
        dr.rectangle([T(sub(q, (1, 1))), T(add(q, (1, 1)))], fill=(255, 140, 0))
    for pd_ in pads:
        q = add(point_at(pd_[1]), mul(normal_at(pd_[1]), pd_[2]))
        dr.rectangle([T(sub(q, (2, 2))), T(add(q, (2, 2)))], fill=(0, 255, 255))
    for z, (a_, b_) in zr.items():
        dr.text(T(point_at((a_ + b_) / 2)), z.upper(), fill=(255, 255, 0))
    img.save(PLOT)
    print("plot", PLOT)

if os.environ.get("NOWRITE"):
    raise SystemExit(0)


# ------------------------------------------------------------------ write resources
def v2(lst):
    return "PackedVector2Array(" + ", ".join("%.3f, %.3f" % (q[0], q[1]) for q in lst) + ")"


def f32(lst):
    return "PackedFloat32Array(" + ", ".join("%.3f" % x for x in lst) + ")"


def v3(lst):
    return "PackedVector3Array(" + ", ".join("%.3f, %.3f, %.3f" % q for q in lst) + ")"


out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "tracks", "dungeon_depths")
os.makedirs(out, exist_ok=True)
subs, branch_ids = [], []


def add_branch(sid, bid, btype, ctrl, hw, curb, s_in, s_out, spp, deck, deck_alt, wall, wall_alt, wall_h, extra="", hws=None):
    branch_ids.append('SubResource("%s")' % sid)
    subs.append("""[sub_resource type="Resource" id="%s"]
script = ExtResource("2_branch")
id = &"%s"
type = &"%s"
control_points = %s
half_width = %.2f
%scurb_width = %.2f
s_in = %.3f
s_out = %.3f
samples_per_segment = %d
deck_color = %s
deck_alt_color = %s
wall_color = %s
wall_alt_color = %s
wall_height = %.2f
%s""" % (sid, bid, btype, v2(ctrl), hw, ("half_widths = %s\n" % f32(hws)) if hws else "", curb, s_in, s_out, spp, deck, deck_alt, wall, wall_alt, wall_h, extra))


STONE = ("Color(0.36, 0.31, 0.30, 1)", "Color(0.32, 0.27, 0.27, 1)", "Color(0.5, 0.42, 0.38, 1)", "Color(0.43, 0.36, 0.33, 1)")
add_branch("Branch_hl", "hall_left", "lane_split", lane_l_cps, SPLIT_LANE_HW, 0.6, lane_s_in, lane_s_out, 8, *STONE, 1.0, hws=lane_l_hw)
add_branch("Branch_hr", "hall_right", "lane_split", lane_r_cps, SPLIT_LANE_HW, 0.6, lane_s_in, lane_s_out, 8, *STONE, 1.0, hws=lane_r_hw)
add_branch("Branch_rail", "mine_rail", "mine_rail", rail_ctrl, RAIL_HW, 0.4, rail_s_in, rail_s_out, 8,
           "Color(0.42, 0.28, 0.16, 1)", "Color(0.34, 0.22, 0.13, 1)", "Color(0.30, 0.38, 0.55, 1)", "Color(0.36, 0.46, 0.66, 1)", 0.9,
           "floor_drag_mult = %g\nwall_drag_mult = 2.0\nrail_lane = %.2f\nheights = %s\n" % (MINE_DRAG, RAIL_LANE, f32(rail_heights)))
add_branch("Branch_gap", "lava_gap", "lava_gap", gap_ctrl, GAP_HW, 0.4, gap_s_in, gap_s_out, 8,
           "Color(0.27, 0.2, 0.18, 1)", "Color(0.22, 0.16, 0.15, 1)", "Color(0.30, 0.38, 0.55, 1)", "Color(0.36, 0.46, 0.66, 1)", 0.9,
           "heights = %s\n" % f32([gap_h] * len(gap_ctrl)))
subs.append("""[sub_resource type="Resource" id="Ramp_gap"]
script = ExtResource("6_ramp")
road = &"lava_gap"
distance = %.3f
length = %.2f
lip_height = %.2f
color_a = Color(0.78, 0.25, 0.17, 1)
color_b = Color(0.96, 0.92, 0.82, 1)
side_color = Color(0.32, 0.26, 0.25, 1)
stripes = 4
""" % (GAP_RAMP_AT, GAP_RAMP_LEN, GAP_RAMP_LIP))
subs.extend(mover_subs)
haz_ids = []
for i, h_ in enumerate(hazards):
    haz_ids.append('SubResource("Hazard_%d")' % i)
    subs.append("""[sub_resource type="Resource" id="Hazard_%d"]
script = ExtResource("4_hazard")
id = &"%s"
kind = &"%s"
polygon = %s
min_cross_speed = %.2f
surface_height = %.3f
""" % (i, h_[0], h_[1], v2(h_[2]), h_[3], h_[4]))
pad_ids = []
for i, pd_ in enumerate(pads):
    pad_ids.append('SubResource("Pad_%d")' % i)
    subs.append("""[sub_resource type="Resource" id="Pad_%d"]
script = ExtResource("5_pad")
road = &"%s"
distance = %.3f
lateral = %.3f
length = %.2f
width = %.2f
""" % (i, pd_[0], pd_[1], pd_[2], pd_[3], pd_[4]))

surf_ids = []
for _k, (zid, kind, poly, hs, fence) in enumerate(surf_zones):
    surf_ids.append('SubResource("Surf_%d")' % _k)
    _r = surf_routes.get(zid, (-1.0, -1.0, False))
    subs.append("""[sub_resource type="Resource" id="Surf_%d"]
script = ExtResource("8_surf")
id = &"%s"
kind = &"%s"
polygon = %s
heights = %s
height = %.3f
fence = %s
route_from = %.2f
route_to = %.2f
boost_cut = %s
""" % (_k, zid, kind, v2(poly), f32(hs), min(hs), "true" if fence else "false", _r[0], _r[1], "true" if _r[2] else "false"))
open_ids = []
for _k, (o0, o1, oside, odepth) in enumerate(surf_openings):
    open_ids.append('SubResource("Open_%d")' % _k)
    subs.append("""[sub_resource type="Resource" id="Open_%d"]
script = ExtResource("9_open")
s_from = %.3f
s_to = %.3f
side = %d
depth = %.2f
""" % (_k, o0, o1, oside, odepth))

TRES = """[gd_resource type="Resource" script_class="TrackData" load_steps=%d format=3]

[ext_resource type="Script" path="res://src/test_track/track_data.gd" id="1_data"]
[ext_resource type="Script" path="res://src/track/track_branch.gd" id="2_branch"]
[ext_resource type="Resource" path="res://assets/tracks/dungeon_depths/dungeon_theme.tres" id="3_theme"]
[ext_resource type="Script" path="res://src/track/track_hazard.gd" id="4_hazard"]
[ext_resource type="Script" path="res://src/track/track_pad.gd" id="5_pad"]
[ext_resource type="Script" path="res://src/track/track_ramp.gd" id="6_ramp"]
[ext_resource type="Script" path="res://src/track/track_mover.gd" id="7_mover"]
[ext_resource type="Script" path="res://src/track/track_surface.gd" id="8_surf"]
[ext_resource type="Script" path="res://src/track/track_wall_opening.gd" id="9_open"]

%s
[resource]
script = ExtResource("1_data")
track_id = &"dungeon_depths"
display_name = "Dungeon Depths"
theme = ExtResource("3_theme")
branches = Array[ExtResource("2_branch")]([%s])
hazards = Array[ExtResource("4_hazard")]([%s])
boost_pads = Array[ExtResource("5_pad")]([%s])
checkpoint_count = 10
item_box_spots = %s
control_points = %s
half_widths = %s
samples_per_segment = %d
road_half_width = 6.0
curb_width = %.2f
open_edges = %s
open_edge_reach = %.2f
respawn_sink_time = %.2f
respawn_speed_frac = %.4f
respawn_immunity_time = %.2f
respawn_back_off = %.2f
boost_pad_time = %.2f
lap_count = 3
start_distance_behind_line = 6.0
query_window = 24
heights = %s
banks = %s
solid_below = 99.0
pillar_color = Color(0.3, 0.24, 0.25, 1)
deck_under_color = Color(0.24, 0.19, 0.2, 1)
ramps = Array[ExtResource("6_ramp")]([SubResource("Ramp_gap")])
movers = Array[ExtResource("7_mover")]([%s])
surfaces = Array[ExtResource("8_surf")]([%s])
wall_openings = Array[ExtResource("9_open")]([%s])
"""
with open(os.path.join(out, "dungeon_depths.tres"), "w", newline="\n") as f:
    f.write(TRES % (10 + len(subs), "\n".join(subs), ", ".join(branch_ids), ", ".join(haz_ids), ", ".join(pad_ids), v2(items), v2(cps), f32(cp_hw), SPP, CURB,
                    v3(open_edges), OPEN_EDGE_REACH, SINK_TIME, RESPAWN_SPEED_FRAC, RESPAWN_IMMUNITY, RESPAWN_BACK_OFF, PAD_BOOST_TIME,
                    f32(cp_h), f32(cp_bank), ", ".join(mover_ids), ", ".join(surf_ids), ", ".join(open_ids)))

THEME = """[gd_resource type="Resource" script_class="TrackTheme" load_steps=2 format=3]

[ext_resource type="Script" path="res://src/track/track_theme.gd" id="1_theme"]

[resource]
script = ExtResource("1_theme")
style = &"dungeon"
scenery_road_margin = 0.15
scenery_clear_height = 2.5
scenery_flat_height = 0.3
scenery_max_nudge = 3.0
sky_top_color = Color(0.07, 0.05, 0.08, 1)
sky_horizon_color = Color(0.16, 0.1, 0.1, 1)
ground_horizon_color = Color(0.16, 0.1, 0.1, 1)
ground_color = Color(0.1, 0.075, 0.085, 1)
ground_size = 1400.0
ambient_color = Color(0.58, 0.5, 0.58, 1)
ambient_energy = 0.8
sun_color = Color(0.55, 0.45, 0.6, 1)
sun_energy = 0.0
fog_enabled = true
fog_color = Color(0.17, 0.1, 0.12, 1)
fog_density = 0.004
road_color = Color(0.34, 0.29, 0.29, 1)
curb_color_a = Color(0.95, 0.64, 0.23, 1)
curb_color_b = Color(0.45, 0.3, 0.25, 1)
wall_color_a = Color(0.5, 0.42, 0.4, 1)
wall_color_b = Color(0.38, 0.31, 0.31, 1)
wall_height = 1.0
merlon_height = 0.0
wall_thickness = 0.8
wall_stripe_segments = 1
stone_light = Color(0.46, 0.38, 0.37, 1)
stone_dark = Color(0.3, 0.24, 0.25, 1)
wood_color = Color(0.4, 0.26, 0.15, 1)
dark_wood_color = Color(0.24, 0.15, 0.1, 1)
torch_color = Color(0.949, 0.639, 0.227, 1)
water_color = Color(1.0, 0.416, 0.102, 1)
lava_core_color = Color(1.0, 0.416, 0.102, 1)
lava_bright_color = Color(1.0, 0.761, 0.29, 1)
lava_crust_color = Color(0.231, 0.114, 0.094, 1)
crystal_color = Color(0.35, 0.62, 1.0, 1)
pad_color_a = Color(0.133, 0.902, 0.878, 1)
pad_color_b = Color(1, 1, 1, 1)
item_box_color = Color(0.9, 0.38, 0.15, 1)
stalagmite_position = Vector2(%.2f, %.2f)
crusher_position = Vector2(%.2f, %.2f)
pulley_position = Vector2(%.2f, %.2f)
lake_center = Vector2(%.2f, %.2f)
lake_radius = 48.0
forge_glow_position = Vector2(%.2f, %.2f)
zone_cellar = Vector2(%.2f, %.2f)
zone_torch = Vector2(%.2f, %.2f)
zone_cavern = Vector2(%.2f, %.2f)
zone_mine = Vector2(%.2f, %.2f)
zone_forge = Vector2(%.2f, %.2f)
hall_range = Vector2(%.2f, %.2f)
"""
with open(os.path.join(out, "dungeon_theme.tres"), "w", newline="\n") as f:
    vals = list(stalagmite) + list(crusher) + list(pulley) + list(lake) + list(forge_glow)
    for z in ("cellar", "torch", "cavern", "mine", "forge"):
        vals += list(zr[z])
    vals += [lane_s_in, lane_s_out]
    f.write(THEME % tuple(vals))
print("wrote")
