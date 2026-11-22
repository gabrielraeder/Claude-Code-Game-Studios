extends "res://tests/unit/race/race_suite_base.gd"
## Core-rebuild story 068, criterion "Factory and setup" (ADR-0007 section 3 Slot roles; section 4 Construction pattern):
## validate_packed and create share one validation, a negative test per setup key, an unbuilt object refuses every bound
## method (one parameterised case per method), dispose is idempotent, slot_roles has no setter.

const _GUARD = preload("res://tests/unit/native/native_test_guard.gd")

const ROLES: PackedInt32Array = [0, 1, 2, 0]
const KEYS: PackedStringArray = ["schema_version", "slot_count", "slot_roles", "seeds", "event_capacity"]

var _sims: Array[RaceSim] = []


func before() -> void:
	assert_str(_GUARD.problem()).is_empty()


func after_test() -> void:
	for sim: RaceSim in _sims:
		sim.dispose()
	_sims.clear()


func _make(roles: PackedInt32Array = ROLES, capacity: int = 4) -> RaceSim:
	var sim: RaceSim = RaceSim.create(setup_for(roles, capacity))
	assert_object(sim).is_not_null()
	_sims.append(sim)
	return sim


func test_valid_setup_validates_to_empty_string() -> void:
	assert_str(RaceSim.validate_packed(setup_for(ROLES))).is_empty()


func test_missing_key_is_refused_with_the_key_name(key: String, test_parameters := [["schema_version"], ["slot_count"], ["slot_roles"], ["seeds"], ["event_capacity"]]) -> void:
	var setup: Dictionary = setup_for(ROLES)
	setup.erase(key)
	var problem: String = RaceSim.validate_packed(setup)
	assert_str(problem).contains(key)
	assert_str(problem).contains("missing")


func test_wrong_typed_key_is_refused_with_the_key_name(key: String, bad: Variant, test_parameters := [
	["schema_version", "1"], ["slot_count", 4.0], ["slot_roles", PackedInt64Array([0])], ["seeds", PackedInt32Array([1])], ["event_capacity", "4"]]) -> void:
	var setup: Dictionary = setup_for(ROLES)
	setup[key] = bad
	var problem: String = RaceSim.validate_packed(setup)
	assert_str(problem).contains(key)
	assert_str(problem).contains("wrong type")


func test_bad_values_are_refused_with_the_key_name(key: String, bad: Variant, test_parameters := [
	["schema_version", 2], ["slot_count", 0], ["slot_count", 33], ["slot_roles", PackedInt32Array([0, 1])],
	["slot_roles", PackedInt32Array([0, 1, 3, 0])], ["seeds", PackedInt64Array()], ["event_capacity", 0], ["event_capacity", 4097]]) -> void:
	var setup: Dictionary = setup_for(ROLES)
	setup[key] = bad
	assert_str(RaceSim.validate_packed(setup)).contains(key)


func test_unknown_key_is_refused_with_its_name() -> void:
	var setup: Dictionary = setup_for(ROLES)
	setup["slot_cuont"] = 4
	assert_str(RaceSim.validate_packed(setup)).contains("slot_cuont")


func test_create_with_a_bad_setup_returns_null_and_reports_the_same_text() -> void:
	var setup: Dictionary = setup_for(ROLES)
	setup.erase("seeds")
	var problem: String = RaceSim.validate_packed(setup)
	assert_str(problem).is_not_empty()
	var capture: ErrorCapture = ErrorCapture.new()
	OS.add_logger(capture)
	var sim: RaceSim = RaceSim.create(setup)
	OS.remove_logger(capture)
	assert_object(sim).is_null()
	assert_array(capture.messages).contains([problem])
	await assert_error(func() -> void: RaceSim.create(setup)).is_push_error(capture.messages[0])


func test_create_sizes_every_buffer_and_reports_setup_facts() -> void:
	var sim: RaceSim = _make()
	assert_bool(sim.is_built()).is_true()
	assert_int(sim.slot_count()).is_equal(4)
	assert_int(sim.local_slot_count()).is_equal(2)
	assert_int(sim.event_capacity()).is_equal(4)
	assert_int(sim.consumer_count()).is_equal(3)
	assert_int(sim.consumer_seed(1)).is_equal(22)
	assert_array(sim.slot_roles()).is_equal(ROLES)
	assert_int(sim.snapshots().size()).is_equal(4 * RaceLayout.SNAP_STRIDE)
	assert_int(sim.progress().size()).is_equal(4 * RaceLayout.PROG_STRIDE)
	assert_int(sim.stage_usec().size()).is_equal(RaceLayout.STAGE_COUNT)
	assert_int(sim.event_headers().size()).is_equal(4 * RaceLayout.EVENT_HEADER_STRIDE)
	assert_int(sim.event_payload().size()).is_equal(4 * RaceLayout.EVENT_PAYLOAD_MAX)
	assert_int(int(sim.snapshots()[RaceLayout.SNAP_TICK])).is_equal(-1)


