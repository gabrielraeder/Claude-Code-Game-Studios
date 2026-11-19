class_name InputActions
extends RefCounted
## Registers the game's input actions in code (keyboard and controller) and names them.
## Implements design/game-brief.md, Controls. Menus use Godot's built-in ui_* actions.
## Godot's defaults map ui_up/ui_down to the d-pad and left stick, but give ui_accept and
## ui_cancel no controller button, so register() adds A (accept) and B (cancel).

const ACCEL: StringName = &"accel"
const BRAKE: StringName = &"brake"
const STEER_LEFT: StringName = &"steer_left"
const STEER_RIGHT: StringName = &"steer_right"
const DRIFT: StringName = &"drift"
const ITEM: StringName = &"item"
const RESTART: StringName = &"restart"
const PAUSE: StringName = &"pause"

## Stick and trigger deadzone (axis values below this read as zero).
const AXIS_DEADZONE: float = 0.2


## Adds every game action to the InputMap. Safe to call more than once.
static func register() -> void:
	_action(ACCEL, [KEY_W, KEY_UP], [], [[JOY_AXIS_TRIGGER_RIGHT, 1.0]])
	_action(BRAKE, [KEY_S, KEY_DOWN], [], [[JOY_AXIS_TRIGGER_LEFT, 1.0]])
	_action(STEER_LEFT, [KEY_A, KEY_LEFT], [], [[JOY_AXIS_LEFT_X, -1.0]])
	_action(STEER_RIGHT, [KEY_D, KEY_RIGHT], [], [[JOY_AXIS_LEFT_X, 1.0]])
	_action(DRIFT, [KEY_SPACE, KEY_SHIFT], [JOY_BUTTON_RIGHT_SHOULDER], [])
	_action(ITEM, [KEY_E, KEY_CTRL], [JOY_BUTTON_LEFT_SHOULDER], [])
	# Restart on the finish screen only (main checks); no keyboard key. Enter/A use ui_accept.
	_action(RESTART, [], [JOY_BUTTON_START], [])
	_action(PAUSE, [KEY_ESCAPE], [JOY_BUTTON_START], [])
	_add_button(&"ui_accept", JOY_BUTTON_A)
	_add_button(&"ui_cancel", JOY_BUTTON_B)


## Adds a controller button to an existing action unless it is already there.
static func _add_button(action: StringName, button: JoyButton) -> void:
	var e := InputEventJoypadButton.new()
	e.button_index = button
	if InputMap.has_action(action) and not InputMap.action_has_event(action, e):
		InputMap.action_add_event(action, e)


static func _action(action: StringName, keys: Array, buttons: Array, axes: Array) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action, AXIS_DEADZONE)
	for k in keys:
		var e := InputEventKey.new()
		e.physical_keycode = k as Key
		InputMap.action_add_event(action, e)
	for b in buttons:
		var e := InputEventJoypadButton.new()
		e.button_index = b as JoyButton
		InputMap.action_add_event(action, e)
	for a: Array in axes:
		var e := InputEventJoypadMotion.new()
		e.axis = a[0] as JoyAxis
		e.axis_value = a[1]
		InputMap.action_add_event(action, e)
