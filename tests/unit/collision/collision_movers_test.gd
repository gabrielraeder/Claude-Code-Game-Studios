extends GdUnitTestSuite
## Core-rebuild story 005: analytic moving colliders (ADR-0002 "Moving colliders", "Queries per kart
## per tick"; Track Collision GDD 3.4, 4.4). Movers are built in code (collision_fixtures.gd); no
## randomness, no time-dependent assertion.
## Filesystem exception: test_no_key_pos_use_outside_core_collision is the one test that reads files
## (the AC-15 scan of the res://src scripts). It runs from source only: an exported build has no .gd
## sources to scan.
##
## Story acceptance criteria (story order) -> GDD / ADR source -> tests:
##   Story AC 1  Pose curve                 (Track Collision AC-12; ADR-0002 Validation Criteria)
##               test_mover_pose_halfway_along_slide_is_at_five_metres,
##               test_mover_pose_wraps_at_period,
##               test_mover_pose_at_key_times_returns_key_poses,
##               test_mover_pose_before_first_key_runs_loop_segment_from_last_key,
##               test_mover_pose_slerps_rotation_between_keys,
##               test_mover_pose_at_non_float32_exact_last_key_time_returns_that_key,
##               test_mover_blocks_or_clears_at_t_as_its_curve_says
##   Story AC 2  Point velocity             (Track Collision AC-13)
##               test_mover_point_velocity_two_metres_from_spin_axis_is_half_pi_times_two,
##               test_mover_point_velocity_matches_finite_difference_of_pose,
##               test_spinner_point_velocity_in_loop_segment_keeps_turning_forward,
##               test_sweep_hit_on_spinning_mover_reports_point_velocity_at_contact,
##               test_cast_ground_on_mover_top_returns_mover_hit_with_point_velocity,
##               test_cast_ground_on_translating_mover_hits_moved_position_with_its_velocity,
##               test_spinner_at_45_degrees_reports_rotated_contact_point_and_normal
##   Story AC 3  Mover overlap              (Track Collision AC-14; ADR-0002 v5/v5.1)
##               test_mover_moving_into_stationary_kart_sets_started_inside,
##               test_moving_kart_started_inside_mover_runs_no_sweep,
##               test_mover_deeper_than_static_wall_wins_overlap,
##               test_static_wall_deeper_than_mover_wins_overlap,
##               test_non_solid_mover_never_blocks_sweep_or_ground_cast,
##               test_deepest_of_two_overlapping_movers_wins,
##               test_static_wall_wins_exact_overlap_depth_tie
##   Story AC 4  One evaluator              (Track Collision AC-15)
##               test_mover_pose_same_t_is_bit_identical_across_calls_and_queries,
##               test_no_key_pos_use_outside_core_collision
##   Ground casts against movers (ADR-0002 cast_ground: nearest wins; story 003 review note)
##               test_cast_ground_beside_mover_returns_static_ground,
##               test_cast_ground_static_ground_nearer_than_mover_wins,
##               test_cast_ground_hits_mover_with_no_ground_below,
##               test_cast_ground_hits_capsule_cap_and_cylinder_top_and_side,
##               test_cast_ground_starting_inside_mover_misses_it,
##               test_cast_ground_miss_with_movers_leaves_hit_untouched,
##               test_cast_ground_nearest_of_two_movers_wins_regardless_of_order,
##               test_cast_ground_static_ground_wins_exact_distance_tie,
##               test_mover_hits_report_mover_surface_and_wall_attr_ids
##   Wall sweeps against movers (ADR-0002 sweep_walls step 5)
##               test_sweep_into_box_mover_blocks_with_safe_fraction,
##               test_sweep_past_box_edge_and_cylinder_rim_hits_rounded_contact,
##               test_sweep_into_capsule_and_cylinder_movers_blocks_with_safe_fraction,
##               test_sweep_ending_flush_with_mover_is_touch_with_fraction_one,
##               test_sweep_passing_beside_mover_misses_and_leaves_hit_untouched,
##               test_sweep_mover_nearer_than_static_wall_wins,
##               test_sweep_static_wall_nearer_than_mover_wins,
##               test_sweep_static_wall_wins_exact_fraction_tie
##   Mover layout checks (story 003 review note)
##               test_layout_error_accepts_valid_movers_of_each_shape,
##               test_layout_error_rejects_mover_id_below_one,
##               test_layout_error_rejects_duplicate_mover_ids,
##               test_layout_error_rejects_non_positive_period,
##               test_layout_error_rejects_unequal_key_arrays,
##               test_layout_error_rejects_fewer_than_two_keys,
##               test_layout_error_rejects_key_t_not_ascending,
##               test_layout_error_rejects_key_t_outside_period,
##               test_layout_error_rejects_invalid_extents_for_shape,
##               test_layout_error_rejects_unknown_shape,
##               test_layout_error_rejects_non_unit_key_rotation,
##               test_layout_error_rejects_null_mover,
##               test_layout_error_rejects_mover_ids_outside_u8,
##               test_layout_error_rejects_non_finite_key_position,
##               test_layout_error_rejects_nearly_unit_key_rotation,
##               test_query_from_bad_mover_push_errors_and_has_no_movers
##   Reuse and lifetime (ADR-0002 Reuse rules; Implementation Guidelines)
##               test_mover_queries_create_no_objects_over_1000_queries,
##               test_mover_pose_of_unknown_id_push_errors_and_returns_identity,
##               test_mover_point_velocity_of_unknown_id_push_errors_and_returns_zero,
##               test_mover_pose_after_dispose_asserts_in_debug_or_returns_identity

const Fixtures = preload("res://tests/unit/collision/collision_fixtures.gd")

## Mover id of the single-mover tests (any id >= 1; 0 means static).
const ID: int = 3
## A second mover id.
const ID_2: int = 8
## Simulation tick (s) used to build "simulation" times n x SIM_DT (ADR-0001: 60 Hz).
const SIM_DT: float = 1.0 / 60.0
## Pose tolerance (m) of AC 1 (story: 5.0 +/- 1e-4).
const POSE_TOLERANCE: float = 0.0001
## Point-velocity magnitude tolerance (m/s) of AC 2 (story: 3.1416 +/- 0.001).
const VELOCITY_TOLERANCE: float = 0.001
## Tolerance (m/s) of a finite-difference velocity (central difference, float32 positions).
const FD_TOLERANCE: float = 0.002
## Half step (s) of the central finite difference.
const FD_STEP: float = 0.01
## Contact position / normal tolerance (m) of an analytic mover contact.
const HIT_TOLERANCE: float = 0.001
## Fraction tolerance (the mover sweep stops refining 0.1 mm short of the contact).
const FRACTION_TOLERANCE: float = 0.001
## Sweep sphere radius (m).
const R: float = Fixtures.SWEEP_RADIUS
## Height (m) the downward ground casts start from.
const CAST_Y: float = 5.0
## Sentinel wall_attr written into a WallHit to prove a miss leaves it untouched.
const SENTINEL_ATTR: int = 99
## Sentinel surface id written into a GroundHit to prove a miss leaves it untouched.
const SENTINEL_SURFACE: int = 77
## Sentinel collider id.
const SENTINEL_COLLIDER_ID: int = 55
## Sentinel collider velocity.
const SENTINEL_VELOCITY: Vector3 = Vector3(1.0, 2.0, 3.0)
## Queries per kind in the object-count check (story: 1000 queries).
const OBJECT_CHECK_REPEATS: int = 1000
## Half extents (m) of the unit test box.
const UNIT_BOX: Vector3 = Vector3(1.0, 1.0, 1.0)
## Half extents (m) of the spinner bar of AC 2 (long along local X).
const BAR: Vector3 = Vector3(3.0, 0.5, 0.25)
## Distance (m) from the spin axis the AC 2 velocity is checked at.
const AXIS_DISTANCE: float = 2.0


# --- helpers ------------------------------------------------------------------------------------

## A WallHit holding sentinel values.
func _sentinel_wall_hit() -> WallHit:
	var hit: WallHit = WallHit.new()
	hit.wall_attr = SENTINEL_ATTR
	hit.fraction = 0.5
	hit.started_inside = true
	hit.point = Vector3.ONE
	hit.normal = Vector3.ONE
	hit.collider_id = SENTINEL_COLLIDER_ID
	hit.collider_velocity = SENTINEL_VELOCITY
	return hit


## A GroundHit holding sentinel values.
func _sentinel_ground_hit() -> GroundHit:
	var hit: GroundHit = GroundHit.new()
	hit.surface_id = SENTINEL_SURFACE
	hit.point = Vector3.ONE
	hit.normal = Vector3.ONE
	hit.collider_id = SENTINEL_COLLIDER_ID
	hit.collider_velocity = SENTINEL_VELOCITY
	return hit


## Asserts every field of [param hit] still holds the _sentinel_wall_hit values.
func _assert_wall_sentinel(hit: WallHit) -> void:
	assert_int(hit.wall_attr).is_equal(SENTINEL_ATTR)
	assert_float(hit.fraction).is_equal(0.5)
	assert_bool(hit.started_inside).is_true()
	assert_vector(hit.point).is_equal(Vector3.ONE)
	assert_vector(hit.normal).is_equal(Vector3.ONE)
	assert_int(hit.collider_id).is_equal(SENTINEL_COLLIDER_ID)
	assert_vector(hit.collider_velocity).is_equal(SENTINEL_VELOCITY)


## Asserts every field of [param hit] still holds the _sentinel_ground_hit values.
func _assert_ground_sentinel(hit: GroundHit) -> void:
	assert_int(hit.surface_id).is_equal(SENTINEL_SURFACE)
	assert_vector(hit.point).is_equal(Vector3.ONE)
	assert_vector(hit.normal).is_equal(Vector3.ONE)
	assert_int(hit.collider_id).is_equal(SENTINEL_COLLIDER_ID)
	assert_vector(hit.collider_velocity).is_equal(SENTINEL_VELOCITY)


## A query over [param movers] only.
func _movers_query(movers: Array[MoverDef]) -> CollisionQuery:
	return CollisionQuery.new(Fixtures.movers_only(movers))


## The slide mover of AC 1 (box from the origin to +10 m along X over 2 s, back by 4 s).
func _slide() -> MoverDef:
	return Fixtures.slide_box(ID, Vector3.ZERO, UNIT_BOX)


