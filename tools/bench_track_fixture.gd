extends RefCounted
## Code-built benchmark track for tools/bench_collision.gd (core-rebuild story 007). DEBUG TOOL, not
## game code: every number below is a named bench constant (tuning-values.md allows that in tools/).
## Deterministic: no randomness, no clock; the same build() gives the same arrays on every run.
##
## Layout (a production rewrite of the spike's idea, prototypes/collision-spike/scripts/track_gen.gd,
## which this file does not load or reference at run time):
##   - a closed figure-eight (lemniscate of Bernoulli) scaled to TRACK_LENGTH m;
##   - two-level crossover: the pass through the crossing near s = TRACK_LENGTH / 4 is lifted
##     BRIDGE_HEIGHT m over the other pass (s = 3 TRACK_LENGTH / 4);
##   - banking from curvature (BANK_GAIN rad per 1/m, at most BANK_MAX_DEG);
##   - ROAD_HALF m road each side of the centre line, OFFROAD_WIDTH m off-road strips (grass / sand
##     blocks of OFFROAD_BLOCK m), WALL_HEIGHT m walls at the outer edges: the left wall carries wall
##     attribute LEFT_WALL_ATTR (one wall shape), the right wall RIGHT_WALL_ATTR (a second shape);
##   - a RAMP_LENGTH m wedge ramp (trick_ramp surface) at s = RAMP_S.
## Triangle budget: SEGMENTS x (ROAD_QUADS + 2 OFF_QUADS) x 2 ground + SEGMENTS x 4 wall + 6 ramp.
## [codeblock]
## var fixture = BenchTrackFixture.new()
## fixture.build()
## var data: TrackCollisionData = fixture.data   # >= 48k ground triangles
## fixture.frame_at(s, lateral, frame)           # frame[0] surface point, [1] forward, [2] up, [3] right
## [/codeblock]

## Track length along the centre line (m).
const TRACK_LENGTH: float = 1200.0
## Longitudinal segments (one per metre).
const SEGMENTS: int = 1200
## Road quads across the road.
const ROAD_QUADS: int = 12
## Off-road quads across each off-road strip.
const OFF_QUADS: int = 4
## Half width of the road (m).
const ROAD_HALF: float = 7.0
## Width of each off-road strip (m).
const OFFROAD_WIDTH: float = 8.0
## Wall height (m).
const WALL_HEIGHT: float = 1.5
## Height of the upper pass over the lower one at the crossover (m).
const BRIDGE_HEIGHT: float = 8.0
## Half the arc length of the bridge bump (m): elevation is a raised cosine over 2x this.
const BRIDGE_HALF_SPAN: float = 220.0
## Bank angle per unit signed curvature (rad per 1/m).
const BANK_GAIN: float = 12.0
## Largest bank angle (degrees).
const BANK_MAX_DEG: float = 12.0
## Length of each grass / sand off-road block (m).
const OFFROAD_BLOCK: float = 50.0
## Arc length where the ramp starts (m).
const RAMP_S: float = 960.0
## Ramp length (m), half width (m) and top height (m).
const RAMP_LENGTH: float = 10.0
const RAMP_HALF_WIDTH: float = 3.0
const RAMP_HEIGHT: float = 1.5
## Lift of the ramp base over the road, so the ramp never sits coplanar with it (m).
const RAMP_LIFT: float = 0.02
## Dense samples of the lemniscate used for the arc-length table.
const DENSE_SAMPLES: int = 40000
## Surface ids (assets/data/core/surface_set.tres): road 0, grass 1, sand 2, trick_ramp 8.
const SURF_ROAD: int = 0
const SURF_GRASS: int = 1
const SURF_SAND: int = 2
const SURF_RAMP: int = 8
## Wall attribute ids (assets/data/core/wall_attr_set.tres): standard 0, rough 1.
const LEFT_WALL_ATTR: int = 0
const RIGHT_WALL_ATTR: int = 1
## Height of the load-probe point over the road at s = 0 (m).
const PROBE_LIFT: float = 2.0

## The built collision data (null before build()).
var data: TrackCollisionData = null
## Per segment sample (closed loop): centre point, forward, banked right, banked up.
var center: PackedVector3Array = PackedVector3Array()
var fwd: PackedVector3Array = PackedVector3Array()
var right: PackedVector3Array = PackedVector3Array()
var up: PackedVector3Array = PackedVector3Array()
## Arc length of the upper pass's crossing (m).
var s_bridge: float = 0.0


## Half width of the drivable cross-section, wall to wall (m).
static func half_total() -> float:
	return ROAD_HALF + OFFROAD_WIDTH


static func _lemniscate(t: float) -> Vector2:
	var s: float = sin(t)
	var c: float = cos(t)
	var den: float = 1.0 + s * s
	return Vector2(c / den, s * c / den)


