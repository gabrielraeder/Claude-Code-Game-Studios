extends GdUnitTestSuite
## Core-rebuild story 007 review: edge cases of the optimised mover code in CollisionQuery (pass
## order, non-solid skipping, pose cache, velocity of the winning slot, data-order ties), the touch
## rule (a mover touch needs the end in contact, within MOVER_SWEEP_TOLERANCE), the fail-closed
## Newton cap. Movers are built in code (collision_fixtures.gd): no randomness, no clock. The static
## RID-proxy scan (no *_create( call in a per-tick method) is now a tools/core_greps.sh rule over native/
## (story 067).

const _GUARD = preload("res://tests/unit/native/native_test_guard.gd")
const Fixtures = preload("res://tests/unit/collision/collision_fixtures.gd")

const ID: int = 3
const ID_2: int = 8
const R: float = Fixtures.SWEEP_RADIUS
const TOL: float = OracleCollisionQuery.MOVER_SWEEP_TOLERANCE
const HIT_TOLERANCE: float = 0.001
const VELOCITY_TOLERANCE: float = 0.001
const UNIT_BOX: Vector3 = Vector3(1.0, 1.0, 1.0)
const HALF_BOX: Vector3 = Vector3(0.5, 0.5, 0.5)
const BAR: Vector3 = Vector3(3.0, 0.5, 0.25)
const CAST_Y: float = 5.0
## Head-on approach to UNIT_BOX's +X face along -X: first contact at centre x = 1 + R.
const APPROACH_FROM: Vector3 = Vector3(5.0, 0.0, 0.0)
const CONTACT_X: float = 1.0 + R
## Distances (in TOL) the end of the motion lies past the first contact, for the blocking cases.
const BLOCK_DEPTHS: PackedFloat64Array = [3.0, 4.0, 5.0]
## Top-face graze: penetration into the top face, and the end gap (in TOL) after leaving the edge.
const GRAZE_DEPTH: float = 0.01
const GRAZE_END_GAP: float = 0.5
## 1 km grazing sweep past a cylinder (radius 1, half height 1): lateral offset of the path (5 mm
## inside contact) and the half length of the motion.
const LONG_OFFSET: float = 1.995
const LONG_HALF: float = 500.0


func before() -> void:
	assert_str(_GUARD.problem()).is_empty()


func _movers_query(movers: Array[MoverDef]) -> CollisionQuery:
	return CollisionQuery.create(Fixtures.movers_only(movers).pack_native())


## Signed gap (distance - R) of the sphere centred at world [param p] to mover [param id] at [param t].
func _gap_at(query: CollisionQuery, mover: MoverDef, t: float, p: Vector3) -> float:
	return query.closest_local(mover.id, query.mover_pose(mover.id, t).affine_inverse() * p) - R


# --- touch rule ---------------------------------------------------------------------------------

func test_mover_sweep_end_penetrating_half_tolerance_is_touch() -> void:
	# Arrange: the end lies 0.5 TOL past the first contact (the end penetrates by 0.5 TOL).
	var box: MoverDef = Fixtures.still_box(ID, Vector3.ZERO, UNIT_BOX)
	var query: CollisionQuery = _movers_query([box])
	var hit: WallHit = WallHit.new()
	var to: Vector3 = Vector3(CONTACT_X - 0.5 * TOL, 0.0, 0.0)
	# Act
	var did_hit: bool = query.sweep_walls(QueryCursor.new(), APPROACH_FROM, to, R, 0.0, hit)
	query.dispose()
	# Assert
	assert_bool(did_hit).is_true()
	assert_float(hit.fraction).is_equal(1.0)
	assert_bool(hit.started_inside).is_false()
	assert_int(hit.collider_id).is_equal(ID)


func test_mover_sweep_contact_three_to_five_tolerances_short_of_end_blocks_at_clear_fraction() -> void:
	for depth in BLOCK_DEPTHS:
		# Arrange: the first contact lies depth x TOL before the end.
		var box: MoverDef = Fixtures.still_box(ID, Vector3.ZERO, UNIT_BOX)
		var query: CollisionQuery = _movers_query([box])
		var hit: WallHit = WallHit.new()
		var to: Vector3 = Vector3(CONTACT_X - depth * TOL, 0.0, 0.0)
		# Act
		var did_hit: bool = query.sweep_walls(QueryCursor.new(), APPROACH_FROM, to, R, 0.0, hit)
		var at: Vector3 = APPROACH_FROM.lerp(to, hit.fraction)
		var gap: float = _gap_at(query, box, 0.0, at)
		query.dispose()
		# Assert
		assert_bool(did_hit).is_true()
		assert_float(hit.fraction).is_less(1.0)
		assert_bool(hit.started_inside).is_false()
		assert_float(gap).is_greater(0.0)


