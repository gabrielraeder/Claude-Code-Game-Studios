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
	## Floor drag multiplier of that road (TrackBranch.floor_drag_mult; 1 = smooth).
	var floor_drag_mult: float = 1.0
	## Distance from the point to that road's centerline.
	var distance: float = 0.0
	## Height (Y, meters) of the road surface at the point (lateral clamped to the road+curb).
	var height: float = 0.0
	## Bank of the road here in radians (positive = banked into a left turn).
	var bank: float = 0.0
	## Slope of the road along its direction: rise per meter (dy/ds), positive = climbing.
	var slope: float = 0.0
	## Unit normal of the road surface (from the slope along the road and the bank across it).
	var surface_normal: Vector3 = Vector3.UP
	## Slope angle along the road in radians (atan of [member slope]).
	var slope_angle: float = 0.0
	## True when the point is on that road's drawn surface (road plus curb); false past an open
	## edge (story 008: over a drop the kart falls, see [member support]).
	var on_deck: bool = true
	## Height of whatever holds a kart up at the point: the road surface (with any ramp) when
	## [member on_deck] or on another road's deck at a similar level, else TrackData.ground_y.
	var support: float = 0.0
	## Height the jump ramp under the point adds to the road (0 when not on a ramp).
	var ramp_rise: float = 0.0


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
	## Road height (Y) of the centerline at each point.
	var y: PackedFloat32Array = PackedFloat32Array()
	## Bank in radians at each point (positive = banked into a left turn).
	var bank: PackedFloat32Array = PackedFloat32Array()
	## Rise per meter along the road at each point (smoothed central difference).
	var slope: PackedFloat32Array = PackedFloat32Array()
	## Cumulative distance per point; the last entry is the total length.
	var cumulative: PackedFloat32Array = PackedFloat32Array()
	var length: float = 0.0
	var closed: bool = false
	## Nominal half width and wall offset (largest values; per-point values are below).
	var half_width: float = 0.0
	var wall_offset: float = 0.0
	var wall_drag_mult: float = 1.0
	## Floor drag multiplier of that road (TrackBranch.floor_drag_mult; 1 = smooth).
	var floor_drag_mult: float = 1.0
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
		if y.size() != n:
			y.resize(n)
			y.fill(0.0)
		if bank.size() != n:
			bank.resize(n)
			bank.fill(0.0)
		slope.resize(n)
		for i in n:
			var i0: int = (i - 1 + n) % n if (closed or i > 0) else 0
			var i1: int = (i + 1) % n if (closed or i < n - 1) else n - 1
			var span: float = cumulative[i1] - cumulative[i0] if i1 > i0 else cumulative[count] - cumulative[i0] + cumulative[i1]
			slope[i] = (y[i1] - y[i0]) / span if span > 0.0001 else 0.0
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

	## Centerline height at segment [param seg], fraction [param t].
	func height_at(seg: int, t: float) -> float:
		return lerpf(y[seg], y[(seg + 1) % points.size()], t)

	## Bank (radians) at segment [param seg], fraction [param t].
	func bank_at(seg: int, t: float) -> float:
		return lerpf(bank[seg], bank[(seg + 1) % points.size()], t)

	## Rise per meter along the road at segment [param seg], fraction [param t].
	func slope_at(seg: int, t: float) -> float:
		return lerpf(slope[seg], slope[(seg + 1) % points.size()], t)

	## Surface height at segment [param seg], fraction [param t], [param lateral] meters to the
	## normal side. The lateral offset is clamped to the road plus curb (the curb is flat out).
	func surface_y(seg: int, t: float, lateral: float) -> float:
		var reach: float = half_at(seg, t) + curb
		return height_at(seg, t) + clampf(lateral, -reach, reach) * tan(bank_at(seg, t))

	## Like [method nearest] over the whole road, but only segments whose centerline height at the
	## nearest point lies in [y_lo, y_hi] count (stacked roads, story 008). Null when none does.
	func nearest_filtered(p: Vector2, y_lo: float, y_hi: float) -> Hit:
		var count: int = segment_count()
		var n: int = points.size()
		var best_i: int = -1
		var best_t: float = 0.0
		var best_d: float = INF
		for i in count:
			var a: Vector2 = points[i]
			var ab: Vector2 = points[(i + 1) % n] - a
			var l2: float = ab.length_squared()
			var t: float = clampf((p - a).dot(ab) / l2, 0.0, 1.0) if l2 > 0.0 else 0.0
			var d: float = p.distance_squared_to(a + ab * t)
			if d >= best_d:
				continue
			var yc: float = height_at(i, t)
			if yc < y_lo or yc > y_hi:
				continue
			best_d = d
			best_i = i
			best_t = t
		if best_i < 0:
			return null
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
## Per hazard: TrackHazard.min_cross_speed (0 = ordinary) and kind (water, lava).
var hazard_gates: PackedFloat32Array = PackedFloat32Array()
var hazard_kinds: Array[StringName] = []
## Surface height (Y) of each hazard (TrackHazard.surface_height; story 008 part 3).
var hazard_heights: PackedFloat32Array = PackedFloat32Array()
## Boost pads: center, unit direction along the road, half length and half width.
var pad_centers: PackedVector2Array = PackedVector2Array()
var pad_dirs: PackedVector2Array = PackedVector2Array()
var pad_halves: PackedVector2Array = PackedVector2Array()
## Road the pad lies on (MAIN_PATH or a branch index) and the road height at its center (story 008).
var pad_paths: PackedInt32Array = PackedInt32Array()
var pad_heights: PackedFloat32Array = PackedFloat32Array()
## Jump ramps (data.ramps, story 008): road index, start along that road, length, lip height,
## lateral center and half width (0 = the whole road with curbs).
var ramp_paths: PackedInt32Array = PackedInt32Array()
var ramp_from: PackedFloat32Array = PackedFloat32Array()
var ramp_len: PackedFloat32Array = PackedFloat32Array()
var ramp_lip: PackedFloat32Array = PackedFloat32Array()
var ramp_lat: PackedFloat32Array = PackedFloat32Array()
var ramp_half: PackedFloat32Array = PackedFloat32Array()
## Main-loop distance of each ramp's lip (drivers that time a trick jump use it).
var ramp_lip_s: PackedFloat32Array = PackedFloat32Array()
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
	var has_h: bool = data.heights.size() == n
	var has_b: bool = data.banks.size() == n
	for i in n:
		var p0: Vector2 = ctrl[(i - 1 + n) % n]
		var p1: Vector2 = ctrl[i]
		var p2: Vector2 = ctrl[(i + 1) % n]
		var p3: Vector2 = ctrl[(i + 2) % n]
		for k in data.samples_per_segment:
			var f: float = float(k) / data.samples_per_segment
			main.points.append(catmull_rom(p0, p1, p2, p3, f))
			main.half.append(lerpf(data.half_widths[i], data.half_widths[(i + 1) % n], f) if widths else data.road_half_width)
			if has_h:
				main.y.append(catmull_rom_f(data.heights[(i - 1 + n) % n], data.heights[i],
						data.heights[(i + 1) % n], data.heights[(i + 2) % n], f))
			else:
				main.y.append(0.0)
			if has_b:
				main.bank.append(deg_to_rad(catmull_rom_f(data.banks[(i - 1 + n) % n], data.banks[i],
						data.banks[(i + 1) % n], data.banks[(i + 2) % n], f)))
			else:
				main.bank.append(0.0)
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
		hazard_gates.append(hz.min_cross_speed)
		hazard_kinds.append(hz.kind)
		hazard_heights.append(hz.surface_height)
	for rp in data.ramps:
		if rp == null or rp.length <= 0.0:
			continue
		var ri: int = -1 if rp.road == &"" else branch_index(rp.road)
		ramp_paths.append(ri)
		ramp_from.append(rp.distance)
		ramp_len.append(rp.length)
		ramp_lip.append(rp.lip_height)
		ramp_lat.append(rp.lateral)
		ramp_half.append(rp.half_width)
		if ri < 0:
			ramp_lip_s.append(fposmod(rp.distance + rp.length, length))
		else:
			var rb: Path = branches[ri]
			ramp_lip_s.append(rb.s_in + (rp.distance + rp.length) / rb.length * (rb.s_out - rb.s_in))

	for pad in data.boost_pads:
		if pad == null:
			continue
		var bi: int = -1 if pad.road == &"" else branch_index(pad.road)
		var path: Path = main if bi < 0 else branches[bi]
		var t: Vector2 = path.tangent_at(pad.distance)
		pad_centers.append(path.point_at(pad.distance) + Vector2(-t.y, t.x) * pad.lateral)
		pad_dirs.append(t)
		pad_halves.append(Vector2(pad.length * 0.5, pad.width * 0.5))
		pad_paths.append(bi if bi >= 0 else MAIN_PATH)
		var pst: Vector2 = path.seg_t_at(pad.distance)
		pad_heights.append(path.surface_y(int(pst.x), pst.y, pad.lateral) + _ramp_rise(bi if bi >= 0 else MAIN_PATH, pad.distance, pad.lateral).x)

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


