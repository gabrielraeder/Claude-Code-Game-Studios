extends SceneTree
## Headless track validation (story 003). Run:
##   godot --headless --path . -s res://tools/track_check.gd -- --track=castle_circuit
## Prints PASS/FAIL lines with numbers; exit code 1 when any check fails. Uses the real
## KartSim, AutopilotDriver, BotDriver, TrackModel and LapCounter at a fixed tick, no rendering.
## Targets for Castle Circuit come from design/references/track-design-reference.md sections 5-6.

const DT: float = 1.0 / 60.0
## A speed-gate probe counts as crossed once it is this far (m) past the strip's center.
const GATE_PAST: float = 6.0
const MAX_RACE_SECONDS: float = 240.0
const INFIELD_STARTS: int = 200
const INFIELD_SECONDS: float = 10.0
## Castle Circuit targets (reference doc section 5).
# Story 008 part 5: the owner widened the upper limit to 1,200 m for the Barbican Spiral (~1,146 m),
# crossover-decision.md. Dungeon keeps its limits.
const CASTLE_LENGTH: Vector2 = Vector2(1000.0, 1200.0)
const CASTLE_LAP: Vector2 = Vector2(45.0, 50.0)
const CASTLE_CORNERS: Vector2i = Vector2i(12, 15)
## Dungeon Depths targets (reference doc section 7): 950-1,100 m, 14-16 corners.
const DUNGEON_LENGTH: Vector2 = Vector2(950.0, 1100.0)
const DUNGEON_CORNERS: Vector2i = Vector2i(14, 16)
## Expected time saving of a well-driven shortcut, seconds (doc: ~1.5-2 s drawbridge, ~2 s passage).
const SHORTCUT_SAVING: Vector2 = Vector2(1.0, 3.0)
## Width rules (doc section 5): grid >= 18 m, a pinch <= 10 m, no width step steeper than this.
const GRID_MIN_WIDTH: float = 18.0
const PINCH_MAX_WIDTH: float = 10.0
const MAX_WIDTH_SLOPE: float = 0.35
## A kart sinking again this soon after a respawn counts as a respawn loop.
const RESPAWN_LOOP_WINDOW: float = 3.0
## Bots as the race uses them (story 005).
const BOT_SET_PATH: String = "res://assets/data/ai/bot_set.tres"
## Story 008 part 4 (height checks): the documented limits of the generated tracks
## (tools/elevation_profile.py GRADE_MAX and BANK_MAX): the genre keeps slopes moderate.
const MAX_GRADE: float = 0.12
const MAX_BANK_DEG: float = 15.0
## A grounded kart may sit at most this far below the road surface (meters).
const MIN_CLEARANCE: float = -0.05
## Two overlapping road surfaces closer than this in height (meters) are one level (a junction);
## farther apart but nearer than TrackData.level_separation, one deck cuts through the other.
const JUNCTION_TOLERANCE: float = 0.35
## Spacing (meters) of the road samples of the static height checks.
const HEIGHT_PROBE_STEP: float = 2.0
# Story 008 part 5: (16) a road compared with ITSELF (a self-crossing loop) ignores its own samples
# closer than this along the road (meters), so only the other pass of the loop counts.
const SELF_CROSS_MIN_GAP: float = 40.0
# (13) an arc of one direction turning at least this much is a spiral (the Barbican Spiral, 280 deg).
const SPIRAL_MIN_DEG: float = 200.0

var _fails: int = 0
var _stats: VehicleStats
var _net: NetConfig
var _track: TrackModel
var _data: TrackData
var _castle: bool = false
var _dungeon: bool = false
## --only=<branch id>: main line plus that branch only, then quit (tuning aid, not a verdict).
var _only: String = ""
## --quick: stop after the shortcut runs (tuning aid).
var _quick: bool = false
# Story 008 part 4: height results gathered over every driven run (autopilot lines and the bot).
var _h_runs: int = 0
var _h_min_clear: float = INF
var _h_min_at: String = ""
var _h_jumps: int = 0
var _h_land_off: int = 0
var _h_land_off_at: String = ""
var _h_progress_violations: int = 0
var _h_rejected: int = 0
var _trace: bool = false
var _trace_from: float = 0.0


func _init() -> void:
	var track_id: String = TrackLibrary.DEFAULT_ID
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--track="):
			track_id = a.substr("--track=".length())
		elif a.begins_with("--only="):
			_only = a.substr("--only=".length())
		elif a.begins_with("--trace="):
			_trace = true
			_trace_from = float(a.substr("--trace=".length()))
		elif a == "--quick":
			_quick = true
	_data = TrackLibrary.load_track(track_id)
	if _data == null:
		print("FAIL load track '%s'" % track_id)
		quit(1)
		return
	_castle = track_id == "castle_circuit"
	_dungeon = track_id == "dungeon_depths"
	_stats = load("res://assets/data/vehicles/armored_cart.tres") as VehicleStats
	_net = load("res://assets/data/net/net_config.tres") as NetConfig
	_track = TrackModel.new(_data)
	print("== track_check: %s (%s) ==" % [_data.display_name, track_id])
	_check_geometry()
	_check_widths()
	_check_grid()
	var main_run: Dictionary = _run_laps({})
	_report_run("(3) main line", main_run)
	var main_avg: float = _flying_avg(main_run)
	_check_ok("(3) main line completes %d laps within the walls" % _data.lap_count,
			main_run.finished and main_run.max_excess <= 0.05 and main_run.sinks == 0,
			"laps %s, max excess over a wall %.3f m, sinks %d" % [_fmt(main_run.times), main_run.max_excess, main_run.sinks])
	var savings: Dictionary = {}
	for bi in _track.branch_count():
		var b: TrackBranch = _data.branches[bi]
		var id: String = String(b.id)
		if _only != "" and id != _only:
			continue
		var run: Dictionary = _run_laps({"shortcut": id})
		_report_run("(4) %s" % id, run)
		var avg: float = _flying_avg(run)
		if b.type == &"lane_split":
			_check_lane(id, run, main_avg)
			continue
		# "Driven well" = the better of the autopilot's two good lines: drifting, or the careful
		# no-drift line (both steer the route exactly; neither is the sloppy driver below).
		var careful: Dictionary = _run_laps({"shortcut": id, "drift": false})
		var c_avg: float = _flying_avg(careful)
		print("     (info) careful no-drift line via %s: finished=%s flying lap %.2f s, wall hits %d, hard %d, sinks %d" % [
				id, str(careful.finished), c_avg, careful.wall_hits, careful.hard_hits, careful.sinks])
		var best_line: String = "drift"
		if careful.finished and careful.sinks == 0 and c_avg < avg:
			run = careful
			avg = c_avg
			best_line = "careful"
		_check_ok("(4) %s: 3 laps, exactly one lap each, branch driven, never in the water" % id,
				run.finished and run.times.size() == _data.lap_count and run.rejected == 0 and run.ticks_on_branch > 60 and run.sinks == 0,
				"ticks on branch %d, rejected line crossings %d, sinks %d" % [run.ticks_on_branch, run.rejected, run.sinks])
		_check_ok("(4) %s faster than main line when driven well" % id, run.finished and avg < main_avg,
				"best line %s: flying lap %.2f s vs main %.2f s, saving %.2f s" % [best_line, avg, main_avg, main_avg - avg])
		savings[id] = main_avg - avg
		var sloppy: Dictionary = _run_laps({"shortcut": id, "drift": false, "blind": 25.0})
		var s_avg: float = _flying_avg(sloppy)
		_check_ok("(5) sloppy driver (full throttle, no drift, straight at the entrance) via %s does not beat the main line" % id,
				(not sloppy.finished) or s_avg >= main_avg,
				"sloppy flying lap %.2f s vs main %.2f s (good run %.2f s), wall hits %d, hard hits %d, sinks %d" % [
						s_avg if sloppy.finished else -1.0, main_avg, avg, sloppy.wall_hits, sloppy.hard_hits, sloppy.sinks])
		savings[id + "_sloppy"] = main_avg - s_avg
		savings[id + "_sloppy_sinks"] = sloppy.sinks
	if _quick or _only != "":
		print("== quick run, %d failed ==" % _fails)
		quit(0)
		return
	_check_progress_jumps()
	_check_infield()
	_check_lap_counter()
	_check_hazards(main_run)
	_check_speed_gate()
	_check_pads(main_run, main_avg)
	_check_corners_and_lap(main_avg)
	_check_shortcut_savings(savings)
	_check_height()
	_check_movers()
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
	var top: Array = []
	for k in run.hit_buckets.keys():
		if int(run.hit_buckets[k]) >= 8:
			top.append("s%d:%d" % [int(k) * 20, int(run.hit_buckets[k])])
	if not top.is_empty():
		print("     %s wall-hit hot spots (20 m buckets, >= 8 hits): %s" % [label, " ".join(top)])
	print("     %s: finished=%s lap times %s, wall hits %d (hard %d), max_speed %.1f, max jump ratio %.2f, pads %d, sinks %d" % [
			label, str(run.finished), _fmt(run.times), run.wall_hits, run.hard_hits, run.max_speed, run.max_jump_ratio,
			run.pads, run.sinks])