func test_mover_sweep_graze_with_end_clear_within_tolerance_blocks_not_touch() -> void:
	# Arrange: across the top face GRAZE_DEPTH deep, off the +X edge, ending with a gap of
	# GRAZE_END_GAP x TOL (clear, but within TOL of contact): a blocking hit at the first contact.
	var box: MoverDef = Fixtures.still_box(ID, Vector3.ZERO, UNIT_BOX)
	var query: CollisionQuery = _movers_query([box])
	var hit: WallHit = WallHit.new()
	var y: float = UNIT_BOX.y + R - GRAZE_DEPTH
	var dy: float = y - UNIT_BOX.y
	var end_x: float = UNIT_BOX.x + sqrt(pow(R + GRAZE_END_GAP * TOL, 2.0) - dy * dy)
	var from: Vector3 = Vector3(-5.0, y, 0.0)
	var to: Vector3 = Vector3(end_x, y, 0.0)
	# Act
	var end_gap: float = _gap_at(query, box, 0.0, to)
	var did_hit: bool = query.sweep_walls(QueryCursor.new(), from, to, R, 0.0, hit)
	var at: Vector3 = from.lerp(to, hit.fraction)
	var gap: float = _gap_at(query, box, 0.0, at)
	query.dispose()
	# Assert
	assert_float(end_gap).is_between(0.0, TOL)
	assert_bool(did_hit).is_true()
	assert_float(hit.fraction).is_less(1.0)
	assert_bool(hit.started_inside).is_false()
	assert_float(gap).is_greater(0.0)


# --- fail closed at the Newton cap -------------------------------------------------------------

func test_one_kilometre_grazing_sweep_past_cylinder_hits() -> void:
	# Arrange: 1 km along +X, 5 mm inside contact with a cylinder's side.
	var cyl: MoverDef = Fixtures.still_round(ID, MoverDef.Shape.CYLINDER, Vector3.ZERO, 1.0, 1.0)
	var query: CollisionQuery = _movers_query([cyl])
	var hit: WallHit = WallHit.new()
	var from: Vector3 = Vector3(-LONG_HALF, 0.0, LONG_OFFSET)
	var to: Vector3 = Vector3(LONG_HALF, 0.0, LONG_OFFSET)
	var contact_x: float = -sqrt(pow(1.0 + R, 2.0) - LONG_OFFSET * LONG_OFFSET)
	# Act
	var did_hit: bool = query.sweep_walls(QueryCursor.new(), from, to, R, 0.0, hit)
	var capped: bool = query.cap_error_reported()
	query.dispose()
	# Assert
	assert_bool(did_hit).is_true()
	assert_bool(capped).is_false()
	assert_float(hit.fraction * 2.0 * LONG_HALF - LONG_HALF).is_equal_approx(contact_x, HIT_TOLERANCE)


func test_mover_sweep_at_newton_cap_fails_closed_with_blocking_hit_at_safe_fraction() -> void:
	# Arrange: an oblique approach to a capsule needs several Newton steps; the cap is lowered to 1.
	var capsule: MoverDef = Fixtures.still_round(ID, MoverDef.Shape.CAPSULE, Vector3.ZERO, 0.5, 1.0)
	var capped_query: CollisionQuery = _movers_query([capsule])
	capped_query.set_newton_cap(1)
	var normal_query: CollisionQuery = _movers_query([capsule])
	var from: Vector3 = Vector3(6.0, 2.5, 3.0)
	var to: Vector3 = Vector3(-4.0, -0.5, -1.0)
	var capped_hit: WallHit = WallHit.new()
	var normal_hit: WallHit = WallHit.new()
	# Act
	var capped_did: bool = capped_query.sweep_walls(QueryCursor.new(), from, to, R, 0.0, capped_hit)
	var normal_did: bool = normal_query.sweep_walls(QueryCursor.new(), from, to, R, 0.0, normal_hit)
	var reported: bool = capped_query.cap_error_reported()
	var gap: float = _gap_at(capped_query, capsule, 0.0, from.lerp(to, capped_hit.fraction))
	capped_query.dispose()
	normal_query.dispose()
	# Assert: blocked short of (or at) the true contact, never through it.
	assert_bool(normal_did).is_true()
	assert_bool(capped_did).is_true()
	assert_bool(reported).is_true()
	assert_bool(capped_hit.started_inside).is_false()
	assert_float(capped_hit.fraction).is_less_equal(normal_hit.fraction)
	assert_float(gap).is_greater(0.0)


# --- pass order, non-solid movers, rotated overlap ---------------------------------------------