func _elevation(s: float) -> float:
	var d: float = absf(s - s_bridge)
	d = minf(d, TRACK_LENGTH - d)
	if d >= BRIDGE_HALF_SPAN:
		return 0.0
	return BRIDGE_HEIGHT * 0.5 * (1.0 + cos(PI * d / BRIDGE_HALF_SPAN))


## Builds the track into [member data] and the frame arrays. Allocates: setup only.
func build() -> void:
	var dense: PackedVector2Array = PackedVector2Array()
	dense.resize(DENSE_SAMPLES + 1)
	var acc: PackedFloat64Array = PackedFloat64Array()
	acc.resize(DENSE_SAMPLES + 1)
	var total: float = 0.0
	for i in DENSE_SAMPLES + 1:
		dense[i] = _lemniscate(TAU * float(i) / float(DENSE_SAMPLES))
		if i > 0:
			total += dense[i].distance_to(dense[i - 1])
		acc[i] = total
	var scale: float = TRACK_LENGTH / total
	@warning_ignore("integer_division")
	s_bridge = acc[DENSE_SAMPLES / 4] * scale
	var seg_len: float = TRACK_LENGTH / float(SEGMENTS)
	center.resize(SEGMENTS)
	var j: int = 0
	for i in SEGMENTS:
		var s: float = seg_len * float(i)
		while j < DENSE_SAMPLES - 1 and acc[j + 1] * scale < s:
			j += 1
		var f: float = (s - acc[j] * scale) / maxf((acc[j + 1] - acc[j]) * scale, 1e-9)
		var p2: Vector2 = dense[j].lerp(dense[j + 1], f) * scale
		center[i] = Vector3(p2.x, _elevation(s), p2.y)
	fwd.resize(SEGMENTS)
	right.resize(SEGMENTS)
	up.resize(SEGMENTS)
	var bank_max: float = deg_to_rad(BANK_MAX_DEG)
	for i in SEGMENTS:
		var p_prev: Vector3 = center[(i - 1 + SEGMENTS) % SEGMENTS]
		var p_next: Vector3 = center[(i + 1) % SEGMENTS]
		var f3: Vector3 = (p_next - p_prev).normalized()
		var r0: Vector3 = f3.cross(Vector3.UP).normalized()
		var u0: Vector3 = r0.cross(f3).normalized()
		var t_prev: Vector3 = Vector3(center[i].x - p_prev.x, 0.0, center[i].z - p_prev.z).normalized()
		var t_next: Vector3 = Vector3(p_next.x - center[i].x, 0.0, p_next.z - center[i].z).normalized()
		var signed_curv: float = (t_next - t_prev).dot(r0) / seg_len
		var theta: float = clampf(-signed_curv * BANK_GAIN, -bank_max, bank_max)
		fwd[i] = f3
		right[i] = r0 * cos(theta) + u0 * sin(theta)
		up[i] = u0 * cos(theta) - r0 * sin(theta)
	data = TrackCollisionData.new()
	_build_ground_and_walls()
	_add_ramp()
	data.probe_point = center[0] + up[0] * PROBE_LIFT
	data.probe_surface_id = SURF_ROAD


func _build_ground_and_walls() -> void:
	var lat: PackedFloat64Array = PackedFloat64Array()
	var lat_road: PackedByteArray = PackedByteArray()
	var ht: float = half_total()
	for k in OFF_QUADS:
		lat.append(-ht + OFFROAD_WIDTH * float(k) / float(OFF_QUADS))
		lat_road.append(0)
	for k in ROAD_QUADS:
		lat.append(-ROAD_HALF + 2.0 * ROAD_HALF * float(k) / float(ROAD_QUADS))
		lat_road.append(1)
	for k in OFF_QUADS:
		lat.append(ROAD_HALF + OFFROAD_WIDTH * float(k) / float(OFF_QUADS))
		lat_road.append(0)
	lat.append(ht)
	var ground: PackedVector3Array = PackedVector3Array()
	var surf: PackedInt32Array = PackedInt32Array()
	var left_wall: PackedVector3Array = PackedVector3Array()
	var right_wall: PackedVector3Array = PackedVector3Array()
	var seg_len: float = TRACK_LENGTH / float(SEGMENTS)
	for i in SEGMENTS:
		var i1: int = (i + 1) % SEGMENTS
		var block: int = int(seg_len * float(i) / OFFROAD_BLOCK)
		var u_avg: Vector3 = (up[i] + up[i1]).normalized()
		for k in lat.size() - 1:
			var sid: int = SURF_ROAD
			if lat_road[k] == 0:
				var left_side: int = 1 if lat[k] < 0.0 else 0
				sid = SURF_GRASS if (block + left_side) % 2 == 0 else SURF_SAND
			var p00: Vector3 = center[i] + right[i] * lat[k]
			var p10: Vector3 = center[i] + right[i] * lat[k + 1]
			var p01: Vector3 = center[i1] + right[i1] * lat[k]
			var p11: Vector3 = center[i1] + right[i1] * lat[k + 1]
			_facing_tri(ground, p00, p01, p10, u_avg)
			_facing_tri(ground, p10, p01, p11, u_avg)
			surf.append(sid)
			surf.append(sid)
		for side in [-1.0, 1.0]:
			var b0: Vector3 = center[i] + right[i] * (ht * side)
			var b1: Vector3 = center[i1] + right[i1] * (ht * side)
			var t0: Vector3 = b0 + up[i] * WALL_HEIGHT
			var t1: Vector3 = b1 + up[i1] * WALL_HEIGHT
			var inward: Vector3 = -right[i] * side
			var faces: PackedVector3Array = left_wall if side < 0.0 else right_wall
			_facing_tri(faces, b0, t0, b1, inward)
			_facing_tri(faces, b1, t0, t1, inward)
	data.ground_faces = ground
	data.surface_of_face = surf
	var walls: Array[PackedVector3Array] = [left_wall, right_wall]
	data.wall_faces = walls
	data.wall_attr_ids = PackedInt32Array([LEFT_WALL_ATTR, RIGHT_WALL_ATTR])


