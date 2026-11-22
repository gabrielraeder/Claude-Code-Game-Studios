extends GdUnitTestSuite
## Core-rebuild story 003: TrackCollisionData builds a CollisionQuery (private Jolt space, server
## shapes and bodies), cast_ground reports stable surface ids from face_index, the probe majority
## with the C12 tie rule, and dispose(). Fixture geometry is built in code (collision_fixtures.gd);
## no file I/O, no randomness, no time-dependent assertion.
##
## Story acceptance criteria (story order) -> GDD / ADR source -> tests:
##   Story AC 1  Jolt pinned, query built   (ADR-0002 Summary)
##               test_project_pins_jolt_face_index_and_main_thread_physics,
##               test_track_collision_data_is_tool_resource_with_schema_fields,
##               test_query_owns_inactive_private_space_with_ground_and_wall_bodies,
##               test_query_shapes_are_one_sided_concave,
##               test_query_from_broken_layout_push_errors_and_misses,
##               test_query_from_null_data_push_errors_and_misses
##   Story AC 2  Ground surface ids         (Track Collision GDD AC-1; ADR-0002 Validation Criteria)
##               test_cast_ground_on_each_kind_returns_registered_id_not_index,
##               test_cast_ground_after_degenerate_triangles_keeps_face_ids_aligned (GDD E-18),
##               test_cast_ground_from_below_misses_back_face,
##               test_cast_ground_ignores_wall_layer_and_hits_ground,
##               test_cast_ground_miss_returns_false_and_leaves_hit_untouched
##   Story AC 3  Probe majority, C12 ties   (Track Collision GDD AC-4, 4.1, E-2; C12 decided
##               2026-11-22: nearest centre of mass on the up plane, distance ties to the lowest
##               probe index)
##               test_probes_road_grass_grass_grass_give_grass,
##               test_probes_two_two_tie_gives_kind_nearest_centre_of_mass,
##               test_bike_one_one_tie_gives_kind_nearest_centre_of_mass,
##               test_probes_equidistant_tie_gives_lowest_index_probe_kind,
##               test_ties_resolve_identically_over_1000_repeats,
##               test_majority_surface_without_hits_keeps_previous_id,
##               test_majority_surface_majority_beats_nearest_probe,
##               test_majority_surface_measures_distance_on_up_plane,
##               test_majority_surface_equal_distance_goes_to_lowest_index
##   Story AC 4  Dispose                    (ADR-0002 Validation Criteria)
##               test_dispose_frees_every_rid_bodies_then_shapes_then_space,
##               test_dispose_returns_object_count_to_baseline,
##               test_dispose_twice_is_safe,
##               test_cast_ground_after_dispose_asserts_in_debug_or_misses,
##               test_query_dropped_without_dispose_warns_and_frees_rids
##
## The freed-RID checks call PhysicsServer3D getters on freed RIDs. Jolt answers them with its
## "not found" value (RID(), SHAPE_CUSTOM, null) and prints one engine "Parameter ... is null"
## ERROR line each: those lines in the log are expected.

const Fixtures = preload("res://tests/unit/collision/collision_fixtures.gd")

## Repeats of the tie cases (Track Collision AC-4).
const TIE_REPEATS: int = 1000
## Position tolerance (m) of a ray hit on flat fixture ground.
const HIT_TOLERANCE: float = 0.001
## Simulation time passed to cast_ground (no movers in these fixtures).
const T: float = 0.0
## Previous surface id used where it must not matter.
const PREVIOUS_ID: int = 99


# --- helpers ------------------------------------------------------------------------------------

## Registry id of [param kind] in the fixture registry.
func _id(kind: StringName) -> int:
	return Fixtures.REGISTRY_IDS[Fixtures.REGISTRY_KINDS.find(kind)]


## Casts [param probes] straight down onto [param query] and returns the majority surface for a
## kart whose centre of mass is [param com] (up = +Y). Uses one cursor and preallocated buffers, as
## a kart would: [param ids] and [param points] must hold at least probes.size() entries.
func _probe_majority(query: CollisionQuery, cursor: QueryCursor, hit: GroundHit, probes: Array[Vector3],
		com: Vector3, ids: PackedInt32Array, points: PackedVector3Array) -> int:
	var n_hit: int = 0
	for k in probes.size():
		var origin: Vector3 = probes[k] + Vector3.UP * Fixtures.CAST_HEIGHT
		if query.cast_ground(cursor, origin, Vector3.DOWN, Fixtures.CAST_LENGTH, T, hit):
			ids[n_hit] = hit.surface_id
			points[n_hit] = hit.point
			n_hit += 1
	return CollisionQuery.majority_surface(ids, points, n_hit, com, Vector3.UP, PREVIOUS_ID)