# ---------------------------------------------------------------- (1) geometry
func _check_geometry() -> void:
	var lo: float = CASTLE_LENGTH.x if _castle else (DUNGEON_LENGTH.x if _dungeon else 600.0)
	var hi: float = CASTLE_LENGTH.y if _castle else (DUNGEON_LENGTH.y if _dungeon else 950.0)
	var len_ok: bool = _track.length >= lo and _track.length <= hi
	var gap: float = _track.point_at(_track.length - 0.01).distance_to(_track.point_at(0.0))
	_check_ok("(1) loop closure and length (%.0f-%.0f m)" % [lo, hi], gap < 0.1 and len_ok,
			"length %.1f m, closure gap %.3f m, %d samples, %d checkpoints" % [_track.length, gap, _track.points.size(), _track.checkpoint_s.size()])
	# No wall fold: the wall on the inside of every bend stays inside the bend radius.
	var worst: float = INF
	var worst_s: float = 0.0
	var pts: PackedVector2Array = _track.points
	var n: int = pts.size()
	for i in n:
		var a: Vector2 = pts[(i - 1 + n) % n]
		var b: Vector2 = pts[i]
		var c: Vector2 = pts[(i + 1) % n]
		var cr: float = (b - a).cross(c - b)
		var area2: float = absf((b - a).cross(c - a))
		if area2 <= 0.0001:
			continue
		var r: float = a.distance_to(b) * b.distance_to(c) * a.distance_to(c) / (2.0 * area2)
		var inner: float = _track.main.wall_pos[i] if cr > 0.0 else _track.main.wall_neg[i]
		if r - inner < worst:
			worst = r - inner
			worst_s = _track.cumulative[i]
	_check_ok("(1) no wall fold (bend radius minus inner wall offset > 0 everywhere)", worst > 0.0,
			"smallest margin %.1f m at s %.0f" % [worst, worst_s])
	for bi in _track.branch_count():
		var b: TrackModel.Path = _track.branches[bi]
		var ratio: float = (b.s_out - b.s_in) / b.length
		_check_ok("(1) branch %s sane" % b.id, ratio < _track.progress_rate_cap - 0.1 and b.s_out > b.s_in,
				"s %.0f..%.0f (%.0f m of main), branch %.0f m, progress ratio %.2f, half width %.2f..%.2f m" % [
						b.s_in, b.s_out, b.s_out - b.s_in, b.length, ratio, _min_arr(b.half), b.half_width])


func _min_arr(a: PackedFloat32Array) -> float:
	var m: float = INF
	for v in a:
		m = minf(m, v)
	return m


# ---------------------------------------------------------------- (9) per-point width
func _check_widths() -> void:
	var main: TrackModel.Path = _track.main
	var grid_back: float = _data.start_distance_behind_line + float((_net.max_racers - 1) / 2) * _net.grid_row_spacing + 6.0
	var grid_min: float = INF
	var narrow: float = INF
	var narrow_s: float = 0.0
	var wide: float = 0.0
	var wide_s: float = 0.0
	var steep: float = 0.0
	var steep_s: float = 0.0
	var n: int = main.points.size()
	for i in n:
		var s: float = main.cumulative[i]
		var w: float = main.half[i] * 2.0
		if s >= _track.length - grid_back or s <= 4.0:
			grid_min = minf(grid_min, w)
		if w < narrow:
			narrow = w
			narrow_s = s
		if w > wide:
			wide = w
			wide_s = s
		var ds: float = main.cumulative[i + 1] - s
		if ds > 0.001:
			var slope: float = absf(main.half[(i + 1) % n] - main.half[i]) / ds
			if slope > steep:
				steep = slope
				steep_s = s
	if not (_castle or _dungeon):
		print("     (9) skipped: %s has a constant width (%.1f m)" % [_data.track_id, wide])
		return
	_check_ok("(9) grid zone >= %.0f m wide" % GRID_MIN_WIDTH, grid_min >= GRID_MIN_WIDTH - 0.01,
			"narrowest grid width %.1f m over the last %.0f m and the line" % [grid_min, grid_back])
	_check_ok("(9) pinches present (<= %.0f m) and plazas wide" % PINCH_MAX_WIDTH, narrow <= PINCH_MAX_WIDTH and wide >= 20.0,
			"narrowest main road %.1f m at s %.0f, widest %.1f m at s %.0f" % [narrow, narrow_s, wide, wide_s])
	_check_ok("(9) no width jump (half width changes <= %.2f m per m)" % MAX_WIDTH_SLOPE, steep <= MAX_WIDTH_SLOPE,
			"steepest %.3f m/m at s %.0f (wall fold covered by (1))" % [steep, steep_s])


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
	var last_row_back: float = _data.start_distance_behind_line + float((_net.max_racers - 1) / 2) * _net.grid_row_spacing
	_check_ok("(2) start straight (grid run-up >= last row + 10 m, >= 15 m ahead)", behind >= last_row_back + 10.0 and ahead >= 15.0,
			"%.0f m straight behind the line, %.0f m ahead, half width at the line %.1f m" % [behind, ahead, _track.half_width_at(0.0)])
	var sims: Array[KartSim] = []
	var min_margin: float = INF
	for id in _net.max_racers:
		var s := KartSim.new(_stats)
		var dist: float = _track.length - _data.start_distance_behind_line - float(id / 2) * _net.grid_row_spacing
		s.reset_to(_track, dist, _net.grid_lateral * (1.0 if id % 2 == 0 else -1.0))
		var q: TrackModel.Query = _track.query(s.position, -1)
		min_margin = minf(min_margin, q.wall_offset - (absf(q.lateral) + _stats.bump_radius))
		sims.append(s)
	var min_gap: float = INF
	for i in sims.size():
		for j in range(i + 1, sims.size()):
			min_gap = minf(min_gap, KartSim.body_gap(sims[i], sims[j]))
	_check_ok("(2) 12 grid slots fit with margin and no overlap", min_margin >= 0.5 and min_gap > 0.0,
			"%d slots, min wall margin %.2f m, min body gap %.2f m, last row %.0f m behind the line" % [sims.size(), min_margin, min_gap, last_row_back])


