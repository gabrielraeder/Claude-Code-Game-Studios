extends SceneTree
## Spline-vs-mesh equivalence (core-rebuild story 008; architecture.md Test Harness). DEBUG TOOL,
## not game code. Retired at A3 (story 065).
##
## Compares the generator-baked test mesh (tools/legacy_test_bake.gd from the extractor's JSON,
## queried through CollisionBootCheck.checked_query and the public CollisionQuery API only) with the
## frozen 2.5D TrackModel of Castle Circuit, which this tool runs directly (ADR-0001 section 9 as
## amended: tools may run the frozen game). About 100k deterministic samples (R2 low-discrepancy
## sequence, no randomness, no clock in any number):
##   - height and surface id: DECK_SAMPLES on the road decks (area-weighted per path) plus
##     ZONE_SAMPLES inside the off-road zones. Truth: TrackModel.query(p, -1, y).support (what holds
##     a kart up there) and the frozen surface (ramp rise > 0 -> trick_ramp, pad_at -> boost_pad,
##     surface_type_at -> its kind, else road). Mesh: cast_ground straight down from RAY_START over
##     the true height.
##   - wall offset: every WALL_SAMPLE_STEP m along every path, both sides. Truth: the frozen
##     barrier along the sweep ray (_frozen_barrier: where the frozen road's own excess turns
##     positive, which is where its lateral clamp stops a kart). Mesh: sweep_walls from the centre
##     line out along the segment normal.
## Samples in a named band (see the constants) are reported in their own rows and are not held to
## the tolerances; every other sample is. Writes the report to REPORT_PATH and prints it.
##
## Run (after the extractor):
##   godot --headless --path . -s res://tools/spline_mesh_equivalence.gd
## Exit 0 when every held sample is within tolerance, 1 otherwise (2 when an input is missing).
## [codeblock]
## # build/legacy_tracks/castle_circuit.json must exist (tools/legacy_track_export.gd).
## # Output: production/qa/evidence/core-rebuild-story-008/equivalence_report.md
## [/codeblock]

const Bake = preload("res://tools/legacy_test_bake.gd")

const TRACK_ID: String = "castle_circuit"
const JSON_PATH: String = "res://build/legacy_tracks/castle_circuit.json"
const REPORT_PATH: String = "res://production/qa/evidence/core-rebuild-story-008/equivalence_report.md"
## Sample counts (about 100k height / surface samples in total, architecture.md Test Harness).
const DECK_SAMPLES: int = 90000
const ZONE_SAMPLES: int = 10000
## Most R2 candidates tried per accepted zone sample.
const ZONE_TRIES: int = 20
## R2 sequence constants (1/phi2 and 1/phi2^2, phi2 the plastic number): a deterministic
## low-discrepancy 2D sequence. Math constants, not tuning.
const R2_A1: float = 0.7548776662466927
const R2_A2: float = 0.5698402909980532
## Ground cast: from RAY_START m over the true height, RAY_START + RAY_DROP m down.
const RAY_START: float = 1.0
const RAY_DROP: float = 4.0
## Wall samples: step along each path (m), sweep height over the road surface (m), sweep radius
## (m) and how far past the true wall the sweep reaches (m).
const WALL_SAMPLE_STEP: float = 0.25
const WALL_PROBE_LIFT: float = 0.5
const WALL_PROBE_RADIUS: float = 0.01
const WALL_SWEEP_EXTRA: float = 1.0
## A frozen wall point this far (m) inside another road's corridor at its level is a junction
## (the frozen query lets the kart change road there; the bake drops that wall).
const JUNCTION_EPS: float = 0.05
## TOLERANCES (story 008 sets them; rationale in the report):
## height |mesh - spline| (m), wall offset |mesh - spline| (m), and the surface-boundary band (m)
## inside which a surface id may differ.
const HEIGHT_TOL: float = 0.05
const WALL_TOL: float = 0.05
const SURFACE_BAND: float = 0.25
## Height band (m) around height steps of the frozen model (a ramp's edges, a deck edge over a
## drop), where a sample's side of the step can differ.
const HEIGHT_BAND: float = 0.25
## Frozen wall truth: march step (m) and bisection steps along the sweep ray to where the frozen
## road's own excess (TrackModel.Path.nearest, query window) turns positive.
const WALL_MARCH: float = 0.25
const WALL_BISECT: int = 16
## The held rows of the first report (2026-11-22, before the bake fixes), for the before/after
## table: [row, samples, out of tolerance, misses, max].
const BASELINE: Array = [
	["height: held", 98120, 146, 1, 0.2212], ["surface: held", 97033, 1, 0, 1.0], ["wall: held", 9234, 146, 10, 0.5147],
]
## Gate-time search: ticks scanned for a time when every gate is down and idle.
const SIM_DT: float = 1.0 / 60.0
const GATE_SCAN_TICKS: int = 3600
## Case-by-case proof of a held failure: the frozen value is probed CASE_PROBE m each side of the
## sample (4 directions for a height, along the road for a wall); a jump above the row's tolerance
## inside that distance is a frozen discontinuity there, otherwise the failure is a bake error.
const CASE_PROBE: float = 0.01
## Worst samples listed per row.
const WORST_LISTED: int = 10


