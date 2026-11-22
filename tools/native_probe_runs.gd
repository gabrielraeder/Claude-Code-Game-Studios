extends SceneTree
## Toolchain probe runs for core-rebuild story 066 (ADR-0007 Verification Required 2, 4, 5, 6).
## One Godot process per mode, run from the command line:
##   godot --headless --path . -s res://tools/native_probe_runs.gd -- --mode=<mode> [--seconds=N]
## Modes:
##   ptrcall      cost per crossing from typed code: int, Vector3 and packed-array arguments
##   heap         600 ticks, caller refreshes its array every tick; static memory must not grow
##   heap_held    600 ticks, caller holds one array for the whole run; one copy, then flat
##   exit_clean   native object alive at quit, held by a GDScript static var (expect exit 0)
##   exit_rid     same, and the object owns server RIDs (expect exit 0, no RID errors)
##   exit_leak_cycle  the probe is held only by a self-containing Array (a GDScript reference cycle)
##   exit_leak    a deliberately leaked object (reference() never released): exits 0 and prints "RID allocations
##                ... leaked" lines on 4.8-beta3 (it does not crash); tools/native_exit_safety.sh fails on those lines
##   reload       frees the extension through GDExtensionManager.reload_extension while a probe owns RIDs
##   crash        calls ToolchainProbe.crash_for_test() (a deliberate null write; used only by tools/crash_repro.sh runs)
##   hold         load the extension and sleep --seconds (holds the DLL for the locked-DLL negative run)
##   import_hook  prints whether the native class exists (used by the fresh-clone check)
## Every mode that runs to its end prints a sentinel line "PROBE_RAN mode=<mode>"; a caller that does not see it
## treats the run as NOT RUN. Observations only: it prints numbers, it never judges them.

const TICKS: int = 600
const WARMUP_TICKS: int = 20
const CALLS: int = 200000
const PACKED_LENGTH: int = 4096
## Samples in the packed-array argument of the ptrcall measurement.
const ARG_PACKED_SIZE: int = 64

static var kept_probe: ToolchainProbe = null


func _initialize() -> void:
	var mode: String = ""
	var seconds: int = 20
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--mode="):
			mode = arg.substr(7)
		elif arg.begins_with("--seconds="):
			seconds = int(arg.substr(10))
	match mode:
		"ptrcall":
			_ptrcall()
		"heap":
			_heap(false)
		"heap_held":
			_heap(true)
		"exit_clean":
			kept_probe = ToolchainProbe.create(PackedFloat64Array([8.0, 0.0]))
			print("exit_clean: probe held by a static var, rid_count=", kept_probe.rid_count())
		"exit_rid":
			kept_probe = ToolchainProbe.create(PackedFloat64Array([8.0, 1.0]))
			print("exit_rid: probe held by a static var, rid_count=", kept_probe.rid_count())
		"exit_leak":
			var leaked: ToolchainProbe = ToolchainProbe.create(PackedFloat64Array([8.0, 1.0]))
			leaked.reference()
			print("exit_leak: reference() taken and never released, rid_count=", leaked.rid_count())
		"exit_leak_cycle":
			var cyc: Array = []
			cyc.append(cyc)
			cyc.append(ToolchainProbe.create(PackedFloat64Array([8.0, 1.0])))
			print("exit_leak_cycle: probe held only by an Array that contains itself")
		"reload":
			var owner_probe: ToolchainProbe = ToolchainProbe.create(PackedFloat64Array([8.0, 1.0]))
			var live_before: int = ToolchainProbe.live_rid_count()
			var reload_result: int = GDExtensionManager.reload_extension("res://addons/dogworks_core/dogworks_core.gdextension")
			print("reload: live_rids_before=", live_before, " reload_result=", reload_result, " class_exists=", ClassDB.class_exists("ToolchainProbe"))
			print("reload: live_rids_after=", ToolchainProbe.live_rid_count(), " old_reference_valid=", is_instance_valid(owner_probe))
			if is_instance_valid(owner_probe):
				print("reload: old reference is_built=", owner_probe.is_built())
		"crash":
			print("crash: calling ToolchainProbe.crash_for_test()")
			ToolchainProbe.crash_for_test()
		"hold":
			var held: DogworksCore = DogworksCore.new()
			print("hold: extension loaded, sleeping ", seconds, " s, target=", DogworksCore.build_target(), " ", held != null)
			OS.delay_msec(seconds * 1000)
		"import_hook":
			print("import_hook: DogworksCore exists=", ClassDB.class_exists("DogworksCore"))
		_:
			print("unknown --mode=", mode)
			quit(2)
			return
	print("PROBE_RAN mode=", mode)
	quit(0)


