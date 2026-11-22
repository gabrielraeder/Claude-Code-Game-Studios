## PROTOTYPE - NOT FOR PRODUCTION. Native spike (ADR-0007).
## GDScript reference copy of the analytic mover routines of src/core/collision/collision_query.gd
## (copied, trimmed: no velocity, no static path, no MoverDef validation). Same arithmetic as the C++ port.
extends RefCounted

const PARALLEL_EPSILON: float = 0.000001
const MOVER_CULL_MARGIN: float = 0.01
const MOVER_SWEEP_TOLERANCE: float = 0.0001
const MOVER_SWEEP_MAX_ITERATIONS: int = 64
const NEWTON_CAPPED: float = -2.0

class MoverDef extends RefCounted:
	var shape: int = 0
	var radius: float = 0.0
	var half_height: float = 0.0
	var half_extents: Vector3 = Vector3.ZERO
	var period: float = 1.0
	var key_t: PackedFloat32Array
	var key_pos: PackedVector3Array
	var key_rot: PackedFloat32Array

var _movers: Array[MoverDef] = []
var _shape_bound: PackedFloat64Array = PackedFloat64Array()
var _path_centre: PackedVector3Array = PackedVector3Array()
var _path_reach: PackedFloat64Array = PackedFloat64Array()
var _pc_t: PackedFloat64Array = PackedFloat64Array()
var _pc_pose: Array[Transform3D] = []
var _pc_inv: Array[Transform3D] = []
var _seg_i: int = 0
var _seg_j: int = 0
var _seg_span: float = 1.0
var _seg_alpha: float = 0.0
var _cl_point: Vector3 = Vector3.ZERO
var _cl_normal: Vector3 = Vector3.UP
var _ray_dist: float = 0.0
var _ray_normal: Vector3 = Vector3.UP
var _sw_fraction: float = 1.0
var _sw_point: Vector3 = Vector3.ZERO
var _sw_normal: Vector3 = Vector3.UP
var _gm_slot: int = -1
var _gm_dist: float = 0.0
var _gm_normal: Vector3 = Vector3.UP
var _ov_slot: int = -1
var _ov_depth: float = 0.0
var _ov_point: Vector3 = Vector3.ZERO
var _ov_normal: Vector3 = Vector3.UP
var _sm_slot: int = -1
var _sm_fraction: float = 1.0
var _sm_point: Vector3 = Vector3.ZERO
var _sm_normal: Vector3 = Vector3.UP
var _rs_count: int = 0
var _rs_slot: PackedInt32Array = PackedInt32Array()
var _rs_from: PackedVector3Array = PackedVector3Array()
var _rs_motion: PackedVector3Array = PackedVector3Array()
var _rs_gap: PackedFloat64Array = PackedFloat64Array()
var _rs_slope: PackedFloat64Array = PackedFloat64Array()
var last_normal: Vector3 = Vector3.ZERO
var _out: PackedFloat64Array = PackedFloat64Array()


func add_mover(shape: int, radius: float, half_height: float, half_extents: Vector3, period: float,
		key_t: PackedFloat32Array, key_pos: PackedVector3Array, key_rot: PackedFloat32Array) -> int:
	var mover: MoverDef = MoverDef.new()
	mover.shape = shape
	mover.radius = radius
	mover.half_height = half_height
	mover.half_extents = half_extents
	mover.period = period
	mover.key_t = key_t
	mover.key_pos = key_pos
	mover.key_rot = key_rot
	var bound: float = 0.0
	match shape:
		0:
			bound = half_extents.length()
		1:
			bound = radius + half_height
		2:
			bound = sqrt(radius * radius + half_height * half_height)
	var lo: Vector3 = key_pos[0]
	var hi: Vector3 = key_pos[0]
	for p: Vector3 in key_pos:
		lo = Vector3(minf(lo.x, p.x), minf(lo.y, p.y), minf(lo.z, p.z))
		hi = Vector3(maxf(hi.x, p.x), maxf(hi.y, p.y), maxf(hi.z, p.z))
	var centre: Vector3 = (lo + hi) * 0.5
	var path_radius: float = 0.0
	for p: Vector3 in key_pos:
		path_radius = maxf(path_radius, centre.distance_to(p))
	_movers.append(mover)
	_shape_bound.append(bound)
	_path_centre.append(centre)
	_path_reach.append(path_radius + bound + MOVER_CULL_MARGIN)
	_pc_t.append(NAN)
	_pc_pose.append(Transform3D.IDENTITY)
	_pc_inv.append(Transform3D.IDENTITY)
	_rs_slot.append(0)
	_rs_from.append(Vector3.ZERO)
	_rs_motion.append(Vector3.ZERO)
	_rs_gap.append(0.0)
	_rs_slope.append(0.0)
	return _movers.size() - 1


