## PROTOTYPE - NOT FOR PRODUCTION. Collision spike. Backend (c): pure-GDScript XZ grid.
##
## Triangles are binned by their XZ bounding box into square cells (CSR layout:
## cell_start + cell_tris). Ground query = Moller-Trumbore ray vs the triangles of
## every cell the ray's XZ footprint touches, front faces only, nearest t wins
## (so decks / ramps resolve by distance along the ray, any ray direction).
## Wall query = sphere-at-endpoint vs wall triangle planes in the cells around the
## end point (face test only, no edge/vertex rounding: a cost proxy for a sweep,
## not a finished algorithm).
extends RefCounted

const TrackGen := preload("res://scripts/track_gen.gd")
const DET_EPS: float = 1e-9

var cell: float = 2.0
var inv_cell: float = 0.5
var min_x: float = 0.0
var min_z: float = 0.0
var nx: int = 0
var nz: int = 0
var build_ms: float = 0.0

# ground triangles
var g_a := PackedVector3Array()
var g_e1 := PackedVector3Array()
var g_e2 := PackedVector3Array()
var g_surf := PackedByteArray()
var g_start := PackedInt32Array()
var g_list := PackedInt32Array()
# wall triangles
var w_a := PackedVector3Array()
var w_e1 := PackedVector3Array()
var w_e2 := PackedVector3Array()
var w_n := PackedVector3Array()
var w_bary := PackedFloat64Array()  # d00, d01, d11, inv_den per tri
var w_start := PackedInt32Array()
var w_list := PackedInt32Array()

var hit_pos: Vector3
var hit_normal: Vector3
var hit_surf: int = -1
var wall_pos: Vector3
var wall_normal: Vector3
var tests_ground: int = 0  # triangle tests performed (diagnostic)
var tests_wall: int = 0

func _bin(faces: PackedVector3Array, start: PackedInt32Array, list: PackedInt32Array, pad: float) -> void:
	var n_tri: int = faces.size() / 3
	var cells: int = nx * nz
	start.resize(cells + 1)
	start.fill(0)
	var ranges := PackedInt32Array()
	ranges.resize(n_tri * 4)
	for t: int in n_tri:
		var a: Vector3 = faces[t * 3]
		var b: Vector3 = faces[t * 3 + 1]
		var c: Vector3 = faces[t * 3 + 2]
		var x0: int = clampi(int(floor((minf(a.x, minf(b.x, c.x)) - pad - min_x) * inv_cell)), 0, nx - 1)
		var x1: int = clampi(int(floor((maxf(a.x, maxf(b.x, c.x)) + pad - min_x) * inv_cell)), 0, nx - 1)
		var z0: int = clampi(int(floor((minf(a.z, minf(b.z, c.z)) - pad - min_z) * inv_cell)), 0, nz - 1)
		var z1: int = clampi(int(floor((maxf(a.z, maxf(b.z, c.z)) + pad - min_z) * inv_cell)), 0, nz - 1)
		ranges[t * 4] = x0
		ranges[t * 4 + 1] = x1
		ranges[t * 4 + 2] = z0
		ranges[t * 4 + 3] = z1
		for z: int in range(z0, z1 + 1):
			for x: int in range(x0, x1 + 1):
				start[z * nx + x + 1] += 1
	for i: int in cells:
		start[i + 1] += start[i]
	list.resize(start[cells])
	var fill := start.duplicate()
	for t: int in n_tri:
		for z: int in range(ranges[t * 4 + 2], ranges[t * 4 + 3] + 1):
			for x: int in range(ranges[t * 4], ranges[t * 4 + 1] + 1):
				var ci: int = z * nx + x
				list[fill[ci]] = t
				fill[ci] += 1

func setup(tg: TrackGen, p_cell: float, wall_pad: float) -> void:
	var t0: int = Time.get_ticks_usec()
	cell = p_cell
	inv_cell = 1.0 / cell
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for v: Vector3 in tg.ground_faces:
		lo = Vector2(minf(lo.x, v.x), minf(lo.y, v.z))
		hi = Vector2(maxf(hi.x, v.x), maxf(hi.y, v.z))
	for v: Vector3 in tg.wall_faces:
		lo = Vector2(minf(lo.x, v.x), minf(lo.y, v.z))
		hi = Vector2(maxf(hi.x, v.x), maxf(hi.y, v.z))
	min_x = lo.x - cell
	min_z = lo.y - cell
	nx = int(ceil((hi.x - min_x) * inv_cell)) + 2
	nz = int(ceil((hi.y - min_z) * inv_cell)) + 2
	var ng: int = tg.ground_tri_count()
	g_a.resize(ng)
	g_e1.resize(ng)
	g_e2.resize(ng)
	g_surf = tg.ground_surf
	for t: int in ng:
		var a: Vector3 = tg.ground_faces[t * 3]
		g_a[t] = a
		g_e1[t] = tg.ground_faces[t * 3 + 1] - a
		g_e2[t] = tg.ground_faces[t * 3 + 2] - a
	var nw: int = tg.wall_tri_count()
	w_a.resize(nw)
	w_e1.resize(nw)
	w_e2.resize(nw)
	w_n.resize(nw)
	w_bary.resize(nw * 4)
	for t: int in nw:
		var a: Vector3 = tg.wall_faces[t * 3]
		var e1: Vector3 = tg.wall_faces[t * 3 + 1] - a
		var e2: Vector3 = tg.wall_faces[t * 3 + 2] - a
		w_a[t] = a
		w_e1[t] = e1
		w_e2[t] = e2
		w_n[t] = e2.cross(e1).normalized()  # Godot front normal (c-a)x(b-a)
		var d00: float = e1.dot(e1)
		var d01: float = e1.dot(e2)
		var d11: float = e2.dot(e2)
		w_bary[t * 4] = d00
		w_bary[t * 4 + 1] = d01
		w_bary[t * 4 + 2] = d11
		w_bary[t * 4 + 3] = 1.0 / (d00 * d11 - d01 * d01)
	_bin(tg.ground_faces, g_start, g_list, 0.0)
	_bin(tg.wall_faces, w_start, w_list, wall_pad)
	build_ms = (Time.get_ticks_usec() - t0) / 1000.0

