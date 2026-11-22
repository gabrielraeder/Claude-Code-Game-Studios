extends SceneTree
## Collision benchmark (core-rebuild story 007; Track Collision AC-20; ADR-0002 Performance
## Implications). DEBUG TOOL: every number here is a named bench constant (tuning-values.md allows
## that in tools/); it changes no game file.
##
## In a running tree, from _physics_process (a Hook node), every tick it times one block: for each of
## KARTS karts, RAYS_PER_KART cast_ground probes and SWEEPS_PER_KART sweep_walls calls (each
## sweep_walls runs its unconditional rest check at `from`, so "3 sweeps, 4 rays and the rest check"
## of ADR-0002), plus one mover_pose per mover (the Track Hazards / presentation evaluator). The
## mover tests inside cast_ground / sweep_walls are part of those calls. Time.get_ticks_usec() wraps
## the block only; kart inputs are computed before it. Tick time t = n x SIM_DT.
## The query is built through CollisionBootCheck.checked_query (the story 006 rule).
## The mesh is tools/bench_track_fixture.gd (>= 48k ground triangles, figure-eight with a two-level
## crossover, banking, off-road, two wall attributes, a ramp).
##
## Sections (all 12 karts in one section at a time; TICKS_PER_SECTION ticks each):
##   curve (banked lobe tip), climb (bridge approach), crossover (6 karts on each level),
##   movers (the layout's movers), ramp.
## Layouts (--layout=): castle (drawbridge, portcullis, 3 non-solid barrels, after the frozen Castle
## Circuit's hazards), worst (5 spinning boxes, 12 karts packed within their reach), static (none).
##
## Run (one process at a time; the timings depend on it):
##   godot --headless --path . -s res://tools/bench_collision.gd -- --layout=castle --out=PATH.txt
## Switches: --layout=castle|worst|static, --out=PATH (summary), --ticks=N (per section),
## --stages (after the timed block, each tick also times STAGE_NAMES one at a time: the
## CollisionQuery calls split by kind, and the raw PhysicsDirectSpaceState3D `_into` calls the same
## inputs need, so the GDScript wrapper cost is visible; use a separate run, since the extra work
## between ticks changes cache state).
## Output lines: BENCH (whole block), SECTION (per section), COUNTS, ALLOC (start / +600 / end),
## STAGE (with --stages).

const Fixture = preload("res://tools/bench_track_fixture.gd")

