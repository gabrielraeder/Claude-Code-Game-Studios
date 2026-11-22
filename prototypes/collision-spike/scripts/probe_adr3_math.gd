## Scratch probe for ADR-0003 review (godot-specialist). PROTOTYPE - NOT FOR PRODUCTION.
## (2) Geometry3D segment closest points: allocation and cost for 66 pairs/tick,
##     vs an allocation-free GDScript helper.
## (3) Up slerp + heading rotate + basis rebuild per kart per tick, 12 karts:
##     cost, orthonormality over 36,000 ticks, Basis(x, y, z) column semantics,
##     Vector3.slerp degenerate cases.
## Run: godot --headless --path prototypes/collision-spike -s res://scripts/probe_adr3_math.gd
extends SceneTree

const PAIRS: int = 66
const TICKS: int = 3000
const KARTS: int = 12

var _c1: Vector3
var _c2: Vector3


## Ericson, Real-Time Collision Detection 5.1.9. Writes into _c1/_c2, returns squared distance.
func _closest_seg_seg(p1: Vector3, q1: Vector3, p2: Vector3, q2: Vector3) -> float:
	var d1: Vector3 = q1 - p1
	var d2: Vector3 = q2 - p2
	var r: Vector3 = p1 - p2
	var a: float = d1.dot(d1)
	var e: float = d2.dot(d2)
	var f: float = d2.dot(r)
	var s: float = 0.0
	var t: float = 0.0
	const EPS: float = 1e-12
	if a <= EPS and e <= EPS:
		_c1 = p1; _c2 = p2
		return r.dot(r)
	if a <= EPS:
		t = clampf(f / e, 0.0, 1.0)
	else:
		var c: float = d1.dot(r)
		if e <= EPS:
			s = clampf(-c / a, 0.0, 1.0)
		else:
			var b: float = d1.dot(d2)
			var denom: float = a * e - b * b
			s = clampf((b * f - c * e) / denom, 0.0, 1.0) if denom != 0.0 else 0.0
			t = (b * s + f) / e
			if t < 0.0:
				t = 0.0; s = clampf(-c / a, 0.0, 1.0)
			elif t > 1.0:
				t = 1.0; s = clampf((b - c) / a, 0.0, 1.0)
	_c1 = p1 + d1 * s
	_c2 = p2 + d2 * t
	return (_c1 - _c2).length_squared()


func _initialize() -> void:
	print("engine=", Engine.get_version_info().string, " debug_build=", OS.is_debug_build())
	_geom()
	_basis()
	quit()


