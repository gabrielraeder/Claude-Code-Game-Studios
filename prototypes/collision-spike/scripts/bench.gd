## PROTOTYPE - NOT FOR PRODUCTION. Collision spike. Q3 benchmark.
##
## Run (one backend per process):
##   godot --headless --path . -s res://scripts/bench.gd -- backend=face api=into size=50k
##   backend = face | shape | grid     api = into | dict (engine only)
##   size = 50k | 150k                 cell = grid cell size in m (grid only)
## Queries are precomputed for every tick (kart paths are not timed). Each tick =
## KARTS x (WHEELS ground rays + 1 wall sweep). Three timed passes: full tick,
## ground rays only, wall sweeps only. Results are dumped to out/res_<tag>.bin
## for cross-backend comparison (compare.gd).
extends SceneTree

const TrackGen := preload("res://scripts/track_gen.gd")
const EngineBackend := preload("res://scripts/backend_engine.gd")
const GridBackend := preload("res://scripts/backend_grid.gd")

const SIM_DT: float = 1.0 / 60.0
const KARTS: int = 12
const WHEELS: int = 4
const TICKS: int = 1800
const WARMUP_TICKS: int = 120
const RAY_START_UP: float = 2.0
const RAY_LEN: float = 4.0
const HALF_WHEELBASE: float = 1.0
const HALF_TRACK: float = 0.7
const SPHERE_UP: float = 0.7
const SPHERE_R: float = 0.6
const KART_SPEED_BASE: float = 24.0
const KART_SPEED_STEP: float = 1.0
const LATERAL_AMP: float = 14.8
const LATERAL_OMEGA_BASE: float = 0.35
const LATERAL_OMEGA_STEP: float = 0.07
const PRESETS: Dictionary = {"50k": [1.0, 10, 4], "150k": [0.5, 14, 8]}
const DEFAULT_CELL: float = 2.0

var _args: Dictionary = {}
# precomputed per tick, per kart
var _origins := PackedVector3Array()  # TICKS * KARTS * WHEELS
var _dirs := PackedVector3Array()     # TICKS * KARTS
var _wfrom := PackedVector3Array()    # TICKS * KARTS
var _wto := PackedVector3Array()      # TICKS * KARTS
# results
var _g_surf := PackedInt32Array()
var _g_y := PackedFloat32Array()
var _w_hit := PackedByteArray()
var _w_nx := PackedFloat32Array()

func _parse_args() -> void:
	_args = {"backend": "face", "api": "into", "size": "50k", "cell": str(DEFAULT_CELL), "ticks": str(TICKS)}
	for a: String in OS.get_cmdline_user_args():
		var kv: PackedStringArray = a.split("=")
		if kv.size() == 2:
			_args[kv[0]] = kv[1]

func _precompute(tg: TrackGen, ticks: int) -> void:
	var total: int = ticks + WARMUP_TICKS
	_origins.resize(total * KARTS * WHEELS)
	_dirs.resize(total * KARTS)
	_wfrom.resize(total * KARTS)
	_wto.resize(total * KARTS)
	var fr := PackedVector3Array()
	fr.resize(3)
	var fr2 := PackedVector3Array()
	fr2.resize(3)
	for n: int in total:
		var t: float = n * SIM_DT
		for k: int in KARTS:
			var s0: float = tg.length * float(k) / float(KARTS)
			var v: float = KART_SPEED_BASE + KART_SPEED_STEP * k
			var om: float = LATERAL_OMEGA_BASE + LATERAL_OMEGA_STEP * k
			var phase: float = 0.9 * k
			var l: float = LATERAL_AMP * sin(om * t + phase)
			tg.frame_at(s0 + v * t, l, fr)
			var l2: float = LATERAL_AMP * sin(om * (t + SIM_DT) + phase)
			tg.frame_at(s0 + v * (t + SIM_DT), l2, fr2)
			var pos: Vector3 = fr[0]
			var f: Vector3 = fr[1]
			var u: Vector3 = fr[2]
			var r: Vector3 = f.cross(u)
			var base: int = (n * KARTS + k) * WHEELS
			_origins[base] = pos + u * RAY_START_UP + f * HALF_WHEELBASE - r * HALF_TRACK
			_origins[base + 1] = pos + u * RAY_START_UP + f * HALF_WHEELBASE + r * HALF_TRACK
			_origins[base + 2] = pos + u * RAY_START_UP - f * HALF_WHEELBASE - r * HALF_TRACK
			_origins[base + 3] = pos + u * RAY_START_UP - f * HALF_WHEELBASE + r * HALF_TRACK
			_dirs[n * KARTS + k] = -u
			_wfrom[n * KARTS + k] = pos + u * SPHERE_UP
			_wto[n * KARTS + k] = fr2[0] + fr2[2] * SPHERE_UP
	_g_surf.resize(total * KARTS * WHEELS)
	_g_y.resize(total * KARTS * WHEELS)
	_w_hit.resize(total * KARTS)
	_w_nx.resize(total * KARTS)

