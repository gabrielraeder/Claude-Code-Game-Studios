extends GdUnitTestSuite
## Core-rebuild story 007 (TD-012): the analytic mover sweep was rewritten for speed (Newton's method
## from the start of the motion, then bisection, replacing story 005's golden-section search). These
## tests show the new sweep_walls agrees with the old routine, kept below as a reference only
## (_ref_sweep / _ref_find_contact: story 005's _sweep_local and _find_contact, verbatim apart from
## reading the query's _closest_local scratch), on hit / miss, time of impact, contact point and
## normal, for every mover kind (box, capsule, cylinder), a tilted still mover and two rotating
## movers, at several tick times. Movers are built in code (collision_fixtures.gd); the sample
## sweeps come from a fixed Fibonacci sphere of directions: no randomness, no clock, no files.
##
## Tolerances, derived from the sweep tolerance TOL = MOVER_SWEEP_TOLERANCE (both routines report a
## safe fraction at most TOL short of the true first contact, so their sphere centres differ by at
## most TOL along the motion):
##   - time of impact: |fraction_new - fraction_old| x length <= TOL (+ float slack);
##   - contact point: <= TOL (+ float slack): the closest point of a convex set is 1-Lipschitz;
##   - normal: angle <= 2 TOL / R (+ margin): the normal is the unit vector from the contact to a
##     centre about R away.
## Every non-touch hit of the new routine must also leave the sphere clear at its reported fraction.
## Samples whose answer is decided inside the tolerance band are not compared (AMBIGUOUS_GAP): a
## graze (the path's minimum gap within AMBIGUOUS_GAP of 0), a first contact within AMBIGUOUS_GAP of
## the end (touch versus block), or an end gap within AMBIGUOUS_GAP of 0.
## Coverage asserted per test: at least COMPARED_SHARE of the samples compared, MIN_EACH hits at
## every time step and MIN_EACH misses overall, and at least MIN_FEATURE hits on every contact
## feature of the shape (box face / edge / corner, cylinder side / cap / rim, capsule side / cap),
## classified by the mover-local normal. The counts are printed.

const Fixtures = preload("res://tests/unit/collision/collision_fixtures.gd")

## Sweep sphere radius (m) and the sweep tolerance (m).
const R: float = Fixtures.SWEEP_RADIUS
const TOL: float = CollisionQuery.MOVER_SWEEP_TOLERANCE
## Float slack (m) for float32 positions a few metres from the origin.
const FLOAT_SLACK: float = 0.00001
## Allowed differences (see the header): fraction x length (m), contact point (m), normal (rad).
const FRACTION_LENGTH_TOLERANCE: float = TOL + FLOAT_SLACK
const POINT_TOLERANCE: float = TOL + FLOAT_SLACK
const NORMAL_TOLERANCE: float = 2.0 * TOL / R + 0.0001
## Width of the band around a decision boundary whose samples are not compared (m).
const AMBIGUOUS_GAP: float = 0.001
## Directions on the Fibonacci sphere the sweeps start from, and the golden angle (rad) spacing them.
const DIRECTIONS: int = 24
const GOLDEN_ANGLE: float = 2.399963229728653
## Start distance from the mover centre, as a multiple of (shape bound + R).
const START_DISTANCE: float = 1.6
## Aim offsets from the mover centre (multiples of the shape bound) and motion lengths (multiples
## of the start distance): some sweeps stop short, some hit, some pass beside. The last two aim
## past a box corner and a cylinder rim, so those features are hit too.
const AIM_OFFSETS: Array[Vector3] = [Vector3.ZERO, Vector3(0.6, 0.3, -0.2), Vector3(-0.4, 0.9, 0.7),
		Vector3(1.0, 0.4, 0.55), Vector3(0.6, 0.9, 0.0)]
