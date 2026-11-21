class_name ControlsMenu
extends UiScreen
## The controls screen (story 007 part 3): one row per game action (InputActions.REBINDABLE),
## a Keyboard and a Controller column. Focus a box and press accept (Enter / A, or click it),
## then press the new key, button, stick direction or trigger: it replaces that action's inputs
## in that column at once. An input another action used is swapped with it (the status line
## says so). Esc or the controller's Back cancels a capture; it also times out. "Reset to
## defaults" restores InputActions' built-in keys. Every change is saved (InputBindings.save).
## Menus keep using the ui_* actions; only game actions are rebound.
##
## States: IDLE (navigate), ARMED (a capture was asked for; waits for the accept press that
## started it to be released, so Enter / A themselves can be bound), CAPTURE (the next input
## of the column is bound).

## The player pressed Back (or ui_cancel while not capturing).
signal back_requested
## A binding changed (rebind, swap or reset); hints that show keys should be rebuilt.
signal bindings_changed

enum State { IDLE, ARMED, CAPTURE }

## Where every change is saved; empty saves nothing (debug shots).
var save_path: String = InputBindings.DEFAULT_PATH

var _state: State = State.IDLE
var _action: StringName = &""
var _device: int = InputBindings.Device.KEYBOARD
var _capture_started_ms: int = 0
var _quiet_until_ms: int = 0
var _cells: Dictionary = {}
var _first_cell: Button
var _status: Label
var _hint: Label
var _reset_button: Button
var _back_button: Button


## True while a capture is armed or running.
func is_capturing() -> bool:
	return _state != State.IDLE


## Starts capturing a new input for [param action] in column [param device] (the same as
## pressing accept on its box). Debug scripts call it too.
func begin_capture(action: StringName, device: int) -> void:
	if not _cells.has(_cell_key(action, device)):
		return
	_action = action
	_device = device
	_state = State.ARMED
	_capture_started_ms = Time.get_ticks_msec()
	var press_key: String = "controls_press_key" if device == InputBindings.Device.KEYBOARD else "controls_press_pad"
	(_cells[_cell_key(action, device)] as Button).text = ui.t(press_key)
	_status.text = ui.t("controls_capture_status", [ui.t("action_" + String(action))])


## Binds [param e] to [param action] as if it had been captured (debug scripts), with the
## same swap, save and status message.
func apply_binding(action: StringName, e: InputEvent) -> void:
	_action = action
	_device = InputBindings.device_of(e)
	_finish_capture(e)


## The status line text (debug checks read it).
func status_text() -> String:
	return _status.text


func _build(root: Control) -> void:
	_add_backdrop(ui.backdrop)
	var column: VBoxContainer = _centered_column(ui.gap - 4)
	var head: PanelContainer = _banner(ui.t("controls_title"), ui.heading_font + 6)
	head.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(head)
	var info: Label = ui.label(ui.t("controls_info"), ui.small_font, ui.parchment)
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(info)
	var out: Array = []
	var panel: PanelContainer = ui.panel(4, out)
	var box: VBoxContainer = out[0]
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(panel)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override(&"h_separation", ui.gap)
	grid.add_theme_constant_override(&"v_separation", ui.controls_row_gap)
	box.add_child(grid)
	for title_key in ["controls_col_action", "controls_col_keyboard", "controls_col_pad"]:
		var h: Label = ui.label(ui.t(title_key), ui.small_font, ui.ink_soft)
		h.custom_minimum_size.x = ui.controls_action_width if title_key == "controls_col_action" else ui.controls_cell_size.x
		grid.add_child(h)
	for a: StringName in InputActions.REBINDABLE:
		var name_label: Label = ui.label(ui.t("action_" + String(a)), ui.body_font)
		name_label.custom_minimum_size = Vector2(ui.controls_action_width, ui.controls_cell_size.y)
		name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		grid.add_child(name_label)
		for device in [InputBindings.Device.KEYBOARD, InputBindings.Device.CONTROLLER]:
			var cell: Button = ui.button("", false, true)
			cell.custom_minimum_size = ui.controls_cell_size
			cell.add_theme_font_size_override(&"font_size", ui.controls_cell_font)
			var fills: Dictionary = {&"normal": ui.parchment, &"hover": ui.parchment.lightened(0.12),
					&"pressed": ui.parchment_dark, &"disabled": ui.disabled}
			for st: StringName in fills:
				var sb: StyleBoxFlat = ui.box(fills[st], ui.ink, ui.border_width - 1, 10)
				sb.content_margin_top = 2
				sb.content_margin_bottom = 2
				cell.add_theme_stylebox_override(st, sb)
			cell.clip_text = true
			cell.pressed.connect(begin_capture.bind(a, device))
			grid.add_child(cell)
			_cells[_cell_key(a, device)] = cell
			if _first_cell == null:
				_first_cell = cell
	_status = ui.label("", ui.body_font, ui.place_first)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_status)
	_hint = ui.label("", ui.small_font, ui.parchment)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_hint)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override(&"separation", ui.gap)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(buttons)
	_reset_button = ui.button(ui.t("controls_reset"))
	_reset_button.pressed.connect(_reset)
	buttons.add_child(_reset_button)
	_back_button = ui.button(ui.t("controls_back"), true)
	_back_button.pressed.connect(func() -> void: back_requested.emit())
	buttons.add_child(_back_button)


