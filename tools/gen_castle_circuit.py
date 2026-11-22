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
import elevation_profile as ev

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
    A(145.5, 10.0, 7.0, 'tourney', tag='kink1', corner='kink', bank=-4.0),  # off-camber on the crest
    S(10.0, 6.5, 'tourney', tag='pre_moat'),
    A(31.3, -156.6, 6.5, 'moat', tag='moat_sweep', open=True, corner='sweeper'),
    S(34.8, 6.5, 'moat', tag='wall_run', open=True),
    A(16.0, 100.0, 6.0, 'moat', tag='gate_turn', corner='90', bank=0.0),  # moat zone stays flat
    S(24.0, 4.5, 'moat', tag='gate_arch'),
    # Story 008 part 5, the Barbican Spiral (owner's decision, crossover-decision.md): a 280 degree
    # LEFT curl around the barbican tower outside the gate, climbing, then the gate_top straight
    # runs over the gatehouse, crossing above the gate arch road it just left.
    A(16.0, -280.0, 5.5, 'village', tag='spiral', corner='spiral'),
    S(35.0, 5.5, 'village', tag='gate_top'),
    S(10.0, 5.5, 'village'),
    A(22.0, -55.9, 5.5, 'village', tag='well_s1', corner='S (well)'),
    S(10.0, 5.5, 'village', tag='well'),
    A(24.0, 55.9, 5.5, 'village', tag='well_s2', bank=-3.0),  # off-camber
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
    # The kink is two halves of one arc: the rampart jump (end of free_b) lands on the first half
    # (flat, see FLAT), the off-camber is on the second half (part 5, designer's recommendation).
    A(168.5, 10.0, 8.0, 'gardens', tag='kink2', corner='kink'),
    A(168.5, 10.0, 8.0, 'gardens', tag='kink2b', bank=-4.0),  # off-camber on the rampart
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
# Net turning of the lap. A closed road that never crosses itself turns +-360 degrees; each
# self-crossing changes that by 360, so a lap with exactly ONE crossing (the Barbican Spiral passing
# over the gate arch, story 008 part 5) turns 0 (or 720), never 360: the 280 degree left curl
# replaced a 80 degree right, 360 less.
TOTAL_TURN = 0.0
assert abs(hsum - TOTAL_TURN) < 1e-6, "turning must total %+.0f, got %s" % (TOTAL_TURN, hsum)


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
cp_turn = []
n_cp = int(round(TURTLE_LEN / CP_STEP))
for k in range(n_cp):
    idx = int(round((k * CP_STEP + LINE_SHIFT) / STEP)) % N
    dp = dense[idx]
    pt = dp["p"]
    if dp["elem"] == split_i:
        pt = add(pt, mul(nrm(dirv(dp["h"])), split_offset(dp["u"])))
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


def s_of(p, lo=None, hi=None):
    """Main-loop spline distance of the centerline point nearest p. Story 008 part 5: the loop now
    crosses itself (the Barbican Spiral over the gate arch), so a nearest point can be on the
    wrong level there; lo/hi (spline meters, lo < hi, no wrap) restrict the search to one stretch."""
    best = (1e18, 0.0)
    for i in range(len(pts)):
        if lo is not None and (cum[i + 1] < lo or cum[i] > hi):
            continue
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


def turtle_to_s(turtle_s):
    """Main-loop spline distance of turtle distance turtle_s, by index: control point k is the
    turtle sample at k * CP_STEP + LINE_SHIFT and sits at spline distance cum[k * SPP], so the
    mapping is linear between control points. Unlike a nearest-point search (s_of) it cannot pick
    the other level where the loop crosses itself (story 008 part 5)."""
    u = ((turtle_s - LINE_SHIFT) % (n_cp * CP_STEP)) / CP_STEP
    k = int(math.floor(u)) % n_cp
    f = u - math.floor(u)
    a = cum[k * SPP]
    b = cum[(k + 1) * SPP] if k + 1 < n_cp else LENGTH
    return (a + (b - a) * f) % LENGTH


def ts(tag, frac=0.0):
    """Main-loop spline distance of a turtle location (element tag, fraction)."""
    return turtle_to_s(elem_s(tag, frac))


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
    sv = s_of(p, br_s_in - 30.0, br_s_out + 10.0)  # the moat level, never the gate_top deck above
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
# Part 5: 13 m (was 6) past hairpin 2: the autopilot now leaves the hairpin wider (it arrives faster
# after the rampart jump moved onto kink2) and crossed the old pad's lane outside it.
HP2_PAD_AHEAD = 13.0
pads.append(("", hp2_end + HP2_PAD_AHEAD, -0.5 * hw_at(hp2_end + HP2_PAD_AHEAD), 6.0, 3.0))
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

