class_name TrackModel
extends RefCounted
## Geometry of a track built from TrackData: the closed main centerline plus open shortcut
## branches, distance along the main loop, nearest-road queries and per-road wall offsets.
## Pure math, no nodes. track_s always means progress along the MAIN loop in meters; on a
## branch it is the branch parameter mapped linearly onto [s_in, s_out].
## Implements design/game-brief.md, Features items 1 and 4.

## Spacing (meters) used to estimate the tangent at a distance.
const TANGENT_STEP: float = 1.0
## Path index of the main road in [member Query.path].
const MAIN_PATH: int = -1
## A query hint is (path + 1) * HINT_STRIDE + segment, so the hint also remembers the road.
const HINT_STRIDE: int = 1000000
## A rail-less branch's open reach grows from 0 where its centerline is this far inside the
## main wall (see _build_branch).
const OPEN_REACH_TAPER: float = 1.0
## Constant slack (meters) added to the progress rate cap.
const PROGRESS_SLACK: float = 0.03


## Result of [method query].
class Query extends RefCounted:
	## Hint to pass back into the next query (encodes road and segment).
	var segment: int = 0
	## Road the point belongs to: MAIN_PATH or a branch index.
	var path: int = -1
	## Segment index within that road.
	var local_segment: int = 0
	## Progress along the MAIN loop (branch parameter mapped onto [s_in, s_out]).
	var s: float = 0.0
	## Signed sideways offset from that road's centerline (left positive).
	var lateral: float = 0.0
	var tangent: Vector2 = Vector2.ZERO
	## Left-pointing unit normal.
	var normal: Vector2 = Vector2.ZERO
	## Distance from that road's centerline to its wall on the side the point is on (local:
	## it follows the road's width profile and open edges).
	var wall_offset: float = 0.0
	## Half the road surface width at that point (without the curb).
	var half_width: float = 0.0
	## Meters along that road (main: equals s; branch: from the branch start).
	var along: float = 0.0
	## Wall drag multiplier of that road (TrackBranch.wall_drag_mult; 1 on the main road).
	var wall_drag_mult: float = 1.0
	## Distance from the point to that road's centerline.
	var distance: float = 0.0


## Nearest-point result on one road (internal).
class Hit extends RefCounted:
	var path: Path
	var seg: int = 0
	var t: float = 0.0
	var dist: float = 0.0
	var excess: float = 0.0
	## +1 when the point is on the road's normal side, -1 otherwise.
	var side: int = 1


