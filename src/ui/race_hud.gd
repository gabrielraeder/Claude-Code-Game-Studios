class_name RaceHud
extends CanvasLayer
## Stream-readable race HUD (story 007 part 2): place banner (top right), item circle with the
## roulette (top left), lap / time / speed pills and the 3-pip drift meter under it, the
## countdown and centre messages, the control hints (bottom left) and a minimap (bottom right)
## with every racer as a pennant triangle in its slot colour.
## Layout follows art bible section 7; every size, colour and string is in UiTheme
## (assets/data/ui/ui_theme.tres, group "Race HUD" and the hud_* texts). The layer is scaled
## to the window height from UiTheme.base_height, like UiScreen.
## Reads KartSim, LapCounter and StartSequence state; sends nothing back (no game logic here).

const MS_TO_KMH: float = 3.6

var _ui: UiTheme
var _root: Control
var _numeral_font: FontVariation
var _place_panel: PanelContainer
var _place_num: Label
var _place_suffix: Label
var _place_total: Label
var _net_info: Label
var _slot: ItemSlot
var _item_name: Label
var _lap_label: Label
var _time_label: Label
var _best_label: Label
var _speed_label: Label
var _pips: DriftPips
var _center: Label
var _big: Label
var _help: Label
var _map_tile: PanelContainer
var _map_track: MinimapTrack
var _map_dots: MinimapDots
var _banner: String = ""
var _lobby: bool = false
var _shown_place: int = -1
var _pop_time: float = 0.0
var _last_ms: int = 0


## Builds the HUD from [param theme_data]. Call once, after the node is in the tree.
func setup(theme_data: UiTheme) -> void:
	_ui = theme_data
	layer = _ui.hud_layer
	_numeral_font = FontVariation.new()
	_numeral_font.base_font = ThemeDB.fallback_font
	_numeral_font.variation_embolden = _ui.hud_numeral_embolden
	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_build_left_column()
	_build_place()
	_build_center()
	_build_minimap()
	_help = _world_label(_ui.hud_hint_font, HORIZONTAL_ALIGNMENT_LEFT)
	_help.anchor_top = 1.0
	_help.anchor_bottom = 1.0
	_help.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_help.offset_left = _ui.hud_margin
	_help.offset_bottom = -_ui.hud_margin
	_help.offset_top = -_ui.hud_margin
	_help.text = _ui.t("hud_hints")
	get_viewport().size_changed.connect(_fit)
	_fit()


## Text shown in the middle of the screen instead of the usual one (empty = none), for
## lobby and connection messages.
func set_banner(text: String) -> void:
	_banner = text


## While true only the banner is shown (no countdown, race badges or minimap); used in a lobby.
func set_lobby(lobby: bool) -> void:
	_lobby = lobby


## Shows the place display ("1st/12") at the top right; [param total] 0 hides it.
func show_place(place: int, total: int) -> void:
	if _ui == null:
		return
	if total <= 0 or place <= 0:
		_place_panel.visible = false
		_shown_place = -1
		return
	_place_panel.visible = not _lobby
	if place != _shown_place:
		if _shown_place > 0 and _ui.hud_place_pop_time > 0.0:
			_pop_time = _ui.hud_place_pop_time
		_shown_place = place
		var ord: String = UiTheme.ordinal(place)
		var digits: String = str(place)
		_place_num.text = digits
		_place_suffix.text = ord.substr(digits.length())
		var c: Color = _ui.place_color(place)
		_place_num.add_theme_color_override(&"font_color", c)
		_place_suffix.add_theme_color_override(&"font_color", c)
	_place_total.text = _ui.t("hud_total", [total])