## ADR-0001 tick length (s).
const SIM_DT: float = 1.0 / 60.0
## Karts per tick (ADR-0002 budget: 12).
const KARTS: int = 12
## Ground probes per kart (4 wheels) and wall sweeps per kart (ADR-0003 slide loop, at most 3).
const RAYS_PER_KART: int = 4
const SWEEPS_PER_KART: int = 3
## Kart sweep-sphere radius (m) and its centre height over the road (m).
const KART_RADIUS: float = 1.0
const SPHERE_HEIGHT: float = 1.2
## Wheel offsets from the kart centre: half track (lateral) and half base (forward), m.
const WHEEL_HALF_TRACK: float = 0.6
const WHEEL_HALF_BASE: float = 0.8
## Ground probe start height over the road and its length (m): starts above the 1.5 m ramp.
const RAY_LIFT: float = 2.0
const RAY_LENGTH: float = 4.0
## Kart speed (m/s): kart i drives KART_SPEED + i x SPEED_STEP.
const KART_SPEED: float = 25.0
const SPEED_STEP: float = 0.5
## Lateral weave: rad/s of kart 0, per-kart step, and phase step (rad).
const WEAVE_RATE: float = 1.3
const WEAVE_RATE_STEP: float = 0.05
const WEAVE_PHASE_STEP: float = 0.9
## Weave amplitude that reaches the walls: the sphere crosses the wall plane by WALL_OVERREACH m at
## the peak, so overlaps, blocking hits, touches and misses all occur.
const WALL_OVERREACH: float = 0.1
## Weave amplitude on the ramp section (m): keeps the karts on the 3 m half-width ramp lane.
const RAMP_AMPLITUDE: float = 2.5
## Weave amplitude in the worst-case mover section (m): keeps the pack within the spinners' reach.
const WORST_AMPLITUDE: float = 5.0
## Slide-loop shape: sweep k starts at from + motion x SLIDE_START[k] and runs |motion| x
## SLIDE_LEN[k] (k = 0 along the motion, k > 0 along the track forward, as a slide along a wall).
const SLIDE_START: PackedFloat64Array = [0.0, 0.5, 0.75]
const SLIDE_LEN: PackedFloat64Array = [1.0, 0.5, 0.25]
## Untimed warm-up ticks (cycling through every section) before the allocation baseline.
const WARMUP_TICKS: int = 60
## Timed ticks per section (default; --ticks= overrides).
const TICKS_PER_SECTION: int = 300
## The allocation window of the story: monitors compared at measured tick 0 and 600.
const ALLOC_WINDOW: int = 600
## The registered budget (ms p95 per tick).
const BUDGET_MS: float = 0.3
## Load-probe cast length (m) passed to checked_query.
const PROBE_MAX_DROP: float = 5.0
## Section names and bands: kart i drives band (i mod band count) of its section; a band is
## (start s, SECTION_BAND_LEN) m. SECTION_BAND2_S0 < 0 means the section has one band.
const SECTION_NAMES: PackedStringArray = ["curve", "climb", "crossover", "movers", "ramp"]
const SECTION_BAND_S0: PackedFloat64Array = [1170.0, 130.0, 280.0, 570.0, 950.0]
const SECTION_BAND2_S0: PackedFloat64Array = [-1.0, -1.0, 880.0, -1.0, -1.0]
const SECTION_BAND_LEN: PackedFloat64Array = [60.0, 60.0, 40.0, 60.0, 40.0]
## Index of the movers section in SECTION_NAMES, and the worst layout's tighter band there.
const MOVERS_SECTION: int = 3
const WORST_BAND: Vector2 = Vector2(596.0, 8.0)
## Castle drawbridge (frozen Castle Circuit: deck 5 m x 18 m, raised 78 deg, period 20 s, raised
## over [12, 20) with 1.2 s transitions): centre s, lateral offset, half extents, keys per transition.
const BRIDGE_S: float = 605.0
const BRIDGE_LATERAL: float = -4.0
const BRIDGE_HALF: Vector3 = Vector3(2.5, 0.2, 9.0)
const BRIDGE_RAISED_DEG: float = 78.0
const BRIDGE_PERIOD: float = 20.0
const BRIDGE_UP_AT: float = 12.0
const BRIDGE_DOWN_AT: float = 20.0
const BRIDGE_TRANSITION: float = 1.2
const TRANSITION_KEYS: int = 4
## Castle portcullis (4.5 m wide, 2.6 m grille, 0.6 m deep, lifts 2.8 m; period 20 s, down over
## [3.5, 9.0) with 0.8 s transitions).
const PORT_S: float = 585.0
const PORT_LATERAL: float = 4.25
const PORT_HALF: Vector3 = Vector3(2.25, 1.3, 0.3)
const PORT_LIFT: float = 2.8
const PORT_PERIOD: float = 20.0
const PORT_DOWN_AT: float = 3.5
const PORT_UP_AT: float = 9.0
const PORT_TRANSITION: float = 0.8
## Castle barrels (radius 0.55, length 1.1, 9 m/s over 68 m, period 10 s, phases 0 / 3.333 / 6.667,
## lanes +2.6 / -2.6 / 0; non-solid: the frozen barrels have solid_body = false, a spin, no push).
const BARREL_START_S: float = 562.0
const BARREL_TRAVEL: float = 68.0
const BARREL_SPEED: float = 9.0
const BARREL_RADIUS: float = 0.55
const BARREL_PERIOD: float = 10.0
const BARREL_KEYS: int = 80
const BARREL_PHASES: PackedFloat64Array = [0.0, 3.333, 6.667]
const BARREL_LANES: PackedFloat64Array = [2.6, -2.6, 0.0]
## Worst case (TD-012): 5 spinning boxes 16 m long; centre s offsets, laterals, heights over the
## road (1.2 m: at kart height; 2.75 m: 5 cm over the sweep sphere's top, the longest search).
const SPIN_S: float = 600.0
const SPIN_HALF: Vector3 = Vector3(8.0, 0.5, 0.3)
const SPIN_S_OFFSETS: PackedFloat64Array = [0.0, -2.0, 2.0, -1.0, 1.0]
const SPIN_LATERALS: PackedFloat64Array = [-3.0, -1.5, 0.0, 1.5, 3.0]
const SPIN_HEIGHTS: PackedFloat64Array = [1.2, 2.75, 2.75, 1.2, 2.75]
const SPIN_PERIOD: float = 2.0
const SPIN_KEYS: int = 4
const SPIN_PHASE_STEP: float = 0.3

