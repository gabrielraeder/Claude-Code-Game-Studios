#!/usr/bin/env python3
"""Generator for the surface test track (story 011 part 1). Authoring aid, not run by the game.

A small rounded rectangle (240 x 120 m, corner radius 24, road half width 7, curb 1.2, lap about 679 m,
turning right) with one zone of each surface kind: on the long east straight, grass and sand on the
outside (left) and mud and rubble on the inside (right), then a shallows lane; a grass patch inside
the first corner with a diagonal boost-cut across it; a slick patch on the west straight. Writes
assets/tracks/test_surfaces/test_surfaces.tres.

Re-run after edits:  python tools/gen_test_surfaces.py
Heading convention: 0 = +x, positive angles turn toward +z (a right turn for the driver); side +1 is
TrackModel's normal, the inside of a right turn.
"""
import math
import os

R = 24.0          # corner radius (centerline)
LX, LZ = 240.0, 120.0
HW = 7.0          # road half width
CURB = 1.2
CP_STEP = 5.0
SPP = 4

pts = []          # control points
elems = []        # (kind, length or angle)
pos = [24.0, 0.0]
head = 0.0


def rn(h):
    return (-math.sin(h), math.cos(h))


def straight(length):
    global pos
    n = max(int(round(length / CP_STEP)), 1)
    d = (math.cos(head), math.sin(head))
    for k in range(n):
        pts.append((pos[0] + d[0] * length * k / n, pos[1] + d[1] * length * k / n))
    pos = [pos[0] + d[0] * length, pos[1] + d[1] * length]


def arc_right(angle):
    global pos, head
    n = max(int(round(R * angle / CP_STEP)), 2)
    c = (pos[0] + R * rn(head)[0], pos[1] + R * rn(head)[1])
    for k in range(n):
        th = angle * k / n
        r = rn(head + th)
        pts.append((c[0] - R * r[0], c[1] - R * r[1]))
    r = rn(head + angle)
    pos = [c[0] - R * r[0], c[1] - R * r[1]]
    head += angle


# the lap: east leg, corner, south leg, corner, west leg, corner, north leg, corner
EAST = LX - 2 * R
SOUTH = LZ - 2 * R
straight(EAST)
arc_right(math.pi / 2)
straight(SOUTH)
arc_right(math.pi / 2)
straight(EAST)
arc_right(math.pi / 2)
straight(SOUTH)
arc_right(math.pi / 2)

ARC = R * math.pi / 2
S_EAST = (0.0, EAST)
S_C1 = (EAST, EAST + ARC)
S_SOUTH = (EAST + ARC, EAST + ARC + SOUTH)
S_WEST0 = EAST + 2 * ARC + SOUTH   # start of the west leg (x = 216 going west)
X0 = 24.0                          # x of s = 0 on the east leg
WALL = HW + CURB

surfaces = []   # (id, kind, polygon, height)
openings = []   # (s_from, s_to, side, depth)


def east_zone(zid, kind, s0, s1, side, width=10.0):
    z0 = WALL * side
    z1 = (WALL + width) * side
    poly = [(X0 + s0, z0), (X0 + s1, z0), (X0 + s1, z1), (X0 + s0, z1)]
    surfaces.append((zid, kind, poly, 0.0))
    openings.append((s0, s1, side, 20.0))


# outside (left, side -1 is the -z side): grass, sand, shallows; inside (right, side +1): mud, rubble
east_zone("grass_a", "grass", 20, 60, -1)
east_zone("sand_a", "sand", 70, 110, -1)
east_zone("shallows_a", "shallows", 120, 175, -1, 12.0)
east_zone("mud_a", "mud", 20, 60, 1)
east_zone("rubble_a", "rubble", 70, 110, 1)

def west_zone(zid, kind, s0, s1, side, width=10.0):
    # West leg (heading west, TrackModel normal = -z): s is measured from the leg's start at x = 216.
    xa, xb = X0 + EAST - s0, X0 + EAST - s1
    z0 = LZ - side * WALL
    z1 = LZ - side * (WALL + width)
    surfaces.append((zid, kind, [(xa, z0), (xb, z0), (xb, z1), (xa, z1)], 0.0))
    openings.append((S_WEST0 + s0, S_WEST0 + s1, side, 20.0))


