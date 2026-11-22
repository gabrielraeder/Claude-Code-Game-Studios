extends GdUnitTestSuite
## Core-rebuild story 007 (QL finding): on the story 007 bench mesh, a static wall sweep whose cast
## hit at unsafe fraction < 1 could find no rest contact exactly at the unsafe point, and reported
## WALL_ATTR_NONE. The input below was captured from the bench (curve section, tick 167, kart 10,
## sweep 0; the right wall carries wall attribute 1). Jolt 5.6 (4.8-beta3) reports safe 0.25 /
## unsafe 0.2539; a rest check at the unsafe point finds nothing, one 0.0001 m further finds the
## wall. The same 22 wall triangles alone do NOT reproduce it (the whole mesh does), so the test
## builds the bench mesh (tools/bench_track_fixture.gd, deterministic, code-built: no file I/O).

const _GUARD = preload("res://tests/unit/native/native_test_guard.gd")
const BenchFixture = preload("res://tools/bench_track_fixture.gd")

## The captured sweep (float32-exact values) and its radius.
const FROM: Vector3 = Vector3(213.37308, -0.99377036, -13.371248)
const TO: Vector3 = Vector3(213.40935, -1.0054376, -12.961111)
const RADIUS: float = 1.0
## The right wall's attribute in the bench mesh, and Jolt's safe fraction for this cast.
const RIGHT_WALL_ATTR: int = 1
const SAFE_FRACTION: float = 0.25
const FRACTION_TOLERANCE: float = 0.0001


func before() -> void:
	assert_str(_GUARD.problem()).is_empty()


func test_sweep_whose_unsafe_point_rest_check_misses_reports_the_wall_attr() -> void:
	# Arrange
	var fixture: BenchFixture = BenchFixture.new()
	fixture.build()
	var query: CollisionQuery = CollisionQuery.create(fixture.data.pack_native())
	var hit: WallHit = WallHit.new()
	# Act
	var did_hit: bool = query.sweep_walls(QueryCursor.new(), FROM, TO, RADIUS, 0.0, hit)
	query.dispose()
	# Assert
	assert_bool(did_hit).is_true()
	assert_bool(hit.started_inside).is_false()
	assert_int(hit.wall_attr).is_equal(RIGHT_WALL_ATTR)
	assert_int(hit.collider_id).is_equal(0)
	assert_float(hit.fraction).is_equal_approx(SAFE_FRACTION, FRACTION_TOLERANCE)
