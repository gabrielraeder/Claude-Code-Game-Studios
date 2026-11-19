class_name RaceHud
extends CanvasLayer
## Minimal race HUD: lap and timer, speed, drift charge bar, controls help, finish panel.
## Reads KartSim and LapCounter state; sends nothing back (no game logic here).
## Implements story 001 lap timer HUD and finish state.

const TEXT_SIZE: int = 24
const CENTER_SIZE: int = 40
const HELP_SIZE: int = 17
const MARGIN: float = 20.0
const BAR_SIZE: Vector2 = Vector2(300, 18)
const BAR_POSITION: Vector2 = Vector2(20, 100)
const BAR_BG_COLOR: Color = Color(0, 0, 0, 0.45)
const BOOST_BAR_COLOR: Color = Color(1.0, 0.55, 0.1)
const MS_TO_KMH: float = 3.6

var _info: Label
var _center: Label
var _help: Label
var _bar_bg: ColorRect
var _bar: ColorRect


func _ready() -> void:
	_info = _label(MARGIN, 16.0, TEXT_SIZE)
	_center = _label(0.0, 0.0, CENTER_SIZE)
	_center.anchor_left = 0.5
	_center.anchor_right = 0.5
	_center.anchor_top = 0.3
	_center.offset_left = -500
	_center.offset_right = 500
	_center.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_help = _label(0.0, 0.0, HELP_SIZE)
	_help.anchor_top = 1.0
	_help.anchor_bottom = 1.0
	_help.offset_left = MARGIN
	_help.offset_top = -100
	_help.text = "W/S or RT/LT  drive / brake      A/D or left stick  steer\n"
	_help.text += "Space/Shift or RB  hold to drift (steer into the turn)\n"
	_help.text += "R  restart      Esc or Start  pause"
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
func refresh(sim: KartSim, laps: LapCounter, race_time: float) -> void:
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
		out.append("Press R or Start to restart")
		_center.text = "\n".join(out)
	elif sim.spin_time > 0.0:
		_center.text = "SPUN OUT!"
	else:
		_center.text = ""


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
