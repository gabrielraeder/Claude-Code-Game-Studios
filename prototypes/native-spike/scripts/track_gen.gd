## PROTOTYPE - NOT FOR PRODUCTION. Collision spike. Deterministic synthetic track.
##
## A figure-eight (lemniscate of Bernoulli) closed loop scaled to TARGET_LENGTH,
## one pass lifted over the other at the crossing (two-level crossover), banked by
## curvature, 14 m road, off-road strips both sides (grass / sand blocks), vertical
## walls at the outer edge, and a ramp wedge on the road.
##
## Winding: Godot's front face for a triangle (a, b, c) has normal (c-a) x (b-a)
## (observed in probe_query.gd). _add_tri() orders vertices so the front normal
## points toward the requested side (ground: up, walls: inward).
##
## Usage:
##   var TrackGen := preload("res://scripts/track_gen.gd")
##   var tg: TrackGen = TrackGen.new()
##   tg.build(1.0, 10, 4)   # segment length (m), road quads across, off-road quads across
##   tg.ground_faces / tg.ground_surf / tg.wall_faces / tg.wall_surf
extends RefCounted

const SURF_ROAD: int = 0
const SURF_GRASS: int = 1
const SURF_SAND: int = 2
const SURF_WALL: int = 3
const SURF_RAMP: int = 4
const SURF_COUNT: int = 5
const SURF_NAMES: PackedStringArray = ["road", "grass", "sand", "wall", "ramp"]

const TARGET_LENGTH: float = 1200.0
const ROAD_HALF: float = 7.0
const OFFROAD_WIDTH: float = 8.0
const WALL_HEIGHT: float = 1.5
const BRIDGE_HEIGHT: float = 8.0
const BRIDGE_HALF_SPAN: float = 220.0
const BANK_GAIN: float = 12.0          # bank rad per (1/m) of curvature
const BANK_MAX: float = deg_to_rad(12.0)
const OFFROAD_BLOCK: float = 50.0      # grass/sand alternation length (m)
const RAMP_S_FRACTION: float = 0.75
const RAMP_S_OFFSET: float = 60.0
const RAMP_LENGTH: float = 10.0
const RAMP_HALF_WIDTH: float = 3.0
const RAMP_HEIGHT: float = 1.5
const DENSE_SAMPLES: int = 40000

var length: float = 0.0
var seg_count: int = 0
## Per centreline sample (seg_count, closed): position, forward, right (banked), up (banked).
var center := PackedVector3Array()
var fwd := PackedVector3Array()
var right := PackedVector3Array()
var up := PackedVector3Array()
var ground_faces := PackedVector3Array()
var ground_surf := PackedByteArray()
var wall_faces := PackedVector3Array()
var wall_surf := PackedByteArray()

static func _lemniscate(t: float) -> Vector2:
	var s: float = sin(t)
	var c: float = cos(t)
	var den: float = 1.0 + s * s
	return Vector2(c / den, s * c / den)

func half_total() -> float:
	return ROAD_HALF + OFFROAD_WIDTH

func ground_tri_count() -> int:
	return ground_faces.size() / 3

func wall_tri_count() -> int:
	return wall_faces.size() / 3

## Ground height bump: the pass through t = PI/2 goes over the bridge.
func _elevation(s: float, s_bridge: float) -> float:
	var d: float = absf(s - s_bridge)
	d = minf(d, length - d)
	if d >= BRIDGE_HALF_SPAN:
		return 0.0
	return BRIDGE_HEIGHT * 0.5 * (1.0 + cos(PI * d / BRIDGE_HALF_SPAN))

func _add_tri(faces: PackedVector3Array, surf: PackedByteArray, a: Vector3, b: Vector3, c: Vector3, want: Vector3, id: int) -> void:
	var n: Vector3 = (c - a).cross(b - a)
	if n.dot(want) < 0.0:
		faces.append_array([a, c, b])
	else:
		faces.append_array([a, b, c])
	surf.append(id)

