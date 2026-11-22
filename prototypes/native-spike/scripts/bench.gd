## PROTOTYPE - NOT FOR PRODUCTION. Native spike (ADR-0007). Benchmarks + determinism compare.
## Run ONE process at a time:
##   godot --headless --path . -s res://scripts/bench.gd -- --part=mover|static|compare --mode=gd|cpp_call|cpp_batch
##        [--ticks=600] [--build=debug|release] [--out=PATH]
## mover: worst layout of tools/bench_collision.gd: 12 karts x (4 rays + 3 sweeps) vs 5 spinning solid boxes.
## static: 12 karts x (4 rays + 3 sweeps with rest checks) on a code-built mesh, PhysicsServer3D `_into`.
## Per-tick time = Time.get_ticks_usec() around the whole block. Inputs are precomputed outside the block.
extends SceneTree

const TrackGen := preload("res://scripts/track_gen.gd")
const GdMovers := preload("res://scripts/gd_movers.gd")
const GdStatic := preload("res://scripts/gd_static.gd")

const SIM_DT: float = 1.0 / 60.0
const KARTS: int = 12
const WARMUP: int = 120
const SPHERE_R_MOVER: float = 1.0
const SPHERE_R_STATIC: float = 0.6
const RAY_LEN_MOVER: float = 4.0
const RAY_LEN_STATIC: float = 4.0
const SPIN_HALF: Vector3 = Vector3(8.0, 0.5, 0.3)
const SPIN_S_OFFSETS: PackedFloat64Array = [0.0, -2.0, 2.0, -1.0, 1.0]
const SPIN_LATERALS: PackedFloat64Array = [-3.0, -1.5, 0.0, 1.5, 3.0]
const SPIN_HEIGHTS: PackedFloat64Array = [1.2, 2.75, 2.75, 1.2, 2.75]
const SPIN_PERIOD: float = 2.0
const SPIN_PHASE_STEP: float = 0.3
const SLIDE_START: PackedFloat64Array = [0.0, 0.5, 0.75]
const SLIDE_LEN: PackedFloat64Array = [1.0, 0.5, 0.25]
const MOVER_BAND: float = 8.0
const MOVER_WEAVE_AMP: float = 5.0
const MOVER_KART_SPEED: float = 25.0
const MOVER_MOTION: Vector3 = Vector3(0.0, 0.5, 0.42)

var _args: Dictionary = {}
var _total: int = 0
# mover inputs (per tick)
var _m_rays: Array[PackedVector3Array] = []
var _m_sf: Array[PackedVector3Array] = []
var _m_st: Array[PackedVector3Array] = []
# static inputs (per tick)
var _s_rays: Array[PackedVector3Array] = []
var _s_dirs: Array[PackedVector3Array] = []
var _s_sf: Array[PackedVector3Array] = []
var _s_st: Array[PackedVector3Array] = []


func _initialize() -> void:
	_args = {"part": "mover", "mode": "gd", "ticks": "600", "build": "debug", "out": ""}
	for a: String in OS.get_cmdline_user_args():
		var kv: PackedStringArray = a.trim_prefix("--").split("=")
		if kv.size() == 2:
			_args[kv[0]] = kv[1]
	var ticks: int = int(_args.ticks)
	_total = ticks + WARMUP
	match _args.part:
		"mover":
			_build_mover_inputs()
			_run_mover(_args.mode, ticks)
		"static":
			_run_static(_args.mode, ticks)
		"compare":
			_compare(ticks)
	quit()


# ---------------------------------------------------------------- mover part

func _fill_movers(add: Callable) -> void:
	for i in 5:
		var phase: float = float(i) * SPIN_PHASE_STEP / SPIN_PERIOD * TAU
		var key_t: PackedFloat32Array = PackedFloat32Array([0.0, 0.5, 1.0, 1.5])
		var centre: Vector3 = Vector3(SPIN_LATERALS[i], SPIN_HEIGHTS[i], SPIN_S_OFFSETS[i])
		var key_pos: PackedVector3Array = PackedVector3Array([centre, centre, centre, centre])
		var key_rot: PackedFloat32Array = PackedFloat32Array()
		for k in 4:
			var ang: float = phase + float(k) * PI * 0.5
			key_rot.append_array(PackedFloat32Array([0.0, sin(ang * 0.5), 0.0, cos(ang * 0.5)]))
		add.call(0, 0.0, 0.0, SPIN_HALF, SPIN_PERIOD, key_t, key_pos, key_rot)