## A mover that translates and tumbles about a tilted axis (finite-difference fixture): 4 keys,
## period 4 s; the loop segment turns back by 2.5 rad (under pi: the shortest path).
func _tumbler() -> MoverDef:
	var axis: Vector3 = Vector3(1.0, 2.0, 0.5).normalized()
	var m: MoverDef = Fixtures.mover(ID, MoverDef.Shape.BOX, 4.0, [0.0, 1.0, 2.0, 3.0],
			[Vector3.ZERO, Vector3(2.0, 0.0, 1.0), Vector3(3.0, 1.0, 1.0), Vector3(1.0, 0.0, -1.0)],
			[Fixtures.rot_key(axis, 0.0), Fixtures.rot_key(axis, 1.0), Fixtures.rot_key(axis, 2.0), Fixtures.rot_key(axis, 2.5)])
	m.half_extents = UNIT_BOX
	return m


## Central finite difference of the world velocity of the body point at [param p] (world, at
## [param t]) of mover [param id].
func _fd_velocity(query: CollisionQuery, id: int, t: float, p: Vector3) -> Vector3:
	var body_point: Vector3 = query.mover_pose(id, t).affine_inverse() * p
	var ahead: Vector3 = query.mover_pose(id, t + FD_STEP) * body_point
	var behind: Vector3 = query.mover_pose(id, t - FD_STEP) * body_point
	return (ahead - behind) / (2.0 * FD_STEP)


## TrackCollisionData.layout_error() of data holding [param movers] only.
func _layout_error_of(movers: Array[MoverDef]) -> String:
	return Fixtures.movers_only(movers).layout_error()


## Every .gd file under [param dir_path], recursively, into [param out].
func _gd_files_under(dir_path: String, out: Array[String]) -> void:
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return
	for f in dir.get_files():
		if f.ends_with(".gd"):
			out.append(dir_path.path_join(f))
	for d in dir.get_directories():
		_gd_files_under(dir_path.path_join(d), out)


# --- Story AC 1: pose curve -------------------------------------------------------------------------

func test_mover_pose_halfway_along_slide_is_at_five_metres() -> void:
	# Arrange
	var query: CollisionQuery = _movers_query([_slide()])
	# Act
	var pose: Transform3D = query.mover_pose(ID, 1.0)
	query.dispose()
	# Assert
	assert_float(pose.origin.x).is_equal_approx(5.0, POSE_TOLERANCE)
	assert_float(pose.origin.y).is_equal_approx(0.0, POSE_TOLERANCE)
	assert_float(pose.origin.z).is_equal_approx(0.0, POSE_TOLERANCE)
	assert_bool(pose.basis.is_equal_approx(Basis.IDENTITY)).is_true()


func test_mover_pose_wraps_at_period() -> void:
	# Arrange
	var query: CollisionQuery = _movers_query([_slide()])
	var period: float = Fixtures.SLIDE_PERIOD
	# Act
	var at_1: Transform3D = query.mover_pose(ID, 1.0)
	var at_period_plus_1: Transform3D = query.mover_pose(ID, period + 1.0)
	var at_3: Transform3D = query.mover_pose(ID, 3.0)
	var at_minus_1: Transform3D = query.mover_pose(ID, -1.0)
	var at_period: Transform3D = query.mover_pose(ID, period)
	var at_0: Transform3D = query.mover_pose(ID, 0.0)
	query.dispose()
	# Assert: equal t modulo the period gives the same pose; t = 3 is on the way back (loop segment).
	assert_bool(at_period_plus_1 == at_1).is_true()
	assert_bool(at_minus_1 == at_3).is_true()
	assert_bool(at_period == at_0).is_true()
	assert_float(at_3.origin.x).is_equal_approx(5.0, POSE_TOLERANCE)


func test_mover_pose_at_key_times_returns_key_poses() -> void:
	# Arrange
	var query: CollisionQuery = _movers_query([_slide()])
	# Act
	var at_first: Vector3 = query.mover_pose(ID, 0.0).origin
	var at_second: Vector3 = query.mover_pose(ID, Fixtures.SLIDE_TIME).origin
	query.dispose()
	# Assert
	assert_vector(at_first).is_equal(Vector3.ZERO)
	assert_vector(at_second).is_equal_approx(Vector3.RIGHT * Fixtures.SLIDE_DISTANCE, Vector3.ONE * POSE_TOLERANCE)


func test_mover_pose_before_first_key_runs_loop_segment_from_last_key() -> void:
	# Arrange: keys at 1 s (A) and 2 s (B), period 4 s. The loop segment runs B (2 s) -> A (5 s), so
	# t = 0 is 2/3 of the way from B back to A.
	var a: Vector3 = Vector3(0.0, 0.0, 0.0)
	var b: Vector3 = Vector3(3.0, 0.0, 0.0)
	var m: MoverDef = Fixtures.mover(ID, MoverDef.Shape.BOX, 4.0, [1.0, 2.0], [a, b], [Fixtures.ROT_IDENTITY, Fixtures.ROT_IDENTITY])
	m.half_extents = UNIT_BOX
	var query: CollisionQuery = _movers_query([m])
	# Act
	var at_0: Vector3 = query.mover_pose(ID, 0.0).origin
	var at_1_5: Vector3 = query.mover_pose(ID, 1.5).origin
	var v_loop: Vector3 = query.mover_point_velocity(ID, 0.0, at_0)
	query.dispose()
	# Assert
	assert_vector(at_0).is_equal_approx(b.lerp(a, 2.0 / 3.0), Vector3.ONE * POSE_TOLERANCE)
	assert_vector(at_1_5).is_equal_approx(a.lerp(b, 0.5), Vector3.ONE * POSE_TOLERANCE)
	assert_vector(v_loop).is_equal_approx((a - b) / 3.0, Vector3.ONE * VELOCITY_TOLERANCE)


func test_mover_pose_slerps_rotation_between_keys() -> void:
	# Arrange: the spinner is at 45 deg about +Y halfway between its first two keys.
	var query: CollisionQuery = _movers_query([Fixtures.spinner_box(ID, Vector3.ZERO, BAR)])
	# Act
	var pose: Transform3D = query.mover_pose(ID, Fixtures.SPIN_STEP_TIME * 0.5)
	query.dispose()
	# Assert
	assert_bool(pose.basis.is_equal_approx(Basis(Vector3.UP, Fixtures.SPIN_STEP_ANGLE * 0.5))).is_true()
	assert_vector(pose.origin).is_equal(Vector3.ZERO)


func test_mover_blocks_or_clears_at_t_as_its_curve_says() -> void:
	# Arrange: a portcullis-like box, down (centre y 1.3) at t = 0, lifted 5 m by t = 2, down again
	# at the period (4 s). The kart sweeps through it along -Z at y = 1.
	var down: Vector3 = Vector3(0.0, 1.3, 0.0)
	var gate: MoverDef = Fixtures.mover(ID, MoverDef.Shape.BOX, 4.0, [0.0, 2.0], [down, down + Vector3.UP * 5.0],
			[Fixtures.ROT_IDENTITY, Fixtures.ROT_IDENTITY])
	gate.half_extents = Vector3(2.25, 1.3, 0.3)
	var query: CollisionQuery = _movers_query([gate])
	var cursor: QueryCursor = QueryCursor.new()
	var from: Vector3 = Vector3(0.0, 1.0, 3.0)
	var to: Vector3 = Vector3(0.0, 1.0, -3.0)
	var hit_down: WallHit = WallHit.new()
	var hit_up: WallHit = _sentinel_wall_hit()
	var hit_down_again: WallHit = WallHit.new()
	# Act
	var blocked: bool = query.sweep_walls(cursor, from, to, R, 0.0, hit_down)
	var cleared: bool = query.sweep_walls(cursor, from, to, R, 2.0, hit_up)
	var blocked_again: bool = query.sweep_walls(cursor, from, to, R, 4.0, hit_down_again)
	query.dispose()
	# Assert: contact when the centre reaches z = 0.3 + 1 = 1.3, i.e. (3 - 1.3) / 6 of the move.
	var expected_fraction: float = (3.0 - 1.3) / 6.0
	assert_bool(blocked).is_true()
	assert_int(hit_down.collider_id).is_equal(ID)
	assert_bool(hit_down.started_inside).is_false()
	assert_float(hit_down.fraction).is_equal_approx(expected_fraction, FRACTION_TOLERANCE)
	assert_float(hit_down.fraction).is_less_equal(expected_fraction)
	assert_vector(hit_down.normal).is_equal_approx(Vector3.BACK, Vector3.ONE * HIT_TOLERANCE)
	assert_bool(cleared).is_false()
	_assert_wall_sentinel(hit_up)
	assert_bool(blocked_again).is_true()
	assert_float(hit_down_again.fraction).is_equal(hit_down.fraction)


# --- Story AC 2: point velocity --------------------------------------------------------------------

func test_mover_point_velocity_two_metres_from_spin_axis_is_half_pi_times_two() -> void:
	# Arrange: 90 deg about +Y in 1 s.
	var query: CollisionQuery = _movers_query([Fixtures.spinner_box(ID, Vector3.ZERO, BAR)])
	var p: Vector3 = Vector3(AXIS_DISTANCE, 0.0, 0.0)
	# Act
	var v: Vector3 = query.mover_point_velocity(ID, 0.5, p)
	query.dispose()
	# Assert: |v| = pi/2 x 2 = 3.1416; omega = +Y pi/2, so v = omega x p = (0, 0, -pi).
	assert_float(v.length()).is_equal_approx(PI / 2.0 * AXIS_DISTANCE, VELOCITY_TOLERANCE)
	assert_vector(v).is_equal_approx(Vector3(0.0, 0.0, -PI), Vector3.ONE * VELOCITY_TOLERANCE)


func test_mover_point_velocity_matches_finite_difference_of_pose() -> void:
	# Arrange: translating and tumbling; one time inside a key segment, one in the loop segment.
	var query: CollisionQuery = _movers_query([_tumbler()])
	var times: Array[float] = [1.3, 3.6]
	var offset: Vector3 = Vector3(1.5, 0.5, -0.7)
	var analytic: Array[Vector3] = []
	var numeric: Array[Vector3] = []
	# Act
	for t in times:
		var p: Vector3 = query.mover_pose(ID, t) * offset
		analytic.append(query.mover_point_velocity(ID, t, p))
		numeric.append(_fd_velocity(query, ID, t, p))
	query.dispose()
	# Assert
	for i in times.size():
		assert_vector(analytic[i]).is_equal_approx(numeric[i], Vector3.ONE * FD_TOLERANCE)
		assert_float(analytic[i].length()).is_greater(1.0)


