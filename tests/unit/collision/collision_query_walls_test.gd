extends GdUnitTestSuite
## Core-rebuild story 004: CollisionQuery.sweep_walls against static walls (ADR-0002 "Queries per
## kart per tick" steps 1-4; movers are story 005). Fixture geometry is built in code
## (collision_fixtures.gd); no file I/O, no randomness, no time-dependent assertion. Walls face +X
## at x = 0 unless a test says otherwise; the sweep sphere has radius SWEEP_RADIUS, so it touches a
## wall when its centre is SWEEP_RADIUS in front of it.
##
## Story acceptance criteria (story order) -> GDD / ADR source -> tests:
##   Story AC 1  Wall attribute id          (Track Collision AC-6; ADR-0002 Validation Criteria)
##               test_sweep_into_rough_wall_returns_its_non_contiguous_id,
##               test_sweep_into_each_wall_shape_returns_that_shapes_wall_attr_id,
##               test_started_inside_rough_wall_returns_its_non_contiguous_id
##   Story AC 2  One-sided walls            (Track Collision AC-7)
##               test_sweep_from_front_face_hits_with_safe_fraction,
##               test_sweep_from_back_face_passes_through,
##               test_sweep_starting_overlapped_from_back_misses,
##               test_sweep_that_would_tunnel_through_wall_is_caught,
##               test_sweep_crossing_wall_from_shallow_overlap_is_caught_as_started_inside
##   Story AC 3  Touch                      (Track Collision AC-10)
##               test_move_ending_flush_head_on_is_touch_with_fraction_one,
##               test_move_ending_flush_obliquely_is_touch_with_fraction_one,
##               test_move_ending_just_short_of_wall_misses_and_leaves_hit_untouched,
##               test_move_ending_just_past_flush_is_blocking_hit_below_one
##   Story AC 4  Started inside             (Track Collision AC-11; ADR-0002 v5 amendment)
##               test_sweep_starting_inside_wall_returns_started_inside_and_overlap_contact,
##               test_sweep_starting_inside_wall_runs_no_cast,
##               test_sweep_starting_flush_reports_started_inside
##   Slide-loop invariant (ADR-0003 slide loop: the kart stops wall_skin short of a wall)
##               test_sweep_from_wall_skin_gap_misses_at_from_and_parallel_slide_misses,
##               test_sweep_into_wall_from_wall_skin_gap_returns_near_zero_fraction_not_started_inside
##   Implementation Notes / ADR-0002 Geometry layout (walls on their own layer)
##               test_sweep_at_floor_wall_corner_returns_wall_not_floor,
##               test_sweep_overlapping_ground_only_misses
##   Inner corner (ADR-0002: rest info returns one contact; probe_adr3_rest.txt E)
##               test_started_inside_inner_corner_returns_deeper_wall,
##               test_sweep_into_inner_corner_hits_wall_reached_first
##   Reuse and lifetime (ADR-0002 Reuse rules, Implementation Guidelines)
##               test_sweep_zero_motion_away_from_walls_misses,
##               test_sweep_radius_change_on_same_cursor_takes_effect,
##               test_sweeps_create_no_objects,
##               test_sweep_walls_after_dispose_asserts_in_debug_or_misses

const _GUARD = preload("res://tests/unit/native/native_test_guard.gd")
const Fixtures = preload("res://tests/unit/collision/collision_fixtures.gd")

## Simulation time passed to sweep_walls (no movers in these fixtures).
const T: float = 0.0
## Position / normal tolerance (m) of a rest contact on a flat fixture wall.
const HIT_TOLERANCE: float = 0.001
## Tolerance of a cast fraction (Jolt's safe and unsafe fractions differ by ~1/4096).
const FRACTION_TOLERANCE: float = 0.001
## Distance (m) in front of a wall the head-on sweeps start from.
const START_DISTANCE: float = 3.0
## Depth (m) a started-inside sphere overlaps a wall by.
const OVERLAP_DEPTH: float = 0.3
## Sentinel written into a WallHit to prove a miss leaves it untouched.
const SENTINEL_ATTR: int = 99
## Sentinel collider id (a mover-like id) written into a WallHit before a sweep.
const SENTINEL_COLLIDER_ID: int = 7
## Sentinel collider velocity written into a WallHit before a sweep.
const SENTINEL_VELOCITY: Vector3 = Vector3(1.0, 2.0, 3.0)
## The slide loop's gap (m) in front of a wall after a blocking hit (ADR-0003 wall_skin default).
const WALL_SKIN: float = 0.02
## Length (m) of the parallel slide along a wall in the wall_skin test.
const SLIDE_LENGTH: float = 2.0
## Sweeps per kind in the object-count check.
const OBJECT_CHECK_REPEATS: int = 250


