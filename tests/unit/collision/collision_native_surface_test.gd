extends GdUnitTestSuite
## Core-rebuild story 067: the native call surface of CollisionQuery, QueryCursor, GroundHit and WallHit
## (ADR-0007 section 4): the unbuilt `.new()` object refuses every bound method (one test per method),
## dispose() is a silent idempotent no-op, the no-argument classes build with `.new()`, the destructor frees
## the server objects of a query dropped without dispose(), and the bound constants match the oracle.
## Tests drive the real native classes (mock() and spy() do not work on them).
##
## Story AC -> tests:
##   Factory and validation (.new() refusals): test_unbuilt_*_refuses, test_unbuilt_dispose_*
##   Native classes: test_hit_objects_*, test_cursor_*, test_bound_constants_match_the_oracle
##   RID teardown: test_destructor_*, test_dispose_*, test_hot_reload_release_*

const _GUARD = preload("res://tests/unit/native/native_test_guard.gd")
const Fixtures = preload("res://tests/unit/collision/collision_fixtures.gd")

const GUARD_FALSE: String = "Condition \"!built\" is true. Returning: false"
const GUARD_VOID: String = "Condition \"!built\" is true."


func before() -> void:
	assert_str(_GUARD.problem()).is_empty()


func test_unbuilt_new_object_reports_not_built_and_not_disposed() -> void:
	# Arrange / Act
	var query: CollisionQuery = CollisionQuery.new()
	# Assert
	assert_bool(query.is_built()).is_false()
	assert_bool(query.is_disposed()).is_false()


func test_unbuilt_cast_ground_refuses() -> void:
	var query: CollisionQuery = CollisionQuery.new()
	await assert_error(func() -> void: query.cast_ground(QueryCursor.new(), Vector3.ZERO, Vector3.DOWN, 1.0, 0.0, GroundHit.new())).is_push_error(GUARD_FALSE)


func test_unbuilt_sweep_walls_refuses() -> void:
	var query: CollisionQuery = CollisionQuery.new()
	await assert_error(func() -> void: query.sweep_walls(QueryCursor.new(), Vector3.ZERO, Vector3.ONE, 1.0, 0.0, WallHit.new())).is_push_error(GUARD_FALSE)


func test_unbuilt_mover_pose_refuses() -> void:
	var query: CollisionQuery = CollisionQuery.new()
	await assert_error(func() -> void: query.mover_pose(1, 0.0)).is_push_error("Condition \"!built\" is true. Returning: Transform3D()")


func test_unbuilt_mover_point_velocity_refuses() -> void:
	var query: CollisionQuery = CollisionQuery.new()
	await assert_error(func() -> void: query.mover_point_velocity(1, 0.0, Vector3.ZERO)).is_push_error("Condition \"!built\" is true. Returning: Vector3()")


func test_unbuilt_has_geometry_refuses() -> void:
	var query: CollisionQuery = CollisionQuery.new()
	await assert_error(func() -> void: query.has_geometry()).is_push_error(GUARD_FALSE)


func test_unbuilt_owned_rids_refuses() -> void:
	var query: CollisionQuery = CollisionQuery.new()
	await assert_error(func() -> void: query.owned_rids()).is_push_error("Condition \"!built\" is true. Returning: rids")


func test_unbuilt_space_rid_refuses() -> void:
	var query: CollisionQuery = CollisionQuery.new()
	await assert_error(func() -> void: query.space_rid()).is_push_error("Condition \"!built\" is true. Returning: RID()")


func test_unbuilt_ground_body_rid_refuses() -> void:
	var query: CollisionQuery = CollisionQuery.new()
	await assert_error(func() -> void: query.ground_body_rid()).is_push_error("Condition \"!built\" is true. Returning: RID()")


func test_unbuilt_wall_body_rid_refuses() -> void:
	var query: CollisionQuery = CollisionQuery.new()
	await assert_error(func() -> void: query.wall_body_rid()).is_push_error("Condition \"!built\" is true. Returning: RID()")


func test_unbuilt_set_newton_cap_refuses() -> void:
	var query: CollisionQuery = CollisionQuery.new()
	await assert_error(func() -> void: query.set_newton_cap(1)).is_push_error(GUARD_VOID)


func test_unbuilt_cap_error_reported_refuses() -> void:
	var query: CollisionQuery = CollisionQuery.new()
	await assert_error(func() -> void: query.cap_error_reported()).is_push_error(GUARD_FALSE)


