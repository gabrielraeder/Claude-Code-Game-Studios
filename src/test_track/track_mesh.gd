class_name TrackMesh
extends Node3D
## Builds the visible track (road, curbs, start line, walls, shortcut branches, moat) from a
## TrackModel and its TrackTheme. Presentation only: collision is done by lateral clamping
## in KartSim. Walls are blocks with alternating colors and heights (crenellation), with a
## gap wherever a branch corridor meets the main road.
## Implements design/game-brief.md, "Look and references".

const START_LINE_CELLS: int = 10
const START_LINE_ROWS: int = 2
## Height of the branch deck above the main road, so overlapping roads do not flicker.
const DECK_Y: float = 0.04
## Height of the moat surface (below the road).
const WATER_Y: float = -0.03
## Extra clearance (meters) between a branch corridor and the main wall opening.
const GAP_MARGIN: float = 0.6


## Creates the meshes for [param track] as children of this node.
func build(track: TrackModel) -> void:
	var th: TrackTheme = track.theme
	var road := SurfaceTool.new()
	road.begin(Mesh.PRIMITIVE_TRIANGLES)
	_main_road(road, track, th)
	_start_line(road, track, th)
	for i in track.branches.size():
		_branch_road(road, track, i)
	add_child(_instance(road.commit()))

	var walls := SurfaceTool.new()
	walls.begin(Mesh.PRIMITIVE_TRIANGLES)
	_main_walls(walls, track, th)
	for i in track.branches.size():
		_branch_walls(walls, track, i)
	add_child(_instance(walls.commit()))

	var water := SurfaceTool.new()
	water.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any_water: bool = false
	for i in track.branches.size():
		any_water = _branch_fill(water, track, i) or any_water
	if any_water:
		add_child(_instance(water.commit()))


func _normals_of(pts: PackedVector2Array, closed: bool) -> Array[Vector2]:
	var n: int = pts.size()
	var out: Array[Vector2] = []
	for i in n:
		var a: Vector2 = pts[(i - 1 + n) % n] if (closed or i > 0) else pts[0]
		var b: Vector2 = pts[(i + 1) % n] if (closed or i < n - 1) else pts[n - 1]
		var t: Vector2 = (b - a).normalized()
		out.append(Vector2(-t.y, t.x))
	return out


func _main_road(st: SurfaceTool, track: TrackModel, th: TrackTheme) -> void:
	var half: float = track.data.road_half_width
	var wall: float = track.wall_offset
	var pts: PackedVector2Array = track.points
	var n: int = pts.size()
	var normals: Array[Vector2] = _normals_of(pts, true)
	for i in n:
		var j: int = (i + 1) % n
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[j]
		var na: Vector2 = normals[i]
		var nb: Vector2 = normals[j]
		_quad(st, a + na * half, a - na * half, b - nb * half, b + nb * half, 0.0, th.road_color)
		var curb: Color = th.curb_color_a if ((i / maxi(th.curb_stripe_segments, 1)) % 2) == 0 else th.curb_color_b
		_quad(st, a + na * wall, a + na * half, b + nb * half, b + nb * wall, 0.01, curb)
		_quad(st, a - na * half, a - na * wall, b - nb * wall, b - nb * half, 0.01, curb)


func _start_line(st: SurfaceTool, track: TrackModel, th: TrackTheme) -> void:
	var half: float = track.data.road_half_width
	var p0: Vector2 = track.point_at(0.0)
	var t0: Vector2 = track.tangent_at(0.0)
	var n0: Vector2 = track.normal_at(0.0)
	var cell_w: float = 2.0 * half / START_LINE_CELLS
	for r in START_LINE_ROWS:
		for c in START_LINE_CELLS:
			var w0: float = -half + c * cell_w
			var w1: float = w0 + cell_w
			var d0: float = -1.0 + r
			var d1: float = d0 + 1.0
			var col: Color = th.line_color_a if (r + c) % 2 == 0 else th.line_color_b
			_quad(st, p0 + n0 * w0 + t0 * d0, p0 + n0 * w1 + t0 * d0,
					p0 + n0 * w1 + t0 * d1, p0 + n0 * w0 + t0 * d1, 0.02, col)


func _branch_road(st: SurfaceTool, track: TrackModel, bi: int) -> void:
	var b: TrackBranch = track.data.branches[bi]
	var path: TrackModel.Path = track.branches[bi]
	var pts: PackedVector2Array = path.points
	var normals: Array[Vector2] = _normals_of(pts, false)
	var half: float = b.half_width + b.curb_width
	for i in pts.size() - 1:
		var col: Color = b.deck_color if i % 2 == 0 else b.deck_alt_color
		_quad(st, pts[i] + normals[i] * half, pts[i] - normals[i] * half,
				pts[i + 1] - normals[i + 1] * half, pts[i + 1] + normals[i + 1] * half, DECK_Y, col)


