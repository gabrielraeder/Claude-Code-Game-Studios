extends SceneTree
## Headless track validation (story 003). Run:
##   godot --headless --path . -s res://tools/track_check.gd -- --track=castle_circuit
## Prints PASS/FAIL lines with numbers; exit code 1 when any check fails. Uses the real
## KartSim, AutopilotDriver, TrackModel and LapCounter at a fixed tick, no rendering.

const DT: float = 1.0 / 60.0
const MAX_RACE_SECONDS: float = 150.0
const INFIELD_STARTS: int = 200
const INFIELD_SECONDS: float = 10.0

var _fails: int = 0
var _stats: VehicleStats
var _net: NetConfig
var _track: TrackModel


func _init() -> void:
	var track_id: String = TrackLibrary.DEFAULT_ID
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--track="):
			track_id = a.substr("--track=".length())
	var data: TrackData = TrackLibrary.load_track(track_id)
	if data == null:
		print("FAIL load track '%s'" % track_id)
		quit(1)
		return
	_stats = load("res://assets/data/vehicles/armored_cart.tres") as VehicleStats
	_net = load("res://assets/data/net/net_config.tres") as NetConfig
	_track = TrackModel.new(data)
	print("== track_check: %s (%s) ==" % [data.display_name, track_id])
	_check_geometry()
	_check_grid()
	var main_run: Dictionary = _run_laps("", true)
	_report_run("(3) main line", main_run)
	var main_avg: float = _flying_avg(main_run)
	_check_ok("(3) main line completes %d laps within the walls" % data.lap_count,
			main_run.finished and main_run.max_excess <= 0.05,
			"laps %s, max |lateral| %.2f m of limit %.2f m" % [_fmt(main_run.times), main_run.max_lateral_ratio_abs, main_run.limit])
	for bi in _track.branch_count():
		var id: String = String(data.branches[bi].id)
		var run: Dictionary = _run_laps(id, true)
		_report_run("(4) %s" % id, run)
		var avg: float = _flying_avg(run)
		_check_ok("(4) %s: 3 laps, exactly one lap each, branch driven" % id,
				run.finished and run.times.size() == data.lap_count and run.rejected == 0 and run.ticks_on_branch > 60,
				"ticks on branch %d, rejected line crossings %d" % [run.ticks_on_branch, run.rejected])
		_check_ok("(4) %s faster than main line when driven well" % id, run.finished and avg < main_avg,
				"flying lap %.2f s vs main %.2f s, saving %.2f s" % [avg, main_avg, main_avg - avg])
		var careful: Dictionary = _run_laps(id, false)
		print("     (info) no-drift but well-steered via %s: finished=%s flying lap %.2f s, wall hits %d, hard %d" % [id, str(careful.finished), _flying_avg(careful), careful.wall_hits, careful.hard_hits])
		var sloppy: Dictionary = _run_laps(id, false, 25.0)
		var s_avg: float = _flying_avg(sloppy)
		var verdict: bool = (not sloppy.finished) or s_avg >= main_avg or avg < s_avg
		_check_ok("(5) sloppy driver (full throttle, no drift, straight at the entrance) via %s does not beat the main line" % id,
				(not sloppy.finished) or s_avg >= main_avg,
				"sloppy flying lap %.2f s vs main %.2f s (good run %.2f s), wall hits %d, hard hits %d" % [
						s_avg if sloppy.finished else -1.0, main_avg, avg, sloppy.wall_hits, sloppy.hard_hits])
		if not verdict:
			pass
	_check_progress_jumps()
	_check_infield()
	_check_lap_counter()
	print("== %s ==" % ("ALL PASS" if _fails == 0 else "%d FAILED" % _fails))
	quit(1 if _fails > 0 else 0)


func _fmt(a: Array) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for v in a:
		parts.append("%.2f" % float(v))
	return "[" + ", ".join(parts) + "]"


func _check_ok(label: String, ok: bool, detail: String) -> void:
	if not ok:
		_fails += 1
	print("%s %s: %s" % ["PASS" if ok else "FAIL", label, detail])


