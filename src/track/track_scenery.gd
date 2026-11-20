class_name TrackScenery
extends Node3D
## Props around a track, chosen by TrackTheme.style. For "castle" (Castle Circuit, story 003
## round 2) each zone of design/references/track-design-reference.md section 8 gets its own
## props along both road edges plus a landmark:
##   Tourney Field: grandstands with a crowd, striped pavilion tents, jousting fence, pennants
##   Moat & Gatehouse: curtain wall with towers, gatehouse arch with portcullis teeth
##   Market Village: timber-frame facades both sides, striped stalls on the lane-split island,
##                   the well, barrels and crates, hanging signs
##   Keep Courtyard: the keep (tallest landmark), knight-dog statue on the hairpin fountain,
##                   training dummies, tapestry and torch-lit roofed passage
##   Rampart Gardens: orchard trees, hedges, a trebuchet, a distant windmill
## Every repeated primitive is drawn by one MultiMeshInstance3D (a handful of draw calls),
## so 12 racers stay smooth. Presentation only.
## Implements design/game-brief.md, "Look and references".

const BOX_CLEARANCE: float = 1.5

var _track: TrackModel
var _th: TrackTheme
## kind -> [Array[Transform3D], Array[Color]]
var _batches: Dictionary = {}


## Builds the props for [param track] as children of this node.
func build(track: TrackModel) -> void:
	_track = track
	_th = track.theme
	if _th.style == &"castle":
		_build_castle()
	_build_item_boxes()
	_flush()


# ---------------------------------------------------------------- batching

func _add(kind: String, xf: Transform3D, col: Color) -> void:
	if not _batches.has(kind):
		var xs: Array[Transform3D] = []
		var cs: Array[Color] = []
		_batches[kind] = [xs, cs]
	(_batches[kind][0] as Array[Transform3D]).append(xf)
	(_batches[kind][1] as Array[Color]).append(col)


# Axis-aligned-to-road box: center (x, y, z), size, facing direction t (x, z plane).
func _box(p: Vector2, y: float, size: Vector3, t: Vector2, col: Color, kind: String = "box") -> void:
	_add(kind, Transform3D(_basis_along(t, size), Vector3(p.x, y, p.y)), col)


func _cyl(p: Vector2, y: float, r: float, h: float, col: Color) -> void:
	_add("cyl", Transform3D(Basis.from_scale(Vector3(r, h, r)), Vector3(p.x, y, p.y)), col)


func _cone(p: Vector2, y: float, r: float, h: float, col: Color) -> void:
	_add("cone", Transform3D(Basis.from_scale(Vector3(r, h, r)), Vector3(p.x, y, p.y)), col)


func _sphere(p: Vector2, y: float, r: float, col: Color) -> void:
	_add("sphere", Transform3D(Basis.from_scale(Vector3(r, r, r)), Vector3(p.x, y, p.y)), col)


func _flush() -> void:
	var meshes: Dictionary = {
		"box": _unit_box(), "glow": _unit_box(), "cyl": _unit_cylinder(1.0, 10),
		"cone": _unit_cylinder(0.0, 10), "pyr": _unit_pyramid(), "sphere": _unit_sphere(),
		"capsule": _unit_capsule(),
	}
	for kind in _batches.keys():
		var pair: Array = _batches[kind]
		_batch(meshes[kind], pair[0], pair[1], kind == "glow")
	_batches.clear()


# ---------------------------------------------------------------- placement helpers

# Excess over the nearest corridor wall at [param p] (> 0 = outside every road), using a
# windowed main-road search around [param s].
func _clearance(p: Vector2, s: float) -> float:
	var best: float = _track.main.nearest(p, _track.main.segment_at(s), 60).excess
	for bp in _track.branches:
		if bp.bounds.has_point(p):
			best = minf(best, bp.nearest(p, -1, 0).excess)
	return best


