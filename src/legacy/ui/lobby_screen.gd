class_name LobbyScreen
extends UiScreen
## The lobby, for the host and for clients: a roster (one row per human), your own racer and
## vehicle pick with a turning 3D preview, and the race setup (track, bots, laps) that only the
## host can change. The host starts when every client is ready; a client toggles Ready.
## It shows a [LobbyState] and emits what the player asked for; Main owns the state and
## the network messages.

## The player changed their own racer or vehicle.
signal pick_changed(racer: int, vehicle: int)
## A client toggled Ready.
signal ready_toggled(is_ready: bool)
## The host asked for the previous (-1) or next (+1) track, bots count or laps.
signal track_stepped(direction: int)
signal bots_stepped(direction: int)
signal laps_stepped(direction: int)
## The host pressed Start.
signal start_requested
## The player pressed Leave (or Esc / B).
signal leave_requested

## Roster column widths in base pixels: swatch, player, role, racer, vehicle, status.
const COLUMN_WIDTHS: Array[int] = [26, 110, 92, 150, 150, 100]

var _racers: RacerSet
var _vehicles: VehicleSet
var _colors: PackedColorArray = PackedColorArray()
var _max_racers: int = 12
var _state: LobbyState = LobbyState.new()
var _my_peer: int = 1
var _is_host: bool = false
var _racer: int = 0
var _vehicle: int = 0
var _ready_local: bool = false
var _preview_key: Vector3i = Vector3i(-1, -1, -1)
var _roster_box: VBoxContainer
var _total_label: Label
var _preview: KartPreview
var _racer_row: CycleRow
var _vehicle_row: CycleRow
var _track_row: CycleRow
var _bots_row: CycleRow
var _laps_row: CycleRow
var _racer_info: Label
var _action_button: Button
var _leave_button: Button
var _status: Label
var _info: Label
var _offline: bool = false
var _title_label: Label
var _setup_heading: Label
var _roster_panel: PanelContainer
var _setup_panel: PanelContainer
var _left: VBoxContainer
var _right: VBoxContainer


## Builds the screen with the rosters it needs. [param colors] is the slot palette, [param max_racers] the race total.
func setup_lobby(theme_data: UiTheme, racers: RacerSet, vehicles: VehicleSet, colors: PackedColorArray, max_racers: int) -> void:
	_racers = racers
	_vehicles = vehicles
	_colors = colors
	_max_racers = max_racers
	setup(theme_data)


## Offline mode (the solo setup): title "Solo race", no roster, no Ready; the race setup moves to
## the left column and the buttons read Start and Back. The same signals are emitted.
func set_offline(offline: bool) -> void:
	_offline = offline
	_title_label.text = ui.t("solo_title") if offline else ui.t("lobby_title")
	_roster_panel.visible = not offline
	_setup_heading.text = ui.t("solo_setup") if offline else ui.t("lobby_setup")
	_setup_panel.reparent(_left if offline else _right, false)
	if offline:
		_left.move_child(_setup_panel, 0)
	else:
		_right.move_child(_setup_panel, 1)
	_leave_button.text = ui.t("solo_back") if offline else ui.t("lobby_leave")
	_info.text = ui.t("solo_info") if offline else ""


## Sets this PC's own pick without emitting (the starting values).
func set_pick(racer: int, vehicle: int) -> void:
	_racer = clampi(racer, 0, maxi(_racers.count() - 1, 0))
	_vehicle = clampi(vehicle, 0, maxi(_vehicles.count() - 1, 0))


## This PC's current pick (x racer, y vehicle).
func pick() -> Vector2i:
	return Vector2i(_racer, _vehicle)


## The line under the title (where we host or connect to).
func set_info(text: String) -> void:
	_info.text = text


## The racer, vehicle, track, bots and laps rows and the action button (debug scripts press them).
func racer_row() -> CycleRow:
	return _racer_row


func vehicle_row() -> CycleRow:
	return _vehicle_row


func track_row() -> CycleRow:
	return _track_row


func bots_row() -> CycleRow:
	return _bots_row


func laps_row() -> CycleRow:
	return _laps_row


func action_button() -> Button:
	return _action_button


## The state shown now.
func state() -> LobbyState:
	return _state


