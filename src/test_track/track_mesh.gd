class_name TrackMesh
extends Node3D
## Builds the visible track (road, curbs, start line, walls, branches, hazard water, boost pads)
## from a TrackModel and its TrackTheme. Presentation only: collision is done by lateral
## clamping in KartSim. Widths follow the road's per-point profile; open edges (over water)
## and rail-less branches get no wall. Walls are blocks with alternating colors and heights
## (crenellation), with a gap wherever another road's corridor meets them.
## Implements design/game-brief.md, "Look and references", and story 003 round 2.

const START_LINE_CELLS: int = 10
const START_LINE_ROWS: int = 2
## Height of the branch deck above the main road, so overlapping roads do not flicker.
const DECK_Y: float = 0.04
## Height of hazard water (below the road).
const WATER_Y: float = -0.03
## Height of boost pads above the road.
const PAD_Y: float = 0.05
## Lift (meters) of a ramp's top surface above the road, so its start does not z-fight the road.
const RAMP_LIFT: float = 0.03
## Extra clearance (meters) between another corridor and a wall that is left out.
const GAP_MARGIN: float = 0.6
## Clearance (meters) a support column keeps from the corridor of a road passing under it, and
## the step it slides along its own road to find a clear spot.
const PILLAR_CLEARANCE: float = 0.8
const PILLAR_SHIFT_STEP: float = 1.5


## Creates the meshes for [param track] as children of this node.
func build(track: TrackModel) -> void:
	var th: TrackTheme = track.theme
	var road := SurfaceTool.new()
	road.begin(Mesh.PRIMITIVE_TRIANGLES)
	_main_road(road, track, th)
	_start_line(road, track, th)
	for i in track.branches.size():
		_branch_road(road, track, i)
	_pads(road, track, th)
	_ramps(road, track)
	_deck_underside(road, track)
	add_child(_instance(road.commit()))

	var walls := SurfaceTool.new()
	walls.begin(Mesh.PRIMITIVE_TRIANGLES)
	_main_walls(walls, track, th)
	_pillars(walls, track)
	for i in track.branches.size():
		_branch_walls(walls, track, i)
	add_child(_instance(walls.commit()))

	var water := SurfaceTool.new()
	water.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any_water: bool = false
	var lava := SurfaceTool.new()
	lava.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any_lava: bool = false
	for i in track.hazard_polygons.size():
		var y: float = DECK_Y + 0.05 if track.hazard_gates[i] > 0.0 else WATER_Y  # the lava gap lies on the deck
		if track.hazard_kinds[i] == &"lava":
			any_lava = _fill_polygon(lava, track.hazard_polygons[i], th.lava_core_color, y) or any_lava
			continue
		any_water = _fill_polygon(water, track.hazard_polygons[i], th.water_color, y) or any_water
	for i in track.branches.size():
		any_water = _branch_fill(water, track, i) or any_water
	if any_water:
		add_child(_instance(water.commit()))
	if any_lava:
		var lm := MeshInstance3D.new()
		lm.mesh = lava.commit()
		lm.material_override = lava_material(th)
		add_child(lm)