func mover_pose(k: int, t: float) -> Transform3D:
	_eval_slot(k, t)
	return _pc_pose[k]


func _find_segment(key_t: PackedFloat32Array, period: float, t: float) -> void:
	var n: int = key_t.size()
	var u: float = fposmod(t, period)
	var i: int = key_t.bsearch(u, false) - 1
	var t0: float = 0.0
	var t1: float = 0.0
	if i >= 0 and i < n - 1:
		_seg_j = i + 1
		t0 = key_t[i]
		t1 = key_t[i + 1]
	else:
		if i < 0 and u < key_t[0]:
			u += period
		i = n - 1
		_seg_j = 0
		t0 = key_t[i]
		t1 = key_t[0] + period
	_seg_i = i
	_seg_span = t1 - t0
	_seg_alpha = clampf((u - t0) / _seg_span, 0.0, 1.0)


func _eval_slot(k: int, t: float) -> void:
	if _pc_t[k] == t:
		return
	var mover: MoverDef = _movers[k]
	_find_segment(mover.key_t, mover.period, t)
	var p0: Vector3 = mover.key_pos[_seg_i]
	var p1: Vector3 = mover.key_pos[_seg_j]
	var kr: PackedFloat32Array = mover.key_rot
	var q0: Quaternion = Quaternion(kr[_seg_i * 4], kr[_seg_i * 4 + 1], kr[_seg_i * 4 + 2], kr[_seg_i * 4 + 3])
	var q1: Quaternion = Quaternion(kr[_seg_j * 4], kr[_seg_j * 4 + 1], kr[_seg_j * 4 + 2], kr[_seg_j * 4 + 3])
	if q0.dot(q1) < 0.0:
		q1 = Quaternion(-q1.x, -q1.y, -q1.z, -q1.w)
	var pose: Transform3D = Transform3D(Basis(q0.slerp(q1, _seg_alpha)), p0.lerp(p1, _seg_alpha))
	_pc_pose[k] = pose
	_pc_inv[k] = pose.inverse()
	_pc_t[k] = t


func _in_reach_at(k: int, a: Vector3, d: Vector3, radius: float, t: float) -> bool:
	_eval_slot(k, t)
	var shape_reach: float = _shape_bound[k] + MOVER_CULL_MARGIN + radius
	return _segment_point_distance_sq(a, d, _pc_pose[k].origin) <= shape_reach * shape_reach


static func _segment_point_distance_sq(a: Vector3, d: Vector3, p: Vector3) -> float:
	var ap: Vector3 = p - a
	var dd: float = d.length_squared()
	var s: float = 0.0
	if dd > 0.0:
		s = clampf(ap.dot(d) / dd, 0.0, 1.0)
	return (ap - d * s).length_squared()


func cast_ground(origin: Vector3, dir: Vector3, max_dist: float, t: float) -> float:
	if _movers.is_empty():
		return -1.0
	_gm_slot = -1
	_gm_dist = max_dist
	var ray: Vector3 = dir * max_dist
	var dd: float = ray.length_squared()
	for k in _movers.size():
		var reach: float = _path_reach[k] + 0.0
		var ap: Vector3 = _path_centre[k] - origin
		var s: float = 0.0
		if dd > 0.0:
			s = clampf(ap.dot(ray) / dd, 0.0, 1.0)
		if (ap - ray * s).length_squared() > reach * reach or not _in_reach_at(k, origin, ray, 0.0, t):
			continue
		var inv: Transform3D = _pc_inv[k]
		if not _ray_local(_movers[k], inv * origin, inv.basis * dir, _gm_dist):
			continue
		if _ray_dist < _gm_dist or _gm_slot < 0:
			_gm_slot = k
			_gm_dist = _ray_dist
			_gm_normal = _pc_pose[k].basis * _ray_normal
	if _gm_slot < 0:
		return -1.0
	last_normal = _gm_normal
	return _gm_dist