# --- helpers ------------------------------------------------------------------------------------

func before() -> void:
	assert_str(_GUARD.problem()).is_empty()


## Id of wall [param wall_name] in the fixture wall registry.
func _wall_id(wall_name: StringName) -> int:
	return Fixtures.WALL_REGISTRY_IDS[Fixtures.WALL_REGISTRY_NAMES.find(wall_name)]


## A point at [param x] in front of the attr_walls plane, mid-height, in the middle of shape [param k].
func _at(x: float, k: int) -> Vector3:
	return Vector3(x, Fixtures.SWEEP_Y, Fixtures.wall_centre_z(k))


## A query over the attr_walls fixture (auto-disposed by the caller).
func _attr_query() -> CollisionQuery:
	return CollisionQuery.create(Fixtures.attr_walls(Fixtures.wall_registry()).pack_native())


## A WallHit holding sentinel values, to check a miss leaves it untouched.
func _sentinel_hit() -> WallHit:
	var hit: WallHit = WallHit.new()
	hit.wall_attr = SENTINEL_ATTR
	hit.fraction = 0.5
	hit.started_inside = true
	hit.point = Vector3.ONE
	hit.collider_id = SENTINEL_COLLIDER_ID
	hit.collider_velocity = SENTINEL_VELOCITY
	return hit


## Runs the bare engine cast on [param cursor]'s objects (what sweep_walls step 2 does), for
## control checks. Returns the cast's return value; the fractions are in cursor.cast_result.
func _raw_cast(query: CollisionQuery, cursor: QueryCursor, from: Vector3, to: Vector3) -> bool:
	var state: PhysicsDirectSpaceState3D = PhysicsServer3D.space_get_direct_state(query.space_rid())
	cursor.sphere.radius = Fixtures.SWEEP_RADIUS
	cursor.shape_params.collision_mask = CollisionQuery.WALL_LAYER
	cursor.shape_params.transform = Transform3D(Basis.IDENTITY, from)
	cursor.shape_params.motion = to - from
	var ok: bool = state.cast_motion_into(cursor.shape_params, cursor.cast_result)
	cursor.shape_params.motion = Vector3.ZERO
	return ok


## Asserts [param hit] is a static-wall contact on the attr_walls plane x = 0 at z [param z].
func _assert_static_contact_on_x_plane(hit: WallHit, z: float) -> void:
	assert_vector(hit.normal).is_equal_approx(Vector3.RIGHT, Vector3.ONE * HIT_TOLERANCE)
	assert_float(hit.point.x).is_equal_approx(0.0, HIT_TOLERANCE)
	assert_float(hit.point.y).is_equal_approx(Fixtures.SWEEP_Y, HIT_TOLERANCE)
	assert_float(hit.point.z).is_equal_approx(z, HIT_TOLERANCE)
	assert_int(hit.collider_id).is_equal(0)
	assert_vector(hit.collider_velocity).is_equal(Vector3.ZERO)


# --- Story AC 1: wall attribute id ---------------------------------------------------------------

func test_sweep_into_rough_wall_returns_its_non_contiguous_id() -> void:
	# Arrange: rough is wall shape 0, registry index 1, id 17.
	var query: CollisionQuery = _attr_query()
	var cursor: QueryCursor = QueryCursor.new()
	var hit: WallHit = WallHit.new()
	var k: int = Fixtures.WALL_SHAPE_ORDER.find(&"rough")
	# Act
	var did_hit: bool = query.sweep_walls(cursor, _at(START_DISTANCE, k), _at(-START_DISTANCE, k), Fixtures.SWEEP_RADIUS, T, hit)
	query.dispose()
	# Assert: the id, not the shape index nor the registry index.
	assert_bool(did_hit).is_true()
	assert_int(hit.wall_attr).is_equal(_wall_id(&"rough"))
	assert_int(hit.wall_attr).is_not_equal(k)
	assert_int(hit.wall_attr).is_not_equal(Fixtures.WALL_REGISTRY_NAMES.find(&"rough"))


func test_sweep_into_each_wall_shape_returns_that_shapes_wall_attr_id() -> void:
	# Arrange
	var data: TrackCollisionData = Fixtures.attr_walls(Fixtures.wall_registry())
	var query: CollisionQuery = CollisionQuery.create(data.pack_native())
	var cursor: QueryCursor = QueryCursor.new()
	var hit: WallHit = WallHit.new()
	var got: Array[int] = []
	# Act
	for k in Fixtures.WALL_SHAPE_ORDER.size():
		hit.clear()
		if query.sweep_walls(cursor, _at(START_DISTANCE, k), _at(-START_DISTANCE, k), Fixtures.SWEEP_RADIUS, T, hit):
			got.append(hit.wall_attr)
	query.dispose()
	# Assert: wall_attr_ids[collider_shape] for every shape, in shape order.
	var expected: Array[int] = []
	for k in Fixtures.WALL_SHAPE_ORDER.size():
		expected.append(_wall_id(Fixtures.WALL_SHAPE_ORDER[k]))
	assert_array(got).is_equal(expected)
	assert_array(got).is_equal(Array(data.wall_attr_ids))