## Error statistics of one report row.
class Row:
	extends RefCounted
	var name: String = ""
	var held: bool = true
	var tol: float = 0.0
	var errors: PackedFloat32Array = PackedFloat32Array()
	var fails: int = 0
	var misses: int = 0
	var worst: Array = []  # [error, text], largest finite errors (or mismatches)
	var missed: PackedStringArray = PackedStringArray()  # first misses

	## Per worst entry, the probe data for the case-by-case proof: [kind, p (Vector2), y_ref, extra].
	var cases: Dictionary = {}

	func add_case(where: String, data: Array) -> void:
		cases[where] = data

	func add(err: float, where: String) -> void:
		if not is_finite(err):
			misses += 1
			fails += 1
			if missed.size() < WORST_LISTED:
				missed.append(where)
			return
		var e: float = absf(err)
		errors.append(e)
		if e > tol:
			fails += 1
		_keep(e, "%s (signed %+.4f)" % [where, err])

	func add_match(ok: bool, where: String) -> void:
		errors.append(0.0 if ok else 1.0)
		if not ok:
			fails += 1
			if worst.size() < WORST_LISTED:
				worst.append([1.0, where])

	func _keep(e: float, where: String) -> void:
		if worst.size() < WORST_LISTED or e > worst[worst.size() - 1][0]:
			worst.append([e, where])
			worst.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
			if worst.size() > WORST_LISTED:
				worst.resize(WORST_LISTED)

	func count() -> int:
		return errors.size() + misses

	func pct(q: float) -> float:
		if errors.is_empty():
			return 0.0
		var s: PackedFloat32Array = errors.duplicate()
		s.sort()
		return s[clampi(int(ceil(q * float(s.size()))) - 1, 0, s.size() - 1)]

	func mean() -> float:
		if errors.is_empty():
			return 0.0
		var t: float = 0.0
		for e in errors:
			t += e
		return t / float(errors.size())


var _model: TrackModel
var _surfaces: SurfaceSet
var _query: CollisionQuery
var _cursor: QueryCursor = QueryCursor.new()
var _ghit: GroundHit = GroundHit.new()
var _whit: WallHit = WallHit.new()
var _t_eval: float = 0.0
var _boundary_polys: Array[PackedVector2Array] = []
var _boundary_rects: Array[Rect2] = []
var _gate_spans: Array[Vector3] = []  # (path, from, to) of the drawbridge-style gate decks


func _initialize() -> void:
	quit(_run())