## Item slot (top left circle): [param icon] is {visible, color, id, spinning} from
## ItemManager.hud_icon().
func set_item(icon: Dictionary) -> void:
	if _slot == null:
		return
	var shown: bool = bool(icon.get("visible", false))
	var id: StringName = StringName(str(icon.get("id", "")))
	var color: Color = icon.get("color", Color.WHITE)
	var spinning: bool = bool(icon.get("spinning", false))
	if shown != _slot.shown or id != _slot.item_id or spinning != _slot.spinning or color != _slot.item_color:
		_slot.shown = shown
		_slot.item_id = id
		_slot.item_color = color
		_slot.spinning = spinning
		_slot.queue_redraw()
		_item_name.text = _ui.t("item_%s" % id) if shown and id != &"" and _ui.texts.has("item_%s" % id) else ""


## Small network status line at the top right under the place (empty hides it).
func set_net_info(text: String) -> void:
	if _net_info != null:
		_net_info.text = text


## Gives the minimap the track to draw (call when the track changes). Thins the centerlines
## once; nothing is rebuilt per frame.
func set_track(track: TrackModel) -> void:
	if _map_track == null or track == null:
		return
	_map_track.build(track, _ui)
	_map_dots.mapper = _map_track
	_map_dots.queue_redraw()


## This frame's racers for the minimap: world positions (x, z), headings (KartSim.yaw), slot
## colours, and the indexes of the local kart and the leader (-1 = none).
func set_minimap_racers(positions: PackedVector2Array, yaws: PackedFloat32Array, colors: PackedColorArray,
		local_index: int, leader_index: int) -> void:
	if _map_dots == null:
		return
	_map_dots.positions = positions
	_map_dots.yaws = yaws
	_map_dots.colors = colors
	_map_dots.local_index = local_index
	_map_dots.leader_index = leader_index
	_map_dots.queue_redraw()


## "1st/12" style text for [param place] of [param total].
static func format_place(place: int, total: int) -> String:
	return "%s/%d" % [UiTheme.ordinal(place), total]


## Formats seconds as m:ss.cc, or --:--.-- for a negative (unknown) time.
static func format_time(t: float) -> String:
	if t < 0.0:
		return "--:--.--"
	return "%d:%05.2f" % [floori(t / 60.0), fmod(t, 60.0)]


## Refreshes every element for this frame.
## [param allow_restart] is false online, where the finish panel has no restart prompt.
func refresh(sim: KartSim, laps: LapCounter, race_time: float, start: StartSequence,
		allow_restart: bool = true) -> void:
	if _ui == null:
		return
	var now_ms: int = Time.get_ticks_msec()
	var dt: float = clampf(float(now_ms - _last_ms) / 1000.0, 0.0, 0.1) if _last_ms > 0 else 0.0
	_last_ms = now_ms
	var racing: bool = not _lobby
	_slot.get_parent().visible = racing
	_map_tile.visible = racing
	if _lobby:
		_place_panel.visible = false
	var lap_shown: int = clampi(laps.lap, 1, laps.lap_target)
	var current: float = race_time - laps.lap_start_time if laps.lap >= 1 and not laps.is_finished else -1.0
	_lap_label.text = _ui.t("hud_lap", [lap_shown, laps.lap_target])
	var shown_t: float = current if current >= 0.0 else (laps.total_time() if laps.is_finished else 0.0)
	_time_label.text = format_time(shown_t)
	_best_label.text = _ui.t("hud_best", [format_time(laps.best_lap())])
	_speed_label.text = _ui.t("hud_speed", [int(absf(sim.speed) * MS_TO_KMH)])
	var tier: int = sim.drift_tier if sim.drifting else 0
	var boosting: bool = sim.boost_time > 0.0
	if tier != _pips.tier or boosting != _pips.boosting:
		_pips.tier = tier
		_pips.boosting = boosting
		_pips.queue_redraw()
	_update_pop(dt)

	if laps.is_finished:
		var out: Array[String] = [_ui.t("hud_finished"), _ui.t("hud_total_time", [format_time(laps.total_time())])]
		for i in laps.lap_times.size():
			out.append(_ui.t("hud_lap_line", [i + 1, format_time(laps.lap_times[i])]))
		out.append(_ui.t("hud_finish_restart") if allow_restart else _ui.t("hud_finish_menu"))
		_center.text = "\n".join(out)
	elif sim.spin_time > 0.0:
		_center.text = _ui.t("hud_spun")
	else:
		_center.text = _start_message(sim, start)
	_big.text = ""
	if _lobby:
		pass
	elif start.is_counting():
		_big.text = str(start.display_number())
		_big.add_theme_color_override(&"font_color", _ui.hud_cream)
	elif start.since_go < sim.stats.start_message_time:
		_big.text = _ui.t("hud_go")
		_big.add_theme_color_override(&"font_color", _ui.hud_go_color)
	if _banner != "":
		_center.text = _banner