# ---------------------------------------------------------------- driving runs
# Runs a driver for the race's laps. Options: shortcut (branch id, "" = main line), drift
# (bool), blind (meters of straight steering at the entrance), bot (use BotDriver), track
# (another TrackModel), dunk_s (main-loop distance where the kart is steered off the open edge
# once), dunk_side (+1/-1 side to steer toward).
func _run_laps(opt: Dictionary) -> Dictionary:
	var track: TrackModel = opt.get("track", _track)
	var sim := KartSim.new(_stats)
	var driver: AutopilotDriver = _make_bot() if opt.get("bot", false) else AutopilotDriver.new()
	driver.shortcut_id = StringName(opt.get("shortcut", ""))
	driver.allow_drift = opt.get("drift", true)
	driver.blind_entrance = opt.get("blind", 0.0)
	var dunk_s: float = opt.get("dunk_s", -1.0)
	var dunk_side: int = opt.get("dunk_side", 1)
	var input := KartInput.new()
	var laps := LapCounter.new(_data.lap_count, track.length, track.checkpoint_s)
	var run: Dictionary = {"finished": false, "times": [], "wall_hits": 0, "hard_hits": 0, "max_speed": 0.0,
			"max_jump_ratio": 0.0, "jump_violations": 0, "max_excess": -INF, "ticks_on_branch": 0,
			"rejected": 0, "limit": 0.0, "max_lateral_ratio_abs": 0.0, "pads": 0, "sinks": 0, "respawns": [],
			"hit_buckets": {}, "loops": 0, "bad_respawns": 0, "sink_durations": [], "laps_started": 0}
	var state: Dictionary = {"t": 0.0, "sank_at": -1.0, "last_respawn": -INF, "dunked": false}
	sim.wall_bumped.connect(func(hard: bool) -> void:
		run.wall_hits += 1
		var bucket: int = int(sim.track_s / 20.0)
		run.hit_buckets[bucket] = int(run.hit_buckets.get(bucket, 0)) + 1
		if hard:
			run.hard_hits += 1)
	sim.pad_boosted.connect(func() -> void: run.pads += 1)
	sim.sank.connect(func() -> void:
		run.sinks += 1
		state.sank_at = state.t
		if state.t - float(state.last_respawn) < RESPAWN_LOOP_WINDOW:
			run.loops += 1)
	sim.respawned.connect(func() -> void:
		state.last_respawn = state.t
		run.sink_durations.append(float(state.t) - float(state.sank_at))
		var q: TrackModel.Query = track.query(sim.position, -1)
		var ok: bool = track.excess_at(sim.position) <= 0.0 and absf(q.lateral) <= q.half_width + 0.01 \
				and not track.in_hazard(sim.position, q)
		run.respawns.append({"pos": sim.position, "s": sim.track_s, "ok": ok, "road": q.path})
		if not ok:
			run.bad_respawns += 1)
	laps.lap_started.connect(func(_l: int) -> void: run.laps_started += 1)
	var label: String = "bot" if opt.get("bot", false) else ("autopilot " + String(opt.get("shortcut", "main")))
	var collect: bool = not opt.has("dunk_s") and not opt.has("track")
	sim.landed.connect(func(_air: float, _impact: float) -> void:
		if not collect or sim.is_sinking():
			return
		_h_jumps += 1
		var lq: TrackModel.Query = track.query(sim.position, -1, sim.height)
		if not lq.on_deck or track.in_hazard(sim.position, lq, sim.speed, sim.height):
			_h_land_off += 1
			_h_land_off_at = "%s s=%.1f" % [label, sim.track_s])
	sim.reset_to(track, track.length - _data.start_distance_behind_line, 0.0)
	laps.reset(sim.track_s)
	var prev_s: float = sim.track_s
	var prev_pos: Vector2 = sim.position
	var max_lat: float = 0.0
	while state.t < MAX_RACE_SECONDS and not laps.is_finished:
		driver.time_to_go = 0.0
		driver.drive(input, sim, track, DT)
		if dunk_s >= 0.0 and not state.dunked and laps.lap == 1 and sim.track_path == TrackModel.MAIN_PATH \
				and sim.track_s >= dunk_s and sim.track_s < dunk_s + 60.0:
			input.steer = -float(dunk_side)
			input.drift = false
		if sim.is_sinking():
			state.dunked = true
		var was_sinking: bool = sim.is_sinking()
		sim.tick(DT, input, track)
		state.t += DT
		laps.update(sim.track_s, state.t)
		var moved: float = sim.position.distance_to(prev_pos)
		var ds: float = absf(wrapf(sim.track_s - prev_s, -track.length * 0.5, track.length * 0.5))
		var teleported: bool = was_sinking and not sim.is_sinking()
		if moved > 0.01 and not teleported:
			run.max_jump_ratio = maxf(run.max_jump_ratio, ds / moved)
		if ds > 2.0 * moved + 0.05 and not teleported:
			run.jump_violations += 1
		prev_s = sim.track_s
		prev_pos = sim.position
		run.max_speed = maxf(run.max_speed, sim.speed)
		if not sim.is_sinking():
			run.max_excess = maxf(run.max_excess, track.excess_at(sim.position))
		if collect and sim.grounded and not sim.is_sinking():
			var hq: TrackModel.Query = track.query(sim.position, -1, sim.height)
			var clear: float = sim.height - (hq.height if hq.on_deck else hq.support)
			if clear < MIN_CLEARANCE and _trace:
				print("       under t=%.2f %s s=%.1f path=%d q.path=%d h=%.3f surf=%.3f vy=%.2f slope=%.3f lat=%.2f speed=%.1f" % [
						state.t, label, sim.track_s, sim.track_path, hq.path, sim.height, hq.height, sim.vertical_velocity,
						hq.slope, hq.lateral, sim.speed])
			if clear < _h_min_clear:
				_h_min_clear = clear
				_h_min_at = "%s s=%.1f road %d" % [label, sim.track_s, hq.path]
		if sim.track_path >= 0:
			run.ticks_on_branch += 1
		var q: TrackModel.Query = track.query(sim.position, -1)
		max_lat = maxf(max_lat, absf(q.lateral))
		run.limit = q.wall_offset
		if _trace and laps.lap == 1 and int(state.t * 60.0) % 10 == 0 and sim.track_s > _trace_from and sim.track_s < _trace_from + 140.0:
			print("       trace t=%.2f s=%.1f path=%d lat=%.2f half=%.2f speed=%.1f boost=%.2f drift=%s" % [state.t, sim.track_s, sim.track_path, q.lateral, q.half_width, sim.speed, sim.boost_time, str(sim.drifting)])
	if collect:
		_h_runs += 1
		_h_progress_violations += int(run.jump_violations)
		_h_rejected += laps.rejected_crossings
	run.finished = laps.is_finished
	run.times = laps.lap_times
	run.rejected = laps.rejected_crossings
	run.max_lateral_ratio_abs = max_lat
	run.total = laps.total_time() if laps.is_finished else INF
	return run