func _on_open() -> void:
	_state = State.IDLE
	_status.text = ""
	_refresh()
	_first_cell.grab_focus()


func close() -> void:
	if _state != State.IDLE:
		_cancel_capture()
	super.close()


# Shows every action's current inputs and the hint (with the menu keys).
func _refresh() -> void:
	for a: StringName in InputActions.REBINDABLE:
		for device in [InputBindings.Device.KEYBOARD, InputBindings.Device.CONTROLLER]:
			(_cells[_cell_key(a, device)] as Button).text = BindingText.action_text(a, device, ui)
	_hint.text = BindingText.fill(ui.t("controls_hint"), ui)


func _process(_delta: float) -> void:
	if not visible or _state == State.IDLE:
		return
	if _state == State.ARMED and not Input.is_action_pressed(&"ui_accept") \
			and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_state = State.CAPTURE
	if float(Time.get_ticks_msec() - _capture_started_ms) > ui.controls_capture_timeout * 1000.0:
		_cancel_capture()
		_status.text = ui.t("controls_timed_out")


# While capturing, every key, button, axis and click goes here first and no further.
func _input(event: InputEvent) -> void:
	if not visible:
		return
	if _state == State.IDLE:
		if Time.get_ticks_msec() < _quiet_until_ms and event is InputEventJoypadMotion:
			get_viewport().set_input_as_handled()  # the stick that was just bound is still held
			return
		super._input(event)
		return
	var device: int = InputBindings.device_of(event)
	if device < 0 and not (event is InputEventMouseButton):
		return
	get_viewport().set_input_as_handled()
	if _state != State.CAPTURE or event.is_echo():
		return
	if _is_cancel(event):
		_cancel_capture()
		_status.text = ui.t("controls_cancelled")
		_play_ui(&"ui_back")
		return
	if device != _device:
		return
	if event is InputEventJoypadMotion:
		if absf((event as InputEventJoypadMotion).axis_value) < ui.controls_axis_threshold:
			return
	elif not event.is_pressed():
		return
	_finish_capture(event)


func _unhandled_input(event: InputEvent) -> void:
	if visible and _state == State.IDLE and event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		back_requested.emit()


# Esc, the controller's Back button or a mouse click ends a capture without binding.
func _is_cancel(event: InputEvent) -> bool:
	if not event.is_pressed():
		return false
	if event is InputEventKey:
		return (event as InputEventKey).physical_keycode == KEY_ESCAPE or (event as InputEventKey).keycode == KEY_ESCAPE
	if event is InputEventJoypadButton:
		return (event as InputEventJoypadButton).button_index == JOY_BUTTON_BACK
	return event is InputEventMouseButton


func _finish_capture(e: InputEvent) -> void:
	_state = State.IDLE
	_quiet_until_ms = Time.get_ticks_msec() + ui.controls_quiet_ms
	var clean: InputEvent = InputBindings.normalized(e)
	if clean == null:
		_refresh()
		return
	var swapped: StringName = InputBindings.bind(_action, clean)
	InputBindings.save(save_path)
	_refresh()
	var action_name: String = ui.t("action_" + String(_action))
	if swapped != &"":
		_status.text = ui.t("controls_swapped", [action_name, ui.t("action_" + String(swapped))])
	else:
		_status.text = ui.t("controls_bound", [action_name, BindingText.event_name(clean, ui)])
	print("[controls] %s %s -> %s%s" % [String(_action), "keyboard" if _device == InputBindings.Device.KEYBOARD else "controller",
			BindingText.event_name(clean, ui), (" (swapped with %s)" % swapped) if swapped != &"" else ""])
	_play_ui(&"ui_accept")
	bindings_changed.emit()


func _cancel_capture() -> void:
	_state = State.IDLE
	_refresh()


func _reset() -> void:
	InputActions.reset_to_defaults()
	InputBindings.save(save_path)
	_refresh()
	_status.text = ui.t("controls_reset_done")
	print("[controls] reset to defaults")
	bindings_changed.emit()


func _cell_key(action: StringName, device: int) -> String:
	return "%s/%d" % [action, device]