## Majority of [param ids] for probes at the cart PROBE_POINTS (all hit), centre of mass [param com].
func _cart_majority(ids: PackedInt32Array, com: Vector3) -> int:
	return CollisionQuery.majority_surface(ids, PackedVector3Array(Fixtures.PROBE_POINTS), ids.size(),
			com, Vector3.UP, PREVIOUS_ID)


## Four zeroed contact points (a preallocated cart buffer).
func _pts4() -> PackedVector3Array:
	return PackedVector3Array([Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO])


## Builds a query from [param data], records its RIDs into [param rids] and drops the only
## reference without dispose() (exercises the NOTIFICATION_PREDELETE fallback).
func _drop_query_without_dispose(data: TrackCollisionData, rids: Array[RID]) -> void:
	var query: CollisionQuery = CollisionQuery.new(data)
	rids.append_array(query.owned_rids())
	query = null


# --- Story AC 1: Jolt pinned and query built ------------------------------------------------------------

func test_project_pins_jolt_face_index_and_main_thread_physics() -> void:
	# Arrange / Act
	var engine_name: String = ProjectSettings.get_setting("physics/3d/physics_engine", "")
	var face_index: bool = ProjectSettings.get_setting("physics/jolt_physics_3d/queries/enable_ray_cast_face_index", false)
	var separate_thread: bool = ProjectSettings.get_setting("physics/3d/run_on_separate_thread", true)
	# Assert
	assert_str(engine_name).is_equal("Jolt Physics")
	assert_bool(face_index).is_true()
	assert_bool(separate_thread).is_false()


func test_track_collision_data_is_tool_resource_with_schema_fields() -> void:
	# Arrange
	var data: TrackCollisionData = TrackCollisionData.new()
	# A valid mover: layout_error() checks movers from story 005.
	var mover: MoverDef = Fixtures.still_box(1, Vector3.ZERO, Vector3.ONE)
	# Act
	data.movers.append(mover)
	var names: Array[String] = []
	for p in data.get_property_list():
		names.append(p["name"])
	# Assert
	assert_bool((data.get_script() as Script).is_tool()).is_true()
	assert_bool((mover.get_script() as Script).is_tool()).is_true()
	assert_int(TrackCollisionData.FORMAT_VERSION).is_equal(1)
	assert_array(names).contains(["ground_faces", "surface_of_face", "wall_faces", "wall_attr_ids",
			"movers", "probe_point", "probe_surface_id"])
	assert_int(data.movers.size()).is_equal(1)
	assert_str(data.layout_error()).is_empty()


func test_query_owns_inactive_private_space_with_ground_and_wall_bodies() -> void:
	# Arrange
	var data: TrackCollisionData = Fixtures.ground_with_walls([0, 0, 0, 0])
	# Act
	var query: CollisionQuery = CollisionQuery.new(data)
	var space: RID = query.space_rid()
	var ground: RID = query.ground_body_rid()
	var walls: RID = query.wall_body_rid()
	# Assert
	assert_bool(space.is_valid()).is_true()
	assert_bool(PhysicsServer3D.space_is_active(space)).is_false()
	for body: RID in [ground, walls]:
		assert_bool(PhysicsServer3D.body_get_space(body) == space).is_true()
		assert_int(PhysicsServer3D.body_get_mode(body)).is_equal(PhysicsServer3D.BODY_MODE_STATIC)
		assert_int(PhysicsServer3D.body_get_collision_mask(body)).is_equal(0)
	assert_int(PhysicsServer3D.body_get_collision_layer(ground)).is_equal(CollisionQuery.GROUND_LAYER)
	assert_int(PhysicsServer3D.body_get_collision_layer(walls)).is_equal(CollisionQuery.WALL_LAYER)
	assert_int(PhysicsServer3D.body_get_shape_count(ground)).is_equal(1)
	assert_int(PhysicsServer3D.body_get_shape_count(walls)).is_equal(data.wall_faces.size())
	# 2 bodies + 1 ground shape + one shape per wall attribute + the space.
	assert_int(query.owned_rids().size()).is_equal(2 + 1 + data.wall_faces.size() + 1)
	query.dispose()