## Animated lava (art bible section 4): a glowing core with brighter veins and a dark jagged
## crust drifting over it. Unshaded, so it needs no light. Shared with the dungeon scenery.
static func lava_material(th: TrackTheme) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = """shader_type spatial;
render_mode unshaded, cull_disabled;
uniform vec3 core : source_color;
uniform vec3 bright : source_color;
uniform vec3 crust : source_color;
varying vec3 wp;
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	float a = sin(wp.x * 0.9 + TIME * 0.8) + sin(wp.z * 1.1 - TIME * 0.6) + sin((wp.x + wp.z) * 0.45 + TIME * 0.4);
	float b = sin(wp.x * 2.3 - TIME * 1.3) * sin(wp.z * 2.1 + TIME * 1.1);
	float jag = abs(sin(a * 1.7 + b * 2.2));
	vec3 c = mix(core, bright, smoothstep(0.55, 0.95, jag));
	float plate = step(0.78, 0.5 + 0.28 * a + 0.3 * b);
	c = mix(c, crust, plate * 0.85);
	ALBEDO = c;
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("core", th.lava_core_color)
	m.set_shader_parameter("bright", th.lava_bright_color)
	m.set_shader_parameter("crust", th.lava_crust_color)
	return m


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
	var path: TrackModel.Path = track.main
	var pts: PackedVector2Array = path.points
	var n: int = pts.size()
	var normals: Array[Vector2] = _normals_of(pts, true)
	for i in n:
		var j: int = (i + 1) % n
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[j]
		var na: Vector2 = normals[i]
		var nb: Vector2 = normals[j]
		var ha: float = path.half[i]
		var hb: float = path.half[j]
		var ca: float = ha + path.curb
		var cb: float = hb + path.curb
		var ka: float = tan(path.bank[i])
		var kb: float = tan(path.bank[j])
		var ya: float = path.y[i]
		var yb: float = path.y[j]
		# The normal side (+) is the high side for a positive bank: y = centerline + lateral * tan(bank).
		_quadh(st, a + na * ha, a - na * ha, b - nb * hb, b + nb * hb,
				PackedFloat32Array([ya + ha * ka, ya - ha * ka, yb - hb * kb, yb + hb * kb]), 0.0, th.road_color)
		var curb: Color = th.curb_color_a if ((i / maxi(th.curb_stripe_segments, 1)) % 2) == 0 else th.curb_color_b
		_quadh(st, a + na * ca, a + na * ha, b + nb * hb, b + nb * cb,
				PackedFloat32Array([ya + ca * ka, ya + ha * ka, yb + hb * kb, yb + cb * kb]), 0.01, curb)
		_quadh(st, a - na * ha, a - na * ca, b - nb * cb, b - nb * hb,
				PackedFloat32Array([ya - ha * ka, ya - ca * ka, yb - cb * kb, yb - hb * kb]), 0.01, curb)


func _start_line(st: SurfaceTool, track: TrackModel, th: TrackTheme) -> void:
	var half: float = track.half_width_at(0.0)
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
			var c0: Vector2 = p0 + n0 * w0 + t0 * d0
			var c1: Vector2 = p0 + n0 * w1 + t0 * d0
			var c2: Vector2 = p0 + n0 * w1 + t0 * d1
			var c3: Vector2 = p0 + n0 * w0 + t0 * d1
			_quadh(st, c0, c1, c2, c3, PackedFloat32Array([_road_y(track, c0), _road_y(track, c1),
					_road_y(track, c2), _road_y(track, c3)]), 0.02, col)


func _branch_road(st: SurfaceTool, track: TrackModel, bi: int) -> void:
	var b: TrackBranch = track.data.branches[bi]
	var path: TrackModel.Path = track.branches[bi]
	var pts: PackedVector2Array = path.points
	var normals: Array[Vector2] = _normals_of(pts, false)
	for i in pts.size() - 1:
		var col: Color = b.deck_color if i % 2 == 0 else b.deck_alt_color
		var ha: float = path.half[i] + b.curb_width
		var hb: float = path.half[i + 1] + b.curb_width
		var ka: float = tan(path.bank[i])
		var kb: float = tan(path.bank[i + 1])
		_quadh(st, pts[i] + normals[i] * ha, pts[i] - normals[i] * ha,
				pts[i + 1] - normals[i + 1] * hb, pts[i + 1] + normals[i + 1] * hb,
				PackedFloat32Array([path.y[i] + ha * ka, path.y[i] - ha * ka,
				path.y[i + 1] - hb * kb, path.y[i + 1] + hb * kb]), DECK_Y, col)


# Boost pads: a base plate with a chevron pointing along the road.
func _pads(st: SurfaceTool, track: TrackModel, th: TrackTheme) -> void:
	for i in track.pad_centers.size():
		var c: Vector2 = track.pad_centers[i]
		var t: Vector2 = track.pad_dirs[i]
		var n: Vector2 = Vector2(-t.y, t.x)
		var h: Vector2 = track.pad_halves[i]
		var q0: Vector2 = c - t * h.x + n * h.y
		var q1: Vector2 = c - t * h.x - n * h.y
		var q2: Vector2 = c + t * h.x - n * h.y
		var q3: Vector2 = c + t * h.x + n * h.y
		_quadh(st, q0, q1, q2, q3, PackedFloat32Array([_road_y(track, q0), _road_y(track, q1),
				_road_y(track, q2), _road_y(track, q3)]), PAD_Y, th.pad_color_a)
		for k in 2:
			var base: Vector2 = c + t * (h.x * (-0.55 + 0.6 * k))
			var tip: Vector2 = base + t * h.x * 0.45
			var w: float = h.y * 0.75
			st.set_color(th.pad_color_b)
			st.set_normal(Vector3.UP)
			for v in [base + n * w, tip, base + n * w * 0.4 + t * 0.6, base - n * w, base - n * w * 0.4 + t * 0.6, tip]:
				st.add_vertex(_v3(v, _road_y(track, v) + PAD_Y + 0.01))


func _main_walls(st: SurfaceTool, track: TrackModel, th: TrackTheme) -> void:
	var path: TrackModel.Path = track.main
	var pts: PackedVector2Array = path.points
	var n: int = pts.size()
	var normals: Array[Vector2] = _normals_of(pts, true)
	var stripe: int = maxi(th.wall_stripe_segments, 1)
	for i in n:
		var j: int = (i + 1) % n
		for side in [1, -1]:
			var wi: float = path.wall_pos[i] if side > 0 else path.wall_neg[i]
			var wj: float = path.wall_pos[j] if side > 0 else path.wall_neg[j]
			if wi > path.half[i] + path.curb + 0.05 or wj > path.half[j] + path.curb + 0.05:
				continue  # open edge over water
			var a: Vector2 = pts[i] + normals[i] * wi * side
			var b: Vector2 = pts[j] + normals[j] * wj * side
			if _in_branch_opening(track, (a + b) * 0.5):
				continue
			var odd: bool = (i / stripe) % 2 == 1
			var h: float = th.wall_height + (0.0 if odd else th.merlon_height)
			var ya: float = path.y[i] + wi * side * tan(path.bank[i])
			var yb: float = path.y[j] + wj * side * tan(path.bank[j])
			_block(st, a, b, -normals[i] * side, th.wall_thickness, ya, yb, h,
					th.wall_color_b if odd else th.wall_color_a)


func _branch_walls(st: SurfaceTool, track: TrackModel, bi: int) -> void:
	var b: TrackBranch = track.data.branches[bi]
	if b.open_edge_reach > 0.0 or b.wall_height <= 0.0:
		return
	var path: TrackModel.Path = track.branches[bi]
	var pts: PackedVector2Array = path.points
	var normals: Array[Vector2] = _normals_of(pts, false)
	for i in pts.size() - 1:
		for side in [1.0, -1.0]:
			var a: Vector2 = pts[i] + normals[i] * path.wall_pos[i] * side
			var c: Vector2 = pts[i + 1] + normals[i + 1] * path.wall_pos[i + 1] * side
			var mid: Vector2 = (a + c) * 0.5
			if track.main.nearest(mid, -1, 0).excess < GAP_MARGIN:
				continue
			if _in_other_branch(track, mid, bi):
				continue
			var ya: float = path.y[i] + DECK_Y + path.wall_pos[i] * side * tan(path.bank[i])
			var yb: float = path.y[i + 1] + DECK_Y + path.wall_pos[i + 1] * side * tan(path.bank[i + 1])
			_block(st, a, c, -normals[i] * side, maxf(b.curb_width, 0.3), ya, yb, b.wall_height,
					b.wall_alt_color if i % 2 == 1 else b.wall_color)


# True when [param p] (a wall point of the main road) lies in the opening of a branch.
func _in_branch_opening(track: TrackModel, p: Vector2) -> bool:
	for bp in track.branches:
		if bp.bounds.has_point(p) and bp.nearest(p, -1, 0).excess < GAP_MARGIN:
			return true
	return false


func _in_other_branch(track: TrackModel, p: Vector2, skip: int) -> bool:
	for bp in track.branches:
		if bp.index != skip and bp.bounds.has_point(p) and bp.nearest(p, -1, 0).excess < GAP_MARGIN:
			return true
	return false


# Fills the area between a branch and the main road it bypasses when the branch asks for it
# (fill_color alpha > 0). True if drawn.
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
	return _fill_polygon(st, poly, b.fill_color, WATER_Y)


func _fill_polygon(st: SurfaceTool, poly: PackedVector2Array, col: Color, y: float) -> bool:
	var tris: PackedInt32Array = Geometry2D.triangulate_polygon(poly)
	if tris.is_empty():
		push_warning("TrackMesh: a hazard/fill polygon could not be triangulated")
		return false
	st.set_color(col)
	st.set_normal(Vector3.UP)
	for idx in tris:
		st.add_vertex(_v3(poly[idx], y))
	return true


# One wall block from [param a] to [param b]; [param inward] points toward the road.
func _block(st: SurfaceTool, a: Vector2, b: Vector2, inward: Vector2, thickness: float,
		base_a: float, base_b: float, height: float, col: Color) -> void:
	var a2: Vector2 = a - inward * thickness
	var b2: Vector2 = b - inward * thickness
	st.set_color(col)
	_vquad(st, a, b, base_a, base_b, height, inward)
	_vquad(st, a2, b2, base_a, base_b, height, -inward)
	_vquad(st, a, a2, base_a, base_a, height, (a - b).normalized())
	_vquad(st, b, b2, base_b, base_b, height, (b - a).normalized())
	st.set_normal(Vector3.UP)
	_tri(st, _v3(a, base_a + height), _v3(b, base_b + height), _v3(b2, base_b + height))
	_tri(st, _v3(a, base_a + height), _v3(b2, base_b + height), _v3(a2, base_a + height))


# A vertical wall face from [param a] (base y0a) to [param b] (base y0b), [param height] tall.
func _vquad(st: SurfaceTool, a: Vector2, b: Vector2, y0a: float, y0b: float, height: float, normal: Vector2) -> void:
	st.set_normal(_v3(normal, 0.0))
	_tri(st, _v3(a, y0a), _v3(b, y0b), _v3(b, y0b + height))
	_tri(st, _v3(a, y0a), _v3(b, y0b + height), _v3(a, y0a + height))


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


# A quad with a height per corner [param ys] (plus [param lift]); the normal follows the surface.
func _quadh(st: SurfaceTool, a: Vector2, b: Vector2, c: Vector2, d: Vector2, ys: PackedFloat32Array,
		lift: float, col: Color) -> void:
	var va := Vector3(a.x, ys[0] + lift, a.y)
	var vb := Vector3(b.x, ys[1] + lift, b.y)
	var vc := Vector3(c.x, ys[2] + lift, c.y)
	var vd := Vector3(d.x, ys[3] + lift, d.y)
	var n: Vector3 = (vb - va).cross(vc - va)
	if n.length_squared() < 0.000001:
		n = (vc - va).cross(vd - va)
	n = n.normalized() if n.length_squared() > 0.000001 else Vector3.UP
	if n.y < 0.0:
		n = -n
	st.set_color(col)
	st.set_normal(n)
	st.add_vertex(va)
	st.add_vertex(vb)
	st.add_vertex(vc)
	st.add_vertex(va)
	st.add_vertex(vc)
	st.add_vertex(vd)


# Road surface height under [param p] on whichever road is nearest (0 on a flat track).
func _road_y(track: TrackModel, p: Vector2) -> float:
	return track.query(p, -1).height


# Square support columns under raised main road, from the ground up to just below the surface.
func _pillars(st: SurfaceTool, track: TrackModel) -> void:
	var d: TrackData = track.data
	var path: TrackModel.Path = track.main
	var hw: float = d.pillar_half_width
	var count: int = int(path.length / maxf(d.pillar_spacing, 1.0))
	for k in count:
		var s: float = (float(k) + 0.5) * path.length / float(count)
		var stv: Vector2 = path.seg_t_at(s)
		var top: float = path.height_at(int(stv.x), stv.y) - hw * absf(tan(path.bank_at(int(stv.x), stv.y))) - 0.03
		if top - d.ground_y < d.pillar_min_height:
			continue
		# A column never stands in a road that passes under this one (story 008, crossovers): it
		# slides along this road until it is clear of the lower road's corridor.
		var c: Vector2 = path.point_at(s)
		var t: Vector2 = path.tangent_at(s)
		var placed: bool = not track.road_below(c, top, hw + PILLAR_CLEARANCE)
		var shift: float = PILLAR_SHIFT_STEP
		while not placed and shift <= d.pillar_spacing:
			for sgn in [1.0, -1.0]:
				var c2: Vector2 = path.point_at(s + shift * sgn)
				if not placed and not track.road_below(c2, top, hw + PILLAR_CLEARANCE):
					c = c2
					t = path.tangent_at(s + shift * sgn)
					var st2: Vector2 = path.seg_t_at(s + shift * sgn)
					top = path.height_at(int(st2.x), st2.y) - hw * absf(tan(path.bank_at(int(st2.x), st2.y))) - 0.03
					placed = true
			shift += PILLAR_SHIFT_STEP
		if not placed:
			continue
		var n: Vector2 = Vector2(-t.y, t.x)
		st.set_color(d.pillar_color)
		var dirs: Array[Vector2] = [t, n, -t, -n]
		for dir in dirs:
			var side: Vector2 = Vector2(-dir.y, dir.x)
			_vquad(st, c + dir * hw - side * hw, c + dir * hw + side * hw, d.ground_y, d.ground_y, top - d.ground_y, dir)
		st.set_normal(Vector3.UP)
		_tri(st, _v3(c + t * hw + n * hw, top), _v3(c + t * hw - n * hw, top), _v3(c - t * hw - n * hw, top))
		_tri(st, _v3(c + t * hw + n * hw, top), _v3(c - t * hw - n * hw, top), _v3(c - t * hw + n * hw, top))


# Jump ramps (story 008): a striped wedge rising from the road to the lip, with side faces and a
# vertical lip face, on the road surface (banked like it).
func _ramps(st: SurfaceTool, track: TrackModel) -> void:
	for i in track.ramp_paths.size():
		var rp: TrackRamp = _ramp_data(track, i)
		var path: TrackModel.Path = track.path_of(track.ramp_paths[i])
		var steps: int = maxi(rp.stripes if rp != null else 6, 1)
		var length: float = track.ramp_len[i]
		var lip: float = track.ramp_lip[i]
		var prev: Array = []
		for k in steps + 1:
			var u: float = length * float(k) / float(steps)
			var d: float = track.ramp_from[i] + u
			var c: Vector2 = path.point_at(d)
			var tg: Vector2 = path.tangent_at(d)
			var n: Vector2 = Vector2(-tg.y, tg.x)
			var stv: Vector2 = path.seg_t_at(d)
			var half: float = track.ramp_half[i]
			if half <= 0.0:
				half = path.half_at(int(stv.x), stv.y) + path.curb
			var lat: float = track.ramp_lat[i]
			var lp: Vector2 = c + n * (lat + half)
			var ln: Vector2 = c + n * (lat - half)
			var bp: float = path.surface_y(int(stv.x), stv.y, lat + half)
			var bn: float = path.surface_y(int(stv.x), stv.y, lat - half)
			var rise: float = lip * u / length + RAMP_LIFT
			var cur: Array = [lp, ln, bp, bn, rise]
			if not prev.is_empty():
				var col: Color = (rp.color_a if k % 2 == 1 else rp.color_b) if rp != null else Color(0.85, 0.62, 0.2)
				_quadh(st, prev[0], prev[1], ln, lp, PackedFloat32Array([prev[2] + prev[4], prev[3] + prev[4],
						bn + rise, bp + rise]), 0.0, col)
				var side: Color = rp.side_color if rp != null else Color(0.4, 0.26, 0.14)
				st.set_color(side)
				for e in [[prev[0], lp, prev[2], bp, n], [prev[1], ln, prev[3], bn, -n]]:
					st.set_normal(_v3(e[4], 0.0))
					_tri(st, _v3(e[0], e[2]), _v3(e[1], e[3]), _v3(e[1], e[3] + rise))
					_tri(st, _v3(e[0], e[2]), _v3(e[1], e[3] + rise), _v3(e[0], e[2] + prev[4]))
			if k == steps:
				st.set_color(rp.side_color if rp != null else Color(0.4, 0.26, 0.14))
				st.set_normal(_v3(tg, 0.0))
				_tri(st, _v3(lp, bp), _v3(ln, bn), _v3(ln, bn + rise))
				_tri(st, _v3(lp, bp), _v3(ln, bn + rise), _v3(lp, bp + rise))
			prev = cur


func _ramp_data(track: TrackModel, index: int) -> TrackRamp:
	var k: int = 0
	for rp in track.data.ramps:
		if rp == null or rp.length <= 0.0:
			continue
		if k == index:
			return rp
		k += 1
	return null


# Underside and edge faces of raised main road (story 008): a bridge or a raised deck reads as a
# solid slab data.deck_thickness thick from below and from the side, instead of a paper surface.
func _deck_underside(st: SurfaceTool, track: TrackModel) -> void:
	var d: TrackData = track.data
	var path: TrackModel.Path = track.main
	var pts: PackedVector2Array = path.points
	var n: int = pts.size()
	var normals: Array[Vector2] = _normals_of(pts, true)
	var th: float = d.deck_thickness
	if th <= 0.0:
		return
	for i in n:
		var j: int = (i + 1) % n
		if minf(path.y[i], path.y[j]) - d.ground_y < d.pillar_min_height:
			continue
		var wa: float = path.half[i] + path.curb
		var wb: float = path.half[j] + path.curb
		var ka: float = tan(path.bank[i])
		var kb: float = tan(path.bank[j])
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[j]
		var pa: Vector2 = a + normals[i] * wa
		var na: Vector2 = a - normals[i] * wa
		var pb: Vector2 = b + normals[j] * wb
		var nb: Vector2 = b - normals[j] * wb
		var ypa: float = path.y[i] + wa * ka
		var yna: float = path.y[i] - wa * ka
		var ypb: float = path.y[j] + wb * kb
		var ynb: float = path.y[j] - wb * kb
		st.set_color(d.deck_under_color)
		st.set_normal(Vector3.DOWN)
		_tri(st, _v3(pa, ypa - th), _v3(pb, ypb - th), _v3(nb, ynb - th))
		_tri(st, _v3(pa, ypa - th), _v3(nb, ynb - th), _v3(na, yna - th))
		_vquad(st, pa, pb, ypa - th, ypb - th, th, normals[i])
		_vquad(st, na, nb, yna - th, ynb - th, th, -normals[i])


func _v3(p: Vector2, y: float) -> Vector3:
	return Vector3(p.x, y, p.y)