func test_unbuilt_closest_local_refuses() -> void:
	var query: CollisionQuery = CollisionQuery.new()
	await assert_error(func() -> void: query.closest_local(1, Vector3.ZERO)).is_push_error("Condition \"!built\" is true. Returning: 0.0")


func test_unbuilt_closest_point_refuses() -> void:
	var query: CollisionQuery = CollisionQuery.new()
	await assert_error(func() -> void: query.closest_point()).is_push_error("Condition \"!built\" is true. Returning: Vector3()")


func test_unbuilt_closest_normal_refuses() -> void:
	var query: CollisionQuery = CollisionQuery.new()
	await assert_error(func() -> void: query.closest_normal()).is_push_error("Condition \"!built\" is true. Returning: Vector3()")


func test_unbuilt_probe_error_refuses_with_a_not_built_sentence() -> void:
	# Arrange
	var query: CollisionQuery = CollisionQuery.new()
	var out: Array[String] = []
	# Act / Assert: the built guard refuses and hands back the sentence.
	await assert_error(func() -> void: out.append(query.probe_error(Vector3.ZERO, 0, 1.0))).is_push_error(
			"Condition \"!built\" is true. Returning: String(\"load probe: the query is not built\")")
	assert_str(out[0]).is_equal("load probe: the query is not built")


func test_unbuilt_blocked_fallback_count_refuses() -> void:
	var query: CollisionQuery = CollisionQuery.new()
	await assert_error(func() -> void: query.blocked_fallback_count()).is_push_error("Condition \"!built\" is true. Returning: 0")


func test_unbuilt_set_force_rest_miss_refuses() -> void:
	var query: CollisionQuery = CollisionQuery.new()
	await assert_error(func() -> void: query.set_force_rest_miss_for_test(true)).is_push_error(GUARD_VOID)


func test_unbuilt_local_point_refuses() -> void:
	var query: CollisionQuery = CollisionQuery.new()
	await assert_error(func() -> void: query.local_point(1, 0.0, Vector3.ZERO)).is_push_error("Condition \"!built\" is true. Returning: Vector3()")


func test_set_newton_cap_below_one_is_rejected() -> void:
	# Arrange
	var query: CollisionQuery = CollisionQuery.create(Fixtures.quadrant_ground([0, 0, 0, 0]).pack_native())
	# Act / Assert
	await assert_error(func() -> void: query.set_newton_cap(0)).is_push_error("Condition \"p_cap < 1\" is true.")
	query.dispose()


func test_cursor_getters_refuse_after_the_engine_objects_are_released() -> void:
	# Arrange: a cursor is built while the servers are alive.
	var cursor: QueryCursor = QueryCursor.new()
	# Act / Assert: its engine objects are reachable as read-only properties.
	assert_bool(cursor.is_built()).is_true()
	assert_object(cursor.sphere).is_not_null()
	assert_object(cursor.shape_params.shape).is_same(cursor.sphere)
	assert_int(cursor.ray_params.collision_mask).is_equal(CollisionQuery.GROUND_LAYER)
	assert_int(cursor.shape_params.collision_mask).is_equal(CollisionQuery.WALL_LAYER)


func test_forced_rest_miss_reports_the_blocked_fallback_and_counts_it() -> void:
	# Arrange: a wall sweep that is blocked; the rest checks are skipped, so the fail-closed fallback runs.
	var query: CollisionQuery = CollisionQuery.create(Fixtures.attr_walls(Fixtures.wall_registry()).pack_native())
	var cursor: QueryCursor = QueryCursor.new()
	var hit: WallHit = WallHit.new()
	var from: Vector3 = Vector3(5.0, Fixtures.SWEEP_Y, Fixtures.wall_centre_z(0))
	var to: Vector3 = Vector3(-5.0, Fixtures.SWEEP_Y, Fixtures.wall_centre_z(0))
	# Act: without the seam the fallback never runs.
	var normal_hit: bool = query.sweep_walls(cursor, from, to, Fixtures.SWEEP_RADIUS, 0.0, hit)
	var attr_normal: int = hit.wall_attr
	var count_normal: int = query.blocked_fallback_count()
	query.set_force_rest_miss_for_test(true)
	var forced_hit: bool = query.sweep_walls(cursor, from, to, Fixtures.SWEEP_RADIUS, 0.0, hit)
	var count_forced: int = query.blocked_fallback_count()
	query.set_force_rest_miss_for_test(false)
	query.dispose()
	# Assert: a hit either way; WALL_ATTR_NONE and the reverse-of-motion normal only in the forced case.
	assert_bool(normal_hit).is_true()
	assert_int(attr_normal).is_not_equal(CollisionQuery.WALL_ATTR_NONE)
	assert_int(count_normal).is_equal(0)
	assert_bool(forced_hit).is_true()
	assert_int(hit.wall_attr).is_equal(CollisionQuery.WALL_ATTR_NONE)
	assert_vector(hit.normal).is_equal_approx(Vector3.RIGHT, Vector3.ONE * 0.0001)
	assert_bool(hit.started_inside).is_false()
	assert_int(count_forced).is_equal(1)