## Names of the _snapshot() entries, in order.
const SNAP_NAMES: PackedStringArray = ["OBJECT_COUNT", "OBJECT_RESOURCE_COUNT", "OBJECT_NODE_COUNT",
		"OBJECT_ORPHAN_NODE_COUNT", "MEMORY_STATIC", "PS3D_INFO_ACTIVE_OBJECTS", "PS3D_INFO_COLLISION_PAIRS",
		"PS3D_INFO_ISLAND_COUNT", "query_owned_rids"]
## Snapshot entries that must not change (MEMORY_STATIC is reported, not gated).
const SNAP_GATED: PackedByteArray = [1, 1, 1, 1, 0, 1, 1, 1, 1]
## Stage names of --stages, in timing order. query_mover_pose_cache_hits measures cache hits only:
## the main block already evaluated every mover at this t.
const STAGE_NAMES: PackedStringArray = ["query_cast_ground_x48", "query_sweep_walls_x36", "query_mover_pose_cache_hits",
		"raw_intersect_ray_into_x48", "raw_rest_at_from_x36", "raw_cast_motion_x36", "raw_rest_at_to_x36"]

var _layout: String = "castle"
var _out: String = ""
var _ticks_per_section: int = TICKS_PER_SECTION
var _fixture: Fixture = null
var _query: CollisionQuery = null
var _mover_ids: PackedInt32Array = PackedInt32Array()
var _n_solid: int = 0
var _cursors: Array[QueryCursor] = []
var _ground_hits: Array[GroundHit] = []
var _wall_hits: Array[WallHit] = []
## Per tick inputs (computed before the timed block).
var _ray_from: PackedVector3Array = PackedVector3Array()
var _ray_dir: PackedVector3Array = PackedVector3Array()
var _sw_from: PackedVector3Array = PackedVector3Array()
var _sw_to: PackedVector3Array = PackedVector3Array()
var _frame: PackedVector3Array = PackedVector3Array()
var _frame2: PackedVector3Array = PackedVector3Array()
## Per (section, kart): band start and length; per section: weave amplitude.
var _kart_s0: PackedFloat64Array = PackedFloat64Array()
var _kart_len: PackedFloat64Array = PackedFloat64Array()
var _sec_amp: PackedFloat64Array = PackedFloat64Array()
## Timed microseconds per measured tick (section-major).
var _us: PackedInt64Array = PackedInt64Array()
## Counters (per section x 5): ray hits, ray mover hits, sweep hits, sweep mover contacts, started_inside.
var _counts: PackedInt64Array = PackedInt64Array()
var _tick: int = 0
var _snap_start: PackedFloat64Array = PackedFloat64Array()
var _snap_window: PackedFloat64Array = PackedFloat64Array()
var _done: bool = false
var _stages: bool = false
## --stages: per measured tick and stage, microseconds (stage-major).
var _stage_us: PackedInt64Array = PackedInt64Array()
## Raw-call cursors for the --stages reference (masks as QueryCursor sets them).
var _raw: QueryCursor = null



