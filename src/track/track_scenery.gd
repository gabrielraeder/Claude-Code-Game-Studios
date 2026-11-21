class_name TrackScenery
extends Node3D
## Props around a track, chosen by TrackTheme.style. For "castle" (Castle Circuit, story 003
## round 2) each zone of design/references/track-design-reference.md section 8 gets its own
## props along both road edges plus a landmark:
##   Tourney Field: grandstands with a crowd, striped pavilion tents, jousting fence, pennants
##   Moat & Gatehouse: curtain wall with towers, gatehouse arch with portcullis teeth; where a
##                     road crosses over the gate arch (story 008 part 5, the Barbican Spiral) the
##                     deck is the gatehouse top: piers under it, a bone balustrade on its parapet,
##                     and the round barbican tower with a paw crest at the spiral's centre
##   Market Village: timber-frame facades both sides, striped stalls on the lane-split island,
##                   the well, barrels and crates, hanging signs
##   Keep Courtyard: the keep (tallest landmark), knight-dog statue on the hairpin fountain,
##                   training dummies, tapestry and torch-lit roofed passage
##   Rampart Gardens: orchard trees, hedges, a trebuchet, a distant windmill
## Every repeated primitive is drawn by one MultiMeshInstance3D (a handful of draw calls),
## so 12 racers stay smooth. Presentation only.
## Implements design/game-brief.md, "Look and references".
## Road guard (bugfix 2026-11-20): karts collide only with road walls, so no prop may reach over
## the drivable area (inside the walls of the main road and every branch) at kart height. Every
## piece goes through [method _add]; a prop's pieces are checked together (a prop group) with their
## whole footprint plus TrackTheme.scenery_road_margin. A prop that reaches over is moved away
## from the road (up to scenery_max_nudge), otherwise left out. Flat pieces (rail sleepers) and
## pieces above the karts (beams, awnings) are allowed over the road.

const BOX_CLEARANCE: float = 1.5
## Road guard: cell size (m) of the road segment index, and how far (m) past a wall it looks.
const GUARD_CELL: float = 8.0
const GUARD_REACH: float = 4.0
## Road guard: spacing (m) of the footprint boundary samples.
const GUARD_STEP: float = 0.5
## Road guard: bounding radius of every unit mesh (box half diagonal 0.87, cylinder 1.12).
const GUARD_UNIT_RADIUS: float = 1.2
## Farthest (m) a dungeon torch slot moves back along the road to get clear of an open edge.
const TORCH_SLOT_SHIFT: float = 12.0
## ... clear of the open edge's reach times this (the edge's corridor widens over a few meters).
const TORCH_EDGE_REACH_MULT: float = 1.5
## Gatehouse deck (story 008 part 5): how far (m) along the gate road and the deck the open span is
## searched for, the sample step (m), and the bone size (m: shaft radius, shaft height, knob radius).
const GATE_SEARCH: float = 30.0
const GATE_STEP: float = 0.25
const BONE_SHAFT: Vector2 = Vector2(0.13, 0.8)
const BONE_KNOB: float = 0.12
## Village houses and barrels keep this far (m) beyond the barbican's radius (the rampart ring of the
## spiral stays clear) and this far (m) from the gatehouse centre (the entry towers).
const BARBICAN_CLEAR: float = 25.0
const GATE_CLEAR: float = 22.0


## Segments of every road bucketed in a grid, for fast "how far outside the walls" queries.
class RoadGrid extends RefCounted:
	var cell: float = 8.0
	var reach: float = 4.0
	var paths: Array[TrackModel.Path] = []
	var cells: Dictionary = {}
	## Story 008 part 3: the track (for TrackModel.blocks_level) and the kart band heights.
	var track: TrackModel
	var clear: float = 2.5
	var flat: float = 0.3

	## Indexes the main road and every branch of [param track].
	func build(track_model: TrackModel, cell_m: float, reach_m: float) -> void:
		var track_ref: TrackModel = track_model
		track = track_ref
		cell = cell_m
		reach = reach_m
		paths = [track.main]
		paths.append_array(track.branches)
		for slot in paths.size():
			var path: TrackModel.Path = paths[slot]
			var n: int = path.points.size()
			var widest: float = 0.0
			for i in n:
				widest = maxf(widest, maxf(path.wall_pos[i], path.wall_neg[i]))
			var grow: float = widest + reach
			for i in path.segment_count():
				var a: Vector2 = path.points[i]
				var b: Vector2 = path.points[(i + 1) % n]
				for cx in range(floori((minf(a.x, b.x) - grow) / cell), floori((maxf(a.x, b.x) + grow) / cell) + 1):
					for cy in range(floori((minf(a.y, b.y) - grow) / cell), floori((maxf(a.y, b.y) + grow) / cell) + 1):
						var key := Vector2i(cx, cy)
						if not cells.has(key):
							cells[key] = []
						(cells[key] as Array).append(Vector2i(slot, i))

	## Smallest excess over a road wall at [param p] (like TrackModel.excess_at; < 0 = inside a
	## corridor), capped at reach. [param away][0] receives the unit direction from the nearest
	## road centreline to [param p]. Story 008 part 3: only road segments that a piece spanning
	## [param y_lo]..[param y_hi] is in the way of count (TrackModel.blocks_level; the default
	## range counts every road, as before).
	func excess(p: Vector2, away: Array, y_lo: float = -INF, y_hi: float = INF) -> float:
		var leveled: bool = y_lo > -INF or y_hi < INF
		var key := Vector2i(floori(p.x / cell), floori(p.y / cell))
		if not cells.has(key):
			return reach
		var best_d := PackedFloat32Array()
		best_d.resize(paths.size())
		best_d.fill(INF)
		var best_seg := PackedInt32Array()
		best_seg.resize(paths.size())
		var best_t := PackedFloat32Array()
		best_t.resize(paths.size())
		for code: Vector2i in cells[key]:
			var path: TrackModel.Path = paths[code.x]
			var a: Vector2 = path.points[code.y]
			var ab: Vector2 = path.points[(code.y + 1) % path.points.size()] - a
			var l2: float = ab.length_squared()
			var t: float = clampf((p - a).dot(ab) / l2, 0.0, 1.0) if l2 > 0.0 else 0.0
			var d: float = p.distance_squared_to(a + ab * t)
			# Story 008 part 4: the surface height at p's side of the road (a banked road's low edge
			# is far below its centreline), not the centreline height.
			if d < best_d[code.x] and leveled:
				var lat: float = (p - a).dot(Vector2(-ab.y, ab.x).normalized()) if l2 > 0.0 else 0.0
				if not track.blocks_level(path.surface_y(code.y, t, lat), y_lo, y_hi, clear, flat):
					continue
			if d < best_d[code.x]:
				best_d[code.x] = d
				best_seg[code.x] = code.y
				best_t[code.x] = t
		var out: float = reach
		for slot in paths.size():
			if best_d[slot] == INF:
				continue
			var path: TrackModel.Path = paths[slot]
			var a: Vector2 = path.points[best_seg[slot]]
			var ab: Vector2 = path.points[(best_seg[slot] + 1) % path.points.size()] - a
			var foot: Vector2 = a + ab * best_t[slot]
			var side: int = 1 if (p - foot).dot(Vector2(-ab.y, ab.x)) >= 0.0 else -1
			var e: float = sqrt(best_d[slot]) - path.wall_at(best_seg[slot], best_t[slot], side)
			if e < out:
				out = e
				var dir: Vector2 = p - foot
				away[0] = dir.normalized() if dir.length_squared() > 0.0001 else Vector2(-ab.y, ab.x).normalized() * float(side)
		return out

	## Story 008 part 3: (excess over the nearest road's wall, that road's surface height at its
	## nearest point) for [param p], any level. x = reach when no road is near.
	func nearest_surface(p: Vector2) -> Vector3:
		var key := Vector2i(floori(p.x / cell), floori(p.y / cell))
		if not cells.has(key):
			return Vector3(reach, 0.0, reach)
		var out := Vector3(reach, 0.0, reach)
		for code: Vector2i in cells[key]:
			var path: TrackModel.Path = paths[code.x]
			var a: Vector2 = path.points[code.y]
			var ab: Vector2 = path.points[(code.y + 1) % path.points.size()] - a
			var l2: float = ab.length_squared()
			var t: float = clampf((p - a).dot(ab) / l2, 0.0, 1.0) if l2 > 0.0 else 0.0
			var off: Vector2 = p - (a + ab * t)
			var side: int = 1 if off.dot(Vector2(-ab.y, ab.x)) >= 0.0 else -1
			var e: float = off.length() - path.wall_at(code.y, t, side)
			if e < out.x:
				var lat: float = off.dot(Vector2(-ab.y, ab.x).normalized()) if l2 > 0.0 else 0.0
				out = Vector3(e, path.surface_y(code.y, t, lat), off.length() - path.half_at(code.y, t) - path.curb)
		return out

