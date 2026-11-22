extends GdUnitTestSuite
## Core-rebuild story 002: the core surface registry (assets/data/core/surface_set.tres, SurfaceSet,
## SurfaceType) and the core wall-attribute registry (WallAttr, WallAttrSet,
## assets/data/core/wall_attr_set.tres). Loads only res:// resources: the core sets, the frozen
## surface set (the AC-3 oracle) and the fixtures in fixtures/ next to this file.
##
## Each rejection test asserts the loader's exact push_error message, so it proves that the check
## it names fired (and not another one), and that the loader returned null.
##
## Acceptance criteria -> tests:
##   Core SurfaceSet          test_core_surface_set_ids_match_pinned_core_ids,
##                            test_surface_set_load_checked_* (one per rejection)
##   Frozen kinds unchanged   test_core_frozen_kinds_handling_matches_frozen_set
##   Wall attributes          test_core_wall_attr_set_holds_standard_and_rough,
##                            test_wall_attr_has_drag_and_bounce_fields_and_no_opening_field,
##                            test_wall_attr_of_unknown_name_returns_null,
##                            test_wall_attr_of_non_contiguous_id_finds_by_name,
##                            test_wall_attr_set_load_checked_* (one per rejection)
##   Additive shared data     test_surface_type_new_fields_have_defaults,
##                            test_registry_scripts_are_tool_scripts,
##                            test_core_neutral_kinds_hold_defaults_and_emit_no_puffs,
##                            test_frozen_surface_set_new_fields_stay_default
##                            (the regression half is tools/regression.sh, run outside gdUnit4)

## The frozen surface set: oracle for the six frozen kinds (Track Collision GDD 3.2.2).
const FROZEN_SURFACE_SET_PATH: String = "res://assets/data/surfaces/surface_set.tres"
## Fixture folder.
const FIXTURES: String = "res://tests/unit/collision/fixtures/"
## A path with no resource behind it.
const MISSING_PATH: String = "res://tests/unit/collision/fixtures/no_such_set.tres"
## Core surface ids pinned before the first core bake (ADR-0002 TrackCollisionData, "Core ids").
const PINNED_SURFACE_IDS: Dictionary[StringName, int] = {
	&"road": 0, &"grass": 1, &"sand": 2, &"mud": 3, &"rubble": 4,
	&"shallows": 5, &"slick": 6, &"boost_pad": 7, &"trick_ramp": 8,
}
## The six kinds of the frozen game.
const FROZEN_KINDS: Array[StringName] = [&"grass", &"sand", &"mud", &"rubble", &"shallows", &"slick"]
## The kinds the core adds, which behave as the frozen "no surface" branch (GDD 3.2.2).
const NEUTRAL_KINDS: Array[StringName] = [&"road", &"boost_pad", &"trick_ramp"]
## The handling columns of Track Collision GDD 3.2.2 (SurfaceType field names). Kept apart from
## SurfaceSet.NEUTRAL_FIELDS on purpose: the test must not trust the code's own list.
const HANDLING_FIELDS: Array[StringName] = [
	&"max_speed_frac", &"drag", &"grip_mult", &"steer_mult", &"drift_allowed", &"surface_decel",
	&"boost_ignores", &"tail_time", &"bump_yaw", &"bump_cycles_per_m", &"bump_height",
]
## Core wall attributes: id and scrape drag (Track Collision GDD 3.3 / AC-8; ids append-only).
const PINNED_WALL_IDS: Dictionary[StringName, int] = {&"standard": 0, &"rough": 1}
const PINNED_WALL_SCRAPE_DRAG: Dictionary[StringName, float] = {&"standard": 1.0, &"rough": 2.0}
## Fixture wall_attr_set_sparse_ids.tres: rough sits at id 5 (ids need not be contiguous).
const SPARSE_ROUGH_ID: int = 5
## Scripts the story marks @tool.
const TOOL_SCRIPT_PATHS: Array[String] = [
	"res://src/data/surface_set.gd",
	"res://src/data/surface_type.gd",
	"res://src/core/collision/wall_attr_set.gd",
	"res://src/core/collision/wall_attr.gd",
]


# --- Core SurfaceSet --------------------------------------------------------------------------