# A BotDriver built like Main builds one (story 005): BotDriver.create with the bot set and a
# context for a lone bot (no rivals, first place, no item, no threat).
func _make_bot() -> BotDriver:
	var set: BotSet = load(BOT_SET_PATH) as BotSet
	if set == null:
		set = BotSet.new()
	var ctx := BotContext.new()
	ctx.racers_fn = func() -> Array: return []
	ctx.progress_fn = func(_id: int) -> float: return 0.0
	ctx.place_fn = func(_id: int) -> int: return 1
	ctx.held_fn = func(_id: int) -> StringName: return &""
	ctx.threat_fn = func(_id: int) -> float: return INF
	return BotDriver.create(set, 1, ctx, _data.lap_count, 0)


# ---------------------------------------------------------------- (10) lane split
func _check_lane(id: String, run: Dictionary, main_avg: float) -> void:
	var avg: float = _flying_avg(run)
	_check_ok("(10) lane split %s: autopilot completes %d laps in the other lane, one lap each" % [id, _data.lap_count],
			run.finished and run.times.size() == _data.lap_count and run.rejected == 0 and run.ticks_on_branch > 60 and run.sinks == 0,
			"ticks in the lane %d, refused line crossings %d, laps started %d" % [run.ticks_on_branch, run.rejected, run.laps_started])
	_check_ok("(10) lane split %s: progress monotonic (no jump), no shortcut (lap within 0.5 s of main)" % id,
			run.jump_violations == 0 and absf(avg - main_avg) <= 0.5,
			"largest ds/moved %.2f, violations %d, lane flying lap %.2f s vs main lane %.2f s" % [run.max_jump_ratio, run.jump_violations, avg, main_avg])


# ---------------------------------------------------------------- (11) hazards
func _check_hazards(main_run: Dictionary) -> void:
	if not _track.has_hazards():
		print("     (11) skipped: no hazards on %s" % _data.track_id)
		return
	# Every point a kart can reach beyond a road surface on an open edge must be water.
	var dry: int = 0
	var samples: int = 0
	var dry_at: Vector2 = Vector2.ZERO
	for e in _data.open_edges:
		var s: float = e.x
		while s <= e.y:
			var side: int = 1 if e.z > 0.0 else -1
			var p0: Vector2 = _track.point_at(s)
			var nrm: Vector2 = _track.normal_at(s) * float(side)
			var lat: float = _track.half_width_at(s) + _data.curb_width + 0.2
			while lat < _track.wall_offset_at(s, side) - 0.2:
				var p: Vector2 = p0 + nrm * lat
				samples += 1
				if not _track.on_surface(p) and not _track.in_hazard_area(p):
					dry += 1
					dry_at = p
				lat += 0.5
			s += 1.0
	for bi in _track.branch_count():
		var b: TrackBranch = _data.branches[bi]
		if b.open_edge_reach <= 0.0:
			continue
		var path: TrackModel.Path = _track.branches[bi]
		var d: float = 0.0
		while d <= path.length:
			var t: Vector2 = path.tangent_at(d)
			var nn: Vector2 = Vector2(-t.y, t.x)
			for side in [1.0, -1.0]:
				var lat: float = path.half_at(path.segment_at(d), 0.0) + b.curb_width + 0.2
				while lat < path.half_width + b.curb_width + b.open_edge_reach - 0.2:
					var p: Vector2 = path.point_at(d) + nn * side * lat
					samples += 1
					if _track.excess_at(p) <= 0.0 and not _track.on_surface(p) and not _track.in_hazard_area(p):
						dry += 1
						dry_at = p
					lat += 0.5
			d += 1.0
	_check_ok("(11) open edges: every reachable off-road point there is water", dry == 0,
			"%d sample points, %d dry (last at %s)" % [samples, dry, str(dry_at)])
	# Steer off the open moat edge once on lap 1.
	var e0: Vector3 = _data.open_edges[0]
	var dunk: Dictionary = _run_laps({"dunk_s": e0.x + 25.0, "dunk_side": 1 if e0.z > 0.0 else -1})
	var durations: Array = dunk.sink_durations
	var dur_ok: bool = durations.size() > 0
	for v in durations:
		dur_ok = dur_ok and absf(float(v) - _data.respawn_sink_time) <= 2.0 * DT
	_check_ok("(11) kart steered off the moat edge sinks, respawns after %.1f s on the road (not in a wall, not in water)" % _data.respawn_sink_time,
			dunk.sinks >= 1 and dur_ok and dunk.bad_respawns == 0 and dunk.respawns.size() == dunk.sinks,
			"sinks %d, respawns %d, sink durations %s, bad respawn points %d, first respawn at s %.1f" % [
					dunk.sinks, dunk.respawns.size(), _fmt(durations), dunk.bad_respawns,
					float(dunk.respawns[0].s) if dunk.respawns.size() > 0 else -1.0])
	_check_ok("(11) no respawn loop, no lap gained, race still finishes",
			dunk.loops == 0 and dunk.finished and dunk.times.size() == _data.lap_count and dunk.rejected == 0 and float(dunk.total) > float(main_run.total),
			"re-sinks within %.0f s of a respawn %d, laps %s, total %.2f s vs clean %.2f s, refused crossings %d" % [
					RESPAWN_LOOP_WINDOW, dunk.loops, _fmt(dunk.times), float(dunk.total), float(main_run.total), dunk.rejected])
	var bot: Dictionary = _run_laps({"bot": true})
	_check_ok("(11) main-line autopilot and BotDriver never fall in over %d laps" % _data.lap_count,
			main_run.sinks == 0 and bot.sinks == 0 and bot.finished,
			"autopilot sinks %d, BotDriver sinks %d (laps %s)" % [main_run.sinks, bot.sinks, _fmt(bot.times)])