func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--layout="):
			_layout = a.substr("--layout=".length())
		elif a.begins_with("--out="):
			_out = a.substr("--out=".length())
		elif a == "--stages":
			_stages = true
		elif a.begins_with("--ticks="):
			_ticks_per_section = int(a.substr("--ticks=".length()))
	if _ticks_per_section < 1:
		printerr("[bench] --ticks must be >= 1 (got %d)" % _ticks_per_section)
		quit(2)
		return
	if not (_layout in ["castle", "worst", "static"]):
		printerr("[bench] unknown --layout=%s" % _layout)
		quit(2)
		return
	var settings_problem: String = CollisionBootCheck.assert_boot_settings()
	if not settings_problem.is_empty():
		printerr("[bench] boot settings: %s" % settings_problem)
		quit(2)
		return
	_fixture = Fixture.new()
	_fixture.build()
	_frame.resize(4)
	_frame2.resize(4)
	match _layout:
		"castle":
			_add_castle_movers()
		"worst":
			_add_worst_movers()
	var surfaces: SurfaceSet = SurfaceSet.load_checked(SurfaceSet.CORE_PATH)
	var walls: WallAttrSet = WallAttrSet.load_checked(WallAttrSet.CORE_PATH)
	var checked: CollisionBootCheck.CheckedQuery = CollisionBootCheck.checked_query(_fixture.data, surfaces, walls, PROBE_MAX_DROP)
	if not checked.problem.is_empty():
		printerr("[bench] load check failed: %s" % checked.problem)
		quit(2)
		return
	_query = checked.query
	for m in _fixture.data.movers:
		_mover_ids.append(m.id)
		if m.solid:
			_n_solid += 1
	for i in KARTS:
		_cursors.append(QueryCursor.new())
		_ground_hits.append(GroundHit.new())
		_wall_hits.append(WallHit.new())
	_ray_from.resize(KARTS * RAYS_PER_KART)
	_ray_dir.resize(KARTS)
	_sw_from.resize(KARTS * SWEEPS_PER_KART)
	_sw_to.resize(KARTS * SWEEPS_PER_KART)
	var wall_amp: float = Fixture.half_total() - KART_RADIUS + WALL_OVERREACH
	for sec in SECTION_NAMES.size():
		for i in KARTS:
			var band: Vector2 = Vector2(SECTION_BAND_S0[sec], SECTION_BAND_LEN[sec])
			if SECTION_BAND2_S0[sec] >= 0.0 and i % 2 == 1:
				band.x = SECTION_BAND2_S0[sec]
			if sec == MOVERS_SECTION and _layout == "worst":
				band = WORST_BAND
			_kart_s0.append(band.x)
			_kart_len.append(band.y)
		var amp: float = wall_amp
		if SECTION_NAMES[sec] == "ramp":
			amp = RAMP_AMPLITUDE
		elif sec == MOVERS_SECTION and _layout == "worst":
			amp = WORST_AMPLITUDE
		_sec_amp.append(amp)
	_us.resize(SECTION_NAMES.size() * _ticks_per_section)
	_stage_us.resize(STAGE_NAMES.size() * SECTION_NAMES.size() * _ticks_per_section)
	_raw = QueryCursor.new()
	_counts.resize(SECTION_NAMES.size() * 5)
	_counts.fill(0)
	print("[bench] layout=%s ground_tris=%d wall_tris=%d movers=%d solid=%d ticks_per_section=%d physics_ticks=%d build=%s" % [
		_layout, _fixture.data.ground_triangle_count(), _wall_tri_count(), _mover_ids.size(), _n_solid,
		_ticks_per_section, Engine.physics_ticks_per_second, "debug" if OS.is_debug_build() else "release"])
	var hook: Hook = Hook.new()
	hook.name = &"BenchCollisionHook"
	hook.on_tick = _on_tick
	root.add_child(hook)


func _wall_tri_count() -> int:
	var n: int = 0
	for faces in _fixture.data.wall_faces:
		@warning_ignore("integer_division")
		n += faces.size() / 3
	return n


func _on_tick() -> void:
	if _done:
		return
	var measured: int = _tick - WARMUP_TICKS
	var total: int = SECTION_NAMES.size() * _ticks_per_section
	var sec: int = 0
	if measured < 0:
		sec = _tick % SECTION_NAMES.size()
	else:
		@warning_ignore("integer_division")
		sec = measured / _ticks_per_section
	var t: float = float(_tick) * SIM_DT
	if measured == 0:
		_snap_start = _snapshot()
	elif measured == ALLOC_WINDOW:
		_snap_window = _snapshot()
	if measured >= total:
		_finish(_snapshot())
		return
	_prepare(sec, t)
	var base: int = sec * 5
	var ray_hits: int = 0
	var ray_movers: int = 0
	var sweep_hits: int = 0
	var sweep_movers: int = 0
	var inside: int = 0
	var t0: int = Time.get_ticks_usec()
	for i in KARTS:
		var cursor: QueryCursor = _cursors[i]
		var ground: GroundHit = _ground_hits[i]
		var wall: WallHit = _wall_hits[i]
		var dir: Vector3 = _ray_dir[i]
		for r in RAYS_PER_KART:
			if _query.cast_ground(cursor, _ray_from[i * RAYS_PER_KART + r], dir, RAY_LENGTH, t, ground):
				ray_hits += 1
				if ground.collider_id != 0:
					ray_movers += 1
		for k in SWEEPS_PER_KART:
			var j: int = i * SWEEPS_PER_KART + k
			if _query.sweep_walls(cursor, _sw_from[j], _sw_to[j], KART_RADIUS, t, wall):
				sweep_hits += 1
				if wall.collider_id != 0:
					sweep_movers += 1
				if wall.started_inside:
					inside += 1
	for m in _mover_ids.size():
		_query.mover_pose(_mover_ids[m], t)
	var us: int = Time.get_ticks_usec() - t0
	if measured >= 0:
		_us[measured] = us
		_counts[base] += ray_hits
		_counts[base + 1] += ray_movers
		_counts[base + 2] += sweep_hits
		_counts[base + 3] += sweep_movers
		_counts[base + 4] += inside
		if _stages:
			_time_stages(measured, t)
	_tick += 1


