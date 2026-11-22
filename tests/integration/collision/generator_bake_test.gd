extends GdUnitTestSuite
## Core-rebuild story 008: tools/legacy_test_bake.gd turns the extractor's neutral JSON into
## TrackCollisionData. Runs the bake on a tiny hand-made JSON fixture (a 48-sided closed loop with
## one boost pad, one slick zone, one ramp and one barrel mover), built by a factory and
## round-tripped through JSON text, so no file I/O and no frozen game. The query is built only
## through CollisionBootCheck.checked_query. Retired with the bake at A3 (story 065).

const Bake = preload("res://tools/legacy_test_bake.gd")
## Story 066 guard: refuses a stale dogworks_core DLL (CollisionQuery is native since story 067).
const _GUARD = preload("res://tests/unit/native/native_test_guard.gd")

## Fixture loop: radius (m), sample count, road half width (m), curb (m), wall offset (m).
const LOOP_RADIUS: float = 30.0
const LOOP_SAMPLES: int = 48
const HALF_WIDTH: float = 4.0
const CURB: float = 1.0
const WALL_OFFSET: float = 5.0
## Sample index the pad sits on, the slick zone sits on, and the ramp starts at.
const PAD_SAMPLE: int = 12
const SLICK_SAMPLE: int = 24
const RAMP_SAMPLE: int = 36
## Pad half extents (m), slick square half size (m), ramp length and lip (m).
const PAD_HALF: Vector2 = Vector2(3.0, 1.5)
const SLICK_HALF: float = 2.0
const RAMP_LENGTH: float = 4.0
const RAMP_LIP: float = 1.0
## Barrel mover: radius, length (m), period (s).
const BARREL_RADIUS: float = 0.5
const BARREL_LENGTH: float = 1.0
const BARREL_PERIOD: float = 2.0
## Frozen-format scalars of the fixture.
const GROUND_Y: float = -0.05
const LEVEL_SEPARATION: float = 3.0
const SURFACE_TOL: float = 0.8
const PAD_TOL: float = 2.0
const DECK_THICKNESS: float = 0.6
## Casts start this high (m) and reach this far down (m).
const CAST_START: float = 2.0
const CAST_LENGTH: float = 4.0
## Offset (m) added to every cast point so it never sits on a mesh vertex.
const PROBE_NUDGE: Vector2 = Vector2(0.13, 0.07)
## Height and wall-offset tolerances (m) of the checks (the story's equivalence tolerances).
const HEIGHT_TOL: float = 0.05
const WALL_TOL: float = 0.05
## Wall sweep: height over the road (m), sphere radius (m), reach past the wall (m).
const SWEEP_LIFT: float = 0.5
const SWEEP_RADIUS: float = 0.1
const SWEEP_EXTRA: float = 1.0

var _surfaces: SurfaceSet
var _walls: WallAttrSet
var _query: CollisionQuery = null


func before() -> void:
	assert_str(_GUARD.problem()).is_empty()


func before_test() -> void:
	_surfaces = SurfaceSet.load_checked(SurfaceSet.CORE_PATH)
	_walls = WallAttrSet.load_checked(WallAttrSet.CORE_PATH)


func after_test() -> void:
	if _query != null:
		_query.dispose()
		_query = null


## Loop vertex [param i] (counter-clockwise in XZ).
static func _vertex(i: int) -> Vector2:
	var a: float = TAU * float(posmod(i, LOOP_SAMPLES)) / float(LOOP_SAMPLES)
	return Vector2(cos(a), sin(a)) * LOOP_RADIUS


