#!/usr/bin/env python3
"""Layout generator for Castle Circuit (story 003, round 2). Authoring aid, not run by the game.

The main loop is written as a turtle path (straights and arcs with a radius, an angle and a
half width), following design/references/track-design-reference.md section 6: five zones
(Tourney Field, Moat & Gatehouse, Market Village, Keep Courtyard, Rampart Gardens), 13
corners, per-point road width. Two straights are solved so the loop closes exactly.
It then derives the branches (village lane split, rail-less drawbridge, secret passage), the
moat hazard polygons and open edge, the boost pads, the item rows and the scenery anchors,
and writes assets/tracks/castle_circuit/castle_circuit.tres and castle_theme.tres.

Re-run after edits:  python tools/gen_castle_circuit.py   (PLOT=path.png draws a top view)
Heading convention: 0 = +x, positive angles turn toward +z (a right turn for the driver).
Side convention: +1 is TrackModel's normal (-t.y, t.x), the inside of a right turn.
"""
import math, os

SPP = 4            # spline samples per control-point segment (TrackData.samples_per_segment)
CP_STEP = 5.0      # meters between control points
STEP = 0.25        # turtle step (meters)
WIDTH_SLOPE = 0.3  # largest change of half width per meter (no wall jumps)
CURB = 1.0         # main curb width (wall = half width + curb)
LINE_SHIFT = 9.0   # the start line sits this far into the first straight (longer grid run-up)

# Respawn and pad rules (TrackData). Respawn speed: 30 mph of a 115 mph top speed (user notes
# 01-veiculos-e-fisica.md 7.4) -> 0.26 of max_speed; 3 s immunity from the same note.
SINK_TIME = 1.0
RESPAWN_SPEED_FRAC = 30.0 / 115.0
RESPAWN_IMMUNITY = 3.0
RESPAWN_BACK_OFF = 4.0
OPEN_EDGE_REACH = 6.0
PAD_BOOST_TIME = 1.1   # like a drift tier 2 boost (armored_cart drift_boost_times[2])
PASSAGE_WALL_DRAG = float(os.environ.get("PASSAGE_WALL_DRAG", "2.0"))


def S(length, hw, zone, **kw):
    return dict(kind="S", length=length, hw=hw, zone=zone, **kw)


def A(radius, angle, hw, zone, **kw):
    return dict(kind="A", radius=radius, angle=angle, hw=hw, zone=zone, **kw)


# ------------------------------------------------------------------ the lap
ELEMS = [
    S(30.0, 9.5, 'tourney', tag='after_line'),
    A(40.0, 130.1, 8.0, 'tourney', tag='sweep1', corner='sweeper'),
    S(20.0, 7.0, 'tourney'),
    A(145.5, 10.0, 7.0, 'tourney', tag='kink1', corner='kink'),
    S(10.0, 6.5, 'tourney', tag='pre_moat'),
    A(31.3, -156.6, 6.5, 'moat', tag='moat_sweep', open=True, corner='sweeper'),
    S(34.8, 6.5, 'moat', tag='wall_run', open=True),
    A(16.0, 100.0, 6.0, 'moat', tag='gate_turn', corner='90'),
    S(24.0, 4.5, 'moat', tag='gate_arch'),
    A(20.0, 80.0, 5.5, 'village', tag='village_in', corner='90'),
    S(10.0, 5.5, 'village'),
    A(22.0, -55.9, 5.5, 'village', tag='well_s1', corner='S (well)'),
    S(10.0, 5.5, 'village', tag='well'),
    A(24.0, 55.9, 5.5, 'village', tag='well_s2'),
    S(104.0, 5.5, 'village', tag='split'),
    A(20.0, 80.0, 6.0, 'village', tag='village_out', corner='90'),
    S(75.0, 11.5, 'keep', tag='plaza'),
    A(15.0, 170.0, 9.5, 'keep', tag='hairpin1', corner='hairpin'),
    S(8.0, 6.5, 'keep', tag='return'),
    A(22.0, -30.0, 5.0, 'keep', tag='chic1', corner='chicane (inner gate)'),
    S(8.0, 5.0, 'keep', tag='inner_gate'),
    A(24.0, 30.0, 5.0, 'keep', tag='chic2'),
    S(10.0, 6.5, 'keep'),
    A(16.1, -95.2, 6.5, 'gardens', tag='back_gate', corner='90'),
    S(6.0, 7.0, 'gardens', tag='garden_in'),
    A(41.6, -61.6, 7.0, 'gardens', tag='sweep3', corner='sweeper'),
    S(None, 7.5, 'gardens', tag='free_b'),
    A(168.5, 20.0, 8.0, 'gardens', tag='kink2', corner='kink'),
    S(20.0, 8.0, 'gardens', tag='garden_straight'),
    A(18.7, -86.7, 8.0, 'gardens', tag='hook', corner='90'),
    S(20.0, 8.0, 'gardens'),
    A(14.0, 170.0, 8.5, 'gardens', tag='hairpin2', corner='hairpin'),
    S(None, 9.5, 'tourney', tag='free_a'),
]
SPLIT_SHIFT = 6.3      # lane centerlines sit this far either side of the street centerline
SPLIT_RAMP = 24.0      # meters to move out to the lanes (and back)
SPLIT_LANE_HW = 3.4    # lane half width (8 m lanes with curbs)


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
split_len = ELEMS[split_i]["length"]


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
n_cp = int(round(TURTLE_LEN / CP_STEP))
for k in range(n_cp):
    idx = int(round((k * CP_STEP + LINE_SHIFT) / STEP)) % N
    dp = dense[idx]
    pt = dp["p"]
    if dp["elem"] == split_i:
        pt = add(pt, mul(nrm(dirv(dp["h"])), split_offset(dp["u"])))
    cps.append(pt)
    cp_hw.append(dp["hw"])


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


