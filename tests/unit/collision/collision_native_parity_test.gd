extends GdUnitTestSuite
## Core-rebuild story 067: parity of the native CollisionQuery with the frozen GDScript oracle
## (OracleCollisionQuery, tests/oracle/collision/) on the story-005 and story-007 fixtures, on mirrored data and
## on the bench mesh (ADR-0007 section 5, "Parity tests"). Seeded pseudo-random casts and sweeps (a fixed seed:
## deterministic), the same inputs to both, plus targeted cases: the touch boundary, the Newton cap and the
## unsafe-point retry.
##
## Exact: hit/miss, surface ids, wall-attribute ids, collider ids and started_inside. EXCEPT inside the band
## where the oracle's clearance or penetration depth to a mover is below BAND (1e-4 m): there float32
## rounding may legitimately flip a hit, so the case is excluded from the exact check and COUNTED; the counts
## are printed ("PARITY ..." lines). Tolerances (each written with its reason, never widened silently):
##   static ray distance 1e-5 m (ADR-0007 section 5, unchanged);
##   MOVER ray distance MOVER_RAY_TOLERANCE: the observed maximum rounded up (a DEVIATION from section 5, see
##   its comment and production/qa/evidence/core-rebuild-story-067/deviations.md);
##   sweep fraction 1e-3; normal angle 1e-4 rad;
##   contact point 1e-3 m and collider velocity 1e-3 m/s (mine: the sweep point is the refined contact, whose
##   position moves with the fraction tolerance; the velocity is v + omega x r on that point);
##   mover pose 1e-5 (translation m / basis) and point velocity 1e-4 m/s (mine: float32 slerp, same math).
## The native fail-closed fallback counter (blocked_fallback_count) must equal the run's expected count, 0 everywhere
## except where a fixture's RANDOM grazing sweeps reach it (ground_with_walls: pinned, see its test). The oracle takes
## the same fallback on the same inputs (the parity check passes on them), so the count is a property of the input,
## not a native difference.

const _GUARD = preload("res://tests/unit/native/native_test_guard.gd")
const Fixtures = preload("res://tests/unit/collision/collision_fixtures.gd")
const BenchFixture = preload("res://tools/bench_track_fixture.gd")

## Clearance / penetration band (m) below which a flipped result is excluded and counted.
const BAND: float = 1e-4
const RAY_DISTANCE_TOLERANCE: float = 1e-5
## Ray-distance tolerance for MOVER hits (collider_id != 0), m. The OBSERVED maximum over every run of this suite
## (the "mover_ray_max" of the PARITY lines: 4.685e-5 on the bench mesh, 32 mover hits at 100 m or more from the
## origin; 1.4e-6 or less on every unit fixture), rounded up to 5e-5. The cause is shown by test_mover_local_transform_*: the engine's Transform3D multiply
## and godot-cpp's round differently by an ulp of the coordinate, and a grazing ray amplifies it. Static
## hits keep RAY_DISTANCE_TOLERANCE exactly.
const MOVER_RAY_TOLERANCE: float = 5e-5
const FRACTION_TOLERANCE: float = 1e-3
const NORMAL_ANGLE_TOLERANCE: float = 1e-4
const POINT_TOLERANCE: float = 1e-3
const VELOCITY_TOLERANCE: float = 1e-3
const POSE_TOLERANCE: float = 1e-5
const POINT_VELOCITY_TOLERANCE: float = 1e-4
const SEED: int = 67
const RAYS: int = 1500
const SWEEPS: int = 1500
const POSES: int = 200
## Tick time step (ADR-0001) used to build the t values: every query of one tick passes the identical t.
const SIM_DT: float = 1.0 / 60.0
const TICKS: int = 480
## The captured sweep of collision_unsafe_point_retry_test.gd (bench mesh, rest check misses at the unsafe point).
const RETRY_FROM: Vector3 = Vector3(213.37308, -0.99377036, -13.371248)
const RETRY_TO: Vector3 = Vector3(213.40935, -1.0054376, -12.961111)
## Lateral reach of the bench mesh's walls (m from the road centre) and the wall sweep sampler's start range.
const BENCH_WALL_LATERAL: float = 14.5