var _track: TrackModel
var _th: TrackTheme
## kind -> [Array[Transform3D], Array[Color], Array[String] of prop tags]
var _batches: Dictionary = {}
## Debug audit (tools/scenery_road_audit.gd): when true, each batch keeps its transforms and
## prop tags as metadata (prop_xforms, prop_tags), because a headless build cannot read
## MultiMesh transforms back. Set before [method build].
var audit_mode: bool = false
# Prop tag recorded with every instance added (which builder placed it; debug audit).
var _tag: String = ""
var _grid: RoadGrid
# kind -> PackedVector3Array of the unit mesh's triangle vertices (road guard footprints).
var _faces: Dictionary = {}
var _meshes: Dictionary = {}
var _group_open: bool = false
var _group: Array = []
# Road guard counts per prop tag: props checked, moved away from the road, left out.
var _guard_props: Dictionary = {}
# Highest road surface of the track (story 008 part 3); 0 on a flat track, where the guard works
# exactly as before.
var _top_road: float = 0.0
var _guard_moved: Dictionary = {}
var _guard_dropped: Dictionary = {}
var _guard_shrunk: Dictionary = {}
# Story 008 part 5: while true, props keep the absolute heights they were built with (the gatehouse
# under and on a deck, where the nearest road in plan is the other level).
var _no_lift: bool = false


## Builds the props for [param track] as children of this node.
func build(track: TrackModel) -> void:
	_track = track
	_th = track.theme
	_meshes = {
		"box": _unit_box(), "glow": _unit_box(), "cyl": _unit_cylinder(1.0, 10),
		"cone": _unit_cylinder(0.0, 10), "pyr": _unit_pyramid(), "sphere": _unit_sphere(),
		"capsule": _unit_capsule(), "glowsphere": _unit_sphere(), "glowcyl": _unit_cylinder(1.0, 10),
		"glowcone": _unit_cylinder(0.0, 10), "glowpyr": _unit_pyramid(),
	}
	for kind in _meshes.keys():
		_faces[kind] = (_meshes[kind] as Mesh).get_faces()
	_grid = RoadGrid.new()
	_grid.build(track, GUARD_CELL, GUARD_REACH)
	_grid.clear = _th.scenery_clear_height
	_grid.flat = _th.scenery_flat_height
	_top_road = track.max_surface_height()
	if _th.style == &"castle":
		_build_castle()
	elif _th.style == &"dungeon":
		_build_dungeon()
	_build_item_boxes()
	_flush()


# ---------------------------------------------------------------- batching

## Road guard summary for the debug audit: per prop tag, props checked / moved / shrunk / left out.
func road_report() -> String:
	var parts: PackedStringArray = PackedStringArray()
	for tag in _guard_props.keys():
		var moved: int = int(_guard_moved.get(tag, 0))
		var dropped: int = int(_guard_dropped.get(tag, 0))
		var shrunk: int = int(_guard_shrunk.get(tag, 0))
		if moved > 0 or dropped > 0 or shrunk > 0:
			parts.append("%s: %d props, %d moved, %d shrunk, %d left out" % [tag, int(_guard_props[tag]), moved, shrunk, dropped])
	return "nothing moved, shrunk or left out" if parts.is_empty() else "; ".join(parts)


# Adds one piece. Inside _begin_prop/_end_prop it waits for the rest of its prop; on its own it
# is a one-piece prop. Either way the road guard checks it before it is drawn.
func _add(kind: String, xf: Transform3D, col: Color) -> void:
	if _group_open:
		_group.append([kind, xf, col])
	else:
		_place([[kind, xf, col]])


# Starts a prop whose pieces the road guard keeps together (moved or left out as one).
func _begin_prop() -> void:
	_group_open = true
	_group = []


func _end_prop() -> void:
	_group_open = false
	_place(_group)
	_group = []


# Road guard: draws [param pieces] ([kind, Transform3D, Color]) when no piece reaches within the
# margin of a road at kart height; otherwise moves them all straight away from the road (up to
# scenery_max_nudge, in a few steps for curves) or leaves the prop out.
func _place(pieces: Array) -> void:
	if pieces.is_empty():
		return
	_guard_props[_tag] = int(_guard_props.get(_tag, 0)) + 1
	var lift: Vector2 = Vector2.ZERO if _no_lift else _road_lift(pieces)
	var shift := Vector3(0.0, lift.x, 0.0)
	# Story 008 part 4: raised beside (not on) its road's deck, the prop gets a plinth to the ground.
	if lift.x > _th.scenery_plinth_min_lift and lift.y > 0.0:
		pieces = pieces.duplicate()
		pieces.append(_plinth(pieces, lift.x))
	var moved: float = 0.0
	for attempt in 4:
		var away: Array = [Vector2.ZERO]
		var worst: float = _pieces_clearance(pieces, shift, away)
		if worst >= _th.scenery_road_margin:
			if attempt > 0:
				_guard_moved[_tag] = int(_guard_moved.get(_tag, 0)) + 1
			for pc in pieces:
				var xf: Transform3D = pc[1]
				_commit(pc[0], Transform3D(xf.basis, xf.origin + shift), pc[2])
			return
		var step: float = _th.scenery_road_margin - worst + 0.05
		moved += step
		if moved > _th.scenery_max_nudge:
			break
		var dir: Vector2 = away[0]
		shift += Vector3(dir.x, 0.0, dir.y) * step
	_guard_dropped[_tag] = int(_guard_dropped.get(_tag, 0)) + 1


# Story 008 part 3: how high a prop is raised (x). A prop whose pieces' centre is over a road or
# within TrackTheme.scenery_attach_reach of its wall belongs to that road (walls, posts, banners,
# arches) and stands on its surface height there; farther props stay on the ground (0). 0 on a flat
# track. Part 4: y = how far (meters) the centre is beyond that road's deck edge (<= 0 = on the deck).
func _road_lift(pieces: Array) -> Vector2:
	if _top_road <= 0.0:
		return Vector2.ZERO
	var c := Vector2.ZERO
	for pc in pieces:
		var o: Vector3 = (pc[1] as Transform3D).origin
		c += Vector2(o.x, o.z)
	c /= float(pieces.size())
	var near: Vector3 = _grid.nearest_surface(c)
	return Vector2(maxf(near.y, 0.0), near.z) if near.x <= _th.scenery_attach_reach else Vector2.ZERO


# A plinth piece under [param pieces] (in their unraised coordinates, so after the [param lift]
# it spans the ground up to the road surface): a box over the pieces' footprint.
func _plinth(pieces: Array, lift: float) -> Array:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for pc in pieces:
		var xf: Transform3D = pc[1]
		if xf.origin.y > _th.scenery_clear_height:
			continue  # high parts (roofs, flames) do not widen the base
		var half: float = 0.5 * maxf(xf.basis.x.length(), xf.basis.z.length())
		lo = Vector2(minf(lo.x, xf.origin.x - half), minf(lo.y, xf.origin.z - half))
		hi = Vector2(maxf(hi.x, xf.origin.x + half), maxf(hi.y, xf.origin.z + half))
	if lo.x == INF:
		var o: Vector3 = (pieces[0][1] as Transform3D).origin
		lo = Vector2(o.x, o.z)
		hi = lo
	var m: float = _th.scenery_plinth_margin
	var size := Vector2(maxf(hi.x - lo.x + m, m), maxf(hi.y - lo.y + m, m))
	var c: Vector2 = (lo + hi) * 0.5
	var g: float = _track.data.ground_y
	var height: float = lift - g
	return ["box", Transform3D(Basis.from_scale(Vector3(size.x, height, size.y)), Vector3(c.x, g - lift + height * 0.5, c.y)),
			_track.data.deck_under_color]


# True when [param pieces] would pass the road guard where they are (no move).
func _pieces_fit(pieces: Array) -> bool:
	return _pieces_clearance(pieces, Vector3.ZERO, [Vector2.ZERO]) >= _th.scenery_road_margin


# Smallest road excess over the kart-height footprint of every piece moved by [param shift];
# [param away][0] receives the direction away from the road at the worst point.
func _pieces_clearance(pieces: Array, shift: Vector3, away: Array) -> float:
	var worst: float = INF
	for pc in pieces:
		var xf: Transform3D = pc[1]
		var probe: Array = [Vector2.ZERO]
		var e: float = _piece_clearance(String(pc[0]), Transform3D(xf.basis, xf.origin + shift), probe)
		if e < worst:
			worst = e
			away[0] = probe[0]
	return worst