func _flying_avg(run: Dictionary) -> float:
	var t: Array = run.times
	if t.size() < 2:
		return INF
	var sum: float = 0.0
	for i in range(1, t.size()):
		sum += float(t[i])
	return sum / float(t.size() - 1)


func _report_run(label: String, run: Dictionary) -> void:
	print("     %s: finished=%s lap times %s, wall hits %d (hard %d), max_speed %.1f, max jump ratio %.2f" % [
			label, str(run.finished), _fmt(run.times), run.wall_hits, run.hard_hits, run.max_speed, run.max_jump_ratio])


# ---------------------------------------------------------------- (1) geometry
func _check_geometry() -> void:
	var len_ok: bool = _track.length >= 600.0 and _track.length <= 950.0
	var gap: float = _track.point_at(_track.length - 0.01).distance_to(_track.point_at(0.0))
	_check_ok("(1) loop closure and length", gap < 0.1 and len_ok,
			"length %.1f m, closure gap %.3f m, %d samples, %d checkpoints" % [_track.length, gap, _track.points.size(), _track.checkpoint_s.size()])
	var min_r: float = INF
	var pts: PackedVector2Array = _track.points
	var n: int = pts.size()
	for i in n:
		var a: Vector2 = pts[(i - 1 + n) % n]
		var b: Vector2 = pts[i]
		var c: Vector2 = pts[(i + 1) % n]
		var area2: float = absf((b - a).cross(c - a))
		if area2 > 0.0001:
			min_r = minf(min_r, a.distance_to(b) * b.distance_to(c) * a.distance_to(c) / (2.0 * area2))
	_check_ok("(1) no wall fold (min centerline radius > wall offset)", min_r > _track.wall_offset,
			"min radius %.1f m, wall offset %.1f m" % [min_r, _track.wall_offset])
	for bi in _track.branch_count():
		var b: TrackModel.Path = _track.branches[bi]
		var ratio: float = (b.s_out - b.s_in) / b.length
		var min_main: float = INF
		for d in range(int(b.length * 0.2), int(b.length * 0.8)):
			var p: Vector2 = b.point_at(float(d))
			min_main = minf(min_main, _track.distance_to_path(p, TrackModel.MAIN_PATH))
		_check_ok("(1) branch %s sane" % b.id, ratio < _track.progress_rate_cap - 0.1 and b.s_out > b.s_in,
				"s %.0f..%.0f (%.0f m of main), branch %.0f m, progress ratio %.2f, middle distance to main road %.1f m (corridors %.1f + %.1f)" % [
						b.s_in, b.s_out, b.s_out - b.s_in, b.length, ratio, min_main, _track.wall_offset, b.wall_offset])


# ---------------------------------------------------------------- (2) start straight and grid
func _check_grid() -> void:
	var p0: Vector2 = _track.point_at(0.0)
	var n0: Vector2 = _track.normal_at(0.0)
	var behind: float = 0.0
	while behind < 200.0 and absf((_track.point_at(-behind - 1.0) - p0).dot(n0)) < 0.1:
		behind += 1.0
	var ahead: float = 0.0
	while ahead < 200.0 and absf((_track.point_at(ahead + 1.0) - p0).dot(n0)) < 0.1:
		ahead += 1.0
	_check_ok("(2) start straight", behind >= 60.0 and ahead >= 20.0,
			"%.0f m straight behind the line, %.0f m ahead, road half width %.1f m" % [behind, ahead, _track.data.road_half_width])
	var sims: Array[KartSim] = []
	var min_margin: float = INF
	for id in _net.max_racers:
		var s := KartSim.new(_stats)
		var dist: float = _track.length - _track.data.start_distance_behind_line - float(id / 2) * _net.grid_row_spacing
		s.reset_to(_track, dist, _net.grid_lateral * (1.0 if id % 2 == 0 else -1.0))
		min_margin = minf(min_margin, _track.wall_offset - (absf(s.lateral) + _stats.bump_radius))
		sims.append(s)
	var min_gap: float = INF
	for i in sims.size():
		for j in range(i + 1, sims.size()):
			min_gap = minf(min_gap, KartSim.body_gap(sims[i], sims[j]))
	var last_row_back: float = _track.data.start_distance_behind_line + float((_net.max_racers - 1) / 2) * _net.grid_row_spacing
	_check_ok("(2) 12 grid slots fit with margin and no overlap", min_margin >= 0.5 and min_gap > 0.0,
			"%d slots, min wall margin %.2f m, min body gap %.2f m, last row %.0f m behind the line" % [sims.size(), min_margin, min_gap, last_row_back])


