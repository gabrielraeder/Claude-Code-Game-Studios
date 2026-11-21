class_name PauseMenu
extends UiScreen
## The pause menu (Esc or Start during a race): Resume, Restart (offline only), Back to menu,
## Quit. Navigable with the keyboard, the mouse and the controller (ui_up / ui_down /
## ui_accept, Esc / Start / B closes). Emits signals only; the owner decides what they do.
## The start screen, lobby and results are their own screens (MainMenu, LobbyScreen, ResultsScreen).

## The player chose Resume, or pressed the pause action while the menu was open.
signal resume_requested
## The player chose Restart.
signal restart_requested
## The player chose Back to menu (leave the race for the start screen).
signal menu_requested
## The player chose Quit.
signal quit_requested

var _resume_button: Button
var _restart_button: Button
var _menu_button: Button
var _quit_button: Button


## Shows the menu; [param restart_available] shows the Restart button (offline only).
func open_pause(restart_available: bool) -> void:
	_restart_button.visible = restart_available
	open()


## The Resume button (debug scripts press it).
func resume_button() -> Button:
	return _resume_button


func _build(root: Control) -> void:
	_add_backdrop(ui.dim)
	var column: VBoxContainer = _centered_column(ui.gap)
	column.add_child(_banner(ui.t("pause_title"), ui.heading_font + 6))
	_resume_button = _add(column, "pause_resume", true, resume_requested)
	_restart_button = _add(column, "pause_restart", false, restart_requested)
	_menu_button = _add(column, "pause_menu", false, menu_requested)
	_quit_button = _add(column, "pause_quit", false, quit_requested)


func _on_open() -> void:
	_resume_button.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed(InputActions.PAUSE) or event.is_action_pressed(&"ui_cancel")):
		get_viewport().set_input_as_handled()
		resume_requested.emit()


func _add(parent: Control, text_key: String, primary_look: bool, target: Signal) -> Button:
	var b: Button = ui.button(ui.t(text_key), primary_look)
	b.pressed.connect(func() -> void: target.emit())
	parent.add_child(b)
	return b
