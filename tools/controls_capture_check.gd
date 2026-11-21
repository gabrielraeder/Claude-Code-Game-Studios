extends SceneTree
## Story 007 part 3: drives the controls screen with fake key / button / axis events (through
## Input.parse_input_event, the same path real presses take) and checks the capture states:
## Enter opens a capture without being captured itself, the next Enter is bound, Esc cancels,
## a trigger is captured on the controller column and swaps. Saves nothing.
##
## Usage: godot --headless --path . -s res://tools/controls_capture_check.gd
## Prints PASS / FAIL per check; exit 0 when all pass.

var _fails: int = 0
var _menu: ControlsMenu


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	InputActions.register()
	var ui: UiTheme = load("res://assets/data/ui/ui_theme.tres") as UiTheme
	_menu = ControlsMenu.new()
	root.add_child(_menu)
	_menu.setup(ui)
	_menu.save_path = ""
	_menu.open()
	await _frames(3)
	# 1. Enter on the focused Drive / Keyboard box: a capture starts; Enter itself is not bound.
	# (Buttons fire on release: the capture opens when Enter comes back up.)
	await _key(KEY_ENTER, true)
	await _key(KEY_ENTER, false)
	_check("Enter (press + release) starts a capture", _menu.is_capturing())
	_check("accel unchanged while capturing", _has_key(InputActions.ACCEL, KEY_W))
	# 2. The next Enter is the new key.
	await _key(KEY_ENTER, true)
	await _key(KEY_ENTER, false)
	_check("capture ended", not _menu.is_capturing())
	_check("accel keyboard = [Enter]", InputBindings.events_of(InputActions.ACCEL, InputBindings.Device.KEYBOARD).size() == 1 \
			and _has_key(InputActions.ACCEL, KEY_ENTER))
	print("status: ", _menu.status_text())
	# 3. Esc cancels a capture and changes nothing.
	await _key(KEY_ENTER, true)
	await _key(KEY_ENTER, false)
	_check("second capture started", _menu.is_capturing())
	await _key(KEY_ESCAPE, true)
	await _key(KEY_ESCAPE, false)
	_check("Esc cancels", not _menu.is_capturing() and _has_key(InputActions.ACCEL, KEY_ENTER) and not _has_key(InputActions.PAUSE, KEY_ENTER))
	print("status: ", _menu.status_text())
	# 4. Controller column: the right trigger (accel's) captured for drift swaps them.
	_menu.begin_capture(InputActions.DRIFT, InputBindings.Device.CONTROLLER)
	await _frames(2)
	var small := InputEventJoypadMotion.new()
	small.axis = JOY_AXIS_TRIGGER_RIGHT
	small.axis_value = 0.3
	Input.parse_input_event(small)
	await _frames(2)
	_check("a light trigger touch is not captured", _menu.is_capturing())
	var rt := InputEventJoypadMotion.new()
	rt.axis = JOY_AXIS_TRIGGER_RIGHT
	rt.axis_value = 0.95
	Input.parse_input_event(rt)
	await _frames(2)
	_check("RT captured for drift", not _menu.is_capturing() and _pad_names(InputActions.DRIFT) == ["RT"])
	_check("accel got drift's RB (swap)", _pad_names(InputActions.ACCEL) == ["RB"])
	print("status: ", _menu.status_text())
	# 5. A keyboard key while capturing the controller column is ignored (not bound there).
	_menu.begin_capture(InputActions.ITEM, InputBindings.Device.CONTROLLER)
	await _frames(2)
	await _key(KEY_Q, true)
	await _key(KEY_Q, false)
	_check("keyboard key ignored by a controller capture", _menu.is_capturing() and not _has_key(InputActions.ITEM, KEY_Q))
	var b := InputEventJoypadButton.new()
	b.button_index = JOY_BUTTON_Y
	b.pressed = true
	Input.parse_input_event(b)
	await _frames(2)
	_check("Y bound to item", _pad_names(InputActions.ITEM) == ["Y"])
	print("RESULT: %s (%d failed)" % ["PASS" if _fails == 0 else "FAIL", _fails])
	quit(0 if _fails == 0 else 1)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _key(code: Key, pressed: bool) -> void:
	var k := InputEventKey.new()
	k.physical_keycode = code
	k.keycode = code
	k.pressed = pressed
	Input.parse_input_event(k)
	await _frames(2)


func _check(label: String, ok: bool) -> void:
	print("%s: %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		_fails += 1


func _has_key(action: StringName, code: Key) -> bool:
	for e in InputBindings.events_of(action, InputBindings.Device.KEYBOARD):
		if (e as InputEventKey).physical_keycode == code:
			return true
	return false


func _pad_names(action: StringName) -> Array[String]:
	var ui: UiTheme = load("res://assets/data/ui/ui_theme.tres") as UiTheme
	var out: Array[String] = []
	for e in InputBindings.events_of(action, InputBindings.Device.CONTROLLER):
		out.append(BindingText.event_name(e, ui))
	return out
