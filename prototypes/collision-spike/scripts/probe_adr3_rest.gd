## Scratch probe for ADR-0003 review (godot-specialist). PROTOTYPE - NOT FOR PRODUCTION.
## What get_rest_info_into returns for a sphere that starts overlapped with a
## one-sided wall: is point on the wall surface and normal toward the sphere, so
## depth = r - dot(center - point, n) is valid? Several depths, yaws, slopes,
## edges, corners, internal diagonals. Also what sweep_walls' cast sees from a
## started-inside point.
## Run: godot --headless --path prototypes/collision-spike -s res://scripts/probe_adr3_rest.gd
extends SceneTree

const R: float = 1.0
var _frame: int = 0
var _st: PhysicsDirectSpaceState3D
var _sph: SphereShape3D
var _q: PhysicsShapeQueryParameters3D
var _rr: PhysicsGetRestInfoResult3D
var _cr: PhysicsCastMotionResult3D
var _rids: Array[RID] = []
var _spaces: Array[RID] = []


## Quad (two triangles a,b,c / c,b,d) whose front faces `front`; plane through `o`
## spanned by unit `u` (half size hu) and `v` (from 0 to hv).
func _quad(o: Vector3, u: Vector3, v: Vector3, hu: float, hv: float, front: Vector3) -> PackedVector3Array:
	var a: Vector3 = o - u * hu
	var b: Vector3 = o - u * hu + v * hv
	var c: Vector3 = o + u * hu
	var d: Vector3 = o + u * hu + v * hv
	var f := PackedVector3Array()
	for tri: Array in [[a, b, c], [c, b, d]]:
		var n: Vector3 = (tri[2] - tri[0]).cross(tri[1] - tri[0])  # Godot front (see probe_adr2)
		if n.dot(front) > 0.0:
			f.append_array([tri[0], tri[1], tri[2]])
		else:
			f.append_array([tri[0], tri[2], tri[1]])
	return f


func _space(faces_list: Array) -> void:
	for r: RID in _rids:
		PhysicsServer3D.free_rid(r)
	_rids.clear()
	var sp: RID = PhysicsServer3D.space_create()
	_spaces.append(sp)
	var b: RID = PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(b, PhysicsServer3D.BODY_MODE_STATIC)
	for faces: PackedVector3Array in faces_list:
		var s: RID = PhysicsServer3D.concave_polygon_shape_create()
		PhysicsServer3D.shape_set_data(s, {"faces": faces, "backface_collision": false})
		PhysicsServer3D.body_add_shape(b, s)
		_rids.append(s)
	PhysicsServer3D.body_set_collision_layer(b, 2)
	PhysicsServer3D.body_set_collision_mask(b, 0)
	PhysicsServer3D.body_set_space(b, sp)
	_rids.push_front(b)  # bodies freed before shapes
	_st = PhysicsServer3D.space_get_direct_state(sp)


func _rest(c: Vector3) -> bool:
	_q.transform = Transform3D(Basis.IDENTITY, c)
	_q.motion = Vector3.ZERO
	return _st.get_rest_info_into(_q, _rr)


func _cast(c: Vector3, motion: Vector3) -> String:
	_q.transform = Transform3D(Basis.IDENTITY, c)
	_q.motion = motion
	var ok: bool = _st.cast_motion_into(_q, _cr)
	_q.motion = Vector3.ZERO
	return "cast ret=%s safe=%.4f unsafe=%.4f" % [ok, _cr.safe_fraction, _cr.unsafe_fraction]


## Prints the rest result; true_d is the analytic depth (r - signed distance to the
## nearest feature), plane_n the face normal.
func _report(tag: String, c: Vector3, true_d: float, plane_n: Vector3) -> void:
	if not _rest(c):
		print("%s c=%s  rest=NONE  (true depth %.4f)" % [tag, c, true_d])
		return
	var n: Vector3 = _rr.normal
	var p: Vector3 = _rr.point
	var d_formula: float = R - (c - p).dot(n)
	var on_plane: float = (p - (c - plane_n * (c - _plane_o).dot(plane_n))).length() if plane_n != Vector3.ZERO else -1.0
	var p_plane_dist: float = (p - _plane_o).dot(plane_n) if plane_n != Vector3.ZERO else 0.0
	# ADR-0003 §6 form: n projected onto the up plane (up = +Y here)
	var nh: Vector3 = Vector3(n.x, 0.0, n.z)
	var adr_d: float = NAN
	var need_h: float = NAN
	if nh.length() > 1e-4:
		nh = nh.normalized()
		adr_d = R - (c - p).dot(nh)
		need_h = true_d / n.dot(nh)  # horizontal push that clears the true depth
	print("%s c=%s p=%s n=%s |n|=%.5f n.plane=%.4f p_off_plane=%.5f | d_formula=%.4f true=%.4f err=%.7f | adr_d(n_h)=%.4f need_h=%.4f" % [
		tag, c, p, n, n.length(), n.dot(plane_n), p_plane_dist, d_formula, true_d, absf(d_formula - true_d), adr_d, need_h])