func test_query_shapes_are_one_sided_concave() -> void:
	# Arrange
	var data: TrackCollisionData = Fixtures.ground_with_walls([0, 0, 0, 0])
	var query: CollisionQuery = CollisionQuery.new(data)
	var rids: Array[RID] = query.owned_rids()
	# Act: the shapes sit between the 2 bodies and the space.
	var shapes: Array[RID] = rids.slice(2, rids.size() - 1)
	# Assert
	assert_int(shapes.size()).is_equal(1 + data.wall_faces.size())
	for shape in shapes:
		assert_int(PhysicsServer3D.shape_get_type(shape)).is_equal(PhysicsServer3D.SHAPE_CONCAVE_POLYGON)
		var shape_data: Dictionary = PhysicsServer3D.shape_get_data(shape)
		assert_bool(shape_data.get("backface_collision", true)).is_false()
	query.dispose()


func test_query_from_broken_layout_push_errors_and_misses() -> void:
	# Arrange: 8 ground triangles but only 7 surface ids.
	var data: TrackCollisionData = Fixtures.quadrant_ground([0, 0, 0, 0])
	data.surface_of_face.resize(data.surface_of_face.size() - 1)
	var out: Array[CollisionQuery] = []
	# Act / Assert
	await assert_error(func() -> void: out.append(CollisionQuery.new(data))).is_push_error(
			"CollisionQuery: surface_of_face has 7 entries for 8 ground triangles; the query has no geometry")
	var query: CollisionQuery = out[0]
	var hit: GroundHit = GroundHit.new()
	assert_bool(query.cast_ground(QueryCursor.new(), Vector3.UP, Vector3.DOWN, Fixtures.CAST_LENGTH, T, hit)).is_false()
	assert_bool(query.ground_body_rid().is_valid()).is_false()
	assert_int(query.owned_rids().size()).is_equal(1)  # the space only
	query.dispose()


func test_query_from_null_data_push_errors_and_misses() -> void:
	# Arrange
	var out: Array[CollisionQuery] = []
	# Act / Assert
	await assert_error(func() -> void: out.append(CollisionQuery.new(null))).is_push_error(
			"CollisionQuery: data is null; the query has no geometry")
	var query: CollisionQuery = out[0]
	assert_bool(query.cast_ground(QueryCursor.new(), Vector3.UP, Vector3.DOWN, Fixtures.CAST_LENGTH, T, GroundHit.new())).is_false()
	query.dispose()


# --- Story AC 2 (GDD AC-1): ground surface ids ----------------------------------------------------------------------

func test_cast_ground_on_each_kind_returns_registered_id_not_index() -> void:
	# Arrange
	var surfaces: SurfaceSet = Fixtures.non_contiguous_registry()
	var query: CollisionQuery = CollisionQuery.new(Fixtures.one_triangle_per_kind(surfaces))
	var cursor: QueryCursor = QueryCursor.new()
	var hit: GroundHit = GroundHit.new()
	for face in surfaces.types.size():
		var expected: SurfaceType = surfaces.types[Fixtures.registry_index_of_face(face)]
		var origin: Vector3 = Fixtures.triangle_centroid(face) + Vector3.UP * Fixtures.CAST_HEIGHT
		# Act
		var did_hit: bool = query.cast_ground(cursor, origin, Vector3.DOWN, Fixtures.CAST_LENGTH, T, hit)
		# Assert
		assert_bool(did_hit).override_failure_message("face %d (%s) missed" % [face, expected.kind]).is_true()
		assert_int(hit.surface_id).override_failure_message("face %d (%s)" % [face, expected.kind]).is_equal(expected.id)
		# The fixture makes id, registry index and face index all differ, so neither index can pass.
		assert_int(hit.surface_id).is_not_equal(Fixtures.registry_index_of_face(face))
		assert_int(hit.surface_id).is_not_equal(face)
		assert_float(hit.point.y).is_equal_approx(0.0, HIT_TOLERANCE)
		assert_vector(hit.normal).is_equal_approx(Vector3.UP, Vector3.ONE * HIT_TOLERANCE)
		assert_int(hit.collider_id).is_equal(0)
		assert_vector(hit.collider_velocity).is_equal(Vector3.ZERO)
	query.dispose()