## --stages: times each STAGE_NAMES entry over every kart, one stage at a time (outside the main
## block). The raw stages set only what the call needs (mask once, per-call from / to / transform /
## motion), as a hand-written caller would.
func _time_stages(measured: int, t: float) -> void:
	var n: int = SECTION_NAMES.size() * _ticks_per_section
	var state: PhysicsDirectSpaceState3D = PhysicsServer3D.space_get_direct_state(_query.space_rid())
	var t0: int = Time.get_ticks_usec()
	for i in KARTS:
		for r in RAYS_PER_KART:
			_query.cast_ground(_cursors[i], _ray_from[i * RAYS_PER_KART + r], _ray_dir[i], RAY_LENGTH, t, _ground_hits[i])
	var t1: int = Time.get_ticks_usec()
	for i in KARTS:
		for k in SWEEPS_PER_KART:
			var j: int = i * SWEEPS_PER_KART + k
			_query.sweep_walls(_cursors[i], _sw_from[j], _sw_to[j], KART_RADIUS, t, _wall_hits[i])
	var t2: int = Time.get_ticks_usec()
	for m in _mover_ids.size():
		_query.mover_pose(_mover_ids[m], t)
	var t3: int = Time.get_ticks_usec()
	var rp: PhysicsRayQueryParameters3D = _raw.ray_params
	var rr: PhysicsIntersectRayResult3D = _raw.ray_result
	for i in KARTS:
		var dir: Vector3 = _ray_dir[i] * RAY_LENGTH
		for r in RAYS_PER_KART:
			var o: Vector3 = _ray_from[i * RAYS_PER_KART + r]
			rp.from = o
			rp.to = o + dir
			state.intersect_ray_into(rp, rr)
	var t4: int = Time.get_ticks_usec()
	var sp: PhysicsShapeQueryParameters3D = _raw.shape_params
	if _raw.sphere.radius != KART_RADIUS:
		_raw.sphere.radius = KART_RADIUS
	for j in KARTS * SWEEPS_PER_KART:
		sp.transform = Transform3D(Basis.IDENTITY, _sw_from[j])
		state.get_rest_info_into(sp, _raw.rest_result)
	var t5: int = Time.get_ticks_usec()
	for j in KARTS * SWEEPS_PER_KART:
		sp.transform = Transform3D(Basis.IDENTITY, _sw_from[j])
		sp.motion = _sw_to[j] - _sw_from[j]
		state.cast_motion_into(sp, _raw.cast_result)
	sp.motion = Vector3.ZERO
	var t6: int = Time.get_ticks_usec()
	for j in KARTS * SWEEPS_PER_KART:
		sp.transform = Transform3D(Basis.IDENTITY, _sw_to[j])
		state.get_rest_info_into(sp, _raw.rest_result)
	var t7: int = Time.get_ticks_usec()
	var stamps: PackedInt64Array = [t0, t1, t2, t3, t4, t5, t6, t7]
	for s in STAGE_NAMES.size():
		_stage_us[s * n + measured] = stamps[s + 1] - stamps[s]