var _plane_o: Vector3 = Vector3.ZERO


func _initialize() -> void:
	_sph = SphereShape3D.new()
	_sph.radius = R
	_q = PhysicsShapeQueryParameters3D.new()
	_q.shape = _sph
	_q.collision_mask = 2
	_rr = PhysicsGetRestInfoResult3D.new()
	_cr = PhysicsCastMotionResult3D.new()


func _process(_d: float) -> bool:
	_frame += 1
	if _frame == 2:
		_main()
		for r: RID in _rids:
			PhysicsServer3D.free_rid(r)
		_rids.clear()
		for s: RID in _spaces:
			PhysicsServer3D.free_rid(s)
		quit()
	return false


func _main() -> void:
	print("engine=", Engine.get_version_info().string, " physics=", ProjectSettings.get_setting("physics/3d/physics_engine"), " R=", R, " q.margin=", _q.margin)
	# A. Vertical wall x=0 facing +X, z in [-10,10], y in [0,4]. Diagonal from (0,0,10)-(0,4,-10).
	_plane_o = Vector3.ZERO
	_space([_quad(Vector3(0, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0), 10.0, 4.0, Vector3(1, 0, 0))])
	print("A. vertical +X wall, depths (center x = R - depth); z=3.0 (off diagonal) and on the internal diagonal")
	for cx: float in [1.05, 1.0, 0.99, 0.98, 0.9, 0.7, 0.5, 0.3, 0.1, 0.01, 0.0, -0.01, -0.3]:
		_report("  A x=%5.2f" % cx, Vector3(cx, 2.0, 3.0), R - cx, Vector3(1, 0, 0))
	# point on the internal diagonal: the line from (0,0,10) to (0,4,-10) passes z=0 at y=2
	for cx: float in [0.7, 0.3]:
		_report("  A diag x=%4.2f" % cx, Vector3(cx, 2.0, 0.0), R - cx, Vector3(1, 0, 0))
	# B. Wall yawed by a (normal (cos a, 0, sin a)), depth 0.3 and 0.8
	print("B. yawed vertical walls, depth 0.3 / 0.8")
	for deg: float in [15.0, 30.0, 45.0, 60.0, 89.0, 137.0]:
		var a: float = deg_to_rad(deg)
		var n: Vector3 = Vector3(cos(a), 0.0, sin(a))
		var u: Vector3 = Vector3(0, 1, 0).cross(n).normalized()
		_plane_o = Vector3(5, 0, -3)
		_space([_quad(_plane_o, u, Vector3(0, 1, 0), 10.0, 4.0, n)])
		for depth: float in [0.3, 0.8]:
			_report("  B yaw=%5.1f d=%.1f" % [deg, depth], _plane_o + n * (R - depth) + Vector3(0, 2, 0) + u * 1.7, depth, n)
	# C. Sloped walls: normal tilted t above horizontal (n=(cos t, sin t, 0)) and below (overhang)
	print("C. sloped walls (normal tilt t from horizontal; negative = overhang), depth 0.3")
	for deg: float in [10.0, 30.0, 45.0, 60.0, -30.0]:
		var t: float = deg_to_rad(deg)
		var n: Vector3 = Vector3(cos(t), sin(t), 0.0)
		var u: Vector3 = Vector3(0, 0, 1)
		var v: Vector3 = n.cross(u).normalized()
		if v.y < 0.0:
			v = -v
		_plane_o = Vector3(0, 0, 0)
		_space([_quad(Vector3(0, 0, 0) - v * 4.0, u, v, 10.0, 8.0, n)])
		_report("  C tilt=%5.1f" % deg, n * (R - 0.3) + u * 2.0, 0.3, n)
	# D. Edge / top-of-wall contacts on the vertical +X wall (top at y=4)
	print("D. near the wall top edge (y=4) and the end edge (z=10)")
	_plane_o = Vector3.ZERO
	_space([_quad(Vector3(0, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0), 10.0, 4.0, Vector3(1, 0, 0))])
	for c: Vector3 in [Vector3(0.3, 4.3, 0.0), Vector3(0.05, 4.5, 0.0), Vector3(0.0, 4.6, 0.0), Vector3(-0.2, 4.5, 0.0), Vector3(0.3, 2.0, 10.4), Vector3(0.3, 4.3, 10.3)]:
		var nearest: Vector3 = Vector3(0.0, clampf(c.y, 0.0, 4.0), clampf(c.z, -10.0, 10.0))
		var dist: float = (c - nearest).length()
		var tag: String = "  D"
		_report(tag, c, R - dist, Vector3(1, 0, 0))
		if _rest(c):
			print("      expected nearest=%s, (c-nearest).normalized()=%s" % [nearest, (c - nearest).normalized() if dist > 1e-6 else Vector3.ZERO])
	# E. Corner: wall X (x=0 facing +X) and wall Z (z=0 facing +Z), same shape and as two shapes.
	print("E. inner corner: which contact does rest info return? (depth X=0.8, Z=0.4) and swapped")
	var wx: PackedVector3Array = _quad(Vector3(0, 0, 5), Vector3(0, 0, 1), Vector3(0, 1, 0), 5.0, 4.0, Vector3(1, 0, 0))
	var wz: PackedVector3Array = _quad(Vector3(5, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0), 5.0, 4.0, Vector3(0, 0, 1))
	var both := PackedVector3Array(); both.append_array(wx); both.append_array(wz)
	for layout: String in ["one_shape", "two_shapes_XZ", "two_shapes_ZX"]:
		match layout:
			"one_shape": _space([both])
			"two_shapes_XZ": _space([wx, wz])
			"two_shapes_ZX": _space([wz, wx])
		for c: Vector3 in [Vector3(0.2, 2.0, 0.6), Vector3(0.6, 2.0, 0.2), Vector3(0.5, 2.0, 0.5)]:
			if _rest(c):
				print("  E %s c=%s -> n=%s p=%s shape=%d" % [layout, c, _rr.normal, _rr.point, _rr.collider_shape])
			else:
				print("  E %s c=%s -> NONE" % [layout, c])
	# F. Cast from a started-inside point (what sweep_walls step 2 sees).
	print("F. cast_motion from overlapped start (vertical +X wall, start x=0.7, depth 0.3)")
	_space([_quad(Vector3(0, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0), 10.0, 4.0, Vector3(1, 0, 0))])
	print("  into wall (-0.5,0,0): ", _cast(Vector3(0.7, 2, 0), Vector3(-0.5, 0, 0)))
	print("  along wall (0,0,2): ", _cast(Vector3(0.7, 2, 0), Vector3(0, 0, 2)))
	print("  away (+0.5,0,0): ", _cast(Vector3(0.7, 2, 0), Vector3(0.5, 0, 0)))
	print("  after push-out to x=1.02, into wall (-0.5): ", _cast(Vector3(1.02, 2, 0), Vector3(-0.5, 0, 0)))
	print("  after push-out to x=1.02 rest: ", "hit n=%s" % _rr.normal if _rest(Vector3(1.02, 2, 0)) else "NONE")
	# G. Randomised (fixed seed) overlap sweep against random wall orientations: max error of the formula
	print("G. 2000 random overlaps (fixed seed): wall normal tilt in [-30,60] deg, yaw any, depth in (0, R)")
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var max_err: float = 0.0
	var misses: int = 0
	var bad_n: int = 0
	var max_p_off: float = 0.0
	for i: int in 40:
		var yaw: float = rng.randf_range(-PI, PI)
		var tilt: float = deg_to_rad(rng.randf_range(-30.0, 60.0))
		var n: Vector3 = Vector3(cos(tilt) * cos(yaw), sin(tilt), cos(tilt) * sin(yaw)).normalized()
		var u: Vector3 = (Vector3(0, 1, 0).cross(n)).normalized()
		var v: Vector3 = n.cross(u).normalized()
		var o: Vector3 = Vector3(rng.randf_range(-50, 50), rng.randf_range(-5, 5), rng.randf_range(-50, 50))
		_space([_quad(o - v * 6.0, u, v, 6.0, 12.0, n)])
		for k: int in 50:
			var depth: float = rng.randf_range(0.01, 0.99)
			var c: Vector3 = o + n * (R - depth) + u * rng.randf_range(-4.0, 4.0) + v * rng.randf_range(-4.0, 4.0)
			if not _rest(c):
				misses += 1
				continue
			var d_formula: float = R - (c - _rr.point).dot(_rr.normal)
			max_err = maxf(max_err, absf(d_formula - depth))
			max_p_off = maxf(max_p_off, absf((_rr.point - o).dot(n)))
			if _rr.normal.dot(n) < 0.999:
				bad_n += 1
	print("  misses=%d normal_not_face(<0.999)=%d max|d_formula-true|=%.7f max|point off plane|=%.7f" % [misses, bad_n, max_err, max_p_off])