func test_started_inside_rough_wall_returns_its_non_contiguous_id() -> void:
	# Arrange
	var query: CollisionQuery = _attr_query()
	var cursor: QueryCursor = QueryCursor.new()
	var hit: WallHit = WallHit.new()
	var k: int = Fixtures.WALL_SHAPE_ORDER.find(&"rough")
	var from: Vector3 = _at(Fixtures.SWEEP_RADIUS - OVERLAP_DEPTH, k)
	# Act
	var did_hit: bool = query.sweep_walls(cursor, from, from + Vector3.FORWARD, Fixtures.SWEEP_RADIUS, T, hit)
	query.dispose()
	# Assert
	assert_bool(did_hit).is_true()
	assert_bool(hit.started_inside).is_true()
	assert_int(hit.wall_attr).is_equal(_wall_id(&"rough"))


# --- Story AC 2: one-sided walls ------------------------------------------------------------------

func test_sweep_from_front_face_hits_with_safe_fraction() -> void:
	# Arrange: from x = 3 to x = -3 (6 m); contact when the centre reaches x = R = 1, i.e. 2/6.
	var query: CollisionQuery = _attr_query()
	var cursor: QueryCursor = QueryCursor.new()
	var hit: WallHit = WallHit.new()
	var from: Vector3 = _at(START_DISTANCE, 0)
	var to: Vector3 = _at(-START_DISTANCE, 0)
	var expected_fraction: float = (START_DISTANCE - Fixtures.SWEEP_RADIUS) / (2.0 * START_DISTANCE)
	# Act
	var did_hit: bool = query.sweep_walls(cursor, from, to, Fixtures.SWEEP_RADIUS, T, hit)
	query.dispose()
	# Assert
	assert_bool(did_hit).is_true()
	assert_bool(hit.started_inside).is_false()
	assert_float(hit.fraction).is_equal_approx(expected_fraction, FRACTION_TOLERANCE)
	# The safe fraction never passes the true first contact.
	assert_float(hit.fraction).is_less_equal(expected_fraction)
	_assert_static_contact_on_x_plane(hit, Fixtures.wall_centre_z(0))


func test_sweep_from_back_face_passes_through() -> void:
	# Arrange: the same line, the other way: from behind the wall to in front of it.
	var query: CollisionQuery = _attr_query()
	var cursor: QueryCursor = QueryCursor.new()
	var hit: WallHit = _sentinel_hit()
	# Act
	var did_hit: bool = query.sweep_walls(cursor, _at(-START_DISTANCE, 0), _at(START_DISTANCE, 0), Fixtures.SWEEP_RADIUS, T, hit)
	query.dispose()
	# Assert
	assert_bool(did_hit).is_false()
	assert_int(hit.wall_attr).is_equal(SENTINEL_ATTR)


func test_sweep_starting_overlapped_from_back_misses() -> void:
	# Arrange: the centre 0.3 m behind the wall (the sphere crosses it), moving further back.
	var query: CollisionQuery = _attr_query()
	var cursor: QueryCursor = QueryCursor.new()
	var hit: WallHit = _sentinel_hit()
	# Act
	var did_hit: bool = query.sweep_walls(cursor, _at(-OVERLAP_DEPTH, 0), _at(-START_DISTANCE, 0), Fixtures.SWEEP_RADIUS, T, hit)
	query.dispose()
	# Assert: a back-side overlap is not a wall contact (one-sided, backface_collision = false).
	assert_bool(did_hit).is_false()
	assert_int(hit.wall_attr).is_equal(SENTINEL_ATTR)


func test_sweep_that_would_tunnel_through_wall_is_caught() -> void:
	# Arrange: a move long enough to end fully behind the wall (no overlap at from or at to), so a
	# rest check at `to` alone would miss it.
	var query: CollisionQuery = _attr_query()
	var cursor: QueryCursor = QueryCursor.new()
	var hit: WallHit = WallHit.new()
	var far: float = START_DISTANCE * 10.0
	var from: Vector3 = _at(START_DISTANCE, 0)
	var to: Vector3 = _at(-far, 0)
	# Act
	var did_hit: bool = query.sweep_walls(cursor, from, to, Fixtures.SWEEP_RADIUS, T, hit)
	query.dispose()
	# Assert
	assert_bool(did_hit).is_true()
	assert_bool(hit.started_inside).is_false()
	assert_float(hit.fraction).is_equal_approx((START_DISTANCE - Fixtures.SWEEP_RADIUS) / (START_DISTANCE + far), FRACTION_TOLERANCE)
	_assert_static_contact_on_x_plane(hit, Fixtures.wall_centre_z(0))