static func _stats(us: PackedInt64Array) -> Dictionary:
	var a: Array = Array(us)
	a.sort()
	var n: int = a.size()
	var sum: float = 0.0
	for x: int in a:
		sum += x
	return {"median_ms": a[n / 2] / 1000.0, "p95_ms": a[int(n * 0.95)] / 1000.0, "p99_ms": a[int(n * 0.99)] / 1000.0,
		"max_ms": a[n - 1] / 1000.0, "mean_ms": sum / n / 1000.0}

func _initialize() -> void:
	_parse_args()
	var backend: String = _args.backend
	var api: String = _args.api
	var size: String = _args.size
	var ticks: int = int(_args.ticks)
	var cell: float = float(_args.cell)
	var preset: Array = PRESETS[size]
	var tag: String = "%s_%s_%s" % [backend, api if backend != "grid" else "c%s" % _args.cell, size]
	print("bench ", tag, "  face_index setting=", ProjectSettings.get_setting("physics/jolt_physics_3d/queries/enable_ray_cast_face_index"))
	var tg: TrackGen = TrackGen.new()
	tg.build(preset[0], preset[1], preset[2])
	print("track: ground tris=%d wall tris=%d" % [tg.ground_tri_count(), tg.wall_tri_count()])
	_precompute(tg, ticks)
	var mem0: int = OS.get_static_memory_usage()
	var eng: EngineBackend = null
	var grid: GridBackend = null
	var build_ms: float
	if backend == "grid":
		grid = GridBackend.new()
		grid.setup(tg, cell, SPHERE_R)
		build_ms = grid.build_ms
		var cells: int = grid.nx * grid.nz
		var nonempty: int = 0
		var maxc: int = 0
		for i: int in cells:
			var c: int = grid.g_start[i + 1] - grid.g_start[i]
			if c > 0:
				nonempty += 1
			maxc = maxi(maxc, c)
		print("grid: %dx%d cells, ground refs=%d (avg %.1f / non-empty cell, max %d), wall refs=%d, est. arrays %.1f MB" % [grid.nx, grid.nz, grid.g_list.size(), float(grid.g_list.size()) / maxf(nonempty, 1), maxc, grid.w_list.size(), grid.memory_estimate_bytes() / 1048576.0])
	else:
		eng = EngineBackend.new()
		eng.setup(tg, EngineBackend.MODE_FACE if backend == "face" else EngineBackend.MODE_SHAPE, EngineBackend.API_INTO if api == "into" else EngineBackend.API_DICT, SPHERE_R)
		build_ms = eng.build_ms
	var mem1: int = OS.get_static_memory_usage()
	print("setup: %.1f ms, static memory +%.2f MB" % [build_ms, (mem1 - mem0) / 1048576.0])
	var total: int = ticks + WARMUP_TICKS
	var t_full := PackedInt64Array()
	var t_ground := PackedInt64Array()
	var t_wall := PackedInt64Array()
	t_full.resize(ticks)
	t_ground.resize(ticks)
	t_wall.resize(ticks)
	var obj0: float = Performance.get_monitor(Performance.OBJECT_COUNT)
	var mem_loop0: int = OS.get_static_memory_usage()
	var peak0: int = OS.get_static_memory_peak_usage()
	# pass 1: full tick
	for n: int in total:
		var t0: int = Time.get_ticks_usec()
		for k: int in KARTS:
			var ki: int = n * KARTS + k
			var dir: Vector3 = _dirs[ki]
			for w: int in WHEELS:
				var qi: int = ki * WHEELS + w
				var hit: bool
				if grid != null:
					hit = grid.cast_ground(_origins[qi], dir, RAY_LEN)
					if hit:
						_g_surf[qi] = grid.hit_surf
						_g_y[qi] = grid.hit_pos.y
					else:
						_g_surf[qi] = -1
				else:
					hit = eng.cast_ground(_origins[qi], dir, RAY_LEN)
					if hit:
						_g_surf[qi] = eng.hit_surf
						_g_y[qi] = eng.hit_pos.y
					else:
						_g_surf[qi] = -1
			var wh: bool
			if grid != null:
				wh = grid.sweep_walls(_wfrom[ki], _wto[ki], SPHERE_R)
				_w_nx[ki] = grid.wall_normal.x if wh else 0.0
			else:
				wh = eng.sweep_walls(_wfrom[ki], _wto[ki])
				_w_nx[ki] = eng.wall_normal.x if wh else 0.0
			_w_hit[ki] = 1 if wh else 0
		var dt: int = Time.get_ticks_usec() - t0
		if n >= WARMUP_TICKS:
			t_full[n - WARMUP_TICKS] = dt
	var obj1: float = Performance.get_monitor(Performance.OBJECT_COUNT)
	var mem_loop1: int = OS.get_static_memory_usage()
	var peak1: int = OS.get_static_memory_peak_usage()
	# pass 2: ground only
	for n: int in total:
		var t0: int = Time.get_ticks_usec()
		for k: int in KARTS:
			var ki: int = n * KARTS + k
			var dir: Vector3 = _dirs[ki]
			for w: int in WHEELS:
				if grid != null:
					grid.cast_ground(_origins[ki * WHEELS + w], dir, RAY_LEN)
				else:
					eng.cast_ground(_origins[ki * WHEELS + w], dir, RAY_LEN)
		if n >= WARMUP_TICKS:
			t_ground[n - WARMUP_TICKS] = Time.get_ticks_usec() - t0
	# pass 3: wall only
	for n: int in total:
		var t0: int = Time.get_ticks_usec()
		for k: int in KARTS:
			var ki: int = n * KARTS + k
			if grid != null:
				grid.sweep_walls(_wfrom[ki], _wto[ki], SPHERE_R)
			else:
				eng.sweep_walls(_wfrom[ki], _wto[ki])
		if n >= WARMUP_TICKS:
			t_wall[n - WARMUP_TICKS] = Time.get_ticks_usec() - t0
	var sf: Dictionary = _stats(t_full)
	var sg: Dictionary = _stats(t_ground)
	var sw: Dictionary = _stats(t_wall)
	var hist := PackedInt32Array()
	hist.resize(TrackGen.SURF_COUNT + 1)
	for s: int in _g_surf:
		hist[s + 1] += 1
	var wall_hits: int = 0
	for h: int in _w_hit:
		wall_hits += h
	print("RESULT %s full: median=%.3f p95=%.3f p99=%.3f max=%.3f mean=%.3f ms" % [tag, sf.median_ms, sf.p95_ms, sf.p99_ms, sf.max_ms, sf.mean_ms])
	print("RESULT %s ground-only: median=%.3f p95=%.3f ms | wall-only: median=%.3f p95=%.3f ms" % [tag, sg.median_ms, sg.p95_ms, sw.median_ms, sw.p95_ms])
	print("loop (full pass, %d ticks): OBJECT_COUNT %+d, static memory %+d B, static peak %+d B" % [total, int(obj1 - obj0), mem_loop1 - mem_loop0, peak1 - peak0])
	print("hits: surface histogram [miss, road, grass, sand, wall, ramp] = %s, wall contacts=%d/%d" % [hist, wall_hits, _w_hit.size()])
	if eng != null:
		print("engine: wall motion-hit without rest contact = %d" % eng.wall_contact_misses)
	var f := FileAccess.open("res://out/res_%s.bin" % tag, FileAccess.WRITE)
	f.store_32(_g_surf.size())
	f.store_buffer(_g_surf.to_byte_array())
	f.store_buffer(_g_y.to_byte_array())
	f.store_32(_w_hit.size())
	f.store_buffer(_w_hit)
	f.store_buffer(_w_nx.to_byte_array())
	f.close()
	if eng != null:
		eng.free_all()
	quit()