# Per-control-point height (or bank in degrees) of branch [param b]: the data when it has one entry
# per control point, with both ends forced to the main road's value at s_in and s_out; else a
# smoothstep blend from the main road's value at s_in to its value at s_out.
func _branch_profile(values: PackedFloat32Array, count: int, b: TrackBranch, is_bank: bool) -> PackedFloat32Array:
	var in_st: Vector2 = main.seg_t_at(b.s_in)
	var out_st: Vector2 = main.seg_t_at(b.s_out)
	var v_in: float = rad_to_deg(main.bank_at(int(in_st.x), in_st.y)) if is_bank else main.height_at(int(in_st.x), in_st.y)
	var v_out: float = rad_to_deg(main.bank_at(int(out_st.x), out_st.y)) if is_bank else main.height_at(int(out_st.x), out_st.y)
	var out := PackedFloat32Array()
	out.resize(count)
	for i in count:
		var u: float = float(i) / float(maxi(count - 1, 1))
		out[i] = values[i] if values.size() == count else lerpf(v_in, v_out, smoothstep(0.0, 1.0, u))
	out[0] = v_in
	out[count - 1] = v_out
	return out


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
	path.floor_drag_mult = b.floor_drag_mult
	path.s_in = b.s_in
	path.s_out = b.s_out
	var cn: int = c.size()
	var widths: bool = b.half_widths.size() == cn
	var hs: PackedFloat32Array = _branch_profile(b.heights, cn, b, false)
	var bs: PackedFloat32Array = _branch_profile(b.banks, cn, b, true)
	for i in cn - 1:
		var p0: Vector2 = c[i - 1] if i > 0 else c[0] * 2.0 - c[1]
		var p3: Vector2 = c[i + 2] if i + 2 < cn else c[cn - 1] * 2.0 - c[cn - 2]
		for k in b.samples_per_segment:
			var f: float = float(k) / b.samples_per_segment
			path.points.append(catmull_rom(p0, c[i], c[i + 1], p3, f))
			path.half.append(lerpf(b.half_widths[i], b.half_widths[i + 1], f) if widths else b.half_width)
			var h0: float = hs[i - 1] if i > 0 else hs[0] * 2.0 - hs[1]
			var h3: float = hs[i + 2] if i + 2 < cn else hs[cn - 1] * 2.0 - hs[cn - 2]
			path.y.append(catmull_rom_f(h0, hs[i], hs[i + 1], h3, f))
			var b0: float = bs[i - 1] if i > 0 else bs[0] * 2.0 - bs[1]
			var b3: float = bs[i + 2] if i + 2 < cn else bs[cn - 1] * 2.0 - bs[cn - 2]
			path.bank.append(deg_to_rad(catmull_rom_f(b0, bs[i], bs[i + 1], b3, f)))
	path.points.append(c[cn - 1])
	path.half.append(b.half_widths[cn - 1] if widths else b.half_width)
	path.y.append(hs[cn - 1])
	path.bank.append(deg_to_rad(bs[cn - 1]))
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
## drivable area. [param y_hint] is the caller's current height (story 008, crossovers): where
## roads overlap in XZ at different heights, only roads (and parts of the main loop) whose
## centerline is within data.level_separation of it are considered, so a kart on a bridge stays
## on the bridge and one under it stays under it. NAN = no height known (nearest in XZ). A hinted
## query searches the main loop only near the hint, which already keeps both levels of a
## self-crossing loop apart.
func query(p: Vector2, hint: int, y_hint: float = NAN) -> Query:
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
	var leveled: bool = not is_nan(y_hint)
	var sep: float = data.level_separation
	var main_hit: Hit = null
	if leveled and main_hint < 0:
		main_hit = main.nearest_filtered(p, y_hint - sep, y_hint + sep)
	if main_hit == null:
		main_hit = main.nearest(p, main_hint, _window)
	var hits: Array[Hit] = [main_hit]
	for bp in branches:
		if bp.bounds.has_point(p):
			var bh: Hit = bp.nearest(p, -1, 0)
			if leveled and bp.index != cur_path and absf(bp.height_at(bh.seg, bh.t) - y_hint) > sep:
				var lh: Hit = bp.nearest_filtered(p, y_hint - sep, y_hint + sep)
				if lh == null:
					continue
				bh = lh
			hits.append(bh)
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
	return _to_query(p, best, y_hint)


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