func test_sweep_crossing_wall_from_shallow_overlap_is_caught_as_started_inside() -> void:
	# Arrange: the centre starts 0.3 m in front of the plane (overlap depth 0.7) and moves 1.3 m
	# through it. The engine cast alone is blind from an overlapped start (control below).
	var query: CollisionQuery = _attr_query()
	var cursor: QueryCursor = QueryCursor.new()
	var hit: WallHit = WallHit.new()
	var from: Vector3 = _at(OVERLAP_DEPTH, 0)
	var to: Vector3 = _at(-Fixtures.SWEEP_RADIUS, 0)
	var control_cast_hit: bool = _raw_cast(query, cursor, from, to)
	# Act
	var did_hit: bool = query.sweep_walls(cursor, from, to, Fixtures.SWEEP_RADIUS, T, hit)
	query.dispose()
	# Assert: the cast would have let it through; the rest check at from catches it.
	assert_bool(control_cast_hit).is_false()
	assert_bool(did_hit).is_true()
	assert_bool(hit.started_inside).is_true()
	assert_float(hit.fraction).is_equal(0.0)
	_assert_static_contact_on_x_plane(hit, Fixtures.wall_centre_z(0))


# --- Story AC 3: touch ------------------------------------------------------------------------------

func test_move_ending_flush_head_on_is_touch_with_fraction_one() -> void:
	# Arrange: ends with the centre exactly R in front of the wall. Jolt reports this cast as a hit
	# with unsafe fraction 1 (probe_walls.txt): the first contact is at the end of the move.
	var query: CollisionQuery = _attr_query()
	var cursor: QueryCursor = QueryCursor.new()
	var hit: WallHit = WallHit.new()
	# Act
	var did_hit: bool = query.sweep_walls(cursor, _at(START_DISTANCE, 0), _at(Fixtures.SWEEP_RADIUS, 0), Fixtures.SWEEP_RADIUS, T, hit)
	query.dispose()
	# Assert
	assert_bool(did_hit).is_true()
	assert_float(hit.fraction).is_equal(1.0)
	assert_bool(hit.started_inside).is_false()
	assert_int(hit.wall_attr).is_equal(_wall_id(Fixtures.WALL_SHAPE_ORDER[0]))
	_assert_static_contact_on_x_plane(hit, Fixtures.wall_centre_z(0))


func test_move_ending_flush_obliquely_is_touch_with_fraction_one() -> void:
	# Arrange: approach at an angle (2 m in, 4 m along) and end flush.
	var query: CollisionQuery = _attr_query()
	var cursor: QueryCursor = QueryCursor.new()
	var hit: WallHit = WallHit.new()
	var z: float = Fixtures.wall_centre_z(1)
	var along: float = 2.0
	var from: Vector3 = Vector3(START_DISTANCE, Fixtures.SWEEP_Y, z - along)
	var to: Vector3 = Vector3(Fixtures.SWEEP_RADIUS, Fixtures.SWEEP_Y, z + along)
	# Act
	var did_hit: bool = query.sweep_walls(cursor, from, to, Fixtures.SWEEP_RADIUS, T, hit)
	query.dispose()
	# Assert
	assert_bool(did_hit).is_true()
	assert_float(hit.fraction).is_equal(1.0)
	assert_bool(hit.started_inside).is_false()
	assert_int(hit.wall_attr).is_equal(_wall_id(Fixtures.WALL_SHAPE_ORDER[1]))
	_assert_static_contact_on_x_plane(hit, z + along)


func test_move_ending_just_short_of_wall_misses_and_leaves_hit_untouched() -> void:
	# Arrange: ends 1 mm short of flush.
	var query: CollisionQuery = _attr_query()
	var cursor: QueryCursor = QueryCursor.new()
	var hit: WallHit = _sentinel_hit()
	var gap: float = 0.001
	# Act
	var did_hit: bool = query.sweep_walls(cursor, _at(START_DISTANCE, 0), _at(Fixtures.SWEEP_RADIUS + gap, 0), Fixtures.SWEEP_RADIUS, T, hit)
	query.dispose()
	# Assert: a miss writes nothing.
	assert_bool(did_hit).is_false()
	assert_int(hit.wall_attr).is_equal(SENTINEL_ATTR)
	assert_float(hit.fraction).is_equal(0.5)
	assert_bool(hit.started_inside).is_true()
	assert_vector(hit.point).is_equal(Vector3.ONE)


