extends SceneTree
## Per-system tick profiler for the frozen 2.5D game (core-rebuild story 001, perf-per-system.md).
## MEASUREMENT TOOL: it runs the real main scene and changes no game file. During NET_RACE it turns
## Main's own _physics_process off and runs a line-for-line copy of Main._net_tick / _tick_owned
## (src/legacy/main.gd) from here, with a microsecond stamp around each call, so every stage of
## the host's tick is timed from outside. The copy calls the same objects in the same order; the
## --trace-out mode proves it (the trace must be IDENTICAL to golden/bots_castle_circuit.csv).
##
## Run (real time, as the perf baseline):
##   godot --headless --path . -s res://tools/profile_tick.gd -- --perf-out=PATH.csv \
##       --host --port=24690 --players=1 --bots=11 --autopilot --quit-after-race --laps=1 \
##       --track=castle_circuit --race-seed=1001
##
## Tool switches (all others go to the game):
##   --perf-out=PATH       per-tick stage times (ms), one row per race tick
##   --proc-out=PATH       per-frame _process time (ms) and KartVisual cost, one row per frame
##   --trace-out=PATH      golden-trace rows (same format as tools/capture_traces.gd) for the fidelity check
##   --replica=0           do not take over Main's tick (only the bracket timing); default 1
##   --profile-scripts     enable the GDScript profiler (needs -d) from the first race tick to quit
##
## Stage columns (ms per tick): hazards = HazardManager.update + _hazard_trace; drive_auto /
## drive_bots = KartDriver.drive of the autopilot / of the 11 bots; sim = KartSim.tick of every
## owned kart (+ StartSequence, apply_start); laps_rank = LapCounter.update + _rank_key; remote =
## RemoteKart work (none in this setup); ranking = RaceRanking.update; contacts =
## _resolve_kart_contacts; separate = _separate_karts (push-apart passes + clamp_to_walls);
## measure = _measure_contacts (debug stats); items = ItemManager.update; net_send = KartWire.pack +
## NetSession.send_state; debug = _net_log_tick, height and surface logs; finish = _finish_check.

const MODE_SOLO: int = 0
const MODE_NET_RACE: int = 3
const RECORDER_PRIORITY: int = 1000000
const TRACE_HEADER: String = "tick,kart,race_time,x,z,height,speed,yaw,track_s,drifting,drift_dir,drift_tier,boost,lap,lap_times"
const STAGES: PackedStringArray = ["hazards", "drive_auto", "drive_bots", "sim", "laps_rank", "remote",
		"ranking", "contacts", "separate", "measure", "items", "net_send", "debug", "finish"]
const PERF_HEADER_HEAD: String = "tick,tick_ms,replica_ms,engine_physics_ms,karts,"
const PERF_HEADER_TAIL: String = ",sim_max_kart_ms,drive_bot_max_ms"

var _main: Node
var _perf_out: String = ""
var _proc_out: String = ""
var _trace_out: String = ""
var _replica: bool = true
var _profile_scripts: bool = false
var _profiling: bool = false
var _perf_rows: PackedStringArray = PackedStringArray()
var _proc_rows: PackedStringArray = PackedStringArray()
var _trace_rows: PackedStringArray = PackedStringArray()
var _ticks: int = 0
var _written: bool = false
var _tick_start_us: int = 0
var _proc_start_us: int = 0
var _replica_us: int = 0
var _replica_ran: bool = false
## Microseconds per stage this tick, indexed like STAGES.
var _us: PackedInt64Array = PackedInt64Array()
var _sim_max_us: int = 0
var _drive_bot_max_us: int = 0


## Calls [member on_tick] every physics tick (or every frame when [member idle]).
class Hook extends Node:
	var on_tick: Callable
	var idle: bool = false

	func _ready() -> void:
		set_process(idle)
		set_physics_process(not idle)

	func _physics_process(_delta: float) -> void:
		on_tick.call()

	func _process(_delta: float) -> void:
		on_tick.call()


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--perf-out="):
			_perf_out = a.substr("--perf-out=".length())
		elif a.begins_with("--proc-out="):
			_proc_out = a.substr("--proc-out=".length())
		elif a.begins_with("--trace-out="):
			_trace_out = a.substr("--trace-out=".length())
		elif a == "--replica=0":
			_replica = false
		elif a == "--profile-scripts":
			_profile_scripts = true
	_us.resize(STAGES.size())
	var scene_path: String = str(ProjectSettings.get_setting("application/run/main_scene", ""))
	var packed: PackedScene = load(scene_path) as PackedScene
	if packed == null:
		printerr("[prof] ERROR: cannot load the main scene '%s'" % scene_path)
		quit(2)
		return
	_main = packed.instantiate()
	_add_hook(&"ProfTickStart", -RECORDER_PRIORITY, false, func() -> void: _tick_start_us = Time.get_ticks_usec())
	# The replica runs at priority 0 before Main (tree order), i.e. where Main's own tick ran:
	# before Main's children (DebugHarness) and after nothing else of the game.
	_add_hook(&"ProfReplica", 0, false, _replica_tick)
	_add_hook(&"ProfTickEnd", RECORDER_PRIORITY, false, _on_tick_end)
	_add_hook(&"ProfProcStart", -RECORDER_PRIORITY, true, func() -> void: _proc_start_us = Time.get_ticks_usec())
	_add_hook(&"ProfProcEnd", RECORDER_PRIORITY, true, _on_proc_end)
	root.add_child(_main)
	current_scene = _main
	var head: String = PERF_HEADER_HEAD + ",".join(STAGES.duplicate()).replace(",", "_ms,") + "_ms" + PERF_HEADER_TAIL
	_perf_rows.append(head)
	_proc_rows.append("frame,proc_ms,visual_ms")
	_trace_rows.append(TRACE_HEADER)
	print("[prof] replica=%s profile_scripts=%s scene=%s" % [str(_replica), str(_profile_scripts), scene_path])