func _to_query(p: Vector2, h: Hit, y_hint: float = NAN) -> Query:
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
	q.floor_drag_mult = path.floor_drag_mult
	q.distance = h.dist
	var reach: float = q.half_width + path.curb
	var lat_c: float = clampf(q.lateral, -reach, reach)
	q.bank = path.bank_at(h.seg, h.t)
	q.slope = path.slope_at(h.seg, h.t)
	q.slope_angle = atan(q.slope)
	q.height = path.height_at(h.seg, h.t) + lat_c * tan(q.bank)
	var rise: Vector2 = _ramp_rise(path.index, along, q.lateral)
	if rise != Vector2.ZERO:
		q.ramp_rise = rise.x
		q.height += rise.x
		q.slope += rise.y
		q.slope_angle = atan(q.slope)
	q.surface_normal = surface_normal_of(q.tangent, q.slope, q.bank)
	q.on_deck = h.dist <= reach
	q.support = q.height if q.on_deck else _support_off_deck(p, path.index, q.height if is_nan(y_hint) else y_hint)
	return q


# Height (x) and slope (y, rise per meter) a ramp adds at [param along] meters on road
# [param path_index], [param lateral] from its centerline; zero off every ramp. The wedge rises
# linearly from its start to the lip and ends there (a step back down to the road).
func _ramp_rise(path_index: int, along: float, lateral: float) -> Vector2:
	for i in ramp_paths.size():
		if ramp_paths[i] != path_index:
			continue
		var u: float = along - ramp_from[i]
		if path_index == MAIN_PATH:
			u = wrapf(u, -length * 0.5, length * 0.5)
		if u < 0.0 or u >= ramp_len[i]:
			continue
		if ramp_half[i] > 0.0 and absf(lateral - ramp_lat[i]) > ramp_half[i]:
			continue
		return Vector2(ramp_lip[i] * u / ramp_len[i], ramp_lip[i] / ramp_len[i])
	return Vector2.ZERO