func test_move_ending_just_past_flush_is_blocking_hit_below_one() -> void:
	# Arrange: ends 1 cm into the wall: the first contact is inside the move, not a touch.
	var query: CollisionQuery = _attr_query()
	var cursor: QueryCursor = QueryCursor.new()
	var hit: WallHit = WallHit.new()
	var into: float = 0.01
	# Act
	var did_hit: bool = query.sweep_walls(cursor, _at(START_DISTANCE, 0), _at(Fixtures.SWEEP_RADIUS - into, 0), Fixtures.SWEEP_RADIUS, T, hit)
	query.dispose()
	# Assert
	assert_bool(did_hit).is_true()
	assert_bool(hit.started_inside).is_false()
	assert_float(hit.fraction).is_less(1.0)
	var length: float = START_DISTANCE - Fixtures.SWEEP_RADIUS + into
	assert_float(hit.fraction).is_equal_approx((START_DISTANCE - Fixtures.SWEEP_RADIUS) / length, FRACTION_TOLERANCE)


# --- Story AC 4: started inside ---------------------------------------------------------------------

func test_sweep_starting_inside_wall_returns_started_inside_and_overlap_contact() -> void:
	# Arrange: wall shape 1 (stone), overlapped by 0.3 m, moving into it. The hit is pre-filled
	# with a non-zero collider id and velocity, so the static values must be written.
	var query: CollisionQuery = _attr_query()
	var cursor: QueryCursor = QueryCursor.new()
	var hit: WallHit = _sentinel_hit()
	var from: Vector3 = _at(Fixtures.SWEEP_RADIUS - OVERLAP_DEPTH, 1)
	# Act
	var did_hit: bool = query.sweep_walls(cursor, from, _at(-START_DISTANCE, 1), Fixtures.SWEEP_RADIUS, T, hit)
	query.dispose()
	# Assert: fraction 0, and point, normal, wall_attr, collider_id from the overlap.
	assert_bool(did_hit).is_true()
	assert_bool(hit.started_inside).is_true()
	assert_float(hit.fraction).is_equal(0.0)
	assert_int(hit.wall_attr).is_equal(_wall_id(Fixtures.WALL_SHAPE_ORDER[1]))
	assert_int(hit.collider_id).is_equal(0)
	assert_vector(hit.collider_velocity).is_equal(Vector3.ZERO)
	_assert_static_contact_on_x_plane(hit, Fixtures.wall_centre_z(1))
	# The overlap depth follows from the contact: R - (c - p).n.
	assert_float(Fixtures.SWEEP_RADIUS - (from - hit.point).dot(hit.normal)).is_equal_approx(OVERLAP_DEPTH, HIT_TOLERANCE)


func test_sweep_starting_inside_wall_runs_no_cast() -> void:
	# Arrange: every cast_motion_into writes the cursor's cast result (a clear cast writes 1.0), so
	# prime it with a known hit fraction, and check a cast on the started-inside motion would
	# overwrite it.
	var query: CollisionQuery = _attr_query()
	var cursor: QueryCursor = QueryCursor.new()
	var hit: WallHit = WallHit.new()
	var from: Vector3 = _at(Fixtures.SWEEP_RADIUS - OVERLAP_DEPTH, 0)
	var to: Vector3 = _at(START_DISTANCE, 0)
	_raw_cast(query, cursor, from, to)
	var control_fraction: float = cursor.cast_result.safe_fraction
	_raw_cast(query, cursor, _at(START_DISTANCE, 0), _at(-START_DISTANCE, 0))
	var primed: float = cursor.cast_result.safe_fraction
	# Act
	var did_hit: bool = query.sweep_walls(cursor, from, to, Fixtures.SWEEP_RADIUS, T, hit)
	var after: float = cursor.cast_result.safe_fraction
	query.dispose()
	# Assert: a cast would have changed the result; the sweep left it as primed.
	assert_bool(absf(control_fraction - primed) > FRACTION_TOLERANCE).is_true()
	assert_bool(did_hit).is_true()
	assert_bool(hit.started_inside).is_true()
	assert_float(after).is_equal(primed)


func test_sweep_starting_flush_reports_started_inside() -> void:
	# Arrange: the centre exactly R in front of the wall (a zero-depth contact), as a kart is after
	# a touch. The rest check at from is unconditional, so this is reported as an overlap; the
	# caller's push-out (ADR-0003 section 6, depth 0 + wall_skin) separates it.
	var query: CollisionQuery = _attr_query()
	var cursor: QueryCursor = QueryCursor.new()
	var hit: WallHit = WallHit.new()
	var from: Vector3 = _at(Fixtures.SWEEP_RADIUS, 0)
	# Act
	var did_hit: bool = query.sweep_walls(cursor, from, from + Vector3.FORWARD, Fixtures.SWEEP_RADIUS, T, hit)
	query.dispose()
	# Assert
	assert_bool(did_hit).is_true()
	assert_bool(hit.started_inside).is_true()
	assert_float(hit.fraction).is_equal(0.0)
	assert_float(Fixtures.SWEEP_RADIUS - (from - hit.point).dot(hit.normal)).is_equal_approx(0.0, HIT_TOLERANCE)


