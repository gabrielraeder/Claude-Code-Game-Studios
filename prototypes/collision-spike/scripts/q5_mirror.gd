## PROTOTYPE - NOT FOR PRODUCTION. Collision spike. Q5: ADR-0001 section 7 mirror on baked triangles.
## Mirrors the 50k synthetic track (x -> -x, winding flipped by swapping b and c),
## then compares rays / sweeps on the original vs the mirrored geometry with mirrored
## queries, for the Jolt face backend and the grid. A third variant mirrors WITHOUT
## the winding flip to show what happens if it is forgotten.
## Run: godot --headless --path . -s res://scripts/q5_mirror.gd   (with the face index setting on)
extends SceneTree

const TrackGen := preload("res://scripts/track_gen.gd")
const EngineBackend := preload("res://scripts/backend_engine.gd")
const GridBackend := preload("res://scripts/backend_grid.gd")

const SAMPLES: int = 4000
const RAY_START_UP: float = 2.0
const RAY_LEN: float = 4.0
const LAT_MAX: float = 14.5
const SPHERE_R: float = 0.6
const SPHERE_UP: float = 0.7
const WALL_PUSH: float = 1.0
const POS_TOL: float = 0.001
const N_TOL: float = 0.001
const CELL: float = 1.0
const M := Basis(Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1))

static func _mx(v: Vector3) -> Vector3:
	return Vector3(-v.x, v.y, v.z)

static func _mirror_faces(f: PackedVector3Array, flip: bool) -> PackedVector3Array:
	var out := PackedVector3Array()
	out.resize(f.size())
	for t: int in f.size() / 3:
		var a: Vector3 = _mx(f[t * 3])
		var b: Vector3 = _mx(f[t * 3 + 1])
		var c: Vector3 = _mx(f[t * 3 + 2])
		out[t * 3] = a
		out[t * 3 + 1] = c if flip else b
		out[t * 3 + 2] = b if flip else c
	return out

func _mirrored(tg: TrackGen, flip: bool) -> TrackGen:
	var m: TrackGen = TrackGen.new()
	m.ground_faces = _mirror_faces(tg.ground_faces, flip)
	m.ground_surf = tg.ground_surf
	m.wall_faces = _mirror_faces(tg.wall_faces, flip)
	m.wall_surf = tg.wall_surf
	return m

func _run(label: String, base_q: Object, mir_q: Object, is_grid: bool, origins: PackedVector3Array, dirs: PackedVector3Array, wf: PackedVector3Array, wt: PackedVector3Array) -> void:
	var hit_both: int = 0
	var miss_both: int = 0
	var hit_only_base: int = 0
	var hit_only_mir: int = 0
	var bad_pos: int = 0
	var bad_n: int = 0
	var bad_surf: int = 0
	var up_normals_mir: int = 0
	for i: int in origins.size():
		var o: Vector3 = origins[i]
		var d: Vector3 = dirs[i]
		var hb: bool = base_q.cast_ground(o, d, RAY_LEN)
		var pb: Vector3 = base_q.hit_pos
		var nb: Vector3 = base_q.hit_normal
		var sb: int = base_q.hit_surf
		var hm: bool = mir_q.cast_ground(_mx(o), _mx(d), RAY_LEN)
		if hb and hm:
			hit_both += 1
			if not mir_q.hit_pos.is_equal_approx(_mx(pb)) and mir_q.hit_pos.distance_to(_mx(pb)) > POS_TOL:
				bad_pos += 1
			if mir_q.hit_normal.distance_to(_mx(nb)) > N_TOL:
				bad_n += 1
			if mir_q.hit_surf != sb:
				bad_surf += 1
			if mir_q.hit_normal.y > 0.0:
				up_normals_mir += 1
		elif hb:
			hit_only_base += 1
		elif hm:
			hit_only_mir += 1
		else:
			miss_both += 1
	var w_both: int = 0
	var w_only_base: int = 0
	var w_only_mir: int = 0
	var w_bad_n: int = 0
	for i: int in wf.size():
		var b: bool
		var m: bool
		if is_grid:
			b = base_q.sweep_walls(wf[i], wt[i], SPHERE_R)
			m = mir_q.sweep_walls(_mx(wf[i]), _mx(wt[i]), SPHERE_R)
		else:
			b = base_q.sweep_walls(wf[i], wt[i])
			m = mir_q.sweep_walls(_mx(wf[i]), _mx(wt[i]))
		if b and m:
			w_both += 1
			if mir_q.wall_normal.distance_to(_mx(base_q.wall_normal)) > N_TOL:
				w_bad_n += 1
		elif b:
			w_only_base += 1
		elif m:
			w_only_mir += 1
	print("Q5 %-34s rays=%d both=%d miss_both=%d only_orig=%d only_mirror=%d | on both: pos>%.3fm=%d normal!=M*n=%d surface diff=%d mirror normals with +y=%d | walls=%d both=%d only_orig=%d only_mirror=%d normal!=M*n=%d" % [label, origins.size(), hit_both, miss_both, hit_only_base, hit_only_mir, POS_TOL, bad_pos, bad_n, bad_surf, up_normals_mir, wf.size(), w_both, w_only_base, w_only_mir, w_bad_n])

