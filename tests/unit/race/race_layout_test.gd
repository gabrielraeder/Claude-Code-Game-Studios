extends GdUnitTestSuite
## Core-rebuild story 068, criterion "Layouts fixed and recorded": the GDScript layout file (RaceLayout) is pinned to
## literal numbers (the ADR-0003 amendment, 2026-11-22), and the constants bound on RaceSim are pinned to the same
## numbers, so the C++ side (static_asserts in native/src/race/race_layout.h plus these bound values) and the GDScript
## side cannot drift apart.

const _GUARD = preload("res://tests/unit/native/native_test_guard.gd")

## The layout, as recorded in ADR-0003 Key Interfaces. Name -> value.
const PINNED: Dictionary = {
	"SETUP_SCHEMA_VERSION": 1, "MAX_SLOTS": 32, "MAX_SEEDS": 64, "MAX_EVENT_CAPACITY": 4096,
	"STAGE_BEGIN_TICK": 0, "STAGE_APPLY_EVENTS": 1, "STAGE_STEP_DRIVE": 2, "STAGE_STEP_BODIES": 3, "STAGE_SET_REMOTE": 4,
	"STAGE_STEP_CONTACT": 5, "STAGE_PROGRESS_ITEMS_HAZARDS": 6, "STAGE_END_TICK": 7, "STAGE_COUNT": 8,
	"ROLE_LOCAL": 0, "ROLE_BOT": 1, "ROLE_REMOTE": 2,
	"DRIVER_STRIDE": 6, "DRIVER_STEER": 0, "DRIVER_THROTTLE": 1, "DRIVER_BRAKE": 2, "DRIVER_DRIFT": 3, "DRIVER_HOP": 4, "DRIVER_ITEM_USE": 5,
	"SNAP_STRIDE": 20, "SNAP_POS": 0, "SNAP_BASIS": 3, "SNAP_VEL": 12, "SNAP_SPEED": 15, "SNAP_FLAGS": 16, "SNAP_KNOCK": 17,
	"SNAP_STATE": 18, "SNAP_TICK": 19, "SNAP_FLAG_TELEPORTED": 1, "SNAP_FLAG_BUMPED": 2, "SNAP_FLAG_HELD": 4, "SNAP_FLAG_CONTACT_ELIGIBLE": 8,
	"REMOTE_STRIDE": 16, "PLACE_STRIDE": 12,
	"PROG_STRIDE": 4, "PROG_DISTANCE": 0, "PROG_LAP": 1, "PROG_RANK": 2, "PROG_FLAGS": 3,
	"PROG_FLAG_MOVED": 1, "PROG_FLAG_SAFE": 2, "PROG_FLAG_FINISHED": 4,
	"EVENT_HEADER_STRIDE": 3, "EVENT_SLOT": 0, "EVENT_KIND": 1, "EVENT_PAYLOAD_OFFSET": 2,
	"EVENT_KIND_KNOCK": 1, "EVENT_KIND_PICKUP": 2, "EVENT_KIND_ITEM_HIT": 3,
	"EVENT_PAYLOAD_KNOCK": 4, "EVENT_PAYLOAD_PICKUP": 1, "EVENT_PAYLOAD_ITEM_HIT": 2, "EVENT_PAYLOAD_MAX": 4,
}


func before() -> void:
	assert_str(_GUARD.problem()).is_empty()


func test_gdscript_layout_file_holds_the_pinned_numbers() -> void:
	var script: GDScript = load("res://src/core/race_layout.gd")
	var constants: Dictionary = script.get_script_constant_map()
	for key: String in PINNED:
		assert_bool(constants.has(key)).override_failure_message("RaceLayout lacks %s" % key).is_true()
		assert_int(constants[key]).override_failure_message("RaceLayout.%s" % key).is_equal(PINNED[key])
	assert_int(constants.size()).override_failure_message("RaceLayout has constants the pin list does not name").is_equal(PINNED.size())


func test_native_bound_constants_hold_the_pinned_numbers() -> void:
	for key: String in PINNED:
		assert_bool(ClassDB.class_has_integer_constant(&"RaceSim", key)).override_failure_message("RaceSim lacks constant %s" % key).is_true()
		assert_int(ClassDB.class_get_integer_constant(&"RaceSim", key)).override_failure_message("RaceSim.%s" % key).is_equal(PINNED[key])
	var bound: PackedStringArray = ClassDB.class_get_integer_constant_list(&"RaceSim", true)
	assert_int(bound.size()).override_failure_message("RaceSim binds constants the pin list does not name").is_equal(PINNED.size())


func test_payload_floats_matches_the_kind_table() -> void:
	assert_int(RaceLayout.payload_floats(RaceLayout.EVENT_KIND_KNOCK)).is_equal(4)
	assert_int(RaceLayout.payload_floats(RaceLayout.EVENT_KIND_PICKUP)).is_equal(1)
	assert_int(RaceLayout.payload_floats(RaceLayout.EVENT_KIND_ITEM_HIT)).is_equal(2)
	assert_int(RaceLayout.payload_floats(0)).is_equal(-1)


func test_snapshot_fields_do_not_overlap_and_fill_the_stride() -> void:
	var starts: Array[int] = [RaceLayout.SNAP_POS, RaceLayout.SNAP_BASIS, RaceLayout.SNAP_VEL, RaceLayout.SNAP_SPEED, RaceLayout.SNAP_FLAGS,
		RaceLayout.SNAP_KNOCK, RaceLayout.SNAP_STATE, RaceLayout.SNAP_TICK]
	var widths: Array[int] = [3, 9, 3, 1, 1, 1, 1, 1]
	var next: int = 0
	for i in starts.size():
		assert_int(starts[i]).is_equal(next)
		next += widths[i]
	assert_int(next).is_equal(RaceLayout.SNAP_STRIDE)
	assert_int(RaceLayout.REMOTE_STRIDE).is_equal(RaceLayout.SNAP_SPEED + 1)