func _start_message(sim: KartSim, start: StartSequence) -> String:
	if start.is_counting() or start.since_go >= sim.stats.start_message_time:
		return ""
	if start.stalled:
		return _ui.t("hud_too_early")
	match start.level:
		3:
			return _ui.t("hud_perfect")
		2:
			return _ui.t("hud_good")
		1:
			return _ui.t("hud_ok")
	return ""


func _update_pop(dt: float) -> void:
	if _pop_time <= 0.0 and _place_panel.scale == Vector2.ONE:
		return
	_pop_time = maxf(_pop_time - dt, 0.0)
	var total: float = maxf(_ui.hud_place_pop_time, 0.001)
	var k: float = sin(PI * (1.0 - _pop_time / total)) if _pop_time > 0.0 else 0.0
	var s: float = lerpf(1.0, _ui.hud_place_pop_scale, k)
	_place_panel.pivot_offset = _place_panel.size * Vector2(1.0, 0.0)
	_place_panel.scale = Vector2(s, s)


# ---------------------------------------------------------------- building

func _build_left_column() -> void:
	var col := VBoxContainer.new()
	col.position = Vector2(_ui.hud_margin, _ui.hud_margin)
	col.add_theme_constant_override(&"separation", _ui.hud_column_gap)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(col)
	var item_row := HBoxContainer.new()
	item_row.add_theme_constant_override(&"separation", _ui.hud_column_gap)
	col.add_child(item_row)
	_slot = ItemSlot.new()
	_slot.ui = _ui
	var d: float = (_ui.hud_item_radius + _ui.hud_badge_border) * 2.0
	_slot.custom_minimum_size = Vector2(d, d)
	item_row.add_child(_slot)
	_item_name = _world_label(_ui.hud_small_font, HORIZONTAL_ALIGNMENT_LEFT, false)
	_item_name.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	item_row.add_child(_item_name)
	var lap_pill: PanelContainer = _pill()
	col.add_child(lap_pill)
	_lap_label = _ink_label(_ui.hud_lap_font, true)
	lap_pill.add_child(_lap_label)
	var time_pill: PanelContainer = _pill()
	col.add_child(time_pill)
	var time_row := HBoxContainer.new()
	time_row.add_theme_constant_override(&"separation", _ui.hud_pill_pad)
	time_pill.add_child(time_row)
	_time_label = _ink_label(_ui.hud_time_font, true)
	time_row.add_child(_time_label)
	_best_label = _ink_label(_ui.hud_small_font, false)
	_best_label.add_theme_color_override(&"font_color", _ui.ink_soft)
	time_row.add_child(_best_label)
	var speed_pill: PanelContainer = _pill()
	col.add_child(speed_pill)
	var speed_row := HBoxContainer.new()
	speed_row.add_theme_constant_override(&"separation", _ui.hud_pill_pad)
	speed_pill.add_child(speed_row)
	_speed_label = _ink_label(_ui.hud_time_font, true)
	_speed_label.custom_minimum_size.x = float(_ui.hud_time_font) * 4.2
	speed_row.add_child(_speed_label)
	_pips = DriftPips.new()
	_pips.ui = _ui
	_pips.custom_minimum_size = Vector2(_ui.hud_pip_size * 3.0 + _ui.hud_pip_gap * 2.0, _ui.hud_pip_size)
	_pips.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	speed_row.add_child(_pips)