# ---------------------------------------------------------------- driving runs
# Runs the autopilot on [param shortcut] (empty = main line) for the race's laps.
func _run_laps(shortcut: String, drift: bool, blind: float = 0.0) -> Dictionary:
	var sim := KartSim.new(_stats)
	var driver := AutopilotDriver.new()
	driver.shortcut_id = StringName(shortcut)
	driver.allow_drift = drift
	driver.blind_entrance = blind
	var input := KartInput.new()
	var laps := LapCounter.new(_track.data.lap_count, _track.length, _track.checkpoint_s)
	var run: Dictionary = {"finished": false, "times": [], "wall_hits": 0, "hard_hits": 0, "max_speed": 0.0,
			"max_jump_ratio": 0.0, "jump_violations": 0, "max_excess": -INF, "ticks_on_branch": 0,
			"rejected": 0, "limit": 0.0, "max_lateral_ratio_abs": 0.0}
	sim.wall_bumped.connect(func(hard: bool) -> void:
		run.wall_hits += 1
		if hard:
			run.hard_hits += 1)
	sim.reset_to(_track, _track.length - _track.data.start_distance_behind_line, 0.0)
	laps.reset(sim.track_s)
	var t: float = 0.0
	var prev_s: float = sim.track_s
	var prev_pos: Vector2 = sim.position
	var max_lat: float = 0.0
	while t < MAX_RACE_SECONDS and not laps.is_finished:
		driver.time_to_go = 0.0
		driver.drive(input, sim, _track, DT)
		sim.tick(DT, input, _track)
		t += DT
		laps.update(sim.track_s, t)
		var moved: float = sim.position.distance_to(prev_pos)
		var ds: float = absf(wrapf(sim.track_s - prev_s, -_track.length * 0.5, _track.length * 0.5))
		if moved > 0.01:
			run.max_jump_ratio = maxf(run.max_jump_ratio, ds / moved)
		if ds > 2.0 * moved + 0.05:
			run.jump_violations += 1
		prev_s = sim.track_s
		prev_pos = sim.position
		run.max_speed = maxf(run.max_speed, sim.speed)
		run.max_excess = maxf(run.max_excess, _track.excess_at(sim.position))
		if sim.track_path >= 0:
			run.ticks_on_branch += 1
		var q: TrackModel.Query = _track.query(sim.position, -1)
		max_lat = maxf(max_lat, absf(q.lateral))
		run.limit = q.wall_offset
	run.finished = laps.is_finished
	run.times = laps.lap_times
	run.rejected = laps.rejected_crossings
	run.max_lateral_ratio_abs = max_lat
	return run


# ---------------------------------------------------------------- (6) progress monotonicity
func _check_progress_jumps() -> void:
	var worst: float = 0.0
	var viol: int = 0
	var runs: Array[String] = [""]
	for bi in _track.branch_count():
		runs.append(String(_track.data.branches[bi].id))
	for id in runs:
		var r: Dictionary = _run_laps(id, true)
		worst = maxf(worst, r.max_jump_ratio)
		viol += int(r.jump_violations)
	_check_ok("(6) track_s never jumps more than 2x the distance moved (incl. branch entry/exit)", viol == 0,
			"%d runs (main + each shortcut), largest ds/moved %.2f, violations %d" % [runs.size(), worst, viol])