## Median of an array of floats.
func _median(values: Array[float]) -> float:
	var copy: Array[float] = values.duplicate()
	copy.sort()
	return copy[copy.size() / 2]


func _ptrcall() -> void:
	var probe: ToolchainProbe = ToolchainProbe.create(PackedFloat64Array([8.0, 0.0]))
	var packed: PackedFloat32Array = PackedFloat32Array()
	packed.resize(ARG_PACKED_SIZE)
	var v: Vector3 = Vector3(1, 2, 3)
	var runs: int = 5
	var base: Array[float] = []
	var scalar: Array[float] = []
	var vec: Array[float] = []
	var pk: Array[float] = []
	for _r: int in runs:
		var t0: int = Time.get_ticks_usec()
		var acc: int = 0
		for i: int in CALLS:
			acc += i
		base.append(float(Time.get_ticks_usec() - t0) / CALLS)
		t0 = Time.get_ticks_usec()
		acc = 0
		for i: int in CALLS:
			acc += probe.echo_int(i)
		scalar.append(float(Time.get_ticks_usec() - t0) / CALLS)
		t0 = Time.get_ticks_usec()
		var out: Vector3 = Vector3.ZERO
		for i: int in CALLS:
			out = probe.echo_vector3(v)
		vec.append(float(Time.get_ticks_usec() - t0) / CALLS)
		t0 = Time.get_ticks_usec()
		var s: float = 0.0
		for i: int in CALLS:
			s = probe.sum_packed(packed)
		pk.append(float(Time.get_ticks_usec() - t0) / CALLS)
	var b: float = _median(base)
	print("ptrcall (median of %d runs x %d calls, loop baseline %.4f us subtracted; typed locals, debug-editor binary, debug DLL)" % [runs, CALLS, b])
	print("  echo_int(int)              total %.4f us  net %.4f us" % [_median(scalar), _median(scalar) - b])
	print("  echo_vector3(Vector3)      total %.4f us  net %.4f us" % [_median(vec), _median(vec) - b])
	print("  sum_packed(PackedFloat32Array of %d, sums it natively) total %.4f us  net %.4f us" % [ARG_PACKED_SIZE, _median(pk), _median(pk) - b])


func _heap(hold_one: bool) -> void:
	var probe: ToolchainProbe = ToolchainProbe.create(PackedFloat64Array([float(PACKED_LENGTH), 0.0]))
	var current: PackedFloat32Array = PackedFloat32Array()
	var held: PackedFloat32Array = PackedFloat32Array()
	for t: int in WARMUP_TICKS:
		probe.step(t)
		current = probe.output()
	var m_start: int = OS.get_static_memory_usage()
	if hold_one:
		held = probe.output()
	var held_first: float = held[0] if hold_one else 0.0
	var m_after_first_cycle: int = 0
	var mem_min: int = 1 << 62
	var mem_max: int = 0
	for t: int in range(WARMUP_TICKS, WARMUP_TICKS + TICKS):
		probe.step(t)
		current = probe.output()
		var m: int = OS.get_static_memory_usage()
		if t == WARMUP_TICKS + 2:
			m_after_first_cycle = m
		if t >= WARMUP_TICKS + 2:
			mem_min = mini(mem_min, m)
			mem_max = maxi(mem_max, m)
	var m_end: int = OS.get_static_memory_usage()
	print("heap mode=%s ticks=%d array_bytes=%d" % ["held" if hold_one else "refreshed", TICKS, PACKED_LENGTH * 4])
	print("  static memory start=%d after_first_cycle=%d end=%d  (tick 3..600 min=%d max=%d)" % [m_start, m_after_first_cycle, m_end, mem_min, mem_max])
	print("  growth start->end=%d  growth after first cycle->end=%d" % [m_end - m_start, m_end - m_after_first_cycle])
	if hold_one:
		print("  held array first element still %.1f (was %.1f): intact=%s" % [held[0], held_first, str(held[0] == held_first)])
	probe.dispose()