## Shows [param state]. [param my_peer] marks your row; [param is_host] unlocks the setup and Start.
func show_state(state: LobbyState, my_peer: int, is_host: bool) -> void:
	_state = state
	_my_peer = my_peer
	_is_host = is_host
	_refresh()


## True when this client has marked itself ready.
func is_ready_local() -> bool:
	return _ready_local


## Clears this client's own Ready mark (a new lobby).
func reset_ready() -> void:
	_ready_local = false


func _build(root: Control) -> void:
	_add_backdrop(ui.backdrop)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 22)
	root.add_child(margin)
	var page := VBoxContainer.new()
	page.add_theme_constant_override(&"separation", ui.gap - 2)
	margin.add_child(page)
	var head := HBoxContainer.new()
	head.add_theme_constant_override(&"separation", 20)
	page.add_child(head)
	var banner: PanelContainer = _banner(ui.t("lobby_title"), ui.heading_font + 4)
	_title_label = banner.get_child(0) as Label
	head.add_child(banner)
	_info = ui.label("", ui.body_font, ui.parchment)
	_info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_info)

	var body := HBoxContainer.new()
	body.add_theme_constant_override(&"separation", ui.gap + 2)
	page.add_child(body)
	var left := VBoxContainer.new()
	left.add_theme_constant_override(&"separation", ui.gap - 2)
	left.custom_minimum_size = Vector2(COLUMN_WIDTHS.reduce(func(a: int, b: int) -> int: return a + b, 0) + 5 * 8 + 2 * ui.panel_margin + 10, 0)
	body.add_child(left)
	var right := VBoxContainer.new()
	right.add_theme_constant_override(&"separation", ui.gap - 2)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(right)

	# Roster.
	var roster_out: Array = []
	var roster_panel: PanelContainer = ui.panel(4, roster_out)
	var rbox: VBoxContainer = roster_out[0]
	left.add_child(roster_panel)
	_roster_panel = roster_panel
	_left = left
	_right = right
	rbox.add_child(ui.label(ui.t("lobby_roster"), ui.heading_font))
	_roster_box = VBoxContainer.new()
	_roster_box.add_theme_constant_override(&"separation", 2)
	rbox.add_child(_roster_box)
	_total_label = ui.label("", ui.small_font, ui.ink_soft)
	rbox.add_child(_total_label)

	# Your pick with the preview.
	var pick_out: Array = []
	var pick_panel: PanelContainer = ui.panel(8, pick_out)
	var pbox: VBoxContainer = pick_out[0]
	right.add_child(pick_panel)
	pbox.add_child(ui.label(ui.t("lobby_pick"), ui.heading_font))
	_preview = KartPreview.new()
	_preview.setup(ui, _vehicles, _racers)
	_preview.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	pbox.add_child(_preview)
	_racer_row = _make_cycle(pbox, Signal())
	_racer_row.stepped.connect(func(d: int) -> void: _step_pick(d, 0))
	_vehicle_row = _make_cycle(pbox, Signal())
	_vehicle_row.stepped.connect(func(d: int) -> void: _step_pick(d, 1))
	_racer_info = ui.label("", ui.small_font, ui.ink_soft)
	_racer_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pbox.add_child(_racer_info)

	# Race setup (host) / what the host chose (clients).
	var setup_out: Array = []
	var setup_panel: PanelContainer = ui.panel(8, setup_out)
	var sbox: VBoxContainer = setup_out[0]
	right.add_child(setup_panel)
	_setup_panel = setup_panel
	_setup_heading = ui.label(ui.t("lobby_setup"), ui.heading_font)
	sbox.add_child(_setup_heading)
	_track_row = _make_cycle(sbox, track_stepped)
	var pair := HBoxContainer.new()
	pair.add_theme_constant_override(&"separation", ui.gap)
	sbox.add_child(pair)
	_bots_row = _make_cycle(pair, bots_stepped)
	_bots_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_laps_row = _make_cycle(pair, laps_stepped)
	_laps_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# Action buttons.
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override(&"separation", ui.gap)
	left.add_child(buttons)
	_action_button = ui.button("", true)
	_action_button.custom_minimum_size.y = ui.cycle_height + 6
	_action_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_action_button.pressed.connect(_on_action)
	buttons.add_child(_action_button)
	_leave_button = ui.button(ui.t("lobby_leave"))
	_leave_button.custom_minimum_size = Vector2(190, ui.button_min.y)
	_leave_button.pressed.connect(func() -> void: leave_requested.emit())
	buttons.add_child(_leave_button)
	_status = ui.label("", ui.body_font, ui.parchment)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(_status)