func before() -> void:
	assert_str(_GUARD.problem()).is_empty()


## The AABB of everything in [param data] plus its mover positions, and the mover anchors.
func _extent(data: TrackCollisionData) -> Dictionary:
	var lo: Vector3 = Vector3(INF, INF, INF)
	var hi: Vector3 = Vector3(-INF, -INF, -INF)
	var anchors: PackedVector3Array = PackedVector3Array()
	var sets: Array[PackedVector3Array] = [data.ground_faces]
	sets.append_array(data.wall_faces)
	for m: MoverDef in data.movers:
		sets.append(m.key_pos)
		anchors.append_array(m.key_pos)
	for pts in sets:
		for p in pts:
			lo = lo.min(p)
			hi = hi.max(p)
	if lo.x == INF:
		lo = -Vector3.ONE
		hi = Vector3.ONE
	return {"lo": lo - Vector3.ONE * 2.0, "hi": hi + Vector3.ONE * 2.0, "anchors": anchors}


func _random_point(rng: RandomNumberGenerator, ext: Dictionary) -> Vector3:
	var anchors: PackedVector3Array = ext["anchors"]
	if not anchors.is_empty() and rng.randf() < 0.6:
		var a: Vector3 = anchors[rng.randi() % anchors.size()]
		return a + Vector3(rng.randf_range(-4.0, 4.0), rng.randf_range(-3.0, 3.0), rng.randf_range(-4.0, 4.0))
	var lo: Vector3 = ext["lo"]
	var hi: Vector3 = ext["hi"]
	return Vector3(rng.randf_range(lo.x, hi.x), rng.randf_range(lo.y, hi.y), rng.randf_range(lo.z, hi.z))


## True when [param p] (a sweep start or end, or a ray origin with radius 0) lies within BAND of touching a
## solid mover of [param oracle] at [param t]: the case where float rounding may flip a result.
func _in_band(oracle: OracleCollisionQuery, data: TrackCollisionData, p: Vector3, radius: float, t: float) -> bool:
	for m: MoverDef in data.movers:
		if not m.solid:
			continue
		var local: Vector3 = oracle.mover_pose(m.id, t).affine_inverse() * p
		if absf(oracle._closest_local(m, local) - radius) < BAND:
			return true
	return false


## Classifies one pair of results: "exact" (they agree on the exact fields), "excluded" (they differ inside the
## band: counted, not failed) or "mismatch" (they differ outside it).
func _judge(native_hit: bool, oracle_hit: bool, native_inside: bool, oracle_inside: bool, native_collider: int, oracle_collider: int, banded: bool) -> String:
	if native_hit == oracle_hit and native_inside == oracle_inside and native_collider == oracle_collider:
		return "exact"
	return "excluded" if banded else "mismatch"


## Largest absolute coordinate of [param v].
func _mag(v: Vector3) -> float:
	return maxf(maxf(absf(v.x), absf(v.y)), absf(v.z))


func _normal_matches(a: Vector3, b: Vector3) -> bool:
	if a.length_squared() == 0.0 or b.length_squared() == 0.0:
		return a == b
	return a.angle_to(b) <= NORMAL_ANGLE_TOLERANCE