# ---------------------------------------------------------------- (12) boost pads
func _check_pads(main_run: Dictionary, main_avg: float) -> void:
	if _data.boost_pads.is_empty():
		print("     (12) skipped: no boost pads on %s" % _data.track_id)
		return
	var bare: TrackData = _data.duplicate() as TrackData
	var no_pad_list: Array[TrackPad] = []
	bare.boost_pads = no_pad_list
	var no_pads: Dictionary = _run_laps({"track": TrackModel.new(bare)})
	var bare_avg: float = _flying_avg(no_pads)
	_check_ok("(12) boost pads trigger on the main line and the lap is faster with them",
			main_run.pads > 0 and main_avg < bare_avg,
			"pads hit %d over %d laps (%d pads, %.1f s boost each), flying lap %.2f s with pads vs %.2f s without (%.2f s gained)" % [
					main_run.pads, _data.lap_count, _data.boost_pads.size(), _data.boost_pad_time, main_avg, bare_avg, bare_avg - main_avg])


# ---------------------------------------------------------------- (13) corners and lap time
func _check_corners_and_lap(main_avg: float) -> void:
	var step: float = 1.0
	var curv: PackedFloat32Array = PackedFloat32Array()
	var s: float = 0.0
	while s < _track.length:
		var a: Vector2 = _street_tangent(s - 2.0)
		var b: Vector2 = _street_tangent(s + 2.0)
		curv.append(a.angle_to(b) / 4.0)
		s += step
	var n: int = curv.size()
	# Contiguous runs of the same bend direction with radius under 250 m; small gaps merged.
	var start: int = 0
	while start < n and absf(curv[start]) > 1.0 / 250.0:
		start += 1
	var arcs: Array[Dictionary] = []
	var i: int = 0
	while i < n:
		var k: int = (start + i) % n
		var c: float = curv[k]
		if absf(c) <= 1.0 / 250.0:
			i += 1
			continue
		var sg: float = signf(c)
		var turn: float = 0.0
		var min_r: float = INF
		var j: int = i
		var gap: int = 0
		while j < n:
			var kk: int = (start + j) % n
			var cc: float = curv[kk]
			if absf(cc) > 1.0 / 250.0 and signf(cc) == sg:
				turn += cc * step
				min_r = minf(min_r, 1.0 / absf(cc))
				gap = 0
			else:
				gap += 1
				if gap > 3:
					break
			j += 1
		var deg: float = rad_to_deg(absf(turn))
		if deg >= 7.0:
			arcs.append({"s": float((start + i) % n) * step, "deg": deg, "dir": "R" if sg > 0.0 else "L", "r": min_r, "end": float((start + j - gap) % n) * step})
		i = j
	# An S-bend or chicane (two opposite arcs under 70 degrees each, closer than 25 m) is one corner.
	var corners: Array[String] = []
	var used: Array[bool] = []
	used.resize(arcs.size())
	used.fill(false)
	for a_i in arcs.size():
		if used[a_i]:
			continue
		var a: Dictionary = arcs[a_i]
		if a_i + 1 < arcs.size():
			var b: Dictionary = arcs[a_i + 1]
			if b.dir != a.dir and float(a.deg) < 70.0 and float(b.deg) < 70.0 and float(b.s) - float(a.end) < 25.0:
				used[a_i + 1] = true
				corners.append("S/chicane %s%s @%.0f" % [a.dir, b.dir, a.s])
				continue
		var kind: String = "kink"
		if float(a.deg) >= SPIRAL_MIN_DEG:
			kind = "spiral"
		elif float(a.deg) >= 150.0 and float(a.r) < 20.0 and float(a.end) - float(a.s) < 60.0:
			kind = "hairpin"
		elif float(a.r) < 30.0 and float(a.deg) >= 60.0:
			kind = "90"
		elif float(a.deg) >= 40.0:
			kind = "sweeper"
		corners.append("%s %s %.0f deg R%.0f @%.0f" % [kind, a.dir, a.deg, a.r, a.s])
	if not (_castle or _dungeon):
		print("     (13) %d corners: %s; flying lap %.2f s" % [corners.size(), ", ".join(corners), main_avg])
		return
	var cr: Vector2i = DUNGEON_CORNERS if _dungeon else CASTLE_CORNERS
	_check_ok("(13) corner count %d-%d (doc ~%d)" % [cr.x, cr.y, 15 if _dungeon else 13],
			corners.size() >= cr.x and corners.size() <= cr.y,
			"%d corners (%d arcs): %s" % [corners.size(), arcs.size(), "; ".join(corners)])
	# Reported, not gated: the doc's 45-50 s assumes an average of 20-23 m/s, and this kart's
	# autopilot averages more (see the line); the length target (1) is the gate.
	var inside: bool = _dungeon or (main_avg >= CASTLE_LAP.x and main_avg <= CASTLE_LAP.y)
	print("%s (13) autopilot flying lap vs doc target %.0f-%.0f s: %.2f s over %.0f m (average %.1f m/s; doc assumed 20-23 m/s)" % [
			"INFO" if inside else "INFO-OUTSIDE-TARGET", CASTLE_LAP.x, CASTLE_LAP.y, main_avg, _track.length, _track.length / main_avg])


# Direction of the street at main-loop distance [param s]: in a lane split the middle between
# the two lanes (the main centerline's lane change is not a corner).
func _street_tangent(s: float) -> Vector2:
	return (_street_point(s + 1.0) - _street_point(s - 1.0)).normalized()


func _street_point(s: float) -> Vector2:
	var sv: float = fposmod(s, _track.length)
	var sum: Vector2 = _track.point_at(sv)
	var count: int = 1
	for bi in _track.branch_count():
		var b: TrackModel.Path = _track.branches[bi]
		if _data.branches[bi].type == &"lane_split" and sv > b.s_in and sv < b.s_out:
			sum += _track.branch_point_at(bi, _track.branch_distance_for_s(bi, sv))
			count += 1
	return sum / float(count)  # two lanes: their middle; three lanes: the middle lane


# ---------------------------------------------------------------- (14) shortcut savings
func _check_shortcut_savings(savings: Dictionary) -> void:
	for bi in _track.branch_count():
		var b: TrackBranch = _data.branches[bi]
		if b.type == &"lane_split":
			continue
		var id: String = String(b.id)
		if not savings.has(id):
			continue
		var good: float = savings[id]
		var sloppy: float = savings.get(id + "_sloppy", -INF)
		_check_ok("(14) %s driven well saves roughly the doc's time (%.1f-%.1f s)" % [id, SHORTCUT_SAVING.x, SHORTCUT_SAVING.y],
				good >= SHORTCUT_SAVING.x and good <= SHORTCUT_SAVING.y,
				"saving %.2f s per lap; sloppy run %s (sinks %d)" % [good,
						("loses %.2f s" % -sloppy) if is_finite(sloppy) and sloppy <= 0.0 else ("saves %.2f s" % sloppy if is_finite(sloppy) else "did not finish"),
						int(savings.get(id + "_sloppy_sinks", 0))])


