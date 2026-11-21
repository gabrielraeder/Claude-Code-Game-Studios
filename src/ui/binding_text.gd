class_name BindingText
extends RefCounted
## Names of the current bindings for the screen (story 007 part 3): key names from the OS
## (by the player's keyboard layout), controller buttons and axes from the UiTheme texts
## (joy_b_N, joy_a_N+ / joy_a_N-, joy_pair_N, key_<Name> overrides). Hint templates name actions
## instead of keys: "{k:accel/brake}" becomes the keyboard keys ("W/S"), "{p:accel/brake}" the
## controller inputs ("RT/LT"); one action lists all its inputs of the column, several actions
## list the first input of each, and a left/right pair on one stick collapses to "Left stick".
## "{k1:ui_accept}" / "{p1:...}" name only the first input of each action ("Enter").
## Display only: it reads the InputMap and changes nothing.

const _PLACEHOLDER: String = "\\{([kp])(1?):([A-Za-z_/]+)\\}"


## Fills every "{k:...}" and "{p:...}" placeholder of [param template] from the InputMap.
static func fill(template: String, ui: UiTheme) -> String:
	var re := RegEx.new()
	re.compile(_PLACEHOLDER)
	var out: String = ""
	var at: int = 0
	for m in re.search_all(template):
		out += template.substr(at, m.get_start() - at)
		var device: int = InputBindings.Device.KEYBOARD if m.get_string(1) == "k" else InputBindings.Device.CONTROLLER
		var actions: PackedStringArray = m.get_string(3).split("/", false)
		out += _actions_text(actions, device, ui, m.get_string(2) == "1")
		at = m.get_end()
	return out + template.substr(at)


## The inputs of [param action] in column [param device] as one text ("Space/Shift"), or the
## "none" text when it has none.
static func action_text(action: StringName, device: int, ui: UiTheme) -> String:
	var names: PackedStringArray = PackedStringArray()
	for e in InputBindings.events_of(action, device):
		names.append(event_name(e, ui))
	return "/".join(names) if not names.is_empty() else ui.t("key_none")


## Short name of one input: "W", "Space", "A", "RT", "Left stick left".
static func event_name(e: InputEvent, ui: UiTheme) -> String:
	if e is InputEventKey:
		var k := e as InputEventKey
		var code: Key = k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode
		if k.physical_keycode != KEY_NONE and DisplayServer.get_name() != "headless":
			code = DisplayServer.keyboard_get_keycode_from_physical(code)
		var key_name: String = OS.get_keycode_string(code)
		return _text_or(ui, "key_" + key_name, key_name)
	if e is InputEventJoypadButton:
		var b: int = int((e as InputEventJoypadButton).button_index)
		return _text_or(ui, "joy_b_%d" % b, ui.t("joy_button", [b]))
	if e is InputEventJoypadMotion:
		var m := e as InputEventJoypadMotion
		var sgn: String = "+" if m.axis_value > 0.0 else "-"
		return _text_or(ui, "joy_a_%d%s" % [int(m.axis), sgn], ui.t("joy_axis", [int(m.axis), sgn]))
	return e.as_text()


static func _actions_text(actions: PackedStringArray, device: int, ui: UiTheme, first_only: bool) -> String:
	if actions.size() == 1 and not first_only:
		return action_text(StringName(actions[0]), device, ui)
	var firsts: Array[InputEvent] = []
	var names: PackedStringArray = PackedStringArray()
	for a in actions:
		var evs: Array[InputEvent] = InputBindings.events_of(StringName(a), device)
		if evs.is_empty():
			names.append(ui.t("key_none"))
			firsts.append(null)
		else:
			names.append(event_name(evs[0], ui))
			firsts.append(evs[0])
	if firsts.size() == 2 and firsts[0] is InputEventJoypadMotion and firsts[1] is InputEventJoypadMotion:
		var a0 := firsts[0] as InputEventJoypadMotion
		var a1 := firsts[1] as InputEventJoypadMotion
		if a0.axis == a1.axis and signf(a0.axis_value) != signf(a1.axis_value) and ui.texts.has("joy_pair_%d" % int(a0.axis)):
			return ui.t("joy_pair_%d" % int(a0.axis))
	return "/".join(names)


static func _text_or(ui: UiTheme, key: String, fallback: String) -> String:
	return str(ui.texts[key]) if ui.texts.has(key) else fallback