## Runs [param n_rays] casts and [param n_sweeps] sweeps against both queries and returns the counts.
## [param sampler] (optional) is called as sampler.call(rng, kind) -> [origin, dir] for kind 0 and
## [from, to] or [from, to, radius] for kind 1; it replaces the random sampling. [param setup] (optional)
## is called as setup.call(native, oracle) after both are built. The result Dictionary also carries "failures".
func _run(name: String, data: TrackCollisionData, sampler: Callable = Callable(), setup: Callable = Callable(), n_rays: int = RAYS, n_sweeps: int = SWEEPS, expected_fallbacks: int = 0) -> Dictionary:
	# Arrange
	var native: CollisionQuery = CollisionQuery.create(data.pack_native())
	var oracle: OracleCollisionQuery = OracleCollisionQuery.new(data)
	if setup.is_valid():
		setup.call(native, oracle)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = SEED
	var ext: Dictionary = _extent(data)
	var n_cursor: QueryCursor = QueryCursor.new()
	var o_cursor: OracleQueryCursor = OracleQueryCursor.new()
	var n_ground: GroundHit = GroundHit.new()
	var o_ground: OracleGroundHit = OracleGroundHit.new()
	var n_wall: WallHit = WallHit.new()
	var o_wall: OracleWallHit = OracleWallHit.new()
	var failures: Array[String] = []
	var fallback_seen: int = 0
	var fallback_inputs: Array[String] = []
	var s: Dictionary = {"ray_hits": 0, "ray_mover_hits": 0, "excluded_rays": 0, "sweep_hits": 0, "sweep_mover_hits": 0,
			"sweep_static_hits": 0, "started_inside": 0, "excluded_sweeps": 0, "mover_ray_max": 0.0, "static_ray_max": 0.0, "poses": 0}
	# Act / Assert: casts.
	for i in n_rays:
		var t: float = rng.randi_range(0, TICKS) * SIM_DT
		var origin: Vector3
		var dir: Vector3
		if sampler.is_valid():
			var sample: Array = sampler.call(rng, 0)
			origin = sample[0]
			dir = sample[1]
		else:
			origin = _random_point(rng, ext)
			dir = (Vector3.DOWN + Vector3(rng.randf_range(-0.6, 0.6), 0.0, rng.randf_range(-0.6, 0.6))).normalized() if rng.randf() < 0.7 \
					else Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)).normalized()
		var max_dist: float = rng.randf_range(1.0, 14.0)
		n_ground.clear()
		o_ground.clear()
		var n_hit: bool = native.cast_ground(n_cursor, origin, dir, max_dist, t, n_ground)
		var o_hit: bool = oracle.cast_ground(o_cursor, origin, dir, max_dist, t, o_ground)
		var verdict: String = _judge(n_hit, o_hit, false, false, n_ground.collider_id if n_hit else 0, o_ground.collider_id if o_hit else 0, _in_band(oracle, data, origin, 0.0, t))
		if verdict == "excluded":
			s["excluded_rays"] += 1
			continue
		if verdict == "mismatch":
			failures.append("ray %d hit native=%s oracle=%s origin=%s dir=%s t=%s" % [i, n_hit, o_hit, origin, dir, t])
			continue
		if not n_hit:
			continue
		s["ray_hits"] += 1
		var dist_diff: float = absf((n_ground.point - origin).dot(dir) - (o_ground.point - origin).dot(dir))
		var tolerance: float = RAY_DISTANCE_TOLERANCE
		if o_ground.collider_id != 0:
			s["ray_mover_hits"] += 1
			s["mover_ray_max"] = maxf(s["mover_ray_max"], dist_diff)
			tolerance = MOVER_RAY_TOLERANCE
		else:
			s["static_ray_max"] = maxf(s["static_ray_max"], dist_diff)
		if n_ground.surface_id != o_ground.surface_id or n_ground.collider_id != o_ground.collider_id \
				or dist_diff > tolerance or not _normal_matches(n_ground.normal, o_ground.normal) \
				or (n_ground.collider_velocity - o_ground.collider_velocity).length() > VELOCITY_TOLERANCE:
			failures.append("ray %d surface %d/%d collider %d/%d dist diff %s (tolerance %s) normal %s/%s vel %s/%s" % [i, n_ground.surface_id, o_ground.surface_id,
					n_ground.collider_id, o_ground.collider_id, dist_diff, tolerance, n_ground.normal, o_ground.normal, n_ground.collider_velocity, o_ground.collider_velocity])
	# Sweeps.
	for i in n_sweeps:
		var t: float = rng.randi_range(0, TICKS) * SIM_DT
		var from: Vector3
		var to: Vector3
		var radius: float = rng.randf_range(0.3, 1.2)
		if sampler.is_valid():
			var sample: Array = sampler.call(rng, 1)
			from = sample[0]
			to = sample[1]
			if sample.size() > 2:
				radius = sample[2]
		else:
			from = _random_point(rng, ext)
			to = from + Vector3(rng.randf_range(-6.0, 6.0), rng.randf_range(-3.0, 3.0), rng.randf_range(-6.0, 6.0))
		n_wall.clear()
		o_wall.clear()
		var n_hit: bool = native.sweep_walls(n_cursor, from, to, radius, t, n_wall)
		var o_hit: bool = oracle.sweep_walls(o_cursor, from, to, radius, t, o_wall)
		if native.blocked_fallback_count() > fallback_seen:
			fallback_seen = native.blocked_fallback_count()
			if fallback_inputs.size() < 4:
				fallback_inputs.append("from=%s to=%s r=%s t=%s -> attr %d fraction %s normal %s point %s" % [from, to, radius, t, n_wall.wall_attr, n_wall.fraction, n_wall.normal, n_wall.point])
		var banded: bool = _in_band(oracle, data, from, radius, t) or _in_band(oracle, data, to, radius, t)
		var verdict: String = _judge(n_hit, o_hit, n_wall.started_inside if n_hit else false, o_wall.started_inside if o_hit else false,
				n_wall.collider_id if n_hit else 0, o_wall.collider_id if o_hit else 0, banded)
		if verdict == "excluded":
			s["excluded_sweeps"] += 1
			continue
		if verdict == "mismatch":
			failures.append("sweep %d hit native=%s oracle=%s from=%s to=%s r=%s t=%s" % [i, n_hit, o_hit, from, to, radius, t])
			continue
		if not n_hit:
			continue
		s["sweep_hits"] += 1
		if o_wall.collider_id != 0:
			s["sweep_mover_hits"] += 1
		else:
			s["sweep_static_hits"] += 1
		if o_wall.started_inside:
			s["started_inside"] += 1
		if n_wall.started_inside != o_wall.started_inside or n_wall.wall_attr != o_wall.wall_attr or n_wall.collider_id != o_wall.collider_id \
				or absf(n_wall.fraction - o_wall.fraction) > FRACTION_TOLERANCE or not _normal_matches(n_wall.normal, o_wall.normal) \
				or (n_wall.point - o_wall.point).length() > POINT_TOLERANCE \
				or (n_wall.collider_velocity - o_wall.collider_velocity).length() > VELOCITY_TOLERANCE:
			failures.append("sweep %d inside %s/%s attr %d/%d collider %d/%d fraction %s/%s normal %s/%s from=%s to=%s r=%s t=%s" % [i, n_wall.started_inside,
					o_wall.started_inside, n_wall.wall_attr, o_wall.wall_attr, n_wall.collider_id, o_wall.collider_id, n_wall.fraction, o_wall.fraction,
					n_wall.normal, o_wall.normal, from, to, radius, t])
	# Poses and point velocities.
	for m: MoverDef in data.movers:
		for i in POSES:
			var t: float = rng.randf_range(0.0, 3.0 * m.period)
			var p: Vector3 = m.key_pos[0] + Vector3(rng.randf_range(-2.0, 2.0), rng.randf_range(-2.0, 2.0), rng.randf_range(-2.0, 2.0))
			var pn: Transform3D = native.mover_pose(m.id, t)
			var po: Transform3D = oracle.mover_pose(m.id, t)
			var vn: Vector3 = native.mover_point_velocity(m.id, t, p)
			var vo: Vector3 = oracle.mover_point_velocity(m.id, t, p)
			s["poses"] += 1
			if (pn.origin - po.origin).length() > POSE_TOLERANCE or not pn.basis.is_equal_approx(po.basis) or (vn - vo).length() > POINT_VELOCITY_TOLERANCE:
				failures.append("mover %d t=%s pose/velocity differs: %s vs %s, %s vs %s" % [m.id, t, pn, po, vn, vo])
	var fallbacks: int = native.blocked_fallback_count()
	print("PARITY fixture=%s rays=%d ray_hits=%d ray_mover_hits=%d excluded_rays=%d sweeps=%d sweep_hits=%d sweep_mover_hits=%d sweep_static_hits=%d started_inside=%d excluded_sweeps=%d poses=%d mover_ray_max=%s static_ray_max=%s blocked_fallbacks=%d failures=%d" % [
			name, n_rays, s["ray_hits"], s["ray_mover_hits"], s["excluded_rays"], n_sweeps, s["sweep_hits"], s["sweep_mover_hits"], s["sweep_static_hits"],
			s["started_inside"], s["excluded_sweeps"], s["poses"], s["mover_ray_max"], s["static_ray_max"], fallbacks, failures.size()])
	for line in fallback_inputs:
		print("FALLBACK_INPUT fixture=%s %s" % [name, line])
	native.dispose()
	oracle.dispose()
	assert_array(failures.slice(0, 10)).is_empty()
	if expected_fallbacks >= 0:
		assert_int(fallbacks).override_failure_message("the blocked-hit fallback count differs from the expected %d" % expected_fallbacks).is_equal(expected_fallbacks)
	assert_int(s["excluded_rays"] + s["excluded_sweeps"]).override_failure_message("excluded count too large").is_less(n_rays / 20)
	s["failures"] = failures.size()
	return s