# a mud lane and a grass lane on the west leg (outside = side -1), so mud can be driven without the start boost
west_zone("mud_b", "mud", 10, 50, -1)
west_zone("grass_b", "grass", 80, 120, -1)

# the corner patch: inside the first corner, between the curb of the east leg, the curb arc and the curb of
# the south leg, closed by a diagonal fence. The kart cuts across it with a boost.
cx, cz = X0 + EAST, R          # corner 1 centre (216, 24)
inner = R - WALL               # curb circle radius
lead = 50.0
patch = [(cx - lead, WALL)]
patch.append((cx, WALL))
steps = 12
for k in range(1, steps + 1):
    phi = (math.pi / 2) * k / steps
    patch.append((cx + inner * math.sin(phi), cz - inner * math.cos(phi)))
patch.append((cx + inner, cz + lead))
surfaces.append(("corner_cut", "grass", patch, 0.0))
openings.append((EAST - lead, EAST + ARC + lead, 1, 40.0))

# the slick patch on the west leg (road centre z = LZ; going west, x = 216 - (s - S_WEST0))
sw0, sw1 = S_WEST0 + 60, S_WEST0 + 72
sx0, sx1 = cx - (sw0 - S_WEST0), cx - (sw1 - S_WEST0)
sl = HW - 1.0
surfaces.append(("slick_a", "slick", [(sx0, LZ - sl), (sx0, LZ + sl), (sx1, LZ + sl), (sx1, LZ - sl)], 0.0))

# ------------------------------------------------------------------ write
out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "tracks", "test_surfaces")
os.makedirs(out, exist_ok=True)


def v2(points):
    return "PackedVector2Array(" + ", ".join("%.3f, %.3f" % p for p in points) + ")"


lines = ['[gd_resource type="Resource" script_class="TrackData" load_steps=%d format=3]\n' % (len(surfaces) + len(openings) + 6),
         '[ext_resource type="Script" path="res://src/test_track/track_data.gd" id="1_track"]',
         '[ext_resource type="Script" path="res://src/track/track_surface.gd" id="2_surf"]',
         '[ext_resource type="Script" path="res://src/track/track_wall_opening.gd" id="3_open"]',
         '[ext_resource type="Script" path="res://src/track/track_pad.gd" id="4_pad"]\n']
for i, (zid, kind, poly, h) in enumerate(surfaces):
    lines.append('[sub_resource type="Resource" id="Z_%d"]\nscript = ExtResource("2_surf")\nid = &"%s"\nkind = &"%s"\npolygon = %s\nheight = %s\n'
                 % (i, zid, kind, v2(poly), h))
for i, (s0, s1, side, depth) in enumerate(openings):
    lines.append('[sub_resource type="Resource" id="O_%d"]\nscript = ExtResource("3_open")\ns_from = %.3f\ns_to = %.3f\nside = %d\ndepth = %s\n'
                 % (i, s0, s1, side, depth))
lines.append('[sub_resource type="Resource" id="Pad_a"]\nscript = ExtResource("4_pad")\ndistance = 150.0\nwidth = 6.0\n')
lines.append('[resource]\nscript = ExtResource("1_track")\ntrack_id = &"test_surfaces"\ndisplay_name = "Test Surfaces"\n'
             'control_points = %s\nsamples_per_segment = %d\nroad_half_width = %s\ncurb_width = %s\nlap_count = 3\n'
             'start_distance_behind_line = 6.0\nquery_window = 14\n'
             'surfaces = Array[ExtResource("2_surf")]([%s])\nwall_openings = Array[ExtResource("3_open")]([%s])\n'
             'boost_pads = Array[ExtResource("4_pad")]([SubResource("Pad_a")])\n'
             % (v2(pts), SPP, HW, CURB,
                ", ".join('SubResource("Z_%d")' % i for i in range(len(surfaces))),
                ", ".join('SubResource("O_%d")' % i for i in range(len(openings)))))
with open(os.path.join(out, "test_surfaces.tres"), "w", newline="\n") as f:
    f.write("\n".join(lines))
total = sum(math.dist(pts[i], pts[(i + 1) % len(pts)]) for i in range(len(pts)))
print("control points %d, lap about %.1f m; zones %d, openings %d" % (len(pts), total, len(surfaces), len(openings)))
