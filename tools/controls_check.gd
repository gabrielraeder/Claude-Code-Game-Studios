extends SceneTree
## Story 007 part 3: scripted check of the controls rebinding (InputBindings) without a window.
## Rebinds an action, checks the InputMap, triggers a keyboard and a controller swap, saves,
## resets, reloads from the file, resets to defaults, then feeds a corrupt file and a file with
## a bad entry (both must fall back to the defaults with a warning). Prints the HUD hint line
## before and after a rebind. Never touches user://controls.json.
##
## Usage: godot --headless --path . -s res://tools/controls_check.gd -- <scratch dir>
## Prints PASS / FAIL per check; exit 0 when all pass.

const UI_THEME_PATH: String = "res://assets/data/ui/ui_theme.tres"

var _fails: int = 0


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var dir: String = args[0] if not args.is_empty() else OS.get_user_data_dir() + "/controls_check"
	DirAccess.make_dir_recursive_absolute(dir)
	var path: String = dir + "/controls_check.json"
	var ui: UiTheme = load(UI_THEME_PATH) as UiTheme
	InputActions.register()
	var defaults: Dictionary = _snapshot()
	print("hints (defaults): ", BindingText.fill(ui.t("hud_hints"), ui).replace("\n", " | "))

	# 1. A plain rebind takes effect at once.
	var key_i := _key(KEY_I)
	var swapped: StringName = InputBindings.bind(InputActions.ACCEL, key_i)
	_check("rebind accel to I: no swap", swapped == &"")
	_check("rebind accel to I: keyboard is exactly [I]", _names(InputActions.ACCEL, 0) == ["I"])
	_check("rebind accel to I: Up arrow no longer drives", not _has_key(InputActions.ACCEL, KEY_UP))
	_check("rebind accel to I: controller column untouched", _names(InputActions.ACCEL, 1) == defaults[InputActions.ACCEL][1])
	print("hints (accel = I): ", BindingText.fill(ui.t("hud_hints"), ui).replace("\n", " | "))

	# 2. Keyboard conflict: Space belongs to drift, so accel and drift swap.
	swapped = InputBindings.bind(InputActions.ACCEL, _key(KEY_SPACE))
	_check("accel to Space swaps with drift", swapped == InputActions.DRIFT)
	_check("after swap accel = [Space]", _names(InputActions.ACCEL, 0) == ["Space"])
	_check("after swap drift has Shift and I, not Space", _has_key(InputActions.DRIFT, KEY_SHIFT) \
			and _has_key(InputActions.DRIFT, KEY_I) and not _has_key(InputActions.DRIFT, KEY_SPACE))
	_check("no input on two actions", _no_doubles())

	# 3. Controller conflict: the right trigger (accel) captured for item: they swap.
	var rt := InputEventJoypadMotion.new()
	rt.axis = JOY_AXIS_TRIGGER_RIGHT
	rt.axis_value = 0.83
	swapped = InputBindings.bind(InputActions.ITEM, rt)
	_check("item to RT swaps with accel", swapped == InputActions.ACCEL)
	_check("item controller = [RT]", _names(InputActions.ITEM, 1) == ["RT"])
	_check("accel controller = [LB]", _names(InputActions.ACCEL, 1) == ["LB"])
	_check("no input on two actions (controller)", _no_doubles())
	var bound: Dictionary = _snapshot()
	print("hints (after swaps): ", BindingText.fill(ui.t("hud_hints"), ui).replace("\n", " | "))

	# 4. Save, reset, reload: the custom bindings survive.
	_check("save ok", InputBindings.save(path) == OK)
	InputActions.reset_to_defaults()
	_check("reset restores the defaults", _snapshot() == defaults)
	var n: int = InputBindings.load_saved(path)
	_check("reload applies all %d actions" % InputActions.REBINDABLE.size(), n == InputActions.REBINDABLE.size())
	_check("reloaded bindings equal the saved ones", _snapshot() == bound)

	# 5. Reset to defaults again.
	InputActions.reset_to_defaults()
	_check("reset to defaults after reload", _snapshot() == defaults)

	# 6. A corrupt file falls back to the defaults (with a warning).
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("{\"version\": 1, \"actions\": {\"accel\": [[[ not json")
	f.close()
	n = InputBindings.load_saved(path)
	_check("corrupt file: nothing applied", n == 0)
	_check("corrupt file: defaults kept", _snapshot() == defaults)

	# 7. A readable file with one bad entry: that action keeps its defaults, the good one applies.
	f = FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"version": 1, "actions": {"accel": {"keys": "W"},
			"drift": {"keys": [int(KEY_J)], "buttons": [int(JOY_BUTTON_X)], "axes": []}}}))
	f.close()
	n = InputBindings.load_saved(path)
	_check("bad entry: one action applied", n == 1)
	_check("bad entry: accel keeps defaults", _names(InputActions.ACCEL, 0) == defaults[InputActions.ACCEL][0])
	_check("bad entry: drift = J / X", _names(InputActions.DRIFT, 0) == ["J"] and _names(InputActions.DRIFT, 1) == ["X"])

	# 8. A missing file: quietly nothing.
	InputActions.reset_to_defaults()
	n = InputBindings.load_saved(dir + "/no_such_file.json")
	_check("missing file: nothing applied, defaults kept", n == 0 and _snapshot() == defaults)

	print("RESULT: %s (%d failed)" % ["PASS" if _fails == 0 else "FAIL", _fails])
	quit(0 if _fails == 0 else 1)


func _check(label: String, ok: bool) -> void:
	print("%s: %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		_fails += 1


func _key(code: Key) -> InputEventKey:
	var k := InputEventKey.new()
	k.physical_keycode = code
	k.pressed = true
	return k


func _has_key(action: StringName, code: Key) -> bool:
	for e in InputBindings.events_of(action, InputBindings.Device.KEYBOARD):
		if (e as InputEventKey).physical_keycode == code:
			return true
	return false


# Names of an action's inputs in column [param device] (0 keyboard, 1 controller), headless-safe.
func _names(action: StringName, device: int) -> Array[String]:
	var ui: UiTheme = load(UI_THEME_PATH) as UiTheme
	var out: Array[String] = []
	for e in InputBindings.events_of(action, device):
		out.append(BindingText.event_name(e, ui))
	return out


func _snapshot() -> Dictionary:
	var d: Dictionary = {}
	for a: StringName in InputActions.REBINDABLE:
		d[a] = [_names(a, 0), _names(a, 1)]
	return d


func _no_doubles() -> bool:
	for a: StringName in InputActions.REBINDABLE:
		for e in InputMap.action_get_events(a):
			if InputBindings.device_of(e) >= 0 and InputBindings.owner_of(e, a) != &"":
				return false
	return true