## One centerline polyline (the main loop or a branch).
class Path extends RefCounted:
	var index: int = -1
	var id: StringName = &""
	var points: PackedVector2Array = PackedVector2Array()
	## Cumulative distance per point; the last entry is the total length.
	var cumulative: PackedFloat32Array = PackedFloat32Array()
	var length: float = 0.0
	var closed: bool = false
	## Nominal half width and wall offset (largest values; per-point values are below).
	var half_width: float = 0.0
	var wall_offset: float = 0.0
	var wall_drag_mult: float = 1.0
	var curb: float = 0.0
	## Half road width at each point.
	var half: PackedFloat32Array = PackedFloat32Array()
	## Wall offset at each point on the normal side (+) and the other side (-).
	var wall_pos: PackedFloat32Array = PackedFloat32Array()
	var wall_neg: PackedFloat32Array = PackedFloat32Array()
	## Main-loop range this road covers (branches only).
	var s_in: float = 0.0
	var s_out: float = 0.0
	## Bounding box inflated by the wall offset.
	var bounds: Rect2 = Rect2()

	func finish() -> void:
		var n: int = points.size()
		var count: int = segment_count()
		cumulative.resize(count + 1)
		cumulative[0] = 0.0
		var min_p: Vector2 = points[0]
		var max_p: Vector2 = points[0]
		for i in count:
			cumulative[i + 1] = cumulative[i] + points[i].distance_to(points[(i + 1) % n])
		for p in points:
			min_p = Vector2(minf(min_p.x, p.x), minf(min_p.y, p.y))
			max_p = Vector2(maxf(max_p.x, p.x), maxf(max_p.y, p.y))
		length = cumulative[count]
		if half.size() != n:
			half.resize(n)
			half.fill(half_width)
		if wall_pos.size() != n:
			wall_pos.resize(n)
			wall_neg.resize(n)
			for i in n:
				wall_pos[i] = half[i] + curb
				wall_neg[i] = half[i] + curb
		var widest: float = 0.0
		for i in n:
			widest = maxf(widest, maxf(wall_pos[i], wall_neg[i]))
		half_width = 0.0
		for v in half:
			half_width = maxf(half_width, v)
		wall_offset = half_width + curb
		var pad: float = widest + 2.0
		bounds = Rect2(min_p - Vector2(pad, pad), (max_p - min_p) + Vector2(pad, pad) * 2.0)

	## Half road width at segment [param seg], fraction [param t].
	func half_at(seg: int, t: float) -> float:
		var n: int = points.size()
		return lerpf(half[seg], half[(seg + 1) % n], t)

	## Wall offset at segment [param seg], fraction [param t], on [param side] (+1 / -1).
	func wall_at(seg: int, t: float, side: int) -> float:
		var n: int = points.size()
		var arr: PackedFloat32Array = wall_pos if side >= 0 else wall_neg
		return lerpf(arr[seg], arr[(seg + 1) % n], t)

	## Segment (x) and fraction (y) at distance [param dist] along the road.
	func seg_t_at(dist: float) -> Vector2:
		var sv: float = fposmod(dist, length) if closed else clampf(dist, 0.0, length)
		var lo: int = segment_at(sv)
		var seg_len: float = cumulative[lo + 1] - cumulative[lo]
		return Vector2(lo, (sv - cumulative[lo]) / seg_len if seg_len > 0.0 else 0.0)

	func segment_count() -> int:
		return points.size() if closed else points.size() - 1

	## Nearest point to [param p]; searches [param window] segments around [param hint]
	## (the whole road when hint is negative or the road is open).
	func nearest(p: Vector2, hint: int, window: int) -> Hit:
		var count: int = segment_count()
		var n: int = points.size()
		var best_i: int = 0
		var best_t: float = 0.0
		var best_d: float = INF
		var use_window: bool = hint >= 0 and closed and window * 2 + 1 < count
		var lo: int = -window if use_window else 0
		var hi: int = window if use_window else count - 1
		for o in range(lo, hi + 1):
			var i: int = posmod(hint + o, count) if use_window else o
			var a: Vector2 = points[i]
			var ab: Vector2 = points[(i + 1) % n] - a
			var l2: float = ab.length_squared()
			var t: float = clampf((p - a).dot(ab) / l2, 0.0, 1.0) if l2 > 0.0 else 0.0
			var d: float = p.distance_squared_to(a + ab * t)
			if d < best_d:
				best_d = d
				best_i = i
				best_t = t
		var h := Hit.new()
		h.path = self
		h.seg = best_i
		h.t = best_t
		h.dist = sqrt(best_d)
		var a2: Vector2 = points[best_i]
		var ab2: Vector2 = points[(best_i + 1) % n] - a2
		h.side = 1 if (p - (a2 + ab2 * best_t)).dot(Vector2(-ab2.y, ab2.x)) >= 0.0 else -1
		h.excess = h.dist - wall_at(best_i, best_t, h.side)
		return h

	## Segment index that contains distance [param dist] along the road.
	func segment_at(dist: float) -> int:
		var count: int = segment_count()
		var sv: float = fposmod(dist, length) if closed else clampf(dist, 0.0, length)
		var lo: int = 0
		var hi: int = count - 1
		while lo < hi:
			var mid: int = (lo + hi + 1) >> 1
			if cumulative[mid] <= sv:
				lo = mid
			else:
				hi = mid - 1
		return lo

	## Point at [param dist] meters along the road (wraps when closed, clamps when open).
	func point_at(dist: float) -> Vector2:
		var sv: float = fposmod(dist, length) if closed else clampf(dist, 0.0, length)
		var lo: int = segment_at(sv)
		var a: Vector2 = points[lo]
		var b: Vector2 = points[(lo + 1) % points.size()]
		var seg_len: float = cumulative[lo + 1] - cumulative[lo]
		return a.lerp(b, (sv - cumulative[lo]) / seg_len if seg_len > 0.0 else 0.0)

	func tangent_at(dist: float) -> Vector2:
		return (point_at(dist + TANGENT_STEP) - point_at(dist - TANGENT_STEP)).normalized()