# ------------------------------------------------------------------ elevation (story 008 part 4)
# Climb from the tourney field through the village up to the keep courtyard (8 m), a rampart
# wall-walk through the gardens with banked corners and a jump, back down to the field by the last
# hairpin. The moat zone (drawbridge, open edge, gatehouse) stays at ground level and flat.
cp_s = [cum[k * SPP] for k in range(len(cps))]
KEEP_H = 8.0
GATE_TOP_H = 7.12     # key height of the gatehouse deck: the blur rounds it to 7.0 over the gate arch (underside 6.4)
GATE_TOP_FROM = 0.15  # fraction of gate_top where the climb ends (the crossing is at ~0.39)
GATE_TOP_TO = 0.85    # ... and where the drop into the market starts (~70 m to the split)
MARKET_H = 4.5        # the lane split (part 4 profile at the split end)
SPIRAL_FLAT = 25.0    # meters at the start of the spiral kept unbanked (no bank lift reaches the arch)
H_KEYS = [
    (ts("free_a", 0.15), 0.0), (ts("after_line", 1.0), 0.0),
    (ts("sweep1", 0.45), 1.4), (ts("sweep1", 0.9), 1.6), (ts("kink1", 0.3), 1.2),     # tourney crest
    (br_s_in - 12.0, 0.0), (ts("spiral", 0.0), 0.0),                                    # moat, gate: ground
    # Barbican Spiral (part 5): climb 0 -> GATE_TOP_H around the barbican, level over the gate arch,
    # then drop into the market to the lane split.
    (ts("gate_top", GATE_TOP_FROM), GATE_TOP_H), (ts("gate_top", GATE_TOP_TO), GATE_TOP_H),
    (ts("split", 0.0), MARKET_H), (ts("split", 1.0), MARKET_H),                         # market, lane split
    (ts("plaza", 0.25), KEEP_H), (ts("back_gate", 0.5), KEEP_H),                        # climb to the keep
    (ts("free_b", 0.0), 7.4), (ts("kink2b", 0.0), 6.5), (ts("hook", 0.5), 4.6),         # rampart walk
    (ts("hairpin2", 0.3), 1.6), (ts("free_a", 0.0), 0.0),                               # down to the field
]
RAMP_LEN = 8.0
RAMP_LIP = 1.4
# The rampart jump (part 5): the lip RAMP_END_GAP before the end of free_b, landing on kink2's first half.
RAMP_END_GAP = 2.0
ramp_s = ts("free_b", 1.0) - RAMP_END_GAP - RAMP_LEN
FLAT = [(br_s_in - 14.0, br_s_in + 16.0), (br_s_out - 16.0, br_s_out + 14.0),
        (lane_s_in - 14.0, lane_s_in + 14.0), (lane_s_out - 14.0, lane_s_out + 14.0),
        (pz_s_in - 14.0, pz_s_in + 14.0), (pz_s_out - 16.0, pz_s_out + 14.0),
        (open_s0 - 6.0, open_s1 + 6.0), (LENGTH - 70.0, 12.0), (ramp_s - 10.0, max(ramp_s + RAMP_LEN + 18.0, ts("kink2b", 0.0))),
        (ts("spiral", 0.0) - 2.0, ts("spiral", 0.0) + SPIRAL_FLAT)]
cp_bank = ev.banks(cp_s, LENGTH, cp_turn, FLAT)
cp_h = ev.blur(ev.piecewise(cp_s, LENGTH, H_KEYS), 3)
cp_h, bank_need = ev.lift_for_banks(cp_h, cp_bank, [w + CURB for w in cp_hw])
cp_h = [round(h, 3) for h in cp_h]
ev.report("castle main", cp_s, cp_h, cp_bank, LENGTH, bool(os.environ.get("PROFILE")))


def main_h(sv):
    """Main-road centerline height at spline distance sv (linear between control points)."""
    sv %= LENGTH
    k = max(i for i in range(len(cp_s)) if cp_s[i] <= sv)
    k2 = (k + 1) % len(cp_s)
    span = (cp_s[k2] - cp_s[k]) % LENGTH
    f = (sv - cp_s[k]) / span if span > 1e-9 else 0.0
    return cp_h[k] + (cp_h[k2] - cp_h[k]) * f


# Crossover report (part 5): where the main loop passes over itself (centerlines closest with the
# two places far apart along the loop), the two heights and the clearance under the deck.
DECK_THICKNESS = 0.6  # TrackData.deck_thickness default
_xing = (1e9, 0.0, 0.0)
for _i in range(0, len(pts), 2):
    for _j in range(_i + 1, len(pts), 2):
        _ds = abs(cum[_j] - cum[_i])
        if min(_ds, LENGTH - _ds) < 60.0:
            continue
        _d = ln(sub(pts[_i], pts[_j]))
        if _d < _xing[0]:
            _xing = (_d, cum[_i], cum[_j])
_lo_s, _hi_s = sorted((_xing[1], _xing[2]), key=main_h)
_g_up = max(abs(main_h(sv + 1.0) - main_h(sv)) for sv in [ts("spiral", 0.0) + k for k in range(int(ts("gate_top", 0.5) - ts("spiral", 0.0)))])
print("crossover: lower s %.1f h %.2f, upper s %.1f h %.2f, centerlines %.2f m apart, deck underside %.2f, clearance %.2f m; "
      "spiral s %.1f..%.1f (h %.2f..%.2f, mid %.2f), gate_top s %.1f..%.1f, max climb grade %.1f %%, market split h %.2f" % (
          _lo_s, main_h(_lo_s), _hi_s, main_h(_hi_s), _xing[0], main_h(_hi_s) - DECK_THICKNESS,
          main_h(_hi_s) - DECK_THICKNESS - main_h(_lo_s), ts("spiral", 0.0), ts("gate_top", 0.0), main_h(ts("spiral", 0.0)),
          main_h(ts("gate_top", 0.0)), main_h(ts("spiral", 0.5)), ts("gate_top", 0.0), ts("gate_top", 1.0), 100 * _g_up,
          main_h(ts("split", 0.0))))
CROSS_LOW_S, CROSS_HIGH_S = _lo_s, _hi_s


# The drawbridge water strip must not claim the spiral top (part 5): where a strip corner lies within
# STRIP_CLEAR of the corridor of main road raised LEVEL_SEP or more (the spiral, 6+ m beside the
# landing), it is pulled back toward the bridge until clear. The road up there always wins.
LEVEL_SEP = 3.0     # TrackData.level_separation default
STRIP_CLEAR = 1.0
_high = [k for k in range(len(pts)) if main_h(cum[k]) >= LEVEL_SEP]


def _high_excess(q):
    best = 1e9
    for k in _high:
        best = min(best, ln(sub(q, pts[k])) - pts_hw[k] - CURB)
    return best