func _build_mover_inputs() -> void:
	_m_rays.clear()
	_m_sf.clear()
	_m_st.clear()
	for n in _total:
		var t: float = n * SIM_DT
		var rays: PackedVector3Array = PackedVector3Array()
		var sf: PackedVector3Array = PackedVector3Array()
		var st: PackedVector3Array = PackedVector3Array()
		for k in KARTS:
			var x: float = MOVER_WEAVE_AMP * sin(1.3 * t + 0.9 * k)
			var z: float = -MOVER_BAND * 0.5 + fposmod(float(k) * MOVER_BAND / KARTS + (MOVER_KART_SPEED + 0.5 * k) * t, MOVER_BAND)
			rays.append(Vector3(x - 0.6, 2.0, z - 0.8))
			rays.append(Vector3(x + 0.6, 2.0, z - 0.8))
			rays.append(Vector3(x - 0.6, 2.0, z + 0.8))
			rays.append(Vector3(x + 0.6, 2.0, z + 0.8))
			var c: Vector3 = Vector3(x, 1.2, z)
			var m: Vector3 = MOVER_MOTION
			for s in 3:
				var a: Vector3 = c + m * SLIDE_START[s]
				sf.append(a)
				if s == 0:
					st.append(a + m * SLIDE_LEN[s])
				else:
					st.append(a + Vector3(0.0, 0.0, 1.0) * m.length() * SLIDE_LEN[s])
		_m_rays.append(rays)
		_m_sf.append(sf)
		_m_st.append(st)


func _make_movers_gd() -> RefCounted:
	var g: RefCounted = GdMovers.new()
	_fill_movers(g.add_mover)
	return g


func _make_movers_cpp() -> RefCounted:
	var q: RefCounted = ClassDB.instantiate("NativeSpikeQuery")
	_fill_movers(q.add_mover)
	return q


## One tick of the movers block in the given mode.
func _mover_tick(mode: String, obj: RefCounted, n: int, out: PackedFloat64Array) -> PackedFloat64Array:
	var t: float = n * SIM_DT
	match mode:
		"gd":
			return obj.tick(t, _m_rays[n], Vector3.DOWN, RAY_LEN_MOVER, _m_sf[n], _m_st[n], SPHERE_R_MOVER)
		"cpp_batch":
			return obj.movers_tick(t, _m_rays[n], Vector3.DOWN, RAY_LEN_MOVER, _m_sf[n], _m_st[n], SPHERE_R_MOVER)
		_:
			var rays: PackedVector3Array = _m_rays[n]
			var sf: PackedVector3Array = _m_sf[n]
			var st: PackedVector3Array = _m_st[n]
			var nr: int = rays.size()
			for i in nr:
				out[i] = obj.mover_cast_ground(rays[i], Vector3.DOWN, RAY_LEN_MOVER, t)
			for i in sf.size():
				var fr: float = obj.mover_sweep(sf[i], st[i], SPHERE_R_MOVER, t)
				var o: int = nr + i * 4
				out[o] = fr
				if fr >= 0.0:
					var nv: Vector3 = obj.get_last_normal()
					out[o + 1] = nv.x
					out[o + 2] = nv.y
					out[o + 3] = nv.z
				else:
					out[o + 1] = 0.0
					out[o + 2] = 0.0
					out[o + 3] = 0.0
			return out


func _run_mover(mode: String, ticks: int) -> void:
	var obj: RefCounted = _make_movers_gd() if mode == "gd" else _make_movers_cpp()
	var out: PackedFloat64Array = PackedFloat64Array()
	out.resize(48 + 36 * 4)
	var us: PackedInt64Array = PackedInt64Array()
	var all: PackedFloat64Array = PackedFloat64Array()
	for n in _total:
		var t0: int = Time.get_ticks_usec()
		var res: PackedFloat64Array = _mover_tick(mode, obj, n, out)
		var dt: int = Time.get_ticks_usec() - t0
		if n >= WARMUP:
			us.append(dt)
			all.append_array(res)
	_report("mover", mode, us, all)


# ---------------------------------------------------------------- static part