func test_cast_ground_after_degenerate_triangles_keeps_face_ids_aligned() -> void:
	# Arrange: four different kinds, with degenerate triangles at face index 0 and 5.
	var kinds: Array[int] = [_id(&"road"), _id(&"grass"), _id(&"mud"), _id(&"sand")]
	var data: TrackCollisionData = Fixtures.quadrant_ground_with_degenerates(kinds)
	var query: CollisionQuery = CollisionQuery.new(data)
	var cursor: QueryCursor = QueryCursor.new()
	var hit: GroundHit = GroundHit.new()
	for k in Fixtures.PROBE_POINTS.size():
		var origin: Vector3 = Fixtures.PROBE_POINTS[k] + Vector3.UP * Fixtures.CAST_HEIGHT
		# Act
		var did_hit: bool = query.cast_ground(cursor, origin, Vector3.DOWN, Fixtures.CAST_LENGTH, T, hit)
		# Assert: each probe still reads its own quadrant, before and after a degenerate face.
		assert_bool(did_hit).override_failure_message("probe %d missed" % k).is_true()
		assert_int(hit.surface_id).override_failure_message("probe %d" % k).is_equal(kinds[k])
	assert_int(data.ground_triangle_count()).is_equal(10)
	query.dispose()


func test_cast_ground_from_below_misses_back_face() -> void:
	# Arrange
	var query: CollisionQuery = CollisionQuery.new(Fixtures.quadrant_ground([0, 0, 0, 0]))
	var origin: Vector3 = Fixtures.PROBE_POINTS[0] + Vector3.DOWN * Fixtures.CAST_HEIGHT
	# Act
	var did_hit: bool = query.cast_ground(QueryCursor.new(), origin, Vector3.UP, Fixtures.CAST_LENGTH, T, GroundHit.new())
	# Assert
	assert_bool(did_hit).is_false()
	query.dispose()


func test_cast_ground_ignores_wall_layer_and_hits_ground() -> void:
	# Arrange: a wall-layer quad at WALL_TOP_Y covers the whole ground.
	var grass: int = _id(&"grass")
	var query: CollisionQuery = CollisionQuery.new(Fixtures.ground_with_walls([grass, grass, grass, grass]))
	var hit: GroundHit = GroundHit.new()
	var origin: Vector3 = Fixtures.PROBE_POINTS[1] + Vector3.UP * Fixtures.CAST_HEIGHT
	# Act
	var did_hit: bool = query.cast_ground(QueryCursor.new(), origin, Vector3.DOWN, Fixtures.CAST_LENGTH, T, hit)
	# Assert
	assert_bool(did_hit).is_true()
	assert_float(hit.point.y).is_equal_approx(0.0, HIT_TOLERANCE)
	assert_int(hit.surface_id).is_equal(grass)
	query.dispose()


func test_cast_ground_miss_returns_false_and_leaves_hit_untouched() -> void:
	# Arrange
	var query: CollisionQuery = CollisionQuery.new(Fixtures.quadrant_ground([0, 0, 0, 0]))
	var cursor: QueryCursor = QueryCursor.new()
	var hit: GroundHit = GroundHit.new()
	var sentinel: Vector3 = Vector3(1.0, 2.0, 3.0)
	hit.point = sentinel
	hit.surface_id = PREVIOUS_ID
	var far: Vector3 = Vector3.RIGHT * Fixtures.QUADRANT_SIZE * 10.0 + Vector3.UP * Fixtures.CAST_HEIGHT
	# Act
	var did_hit: bool = query.cast_ground(cursor, far, Vector3.DOWN, Fixtures.CAST_LENGTH, T, hit)
	# Assert
	assert_bool(did_hit).is_false()
	assert_vector(hit.point).is_equal(sentinel)
	assert_int(hit.surface_id).is_equal(PREVIOUS_ID)
	query.dispose()


# --- Story AC 3 (GDD AC-4): probe majority; C12 ties go to the probe nearest the CoM ----------