func _make_cycle(parent: Control, step_signal: Signal) -> CycleRow:
	var row := CycleRow.new()
	row.custom_minimum_size = Vector2(0, ui.cycle_height)
	row.focus_mode = Control.FOCUS_ALL
	if not step_signal.is_null():
		row.stepped.connect(func(d: int) -> void: step_signal.emit(d))
	parent.add_child(row)
	return row


func _fit() -> void:
	super._fit()
	if _preview != null:
		_preview.set_ui_scale(scale.y)


func _on_open() -> void:
	_refresh()
	_racer_row.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		leave_requested.emit()


func _on_action() -> void:
	if _is_host:
		start_requested.emit()
	else:
		_ready_local = not _ready_local
		ready_toggled.emit(_ready_local)
		_refresh()


func _step_pick(direction: int, which: int) -> void:
	if which == 0:
		_racer = posmod(_racer + direction, maxi(_racers.count(), 1))
	else:
		_vehicle = posmod(_vehicle + direction, maxi(_vehicles.count(), 1))
	pick_changed.emit(_racer, _vehicle)
	_refresh()


func _slot_color(slot: int) -> Color:
	if _colors.is_empty():
		return ui.primary
	return _colors[slot % _colors.size()]


func _refresh() -> void:
	if _roster_box == null or _racers == null:
		return
	var my_index: int = _state.index_of_peer(_my_peer)
	var slot: int = maxi(my_index, 0)
	if not _offline:
		_rebuild_roster(my_index)
	var racer_def: RacerDef = _racers.racer_at(_racer)
	var vehicle_def: VehicleStats = _vehicles.vehicle_at(_vehicle)
	_racer_row.show_value(ui.t("cycle_racer"), racer_def.display_name)
	_vehicle_row.show_value(ui.t("cycle_vehicle"), vehicle_def.display_name)
	_racer_info.text = ui.t("lobby_racer_info", [racer_def.display_name, racer_def.breed, vehicle_def.display_name])
	var key := Vector3i(_racer, _vehicle, slot)
	if key != _preview_key:
		_preview_key = key
		_preview.show_pick(_racer, _vehicle, slot, _slot_color(slot))
	# Race setup.
	var track_data: TrackData = TrackLibrary.load_track(_state.track)
	var track_name: String = track_data.display_name if track_data != null else _state.track
	_track_row.show_value(ui.t("cycle_track"), track_name, _is_host)
	_bots_row.show_value(ui.t("cycle_bots"), str(_state.bots), _is_host)
	_laps_row.show_value(ui.t("cycle_laps"), str(_state.laps), _is_host)
	for r in [_track_row, _bots_row, _laps_row]:
		(r as CycleRow).disabled = not _is_host
	_total_label.text = ui.t("lobby_total", [_state.humans(), _state.bots, _state.humans() + _state.bots, _max_racers])
	# Action button and status line.
	var focus_list: Array[Control] = [_racer_row, _vehicle_row]
	if _offline:
		focus_list.append_array([_track_row, _bots_row, _laps_row])
		_action_button.text = ui.t("lobby_start")
		_action_button.disabled = false
		_status.text = ui.t("solo_total", [_state.bots, _state.bots + 1, _max_racers])
	elif _is_host:
		focus_list.append_array([_track_row, _bots_row, _laps_row])
		var waiting: int = _state.waiting_count()
		_action_button.text = ui.t("lobby_start")
		_action_button.disabled = waiting > 0
		_status.text = ui.t("lobby_wait_players", [waiting]) if waiting > 0 else ui.t("lobby_all_ready")
	else:
		_action_button.text = ui.t("lobby_unready") if _ready_local else ui.t("lobby_ready")
		_action_button.disabled = false
		_status.text = ui.t("lobby_wait_host") if _ready_local else ui.t("lobby_get_ready")
	focus_list.append_array([_action_button, _leave_button])
	_link_focus(focus_list)