func _build_place() -> void:
	_place_panel = PanelContainer.new()
	_place_panel.add_theme_stylebox_override(&"panel", _ui.box(_ui.parchment, _ui.ink, _ui.border_width + 1, 14))
	_place_panel.anchor_left = 1.0
	_place_panel.anchor_right = 1.0
	_place_panel.offset_left = -_ui.hud_margin
	_place_panel.offset_right = -_ui.hud_margin
	_place_panel.offset_top = _ui.hud_margin
	_place_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_place_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_place_panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 2)
	_place_panel.add_child(row)
	_place_num = _outlined(_ui.hud_place_font, _ui.place_first, _ui.hud_place_outline, true)
	row.add_child(_place_num)
	_place_suffix = _outlined(_ui.hud_place_suffix_font, _ui.place_first, _ui.hud_outline, true)
	_place_suffix.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(_place_suffix)
	_place_total = _ink_label(_ui.hud_place_total_font, true)
	_place_total.size_flags_vertical = Control.SIZE_SHRINK_END
	row.add_child(_place_total)
	_place_panel.visible = false
	_net_info = _world_label(_ui.hud_hint_font, HORIZONTAL_ALIGNMENT_RIGHT)
	_net_info.anchor_left = 1.0
	_net_info.anchor_right = 1.0
	_net_info.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_net_info.offset_left = -_ui.hud_margin
	_net_info.offset_right = -_ui.hud_margin
	_net_info.offset_top = _ui.hud_margin + float(_ui.hud_place_font) * 1.55


func _build_center() -> void:
	_big = _outlined(_ui.hud_countdown_font, _ui.hud_cream, _ui.hud_place_outline + 2, true)
	_big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_big.anchor_left = 0.5
	_big.anchor_right = 0.5
	_big.anchor_top = 0.1
	_big.anchor_bottom = 0.1
	_big.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_root.add_child(_big)
	_center = _world_label(_ui.hud_message_font, HORIZONTAL_ALIGNMENT_CENTER)
	_center.anchor_left = 0.5
	_center.anchor_right = 0.5
	_center.anchor_top = 0.3
	_center.anchor_bottom = 0.3
	_center.grow_horizontal = Control.GROW_DIRECTION_BOTH


func _build_minimap() -> void:
	_map_tile = PanelContainer.new()
	_map_tile.add_theme_stylebox_override(&"panel", _map_style())
	_map_tile.anchor_left = 1.0
	_map_tile.anchor_right = 1.0
	_map_tile.anchor_top = 1.0
	_map_tile.anchor_bottom = 1.0
	var sz: float = _ui.hud_minimap_size
	_map_tile.offset_left = -_ui.hud_margin - sz
	_map_tile.offset_right = -_ui.hud_margin
	_map_tile.offset_top = -_ui.hud_margin - sz
	_map_tile.offset_bottom = -_ui.hud_margin
	_map_tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_map_tile)
	_map_track = MinimapTrack.new()
	_map_track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map_tile.add_child(_map_track)
	_map_dots = MinimapDots.new()
	_map_dots.ui = _ui
	_map_dots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map_dots.set_anchors_preset(Control.PRESET_FULL_RECT)
	_map_track.add_child(_map_dots)


func _map_style() -> StyleBoxFlat:
	var sb: StyleBoxFlat = _ui.box(_ui.hud_badge_fill, _ui.ink, _ui.border_width, 0)
	sb.set_corner_radius_all(_ui.hud_minimap_corner)
	return sb


