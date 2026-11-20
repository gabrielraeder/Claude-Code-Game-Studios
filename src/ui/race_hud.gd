class_name RaceHud
extends CanvasLayer
## Minimal race HUD: lap and timer, speed, drift charge bar, controls help, finish panel.
## Reads KartSim and LapCounter state; sends nothing back (no game logic here).
## Implements story 001 lap timer HUD and finish state.

const TEXT_SIZE: int = 24
const CENTER_SIZE: int = 40
const HELP_SIZE: int = 17
const COUNTDOWN_SIZE: int = 110
const GO_COLOR: Color = Color(0.4, 1.0, 0.4)
const MARGIN: float = 20.0
const BAR_SIZE: Vector2 = Vector2(300, 18)
const BAR_POSITION: Vector2 = Vector2(20, 100)
const BAR_BG_COLOR: Color = Color(0, 0, 0, 0.45)
const BOOST_BAR_COLOR: Color = Color(1.0, 0.55, 0.1)
const MS_TO_KMH: float = 3.6

var _info: Label
var _center: Label
var _big: Label
var _help: Label
var _bar_bg: ColorRect
var _bar: ColorRect
var _place: Label
var _net_info: Label
var _slot: ItemSlot
var _banner: String = ""
var _lobby: bool = false


## Text shown in the middle of the screen instead of the usual one (empty = none), for
## lobby and connection messages.
func set_banner(text: String) -> void:
	_banner = text


## While true only the banner is shown (no countdown number); used while waiting in a lobby.
func set_lobby(lobby: bool) -> void:
	_lobby = lobby


## Shows the place display ("1st/12") at the top right; [param total] 0 hides it.
func show_place(place: int, total: int) -> void:
	_place.text = format_place(place, total) if total > 0 else ""


## Item slot (top center circle): [param icon] is {visible, color, glyph, spinning}.
## Flat placeholder icon; the real art is story 007.
func set_item(icon: Dictionary) -> void:
	if _slot == null:
		_slot = ItemSlot.new()
		_slot.position = Vector2(0, 0)
		add_child(_slot)
	_slot.icon = icon
	_slot.queue_redraw()