## Computes every kart's probe and sweep inputs for section [param sec] at time [param t].
## Allocation-free.
func _prepare(sec: int, t: float) -> void:
	var amp: float = _sec_amp[sec]
	for i in KARTS:
		var idx: int = sec * KARTS + i
		var band_len: float = _kart_len[idx]
		var v: float = KART_SPEED + float(i) * SPEED_STEP
		var s: float = _kart_s0[idx] + fposmod(band_len * float(i) / float(KARTS) + v * t, band_len)
		var w: float = WEAVE_RATE + float(i) * WEAVE_RATE_STEP
		var phase: float = float(i) * WEAVE_PHASE_STEP + w * t
		var lat: float = amp * sin(phase)
		var lat_v: float = amp * w * cos(phase)
		_fixture.frame_at(s, lat, _frame)
		_fixture.frame_at(s + v * SIM_DT, lat + lat_v * SIM_DT, _frame2)
		var p: Vector3 = _frame[0]
		var f: Vector3 = _frame[1]
		var u: Vector3 = _frame[2]
		var r: Vector3 = _frame[3]
		var a: Vector3 = p + u * SPHERE_HEIGHT
		var motion: Vector3 = _frame2[0] + _frame2[2] * SPHERE_HEIGHT - a
		var length: float = motion.length()
		for k in SWEEPS_PER_KART:
			var from: Vector3 = a + motion * SLIDE_START[k]
			var dir: Vector3 = motion if k == 0 else f * length
			_sw_from[i * SWEEPS_PER_KART + k] = from
			_sw_to[i * SWEEPS_PER_KART + k] = from + dir * SLIDE_LEN[k]
		var lift: Vector3 = p + u * RAY_LIFT
		_ray_from[i * RAYS_PER_KART] = lift - r * WHEEL_HALF_TRACK + f * WHEEL_HALF_BASE
		_ray_from[i * RAYS_PER_KART + 1] = lift + r * WHEEL_HALF_TRACK + f * WHEEL_HALF_BASE
		_ray_from[i * RAYS_PER_KART + 2] = lift - r * WHEEL_HALF_TRACK - f * WHEEL_HALF_BASE
		_ray_from[i * RAYS_PER_KART + 3] = lift + r * WHEEL_HALF_TRACK - f * WHEEL_HALF_BASE
		_ray_dir[i] = -u


## Monitor values (OBJECT_COUNT, OBJECT_RESOURCE_COUNT, OBJECT_NODE_COUNT, OBJECT_ORPHAN_NODE_COUNT,
## MEMORY_STATIC, PhysicsServer3D INFO_ACTIVE_OBJECTS / INFO_COLLISION_PAIRS / INFO_ISLAND_COUNT,
## the query's owned RID count). Outside the timed block.
func _snapshot() -> PackedFloat64Array:
	return PackedFloat64Array([
		Performance.get_monitor(Performance.OBJECT_COUNT),
		Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT),
		Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),
		Performance.get_monitor(Performance.MEMORY_STATIC),
		float(PhysicsServer3D.get_process_info(PhysicsServer3D.INFO_ACTIVE_OBJECTS)),
		float(PhysicsServer3D.get_process_info(PhysicsServer3D.INFO_COLLISION_PAIRS)),
		float(PhysicsServer3D.get_process_info(PhysicsServer3D.INFO_ISLAND_COUNT)),
		float(_query.owned_rids().size()),
	])




## Nearest-rank percentile ([param q] in (0, 1]) of the sorted [param v].
static func _pct(v: PackedInt64Array, q: float) -> int:
	var n: int = v.size()
	return v[clampi(ceili(q * float(n)) - 1, 0, n - 1)]