func test_sweep_from_wall_skin_gap_misses_at_from_and_parallel_slide_misses() -> void:
	# Arrange: where the slide loop leaves a kart after a blocking hit: wall_skin in front of the
	# wall. Neither standing there nor sliding parallel to the wall is a contact.
	var query: CollisionQuery = _attr_query()
	var cursor: QueryCursor = QueryCursor.new()
	var still: WallHit = _sentinel_hit()
	var slide: WallHit = _sentinel_hit()
	var from: Vector3 = _at(Fixtures.SWEEP_RADIUS + WALL_SKIN, 0)
	# Act
	var still_hit: bool = query.sweep_walls(cursor, from, from, Fixtures.SWEEP_RADIUS, T, still)
	var slide_hit: bool = query.sweep_walls(cursor, from, from + Vector3.BACK * SLIDE_LENGTH, Fixtures.SWEEP_RADIUS, T, slide)
	query.dispose()
	# Assert
	assert_bool(still_hit).is_false()
	assert_bool(slide_hit).is_false()
	assert_int(still.wall_attr).is_equal(SENTINEL_ATTR)
	assert_int(slide.wall_attr).is_equal(SENTINEL_ATTR)


func test_sweep_into_wall_from_wall_skin_gap_returns_near_zero_fraction_not_started_inside() -> void:
	# Arrange: from wall_skin in front of the wall, straight into it.
	var query: CollisionQuery = _attr_query()
	var cursor: QueryCursor = QueryCursor.new()
	var hit: WallHit = WallHit.new()
	var from: Vector3 = _at(Fixtures.SWEEP_RADIUS + WALL_SKIN, 0)
	var to: Vector3 = _at(-START_DISTANCE, 0)
	var length: float = Fixtures.SWEEP_RADIUS + WALL_SKIN + START_DISTANCE
	# Act
	var did_hit: bool = query.sweep_walls(cursor, from, to, Fixtures.SWEEP_RADIUS, T, hit)
	query.dispose()
	# Assert: a blocking hit at about wall_skin / length, not an overlap.
	assert_bool(did_hit).is_true()
	assert_bool(hit.started_inside).is_false()
	assert_float(hit.fraction).is_equal_approx(WALL_SKIN / length, FRACTION_TOLERANCE)
	assert_float(hit.fraction).is_less_equal(WALL_SKIN / length)
	_assert_static_contact_on_x_plane(hit, Fixtures.wall_centre_z(0))


# --- Walls on their own layer ------------------------------------------------------------------------

func test_sweep_at_floor_wall_corner_returns_wall_not_floor() -> void:
	# Arrange: the sphere overlaps the floor by 0.5 m all along the move (centre at y = 0.5) and
	# reaches the side wall. With a combined mask the floor would be the rest contact (probe T3).
	var query: CollisionQuery = CollisionQuery.create(Fixtures.ground_and_side_wall([0, 0, 0, 0]).pack_native())
	var cursor: QueryCursor = QueryCursor.new()
	var hit: WallHit = WallHit.new()
	var y: float = 0.5
	var wall_x: float = -Fixtures.QUADRANT_SIZE
	var from: Vector3 = Vector3(wall_x + START_DISTANCE, y, 0.0)
	var to: Vector3 = Vector3(wall_x - START_DISTANCE, y, 0.0)
	# Act
	var did_hit: bool = query.sweep_walls(cursor, from, to, Fixtures.SWEEP_RADIUS, T, hit)
	query.dispose()
	# Assert: no started_inside from the floor; the contact is the wall's.
	assert_bool(did_hit).is_true()
	assert_bool(hit.started_inside).is_false()
	assert_int(hit.wall_attr).is_equal(Fixtures.WALL_ATTR_IDS[0])
	assert_vector(hit.normal).is_equal_approx(Vector3.RIGHT, Vector3.ONE * HIT_TOLERANCE)
	assert_float(hit.point.x).is_equal_approx(wall_x, HIT_TOLERANCE)


func test_sweep_overlapping_ground_only_misses() -> void:
	# Arrange: ground, no walls; the sphere is half sunk in the ground.
	var query: CollisionQuery = CollisionQuery.create(Fixtures.quadrant_ground([0, 0, 0, 0]).pack_native())
	var cursor: QueryCursor = QueryCursor.new()
	var hit: WallHit = _sentinel_hit()
	var from: Vector3 = Vector3(-1.0, 0.5, 0.0)
	# Act
	var did_hit: bool = query.sweep_walls(cursor, from, from + Vector3.RIGHT * 2.0, Fixtures.SWEEP_RADIUS, T, hit)
	query.dispose()
	# Assert
	assert_bool(did_hit).is_false()
	assert_int(hit.wall_attr).is_equal(SENTINEL_ATTR)