## The fixture document, as the extractor would write it, round-tripped through JSON text.
static func _fixture_doc() -> Dictionary:
	var points: Array = []
	var ys: Array = []
	var banks: Array = []
	var halves: Array = []
	var walls: Array = []
	var opening: Array = []
	var cumulative: Array = [0.0]
	for i in LOOP_SAMPLES:
		var v: Vector2 = _vertex(i)
		points.append_array([v.x, v.y])
		ys.append(0.0)
		banks.append(0.0)
		halves.append(HALF_WIDTH)
		walls.append(WALL_OFFSET)
		opening.append(0)
		cumulative.append(float(cumulative[i]) + v.distance_to(_vertex(i + 1)))
	var length: float = cumulative[LOOP_SAMPLES]
	var pad_c: Vector2 = _vertex(PAD_SAMPLE)
	var pad_t: Vector2 = (_vertex(PAD_SAMPLE + 1) - _vertex(PAD_SAMPLE - 1)).normalized()
	var sc: Vector2 = _vertex(SLICK_SAMPLE)
	var doc: Dictionary = {
		"format": Bake.FORMAT_NAME, "version": Bake.FORMAT_VERSION, "track_id": "fixture_loop",
		"main_length": length, "ground_y": GROUND_Y, "level_separation": LEVEL_SEPARATION,
		"deck_thickness": DECK_THICKNESS, "surface_height_tolerance": SURFACE_TOL,
		"pad_height_tolerance": PAD_TOL, "road_keep_band": 1.5, "branch_switch_margin": 0.75, "query_window": 14,
		"checkpoint_s": [],
		"paths": [{
			"index": -1, "id": "main", "closed": true, "curb": CURB, "length": length, "s_in": 0.0,
			"s_out": 0.0, "wall_drag_mult": 1.0, "floor_drag_mult": 1.0, "points": points, "y": ys,
			"bank": banks, "half": halves, "wall_pos": walls, "wall_neg": walls, "opening": opening,
			"cumulative": cumulative,
		}],
		"ramps": [{"path": -1, "from": float(cumulative[RAMP_SAMPLE]), "length": RAMP_LENGTH, "lip": RAMP_LIP,
				"lateral": 0.0, "half": 0.0}],
		"pads": [{"center": [pad_c.x, pad_c.y], "dir": [pad_t.x, pad_t.y], "half": [PAD_HALF.x, PAD_HALF.y],
				"path": -1, "height": 0.0}],
		"zones": [{"id": "slick_patch", "kind": "slick", "on_road": true,
				"polygon": [sc.x - SLICK_HALF, sc.y - SLICK_HALF, sc.x + SLICK_HALF, sc.y - SLICK_HALF,
						sc.x + SLICK_HALF, sc.y + SLICK_HALF, sc.x - SLICK_HALF, sc.y + SLICK_HALF],
				"height": 0.0, "vertex_heights": [], "triangles": [], "height_min": 0.0, "height_max": 0.0,
				"fence": false, "fence_edges": []}],
		"hazards": [],
		"movers": [{"id": "barrel_0", "kind": "barrel", "visual": "barrel", "hit_effect": "spin",
				"solid_body": false, "path": -1, "path_from": 0.0, "path_to": 2.0, "lane_offset": 0.0,
				"schedule_period": BARREL_PERIOD, "period": BARREL_PERIOD, "phase": 0.0, "traveler": true,
				"shuttle": false, "body_radius": BARREL_RADIUS, "body_length": BARREL_LENGTH,
				"key_t": [0.0, 1.0], "key_pos": [LOOP_RADIUS, 0.0, 0.0, LOOP_RADIUS, 0.0, 1.0],
				"key_progress": [1.0, 1.0], "key_tangent": [0.0, 1.0, 0.0, 1.0], "key_slope": [0.0, 0.0],
				"key_distance": [0.0, 1.0]}],
	}
	return JSON.parse_string(JSON.stringify(doc, "", true, true)) as Dictionary


func _bake() -> Bake.BakeResult:
	return Bake.bake_doc(_fixture_doc(), _surfaces, _walls)


## Casts down at [param p] moved by PROBE_NUDGE, so no cast lands exactly on a mesh vertex (at an
## exact shared vertex Jolt's face index is ambiguous; seen in story 008).
func _cast(q: CollisionQuery, p: Vector2, hit: GroundHit) -> bool:
	var at: Vector2 = p + PROBE_NUDGE
	return q.cast_ground(QueryCursor.new(), Vector3(at.x, CAST_START, at.y), Vector3.DOWN, CAST_LENGTH, 0.0, hit)


func test_fixture_bakes_with_valid_layout_and_core_ids() -> void:
	var baked: Bake.BakeResult = _bake()
	assert_str(baked.problem).is_empty()
	assert_object(baked.data).is_not_null()
	assert_str(baked.data.layout_error()).is_empty()
	assert_str(baked.data.id_error(_surfaces, _walls)).is_empty()
	assert_int(baked.data.ground_triangle_count()).is_greater(0)


func test_surface_ids_are_road_pad_slick_and_ramp() -> void:
	var baked: Bake.BakeResult = _bake()
	var ids: Array = Array(baked.data.surface_of_face)
	for kind in [&"road", &"boost_pad", &"slick", &"trick_ramp"]:
		assert_bool(ids.has(_surfaces.type_of(kind).id)).override_failure_message("no %s triangle" % kind).is_true()


func test_walls_are_one_standard_shape() -> void:
	var baked: Bake.BakeResult = _bake()
	assert_array(Array(baked.data.wall_attr_ids)).is_equal([_walls.attr_of(&"standard").id])
	assert_int(baked.data.wall_faces[0].size()).is_greater(0)


func test_barrel_becomes_a_non_solid_cylinder_mover() -> void:
	var baked: Bake.BakeResult = _bake()
	assert_int(baked.data.movers.size()).is_equal(1)
	var m: MoverDef = baked.data.movers[0]
	assert_int(m.id).is_equal(1)
	assert_bool(m.solid).is_false()
	assert_int(m.shape).is_equal(MoverDef.Shape.CYLINDER)
	assert_float(m.radius).is_equal_approx(BARREL_RADIUS, 0.0001)
	assert_int(m.key_t.size()).is_equal(2)
	assert_str(m.layout_error()).is_empty()