var data: TrackData
## The main road.
var main: Path
## Branch roads, in the order of data.branches.
var branches: Array[Path] = []
## Main centerline samples as (x, z).
var points: PackedVector2Array = PackedVector2Array()
## Cumulative distance at each main sample; one extra entry holds the full length.
var cumulative: PackedFloat32Array = PackedFloat32Array()
## Total main loop length in meters.
var length: float = 0.0
## Distance from the main centerline to the main wall.
var wall_offset: float = 0.0
## Interior checkpoint distances along the main loop (ascending, excluding the line at 0).
var checkpoint_s: PackedFloat32Array = PackedFloat32Array()
## Look of the track (data.theme, or the plain default).
var theme: TrackTheme
## Largest change of track_s per meter moved (see limit_progress).
var progress_rate_cap: float = 1.95
## Hazard outlines and their bounding boxes (data.hazards).
var hazard_polygons: Array[PackedVector2Array] = []
var hazard_bounds: Array[Rect2] = []
## Boost pads: center, unit direction along the road, half length and half width.
var pad_centers: PackedVector2Array = PackedVector2Array()
var pad_dirs: PackedVector2Array = PackedVector2Array()
var pad_halves: PackedVector2Array = PackedVector2Array()
var _switch_margin: float = 0.75
var _keep_band: float = 1.5
var _window: int = 14


func _init(track_data: TrackData) -> void:
	data = track_data
	theme = data.theme if data.theme != null else TrackTheme.new()
	progress_rate_cap = data.progress_rate_cap
	_switch_margin = data.branch_switch_margin
	_keep_band = data.road_keep_band
	_window = data.query_window
	wall_offset = data.road_half_width + data.curb_width
	main = Path.new()
	main.closed = true
	main.half_width = data.road_half_width
	main.curb = data.curb_width
	var ctrl: PackedVector2Array = data.control_points
	var n: int = ctrl.size()
	var widths: bool = data.half_widths.size() == n
	for i in n:
		var p0: Vector2 = ctrl[(i - 1 + n) % n]
		var p1: Vector2 = ctrl[i]
		var p2: Vector2 = ctrl[(i + 1) % n]
		var p3: Vector2 = ctrl[(i + 2) % n]
		for k in data.samples_per_segment:
			var f: float = float(k) / data.samples_per_segment
			main.points.append(catmull_rom(p0, p1, p2, p3, f))
			main.half.append(lerpf(data.half_widths[i], data.half_widths[(i + 1) % n], f) if widths else data.road_half_width)
	_main_walls()
	main.finish()
	points = main.points
	cumulative = main.cumulative
	length = main.length
	for bi in data.branches.size():
		branches.append(_build_branch(bi, data.branches[bi]))
	var count: int = maxi(data.checkpoint_count, 1)
	for k in range(1, count):
		checkpoint_s.append(length * float(k) / float(count))
	for hz in data.hazards:
		if hz == null or hz.polygon.size() < 3:
			continue
		hazard_polygons.append(hz.polygon)
		var r := Rect2(hz.polygon[0], Vector2.ZERO)
		for q in hz.polygon:
			r = r.expand(q)
		hazard_bounds.append(r)
	for pad in data.boost_pads:
		if pad == null:
			continue
		var bi: int = -1 if pad.road == &"" else branch_index(pad.road)
		var path: Path = main if bi < 0 else branches[bi]
		var t: Vector2 = path.tangent_at(pad.distance)
		pad_centers.append(path.point_at(pad.distance) + Vector2(-t.y, t.x) * pad.lateral)
		pad_dirs.append(t)
		pad_halves.append(Vector2(pad.length * 0.5, pad.width * 0.5))


# Wall offsets per main sample: half width + curb, plus the open-edge reach on open stretches.
func _main_walls() -> void:
	var m: int = main.points.size()
	var acc: float = 0.0
	main.wall_pos.resize(m)
	main.wall_neg.resize(m)
	for i in m:
		var w: float = main.half[i] + data.curb_width
		main.wall_pos[i] = w
		main.wall_neg[i] = w
		for e in data.open_edges:
			if acc >= e.x and acc <= e.y:
				if e.z > 0.0:
					main.wall_pos[i] = w + data.open_edge_reach
				else:
					main.wall_neg[i] = w + data.open_edge_reach
		acc += main.points[i].distance_to(main.points[(i + 1) % m])