# --- Inner corner ------------------------------------------------------------------------------------

func test_started_inside_inner_corner_returns_deeper_wall() -> void:
	# Arrange: overlapping both corner walls, once deeper into the x = 0 wall (rough), once deeper
	# into the z = 0 wall (stone). Depths 0.8 and 0.4 (probe_adr3_rest.txt E).
	var query: CollisionQuery = CollisionQuery.create(Fixtures.inner_corner(Fixtures.wall_registry()).pack_native())
	var cursor: QueryCursor = QueryCursor.new()
	var hit_x: WallHit = WallHit.new()
	var hit_z: WallHit = WallHit.new()
	var deep_x: Vector3 = Vector3(0.2, Fixtures.SWEEP_Y, 0.6)
	var deep_z: Vector3 = Vector3(0.6, Fixtures.SWEEP_Y, 0.2)
	# Act
	var did_x: bool = query.sweep_walls(cursor, deep_x, deep_x + Vector3.ONE, Fixtures.SWEEP_RADIUS, T, hit_x)
	var did_z: bool = query.sweep_walls(cursor, deep_z, deep_z + Vector3.ONE, Fixtures.SWEEP_RADIUS, T, hit_z)
	query.dispose()
	# Assert
	assert_bool(did_x).is_true()
	assert_bool(hit_x.started_inside).is_true()
	assert_int(hit_x.wall_attr).is_equal(_wall_id(&"rough"))
	assert_vector(hit_x.normal).is_equal_approx(Vector3.RIGHT, Vector3.ONE * HIT_TOLERANCE)
	assert_vector(hit_x.point).is_equal_approx(Vector3(0.0, Fixtures.SWEEP_Y, 0.6), Vector3.ONE * HIT_TOLERANCE)
	assert_bool(did_z).is_true()
	assert_bool(hit_z.started_inside).is_true()
	assert_int(hit_z.wall_attr).is_equal(_wall_id(&"stone"))
	assert_vector(hit_z.normal).is_equal_approx(Vector3.BACK, Vector3.ONE * HIT_TOLERANCE)
	assert_vector(hit_z.point).is_equal_approx(Vector3(0.6, Fixtures.SWEEP_Y, 0.0), Vector3.ONE * HIT_TOLERANCE)


func test_sweep_into_inner_corner_hits_wall_reached_first() -> void:
	# Arrange: two diagonal moves into the corner. Move A reaches x = R at fraction 0.75 while z is
	# still 1.5 (rough wall first); move B reaches z = R at fraction 0.75 while x is 2.25 (stone).
	var query: CollisionQuery = CollisionQuery.create(Fixtures.inner_corner(Fixtures.wall_registry()).pack_native())
	var cursor: QueryCursor = QueryCursor.new()
	var hit_a: WallHit = WallHit.new()
	var hit_b: WallHit = WallHit.new()
	var y: float = Fixtures.SWEEP_Y
	var expected_fraction: float = 0.75
	# Act
	var did_a: bool = query.sweep_walls(cursor, Vector3(4.0, y, 3.0), Vector3(0.0, y, 1.0), Fixtures.SWEEP_RADIUS, T, hit_a)
	var did_b: bool = query.sweep_walls(cursor, Vector3(3.0, y, 4.0), Vector3(2.0, y, 0.0), Fixtures.SWEEP_RADIUS, T, hit_b)
	query.dispose()
	# Assert
	assert_bool(did_a).is_true()
	assert_bool(hit_a.started_inside).is_false()
	assert_int(hit_a.wall_attr).is_equal(_wall_id(&"rough"))
	assert_vector(hit_a.normal).is_equal_approx(Vector3.RIGHT, Vector3.ONE * HIT_TOLERANCE)
	assert_float(hit_a.fraction).is_equal_approx(expected_fraction, FRACTION_TOLERANCE)
	assert_bool(did_b).is_true()
	assert_bool(hit_b.started_inside).is_false()
	assert_int(hit_b.wall_attr).is_equal(_wall_id(&"stone"))
	assert_vector(hit_b.normal).is_equal_approx(Vector3.BACK, Vector3.ONE * HIT_TOLERANCE)
	assert_float(hit_b.fraction).is_equal_approx(expected_fraction, FRACTION_TOLERANCE)


# --- Reuse and lifetime ------------------------------------------------------------------------------