func _run() -> int:
	var data: TrackData = TrackLibrary.load_track(TRACK_ID)
	var doc: Dictionary = Bake.load_doc(JSON_PATH)
	_surfaces = SurfaceSet.load_checked(SurfaceSet.CORE_PATH)
	var walls: WallAttrSet = WallAttrSet.load_checked(WallAttrSet.CORE_PATH)
	if data == null or doc.is_empty() or _surfaces == null or walls == null:
		print("MISSING input: track %s, JSON %s (run tools/legacy_track_export.gd), core registries" % [TRACK_ID, JSON_PATH])
		return 2
	_model = TrackModel.new(data)
	var hazards: HazardManager = HazardManager.new()
	hazards.setup(_model)
	_t_eval = _gate_time(hazards)
	hazards.free()
	var baked: Bake.BakeResult = Bake.bake_doc(doc, _surfaces, walls)
	if not baked.problem.is_empty():
		print("FAIL bake: %s" % baked.problem)
		return 1
	var checked: CollisionBootCheck.CheckedQuery = CollisionBootCheck.checked_query(baked.data, _surfaces, walls, Bake.PROBE_MAX_DROP)
	if not checked.problem.is_empty():
		print("FAIL checked_query: %s" % checked.problem)
		return 1
	_query = checked.query
	_build_boundaries()
	var rows: Dictionary = {}
	for spec in [
		["height: held", true, HEIGHT_TOL], ["height: ramp-edge band", false, HEIGHT_TOL],
		["height: deck-edge band (open edge)", false, HEIGHT_TOL], ["height: drawbridge deck (mover)", false, HEIGHT_TOL],
		["surface: held", true, 0.0], ["surface: boundary band", false, 0.0], ["surface: drawbridge deck (mover)", false, 0.0],
		["wall: held", true, WALL_TOL], ["wall: wall opening or its transition segment", false, WALL_TOL],
		["wall: junction (inside another corridor)", false, WALL_TOL], ["wall: no frozen barrier on the ray", false, WALL_TOL],
	]:
		var r: Row = Row.new()
		r.name = spec[0]
		r.held = spec[1]
		r.tol = spec[2]
		rows[r.name] = r
	var by_source: Dictionary = {}
	var n_deck: int = _deck_samples(rows, by_source)
	var n_zone: int = _zone_samples(rows, by_source)
	var n_wall: int = _wall_samples(rows)
	_query.dispose()
	var held_fail: int = 0
	for r: Row in rows.values():
		if r.held:
			held_fail += r.fails
	var text: String = _report(rows, by_source, baked, n_deck, n_zone, n_wall, held_fail)
	print(text)
	var f: FileAccess = FileAccess.open(ProjectSettings.globalize_path(REPORT_PATH), FileAccess.WRITE)
	if f == null:
		print("FAIL cannot write %s" % REPORT_PATH)
		return 1
	f.store_string(text)
	f.close()
	return 0 if held_fail == 0 else 1


## First tick time at which every gate is idle and fully down (progress 0).
func _gate_time(hazards: HazardManager) -> float:
	for k in GATE_SCAN_TICKS:
		var t: float = float(k) * SIM_DT
		var down: bool = true
		for i in hazards.count():
			var m: TrackMover = hazards.mover(i)
			if m.kind == &"gate" and hazards.progress_at(m, t) > 0.0:
				down = false
		if down:
			return t
	return 0.0


func _build_boundaries() -> void:
	for i in _model.zone_polygons.size():
		_boundary_polys.append(_model.zone_polygons[i])
	for i in _model.pad_centers.size():
		var c: Vector2 = _model.pad_centers[i]
		var t: Vector2 = _model.pad_dirs[i]
		var h: Vector2 = _model.pad_halves[i]
		var n: Vector2 = Vector2(-t.y, t.x)
		_boundary_polys.append(PackedVector2Array([c - t * h.x - n * h.y, c + t * h.x - n * h.y, c + t * h.x + n * h.y, c - t * h.x + n * h.y]))
	for poly in _boundary_polys:
		var r: Rect2 = Rect2(poly[0], Vector2.ZERO)
		for p in poly:
			r = r.expand(p)
		_boundary_rects.append(r.grow(SURFACE_BAND))
	for m in _model.data.movers:
		if m.kind == &"gate" and m.hit_effect != &"stop":
			var pi: int = TrackModel.MAIN_PATH if m.path == &"main" else _model.branch_index(m.path)
			_gate_spans.append(Vector3(pi, m.path_from, m.path_to))