func test_parity_on_the_mirror_fixture_with_all_mover_shapes() -> void:
	_run("mirror_fixture", Fixtures.mirror_fixture())


func test_parity_on_the_mirrored_mirror_fixture() -> void:
	# Arrange: TrackCollisionData.mirrored() (x -> -x, winding flipped, mover keys mirrored).
	_run("mirrored_mirror_fixture", Fixtures.mirror_fixture().mirrored())


func test_parity_on_ground_with_walls() -> void:
	# Arrange / Act: random grazing sweeps at the wall ends of this fixture reach the fail-closed fallback (a cast
	# hit whose unsafe point and 0.001 m retry find no rest contact): 8 of the 1500 seeded sweeps, in the oracle too
	# (its push_warning "no rest contact at the unsafe point"). Pinned: a change in the count is a behaviour change.
	_run("ground_with_walls", Fixtures.ground_with_walls([0, 0, 0, 0]), Callable(), Callable(), RAYS, SWEEPS, 8)


func test_parity_on_attribute_walls() -> void:
	# Pinned: 5 of the 1500 seeded sweeps graze a wall's bottom edge and reach the fail-closed fallback, in the oracle too.
	_run("attr_walls", Fixtures.attr_walls(Fixtures.wall_registry()), Callable(), Callable(), RAYS, SWEEPS, 5)