func _quad(faces: PackedVector3Array, surf: PackedByteArray, p00: Vector3, p10: Vector3, p01: Vector3, p11: Vector3, want: Vector3, id: int) -> void:
	_add_tri(faces, surf, p00, p01, p10, want, id)
	_add_tri(faces, surf, p10, p01, p11, want, id)

## Builds the track. seg_len sets the longitudinal resolution, road_quads and
## off_quads the lateral subdivisions (the knobs for the triangle budget).
func build(seg_len: float, road_quads: int, off_quads: int) -> void:
	# 1. dense lemniscate, arc length, scale to TARGET_LENGTH
	var dense := PackedVector2Array()
	dense.resize(DENSE_SAMPLES + 1)
	var acc := PackedFloat64Array()
	acc.resize(DENSE_SAMPLES + 1)
	var total: float = 0.0
	for i: int in DENSE_SAMPLES + 1:
		dense[i] = _lemniscate(TAU * float(i) / float(DENSE_SAMPLES))
		if i > 0:
			total += dense[i].distance_to(dense[i - 1])
		acc[i] = total
	var scale: float = TARGET_LENGTH / total
	length = TARGET_LENGTH
	seg_count = int(round(length / seg_len))
	var s_bridge: float = acc[DENSE_SAMPLES / 4] * scale  # t = PI/2
	# 2. uniform resample in arc length
	var pts := PackedVector3Array()
	pts.resize(seg_count)
	var j: int = 0
	for i: int in seg_count:
		var s: float = length * float(i) / float(seg_count)
		while j < DENSE_SAMPLES - 1 and acc[j + 1] * scale < s:
			j += 1
		var f: float = (s - acc[j] * scale) / maxf((acc[j + 1] - acc[j]) * scale, 1e-9)
		var p2: Vector2 = dense[j].lerp(dense[j + 1], f) * scale
		pts[i] = Vector3(p2.x, _elevation(s, s_bridge), p2.y)
	# 3. frames with banking
	center = pts
	fwd.resize(seg_count)
	right.resize(seg_count)
	up.resize(seg_count)
	for i: int in seg_count:
		var p_prev: Vector3 = pts[(i - 1 + seg_count) % seg_count]
		var p_next: Vector3 = pts[(i + 1) % seg_count]
		var f3: Vector3 = (p_next - p_prev).normalized()
		var r0: Vector3 = f3.cross(Vector3.UP).normalized()
		var u0: Vector3 = r0.cross(f3).normalized()
		var t_prev: Vector3 = Vector3(pts[i].x - p_prev.x, 0, pts[i].z - p_prev.z).normalized()
		var t_next: Vector3 = Vector3(p_next.x - pts[i].x, 0, p_next.z - pts[i].z).normalized()
		var signed_curv: float = (t_next - t_prev).dot(r0) / seg_len
		var theta: float = clampf(-signed_curv * BANK_GAIN, -BANK_MAX, BANK_MAX)
		fwd[i] = f3
		right[i] = r0 * cos(theta) + u0 * sin(theta)
		up[i] = u0 * cos(theta) - r0 * sin(theta)
	# 4. cross-section lateral stations
	var lat := PackedFloat64Array()
	var lat_surf := PackedInt32Array()  # surface of the strip starting at this station (-1 = side-dependent off-road)
	var ht: float = half_total()
	for k: int in off_quads:
		lat.append(-ht + OFFROAD_WIDTH * float(k) / float(off_quads))
		lat_surf.append(-1)
	for k: int in road_quads:
		lat.append(-ROAD_HALF + 2.0 * ROAD_HALF * float(k) / float(road_quads))
		lat_surf.append(SURF_ROAD)
	for k: int in off_quads:
		lat.append(ROAD_HALF + OFFROAD_WIDTH * float(k) / float(off_quads))
		lat_surf.append(-1)
	lat.append(ht)
	ground_faces = PackedVector3Array()
	ground_surf = PackedByteArray()
	wall_faces = PackedVector3Array()
	wall_surf = PackedByteArray()
	for i: int in seg_count:
		var i1: int = (i + 1) % seg_count
		var s: float = length * float(i) / float(seg_count)
		var block: int = int(s / OFFROAD_BLOCK)
		var u_avg: Vector3 = (up[i] + up[i1]).normalized()
		for k: int in lat.size() - 1:
			var sid: int = lat_surf[k]
			if sid < 0:
				var left_side: bool = lat[k] < 0.0
				sid = SURF_GRASS if ((block + (1 if left_side else 0)) % 2 == 0) else SURF_SAND
			var p00: Vector3 = center[i] + right[i] * lat[k]
			var p10: Vector3 = center[i] + right[i] * lat[k + 1]
			var p01: Vector3 = center[i1] + right[i1] * lat[k]
			var p11: Vector3 = center[i1] + right[i1] * lat[k + 1]
			_quad(ground_faces, ground_surf, p00, p10, p01, p11, u_avg, sid)
		for side: float in [-1.0, 1.0]:
			var b0: Vector3 = center[i] + right[i] * (ht * side)
			var b1: Vector3 = center[i1] + right[i1] * (ht * side)
			var t0: Vector3 = b0 + up[i] * WALL_HEIGHT
			var t1: Vector3 = b1 + up[i1] * WALL_HEIGHT
			var inward: Vector3 = -right[i] * side
			_quad(wall_faces, wall_surf, b0, t0, b1, t1, inward, SURF_WALL)
	_add_ramp(seg_len)