## Distance (m) from [param p] to the nearest zone or pad outline (INF when none is within the band).
func _region_edge_distance(p: Vector2) -> float:
	var best: float = INF
	for i in _boundary_polys.size():
		if not _boundary_rects[i].has_point(p):
			continue
		var poly: PackedVector2Array = _boundary_polys[i]
		for k in poly.size():
			best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, poly[k], poly[(k + 1) % poly.size()])))
	return best


## Distance (m), in the road's (along, lateral) frame, from query [param q] to the outline of the
## nearest ramp on its road (INF when none).
func _ramp_edge_distance(q: TrackModel.Query) -> float:
	var best: float = INF
	for i in _model.ramp_paths.size():
		if _model.ramp_paths[i] != q.path:
			continue
		var u: float = q.along - _model.ramp_from[i]
		if q.path == TrackModel.MAIN_PATH:
			u = wrapf(u, -_model.length * 0.5, _model.length * 0.5)
		var du: float = maxf(-u, u - _model.ramp_len[i])
		var d: float
		if _model.ramp_half[i] > 0.0:
			var dl: float = absf(q.lateral - _model.ramp_lat[i]) - _model.ramp_half[i]
			d = Vector2(maxf(du, 0.0), maxf(dl, 0.0)).length() if (du > 0.0 or dl > 0.0) else -maxf(du, dl)
		else:
			d = absf(du)
		best = minf(best, absf(d))
	return best


func _in_gate_span(q: TrackModel.Query) -> bool:
	for g in _gate_spans:
		if int(g.x) == q.path and q.along >= g.y - HEIGHT_BAND and q.along <= g.z + HEIGHT_BAND:
			return true
	return false


## The frozen surface id at [param p] for a kart held at [param h] (core ids).
func _frozen_surface(p: Vector2, h: float, q: TrackModel.Query) -> int:
	if q.ramp_rise > 0.0 and q.on_deck:
		return _surfaces.type_of(Bake.KIND_RAMP).id
	if _model.pad_at(p, h) >= 0:
		return _surfaces.type_of(Bake.KIND_PAD).id
	var t: SurfaceType = _model.surface_type_at(p, h)
	if t != null:
		return _surfaces.type_of(t.kind).id
	return _surfaces.type_of(Bake.KIND_ROAD).id


## Compares one height / surface sample at [param p] (a kart at about [param y_ref]).
func _sample(p: Vector2, y_ref: float, source: String, rows: Dictionary, by_source: Dictionary) -> void:
	var q: TrackModel.Query = _model.query(p, -1, y_ref)
	var h_true: float = q.support
	var s_true: int = _frozen_surface(p, h_true, q)
	var hit: bool = _query.cast_ground(_cursor, Vector3(p.x, h_true + RAY_START, p.y), Vector3.DOWN, RAY_START + RAY_DROP, _t_eval, _ghit)
	var err: float = _ghit.point.y - h_true if hit else INF
	var where: String = "%s at (%.2f, %.2f), path %d along %.2f lateral %.2f, spline %.3f" % [source, p.x, p.y, q.path, q.along, q.lateral, h_true]
	var reach: float = q.half_width + _model.path_of(q.path).curb
	var gate: bool = _in_gate_span(q)
	var ramp_d: float = _ramp_edge_distance(q)
	var open_edge: bool = q.wall_offset > reach + JUNCTION_EPS and absf(q.distance - reach) < HEIGHT_BAND
	var deck_edge: bool = open_edge
	var hrow: String = "height: held"
	if gate:
		hrow = "height: drawbridge deck (mover)"
	elif ramp_d < HEIGHT_BAND:
		hrow = "height: ramp-edge band"
	elif open_edge:
		hrow = "height: deck-edge band (open edge)"
	(rows[hrow] as Row).add(err, where)
	if hrow == "height: held" and is_finite(err) and absf(err) > HEIGHT_TOL:
		(rows[hrow] as Row).add_case("%s (signed %+.4f)" % [where, err], ["height", p, y_ref])
	if hrow == "height: held":
		if not by_source.has(source):
			var r: Row = Row.new()
			r.name = source
			r.tol = HEIGHT_TOL
			by_source[source] = r
		(by_source[source] as Row).add(err, where)
	var srow: String = "surface: held"
	if gate:
		srow = "surface: drawbridge deck (mover)"
	elif minf(_region_edge_distance(p), ramp_d) < SURFACE_BAND or deck_edge:
		srow = "surface: boundary band"
	var s_mesh: int = _ghit.surface_id if hit else -1
	(rows[srow] as Row).add_match(s_mesh == s_true, "%s: spline id %d, mesh id %d" % [where, s_true, s_mesh])