func test_probes_road_grass_grass_grass_give_grass() -> void:
	# Arrange: FL road, FR grass, RL grass, RR grass; the CoM sits on the road probe, which must not
	# matter (no tie).
	var road: int = _id(&"road")
	var grass: int = _id(&"grass")
	var query: CollisionQuery = CollisionQuery.new(Fixtures.quadrant_ground([road, grass, grass, grass]))
	var com: Vector3 = Fixtures.PROBE_POINTS[0]
	# Act
	var surface: int = _probe_majority(query, QueryCursor.new(), GroundHit.new(), Fixtures.PROBE_POINTS,
			com, PackedInt32Array([0, 0, 0, 0]), _pts4())
	# Assert
	assert_int(surface).is_equal(grass)
	query.dispose()


func test_probes_two_two_tie_gives_kind_nearest_centre_of_mass() -> void:
	# Arrange: CoM toward FR. "Lowest index" would pick FL's kind; C12 picks FR's. The two layouts
	# give road (id 0) then grass (id 7), so no id order can pass either.
	var road: int = _id(&"road")
	var grass: int = _id(&"grass")
	var a_query: CollisionQuery = CollisionQuery.new(Fixtures.quadrant_ground([grass, road, road, grass]))
	var b_query: CollisionQuery = CollisionQuery.new(Fixtures.quadrant_ground([road, grass, grass, road]))
	var cursor: QueryCursor = QueryCursor.new()
	var hit: GroundHit = GroundHit.new()
	var ids: PackedInt32Array = PackedInt32Array([0, 0, 0, 0])
	var points: PackedVector3Array = _pts4()
	var com: Vector3 = Fixtures.COM_NEAR_FRONT_RIGHT
	# Act
	var a: int = _probe_majority(a_query, cursor, hit, Fixtures.PROBE_POINTS, com, ids, points)
	var b: int = _probe_majority(b_query, cursor, hit, Fixtures.PROBE_POINTS, com, ids, points)
	# Assert
	assert_int(a).is_equal(road)
	assert_int(b).is_equal(grass)
	a_query.dispose()
	b_query.dispose()


func test_bike_one_one_tie_gives_kind_nearest_centre_of_mass() -> void:
	# Arrange: 2 probes (front, rear); CoM toward the rear, so "lowest index" (front) disagrees.
	var road: int = _id(&"road")
	var mud: int = _id(&"mud")
	var mud_front: CollisionQuery = CollisionQuery.new(Fixtures.bike_ground(mud, road))
	var road_front: CollisionQuery = CollisionQuery.new(Fixtures.bike_ground(road, mud))
	var cursor: QueryCursor = QueryCursor.new()
	var hit: GroundHit = GroundHit.new()
	var ids: PackedInt32Array = PackedInt32Array([0, 0])
	var points: PackedVector3Array = PackedVector3Array([Vector3.ZERO, Vector3.ZERO])
	var com: Vector3 = Fixtures.COM_BIKE_NEAR_REAR
	# Act
	var a: int = _probe_majority(mud_front, cursor, hit, Fixtures.BIKE_PROBE_POINTS, com, ids, points)
	var b: int = _probe_majority(road_front, cursor, hit, Fixtures.BIKE_PROBE_POINTS, com, ids, points)
	# Assert: the rear probe's kind.
	assert_int(a).is_equal(road)
	assert_int(b).is_equal(mud)
	mud_front.dispose()
	road_front.dispose()


func test_probes_equidistant_tie_gives_lowest_index_probe_kind() -> void:
	# Arrange: CoM exactly between the probes (cart: all four equidistant; bike: both).
	var road: int = _id(&"road")
	var grass: int = _id(&"grass")
	var cart: CollisionQuery = CollisionQuery.new(Fixtures.quadrant_ground([grass, road, road, grass]))
	var bike: CollisionQuery = CollisionQuery.new(Fixtures.bike_ground(road, grass))
	var cursor: QueryCursor = QueryCursor.new()
	var hit: GroundHit = GroundHit.new()
	# Act
	var cart_surface: int = _probe_majority(cart, cursor, hit, Fixtures.PROBE_POINTS, Fixtures.COM_CENTRE,
			PackedInt32Array([0, 0, 0, 0]), _pts4())
	var bike_surface: int = _probe_majority(bike, cursor, hit, Fixtures.BIKE_PROBE_POINTS, Fixtures.COM_BIKE_MIDWAY,
			PackedInt32Array([0, 0]), PackedVector3Array([Vector3.ZERO, Vector3.ZERO]))
	# Assert: probe 0's kind (cart front-left; bike front).
	assert_int(cart_surface).is_equal(grass)
	assert_int(bike_surface).is_equal(road)
	cart.dispose()
	bike.dispose()