func _initialize() -> void:
	print("face index setting = ", ProjectSettings.get_setting("physics/jolt_physics_3d/queries/enable_ray_cast_face_index"))
	var tg: TrackGen = TrackGen.new()
	tg.build(1.0, 10, 4)
	# deterministic query set: SAMPLES points along the loop, lateral sweep across the width
	var origins := PackedVector3Array()
	var dirs := PackedVector3Array()
	var wf := PackedVector3Array()
	var wt := PackedVector3Array()
	var fr := PackedVector3Array()
	fr.resize(3)
	for i: int in SAMPLES:
		var s: float = tg.length * (float(i) + 0.37) / float(SAMPLES)
		var l: float = LAT_MAX * sin(float(i) * 0.731)
		tg.frame_at(s, l, fr)
		origins.append(fr[0] + fr[2] * RAY_START_UP)
		dirs.append(-fr[2])
		var r: Vector3 = fr[1].cross(fr[2])
		var side: float = signf(l) if l != 0.0 else 1.0
		wf.append(fr[0] + fr[2] * SPHERE_UP)
		wt.append(fr[0] + fr[2] * SPHERE_UP + r * side * WALL_PUSH + fr[1] * 0.5)
	var mir: TrackGen = _mirrored(tg, true)
	var mir_noflip: TrackGen = _mirrored(tg, false)
	for variant: Array in [["engine face, winding flipped", mir], ["engine face, winding NOT flipped", mir_noflip]]:
		var a: EngineBackend = EngineBackend.new()
		a.setup(tg, EngineBackend.MODE_FACE, EngineBackend.API_INTO, SPHERE_R)
		var b: EngineBackend = EngineBackend.new()
		b.setup(variant[1], EngineBackend.MODE_FACE, EngineBackend.API_INTO, SPHERE_R)
		_run(variant[0], a, b, false, origins, dirs, wf, wt)
		a.free_all()
		b.free_all()
	for variant: Array in [["grid, winding flipped", mir], ["grid, winding NOT flipped", mir_noflip]]:
		var a: GridBackend = GridBackend.new()
		a.setup(tg, CELL, SPHERE_R)
		var b: GridBackend = GridBackend.new()
		b.setup(variant[1], CELL, SPHERE_R)
		_run(variant[0], a, b, true, origins, dirs, wf, wt)
	# pose bases: M*B*M stays a rotation and its forward is the mirrored forward
	var worst_det: float = 0.0
	var worst_fwd: float = 0.0
	for i: int in 100:
		var b: Basis = Basis.from_euler(Vector3(0.1 * sin(i), 0.37 * i, 0.2 * cos(i * 1.3)))
		var mb: Basis = M * b * M
		worst_det = maxf(worst_det, absf(mb.determinant() - 1.0))
		worst_fwd = maxf(worst_fwd, (mb * Vector3(0, 0, -1)).distance_to(_mx(b * Vector3(0, 0, -1))))
	var naive: Basis = Basis(Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)) * Basis.from_euler(Vector3(0, 0.5, 0))
	print("Q5 poses: max |det(M*B*M) - 1| = %.9f, max |fwd(M*B*M) - M*fwd(B)| = %.9f over 100 bases; naive M*B has det %.3f" % [worst_det, worst_fwd, naive.determinant()])
	quit()