func test_core_surface_set_ids_match_pinned_core_ids() -> void:
	# Arrange / Act
	var surfaces: SurfaceSet = SurfaceSet.load_checked(SurfaceSet.CORE_PATH)
	# Assert
	assert_object(surfaces).is_not_null()
	assert_int(surfaces.types.size()).is_equal(PINNED_SURFACE_IDS.size())
	var seen: Dictionary[int, bool] = {}
	for t in surfaces.types:
		assert_bool(PINNED_SURFACE_IDS.has(t.kind)).override_failure_message(
			"unexpected kind %s" % t.kind).is_true()
		assert_int(t.id).override_failure_message("%s id" % t.kind).is_equal(PINNED_SURFACE_IDS.get(t.kind, -1))
		assert_int(t.id).is_between(0, SurfaceSet.MAX_ID)
		assert_bool(seen.has(t.id)).override_failure_message("id %d repeated" % t.id).is_false()
		seen[t.id] = true
	assert_int(surfaces.type_of(&"road").id).is_equal(0)
	assert_object(surfaces.type_of(&"boost_pad")).is_not_null()
	assert_object(surfaces.type_of(&"trick_ramp")).is_not_null()


func test_surface_set_load_checked_duplicate_id_returns_null() -> void:
	var path: String = FIXTURES + "surface_set_duplicate_id.tres"
	var out: Array = []
	await assert_error(func() -> void: out.append(SurfaceSet.load_checked(path))).is_push_error(
		"SurfaceSet.load_checked: %s repeats surface id 0 (grass)" % path)
	assert_object(out[0]).is_null()


func test_surface_set_load_checked_missing_id_returns_null() -> void:
	# The frozen set's types carry no id (-1).
	var path: String = FROZEN_SURFACE_SET_PATH
	var out: Array = []
	await assert_error(func() -> void: out.append(SurfaceSet.load_checked(path))).is_push_error(
		"SurfaceSet.load_checked: %s type grass has id -1, outside 0..255" % path)
	assert_object(out[0]).is_null()


func test_surface_set_load_checked_id_over_max_returns_null() -> void:
	var path: String = FIXTURES + "surface_set_id_over_max.tres"
	var out: Array = []
	await assert_error(func() -> void: out.append(SurfaceSet.load_checked(path))).is_push_error(
		"SurfaceSet.load_checked: %s type grass has id 256, outside 0..255" % path)
	assert_object(out[0]).is_null()


func test_surface_set_load_checked_null_entry_returns_null() -> void:
	var path: String = FIXTURES + "surface_set_null_entry.tres"
	var out: Array = []
	await assert_error(func() -> void: out.append(SurfaceSet.load_checked(path))).is_push_error(
		"SurfaceSet.load_checked: %s has a null type at index 1" % path)
	assert_object(out[0]).is_null()


func test_surface_set_load_checked_empty_kind_returns_null() -> void:
	var path: String = FIXTURES + "surface_set_empty_kind.tres"
	var out: Array = []
	await assert_error(func() -> void: out.append(SurfaceSet.load_checked(path))).is_push_error(
		"SurfaceSet.load_checked: %s has a type with an empty kind at index 1" % path)
	assert_object(out[0]).is_null()


func test_surface_set_load_checked_duplicate_kind_returns_null() -> void:
	var path: String = FIXTURES + "surface_set_duplicate_kind.tres"
	var out: Array = []
	await assert_error(func() -> void: out.append(SurfaceSet.load_checked(path))).is_push_error(
		"SurfaceSet.load_checked: %s repeats kind road" % path)
	assert_object(out[0]).is_null()


func test_surface_set_load_checked_neutral_with_drag_returns_null() -> void:
	var path: String = FIXTURES + "surface_set_neutral_with_drag.tres"
	var out: Array = []
	await assert_error(func() -> void: out.append(SurfaceSet.load_checked(path))).is_push_error(
		"SurfaceSet.load_checked: %s neutral type road has drag = 0.5, not the default 0.0" % path)
	assert_object(out[0]).is_null()


func test_surface_set_load_checked_missing_path_reports_not_found() -> void:
	var out: Array = []
	await assert_error(func() -> void: out.append(SurfaceSet.load_checked(MISSING_PATH))).is_push_error(
		"SurfaceSet.load_checked: %s not found" % MISSING_PATH)
	assert_object(out[0]).is_null()


func test_surface_set_load_checked_other_resource_reports_wrong_type() -> void:
	var path: String = WallAttrSet.CORE_PATH
	var out: Array = []
	await assert_error(func() -> void: out.append(SurfaceSet.load_checked(path))).is_push_error(
		"SurfaceSet.load_checked: %s is not a SurfaceSet" % path)
	assert_object(out[0]).is_null()


# --- Frozen kinds unchanged -------------------------------------------------------------------