_trimmed = 0
for _side in (strip_l, strip_r):
    for _i, _q in enumerate(_side):
        _c = bridge_pts[_i]
        _f = 1.0
        while _high_excess(add(_c, mul(sub(_q, _c), _f))) < STRIP_CLEAR and _f > 0.3:
            _f -= 0.05
        if _f < 1.0:
            _side[_i] = add(_c, mul(sub(_q, _c), _f))
            _trimmed += 1
bridge_strip = strip_l[::3] + [strip_l[-1]] + list(reversed(strip_r[::3] + [strip_r[-1]]))
print("drawbridge strip: %d corners pulled back from the spiral top; nearest strip corner %.1f m outside its corridor" % (_trimmed, min(_high_excess(q) for q in bridge_strip)))


# ------------------------------------------------------------------ drawbridge deck span (story 009)
# The movable deck: the stretch of the bridge branch that lies over the moat (outside the main
# road's corridor by more than DECK_OUT_MARGIN) and is straight. Its far end (toward the gatehouse)
# is the hinge. Distances are meters along the branch (TrackBranch path distance).
DECK_OUT_MARGIN = float(os.environ.get("DECK_OUT_MARGIN", "1.0"))
_bcum = [0.0]
for _i in range(1, len(bridge_pts)):
    _bcum.append(_bcum[-1] + ln(sub(bridge_pts[_i], bridge_pts[_i - 1])))


def _main_excess(q):
    return min(ln(sub(q, pts[k])) - pts_hw[k] - CURB for k in range(0, len(pts)))


_bex = [_main_excess(q) for q in bridge_pts]
_dir_str = norm(sub(V2b, V1b))   # the straight plank between the entry arc and the landing arc
DECK_STRAIGHT_DEG = float(os.environ.get("DECK_STRAIGHT_DEG", "2.0"))
_over = []
for _i in range(1, len(bridge_pts) - 1):
    _h = norm(sub(bridge_pts[_i + 1], bridge_pts[_i - 1]))
    _ang = math.degrees(math.acos(max(-1.0, min(1.0, dot(_h, _dir_str)))))
    if _bex[_i] > DECK_OUT_MARGIN and _ang < DECK_STRAIGHT_DEG:
        _over.append(_i)
DECK_LENGTH = float(os.environ.get("DECK_LENGTH", "18.0"))   # the raised deck is this tall (m): short, so it reads as a leaf
DECK_TO = _bcum[_over[-1]]
DECK_FROM = max(_bcum[_over[0]], DECK_TO - DECK_LENGTH)
# The signal posts stand at the branch entrance (first point clearly over the water), so a kart
# reads the lantern before it commits to the bridge.
DECK_SIGNAL_EXCESS = float(os.environ.get("DECK_SIGNAL_EXCESS", "3.0"))
DECK_SIGNAL = next(_bcum[i] for i in range(len(bridge_pts)) if _bex[i] > DECK_SIGNAL_EXCESS)
print("drawbridge deck span %.1f..%.1f of %.1f m branch (%.1f m long, straight, over water)" % (DECK_FROM, DECK_TO, _bcum[-1], DECK_TO - DECK_FROM))


# The village lane runs beside the main lane: same height at the same place, so a kart changing
# lane or merging meets no step (the default branch blend would differ from the main climb).
lane_heights = [round(main_h(s_of(q)), 3) for q in lane_cps]


# ------------------------------------------------------------------ surface zones (story 011 part 2)
# Off-road ground beside the road (reached through wall openings), a ford through the moat and an
# on-road slick patch. Every zone vertex carries its own height (TrackSurface.heights): the height of
# the road edge it sits on (with the bank), so a zone beside a climbing or banked road meets the curb
# without a step. Outer vertices take the height of the nearest road-edge vertex.
def bank_deg_at(sv):
    """Main-road bank (degrees, TrackModel sign) at spline distance sv (linear between control points)."""
    sv %= LENGTH
    k = max(i for i in range(len(cp_s)) if cp_s[i] <= sv)
    k2 = (k + 1) % len(cp_s)
    span = (cp_s[k2] - cp_s[k]) % LENGTH
    f = (sv - cp_s[k]) / span if span > 1e-9 else 0.0
    return cp_bank[k] + (cp_bank[k2] - cp_bank[k]) * f


def edge_pt(sv, side, inset=0.3):
    """Point on the main road's curb edge on [side] at sv, [inset] meters inside the curb, and its height."""
    lat = side * (hw_at(sv) + CURB - inset)
    return add(point_at(sv), mul(normal_at(sv), lat)), main_h(sv) + lat * math.tan(math.radians(bank_deg_at(sv)))


def curb_run(s0, s1, side, step=3.0):
    """Curb-edge points (and heights) from s0 to s1 (s1 > s0, may pass LENGTH)."""
    out = []
    n = max(int(math.ceil((s1 - s0) / step)), 1)
    for k in range(n + 1):
        out.append(edge_pt(s0 + (s1 - s0) * k / n, side))
    return out


def nearest_h(p, edge):
    return min(edge, key=lambda e: ln(sub(e[0], p)))[1]


surf_zones = []      # (id, kind, polygon, heights, fence)
surf_openings = []   # (s_from, s_to, side, depth)
surf_routes = {}     # id -> (route_from, route_to, boost_cut): TrackSurface route fields
surf_via = {}        # id -> waypoints across the zone (TrackSurface.route_via)
SURF_OPEN_DEPTH = 60.0