# What holds a kart up at [param p] off its own road's deck (past an open edge): another road's
# deck under it no higher than level_separation above [param y_ref], else the world floor
# (data.ground_y).
func _support_off_deck(p: Vector2, own: int, y_ref: float) -> float:
	var best: float = data.ground_y
	var roads: Array[Path] = [main]
	roads.append_array(branches)
	for path in roads:
		if path.index == own or not path.bounds.has_point(p):
			continue
		var h: Hit = path.nearest_filtered(p, -INF, y_ref + data.level_separation)
		if h == null or h.dist > path.half_at(h.seg, h.t) + path.curb:
			continue
		var a: Vector2 = path.points[h.seg]
		var b: Vector2 = path.points[(h.seg + 1) % path.points.size()]
		var lat: float = (p - a.lerp(b, h.t)).dot(Vector2(-(b - a).y, (b - a).x).normalized()) if a != b else 0.0
		best = maxf(best, path.surface_y(h.seg, h.t, lat))
	return best


## True when some road (or another part of the main loop) passes under [param p] at least
## data.level_separation below [param y] and its corridor (wall offset plus [param margin])
## contains [param p]. TrackMesh keeps bridge supports out of the road below with it.
func road_below(p: Vector2, y: float, margin: float) -> bool:
	var roads: Array[Path] = [main]
	roads.append_array(branches)
	for path in roads:
		if not path.bounds.has_point(p):
			continue
		var h: Hit = path.nearest_filtered(p, -INF, y - data.level_separation)
		if h != null and h.excess < margin:
			return true
	return false