func _add_ramp() -> void:
	var seg_len: float = TRACK_LENGTH / float(SEGMENTS)
	var i0: int = int(RAMP_S / seg_len) % SEGMENTS
	var i1: int = (i0 + maxi(1, int(round(RAMP_LENGTH / seg_len)))) % SEGMENTS
	var a_l: Vector3 = center[i0] - right[i0] * RAMP_HALF_WIDTH + up[i0] * RAMP_LIFT
	var a_r: Vector3 = center[i0] + right[i0] * RAMP_HALF_WIDTH + up[i0] * RAMP_LIFT
	var b_l: Vector3 = center[i1] - right[i1] * RAMP_HALF_WIDTH + up[i1] * (RAMP_HEIGHT + RAMP_LIFT)
	var b_r: Vector3 = center[i1] + right[i1] * RAMP_HALF_WIDTH + up[i1] * (RAMP_HEIGHT + RAMP_LIFT)
	var base_l: Vector3 = center[i1] - right[i1] * RAMP_HALF_WIDTH + up[i1] * RAMP_LIFT
	var base_r: Vector3 = center[i1] + right[i1] * RAMP_HALF_WIDTH + up[i1] * RAMP_LIFT
	var ground: PackedVector3Array = data.ground_faces
	var surf: PackedInt32Array = data.surface_of_face
	var tris: Array[PackedVector3Array] = [
		PackedVector3Array([a_l, b_l, a_r, up[i0]]),          # sloped top
		PackedVector3Array([a_r, b_l, b_r, up[i0]]),
		PackedVector3Array([base_l, b_l, base_r, fwd[i1]]),   # drop-off face
		PackedVector3Array([base_r, b_l, b_r, fwd[i1]]),
		PackedVector3Array([a_l, base_l, b_l, -right[i0]]),   # sides
		PackedVector3Array([a_r, base_r, b_r, right[i0]]),
	]
	for tri in tris:
		_facing_tri(ground, tri[0], tri[1], tri[2], tri[3])
		surf.append(SURF_RAMP)
	data.ground_faces = ground
	data.surface_of_face = surf


## Appends (a, b, c) or (a, c, b), whichever has its Godot front ((c - a) x (b - a)) along facing.
static func _facing_tri(faces: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3, facing: Vector3) -> void:
	if (c - a).cross(b - a).dot(facing) > 0.0:
		faces.append(a)
		faces.append(b)
		faces.append(c)
	else:
		faces.append(a)
		faces.append(c)
		faces.append(b)


## The track frame at arc length [param s] (wraps) and lateral offset [param lateral] (m, + right),
## written into [param out] (size >= 4): out[0] the point on the road surface plane, out[1] forward,
## out[2] up, out[3] right (unit). Allocation-free.
func frame_at(s: float, lateral: float, out: PackedVector3Array) -> void:
	var u: float = fposmod(s, TRACK_LENGTH) / TRACK_LENGTH * float(SEGMENTS)
	var i: int = int(u) % SEGMENTS
	var i1: int = (i + 1) % SEGMENTS
	var f: float = u - floorf(u)
	var r: Vector3 = right[i].lerp(right[i1], f).normalized()
	out[0] = center[i].lerp(center[i1], f) + r * lateral
	out[1] = fwd[i].lerp(fwd[i1], f).normalized()
	out[2] = up[i].lerp(up[i1], f).normalized()
	out[3] = r
