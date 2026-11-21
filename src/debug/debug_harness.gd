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
var _pad_shot_done: bool = false
## Most bump screenshots taken in one run.
const MAX_BUMP_SHOTS: int = 3
## Seconds after a timed-hazard hit (story 009) before its screenshot (the spin or the bump shows).
const HAZARD_SHOT_DELAY: float = 0.3
var _air_shots: int = 0
var _height_file: FileAccess
# Height summary (story 008): smallest clearance above the support while grounded and on a deck,
# total air time, and ticks logged.
var _min_clearance: float = INF
var _min_clearance_s: float = 0.0
var _air_total: float = 0.0
var _height_ticks: int = 0


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
	var items: Object = _main.get("items")
	if items != null and _options.shots_dir != "":
		items.item_event.connect(_on_item_event)
	_sim.sank.connect(func() -> void:
		var fall: bool = _sim.hazard_kind == KartSim.FALL_KIND
		if fall:
			print("[air] FALL t=%.2f s=%.1f h=%.2f road=%.2f lat=%.1f falls=%d" % [_main.race_time, _sim.track_s,
					_sim.height, _sim.road_height, _sim.lateral, _sim.fall_count])
		_delayed_shot("fall_sink" if fall else "moat_sink", 0.25 if fall else 0.5))
	# Story 009: a timed hazard spun the kart (barrel) or stopped it (portcullis).
	_sim.mover_hit.connect(func(mi: int) -> void:
		var hm: HazardManager = _main.get("hazards") as HazardManager
		var id: String = String(hm.mover(mi).id) if hm != null else str(mi)
		_delayed_shot("hazard_%s_t%03d" % [id, int(_main.race_time)], HAZARD_SHOT_DELAY))
	_sim.respawned.connect(func() -> void:
		var fall: bool = _sim.hazard_kind == KartSim.FALL_KIND
		print("[air] RESPAWN t=%.2f s=%.1f h=%.2f immunity=%.2f speed=%.1f kind=%s" % [_main.race_time, _sim.track_s,
				_sim.height, _sim.hit_immunity_time, _sim.speed, _sim.hazard_kind])
		_delayed_shot("fall_respawn" if fall else "moat_respawn", 0.4))
	_sim.took_off.connect(func(trick: bool) -> void:
		print("[air] TAKEOFF t=%.2f s=%.1f h=%.2f vy=%.2f speed=%.1f trick=%d drift=%d boost=%.2f" % [
				_main.race_time, _sim.track_s, _sim.height, _sim.vertical_velocity, _sim.speed,
				1 if trick else 0, 1 if _sim.drifting else 0, _sim.boost_time])
		if _air_shots == 0:
			_delayed_shot("jump_air", 0.3))
	_sim.landed.connect(func(airtime: float, impact: float) -> void:
		print("[air] LAND t=%.2f s=%.1f airtime=%.2f impact=%.2f h=%.2f speed=%.1f drift=%d tier=%d boost=%.2f" % [
				_main.race_time, _sim.track_s, airtime, impact, _sim.height, _sim.speed,
				1 if _sim.drifting else 0, _sim.drift_tier, _sim.boost_time])
		if _air_shots == 0:
			_air_shots += 1
			_delayed_shot("jump_land", 0.03))
	_sim.trick_boosted.connect(func() -> void:
		print("[air] TRICK t=%.2f s=%.1f boost=%.2f" % [_main.race_time, _sim.track_s, _sim.boost_time]))
	if _options.height_log != "" and _options.height_log != "every-tick":
		DirAccess.make_dir_recursive_absolute(_options.height_log.get_base_dir())
		_height_file = FileAccess.open(_options.height_log, FileAccess.WRITE)
		if _height_file != null:
			_height_file.store_line("t,lap,s,path,x,z,height,support,road,clearance,grounded,on_deck,vy,speed,sinking")
	_sim.pad_boosted.connect(func() -> void:
		if not _pad_shot_done:
			_pad_shot_done = true
			_delayed_shot("boost_pad", 0.05))


const ITEM_SHOT_DELAY: Dictionary = {
	&"roulette": 0.5, &"horn": 0.25, &"stone": 0.3, &"spill": 1.2, &"falcon": 0.5,
	&"shield": 0.3, &"bounce": 0.05, &"slick_ahead": 0.05, &"hit": 0.15, &"shield_break": 0.1,
}
var _item_shots: Dictionary = {}