func _build_static_world() -> TrackGen:
	var tg: TrackGen = TrackGen.new()
	tg.build(1.0, 10, 4)
	print("track: ground tris=", tg.ground_tri_count(), " wall tris=", tg.wall_tri_count(), " total=", tg.ground_tri_count() + tg.wall_tri_count())
	_s_rays.clear()
	_s_dirs.clear()
	_s_sf.clear()
	_s_st.clear()
	var fr: PackedVector3Array = PackedVector3Array()
	fr.resize(3)
	var fr2: PackedVector3Array = PackedVector3Array()
	fr2.resize(3)
	for n in _total:
		var t: float = n * SIM_DT
		var rays: PackedVector3Array = PackedVector3Array()
		var dirs: PackedVector3Array = PackedVector3Array()
		var sf: PackedVector3Array = PackedVector3Array()
		var st: PackedVector3Array = PackedVector3Array()
		for k in KARTS:
			var s0: float = tg.length * float(k) / float(KARTS)
			var v: float = 24.0 + 1.0 * k
			var om: float = 0.35 + 0.07 * k
			var phase: float = 0.9 * k
			tg.frame_at(s0 + v * t, 14.8 * sin(om * t + phase), fr)
			tg.frame_at(s0 + v * (t + SIM_DT), 14.8 * sin(om * (t + SIM_DT) + phase), fr2)
			var pos: Vector3 = fr[0]
			var f: Vector3 = fr[1]
			var u: Vector3 = fr[2]
			var r: Vector3 = f.cross(u)
			var base: Vector3 = pos + u * 2.0
			rays.append(base + f * 1.0 - r * 0.7)
			rays.append(base + f * 1.0 + r * 0.7)
			rays.append(base - f * 1.0 - r * 0.7)
			rays.append(base - f * 1.0 + r * 0.7)
			dirs.append(-u)
			var from: Vector3 = pos + u * 0.7
			var m: Vector3 = (fr2[0] + fr2[2] * 0.7) - from
			for s in 3:
				var a: Vector3 = from + m * SLIDE_START[s]
				sf.append(a)
				if s == 0:
					st.append(a + m * SLIDE_LEN[s])
				else:
					st.append(a + f * m.length() * SLIDE_LEN[s])
		_s_rays.append(rays)
		_s_dirs.append(dirs)
		_s_sf.append(sf)
		_s_st.append(st)
	return tg


func _static_tick(mode: String, obj: RefCounted, n: int, out: PackedFloat64Array) -> PackedFloat64Array:
	match mode:
		"gd":
			return obj.tick(_s_rays[n], _s_dirs[n], RAY_LEN_STATIC, _s_sf[n], _s_st[n], SPHERE_R_STATIC)
		"cpp_batch":
			return obj.static_tick(_s_rays[n], _s_dirs[n], RAY_LEN_STATIC, _s_sf[n], _s_st[n], SPHERE_R_STATIC)
		_:
			var rays: PackedVector3Array = _s_rays[n]
			var dirs: PackedVector3Array = _s_dirs[n]
			var sf: PackedVector3Array = _s_sf[n]
			var st: PackedVector3Array = _s_st[n]
			for i in rays.size():
				out[i] = obj.static_cast_ground(rays[i], dirs[i / 4], RAY_LEN_STATIC)
			for i in sf.size():
				out[48 + i] = obj.static_sweep(sf[i], st[i], SPHERE_R_STATIC)
			return out


func _make_static(mode: String, tg: TrackGen) -> RefCounted:
	if mode == "gd":
		var g: RefCounted = GdStatic.new()
		g.setup(tg.ground_faces, tg.wall_faces)
		return g
	var q: RefCounted = ClassDB.instantiate("NativeSpikeQuery")
	q.setup_static(tg.ground_faces, tg.wall_faces)
	return q


func _run_static(mode: String, ticks: int) -> void:
	var tg: TrackGen = _build_static_world()
	var obj: RefCounted = _make_static(mode, tg)
	var out: PackedFloat64Array = PackedFloat64Array()
	out.resize(48 + 36)
	# first query forces any lazy build outside the timed loop
	_static_tick(mode, obj, 0, out)
	var us: PackedInt64Array = PackedInt64Array()
	var all: PackedFloat64Array = PackedFloat64Array()
	for n in _total:
		var t0: int = Time.get_ticks_usec()
		var res: PackedFloat64Array = _static_tick(mode, obj, n, out)
		var dt: int = Time.get_ticks_usec() - t0
		if n >= WARMUP:
			us.append(dt)
			all.append_array(res)
	_report("static", mode, us, all)
	if mode == "gd":
		obj.dispose()


# ---------------------------------------------------------------- report / compare

func _report(part: String, mode: String, us: PackedInt64Array, all: PackedFloat64Array) -> void:
	var a: Array = Array(us)
	a.sort()
	var n: int = a.size()
	var sum: float = 0.0
	for x: int in a:
		sum += x
	var hits: int = 0
	var inside: int = 0
	for v: float in all:
		if v >= 0.0:
			hits += 1
		if v == 0.0:
			inside += 1
	var line: String = "RESULT part=%s mode=%s build=%s ticks=%d median_us=%d p95_us=%d mean_us=%.1f min_us=%d max_us=%d nonneg_values=%d zeros=%d sha256=%s" % [
		part, mode, _args.build, n, a[n / 2], a[int(n * 0.95)], sum / n, a[0], a[n - 1], hits, inside, _sha(all)]
	print(line)
	if _args.out != "":
		var f: FileAccess = FileAccess.open(_args.out, FileAccess.READ_WRITE)
		if f == null:
			f = FileAccess.open(_args.out, FileAccess.WRITE)
		f.seek_end()
		f.store_line(line)
		f.close()