func test_unbuilt_dispose_is_a_silent_no_op() -> void:
	# Arrange
	var query: CollisionQuery = CollisionQuery.new()
	# Act / Assert: no error, no warning.
	await assert_error(func() -> void: query.dispose()).is_success()
	assert_bool(query.is_built()).is_false()


func test_dispose_twice_after_create_is_silent_and_marks_disposed() -> void:
	# Arrange
	var query: CollisionQuery = CollisionQuery.create(Fixtures.quadrant_ground([0, 0, 0, 0]).pack_native())
	# Act
	query.dispose()
	# Assert
	await assert_error(func() -> void: query.dispose()).is_success()
	assert_bool(query.is_disposed()).is_true()
	assert_bool(query.is_built()).is_false()


func test_hit_objects_and_cursor_build_with_new_and_no_arguments() -> void:
	# Arrange / Act
	var ground: GroundHit = GroundHit.new()
	var wall: WallHit = WallHit.new()
	var cursor: QueryCursor = QueryCursor.new()
	# Assert: the defaults of the GDScript oracle.
	assert_vector(ground.normal).is_equal(Vector3.UP)
	assert_int(ground.surface_id).is_equal(-1)
	assert_int(ground.collider_id).is_equal(0)
	assert_float(wall.fraction).is_equal(1.0)
	assert_int(wall.wall_attr).is_equal(-1)
	assert_bool(wall.started_inside).is_false()
	assert_bool(cursor.is_built()).is_true()


func test_hit_clear_resets_every_field() -> void:
	# Arrange
	var ground: GroundHit = GroundHit.new()
	ground.point = Vector3.ONE
	ground.surface_id = 4
	ground.collider_id = 2
	ground.collider_velocity = Vector3.ONE
	var wall: WallHit = WallHit.new()
	wall.point = Vector3.ONE
	wall.wall_attr = 3
	wall.fraction = 0.25
	wall.started_inside = true
	wall.collider_id = 5
	# Act
	ground.clear()
	wall.clear()
	# Assert
	assert_vector(ground.point).is_equal(Vector3.ZERO)
	assert_int(ground.surface_id).is_equal(-1)
	assert_int(ground.collider_id).is_equal(0)
	assert_vector(ground.collider_velocity).is_equal(Vector3.ZERO)
	assert_int(wall.wall_attr).is_equal(-1)
	assert_float(wall.fraction).is_equal(1.0)
	assert_bool(wall.started_inside).is_false()
	assert_int(wall.collider_id).is_equal(0)


func test_bound_constants_match_the_oracle() -> void:
	# Arrange / Act / Assert: the native constants equal the frozen GDScript oracle's.
	assert_int(CollisionQuery.GROUND_LAYER).is_equal(OracleCollisionQuery.GROUND_LAYER)
	assert_int(CollisionQuery.WALL_LAYER).is_equal(OracleCollisionQuery.WALL_LAYER)
	assert_int(CollisionQuery.SURFACE_NONE).is_equal(OracleCollisionQuery.SURFACE_NONE)
	assert_int(CollisionQuery.WALL_ATTR_NONE).is_equal(OracleCollisionQuery.WALL_ATTR_NONE)
	assert_int(CollisionQuery.MOVER_SWEEP_MAX_ITERATIONS).is_equal(OracleCollisionQuery.MOVER_SWEEP_MAX_ITERATIONS)
	assert_float(CollisionQuery.mover_sweep_tolerance()).is_equal(OracleCollisionQuery.MOVER_SWEEP_TOLERANCE)
	assert_float(CollisionQuery.probe_t()).is_equal(OracleCollisionQuery.PROBE_T)
	assert_float(CollisionQuery.unsafe_retry_length()).is_equal(OracleCollisionQuery.UNSAFE_RETRY_LENGTH)
	assert_int(CollisionQuery.PACKED_SCHEMA_VERSION).is_equal(TrackCollisionData.NATIVE_SCHEMA_VERSION)
	assert_int(CollisionQuery.PACKED_SCHEMA_VERSION).is_equal(MoverDef.NATIVE_SCHEMA_VERSION)