func test_spinner_point_velocity_in_loop_segment_keeps_turning_forward() -> void:
	# Arrange: the loop segment (270 deg -> 360 deg) must turn +90 deg, not back 270 deg.
	var query: CollisionQuery = _movers_query([Fixtures.spinner_box(ID, Vector3.ZERO, BAR)])
	var t: float = 3.5
	var p: Vector3 = query.mover_pose(ID, t) * Vector3(AXIS_DISTANCE, 0.0, 0.0)
	# Act
	var v: Vector3 = query.mover_point_velocity(ID, t, p)
	var fd: Vector3 = _fd_velocity(query, ID, t, p)
	query.dispose()
	# Assert
	assert_vector(v).is_equal_approx(Vector3.UP.cross(p) * (PI / 2.0), Vector3.ONE * VELOCITY_TOLERANCE)
	assert_vector(v).is_equal_approx(fd, Vector3.ONE * FD_TOLERANCE)


func test_sweep_hit_on_spinning_mover_reports_point_velocity_at_contact() -> void:
	# Arrange: at t = 0 the bar lies along X (its +Z face at z = 0.25). The kart comes down -Z at the
	# x where the contact (x, 0, 0.25) is AXIS_DISTANCE from the axis.
	var query: CollisionQuery = _movers_query([Fixtures.spinner_box(ID, Vector3.ZERO, BAR)])
	var cursor: QueryCursor = QueryCursor.new()
	var hit: WallHit = WallHit.new()
	var x: float = sqrt(AXIS_DISTANCE * AXIS_DISTANCE - BAR.z * BAR.z)
	var from: Vector3 = Vector3(x, 0.0, 3.0)
	var to: Vector3 = Vector3(x, 0.0, -1.0)
	# Act
	var did_hit: bool = query.sweep_walls(cursor, from, to, R, 0.0, hit)
	var expected_v: Vector3 = query.mover_point_velocity(ID, 0.0, hit.point)
	query.dispose()
	# Assert
	assert_bool(did_hit).is_true()
	assert_int(hit.collider_id).is_equal(ID)
	assert_int(hit.wall_attr).is_equal(0)  # MoverDef.wall_attr_id default (standard)
	assert_float(hit.fraction).is_equal_approx((3.0 - (BAR.z + R)) / 4.0, FRACTION_TOLERANCE)
	assert_vector(hit.point).is_equal_approx(Vector3(x, 0.0, BAR.z), Vector3.ONE * HIT_TOLERANCE)
	assert_vector(hit.normal).is_equal_approx(Vector3.BACK, Vector3.ONE * HIT_TOLERANCE)
	assert_vector(hit.collider_velocity).is_equal(expected_v)
	assert_float(hit.collider_velocity.length()).is_equal_approx(PI / 2.0 * AXIS_DISTANCE, VELOCITY_TOLERANCE)


func test_cast_ground_on_mover_top_returns_mover_hit_with_point_velocity() -> void:
	# Arrange: a spinning platform (top at y = 1.25) over the quadrant ground at y = 0.
	var platform: MoverDef = Fixtures.spinner_box(ID, Vector3(0.0, 1.0, 0.0), Vector3(1.0, 0.25, 1.0))
	var data: TrackCollisionData = Fixtures.quadrant_ground([0, 1, 2, 3])
	data.movers = [platform]
	var query: CollisionQuery = CollisionQuery.new(data)
	var cursor: QueryCursor = QueryCursor.new()
	var hit: GroundHit = GroundHit.new()
	var origin: Vector3 = Vector3(0.5, CAST_Y, 0.5)
	# Act
	var did_hit: bool = query.cast_ground(cursor, origin, Vector3.DOWN, Fixtures.CAST_LENGTH, 0.0, hit)
	var expected_v: Vector3 = query.mover_point_velocity(ID, 0.0, hit.point)
	query.dispose()
	# Assert: the platform is nearer than the ground; v = (0, pi/2, 0) x (0.5, 0.25, 0.5).
	assert_bool(did_hit).is_true()
	assert_int(hit.collider_id).is_equal(ID)
	assert_int(hit.surface_id).is_equal(0)  # MoverDef.surface_id default (road)
	assert_vector(hit.point).is_equal_approx(Vector3(0.5, 1.25, 0.5), Vector3.ONE * HIT_TOLERANCE)
	assert_vector(hit.normal).is_equal_approx(Vector3.UP, Vector3.ONE * HIT_TOLERANCE)
	assert_vector(hit.collider_velocity).is_equal(expected_v)
	assert_vector(hit.collider_velocity).is_equal_approx(Vector3(PI / 4.0, 0.0, -PI / 4.0), Vector3.ONE * VELOCITY_TOLERANCE)


# --- Story AC 3: mover overlap -------------------------------------------------------------------------

func test_mover_moving_into_stationary_kart_sets_started_inside() -> void:
	# Arrange: a box (half 0.5) sliding +X at 5 m/s from x = -5; the kart sits still at the origin.
	# At t = 0.8 the box centre is at x = -1, overlapping the sphere by 0.5.
	var box: MoverDef = Fixtures.slide_box(ID, Vector3(-5.0, 0.0, 0.0), Vector3.ONE * 0.5)
	var query: CollisionQuery = _movers_query([box])
	var cursor: QueryCursor = QueryCursor.new()
	var kart: Vector3 = Vector3.ZERO
	var before: WallHit = _sentinel_wall_hit()
	var hit: WallHit = WallHit.new()
	# Act
	var hit_before: bool = query.sweep_walls(cursor, kart, kart, R, 0.0, before)
	var hit_after: bool = query.sweep_walls(cursor, kart, kart, R, 0.8, hit)
	query.dispose()
	# Assert
	assert_bool(hit_before).is_false()
	_assert_wall_sentinel(before)
	assert_bool(hit_after).is_true()
	assert_bool(hit.started_inside).is_true()
	assert_float(hit.fraction).is_equal(0.0)
	assert_int(hit.collider_id).is_equal(ID)
	assert_int(hit.wall_attr).is_equal(0)  # MoverDef.wall_attr_id default (standard)
	assert_vector(hit.point).is_equal_approx(Vector3(-0.5, 0.0, 0.0), Vector3.ONE * HIT_TOLERANCE)
	assert_vector(hit.normal).is_equal_approx(Vector3.RIGHT, Vector3.ONE * HIT_TOLERANCE)
	assert_vector(hit.collider_velocity).is_equal_approx(Vector3(5.0, 0.0, 0.0), Vector3.ONE * VELOCITY_TOLERANCE)


func test_moving_kart_started_inside_mover_runs_no_sweep() -> void:
	# Arrange: the kart starts 0.3 m inside a still box's +X face and moves on into it.
	var query: CollisionQuery = _movers_query([Fixtures.still_box(ID, Vector3.ZERO, UNIT_BOX)])
	var cursor: QueryCursor = QueryCursor.new()
	var hit: WallHit = WallHit.new()
	var from: Vector3 = Vector3(UNIT_BOX.x + R - 0.3, 0.0, 0.0)
	# Act
	var did_hit: bool = query.sweep_walls(cursor, from, from + Vector3.LEFT * 4.0, R, 0.0, hit)
	query.dispose()
	# Assert: the overlap at from, not a contact along the motion.
	assert_bool(did_hit).is_true()
	assert_bool(hit.started_inside).is_true()
	assert_float(hit.fraction).is_equal(0.0)
	assert_vector(hit.point).is_equal_approx(Vector3(UNIT_BOX.x, 0.0, 0.0), Vector3.ONE * HIT_TOLERANCE)
	assert_vector(hit.normal).is_equal_approx(Vector3.RIGHT, Vector3.ONE * HIT_TOLERANCE)
	assert_vector(hit.collider_velocity).is_equal(Vector3.ZERO)


func test_mover_deeper_than_static_wall_wins_overlap() -> void:
	# Arrange: the kart overlaps the rough wall (x = 0, facing +X) by 0.2 and a still box (half 0.5)
	# on its +X side by 0.5.
	var data: TrackCollisionData = Fixtures.attr_walls(Fixtures.wall_registry())
	var kart: Vector3 = Vector3(R - 0.2, Fixtures.SWEEP_Y, Fixtures.wall_centre_z(0))
	data.movers = [Fixtures.still_box(ID, kart + Vector3.RIGHT * (R + 0.5 - 0.5), Vector3.ONE * 0.5)]
	var query: CollisionQuery = CollisionQuery.new(data)
	var cursor: QueryCursor = QueryCursor.new()
	var hit: WallHit = WallHit.new()
	# Act
	var did_hit: bool = query.sweep_walls(cursor, kart, kart + Vector3.FORWARD, R, 0.0, hit)
	query.dispose()
	# Assert
	assert_bool(did_hit).is_true()
	assert_bool(hit.started_inside).is_true()
	assert_int(hit.collider_id).is_equal(ID)
	assert_int(hit.wall_attr).is_equal(0)  # MoverDef.wall_attr_id default (standard)
	assert_vector(hit.normal).is_equal_approx(Vector3.LEFT, Vector3.ONE * HIT_TOLERANCE)
	assert_vector(hit.point).is_equal_approx(kart + Vector3.RIGHT * 0.5, Vector3.ONE * HIT_TOLERANCE)


func test_static_wall_deeper_than_mover_wins_overlap() -> void:
	# Arrange: the kart overlaps the rough wall by 0.2 and the still box by only 0.1.
	var data: TrackCollisionData = Fixtures.attr_walls(Fixtures.wall_registry())
	var kart: Vector3 = Vector3(R - 0.2, Fixtures.SWEEP_Y, Fixtures.wall_centre_z(0))
	data.movers = [Fixtures.still_box(ID, kart + Vector3.RIGHT * (R + 0.5 - 0.1), Vector3.ONE * 0.5)]
	var query: CollisionQuery = CollisionQuery.new(data)
	var cursor: QueryCursor = QueryCursor.new()
	var hit: WallHit = WallHit.new()
	var rough_id: int = Fixtures.WALL_REGISTRY_IDS[Fixtures.WALL_REGISTRY_NAMES.find(&"rough")]
	# Act
	var did_hit: bool = query.sweep_walls(cursor, kart, kart + Vector3.FORWARD, R, 0.0, hit)
	query.dispose()
	# Assert
	assert_bool(did_hit).is_true()
	assert_bool(hit.started_inside).is_true()
	assert_int(hit.collider_id).is_equal(0)
	assert_int(hit.wall_attr).is_equal(rough_id)
	assert_vector(hit.normal).is_equal_approx(Vector3.RIGHT, Vector3.ONE * HIT_TOLERANCE)
	assert_vector(hit.collider_velocity).is_equal(Vector3.ZERO)