func test_sweep_overlap_on_later_mover_wins_over_sweep_hit_on_earlier_mover() -> void:
	# Arrange: slot 0 is clear at from but in the path; slot 1 overlaps the sphere at from by 0.3.
	var ahead: MoverDef = Fixtures.still_box(ID, Vector3(-3.0, 0.0, 0.0), HALF_BOX)
	var overlapping: MoverDef = Fixtures.still_box(ID_2, Vector3(1.2, 0.0, 0.0), HALF_BOX)
	var query: CollisionQuery = _movers_query([ahead, overlapping])
	var hit: WallHit = WallHit.new()
	# Act
	var did_hit: bool = query.sweep_walls(QueryCursor.new(), Vector3.ZERO, Vector3(-5.0, 0.0, 0.0), R, 0.0, hit)
	query.dispose()
	# Assert
	assert_bool(did_hit).is_true()
	assert_bool(hit.started_inside).is_true()
	assert_float(hit.fraction).is_equal(0.0)
	assert_int(hit.collider_id).is_equal(ID_2)
	assert_vector(hit.point).is_equal_approx(Vector3(0.7, 0.0, 0.0), Vector3.ONE * HIT_TOLERANCE)
	assert_vector(hit.normal).is_equal_approx(Vector3.LEFT, Vector3.ONE * HIT_TOLERANCE)


func test_overlap_on_rotated_mover_reports_world_point_and_normal() -> void:
	# Arrange: the spinning bar at 45 deg (t = half a key step); the sphere overlaps its rotated +Z
	# face by 0.2, without moving.
	var spinner: MoverDef = Fixtures.spinner_box(ID, Vector3.ZERO, BAR)
	var query: CollisionQuery = _movers_query([spinner])
	var t: float = Fixtures.SPIN_STEP_TIME * 0.5
	var pose: Transform3D = query.mover_pose(ID, t)
	var local_point: Vector3 = Vector3(1.0, 0.0, BAR.z)
	var world_point: Vector3 = pose * local_point
	var world_normal: Vector3 = pose.basis * Vector3.BACK
	var centre: Vector3 = world_point + world_normal * (R - 0.2)
	var omega: Vector3 = Vector3.UP * (Fixtures.SPIN_STEP_ANGLE / Fixtures.SPIN_STEP_TIME)
	var hit: WallHit = WallHit.new()
	# Act
	var did_hit: bool = query.sweep_walls(QueryCursor.new(), centre, centre, R, t, hit)
	query.dispose()
	# Assert
	assert_bool(did_hit).is_true()
	assert_bool(hit.started_inside).is_true()
	assert_vector(hit.point).is_equal_approx(world_point, Vector3.ONE * HIT_TOLERANCE)
	assert_vector(hit.normal).is_equal_approx(world_normal, Vector3.ONE * HIT_TOLERANCE)
	assert_vector(hit.collider_velocity).is_equal_approx(omega.cross(world_point - pose.origin), Vector3.ONE * VELOCITY_TOLERANCE)


func test_non_solid_mover_listed_before_solid_one_is_skipped() -> void:
	# Arrange: slot 0 non-solid, overlapping the sweep start and over the ray; slot 1 solid.
	var ghost_wall: MoverDef = Fixtures.still_box(ID, Vector3.ZERO, HALF_BOX)
	ghost_wall.solid = false
	var ghost_deck: MoverDef = Fixtures.still_box(ID + 10, Vector3(-3.0, 2.0, 0.0), HALF_BOX)
	ghost_deck.solid = false
	var solid: MoverDef = Fixtures.still_box(ID_2, Vector3(-3.0, 0.0, 0.0), HALF_BOX)
	var query: CollisionQuery = _movers_query([ghost_wall, ghost_deck, solid])
	var wall: WallHit = WallHit.new()
	var ground: GroundHit = GroundHit.new()
	# Act
	var swept: bool = query.sweep_walls(QueryCursor.new(), Vector3.ZERO, Vector3(-5.0, 0.0, 0.0), R, 0.0, wall)
	var cast: bool = query.cast_ground(QueryCursor.new(), Vector3(-3.0, CAST_Y, 0.0), Vector3.DOWN, Fixtures.CAST_LENGTH, 0.0, ground)
	query.dispose()
	# Assert: contact at centre x = -1.5 (fraction 0.3), and the solid box's top at y = 0.5.
	assert_bool(swept).is_true()
	assert_bool(wall.started_inside).is_false()
	assert_int(wall.collider_id).is_equal(ID_2)
	assert_float(wall.fraction).is_equal_approx(0.3, HIT_TOLERANCE)
	assert_bool(cast).is_true()
	assert_int(ground.collider_id).is_equal(ID_2)
	assert_float(ground.point.y).is_equal_approx(HALF_BOX.y, HIT_TOLERANCE)


# --- pose cache, winning slot, ties ------------------------------------------------------------