func _sha(arr: PackedFloat64Array) -> String:
	var ctx: HashingContext = HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(arr.to_byte_array())
	return ctx.finish().hex_encode()


func _diff(label: String, a: PackedFloat64Array, b: PackedFloat64Array) -> void:
	var n_diff: int = 0
	var max_abs: float = 0.0
	var max_rel: float = 0.0
	var worst_i: int = -1
	for i in a.size():
		if a[i] != b[i]:
			n_diff += 1
			var d: float = absf(a[i] - b[i])
			if d > max_abs:
				max_abs = d
				worst_i = i
			max_rel = maxf(max_rel, d / maxf(absf(a[i]), 1e-12))
	print("COMPARE %s values=%d bit_different=%d max_abs=%s max_rel=%s worst_index=%d" % [label, a.size(), n_diff, String.num_scientific(max_abs), String.num_scientific(max_rel), worst_i])


func _compare(ticks: int) -> void:
	# movers: gd vs cpp_batch vs cpp_call, bit comparison over all ticks
	_build_mover_inputs()
	var g: RefCounted = _make_movers_gd()
	var c: RefCounted = _make_movers_cpp()
	var c2: RefCounted = _make_movers_cpp()
	var out: PackedFloat64Array = PackedFloat64Array()
	out.resize(48 + 36 * 4)
	var ag: PackedFloat64Array = PackedFloat64Array()
	var ac: PackedFloat64Array = PackedFloat64Array()
	var ac2: PackedFloat64Array = PackedFloat64Array()
	for n in _total:
		ag.append_array(_mover_tick("gd", g, n, out))
		ac.append_array(_mover_tick("cpp_batch", c, n, out))
		ac2.append_array(_mover_tick("cpp_call", c2, n, out))
	_diff("mover gd_vs_cpp_batch", ag, ac)
	_diff("mover cpp_batch_vs_cpp_call", ac, ac2)
	var cat_n: PackedInt32Array = PackedInt32Array([0, 0, 0])
	var cat_d: PackedInt32Array = PackedInt32Array([0, 0, 0])
	var cat_max: PackedFloat64Array = PackedFloat64Array([0.0, 0.0, 0.0])
	for i in ag.size():
		var r: int = i % 192
		var cat: int = 0 if r < 48 else (1 if (r - 48) % 4 == 0 else 2)
		cat_n[cat] += 1
		if ag[i] != ac[i]:
			cat_d[cat] += 1
			cat_max[cat] = maxf(cat_max[cat], absf(ag[i] - ac[i]))
	print("COMPARE mover breakdown rays: %d/%d diff max=%s | sweep fraction: %d/%d diff max=%s | sweep normal: %d/%d diff max=%s" % [
		cat_d[0], cat_n[0], String.num_scientific(cat_max[0]), cat_d[1], cat_n[1], String.num_scientific(cat_max[1]), cat_d[2], cat_n[2], String.num_scientific(cat_max[2])])
	# poses: every mover at 200 times, bit comparison of the Transform3D
	var pose_diff: int = 0
	var pose_max: float = 0.0
	var pose_n: int = 0
	for k in 5:
		for i in 200:
			var t: float = i * 0.0137
			var pg: Transform3D = g.mover_pose(k, t)
			var pc: Transform3D = c.mover_pose(k, t)
			pose_n += 1
			if pg != pc:
				pose_diff += 1
			for r in 3:
				pose_max = maxf(pose_max, maxf(maxf(absf(pg.basis[r].x - pc.basis[r].x), absf(pg.basis[r].y - pc.basis[r].y)), absf(pg.basis[r].z - pc.basis[r].z)))
	print("COMPARE mover_pose gd_vs_cpp poses=%d bit_different=%d max_basis_abs=%s" % [pose_n, pose_diff, String.num_scientific(pose_max)])
	# static
	var tg: TrackGen = _build_static_world()
	var sg: RefCounted = _make_static("gd", tg)
	var sc: RefCounted = _make_static("cpp_batch", tg)
	var sout: PackedFloat64Array = PackedFloat64Array()
	sout.resize(48 + 36)
	var bg: PackedFloat64Array = PackedFloat64Array()
	var bc: PackedFloat64Array = PackedFloat64Array()
	for n in _total:
		bg.append_array(_static_tick("gd", sg, n, sout))
		bc.append_array(_static_tick("cpp_batch", sc, n, sout))
	_diff("static gd_vs_cpp_batch", bg, bc)
	sg.dispose()