# Smallest road excess over the footprint of one piece between the ground and
# scenery_clear_height (its unit mesh cut to that band; every unit mesh is convex). INF when the
# piece is flat (top <= scenery_flat_height), entirely above the karts or under the ground.
func _piece_clearance(kind: String, xf: Transform3D, away: Array) -> float:
	# Story 008 part 3: the band reaches up to kart height over the highest road; each road then
	# counts only when the piece is at its level (RoadGrid.excess with the piece's height range).
	var leveled: bool = _top_road > 0.0
	var top_y: float = _th.scenery_clear_height - 0.01 + _top_road
	var o: Vector3 = xf.origin
	var bound: float = GUARD_UNIT_RADIUS * maxf(xf.basis.x.length(), maxf(xf.basis.y.length(), xf.basis.z.length()))
	if o.y + bound <= 0.0 or o.y - bound >= top_y:
		return INF
	var centre: float = _grid.excess(Vector2(o.x, o.z), away, o.y - bound, o.y + bound) if leveled \
			else _grid.excess(Vector2(o.x, o.z), away)
	if centre > bound + _th.scenery_road_margin:
		return centre
	var faces: PackedVector3Array = _faces[kind]
	var world := PackedVector3Array()
	world.resize(faces.size())
	var y_hi: float = -INF
	for k in faces.size():
		world[k] = xf * faces[k]
		y_hi = maxf(y_hi, world[k].y)
	var y_lo: float = INF
	for k in world.size():
		y_lo = minf(y_lo, world[k].y)
	if y_hi <= _th.scenery_flat_height and not leveled:
		return INF
	var band := PackedVector2Array()
	for k in range(0, world.size() - 2, 3):
		for e in 3:
			_clip_band(world[k + e], world[k + (e + 1) % 3], top_y, band)
	if band.is_empty():
		return INF
	var hull: PackedVector2Array = Geometry2D.convex_hull(band)
	var worst: float = INF
	for k in hull.size():
		var a: Vector2 = hull[k]
		var b: Vector2 = hull[(k + 1) % hull.size()]
		var n: int = maxi(1, ceili(a.distance_to(b) / GUARD_STEP))
		for j in n:
			var probe: Array = [Vector2.ZERO]
			var e: float = _grid.excess(a.lerp(b, float(j) / float(n)), probe, y_lo, y_hi) if leveled \
					else _grid.excess(a.lerp(b, float(j) / float(n)), probe)
			if e < worst:
				worst = e
				away[0] = probe[0]
	return worst


# Appends the part of segment [param a]-[param b] between y 0 and [param top_y] (x, z).
func _clip_band(a: Vector3, b: Vector3, top_y: float, out: PackedVector2Array) -> void:
	var t0: float = 0.0
	var t1: float = 1.0
	var dy: float = b.y - a.y
	if absf(dy) < 0.000001:
		if a.y < 0.0 or a.y > top_y:
			return
	else:
		var ta: float = (0.0 - a.y) / dy
		var tb: float = (top_y - a.y) / dy
		t0 = maxf(t0, minf(ta, tb))
		t1 = minf(t1, maxf(ta, tb))
		if t0 > t1:
			return
	var p0: Vector3 = a.lerp(b, t0)
	var p1: Vector3 = a.lerp(b, t1)
	out.append(Vector2(p0.x, p0.z))
	out.append(Vector2(p1.x, p1.z))


func _commit(kind: String, xf: Transform3D, col: Color) -> void:
	if not _batches.has(kind):
		var xs: Array[Transform3D] = []
		var cs: Array[Color] = []
		var tags: Array[String] = []
		_batches[kind] = [xs, cs, tags]
	(_batches[kind][0] as Array[Transform3D]).append(xf)
	(_batches[kind][1] as Array[Color]).append(col)
	(_batches[kind][2] as Array[String]).append(_tag)


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
		"capsule": _unit_capsule(), "glowsphere": _unit_sphere(), "glowcyl": _unit_cylinder(1.0, 10),
		"glowcone": _unit_cylinder(0.0, 10), "glowpyr": _unit_pyramid(),
	}
	for kind in _batches.keys():
		var pair: Array = _batches[kind]
		var mmi: MultiMeshInstance3D = _batch(_meshes[kind], pair[0], pair[1], kind.begins_with("glow"))
		if mmi != null:
			mmi.name = kind
			if audit_mode:
				mmi.set_meta(&"prop_tags", PackedStringArray(pair[2] as Array[String]))
				mmi.set_meta(&"prop_xforms", (pair[0] as Array[Transform3D]).duplicate())
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
	_barbican()
	_village()
	_keep()
	_gardens()
	_passage()


# ---------------------------------------------------------------- dungeon (Dungeon Depths, round 3)
# Placeholder low-poly props following design/art/art-bible.md sections 2-4 and 6: dark stone lit by
# torch pools and lava, a dog-kingdom underworld (bones, barrels, mine carts, forge moulds).
# Light budget: every flame, lava and crystal is an emissive MultiMesh; only a handful of static
# OmniLight3D (see _dungeon_lights) add warm pools, so 12 racers stay inside the frame budget.

func _hash01(a: float, b: float) -> float:
	return fposmod(sin(a * 12.9898 + b * 78.233) * 43758.5453, 1.0)


func _is_open_edge(s: float, side: int) -> bool:
	return _track.wall_offset_at(s, side) > _track.half_width_at(s) + _track.data.curb_width + 0.5


func _build_dungeon() -> void:
	_dungeon_torches()
	_cellar()
	_pillar_hall()
	_cavern()
	_mine()
	_forge()
	_shortcut_marks()
	_dungeon_lights()


# Torches on posts along both road edges: dense in the enclosed zones, sparse in the cavern.
func _dungeon_torches() -> void:
	_tag = "dungeon_torches"
	var cav: Vector2 = _th.zone_cavern
	for side in [-1, 1]:
		var s: float = 6.0
		while s < _track.length:
			var in_cavern: bool = s >= cav.x and s <= cav.y
			var step: float = 40.0 if in_cavern else 12.0
			# Story 008 part 4 leftover: a torch just before an open edge stood inside the edge's
			# reach (the drop beside the lava bridge); it moves back along the road until clear.
			var ts_: float = _torch_slot(s, side)
			var p: Vector2 = _edge(ts_, side, 0.5)
			if ts_ >= 0.0 and _free(p, ts_, 0.25):
				_begin_prop()
				_box(p, 0.95, Vector3(0.22, 1.9, 0.22), _track.tangent_at(ts_), _th.dark_wood_color)
				_add("glowsphere", Transform3D(Basis.from_scale(Vector3(0.3, 0.38, 0.3)), Vector3(p.x, 2.15, p.y)), _th.torch_color)
				_add("glowsphere", Transform3D(Basis.from_scale(Vector3(0.16, 0.2, 0.16)), Vector3(p.x, 2.2, p.y)), _th.lava_bright_color)
				_end_prop()
			s += step


# Story 008 part 5: [param s] moved back along the road (up to TORCH_SLOT_SHIFT m) until no open
# edge on [param side] lies within its reach (TrackData.open_edge_reach) ahead or behind; -1 when
# there is no such place.
func _torch_slot(s: float, side: int) -> float:
	var reach: float = _track.data.open_edge_reach * TORCH_EDGE_REACH_MULT + 1.0
	var shift: float = 0.0
	while shift <= TORCH_SLOT_SHIFT:
		var sv: float = fposmod(s - shift, _track.length)
		if not _is_open_edge(sv, side) and not _is_open_edge(sv + reach, side) and not _is_open_edge(sv - reach, side):
			return sv
		shift += 2.0
	return -1.0


# Cellar Vaults: stone arches every 12 m, barrel racks and giant casks outside the walls, lanterns.
func _cellar() -> void:
	_tag = "cellar"
	for s in _range_steps(_th.zone_cellar, 12.0):
		var c: Vector2 = _track.point_at(s)
		var t: Vector2 = _track.tangent_at(s)
		var n: Vector2 = _track.normal_at(s)
		var w: float = _track.half_width_at(s) + _track.data.curb_width + 0.9
		_begin_prop()
		for side in [-1.0, 1.0]:
			_box(c + n * side * w, 2.1, Vector3(1.3, 4.2, 1.3), t, _th.stone_light)
		_box(c, 4.6, Vector3(w * 2.0 + 1.6, 0.9, 1.4), t, _th.stone_dark)
		_add("glowsphere", Transform3D(Basis.from_scale(Vector3(0.3, 0.3, 0.3)), Vector3(c.x, 3.9, c.y)), _th.torch_color)
		if _pieces_fit(_group):
			_end_prop()
		else:
			# A column stands on a crossing road (the lava gap): the road guard moves or leaves
			# out each piece on its own, so the rest of the arch stays.
			_group_open = false
			for pc in _group:
				_place([pc])
			_group = []
	for s in _range_steps(_th.zone_cellar, 26.0):
		for side in [-1, 1]:
			var p: Vector2 = _edge(s, side, 3.2)
			if not _free(p, s, 2.0) or _is_open_edge(s, side):
				continue
			var t: Vector2 = _track.tangent_at(s)
			_begin_prop()
			_box(p, 1.1, Vector3(2.6, 2.2, 1.6), t, _th.dark_wood_color)
			for k in 3:
				_cyl(p + t * (float(k) - 1.0) * 0.8, 1.5, 0.45, 0.9, _th.wood_color)
			_end_prop()
			if _hash01(s, float(side)) > 0.55:
				_cyl(_edge(s + 9.0, side, 5.5), 1.5, 2.1, 3.0, _th.wood_color)