func test_ties_resolve_identically_over_1000_repeats() -> void:
	# Arrange: the off-centre CoM cases, whose C12 answer differs from the lowest-index answer.
	var road: int = _id(&"road")
	var grass: int = _id(&"grass")
	var cart: CollisionQuery = CollisionQuery.new(Fixtures.quadrant_ground([grass, road, road, grass]))
	var bike: CollisionQuery = CollisionQuery.new(Fixtures.bike_ground(grass, road))
	var cursor: QueryCursor = QueryCursor.new()
	var hit: GroundHit = GroundHit.new()
	var ids4: PackedInt32Array = PackedInt32Array([0, 0, 0, 0])
	var pts4: PackedVector3Array = _pts4()
	var ids2: PackedInt32Array = PackedInt32Array([0, 0])
	var pts2: PackedVector3Array = PackedVector3Array([Vector3.ZERO, Vector3.ZERO])
	var cart_other: int = 0
	var bike_other: int = 0
	# Act
	for i in TIE_REPEATS:
		if _probe_majority(cart, cursor, hit, Fixtures.PROBE_POINTS, Fixtures.COM_NEAR_FRONT_RIGHT, ids4, pts4) != road:
			cart_other += 1
		if _probe_majority(bike, cursor, hit, Fixtures.BIKE_PROBE_POINTS, Fixtures.COM_BIKE_NEAR_REAR, ids2, pts2) != road:
			bike_other += 1
	# Assert
	assert_int(cart_other).override_failure_message("2-2 tie differed %d times" % cart_other).is_equal(0)
	assert_int(bike_other).override_failure_message("1-1 tie differed %d times" % bike_other).is_equal(0)
	cart.dispose()
	bike.dispose()


func test_majority_surface_without_hits_keeps_previous_id() -> void:
	# Arrange
	var ids: PackedInt32Array = PackedInt32Array([_id(&"grass"), _id(&"mud"), 0, 0])
	var points: PackedVector3Array = PackedVector3Array(Fixtures.PROBE_POINTS)
	var com: Vector3 = Fixtures.COM_CENTRE
	# Act / Assert: airborne (no probe hit) keeps the previous surface.
	assert_int(CollisionQuery.majority_surface(ids, points, 0, com, Vector3.UP, PREVIOUS_ID)).is_equal(PREVIOUS_ID)
	assert_int(CollisionQuery.majority_surface(PackedInt32Array(), PackedVector3Array(), 4, com, Vector3.UP,
			PREVIOUS_ID)).is_equal(PREVIOUS_ID)
	# Only the first count entries are read.
	assert_int(CollisionQuery.majority_surface(ids, points, 1, com, Vector3.UP, PREVIOUS_ID)).is_equal(_id(&"grass"))


func test_majority_surface_majority_beats_nearest_probe() -> void:
	# Arrange
	var road: int = _id(&"road")
	var grass: int = _id(&"grass")
	var mud: int = _id(&"mud")
	var sand: int = _id(&"sand")
	var near_fl: Vector3 = Fixtures.PROBE_POINTS[0]
	var near_rl: Vector3 = Fixtures.PROBE_POINTS[2]
	var three: PackedVector3Array = PackedVector3Array([Fixtures.PROBE_POINTS[0], Fixtures.PROBE_POINTS[1],
			Fixtures.PROBE_POINTS[2]])
	# Act / Assert
	# 2-1-1 with the CoM on a single probe: the pair still wins.
	assert_int(_cart_majority(PackedInt32Array([road, grass, mud, mud]), near_fl)).is_equal(mud)
	# 1-1-1-1: the kind of the probe nearest the CoM (rear-left), not the first probe's.
	assert_int(_cart_majority(PackedInt32Array([sand, road, grass, mud]), near_rl)).is_equal(grass)
	# One probe missed (3 hits, 2-1), CoM on the single: the pair wins.
	assert_int(CollisionQuery.majority_surface(PackedInt32Array([road, grass, grass]), three, 3, near_fl,
			Vector3.UP, PREVIOUS_ID)).is_equal(grass)
	# One probe missed (3 hits, 1-1-1): the kind nearest the CoM.
	assert_int(CollisionQuery.majority_surface(PackedInt32Array([mud, road, grass]), three, 3, near_rl,
			Vector3.UP, PREVIOUS_ID)).is_equal(grass)