func memory_estimate_bytes() -> int:
	return (g_a.size() * 3 * 12) + g_surf.size() + (g_start.size() + g_list.size()) * 4 \
		+ (w_a.size() * 4 * 12) + w_bary.size() * 8 + (w_start.size() + w_list.size()) * 4

func _cell_x(x: float) -> int:
	return clampi(int(floor((x - min_x) * inv_cell)), 0, nx - 1)

func _cell_z(z: float) -> int:
	return clampi(int(floor((z - min_z) * inv_cell)), 0, nz - 1)

## Ray from origin along dir (unit) up to max_dist; nearest front face wins.
func cast_ground(origin: Vector3, dir: Vector3, max_dist: float) -> bool:
	var end: Vector3 = origin + dir * max_dist
	var x0: int = _cell_x(minf(origin.x, end.x))
	var x1: int = _cell_x(maxf(origin.x, end.x))
	var z0: int = _cell_z(minf(origin.z, end.z))
	var z1: int = _cell_z(maxf(origin.z, end.z))
	var best_t: float = max_dist
	var best: int = -1
	for z: int in range(z0, z1 + 1):
		for x: int in range(x0, x1 + 1):
			var ci: int = z * nx + x
			for k: int in range(g_start[ci], g_start[ci + 1]):
				var t: int = g_list[k]
				var e1: Vector3 = g_e1[t]
				var e2: Vector3 = g_e2[t]
				var p: Vector3 = dir.cross(e2)
				var det: float = e1.dot(p)
				# front face (Godot): normal e2 x e1, so dir . n = det < 0
				if det > -DET_EPS:
					continue
				var inv: float = 1.0 / det
				var s: Vector3 = origin - g_a[t]
				var u: float = s.dot(p) * inv
				if u < 0.0 or u > 1.0:
					continue
				var q: Vector3 = s.cross(e1)
				var v: float = dir.dot(q) * inv
				if v < 0.0 or u + v > 1.0:
					continue
				var tt: float = e2.dot(q) * inv
				if tt >= 0.0 and tt < best_t:
					best_t = tt
					best = t
	tests_ground += 1
	if best < 0:
		return false
	hit_pos = origin + dir * best_t
	hit_normal = g_e2[best].cross(g_e1[best]).normalized()
	hit_surf = g_surf[best]
	return true

## Sphere sweep from -> to vs wall faces (front side only, like Jolt one-sided
## faces). If the sphere starts clear of a face plane (d_from >= r) the first
## contact point along the segment is tested; otherwise (already touching) the
## end point. Face interior only: edges / vertices are not rounded.
func sweep_walls(from: Vector3, to: Vector3, r: float) -> bool:
	var ci: int = _cell_z(to.z) * nx + _cell_x(to.x)  # walls binned with pad >= r
	var best_f: float = INF
	var best: int = -1
	var best_c: Vector3
	for k: int in range(w_start[ci], w_start[ci + 1]):
		var t: int = w_list[k]
		var n: Vector3 = w_n[t]
		var a: Vector3 = w_a[t]
		var d_to: float = (to - a).dot(n)
		if d_to >= r:
			continue
		var d_from: float = (from - a).dot(n)
		if d_from < 0.0:
			continue  # centre behind the face: one-sided, ignore
		var c: Vector3 = to
		var f: float = 1.0
		if d_from >= r:
			f = (d_from - r) / (d_from - d_to)
			c = from + (to - from) * f
		var w: Vector3 = c - a
		w -= n * w.dot(n)
		var d20: float = w.dot(w_e1[t])
		var d21: float = w.dot(w_e2[t])
		var b: int = t * 4
		var bv: float = (w_bary[b + 2] * d20 - w_bary[b + 1] * d21) * w_bary[b + 3]
		var bw: float = (w_bary[b] * d21 - w_bary[b + 1] * d20) * w_bary[b + 3]
		if bv < 0.0 or bw < 0.0 or bv + bw > 1.0:
			continue
		if f < best_f:
			best_f = f
			best = t
			best_c = c
	tests_wall += 1
	if best < 0:
		return false
	wall_normal = w_n[best]
	wall_pos = best_c - wall_normal * (best_c - w_a[best]).dot(wall_normal)
	return true