# Pillar hall: two rows of carved columns along the hall. The three lanes are 8.2 m apart with
# 4.0-4.3 m walls, so their corridors touch: there is no island between them and a column there
# stood on the asphalt (karts drove through it). Road guard (bugfix 2026-11-20): a column goes
# between two lanes only where they leave room for it (shrunk to fit, down to 35 %), otherwise it
# moves just outside the outer wall of its lane, so the hall keeps its two colonnades.
func _pillar_hall() -> void:
	_tag = "pillar_hall"
	var lanes: Array[int] = []
	for bi in _track.branch_count():
		if _track.data.branches[bi].type == &"lane_split":
			lanes.append(bi)
	if lanes.is_empty():
		return
	var s: float = _th.hall_range.x + 4.0
	while s < _th.hall_range.y - 2.0:
		var pm: Vector2 = _track.point_at(s)
		for bi in lanes:
			var pb: Vector2 = _track.branch_point_at(bi, _track.branch_distance_for_s(bi, s))
			if pm.distance_to(pb) < 6.5:
				continue
			var mid: Vector2 = (pm + pb) * 0.5
			var t: Vector2 = _track.tangent_at(s)
			# Road guard: the island between two lanes is narrow, so the column shrinks to fit it
			# (base half diagonal 1.7 m at full size) instead of standing on the asphalt.
			var room: float = _grid.excess(mid, [Vector2.ZERO]) - _th.scenery_road_margin
			var f: float = clampf(room / (1.2 * sqrt(2.0)), 0.0, 1.0)
			if f < 0.35:
				f = 1.0
				var outward: Vector2 = (pb - pm).normalized()
				var lane_wall: float = _track.data.branches[bi].half_width + _track.data.branches[bi].curb_width
				mid = pb + outward * (lane_wall + 1.2 * sqrt(2.0) + _th.scenery_road_margin + 0.05)
				_guard_moved[_tag] = int(_guard_moved.get(_tag, 0)) + 1
			elif f < 1.0:
				_guard_shrunk[_tag] = int(_guard_shrunk.get(_tag, 0)) + 1
			_begin_prop()
			_cyl(mid, 2.6, 0.95 * f, 5.2, _th.stone_light)
			_box(mid, 0.25, Vector3(2.4 * f, 0.5, 2.4 * f), t, _th.stone_dark)
			_box(mid, 5.3, Vector3(2.3 * f, 0.6, 2.3 * f), t, _th.stone_dark)
			_add("glowsphere", Transform3D(Basis.from_scale(Vector3(0.25, 0.25, 0.25)), Vector3(mid.x, 4.0, mid.y)), _th.torch_color)
			_end_prop()
		s += 9.0


# Great Cavern: the lava lake, the huge stalagmite, rock lumps, crystals, a rock arch and a lava fall.
func _cavern() -> void:
	_tag = "cavern"
	var lake := MeshInstance3D.new()
	lake.name = "lava_lake"
	var disc := CylinderMesh.new()
	disc.top_radius = _th.lake_radius
	disc.bottom_radius = _th.lake_radius
	disc.height = 0.2
	disc.radial_segments = 40
	disc.rings = 1
	lake.mesh = disc
	lake.material_override = TrackMesh.lava_material(_th)
	lake.position = Vector3(_th.lake_center.x, -0.11, _th.lake_center.y)  # top just above the ground plane
	add_child(lake)
	var sp: Vector2 = _th.stalagmite_position
	_cone(sp, 0.0, 7.5, 26.0, _th.stone_dark)
	for k in 5:
		var a: float = float(k) * 1.256
		_cone(sp + Vector2(cos(a), sin(a)) * 6.5, 0.0, 2.2, 7.0 + 3.0 * float(k % 3), _th.stone_light)
	# rock lumps and crystals outside the walls (sparse foreground)
	_tag = "cavern_rocks"
	for s in _range_steps(_th.zone_cavern, 16.0):
		for side in [-1, 1]:
			if _is_open_edge(s, side):
				continue
			var h: float = _hash01(s, float(side) * 3.0)
			var p: Vector2 = _edge(s, side, 5.0 + h * 14.0)
			if not _free(p, s, 3.0) or p.distance_to(sp) < 12.0:
				continue
			if h > 0.7:
				_add("glowpyr", Transform3D(Basis(Vector3.UP, h * 6.0).scaled(Vector3(1.4, 3.6, 1.4)), Vector3(p.x, 1.8, p.y)), _th.crystal_color)
			else:
				_cone(p, 0.0, 1.6 + 2.0 * h, 4.0 + 8.0 * h, _th.stone_dark)
	# giant fossil-like rock arch (vista) on the outer side of the cavern
	var mid_s: float = (_th.zone_cavern.x + _th.zone_cavern.y) * 0.5
	var ac: Vector2 = _edge(mid_s, 1, 46.0)
	var at: Vector2 = _track.tangent_at(mid_s)
	_begin_prop()
	_cyl(ac - at * 14.0, 0.0, 3.4, 24.0, _th.stone_dark)
	_cyl(ac + at * 14.0, 0.0, 3.4, 24.0, _th.stone_dark)
	_box(ac, 24.0, Vector3(9.0, 4.5, 36.0), at, _th.stone_dark)
	_end_prop()
	# lava fall in the background, beyond the lake
	var fall: Vector2 = _th.lake_center + Vector2(_th.lake_radius + 14.0, 0.0)  # east of the lake, away from every road
	_add("glow", Transform3D(Basis.from_scale(Vector3(14.0, 34.0, 1.2)), Vector3(fall.x, 17.0, fall.y)), _th.lava_core_color)
	_add("glow", Transform3D(Basis.from_scale(Vector3(7.0, 30.0, 1.4)), Vector3(fall.x, 16.0, fall.y)), _th.lava_bright_color)


# Mine Works: timber supports every 8 m, the ore crusher and pulley wheel, carts of bones and ore,
# ore piles, and sleepers and rails on the mine-cart shortcut.
func _mine() -> void:
	_tag = "mine"
	for s in _range_steps(_th.zone_mine, 8.0):
		var c: Vector2 = _track.point_at(s)
		var t: Vector2 = _track.tangent_at(s)
		var n: Vector2 = _track.normal_at(s)
		var w: float = _track.half_width_at(s) + _track.data.curb_width + 0.5
		var lean: float = (_hash01(s, 1.0) - 0.5) * 0.14
		for side in [-1.0, 1.0]:
			var pp: Vector2 = c + n * side * w
			if _clearance(pp, s) > 0.6:
				continue
			_box(pp, 1.8, Vector3(0.5, 3.6, 0.5), t, _th.wood_color)
		var beam := Transform3D(Basis(Vector3(t.x, 0.0, t.y), lean) * _basis_along(t, Vector3(w * 2.0 + 0.9, 0.5, 0.6)), Vector3(c.x, 3.8, c.y))
		_add("box", beam, _th.dark_wood_color)
	# crusher (hairpin center) and pulley wheel
	_tag = "mine_crusher"
	var cr: Vector2 = _th.crusher_position
	_begin_prop()
	_box(cr, 2.6, Vector3(8.0, 5.2, 8.0), Vector2(1, 0), _th.stone_dark)
	_cone(cr, 5.2, 4.2, 4.0, _th.wood_color)
	_add("glow", Transform3D(Basis.from_scale(Vector3(5.0, 1.2, 0.3)), Vector3(cr.x, 2.0, cr.y + 4.1)), _th.lava_core_color)
	_end_prop()
	var pu: Vector2 = _th.pulley_position
	_begin_prop()
	_add("cyl", Transform3D(Basis(Vector3.RIGHT, PI * 0.5).scaled(Vector3(3.0, 0.7, 3.0)), Vector3(pu.x, 6.0, pu.y)), _th.dark_wood_color)
	for sx in [-1.0, 1.0]:
		_box(pu + Vector2(sx * 3.4, 0.0), 3.0, Vector3(0.6, 6.0, 0.6), Vector2(1, 0), _th.wood_color)
	_end_prop()
	# carts of bones and ore, ore piles, lantern posts
	_tag = "mine_carts"
	for s in _range_steps(_th.zone_mine, 30.0):
		for side in [-1, 1]:
			var p: Vector2 = _edge(s, side, 3.0)
			if not _free(p, s, 1.5):
				continue
			var t: Vector2 = _track.tangent_at(s)
			_begin_prop()
			_box(p, 0.7, Vector3(1.6, 1.0, 2.4), t, _th.dark_wood_color)
			_sphere(p + t * 0.3, 1.35, 0.4, Color(0.92, 0.88, 0.78))
			_sphere(p - t * 0.5, 1.3, 0.34, Color(0.92, 0.88, 0.78))
			_end_prop()
			_cone(_edge(s + 12.0, side, 4.5), 0.0, 2.2, 2.4, Color(0.28, 0.22, 0.2))
			var lp: Vector2 = _edge(s + 15.0, side, 1.6)
			_begin_prop()
			_box(lp, 1.2, Vector3(0.2, 2.4, 0.2), t, _th.dark_wood_color)
			_add("glowsphere", Transform3D(Basis.from_scale(Vector3(0.3, 0.3, 0.3)), Vector3(lp.x, 2.6, lp.y)), _th.torch_color)
			_end_prop()
	# sleepers and rails of the mine-cart branch
	_tag = "mine_rail"
	for bi in _track.branch_count():
		if _track.data.branches[bi].type != &"mine_rail":
			continue
		var path: TrackModel.Path = _track.branches[bi]
		var hw: float = _track.data.branches[bi].half_width
		var lane: float = _track.data.branches[bi].rail_lane
		var d: float = 1.0
		while d < path.length - 1.0:
			var p: Vector2 = path.point_at(d)
			var t: Vector2 = path.tangent_at(d)
			var n: Vector2 = Vector2(-t.y, t.x)
			_box(p, 0.12, Vector3(hw * 2.0, 0.1, 0.34), t, _th.wood_color)
			for side in [-1.0, 1.0]:
				_box(p + n * (lane + side * 0.9), 0.2, Vector3(0.1, 0.12, 1.7), t, Color(0.55, 0.55, 0.6))
			d += 1.6