func test_majority_surface_measures_distance_on_up_plane() -> void:
	# Arrange: probe 1 is far in 3D (3 m up) but nearer on the up plane (0.5 m against 1 m).
	var a: int = _id(&"road")
	var b: int = _id(&"grass")
	var ids: PackedInt32Array = PackedInt32Array([a, b])
	var points: PackedVector3Array = PackedVector3Array([Vector3(1.0, 0.0, 0.0), Vector3(0.5, 3.0, 0.0)])
	# Act
	var on_up_plane: int = CollisionQuery.majority_surface(ids, points, 2, Vector3.ZERO, Vector3.UP, PREVIOUS_ID)
	# With up = +X the plane is YZ: probe 0 is at distance 0, probe 1 at 3.
	var on_x_plane: int = CollisionQuery.majority_surface(ids, points, 2, Vector3.ZERO, Vector3.RIGHT, PREVIOUS_ID)
	# Assert
	assert_int(on_up_plane).is_equal(b)
	assert_int(on_x_plane).is_equal(a)


func test_majority_surface_equal_distance_goes_to_lowest_index() -> void:
	# Arrange: two probes mirrored about the CoM, so their planar distances are exactly equal.
	var road: int = _id(&"road")
	var grass: int = _id(&"grass")
	var points: PackedVector3Array = PackedVector3Array([Vector3(-0.5, 0.0, -0.7), Vector3(0.5, 0.0, -0.7)])
	var com: Vector3 = Vector3(0.0, 0.0, -0.7)
	# Act
	var road_first: int = CollisionQuery.majority_surface(PackedInt32Array([road, grass]), points, 2, com,
			Vector3.UP, PREVIOUS_ID)
	var grass_first: int = CollisionQuery.majority_surface(PackedInt32Array([grass, road]), points, 2, com,
			Vector3.UP, PREVIOUS_ID)
	# Assert: probe index decides, not id.
	assert_int(road_first).is_equal(road)
	assert_int(grass_first).is_equal(grass)


# --- Story AC 4: dispose --------------------------------------------------------------------------------

func test_dispose_frees_every_rid_bodies_then_shapes_then_space() -> void:
	# Arrange
	var data: TrackCollisionData = Fixtures.ground_with_walls([0, 0, 0, 0])
	var query: CollisionQuery = CollisionQuery.new(data)
	var rids: Array[RID] = query.owned_rids()
	var space: RID = query.space_rid()
	var n_bodies: int = 2
	var n_shapes: int = 1 + data.wall_faces.size()
	# Assert the free order before freeing: bodies, then shapes, then the space.
	assert_int(rids.size()).is_equal(n_bodies + n_shapes + 1)
	for i in n_bodies:
		assert_bool(PhysicsServer3D.body_get_space(rids[i]) == space).override_failure_message(
				"rid %d is not a body of the space" % i).is_true()
	for i in range(n_bodies, n_bodies + n_shapes):
		assert_int(PhysicsServer3D.shape_get_type(rids[i])).is_equal(PhysicsServer3D.SHAPE_CONCAVE_POLYGON)
	assert_bool(rids[rids.size() - 1] == space).is_true()
	assert_object(PhysicsServer3D.space_get_direct_state(space)).is_not_null()
	# Act
	query.dispose()
	# Assert: nothing is left on the server (orphan check). Each getter prints an expected
	# "Parameter ... is null" engine error and returns its not-found value.
	assert_bool(query.is_disposed()).is_true()
	assert_array(query.owned_rids()).is_empty()
	assert_bool(query.space_rid().is_valid()).is_false()
	for i in n_bodies:
		assert_bool(PhysicsServer3D.body_get_space(rids[i]).is_valid()).override_failure_message(
				"body %d still exists" % i).is_false()
	for i in range(n_bodies, n_bodies + n_shapes):
		assert_int(PhysicsServer3D.shape_get_type(rids[i])).override_failure_message(
				"shape %d still exists" % i).is_equal(PhysicsServer3D.SHAPE_CUSTOM)
	assert_object(PhysicsServer3D.space_get_direct_state(space)).is_null()