func _add_hook(node_name: StringName, priority: int, idle: bool, fn: Callable) -> void:
	var h := Hook.new()
	h.name = node_name
	h.idle = idle
	if idle:
		h.process_priority = priority
	else:
		h.process_physics_priority = priority
	h.process_mode = Node.PROCESS_MODE_ALWAYS
	h.on_tick = fn
	root.add_child(h)


func _racing() -> bool:
	if _main == null or not is_instance_valid(_main):
		return false
	var mode: int = int(_main.get("_mode"))
	return mode == MODE_NET_RACE or (mode == MODE_SOLO and not paused)


# ---------------------------------------------------------------- the replica of Main's tick

func _replica_tick() -> void:
	_replica_ran = false
	if _main == null or not is_instance_valid(_main) or not _main.is_node_ready():
		return
	var mode: int = int(_main.get("_mode"))
	if not _replica or mode != MODE_NET_RACE:
		if _replica and not _main.is_physics_processing():
			_main.set_physics_process(true)  # outside NET_RACE Main runs its own tick
		return
	if _main.is_physics_processing():
		# First NET_RACE tick: Main already ran this tick's _physics_process? No: it runs after
		# this node (tree order), so turning it off here hands the whole tick to the replica.
		_main.set_physics_process(false)
	var t0: int = Time.get_ticks_usec()
	_net_tick(get_physics_process_delta_time_safe())
	_replica_us = Time.get_ticks_usec() - t0
	_replica_ran = true


func get_physics_process_delta_time_safe() -> float:
	return _main.get_physics_process_delta_time()


# Copy of Main._net_tick (src/legacy/main.gd), stage-timed.
func _net_tick(dt: float) -> void:
	_us.fill(0)
	_sim_max_us = 0
	_drive_bot_max_us = 0
	var m: Node = _main
	var t: int = Time.get_ticks_usec()
	m.race_time += dt
	var race_time: float = m.race_time
	var hazards: Object = m.get("_hazards")
	hazards.update(race_time)
	m._hazard_trace()
	t = _lap(0, t)
	var track: Object = m.get("_track")
	var racers: Array = m.get("_racers")
	var keys: Dictionary = {}
	for r: Object in racers:
		if r.dropped:
			if r.is_finished():
				keys[r.kart_id] = m._rank_key(r)
			continue
		if r.owned:
			if _tick_owned(r, dt, true, race_time, track):
				t = Time.get_ticks_usec()
				r.laps.update(r.sim.track_s, race_time)
				t = _lap(4, t)
		else:
			t = Time.get_ticks_usec()
			r.remote.update_view(race_time)
			r.remote.sample_surface(track)
			r.remote.sample_surface_type(track)
			t = _lap(5, t)
		t = Time.get_ticks_usec()
		keys[r.kart_id] = m._rank_key(r)
		t = _lap(4, t)
	t = Time.get_ticks_usec()
	m.get("_ranking").update(dt, keys)
	t = _lap(6, t)
	m._resolve_kart_contacts()
	t = _lap(7, t)
	m._separate_karts()
	t = _lap(8, t)
	m._measure_contacts()
	t = _lap(9, t)
	m.get("_items").update(dt, race_time)
	t = _lap(10, t)
	var net_config: Object = m.get("net_config")
	m._send_accum += dt
	var interval: float = 1.0 / net_config.send_hz
	if m._send_accum >= interval:
		m._send_accum = fmod(m._send_accum, interval)
		var net: Object = m.get("_net")
		for r: Object in racers:
			if r.owned and not r.dropped:
				net.send_state(r.kart_id, race_time, KartWire.pack(r.sim, r.laps))
	t = _lap(11, t)
	m._net_log_tick(dt)
	var options: Object = m.get("_options")
	if options.height_log == "every-tick":
		m._log_heights()
	if options.autopilot:
		m._log_surface(dt)
	t = _lap(12, t)
	m._finish_check(dt)
	t = _lap(13, t)