func test_cast_ground_at_two_times_on_one_query_matches_fresh_queries() -> void:
	# Arrange: a spinning bar; one query cast at t1 then t2, against a fresh query per time.
	var movers: Array[MoverDef] = [Fixtures.spinner_box(ID, Vector3.ZERO, BAR)]
	var data: TrackCollisionData = Fixtures.movers_only(movers)
	var reused: CollisionQuery = CollisionQuery.create(data.pack_native())
	var origin: Vector3 = Vector3(2.0, CAST_Y, 0.1)
	for t in [0.0, Fixtures.SPIN_STEP_TIME * 0.5, 0.0, Fixtures.SPIN_STEP_TIME * 1.25]:
		var fresh: CollisionQuery = CollisionQuery.create(data.pack_native())
		var a: GroundHit = GroundHit.new()
		var b: GroundHit = GroundHit.new()
		# Act
		var hit_a: bool = reused.cast_ground(QueryCursor.new(), origin, Vector3.DOWN, Fixtures.CAST_LENGTH, t, a)
		var hit_b: bool = fresh.cast_ground(QueryCursor.new(), origin, Vector3.DOWN, Fixtures.CAST_LENGTH, t, b)
		fresh.dispose()
		# Assert
		assert_bool(hit_a).is_equal(hit_b)
		assert_vector(a.point).is_equal(b.point)
		assert_vector(a.normal).is_equal(b.normal)
		assert_vector(a.collider_velocity).is_equal(b.collider_velocity)
	reused.dispose()


func test_nearer_moving_mover_listed_second_reports_its_own_velocity() -> void:
	# Arrange: slot 0 still; slot 1 the slide box (+X at SLIDE_DISTANCE / SLIDE_TIME), centred over
	# the probe and in the sweep path at t = SLIDE_TIME / 4, nearer than slot 0 for both queries.
	var t: float = Fixtures.SLIDE_TIME * 0.25
	var speed: float = Fixtures.SLIDE_DISTANCE / Fixtures.SLIDE_TIME
	var deck: Vector3 = Vector3(1.0, 0.25, 1.0)
	var low: MoverDef = Fixtures.still_box(ID, Vector3(0.0, 1.0, 0.0), deck)
	var far: MoverDef = Fixtures.still_box(ID + 10, Vector3(-4.0, 3.0, 0.0), HALF_BOX)
	var slide: MoverDef = Fixtures.slide_box(ID_2, Vector3(-speed * t, 3.0, 0.0), deck)
	var query: CollisionQuery = _movers_query([low, far, slide])
	var ground: GroundHit = GroundHit.new()
	var wall: WallHit = WallHit.new()
	# Act
	query.cast_ground(QueryCursor.new(), Vector3(0.2, CAST_Y, 0.2), Vector3.DOWN, Fixtures.CAST_LENGTH, t, ground)
	query.sweep_walls(QueryCursor.new(), Vector3(5.0, 3.0, 0.0), Vector3(-6.0, 3.0, 0.0), R, t, wall)
	query.dispose()
	# Assert
	assert_int(ground.collider_id).is_equal(ID_2)
	assert_vector(ground.collider_velocity).is_equal_approx(Vector3(speed, 0.0, 0.0), Vector3.ONE * VELOCITY_TOLERANCE)
	assert_int(wall.collider_id).is_equal(ID_2)
	assert_vector(wall.collider_velocity).is_equal_approx(Vector3(speed, 0.0, 0.0), Vector3.ONE * VELOCITY_TOLERANCE)


func test_exact_mover_sweep_fraction_tie_goes_to_data_order() -> void:
	# Arrange: two boxes mirrored in z with the same face plane x = -2.5 (dyadic values: the two
	# gap functions are bit-identical), in both data orders.
	var a: MoverDef = Fixtures.still_box(ID, Vector3(-3.0, 0.0, 0.25), HALF_BOX)
	var b: MoverDef = Fixtures.still_box(ID_2, Vector3(-3.0, 0.0, -0.25), HALF_BOX)
	var a_first: CollisionQuery = _movers_query([a, b])
	var b_first: CollisionQuery = _movers_query([b, a])
	var hit_a: WallHit = WallHit.new()
	var hit_b: WallHit = WallHit.new()
	var to: Vector3 = Vector3(-5.0, 0.0, 0.0)
	# Act
	a_first.sweep_walls(QueryCursor.new(), Vector3.ZERO, to, R, 0.0, hit_a)
	b_first.sweep_walls(QueryCursor.new(), Vector3.ZERO, to, R, 0.0, hit_b)
	a_first.dispose()
	b_first.dispose()
	# Assert
	assert_float(hit_a.fraction).is_equal(hit_b.fraction)
	assert_int(hit_a.collider_id).is_equal(ID)
	assert_int(hit_b.collider_id).is_equal(ID_2)