func _deck_samples(rows: Dictionary, by_source: Dictionary) -> int:
	var roads: Array[TrackModel.Path] = [_model.main]
	roads.append_array(_model.branches)
	var areas: PackedFloat64Array = PackedFloat64Array()
	var total: float = 0.0
	for road in roads:
		var w: float = 0.0
		for i in road.half.size():
			w += 2.0 * (road.half[i] + road.curb)
		var a: float = road.length * w / float(road.half.size())
		areas.append(a)
		total += a
	var n_all: int = 0
	for ri in roads.size():
		var road: TrackModel.Path = roads[ri]
		var n: int = int(round(float(DECK_SAMPLES) * areas[ri] / total))
		var source: String = "deck %s" % ("main" if road.index < 0 else String(road.id))
		for k in n:
			var u: float = fposmod(0.5 + float(k) * R2_A1, 1.0)
			var v: float = fposmod(0.5 + float(k) * R2_A2, 1.0)
			var along: float = u * road.length
			var st: Vector2 = road.seg_t_at(along)
			var seg: int = int(st.x)
			var ab: Vector2 = road.points[(seg + 1) % road.points.size()] - road.points[seg]
			var nrm: Vector2 = Vector2(-ab.y, ab.x).normalized()
			var reach: float = road.half_at(seg, st.y) + road.curb
			var lat: float = (2.0 * v - 1.0) * reach
			var p: Vector2 = road.point_at(along) + nrm * lat
			_sample(p, road.surface_y(seg, st.y, lat), source, rows, by_source)
			n_all += 1
	return n_all


func _zone_samples(rows: Dictionary, by_source: Dictionary) -> int:
	var ground: Array[int] = []
	for zi in _model.zone_polygons.size():
		if not _model.zone_types[zi].on_road:
			ground.append(zi)
	if ground.is_empty():
		return 0
	var n_all: int = 0
	@warning_ignore("integer_division")
	var per_zone: int = ZONE_SAMPLES / ground.size()
	for zi in ground:
		var b: Rect2 = _model.zone_bounds[zi]
		var poly: PackedVector2Array = _model.zone_polygons[zi]
		var got: int = 0
		var k: int = 0
		while got < per_zone and k < per_zone * ZONE_TRIES:
			var p: Vector2 = b.position + b.size * Vector2(fposmod(0.5 + float(k) * R2_A1, 1.0), fposmod(0.5 + float(k) * R2_A2, 1.0))
			k += 1
			if not Geometry2D.is_point_in_polygon(p, poly):
				continue
			_sample(p, _model.zone_height_at(zi, p), "zone %s" % _model.zone_ids[zi], rows, by_source)
			got += 1
			n_all += 1
	return n_all