const LENGTH_FACTORS: PackedFloat64Array = [0.2, 0.55, 1.4]
## Coverage: share of samples compared, hits per time step and misses overall, hits per feature.
const COMPARED_SHARE: float = 0.5
const MIN_EACH: int = 15
const MIN_FEATURE: int = 1
## A normal component below this counts as zero when classifying the contact feature.
const FEATURE_EPSILON: float = 0.001
## Golden-section iterations of the reference minimum-gap search (ambiguity filter only).
const MIN_GAP_ITERATIONS: int = 80
## 1 / golden ratio (reference searches only).
const INV_PHI: float = 0.6180339887498949
## Mover id used by every test, and the centre and sizes of every mover.
const ID: int = 4
const AT: Vector3 = Vector3(1.0, 2.0, -3.0)
const BOX_HALF: Vector3 = Vector3(1.5, 0.5, 0.75)
const ROUND_RADIUS: float = 0.8
const ROUND_HALF_HEIGHT: float = 1.2
const TILT_AXIS: Vector3 = Vector3(1.0, 1.0, 0.0)
const TILT_ANGLE: float = 0.7
## Tick times the rotating movers are sampled at (s; 3.5 is in the spinner's loop segment).
const SPIN_TIMES: PackedFloat64Array = [0.0, 0.4, 1.25, 3.5]
## Tumbling capsule: period (s) and the angle (rad) per key about a tilted axis.
const TUMBLE_PERIOD: float = 3.0
const TUMBLE_STEP: float = 2.0
const TUMBLE_AXIS: Vector3 = Vector3(0.3, 1.0, 0.5)


## Shape bound of [param mover] (radius of a sphere about its origin holding the shape).
func _bound(mover: MoverDef) -> float:
	match mover.shape:
		MoverDef.Shape.BOX:
			return mover.half_extents.length()
		MoverDef.Shape.CAPSULE:
			return mover.radius + mover.half_height
		_:
			return sqrt(mover.radius * mover.radius + mover.half_height * mover.half_height)


## The contact features of [param mover]'s shape, in classification order.
func _features(mover: MoverDef) -> PackedStringArray:
	match mover.shape:
		MoverDef.Shape.BOX:
			return ["face", "edge", "corner"]
		MoverDef.Shape.CAPSULE:
			return ["side", "cap"]
		_:
			return ["side", "cap", "rim"]


## The feature of [param mover] whose outward normal is the mover-local [param n].
func _feature_of(mover: MoverDef, n: Vector3) -> String:
	match mover.shape:
		MoverDef.Shape.BOX:
			var nonzero: int = 0
			for axis in 3:
				if absf(n[axis]) > FEATURE_EPSILON:
					nonzero += 1
			return ["face", "face", "edge", "corner"][nonzero]
		MoverDef.Shape.CAPSULE:
			return "side" if absf(n.y) < FEATURE_EPSILON else "cap"
		_:
			if absf(n.y) < FEATURE_EPSILON:
				return "side"
			return "cap" if absf(n.y) > 1.0 - FEATURE_EPSILON else "rim"


## Story 005's golden-section search (reference only).
func _ref_find_contact(q: CollisionQuery, mover: MoverDef, local_from: Vector3, local_motion: Vector3, length: float, radius: float) -> float:
	var a: float = 0.0
	var b: float = 1.0
	var c: float = b - INV_PHI * (b - a)
	var d: float = a + INV_PHI * (b - a)
	var fc: float = q._closest_local(mover, local_from + local_motion * c) - radius
	if fc <= 0.0:
		return c
	var fd: float = q._closest_local(mover, local_from + local_motion * d) - radius
	if fd <= 0.0:
		return d
	var iterations: int = 0
	while (b - a) * length > CollisionQuery.MOVER_SWEEP_TOLERANCE and iterations < CollisionQuery.MOVER_SWEEP_MAX_ITERATIONS:
		if maxf(fc, fd) > (b - a) * length:
			return -1.0
		if fc < fd:
			b = d
			d = c
			fd = fc
			c = b - INV_PHI * (b - a)
			fc = q._closest_local(mover, local_from + local_motion * c) - radius
			if fc <= 0.0:
				return c
		else:
			a = c
			c = d
			fc = fd
			d = a + INV_PHI * (b - a)
			fd = q._closest_local(mover, local_from + local_motion * d) - radius
			if fd <= 0.0:
				return d
		iterations += 1
	return -1.0