# ------------------------------------------------------------------ lane split branch
lane_cps = []
lane_hw = []
u = 0.0
i0 = starts[split_i]
i1 = starts[split_i + 1]
k = i0
while k <= i1:
    dp = dense[min(k, N - 1)] if k < i1 else None
    if dp is None:
        e_end = dense[i1 % N]
        lane_cps.append(e_end["p"])
        lane_hw.append(e_end["hw"])
        break
    lane_cps.append(add(dp["p"], mul(nrm(dirv(dp["h"])), -split_offset(dp["u"]))))
    lane_hw.append(dp["hw"])
    k += int(round(CP_STEP / STEP))
lane_s_in = s_of(lane_cps[0])
lane_s_out = s_of(lane_cps[-1])
Ll, _ = branch_len(lane_cps, 8)

# ------------------------------------------------------------------ drawbridge
# Leaves the main road early in the moat sweeper (a tight left), then runs straight across
# the moat and lands in line with the gatehouse arch, where the main road arrives after the
# long way round and its 90 R.
BRIDGE_IN_OFFSET = float(os.environ.get("BRIDGE_IN_OFFSET", "-12.0"))  # meters from the moat sweeper start
br_s_in = ts("moat_sweep", 0.0) + BRIDGE_IN_OFFSET
br_s_out = ts("gate_arch", 0.05)
B = point_at(br_s_out)
uB = tangent_at(br_s_out)
Ain = point_at(br_s_in)
tA = tangent_at(br_s_in)
# Tight left entry arc that starts on the road surface and leaves through the moat-side edge
# (the drift line), a straight plank across the moat, then a gentle right into the arch line.
BRIDGE_ENTRY_R = float(os.environ.get("BRIDGE_ENTRY_R", "15.0"))
BRIDGE_LAND_R = 20.0
BRIDGE_D1 = float(os.environ.get("BRIDGE_D1", "26.0"))
BRIDGE_D2 = 16.0
lead = Ain
V1b = add(Ain, mul(tA, BRIDGE_D1))
V2b = sub(B, mul(uB, BRIDGE_D2))
bridge_ctrl = fillet([Ain, V1b, V2b, B], [0, BRIDGE_ENTRY_R, BRIDGE_LAND_R, 0], 3.0)
Lb, bridge_pts = branch_len(bridge_ctrl, 12)
_br_min_r = 1e9
for k in range(1, len(bridge_pts) - 1):
    a_, b_, c_ = bridge_pts[k - 1], bridge_pts[k], bridge_pts[k + 1]
    ar = abs((b_[0] - a_[0]) * (c_[1] - a_[1]) - (b_[1] - a_[1]) * (c_[0] - a_[0]))
    if ar > 1e-6:
        _br_min_r = min(_br_min_r, ln(sub(b_, a_)) * ln(sub(c_, b_)) * ln(sub(c_, a_)) / (2 * ar))