func test_non_solid_mover_never_blocks_sweep_or_ground_cast() -> void:
	# Arrange: a non-solid box over the ground, overlapping the kart and across its path.
	var barrel: MoverDef = Fixtures.still_box(ID, Vector3(0.0, 1.0, 0.0), Vector3(1.0, 0.5, 1.0))
	barrel.solid = false
	var data: TrackCollisionData = Fixtures.quadrant_ground([0, 1, 2, 3])
	data.movers = [barrel]
	var query: CollisionQuery = CollisionQuery.new(data)
	var cursor: QueryCursor = QueryCursor.new()
	var inside: WallHit = _sentinel_wall_hit()
	var through: WallHit = _sentinel_wall_hit()
	var ground: GroundHit = GroundHit.new()
	# Act
	var hit_inside: bool = query.sweep_walls(cursor, Vector3(0.0, 1.0, 0.0), Vector3(0.0, 1.0, -0.5), R, 0.0, inside)
	var hit_through: bool = query.sweep_walls(cursor, Vector3(4.0, 1.0, 0.0), Vector3(-4.0, 1.0, 0.0), R, 0.0, through)
	var hit_ground: bool = query.cast_ground(cursor, Vector3(0.5, CAST_Y, 0.5), Vector3.DOWN, Fixtures.CAST_LENGTH, 0.0, ground)
	var pose: Transform3D = query.mover_pose(ID, 0.0)
	query.dispose()
	# Assert: sweeps miss; the ground cast passes the barrel and hits the ground (rear-right, id 3).
	assert_bool(hit_inside).is_false()
	_assert_wall_sentinel(inside)
	assert_bool(hit_through).is_false()
	_assert_wall_sentinel(through)
	assert_bool(hit_ground).is_true()
	assert_int(ground.collider_id).is_equal(0)
	assert_int(ground.surface_id).is_equal(3)
	assert_float(ground.point.y).is_equal_approx(0.0, HIT_TOLERANCE)
	assert_vector(pose.origin).is_equal(Vector3(0.0, 1.0, 0.0))


# --- Story AC 4: one evaluator ---------------------------------------------------------------------

func test_mover_pose_same_t_is_bit_identical_across_calls_and_queries() -> void:
	# Arrange: "simulation" (query A, t = n x SIM_DT, twice) and "presentation" (query B over the same
	# data, the same t).
	var data: TrackCollisionData = Fixtures.movers_only([_tumbler()])
	var sim: CollisionQuery = CollisionQuery.new(data)
	var presentation: CollisionQuery = CollisionQuery.new(data)
	var t: float = 77 * SIM_DT
	var p: Vector3 = Vector3(0.3, 0.2, 0.1)
	# Act
	var sim_1: Transform3D = sim.mover_pose(ID, t)
	sim.mover_pose(ID, t + SIM_DT)  # another evaluation in between
	var sim_2: Transform3D = sim.mover_pose(ID, t)
	var shown: Transform3D = presentation.mover_pose(ID, t)
	var v_sim: Vector3 = sim.mover_point_velocity(ID, t, p)
	var v_shown: Vector3 = presentation.mover_point_velocity(ID, t, p)
	sim.dispose()
	presentation.dispose()
	# Assert: exact equality (==), not approximate.
	assert_bool(sim_1 == sim_2).is_true()
	assert_bool(sim_1 == shown).is_true()
	assert_bool(v_sim == v_shown).is_true()


func test_no_key_pos_use_outside_core_collision() -> void:
	# Arrange
	var files: Array[String] = []
	_gd_files_under("res://src", files)
	var offenders: Array[String] = []
	# Act
	var unreadable: Array[String] = []
	for path in files:
		var text: String = FileAccess.get_file_as_string(path)
		if FileAccess.get_open_error() != OK or text.is_empty():
			unreadable.append(path)
		if path.begins_with("res://src/core/collision/"):
			continue
		if text.contains("key_pos"):
			offenders.append(path)
	# Assert: every file was read, the scan saw the collision sources, nothing else reads mover keys.
	assert_array(unreadable).is_empty()
	assert_array(files).contains(["res://src/core/collision/collision_query.gd"])
	assert_array(offenders).is_empty()


# --- Ground casts against movers -------------------------------------------------------------------

func test_cast_ground_beside_mover_returns_static_ground() -> void:
	# Arrange
	var data: TrackCollisionData = Fixtures.quadrant_ground([0, 1, 2, 3])
	data.movers = [Fixtures.still_box(ID, Vector3(0.0, 1.0, 0.0), Vector3(1.0, 0.25, 1.0))]
	var query: CollisionQuery = CollisionQuery.new(data)
	var hit: GroundHit = GroundHit.new()
	# Act: x = 1.5 is beyond the box's half extent of 1.
	var did_hit: bool = query.cast_ground(QueryCursor.new(), Vector3(1.5, CAST_Y, 1.5), Vector3.DOWN, Fixtures.CAST_LENGTH, 0.0, hit)
	query.dispose()
	# Assert
	assert_bool(did_hit).is_true()
	assert_int(hit.collider_id).is_equal(0)
	assert_int(hit.surface_id).is_equal(3)
	assert_vector(hit.collider_velocity).is_equal(Vector3.ZERO)


func test_cast_ground_static_ground_nearer_than_mover_wins() -> void:
	# Arrange: the box lies below the ground.
	var data: TrackCollisionData = Fixtures.quadrant_ground([0, 1, 2, 3])
	data.movers = [Fixtures.still_box(ID, Vector3(0.0, -1.0, 0.0), Vector3(1.0, 0.25, 1.0))]
	var query: CollisionQuery = CollisionQuery.new(data)
	var hit: GroundHit = GroundHit.new()
	# Act
	var did_hit: bool = query.cast_ground(QueryCursor.new(), Vector3(0.5, CAST_Y, 0.5), Vector3.DOWN, Fixtures.CAST_LENGTH, 0.0, hit)
	query.dispose()
	# Assert
	assert_bool(did_hit).is_true()
	assert_int(hit.collider_id).is_equal(0)
	assert_int(hit.surface_id).is_equal(3)
	assert_float(hit.point.y).is_equal_approx(0.0, HIT_TOLERANCE)


func test_cast_ground_hits_mover_with_no_ground_below() -> void:
	# Arrange
	var query: CollisionQuery = _movers_query([Fixtures.still_box(ID, Vector3(0.0, 1.0, 0.0), UNIT_BOX)])
	var hit: GroundHit = GroundHit.new()
	# Act
	var did_hit: bool = query.cast_ground(QueryCursor.new(), Vector3(0.2, CAST_Y, -0.3), Vector3.DOWN, Fixtures.CAST_LENGTH, 0.0, hit)
	query.dispose()
	# Assert
	assert_bool(did_hit).is_true()
	assert_int(hit.collider_id).is_equal(ID)
	assert_vector(hit.point).is_equal_approx(Vector3(0.2, 2.0, -0.3), Vector3.ONE * HIT_TOLERANCE)
	assert_vector(hit.normal).is_equal_approx(Vector3.UP, Vector3.ONE * HIT_TOLERANCE)
	assert_vector(hit.collider_velocity).is_equal(Vector3.ZERO)


func test_cast_ground_hits_capsule_cap_and_cylinder_top_and_side() -> void:
	# Arrange: a capsule (r 0.5, half_height 1) at the origin, a cylinder (same sizes) at x = 10.
	var capsule: MoverDef = Fixtures.still_round(ID, MoverDef.Shape.CAPSULE, Vector3.ZERO, 0.5, 1.0)
	var cylinder: MoverDef = Fixtures.still_round(ID_2, MoverDef.Shape.CYLINDER, Vector3(10.0, 0.0, 0.0), 0.5, 1.0)
	var query: CollisionQuery = _movers_query([capsule, cylinder])
	var cursor: QueryCursor = QueryCursor.new()
	var cap_hit: GroundHit = GroundHit.new()
	var top_hit: GroundHit = GroundHit.new()
	var side_hit: GroundHit = GroundHit.new()
	# Act
	var on_cap: bool = query.cast_ground(cursor, Vector3(0.2, CAST_Y, 0.0), Vector3.DOWN, Fixtures.CAST_LENGTH, 0.0, cap_hit)
	var on_top: bool = query.cast_ground(cursor, Vector3(10.3, CAST_Y, 0.0), Vector3.DOWN, Fixtures.CAST_LENGTH, 0.0, top_hit)
	var on_side: bool = query.cast_ground(cursor, Vector3(15.0, 0.5, 0.0), Vector3.LEFT, Fixtures.CAST_LENGTH, 0.0, side_hit)
	query.dispose()
	# Assert: capsule top sphere at y = 1: y = 1 + sqrt(0.25 - 0.04).
	var cap_y: float = 1.0 + sqrt(0.25 - 0.04)
	assert_bool(on_cap).is_true()
	assert_int(cap_hit.collider_id).is_equal(ID)
	assert_vector(cap_hit.point).is_equal_approx(Vector3(0.2, cap_y, 0.0), Vector3.ONE * HIT_TOLERANCE)
	assert_vector(cap_hit.normal).is_equal_approx(Vector3(0.2, cap_y - 1.0, 0.0) / 0.5, Vector3.ONE * HIT_TOLERANCE)
	assert_bool(on_top).is_true()
	assert_int(top_hit.collider_id).is_equal(ID_2)
	assert_vector(top_hit.point).is_equal_approx(Vector3(10.3, 1.0, 0.0), Vector3.ONE * HIT_TOLERANCE)
	assert_vector(top_hit.normal).is_equal_approx(Vector3.UP, Vector3.ONE * HIT_TOLERANCE)
	assert_bool(on_side).is_true()
	assert_vector(side_hit.point).is_equal_approx(Vector3(10.5, 0.5, 0.0), Vector3.ONE * HIT_TOLERANCE)
	assert_vector(side_hit.normal).is_equal_approx(Vector3.RIGHT, Vector3.ONE * HIT_TOLERANCE)


func test_cast_ground_starting_inside_mover_misses_it() -> void:
	# Arrange: the ray starts inside the box; ground lies below.
	var data: TrackCollisionData = Fixtures.quadrant_ground([0, 1, 2, 3])
	data.movers = [Fixtures.still_box(ID, Vector3(0.0, 1.0, 0.0), UNIT_BOX)]
	var query: CollisionQuery = CollisionQuery.new(data)
	var hit: GroundHit = GroundHit.new()
	# Act
	var did_hit: bool = query.cast_ground(QueryCursor.new(), Vector3(0.5, 1.5, 0.5), Vector3.DOWN, Fixtures.CAST_LENGTH, 0.0, hit)
	query.dispose()
	# Assert: no back-face hit on the box's bottom; the ground is hit.
	assert_bool(did_hit).is_true()
	assert_int(hit.collider_id).is_equal(0)
	assert_float(hit.point.y).is_equal_approx(0.0, HIT_TOLERANCE)