## Story 008 part 3 (scenery guard and audit): true when a piece spanning heights
## [param y_lo]..[param y_hi] is in the way of a road whose surface is at [param h]. It is when it
## reaches below h + [param clear] (kart height over that road) and its top is above
## h + [param flat] (drive-over detail) on a road near the ground, or above the deck's underside
## (h - deck_thickness) on a raised road: a prop through a bridge deck is in the way, one under the
## deck and above the karts of the road below is not.
func blocks_level(h: float, y_lo: float, y_hi: float, clear: float, flat: float) -> bool:
	if y_lo >= h + clear:
		return false
	if h - data.ground_y >= data.pillar_min_height:
		return y_hi > h - data.deck_thickness
	return y_hi > h + flat


## Like [method excess_at], but only roads that a piece spanning heights [param y_lo]..[param y_hi]
## is in the way of count (see [method blocks_level]; centreline heights). INF when none does.
func excess_at_level(p: Vector2, y_lo: float, y_hi: float, clear: float, flat: float) -> float:
	var best: float = INF
	var roads: Array[Path] = [main]
	roads.append_array(branches)
	var raised: float = data.ground_y + data.pillar_min_height
	for path in roads:
		# Ground-level roads (centreline below `raised`) and raised ones have different bands.
		var lo_a: float = y_lo - clear
		var bands: Array[Vector2] = [Vector2(lo_a, minf(raised, y_hi - flat)),
				Vector2(maxf(lo_a, raised), y_hi + data.deck_thickness)]
		for band in bands:
			if band.x > band.y:
				continue
			var h: Hit = path.nearest_filtered(p, band.x, band.y)
			if h != null:
				best = minf(best, h.excess)
	return best


## Highest road surface point of the track (meters; about 0 on a flat track).
func max_surface_height() -> float:
	var top: float = 0.0
	var roads: Array[Path] = [main]
	roads.append_array(branches)
	for path in roads:
		for i in path.points.size():
			top = maxf(top, path.y[i] + (path.half[i] + path.curb) * absf(tan(path.bank[i])))
	return top


## Story 008 part 3 (chase camera): height of whatever is under a point at [param p] seen from
## [param y_ref] (the followed kart's height): the road surface at that level when [param p] is
## on its deck, else the highest deck under it no higher than level_separation above y_ref, else
## the ground.
func floor_under(p: Vector2, y_ref: float) -> float:
	var q: Query = query(p, -1, y_ref)
	return maxf(q.support, data.ground_y)


## Story 008 part 3 (chase camera): underside height (surface - deck_thickness) of the lowest road
## deck over [param p] that is more than level_separation above [param y_ref] and whose corridor
## (plus [param margin]) contains p; INF when none (open sky).
func deck_above(p: Vector2, y_ref: float, margin: float) -> float:
	var best: float = INF
	var roads: Array[Path] = [main]
	roads.append_array(branches)
	for path in roads:
		if not path.bounds.has_point(p):
			continue
		var h: Hit = path.nearest_filtered(p, y_ref + data.level_separation, INF)
		if h == null or h.excess > margin:
			continue
		var a: Vector2 = path.points[h.seg]
		var b: Vector2 = path.points[(h.seg + 1) % path.points.size()]
		var lat: float = (p - a.lerp(b, h.t)).dot(Vector2(-(b - a).y, (b - a).x).normalized()) if a != b else 0.0
		best = minf(best, path.surface_y(h.seg, h.t, lat) - data.deck_thickness)
	return best


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