func test_parity_on_the_inner_corner() -> void:
	# Pinned: 1 of the 1500 seeded sweeps reaches the fail-closed fallback (edge graze), in the oracle too.
	_run("inner_corner", Fixtures.inner_corner(Fixtures.wall_registry()), Callable(), Callable(), RAYS, SWEEPS, 1)


func test_parity_on_spinners_and_a_slider_over_ground() -> void:
	# Arrange: ground plus a spinning box, a sliding box and two still round movers, all solid and close together.
	var data: TrackCollisionData = Fixtures.quadrant_ground([0, 0, 0, 0])
	var spinner: MoverDef = Fixtures.spinner_box(1, Vector3(0.0, 1.0, 0.0), Vector3(1.5, 0.5, 0.4))
	var slider: MoverDef = Fixtures.slide_box(2, Vector3(-3.0, 1.0, 1.5), Vector3(0.6, 0.6, 0.6))
	var capsule: MoverDef = Fixtures.still_round(3, MoverDef.Shape.CAPSULE, Vector3(1.0, 1.0, -1.5), 0.5, 0.8)
	var cylinder: MoverDef = Fixtures.still_round(4, MoverDef.Shape.CYLINDER, Vector3(-1.5, 1.0, -1.0), 0.6, 0.5)
	data.movers = [spinner, slider, capsule, cylinder]
	_run("movers_over_ground", data)