# Up / down walk one list so every enabled control is reachable without a mouse.
func _link_focus(controls: Array[Control]) -> void:
	var enabled: Array[Control] = []
	for c in controls:
		if not (c is BaseButton and (c as BaseButton).disabled):
			enabled.append(c)
	for i in enabled.size():
		var c: Control = enabled[i]
		c.focus_neighbor_top = c.get_path_to(enabled[(i - 1 + enabled.size()) % enabled.size()])
		c.focus_neighbor_bottom = c.get_path_to(enabled[(i + 1) % enabled.size()])
	# A disabled Start button must not hold focus.
	if _action_button.disabled and _action_button.has_focus():
		_leave_button.grab_focus()


func _rebuild_roster(my_index: int) -> void:
	for c in _roster_box.get_children():
		_roster_box.remove_child(c)
		c.queue_free()
	var head: HBoxContainer = _row_box(false)
	var titles: Array[String] = ["", ui.t("col_player"), ui.t("col_role"), ui.t("col_racer"), ui.t("col_vehicle"), ui.t("col_status")]
	for i in titles.size():
		head.add_child(_cell(titles[i], COLUMN_WIDTHS[i], ui.ink_soft, ui.small_font))
	_roster_box.add_child(head.get_parent())
	for i in _state.entries.size():
		var e: Dictionary = _state.entries[i]
		var mine: bool = i == my_index
		var racer: int = _racer if mine else int(e.racer)
		var vehicle: int = _vehicle if mine else int(e.vehicle)
		var is_host_row: bool = int(e.peer) == LobbyState.HOST_PEER
		var ready: bool = true if is_host_row else (_ready_local if mine else bool(e.ready))
		var box: HBoxContainer = _row_box(mine)
		var swatch := ColorRect.new()
		swatch.color = _slot_color(i)
		swatch.custom_minimum_size = Vector2(COLUMN_WIDTHS[0] - 6, ui.row_height - 8)
		var holder := Control.new()
		holder.custom_minimum_size = Vector2(COLUMN_WIDTHS[0], ui.row_height)
		holder.add_child(swatch)
		swatch.position = Vector2(0, 4)
		box.add_child(holder)
		box.add_child(_cell(ui.t("player_name", [i + 1]), COLUMN_WIDTHS[1], ui.ink, ui.body_font))
		var tags: Array[String] = []
		if is_host_row:
			tags.append(ui.t("role_host"))
		if mine:
			tags.append(ui.t("role_you"))
		if bool(e.get("new", false)):
			tags.append(ui.t("role_new"))
		box.add_child(_cell(", ".join(tags), COLUMN_WIDTHS[2], ui.ink, ui.small_font))
		box.add_child(_cell(_racers.racer_at(racer).display_name, COLUMN_WIDTHS[3], ui.ink, ui.body_font))
		box.add_child(_cell(_vehicles.vehicle_at(vehicle).display_name, COLUMN_WIDTHS[4], ui.ink, ui.body_font))
		var status: String = ui.t("status_ready") if ready else ui.t("status_not_ready")
		box.add_child(_cell(status, COLUMN_WIDTHS[5], ui.ready_color if ready else ui.not_ready_color, ui.small_font))
		_roster_box.add_child(box.get_parent())


# A row panel; returns the HBox inside (its parent is the panel to add).
func _row_box(highlight: bool) -> HBoxContainer:
	var p := PanelContainer.new()
	var sb: StyleBoxFlat = ui.box(ui.parchment_dark if highlight else Color(0, 0, 0, 0),
			ui.primary if highlight else Color(0, 0, 0, 0), 3, 4)
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	p.add_theme_stylebox_override(&"panel", sb)
	var h := HBoxContainer.new()
	h.add_theme_constant_override(&"separation", 8)
	p.add_child(h)
	return h


func _cell(text: String, width: int, color: Color, size: int) -> Label:
	var l: Label = ui.label(text, size, color)
	l.custom_minimum_size = Vector2(width, ui.row_height)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.clip_text = true
	return l
