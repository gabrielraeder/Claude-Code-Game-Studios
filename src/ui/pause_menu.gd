class_name PauseMenu
extends CanvasLayer
## Plain start / pause menu: Resume (or Start), Restart, Quit. Navigable with the keyboard,
## the mouse and the controller through Godot's built-in ui_up, ui_down and ui_accept.
## Implements story 001 "Menus are reachable and usable from the controller too".
## Emits signals only; the owner decides what they do (no reference to game code).

## The player chose Resume / Start, or pressed the pause action while the menu was open.
signal resume_requested
## The player chose Restart.
signal restart_requested
## The player chose Quit.
signal quit_requested

const DIM_COLOR: Color = Color(0, 0, 0, 0.6)
const TITLE_SIZE: int = 48
const BUTTON_MIN_SIZE: Vector2 = Vector2(260, 48)
const MENU_LAYER: int = 10

var _title: Label
var _resume_button: Button
var _restart_button: Button
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
	_resume_button = _make_button(box, "Resume", resume_requested)
	_restart_button = _make_button(box, "Restart", restart_requested)
	_quit_button = _make_button(box, "Quit", quit_requested)
	visible = false


## True while the menu is showing.
func is_open() -> bool:
	return visible


## Shows the menu. [param title] is the heading; [param start_screen] makes the first
## button read "Start" and stops the pause action from closing it.
func open(title: String, start_screen: bool) -> void:
	_is_start_screen = start_screen
	_title.text = title
	_resume_button.text = "Start" if start_screen else "Resume"
	visible = true
	_resume_button.grab_focus()


## Hides the menu.
func close() -> void:
	visible = false


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