func _build_branch(index: int, b: TrackBranch) -> Path:
	var c: PackedVector2Array = b.control_points.duplicate()
	c[0] = main.point_at(b.s_in)
	c[c.size() - 1] = main.point_at(b.s_out)
	var path := Path.new()
	path.index = index
	path.id = b.id
	path.closed = false
	path.half_width = b.half_width
	path.curb = b.curb_width
	path.wall_drag_mult = b.wall_drag_mult
	path.s_in = b.s_in
	path.s_out = b.s_out
	var cn: int = c.size()
	var widths: bool = b.half_widths.size() == cn
	for i in cn - 1:
		var p0: Vector2 = c[i - 1] if i > 0 else c[0] * 2.0 - c[1]
		var p3: Vector2 = c[i + 2] if i + 2 < cn else c[cn - 1] * 2.0 - c[cn - 2]
		for k in b.samples_per_segment:
			var f: float = float(k) / b.samples_per_segment
			path.points.append(catmull_rom(p0, c[i], c[i + 1], p3, f))
			path.half.append(lerpf(b.half_widths[i], b.half_widths[i + 1], f) if widths else b.half_width)
	path.points.append(c[cn - 1])
	path.half.append(b.half_widths[cn - 1] if widths else b.half_width)
	var m: int = path.points.size()
	path.wall_pos.resize(m)
	path.wall_neg.resize(m)
	for i in m:
		# The open reach only applies where the deck is out over the hazard: it tapers to 0
		# where the branch runs inside the main corridor, so its ends never open a gap past
		# the main road's walls.
		var reach: float = 0.0
		if b.open_edge_reach > 0.0:
			var out: float = main.nearest(path.points[i], -1, 0).excess
			reach = clampf(out + OPEN_REACH_TAPER, 0.0, b.open_edge_reach)
		var w: float = path.half[i] + b.curb_width + reach
		path.wall_pos[i] = w
		path.wall_neg[i] = w
	path.finish()
	return path


## Nearest road info for [param p]. [param hint] is a previous Query.segment (or negative to
## search everywhere). The kart belongs to the road whose corridor it is inside; where
## corridors overlap it keeps its road unless another centerline is clearly closer. Outside
## every corridor the nearest corridor edge is used, so the union of corridors is the
## drivable area.
func query(p: Vector2, hint: int) -> Query:
	var cur_path: int = MAIN_PATH
	var cur_seg: int = -1
	if hint >= 0:
		cur_path = hint / HINT_STRIDE - 1
		cur_seg = hint % HINT_STRIDE
	var main_hint: int = -1
	if cur_path == MAIN_PATH:
		main_hint = cur_seg
	elif cur_path >= 0 and cur_path < branches.size():
		var bp: Path = branches[cur_path]
		var frac: float = bp.cumulative[mini(cur_seg, bp.segment_count())] / bp.length
		main_hint = main.segment_at(bp.s_in + frac * (bp.s_out - bp.s_in))
	else:
		cur_path = MAIN_PATH
	var hits: Array[Hit] = [main.nearest(p, main_hint, _window)]
	for bp in branches:
		if bp.bounds.has_point(p):
			hits.append(bp.nearest(p, -1, 0))
	var cur: Hit = null
	var best: Hit = null
	for h in hits:
		if h.path.index == cur_path:
			cur = h
		if best == null or _better(h, best):
			best = h
	# Stay on the current road while still inside its corridor: a kart only changes road when
	# it actually leaves one, so following the main road past a branch entrance (where both
	# centerlines start together) never captures it into the branch.
	if cur != null and best != cur and cur.excess <= -_keep_band:
		best = cur
	elif cur != null and best != cur and cur.excess <= 0.0 and best.excess <= 0.0:
		if best.dist + _switch_margin > cur.dist:
			best = cur
	elif cur != null and best != cur and best.excess > 0.0 and cur.excess - best.excess <= _switch_margin:
		best = cur
	return _to_query(p, best)


# Inside beats outside; among inside roads the nearest centerline wins; among outside roads
# the smallest excess over the wall wins.
func _better(a: Hit, b: Hit) -> bool:
	var a_in: bool = a.excess <= 0.0
	var b_in: bool = b.excess <= 0.0
	if a_in != b_in:
		return a_in
	if a_in:
		return a.dist < b.dist
	return a.excess < b.excess