print("bridge min radius %.1f m; A %s tA %s B %s uB %s turn %.0f deg" % (_br_min_r, str(tuple(round(v,1) for v in Ain)), str(tuple(round(v,2) for v in tA)), str(tuple(round(v,1) for v in B)), str(tuple(round(v,2) for v in uB)), math.degrees(math.atan2(tA[0]*uB[1]-tA[1]*uB[0], dot(tA,uB)))))
BRIDGE_HW = 2.5

# ------------------------------------------------------------------ secret passage
# Leaves the plaza diagonally through the tapestry in its inner wall into the keep wing (the
# block between the plaza and the road back from the hairpin), runs forward inside it, then two
# 90 degree bends drop it onto the return road past the hairpin.
PASSAGE_ENTRY = float(os.environ.get("PASSAGE_ENTRY", "0.622"))  # fraction along the plaza
PASSAGE_RUN = 12.0     # meters run forward inside the keep wing
RB = 9.0               # bend radius of the two 90 degree bends


hp_i0 = elem_index("hairpin1")
hp_sign = 1 if ELEMS[hp_i0]["angle"] > 0 else -1   # the return road lies on this side
pz_s_in = ts("plaza", PASSAGE_ENTRY)
P0 = point_at(pz_s_in)
t0 = tangent_at(pz_s_in)
n_in = mul(nrm(t0), hp_sign)
ret_s0 = ts("return", 0.0)
ret_cands = [ret_s0 + k * 0.5 for k in range(0, 200)]
gap_mid = None
best_ = (1e9, None)
for sv in ret_cands:  # return-road point level with P0 + PASSAGE_RUN forward
    q = point_at(sv)
    along = dot(sub(q, P0), t0)
    if abs(along - (PASSAGE_RUN + 6.0)) < best_[0]:
        best_ = (abs(along - (PASSAGE_RUN + 6.0)), sv)
V3s = best_[1]
V3 = point_at(V3s)
sep_ = dot(sub(V3, P0), n_in)
plaza_wall = hw_at(pz_s_in) + CURB
ret_wall = hw_at(V3s) + CURB
lane = (plaza_wall + (sep_ - ret_wall)) * 0.5          # middle of the keep wing
V1 = add(add(P0, mul(t0, 6.0)), mul(n_in, lane))
V2 = add(V1, mul(t0, PASSAGE_RUN))
V2 = add(P0, add(mul(t0, dot(sub(V3, P0), t0)), mul(n_in, lane)))
pz_s_out = V3s + 9.0
T_ = point_at(pz_s_out)
passage_ctrl = fillet([P0, V1, V2, V3, T_], [0, 7.0, RB, RB, 0])
pz_s_out = s_of(T_)
Lp, passage_pts = branch_len(passage_ctrl, 4)
PASSAGE_HW = 2.25
print("passage: keep wing %.1f m wide (walls at %.1f and %.1f of %.1f), lane at %.1f" % (sep_ - ret_wall - plaza_wall, plaza_wall, sep_ - ret_wall, sep_, lane))

# ------------------------------------------------------------------ moat hazard
# Main open edge: the inside (left) of the moat sweeper and the wall run.
open_s0 = ts("moat_sweep", 0.0) + 4.0
open_s1 = ts("gate_turn", 0.0) - 2.0
open_side = -1  # inside of a left turn
# Moat lens: the main road's inner edge between where the bridge leaves and rejoins the main
# corridor, closed by the bridge itself (the strips below cover both sides of the bridge).
def _main_dist(p):
    sv = s_of(p)
    return ln(sub(p, point_at(sv))), sv
outside = [q for q in bridge_pts if _main_dist(q)[0] > hw_at(_main_dist(q)[1]) + CURB + 0.5]
lens_s0 = _main_dist(outside[0])[1]
lens_s1 = _main_dist(outside[-1])[1]
moat = []
k = lens_s0
while k <= lens_s1:
    moat.append(add(point_at(k), mul(normal_at(k), open_side * (hw_at(k) + CURB - 0.3))))
    k += 3.0