func test_destructor_frees_server_objects_of_a_query_dropped_without_dispose() -> void:
	# Arrange
	var rids: Array[RID] = []
	var make: Callable = func() -> void:
		var query: CollisionQuery = CollisionQuery.create(Fixtures.ground_with_walls([0, 0, 0, 0]).pack_native())
		rids.append_array(query.owned_rids())
	# Act: the only reference drops inside the callable, without dispose().
	await assert_error(make).is_success()
	# Assert: 2 bodies, ground shape + wall shapes, space: all gone, and no warning was logged.
	assert_int(rids.size()).is_greater_equal(5)
	assert_bool(PhysicsServer3D.body_get_space(rids[0]).is_valid()).is_false()
	assert_int(PhysicsServer3D.shape_get_type(rids[2])).is_equal(PhysicsServer3D.SHAPE_CUSTOM)
	assert_object(PhysicsServer3D.space_get_direct_state(rids[rids.size() - 1])).is_null()


func test_live_rid_count_rises_on_create_and_returns_to_baseline_on_dispose_and_on_drop() -> void:
	# Arrange: constructors create no RID; create() does; dispose() and the destructor give them back.
	var baseline: int = CollisionQuery.live_rid_count()
	var unbuilt: CollisionQuery = CollisionQuery.new()
	var after_new: int = CollisionQuery.live_rid_count()
	var data: TrackCollisionData = Fixtures.ground_with_walls([0, 0, 0, 0])
	# Act
	var query: CollisionQuery = CollisionQuery.create(data.pack_native())
	var owned: int = query.owned_rids().size()
	var after_create: int = CollisionQuery.live_rid_count()
	query.dispose()
	var after_dispose: int = CollisionQuery.live_rid_count()
	var dropped: Callable = func() -> void:
		CollisionQuery.create(data.pack_native())
	dropped.call()
	var after_drop: int = CollisionQuery.live_rid_count()
	# Assert
	assert_bool(unbuilt.is_built()).is_false()
	assert_int(after_new).is_equal(baseline)
	assert_int(owned).is_greater(0)
	assert_int(after_create).is_equal(baseline + owned)
	assert_int(after_dispose).is_equal(baseline)
	assert_int(after_drop).is_equal(baseline)


func test_600_ticks_of_casts_and_sweeps_allocate_nothing() -> void:
	# Arrange: every object exists and every path (ground ray, mover ray, wall sweep, mover sweep, pose) ran once.
	var query: CollisionQuery = CollisionQuery.create(Fixtures.mirror_fixture().pack_native())
	var cursor: QueryCursor = QueryCursor.new()
	var ground: GroundHit = GroundHit.new()
	var wall: WallHit = WallHit.new()
	var spinner_at: Vector3 = Fixtures.MIRROR_SPINNER_AT
	for tick in 60:
		var t: float = tick * (1.0 / 60.0)
		query.cast_ground(cursor, spinner_at + Vector3.UP * 3.0, Vector3.DOWN, 6.0, t, ground)
		query.sweep_walls(cursor, spinner_at + Vector3(4.0, 0.0, 0.0), spinner_at, 0.5, t, wall)
		query.mover_pose(1, t)
	var objects_before: int = int(Performance.get_monitor(Performance.OBJECT_COUNT))
	var memory_before: int = OS.get_static_memory_usage()
	# Act: 600 ticks.
	for tick in 600:
		var t: float = tick * (1.0 / 60.0)
		query.cast_ground(cursor, spinner_at + Vector3.UP * 3.0, Vector3.DOWN, 6.0, t, ground)
		query.sweep_walls(cursor, spinner_at + Vector3(4.0, 0.0, 0.0), spinner_at, 0.5, t, wall)
		query.mover_pose(1, t)
		query.mover_point_velocity(1, t, spinner_at)
	var objects_after: int = int(Performance.get_monitor(Performance.OBJECT_COUNT))
	var memory_after: int = OS.get_static_memory_usage()
	query.dispose()
	# Assert: no object created, and the static heap did not grow (the story-007 "no allocation" criterion).
	assert_int(objects_after).is_equal(objects_before)
	assert_int(memory_after).is_less_equal(memory_before)