## The bench mesh plus four spinners on its road, and the sampler: kind 0 rays over the movers or the road, kind 1
## sweeps half over the movers and half toward the walls (so the 4,800 wall triangles take part).
func _bench_case() -> Array:
	var bench: BenchFixture = BenchFixture.new()
	bench.build()
	var frame: PackedVector3Array = PackedVector3Array()
	frame.resize(4)
	var movers: Array[MoverDef] = []
	for k in 4:
		bench.frame_at(100.0 + 90.0 * k, 0.0, frame)
		movers.append(Fixtures.spinner_box(k + 1, frame[0] + frame[2] * 1.0, Vector3(2.0, 0.6, 0.5)))
	bench.data.movers = movers
	var sampler: Callable = func(rng: RandomNumberGenerator, kind: int) -> Array:
		var f: PackedVector3Array = PackedVector3Array()
		f.resize(4)
		var s: float = 100.0 + 90.0 * float(rng.randi() % 4) + rng.randf_range(-6.0, 6.0) if rng.randf() < 0.7 else rng.randf_range(0.0, 1200.0)
		if kind == 0:
			bench.frame_at(s, rng.randf_range(-7.0, 7.0), f)
			return [f[0] + f[2] * 2.5, (-f[2] + f[3] * rng.randf_range(-0.3, 0.3)).normalized()]
		if rng.randf() < 0.5:
			bench.frame_at(s, rng.randf_range(-7.0, 7.0), f)
			var start: Vector3 = f[0] + f[2] * 1.2
			return [start, start + f[1] * rng.randf_range(1.0, 7.0) + f[3] * rng.randf_range(-3.0, 3.0)]
		# Toward a wall: start near one side, move outward with some forward motion.
		var side: float = 1.0 if rng.randf() < 0.5 else -1.0
		bench.frame_at(rng.randf_range(0.0, 1200.0), side * rng.randf_range(BENCH_WALL_LATERAL - 4.0, BENCH_WALL_LATERAL), f)
		var from: Vector3 = f[0] + f[2] * 1.2
		return [from, from + f[3] * side * rng.randf_range(0.5, 4.0) + f[1] * rng.randf_range(0.0, 5.0)]
	return [bench, sampler]


func test_parity_on_the_bench_mesh_with_movers_and_walls() -> void:
	# Arrange
	var bench_case: Array = _bench_case()
	var bench: BenchFixture = bench_case[0]
	# Act
	var s: Dictionary = _run("bench_mesh", bench.data, bench_case[1])
	# Assert: the wall triangles took part (static wall hits), as well as the movers.
	assert_int(s["sweep_static_hits"]).override_failure_message("no static wall hits on the bench mesh").is_greater(20)
	assert_int(s["ray_mover_hits"]).is_greater(0)
	assert_float(s["static_ray_max"]).is_less_equal(RAY_DISTANCE_TOLERANCE)


