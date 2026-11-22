class_name CycleRow
extends Button
## A focusable row that cycles through choices: "Racer:  < Sunny >". Left / right (keyboard,
## d-pad, stick) step -1 / +1, accept steps +1, a mouse click on the left or right half steps
## back or forward. Shows no choice list itself; the owner keeps the value and calls
## [method show_value].

## The player asked for the previous (-1) or next (+1) choice.
signal stepped(direction: int)

var _caption: String = ""


## Sets the caption and the shown choice; [param arrows] false shows it as plain text
## (a client looking at the host's setup).
func show_value(caption: String, value: String, arrows: bool = true) -> void:
	_caption = caption
	text = ("%s   <  %s  >" if arrows else "%s:   %s") % [caption, value]


func _ready() -> void:
	alignment = HORIZONTAL_ALIGNMENT_CENTER
	pressed.connect(_on_pressed)


func _gui_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_left"):
		accept_event()
		stepped.emit(-1)
	elif event.is_action_pressed(&"ui_right"):
		accept_event()
		stepped.emit(1)
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		grab_focus()
		stepped.emit(-1 if (event as InputEventMouseButton).position.x < size.x * 0.5 else 1)


func _on_pressed() -> void:
	# Keyboard / controller accept (a mouse click is handled in _gui_input and never reaches here).
	stepped.emit(1)