## Story 005's _sweep_local (reference only). Returns [] on a miss, else [fraction, local point,
## local normal].
func _ref_sweep(q: CollisionQuery, mover: MoverDef, local_from: Vector3, local_motion: Vector3, length: float, radius: float, gap0: float) -> Array:
	var gap1: float = q._closest_local(mover, local_from + local_motion) - radius
	var hi: float = 1.0
	if gap1 > 0.0:
		if gap0 + gap1 > length:
			return []
		hi = _ref_find_contact(q, mover, local_from, local_motion, length, radius)
		if hi < 0.0:
			return []
	var lo: float = 0.0
	var iterations: int = 0
	while (hi - lo) * length > CollisionQuery.MOVER_SWEEP_TOLERANCE and iterations < CollisionQuery.MOVER_SWEEP_MAX_ITERATIONS:
		var mid: float = (lo + hi) * 0.5
		if q._closest_local(mover, local_from + local_motion * mid) - radius <= 0.0:
			hi = mid
		else:
			lo = mid
		iterations += 1
	var fraction: float = lo
	if gap1 <= 0.0 and hi == 1.0:
		fraction = 1.0
	q._closest_local(mover, local_from + local_motion * fraction)
	return [fraction, q._cl_point, q._cl_normal]


## Minimum of the convex gap along the motion (golden-section; ambiguity filter only).
func _min_gap(q: CollisionQuery, mover: MoverDef, local_from: Vector3, local_motion: Vector3) -> float:
	var a: float = 0.0
	var b: float = 1.0
	for _n in MIN_GAP_ITERATIONS:
		var c: float = b - INV_PHI * (b - a)
		var d: float = a + INV_PHI * (b - a)
		if q._closest_local(mover, local_from + local_motion * c) < q._closest_local(mover, local_from + local_motion * d):
			b = d
		else:
			a = c
	return q._closest_local(mover, local_from + local_motion * (a + b) * 0.5) - R


## Checks one compared hit of the new routine against the reference [param ref]; appends failures.
func _check_hit(q: CollisionQuery, mover: MoverDef, pose: Transform3D, local_from: Vector3, local_motion: Vector3,
		length: float, hit: WallHit, ref: Array, label: String, failures: Array[String]) -> void:
	var ref_point: Vector3 = pose * Vector3(ref[1])
	var ref_normal: Vector3 = pose.basis * Vector3(ref[2])
	if absf(hit.fraction - float(ref[0])) * length > FRACTION_LENGTH_TOLERANCE:
		failures.append("%s: fraction %s vs old %s" % [label, hit.fraction, ref[0]])
	if hit.point.distance_to(ref_point) > POINT_TOLERANCE:
		failures.append("%s: point %s vs old %s" % [label, hit.point, ref_point])
	if hit.normal.angle_to(ref_normal) > NORMAL_TOLERANCE:
		failures.append("%s: normal %s vs old %s" % [label, hit.normal, ref_normal])
	if hit.started_inside or hit.collider_id != ID:
		failures.append("%s: started_inside %s collider %d" % [label, hit.started_inside, hit.collider_id])
	# Safety: a blocking hit leaves the sphere clear at its fraction (computed as the query does).
	if hit.fraction < 1.0 and q._closest_local(mover, local_from + local_motion * hit.fraction) - R <= 0.0:
		failures.append("%s: not clear at the reported fraction %s" % [label, hit.fraction])