func test_parity_of_the_captured_unsafe_point_retry_sweep() -> void:
	# Arrange: the sweep of collision_unsafe_point_retry_test.gd (bench mesh): the rest check at the cast's
	# unsafe point misses and the 0.001 m retry finds the wall.
	var bench: BenchFixture = BenchFixture.new()
	bench.build()
	var native: CollisionQuery = CollisionQuery.create(bench.data.pack_native())
	var oracle: OracleCollisionQuery = OracleCollisionQuery.new(bench.data)
	var n_hit: WallHit = WallHit.new()
	var o_hit: OracleWallHit = OracleWallHit.new()
	# Act
	var n_did: bool = native.sweep_walls(QueryCursor.new(), RETRY_FROM, RETRY_TO, 1.0, 0.0, n_hit)
	var o_did: bool = oracle.sweep_walls(OracleQueryCursor.new(), RETRY_FROM, RETRY_TO, 1.0, 0.0, o_hit)
	var fallbacks: int = native.blocked_fallback_count()
	native.dispose()
	oracle.dispose()
	# Assert: the retry found the wall in both, and the fallback did not run.
	assert_bool(n_did).is_true()
	assert_bool(o_did).is_true()
	assert_int(n_hit.wall_attr).is_equal(o_hit.wall_attr)
	assert_int(n_hit.wall_attr).is_not_equal(CollisionQuery.WALL_ATTR_NONE)
	assert_float(n_hit.fraction).is_equal_approx(o_hit.fraction, FRACTION_TOLERANCE)
	assert_bool(_normal_matches(n_hit.normal, o_hit.normal)).is_true()
	assert_int(fallbacks).is_equal(0)


func test_parity_on_the_touch_boundary_of_a_still_box() -> void:
	# Arrange: a still box (half 1) at the origin and a sphere of radius 0.5 whose end lands within +-2e-3 m of
	# flush contact (centre x = 1.5): inside, touching and just short of the MOVER_SWEEP_TOLERANCE band.
	var data: TrackCollisionData = Fixtures.movers_only([Fixtures.still_box(1, Vector3.ZERO, Vector3.ONE)])
	var sampler: Callable = func(rng: RandomNumberGenerator, kind: int) -> Array:
		if kind == 0:
			return [Vector3(5.0, rng.randf_range(-0.9, 0.9), rng.randf_range(-0.9, 0.9)), Vector3.LEFT]
		var delta: float = float(rng.randi_range(-40, 40)) * 5e-5
		var y: float = rng.randf_range(-0.4, 0.4)
		var z: float = rng.randf_range(-0.4, 0.4)
		return [Vector3(10.0, y, z), Vector3(1.5 + delta, y, z), 0.5]
	# Act
	var s: Dictionary = _run("touch_boundary", data, sampler, Callable(), 200, 1500)
	# Assert: there are hits, and the within-band flips (if any) were counted, not hidden.
	assert_int(s["sweep_hits"] + s["excluded_sweeps"]).is_greater(500)


func test_parity_at_the_newton_cap_fails_closed_the_same_way() -> void:
	# Arrange: the cap lowered to 1 on both, oblique sweeps at a capsule: both report a blocking hit at the last
	# safe fraction. The native reports its one fail-closed error (once per query), which the test expects; the oracle's is silenced.
	var data: TrackCollisionData = Fixtures.movers_only([Fixtures.still_round(3, MoverDef.Shape.CAPSULE, Vector3.ZERO, 0.5, 1.0)])
	var sampler: Callable = func(rng: RandomNumberGenerator, kind: int) -> Array:
		if kind == 0:
			return [Vector3(6.0, 0.0, 0.0), Vector3.LEFT]
		return [Vector3(6.0, rng.randf_range(1.0, 3.0), rng.randf_range(1.0, 3.0)), Vector3(-4.0, rng.randf_range(-1.0, 0.5), rng.randf_range(-1.0, 1.0)), 1.0]
	var setup: Callable = func(native: CollisionQuery, oracle: OracleCollisionQuery) -> void:
		native.set_newton_cap(1)
		oracle._newton_cap = 1
		# The oracle's own once-per-query report is silenced (its flag set) so the native one is the only error.
		oracle._cap_error_reported = true
	var out: Array[Dictionary] = []
	# Act / Assert: the native and the oracle each push one fail-closed error.
	await assert_error(func() -> void: out.append(_run("newton_cap_1", data, sampler, setup, 50, 300))).is_push_error(
			"CollisionQuery: the mover sweep reached its iteration cap against mover 3; reporting a blocking hit at the last safe fraction 0.4793593422487 (reported once per query)")