func _pill() -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = _ui.hud_badge_fill
	sb.border_color = _ui.ink
	sb.set_border_width_all(_ui.hud_badge_border)
	sb.set_corner_radius_all(int(_ui.hud_pill_height * 0.5))
	sb.content_margin_left = _ui.hud_pill_pad
	sb.content_margin_right = _ui.hud_pill_pad
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	sb.anti_aliasing = true
	p.add_theme_stylebox_override(&"panel", sb)
	p.custom_minimum_size.y = _ui.hud_pill_height
	p.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


# Ink text on a parchment badge.
func _ink_label(size: int, heavy: bool) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override(&"font_size", size)
	l.add_theme_color_override(&"font_color", _ui.ink)
	if heavy:
		l.add_theme_font_override(&"font", _numeral_font)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


# Coloured text with an Ink outline (the place numeral, the countdown).
func _outlined(size: int, color: Color, outline: int, heavy: bool) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override(&"font_size", size)
	l.add_theme_color_override(&"font_color", color)
	l.add_theme_color_override(&"font_outline_color", _ui.ink)
	l.add_theme_constant_override(&"outline_size", outline)
	if heavy:
		l.add_theme_font_override(&"font", _numeral_font)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


# Cream text with an Ink outline straight over the world; added to the root unless [param add] is false.
func _world_label(size: int, align: HorizontalAlignment, add: bool = true) -> Label:
	var l: Label = _outlined(size, _ui.hud_cream, _ui.hud_outline, false)
	l.horizontal_alignment = align
	if add:
		_root.add_child(l)
	return l


# Scales the layer so the layout spans the window height the same way at every resolution.
func _fit() -> void:
	if _root == null:
		return
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var s: float = maxf(vp.y / _ui.base_height, 0.1)
	scale = Vector2(s, s)
	_root.position = Vector2.ZERO
	_root.size = vp / s


## Circle that draws the held item (or the spinning roulette): a flat icon per item id in its
## art bible section 4 colour, with the Ink outline.
class ItemSlot extends Control:
	var ui: UiTheme
	var shown: bool = false
	var spinning: bool = false
	var item_id: StringName = &""
	var item_color: Color = Color.WHITE

	func _draw() -> void:
		var r: float = ui.hud_item_radius
		var c := Vector2(r + ui.hud_badge_border, r + ui.hud_badge_border)
		draw_circle(c, r + ui.hud_badge_border, ui.ink)
		draw_circle(c, r, ui.hud_badge_fill)
		if not shown:
			return
		var ir: float = ui.hud_item_icon_radius
		var bw: float = float(ui.hud_badge_border)
		match item_id:
			&"horn":
				# A flared horn: a wide triangle bell on a narrow mouthpiece.
				var pts := PackedVector2Array([c + Vector2(-ir, -ir * 0.25), c + Vector2(ir * 0.55, -ir * 0.85),
						c + Vector2(ir * 0.55, ir * 0.85), c + Vector2(-ir, ir * 0.25)])
				_poly(pts, item_color, bw)
				draw_circle(c + Vector2(ir * 0.55, 0.0), ir * 0.25, ui.ink)
			&"stone":
				var pts := PackedVector2Array()
				for i in 7:
					var a: float = TAU * float(i) / 7.0
					pts.append(c + Vector2(cos(a), sin(a)) * ir * (0.85 if i % 2 == 0 else 1.0))
				_poly(pts, item_color, bw)
			&"spill":
				draw_circle(c + Vector2(-ir * 0.35, ir * 0.15), ir * 0.6 + bw, ui.ink)
				draw_circle(c + Vector2(ir * 0.4, ir * 0.25), ir * 0.5 + bw, ui.ink)
				draw_circle(c + Vector2(0.0, -ir * 0.35), ir * 0.45 + bw, ui.ink)
				draw_circle(c + Vector2(-ir * 0.35, ir * 0.15), ir * 0.6, item_color)
				draw_circle(c + Vector2(ir * 0.4, ir * 0.25), ir * 0.5, item_color)
				draw_circle(c + Vector2(0.0, -ir * 0.35), ir * 0.45, item_color)
			&"falcon":
				# A swooping chevron (wings) with a head.
				var pts := PackedVector2Array([c + Vector2(-ir, -ir * 0.45), c + Vector2(0.0, ir * 0.2),
						c + Vector2(ir, -ir * 0.45), c + Vector2(ir * 0.2, ir * 0.75), c + Vector2(-ir * 0.2, ir * 0.75)])
				_poly(pts, item_color, bw)
			&"shield":
				var pts := PackedVector2Array([c + Vector2(-ir * 0.8, -ir * 0.8), c + Vector2(ir * 0.8, -ir * 0.8),
						c + Vector2(ir * 0.8, ir * 0.05), c + Vector2(0.0, ir), c + Vector2(-ir * 0.8, ir * 0.05)])
				_poly(pts, item_color, bw)
			_:
				draw_circle(c, ir + bw, ui.ink)
				draw_circle(c, ir, item_color)
		if spinning:
			draw_arc(c, r - bw * 1.5, -PI * 0.5, PI * 0.5, 16, ui.focus_ring, bw * 1.5, true)

	func _poly(pts: PackedVector2Array, fill: Color, width: float) -> void:
		draw_colored_polygon(pts, fill)
		var closed: PackedVector2Array = pts.duplicate()
		closed.append(pts[0])
		draw_polyline(closed, ui.ink, width, true)