# Lava Forge: furnaces with glowing mouths, anvils, chimneys, cooling racks, horseshoe and collar
# moulds, and the landmark: a tall glowing smelter stack that stays in view across the lap.
func _forge() -> void:
	_tag = "forge"
	for s in _range_steps(_th.zone_forge, 26.0):
		for side in [-1, 1]:
			var p: Vector2 = _edge(s, side, 4.0)
			if not _free(p, s, 2.5) or _is_open_edge(s, side):
				continue
			var t: Vector2 = _track.tangent_at(s)
			var toward: Vector2 = -_track.normal_at(s) * float(side)
			_begin_prop()
			_box(p, 2.3, Vector3(4.6, 4.6, 4.6), t, _th.stone_dark)
			_add("glow", Transform3D(_basis_along(t, Vector3(2.6, 1.8, 0.3)), Vector3(p.x + toward.x * 2.35, 1.6, p.y + toward.y * 2.35)), _th.lava_core_color)
			_cyl(p, 4.6, 0.9, 8.0, _th.stone_light)
			_end_prop()
			var q: Vector2 = _edge(s + 11.0, side, 2.4)
			if _free(q, s, 1.0):
				_begin_prop()
				_box(q, 0.5, Vector3(1.5, 1.0, 0.9), t, Color(0.2, 0.18, 0.2))
				_box(q, 1.05, Vector3(1.9, 0.18, 0.9), t, Color(0.26, 0.24, 0.26))
				_end_prop()
			var r: Vector2 = _edge(s + 18.0, side, 3.0)
			if _free(r, s, 1.5):
				_begin_prop()
				_box(r, 1.0, Vector3(3.0, 0.2, 1.6), t, _th.dark_wood_color)
				for k in 3:  # horseshoe and collar moulds: a row of bars on a rack
					_box(r + t * (float(k) - 1.0) * 0.9, 1.2, Vector3(0.5, 0.25, 0.2), t, _th.lava_bright_color if k == 1 else Color(0.5, 0.5, 0.55))
				_end_prop()
	var gp: Vector2 = _th.forge_glow_position
	_cyl(gp, 0.0, 7.0, 62.0, _th.stone_dark)
	_add("glowcyl", Transform3D(Basis.from_scale(Vector3(6.2, 3.0, 6.2)), Vector3(gp.x, 62.0, gp.y)), _th.lava_core_color)
	_add("glowcone", Transform3D(Basis.from_scale(Vector3(5.0, 16.0, 5.0)), Vector3(gp.x, 66.0, gp.y)), _th.lava_bright_color)
	for k in 4:
		var a: float = float(k) * PI * 0.5 + PI * 0.25
		_box(gp + Vector2(cos(a), sin(a)) * 8.0, 6.0, Vector3(3.0, 12.0, 3.0), Vector2(cos(a), sin(a)), _th.stone_light)
	# the lava channel under the bridge: lava beyond the hazard strips, on both sides
	for e in _track.data.open_edges:
		if e.z < 0.0 and e.x >= _th.zone_forge.x - 5.0 and e.y <= _th.zone_forge.y + 5.0:
			var m: float = (e.x + e.y) * 0.5
			var chan := MeshInstance3D.new()
			chan.name = "lava_channel"
			var bm := BoxMesh.new()
			bm.size = Vector3(64.0, 0.2, e.y - e.x + 2.0)
			chan.mesh = bm
			chan.material_override = TrackMesh.lava_material(_th)
			var tt: Vector2 = _track.tangent_at(m)
			var cc: Vector2 = _track.point_at(m)
			chan.transform = Transform3D(_basis_along(tt, Vector3.ONE), Vector3(cc.x, -0.11, cc.y))
			add_child(chan)


# Cold blue crystals mark the shortcut entrances and exits (art bible section 4).
func _shortcut_marks() -> void:
	_tag = "shortcut_marks"
	for bi in _track.branch_count():
		var b: TrackBranch = _track.data.branches[bi]
		if b.type == &"lane_split":
			continue
		var path: TrackModel.Path = _track.branches[bi]
		for end in [0.0, path.length]:
			var p: Vector2 = path.point_at(end)
			var t: Vector2 = path.tangent_at(end)
			var n: Vector2 = Vector2(-t.y, t.x)
			for side in [-1.0, 1.0]:
				for k in 3:
					var q: Vector2 = p + n * side * (b.half_width + b.curb_width + 1.4 + 0.6 * float(k)) + t * (float(k) - 1.0) * 1.2
					if _track.excess_at(q) <= 0.3 or _track.in_hazard_area(q):
						continue
					var sc: float = 1.0 + 0.5 * float(k)
					_add("glowpyr", Transform3D(Basis.from_scale(Vector3(0.8, 2.2 * sc, 0.8)), Vector3(q.x, 1.1 * sc, q.y)), _th.crystal_color)


# A handful of static OmniLight3D pools (art bible section 2): the forge glow, the lava lake, the
# crusher, the crystals, the pillar hall, the cellar, the bridge and the lava gap. Everything else
# is emissive geometry. No shadows.
func _dungeon_lights() -> void:
	var hall_mid: float = (_th.hall_range.x + _th.hall_range.y) * 0.5
	var spots: Array = [
		[_th.forge_glow_position, 30.0, _th.lava_core_color, 5.0, 110.0],
		[_th.lake_center, 8.0, _th.lava_core_color, 3.5, 75.0],
		[_th.crusher_position, 5.0, _th.torch_color, 2.5, 28.0],
		[_th.stalagmite_position, 6.0, _th.crystal_color, 2.0, 38.0],
		[_track.point_at(hall_mid), 4.5, _th.torch_color, 2.5, 26.0],
		[_track.point_at(fposmod(_th.zone_cellar.x + 40.0, _track.length)), 4.5, _th.torch_color, 2.5, 30.0],
		[_track.point_at((_th.zone_forge.x + _th.zone_forge.y) * 0.5), 5.0, _th.lava_core_color, 3.0, 40.0],
	]
	for i in _track.hazard_gates.size():
		if _track.hazard_gates[i] > 0.0:
			spots.append([_track.hazard_bounds[i].get_center(), 3.5, _th.lava_core_color, 3.0, 22.0])
	for spot in spots:
		var l := OmniLight3D.new()
		var xz: Vector2 = spot[0]
		l.position = Vector3(xz.x, float(spot[1]), xz.y)
		l.light_color = spot[2]
		l.light_energy = float(spot[3])
		l.omni_range = float(spot[4])
		l.shadow_enabled = false
		add_child(l)


# Banner poles every banner_spacing meters along both edges, everywhere.
func _banners() -> void:
	_tag = "banners"
	var th: TrackTheme = _th
	var k: int = 0
	for s in _range_steps(Vector2(0.0, _track.length), th.banner_spacing):
		var t: Vector2 = _track.tangent_at(s)
		for side in [1, -1]:
			var p: Vector2 = _edge(s, side, th.banner_distance_from_wall)
			if not _free(p, s, BOX_CLEARANCE * 0.5):
				continue
			_begin_prop()
			_box(p, th.banner_height * 0.5, Vector3(0.3, th.banner_height, 0.3), t, th.banner_pole_color)
			_box(p - t * 0.9, th.banner_height - 1.7, Vector3(0.08, 3.0, 1.8), t,
					th.banner_color_a if k % 2 == 0 else th.banner_color_b)
			_end_prop()
		k += 1