# ---------------------------------------------------------------- (6) progress monotonicity
func _check_progress_jumps() -> void:
	var worst: float = 0.0
	var viol: int = 0
	var runs: Array[String] = [""]
	for bi in _track.branch_count():
		runs.append(String(_data.branches[bi].id))
	for id in runs:
		var r: Dictionary = _run_laps({"shortcut": id})
		worst = maxf(worst, r.max_jump_ratio)
		viol += int(r.jump_violations)
	_check_ok("(6) track_s never jumps more than 2x the distance moved (incl. branch entry/exit)", viol == 0,
			"%d runs (main + each branch), largest ds/moved %.2f, violations %d" % [runs.size(), worst, viol])


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
		# Story 008 part 5: the start is on the ground; with its height the query picks the ground
		# level next to the Barbican Spiral's crossing, not the gatehouse deck above it.
		sim.height = maxf(_data.ground_y, 0.0)
		sim.track_s = _track.query(p, -1, sim.height).s
		var laps := LapCounter.new(_data.lap_count, _track.length, _track.checkpoint_s)
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
			if sim.is_sinking():
				continue
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
	var lc2 := LapCounter.new(3, len, cps)
	lc2.reset(len - 6.0)
	lc2.update(2.0, 0.0)
	lc2.update(len * 0.4, 1.0)
	lc2.resync(len - 20.0)
	lc2.update(len - 10.0, 2.0)
	lc2.update(3.0, 3.0)
	_check_ok("(8) crossing the line without the checkpoints is not a lap", lc2.lap == 1 and lc2.rejected_crossings == 1,
			"lap %d, refused crossings %d, checkpoints passed %d of %d" % [lc2.lap, lc2.rejected_crossings, lc2.checkpoints_passed(), lc2.checkpoint_total()])
	var lc3 := LapCounter.new(3, len, cps)
	lc3.reset(len - 6.0)
	var s3: float = len - 6.0
	var steps: int = int((len + 12.0) / 5.0) + 2
	for i in steps:
		s3 = fposmod(s3 + 5.0, len)
		lc3.update(s3, float(i))
	_check_ok("(8) a full lap counts exactly once", lc3.lap == 2 and lc3.lap_times.size() == 1,
			"lap %d, completed laps %d, refused crossings %d" % [lc3.lap, lc3.lap_times.size(), lc3.rejected_crossings])


# ---------------------------------------------------------------- (15) speed gate (lava gap)
# A kart driven straight along the gated branch toward the strip: fast (boosting) crosses, slow
# sinks and respawns on the main road, safely and without a loop.
func _check_speed_gate() -> void:
	var gi: int = -1
	for i in _track.hazard_gates.size():
		if _track.hazard_gates[i] > 0.0:
			gi = i
	if gi < 0:
		return
	var rect: Rect2 = _track.hazard_bounds[gi]
	var center: Vector2 = rect.get_center()
	var bi: int = -1
	var best: float = INF
	for i in _track.branch_count():
		var d: float = _track.distance_to_path(center, i)
		if d < best:
			best = d
			bi = i
	var path: TrackModel.Path = _track.branches[bi]
	var u_gap: float = _track.branch_along(bi, center)
	var gate: float = _track.hazard_gates[gi]
	var fast: Dictionary = _gate_probe(bi, u_gap, gate + 3.0, true)
	var slow: Dictionary = _gate_probe(bi, u_gap, gate - 6.0, false)
	var mid: Dictionary = _gate_probe(bi, u_gap, gate - 0.5, false)
	_check_ok("(15) speed gate %.1f m/s on %s: at %.1f m/s crosses; at %.1f and %.1f m/s sinks" % [gate, path.id, gate + 3.0, gate - 0.5, gate - 6.0],
			fast.sinks == 0 and fast.crossed and slow.sinks >= 1 and mid.sinks >= 1,
			"fast: sinks %d, crossed %s; %.1f m/s: sinks %d; %.1f m/s: sinks %d" % [fast.sinks, str(fast.crossed), gate - 0.5, mid.sinks, gate - 6.0, slow.sinks])
	_check_ok("(15) after sinking in the gap the kart respawns on the main road, safe, once, with immunity",
			slow.sinks == 1 and slow.respawns == 1 and slow.ok and slow.road == TrackModel.MAIN_PATH and slow.immune,
			"sinks %d, respawns %d, safe %s, road %d (main = -1), immune %s, sink time %.2f s" % [slow.sinks, slow.respawns, str(slow.ok), slow.road, str(slow.immune), slow.sink_time])


func _gate_probe(bi: int, u_gap: float, speed: float, boosting: bool) -> Dictionary:
	var path: TrackModel.Path = _track.branches[bi]
	var sim := KartSim.new(_stats)
	sim.reset_to(_track, 0.0, 0.0)
	var d0: float = u_gap - 14.0
	var t: Vector2 = path.tangent_at(d0)
	sim.position = path.point_at(d0)
	sim.yaw = atan2(-t.x, -t.y)
	sim._segment_hint = -1
	sim.speed = speed
	sim.velocity = sim.forward() * speed
	sim.track_s = _track.query(sim.position, -1).s
	if boosting:
		sim.boost_time = 1.2
	var res: Dictionary = {"sinks": 0, "respawns": 0, "ok": false, "road": -2, "immune": false, "crossed": false, "sink_time": 0.0}
	sim.sank.connect(func() -> void: res.sinks += 1)
	sim.respawned.connect(func() -> void:
		res.respawns += 1
		var q: TrackModel.Query = _track.query(sim.position, -1)
		res.ok = _track.excess_at(sim.position) <= 0.0 and not _track.in_hazard(sim.position, q)
		res.road = q.path
		res.immune = sim.is_hit_immune())
	var input := KartInput.new()
	var time: float = 0.0
	var sink_start: float = -1.0
	while time < 6.0:
		input.throttle = 1.0 if boosting else 0.0  # the slow probes coast: they must not re-accelerate past the gate
		input.steer = 0.0
		var was: bool = sim.is_sinking()
		sim.tick(DT, input, _track)
		time += DT
		if sim.is_sinking() and not was:
			sink_start = time
		if was and not sim.is_sinking():
			res.sink_time = time - sink_start
		if _track.branch_along(bi, sim.position) > u_gap + GATE_PAST and sim.track_path == bi and res.sinks == 0:
			res.crossed = true
			break
	return res