func sweep(from: Vector3, to: Vector3, radius: float, t: float) -> float:
	var motion: Vector3 = to - from
	if _movers.is_empty():
		return -1.0
	_test_movers_for_sweep(from, motion, radius, t, motion != Vector3.ZERO)
	if _ov_slot >= 0:
		last_normal = _ov_normal
		return 0.0
	if _sm_slot >= 0:
		last_normal = _sm_normal
		return _sm_fraction
	return -1.0


## Batch with the same layout as NativeSpikeQuery.movers_tick (the loop itself is GDScript).
func tick(t: float, ray_origins: PackedVector3Array, ray_dir: Vector3, ray_len: float,
		sweep_from: PackedVector3Array, sweep_to: PackedVector3Array, radius: float) -> PackedFloat64Array:
	var nr: int = ray_origins.size()
	var ns: int = sweep_from.size()
	if _out.size() != nr + ns * 4:
		_out.resize(nr + ns * 4)
	for i in nr:
		_out[i] = cast_ground(ray_origins[i], ray_dir, ray_len, t)
	for i in ns:
		var fr: float = sweep(sweep_from[i], sweep_to[i], radius, t)
		var o: int = nr + i * 4
		_out[o] = fr
		if fr >= 0.0:
			_out[o + 1] = last_normal.x
			_out[o + 2] = last_normal.y
			_out[o + 3] = last_normal.z
		else:
			_out[o + 1] = 0.0
			_out[o + 2] = 0.0
			_out[o + 3] = 0.0
	return _out


func _test_movers_for_sweep(from: Vector3, motion: Vector3, radius: float, t: float, do_sweep: bool) -> void:
	_ov_slot = -1
	_ov_depth = -INF
	_rs_count = 0
	var dd: float = motion.length_squared()
	for k in _movers.size():
		var reach: float = _path_reach[k] + radius
		var ap: Vector3 = _path_centre[k] - from
		var s: float = 0.0
		if dd > 0.0:
			s = clampf(ap.dot(motion) / dd, 0.0, 1.0)
		if (ap - motion * s).length_squared() > reach * reach or not _in_reach_at(k, from, motion, radius, t):
			continue
		var inv: Transform3D = _pc_inv[k]
		var local_from: Vector3 = inv * from
		var gap: float = _closest_local(_movers[k], local_from) - radius
		if gap <= 0.0:
			if -gap > _ov_depth:
				_ov_slot = k
				_ov_depth = -gap
				_ov_point = _cl_point
				_ov_normal = _cl_normal
			continue
		if do_sweep and _ov_slot < 0:
			var local_motion: Vector3 = inv.basis * motion
			_rs_slot[_rs_count] = k
			_rs_from[_rs_count] = local_from
			_rs_motion[_rs_count] = local_motion
			_rs_gap[_rs_count] = gap
			_rs_slope[_rs_count] = _cl_normal.dot(local_motion)
			_rs_count += 1
	_sm_slot = -1
	_sm_fraction = INF
	if _ov_slot >= 0:
		var pose0: Transform3D = _pc_pose[_ov_slot]
		_ov_point = pose0 * _ov_point
		_ov_normal = pose0.basis * _ov_normal
		return
	if _rs_count == 0:
		return
	var length: float = motion.length()
	for n in _rs_count:
		var k: int = _rs_slot[n]
		if not _sweep_local(_movers[k], _rs_from[n], _rs_motion[n], length, radius, _rs_gap[n], _rs_slope[n]):
			continue
		if _sw_fraction < _sm_fraction:
			_sm_slot = k
			_sm_fraction = _sw_fraction
			_sm_point = _sw_point
			_sm_normal = _sw_normal
	if _sm_slot >= 0:
		var pose: Transform3D = _pc_pose[_sm_slot]
		_sm_point = pose * _sm_point
		_sm_normal = pose.basis * _sm_normal


func _closest_local(mover: MoverDef, p: Vector3) -> float:
	match mover.shape:
		0:
			return _closest_box(mover.half_extents, p)
		1:
			return _closest_capsule(mover.radius, mover.half_height, p)
		_:
			return _closest_cylinder(mover.radius, mover.half_height, p)