func _start_arch() -> void:
	_tag = "start_arch"
	var th: TrackTheme = _th
	var p0: Vector2 = _track.point_at(0.0)
	var t0: Vector2 = _track.tangent_at(0.0)
	var n0: Vector2 = _track.normal_at(0.0)
	var reach: float = _track.wall_offset_at(0.0, 1) + 0.8
	_begin_prop()
	for side in [1.0, -1.0]:
		_box(p0 + n0 * side * reach, 4.5, Vector3(1.2, 9.0, 1.2), t0, th.start_arch_color)
	_box(p0, 9.0, Vector3(reach * 2.0 + 1.2, 1.6, 1.0), t0, th.banner_color_b)
	_box(p0 - t0 * 0.6, 7.0, Vector3(reach * 1.4, 2.6, 0.1), t0, th.banner_color_a)
	_end_prop()


# Tourney Field: grandstands with a crowd on the outside of the start straight, tents and a
# jousting fence in the lists (inside the first sweeper), pennant strings on the edges.
func _tourney() -> void:
	_tag = "tourney"
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
			_begin_prop()
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
			_end_prop()
	# Tents and jousting fence around the lists center.
	_tag = "tourney_lists"
	var lc: Vector2 = th.lists_center
	if lc != Vector2.ZERO:
		for k in 6:
			var ang: float = TAU * float(k) / 6.0
			var p: Vector2 = lc + Vector2(cos(ang), sin(ang)) * 16.0
			if not _free(p, r.x, 4.0):
				continue
			_begin_prop()
			_cyl(p, 1.5, 2.6, 3.0, th.tent_color_b if k % 2 == 0 else th.tent_color_a)
			_cone(p, 4.6, 3.2, 3.2, th.tent_color_a if k % 2 == 0 else th.tent_color_b)
			_box(p, 7.0, Vector3(0.1, 1.2, 0.8), Vector2(1, 0), th.banner_color_b)
			_end_prop()
		for k in 14:
			var p: Vector2 = lc + Vector2(-13.0 + k * 2.0, 0.0)
			if _free(p, r.x, 1.0):
				_begin_prop()
				_box(p, 0.6, Vector3(2.0, 0.15, 0.15), Vector2(1, 0), th.wood_color)
				_box(p, 1.1, Vector3(2.0, 0.15, 0.15), Vector2(1, 0), th.wood_color)
				_box(p + Vector2(-1.0, 0.0), 0.7, Vector3(0.2, 1.4, 0.2), Vector2(1, 0), th.dark_wood_color)
				_end_prop()
	# Pennant strings: small alternating flags between banner poles along the zone.
	_tag = "tourney_pennants"
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
	_tag = "moat_and_gate"
	var th: TrackTheme = _th
	var g: Vector2 = th.gate_position
	if g == Vector2.ZERO:
		return
	# Story 008 part 5: the gate arch is the ground level under the gatehouse deck; a query
	# without height could return the deck above it.
	var ground: float = maxf(_track.data.ground_y, 0.0)
	var gs: float = _track.query(g, -1, ground).s
	var t: Vector2 = _track.tangent_at(gs)
	var n: Vector2 = _track.normal_at(gs)
	var hw: float = _track.wall_offset_at(gs, 1)
	if is_finite(_track.deck_above(g, ground, 0.0)):
		_gatehouse_deck(gs)
	else:
		# Gatehouse: two towers, a top block, portcullis teeth.
		for side in [1.0, -1.0]:
			var tp: Vector2 = g + n * side * (hw + 3.0)
			_begin_prop()
			_cyl(tp, 6.0, 3.2, 12.0, th.tower_color)
			_cone(tp, 15.0, 4.0, 6.0, th.roof_color)
			_end_prop()
		_box(g, 9.5, Vector3(2.0 * hw + 6.0, 5.0, 5.0), t, th.stone_light)
		for k in 7:
			var tooth: Vector2 = g + n * (-hw + 0.5 + k * (2.0 * hw - 1.0) / 6.0)
			_box(tooth, 6.4, Vector3(0.25, 1.4, 0.25), t, th.dark_wood_color)
	# Curtain wall both ways from the gate, with towers every 32 m, skipping roads and water.
	_tag = "curtain_wall"
	for side in [1.0, -1.0]:
		var d: float = hw + 6.0
		while d < 80.0:
			var p: Vector2 = g + n * side * d
			# Part 5: never under a road at any level (the gatehouse deck runs along this line;
			# the solid rampart under it is the wall there).
			if _free(p, gs, 1.5) and _track.excess_at(p) >= 1.5:
				_begin_prop()
				_box(p, 2.5, Vector3(4.0, 5.0, 2.2), t, th.stone_light)
				if int(d / 4.0) % 2 == 0:
					_box(p, 5.6, Vector3(1.6, 1.2, 2.2), t, th.stone_dark)
				if int(d) % 32 < 4:
					_cyl(p, 6.5, 3.6, 13.0, th.tower_color)
					_cone(p, 16.0, 4.6, 6.0, th.roof_color)
				_end_prop()
			d += 4.0
	# Low stone studs along the open moat edge (the curb is the only barrier: a warning line).
	# They stand where a kart can drive off into the water, so they are flat drive-over stones
	# (road guard: no taller than scenery_flat_height), not posts a kart would pass through.
	_tag = "moat_posts"
	var stud: float = th.scenery_flat_height * 0.9
	for e in _track.data.open_edges:
		for s in _range_steps(Vector2(e.x, e.y), 7.0):
			var p: Vector2 = _track.point_at(s) + _track.normal_at(s) * e.z * (_track.half_width_at(s) + _track.data.curb_width + 0.4)
			_box(p, stud * 0.5, Vector3(0.6, stud, 0.6), _track.tangent_at(s), th.stone_dark)