## Unit normal of a road surface with direction [param tangent] (x, z), rise per meter
## [param slope] along it and bank [param bank] (radians, positive = banked into a left turn).
static func surface_normal_of(tangent: Vector2, slope: float, bank: float) -> Vector3:
	var side: Vector2 = Vector2(-tangent.y, tangent.x)
	var k: float = tan(bank)
	return Vector3(-slope * tangent.x - k * side.x, 1.0, -slope * tangent.y - k * side.y).normalized()


## Height of the MAIN centerline at main-loop distance [param s] (wraps).
func height_at(s: float) -> float:
	var st: Vector2 = main.seg_t_at(s)
	return main.height_at(int(st.x), st.y)


## Bank (radians, positive = left-turn bank) of the MAIN road at main-loop distance [param s].
func bank_at(s: float) -> float:
	var st: Vector2 = main.seg_t_at(s)
	return main.bank_at(int(st.x), st.y)


## Slope angle (radians, positive = climbing) of the MAIN road at main-loop distance [param s].
func slope_angle_at(s: float) -> float:
	var st: Vector2 = main.seg_t_at(s)
	return atan(main.slope_at(int(st.x), st.y))


## Surface height of road [param path_index] under the point [param p] (nearest point of that
## road, whatever its corridor; lateral clamped to road plus curb).
func surface_height_on(path_index: int, p: Vector2) -> float:
	var path: Path = path_of(path_index)
	var h: Hit = path.nearest(p, -1, 0)
	var a: Vector2 = path.points[h.seg]
	var b: Vector2 = path.points[(h.seg + 1) % path.points.size()]
	var lateral: float = (p - a.lerp(b, h.t)).dot(Vector2(-(b - a).y, (b - a).x).normalized()) if a != b else 0.0
	return path.surface_y(h.seg, h.t, lateral)


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


## Road surface height (Y) at item-box spot [param i]: the main road at the spot's distance and
## sideways offset, with its bank and any ramp (story 008 part 3). The spot is on the main loop,
## so where the loop crosses itself it is the level of that stretch, not the road above or below.
func item_box_height(i: int) -> float:
	var spot: Vector2 = data.item_box_spots[i]
	var st: Vector2 = main.seg_t_at(spot.x)
	return main.surface_y(int(st.x), st.y, spot.y) + _ramp_rise(MAIN_PATH, fposmod(spot.x, length), spot.y).x


## Unit surface normal of the main road at item-box spot [param i] (its slope and bank).
func item_box_normal(i: int) -> Vector3:
	var spot: Vector2 = data.item_box_spots[i]
	var st: Vector2 = main.seg_t_at(spot.x)
	return surface_normal_of(main.tangent_at(spot.x), main.slope_at(int(st.x), st.y), main.bank_at(int(st.x), st.y))


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
## point's own query if known, is checked first. With a height [param y] (story 008) only a road
## whose surface there is within data.level_separation of it counts: a bridge high above a kart
## in the water does not hold it up. NAN = any height (flat behavior).
func on_surface(p: Vector2, q: Query = null, y: float = NAN) -> bool:
	var leveled: bool = not is_nan(y)
	if q != null:
		var own: Path = path_of(q.path)
		if q.distance <= q.half_width + own.curb and (not leveled or absf(q.height - y) <= data.level_separation):
			return true
	var roads: Array[Path] = [main]
	roads.append_array(branches)
	for path in roads:
		if q != null and path.index == q.path and not leveled:
			continue
		if not path.bounds.has_point(p):
			continue
		var h: Hit = path.nearest(p, -1, 0) if not leveled else path.nearest_filtered(p, y - data.level_separation, y + data.level_separation)
		if h != null and h.dist <= path.half_at(h.seg, h.t) + path.curb:
			return true
	return false