## Runs every sample sweep against [param mover] at each time of [param times] and compares the new
## sweep_walls with the reference. Returns {samples, compared, misses, hits_per_time, features,
## failures}.
func _compare(mover: MoverDef, times: PackedFloat64Array) -> Dictionary:
	var movers: Array[MoverDef] = [mover]
	var query: CollisionQuery = CollisionQuery.new(Fixtures.movers_only(movers))
	var cursor: QueryCursor = QueryCursor.new()
	var hit: WallHit = WallHit.new()
	var failures: Array[String] = []
	var out: Dictionary = {"samples": 0, "compared": 0, "misses": 0, "hits_per_time": [], "features": {}, "failures": failures}
	for feature in _features(mover):
		out["features"][feature] = 0
	var distance: float = START_DISTANCE * (_bound(mover) + R)
	for t in times:
		var hits_now: int = 0
		var pose: Transform3D = query.mover_pose(ID, t)
		var inv: Transform3D = pose.inverse()
		for i in DIRECTIONS:
			var y: float = 1.0 - 2.0 * (float(i) + 0.5) / float(DIRECTIONS)
			var ring: float = sqrt(1.0 - y * y)
			var phi: float = GOLDEN_ANGLE * float(i)
			var from: Vector3 = pose.origin + Vector3(ring * cos(phi), y, ring * sin(phi)) * distance
			for aim in AIM_OFFSETS:
				for factor in LENGTH_FACTORS:
					out["samples"] += 1
					var target: Vector3 = pose.origin + pose.basis * (aim * _bound(mover))
					var to: Vector3 = from + (target - from).normalized() * distance * factor
					var local_from: Vector3 = inv * from
					var local_motion: Vector3 = inv.basis * (to - from)
					var length: float = (to - from).length()
					var gap0: float = query._closest_local(mover, local_from) - R
					var gap1: float = query._closest_local(mover, local_from + local_motion) - R
					if gap0 <= AMBIGUOUS_GAP or absf(gap1) < AMBIGUOUS_GAP or absf(_min_gap(query, mover, local_from, local_motion)) < AMBIGUOUS_GAP:
						continue
					var ref: Array = _ref_sweep(query, mover, local_from, local_motion, length, R, gap0)
					if not ref.is_empty() and (1.0 - float(ref[0])) * length < AMBIGUOUS_GAP:
						continue
					var got: bool = query.sweep_walls(cursor, from, to, R, t, hit)
					out["compared"] += 1
					var label: String = "t=%s from=%s to=%s" % [t, from, to]
					if ref.is_empty():
						out["misses"] += 1
						if got:
							failures.append("%s: new hit (fraction %s), old missed" % [label, hit.fraction])
						continue
					hits_now += 1
					if not got:
						failures.append("%s: new missed, old hit at fraction %s" % [label, ref[0]])
						continue
					out["features"][_feature_of(mover, inv.basis * hit.normal)] += 1
					_check_hit(query, mover, pose, local_from, local_motion, length, hit, ref, label, failures)
		out["hits_per_time"].append(hits_now)
	query.dispose()
	return out


func _assert_agrees(name: String, mover: MoverDef, times: PackedFloat64Array) -> void:
	var result: Dictionary = _compare(mover, times)
	print("[equivalence] %s: compared %d of %d samples, hits per time %s, misses %d, feature hits %s" % [
			name, result["compared"], result["samples"], result["hits_per_time"], result["misses"], result["features"]])
	var failures: Array[String] = result["failures"]
	assert_array(failures).is_empty()
	assert_int(int(result["compared"])).is_greater_equal(ceili(COMPARED_SHARE * float(result["samples"])))
	for hits in result["hits_per_time"]:
		assert_int(int(hits)).is_greater_equal(MIN_EACH)
	assert_int(int(result["misses"])).is_greater_equal(MIN_EACH)
	for feature in result["features"]:
		assert_int(int(result["features"][feature])).override_failure_message(
				"%s: only %d hits on feature %s" % [name, result["features"][feature], feature]).is_greater_equal(MIN_FEATURE)


func _tilted(shape: MoverDef.Shape) -> MoverDef:
	var key: Vector4 = Fixtures.rot_key(TILT_AXIS.normalized(), TILT_ANGLE)
	var m: MoverDef = Fixtures.mover(ID, shape, 2.0, [0.0, 1.0], [AT, AT], [key, key])
	m.half_extents = BOX_HALF
	m.radius = ROUND_RADIUS
	m.half_height = ROUND_HALF_HEIGHT
	return m


func test_new_sweep_agrees_with_old_on_still_box() -> void:
	_assert_agrees("still box", Fixtures.still_box(ID, AT, BOX_HALF), PackedFloat64Array([0.0]))


func test_new_sweep_agrees_with_old_on_still_capsule() -> void:
	_assert_agrees("still capsule", Fixtures.still_round(ID, MoverDef.Shape.CAPSULE, AT, ROUND_RADIUS, ROUND_HALF_HEIGHT), PackedFloat64Array([0.0]))


func test_new_sweep_agrees_with_old_on_still_cylinder() -> void:
	_assert_agrees("still cylinder", Fixtures.still_round(ID, MoverDef.Shape.CYLINDER, AT, ROUND_RADIUS, ROUND_HALF_HEIGHT), PackedFloat64Array([0.0]))