func test_checked_query_passes_and_casts_find_the_baked_surfaces() -> void:
	var baked: Bake.BakeResult = _bake()
	var checked: CollisionBootCheck.CheckedQuery = CollisionBootCheck.checked_query(baked.data, _surfaces, _walls, Bake.PROBE_MAX_DROP)
	assert_str(checked.problem).is_empty()
	_query = checked.query
	var hit: GroundHit = GroundHit.new()
	assert_bool(_cast(_query, _vertex(PAD_SAMPLE), hit)).is_true()
	assert_int(hit.surface_id).is_equal(_surfaces.type_of(&"boost_pad").id)
	assert_bool(_cast(_query, _vertex(SLICK_SAMPLE), hit)).is_true()
	assert_int(hit.surface_id).is_equal(_surfaces.type_of(&"slick").id)
	var road_point: Vector2 = _vertex(PAD_SAMPLE + 6)
	assert_bool(_cast(_query, road_point, hit)).is_true()
	assert_int(hit.surface_id).is_equal(_surfaces.type_of(&"road").id)
	assert_float(hit.point.y).is_equal_approx(0.0, HEIGHT_TOL)
	var ramp_mid: Vector2 = _vertex(RAMP_SAMPLE).move_toward(_vertex(RAMP_SAMPLE + 1), RAMP_LENGTH * 0.5)
	assert_bool(_cast(_query, ramp_mid, hit)).is_true()
	assert_int(hit.surface_id).is_equal(_surfaces.type_of(&"trick_ramp").id)
	assert_float(hit.point.y).is_equal_approx(RAMP_LIP * 0.5, HEIGHT_TOL)


func test_wall_sweep_finds_the_wall_at_the_frozen_offset() -> void:
	var baked: Bake.BakeResult = _bake()
	var checked: CollisionBootCheck.CheckedQuery = CollisionBootCheck.checked_query(baked.data, _surfaces, _walls, Bake.PROBE_MAX_DROP)
	assert_str(checked.problem).is_empty()
	_query = checked.query
	var c: Vector2 = _vertex(0)
	var out_dir: Vector2 = c.normalized()
	var to: Vector2 = c + out_dir * (WALL_OFFSET + SWEEP_EXTRA)
	var hit: WallHit = WallHit.new()
	var blocked: bool = _query.sweep_walls(QueryCursor.new(), Vector3(c.x, SWEEP_LIFT, c.y), Vector3(to.x, SWEEP_LIFT, to.y),
			SWEEP_RADIUS, 0.0, hit)
	assert_bool(blocked).is_true()
	assert_bool(hit.started_inside).is_false()
	assert_float((Vector2(hit.point.x, hit.point.z) - c).dot(out_dir)).is_equal_approx(WALL_OFFSET, WALL_TOL)
	assert_int(hit.wall_attr).is_equal(_walls.attr_of(&"standard").id)


func test_cast_exactly_on_a_shared_deck_vertex_hits_the_deck() -> void:
	# Arrange: a deck vertex shared by the two segments either side of a loop sample (pad centre and
	# a plain road sample). Story 008 found casts there falling through a sub-millimetre row crack.
	var baked: Bake.BakeResult = _bake()
	var checked: CollisionBootCheck.CheckedQuery = CollisionBootCheck.checked_query(baked.data, _surfaces, _walls, Bake.PROBE_MAX_DROP)
	assert_str(checked.problem).is_empty()
	_query = checked.query
	var hit: GroundHit = GroundHit.new()
	for sample in [PAD_SAMPLE, PAD_SAMPLE + 6]:
		var p: Vector2 = _vertex(sample)
		# Act: no nudge.
		var found: bool = _query.cast_ground(QueryCursor.new(), Vector3(p.x, CAST_START, p.y), Vector3.DOWN, CAST_LENGTH, 0.0, hit)
		# Assert: the deck (height 0), not the floor at GROUND_Y.
		assert_bool(found).is_true()
		assert_float(hit.point.y).is_equal_approx(0.0, HEIGHT_TOL)
		# The surface id at an exact shared vertex is NOT asserted: there the native cast can report a
		# neighbouring triangle's face index (story 008 open item, not worked around in the bake).


func test_deck_grid_is_watertight() -> void:
	var baked: Bake.BakeResult = _bake()
	var edges: Dictionary = baked.stats["deck_open_edges"]
	assert_int(int(edges["unexpected"])).override_failure_message(str(baked.notes)).is_equal(0)
	assert_int(int(edges["outer"])).is_greater(0)


func test_wrong_format_version_is_refused() -> void:
	var doc: Dictionary = _fixture_doc()
	doc["version"] = Bake.FORMAT_VERSION + 1
	var baked: Bake.BakeResult = Bake.bake_doc(doc, _surfaces, _walls)
	assert_str(baked.problem).contains("not a")
	assert_object(baked.data).is_null()


func test_bake_is_deterministic() -> void:
	var a: Bake.BakeResult = _bake()
	var b: Bake.BakeResult = _bake()
	assert_bool(a.data.ground_faces == b.data.ground_faces).is_true()
	assert_bool(a.data.surface_of_face == b.data.surface_of_face).is_true()
	assert_bool(a.data.wall_faces == b.data.wall_faces).is_true()
