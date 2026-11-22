extends GdUnitTestSuite
## Core-rebuild story 066: gdUnit4 drives the native classes (DogworksCore, ToolchainProbe) from
## typed GDScript. Covers ADR-0007 Verification Required 1 (gdUnit4 drives a native class),
## 2 (typed factory, unbuilt .new(), per-method guards), 7 (marker functions) and 9 (class_call_static).
## Tests drive the real classes. mock() and spy() on a native class do not intercept native methods; the
## two tests at the end record what they do (see production/qa/evidence/core-rebuild-story-066/mock_spy_result.md).
##
## Story AC -> tests:
##   gdUnit4 drives a native class: every test below passes through the gdUnit4 runner
##   Construction and typed calls: test_validate_packed_*, test_create_*, test_unbuilt_*
##   Static call (VR 9): test_class_call_static_reaches_bind_static_method
##   RID teardown: test_dispose_*, test_dropping_*, test_live_rid_count_*

const _GUARD = preload("res://tests/unit/native/native_test_guard.gd")
const _BOOT = preload("res://src/core/native_boot_check.gd")

const VALID: PackedFloat64Array = [8.0, 1.0]
const UNBUILT_GUARD_ZERO: String = "Condition \"!built\" is true. Returning: 0"

## Probes a test made; after_test() disposes them (dispose() is idempotent).
var _probes: Array[ToolchainProbe] = []