func _main_walls(st: SurfaceTool, track: TrackModel, th: TrackTheme) -> void:
	var pts: PackedVector2Array = track.points
	var n: int = pts.size()
	var normals: Array[Vector2] = _normals_of(pts, true)
	var stripe: int = maxi(th.wall_stripe_segments, 1)
	for i in n:
		var j: int = (i + 1) % n
		for side in [1.0, -1.0]:
			var a: Vector2 = pts[i] + normals[i] * track.wall_offset * side
			var b: Vector2 = pts[j] + normals[j] * track.wall_offset * side
			if _in_branch_opening(track, (a + b) * 0.5):
				continue
			var odd: bool = (i / stripe) % 2 == 1
			var h: float = th.wall_height + (0.0 if odd else th.merlon_height)
			_block(st, a, b, -normals[i] * side, th.wall_thickness, h,
					th.wall_color_b if odd else th.wall_color_a)


func _branch_walls(st: SurfaceTool, track: TrackModel, bi: int) -> void:
	var b: TrackBranch = track.data.branches[bi]
	var path: TrackModel.Path = track.branches[bi]
	var pts: PackedVector2Array = path.points
	var normals: Array[Vector2] = _normals_of(pts, false)
	for i in pts.size() - 1:
		for side in [1.0, -1.0]:
			var a: Vector2 = pts[i] + normals[i] * path.wall_offset * side
			var c: Vector2 = pts[i + 1] + normals[i + 1] * path.wall_offset * side
			var mid: Vector2 = (a + c) * 0.5
			if track.distance_to_path(mid, TrackModel.MAIN_PATH) < track.wall_offset + GAP_MARGIN:
				continue
			_block(st, a, c, -normals[i] * side, b.curb_width, b.wall_height,
					b.wall_alt_color if i % 2 == 1 else b.wall_color)


# True when [param p] (a wall point of the main road) lies in the opening of a branch.
func _in_branch_opening(track: TrackModel, p: Vector2) -> bool:
	for bp in track.branches:
		if bp.bounds.has_point(p) and track.distance_to_path(p, bp.index) < bp.wall_offset + GAP_MARGIN:
			return true
	return false


# Fills the area between a branch and the main road it bypasses (the moat). True if drawn.
func _branch_fill(st: SurfaceTool, track: TrackModel, bi: int) -> bool:
	var b: TrackBranch = track.data.branches[bi]
	if b.fill_color.a <= 0.0:
		return false
	var path: TrackModel.Path = track.branches[bi]
	var poly := PackedVector2Array()
	poly.append(track.point_at(b.s_in))
	for i in track.points.size():
		var c: float = track.cumulative[i]
		if c > b.s_in + 0.5 and c < b.s_out - 0.5:
			poly.append(track.points[i])
	poly.append(track.point_at(b.s_out))
	for k in range(path.points.size() - 2, 0, -1):
		poly.append(path.points[k])
	var tris: PackedInt32Array = Geometry2D.triangulate_polygon(poly)
	if tris.is_empty():
		push_warning("TrackMesh: moat polygon of branch %s could not be triangulated" % b.id)
		return false
	st.set_color(b.fill_color)
	st.set_normal(Vector3.UP)
	for idx in tris:
		st.add_vertex(_v3(poly[idx], WATER_Y))
	return true


# One wall block from [param a] to [param b]; [param inward] points toward the road.
func _block(st: SurfaceTool, a: Vector2, b: Vector2, inward: Vector2, thickness: float,
		height: float, col: Color) -> void:
	var a2: Vector2 = a - inward * thickness
	var b2: Vector2 = b - inward * thickness
	st.set_color(col)
	_vquad(st, a, b, 0.0, height, inward)
	_vquad(st, a2, b2, 0.0, height, -inward)
	_vquad(st, a, a2, 0.0, height, (a - b).normalized())
	_vquad(st, b, b2, 0.0, height, (b - a).normalized())
	st.set_normal(Vector3.UP)
	_tri(st, _v3(a, height), _v3(b, height), _v3(b2, height))
	_tri(st, _v3(a, height), _v3(b2, height), _v3(a2, height))


func _vquad(st: SurfaceTool, a: Vector2, b: Vector2, y0: float, y1: float, normal: Vector2) -> void:
	st.set_normal(_v3(normal, 0.0))
	_tri(st, _v3(a, y0), _v3(b, y0), _v3(b, y1))
	_tri(st, _v3(a, y0), _v3(b, y1), _v3(a, y1))


func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)


func _instance(mesh: Mesh) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	# Vertex colors are authored in sRGB (like every Color in the theme data).
	m.vertex_color_is_srgb = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	return mi


func _v3(p: Vector2, y: float) -> Vector3:
	return Vector3(p.x, y, p.y)


func _quad(st: SurfaceTool, a: Vector2, b: Vector2, c: Vector2, d: Vector2, y: float, col: Color) -> void:
	st.set_color(col)
	st.set_normal(Vector3.UP)
	st.add_vertex(_v3(a, y))
	st.add_vertex(_v3(b, y))
	st.add_vertex(_v3(c, y))
	st.add_vertex(_v3(a, y))
	st.add_vertex(_v3(c, y))
	st.add_vertex(_v3(d, y))