func test_slot_roles_has_no_setter_and_returns_a_copy() -> void:
	var methods: PackedStringArray = PackedStringArray()
	for entry: Dictionary in ClassDB.class_get_method_list(&"RaceSim", true):
		methods.append(entry["name"])
	assert_bool(methods.has("set_slot_roles")).is_false()
	assert_bool(methods.has("slot_roles")).is_true()
	var sim: RaceSim = _make()
	var roles: PackedInt32Array = sim.slot_roles()
	roles[0] = 2
	assert_array(sim.slot_roles()).is_equal(ROLES)


func test_new_object_is_unbuilt() -> void:
	assert_bool(RaceSim.new().is_built()).is_false()


func test_unbuilt_dispose_is_a_silent_no_op() -> void:
	var sim: RaceSim = RaceSim.new()
	await assert_error(func() -> void: sim.dispose()).is_success()


func test_dispose_twice_is_silent_and_later_calls_refuse() -> void:
	var live_before: int = RaceSim.live_count()
	var sim: RaceSim = _make()
	assert_int(RaceSim.live_count()).is_equal(live_before + 1)
	sim.dispose()
	assert_int(RaceSim.live_count()).is_equal(live_before)
	await assert_error(func() -> void: sim.dispose()).is_success()
	assert_bool(sim.is_built()).is_false()
	await refuses(func() -> void: sim.begin_tick(0), "not built")


## One case per bound method (the exempt ones, is_built and dispose, have their own tests above).
func test_unbuilt_method_refuses(method: String, args: Array, test_parameters := [
	["begin_tick", [0]], ["apply_events", [PackedInt32Array(), PackedFloat32Array()]], ["step_drive", [PackedFloat32Array()]],
	["step_bodies", []], ["set_remote", [PackedFloat32Array(), 0]], ["step_contact", []], ["step_progress_items_hazards", []],
	["end_tick", []], ["place", [0, PackedFloat32Array()]], ["hold", [0]], ["snapshots", []], ["progress", []], ["stage_usec", []],
	["event_headers", []], ["event_payload", []], ["event_count", []], ["events_overflowed", []], ["snapshot_position", [0]],
	["snapshot_basis", [0]], ["snapshot_velocity", [0]], ["snapshot_speed", [0]], ["snapshot_flags", [0]], ["progress_distance", [0]],
	["progress_lap", [0]], ["progress_rank", [0]], ["slot_count", []], ["slot_roles", []], ["local_slot_count", []],
	["event_capacity", []], ["consumer_count", []], ["consumer_seed", [0]], ["tick", []], ["tick_time", []],
	["debug_emit_event", [0, 1, PackedFloat32Array([1.0])]], ["debug_write_progress", [0, 0, 1.0]], ["debug_drive_rows", [0]],
	["debug_start_rows", [0]], ["debug_integrated", [0]], ["debug_bot_decisions", [0]]]) -> void:
	var sim: RaceSim = RaceSim.new()
	await refuses(Callable(sim, method).bindv(args), "not built")


func test_every_bound_method_has_an_unbuilt_refusal_case() -> void:
	var exempt: PackedStringArray = ["is_built", "dispose"]
	var covered: PackedStringArray = PackedStringArray(["begin_tick", "apply_events", "step_drive", "step_bodies", "set_remote", "step_contact",
		"step_progress_items_hazards", "end_tick", "place", "hold", "snapshots", "progress", "stage_usec", "event_headers", "event_payload",
		"event_count", "events_overflowed", "snapshot_position", "snapshot_basis", "snapshot_velocity", "snapshot_speed", "snapshot_flags",
		"progress_distance", "progress_lap", "progress_rank", "slot_count", "slot_roles", "local_slot_count", "event_capacity",
		"consumer_count", "consumer_seed", "tick", "tick_time", "debug_emit_event", "debug_write_progress", "debug_drive_rows",
		"debug_start_rows", "debug_integrated", "debug_bot_decisions"])
	for entry: Dictionary in ClassDB.class_get_method_list(&"RaceSim", true):
		var name: String = entry["name"]
		if (entry["flags"] as int) & METHOD_FLAG_STATIC:
			continue
		assert_bool(exempt.has(name) or covered.has(name)).override_failure_message("bound method %s has no unbuilt refusal case" % name).is_true()