# Copy of Main._tick_owned, with KartDriver.drive and KartSim.tick timed apart.
func _tick_owned(r: Object, dt: float, synced: bool, race_time: float, track: Object) -> bool:
	var start: Object = r.start
	if synced and start.is_counting():
		start.time_to_go = maxf(dt - race_time, 0.0)
	r.driver.time_to_go = start.time_to_go if start.is_counting() else 0.0
	var t0: int = Time.get_ticks_usec()
	r.driver.drive(r.input, r.sim, track, dt)
	var drive_us: int = Time.get_ticks_usec() - t0
	if r.is_bot:
		_us[2] += drive_us
		_drive_bot_max_us = maxi(_drive_bot_max_us, drive_us)
	else:
		_us[1] += drive_us
	t0 = Time.get_ticks_usec()
	if r.laps.is_finished:
		r.input.clear()
	var driving: bool = true
	if start.is_counting():
		var held: bool = r.input.throttle > 0.0
		r.input.clear()
		if not start.update(dt, held):
			driving = false
		else:
			r.sim.apply_start(start.level, start.stalled)
	else:
		start.update(dt, false)
	r.sim.tick(dt, r.input, track)
	var sim_us: int = Time.get_ticks_usec() - t0
	_us[3] += sim_us
	_sim_max_us = maxi(_sim_max_us, sim_us)
	return driving


# Adds the time since [param t] to stage [param i]; returns the new stamp.
func _lap(i: int, t: int) -> int:
	var now: int = Time.get_ticks_usec()
	_us[i] += now - t
	return now


# ---------------------------------------------------------------- recording

func _on_tick_end() -> void:
	if _written or not _racing():
		return
	if _profile_scripts and not _profiling:
		_profiling = true
		EngineDebugger.profiler_enable(&"scripts", true)
		print("[prof] GDScript profiler on at race tick %d" % _ticks)
	var tick_ms: float = float(Time.get_ticks_usec() - _tick_start_us) / 1000.0
	var engine_ms: float = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	var racers: Array = _main.get("_racers")
	var owned: Array = []
	for r: Object in racers:
		if r.get("owned") and not r.get("dropped") and r.get("laps") != null:
			owned.append(r)
	if _perf_out != "":
		var cells: PackedStringArray = PackedStringArray([str(_ticks), "%.4f" % tick_ms,
				"%.4f" % (float(_replica_us) / 1000.0 if _replica_ran else -1.0), "%.4f" % engine_ms, str(owned.size())])
		for i in STAGES.size():
			cells.append("%.4f" % (float(_us[i]) / 1000.0 if _replica_ran else -1.0))
		cells.append("%.4f" % (float(_sim_max_us) / 1000.0))
		cells.append("%.4f" % (float(_drive_bot_max_us) / 1000.0))
		_perf_rows.append(",".join(cells))
	if _trace_out != "":
		var race_time: float = float(_main.get("race_time"))
		for r: Object in owned:
			_trace_rows.append(_row(r, race_time))
	_ticks += 1


func _on_proc_end() -> void:
	if _written or _proc_out == "" or not _racing():
		KartVisual.take_cost_usec()
		return
	var proc_ms: float = float(Time.get_ticks_usec() - _proc_start_us) / 1000.0
	_proc_rows.append("%d,%.4f,%.4f" % [_proc_rows.size() - 1, proc_ms, float(KartVisual.take_cost_usec()) / 1000.0])


# One trace row, same as tools/capture_traces.gd _row (the recorder counts ticks the same way).
func _row(r: Object, race_time: float) -> String:
	var sim: Object = r.get("sim")
	var laps: Object = r.get("laps")
	var pos: Vector2 = sim.get("position")
	var times: PackedStringArray = PackedStringArray()
	for lt: float in laps.get("lap_times"):
		times.append(String.num_scientific(lt))
	return ",".join(PackedStringArray([
		str(_ticks), str(r.get("kart_id")), String.num_scientific(race_time),
		String.num_scientific(pos.x), String.num_scientific(pos.y),
		String.num_scientific(float(sim.get("height"))), String.num_scientific(float(sim.get("speed"))),
		String.num_scientific(float(sim.get("yaw"))), String.num_scientific(float(sim.get("track_s"))),
		"1" if sim.get("drifting") else "0", str(sim.get("drift_dir")), str(sim.get("drift_tier")),
		String.num_scientific(float(sim.get("boost_time"))), str(laps.get("lap")), ";".join(times),
	]))


func _finalize() -> void:
	if _profiling:
		EngineDebugger.profiler_enable(&"scripts", false)  # prints the ACCUMULATED table
		_profiling = false
	if _written:
		return
	_written = true
	if _perf_out != "":
		_save(_perf_out, _perf_rows)
	if _proc_out != "":
		_save(_proc_out, _proc_rows)
	if _trace_out != "":
		_save(_trace_out, _trace_rows)
	print("[prof] %d race ticks recorded" % _ticks)


func _save(path: String, rows: PackedStringArray) -> void:
	var abs_out: String = ProjectSettings.globalize_path(path)
	DirAccess.make_dir_recursive_absolute(abs_out.get_base_dir())
	var f := FileAccess.open(abs_out, FileAccess.WRITE)
	if f == null:
		printerr("[prof] ERROR: cannot write %s" % abs_out)
		return
	f.store_string("\n".join(rows) + "\n")
	f.close()
	print("[prof] wrote %d rows -> %s" % [rows.size() - 1, abs_out])