# ---------------------------------------------------------------- (16) height (story 008 part 4)
# Driven: grounded karts never below the road over every lap driven above (autopilot lines and the
# bot); every jump lands on a road deck (not off the road, not in a hazard); progress stays
# continuous and checkpoints in order (a crossover never mixes levels). Static: grades and banks
# within the documented limits; every road sample queried at its own height finds its own level;
# no deck cuts through another (overlapping roads are one level, a junction, or at least
# level_separation apart, a crossover).
func _check_height() -> void:
	_check_ok("(16) grounded karts never below the road surface (min clearance >= %.2f m)" % MIN_CLEARANCE,
			_h_min_clear >= MIN_CLEARANCE,
			"%d runs, min clearance %.3f m (%s)" % [_h_runs, _h_min_clear, _h_min_at])
	_check_ok("(16) every jump lands on the road", _h_land_off == 0,
			"%d landings over those runs, %d off the road or in a hazard%s" % [_h_jumps, _h_land_off,
					(" (last " + _h_land_off_at + ")") if _h_land_off > 0 else ""])
	_check_ok("(16) progress continuous and checkpoints in order on every run (levels never mixed)",
			_h_progress_violations == 0 and _h_rejected == 0,
			"track_s jumps %d, refused line crossings %d" % [_h_progress_violations, _h_rejected])
	var roads: Array[TrackModel.Path] = [_track.main]
	roads.append_array(_track.branches)
	var worst_grade: float = 0.0
	var worst_grade_at: String = ""
	var worst_bank: float = 0.0
	var worst_bank_at: String = ""
	for path in roads:
		for i in path.points.size():
			if absf(path.slope[i]) > absf(worst_grade):
				worst_grade = path.slope[i]
				worst_grade_at = "road %d at %.0f m" % [path.index, path.cumulative[mini(i, path.cumulative.size() - 1)]]
			if absf(path.bank[i]) > absf(worst_bank):
				worst_bank = path.bank[i]
				worst_bank_at = "road %d at %.0f m" % [path.index, path.cumulative[mini(i, path.cumulative.size() - 1)]]
	_check_ok("(16) grades within %.0f %% and banks within %.0f degrees" % [MAX_GRADE * 100.0, MAX_BANK_DEG],
			absf(worst_grade) <= MAX_GRADE + 0.0005 and rad_to_deg(absf(worst_bank)) <= MAX_BANK_DEG + 0.05,
			"max grade %.1f %% (%s), max bank %.1f deg (%s)" % [worst_grade * 100.0, worst_grade_at,
					rad_to_deg(worst_bank), worst_bank_at])
	var samples: int = 0
	var mixed: int = 0
	var mixed_at: String = ""
	var cut: int = 0
	var cut_at: String = ""
	var crossings: int = 0
	var sep: float = _data.level_separation
	for path in roads:
		var d: float = 0.0
		while d < path.length:
			var stv: Vector2 = path.seg_t_at(d)
			var c: Vector2 = path.point_at(d)
			var t: Vector2 = path.tangent_at(d)
			var nn: Vector2 = Vector2(-t.y, t.x)
			var half: float = path.half_at(int(stv.x), stv.y)
			for lat in [0.0, half * 0.9, -half * 0.9]:
				var p: Vector2 = c + nn * lat
				var y: float = path.surface_y(int(stv.x), stv.y, lat)
				samples += 1
				var q: TrackModel.Query = _track.query(p, -1, y)
				if absf(q.height - q.ramp_rise - y) > JUNCTION_TOLERANCE:
					mixed += 1
					mixed_at = "road %d at %.0f m lat %.1f: own %.2f, query %.2f (road %d)" % [path.index, d, lat, y, q.height, q.path]
				# Story 008 part 5: the main loop crosses itself (Barbican Spiral over the gate arch).
				if path.closed:
					var self_hit: Vector2 = _self_level_probe(path, d, p, y, sep)
					if self_hit.x > 0.5:
						crossings += 1
					if self_hit.y > 0.5:
						cut += 1
						cut_at = "road %d at %.0f m crosses itself at its own level (%.2f)" % [path.index, d, y]
				for other in roads:
					if other == path or not other.bounds.has_point(p):
						continue
					var h: TrackModel.Hit = other.nearest_filtered(p, y - sep, y + sep)
					var below: TrackModel.Hit = other.nearest_filtered(p, -INF, y - sep)
					if below != null and below.excess <= 0.0:
						crossings += 1
					if h == null or h.excess > 0.0:
						continue
					var oy: float = other.surface_y(h.seg, h.t, float(h.side) * h.dist)
					if absf(oy - y) > JUNCTION_TOLERANCE:
						cut += 1
						cut_at = "road %d at %.0f m vs road %d: %.2f vs %.2f" % [path.index, d, other.index, y, oy]
			d += HEIGHT_PROBE_STEP
	_check_ok("(16) a query at a road's own height finds that level (stacked roads never mixed)", mixed == 0,
			"%d samples, %d found another level%s" % [samples, mixed, (" (last " + mixed_at + ")") if mixed > 0 else ""])
	_check_ok("(16) no road deck cuts through another (overlaps are junctions at one level or crossovers)", cut == 0,
			"%d samples, %d cuts, %d samples over a road below (crossovers)%s" % [samples, cut, crossings,
					(" (last " + cut_at + ")") if cut > 0 else ""])
	if _castle:
		_check_ok("(16) the Barbican Spiral crossover exists (samples over a road below > 0, none mixed)",
				crossings > 0 and mixed == 0, "%d samples over a road below, %d mixed" % [crossings, mixed])


# Story 008 part 5: the main loop against its OTHER pass (samples further than SELF_CROSS_MIN_GAP
# along the loop) at [param p]. x = 1 when that pass's corridor holds p at least [param sep] below
# [param y] (a crossover sample), y = 1 when it holds p at a height that is neither within
# JUNCTION_TOLERANCE of y nor [param sep] away (a deck cutting through the other pass).
func _self_level_probe(path: TrackModel.Path, d: float, p: Vector2, y: float, sep: float) -> Vector2:
	var out := Vector2.ZERO
	var n: int = path.points.size()
	for i in path.segment_count():
		var gap: float = absf(path.cumulative[i] - d)
		if minf(gap, path.length - gap) < SELF_CROSS_MIN_GAP:
			continue
		var a: Vector2 = path.points[i]
		var ab: Vector2 = path.points[(i + 1) % n] - a
		var l2: float = ab.length_squared()
		var t: float = clampf((p - a).dot(ab) / l2, 0.0, 1.0) if l2 > 0.0 else 0.0
		var off: Vector2 = p - (a + ab * t)
		var side: int = 1 if off.dot(Vector2(-ab.y, ab.x)) >= 0.0 else -1
		if off.length() - path.wall_at(i, t, side) > 0.0:
			continue
		var lat: float = off.dot(Vector2(-ab.y, ab.x).normalized()) if l2 > 0.0 else 0.0
		var oy: float = path.surface_y(i, t, lat)
		if oy <= y - sep:
			out.x = 1.0
		elif absf(oy - y) > JUNCTION_TOLERANCE and absf(oy - y) < sep:
			out.y = 1.0
	return out


# ---------------------------------------------------------------- (17) timed hazards (story 009)
## Seconds between samples when scanning a mover's schedule.
const MOVER_SCAN_STEP: float = 0.05