## Collects the messages the engine's error handler delivers while a call runs.
class _ErrorCapture extends Logger:
	var messages: Array[String] = []

	func _log_error(_function: String, _file: String, _line: int, code: String, rationale: String, _editor_notify: bool, _error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		messages.append(code)
		messages.append(rationale)


func before() -> void:
	assert_str(_GUARD.problem()).is_empty()


func after_test() -> void:
	for probe: ToolchainProbe in _probes:
		probe.dispose()
	_probes.clear()


## Builds a probe from valid packed data and registers it for after_test() cleanup.
func _make(packed: PackedFloat64Array = VALID) -> ToolchainProbe:
	var probe: ToolchainProbe = ToolchainProbe.create(packed)
	_probes.append(probe)
	return probe


func test_sim_hz_is_60() -> void:
	var hz: int = DogworksCore.sim_hz()
	assert_int(hz).is_equal(60)


func test_sim_hz_times_boot_check_sim_dt_is_one() -> void:
	assert_float(DogworksCore.sim_hz() * _BOOT.SIM_DT).is_equal(1.0)


func test_boot_check_refuses_when_ticks_per_second_differs_from_sim_hz() -> void:
	var key: String = "physics/common/physics_ticks_per_second"
	var original: Variant = ProjectSettings.get_setting(key)
	ProjectSettings.set_setting(key, 30)
	var problem: String = _BOOT.check()
	ProjectSettings.set_setting(key, original)
	assert_str(problem).contains("physics_ticks_per_second")
	assert_str(_BOOT.check()).is_empty()


func test_class_call_static_reaches_bind_static_method() -> void:
	var via_class_db: Variant = ClassDB.class_call_static(&"DogworksCore", &"sim_hz")
	assert_int(via_class_db).is_equal(60)


func test_hashes_are_64_lowercase_hex_and_target_is_debug_slot() -> void:
	var rx: RegEx = RegEx.create_from_string("^[0-9a-f]{64}$")
	assert_bool(rx.search(DogworksCore.source_hash()) != null).is_true()
	assert_bool(rx.search(DogworksCore.build_hash()) != null).is_true()
	assert_str(DogworksCore.build_target()).is_equal("debug")


func test_dogworks_core_new_without_arguments_builds_an_object() -> void:
	var core: DogworksCore = DogworksCore.new()
	assert_object(core).is_not_null()


func test_validate_packed_accepts_valid_packed() -> void:
	var problem: String = ToolchainProbe.validate_packed(VALID)
	assert_str(problem).is_empty()


func test_validate_packed_names_the_bad_key() -> void:
	assert_str(ToolchainProbe.validate_packed(PackedFloat64Array([0.0, 1.0]))).contains("packed[0] output_length")
	assert_str(ToolchainProbe.validate_packed(PackedFloat64Array([8.0, 2.0]))).contains("packed[1] rid_servers")
	assert_str(ToolchainProbe.validate_packed(PackedFloat64Array([8.0]))).contains("expected 2 values")


func test_create_with_valid_packed_assigns_to_a_typed_local() -> void:
	var probe: ToolchainProbe = _make()
	assert_object(probe).is_not_null()
	assert_bool(probe.is_built()).is_true()
	assert_int(probe.rid_count()).is_equal(3)
	assert_int(probe.get_output_length()).is_equal(8)


func test_create_with_invalid_packed_returns_null_and_reports_the_validate_packed_message() -> void:
	var bad: PackedFloat64Array = PackedFloat64Array([0.0, 1.0])
	var expected: String = ToolchainProbe.validate_packed(bad)
	var capture: _ErrorCapture = _ErrorCapture.new()
	OS.add_logger(capture)
	var result: ToolchainProbe = ToolchainProbe.create(bad)
	OS.remove_logger(capture)
	assert_object(result).is_null()
	assert_array(capture.messages).contains([expected])
	# gdUnit4 would count the logged error as a failure of this test if it saw it; it matches the macro text.
	await assert_error(func() -> void: ToolchainProbe.create(bad)).is_push_error("Method/function failed. Returning: Ref<ToolchainProbe>()")


func test_unbuilt_new_object_reports_not_built() -> void:
	var probe: ToolchainProbe = ToolchainProbe.new()
	assert_bool(probe.is_built()).is_false()


func test_unbuilt_get_output_length_refuses() -> void:
	var probe: ToolchainProbe = ToolchainProbe.new()
	await assert_error(func() -> void: probe.get_output_length()).is_push_error(UNBUILT_GUARD_ZERO)


func test_unbuilt_echo_int_refuses() -> void:
	var probe: ToolchainProbe = ToolchainProbe.new()
	await assert_error(func() -> void: probe.echo_int(1)).is_push_error(UNBUILT_GUARD_ZERO)


func test_unbuilt_echo_scalar_refuses() -> void:
	var probe: ToolchainProbe = ToolchainProbe.new()
	await assert_error(func() -> void: probe.echo_scalar(1.0)).is_push_error("Condition \"!built\" is true. Returning: 0.0")


func test_unbuilt_echo_vector3_refuses() -> void:
	var probe: ToolchainProbe = ToolchainProbe.new()
	await assert_error(func() -> void: probe.echo_vector3(Vector3.ONE)).is_push_error("Condition \"!built\" is true. Returning: Vector3()")


func test_unbuilt_sum_packed_refuses() -> void:
	var probe: ToolchainProbe = ToolchainProbe.new()
	await assert_error(func() -> void: probe.sum_packed(PackedFloat32Array([1.0]))).is_push_error("Condition \"!built\" is true. Returning: 0.0")


func test_unbuilt_step_refuses() -> void:
	var probe: ToolchainProbe = ToolchainProbe.new()
	await assert_error(func() -> void: probe.step(0)).is_push_error("Condition \"!built\" is true.")


func test_unbuilt_output_refuses() -> void:
	var probe: ToolchainProbe = ToolchainProbe.new()
	await assert_error(func() -> void: probe.output()).is_push_error("Condition \"!built\" is true. Returning: PackedFloat32Array()")


func test_unbuilt_rid_count_refuses() -> void:
	var probe: ToolchainProbe = ToolchainProbe.new()
	await assert_error(func() -> void: probe.rid_count()).is_push_error(UNBUILT_GUARD_ZERO)


func test_unbuilt_dispose_is_a_silent_no_op() -> void:
	var probe: ToolchainProbe = ToolchainProbe.new()
	await assert_error(func() -> void: probe.dispose()).is_success()


func test_built_probe_echoes_scalar_vector_and_packed_values() -> void:
	var probe: ToolchainProbe = _make(PackedFloat64Array([4.0, 0.0]))
	assert_int(probe.echo_int(7)).is_equal(7)
	assert_float(probe.echo_scalar(2.5)).is_equal(2.5)
	assert_vector(probe.echo_vector3(Vector3(1, 2, 3))).is_equal(Vector3(1, 2, 3))
	assert_float(probe.sum_packed(PackedFloat32Array([1.0, 2.0, 3.0]))).is_equal(6.0)


func test_sum_packed_of_an_empty_array_is_zero_without_error() -> void:
	var probe: ToolchainProbe = _make(PackedFloat64Array([4.0, 0.0]))
	await assert_error(func() -> void: probe.sum_packed(PackedFloat32Array())).is_success()
	assert_float(probe.sum_packed(PackedFloat32Array())).is_equal(0.0)


func test_outputs_are_zero_filled_before_the_first_step() -> void:
	var probe: ToolchainProbe = _make(PackedFloat64Array([3.0, 0.0]))
	probe.step(0)
	probe.step(1)
	var odd: PackedFloat32Array = probe.output()
	probe.step(2)
	assert_array(odd).is_equal(PackedFloat32Array([0.5, 1.5, 2.5]))


func test_step_fills_alternating_buffers_and_output_returns_the_last_one() -> void:
	var probe: ToolchainProbe = _make(PackedFloat64Array([3.0, 0.0]))
	probe.step(2)
	var even: PackedFloat32Array = probe.output()
	probe.step(3)
	var odd: PackedFloat32Array = probe.output()
	assert_array(even).is_equal(PackedFloat32Array([1.0, 2.0, 3.0]))
	assert_array(odd).is_equal(PackedFloat32Array([1.5, 2.5, 3.5]))


func test_live_rid_count_rises_by_three_on_create_and_returns_to_baseline_after_dispose() -> void:
	var baseline: int = ToolchainProbe.live_rid_count()
	var probe: ToolchainProbe = _make()
	assert_int(ToolchainProbe.live_rid_count()).is_equal(baseline + 3)
	probe.dispose()
	assert_int(ToolchainProbe.live_rid_count()).is_equal(baseline)
	assert_bool(probe.is_built()).is_false()


func test_dispose_twice_is_silent_and_keeps_the_baseline() -> void:
	var baseline: int = ToolchainProbe.live_rid_count()
	var probe: ToolchainProbe = _make()
	probe.dispose()
	await assert_error(func() -> void: probe.dispose()).is_success()
	assert_int(ToolchainProbe.live_rid_count()).is_equal(baseline)


func test_dropping_the_last_reference_without_dispose_frees_the_rids() -> void:
	var baseline: int = ToolchainProbe.live_rid_count()
	var probe: ToolchainProbe = ToolchainProbe.create(VALID)
	assert_int(ToolchainProbe.live_rid_count()).is_equal(baseline + 3)
	probe = null
	assert_int(ToolchainProbe.live_rid_count()).is_equal(baseline)


func test_mock_of_native_class_does_not_intercept_bound_native_methods() -> void:
	# Observed (story 066, ADR-0007 Verification Required 1): mock() returns an object, but a call
	# to a bound native method goes to the native code (here the unbuilt guard fires), not to the
	# mock. So a mock cannot replace the native class: tests drive the real class.
	var mocked: ToolchainProbe = mock(ToolchainProbe)
	assert_object(mocked).is_not_null()
	await assert_error(func() -> void: mocked.echo_int(5)).is_push_error(UNBUILT_GUARD_ZERO)


func test_spy_of_a_built_native_object_is_an_unbuilt_copy() -> void:
	# Observed (story 066): spy() copies the object, so the spy is not the built original: its native
	# call hits the unbuilt guard and does not return the original's answer.
	var probe: ToolchainProbe = _make(PackedFloat64Array([4.0, 0.0]))
	var spied: ToolchainProbe = spy(probe)
	assert_object(spied).is_not_null()
	await assert_error(func() -> void: spied.echo_int(9)).is_push_error(UNBUILT_GUARD_ZERO)
