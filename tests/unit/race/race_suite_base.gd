extends GdUnitTestSuite
## Shared base of the race-tick suites (core-rebuild story 068). It names no native class: each suite that does
## preloads native_test_guard.gd and calls it in before(). Holds the refusal helper (an ERR_FAIL is an engine
## error: the logger sees its text, and gdUnit4 needs assert_error to accept it) and the tick driver.

const SIM_HZ_DT: float = 1.0 / 60.0


## Collects the messages the engine's error handler delivers while a call runs.
class ErrorCapture extends Logger:
	var messages: Array[String] = []

	func _log_error(_function: String, _file: String, _line: int, code: String, rationale: String, _editor_notify: bool, _error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		messages.append(code)
		messages.append(rationale)


## Runs [param call] once with the logger attached, asserts that the engine reported an error whose text contains
## [param fragment], then runs it again under assert_error so gdUnit4 accepts the error. Refusals must leave the
## state unchanged, so the second run refuses the same way.
func refuses(call: Callable, fragment: String) -> void:
	var capture: ErrorCapture = ErrorCapture.new()
	OS.add_logger(capture)
	call.call()
	OS.remove_logger(capture)
	assert_bool(capture.messages.is_empty()).is_false()
	var found: bool = false
	for text: String in capture.messages:
		if text.contains(fragment):
			found = true
	assert_bool(found).override_failure_message("no engine error contains '%s'; got %s" % [fragment, capture.messages]).is_true()
	await assert_error(call).is_push_error(capture.messages[0])


## Zero rows for [param local] driver rows.
func driver_rows(local: int, steer: float = 0.0) -> PackedFloat32Array:
	var rows: PackedFloat32Array = PackedFloat32Array()
	rows.resize(local * RaceLayout.DRIVER_STRIDE)
	rows.fill(0.0)
	for i in local:
		rows[i * RaceLayout.DRIVER_STRIDE + RaceLayout.DRIVER_STEER] = steer
	return rows


## Zero rows (identity basis) for [param remote] remote rows.
func remote_rows(remote: int) -> PackedFloat32Array:
	var rows: PackedFloat32Array = PackedFloat32Array()
	rows.resize(remote * RaceLayout.REMOTE_STRIDE)
	rows.fill(0.0)
	for i in remote:
		var base: int = i * RaceLayout.REMOTE_STRIDE + RaceLayout.SNAP_BASIS
		rows[base] = 1.0
		rows[base + 4] = 1.0
		rows[base + 8] = 1.0
	return rows


## A valid setup dictionary for [param roles].
func setup_for(roles: PackedInt32Array, capacity: int = 4) -> Dictionary:
	return {
		"schema_version": RaceLayout.SETUP_SCHEMA_VERSION,
		"slot_count": roles.size(),
		"slot_roles": roles,
		"seeds": PackedInt64Array([11, 22, 33]),
		"event_capacity": capacity,
	}
