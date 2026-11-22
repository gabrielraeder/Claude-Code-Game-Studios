extends SceneTree
## Golden-trace recorder for the frozen 2.5D game (core-rebuild story 001). REGRESSION TOOL:
## it runs the real main scene unchanged and only reads its state, so the trace is the game.
##
## Run (headless, one physics tick per frame, so the run is deterministic and fast):
##   godot --headless --fixed-fps 60 --path . -s res://tools/capture_traces.gd -- \
##       --trace-out=PATH.csv <game args, e.g. --autopilot --quit-after-race --laps=1 --track=castle_circuit>
##
## Tool switches (all others go to the game, which reads OS.get_cmdline_user_args() itself):
##   --trace-out=PATH      CSV of one row per owned kart per physics tick (required unless --perf-out)
##   --perf-out=PATH       CSV of the host's physics-step time per tick instead of the trace
##   --trace-max-ticks=N   stop after N recorded ticks (safety cap, default MAX_TICKS_DEFAULT)
##
## Recording starts on the first tick the game is racing (Main.Mode SOLO with the tree running,
## or NET_RACE), so lobby timing never shifts the tick numbers. The file is written when the game
## quits (atomic: a .tmp file renamed over the target). Floats use String.num_scientific, the
## shortest text that reads back as the same 64-bit value, so equal text means equal values.
## A run that recorded no data row (0 ticks, or ticks with no owned kart) writes no file, prints
## an ERROR line and exits 1: an empty trace is a failed capture, never a golden file.

## Main.Mode values this tool reads (src main.gd enum Mode { SOLO, HOST_LOBBY, CLIENT_LOBBY, NET_RACE }).
const MODE_SOLO: int = 0
const MODE_NET_RACE: int = 3
## Default cap on recorded ticks: four minutes of race at 60 ticks per second.
const MAX_TICKS_DEFAULT: int = 14400
## Physics priority of the recorder: far above the game's nodes (default 0), so it reads each
## tick's state after every game node has run that tick.
const RECORDER_PRIORITY: int = 1000000
## CSV columns of a trace row.
const TRACE_HEADER: String = "tick,kart,race_time,x,z,height,speed,yaw,track_s,drifting,drift_dir,drift_tier,boost,lap,lap_times"
## CSV columns of a perf row: tick_ms = wall time from the first to the last node of this
## physics tick (the game's whole tick, timed directly); engine_physics_ms = the engine's
## TIME_PHYSICS_PROCESS monitor as read during the tick (its last completed frame).
const PERF_HEADER: String = "tick,tick_ms,engine_physics_ms,karts"

var _main: Node
var _trace_out: String = ""
var _perf_out: String = ""
var _max_ticks: int = MAX_TICKS_DEFAULT
var _rows: PackedStringArray = PackedStringArray()
var _ticks: int = 0
var _karts_seen: int = 0
var _written: bool = false
var _tick_start_us: int = 0


## Recorder node: calls [member on_tick] every physics tick. The tool adds two: one before the
## game's nodes (tick start stamp) and one after them (the record).
class TickRecorder extends Node:
	## Called once per physics tick at this node's place in the physics order.
	var on_tick: Callable

	func _physics_process(_delta: float) -> void:
		on_tick.call()


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--trace-out="):
			_trace_out = a.substr("--trace-out=".length())
		elif a.begins_with("--perf-out="):
			_perf_out = a.substr("--perf-out=".length())
		elif a.begins_with("--trace-max-ticks="):
			_max_ticks = a.substr("--trace-max-ticks=".length()).to_int()
	if _trace_out == "" and _perf_out == "":
		printerr("[trace] ERROR: give --trace-out=PATH or --perf-out=PATH after --")
		quit(2)
		return
	var scene_path: String = str(ProjectSettings.get_setting("application/run/main_scene", ""))
	var packed: PackedScene = load(scene_path) as PackedScene
	if packed == null:
		printerr("[trace] ERROR: cannot load the main scene '%s'" % scene_path)
		quit(2)
		return
	_main = packed.instantiate()
	var rec := TickRecorder.new()
	rec.name = &"TraceRecorder"
	rec.process_physics_priority = RECORDER_PRIORITY
	rec.process_mode = Node.PROCESS_MODE_ALWAYS
	rec.on_tick = _on_tick  # the tool (a SceneTree) outlives the node: no RefCounted cycle
	root.add_child(rec)
	var stamp := TickRecorder.new()
	stamp.name = &"TraceTickStart"
	stamp.process_physics_priority = -RECORDER_PRIORITY
	stamp.process_mode = Node.PROCESS_MODE_ALWAYS
	stamp.on_tick = func() -> void: _tick_start_us = Time.get_ticks_usec()
	root.add_child(stamp)
	root.add_child(_main)
	current_scene = _main
	_rows.append(PERF_HEADER if _perf_out != "" else TRACE_HEADER)
	print("[trace] recording %s from %s" % [_perf_out if _perf_out != "" else _trace_out, scene_path])