# 1. Tourney turf: grass inside the jousting-field sweeper (sweep1, a 130 degree right around the
# lists), a circular segment between the inner curb and the chord. Cutting across it is shorter than
# the road but the grass caps the speed: it pays only with a boost (drift boost, pad or War Horn).
TURF_FROM = float(os.environ.get("TURF_FROM", "0.06"))   # fractions of sweep1 where the patch meets the curb
TURF_TO = float(os.environ.get("TURF_TO", "0.94"))
_t0, _t1 = ts("sweep1", TURF_FROM), ts("sweep1", TURF_TO)
_turf = curb_run(_t0, _t1, 1, 3.0)
surf_zones.append(("tourney_turf", "grass", [e[0] for e in _turf], [e[1] for e in _turf], True))
surf_openings.append((_t0 - 1.0, _t1 + 1.0, 1, SURF_OPEN_DEPTH))
TURF_CHORD = ln(sub(_turf[0][0], _turf[-1][0]))
TURF_ROUTE_IN = 2.0    # the route starts this far before the patch and heads for the road this far past it
TURF_ROUTE_OUT = 4.0
surf_routes["tourney_turf"] = (_t0 - TURF_ROUTE_IN, _t1 + TURF_ROUTE_OUT, True)

# 2. Kennel yard: mud on the outside of the hairpin 2 exit, beside the free_a straight (where a kart
# runs wide out of the hairpin).
YARD_FROM = float(os.environ.get("YARD_FROM", "4.0"))     # meters past the hairpin end
YARD_LEN = float(os.environ.get("YARD_LEN", "30.0"))
YARD_DEPTH = float(os.environ.get("YARD_DEPTH", "11.0"))  # meters from the curb out
_y0 = hp2_end + YARD_FROM
_y1 = _y0 + YARD_LEN
_yard_in = curb_run(_y0, _y1, -1, 3.0)
# The far edge is shorter than the curb edge by YARD_TAPER at each end: the end fences slant back to
# the road, so a kart running along the yard is steered out instead of stopped head-on.
YARD_TAPER = float(os.environ.get("YARD_TAPER", "8.0"))
_yo0, _yo1 = _y0 + YARD_TAPER, _y1 - YARD_TAPER
_yard_out = [(add(point_at(_yo1 - (_yo1 - _yo0) * k / 6), mul(normal_at(_yo1 - (_yo1 - _yo0) * k / 6),
                                                              -(hw_at(_yo1 - (_yo1 - _yo0) * k / 6) + CURB + YARD_DEPTH))), None)
             for k in range(7)]
_yard_poly = [e[0] for e in _yard_in] + [e[0] for e in _yard_out]
_yard_h = [e[1] for e in _yard_in] + [nearest_h(e[0], _yard_in) for e in _yard_out]
surf_zones.append(("kennel_yard", "mud", _yard_poly, _yard_h, True))
surf_openings.append((_y0 - 1.0, _y1 + 1.0, -1, SURF_OPEN_DEPTH))

# 3. Moat shallows: a fenced ford through the moat beside the drawbridge, on the moat (lens) side of
# it, following the bridge at FORD_OFFSET. Slow (shallow water) but it never sinks: the way across
# while the bridge is up. Its two ends meet the main road's inner (moat) edge; its sides are fenced.
# Kept clear of the bridge's corridor (BRIDGE_HW + OPEN_EDGE_REACH) so a kart in the ford is never
# taken for a kart on the bridge, and the wall openings toward it are only as deep as the ford needs
# (per stretch), so the main road's corridor never reaches the bridge.
FORD_OFFSET = float(os.environ.get("FORD_OFFSET", "12.5"))  # ford centerline from the bridge centerline (m)
FORD_HW = float(os.environ.get("FORD_HW", "3.0"))           # ford half width (m)
# m between the ford and the bridge deck. A kart in the ford is held by the ford's fences and belongs
# to the main road (TrackModel.query ignores a branch it is not on the deck of while on a zone).
FORD_BRIDGE_CLEAR = float(os.environ.get("FORD_BRIDGE_CLEAR", "2.0"))
assert FORD_OFFSET - FORD_HW >= BRIDGE_HW + FORD_BRIDGE_CLEAR


def _in_poly(p, poly):
    c = False
    j = len(poly) - 1
    for i in range(len(poly)):
        if (poly[i][1] > p[1]) != (poly[j][1] > p[1]) and                 p[0] < (poly[j][0] - poly[i][0]) * (p[1] - poly[i][1]) / (poly[j][1] - poly[i][1]) + poly[i][0]:
            c = not c
        j = i
    return c


def _bnorm(i):
    a_ = bridge_pts[max(i - 1, 0)]
    b_ = bridge_pts[min(i + 1, len(bridge_pts) - 1)]
    return nrm(norm(sub(b_, a_)))


_im = len(bridge_pts) // 2
_sg = 1.0 if _main_dist(add(bridge_pts[_im], mul(_bnorm(_im), FORD_OFFSET)))[0] <     _main_dist(add(bridge_pts[_im], mul(_bnorm(_im), -FORD_OFFSET)))[0] else -1.0


def _ford_pts(i):
    n_ = mul(_bnorm(i), _sg)
    return add(bridge_pts[i], mul(n_, FORD_OFFSET - FORD_HW)), add(bridge_pts[i], mul(n_, FORD_OFFSET + FORD_HW))


def _outside_main(q):
    d, sv = _main_dist(q)
    return d > hw_at(sv) + CURB - 0.3


# The ford peels off the road's moat-side lane tangentially (a Hermite curve over FORD_LEAD meters of
# road), runs parallel to the bridge in the middle, and merges back the same way, so a kart can drive
# in at speed. Its road-side edge is clamped to the curb where it is still over the road: the mouths
# are long tapers along the curb.
FORD_MID_CLEAR = float(os.environ.get("FORD_MID_CLEAR", "4.0"))  # middle: the road-side edge this far past the curb
FORD_LEAD = float(os.environ.get("FORD_LEAD", "24.0"))           # meters of road over which it peels off / merges
FORD_LANE = float(os.environ.get("FORD_LANE", "2.5"))            # its centerline starts this far inside the road edge
# Where the road-side edge is less than this past the curb it is put on the curb: no thin strip of
# moat between the road and the ford (a kart taking the ford wide would drop into it).
FORD_SLIVER = float(os.environ.get("FORD_SLIVER", "3.0"))


def _excess_main(q):
    d, sv = _main_dist(q)
    return d - hw_at(sv) - CURB, sv