func test_sweep_zero_motion_away_from_walls_misses() -> void:
	# Arrange
	var query: CollisionQuery = _attr_query()
	var cursor: QueryCursor = QueryCursor.new()
	var hit: WallHit = _sentinel_hit()
	var at: Vector3 = _at(START_DISTANCE, 0)
	# Act
	var did_hit: bool = query.sweep_walls(cursor, at, at, Fixtures.SWEEP_RADIUS, T, hit)
	query.dispose()
	# Assert
	assert_bool(did_hit).is_false()
	assert_int(hit.wall_attr).is_equal(SENTINEL_ATTR)


func test_sweep_radius_change_on_same_cursor_takes_effect() -> void:
	# Arrange: a move ending with the centre 0.9 m in front of the wall: inside radius 1.0, clear
	# of radius 0.5.
	var query: CollisionQuery = _attr_query()
	var cursor: QueryCursor = QueryCursor.new()
	var hit: WallHit = WallHit.new()
	var small_radius: float = 0.5
	var from: Vector3 = _at(START_DISTANCE, 0)
	var to: Vector3 = _at(0.9, 0)
	var sphere_before: SphereShape3D = cursor.sphere
	# Act
	var big_1: bool = query.sweep_walls(cursor, from, to, Fixtures.SWEEP_RADIUS, T, hit)
	var small: bool = query.sweep_walls(cursor, from, to, small_radius, T, hit)
	var radius_after_small: float = cursor.sphere.radius
	var big_2: bool = query.sweep_walls(cursor, from, to, Fixtures.SWEEP_RADIUS, T, hit)
	query.dispose()
	# Assert: the same sphere object, resized each time.
	assert_bool(big_1).is_true()
	assert_bool(small).is_false()
	assert_float(radius_after_small).is_equal(small_radius)
	assert_bool(big_2).is_true()
	assert_object(cursor.sphere).is_same(sphere_before)
	assert_object(cursor.shape_params.shape).is_same(sphere_before)


func test_sweeps_create_no_objects() -> void:
	# Arrange: query, cursor and hit exist before the baseline; one warm-up sweep of each kind.
	var query: CollisionQuery = _attr_query()
	var cursor: QueryCursor = QueryCursor.new()
	var hit: WallHit = WallHit.new()
	var blocked_from: Vector3 = _at(START_DISTANCE, 0)
	var blocked_to: Vector3 = _at(-START_DISTANCE, 0)
	var inside: Vector3 = _at(Fixtures.SWEEP_RADIUS - OVERLAP_DEPTH, 1)
	var touch_to: Vector3 = _at(Fixtures.SWEEP_RADIUS, 2)
	var clear_to: Vector3 = _at(START_DISTANCE * 2.0, 2)
	var kinds: Array[Vector3] = [blocked_from, blocked_to, inside, blocked_to, _at(START_DISTANCE, 2), touch_to, _at(START_DISTANCE, 2), clear_to]
	for i in range(0, kinds.size(), 2):
		query.sweep_walls(cursor, kinds[i], kinds[i + 1], Fixtures.SWEEP_RADIUS, T, hit)
	var baseline: int = int(Performance.get_monitor(Performance.OBJECT_COUNT))
	# Act
	for n in OBJECT_CHECK_REPEATS:
		query.sweep_walls(cursor, blocked_from, blocked_to, Fixtures.SWEEP_RADIUS, T, hit)
		query.sweep_walls(cursor, inside, blocked_to, Fixtures.SWEEP_RADIUS, T, hit)
		query.sweep_walls(cursor, _at(START_DISTANCE, 2), touch_to, Fixtures.SWEEP_RADIUS, T, hit)
		query.sweep_walls(cursor, _at(START_DISTANCE, 2), clear_to, Fixtures.SWEEP_RADIUS, T, hit)
	var after: int = int(Performance.get_monitor(Performance.OBJECT_COUNT))
	query.dispose()
	# Assert
	assert_int(after).is_equal(baseline)


func test_sweep_walls_after_dispose_refuses_and_misses() -> void:
	# Arrange
	var query: CollisionQuery = _attr_query()
	query.dispose()
	var cursor: QueryCursor = QueryCursor.new()
	var hit: WallHit = _sentinel_hit()
	var from: Vector3 = _at(START_DISTANCE, 0)
	var to: Vector3 = _at(-START_DISTANCE, 0)
	var out: Array = []
	# Act / Assert: a disposed query is unbuilt: the built guard refuses, in debug and release alike.
	await assert_error(func() -> void: out.append(query.sweep_walls(cursor, from, to, Fixtures.SWEEP_RADIUS, T, hit))).is_push_error(
			"Condition \"!built\" is true. Returning: false")
	assert_bool(out[0]).is_false()
	assert_int(hit.wall_attr).is_equal(SENTINEL_ATTR)
