class_name UiScreen
extends CanvasLayer
## Base of the full-screen menus (main menu, lobby, results, pause): a CanvasLayer holding one
## themed root Control that is scaled to the window height (the layout is designed at
## UiTheme.base_height). Subclasses build their content in [method _build]. Screens only
## show data and emit signals; the owner decides what a press does.

## The player pressed the "Sound: On/Off" button of this screen (screens that have one).
signal sound_toggle_requested

## Theme data (colours, sizes, text).
var ui: UiTheme
## Plays a UI sound by event name (&"ui_move", &"ui_accept", &"ui_back") through the audio
## event system; set by the owner (RaceFlowUi.set_sound_player). Empty = silent.
var sound_fn: Callable = Callable()
var _sound_button: Button
var _opened_frame: int = -1
## Root Control the content goes into; its size is the window size divided by the UI scale.
var _root: Control


## Builds the screen. Call once, after the node is in the tree.
func setup(theme_data: UiTheme) -> void:
	ui = theme_data
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = ui.screen_layer
	_root = Control.new()
	_root.theme = ui.build_theme()
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	get_viewport().size_changed.connect(_fit)
	get_viewport().gui_focus_changed.connect(_on_focus_changed)
	_build(_root)
	_fit()
	visible = false


## True while the screen is showing.
func is_open() -> bool:
	return visible


## Shows the screen.
func open() -> void:
	visible = true
	_opened_frame = Engine.get_process_frames()
	_fit()
	_on_open()


## Shows "Sound: On" or "Sound: Off" on this screen's sound button (if it has one).
func set_sound_state(muted: bool) -> void:
	if _sound_button != null:
		_sound_button.text = ui.t("sound_off" if muted else "sound_on")


## Hides the screen.
func close() -> void:
	visible = false


## Subclasses create their nodes under [param root] here.
func _build(_root_node: Control) -> void:
	pass


## Subclasses grab the first focus here.
func _on_open() -> void:
	pass


# Scales the layer so the layout always spans the window height the same way.
func _fit() -> void:
	if _root == null:
		return
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var s: float = maxf(vp.y / ui.base_height, 0.1)
	scale = Vector2(s, s)
	_root.position = Vector2.ZERO
	_root.size = vp / s


## Makes a full-window dim rectangle in [param color] under everything else.
func _add_backdrop(color: Color) -> void:
	var d := ColorRect.new()
	d.color = color
	d.set_anchors_preset(Control.PRESET_FULL_RECT)
	d.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(d)


## A full-window CenterContainer with a VBox in it (returned); the layout most screens use.
func _centered_column(separation: int) -> VBoxContainer:
	var c := CenterContainer.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(c)
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", separation)
	c.add_child(v)
	return v


## A parchment banner panel with [param text] as a heading (the logo's banner style).
func _banner(text: String, size: int) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override(&"panel", ui.box(ui.parchment, ui.ink, ui.border_width + 2, 22))
	var l := ui.label(text, size)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p.add_child(l)
	return p


## Adds the "Sound: On/Off" button to [param parent]; pressing it emits sound_toggle_requested.
func _add_sound_button(parent: Control) -> Button:
	_sound_button = ui.button(ui.t("sound_on"))
	_sound_button.pressed.connect(func() -> void: sound_toggle_requested.emit())
	parent.add_child(_sound_button)
	return _sound_button


# UI sounds, hooked once for every screen: a tick when the focus moves inside this screen (not
# the focus the screen grabs as it opens), accept when a focused button is pressed, back on ui_cancel.
func _on_focus_changed(control: Control) -> void:
	if not visible or control == null or not is_ancestor_of(control):
		return
	if control is BaseButton and not control.has_meta(&"ui_sound"):
		control.set_meta(&"ui_sound", true)
		(control as BaseButton).pressed.connect(func() -> void: _play_ui(&"ui_accept"))
	if Engine.get_process_frames() - _opened_frame > 1:
		_play_ui(&"ui_move")


func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed(&"ui_cancel") and not event.is_echo():
		_play_ui(&"ui_back")


func _play_ui(event_name: StringName) -> void:
	if sound_fn.is_valid():
		sound_fn.call(event_name)