func _wall_samples(rows: Dictionary) -> int:
	var roads: Array[TrackModel.Path] = [_model.main]
	roads.append_array(_model.branches)
	var sep: float = _model.data.level_separation
	var n_all: int = 0
	for road in roads:
		var steps: int = int(floor(road.length / WALL_SAMPLE_STEP))
		for k in steps:
			var along: float = float(k) * WALL_SAMPLE_STEP
			var st: Vector2 = road.seg_t_at(along)
			var seg: int = int(st.x)
			var ab: Vector2 = road.points[(seg + 1) % road.points.size()] - road.points[seg]
			if ab.length_squared() <= 0.0:
				continue
			var nrm: Vector2 = Vector2(-ab.y, ab.x).normalized()
			var c: Vector2 = road.point_at(along)
			var yc: float = road.height_at(seg, st.y)
			for side in [1, -1]:
				var w_sample: float = road.wall_at(seg, st.y, side)
				var w: float = _frozen_barrier(road, c, nrm * float(side), seg, w_sample + WALL_SWEEP_EXTRA)
				var dir: Vector2 = nrm * float(side)
				var where: String = "path %d along %.2f side %+d, frozen barrier %.3f (wall_at %.3f)" % [road.index, along, side, w, w_sample]
				var row: String = "wall: held"
				var bit: int = 1 if side > 0 else 2
				var np: int = road.points.size()
				if not road.opening.is_empty() and ((road.opening[seg] & bit) != 0 or (road.opening[(seg + 1) % np] & bit) != 0
						or (road.opening[(seg - 1 + np) % np] & bit) != 0):
					row = "wall: wall opening or its transition segment"
				elif not is_finite(w):
					row = "wall: no frozen barrier on the ray"
				elif _junction(road, roads, c + dir * w, yc, sep):
					row = "wall: junction (inside another corridor)"
				var from: Vector3 = Vector3(c.x, road.surface_y(seg, st.y, 0.0) + WALL_PROBE_LIFT, c.y)
				var far: float = (w if is_finite(w) else w_sample) + WALL_SWEEP_EXTRA
				var to_xz: Vector2 = c + dir * far
				var to: Vector3 = Vector3(to_xz.x, road.surface_y(seg, st.y, far * float(side)) + WALL_PROBE_LIFT, to_xz.y)
				var err: float = INF
				if _query.sweep_walls(_cursor, from, to, WALL_PROBE_RADIUS, _t_eval, _whit) and not _whit.started_inside:
					err = (Vector2(_whit.point.x, _whit.point.z) - c).dot(dir) - w
					where += ", mesh hit %s attr %d mover %d" % [_whit.point, _whit.wall_attr, _whit.collider_id]
				elif _whit.started_inside:
					where += ", started inside (attr %d mover %d)" % [_whit.wall_attr, _whit.collider_id]
				(rows[row] as Row).add(err, where)
				if row == "wall: held" and is_finite(err) and absf(err) > WALL_TOL:
					(rows[row] as Row).add_case("%s (signed %+.4f)" % [where, err], ["wall", road.index, along, side])
				n_all += 1
	return n_all


## Distance (m) from centre-line point [param c] along unit [param dir] to the frozen barrier: where
## the road's own excess (nearest centre-line point within the query window, TrackModel.Path.nearest,
## minus its wall offset there) first turns positive. INF when it stays inside up to [param reach].
## This is where the frozen kart's lateral clamp stops it, also on the inside of a turn or a taper.
func _frozen_barrier(road: TrackModel.Path, c: Vector2, dir: Vector2, seg: int, reach: float) -> float:
	var window: int = _model.data.query_window
	var prev: float = 0.0
	var s: float = WALL_MARCH
	while s <= reach:
		if road.nearest(c + dir * s, seg, window).excess > 0.0:
			var lo: float = prev
			var hi: float = s
			for it in WALL_BISECT:
				var mid: float = (lo + hi) * 0.5
				if road.nearest(c + dir * mid, seg, window).excess > 0.0:
					hi = mid
				else:
					lo = mid
			return (lo + hi) * 0.5
		prev = s
		s += WALL_MARCH
	return INF


func _junction(road: TrackModel.Path, roads: Array[TrackModel.Path], wp: Vector2, y: float, sep: float) -> bool:
	for other in roads:
		if other == road or not other.bounds.has_point(wp):
			continue
		var h: TrackModel.Hit = other.nearest_filtered(wp, y - sep, y + sep)
		if h != null and h.excess < -JUNCTION_EPS:
			return true
	return false