func _closest_box(h: Vector3, p: Vector3) -> float:
	var q: Vector3 = p.clamp(-h, h)
	if q != p:
		var out_v: Vector3 = p - q
		var d: float = out_v.length()
		_cl_point = q
		_cl_normal = out_v / d
		return d
	var face: Vector3 = h - p.abs()
	var axis: int = 0
	if face.y < face[axis]:
		axis = 1
	if face.z < face[axis]:
		axis = 2
	var sign_a: float = 1.0 if p[axis] >= 0.0 else -1.0
	_cl_point = p
	_cl_point[axis] = sign_a * h[axis]
	_cl_normal = Vector3.ZERO
	_cl_normal[axis] = sign_a
	return -face[axis]


func _closest_capsule(r: float, hh: float, p: Vector3) -> float:
	var axis_point: Vector3 = Vector3(0.0, clampf(p.y, -hh, hh), 0.0)
	var v: Vector3 = p - axis_point
	var d: float = v.length()
	if d > 0.0:
		_cl_normal = v / d
	else:
		_cl_normal = Vector3.RIGHT
	_cl_point = axis_point + _cl_normal * r
	return d - r


func _closest_cylinder(r: float, hh: float, p: Vector3) -> float:
	var rho: float = sqrt(p.x * p.x + p.z * p.z)
	var y_out: float = absf(p.y) - hh
	if rho > r or y_out > 0.0:
		var q: Vector3 = Vector3(p.x, clampf(p.y, -hh, hh), p.z)
		if rho > r:
			q.x *= r / rho
			q.z *= r / rho
		var out_v: Vector3 = p - q
		var d: float = out_v.length()
		_cl_point = q
		_cl_normal = out_v / d
		return d
	var side: float = r - rho
	var cap: float = -y_out
	if cap <= side:
		var sign_y: float = 1.0 if p.y >= 0.0 else -1.0
		_cl_point = Vector3(p.x, sign_y * hh, p.z)
		_cl_normal = Vector3(0.0, sign_y, 0.0)
		return -cap
	var radial: Vector3 = Vector3.RIGHT
	if rho > 0.0:
		radial = Vector3(p.x / rho, 0.0, p.z / rho)
	_cl_point = Vector3(radial.x * r, p.y, radial.z * r)
	_cl_normal = radial
	return -side


func _ray_local(mover: MoverDef, o: Vector3, d: Vector3, max_dist: float) -> bool:
	match mover.shape:
		0:
			return _ray_box(mover.half_extents, o, d, max_dist)
		1:
			return _ray_capsule(mover.radius, mover.half_height, o, d, max_dist)
		_:
			return _ray_cylinder(mover.radius, mover.half_height, o, d, max_dist)


func _ray_box(h: Vector3, o: Vector3, d: Vector3, max_dist: float) -> bool:
	var t_in: float = -INF
	var t_out: float = INF
	var n_in: Vector3 = Vector3.ZERO
	for axis in 3:
		var oa: float = o[axis]
		var da: float = d[axis]
		var ha: float = h[axis]
		if absf(da) < PARALLEL_EPSILON:
			if absf(oa) > ha:
				return false
			continue
		var s_low: float = (-ha - oa) / da
		var s_high: float = (ha - oa) / da
		var s0: float = minf(s_low, s_high)
		if s0 > t_in:
			t_in = s0
			n_in = Vector3.ZERO
			n_in[axis] = -1.0 if da > 0.0 else 1.0
		t_out = minf(t_out, maxf(s_low, s_high))
		if t_in > t_out:
			return false
	if t_in < 0.0 or t_in > max_dist:
		return false
	_ray_dist = t_in
	_ray_normal = n_in
	return true


func _ray_capsule(r: float, hh: float, o: Vector3, d: Vector3, max_dist: float) -> bool:
	var o_axis: Vector3 = Vector3(0.0, clampf(o.y, -hh, hh), 0.0)
	if (o - o_axis).length_squared() < r * r:
		return false
	var best: float = INF
	var best_n: Vector3 = Vector3.UP
	var a: float = d.x * d.x + d.z * d.z
	var c: float = o.x * o.x + o.z * o.z - r * r
	if a > PARALLEL_EPSILON and c >= 0.0:
		var b: float = o.x * d.x + o.z * d.z
		var disc: float = b * b - a * c
		if disc >= 0.0:
			var s: float = (-b - sqrt(disc)) / a
			if s >= 0.0 and absf(o.y + d.y * s) <= hh:
				best = s
				best_n = Vector3(o.x + d.x * s, 0.0, o.z + d.z * s) / r
	for end in 2:
		var centre: Vector3 = Vector3(0.0, hh if end == 1 else -hh, 0.0)
		var s2: float = _ray_sphere(o - centre, d, r)
		if s2 < best:
			best = s2
			best_n = (o - centre + d * s2) / r
	if best > max_dist:
		return false
	_ray_dist = best
	_ray_normal = best_n
	return true