# Story 008 part 5: the gate road runs under the gatehouse deck (the Barbican Spiral's gate_top
# straight crosses over it), so the deck IS the gatehouse top. No tower or block may stand on the
# upper road: two stone piers fill the open span under the deck on both sides of the gate passage
# (from the passage to where the solid rampart begins), the portcullis hangs under the deck's
# entry edge, two round towers flank the entry, and a bone balustrade fills the crenels of the
# deck's parapet over the span (art bible section 6: bone railing posts).
func _gatehouse_deck(gs: float) -> void:
	var th: TrackTheme = _th
	var d: TrackData = _track.data
	var ground: float = maxf(d.ground_y, 0.0)
	var g: Vector2 = _track.point_at(gs)
	var t: Vector2 = _track.tangent_at(gs)
	var n: Vector2 = _track.normal_at(gs)
	var up: TrackModel.Path = _track.main
	var hit: TrackModel.Hit = up.nearest_filtered(g, ground + d.level_separation, INF)
	if hit == null:
		return
	var count: int = up.points.size()
	var ua: Vector2 = up.points[hit.seg]
	var ub: Vector2 = up.points[(hit.seg + 1) % count]
	var u: Vector2 = (ub - ua).normalized()
	var u_s: float = up.cumulative[hit.seg] + hit.t * (up.cumulative[hit.seg + 1] - up.cumulative[hit.seg])
	var sin_th: float = absf(t.cross(u))
	var cos_th: float = absf(t.dot(u))
	if sin_th < 0.3:
		return  # roads nearly parallel: not a gate crossing
	# where the two centrelines cross
	var a_x: float = (ua.lerp(ub, hit.t) - g).cross(u) / t.cross(u)
	var x: Vector2 = g + t * a_x
	var u_x: float = u_s + (x - ua.lerp(ub, hit.t)).dot(u)
	var lower_wall: float = maxf(_track.wall_offset_at(gs, 1), _track.wall_offset_at(gs, -1))
	var upper_wall: float = up.wall_at(hit.seg, hit.t, 1)
	_tag = "gatehouse"
	_no_lift = true
	# Piers: from the passage wall to the end of the open span, under the deck, on both sides.
	var pier_half: float = upper_wall - 0.5
	for sgn in [1.0, -1.0]:
		var open_end: float = 0.0
		var b: float = 0.0
		while b <= GATE_SEARCH:
			var stv: Vector2 = up.seg_t_at(u_x + sgn * b)
			var c: Vector2 = up.point_at(u_x + sgn * b)
			if not _track.road_below(c, up.height_at(int(stv.x), stv.y), up.half_at(int(stv.x), stv.y) + up.curb + TrackMesh.PILLAR_CLEARANCE):
				break
			open_end = b
			b += GATE_STEP
		var inner: float = (lower_wall + th.scenery_road_margin + 0.1 + pier_half * cos_th) / sin_th
		var outer: float = open_end - 0.3
		if outer - inner < 1.0:
			continue
		var dir: Vector2 = u * sgn
		var side_n: Vector2 = Vector2(-dir.y, dir.x)
		var top: float = INF
		for along in [inner, outer]:
			for across in [-pier_half, pier_half]:
				top = minf(top, _track.deck_above(x + dir * along + side_n * across, ground, 0.0))
		if not is_finite(top):
			continue
		top -= th.deck_prop_gap
		var pc: Vector2 = x + dir * (inner + outer) * 0.5
		_begin_prop()
		_box(pc, ground + (top - ground) * 0.5, Vector3(pier_half * 2.0, top - ground, outer - inner), dir, th.stone_light)
		_end_prop()
	# Portcullis under the deck's entry edge (the side the gate road comes from) and the entry towers.
	var d0: float = INF
	var k: float = -GATE_SEARCH
	while k <= GATE_SEARCH:
		if is_finite(_track.deck_above(_track.point_at(gs + k), ground, 0.0)):
			d0 = k
			break
		k += GATE_STEP
	if is_finite(d0):
		var se: float = gs + d0 + 0.3
		var pe: Vector2 = _track.point_at(se)
		var ne: Vector2 = _track.normal_at(se)
		var te: Vector2 = _track.tangent_at(se)
		var under: float = _track.deck_above(pe, ground, 0.0)
		var hwe: float = _track.half_width_at(se)
		if is_finite(under):
			_begin_prop()
			_box(pe, under - 0.2, Vector3(2.0 * hwe, 0.25, 0.25), te, th.dark_wood_color)
			for j in 7:
				var tooth: Vector2 = pe + ne * (-hwe + 0.5 + float(j) * (2.0 * hwe - 1.0) / 6.0)
				_box(tooth, under - 0.75, Vector3(0.25, 1.4, 0.25), te, th.dark_wood_color)
			_end_prop()
		for side in [1.0, -1.0]:
			var tp: Vector2 = _track.point_at(gs + d0 - 4.0) + _track.normal_at(gs + d0 - 4.0) * side * (lower_wall + 3.6)
			_begin_prop()
			_cyl(tp, ground + 6.0, 3.2, 12.0, th.tower_color)
			_cone(tp, ground + 15.0, 4.0, 6.0, th.roof_color)
			_end_prop()
	# Bone balustrade: one bone in each crenel (the wall segments without a merlon) of the deck's
	# parapet over the open span, both sides.
	var stripe: int = maxi(th.wall_stripe_segments, 1)
	var reach: int = int(GATE_SEARCH / maxf(up.length / float(count), 0.1))
	for o in range(-reach, reach + 1):
		var i: int = posmod(hit.seg + o, count)
		var j: int = (i + 1) % count
		if (i / stripe) % 2 != 1:
			continue
		if not _track.road_below(up.points[i], up.y[i], up.half[i] + up.curb + TrackMesh.PILLAR_CLEARANCE):
			continue
		var seg_dir: Vector2 = (up.points[j] - up.points[i]).normalized()
		var nrm: Vector2 = (up.points[j] - up.points[posmod(i - 1, count)]).normalized()
		nrm = Vector2(-nrm.y, nrm.x)
		for side in [1.0, -1.0]:
			var wi: float = up.wall_pos[i] if side > 0.0 else up.wall_neg[i]
			if wi > up.half[i] + up.curb + 0.05:
				continue
			var wj: float = up.wall_pos[j] if side > 0.0 else up.wall_neg[j]
			var mid: Vector2 = (up.points[i] + up.points[j]) * 0.5 + nrm * side * ((wi + wj) * 0.5 + th.wall_thickness * 0.5)
			var base: float = (up.y[i] + wi * side * tan(up.bank[i]) + up.y[j] + wj * side * tan(up.bank[j])) * 0.5 + th.wall_height
			_begin_prop()
			_add("capsule", Transform3D(Basis.from_scale(Vector3(BONE_SHAFT.x * 2.0, BONE_SHAFT.y * 0.5, BONE_SHAFT.x * 2.0)),
					Vector3(mid.x, base + BONE_SHAFT.y * 0.5 + BONE_KNOB * 0.5, mid.y)), th.bone_color)
			for end_y in [base + BONE_KNOB * 0.6, base + BONE_SHAFT.y + BONE_KNOB * 0.4]:
				for e in [-1.0, 1.0]:
					var kp: Vector2 = mid + seg_dir * e * BONE_KNOB * 0.9
					_sphere(kp, end_y, BONE_KNOB, th.bone_color)
			_end_prop()
	_no_lift = false


# Story 008 part 5: the barbican, a round tower at the centre of the Barbican Spiral: stone body,
# a darker ring course, a cone roof, and a paw crest standing on the roof's apex facing the gate
# (art bible section 6: the paw crest at its largest scale on a gate building).
func _barbican() -> void:
	var bp: Vector2 = _th.barbican_position
	if bp == Vector2.ZERO:
		return
	_tag = "barbican"
	var th: TrackTheme = _th
	var ground: float = maxf(_track.data.ground_y, 0.0)
	var r: float = th.barbican_radius
	var h: float = th.barbican_height
	var face: Vector2 = (th.gate_position - bp).normalized() if th.gate_position != Vector2.ZERO else Vector2(1.0, 0.0)
	_no_lift = true
	_begin_prop()
	_cyl(bp, ground + h * 0.5, r, h, th.tower_color)
	_cyl(bp, ground + h - 0.4, r + 0.35, 0.8, th.stone_dark)
	_cone(bp, ground + h + th.barbican_roof_height * 0.5, r + 0.9, th.barbican_roof_height, th.roof_color)
	# paw crest: a disc on the apex facing the gate, a big pad and four toes on both faces
	var cr: float = th.barbican_crest_radius
	var c3 := Vector3(bp.x, ground + h + th.barbican_roof_height + cr * 0.85, bp.y)
	var f3 := Vector3(face.x, 0.0, face.y)
	var p3 := Vector3(-face.y, 0.0, face.x)
	_add("cyl", Transform3D(Basis(p3 * cr, f3 * 0.12, Vector3.UP * cr), c3), th.crest_color)
	for fs in [1.0, -1.0]:
		var o3: Vector3 = c3 + f3 * fs * 0.14
		_add("sphere", Transform3D(Basis(p3 * cr * 0.36, f3 * 0.08, Vector3.UP * cr * 0.3), o3 - Vector3.UP * cr * 0.22), th.crest_paw_color)
		for toe in 4:
			var a: float = deg_to_rad(-54.0 + 36.0 * float(toe))
			var tp3: Vector3 = o3 + p3 * sin(a) * cr * 0.5 + Vector3.UP * (cos(a) * cr * 0.5 - cr * 0.05)
			_add("sphere", Transform3D(Basis(p3 * cr * 0.13, f3 * 0.07, Vector3.UP * cr * 0.16), tp3), th.crest_paw_color)
	_end_prop()
	_no_lift = false


# True when [param p] is within the barbican's radius plus [param extra] meters of its centre.
func _near_barbican(p: Vector2, extra: float) -> bool:
	var bp: Vector2 = _th.barbican_position
	return bp != Vector2.ZERO and p.distance_to(bp) < _th.barbican_radius + extra


# True when [param p] is within [param radius] meters of the gatehouse (TrackTheme.gate_position).
func _near_gate(p: Vector2, radius: float) -> bool:
	var g: Vector2 = _th.gate_position
	return g != Vector2.ZERO and p.distance_to(g) < radius


# Market Village: house facades on both sides, stalls on the island of the lane split, the
# well, barrels, crates and hanging signs.
func _village() -> void:
	_tag = "village"
	var th: TrackTheme = _th
	var r: Vector2 = th.zone_village
	var k: int = 0
	for s in _range_steps(r, 8.0):
		var t: Vector2 = _track.tangent_at(s)
		for side in [1, -1]:
			var out: Vector2 = _track.normal_at(s) * float(side)
			var p: Vector2 = _edge(s, side, 4.2)
			# Story 008 part 5: the Barbican Spiral and the gatehouse stand clear: no house on the
			# rampart ring around the barbican or against the gate towers (they cut into each other).
			if not _free(p, s, 3.0) or _near_barbican(p, BARBICAN_CLEAR) or _near_gate(p, GATE_CLEAR):
				continue
			_tag = "village_house"
			_begin_prop()
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
			_end_prop()
			if k % 2 == 0:
				_tag = "village_barrels"
				var bp: Vector2 = _edge(s, side, 0.9) + t * 2.0
				if _free(bp, s, 0.4) and not _near_barbican(bp, BARBICAN_CLEAR) and not _near_gate(bp, GATE_CLEAR):
					_begin_prop()
					_cyl(bp, 0.5, 0.45, 1.0, th.wood_color)
					_cyl(bp + t * 1.0, 0.5, 0.45, 1.0, th.wood_color)
					_box(bp - t * 1.1, 0.45, Vector3(0.9, 0.9, 0.9), t, th.dark_wood_color.lightened(0.2))
					_end_prop()
			k += 1
	# Stalls on the island between the lanes.
	_tag = "village_stall"
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
				# Road guard: the whole stall (counter, fruit, awning) is checked, not its centre.
				_begin_prop()
				_box(mp, 0.55, Vector3(2.0, 1.1, 5.0), t, th.wood_color)
				for st in 4:
					_box(mp + t * (-1.9 + st * 1.26), 2.6, Vector3(2.6, 0.12, 1.26), t, th.tent_color_a if (st + j) % 2 == 0 else th.tent_color_b)
				_box(mp, 1.3, Vector3(1.4, 0.4, 3.0), t, th.fruit_color)
				_end_prop()
			a0 += 9.0
			j += 1
	# The well: on the free side of the S-bend.
	_tag = "village_well"
	var w: Vector2 = th.well_position
	if w != Vector2.ZERO:
		var ws: float = _track.query(w, -1).s
		for side in [1, -1]:
			var p: Vector2 = _edge(ws, side, 3.0)
			if _free(p, ws, 2.0):
				_begin_prop()
				_cyl(p, 0.5, 1.6, 1.0, th.stone_light)
				_box(p, 1.8, Vector3(0.2, 2.6, 0.2), Vector2(1, 0), th.dark_wood_color)
				_cone(p, 3.4, 2.0, 1.2, th.roof_color)
				_end_prop()
				break