func _geom() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var a0 := PackedVector3Array(); var a1 := PackedVector3Array()
	for i: int in 12:
		var c := Vector3(rng.randf_range(-20, 20), rng.randf_range(-1, 1), rng.randf_range(-20, 20))
		var h := Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized() * 0.9
		a0.append(c - h); a1.append(c + h)
	var res: PackedVector3Array = Geometry3D.get_closest_points_between_segments(a0[0], a1[0], a0[1], a1[1])
	print("G. Geometry3D.get_closest_points_between_segments returns type=", type_string(typeof(res)), " size=", res.size())
	# Distinct allocation per call: hold N results, static memory grows ~N * buffer
	var hold: Array = []
	hold.resize(10000)
	var m0: int = OS.get_static_memory_usage()
	for k: int in 10000:
		hold[k] = Geometry3D.get_closest_points_between_segments(a0[k % 12], a1[k % 12], a0[(k + 1) % 12], a1[(k + 1) % 12])
	var m1: int = OS.get_static_memory_usage()
	print("   holding 10000 results: static mem +%d bytes (%.1f B/result) -> one heap buffer per call" % [m1 - m0, float(m1 - m0) / 10000.0])
	hold.clear()
	# Correctness of the helper vs Geometry3D (random segments)
	var max_diff: float = 0.0
	for k: int in 5000:
		var p1 := Vector3(rng.randf_range(-3, 3), rng.randf_range(-3, 3), rng.randf_range(-3, 3))
		var q1 := p1 + Vector3(rng.randf_range(-2, 2), rng.randf_range(-2, 2), rng.randf_range(-2, 2))
		var p2 := Vector3(rng.randf_range(-3, 3), rng.randf_range(-3, 3), rng.randf_range(-3, 3))
		var q2 := p2 + Vector3(rng.randf_range(-2, 2), rng.randf_range(-2, 2), rng.randf_range(-2, 2))
		if k % 50 == 0:
			q2 = p2 + (q1 - p1)  # parallel case
		var g: PackedVector3Array = Geometry3D.get_closest_points_between_segments(p1, q1, p2, q2)
		var d_h: float = sqrt(_closest_seg_seg(p1, q1, p2, q2))
		max_diff = maxf(max_diff, absf(d_h - g[0].distance_to(g[1])))
	print("   helper vs Geometry3D distance, 5000 random (1/50 parallel): max |diff| = %.7f m" % max_diff)
	# Timing: 66 pairs per tick
	var sink: float = 0.0
	for rep: int in 2:
		var t0: int = Time.get_ticks_usec()
		for tick: int in TICKS:
			for i: int in 12:
				for j: int in range(i + 1, 12):
					var g2: PackedVector3Array = Geometry3D.get_closest_points_between_segments(a0[i], a1[i], a0[j], a1[j])
					sink += g2[0].x
		var t1: int = Time.get_ticks_usec()
		for tick: int in TICKS:
			for i: int in 12:
				for j: int in range(i + 1, 12):
					sink += _closest_seg_seg(a0[i], a1[i], a0[j], a1[j])
		var t2: int = Time.get_ticks_usec()
		for tick: int in TICKS:
			for i: int in 12:
				for j: int in range(i + 1, 12):
					sink += (a0[i] - a0[j]).length_squared()
		var t3: int = Time.get_ticks_usec()
		print("   rep%d per tick (66 pairs): Geometry3D=%.2f us  GDScript helper=%.2f us  loop+1 dist baseline=%.2f us" % [
			rep, float(t1 - t0) / TICKS, float(t2 - t1) / TICKS, float(t3 - t2) / TICKS])
	print("   sink=", sink != 0.0)


func _rebuild(basis: Basis, up: Vector3, last_heading: Vector3) -> Basis:
	var f: Vector3 = -basis.z
	var h: Vector3 = f - up * f.dot(up)
	if h.length_squared() < 1e-8:
		h = last_heading
	h = h.normalized()
	var z: Vector3 = -h
	var x: Vector3 = up.cross(z)
	return Basis(x, up, z)


func _ortho_err(b: Basis) -> float:
	var e: float = 0.0
	e = maxf(e, absf(b.x.length() - 1.0)); e = maxf(e, absf(b.y.length() - 1.0)); e = maxf(e, absf(b.z.length() - 1.0))
	e = maxf(e, absf(b.x.dot(b.y))); e = maxf(e, absf(b.y.dot(b.z))); e = maxf(e, absf(b.z.dot(b.x)))
	return e