# --- harness checks: the exclusion band is real and reported ----------------------------------------------

func test_a_flip_inside_the_band_is_excluded_and_counted_but_one_outside_fails() -> void:
	# Arrange: the same disagreement (native hit, oracle miss) judged inside and outside the band.
	var inside: String = _judge(true, false, false, false, 0, 0, true)
	var outside: String = _judge(true, false, false, false, 0, 0, false)
	var agree: String = _judge(true, true, false, false, 1, 1, false)
	var collider_flip: String = _judge(true, true, false, false, 1, 2, false)
	# Assert
	assert_str(inside).is_equal("excluded")
	assert_str(outside).is_equal("mismatch")
	assert_str(agree).is_equal("exact")
	assert_str(collider_flip).is_equal("mismatch")


func test_band_detection_flags_a_sphere_5e_minus_5_from_a_box_and_not_one_1e_minus_3_away() -> void:
	# Arrange: box half 1 at the origin, sphere radius 0.5: flush contact at centre x = 1.5.
	var data: TrackCollisionData = Fixtures.movers_only([Fixtures.still_box(1, Vector3.ZERO, Vector3.ONE)])
	var oracle: OracleCollisionQuery = OracleCollisionQuery.new(data)
	# Act
	var near: bool = _in_band(oracle, data, Vector3(1.5 + 5e-5, 0.0, 0.0), 0.5, 0.0)
	var far: bool = _in_band(oracle, data, Vector3(1.5 + 1e-3, 0.0, 0.0), 0.5, 0.0)
	oracle.dispose()
	# Assert
	assert_bool(near).is_true()
	assert_bool(far).is_false()


func test_mover_local_transform_and_pose_are_compared_bit_for_bit_with_the_oracle() -> void:
	# Arrange: the cause of the mover ray-distance difference. The mover-local point is the first float32
	# computation of a mover ray; compare native and oracle on many points 100 m or more from the origin.
	var data: TrackCollisionData = Fixtures.movers_only([Fixtures.spinner_box(1, Vector3(300.0, 1.0, -200.0), Vector3(2.0, 0.6, 0.5))])
	var native: CollisionQuery = CollisionQuery.create(data.pack_native())
	var oracle: OracleCollisionQuery = OracleCollisionQuery.new(data)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = SEED
	var mismatched: int = 0
	var pose_mismatched: int = 0
	var worst: float = 0.0
	var n: int = 400
	# Act
	for i in n:
		var t: float = rng.randi_range(0, TICKS) * SIM_DT
		var p: Vector3 = Vector3(300.0, 1.0, -200.0) + Vector3(rng.randf_range(-5.0, 5.0), rng.randf_range(-3.0, 3.0), rng.randf_range(-5.0, 5.0))
		var local_native: Vector3 = native.local_point(1, t, p)
		var local_oracle: Vector3 = oracle.mover_pose(1, t).inverse() * p
		if local_native != local_oracle:
			mismatched += 1
			worst = maxf(worst, (local_native - local_oracle).length())
		if native.mover_pose(1, t) != oracle.mover_pose(1, t):
			pose_mismatched += 1
	print("LOCAL_TRANSFORM points=%d local_point_bit_mismatches=%d pose_bit_mismatches=%d worst_local_diff=%s" % [n, mismatched, pose_mismatched, worst])
	native.dispose()
	oracle.dispose()
	# Assert: a difference, if any, is rounding of a float32 coordinate near 300 m (ulp 3e-5 m), never more.
	assert_float(worst).is_less(4.0 * 3.1e-5)