func _check_movers() -> void:
	if _data.movers.is_empty():
		print("     (17) skipped: no timed hazards on %s" % _data.track_id)
		return
	var hm := HazardManager.new()
	hm.setup(_track)
	for i in hm.count():
		var m: TrackMover = hm.mover(i)
		_check_ok("(17) mover %s: schedule consistent" % m.id, m.validate() == "", m.validate())
		var span: float = maxf(m.period * 3.0, MOVER_SCAN_STEP)
		var blocked_n: int = 0
		var main_blocked_n: int = 0
		var n: int = 0
		var run_len: float = 0.0
		var longest_closed: float = 0.0
		var longest_open: float = 0.0
		var cur: bool = hm.is_active(m, 0.0)
		var t: float = 0.0
		while t < span:
			var act: bool = hm.is_active(m, t)
			n += 1
			if act:
				blocked_n += 1
				if hm.path_index(i) == TrackModel.MAIN_PATH and m.kind == &"gate":
					main_blocked_n += 1
			if act == cur:
				run_len += MOVER_SCAN_STEP
			else:
				if cur:
					longest_closed = maxf(longest_closed, run_len)
				else:
					longest_open = maxf(longest_open, run_len)
				cur = act
				run_len = MOVER_SCAN_STEP
			t += MOVER_SCAN_STEP
		var frac: float = hm.blocked_fraction(m)
		print("     (17) %s: blocked %.1f %% of the time (scan %.1f %%), longest closed %.2f s, longest open %.2f s, period %.1f s" % [
				m.id, frac * 100.0, 100.0 * float(blocked_n) / float(n), longest_closed, longest_open, m.period])
		_check_ok("(17) %s never blocks the main road" % m.id, main_blocked_n == 0 and hm.path_index(i) != TrackModel.MAIN_PATH or m.kind != &"gate",
				"%d of %d samples with a gate blocking the main road" % [main_blocked_n, n])
		if m.kind == &"gate":
			_check_ok("(17) %s open at least %.0f %% and closed at least %.0f %% of the time" % [m.id, m.min_open_fraction * 100.0, m.min_blocked_fraction * 100.0],
					1.0 - frac >= m.min_open_fraction and frac >= m.min_blocked_fraction,
					"open %.1f %%, closed %.1f %%" % [(1.0 - frac) * 100.0, frac * 100.0])
			_check_ok("(17) %s deck lies on its branch and inside it" % m.id,
					hm.path_index(i) >= 0 and m.path_from >= 0.0 and m.path_to <= _track.branch_length(hm.path_index(i)) and m.path_from < m.path_to,
					"deck %.1f..%.1f of %.1f m" % [m.path_from, m.path_to, _track.branch_length(maxi(hm.path_index(i), 0))])
			if m.out_of_phase_with != &"":
				_check_out_of_phase(hm, m, span)
		if m.is_traveler():
			var road: TrackModel.Path = _track.path_of(hm.path_index(i))
			var worst_lane: float = 0.0
			var d: float = m.path_from
			while d <= m.path_to:
				var st: Vector2 = road.seg_t_at(d)
				worst_lane = maxf(worst_lane, absf(m.lane_offset) + m.body_radius - road.half_at(int(st.x), st.y))
				d += 1.0
			_check_ok("(17) %s rolls on its road, its body inside the road surface" % m.id,
					m.path_from >= 0.0 and m.path_to <= road.length and m.path_from < m.path_to and worst_lane <= 0.0,
					"run %.1f..%.1f of %.1f m, body out by %.2f m" % [m.path_from, m.path_to, road.length, worst_lane])
	_check_travelers_leave_room(hm)
	hm.free()


## Seconds scanned for the barrel cross-sections, in periods of the longest traveler period.
const TRAVELER_SCAN_PERIODS: float = 3.0

# (17) Rolling bodies never close a road: at every sampled moment, at the cross-section of every
# rolling body, the union of all bodies' hit circles (radius hit_radius) over the road surface leaves
# a free gap at least min_free_gap wide (the main road is never fully blocked).
func _check_travelers_leave_room(hm: HazardManager) -> void:
	var idx: Array[int] = []
	var longest: float = 0.0
	for i in hm.count():
		if hm.mover(i).is_traveler():
			idx.append(i)
			longest = maxf(longest, hm.mover(i).period)
	if idx.is_empty():
		return
	var worst_gap: float = INF
	var worst_at: String = ""
	var bad: int = 0
	var samples: int = 0
	var t: float = 0.0
	while t < maxf(longest, MOVER_SCAN_STEP) * TRAVELER_SCAN_PERIODS:
		for a in idx:
			var ma: TrackMover = hm.mover(a)
			if not hm.is_active(ma, t):
				continue
			samples += 1
			var pa: int = hm.path_index(a)
			var road: TrackModel.Path = _track.path_of(pa)
			var da: float = hm.distance_at(ma, t)
			var st: Vector2 = road.seg_t_at(da)
			var half: float = road.half_at(int(st.x), st.y)
			var spans: Array[Vector2] = []
			for b in idx:
				var mb: TrackMover = hm.mover(b)
				if hm.path_index(b) != pa or not hm.is_active(mb, t):
					continue
				var dd: float = absf(hm.distance_at(mb, t) - da)
				if dd >= mb.hit_radius:
					continue
				var w: float = sqrt(mb.hit_radius * mb.hit_radius - dd * dd)
				spans.append(Vector2(mb.lane_offset - w, mb.lane_offset + w))
			spans.sort_custom(func(u: Vector2, v: Vector2) -> bool: return u.x < v.x)
			var gap: float = 0.0
			var edge: float = -half
			for sp in spans:
				gap = maxf(gap, sp.x - edge)
				edge = maxf(edge, sp.y)
			gap = maxf(gap, half - edge)
			if gap < worst_gap:
				worst_gap = gap
				worst_at = "t=%.2f %s at %.1f m" % [t, ma.id, da]
			if gap < ma.min_free_gap:
				bad += 1
		t += MOVER_SCAN_STEP
	print("     (17) rolling bodies: %d cross-sections, narrowest free gap %.2f m (%s)" % [samples, worst_gap, worst_at])
	_check_ok("(17) rolling bodies always leave a free lane (gap >= min_free_gap)", bad == 0,
			"%d of %d cross-sections narrower" % [bad, samples])


# (17) Two gates that must not be closed together (the drawbridge and the portcullis).
func _check_out_of_phase(hm: HazardManager, m: TrackMover, span: float) -> void:
	var oi: int = hm.index_of(m.out_of_phase_with)
	if oi < 0:
		_check_ok("(17) %s: out_of_phase_with %s exists" % [m.id, m.out_of_phase_with], false, "no such mover")
		return
	var o: TrackMover = hm.mover(oi)
	var both: int = 0
	var closest: float = INF
	var last_a: float = -INF
	var last_b: float = -INF
	var t: float = 0.0
	var scan: float = maxf(span, maxf(o.period, m.period) * TRAVELER_SCAN_PERIODS)
	while t < scan:
		var a: bool = hm.is_active(m, t)
		var b: bool = hm.is_active(o, t)
		if a and b:
			both += 1
		if a:
			last_a = t
			closest = minf(closest, t - last_b)
		if b:
			last_b = t
			closest = minf(closest, t - last_a)
		t += MOVER_SCAN_STEP
	print("     (17) %s vs %s: closed together %.2f s, shortest time between one closing and the other %.2f s" % [
			m.id, o.id, float(both) * MOVER_SCAN_STEP, closest])
	_check_ok("(17) %s and %s are never closed at the same time" % [m.id, o.id], both == 0,
			"%d samples with both closed" % both)