func test_core_frozen_kinds_handling_matches_frozen_set() -> void:
	# Arrange
	var core: SurfaceSet = SurfaceSet.load_checked(SurfaceSet.CORE_PATH)
	var frozen: SurfaceSet = load(FROZEN_SURFACE_SET_PATH) as SurfaceSet
	assert_object(core).is_not_null()
	assert_object(frozen).is_not_null()
	assert_int(frozen.types.size()).is_equal(FROZEN_KINDS.size())
	for kind in FROZEN_KINDS:
		# Act
		var core_type: SurfaceType = core.type_of(kind)
		var frozen_type: SurfaceType = frozen.type_of(kind)
		# Assert
		assert_object(core_type).override_failure_message("core has no %s" % kind).is_not_null()
		assert_object(frozen_type).override_failure_message("frozen has no %s" % kind).is_not_null()
		assert_bool(core_type.neutral).override_failure_message("%s neutral" % kind).is_false()
		for field in HANDLING_FIELDS:
			# A renamed field would read null on both sides and compare equal: require it exists.
			assert_bool(field in core_type).override_failure_message("core has no field %s" % field).is_true()
			assert_bool(field in frozen_type).override_failure_message("frozen has no field %s" % field).is_true()
			assert_that(core_type.get(field)).override_failure_message(
				"%s.%s: core %s, frozen %s" % [kind, field, core_type.get(field), frozen_type.get(field)]
			).is_equal(frozen_type.get(field))


# --- Wall attributes --------------------------------------------------------------------------

func test_core_wall_attr_set_holds_standard_and_rough() -> void:
	# Arrange / Act
	var walls: WallAttrSet = WallAttrSet.load_checked(WallAttrSet.CORE_PATH)
	# Assert
	assert_object(walls).is_not_null()
	assert_int(walls.attrs.size()).is_equal(PINNED_WALL_IDS.size())
	var seen: Dictionary[int, bool] = {}
	for a in walls.attrs:
		assert_int(a.id).is_between(0, WallAttrSet.MAX_ID)
		assert_bool(seen.has(a.id)).override_failure_message("id %d repeated" % a.id).is_false()
		seen[a.id] = true
	for attr_name in PINNED_WALL_IDS:
		var attr: WallAttr = walls.attr_of(attr_name)
		assert_object(attr).override_failure_message("no %s" % attr_name).is_not_null()
		assert_int(attr.id).is_equal(PINNED_WALL_IDS[attr_name])
		assert_float(attr.scrape_drag_mult).is_equal(PINNED_WALL_SCRAPE_DRAG[attr_name])