## Three pips: lit up to the drift tier in the tier colours, all lit in the boost colour while a
## boost runs (colour is never the only cue: the pip count carries the tier).
class DriftPips extends Control:
	var ui: UiTheme
	var tier: int = 0
	var boosting: bool = false

	func _draw() -> void:
		var s: float = ui.hud_pip_size
		for i in 3:
			var r := Rect2(Vector2(float(i) * (s + ui.hud_pip_gap), 0.0), Vector2(s, s))
			var col: Color = ui.hud_pip_off
			if i < tier and i < ui.hud_drift_tier_colors.size():
				col = ui.hud_drift_tier_colors[mini(tier - 1, ui.hud_drift_tier_colors.size() - 1)]
			elif boosting and tier == 0:
				col = ui.hud_boost_color
			var cc: Vector2 = r.get_center()
			draw_circle(cc, s * 0.5, ui.ink)
			draw_circle(cc, s * 0.5 - 2.0, ui.parchment)
			draw_circle(cc, s * 0.5 - 2.0, col)


## The track on the minimap: main loop and branches thinned once into tile coordinates and drawn
## as chunky lines. Godot keeps the draw commands until queue_redraw, so this costs nothing per frame.
class MinimapTrack extends Control:
	var ui: UiTheme
	var lines: Array[PackedVector2Array] = []
	var closed: Array[bool] = []
	var is_branch: Array[bool] = []
	var start_a: Vector2 = Vector2.ZERO
	var start_b: Vector2 = Vector2.ZERO
	var _origin: Vector2 = Vector2.ZERO
	var _scale: float = 1.0
	var _offset: Vector2 = Vector2.ZERO

	## Thins the track's centerlines and fits them into the tile.
	func build(track: TrackModel, theme_data: UiTheme) -> void:
		ui = theme_data
		var inner: float = ui.hud_minimap_size - ui.hud_minimap_pad * 2.0
		var b: Rect2 = Rect2(track.main.points[0], Vector2.ZERO)
		var paths: Array[TrackModel.Path] = [track.main]
		paths.append_array(track.branches)
		for p in paths:
			for pt in p.points:
				b = b.expand(pt)
		var span: float = maxf(maxf(b.size.x, b.size.y), 1.0)
		_scale = inner / span
		_origin = b.position
		_offset = Vector2(ui.hud_minimap_pad, ui.hud_minimap_pad) + (Vector2(inner, inner) - b.size * _scale) * 0.5
		lines.clear()
		closed.clear()
		is_branch.clear()
		for p in paths:
			var step: int = maxi(1, ceili(float(p.points.size()) / float(maxi(ui.hud_minimap_max_points, 8))))
			var out := PackedVector2Array()
			for i in range(0, p.points.size(), step):
				out.append(to_map(p.points[i]))
			if p.closed:
				out.append(out[0])
			else:
				out.append(to_map(p.points[p.points.size() - 1]))
			lines.append(out)
			closed.append(p.closed)
			is_branch.append(p != track.main)
		var s0: Vector2 = track.point_at(0.0)
		var n0: Vector2 = track.normal_at(0.0) * track.main.half_width * 1.6
		start_a = to_map(s0 - n0)
		start_b = to_map(s0 + n0)
		custom_minimum_size = Vector2(ui.hud_minimap_size, ui.hud_minimap_size)
		queue_redraw()

	## World (x, z) to tile coordinates.
	func to_map(p: Vector2) -> Vector2:
		return _offset + (p - _origin) * _scale

	func _draw() -> void:
		if ui == null:
			return
		for i in lines.size():
			if is_branch[i]:
				draw_polyline(lines[i], ui.ink, ui.hud_minimap_branch_outer, true)
		for i in lines.size():
			if not is_branch[i]:
				draw_polyline(lines[i], ui.ink, ui.hud_minimap_road_outer, true)
		for i in lines.size():
			draw_polyline(lines[i], ui.hud_minimap_road_color,
					ui.hud_minimap_branch_inner if is_branch[i] else ui.hud_minimap_road_inner, true)
		draw_line(start_a, start_b, ui.hud_minimap_start_color, ui.hud_minimap_road_inner, true)