far = list(reversed(outside))
moat_poly = moat + far
edge_in = []
edge_out = []
k = open_s0 - 2.0
while k <= open_s1 + 2.0:
    nn_ = mul(normal_at(k), open_side)
    edge_in.append(add(point_at(k), mul(nn_, hw_at(k) + CURB - 0.3)))
    edge_out.append(add(point_at(k), mul(nn_, hw_at(k) + CURB + OPEN_EDGE_REACH + 1.5)))
    k += 3.0
edge_strip = edge_in + list(reversed(edge_out))
# a strip along the whole bridge (both sides) so every point of its open corridor is water
strip_l = [add(q, mul(nrm(norm(sub(bridge_pts[min(i + 1, len(bridge_pts) - 1)], bridge_pts[max(i - 1, 0)]))), BRIDGE_HW + OPEN_EDGE_REACH + 1.5)) for i, q in enumerate(bridge_pts)]
strip_r = [add(q, mul(nrm(norm(sub(bridge_pts[min(i + 1, len(bridge_pts) - 1)], bridge_pts[max(i - 1, 0)]))), -(BRIDGE_HW + OPEN_EDGE_REACH + 1.5))) for i, q in enumerate(bridge_pts)]
bridge_strip = strip_l[::3] + [strip_l[-1]] + list(reversed(strip_r[::3] + [strip_r[-1]]))

# ------------------------------------------------------------------ pads, items
def lat_of(p, s):
    return dot(sub(p, point_at(s)), normal_at(s))


hp1_end = ts("return", 0.0)
hp2_end = ts("free_a", 0.0)
pads = []
# outside exit of hairpin 1 (left hairpin: outside = +side), outside exit of hairpin 2 (right: -side)
pads.append(("", hp1_end + 6.0, -hp_sign * 0.5 * hw_at(hp1_end + 6.0), 6.0, 3.0))
pads.append(("", hp2_end + 6.0, -0.5 * hw_at(hp2_end + 6.0), 6.0, 3.0))
# drawbridge landing (on the arch road just after the bridge joins) and passage exit
pads.append(("drawbridge", Lb - 14.0, 0.0, 5.0, 3.0))
pads.append(("secret_passage", Lp - 6.0, 0.0, 6.0, 4.0))

items = []
row1 = 250.0
for lat in (-4.5, -1.5, 1.5, 4.5):
    items.append((row1, lat * hw_at(row1) / 7.0))