## The case-by-case verdict of worst entry [param where] of row [param r] (held rows only): the
## largest frozen jump within CASE_PROBE m, and whether it exceeds the row's tolerance.
func _case_text(r: Row, where: String) -> String:
	if not r.cases.has(where):
		return ""
	var c: Array = r.cases[where]
	var jump: float = 0.0
	if c[0] == "height":
		var p: Vector2 = c[1]
		var base: float = _model.query(p, -1, c[2]).support
		for d in [Vector2(CASE_PROBE, 0.0), Vector2(-CASE_PROBE, 0.0), Vector2(0.0, CASE_PROBE), Vector2(0.0, -CASE_PROBE)]:
			jump = maxf(jump, absf(_model.query(p + d, -1, c[2]).support - base))
	else:
		var road: TrackModel.Path = _model.path_of(c[1])
		var vals: PackedFloat32Array = PackedFloat32Array()
		for da in [-CASE_PROBE, 0.0, CASE_PROBE]:
			var along: float = float(c[2]) + da
			var st: Vector2 = road.seg_t_at(along)
			var seg: int = int(st.x)
			var ab: Vector2 = road.points[(seg + 1) % road.points.size()] - road.points[seg]
			var nrm: Vector2 = Vector2(-ab.y, ab.x).normalized()
			vals.append(_frozen_barrier(road, road.point_at(along), nrm * float(c[3]), seg, road.wall_at(seg, st.y, c[3]) + WALL_SWEEP_EXTRA))
		jump = maxf(absf(vals[0] - vals[1]), absf(vals[2] - vals[1]))
	var verdict: String = "FROZEN DISCONTINUITY" if jump > r.tol else "bake error (frozen smooth here)"
	return " -> frozen jump within %.2f m: %.4f -> %s" % [CASE_PROBE, jump, verdict]


