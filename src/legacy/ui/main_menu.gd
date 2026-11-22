class_name MainMenu
extends UiScreen
## The start screen: title banner, Solo / Host / Controls / Quit on the left, Join with an IP
## field and the recent hosts on the right. Works with mouse, keyboard (ui_up / ui_down /
## ui_accept) and controller (d-pad / stick / A). Emits signals only.

## Play offline against nobody (the old "Start").
signal solo_requested
## Host a lobby.
signal host_requested
## Join the host at [param address] ("ip" or "ip:port").
signal join_requested(address: String)
## The Controls button was pressed (RaceFlowUi opens the controls screen).
signal controls_requested
## Quit the game.
signal quit_requested

var _solo_button: Button
var _host_button: Button
var _controls_button: Button
var _quit_button: Button
var _ip_edit: LineEdit
var _join_button: Button
var _recent_box: VBoxContainer
var _status: Label
var _hint: Label


## The IP text field (debug scripts type into it).
func ip_edit() -> LineEdit:
	return _ip_edit


## The Host button (debug scripts press it).
func host_button() -> Button:
	return _host_button


## The Solo race button (debug scripts press it).
func solo_button() -> Button:
	return _solo_button


## The Join button (debug scripts press it).
func join_button() -> Button:
	return _join_button


## Enables or disables the Controls button (it starts disabled until the controls menu exists).
func set_controls_enabled(enabled: bool) -> void:
	_controls_button.disabled = not enabled


## Shows a message under the panels (a connection error, say); empty hides it.
func set_status(text: String) -> void:
	_status.text = text
	_status.visible = text != ""


## Reloads the recent host list and the IP field from disk.
func refresh_recent() -> void:
	var list: PackedStringArray = RecentHosts.load_list(ui.recent_file, ui.default_address, ui.recent_max)
	for c in _recent_box.get_children():
		_recent_box.remove_child(c)
		c.queue_free()
	for addr in list:
		var b: Button = ui.button(addr, false, true)
		b.custom_minimum_size = Vector2(0, ui.small_button_min.y)
		b.pressed.connect(func() -> void:
			_ip_edit.text = addr
			_join_button.grab_focus())
		_recent_box.add_child(b)
	_ip_edit.text = list[0]


func _build(root: Control) -> void:
	_add_backdrop(ui.backdrop)
	var column: VBoxContainer = _centered_column(ui.gap + 10)
	var title: PanelContainer = _banner(ui.t("title"), ui.title_font)
	column.add_child(title)
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", ui.gap + 6)
	column.add_child(row)

	var left_out: Array = []
	var left: PanelContainer = ui.panel(ui.gap, left_out)
	var lbox: VBoxContainer = left_out[0]
	left.custom_minimum_size = Vector2(340, 0)
	row.add_child(left)
	lbox.add_child(ui.label(ui.t("menu_play_heading"), ui.heading_font))
	_host_button = ui.button(ui.t("menu_host"), true)
	_host_button.pressed.connect(func() -> void: host_requested.emit())
	lbox.add_child(_host_button)
	_solo_button = ui.button(ui.t("menu_solo"))
	_solo_button.pressed.connect(func() -> void: solo_requested.emit())
	lbox.add_child(_solo_button)
	_controls_button = ui.button(ui.t("menu_controls"))
	_controls_button.disabled = true
	_controls_button.pressed.connect(func() -> void: controls_requested.emit())
	lbox.add_child(_controls_button)
	_add_sound_button(lbox)
	_quit_button = ui.button(ui.t("menu_quit"))
	_quit_button.pressed.connect(func() -> void: quit_requested.emit())
	lbox.add_child(_quit_button)

	var right_out: Array = []
	var right: PanelContainer = ui.panel(ui.gap - 4, right_out)
	var rbox: VBoxContainer = right_out[0]
	right.custom_minimum_size = Vector2(560, 0)
	row.add_child(right)
	rbox.add_child(ui.label(ui.t("menu_join_heading"), ui.heading_font))
	var join_row := HBoxContainer.new()
	join_row.add_theme_constant_override(&"separation", 10)
	rbox.add_child(join_row)
	_ip_edit = LineEdit.new()
	_ip_edit.placeholder_text = ui.t("menu_ip_placeholder")
	_ip_edit.custom_minimum_size = Vector2(300, ui.button_min.y)
	_ip_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ip_edit.text_submitted.connect(func(_t: String) -> void: _request_join())
	join_row.add_child(_ip_edit)
	_join_button = ui.button(ui.t("menu_join"))
	_join_button.custom_minimum_size = Vector2(140, ui.button_min.y)
	_join_button.pressed.connect(_request_join)
	join_row.add_child(_join_button)
	rbox.add_child(ui.label(ui.t("menu_recent"), ui.body_font, ui.ink_soft))
	_recent_box = VBoxContainer.new()
	_recent_box.add_theme_constant_override(&"separation", 6)
	rbox.add_child(_recent_box)

	_status = ui.label("", ui.body_font, ui.place_first)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.visible = false
	column.add_child(_status)
	_hint = ui.label("", ui.small_font, ui.parchment)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_hint)


func _on_open() -> void:
	refresh_recent()
	_hint.text = BindingText.fill(ui.t("menu_hint"), ui)
	_host_button.grab_focus()


func _request_join() -> void:
	var address: String = _ip_edit.text.strip_edges()
	if address == "":
		address = ui.default_address
	join_requested.emit(address)