func _add_ramp(seg_len: float) -> void:
	var i0: int = int(((length * RAMP_S_FRACTION + RAMP_S_OFFSET) / length) * seg_count) % seg_count
	var n_steps: int = maxi(1, int(round(RAMP_LENGTH / seg_len)))
	var i1: int = (i0 + n_steps) % seg_count
	var lift: float = 0.02  # avoid coplanar start
	var a_l: Vector3 = center[i0] + right[i0] * -RAMP_HALF_WIDTH + up[i0] * lift
	var a_r: Vector3 = center[i0] + right[i0] * RAMP_HALF_WIDTH + up[i0] * lift
	var b_l: Vector3 = center[i1] + right[i1] * -RAMP_HALF_WIDTH + up[i1] * (RAMP_HEIGHT + lift)
	var b_r: Vector3 = center[i1] + right[i1] * RAMP_HALF_WIDTH + up[i1] * (RAMP_HEIGHT + lift)
	var base_l: Vector3 = center[i1] + right[i1] * -RAMP_HALF_WIDTH + up[i1] * lift
	var base_r: Vector3 = center[i1] + right[i1] * RAMP_HALF_WIDTH + up[i1] * lift
	_quad(ground_faces, ground_surf, a_l, a_r, b_l, b_r, up[i0], SURF_RAMP)            # sloped top
	_quad(ground_faces, ground_surf, base_l, base_r, b_l, b_r, fwd[i1], SURF_RAMP)     # drop-off face
	_add_tri(ground_faces, ground_surf, a_l, base_l, b_l, -right[i0], SURF_RAMP)       # sides
	_add_tri(ground_faces, ground_surf, a_r, base_r, b_r, right[i0], SURF_RAMP)

## Sample the track frame at arc length s (wraps), lateral offset l.
## Writes into out (0 = position on the surface, 1 = forward, 2 = up).
func frame_at(s: float, l: float, out: PackedVector3Array) -> void:
	var u: float = fposmod(s, length) / length * float(seg_count)
	var i: int = int(u) % seg_count
	var i1: int = (i + 1) % seg_count
	var f: float = u - floor(u)
	var c: Vector3 = center[i].lerp(center[i1], f)
	var r: Vector3 = right[i].lerp(right[i1], f).normalized()
	out[0] = c + r * l
	out[1] = fwd[i].lerp(fwd[i1], f).normalized()
	out[2] = up[i].lerp(up[i1], f).normalized()
