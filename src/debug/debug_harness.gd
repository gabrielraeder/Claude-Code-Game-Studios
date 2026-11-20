class_name DebugHarness
extends Node
## DEBUG AID. Observes a run from outside the game code: counts boosts per tier, tracks max
## speed, saves screenshots, writes a CSV log and quits. Driven by DebugOptions.
## The game never depends on this node; it only reads public state and signals.

## Race-clock seconds (driving time) at which screenshots are saved.
const SHOT_TIMES: Array[float] = [3.0, 10.0, 20.0]
## Real seconds after start when the menu screenshot is taken.
const MENU_SHOT_DELAY: float = 1.0
## Physics ticks between verbose status lines.
const VERBOSE_EVERY_TICKS: int = 120

var _options: DebugOptions
var _main: Node
var _sim: KartSim
var _laps: LapCounter
var _headless: bool = false
var _boosts: Array[int] = [0, 0, 0]
var _max_speed: float = 0.0
var _shots_left: Array[float] = []
var _real_time: float = 0.0
var _menu_shot_done: bool = false
var _logged: bool = false
var _ticks: int = 0
var _tier_shots: Array[bool] = [false, false, false]
var _countdown_shot_done: bool = false
var _go_shot_done: bool = false
var _start_level: int = 0
var _bump_shots: int = 0
var _shot_s_done: Array[bool] = []
var _last_shot_s: float = 0.0
## Most bump screenshots taken in one run.
const MAX_BUMP_SHOTS: int = 3


## Attaches to the running game. [param main] must expose the properties and the
## race_finished signal used below.
func setup(options: DebugOptions, main: Node, sim: KartSim, laps: LapCounter) -> void:
	_options = options
	_main = main
	_sim = sim
	_laps = laps
	process_mode = Node.PROCESS_MODE_ALWAYS
	_headless = DisplayServer.get_name() == "headless"
	_shots_left = SHOT_TIMES.duplicate()
	if not _options.shot_s.is_empty():
		_shots_left.clear()
	_shot_s_done.resize(_options.shot_s.size())
	_shot_s_done.fill(false)
	if _options.shots_dir != "":
		DirAccess.make_dir_recursive_absolute(_options.shots_dir)
	_sim.drift_ended.connect(_on_drift_ended)
	_main.race_finished.connect(_on_race_finished)


func _on_drift_ended(tier: int, _boost_seconds: float) -> void:
	if tier > 0 and tier <= _boosts.size():
		_boosts[tier - 1] += 1


func _physics_process(_dt: float) -> void:
	_max_speed = maxf(_max_speed, absf(_sim.speed))
	_start_level = maxi(_start_level, _sim.start_boost_level)
	_ticks += 1
	if _options.verbose and _ticks % VERBOSE_EVERY_TICKS == 0:
		print("[debug] t=%.1f lap=%d s=%.0f lat=%.1f speed=%.1f drift=%s tier=%d boosts=%s" % [
			_main.race_time, _laps.lap, _sim.track_s, _sim.lateral, _sim.speed,
			str(_sim.drifting), _sim.drift_tier, str(_boosts)])


func _process(delta: float) -> void:
	_real_time += delta
	if _options.quit_after_seconds > 0.0 and _real_time >= _options.quit_after_seconds:
		get_tree().quit()
		return
	if _options.shots_dir == "" or _headless:
		return
	if not _menu_shot_done and _main.menu_is_open() and _real_time >= MENU_SHOT_DELAY:
		_menu_shot_done = true
		_save_shot("menu")
	var start: StartSequence = _main.start_sequence
	if not _countdown_shot_done and start.is_counting() and start.time_to_go <= 1.9 and not _main.menu_is_open():
		_countdown_shot_done = true
		_save_shot("countdown")
	if not _go_shot_done and not start.is_counting() and start.since_go >= 0.3:
		_go_shot_done = true
		_save_shot("start_go")
	if _sim.drifting and _sim.drift_tier > 0 and not _tier_shots[_sim.drift_tier - 1]:
		_tier_shots[_sim.drift_tier - 1] = true
		_save_shot("spark_tier%d" % _sim.drift_tier)
	if _bump_shots < MAX_BUMP_SHOTS and int(_main.get("bump_count")) > _bump_shots:
		_bump_shots += 1
		_save_shot("bump_%d" % _bump_shots)
	for k in _options.shot_s.size():
		var target_s: float = _options.shot_s[k]
		if not _shot_s_done[k] and _laps.lap >= 1 and _last_shot_s < target_s and _sim.track_s >= target_s \
				and _sim.track_s - target_s < 40.0:
			_shot_s_done[k] = true
			_save_shot("at_s%03d" % int(target_s))
	_last_shot_s = _sim.track_s
	if not _shots_left.is_empty() and _main.race_time >= _shots_left[0]:
		var t: float = _shots_left.pop_front()
		_save_shot("drive_t%02d" % int(t))


func _on_race_finished(_total: float) -> void:
	if _options.shots_dir != "" and not _headless:
		# Let the finish panel render, then capture it.
		await get_tree().create_timer(0.5).timeout
		_save_shot("finish")
	_write_log()
	print("[debug] finished: laps %s boosts %s start_boost %d max_speed %.2f cap %.2f" % [
		str(_laps.lap_times), str(_boosts), _start_level, _max_speed,
		_sim.stats.max_speed * _sim.stats.boost_speed_mult])
	# Online, Main quits once every human has finished, so no one is left racing alone.
	if _options.quit_after_race and not _main.net_active:
		get_tree().quit()


func _save_shot(shot_name: String) -> void:
	var path: String = "%s/%s.png" % [_options.shots_dir, shot_name]
	var err: Error = get_viewport().get_texture().get_image().save_png(path)
	print("[debug] screenshot %s (err %d)" % [path, err])


func _write_log() -> void:
	if _options.log_path == "" or _logged:
		return
	_logged = true
	var f := FileAccess.open(_options.log_path, FileAccess.WRITE)
	if f == null:
		printerr("[debug] cannot open log ", _options.log_path)
		return
	f.store_line("lap1,lap2,lap3,total,boost_blue,boost_orange,boost_purple,start_boost_level,max_speed,speed_cap_with_boost")
	var laps: Array[String] = []
	for i in _laps.lap_target:
		laps.append("%.2f" % (_laps.lap_times[i] if i < _laps.lap_times.size() else -1.0))
	f.store_line("%s,%.2f,%d,%d,%d,%d,%.2f,%.2f" % [",".join(laps), _laps.total_time(),
		_boosts[0], _boosts[1], _boosts[2], _start_level, _max_speed,
		_sim.stats.max_speed * _sim.stats.boost_speed_mult])
	f.close()