func _finish(snap_end: PackedFloat64Array) -> void:
	_done = true
	var lines: PackedStringArray = PackedStringArray()
	lines.append("[bench] layout=%s karts=%d rays_per_kart=%d sweeps_per_kart=%d movers=%d solid=%d ground_tris=%d wall_tris=%d ticks_per_section=%d build=%s engine=%s" % [
		_layout, KARTS, RAYS_PER_KART, SWEEPS_PER_KART, _mover_ids.size(), _n_solid,
		_fixture.data.ground_triangle_count(), _wall_tri_count(), _ticks_per_section,
		"debug" if OS.is_debug_build() else "release", Engine.get_version_info()["string"]])
	var all: PackedInt64Array = _us.duplicate()
	all.sort()
	var worst_sec_p95: int = 0
	lines.append("BENCH layout=%s section=all median_us=%d p95_us=%d max_us=%d" % [_layout, _pct(all, 0.5), _pct(all, 0.95), all[all.size() - 1]])
	for sec in SECTION_NAMES.size():
		var part: PackedInt64Array = _us.slice(sec * _ticks_per_section, (sec + 1) * _ticks_per_section)
		part.sort()
		var p95: int = _pct(part, 0.95)
		worst_sec_p95 = maxi(worst_sec_p95, p95)
		lines.append("SECTION layout=%s section=%s median_us=%d p95_us=%d max_us=%d" % [_layout, SECTION_NAMES[sec], _pct(part, 0.5), p95, part[part.size() - 1]])
		var b: int = sec * 5
		lines.append("COUNTS layout=%s section=%s per_tick ray_hits=%.2f ray_mover_hits=%.2f sweep_hits=%.2f sweep_mover_contacts=%.2f started_inside=%.2f" % [
			_layout, SECTION_NAMES[sec], float(_counts[b]) / _ticks_per_section, float(_counts[b + 1]) / _ticks_per_section,
			float(_counts[b + 2]) / _ticks_per_section, float(_counts[b + 3]) / _ticks_per_section, float(_counts[b + 4]) / _ticks_per_section])
	var alloc_ok: bool = true
	for k in SNAP_NAMES.size():
		var at_window: float = _snap_window[k] if _snap_window.size() > k else NAN
		var same: bool = _snap_start[k] == at_window and _snap_start[k] == snap_end[k]
		if SNAP_GATED[k] == 1 and not same:
			alloc_ok = false
		lines.append("ALLOC %s start=%s tick%d=%s end=%s %s" % [SNAP_NAMES[k], _snap_start[k], ALLOC_WINDOW, at_window, snap_end[k],
				"unchanged" if same else ("CHANGED" if SNAP_GATED[k] == 1 else "changed (not gated)")])
	if _stages:
		var n: int = SECTION_NAMES.size() * _ticks_per_section
		for s in STAGE_NAMES.size():
			for sec in SECTION_NAMES.size():
				var part: PackedInt64Array = _stage_us.slice(s * n + sec * _ticks_per_section, s * n + (sec + 1) * _ticks_per_section)
				part.sort()
				lines.append("STAGE layout=%s stage=%s section=%s median_us=%d p95_us=%d" % [_layout, STAGE_NAMES[s], SECTION_NAMES[sec], _pct(part, 0.5), _pct(part, 0.95)])
		lines.append("STAGE_NOTE query_mover_pose_cache_hits times cache hits only (the main block already evaluated every mover at this t)")
	lines.append("VERDICT_INPUTS worst_section_p95_us=%d budget_us=%d alloc_unchanged=%s" % [worst_sec_p95, int(BUDGET_MS * 1000.0), alloc_ok])
	var text: String = "\n".join(lines)
	print(text)
	if not _out.is_empty():
		var file: FileAccess = FileAccess.open(_out, FileAccess.WRITE)
		if file == null:
			printerr("[bench] cannot write %s" % _out)
		else:
			file.store_string(text + "\n")
			file.close()
	_query.dispose()
	_query = null
	quit(0)


## Basis of the track frame at (s, lateral): x = right, y = up, z = -forward (a proper rotation).
func _frame_basis(s: float, lateral: float) -> Basis:
	_fixture.frame_at(s, lateral, _frame)
	return Basis(_frame[3], _frame[2], -_frame[1]).orthonormalized()


static func _quat_key(b: Basis) -> Vector4:
	var q: Quaternion = b.get_rotation_quaternion()
	return Vector4(q.x, q.y, q.z, q.w)


func _new_mover(shape: MoverDef.Shape, period: float) -> MoverDef:
	var m: MoverDef = MoverDef.new()
	m.id = _fixture.data.movers.size() + 1
	m.shape = shape
	m.period = period
	return m