func _basis() -> void:
	var b0 := Basis(Vector3(1, 0, 0), Vector3(0, 2, 0), Vector3(0, 0, 3))
	print("B. Basis(x,y,z) is columns: b.x=%s b.y=%s b.z=%s (expect (1,0,0) (0,2,0) (0,0,3)); row0=%s" % [b0.x, b0.y, b0.z, b0[0]])
	var up0 := Vector3(0, 1, 0)
	print("   Vector3.slerp antiparallel: (0,1,0).slerp((0,-1,0), 0.5)=%s ; near-anti (0,1,0)->(1e-4,-1,0) w=0.5 =%s" % [
		up0.slerp(Vector3(0, -1, 0), 0.5), up0.slerp(Vector3(1e-4, -1, 0).normalized(), 0.5)])
	print("   Vector3.slerp parallel: (0,1,0).slerp((0,1,0),0.3)=%s ; unit-length preserved for 30deg: |s|=%.9f" % [
		up0.slerp(up0, 0.3), up0.slerp(Vector3(0.5, 0.866025, 0).normalized(), 0.37).length()])
	# Long run: 36,000 ticks, deterministic varying normals and yaw rates.
	var dt: float = 1.0 / 60.0
	for normalize_up: bool in [false, true]:
		var basis := Basis.IDENTITY
		var up := Vector3.UP
		var last_heading := Vector3(0, 0, -1)
		var max_err: float = 0.0
		var max_up_dev: float = 0.0
		var max_uplen_dev: float = 0.0
		for n: int in 36000:
			var tt: float = n * dt
			var target := Vector3(0.5 * sin(tt * 0.7), 1.0, 0.5 * cos(tt * 0.31)).normalized()
			var yaw_rate: float = 2.5 * sin(tt * 0.9)
			var f: Vector3 = (-basis.z).rotated(up, yaw_rate * dt)
			basis = Basis(up.cross(-f), up, -f)
			up = up.slerp(target, 1.0 - exp(-14.0 * dt))
			if normalize_up:
				up = up.normalized()
			basis = _rebuild(basis, up, last_heading)
			last_heading = -basis.z
			max_err = maxf(max_err, _ortho_err(basis))
			max_up_dev = maxf(max_up_dev, (basis.y - up).length())
			max_uplen_dev = maxf(max_uplen_dev, absf(up.length() - 1.0))
		print("   36000 ticks normalize_up=%s: max ortho err=%.8f  max |basis.y-up|=%.8f  max ||up|-1|=%.8f  final ortho err=%.8f" % [
			normalize_up, max_err, max_up_dev, max_uplen_dev, _ortho_err(basis)])
	# Timing: 12 karts per tick, full up+basis block (rotate heading, slerp, normalize, rebuild)
	var bases: Array[Basis] = []
	var ups: Array[Vector3] = []
	var lh: Array[Vector3] = []
	for k: int in KARTS:
		bases.append(Basis.IDENTITY); ups.append(Vector3.UP); lh.append(Vector3(0, 0, -1))
	var w: float = 1.0 - exp(-14.0 * dt)
	for rep: int in 2:
		var t0: int = Time.get_ticks_usec()
		for n: int in TICKS:
			var tt: float = n * dt
			for k: int in KARTS:
				var up: Vector3 = ups[k]
				var target := Vector3(0.3 * sin(tt + k), 1.0, 0.3 * cos(tt * 0.5 + k)).normalized()
				var f: Vector3 = (-bases[k].z).rotated(up, 0.03)
				up = up.slerp(target, w).normalized()
				var h: Vector3 = f - up * f.dot(up)
				if h.length_squared() < 1e-8:
					h = lh[k]
				h = h.normalized()
				bases[k] = Basis(up.cross(-h), up, -h)
				ups[k] = up
				lh[k] = h
		var t1: int = Time.get_ticks_usec()
		# Quaternion variant: q.slerp toward a rotation that aligns up with target
		var qs: Array[Quaternion] = []
		for k: int in KARTS:
			qs.append(Quaternion.IDENTITY)
		var t2: int = Time.get_ticks_usec()
		for n: int in TICKS:
			var tt: float = n * dt
			for k: int in KARTS:
				var q: Quaternion = qs[k]
				var target := Vector3(0.3 * sin(tt + k), 1.0, 0.3 * cos(tt * 0.5 + k)).normalized()
				var cur_up: Vector3 = q * Vector3.UP
				var align := Quaternion(cur_up, target)
				q = (Quaternion.IDENTITY.slerp(align, w) * q * Quaternion(Vector3.UP, 0.03)).normalized()
				qs[k] = q
				var bb := Basis(q)
		var t3: int = Time.get_ticks_usec()
		print("   rep%d per tick, 12 karts: Vector3 slerp + basis rebuild=%.2f us (%.2f us/kart)  Quaternion variant=%.2f us" % [
			rep, float(t1 - t0) / TICKS, float(t1 - t0) / TICKS / KARTS, float(t3 - t2) / TICKS])