func test_dispose_returns_object_count_to_baseline() -> void:
	# Arrange: everything except the query exists before the baseline.
	var data: TrackCollisionData = Fixtures.ground_with_walls([0, 0, 0, 0])
	var cursor: QueryCursor = QueryCursor.new()
	var hit: GroundHit = GroundHit.new()
	var origin: Vector3 = Fixtures.PROBE_POINTS[0] + Vector3.UP * Fixtures.CAST_HEIGHT
	var baseline: int = int(Performance.get_monitor(Performance.OBJECT_COUNT))
	# Act: load, query, unload.
	var query: CollisionQuery = CollisionQuery.new(data)
	var loaded: int = int(Performance.get_monitor(Performance.OBJECT_COUNT))
	var did_hit: bool = query.cast_ground(cursor, origin, Vector3.DOWN, Fixtures.CAST_LENGTH, T, hit)
	var query_ref: WeakRef = weakref(query)
	query.dispose()
	query = null
	var query_freed: bool = query_ref.get_ref() == null
	query_ref = null  # the WeakRef is an Object too: drop it before counting
	var unloaded: int = int(Performance.get_monitor(Performance.OBJECT_COUNT))
	# Assert: the query and its space's direct state existed, then nothing is left behind.
	assert_bool(did_hit).is_true()
	assert_int(loaded).is_greater(baseline)
	assert_bool(query_freed).is_true()
	assert_int(unloaded).is_equal(baseline)


func test_dispose_twice_is_safe() -> void:
	# Arrange
	var query: CollisionQuery = CollisionQuery.new(Fixtures.ground_with_walls([0, 0, 0, 0]))
	query.dispose()
	# Act / Assert: the second call logs nothing and changes nothing.
	await assert_error(func() -> void: query.dispose()).is_success()
	assert_bool(query.is_disposed()).is_true()
	assert_array(query.owned_rids()).is_empty()
	assert_bool(query.space_rid().is_valid()).is_false()


func test_cast_ground_after_dispose_asserts_in_debug_or_misses() -> void:
	# Arrange
	var query: CollisionQuery = CollisionQuery.new(Fixtures.quadrant_ground([0, 0, 0, 0]))
	query.dispose()
	var cursor: QueryCursor = QueryCursor.new()
	var hit: GroundHit = GroundHit.new()
	hit.surface_id = PREVIOUS_ID
	var origin: Vector3 = Fixtures.PROBE_POINTS[0] + Vector3.UP * Fixtures.CAST_HEIGHT
	var out: Array = []
	# Act / Assert: debug builds stop at assert(not _disposed); release builds strip the assert and
	# return false. Either way nothing is read from the freed space and the hit is untouched.
	if OS.is_debug_build():
		await assert_error(func() -> void: out.append(query.cast_ground(cursor, origin, Vector3.DOWN, Fixtures.CAST_LENGTH, T, hit))).is_runtime_error(
				"Assertion failed: CollisionQuery.cast_ground after dispose()")
	else:
		assert_bool(query.cast_ground(cursor, origin, Vector3.DOWN, Fixtures.CAST_LENGTH, T, hit)).is_false()
	assert_int(hit.surface_id).is_equal(PREVIOUS_ID)


func test_query_dropped_without_dispose_warns_and_frees_rids() -> void:
	# Arrange
	var data: TrackCollisionData = Fixtures.quadrant_ground([0, 0, 0, 0])
	var rids: Array[RID] = []
	# Act: the only reference drops inside the callable, without dispose().
	await assert_error(_drop_query_without_dispose.bind(data, rids)).is_push_warning("CollisionQuery freed without dispose(); disposing now (call dispose() at track unload)")
	# Assert: ground body, ground shape and space, all freed by the fallback.
	assert_int(rids.size()).is_equal(3)
	assert_bool(PhysicsServer3D.body_get_space(rids[0]).is_valid()).is_false()
	assert_int(PhysicsServer3D.shape_get_type(rids[1])).is_equal(PhysicsServer3D.SHAPE_CUSTOM)
	assert_object(PhysicsServer3D.space_get_direct_state(rids[2])).is_null()