## Circle that draws the held item.
class ItemSlot extends Control:
	var icon: Dictionary = {}

	func _ready() -> void:
		anchor_left = 0.5
		anchor_right = 0.5
		offset_left = -48.0
		offset_right = 48.0
		offset_top = 10.0
		offset_bottom = 106.0

	func _draw() -> void:
		var c := Vector2(48, 48)
		draw_circle(c, 44.0, Color(0, 0, 0, 0.45))
		if not bool(icon.get("visible", false)):
			return
		draw_circle(c, 36.0, icon.get("color", Color.WHITE))
		var font: Font = ThemeDB.fallback_font
		draw_string(font, c + Vector2(-10, 12), str(icon.get("glyph", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, 34, Color.BLACK)


## Small network status line at the bottom right (empty hides it).
func set_net_info(text: String) -> void:
	_net_info.text = text


## "1st/12" style text for [param place] of [param total].
static func format_place(place: int, total: int) -> String:
	var suffix: String = "th"
	if place % 100 < 11 or place % 100 > 13:
		match place % 10:
			1:
				suffix = "st"
			2:
				suffix = "nd"
			3:
				suffix = "rd"
	return "%d%s/%d" % [place, suffix, total]


func _ready() -> void:
	_place = _label(0.0, 0.0, CENTER_SIZE)
	_place.anchor_left = 1.0
	_place.anchor_right = 1.0
	_place.offset_left = -300
	_place.offset_right = -MARGIN
	_place.offset_top = 16
	_place.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_net_info = _label(0.0, 0.0, HELP_SIZE)
	_net_info.anchor_left = 1.0
	_net_info.anchor_right = 1.0
	_net_info.anchor_top = 1.0
	_net_info.anchor_bottom = 1.0
	_net_info.offset_left = -400
	_net_info.offset_right = -MARGIN
	_net_info.offset_top = -40
	_net_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_info = _label(MARGIN, 16.0, TEXT_SIZE)
	_center = _label(0.0, 0.0, CENTER_SIZE)
	_center.anchor_left = 0.5
	_center.anchor_right = 0.5
	_center.anchor_top = 0.3
	_center.offset_left = -500
	_center.offset_right = 500
	_center.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_big = _label(0.0, 0.0, COUNTDOWN_SIZE)
	_big.anchor_left = 0.5
	_big.anchor_right = 0.5
	_big.anchor_top = 0.08
	_big.offset_left = -500
	_big.offset_right = 500
	_big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_help = _label(0.0, 0.0, HELP_SIZE)
	_help.anchor_top = 1.0
	_help.anchor_bottom = 1.0
	_help.offset_left = MARGIN
	_help.offset_top = -100
	_help.text = "W/S or RT/LT  drive / brake      A/D or left stick  steer\n"
	_help.text += "Space/Shift or RB  hold to drift (steer into the turn)\n"
	_help.text += "Esc or Start  pause (Restart is in the pause menu)"
	_bar_bg = ColorRect.new()
	_bar_bg.color = BAR_BG_COLOR
	_bar_bg.position = BAR_POSITION
	_bar_bg.size = BAR_SIZE
	add_child(_bar_bg)
	_bar = ColorRect.new()
	_bar.position = BAR_POSITION
	_bar.size = Vector2(0, BAR_SIZE.y)
	add_child(_bar)


## Refreshes every element for this frame.
## [param allow_restart] is false online, where the finish panel has no restart prompt.
func refresh(sim: KartSim, laps: LapCounter, race_time: float, start: StartSequence,
		allow_restart: bool = true) -> void:
	var lap_shown: int = clampi(laps.lap, 1, laps.lap_target)
	var current: float = race_time - laps.lap_start_time if laps.lap >= 1 and not laps.is_finished else -1.0
	var lines: Array[String] = []
	lines.append("Lap %d/%d     %s     %d km/h" % [lap_shown, laps.lap_target,
			format_time(maxf(race_time, 0.0)), int(absf(sim.speed) * MS_TO_KMH)])
	lines.append("This lap %s     Best %s" % [format_time(current), format_time(laps.best_lap())])
	_info.text = "\n".join(lines)

	var tiers: PackedFloat32Array = sim.stats.drift_tier_times
	if sim.drifting:
		_bar.size.x = BAR_SIZE.x * clampf(sim.drift_time / tiers[tiers.size() - 1], 0.0, 1.0)
		_bar.color = sim.stats.spark_colors[mini(sim.drift_tier, sim.stats.spark_colors.size() - 1)]
	else:
		_bar.size.x = 0.0
	if sim.boost_time > 0.0:
		_bar.size.x = BAR_SIZE.x
		_bar.color = BOOST_BAR_COLOR

	if laps.is_finished:
		var out: Array[String] = ["FINISHED", "Total %s" % format_time(laps.total_time())]
		for i in laps.lap_times.size():
			out.append("Lap %d  %s" % [i + 1, format_time(laps.lap_times[i])])
		if allow_restart:
			out.append("Press Start / A / Enter to restart, Esc for the menu")
		else:
			out.append("Press Esc / Start for the menu")
		_center.text = "\n".join(out)
	elif sim.spin_time > 0.0:
		_center.text = "SPUN OUT!"
	else:
		_center.text = _start_message(sim, start)
	_big.text = ""
	_big.add_theme_color_override("font_color", Color.WHITE)
	if _lobby:
		pass
	elif start.is_counting():
		_big.text = str(start.display_number())
	elif start.since_go < sim.stats.start_message_time:
		_big.text = "GO!"
		_big.add_theme_color_override("font_color", GO_COLOR)
	if _banner != "":
		_center.text = _banner


func _start_message(sim: KartSim, start: StartSequence) -> String:
	if start.is_counting() or start.since_go >= sim.stats.start_message_time:
		return ""
	if start.stalled:
		return "TOO EARLY!"
	match start.level:
		3:
			return "PERFECT START!"
		2:
			return "GOOD START!"
		1:
			return "OK START"
	return ""


## Formats seconds as m:ss.cc, or --:--.-- for a negative (unknown) time.
static func format_time(t: float) -> String:
	if t < 0.0:
		return "--:--.--"
	return "%d:%05.2f" % [floori(t / 60.0), fmod(t, 60.0)]


func _label(x: float, y: float, size: int) -> Label:
	var l := Label.new()
	l.position = Vector2(x, y)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color.WHITE)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 8)
	add_child(l)
	return l