func _on_tick() -> void:
	if _written or _main == null or not is_instance_valid(_main):
		return
	var mode: int = int(_main.get("_mode"))
	var racing: bool = mode == MODE_NET_RACE or (mode == MODE_SOLO and not paused)
	if not racing:
		return
	var racers: Array = _main.get("_racers")
	var owned: Array = []
	for r: Object in racers:
		if r.get("owned") and not r.get("dropped") and r.get("laps") != null:
			owned.append(r)
	_karts_seen = maxi(_karts_seen, owned.size())
	if _perf_out != "":
		var tick_ms: float = float(Time.get_ticks_usec() - _tick_start_us) / 1000.0
		var engine_ms: float = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		_rows.append("%d,%s,%s,%d" % [_ticks, String.num_scientific(tick_ms),
				String.num_scientific(engine_ms), owned.size()])
	else:
		var race_time: float = float(_main.get("race_time"))
		for r: Object in owned:
			_rows.append(_row(r, race_time))
	_ticks += 1
	if _ticks >= _max_ticks:
		print("[trace] reached --trace-max-ticks=%d; quitting" % _max_ticks)
		quit()


# One CSV row of kart [param r] at the current tick.
func _row(r: Object, race_time: float) -> String:
	var sim: Object = r.get("sim")
	var laps: Object = r.get("laps")
	var pos: Vector2 = sim.get("position")
	var times: PackedStringArray = PackedStringArray()
	for t: float in laps.get("lap_times"):
		times.append(String.num_scientific(t))
	return ",".join(PackedStringArray([
		str(_ticks), str(r.get("kart_id")), String.num_scientific(race_time),
		String.num_scientific(pos.x), String.num_scientific(pos.y),
		String.num_scientific(float(sim.get("height"))), String.num_scientific(float(sim.get("speed"))),
		String.num_scientific(float(sim.get("yaw"))), String.num_scientific(float(sim.get("track_s"))),
		"1" if sim.get("drifting") else "0", str(sim.get("drift_dir")), str(sim.get("drift_tier")),
		String.num_scientific(float(sim.get("boost_time"))), str(laps.get("lap")), ";".join(times),
	]))


func _finalize() -> void:
	_write()


# Writes the rows once, through a .tmp file renamed over the target.
func _write() -> void:
	if _written:
		return
	_written = true
	var out: String = _perf_out if _perf_out != "" else _trace_out
	if _ticks == 0 or _rows.size() <= 1:
		printerr("[trace] ERROR: recorded %d ticks and %d data rows (the game never raced?); no file written to %s"
				% [_ticks, _rows.size() - 1, out])
		quit(1)  # sets the process exit code; the tree is already quitting
		return
	var abs_out: String = ProjectSettings.globalize_path(out)
	DirAccess.make_dir_recursive_absolute(abs_out.get_base_dir())
	var tmp: String = abs_out + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		printerr("[trace] ERROR: cannot write %s (%s)" % [tmp, error_string(FileAccess.get_open_error())])
		return
	f.store_string("\n".join(_rows) + "\n")
	f.close()
	if FileAccess.file_exists(abs_out):
		DirAccess.remove_absolute(abs_out)
	var err: Error = DirAccess.rename_absolute(tmp, abs_out)
	if err != OK:
		printerr("[trace] ERROR: cannot rename %s to %s (%s)" % [tmp, abs_out, error_string(err)])
		return
	print("[trace] wrote %d ticks, up to %d karts -> %s" % [_ticks, _karts_seen, abs_out])