func test_new_sweep_agrees_with_old_on_tilted_box_and_cylinder() -> void:
	_assert_agrees("tilted box", _tilted(MoverDef.Shape.BOX), PackedFloat64Array([0.0]))
	_assert_agrees("tilted cylinder", _tilted(MoverDef.Shape.CYLINDER), PackedFloat64Array([0.0]))


func test_new_sweep_agrees_with_old_on_spinning_box_at_several_times() -> void:
	_assert_agrees("spinning box", Fixtures.spinner_box(ID, AT, BOX_HALF), SPIN_TIMES)


func test_new_sweep_agrees_with_old_on_tumbling_capsule_at_several_times() -> void:
	var axis: Vector3 = TUMBLE_AXIS.normalized()
	var m: MoverDef = Fixtures.mover(ID, MoverDef.Shape.CAPSULE, TUMBLE_PERIOD, [0.0, 1.0, 2.0], [AT, AT + Vector3.UP, AT],
			[Fixtures.rot_key(axis, 0.0), Fixtures.rot_key(axis, TUMBLE_STEP), Fixtures.rot_key(axis, 2.0 * TUMBLE_STEP)])
	m.radius = ROUND_RADIUS
	m.half_height = ROUND_HALF_HEIGHT
	_assert_agrees("tumbling capsule", m, SPIN_TIMES)


func test_new_sweep_same_inputs_give_bit_identical_results() -> void:
	# Arrange: a spinning box; one sweep that hits it, run on two fresh queries and twice on one.
	var movers: Array[MoverDef] = [Fixtures.spinner_box(ID, AT, BOX_HALF)]
	var data: TrackCollisionData = Fixtures.movers_only(movers)
	var a: CollisionQuery = CollisionQuery.new(data)
	var b: CollisionQuery = CollisionQuery.new(data)
	var cursor: QueryCursor = QueryCursor.new()
	var from: Vector3 = AT + Vector3(4.0, 0.2, 0.5)
	var to: Vector3 = AT + Vector3(-1.0, 0.2, 0.3)
	var t: float = 0.4
	var h1: WallHit = WallHit.new()
	var h2: WallHit = WallHit.new()
	var h3: WallHit = WallHit.new()
	# Act
	var hit1: bool = a.sweep_walls(cursor, from, to, R, t, h1)
	var hit2: bool = a.sweep_walls(cursor, from, to, R, t, h2)
	var hit3: bool = b.sweep_walls(cursor, from, to, R, t, h3)
	a.dispose()
	b.dispose()
	# Assert
	assert_bool(hit1).is_true()
	assert_bool(hit2).is_true()
	assert_bool(hit3).is_true()
	for h in [h2, h3]:
		assert_float(h.fraction).is_equal(h1.fraction)
		assert_vector(h.point).is_equal(h1.point)
		assert_vector(h.normal).is_equal(h1.normal)
		assert_vector(h.collider_velocity).is_equal(h1.collider_velocity)


func test_cached_pose_equals_fresh_query_pose_at_each_time() -> void:
	# Arrange: one query evaluated at many times in a row (the cache in use) against a fresh query
	# per time (no cache). Spinner times cover a key time and the loop segment.
	var movers: Array[MoverDef] = [Fixtures.spinner_box(ID, AT, BOX_HALF)]
	var data: TrackCollisionData = Fixtures.movers_only(movers)
	var cached: CollisionQuery = CollisionQuery.new(data)
	var probe: Vector3 = AT + Vector3(1.0, 0.0, 0.5)
	for t in [0.0, 1.0, 1.0, 2.5, 3.5, 0.0, 3.999]:
		var fresh: CollisionQuery = CollisionQuery.new(data)
		# Act
		var pose_cached: Transform3D = cached.mover_pose(ID, t)
		var vel_cached: Vector3 = cached.mover_point_velocity(ID, t, probe)
		var pose_fresh: Transform3D = fresh.mover_pose(ID, t)
		var vel_fresh: Vector3 = fresh.mover_point_velocity(ID, t, probe)
		fresh.dispose()
		# Assert
		assert_bool(pose_cached == pose_fresh).is_true()
		assert_vector(vel_cached).is_equal(vel_fresh)
	cached.dispose()