# Keep Courtyard: the keep, the knight-dog statue on the hairpin fountain, training dummies.
func _keep() -> void:
	_tag = "keep"
	var th: TrackTheme = _th
	var kc: Vector2 = th.keep_center
	var ks: Vector3 = th.keep_size * Vector3(1.4, 1.5, 1.4)
	if kc != Vector2.ZERO:
		_begin_prop()
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
		_end_prop()
	var sp: Vector2 = th.statue_position
	if sp != Vector2.ZERO:
		_begin_prop()
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
		_end_prop()
	# Training dummies and braziers along the plaza edges.
	_tag = "keep_dummies"
	var r: Vector2 = th.zone_keep
	var k: int = 0
	for s in _range_steps(r, 11.0):
		for side in [1, -1]:
			var p: Vector2 = _edge(s, side, 2.0)
			if not _free(p, s, 1.0):
				continue
			_begin_prop()
			if k % 2 == 0:
				_box(p, 1.0, Vector3(0.25, 2.0, 0.25), Vector2(1, 0), th.dark_wood_color)
				_box(p, 1.6, Vector3(1.6, 0.2, 0.2), _track.tangent_at(s), th.wood_color)
				_sphere(p, 2.3, 0.35, th.house_wall_color)
			else:
				_box(p, 0.6, Vector3(0.6, 1.2, 0.6), Vector2(1, 0), th.stone_dark)
				_box(p, 1.35, Vector3(0.5, 0.3, 0.5), Vector2(1, 0), th.torch_color, "glow")
			_end_prop()
			k += 1


# Rampart Gardens: orchard trees and hedges on both edges, the trebuchet, the distant windmill.
func _gardens() -> void:
	_tag = "gardens"
	var th: TrackTheme = _th
	var r: Vector2 = th.zone_gardens
	var k: int = 0
	for s in _range_steps(r, 7.0):
		var t: Vector2 = _track.tangent_at(s)
		for side in [1, -1]:
			# A 7 m hedge row along the road edge (it was turned along the normal, so it reached
			# 2.3 m into the road; bugfix 2026-11-20), in two 3.5 m pieces that follow the bend
			# (story 008 part 5: one straight 7 m piece cut 0.25 m into the inside of hairpin 2).
			for half_off in [-1.75, 1.75]:
				var hs: float = s + half_off
				var hp: Vector2 = _edge(hs, side, 1.2)
				if _free(hp, hs, 0.5):
					_box(hp, 0.6, Vector3(1.0, 1.2, 3.5), _track.tangent_at(hs), th.hedge_color)
			var p: Vector2 = _edge(s, side, 5.0 + float(k % 3) * 2.5)
			if _free(p, s, 3.0):
				_begin_prop()
				_cyl(p, 1.1, 0.35, 2.2, th.dark_wood_color)
				_sphere(p, 3.2, 2.1, th.foliage_color if k % 2 == 0 else th.foliage_alt_color)
				_sphere(p + t * 0.9, 3.9, 0.3, th.fruit_color)
				_end_prop()
			k += 1
	# Trebuchet on the lawn inside the long sweeper.
	_tag = "gardens_trebuchet"
	var oc: Vector2 = th.orchard_center
	if oc != Vector2.ZERO:
		_begin_prop()
		_box(oc, 0.4, Vector3(6.0, 0.8, 4.0), Vector2(1, 0), th.wood_color)
		for sx in [-1.5, 1.5]:
			_box(oc + Vector2(0.0, sx), 3.0, Vector3(0.5, 6.0, 0.5), Vector2(1, 0), th.dark_wood_color)
		_add("box", Transform3D(Basis(Vector3(0, 0, 1), 0.6).scaled(Vector3(12.0, 0.4, 0.4)), Vector3(oc.x, 6.5, oc.y)), th.wood_color)
		_box(oc + Vector2(-3.5, 0.0), 3.4, Vector3(1.6, 1.6, 1.6), Vector2(1, 0), th.stone_dark)
		_end_prop()
	var wm: Vector2 = th.windmill_position
	if wm != Vector2.ZERO:
		_begin_prop()
		_cyl(wm, 7.0, 4.0, 14.0, th.house_wall_color)
		_cone(wm, 16.5, 4.8, 5.0, th.roof_color)
		for b in 4:
			var ang: float = PI * 0.25 + b * PI * 0.5
			_add("box", Transform3D(Basis(Vector3(0, 0, 1), ang).scaled(Vector3(11.0, 1.4, 0.2)),
					Vector3(wm.x + cos(ang) * 5.5, 13.0 + sin(ang) * 5.5, wm.y + 4.3)), th.house_wall_color.darkened(0.1))
		_end_prop()


# The secret passage: tapestry at the entrance, a dark roof where it runs inside the keep wing,
# torches along both walls, arches at both ends.
func _passage() -> void:
	_tag = "passage"
	var th: TrackTheme = _th
	for bi in _track.branch_count():
		var b: TrackBranch = _track.data.branches[bi]
		var path: TrackModel.Path = _track.branches[bi]
		if b.arch_ends:
			for end in [0, 1]:
				var d0: float = _arch_distance(path, end == 1)
				var inward: float = -1.0 if end == 1 else 1.0
				# Road guard: where the passage leaves the plaza one column would stand on the main
				# road, so the arch moves into the passage (1 m steps) until both columns are clear.
				var placed: bool = false
				for step in int(path.length * 0.4):
					var d: float = d0 + inward * float(step)
					var ap: Vector2 = path.point_at(d)
					var at: Vector2 = path.tangent_at(d)
					var an: Vector2 = Vector2(-at.y, at.x)
					# Columns keep the road margin off the passage walls (they stood flush on them).
					var gap: float = path.wall_offset + 1.05 + _th.scenery_road_margin
					_begin_prop()
					for side in [1.0, -1.0]:
						_box(ap + an * side * gap, (b.wall_height + 1.6) * 0.5, Vector3(1.8, b.wall_height + 1.6, 1.8), at, th.arch_color)
					_box(ap, b.wall_height + 1.9, Vector3(gap * 2.0 + 1.8, 1.4, 1.8), at, th.arch_color.darkened(0.1))
					if end == 0:
						# The tapestry hangs on the front of the arch, above the karts (it hung across
						# the entrance at kart height, where karts drove through it).
						var tap_h: float = b.wall_height * 0.8
						_box(ap - at * 0.95, th.scenery_clear_height + tap_h * 0.5, Vector3(gap * 2.0 - 0.6, tap_h, 0.08), at, th.tapestry_color)
					if _pieces_fit(_group):
						if step > 0:
							_guard_moved[_tag] = int(_guard_moved.get(_tag, 0)) + 1
						_end_prop()
						placed = true
						break
					_group_open = false
					_group = []
				if not placed:
					_guard_props[_tag] = int(_guard_props.get(_tag, 0)) + 1
					_guard_dropped[_tag] = int(_guard_dropped.get(_tag, 0)) + 1
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
	# (>= / <=: with > and < the start end returned 0 at once, so the entrance arch stood in the plaza.)
	while d >= 0.0 and d <= path.length:
		if _track.main.nearest(path.point_at(d), -1, 0).excess > 1.0:
			break
		d += dir
	return clampf(d, 0.0, path.length)


func _build_item_boxes() -> void:
	# Story 004: the ItemManager draws the boxes (they rotate, bob, hide and respawn).
	return
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
func _batch(mesh: Mesh, xforms: Array[Transform3D], colors: Array[Color], glow: bool) -> MultiMeshInstance3D:
	if xforms.is_empty():
		return null
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
	return mmi
