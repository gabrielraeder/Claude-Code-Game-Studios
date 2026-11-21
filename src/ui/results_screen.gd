class_name ResultsScreen
extends UiScreen
## The results after a race: one row per racer with place, name, dog, vehicle and finish time
## (DNF when unfinished). The winner's row is gold, your row has a Red-Orange outline. The host
## gets Rematch and Back to lobby, clients see "Waiting for the host", a solo player gets
## Restart and Menu. It only shows the list it is given (built from the networked race state).

## Who is looking: decides the buttons.
enum Viewer { SOLO, HOST, CLIENT }

## Host: start the same race again.
signal rematch_requested
## Host: go back to the lobby.
signal lobby_requested
## Solo: race again.
signal restart_requested
## Solo: back to the main menu. Client: leave the host.
signal menu_requested

## Roster column widths in base pixels: place, swatch, name, racer, vehicle, time.
const COLUMN_WIDTHS: Array[int] = [74, 26, 180, 160, 170, 110]

var _racers: RacerSet
var _vehicles: VehicleSet
var _colors: PackedColorArray = PackedColorArray()
var _rows: VBoxContainer
var _buttons: HBoxContainer
var _wait_label: Label
var _note: Label
var _first_button: Button
var _viewer: Viewer = Viewer.SOLO
var _title: PanelContainer
var _title_label: Label


## Builds the screen with the rosters it needs ([param colors] is the slot palette).
func setup_results(theme_data: UiTheme, racers: RacerSet, vehicles: VehicleSet, colors: PackedColorArray) -> void:
	_racers = racers
	_vehicles = vehicles
	_colors = colors
	setup(theme_data)


## Shows [param entries] (dictionaries with place, kart_id, name, racer, vehicle, time where time
## below 0 means did not finish), highlighting [param my_kart]; [param viewer] picks the buttons.
func show_results(entries: Array, my_kart: int, viewer: Viewer) -> void:
	_viewer = viewer
	for c in _rows.get_children():
		_rows.remove_child(c)
		c.queue_free()
	_rows.add_child(_make_row(null, my_kart, true))
	for e: Dictionary in entries:
		_rows.add_child(_make_row(e, my_kart, false))
	for c in _buttons.get_children():
		_buttons.remove_child(c)
		c.queue_free()
	_wait_label.visible = viewer == Viewer.CLIENT
	match viewer:
		Viewer.HOST:
			_first_button = _add_button("results_rematch", true, func() -> void: rematch_requested.emit())
			_add_button("results_lobby", false, func() -> void: lobby_requested.emit())
		Viewer.CLIENT:
			_first_button = _add_button("results_leave", false, func() -> void: menu_requested.emit())
		_:
			_first_button = _add_button("results_restart", true, func() -> void: restart_requested.emit())
			_add_button("results_menu", false, func() -> void: menu_requested.emit())
	if visible:
		_first_button.grab_focus()


## A line under the table (who watched the race and joins the next one); empty hides it.
func set_note(text: String) -> void:
	_note.text = text
	_note.visible = text != ""


## The first button (Rematch for the host); debug scripts press it.
func first_button() -> Button:
	return _first_button


func _build(root: Control) -> void:
	_add_backdrop(ui.dim)
	var column: VBoxContainer = _centered_column(ui.gap)
	_title = _banner(ui.t("results_title"), ui.heading_font + 6)
	column.add_child(_title)
	var out: Array = []
	var panel: PanelContainer = ui.panel(4, out)
	var box: VBoxContainer = out[0]
	column.add_child(panel)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override(&"separation", 3)
	box.add_child(_rows)
	_note = ui.label("", ui.body_font, ui.place_first)
	_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_note.visible = false
	column.add_child(_note)
	_wait_label = ui.label(ui.t("results_wait_host"), ui.body_font, ui.parchment)
	_wait_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_wait_label)
	_buttons = HBoxContainer.new()
	_buttons.add_theme_constant_override(&"separation", ui.gap)
	_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(_buttons)


func _on_open() -> void:
	if _first_button != null:
		_first_button.grab_focus()


func _add_button(text_key: String, primary_look: bool, action: Callable) -> Button:
	var b: Button = ui.button(ui.t(text_key), primary_look)
	b.pressed.connect(action)
	_buttons.add_child(b)
	return b


# One results row; [param entry] null makes the header.
func _make_row(entry: Variant, my_kart: int, header: bool) -> Control:
	var p := PanelContainer.new()
	var fill: Color = Color(0, 0, 0, 0)
	var border: Color = Color(0, 0, 0, 0)
	var place: int = 0
	var mine: bool = false
	if not header:
		var e: Dictionary = entry
		place = int(e.place)
		mine = int(e.kart_id) == my_kart
		fill = ui.place_first if place == 1 else ui.parchment_dark
		border = ui.primary if mine else Color(0, 0, 0, 0)
	var sb: StyleBoxFlat = ui.box(fill, border, 4 if mine else 0, 4)
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	p.add_theme_stylebox_override(&"panel", sb)
	var h := HBoxContainer.new()
	h.add_theme_constant_override(&"separation", 8)
	p.add_child(h)
	if header:
		var titles: Array[String] = [ui.t("col_place"), "", ui.t("col_player"), ui.t("col_racer"), ui.t("col_vehicle"), ui.t("col_time")]
		for i in titles.size():
			h.add_child(_cell(titles[i], COLUMN_WIDTHS[i], ui.ink_soft, ui.small_font))
		return p
	var e: Dictionary = entry
	var badge := PanelContainer.new()
	var bsb: StyleBoxFlat = ui.box(ui.place_color(place), ui.ink, 2, 2)
	bsb.content_margin_top = 0
	bsb.content_margin_bottom = 0
	badge.add_theme_stylebox_override(&"panel", bsb)
	badge.custom_minimum_size = Vector2(COLUMN_WIDTHS[0], ui.row_height)
	var pl: Label = ui.label(UiTheme.ordinal(place), ui.body_font, ui.ink)
	pl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.add_child(pl)
	h.add_child(badge)
	var swatch := ColorRect.new()
	swatch.color = _colors[int(e.kart_id) % _colors.size()] if not _colors.is_empty() else ui.primary
	swatch.custom_minimum_size = Vector2(COLUMN_WIDTHS[1] - 6, ui.row_height - 8)
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(COLUMN_WIDTHS[1], ui.row_height)
	holder.add_child(swatch)
	swatch.position = Vector2(0, 4)
	h.add_child(holder)
	var name_text: String = str(e.name)
	if mine:
		name_text += " " + ui.t("results_you")
	h.add_child(_cell(name_text, COLUMN_WIDTHS[2], ui.ink, ui.body_font))
	h.add_child(_cell(_racers.racer_at(int(e.racer)).display_name, COLUMN_WIDTHS[3], ui.ink, ui.body_font))
	h.add_child(_cell(_vehicles.vehicle_at(int(e.vehicle)).display_name, COLUMN_WIDTHS[4], ui.ink, ui.body_font))
	var t: float = float(e.time)
	h.add_child(_cell(RaceHud.format_time(t) if t >= 0.0 else ui.t("results_dnf"), COLUMN_WIDTHS[5],
			ui.ink if t >= 0.0 else ui.not_ready_color, ui.body_font))
	return p


func _cell(text: String, width: int, color: Color, size: int) -> Label:
	var l: Label = ui.label(text, size, color)
	l.custom_minimum_size = Vector2(width, ui.row_height)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.clip_text = true
	return l