def _longest_run(flags):
    runs = []
    i = 0
    while i < len(flags):
        if flags[i]:
            j = i
            while j + 1 < len(flags) and flags[j + 1]:
                j += 1
            runs.append((i, j))
            i = j + 1
        else:
            i += 1
    return max(runs, key=lambda r: r[1] - r[0])


def _bcen(i):
    return add(bridge_pts[i], mul(mul(_bnorm(i), _sg), FORD_OFFSET))


def _btan(i):
    return norm(sub(bridge_pts[min(i + 1, len(bridge_pts) - 1)], bridge_pts[max(i - 1, 0)]))


def _hermite(p0, t0, p1, t1, step=1.0):
    L = ln(sub(p1, p0))
    n = max(int(L / step), 2)
    out = []
    for k in range(n):
        u = k / n
        h00, h10, h01, h11 = 2 * u ** 3 - 3 * u ** 2 + 1, u ** 3 - 2 * u ** 2 + u, -2 * u ** 3 + 3 * u ** 2, u ** 3 - u ** 2
        out.append(add(add(mul(p0, h00), mul(t0, h10 * L)), add(mul(p1, h01), mul(t1, h11 * L))))
    return out


_m0, _m1 = _longest_run([_excess_main(_ford_pts(i)[1])[0] > FORD_MID_CLEAR for i in range(len(bridge_pts))])
_sa = _main_dist(_bcen(_m0))[1] - FORD_LEAD
_sb = _main_dist(_bcen(_m1))[1] + FORD_LEAD
_P0 = add(point_at(_sa), mul(normal_at(_sa), open_side * (hw_at(_sa) - FORD_LANE)))
_P3 = add(point_at(_sb), mul(normal_at(_sb), open_side * (hw_at(_sb) - FORD_LANE)))
_C = _hermite(_P0, tangent_at(_sa), _bcen(_m0), _btan(_m0)) + [_bcen(i) for i in range(_m0, _m1 + 1)]     + _hermite(_bcen(_m1), _btan(_m1), _P3, tangent_at(_sb))[1:] + [_P3]


def _ctan(k):
    return norm(sub(_C[min(k + 1, len(_C) - 1)], _C[max(k - 1, 0)]))


_CA = [add(_C[k], mul(nrm(_ctan(k)), -_sg * FORD_HW)) for k in range(len(_C))]   # bridge side
_CB = [add(_C[k], mul(nrm(_ctan(k)), _sg * FORD_HW)) for k in range(len(_C))]    # road side
# Off the road on its bridge side, and clear of the bridge deck.
_bmin = BRIDGE_HW + FORD_BRIDGE_CLEAR
_kA, _kE = _longest_run([_excess_main(q)[0] > -0.3 and min(ln(sub(q, b_)) for b_ in bridge_pts) >= _bmin for q in _CA])
_A = []
_B = []
_Ah = []
_Bh = []
for _k in range(_kA, _kE + 1):
    _A.append(_CA[_k])
    _Ah.append(edge_pt(_main_dist(_CA[_k])[1], open_side)[1])
    _ex, _sv = _excess_main(_CB[_k])
    if _ex > FORD_SLIVER:
        _B.append(_CB[_k])
        _Bh.append(edge_pt(_sv, open_side)[1])
    else:
        _e = edge_pt(_sv, open_side)
        _B.append(_e[0])
        _Bh.append(_e[1])
