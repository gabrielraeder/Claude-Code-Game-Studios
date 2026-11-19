class_name PauseMenu
extends CanvasLayer
## Plain start / pause menu: Resume (or Start), Host, Join (with an IP field), Restart,
## Back to menu, Quit.
## Navigable with the keyboard, the mouse and the controller through Godot's built-in
## ui_up, ui_down and ui_accept. Host and Join show only on the start screen (story 002;
## the real lobby screen is story 007). Emits signals only; the owner decides what they do.

## The player chose Resume / Start, or pressed the pause action while the menu was open.
signal resume_requested
## The player chose Restart.
signal restart_requested
## The player chose Back to menu (leave the race or lobby for the start screen).
signal menu_requested
## The player chose Quit.
signal quit_requested
## The player chose Host.
signal host_requested
## The player chose Join; [param address] is the text in the IP field.
signal join_requested(address: String)

const DIM_COLOR: Color = Color(0, 0, 0, 0.6)
const TITLE_SIZE: int = 48
const STATUS_SIZE: int = 22
const BUTTON_MIN_SIZE: Vector2 = Vector2(260, 48)
const MENU_LAYER: int = 10
const DEFAULT_ADDRESS: String = "127.0.0.1"

var _title: Label
var _status: Label
var _resume_button: Button
var _host_button: Button
var _ip_edit: LineEdit
var _join_button: Button
var _restart_button: Button
var _menu_button: Button
var _quit_button: Button
var _is_start_screen: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = MENU_LAYER
	var dim := ColorRect.new()
	dim.color = DIM_COLOR
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	center.add_child(box)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", TITLE_SIZE)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_title)
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", STATUS_SIZE)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.visible = false
	box.add_child(_status)
	_resume_button = _make_button(box, "Resume", resume_requested)
	_host_button = _make_button(box, "Host", host_requested)
	_ip_edit = LineEdit.new()
	_ip_edit.text = DEFAULT_ADDRESS
	_ip_edit.placeholder_text = "Host IP (Tailscale 100.x or LAN)"
	_ip_edit.custom_minimum_size = BUTTON_MIN_SIZE
	box.add_child(_ip_edit)
	_join_button = Button.new()
	_join_button.text = "Join"
	_join_button.custom_minimum_size = BUTTON_MIN_SIZE
	_join_button.pressed.connect(func() -> void: join_requested.emit(_ip_edit.text.strip_edges()))
	box.add_child(_join_button)
	_restart_button = _make_button(box, "Restart", restart_requested)
	_menu_button = _make_button(box, "Back to menu", menu_requested)
	_quit_button = _make_button(box, "Quit", quit_requested)
	visible = false


## True while the menu is showing.
func is_open() -> bool:
	return visible


## Shows the menu. [param title] is the heading; [param start_screen] makes the first
## button read "Start", shows Host / Join and stops the pause action from closing it.
func open(title: String, start_screen: bool) -> void:
	_is_start_screen = start_screen
	_title.text = title
	_resume_button.text = "Start" if start_screen else "Resume"
	_resume_button.visible = true
	set_net_buttons_visible(start_screen)
	_restart_button.visible = true
	_menu_button.visible = not start_screen
	set_status("")
	visible = true
	_resume_button.grab_focus()


## Hides the menu.
func close() -> void:
	visible = false


## Shows or hides Host, the IP field and Join.
func set_net_buttons_visible(shown: bool) -> void:
	_host_button.visible = shown
	_ip_edit.visible = shown
	_join_button.visible = shown
	# In a lobby (start screen without Host / Join) Back to menu cancels hosting or joining.
	if _is_start_screen:
		_menu_button.visible = not shown


## Sets the line under the title (hidden when empty).
func set_status(text: String) -> void:
	_status.text = text
	_status.visible = text != ""


## Relabels the first button and shows or hides it (the host's "Start race", hidden while joining).
func set_primary_button(text: String, shown: bool) -> void:
	_resume_button.text = text
	_resume_button.visible = shown
	if shown:
		_resume_button.grab_focus()
	elif _menu_button.visible:
		_menu_button.grab_focus()
	else:
		_quit_button.grab_focus()


## Shows or hides the Restart button (restart is offline only).
func set_restart_visible(shown: bool) -> void:
	_restart_button.visible = shown


func _unhandled_input(event: InputEvent) -> void:
	if visible and not _is_start_screen and (event.is_action_pressed(InputActions.PAUSE) or event.is_action_pressed(&"ui_cancel")):
		get_viewport().set_input_as_handled()
		resume_requested.emit()


func _make_button(parent: Control, label: String, target: Signal) -> Button:
	var b := Button.new()
	b.text = label
	b.custom_minimum_size = BUTTON_MIN_SIZE
	b.pressed.connect(func() -> void: target.emit())
	parent.add_child(b)
	return b