func _report(rows: Dictionary, by_source: Dictionary, baked: Bake.BakeResult, n_deck: int, n_zone: int,
		n_wall: int, held_fail: int) -> String:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("# Spline-vs-mesh equivalence: %s (core-rebuild story 008)" % TRACK_ID)
	lines.append("")
	lines.append("Generated by `tools/spline_mesh_equivalence.gd` (headless, deterministic: R2 sample sequence, no clock).")
	lines.append("Spline = the frozen `TrackModel` run live. Mesh = `tools/legacy_test_bake.gd` from `%s`, queried through" % JSON_PATH.trim_prefix("res://"))
	lines.append("`CollisionBootCheck.checked_query` and the public `cast_ground` / `sweep_walls` API at t = %.4f s (every gate down)." % _t_eval)
	lines.append("")
	lines.append("Samples: %d deck + %d zone = %d height / surface samples; %d wall samples (every %.2f m, both sides, every path)." % [n_deck, n_zone, n_deck + n_zone, n_wall, WALL_SAMPLE_STEP])
	lines.append("Bake: %s" % JSON.stringify(baked.stats))
	for note in baked.notes:
		lines.append("Bake note: %s" % note)
	lines.append("")
	lines.append("## Tolerances (set by this story)")
	lines.append("")
	lines.append("- Height: |mesh - spline| <= %.3f m on every held sample. The bake puts every deck vertex exactly on the frozen surface, so the only error is the planar triangle between vertices <= %.1f m apart against the frozen bank and corner fans; %.0f cm is under a tenth of the kart's suspension travel and far under the 3 m level separation." % [HEIGHT_TOL, Bake.ALONG_STEP, HEIGHT_TOL * 100.0])
	lines.append("- Surface id: must match on every held sample, i.e. every sample farther than %.2f m from a zone, pad or ramp outline. The bake clips deck triangles exactly to zone and pad outlines, so only the cross-section interpolation (lerped mitred normals vs the frozen perpendicular projection) and the ramp wedge cells can move an outline; %.2f m is a quarter of a kart width." % [SURFACE_BAND, SURFACE_BAND])
	lines.append("- Wall offset: |mesh - spline| <= %.3f m on every held sample. The mesh wall vertices sit on the frozen offset; the chord between mitred vertices <= %.1f m apart deviates by w(1 - cos) of the half turn per sample." % [WALL_TOL, Bake.WALL_STEP])
	lines.append("- Wall probe: a %.2f m sphere. It measures the wall offset along the sweep ray, not kart contact: a 0.1 m sphere touches a wall that runs nearly along the ray (a steep taper) with its side, up to r / sin(angle) early (about 0.32 m at 17 degrees on the drawbridge), which is the probe, not the mesh." % WALL_PROBE_RADIUS)
	lines.append("- Not held (own rows): samples within %.2f m of a frozen height step (ramp edges; a deck edge over an open drop), the drawbridge deck (a rigid mover box in the mesh by design, a road-following deck in the frozen game), wall openings (ADR-0002: an opening is the absence of wall) and walls inside another road's corridor (the frozen query lets the kart change road there, so that wall is not a barrier)." % HEIGHT_BAND)
	lines.append("")
	lines.append("## Results")
	lines.append("")
	lines.append("| Row | Held | Samples | Out of tolerance | Misses | Max | p99 | p99.9 | Mean |")
	lines.append("|---|---|---|---|---|---|---|---|---|")
	for r: Row in rows.values():
		lines.append("| %s | %s | %d | %d | %d | %.4f | %.4f | %.4f | %.5f |" % [r.name, "yes" if r.held else "no", r.count(), r.fails, r.misses, r.pct(1.0), r.pct(0.99), r.pct(0.999), r.mean()])
	lines.append("")
	lines.append("### Before / after the bake fixes (held rows)")
	lines.append("")
	lines.append("Before = the first report (2026-11-22). Row changes since: the walled deck-edge band is gone (those samples are held now), and the wall truth is the frozen barrier along the ray instead of wall_at at the sample.")
	lines.append("")
	lines.append("| Row | Before: samples | Before: out | Before: misses | Before: max | After: samples | After: out | After: misses | After: max |")
	lines.append("|---|---|---|---|---|---|---|---|---|")
	for b in BASELINE:
		var r: Row = rows[b[0]]
		lines.append("| %s | %d | %d | %d | %.4f | %d | %d | %d | %.4f |" % [b[0], b[1], b[2], b[3], b[4], r.count(), r.fails, r.misses, r.pct(1.0)])
	lines.append("")
	lines.append("Held worst entries carry a case-by-case verdict: the frozen value probed %.2f m each side; a jump above the row tolerance there is the frozen game's own discontinuity, otherwise a bake error." % CASE_PROBE)
	lines.append("")
	lines.append("Surface rows: error 1 = id mismatch, so Max 1 means at least one mismatch and Mean is the mismatch rate.")
	lines.append("")
	lines.append("### Held height samples by source")
	lines.append("")
	lines.append("| Source | Samples | Out of tolerance | Misses | Max | p99 | Mean |")
	lines.append("|---|---|---|---|---|---|---|")
	var keys: Array = by_source.keys()
	keys.sort()
	for key in keys:
		var r: Row = by_source[key]
		lines.append("| %s | %d | %d | %d | %.4f | %.4f | %.5f |" % [r.name, r.count(), r.fails, r.misses, r.pct(1.0), r.pct(0.99), r.mean()])
	lines.append("")
	lines.append("### Worst samples per row")
	lines.append("")
	for r: Row in rows.values():
		if r.worst.is_empty() and r.missed.is_empty():
			continue
		lines.append("- **%s**" % r.name)
		for w in r.worst:
			lines.append("  - %.4f: %s%s" % [w[0], w[1], _case_text(r, w[1])])
		for m in r.missed:
			lines.append("  - miss: %s" % m)
	lines.append("")
	lines.append("## Observation")
	lines.append("")
	lines.append("Held samples out of tolerance: %d." % held_fail)
	return "\n".join(lines) + "\n"
