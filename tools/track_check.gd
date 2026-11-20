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
const CASTLE_LENGTH: Vector2 = Vector2(1000.0, 1150.0)
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
	var driver: AutopilotDriver = BotDriver.new() if opt.get("bot", false) else AutopilotDriver.new()
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
		if sim.track_path >= 0:
			run.ticks_on_branch += 1
		var q: TrackModel.Query = track.query(sim.position, -1)
		max_lat = maxf(max_lat, absf(q.lateral))
		run.limit = q.wall_offset
		if _trace and laps.lap == 1 and int(state.t * 60.0) % 10 == 0 and sim.track_s > _trace_from and sim.track_s < _trace_from + 140.0:
			print("       trace t=%.2f s=%.1f path=%d lat=%.2f half=%.2f speed=%.1f boost=%.2f drift=%s" % [state.t, sim.track_s, sim.track_path, q.lateral, q.half_width, sim.speed, sim.boost_time, str(sim.drifting)])
	run.finished = laps.is_finished
	run.times = laps.lap_times
	run.rejected = laps.rejected_crossings
	run.max_lateral_ratio_abs = max_lat
	run.total = laps.total_time() if laps.is_finished else INF
	return run


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
		if float(a.deg) >= 150.0 and float(a.r) < 20.0 and float(a.end) - float(a.s) < 60.0:
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
		sim.track_s = _track.query(p, -1).s
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