func _to_query(p: Vector2, h: Hit) -> Query:
	var path: Path = h.path
	var n: int = path.points.size()
	var a: Vector2 = path.points[h.seg]
	var b: Vector2 = path.points[(h.seg + 1) % n]
	var q := Query.new()
	q.path = path.index
	q.local_segment = h.seg
	q.segment = (path.index + 1) * HINT_STRIDE + h.seg
	q.tangent = (b - a).normalized()
	q.normal = Vector2(-q.tangent.y, q.tangent.x)
	var along: float = path.cumulative[h.seg] + a.distance_to(b) * h.t
	if path.index == MAIN_PATH:
		q.s = along
	else:
		q.s = path.s_in + along / path.length * (path.s_out - path.s_in)
	# Lateral is the signed distance to the nearest point, and the normal points from that
	# point to p, so clamping to the wall is exact even at a segment end or a concave kink.
	var off: Vector2 = p - a.lerp(b, h.t)
	var side: float = 1.0 if off.dot(q.normal) >= 0.0 else -1.0
	q.lateral = side * h.dist
	if h.dist > 0.0001:
		q.normal = off / h.dist * side
	q.wall_offset = path.wall_at(h.seg, h.t, 1 if side > 0.0 else -1)
	q.half_width = path.half_at(h.seg, h.t)
	q.along = along
	q.wall_drag_mult = path.wall_drag_mult
	q.distance = h.dist
	return q


## Smallest (distance to a centerline - that road's wall offset) over all roads; <= 0 means
## [param p] is inside the union of corridors.
func excess_at(p: Vector2) -> float:
	var best: float = main.nearest(p, -1, 0).excess
	for bp in branches:
		best = minf(best, bp.nearest(p, -1, 0).excess)
	return best


## How far [param p] is beyond the wall of road [param path_index] only (MAIN_PATH or a
## branch index; negative = inside that road). Unlike excess_at, other roads do not count,
## so a wall between two roads (the secret passage and the plaza) is respected.
func excess_on_path(p: Vector2, path_index: int) -> float:
	var path: Path = main if path_index == MAIN_PATH or path_index >= branches.size() else branches[path_index]
	return path.nearest(p, -1, 0).excess


## Distance from [param p] to the centerline of road [param path_index] (MAIN_PATH or a
## branch index), searching the whole road.
func distance_to_path(p: Vector2, path_index: int) -> float:
	var path: Path = main if path_index == MAIN_PATH else branches[path_index]
	return path.nearest(p, -1, 0).dist


## Point on the MAIN centerline at [param dist] meters (wraps around the loop).
func point_at(dist: float) -> Vector2:
	return main.point_at(dist)


## Unit direction of travel on the main loop at [param dist].
func tangent_at(dist: float) -> Vector2:
	return main.tangent_at(dist)


## Left-pointing unit normal on the main loop at [param dist].
func normal_at(dist: float) -> Vector2:
	var t: Vector2 = tangent_at(dist)
	return Vector2(-t.y, t.x)


## Number of shortcut branches.
func branch_count() -> int:
	return branches.size()


## Index of the branch whose id or type is [param id], or -1.
func branch_index(id: StringName) -> int:
	for i in data.branches.size():
		if data.branches[i].id == id or data.branches[i].type == id:
			return i
	return -1


## Length of branch [param i] in meters.
func branch_length(i: int) -> float:
	return branches[i].length


## Point on branch [param i] at [param dist] meters from its start (clamped to the branch).
## Meters along branch [param i] of the point on it nearest [param p].
func branch_along(i: int, p: Vector2) -> float:
	var bp: Path = branches[i]
	var h: Hit = bp.nearest(p, -1, 0)
	var a: Vector2 = bp.points[h.seg]
	var b: Vector2 = bp.points[mini(h.seg + 1, bp.points.size() - 1)]
	return bp.cumulative[h.seg] + a.distance_to(b) * h.t


func branch_point_at(i: int, dist: float) -> Vector2:
	return branches[i].point_at(dist)


## Unit direction of travel on branch [param i] at [param dist] meters from its start.
func branch_tangent_at(i: int, dist: float) -> Vector2:
	return branches[i].tangent_at(dist)