func test_cast_ground_miss_with_movers_leaves_hit_untouched() -> void:
	# Arrange
	var query: CollisionQuery = _movers_query([Fixtures.still_box(ID, Vector3.ZERO, UNIT_BOX)])
	var hit: GroundHit = _sentinel_ground_hit()
	# Act: beside the box, and above it but too short to reach it.
	var beside: bool = query.cast_ground(QueryCursor.new(), Vector3(3.0, CAST_Y, 0.0), Vector3.DOWN, Fixtures.CAST_LENGTH, 0.0, hit)
	var short: bool = query.cast_ground(QueryCursor.new(), Vector3(0.0, CAST_Y, 0.0), Vector3.DOWN, CAST_Y - 1.5, 0.0, hit)
	query.dispose()
	# Assert
	assert_bool(beside).is_false()
	assert_bool(short).is_false()
	_assert_ground_sentinel(hit)


# --- Wall sweeps against movers ---------------------------------------------------------------------

func test_sweep_into_box_mover_blocks_with_safe_fraction() -> void:
	# Arrange: from x = 5 to x = -5 into a still unit box: contact at centre x = 2, i.e. 3/10.
	var query: CollisionQuery = _movers_query([Fixtures.still_box(ID, Vector3.ZERO, UNIT_BOX)])
	var hit: WallHit = WallHit.new()
	# Act
	var did_hit: bool = query.sweep_walls(QueryCursor.new(), Vector3(5.0, 0.0, 0.0), Vector3(-5.0, 0.0, 0.0), R, 0.0, hit)
	query.dispose()
	# Assert
	assert_bool(did_hit).is_true()
	assert_bool(hit.started_inside).is_false()
	assert_float(hit.fraction).is_equal_approx(0.3, FRACTION_TOLERANCE)
	assert_float(hit.fraction).is_less_equal(0.3)
	assert_vector(hit.point).is_equal_approx(Vector3(1.0, 0.0, 0.0), Vector3.ONE * HIT_TOLERANCE)
	assert_vector(hit.normal).is_equal_approx(Vector3.RIGHT, Vector3.ONE * HIT_TOLERANCE)
	assert_int(hit.collider_id).is_equal(ID)
	assert_vector(hit.collider_velocity).is_equal(Vector3.ZERO)


func test_sweep_past_box_edge_and_cylinder_rim_hits_rounded_contact() -> void:
	# Arrange: both paths run along -X at 0.6 above the top face, so the sphere meets the top edge /
	# rim (not a face): contact when the horizontal offset from the edge is sqrt(1 - 0.36) = 0.8.
	var box: MoverDef = Fixtures.still_box(ID, Vector3.ZERO, UNIT_BOX)
	var cylinder: MoverDef = Fixtures.still_round(ID_2, MoverDef.Shape.CYLINDER, Vector3(0.0, 0.0, 20.0), 0.5, 1.0)
	var query: CollisionQuery = _movers_query([box, cylinder])
	var cursor: QueryCursor = QueryCursor.new()
	var box_hit: WallHit = WallHit.new()
	var rim_hit: WallHit = WallHit.new()
	# Act
	var on_box: bool = query.sweep_walls(cursor, Vector3(5.0, 1.6, 0.0), Vector3(-5.0, 1.6, 0.0), R, 0.0, box_hit)
	var on_rim: bool = query.sweep_walls(cursor, Vector3(5.0, 1.6, 20.0), Vector3(-5.0, 1.6, 20.0), R, 0.0, rim_hit)
	query.dispose()
	# Assert
	assert_bool(on_box).is_true()
	assert_float(box_hit.fraction).is_equal_approx((5.0 - 1.8) / 10.0, FRACTION_TOLERANCE)
	assert_vector(box_hit.point).is_equal_approx(Vector3(1.0, 1.0, 0.0), Vector3.ONE * HIT_TOLERANCE)
	assert_vector(box_hit.normal).is_equal_approx(Vector3(0.8, 0.6, 0.0), Vector3.ONE * HIT_TOLERANCE)
	assert_bool(on_rim).is_true()
	assert_int(rim_hit.collider_id).is_equal(ID_2)
	assert_float(rim_hit.fraction).is_equal_approx((5.0 - 1.3) / 10.0, FRACTION_TOLERANCE)
	assert_vector(rim_hit.point).is_equal_approx(Vector3(0.5, 1.0, 20.0), Vector3.ONE * HIT_TOLERANCE)
	assert_vector(rim_hit.normal).is_equal_approx(Vector3(0.8, 0.6, 0.0), Vector3.ONE * HIT_TOLERANCE)


func test_sweep_into_capsule_and_cylinder_movers_blocks_with_safe_fraction() -> void:
	# Arrange: a capsule (r 0.5, half_height 1) hit on its side; a cylinder (same) hit on its top.
	var capsule: MoverDef = Fixtures.still_round(ID, MoverDef.Shape.CAPSULE, Vector3.ZERO, 0.5, 1.0)
	var cylinder: MoverDef = Fixtures.still_round(ID_2, MoverDef.Shape.CYLINDER, Vector3(0.0, 0.0, 20.0), 0.5, 1.0)
	var query: CollisionQuery = _movers_query([capsule, cylinder])
	var cursor: QueryCursor = QueryCursor.new()
	var side_hit: WallHit = WallHit.new()
	var top_hit: WallHit = WallHit.new()
	# Act
	var on_side: bool = query.sweep_walls(cursor, Vector3(5.0, 0.5, 0.0), Vector3(-5.0, 0.5, 0.0), R, 0.0, side_hit)
	var on_top: bool = query.sweep_walls(cursor, Vector3(0.2, 5.0, 20.0), Vector3(0.2, -5.0, 20.0), R, 0.0, top_hit)
	query.dispose()
	# Assert: capsule contact at centre x = 1.5 (0.35); cylinder at centre y = 2 (0.3).
	assert_bool(on_side).is_true()
	assert_int(side_hit.collider_id).is_equal(ID)
	assert_float(side_hit.fraction).is_equal_approx(0.35, FRACTION_TOLERANCE)
	assert_vector(side_hit.point).is_equal_approx(Vector3(0.5, 0.5, 0.0), Vector3.ONE * HIT_TOLERANCE)
	assert_vector(side_hit.normal).is_equal_approx(Vector3.RIGHT, Vector3.ONE * HIT_TOLERANCE)
	assert_bool(on_top).is_true()
	assert_int(top_hit.collider_id).is_equal(ID_2)
	assert_float(top_hit.fraction).is_equal_approx(0.3, FRACTION_TOLERANCE)
	assert_vector(top_hit.point).is_equal_approx(Vector3(0.2, 1.0, 20.0), Vector3.ONE * HIT_TOLERANCE)
	assert_vector(top_hit.normal).is_equal_approx(Vector3.UP, Vector3.ONE * HIT_TOLERANCE)


func test_sweep_ending_flush_with_mover_is_touch_with_fraction_one() -> void:
	# Arrange: the move ends with the centre exactly R in front of the unit box's +X face.
	var query: CollisionQuery = _movers_query([Fixtures.still_box(ID, Vector3.ZERO, UNIT_BOX)])
	var hit: WallHit = WallHit.new()
	# Act
	var did_hit: bool = query.sweep_walls(QueryCursor.new(), Vector3(5.0, 0.0, 0.0), Vector3(UNIT_BOX.x + R, 0.0, 0.0), R, 0.0, hit)
	query.dispose()
	# Assert
	assert_bool(did_hit).is_true()
	assert_bool(hit.started_inside).is_false()
	assert_float(hit.fraction).is_equal(1.0)
	assert_int(hit.collider_id).is_equal(ID)
	assert_vector(hit.normal).is_equal_approx(Vector3.RIGHT, Vector3.ONE * HIT_TOLERANCE)


func test_sweep_passing_beside_mover_misses_and_leaves_hit_untouched() -> void:
	# Arrange: paths that stay clear: ending short of the box, passing 0.05 m above it (Newton's
	# method proves the miss: a slope >= 0 at a clear point), and far away.
	var query: CollisionQuery = _movers_query([Fixtures.still_box(ID, Vector3.ZERO, UNIT_BOX)])
	var cursor: QueryCursor = QueryCursor.new()
	var hit: WallHit = _sentinel_wall_hit()
	var y_clear: float = UNIT_BOX.y + R + 0.05
	# Act
	var short: bool = query.sweep_walls(cursor, Vector3(5.0, 0.0, 0.0), Vector3(2.1, 0.0, 0.0), R, 0.0, hit)
	var above: bool = query.sweep_walls(cursor, Vector3(5.0, y_clear, 0.0), Vector3(-5.0, y_clear, 0.0), R, 0.0, hit)
	var far: bool = query.sweep_walls(cursor, Vector3(50.0, 0.0, 0.0), Vector3(40.0, 0.0, 0.0), R, 0.0, hit)
	query.dispose()
	# Assert
	assert_bool(short).is_false()
	assert_bool(above).is_false()
	assert_bool(far).is_false()
	_assert_wall_sentinel(hit)


func test_sweep_mover_nearer_than_static_wall_wins() -> void:
	# Arrange: the rough wall at x = 0; a still box (half 0.5) at x = 3 between the kart and the wall.
	var data: TrackCollisionData = Fixtures.attr_walls(Fixtures.wall_registry())
	var z: float = Fixtures.wall_centre_z(0)
	data.movers = [Fixtures.still_box(ID, Vector3(3.0, Fixtures.SWEEP_Y, z), Vector3.ONE * 0.5)]
	var query: CollisionQuery = CollisionQuery.new(data)
	var hit: WallHit = WallHit.new()
	# Act: from x = 6 to x = -2: box contact at centre x = 4.5 (1.5 / 8), wall at x = 1 (5 / 8).
	var did_hit: bool = query.sweep_walls(QueryCursor.new(), Vector3(6.0, Fixtures.SWEEP_Y, z), Vector3(-2.0, Fixtures.SWEEP_Y, z), R, 0.0, hit)
	query.dispose()
	# Assert
	assert_bool(did_hit).is_true()
	assert_int(hit.collider_id).is_equal(ID)
	assert_int(hit.wall_attr).is_equal(0)  # MoverDef.wall_attr_id default (standard)
	assert_float(hit.fraction).is_equal_approx(1.5 / 8.0, FRACTION_TOLERANCE)