# Pictures of item events (story 004): the first one or two of each kind.
func _on_item_event(kind: StringName, text: String) -> void:
	if not ITEM_SHOT_DELAY.has(kind):
		return
	if kind in [&"horn", &"stone", &"spill", &"falcon", &"shield", &"bounce", &"roulette"]:
		var owner_id: int = _owner_of(text)
		if owner_id != int(_main.get("local_kart_id")):
			return
	var n: int = int(_item_shots.get(kind, 0))
	if n >= (6 if kind == &"hit" or kind == &"shield_break" else 1):
		return
	_item_shots[kind] = n + 1
	var tag: String = text.replace(" ", "_").replace("=", "")
	var delay: float = float(ITEM_SHOT_DELAY[kind])
	if kind == &"hit" or kind == &"shield_break":
		delay = 0.05 if n == 0 else (0.2 if n == 1 else 0.45)
	if (kind == &"hit" or kind == &"shield_break") and n >= 2:
		delay = 0.45  # later pictures show the spin and the star puffs without the flash
	_delayed_shot("item_%s_%d_%s" % [kind, n, tag], delay)


# Kart id that fired the item in an item_event text (owner=, kart=, or seq=owner*100000+n).
func _owner_of(text: String) -> int:
	for part in text.split(" "):
		if part.begins_with("owner=") or part.begins_with("kart="):
			return int(part.get_slice("=", 1))
		if part.begins_with("seq="):
			return int(part.get_slice("=", 1)) / 100000
	return -1


func _on_drift_ended(tier: int, _boost_seconds: float) -> void:
	if tier > 0 and tier <= _boosts.size():
		_boosts[tier - 1] += 1


func _physics_process(_dt: float) -> void:
	_max_speed = maxf(_max_speed, absf(_sim.speed))
	if _height_file != null and not _main.start_sequence.is_counting():
		_log_height(_dt)
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


# One CSV row per tick: the kart's height against what holds it up and the road beside it.
func _log_height(dt: float) -> void:
	var clearance: float = _sim.height - _sim.support_height
	if _sim.grounded and _sim.on_deck and not _sim.is_sinking():
		if clearance < _min_clearance:
			_min_clearance = clearance
			_min_clearance_s = _sim.track_s
	if not _sim.grounded:
		_air_total += dt
	_height_ticks += 1
	_height_file.store_line("%.3f,%d,%.2f,%d,%.2f,%.2f,%.3f,%.3f,%.3f,%.3f,%d,%d,%.2f,%.2f,%d" % [_main.race_time,
			_laps.lap, _sim.track_s, _sim.track_path, _sim.position.x, _sim.position.y, _sim.height,
			_sim.support_height, _sim.road_height, clearance, 1 if _sim.grounded else 0, 1 if _sim.on_deck else 0,
			_sim.vertical_velocity, _sim.speed, 1 if _sim.is_sinking() else 0])


## Prints the height summary line ([air] SUMMARY) and closes the height log.
func print_height_summary() -> void:
	if _height_file == null:
		return
	_height_file.close()
	_height_file = null
	print("[air] SUMMARY ticks=%d min_grounded_clearance=%.3f at_s=%.1f air_total=%.2f jumps=%d tricks=%d falls=%d respawns=%d laps=%s" % [
			_height_ticks, _min_clearance, _min_clearance_s, _air_total, _sim.jump_count, _sim.trick_count,
			_sim.fall_count, _sim.respawn_count, str(_laps.lap_times)])


func _exit_tree() -> void:
	print_height_summary()


func _on_race_finished(_total: float) -> void:
	print_height_summary()
	if _options.shots_dir != "" and not _headless:
		# Let the finish panel render, then capture it.
		await get_tree().create_timer(0.5).timeout
		_save_shot("finish")
	_write_log()
	var cam: ChaseCamera = _main.get("_camera") as ChaseCamera
	if cam != null:
		print("[camera] min height over the surface under it: raw %.2f final %.2f; floor clamp frames %d, ceiling clamp frames %d" % [
				cam.debug_min_raw_clearance, cam.debug_min_clearance, cam.debug_floor_frames, cam.debug_ceiling_frames])
	print("[debug] finished: laps %s boosts %s start_boost %d max_speed %.2f cap %.2f" % [
		str(_laps.lap_times), str(_boosts), _start_level, _max_speed,
		_sim.stats.max_speed * _sim.stats.boost_speed_mult])
	# Online, Main quits once every human has finished, so no one is left racing alone.
	if _options.quit_after_race and not _main.net_active:
		get_tree().quit()


func _delayed_shot(shot_name: String, delay: float) -> void:
	if _options.shots_dir == "" or _headless:
		return
	await get_tree().create_timer(delay).timeout
	_save_shot(shot_name)


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