_ford_poly = _A + list(reversed(_B))
_ford_h = _Ah + list(reversed(_Bh))
surf_zones.append(("moat_shallows", "shallows", _ford_poly, _ford_h, True))
FORD_LEN = sum(ln(sub(_C[k + 1], _C[k])) for k in range(_kA, _kE))
_bridge_gap = min(min(ln(sub(q, b_)) for b_ in bridge_pts) for q in _CA[_kA:_kE + 1])
assert _bridge_gap >= _bmin, "ford too close to the bridge deck (%.2f m)" % _bridge_gap
# Openings: per FORD_CHUNK meters of main road, as deep as the ford reaches beyond the curb there.
FORD_CHUNK = 6.0
FORD_DEPTH_MARGIN = 1.5
_reach = {}
_xs = [q[0] for q in _ford_poly]
_zs = [q[1] for q in _ford_poly]
_gx = min(_xs)
while _gx <= max(_xs):
    _gz = min(_zs)
    while _gz <= max(_zs):
        if _in_poly((_gx, _gz), _ford_poly):
            d, sv = _main_dist((_gx, _gz))
            k = int(sv // FORD_CHUNK)
            _reach[k] = max(_reach.get(k, 0.0), d - hw_at(sv) - CURB)
        _gz += 0.5
    _gx += 0.5
_ford_open = []
for k in sorted(_reach):
    surf_openings.append((k * FORD_CHUNK, (k + 1) * FORD_CHUNK, open_side, max(_reach[k], 0.0) + FORD_DEPTH_MARGIN))
    _ford_open.append((k * FORD_CHUNK, max(_reach[k], 0.0) + FORD_DEPTH_MARGIN))
# The bridge must stay outside the main corridor where the openings widen it.
_bridge_margin = 1e9
for q in bridge_pts:
    d, sv = _main_dist(q)
    k = int(sv // FORD_CHUNK)
    if k in _reach:
        _bridge_margin = min(_bridge_margin, d - hw_at(sv) - CURB - (_reach[k] + FORD_DEPTH_MARGIN))
FORD_S = (_main_dist(_A[0])[1], _main_dist(_A[-1])[1])
FORD_ROUTE_IN = 4.0    # the route starts this far before the ford peels off and heads for the road this far past its merge
FORD_ROUTE_OUT = 6.0
FORD_VIA_STEP = 8.0    # meters between the route's waypoints along the ford's centerline
_via = []
_acc = FORD_VIA_STEP
for _k in range(1, len(_C)):
    _acc += ln(sub(_C[_k], _C[_k - 1]))
    if _acc >= FORD_VIA_STEP:
        _acc = 0.0
        _via.append(_C[_k])
surf_via["moat_shallows"] = _via
surf_routes["moat_shallows"] = (_sa - FORD_ROUTE_IN, _sb + FORD_ROUTE_OUT, False)
print("ford: peels off s %.1f, merges s %.1f, off the road s %.1f..%.1f, %.1f m long, %.1f m from the bridge centerline at least; openings %s; bridge clear of the widened main corridor by %.1f m" % (
      _sa, _sb, FORD_S[0], FORD_S[1], FORD_LEN, _bridge_gap, ["%.0f:%.1f" % o for o in _ford_open], _bridge_margin))

# 4. Spilled ale: a slick patch on the main lane of the village lane split (outside the tavern), so a
# kart can take the other lane to avoid it.
ALE_AT = float(os.environ.get("ALE_AT", "0.55"))    # fraction of the split straight
ALE_LEN = float(os.environ.get("ALE_LEN", "9.0"))
ALE_INSET = float(os.environ.get("ALE_INSET", "0.6"))  # meters inside the road edge on each side
_a0 = ts("split", ALE_AT)
_a1 = _a0 + ALE_LEN
_ale = []
for sv, lat_sign in ((_a0, -1), (_a1, -1), (_a1, 1), (_a0, 1)):
    lat = lat_sign * (hw_at(sv) - ALE_INSET)
    _ale.append((add(point_at(sv), mul(normal_at(sv), lat)), main_h(sv) + lat * math.tan(math.radians(bank_deg_at(sv)))))
surf_zones.append(("ale_spill", "slick", [e[0] for e in _ale], [e[1] for e in _ale], False))
SURF_PLOT = [(z[0], z[2]) for z in surf_zones]
print("surfaces: turf s %.1f..%.1f chord %.1f m (road arc %.1f m); yard s %.1f..%.1f; ford s %.1f..%.1f (%.1f m, offset %.1f "
      "from the bridge); ale s %.1f..%.1f h %.2f" % (_t0, _t1, TURF_CHORD, _t1 - _t0, _y0, _y1, FORD_S[0], FORD_S[1], FORD_LEN,
                                                  FORD_OFFSET, _a0, _a1, main_h(_a0)))
for z in surf_zones:
    print("  zone %-14s %-8s %d points, h %.2f..%.2f" % (z[0], z[1], len(z[2]), min(z[3]), max(z[3])))

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
# Story 008 part 5: the barbican tower stands at the centre of the spiral (a left curl: centre on -side).
sp_i = elem_index("spiral")
sps = dense[starts[sp_i]]
barbican = add(sps["p"], mul(nrm(dirv(sps["h"])), -ELEMS[sp_i]["radius"]))
bounds_min = (min(p_[0] for p_ in pts), min(p_[1] for p_ in pts))
bounds_max = (max(p_[0] for p_ in pts), max(p_[1] for p_ in pts))
windmill = (bounds_max[0] + 90.0, bounds_min[1] - 40.0)
trebuchet = add(orchard_center, (0.0, 0.0))

PLOT = os.environ.get("PLOT")
if PLOT:
    from PIL import Image, ImageDraw
    sc = float(os.environ.get("PLOT_SCALE", "1.6"))
    if os.environ.get("PLOT_GATE"):  # zoom on the Barbican Spiral and the gate
        bounds_min = (barbican[0] - 70.0, barbican[1] - 70.0)
        bounds_max = (barbican[0] + 70.0, barbican[1] + 70.0)
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
    for s_ in range(0, int(LENGTH), 10 if os.environ.get("PLOT_GATE") else 50):
        dr.text(T(point_at(s_)), str(s_), fill=(255, 255, 255))
    dr.line([T(add(point_at(0), mul(normal_at(0), 10))), T(add(point_at(0), mul(normal_at(0), -10)))], fill=(255, 255, 255), width=3)
    for q in (statue, keep, well, windmill, lists_center, orchard_center, barbican):
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
for _need in ("src/track/track_hazard.gd", "src/track/track_pad.gd", "src/track/track_mover.gd"):
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
heights = %s
""" % (v2(lane_cps), SPLIT_LANE_HW, f32(lane_hw), lane_s_in, lane_s_out, f32(lane_heights)))
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
# Drawbridge timer (story 009): down 12 s, raised 8 s (the rise starts at second 12 of the 20 s
# cycle, takes 1.2 s; the horn and the flashing lantern warn 1.5 s before). PHASE shifts the cycle.
DRAW_PERIOD = float(os.environ.get("DRAW_PERIOD", "20.0"))
DRAW_ACTIVE_START = float(os.environ.get("DRAW_ACTIVE_START", "12.0"))
DRAW_ACTIVE_TIME = float(os.environ.get("DRAW_ACTIVE_TIME", "8.0"))
DRAW_TRANSITION = float(os.environ.get("DRAW_TRANSITION", "1.2"))
DRAW_WARNING = float(os.environ.get("DRAW_WARNING", "1.5"))
DRAW_PHASE = float(os.environ.get("DRAW_PHASE", "0.0"))
subs.append("""[sub_resource type="Resource" id="Mover_drawbridge"]
script = ExtResource("7_mover")
id = &"drawbridge_deck"
kind = &"gate"
period = %.2f
active_start = %.2f
active_time = %.2f
transition_time = %.2f
phase = %.2f
warning_lead = %.2f
block_progress = 0.25
path = &"drawbridge"
path_from = %.2f
path_to = %.2f
hit_effect = &"sink"
sink_kind = &"water"
visual = &"drawbridge"
raised_angle_deg = 78.0
deck_half_width = %.2f
deck_color = Color(0.55, 0.36, 0.2, 1)
deck_alt_color = Color(0.46, 0.29, 0.16, 1)
signal_along = %.2f
signal_side = 4.6
signal_height = 3.2
chain_anchor_height = 20.0
chain_anchor_beyond = 1.5
sound_warn = &"drawbridge_up"
sound_down = &"drawbridge_down"
""" % (DRAW_PERIOD, DRAW_ACTIVE_START, DRAW_ACTIVE_TIME, DRAW_TRANSITION, DRAW_PHASE, DRAW_WARNING, DECK_FROM, DECK_TO, BRIDGE_HW, DECK_SIGNAL))
# Portcullis (story 009 part 2): an iron grille across the secret passage, a little way in where
# both passage walls are clear of the plaza, on the same 20 s cycle as the drawbridge but down while
# the drawbridge is down, so the two shortcuts are never closed together. A kart is stopped
# against it (a wall, not a sink: the passage is enclosed).
PORT_CLEAR = float(os.environ.get("PORT_CLEAR", "1.0"))    # m the passage walls must be off the plaza
PORT_INSET = float(os.environ.get("PORT_INSET", "2.0"))    # m further in from there
PORT_THICK = 0.6                                           # m of road the grille covers
PORT_PERIOD = float(os.environ.get("PORT_PERIOD", str(DRAW_PERIOD)))
PORT_ACTIVE_START = float(os.environ.get("PORT_ACTIVE_START", "3.5"))
PORT_ACTIVE_TIME = float(os.environ.get("PORT_ACTIVE_TIME", "5.5"))
PORT_TRANSITION = float(os.environ.get("PORT_TRANSITION", "0.8"))
PORT_WARNING = float(os.environ.get("PORT_WARNING", "1.5"))
PORT_PHASE = float(os.environ.get("PORT_PHASE", "0.0"))
_pcum = [0.0]
for _i in range(1, len(passage_pts)):
    _pcum.append(_pcum[-1] + ln(sub(passage_pts[_i], passage_pts[_i - 1])))
_pex = [_main_excess(q) for q in passage_pts]
PORT_FROM = next(_pcum[i] for i in range(len(passage_pts)) if _pex[i] > PASSAGE_HW + 0.4 + PORT_CLEAR) + PORT_INSET
PORT_TO = PORT_FROM + PORT_THICK
print("portcullis at %.1f..%.1f of %.1f m passage; cycle %.0f s, down %.1f..%.1f s (drawbridge up %.1f..%.1f s)" % (
      PORT_FROM, PORT_TO, _pcum[-1], PORT_PERIOD, PORT_ACTIVE_START, PORT_ACTIVE_START + PORT_ACTIVE_TIME + PORT_TRANSITION,
      DRAW_ACTIVE_START, DRAW_ACTIVE_START + DRAW_ACTIVE_TIME + DRAW_TRANSITION))
subs.append("""[sub_resource type="Resource" id="Mover_portcullis"]
script = ExtResource("7_mover")
id = &"portcullis"
kind = &"gate"
period = %.2f
active_start = %.2f
active_time = %.2f
transition_time = %.2f
phase = %.2f
warning_lead = %.2f
block_progress = 0.25
out_of_phase_with = &"drawbridge_deck"
path = &"secret_passage"
path_from = %.2f
path_to = %.2f
hit_effect = &"stop"
stop_rebound = 0.15
visual = &"portcullis"
deck_half_width = %.2f
signal_along = %.2f
signal_height = 3.2
lift_height = 2.8
grille_height = 2.6
bar_spacing = 0.45
bar_size = 0.12
sound_warn = &"portcullis_warn"
sound_down = &""
sound_active = &"portcullis_slam"
""" % (PORT_PERIOD, PORT_ACTIVE_START, PORT_ACTIVE_TIME, PORT_TRANSITION, PORT_PHASE, PORT_WARNING, PORT_FROM, PORT_TO,
       PASSAGE_HW, (PORT_FROM + PORT_TO) * 0.5))
mover_ids = ['SubResource("Mover_drawbridge")', 'SubResource("Mover_portcullis")']
# Rolling barrels (story 009 part 2): released from the cellars at the top of the market drop (the
# end of the gatehouse deck, 7 m) they roll down the street to the lane split (4.5 m) in their own
# lanes, staggered so only one crosses any spot at a time: the street always has free lanes.
BARREL_COUNT = int(os.environ.get("BARREL_COUNT", "3"))          # 2..4
BARREL_LANES = [float(v) for v in os.environ.get("BARREL_LANES", "2.6,-2.6,0.0,-1.3").split(",")]
BARREL_PERIOD = float(os.environ.get("BARREL_PERIOD", "10.0"))
BARREL_SPEED = float(os.environ.get("BARREL_SPEED", "9.0"))
BARREL_WARNING = float(os.environ.get("BARREL_WARNING", "1.5"))  # s a barrel waits, seen, at the top
BARREL_FROM = ts("gate_top", GATE_TOP_TO) - 1.0
BARREL_TO = ts("split", 0.0) - 3.0
assert 2 <= BARREL_COUNT <= 4
assert (BARREL_TO - BARREL_FROM) / BARREL_SPEED + BARREL_WARNING <= BARREL_PERIOD
print("barrels: %d on main s %.1f..%.1f (h %.2f -> %.2f), %.1f m/s, run %.2f s of a %.1f s cycle, lanes %s" % (
      BARREL_COUNT, BARREL_FROM, BARREL_TO, main_h(BARREL_FROM), main_h(BARREL_TO), BARREL_SPEED,
      (BARREL_TO - BARREL_FROM) / BARREL_SPEED, BARREL_PERIOD, BARREL_LANES[:BARREL_COUNT]))
for _k in range(BARREL_COUNT):
    mover_ids.append('SubResource("Mover_barrel_%d")' % _k)
    subs.append("""[sub_resource type="Resource" id="Mover_barrel_%d"]
script = ExtResource("7_mover")
id = &"barrel_%d"
kind = &"barrel"
period = %.2f
active_start = 0.0
active_time = 0.0
transition_time = 0.0
phase = %.3f
warning_lead = %.2f
path = &"main"
path_from = %.2f
path_to = %.2f
speed = %.2f
lane_offset = %.2f
solid_lead = 0.75
hit_radius = 1.4
hit_height = 1.5
min_free_gap = 3.0
hit_effect = &"spin"
hit_profile = 1
visual = &"barrel"
body_radius = 0.55
body_length = 1.1
appear_distance = 2.0
sound_warn = &""
sound_down = &""
sound_active = &"barrel_roll"
""" % (_k, _k, BARREL_PERIOD, BARREL_PERIOD * _k / BARREL_COUNT, BARREL_WARNING, BARREL_FROM, BARREL_TO, BARREL_SPEED,
       BARREL_LANES[_k % len(BARREL_LANES)]))
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

# Story 011 part 2: surface zones and wall openings.
surf_ids = []
for _k, (zid, kind, poly, hs, fence) in enumerate(surf_zones):
    surf_ids.append('SubResource("Surf_%d")' % _k)
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
route_via = %s
""" % (_k, zid, kind, v2(poly), f32(hs), min(hs), "true" if fence else "false", surf_routes.get(zid, (-1.0, -1.0, False))[0],
       surf_routes.get(zid, (-1.0, -1.0, False))[1], "true" if surf_routes.get(zid, (-1.0, -1.0, False))[2] else "false", v2(surf_via.get(zid, []))))
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
[ext_resource type="Resource" path="res://assets/tracks/castle_circuit/castle_theme.tres" id="3_theme"]
[ext_resource type="Script" path="res://src/track/track_hazard.gd" id="4_hazard"]
[ext_resource type="Script" path="res://src/track/track_pad.gd" id="5_pad"]
[ext_resource type="Script" path="res://src/track/track_ramp.gd" id="6_ramp"]
[ext_resource type="Script" path="res://src/track/track_mover.gd" id="7_mover"]
[ext_resource type="Script" path="res://src/track/track_surface.gd" id="8_surf"]
[ext_resource type="Script" path="res://src/track/track_wall_opening.gd" id="9_open"]

%s
[resource]
script = ExtResource("1_data")
track_id = &"castle_circuit"
display_name = "Castle Circuit"
theme = ExtResource("3_theme")
branches = Array[ExtResource("2_branch")]([SubResource("Branch_lane"), SubResource("Branch_bridge"), SubResource("Branch_passage")])
hazards = Array[ExtResource("4_hazard")]([SubResource("Hazard_moat"), SubResource("Hazard_edge"), SubResource("Hazard_bridge")])
boost_pads = Array[ExtResource("5_pad")]([%s])
movers = Array[ExtResource("7_mover")]([%s])
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
heights = %s
banks = %s
solid_below = 99.0
pillar_color = Color(0.56, 0.55, 0.57, 1)
deck_under_color = Color(0.42, 0.41, 0.43, 1)
ramps = Array[ExtResource("6_ramp")]([SubResource("Ramp_0")])
surfaces = Array[ExtResource("8_surf")]([%s])
wall_openings = Array[ExtResource("9_open")]([%s])
"""
subs.append("""[sub_resource type="Resource" id="Ramp_0"]
script = ExtResource("6_ramp")
distance = %.3f
length = %.2f
lip_height = %.2f
color_a = Color(0.78, 0.25, 0.17, 1)
color_b = Color(0.96, 0.92, 0.82, 1)
side_color = Color(0.56, 0.55, 0.57, 1)
""" % (ramp_s, RAMP_LEN, RAMP_LIP))
with open(os.path.join(out, "castle_circuit.tres"), "w", newline="\n") as f:
    f.write(TRES % (9 + len(subs), "\n".join(subs), ", ".join(pad_ids), ", ".join(mover_ids), v2(items), v2(cps), f32(cp_hw), SPP, CURB,
                    v3([(open_s0, open_s1, open_side)]), OPEN_EDGE_REACH, SINK_TIME, RESPAWN_SPEED_FRAC,
                    RESPAWN_IMMUNITY, RESPAWN_BACK_OFF, PAD_BOOST_TIME, f32(cp_h), f32(cp_bank),
                    ", ".join(surf_ids), ", ".join(open_ids)))

zr = {"tourney": (ts("free_a"), ts("moat_sweep")), "moat": (ts("moat_sweep"), ts("spiral")),
      "village": (ts("spiral"), ts("plaza")), "keep": (ts("plaza"), ts("back_gate")),
      "gardens": (ts("back_gate"), ts("free_a"))}
print("zones (main s):", {k: (round(v[0]), round(v[1])) for k, v in zr.items()})
THEME = """[gd_resource type="Resource" script_class="TrackTheme" load_steps=2 format=3]

[ext_resource type="Script" path="res://src/track/track_theme.gd" id="1_theme"]

[resource]
script = ExtResource("1_theme")
style = &"castle"
scenery_road_margin = 0.15
scenery_clear_height = 2.5
scenery_flat_height = 0.3
scenery_max_nudge = 3.0
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
barbican_position = Vector2(%.2f, %.2f)
zone_tourney = Vector2(%.2f, %.2f)
zone_moat = Vector2(%.2f, %.2f)
zone_village = Vector2(%.2f, %.2f)
zone_keep = Vector2(%.2f, %.2f)
zone_gardens = Vector2(%.2f, %.2f)
"""
with open(os.path.join(out, "castle_theme.tres"), "w", newline="\n") as f:
    vals = list(keep) + list(statue) + list(well) + list(lists_center) + list(orchard_center) + list(windmill) + list(gate_p) + list(barbican)
    for z in ("tourney", "moat", "village", "keep", "gardens"):
        vals += list(zr[z])
    f.write(THEME % tuple(vals))
print("wrote")