func test_sweep_static_wall_nearer_than_mover_wins() -> void:
	# Arrange: the still box sits behind the wall plane (x in [-1.5, -0.5]).
	var data: TrackCollisionData = Fixtures.attr_walls(Fixtures.wall_registry())
	var z: float = Fixtures.wall_centre_z(0)
	data.movers = [Fixtures.still_box(ID, Vector3(-1.0, Fixtures.SWEEP_Y, z), Vector3.ONE * 0.5)]
	var query: CollisionQuery = CollisionQuery.new(data)
	var hit: WallHit = WallHit.new()
	var rough_id: int = Fixtures.WALL_REGISTRY_IDS[Fixtures.WALL_REGISTRY_NAMES.find(&"rough")]
	# Act: from x = 6 to x = -2: wall contact at x = 1 (5 / 8), box at x = 0.5 (5.5 / 8).
	var did_hit: bool = query.sweep_walls(QueryCursor.new(), Vector3(6.0, Fixtures.SWEEP_Y, z), Vector3(-2.0, Fixtures.SWEEP_Y, z), R, 0.0, hit)
	query.dispose()
	# Assert
	assert_bool(did_hit).is_true()
	assert_int(hit.collider_id).is_equal(0)
	assert_int(hit.wall_attr).is_equal(rough_id)
	assert_float(hit.fraction).is_equal_approx(5.0 / 8.0, FRACTION_TOLERANCE)


# --- Review follow-ups: wrap, moved and rotated contacts, ids, two movers, ties ------------------

func test_mover_pose_at_non_float32_exact_last_key_time_returns_that_key() -> void:
	# Arrange: last keys at 3.7 s and 0.1 s, neither float32-exact (the float32 key sits a hair above
	# the float64 t, so a t equal to the key time must not fall into the loop segment).
	var a: Vector3 = Vector3(0.0, 0.0, 0.0)
	var b: Vector3 = Vector3(1.0, 0.0, 0.0)
	var c: Vector3 = Vector3(2.0, 0.0, 5.0)
	var late: MoverDef = Fixtures.mover(ID, MoverDef.Shape.BOX, 5.0, [0.0, 1.0, 3.7], [a, b, c],
			[Fixtures.ROT_IDENTITY, Fixtures.ROT_IDENTITY, Fixtures.ROT_IDENTITY])
	late.half_extents = UNIT_BOX
	var early: MoverDef = Fixtures.mover(ID_2, MoverDef.Shape.BOX, 1.0, [0.0, 0.1], [a, c],
			[Fixtures.ROT_IDENTITY, Fixtures.ROT_IDENTITY])
	early.half_extents = UNIT_BOX
	var query: CollisionQuery = _movers_query([late, early])
	# Act
	var at_late_key: Vector3 = query.mover_pose(ID, 3.7).origin
	var at_early_key: Vector3 = query.mover_pose(ID_2, 0.1).origin
	query.dispose()
	# Assert
	assert_vector(at_late_key).is_equal_approx(c, Vector3.ONE * POSE_TOLERANCE)
	assert_vector(at_early_key).is_equal_approx(c, Vector3.ONE * POSE_TOLERANCE)


func test_cast_ground_on_translating_mover_hits_moved_position_with_its_velocity() -> void:
	# Arrange: a deck (half 1 x 0.25 x 1, centre y 1) sliding +X at 5 m/s: at t = 1 it is at x = 5.
	var deck: MoverDef = Fixtures.slide_box(ID, Vector3(0.0, 1.0, 0.0), Vector3(1.0, 0.25, 1.0))
	var query: CollisionQuery = _movers_query([deck])
	var cursor: QueryCursor = QueryCursor.new()
	var hit: GroundHit = GroundHit.new()
	var old_spot: GroundHit = _sentinel_ground_hit()
	var t: float = 1.0
	# Act
	var on_deck: bool = query.cast_ground(cursor, Vector3(5.3, CAST_Y, 0.2), Vector3.DOWN, Fixtures.CAST_LENGTH, t, hit)
	var at_old_position: bool = query.cast_ground(cursor, Vector3(0.3, CAST_Y, 0.2), Vector3.DOWN, Fixtures.CAST_LENGTH, t, old_spot)
	query.dispose()
	# Assert
	assert_bool(on_deck).is_true()
	assert_int(hit.collider_id).is_equal(ID)
	assert_vector(hit.point).is_equal_approx(Vector3(5.3, 1.25, 0.2), Vector3.ONE * HIT_TOLERANCE)
	assert_vector(hit.collider_velocity).is_equal_approx(Vector3(5.0, 0.0, 0.0), Vector3.ONE * VELOCITY_TOLERANCE)
	assert_bool(at_old_position).is_false()
	_assert_ground_sentinel(old_spot)


func test_spinner_at_45_degrees_reports_rotated_contact_point_and_normal() -> void:
	# Arrange: at t = 0.5 the bar (half 3 x 0.5 x 0.25) is turned 45 deg about +Y.
	var query: CollisionQuery = _movers_query([Fixtures.spinner_box(ID, Vector3.ZERO, BAR)])
	var cursor: QueryCursor = QueryCursor.new()
	var t: float = Fixtures.SPIN_STEP_TIME * 0.5
	var basis: Basis = Basis(Vector3.UP, Fixtures.SPIN_STEP_ANGLE * 0.5)
	var top_point: Vector3 = basis * Vector3(2.0, BAR.y, 0.0)          # (1.414, 0.5, -1.414)
	var face_normal: Vector3 = basis * Vector3.BACK                     # (0.707, 0, 0.707)
	var face_point: Vector3 = basis * Vector3(1.0, 0.0, BAR.z)          # (0.884, 0, -0.530)
	var ground: GroundHit = GroundHit.new()
	var wall: WallHit = WallHit.new()
	# Act: down onto the rotated top; into the rotated +Z face along its normal (contact at 2 / 4).
	var on_top: bool = query.cast_ground(cursor, Vector3(top_point.x, CAST_Y, top_point.z), Vector3.DOWN, Fixtures.CAST_LENGTH, t, ground)
	var on_face: bool = query.sweep_walls(cursor, face_point + face_normal * 3.0, face_point - face_normal, R, t, wall)
	query.dispose()
	# Assert
	assert_bool(on_top).is_true()
	assert_vector(ground.point).is_equal_approx(top_point, Vector3.ONE * HIT_TOLERANCE)
	assert_vector(ground.normal).is_equal_approx(Vector3.UP, Vector3.ONE * HIT_TOLERANCE)
	assert_vector(ground.collider_velocity).is_equal_approx(Vector3.UP.cross(top_point) * (PI / 2.0), Vector3.ONE * VELOCITY_TOLERANCE)
	assert_bool(on_face).is_true()
	assert_float(wall.fraction).is_equal_approx(0.5, FRACTION_TOLERANCE)
	assert_vector(wall.point).is_equal_approx(face_point, Vector3.ONE * HIT_TOLERANCE)
	assert_vector(wall.normal).is_equal_approx(face_normal, Vector3.ONE * HIT_TOLERANCE)


func test_mover_hits_report_mover_surface_and_wall_attr_ids() -> void:
	# Arrange: a box carrying non-default ids (grass-like 6, rough-like 17).
	var box: MoverDef = Fixtures.still_box(ID, Vector3(0.0, 1.0, 0.0), UNIT_BOX)
	box.surface_id = 6
	box.wall_attr_id = 17
	var query: CollisionQuery = _movers_query([box])
	var cursor: QueryCursor = QueryCursor.new()
	var ground: GroundHit = GroundHit.new()
	var swept: WallHit = WallHit.new()
	var inside: WallHit = WallHit.new()
	# Act
	query.cast_ground(cursor, Vector3(0.0, CAST_Y, 0.0), Vector3.DOWN, Fixtures.CAST_LENGTH, 0.0, ground)
	query.sweep_walls(cursor, Vector3(5.0, 1.0, 0.0), Vector3(-5.0, 1.0, 0.0), R, 0.0, swept)
	query.sweep_walls(cursor, Vector3(1.5, 1.0, 0.0), Vector3(1.5, 1.0, 0.0), R, 0.0, inside)
	query.dispose()
	# Assert
	assert_int(ground.surface_id).is_equal(6)
	assert_int(swept.wall_attr).is_equal(17)
	assert_bool(inside.started_inside).is_true()
	assert_int(inside.wall_attr).is_equal(17)


func test_cast_ground_nearest_of_two_movers_wins_regardless_of_order() -> void:
	# Arrange: a low deck (top 1.25) and a high deck (top 3.25), in both data orders.
	var low: MoverDef = Fixtures.still_box(ID, Vector3(0.0, 1.0, 0.0), Vector3(1.0, 0.25, 1.0))
	var high: MoverDef = Fixtures.still_box(ID_2, Vector3(0.0, 3.0, 0.0), Vector3(1.0, 0.25, 1.0))
	var low_first: CollisionQuery = _movers_query([low, high])
	var high_first: CollisionQuery = _movers_query([high, low])
	var hit_a: GroundHit = GroundHit.new()
	var hit_b: GroundHit = GroundHit.new()
	var origin: Vector3 = Vector3(0.2, CAST_Y, 0.2)
	# Act
	low_first.cast_ground(QueryCursor.new(), origin, Vector3.DOWN, Fixtures.CAST_LENGTH, 0.0, hit_a)
	high_first.cast_ground(QueryCursor.new(), origin, Vector3.DOWN, Fixtures.CAST_LENGTH, 0.0, hit_b)
	low_first.dispose()
	high_first.dispose()
	# Assert
	assert_int(hit_a.collider_id).is_equal(ID_2)
	assert_float(hit_a.point.y).is_equal_approx(3.25, HIT_TOLERANCE)
	assert_int(hit_b.collider_id).is_equal(ID_2)


func test_deepest_of_two_overlapping_movers_wins() -> void:
	# Arrange: the kart (at the origin) overlaps box ID by 0.2 (listed first) and box ID_2 by 0.6.
	var shallow: MoverDef = Fixtures.still_box(ID, Vector3(R + 0.5 - 0.2, 0.0, 0.0), Vector3.ONE * 0.5)
	var deep: MoverDef = Fixtures.still_box(ID_2, Vector3(-(R + 0.5 - 0.6), 0.0, 0.0), Vector3.ONE * 0.5)
	var query: CollisionQuery = _movers_query([shallow, deep])
	var hit: WallHit = WallHit.new()
	# Act
	var did_hit: bool = query.sweep_walls(QueryCursor.new(), Vector3.ZERO, Vector3.ZERO, R, 0.0, hit)
	query.dispose()
	# Assert: the deep box is on -X, so its normal points +X toward the centre.
	assert_bool(did_hit).is_true()
	assert_bool(hit.started_inside).is_true()
	assert_int(hit.collider_id).is_equal(ID_2)
	assert_vector(hit.normal).is_equal_approx(Vector3.RIGHT, Vector3.ONE * HIT_TOLERANCE)
	assert_vector(hit.point).is_equal_approx(Vector3(-0.4, 0.0, 0.0), Vector3.ONE * HIT_TOLERANCE)