## Left-pointing unit normal on branch [param i] at [param dist].
func branch_normal_at(i: int, dist: float) -> Vector2:
	var t: Vector2 = branch_tangent_at(i, dist)
	return Vector2(-t.y, t.x)


## Meters along branch [param i] that correspond to main-loop progress [param s].
func branch_distance_for_s(i: int, s: float) -> float:
	var b: Path = branches[i]
	return (s - b.s_in) / (b.s_out - b.s_in) * b.length


## World position of item-box spot [param i] (data.item_box_spots).
func item_box_position(i: int) -> Vector2:
	var spot: Vector2 = data.item_box_spots[i]
	return point_at(spot.x) + normal_at(spot.x) * spot.y


## Half road width of the main road at main-loop distance [param s].
func half_width_at(s: float) -> float:
	var st: Vector2 = main.seg_t_at(s)
	return main.half_at(int(st.x), st.y)


## Main wall offset at [param s] on [param side] (+1 = normal side, -1 the other).
func wall_offset_at(s: float, side: int) -> float:
	var st: Vector2 = main.seg_t_at(s)
	return main.wall_at(int(st.x), st.y, side)


## The road object for [param path_index] (MAIN_PATH or a branch index).
func path_of(path_index: int) -> Path:
	return main if path_index < 0 or path_index >= branches.size() else branches[path_index]


## Query hint that keeps a query on road [param path_index] near [param along] meters.
func hint_for(path_index: int, along: float) -> int:
	var path: Path = path_of(path_index)
	return (path.index + 1) * HINT_STRIDE + path.segment_at(along)


## True when the track has hazard areas.
func has_hazards() -> bool:
	return not hazard_polygons.is_empty()


## True when [param p] lies inside a hazard outline (ignores roads; see [method in_hazard]).
func in_hazard_area(p: Vector2) -> bool:
	for i in hazard_polygons.size():
		if hazard_bounds[i].has_point(p) and Geometry2D.is_point_in_polygon(p, hazard_polygons[i]):
			return true
	return false


## True when [param p] is on the drawn surface (road plus curb) of any road. [param q], the
## point's own query if known, is checked first.
func on_surface(p: Vector2, q: Query = null) -> bool:
	if q != null:
		var own: Path = path_of(q.path)
		if q.distance <= q.half_width + own.curb:
			return true
	var roads: Array[Path] = [main]
	roads.append_array(branches)
	for path in roads:
		if q != null and path.index == q.path:
			continue
		if not path.bounds.has_point(p):
			continue
		var h: Hit = path.nearest(p, -1, 0)
		if h.dist <= path.half_at(h.seg, h.t) + path.curb:
			return true
	return false


## True when a kart center at [param p] is in a hazard: inside an outline and on no road.
func in_hazard(p: Vector2, q: Query = null) -> bool:
	return in_hazard_area(p) and not on_surface(p, q)


## Index of the boost pad under [param p], or -1.
func pad_at(p: Vector2) -> int:
	for i in pad_centers.size():
		var d: Vector2 = p - pad_centers[i]
		var t: Vector2 = pad_dirs[i]
		var hl: Vector2 = pad_halves[i]
		if absf(d.dot(t)) <= hl.x and absf(d.cross(t)) <= hl.y:
			return i
	return -1


## Where a kart that last drove safely at [param along] meters on road [param path_index]
## reappears: [position, unit direction] on that road's centerline, data.respawn_back_off
## meters back (clamped to the start of a branch).
func respawn_pose(path_index: int, along: float) -> Array:
	var path: Path = path_of(path_index)
	var d: float = along - data.respawn_back_off
	if not path.closed:
		d = clampf(d, 0.0, path.length)
	return [path.point_at(d), path.tangent_at(d)]


## New progress value that moves from [param prev] toward [param target] by at most
## progress_rate_cap times [param moved] (meters actually travelled) plus a small slack, with
## wrap-around at the loop length. Keeps track_s smooth where roads join.
func limit_progress(prev: float, target: float, moved: float) -> float:
	var d: float = wrapf(target - prev, -length * 0.5, length * 0.5)
	var allow: float = progress_rate_cap * moved + PROGRESS_SLACK
	if absf(d) <= allow:
		return target
	return fposmod(prev + signf(d) * allow, length)


## Catmull-Rom spline point between [param p1] and [param p2].
static func catmull_rom(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var t2: float = t * t
	var t3: float = t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
			+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)