row2 = (lane_s_in + lane_s_out) * 0.5
items.append((row2, lat_of(point_at(row2), row2)))  # main lane centerline is the main centerline
items.append((row2, lat_of(lane_cps[len(lane_cps) // 2], row2)))
row3 = ts("plaza", 0.8)
for lat in (-7.5, -2.5, 2.5, 7.5):
    items.append((row3, lat))

# ------------------------------------------------------------------ report
print("main length %.1f m (turtle %.1f), control points %d, free straights %.1f / %.1f" % (LENGTH, TURTLE_LEN, len(cps), la, lb))
for i, e in enumerate(ELEMS):
    if e.get("corner"):
        print("  corner %-22s s=%6.1f  R=%5.1f  %+5.0f deg  hw %.1f" % (e["corner"] + (" R" if e["angle"] > 0 else " L"), ts(e["tag"]) if e.get("tag") else -1, e["radius"], e["angle"], e["hw"]))
zone_s = {}
for i, e in enumerate(ELEMS):
    z = e["zone"]
    s = dense[starts[i]]["s"]
    zone_s.setdefault(z, [s, s])
    zone_s[z][1] = dense[starts[i + 1] - 1]["s"]
print("zones (turtle m):", {z: (round(v[0]), round(v[1])) for z, v in zone_s.items()})
print("lane split s %.1f..%.1f (main %.1f m) lane %.1f m ratio %.3f" % (lane_s_in, lane_s_out, lane_s_out - lane_s_in, Ll, (lane_s_out - lane_s_in) / Ll))
print("drawbridge s %.1f..%.1f (main %.1f m) branch %.1f m ratio %.2f saves %.1f m" % (br_s_in, br_s_out, br_s_out - br_s_in, Lb, (br_s_out - br_s_in) / Lb, br_s_out - br_s_in - Lb))
print("passage s %.1f..%.1f (main %.1f m) branch %.1f m ratio %.2f saves %.1f m" % (pz_s_in, pz_s_out, pz_s_out - pz_s_in, Lp, (pz_s_out - pz_s_in) / Lp, pz_s_out - pz_s_in - Lp))
print("open edge s %.1f..%.1f side %d" % (open_s0, open_s1, open_side))

# ------------------------------------------------------------------ scenery anchors
def zone_range(z):
    a, b = zone_s[z]
    return (s_of(dense[int(a / STEP)]["p"]), s_of(dense[min(int(b / STEP), N - 1)]["p"]))


hp_i = elem_index("hairpin1")
hp_e = ELEMS[hp_i]
hs0 = dense[starts[hp_i]]
statue = add(hs0["p"], mul(nrm(dirv(hs0["h"])), hp_sign * hp_e["radius"]))  # hairpin 1 center
h2_i = elem_index("hairpin2")
h2s = dense[starts[h2_i]]
hairpin2_center = add(h2s["p"], mul(nrm(dirv(h2s["h"])), ELEMS[h2_i]["radius"]))
sw1 = ELEMS[elem_index("sweep1")]
s1s = dense[starts[elem_index("sweep1")]]
lists_center = add(s1s["p"], mul(nrm(dirv(s1s["h"])), sw1["radius"]))
well_p = dense[starts[elem_index("well")] + int(6 / STEP)]
well = add(well_p["p"], mul(nrm(dirv(well_p["h"])), 0.0))
# keep: beyond the hairpin's far side, away from the plaza
keep = add(statue, mul(dirv(hs0["h"]), hp_e["radius"] + 34.0))
s3 = ELEMS[elem_index("sweep3")]
s3s = dense[starts[elem_index("sweep3")]]
orchard_center = add(s3s["p"], mul(nrm(dirv(s3s["h"])), s3["radius"]))
gate_p = point_at(ts("gate_arch", 0.5))
bounds_min = (min(p_[0] for p_ in pts), min(p_[1] for p_ in pts))
bounds_max = (max(p_[0] for p_ in pts), max(p_[1] for p_ in pts))
windmill = (bounds_max[0] + 90.0, bounds_min[1] - 40.0)
trebuchet = add(orchard_center, (0.0, 0.0))

PLOT = os.environ.get("PLOT")
if PLOT:
    from PIL import Image, ImageDraw
    sc = 1.6
    W = int((bounds_max[0] - bounds_min[0] + 80) * sc)
    H = int((bounds_max[1] - bounds_min[1] + 80) * sc)
    img = Image.new("RGB", (W, H), (60, 110, 50))
    dr = ImageDraw.Draw(img)
    T = lambda q: ((q[0] - bounds_min[0] + 40) * sc, (q[1] - bounds_min[1] + 40) * sc)
    dr.polygon([T(q) for q in moat_poly], fill=(40, 90, 170))
    dr.polygon([T(q) for q in bridge_strip], outline=(40, 140, 220))
    for i in range(len(pts)):
        a = pts[i]
        b = pts[(i + 1) % len(pts)]
        nn = nrm(norm(sub(b, a)))
        w = pts_hw[i]
        dr.polygon([T(add(a, mul(nn, w))), T(add(b, mul(nn, w))), T(add(b, mul(nn, -w))), T(add(a, mul(nn, -w)))], fill=(120, 115, 105))
    for pl, col, w in ((lane_cps, (200, 180, 120), SPLIT_LANE_HW), (bridge_pts, (150, 100, 50), BRIDGE_HW), (passage_pts, (90, 90, 90), PASSAGE_HW)):
        o = spline_open(pl, 4) if pl is lane_cps else pl
        for i in range(len(o) - 1):
            dr.line([T(o[i]), T(o[i + 1])], fill=col, width=int(2 * w * sc))
    for s_ in range(0, int(LENGTH), 50):
        dr.text(T(point_at(s_)), str(s_), fill=(255, 255, 255))
    dr.line([T(add(point_at(0), mul(normal_at(0), 10))), T(add(point_at(0), mul(normal_at(0), -10)))], fill=(255, 255, 255), width=3)
    for q in (statue, keep, well, windmill, lists_center, orchard_center):
        dr.ellipse([T(sub(q, (3, 3))), T(add(q, (3, 3)))], fill=(230, 60, 30))
    for it in items:
        q = add(point_at(it[0]), mul(normal_at(it[0]), it[1]))
        dr.rectangle([T(sub(q, (1, 1))), T(add(q, (1, 1)))], fill=(255, 140, 0))
    for pd_ in pads:
        if pd_[0] == "":
            q = add(point_at(pd_[1]), mul(normal_at(pd_[1]), pd_[2]))
        else:
            q = passage_pts[min(int(pd_[1] / Lp * (len(passage_pts) - 1)), len(passage_pts) - 1)]
        dr.rectangle([T(sub(q, (2, 2))), T(add(q, (2, 2)))], fill=(0, 255, 255))
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


_root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
for _need in ("src/track/track_hazard.gd", "src/track/track_pad.gd"):
    if not os.path.exists(os.path.join(_root, _need)):
        raise SystemExit("refusing to write: %s does not exist yet (round-2 model not in place)" % _need)
out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "tracks", "castle_circuit")
os.makedirs(out, exist_ok=True)
subs = []
subs.append("""[sub_resource type="Resource" id="Branch_lane"]
script = ExtResource("2_branch")
id = &"village_lane"
type = &"lane_split"
control_points = %s
half_width = %.2f
half_widths = %s
curb_width = 0.6
s_in = %.3f
s_out = %.3f
samples_per_segment = 8
deck_color = Color(0.46, 0.42, 0.37, 1)
deck_alt_color = Color(0.43, 0.39, 0.34, 1)
wall_color = Color(0.55, 0.38, 0.22, 1)
wall_alt_color = Color(0.48, 0.33, 0.19, 1)
wall_height = 0.9
""" % (v2(lane_cps), SPLIT_LANE_HW, f32(lane_hw), lane_s_in, lane_s_out))
subs.append("""[sub_resource type="Resource" id="Branch_bridge"]
script = ExtResource("2_branch")
id = &"drawbridge"
type = &"drawbridge"
control_points = %s
half_width = %.2f
curb_width = 0.0
open_edge_reach = %.2f
s_in = %.3f
s_out = %.3f
samples_per_segment = 12
deck_color = Color(0.55, 0.36, 0.2, 1)
deck_alt_color = Color(0.46, 0.29, 0.16, 1)
wall_color = Color(0.4, 0.26, 0.14, 1)
wall_alt_color = Color(0.5, 0.33, 0.18, 1)
wall_height = 0.0
""" % (v2(bridge_ctrl), BRIDGE_HW, OPEN_EDGE_REACH, br_s_in, br_s_out))
subs.append("""[sub_resource type="Resource" id="Branch_passage"]
script = ExtResource("2_branch")
id = &"secret_passage"
type = &"secret_passage"
control_points = %s
half_width = %.2f
curb_width = 0.4
wall_drag_mult = %g
s_in = %.3f
s_out = %.3f
samples_per_segment = 4
deck_color = Color(0.3, 0.28, 0.27, 1)
deck_alt_color = Color(0.27, 0.25, 0.24, 1)
wall_color = Color(0.42, 0.4, 0.4, 1)
wall_alt_color = Color(0.36, 0.34, 0.34, 1)
wall_height = 1.3
arch_ends = true
roofed = false
""" % (v2(passage_ctrl), PASSAGE_HW, PASSAGE_WALL_DRAG, pz_s_in, pz_s_out))
subs.append("""[sub_resource type="Resource" id="Hazard_moat"]
script = ExtResource("4_hazard")
id = &"moat"
kind = &"water"
polygon = %s
""" % v2(moat_poly))
subs.append("""[sub_resource type="Resource" id="Hazard_edge"]
script = ExtResource("4_hazard")
id = &"moat_edge"
kind = &"water"
polygon = %s
""" % v2(edge_strip))
subs.append("""[sub_resource type="Resource" id="Hazard_bridge"]
script = ExtResource("4_hazard")
id = &"moat_bridge"
kind = &"water"
polygon = %s
""" % v2(bridge_strip))
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

TRES = """[gd_resource type="Resource" script_class="TrackData" load_steps=%d format=3]

[ext_resource type="Script" path="res://src/test_track/track_data.gd" id="1_data"]
[ext_resource type="Script" path="res://src/track/track_branch.gd" id="2_branch"]
[ext_resource type="Resource" path="res://assets/tracks/castle_circuit/castle_theme.tres" id="3_theme"]
[ext_resource type="Script" path="res://src/track/track_hazard.gd" id="4_hazard"]
[ext_resource type="Script" path="res://src/track/track_pad.gd" id="5_pad"]

%s
[resource]
script = ExtResource("1_data")
track_id = &"castle_circuit"
display_name = "Castle Circuit"
theme = ExtResource("3_theme")
branches = Array[ExtResource("2_branch")]([SubResource("Branch_lane"), SubResource("Branch_bridge"), SubResource("Branch_passage")])
hazards = Array[ExtResource("4_hazard")]([SubResource("Hazard_moat"), SubResource("Hazard_edge"), SubResource("Hazard_bridge")])
boost_pads = Array[ExtResource("5_pad")]([%s])
checkpoint_count = 10
item_box_spots = %s
control_points = %s
half_widths = %s
samples_per_segment = %d
road_half_width = 6.5
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
"""
with open(os.path.join(out, "castle_circuit.tres"), "w", newline="\n") as f:
    f.write(TRES % (6 + len(subs), "\n".join(subs), ", ".join(pad_ids), v2(items), v2(cps), f32(cp_hw), SPP, CURB,
                    v3([(open_s0, open_s1, open_side)]), OPEN_EDGE_REACH, SINK_TIME, RESPAWN_SPEED_FRAC,
                    RESPAWN_IMMUNITY, RESPAWN_BACK_OFF, PAD_BOOST_TIME))

zr = {"tourney": (ts("free_a"), ts("moat_sweep")), "moat": (ts("moat_sweep"), ts("village_in")),
      "village": (ts("village_in"), ts("plaza")), "keep": (ts("plaza"), ts("back_gate")),
      "gardens": (ts("back_gate"), ts("free_a"))}
print("zones (main s):", {k: (round(v[0]), round(v[1])) for k, v in zr.items()})
THEME = """[gd_resource type="Resource" script_class="TrackTheme" load_steps=2 format=3]

[ext_resource type="Script" path="res://src/track/track_theme.gd" id="1_theme"]

[resource]
script = ExtResource("1_theme")
style = &"castle"
ground_color = Color(0.36, 0.56, 0.26, 1)
ground_size = 1400.0
road_color = Color(0.5, 0.46, 0.4, 1)
curb_color_a = Color(0.9, 0.38, 0.15, 1)
curb_color_b = Color(0.95, 0.9, 0.74, 1)
wall_color_a = Color(0.66, 0.65, 0.66, 1)
wall_color_b = Color(0.56, 0.55, 0.57, 1)
wall_height = 1.1
merlon_height = 0.9
wall_thickness = 0.7
wall_stripe_segments = 1
ambient_energy = 0.55
keep_center = Vector2(%.2f, %.2f)
statue_position = Vector2(%.2f, %.2f)
well_position = Vector2(%.2f, %.2f)
lists_center = Vector2(%.2f, %.2f)
orchard_center = Vector2(%.2f, %.2f)
windmill_position = Vector2(%.2f, %.2f)
gate_position = Vector2(%.2f, %.2f)
zone_tourney = Vector2(%.2f, %.2f)
zone_moat = Vector2(%.2f, %.2f)
zone_village = Vector2(%.2f, %.2f)
zone_keep = Vector2(%.2f, %.2f)
zone_gardens = Vector2(%.2f, %.2f)
"""
with open(os.path.join(out, "castle_theme.tres"), "w", newline="\n") as f:
    vals = list(keep) + list(statue) + list(well) + list(lists_center) + list(orchard_center) + list(windmill) + list(gate_p)
    for z in ("tourney", "moat", "village", "keep", "gardens"):
        vals += list(zr[z])
    f.write(THEME % tuple(vals))
print("wrote")