## True when a kart center at [param p] is in a hazard: inside an outline and on no road. A
## speed-gated hazard (min_cross_speed > 0) counts even over a road deck, but not while
## [param speed] reaches its threshold. [param y]: see [method hazard_index].
func in_hazard(p: Vector2, q: Query = null, speed: float = 0.0, y: float = NAN) -> bool:
	return hazard_index(p, q, speed, y) >= 0


## Index of the hazard that [param p] is in (see [method in_hazard]), or -1. With the kart's
## height [param y] (story 008 part 3) a hazard counts only when the kart is at or below its
## surface (TrackHazard.surface_height + data.hazard_sink_margin): a kart on a bridge or flying
## over the water is safe, one that falls into it sinks; and only a road at the kart's level
## keeps it out. NAN = no height test (flat behavior, the sound and track tools).
func hazard_index(p: Vector2, q: Query = null, speed: float = 0.0, y: float = NAN) -> int:
	var surface: int = -1  # lazily: 0 off the road, 1 on a road
	for i in hazard_polygons.size():
		if not hazard_bounds[i].has_point(p) or not Geometry2D.is_point_in_polygon(p, hazard_polygons[i]):
			continue
		if not is_nan(y) and y > hazard_heights[i] + data.hazard_sink_margin:
			continue
		if hazard_gates[i] > 0.0:
			if speed < hazard_gates[i]:
				return i
			continue
		if surface < 0:
			surface = 1 if on_surface(p, q, y) else 0
		if surface == 0:
			return i
	return -1


## True when [param p] is inside a hazard outline whose surface is below [param y] (a kart in the
## air over water that has not reached it yet: it falls in rather than being caught by the fall
## respawn). Story 008 part 3.
func hazard_below(p: Vector2, y: float) -> bool:
	for i in hazard_polygons.size():
		if hazard_bounds[i].has_point(p) and Geometry2D.is_point_in_polygon(p, hazard_polygons[i]) 				and y > hazard_heights[i] + data.hazard_sink_margin:
			return true
	return false


## Index of the boost pad under [param p], or -1. With a height [param y] (story 008 part 3) a pad
## counts only for a kart on its level (within data.pad_height_tolerance of the road height at the
## pad's center), not one on a bridge above it or a road below it. NAN = no height test.
func pad_at(p: Vector2, y: float = NAN) -> int:
	for i in pad_centers.size():
		var d: Vector2 = p - pad_centers[i]
		var t: Vector2 = pad_dirs[i]
		var hl: Vector2 = pad_halves[i]
		if absf(d.dot(t)) <= hl.x and absf(d.cross(t)) <= hl.y 				and (is_nan(y) or absf(y - pad_heights[i]) <= data.pad_height_tolerance):
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


## Smooth profile value between [param p1] and [param p2] (the height and bank profiles): a cubic
## Hermite with Catmull-Rom tangents, limited so it never overshoots its control values (a plain
## Catmull-Rom dips below a flat stretch after a hill, which would sink the road under the ground).
## Same parameter t as the centerline spline; a control value that is a peak or a valley gets a
## flat tangent, so crests and dips land exactly on their data values.
static func catmull_rom_f(p0: float, p1: float, p2: float, p3: float, t: float) -> float:
	var d: float = p2 - p1
	var m1: float = 0.0
	var m2: float = 0.0
	if absf(d) > 0.00001:
		m1 = clampf((p2 - p0) * 0.5, minf(0.0, 3.0 * d), maxf(0.0, 3.0 * d))
		m2 = clampf((p3 - p1) * 0.5, minf(0.0, 3.0 * d), maxf(0.0, 3.0 * d))
		if m1 * d < 0.0 or (p1 - p0) * d <= 0.0:
			m1 = 0.0
		if m2 * d < 0.0 or (p3 - p2) * d <= 0.0:
			m2 = 0.0
	var t2: float = t * t
	var t3: float = t2 * t
	return (2.0 * t3 - 3.0 * t2 + 1.0) * p1 + (t3 - 2.0 * t2 + t) * m1 + (-2.0 * t3 + 3.0 * t2) * p2 + (t3 - t2) * m2


## Catmull-Rom spline point between [param p1] and [param p2].
static func catmull_rom(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var t2: float = t * t
	var t3: float = t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
			+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)
