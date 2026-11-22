extends SceneTree
## Exit-safety probe of the native collision classes (core-rebuild story 067, ADR-0007 section 4 "RID ownership
## and teardown"): a built CollisionQuery (it owns server RIDs), a QueryCursor (it holds engine Resources), a
## GroundHit and a WallHit are kept in static variables and the process quits WITHOUT dispose(). Run with
## --verbose: the exit must be 0 with no ERROR line and no "RID allocations ... leaked" / "ObjectDB instances ...
## leaked" line (tools/native_exit_safety.sh checks all three). Prints the sentinel "PROBE_RAN" at the end.
##   godot --headless --verbose --path . -s res://tools/collision_exit_probe.gd

const Fixtures = preload("res://tests/unit/collision/collision_fixtures.gd")

static var _held_query: CollisionQuery = null
static var _held_cursor: QueryCursor = null
static var _held_ground: GroundHit = null
static var _held_wall: WallHit = null


func _init() -> void:
	_held_query = CollisionQuery.create(Fixtures.mirror_fixture().pack_native())
	_held_cursor = QueryCursor.new()
	_held_ground = GroundHit.new()
	_held_wall = WallHit.new()
	var ground_ok: bool = _held_query.cast_ground(_held_cursor, Vector3(4.0, 3.0, 0.0), Vector3.DOWN, 10.0, 0.0, _held_ground)
	var wall_ok: bool = _held_query.sweep_walls(_held_cursor, Vector3(6.0, 2.0, 0.0), Vector3(-6.0, 2.0, 0.0), 0.5, 0.0, _held_wall)
	print("PROBE_RAN built=%s cursor_built=%s owned_rids=%d ground=%s wall=%s" % [_held_query.is_built(), _held_cursor.is_built(), _held_query.owned_rids().size(), ground_ok, wall_ok])
	quit(0)
