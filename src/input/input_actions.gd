class_name InputActions
extends RefCounted
## Registers the game's input actions in code (keyboard and controller) and names them.
## Implements design/game-brief.md, Controls. Menus use Godot's built-in ui_up, ui_down,
## ui_accept actions, which already map to the d-pad, stick and A button.

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
	_action(RESTART, [KEY_R], [], [])
	_action(PAUSE, [KEY_ESCAPE], [JOY_BUTTON_START], [])


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