func _add_castle_movers() -> void:
	# Drawbridge: a deck lying flush with the road (top at road level), hinged at its far end; the
	# near end lifts BRIDGE_RAISED_DEG. Keys: down until the rise, TRANSITION_KEYS steps up, raised,
	# TRANSITION_KEYS - 1 steps down (the loop segment closes on the first, lowered key).
	var b0: Basis = _frame_basis(BRIDGE_S, BRIDGE_LATERAL)
	var surface: Vector3 = _frame[0]
	var fwd: Vector3 = _frame[1]
	var up: Vector3 = _frame[2]
	var axis: Vector3 = _frame[3]
	var c0: Vector3 = surface - up * BRIDGE_HALF.y
	var hinge: Vector3 = surface + fwd * BRIDGE_HALF.z
	var sign_a: float = 1.0 if (Basis(axis, 0.1) * -fwd).dot(up) > 0.0 else -1.0
	var bridge: MoverDef = _new_mover(MoverDef.Shape.BOX, BRIDGE_PERIOD)
	bridge.half_extents = BRIDGE_HALF
	var times: PackedFloat32Array = PackedFloat32Array([0.0])
	var angles: PackedFloat64Array = PackedFloat64Array([0.0])
	var rise_start: float = BRIDGE_UP_AT - BRIDGE_TRANSITION
	for k in TRANSITION_KEYS + 1:
		times.append(rise_start + BRIDGE_TRANSITION * float(k) / float(TRANSITION_KEYS))
		angles.append(BRIDGE_RAISED_DEG * float(k) / float(TRANSITION_KEYS))
	var fall_start: float = BRIDGE_DOWN_AT - BRIDGE_TRANSITION
	for k in TRANSITION_KEYS:
		times.append(fall_start + BRIDGE_TRANSITION * float(k) / float(TRANSITION_KEYS))
		angles.append(BRIDGE_RAISED_DEG * (1.0 - float(k) / float(TRANSITION_KEYS)))
	for k in times.size():
		var rot: Basis = Basis(axis, sign_a * deg_to_rad(angles[k]))
		bridge.key_t.append(times[k])
		bridge.key_pos.append(hinge + rot * (c0 - hinge))
		bridge.key_rot.append(_quat_key(rot * b0))
	_fixture.data.movers.append(bridge)
	# Portcullis: up (open) at t = 0, drops over PORT_TRANSITION to the road, rises again.
	var pb: Basis = _frame_basis(PORT_S, PORT_LATERAL)
	var down_c: Vector3 = _frame[0] + _frame[2] * PORT_HALF.y
	var up_c: Vector3 = down_c + _frame[2] * PORT_LIFT
	var port: MoverDef = _new_mover(MoverDef.Shape.BOX, PORT_PERIOD)
	port.half_extents = PORT_HALF
	var pt: PackedFloat32Array = [0.0, PORT_DOWN_AT - PORT_TRANSITION, PORT_DOWN_AT, PORT_UP_AT, PORT_UP_AT + PORT_TRANSITION]
	var pp: PackedVector3Array = [up_c, up_c, down_c, down_c, up_c]
	for k in pt.size():
		port.key_t.append(pt[k])
		port.key_pos.append(pp[k])
		port.key_rot.append(_quat_key(pb))
	_fixture.data.movers.append(port)
	# Barrels: non-solid cylinders (axis along the road's right) rolling down the road.
	for n in BARREL_PHASES.size():
		var barrel: MoverDef = _new_mover(MoverDef.Shape.CYLINDER, BARREL_PERIOD)
		barrel.solid = false
		barrel.radius = BARREL_RADIUS
		barrel.half_height = BARREL_RADIUS
		for k in BARREL_KEYS:
			var u: float = BARREL_PERIOD * float(k) / float(BARREL_KEYS)
			var d: float = minf(BARREL_SPEED * fposmod(u - BARREL_PHASES[n], BARREL_PERIOD), BARREL_TRAVEL)
			var fb: Basis = _frame_basis(BARREL_START_S + d, BARREL_LANES[n])
			var at: Vector3 = _frame[0] + _frame[2] * BARREL_RADIUS
			var lying: Basis = Basis(_frame[2], _frame[3], _frame[1]).orthonormalized()
			var roll: Basis = Basis(fb.x, -d / BARREL_RADIUS)
			barrel.key_t.append(u)
			barrel.key_pos.append(at)
			barrel.key_rot.append(_quat_key(roll * lying))
		_fixture.data.movers.append(barrel)


func _add_worst_movers() -> void:
	for n in SPIN_S_OFFSETS.size():
		var b0: Basis = _frame_basis(SPIN_S + SPIN_S_OFFSETS[n], SPIN_LATERALS[n])
		var at: Vector3 = _frame[0] + _frame[2] * SPIN_HEIGHTS[n]
		var axis: Vector3 = _frame[2]
		var spinner: MoverDef = _new_mover(MoverDef.Shape.BOX, SPIN_PERIOD)
		spinner.half_extents = SPIN_HALF
		for k in SPIN_KEYS:
			var angle: float = float(n) * SPIN_PHASE_STEP + TAU * float(k) / float(SPIN_KEYS)
			spinner.key_t.append(SPIN_PERIOD * float(k) / float(SPIN_KEYS))
			spinner.key_pos.append(at)
			spinner.key_rot.append(_quat_key(Basis(axis, angle) * b0))
		_fixture.data.movers.append(spinner)


## Calls [member on_tick] every physics tick.
class Hook extends Node:
	var on_tick: Callable

	func _physics_process(_delta: float) -> void:
		on_tick.call()