func test_cast_ground_static_ground_wins_exact_distance_tie() -> void:
	# Arrange: a box whose top is exactly the ground plane y = 0 (dyadic values: exact distances).
	var data: TrackCollisionData = Fixtures.quadrant_ground([0, 1, 2, 3])
	data.movers = [Fixtures.still_box(ID, Vector3(0.5, -0.5, 0.5), Vector3.ONE * 0.5)]
	var query: CollisionQuery = CollisionQuery.new(data)
	var hit: GroundHit = GroundHit.new()
	# Act
	var did_hit: bool = query.cast_ground(QueryCursor.new(), Vector3(0.5, CAST_Y, 0.5), Vector3.DOWN, Fixtures.CAST_LENGTH, 0.0, hit)
	query.dispose()
	# Assert
	assert_bool(did_hit).is_true()
	assert_int(hit.collider_id).is_equal(0)
	assert_int(hit.surface_id).is_equal(3)


func test_sweep_static_wall_wins_exact_fraction_tie() -> void:
	# Arrange: a box behind the rough wall with its +X face in the wall plane; the move ends flush
	# with both, so both are touches at fraction 1.0.
	var data: TrackCollisionData = Fixtures.attr_walls(Fixtures.wall_registry())
	var z: float = Fixtures.wall_centre_z(0)
	data.movers = [Fixtures.still_box(ID, Vector3(-0.5, Fixtures.SWEEP_Y, z), Vector3.ONE * 0.5)]
	var query: CollisionQuery = CollisionQuery.new(data)
	var hit: WallHit = WallHit.new()
	var rough_id: int = Fixtures.WALL_REGISTRY_IDS[Fixtures.WALL_REGISTRY_NAMES.find(&"rough")]
	# Act
	var did_hit: bool = query.sweep_walls(QueryCursor.new(), Vector3(5.0, Fixtures.SWEEP_Y, z), Vector3(R, Fixtures.SWEEP_Y, z), R, 0.0, hit)
	query.dispose()
	# Assert
	assert_bool(did_hit).is_true()
	assert_float(hit.fraction).is_equal(1.0)
	assert_int(hit.collider_id).is_equal(0)
	assert_int(hit.wall_attr).is_equal(rough_id)


func test_static_wall_wins_exact_overlap_depth_tie() -> void:
	# Arrange: the kart 0.75 in front of the rough wall and of a box whose +X face is in the wall
	# plane: both overlaps are 0.25 deep (dyadic values: exact depths).
	var data: TrackCollisionData = Fixtures.attr_walls(Fixtures.wall_registry())
	var z: float = Fixtures.wall_centre_z(0)
	data.movers = [Fixtures.still_box(ID, Vector3(-0.5, Fixtures.SWEEP_Y, z), Vector3.ONE * 0.5)]
	var query: CollisionQuery = CollisionQuery.new(data)
	var hit: WallHit = WallHit.new()
	var kart: Vector3 = Vector3(0.75, Fixtures.SWEEP_Y, z)
	var rough_id: int = Fixtures.WALL_REGISTRY_IDS[Fixtures.WALL_REGISTRY_NAMES.find(&"rough")]
	# Act
	var did_hit: bool = query.sweep_walls(QueryCursor.new(), kart, kart, R, 0.0, hit)
	query.dispose()
	# Assert
	assert_bool(did_hit).is_true()
	assert_bool(hit.started_inside).is_true()
	assert_int(hit.collider_id).is_equal(0)
	assert_int(hit.wall_attr).is_equal(rough_id)


# --- Mover layout checks ---------------------------------------------------------------------------

func test_layout_error_accepts_valid_movers_of_each_shape() -> void:
	# Arrange: a box, a capsule with half_height 0 (a sphere), a cylinder, a slide and a spinner.
	var movers: Array[MoverDef] = [
		Fixtures.still_box(1, Vector3.ZERO, UNIT_BOX),
		Fixtures.still_round(2, MoverDef.Shape.CAPSULE, Vector3.ZERO, 0.5, 0.0),
		Fixtures.still_round(3, MoverDef.Shape.CYLINDER, Vector3.ZERO, 0.5, 1.0),
		Fixtures.slide_box(4, Vector3.ZERO, UNIT_BOX),
		Fixtures.spinner_box(5, Vector3.ZERO, BAR),
	]
	# Act / Assert
	assert_str(_layout_error_of(movers)).is_empty()


func test_layout_error_rejects_mover_id_below_one() -> void:
	# Arrange
	var zero: MoverDef = Fixtures.still_box(0, Vector3.ZERO, UNIT_BOX)
	var negative: MoverDef = Fixtures.still_box(-2, Vector3.ZERO, UNIT_BOX)
	# Act / Assert
	assert_str(_layout_error_of([zero])).is_equal("movers[0]: id is 0 (mover ids are >= 1; 0 means static geometry)")
	assert_str(_layout_error_of([negative])).starts_with("movers[0]: id is -2")


func test_layout_error_rejects_duplicate_mover_ids() -> void:
	# Arrange
	var movers: Array[MoverDef] = [
		Fixtures.still_box(4, Vector3.ZERO, UNIT_BOX),
		Fixtures.still_box(6, Vector3.ZERO, UNIT_BOX),
		Fixtures.still_box(4, Vector3.ZERO, UNIT_BOX),
	]
	# Act / Assert
	assert_str(_layout_error_of(movers)).is_equal("movers[2] has id 4, already used by movers[0] (mover ids are unique)")


func test_layout_error_rejects_non_positive_period() -> void:
	# Arrange
	var zero: MoverDef = Fixtures.still_box(ID, Vector3.ZERO, UNIT_BOX)
	zero.period = 0.0
	var negative: MoverDef = Fixtures.still_box(ID, Vector3.ZERO, UNIT_BOX)
	negative.period = -1.0
	var not_finite: MoverDef = Fixtures.still_box(ID, Vector3.ZERO, UNIT_BOX)
	not_finite.period = INF
	# Act / Assert
	for m: MoverDef in [zero, negative, not_finite]:
		assert_str(_layout_error_of([m])).contains("period is")


func test_layout_error_rejects_unequal_key_arrays() -> void:
	# Arrange
	var short_pos: MoverDef = Fixtures.still_box(ID, Vector3.ZERO, UNIT_BOX)
	short_pos.key_pos = PackedVector3Array([Vector3.ZERO])
	var long_rot: MoverDef = Fixtures.still_box(ID, Vector3.ZERO, UNIT_BOX)
	long_rot.key_rot.append(Fixtures.ROT_IDENTITY)
	# Act / Assert
	assert_str(_layout_error_of([short_pos])).is_equal("movers[0]: key arrays differ in length (key_t 2, key_pos 1, key_rot 2)")
	assert_str(_layout_error_of([long_rot])).is_equal("movers[0]: key arrays differ in length (key_t 2, key_pos 2, key_rot 3)")


func test_layout_error_rejects_fewer_than_two_keys() -> void:
	# Arrange
	var one: MoverDef = Fixtures.mover(ID, MoverDef.Shape.BOX, 2.0, [0.0], [Vector3.ZERO], [Fixtures.ROT_IDENTITY])
	one.half_extents = UNIT_BOX
	var none: MoverDef = Fixtures.mover(ID, MoverDef.Shape.BOX, 2.0, [], [], [])
	none.half_extents = UNIT_BOX
	# Act / Assert
	assert_str(_layout_error_of([one])).is_equal("movers[0]: has 1 keys (at least 2)")
	assert_str(_layout_error_of([none])).is_equal("movers[0]: has 0 keys (at least 2)")


func test_layout_error_rejects_key_t_not_ascending() -> void:
	# Arrange: a repeated key time and a descending one.
	var repeated: MoverDef = Fixtures.mover(ID, MoverDef.Shape.BOX, 4.0, [0.0, 1.0, 1.0],
			[Vector3.ZERO, Vector3.ONE, Vector3.ZERO], [Fixtures.ROT_IDENTITY, Fixtures.ROT_IDENTITY, Fixtures.ROT_IDENTITY])
	repeated.half_extents = UNIT_BOX
	var descending: MoverDef = Fixtures.mover(ID, MoverDef.Shape.BOX, 4.0, [0.0, 2.0, 1.0],
			[Vector3.ZERO, Vector3.ONE, Vector3.ZERO], [Fixtures.ROT_IDENTITY, Fixtures.ROT_IDENTITY, Fixtures.ROT_IDENTITY])
	descending.half_extents = UNIT_BOX
	# Act / Assert
	assert_str(_layout_error_of([repeated])).starts_with("movers[0]: key_t[2] = ")
	assert_str(_layout_error_of([repeated])).contains("strictly ascend")
	assert_str(_layout_error_of([descending])).starts_with("movers[0]: key_t[2] = ")
	assert_str(_layout_error_of([descending])).contains("strictly ascend")


func test_layout_error_rejects_key_t_outside_period() -> void:
	# Arrange: a negative first key; a last key at the period; a last key past it.
	var negative: MoverDef = Fixtures.still_box(ID, Vector3.ZERO, UNIT_BOX)
	negative.key_t = PackedFloat32Array([-0.5, 1.0])
	var at_period: MoverDef = Fixtures.still_box(ID, Vector3.ZERO, UNIT_BOX)
	at_period.key_t = PackedFloat32Array([0.0, at_period.period])
	var past_period: MoverDef = Fixtures.still_box(ID, Vector3.ZERO, UNIT_BOX)
	past_period.key_t = PackedFloat32Array([0.0, past_period.period + 1.0])
	# Act / Assert
	assert_str(_layout_error_of([negative])).starts_with("movers[0]: key_t[0] is -0.5")
	assert_str(_layout_error_of([at_period])).contains("is not before period")
	assert_str(_layout_error_of([past_period])).contains("is not before period")