static func _ray_sphere(oc: Vector3, d: Vector3, r: float) -> float:
	var b: float = oc.dot(d)
	var c: float = oc.length_squared() - r * r
	var disc: float = b * b - c
	if disc < 0.0 or (c > 0.0 and b > 0.0):
		return INF
	var s: float = -b - sqrt(disc)
	return s if s >= 0.0 else INF


func _ray_cylinder(r: float, hh: float, o: Vector3, d: Vector3, max_dist: float) -> bool:
	var t_in: float = -INF
	var t_out: float = INF
	var entry_is_cap: bool = true
	if absf(d.y) < PARALLEL_EPSILON:
		if absf(o.y) > hh:
			return false
	else:
		var s_low: float = (-hh - o.y) / d.y
		var s_high: float = (hh - o.y) / d.y
		t_in = minf(s_low, s_high)
		t_out = maxf(s_low, s_high)
	var a: float = d.x * d.x + d.z * d.z
	var c: float = o.x * o.x + o.z * o.z - r * r
	if a < PARALLEL_EPSILON:
		if c > 0.0:
			return false
	else:
		var b: float = o.x * d.x + o.z * d.z
		var disc: float = b * b - a * c
		if disc < 0.0:
			return false
		var root: float = sqrt(disc)
		if (-b - root) / a > t_in:
			t_in = (-b - root) / a
			entry_is_cap = false
		t_out = minf(t_out, (-b + root) / a)
	if t_in > t_out or t_in < 0.0 or t_in > max_dist:
		return false
	_ray_dist = t_in
	if entry_is_cap:
		_ray_normal = Vector3(0.0, 1.0 if d.y < 0.0 else -1.0, 0.0)
	else:
		_ray_normal = Vector3(o.x + d.x * t_in, 0.0, o.z + d.z * t_in) / r
	return true


func _sweep_local(mover: MoverDef, local_from: Vector3, local_motion: Vector3, length: float,
		radius: float, gap0: float, slope0: float) -> bool:
	var hi: float = NEWTON_CAPPED
	var step_min: float = MOVER_SWEEP_TOLERANCE / length
	var lo: float = 0.0
	var f: float = gap0
	var slope: float = slope0
	for _iteration in MOVER_SWEEP_MAX_ITERATIONS:
		if slope >= 0.0:
			return false
		var s: float = lo - f / slope
		if s > 1.0:
			if s - 1.0 > step_min:
				return false
			s = 1.0
		if s - lo < step_min:
			s = minf(lo + step_min, 1.0)
		var fs: float = _closest_local(mover, local_from + local_motion * s) - radius
		if fs <= 0.0:
			hi = s
			break
		if s >= 1.0:
			return false
		lo = s
		f = fs
		slope = _cl_normal.dot(local_motion)
	if hi == NEWTON_CAPPED:
		_sw_fraction = lo
		_closest_local(mover, local_from + local_motion * lo)
		_sw_point = _cl_point
		_sw_normal = _cl_normal
		return true
	var iterations: int = 0
	while (hi - lo) * length > MOVER_SWEEP_TOLERANCE and iterations < MOVER_SWEEP_MAX_ITERATIONS:
		var mid: float = (lo + hi) * 0.5
		if _closest_local(mover, local_from + local_motion * mid) - radius <= 0.0:
			hi = mid
		else:
			lo = mid
		iterations += 1
	if (1.0 - hi) * length < MOVER_SWEEP_TOLERANCE and _closest_local(mover, local_from + local_motion) - radius <= 0.0:
		_sw_fraction = 1.0
	else:
		_sw_fraction = lo
		_closest_local(mover, local_from + local_motion * lo)
	_sw_point = _cl_point
	_sw_normal = _cl_normal
	return true