# ---------------------------------------------------------------- (7) infield and checkpoints
func _check_infield() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260101
	var b: Rect2 = _track.main.bounds
	var starts: int = 0
	var laps_done: int = 0
	var escaped: int = 0
	var worst: float = -INF
	var rejected: int = 0
	var guard: int = 0
	while starts < INFIELD_STARTS and guard < 100000:
		guard += 1
		var p := Vector2(rng.randf_range(b.position.x, b.end.x), rng.randf_range(b.position.y, b.end.y))
		if _track.excess_at(p) <= 0.0:
			continue
		starts += 1
		var sim := KartSim.new(_stats)
		sim.reset_to(_track, 0.0, 0.0)
		sim.position = p
		sim.yaw = rng.randf_range(-PI, PI)
		sim._segment_hint = -1
		sim.track_s = _track.query(p, -1).s
		var laps := LapCounter.new(_track.data.lap_count, _track.length, _track.checkpoint_s)
		laps.reset(_track.length - 1.0)
		laps.update(1.0, 0.0)
		laps.resync(sim.track_s)
		var input := KartInput.new()
		input.throttle = 1.0
		var t: float = 0.0
		while t < INFIELD_SECONDS:
			sim.tick(DT, input, _track)
			t += DT
			laps.update(sim.track_s, t)
			var ex: float = _track.excess_at(sim.position)
			worst = maxf(worst, ex)
			if ex > 0.05:
				escaped += 1
				break
		if laps.lap_times.size() > 0 or laps.lap >= 2:
			laps_done += 1
		rejected += laps.rejected_crossings
	_check_ok("(7) %d infield starts, straight at random headings for %.0f s: no lap, never outside the corridors" % [starts, INFIELD_SECONDS],
			starts == INFIELD_STARTS and laps_done == 0 and escaped == 0,
			"laps gained %d, escapes %d, worst excess over wall %.3f m, refused line crossings %d" % [laps_done, escaped, worst, rejected])


# ---------------------------------------------------------------- (8) lap counter edge cases
func _check_lap_counter() -> void:
	var len: float = _track.length
	var cps: PackedFloat32Array = _track.checkpoint_s
	var lc := LapCounter.new(3, len, cps)
	var started: Array[int] = []
	lc.lap_started.connect(func(l: int) -> void: started.append(l))
	lc.reset(len - 6.0)
	var t: float = 0.0
	var s: float = len - 6.0
	# Drive over the line, back over it, and forward again.
	for step in 12:
		s += 1.0
		if s >= len:
			s -= len
		lc.update(s, t)
	var lap_after_cross: int = lc.lap
	for step in 12:
		s -= 1.0
		if s < 0.0:
			s += len
		lc.update(s, t)
	var lap_after_back: int = lc.lap
	for step in 12:
		s += 1.0
		if s >= len:
			s -= len
		lc.update(s, t)
	_check_ok("(8) reversing over the line gives no extra lap", lap_after_cross == 1 and lap_after_back == 0 and lc.lap == 1 and started == [1],
			"lap after crossing %d, after reversing %d, after crossing again %d, lap_started events %s, completed laps %d" % [
					lap_after_cross, lap_after_back, lc.lap, str(started), lc.lap_times.size()])
	# A teleported kart crossing the line without the checkpoints is refused.
	var lc2 := LapCounter.new(3, len, cps)
	lc2.reset(len - 6.0)
	lc2.update(2.0, 0.0)
	lc2.update(len * 0.4, 1.0)
	lc2.resync(len - 20.0)
	lc2.update(len - 10.0, 2.0)
	lc2.update(3.0, 3.0)
	_check_ok("(8) crossing the line without the checkpoints is not a lap", lc2.lap == 1 and lc2.rejected_crossings == 1,
			"lap %d, refused crossings %d, checkpoints passed %d of %d" % [lc2.lap, lc2.rejected_crossings, lc2.checkpoints_passed(), lc2.checkpoint_total()])
	# A full lap in 5 m steps counts exactly once.
	var lc3 := LapCounter.new(3, len, cps)
	lc3.reset(len - 6.0)
	var s3: float = len - 6.0
	var steps: int = int((len + 12.0) / 5.0) + 2
	for i in steps:
		s3 = fposmod(s3 + 5.0, len)
		lc3.update(s3, float(i))
	_check_ok("(8) a full lap counts exactly once", lc3.lap == 2 and lc3.lap_times.size() == 1,
			"lap %d, completed laps %d, refused crossings %d" % [lc3.lap, lc3.lap_times.size(), lc3.rejected_crossings])
	# Shortcut laps count once each: see (4) (3 laps, 0 refused crossings).