func test_wall_attr_has_drag_and_bounce_fields_and_no_opening_field() -> void:
	# Arrange
	var attr := WallAttr.new()
	# Act: names of its script variables
	var fields: Array[String] = []
	for p: Dictionary in attr.get_property_list():
		if p["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
			fields.append(p["name"])
	# Assert
	assert_array(fields).contains(["name", "id", "scrape_drag_mult", "bounce_mult"])
	assert_array(fields).not_contains(["opening"])
	assert_int(attr.id).is_equal(-1)


func test_wall_attr_of_unknown_name_returns_null() -> void:
	# Arrange
	var walls: WallAttrSet = WallAttrSet.load_checked(WallAttrSet.CORE_PATH)
	assert_object(walls).is_not_null()
	# Act / Assert: the importer passes the <name> of wall_<name>
	assert_object(walls.attr_of(&"no_such_wall")).is_null()
	assert_object(walls.attr_of(&"wall_standard")).is_null()
	assert_object(walls.attr_of(&"standard")).is_not_null()


func test_wall_attr_of_non_contiguous_id_finds_by_name() -> void:
	# Arrange
	var walls: WallAttrSet = WallAttrSet.load_checked(FIXTURES + "wall_attr_set_sparse_ids.tres")
	assert_object(walls).is_not_null()
	# Act
	var rough: WallAttr = walls.attr_of(&"rough")
	# Assert: the name finds it, whatever its id or array index
	assert_object(rough).is_not_null()
	assert_int(rough.id).is_equal(SPARSE_ROUGH_ID)


func test_wall_attr_set_load_checked_duplicate_id_returns_null() -> void:
	var path: String = FIXTURES + "wall_attr_set_duplicate_id.tres"
	var out: Array = []
	await assert_error(func() -> void: out.append(WallAttrSet.load_checked(path))).is_push_error(
		"WallAttrSet.load_checked: %s repeats wall-attribute id 0 (rough)" % path)
	assert_object(out[0]).is_null()


func test_wall_attr_set_load_checked_negative_id_returns_null() -> void:
	var path: String = FIXTURES + "wall_attr_set_negative_id.tres"
	var out: Array = []
	await assert_error(func() -> void: out.append(WallAttrSet.load_checked(path))).is_push_error(
		"WallAttrSet.load_checked: %s attribute rough has id -1, outside 0..255" % path)
	assert_object(out[0]).is_null()


func test_wall_attr_set_load_checked_id_over_max_returns_null() -> void:
	var path: String = FIXTURES + "wall_attr_set_id_over_max.tres"
	var out: Array = []
	await assert_error(func() -> void: out.append(WallAttrSet.load_checked(path))).is_push_error(
		"WallAttrSet.load_checked: %s attribute rough has id 256, outside 0..255" % path)
	assert_object(out[0]).is_null()


func test_wall_attr_set_load_checked_null_entry_returns_null() -> void:
	var path: String = FIXTURES + "wall_attr_set_null_entry.tres"
	var out: Array = []
	await assert_error(func() -> void: out.append(WallAttrSet.load_checked(path))).is_push_error(
		"WallAttrSet.load_checked: %s has a null attribute at index 1" % path)
	assert_object(out[0]).is_null()


func test_wall_attr_set_load_checked_empty_name_returns_null() -> void:
	var path: String = FIXTURES + "wall_attr_set_empty_name.tres"
	var out: Array = []
	await assert_error(func() -> void: out.append(WallAttrSet.load_checked(path))).is_push_error(
		"WallAttrSet.load_checked: %s has an attribute with an empty name at index 1" % path)
	assert_object(out[0]).is_null()


func test_wall_attr_set_load_checked_duplicate_name_returns_null() -> void:
	var path: String = FIXTURES + "wall_attr_set_duplicate_name.tres"
	var out: Array = []
	await assert_error(func() -> void: out.append(WallAttrSet.load_checked(path))).is_push_error(
		"WallAttrSet.load_checked: %s repeats name standard" % path)
	assert_object(out[0]).is_null()


func test_wall_attr_set_load_checked_missing_path_reports_not_found() -> void:
	var out: Array = []
	await assert_error(func() -> void: out.append(WallAttrSet.load_checked(MISSING_PATH))).is_push_error(
		"WallAttrSet.load_checked: %s not found" % MISSING_PATH)
	assert_object(out[0]).is_null()


func test_wall_attr_set_load_checked_other_resource_reports_wrong_type() -> void:
	var path: String = SurfaceSet.CORE_PATH
	var out: Array = []
	await assert_error(func() -> void: out.append(WallAttrSet.load_checked(path))).is_push_error(
		"WallAttrSet.load_checked: %s is not a WallAttrSet" % path)
	assert_object(out[0]).is_null()


# --- Additive shared-data change --------------------------------------------------------------

func test_surface_type_new_fields_have_defaults() -> void:
	# Arrange / Act
	var t := SurfaceType.new()
	# Assert
	assert_int(t.id).is_equal(-1)
	assert_bool(t.neutral).is_false()


func test_registry_scripts_are_tool_scripts() -> void:
	for path in TOOL_SCRIPT_PATHS:
		# Arrange / Act
		var script: Script = load(path) as Script
		# Assert
		assert_object(script).override_failure_message("cannot load %s" % path).is_not_null()
		assert_bool(script.is_tool()).override_failure_message("%s is not @tool" % path).is_true()


func test_core_neutral_kinds_hold_defaults_and_emit_no_puffs() -> void:
	# Arrange
	var core: SurfaceSet = SurfaceSet.load_checked(SurfaceSet.CORE_PATH)
	var defaults := SurfaceType.new()
	assert_object(core).is_not_null()
	for kind in NEUTRAL_KINDS:
		# Act
		var t: SurfaceType = core.type_of(kind)
		# Assert
		assert_object(t).override_failure_message("core has no %s" % kind).is_not_null()
		assert_bool(t.neutral).override_failure_message("%s neutral" % kind).is_true()
		for field in HANDLING_FIELDS:
			assert_that(t.get(field)).override_failure_message(
				"%s.%s: %s, default %s" % [kind, field, t.get(field), defaults.get(field)]
			).is_equal(defaults.get(field))
		# No puffs of their own, as slick (no "dust" from the field default).
		assert_that(t.effect).override_failure_message("%s effect" % kind).is_equal(&"none")
		assert_int(t.puff_amount).override_failure_message("%s puff_amount" % kind).is_equal(0)


func test_frozen_surface_set_new_fields_stay_default() -> void:
	# Arrange / Act
	var frozen: SurfaceSet = load(FROZEN_SURFACE_SET_PATH) as SurfaceSet
	# Assert: the frozen data is untouched by the additive fields
	assert_object(frozen).is_not_null()
	for t in frozen.types:
		assert_int(t.id).override_failure_message("%s id" % t.kind).is_equal(-1)
		assert_bool(t.neutral).override_failure_message("%s neutral" % t.kind).is_false()