func test_layout_error_rejects_invalid_extents_for_shape() -> void:
	# Arrange
	var flat_box: MoverDef = Fixtures.still_box(ID, Vector3.ZERO, Vector3(1.0, 0.0, 1.0))
	var thin_capsule: MoverDef = Fixtures.still_round(ID, MoverDef.Shape.CAPSULE, Vector3.ZERO, 0.0, 1.0)
	var inverted_capsule: MoverDef = Fixtures.still_round(ID, MoverDef.Shape.CAPSULE, Vector3.ZERO, 0.5, -0.1)
	var flat_cylinder: MoverDef = Fixtures.still_round(ID, MoverDef.Shape.CYLINDER, Vector3.ZERO, 0.5, 0.0)
	var thin_cylinder: MoverDef = Fixtures.still_round(ID, MoverDef.Shape.CYLINDER, Vector3.ZERO, 0.0, 1.0)
	# A box's radius / half_height and a capsule's half_extents are ignored.
	var box_with_radius: MoverDef = Fixtures.still_box(ID, Vector3.ZERO, UNIT_BOX)
	box_with_radius.radius = 0.0
	# Act / Assert
	assert_str(_layout_error_of([flat_box])).starts_with("movers[0]: BOX half_extents")
	assert_str(_layout_error_of([thin_capsule])).starts_with("movers[0]: CAPSULE needs radius > 0")
	assert_str(_layout_error_of([inverted_capsule])).starts_with("movers[0]: CAPSULE needs radius > 0")
	assert_str(_layout_error_of([flat_cylinder])).starts_with("movers[0]: CYLINDER needs radius > 0")
	assert_str(_layout_error_of([thin_cylinder])).starts_with("movers[0]: CYLINDER needs radius > 0")
	assert_str(_layout_error_of([box_with_radius])).is_empty()


func test_layout_error_rejects_unknown_shape() -> void:
	# Arrange: a .res can hold any int in the enum field.
	var odd: MoverDef = Fixtures.still_box(ID, Vector3.ZERO, UNIT_BOX)
	odd.shape = 7 as MoverDef.Shape
	# Act / Assert
	assert_str(_layout_error_of([odd])).is_equal("movers[0]: shape 7 is not BOX, CAPSULE or CYLINDER")


func test_layout_error_rejects_non_unit_key_rotation() -> void:
	# Arrange
	var scaled: MoverDef = Fixtures.still_box(ID, Vector3.ZERO, UNIT_BOX)
	scaled.key_rot = PackedVector4Array([Fixtures.ROT_IDENTITY, Vector4(0.0, 0.0, 0.0, 2.0)])
	var zero: MoverDef = Fixtures.still_box(ID, Vector3.ZERO, UNIT_BOX)
	zero.key_rot = PackedVector4Array([Vector4.ZERO, Fixtures.ROT_IDENTITY])
	# Act / Assert
	assert_str(_layout_error_of([scaled])).starts_with("movers[0]: key_rot[1]")
	assert_str(_layout_error_of([zero])).starts_with("movers[0]: key_rot[0]")


func test_layout_error_rejects_null_mover() -> void:
	# Arrange
	var movers: Array[MoverDef] = [Fixtures.still_box(ID, Vector3.ZERO, UNIT_BOX), null]
	# Act / Assert
	assert_str(_layout_error_of(movers)).is_equal("movers[1] is null")


func test_query_from_bad_mover_push_errors_and_has_no_movers() -> void:
	# Arrange
	var data: TrackCollisionData = Fixtures.movers_only([Fixtures.still_box(0, Vector3.ZERO, UNIT_BOX)])
	var out: Array[CollisionQuery] = []
	# Act / Assert
	await assert_error(func() -> void: out.append(CollisionQuery.new(data))).is_push_error(
			"CollisionQuery: movers[0]: id is 0 (mover ids are >= 1; 0 means static geometry); the query has no geometry")
	var query: CollisionQuery = out[0]
	var hit: WallHit = _sentinel_wall_hit()
	assert_bool(query.sweep_walls(QueryCursor.new(), Vector3.ZERO, Vector3.ZERO, R, 0.0, hit)).is_false()
	_assert_wall_sentinel(hit)
	query.dispose()


# --- Reuse and lifetime -----------------------------------------------------------------------------

func test_mover_queries_create_no_objects_over_1000_queries() -> void:
	# Arrange: ground, walls and three movers (spinning platform, sliding box, capsule); every path of
	# the mover code runs once before the baseline.
	var data: TrackCollisionData = Fixtures.ground_and_side_wall([0, 1, 2, 3])
	var platform: MoverDef = Fixtures.spinner_box(ID, Vector3(0.0, 1.0, 0.0), Vector3(1.0, 0.25, 1.0))
	var slider: MoverDef = Fixtures.slide_box(ID_2, Vector3(-5.0, 2.0, 0.0), Vector3.ONE * 0.5)
	var capsule: MoverDef = Fixtures.still_round(9, MoverDef.Shape.CAPSULE, Vector3(1.0, 3.0, 1.0), 0.5, 0.5)
	data.movers = [platform, slider, capsule]
	var query: CollisionQuery = CollisionQuery.new(data)
	var cursor: QueryCursor = QueryCursor.new()
	var ground: GroundHit = GroundHit.new()
	var wall: WallHit = WallHit.new()
	var down_on_platform: Vector3 = Vector3(0.5, CAST_Y, 0.5)
	var down_on_ground: Vector3 = Vector3(1.5, CAST_Y, -1.5)
	var into_capsule_from: Vector3 = Vector3(5.0, 3.0, 1.0)
	var into_capsule_to: Vector3 = Vector3(-1.0, 3.0, 1.0)
	# 0.05 m clear of the capsule's top (y 4): the Newton search proves a miss.
	var graze_from: Vector3 = Vector3(5.0, 5.05, 1.0)
	var graze_to: Vector3 = Vector3(-3.0, 5.05, 1.0)
	# Ends inside the platform: the bisection from a contact at the end.
	var drop_from: Vector3 = Vector3(-0.5, 3.0, -0.5)
	var drop_to: Vector3 = Vector3(-0.5, 1.6, -0.5)
	var t: float = 0.8
	var queries: Callable = func() -> void:
		query.cast_ground(cursor, down_on_platform, Vector3.DOWN, Fixtures.CAST_LENGTH, t, ground)
		query.cast_ground(cursor, down_on_ground, Vector3.DOWN, Fixtures.CAST_LENGTH, t, ground)
		query.sweep_walls(cursor, into_capsule_from, into_capsule_to, R, t, wall)
		query.sweep_walls(cursor, graze_from, graze_to, R, t, wall)
		query.sweep_walls(cursor, drop_from, drop_to, R, t, wall)
		query.sweep_walls(cursor, Vector3(-1.0, 2.0, 0.0), Vector3(-1.0, 2.0, -0.5), R, t, wall)
		query.mover_pose(ID, t)
		query.mover_point_velocity(ID, t, down_on_platform)
	queries.call()
	var baseline: int = int(Performance.get_monitor(Performance.OBJECT_COUNT))
	# Act
	for _n in OBJECT_CHECK_REPEATS:
		queries.call()
	var after: int = int(Performance.get_monitor(Performance.OBJECT_COUNT))
	query.dispose()
	# Assert
	assert_int(after).is_equal(baseline)


func test_mover_pose_of_unknown_id_push_errors_and_returns_identity() -> void:
	# Arrange
	var query: CollisionQuery = _movers_query([_slide()])
	var out: Array[Transform3D] = []
	# Act / Assert
	await assert_error(func() -> void: out.append(query.mover_pose(ID_2, 0.0))).is_push_error(
			"CollisionQuery.mover_pose: no mover with id %d" % ID_2)
	query.dispose()
	assert_bool(out[0] == Transform3D.IDENTITY).is_true()


func test_mover_pose_after_dispose_asserts_in_debug_or_returns_identity() -> void:
	# Arrange
	var query: CollisionQuery = _movers_query([_slide()])
	query.dispose()
	var out: Array[Transform3D] = []
	# Act / Assert: debug builds stop at assert(not _disposed); release builds return the identity.
	if OS.is_debug_build():
		await assert_error(func() -> void: out.append(query.mover_pose(ID, 1.0))).is_runtime_error(
				"Assertion failed: CollisionQuery.mover_pose after dispose()")
	else:
		assert_bool(query.mover_pose(ID, 1.0) == Transform3D.IDENTITY).is_true()


func test_mover_point_velocity_of_unknown_id_push_errors_and_returns_zero() -> void:
	# Arrange
	var query: CollisionQuery = _movers_query([_slide()])
	var out: Array[Vector3] = []
	# Act / Assert
	await assert_error(func() -> void: out.append(query.mover_point_velocity(ID_2, 0.0, Vector3.ONE))).is_push_error(
			"CollisionQuery.mover_point_velocity: no mover with id %d" % ID_2)
	query.dispose()
	assert_vector(out[0]).is_equal(Vector3.ZERO)


func test_layout_error_rejects_mover_ids_outside_u8() -> void:
	# Arrange
	var big_surface: MoverDef = Fixtures.still_box(ID, Vector3.ZERO, UNIT_BOX)
	big_surface.surface_id = 256
	var negative_surface: MoverDef = Fixtures.still_box(ID, Vector3.ZERO, UNIT_BOX)
	negative_surface.surface_id = -1
	var big_wall: MoverDef = Fixtures.still_box(ID, Vector3.ZERO, UNIT_BOX)
	big_wall.wall_attr_id = 256
	var top: MoverDef = Fixtures.still_box(ID, Vector3.ZERO, UNIT_BOX)
	top.surface_id = 255
	top.wall_attr_id = 255
	# Act / Assert
	assert_str(_layout_error_of([big_surface])).is_equal("movers[0]: surface_id is 256, outside 0..255")
	assert_str(_layout_error_of([negative_surface])).is_equal("movers[0]: surface_id is -1, outside 0..255")
	assert_str(_layout_error_of([big_wall])).is_equal("movers[0]: wall_attr_id is 256, outside 0..255")
	assert_str(_layout_error_of([top])).is_empty()


func test_layout_error_rejects_non_finite_key_position() -> void:
	# Arrange
	var infinite: MoverDef = Fixtures.still_box(ID, Vector3.ZERO, UNIT_BOX)
	infinite.key_pos = PackedVector3Array([Vector3.ZERO, Vector3(INF, 0.0, 0.0)])
	var nan_pos: MoverDef = Fixtures.still_box(ID, Vector3.ZERO, UNIT_BOX)
	nan_pos.key_pos = PackedVector3Array([Vector3(0.0, NAN, 0.0), Vector3.ZERO])
	# Act / Assert
	assert_str(_layout_error_of([infinite])).starts_with("movers[0]: key_pos[1]")
	assert_str(_layout_error_of([nan_pos])).starts_with("movers[0]: key_pos[0]")


func test_layout_error_rejects_nearly_unit_key_rotation() -> void:
	# Arrange: |q|^2 = 1.0002 passes Godot's is_normalized (0.001) but not UNIT_QUAT_TOLERANCE.
	var loose: MoverDef = Fixtures.still_box(ID, Vector3.ZERO, UNIT_BOX)
	loose.key_rot = PackedVector4Array([Fixtures.ROT_IDENTITY, Vector4(0.0, 0.0, 0.0, 1.0001)])
	# Act / Assert
	assert_str(_layout_error_of([loose])).starts_with("movers[0]: key_rot[1]")