func _free(p: Vector2, s: float, clearance: float) -> bool:
	return _clearance(p, s) >= clearance and not _track.in_hazard_area(p)


# Main-loop distances from [param r].x to [param r].y (wrapping) every [param step] meters.
func _range_steps(r: Vector2, step: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var a: float = r.x
	var b: float = r.y if r.y > r.x else r.y + _track.length
	var s: float = a + step * 0.5
	while s < b:
		out.append(fposmod(s, _track.length))
		s += step
	return out


# Point [param out] meters outside the main wall at [param s] on [param side].
func _edge(s: float, side: int, out: float) -> Vector2:
	return _track.point_at(s) + _track.normal_at(s) * float(side) * (_track.wall_offset_at(s, side) + out)


# ---------------------------------------------------------------- castle

func _build_castle() -> void:
	_banners()
	_start_arch()
	_tourney()
	_moat_and_gate()
	_village()
	_keep()
	_gardens()
	_passage()


# Banner poles every banner_spacing meters along both edges, everywhere.
func _banners() -> void:
	var th: TrackTheme = _th
	var k: int = 0
	for s in _range_steps(Vector2(0.0, _track.length), th.banner_spacing):
		var t: Vector2 = _track.tangent_at(s)
		for side in [1, -1]:
			var p: Vector2 = _edge(s, side, th.banner_distance_from_wall)
			if not _free(p, s, BOX_CLEARANCE * 0.5):
				continue
			_box(p, th.banner_height * 0.5, Vector3(0.3, th.banner_height, 0.3), t, th.banner_pole_color)
			_box(p - t * 0.9, th.banner_height - 1.7, Vector3(0.08, 3.0, 1.8), t,
					th.banner_color_a if k % 2 == 0 else th.banner_color_b)
		k += 1


func _start_arch() -> void:
	var th: TrackTheme = _th
	var p0: Vector2 = _track.point_at(0.0)
	var t0: Vector2 = _track.tangent_at(0.0)
	var n0: Vector2 = _track.normal_at(0.0)
	var reach: float = _track.wall_offset_at(0.0, 1) + 0.8
	for side in [1.0, -1.0]:
		_box(p0 + n0 * side * reach, 4.5, Vector3(1.2, 9.0, 1.2), t0, th.start_arch_color)
	_box(p0, 9.0, Vector3(reach * 2.0 + 1.2, 1.6, 1.0), t0, th.banner_color_b)
	_box(p0 - t0 * 0.6, 7.0, Vector3(reach * 1.4, 2.6, 0.1), t0, th.banner_color_a)


# Tourney Field: grandstands with a crowd on the outside of the start straight, tents and a
# jousting fence in the lists (inside the first sweeper), pennant strings on the edges.
func _tourney() -> void:
	var th: TrackTheme = _th
	var r: Vector2 = th.zone_tourney
	var ci: int = 0
	# Grandstands: both sides of the grid straight (the run-up and the first meters).
	for s in _range_steps(Vector2(_track.length - 70.0, 30.0), 6.0):
		var t: Vector2 = _track.tangent_at(s)
		for side in [1, -1]:
			var base: Vector2 = _edge(s, side, 2.5)
			if not _free(base, s, 1.0):
				continue
			var out: Vector2 = _track.normal_at(s) * float(side)
			for step in 4:
				var p: Vector2 = base + out * (1.2 + step * 1.6)
				var h: float = 0.8 + step * 0.9
				_box(p, h * 0.5, Vector3(1.6, h, 6.0), t, th.stone_light if step % 2 == 0 else th.stone_dark)
				for c in 3:
					var cp: Vector2 = p + t * (-2.0 + c * 2.0) + out * 0.1
					var col: Color = th.crowd_colors[ci % th.crowd_colors.size()]
					ci += 1
					_add("capsule", Transform3D(Basis.from_scale(Vector3(0.45, 0.6, 0.45)), Vector3(cp.x, h + 0.6, cp.y)), col)
			# Roof canopy over the top rows.
			_box(base + out * 5.0, 6.2, Vector3(6.5, 0.2, 6.0), t, th.tent_color_a if int(s / 6.0) % 2 == 0 else th.tent_color_b)
	# Tents and jousting fence around the lists center.
	var lc: Vector2 = th.lists_center
	if lc != Vector2.ZERO:
		for k in 6:
			var ang: float = TAU * float(k) / 6.0
			var p: Vector2 = lc + Vector2(cos(ang), sin(ang)) * 16.0
			if not _free(p, r.x, 4.0):
				continue
			_cyl(p, 1.5, 2.6, 3.0, th.tent_color_b if k % 2 == 0 else th.tent_color_a)
			_cone(p, 4.6, 3.2, 3.2, th.tent_color_a if k % 2 == 0 else th.tent_color_b)
			_box(p, 7.0, Vector3(0.1, 1.2, 0.8), Vector2(1, 0), th.banner_color_b)
		for k in 14:
			var p: Vector2 = lc + Vector2(-13.0 + k * 2.0, 0.0)
			if _free(p, r.x, 1.0):
				_box(p, 0.6, Vector3(2.0, 0.15, 0.15), Vector2(1, 0), th.wood_color)
				_box(p, 1.1, Vector3(2.0, 0.15, 0.15), Vector2(1, 0), th.wood_color)
				_box(p + Vector2(-1.0, 0.0), 0.7, Vector3(0.2, 1.4, 0.2), Vector2(1, 0), th.dark_wood_color)
	# Pennant strings: small alternating flags between banner poles along the zone.
	for s in _range_steps(r, 3.0):
		var t: Vector2 = _track.tangent_at(s)
		for side in [1, -1]:
			var p: Vector2 = _edge(s, side, th.banner_distance_from_wall)
			if not _free(p, s, 0.5):
				continue
			_add("pyr", Transform3D(_basis_along(t, Vector3(0.9, -1.0, 0.15)), Vector3(p.x, 5.0, p.y)),
					th.banner_color_b if int(s / 3.0) % 2 == 0 else th.banner_color_a)


# Moat & Gatehouse: curtain wall with merlons and towers through the gate, gatehouse arch with
# portcullis teeth over the arch road; reeds of stone on the moat edges.
func _moat_and_gate() -> void:
	var th: TrackTheme = _th
	var g: Vector2 = th.gate_position
	if g == Vector2.ZERO:
		return
	var gs: float = _track.query(g, -1).s
	var t: Vector2 = _track.tangent_at(gs)
	var n: Vector2 = _track.normal_at(gs)
	var hw: float = _track.wall_offset_at(gs, 1)
	# Gatehouse: two towers, a top block, portcullis teeth.
	for side in [1.0, -1.0]:
		var tp: Vector2 = g + n * side * (hw + 3.0)
		_cyl(tp, 6.0, 3.2, 12.0, th.tower_color)
		_cone(tp, 15.0, 4.0, 6.0, th.roof_color)
	_box(g, 9.5, Vector3(2.0 * hw + 6.0, 5.0, 5.0), t, th.stone_light)
	for k in 7:
		var tooth: Vector2 = g + n * (-hw + 0.5 + k * (2.0 * hw - 1.0) / 6.0)
		_box(tooth, 6.4, Vector3(0.25, 1.4, 0.25), t, th.dark_wood_color)
	# Curtain wall both ways from the gate, with towers every 32 m, skipping roads and water.
	for side in [1.0, -1.0]:
		var d: float = hw + 6.0
		while d < 80.0:
			var p: Vector2 = g + n * side * d
			if _free(p, gs, 1.5):
				_box(p, 2.5, Vector3(4.0, 5.0, 2.2), t, th.stone_light)
				if int(d / 4.0) % 2 == 0:
					_box(p, 5.6, Vector3(1.6, 1.2, 2.2), t, th.stone_dark)
				if int(d) % 32 < 4:
					_cyl(p, 6.5, 3.6, 13.0, th.tower_color)
					_cone(p, 16.0, 4.6, 6.0, th.roof_color)
			d += 4.0
	# Low stone posts along the open moat edge (the curb is the only barrier: a warning line).
	for e in _track.data.open_edges:
		for s in _range_steps(Vector2(e.x, e.y), 7.0):
			var p: Vector2 = _track.point_at(s) + _track.normal_at(s) * e.z * (_track.half_width_at(s) + _track.data.curb_width + 0.4)
			_box(p, 0.3, Vector3(0.6, 0.6, 0.6), _track.tangent_at(s), th.stone_dark)


# Market Village: house facades on both sides, stalls on the island of the lane split, the
# well, barrels, crates and hanging signs.
func _village() -> void:
	var th: TrackTheme = _th
	var r: Vector2 = th.zone_village
	var k: int = 0
	for s in _range_steps(r, 8.0):
		var t: Vector2 = _track.tangent_at(s)
		for side in [1, -1]:
			var out: Vector2 = _track.normal_at(s) * float(side)
			var p: Vector2 = _edge(s, side, 4.2)
			if not _free(p, s, 3.0):
				continue
			var h: float = 5.0 + float((k * 7) % 3) * 1.2
			_box(p, h * 0.5, Vector3(6.0, h, 7.6), out, th.house_wall_color)
			_add("pyr", Transform3D(Basis(Vector3.UP, atan2(out.x, out.y) + PI * 0.25).scaled(Vector3(6.4, 3.0, 8.6)),
					Vector3(p.x, h + 1.5, p.y)), th.house_roof_color)
			# Dark timber beams on the street face.
			var face: Vector2 = p - out * 3.82
			for b in 3:
				_box(face + t * (-3.2 + b * 3.2), h * 0.5, Vector3(0.3, h, 0.12), t, th.dark_wood_color)
			_box(face, h * 0.55, Vector3(0.3, 0.3, 6.0), t, th.dark_wood_color)
			# Hanging sign every third house, barrels and crates every other.
			if k % 3 == 0:
				_box(face - out * 0.9, 3.4, Vector3(0.1, 0.8, 1.2), t, th.banner_color_a)
			if k % 2 == 0:
				var bp: Vector2 = _edge(s, side, 0.9) + t * 2.0
				if _free(bp, s, 0.4):
					_cyl(bp, 0.5, 0.45, 1.0, th.wood_color)
					_cyl(bp + t * 1.0, 0.5, 0.45, 1.0, th.wood_color)
					_box(bp - t * 1.1, 0.45, Vector3(0.9, 0.9, 0.9), t, th.dark_wood_color.lightened(0.2))
			k += 1
	# Stalls on the island between the lanes.
	for bi in _track.branch_count():
		if _track.data.branches[bi].type != &"lane_split":
			continue
		var b: TrackModel.Path = _track.branches[bi]
		var a0: float = b.s_in + 26.0
		var j: int = 0
		while a0 < b.s_out - 26.0:
			var mp: Vector2 = (_track.point_at(a0) + _track.branch_point_at(bi, _track.branch_distance_for_s(bi, a0))) * 0.5
			var t: Vector2 = _track.tangent_at(a0)
			if _free(mp, a0, 0.3):
				_box(mp, 0.55, Vector3(2.0, 1.1, 5.0), t, th.wood_color)
				for st in 4:
					_box(mp + t * (-1.9 + st * 1.26), 2.6, Vector3(2.6, 0.12, 1.26), t, th.tent_color_a if (st + j) % 2 == 0 else th.tent_color_b)
				_box(mp, 1.3, Vector3(1.4, 0.4, 3.0), t, th.fruit_color)
			a0 += 9.0
			j += 1
	# The well: on the free side of the S-bend.
	var w: Vector2 = th.well_position
	if w != Vector2.ZERO:
		var ws: float = _track.query(w, -1).s
		for side in [1, -1]:
			var p: Vector2 = _edge(ws, side, 3.0)
			if _free(p, ws, 2.0):
				_cyl(p, 0.5, 1.6, 1.0, th.stone_light)
				_box(p, 1.8, Vector3(0.2, 2.6, 0.2), Vector2(1, 0), th.dark_wood_color)
				_cone(p, 3.4, 2.0, 1.2, th.roof_color)
				break


# Keep Courtyard: the keep, the knight-dog statue on the hairpin fountain, training dummies.
func _keep() -> void:
	var th: TrackTheme = _th
	var kc: Vector2 = th.keep_center
	var ks: Vector3 = th.keep_size * Vector3(1.4, 1.5, 1.4)
	if kc != Vector2.ZERO:
		_box(kc, ks.y * 0.5, ks, Vector2(1, 0), th.tower_color)
		_box(kc, ks.y + 2.0, Vector3(ks.x * 0.72, 4.0, ks.z * 0.72), Vector2(1, 0), th.tower_color.lightened(0.15))
		for sx in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				var tp: Vector2 = kc + Vector2(sx * ks.x * 0.5, sz * ks.z * 0.5)
				_cyl(tp, ks.y * 0.6, 4.0, ks.y * 1.2, th.tower_color)
				_cone(tp, ks.y * 1.2 + 3.5, 5.0, 7.0, th.roof_color)
		_cyl(kc, ks.y + 8.0, 3.0, 8.0, th.tower_color)
		_cone(kc, ks.y + 15.0, 4.0, 7.0, th.roof_color)
		_box(kc, ks.y + 21.0, Vector3(0.1, 3.0, 4.0), Vector2(1, 0), th.banner_color_b)
	var sp: Vector2 = th.statue_position
	if sp != Vector2.ZERO:
		_cyl(sp, 0.35, 3.6, 0.7, th.stone_dark)
		_cyl(sp, 0.72, 3.1, 0.06, th.water_color)
		_box(sp, 1.6, Vector3(1.8, 2.4, 1.8), Vector2(1, 0), th.stone_light)
		# Knight dog: body, chest plate, head, ears, raised sword.
		_add("capsule", Transform3D(Basis.from_scale(Vector3(0.9, 1.4, 0.9)), Vector3(sp.x, 3.9, sp.y)), th.statue_color)
		_box(sp + Vector2(0.0, -0.5), 4.0, Vector3(1.3, 1.2, 0.4), Vector2(1, 0), th.statue_color.darkened(0.15))
		_sphere(sp, 5.6, 0.75, th.statue_color)
		_box(sp + Vector2(0.0, -0.8), 5.4, Vector3(0.5, 0.4, 0.7), Vector2(1, 0), th.statue_color)
		for ex in [-0.6, 0.6]:
			_box(sp + Vector2(ex, 0.0), 5.9, Vector3(0.25, 0.9, 0.35), Vector2(1, 0), th.statue_color.darkened(0.1))
		_box(sp + Vector2(1.0, 0.0), 6.2, Vector3(0.15, 3.0, 0.15), Vector2(1, 0), th.stone_light.lightened(0.2))
	# Training dummies and braziers along the plaza edges.
	var r: Vector2 = th.zone_keep
	var k: int = 0
	for s in _range_steps(r, 11.0):
		for side in [1, -1]:
			var p: Vector2 = _edge(s, side, 2.0)
			if not _free(p, s, 1.0):
				continue
			if k % 2 == 0:
				_box(p, 1.0, Vector3(0.25, 2.0, 0.25), Vector2(1, 0), th.dark_wood_color)
				_box(p, 1.6, Vector3(1.6, 0.2, 0.2), _track.tangent_at(s), th.wood_color)
				_sphere(p, 2.3, 0.35, th.house_wall_color)
			else:
				_box(p, 0.6, Vector3(0.6, 1.2, 0.6), Vector2(1, 0), th.stone_dark)
				_box(p, 1.35, Vector3(0.5, 0.3, 0.5), Vector2(1, 0), th.torch_color, "glow")
			k += 1


# Rampart Gardens: orchard trees and hedges on both edges, the trebuchet, the distant windmill.
func _gardens() -> void:
	var th: TrackTheme = _th
	var r: Vector2 = th.zone_gardens
	var k: int = 0
	for s in _range_steps(r, 7.0):
		var t: Vector2 = _track.tangent_at(s)
		for side in [1, -1]:
			var hp: Vector2 = _edge(s, side, 1.2)
			if _free(hp, s, 0.5):
				_box(hp, 0.6, Vector3(1.0, 1.2, 7.0), _track.normal_at(s), th.hedge_color)
			var p: Vector2 = _edge(s, side, 5.0 + float(k % 3) * 2.5)
			if _free(p, s, 3.0):
				_cyl(p, 1.1, 0.35, 2.2, th.dark_wood_color)
				_sphere(p, 3.2, 2.1, th.foliage_color if k % 2 == 0 else th.foliage_alt_color)
				_sphere(p + t * 0.9, 3.9, 0.3, th.fruit_color)
			k += 1
	# Trebuchet on the lawn inside the long sweeper.
	var oc: Vector2 = th.orchard_center
	if oc != Vector2.ZERO:
		_box(oc, 0.4, Vector3(6.0, 0.8, 4.0), Vector2(1, 0), th.wood_color)
		for sx in [-1.5, 1.5]:
			_box(oc + Vector2(0.0, sx), 3.0, Vector3(0.5, 6.0, 0.5), Vector2(1, 0), th.dark_wood_color)
		_add("box", Transform3D(Basis(Vector3(0, 0, 1), 0.6).scaled(Vector3(12.0, 0.4, 0.4)), Vector3(oc.x, 6.5, oc.y)), th.wood_color)
		_box(oc + Vector2(-3.5, 0.0), 3.4, Vector3(1.6, 1.6, 1.6), Vector2(1, 0), th.stone_dark)
	var wm: Vector2 = th.windmill_position
	if wm != Vector2.ZERO:
		_cyl(wm, 7.0, 4.0, 14.0, th.house_wall_color)
		_cone(wm, 16.5, 4.8, 5.0, th.roof_color)
		for b in 4:
			var ang: float = PI * 0.25 + b * PI * 0.5
			_add("box", Transform3D(Basis(Vector3(0, 0, 1), ang).scaled(Vector3(11.0, 1.4, 0.2)),
					Vector3(wm.x + cos(ang) * 5.5, 13.0 + sin(ang) * 5.5, wm.y + 4.3)), th.house_wall_color.darkened(0.1))


# The secret passage: tapestry at the entrance, a dark roof where it runs inside the keep wing,
# torches along both walls, arches at both ends.
func _passage() -> void:
	var th: TrackTheme = _th
	for bi in _track.branch_count():
		var b: TrackBranch = _track.data.branches[bi]
		var path: TrackModel.Path = _track.branches[bi]
		if b.arch_ends:
			for end in [0, 1]:
				var d: float = _arch_distance(path, end == 1)
				var ap: Vector2 = path.point_at(d)
				var at: Vector2 = path.tangent_at(d)
				var an: Vector2 = Vector2(-at.y, at.x)
				var gap: float = path.wall_offset + 0.9
				for side in [1.0, -1.0]:
					_box(ap + an * side * gap, (b.wall_height + 1.6) * 0.5, Vector3(1.8, b.wall_height + 1.6, 1.8), at, th.arch_color)
				_box(ap, b.wall_height + 1.9, Vector3(gap * 2.0 + 1.8, 1.4, 1.8), at, th.arch_color.darkened(0.1))
				if end == 0:
					# The hanging tapestry over the entrance.
					_box(ap - at * 0.3, b.wall_height * 0.6 + 0.9, Vector3(gap * 2.0 - 0.6, b.wall_height * 0.8, 0.08), at, th.tapestry_color)
		if not b.roofed:
			continue
		var d2: float = 0.0
		var k: int = 0
		while d2 < path.length:
			var p: Vector2 = path.point_at(d2)
			var t: Vector2 = path.tangent_at(d2)
			var inside: bool = _track.main.nearest(p, -1, 0).excess > 0.5
			if inside:
				_box(p, b.wall_height + 0.2, Vector3(path.wall_offset * 2.0 + 1.0, 0.4, 2.1), t, th.stone_dark.darkened(0.3))
				if k % 4 == 0:
					var nn: Vector2 = Vector2(-t.y, t.x)
					for side in [1.0, -1.0]:
						_box(p + nn * side * (path.wall_offset - 0.1), b.wall_height * 0.7, Vector3(0.25, 0.25, 0.25), t, th.torch_color, "glow")
			d2 += 2.0
			k += 1


# Distance along a branch where it has left the main corridor (start or end side).
func _arch_distance(path: TrackModel.Path, from_end: bool) -> float:
	var d: float = path.length if from_end else 0.0
	var dir: float = -1.0 if from_end else 1.0
	while d > 0.0 and d < path.length:
		if _track.main.nearest(path.point_at(d), -1, 0).excess > 1.0:
			break
		d += dir
	return clampf(d, 0.0, path.length)


func _build_item_boxes() -> void:
	for i in _track.data.item_box_spots.size():
		var p: Vector2 = _track.item_box_position(i)
		var sz: float = _th.item_box_size
		_add("box", Transform3D(Basis(Vector3.UP, PI * 0.25).scaled(Vector3(sz, sz, sz)), Vector3(p.x, sz * 0.9, p.y)), _th.item_box_color)


# Basis whose local z axis follows [param t] (x, z plane), scaled by [param scale].
func _basis_along(t: Vector2, scale: Vector3) -> Basis:
	var zaxis := Vector3(t.x, 0.0, t.y)
	var xaxis := Vector3(-t.y, 0.0, t.x)
	return Basis(xaxis * scale.x, Vector3.UP * scale.y, zaxis * scale.z)


func _unit_box() -> Mesh:
	var m := BoxMesh.new()
	m.size = Vector3.ONE
	return m


func _unit_cylinder(top_radius: float, segments: int) -> Mesh:
	var m := CylinderMesh.new()
	m.top_radius = top_radius
	m.bottom_radius = 1.0
	m.height = 1.0
	m.radial_segments = segments
	m.rings = 1
	return m


func _unit_pyramid() -> Mesh:
	var m := CylinderMesh.new()
	m.top_radius = 0.0
	m.bottom_radius = 0.7071
	m.height = 1.0
	m.radial_segments = 4
	m.rings = 1
	return m


func _unit_sphere() -> Mesh:
	var m := SphereMesh.new()
	m.radius = 1.0
	m.height = 2.0
	m.radial_segments = 10
	m.rings = 6
	return m


func _unit_capsule() -> Mesh:
	var m := CapsuleMesh.new()
	m.radius = 0.5
	m.height = 2.0
	m.radial_segments = 8
	m.rings = 2
	return m


# One MultiMeshInstance3D drawing [param mesh] at every transform, tinted per instance.
# [param glow] makes it emissive (torches, braziers) instead of lighting it.
func _batch(mesh: Mesh, xforms: Array[Transform3D], colors: Array[Color], glow: bool) -> void:
	if xforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		mm.set_instance_color(i, colors[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	# Vertex colors are authored in sRGB (like every Color in the theme data).
	mat.vertex_color_is_srgb = true
	if glow:
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mmi.material_override = mat
	add_child(mmi)