## Racer markers on the minimap, redrawn every frame: a pennant triangle in the slot colour
## pointing along the kart's heading, a gold ring under the leader and a cream ring around the
## local player (shape, not colour alone). Drawn others first, then the leader, then the player.
class MinimapDots extends Control:
	var ui: UiTheme
	var mapper: MinimapTrack
	var positions: PackedVector2Array = PackedVector2Array()
	var yaws: PackedFloat32Array = PackedFloat32Array()
	var colors: PackedColorArray = PackedColorArray()
	var local_index: int = -1
	var leader_index: int = -1

	func _draw() -> void:
		if mapper == null or ui == null:
			return
		for i in positions.size():
			if i != local_index and i != leader_index:
				_marker(i)
		if leader_index >= 0 and leader_index < positions.size() and leader_index != local_index:
			_marker(leader_index)
		if local_index >= 0 and local_index < positions.size():
			_marker(local_index)

	func _marker(i: int) -> void:
		var p: Vector2 = mapper.to_map(positions[i])
		var yaw: float = yaws[i] if i < yaws.size() else 0.0
		var f := Vector2(-sin(yaw), -cos(yaw))
		var side := Vector2(-f.y, f.x)
		var ln: float = ui.hud_minimap_dot_len
		var half: float = ui.hud_minimap_dot_half
		if i == leader_index:
			# Leading local player: the gold ring sits outside the cream one.
			var lr: float = ui.hud_minimap_leader_ring
			if i == local_index:
				lr = ui.hud_minimap_local_ring + ui.hud_minimap_local_ring_width
			draw_circle(p, lr + ui.hud_minimap_dot_border, ui.ink)
			draw_circle(p, lr, ui.place_first)
		if i == local_index:
			draw_circle(p, ui.hud_minimap_local_ring + ui.hud_minimap_dot_border, ui.ink)
			draw_circle(p, ui.hud_minimap_local_ring, ui.hud_cream)
		var tip: Vector2 = p + f * ln * 0.6
		var back: Vector2 = p - f * ln * 0.4
		var pts := PackedVector2Array([tip, back + side * half, back - side * half])
		var col: Color = colors[i] if i < colors.size() else Color.WHITE
		draw_colored_polygon(pts, col)
		pts.append(tip)
		draw_polyline(pts, ui.ink, ui.hud_minimap_dot_border, true)
