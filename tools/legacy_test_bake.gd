extends SceneTree
## Generator-baked test mesh (core-rebuild story 008; ADR-0004 section 15 consumer 1, collision
## half). DEBUG TOOL, not game code. Retired at A3 (story 065).
##
## Turns the neutral JSON of tools/legacy_track_export.gd into a TrackCollisionData: ground
## triangles with core surface ids, one wall shape per core wall attribute, and MoverDefs. It reads
## only that JSON and the core registries; it never loads the frozen game. Every number below is a
## named bake constant (tuning-values.md allows that in tools/).
##
## Run (after the extractor):
##   godot --headless --path . -s res://tools/legacy_test_bake.gd -- [--in=DIR] [--tracks=a,b]
## For each track: bakes, builds the query through CollisionBootCheck.checked_query (the only
## construction path; it runs the story-006 load checks), does the same for the mirrored data,
## disposes both and prints PASS / FAIL lines. Exit 0 when every track passes, else 1.
## From code (tests, tools/spline_mesh_equivalence.gd), the static API:
## [codeblock]
## const Bake = preload("res://tools/legacy_test_bake.gd")
## var doc: Dictionary = Bake.load_doc("res://build/legacy_tracks/castle_circuit.json")
## var surfaces: SurfaceSet = SurfaceSet.load_checked(SurfaceSet.CORE_PATH)
## var walls: WallAttrSet = WallAttrSet.load_checked(WallAttrSet.CORE_PATH)
## var baked: Bake.BakeResult = Bake.bake_doc(doc, surfaces, walls)
## assert(baked.problem.is_empty(), baked.problem)
## var checked: CollisionBootCheck.CheckedQuery = CollisionBootCheck.checked_query(baked.data,
##         surfaces, walls, Bake.PROBE_MAX_DROP)
## # ... queries ...
## checked.query.dispose()
## [/codeblock]
##
## Model (how the frozen 2.5D track becomes triangles):
##   - Road decks: every path's samples become cross-sections (mitre vectors, lerped between), edges
##     fitted to the frozen reach, EDGE_SKIRT more under a wall; heights from each cell's own
##     segment (so the inside-of-turn step at a mitre line is kept); where two decks overlap, each is
##     cut on the frozen road-ownership line;
##     cut into cells of at most ALONG_STEP x LAT_STEP m from -(half + curb) to +(half + curb). Each
##     vertex height is the frozen formula at the vertex's own nearest centre-line point
##     (y + clamp(lateral) x tan(bank)). The deck under a drawbridge gate is left out: the gate's
##     deck is a mover.
##   - Surface ids on the deck: each deck triangle is clipped exactly (Geometry2D) against the boost
##     pads (boost_pad) and then the surface zones in data order (the zone's kind), at the
##     triangle's level; the rest is road.
##   - Ramps: a wedge (trick_ramp) on top of the deck, RAMP_LIFT above it at its foot, rising to the
##     lip, with a lip face and side faces.
##   - Off-road zones: their own triangles at the frozen zone heights.
##   - Floor: one quad at TrackData.ground_y under everything (road id: the neutral "no surface").
##   - Walls: each path side at the frozen barrier (_barrier: where the frozen lateral clamp
##     stops a kart, which also closes turns tighter than the offset), from WALL_BELOW under the edge to
##     WALL_HEIGHT over it (down to the floor where the wall stands past an open edge), facing the
##     road. Absent in wall openings (ADR-0002: an opening is the absence of wall), and where it
##     lies inside another road's corridor at the same level (the frozen query lets the kart change
##     road there). Zone fence edges are walls too, facing into the zone, except on a road deck or in
##     a branch corridor. A road's wall attribute is the core attribute whose scrape_drag_mult is
##     nearest to its frozen wall_drag_mult.
##   - Movers (ids 1.. in data order), keys = the frozen pose at every sim tick: drawbridge deck
##     (solid box about the hinge), portcullis (solid box grille, lifted lift_height when open),
##     barrel and burst (non-solid cylinders), cart (box, solid when the frozen solid_body is).

## JSON format this bake reads (tools/legacy_track_export.gd).
const FORMAT_NAME: String = "dogworks-legacy-track"
const FORMAT_VERSION: int = 1
const DEFAULT_IN: String = "res://build/legacy_tracks"
const DEFAULT_TRACKS: PackedStringArray = ["castle_circuit", "dungeon_depths"]
## Largest deck cell along and across the road (m).
const ALONG_STEP: float = 1.0
const LAT_STEP: float = 1.0
## Largest ramp-wedge cell along the ramp (m).
const RAMP_STEP: float = 0.5
## Height of a ramp wedge's foot over the deck (m), so the wedge never sits coplanar with it.
const RAMP_LIFT: float = 0.01
## Wall extent over and under the road edge (m). Below the 3 m level separation of the generator
## tracks, so the walls of a lower road never reach a deck above it.
const WALL_HEIGHT: float = 2.0
const WALL_BELOW: float = 0.5
## Largest wall or fence piece (m); each piece is kept or dropped as a whole.
const WALL_STEP: float = 0.25
## A wall piece is "inside" another corridor when it is this far (m) inside its wall; a wall lying
## on another road's wall line is kept.
const JUNCTION_EPS: float = 0.05
## A wall counts as standing past an open edge when it is this far (m) past the deck edge.
const OPEN_EPS: float = 0.01
## Floor margin past every wall (m).
const FLOOR_MARGIN: float = 20.0
## Segments searched each side of the hint for a deck vertex's nearest centre-line point.
const NEAREST_WINDOW: int = 6
## Smallest cos(half turn) a mitre is scaled by (caps the mitre at 2x on a turn past 120 degrees);
## geometry, not tuning.
const MIN_MITRE_COS: float = 0.5
## Load-probe point: this high (m) over the main road's start, cast PROBE_MAX_DROP m down
## (ADR-0005 TrackImportLimits.probe_max_drop_m does not exist yet).
const PROBE_LIFT: float = 2.0
## How far (m) a deck runs on past a walled frozen edge, under its wall (the wall stands WALL_BELOW
## into the ground there, so the skirt is closed off). Not at open edges, where the drop is exact.
const EDGE_SKIRT: float = 0.03
## Bisection steps that find where a deck triangle edge crosses the frozen road-ownership line
## (about 1 mm on a 1 m edge).
const CUT_ITERATIONS: int = 10
## Barrier search (_barrier) along a cross-section: march step (m), bisection steps, and how far (m)
## past the nominal offset it looks.
const ROOT_MARCH: float = 0.1
const ROOT_BISECT: int = 24
const ROOT_SPAN: float = 2.0
## Two heights of one boundary vertex closer than this (m) are the same frozen value (float noise):
## the vertex is shared bit for bit. Farther apart, the frozen surface steps there (two feet) and the
## deck keeps both. Geometry, not tuning.
const STEP_EPS: float = 0.0001
## How far (m) a step vertex reaches into the neighbouring segment's cells (see _boundary_row).
const STEP_OVERLAP: float = 0.002
## Unexpected open deck edges listed in the bake notes.
const EDGES_LISTED: int = 10
## Step-vertex cast check: start height over the upper side (m) and the height tolerance (m).
const STEP_CAST_START: float = 0.5
const STEP_CAST_EPS: float = 0.001
## Adaptive deck cells (_refine_tri): a cell is split in four while the frozen height at an edge
## midpoint or the centroid is more than REFINE_TOL (m) off the cell's plane, up to REFINE_DEPTH
## levels (1 m -> 12.5 cm). The cell size then follows the frozen curvature, bank and taper.
const REFINE_TOL: float = 0.005
const REFINE_DEPTH: int = 3
## Adaptive wall pieces (_wall_refine): a piece is halved while the frozen barrier at its middle is
## more than WALL_REFINE_TOL (m) off its chord, up to WALL_REFINE_DEPTH levels (0.25 m -> 1.6 cm).
const WALL_REFINE_TOL: float = 0.005
const WALL_REFINE_DEPTH: int = 4
## T-junction repair (_fix_t_junctions): a vertex within TJ_EPS (m, in XZ) of another triangle's
## edge and within TJ_HEIGHT_TOL (m) of the edge's height there is inserted into that triangle, so
## refined, split and clipped cells share every edge vertex and no ray can slip between them.
## TJ_HEIGHT_TOL is above REFINE_TOL (the largest mid-height mismatch a refinement makes) and below
## RAMP_LIFT and the floor gap, so a ramp foot or the floor is never stitched into a deck. Edges
## longer than TJ_MAX_EDGE (the floor, whole zones) are skipped.
const TJ_EPS: float = 0.0001
const TJ_HEIGHT_TOL: float = 0.007
const TJ_CELL: float = 0.5
const TJ_MAX_EDGE: float = 2.0
## How far (m) the kept side of an ownership cut runs past the cut line, so the two decks of a seam
## overlap by a sliver instead of meeting on a line.
const SEAM_OVERLAP: float = 0.002
## Seam handling: subdivision levels of a cell touching another road's ownership (1 m / 2^5 = 3 cm),
## how far (m) a seam probe sits inside the kept side of a cut, and the height tolerance (m) of a
## seam probe against the holding road's frozen height (the planar cells are within millimetres;
## a fall-through lands a deck thickness or more lower).
const SEAM_DEPTH: int = 5
const SEAM_PROBE_IN: float = 0.005
const SEAM_CAST_TOL: float = 0.02
const PROBE_MAX_DROP: float = 4.0
## Smallest grille half thickness (m) of a portcullis box.
const MIN_GRILLE_HALF: float = 0.1
## Area tolerance (m^2) of the clip bookkeeping; geometry, not tuning.
const AREA_EPS: float = 0.0001
## Relative area mismatch of a clip (Clipper rounds coordinates) above which the clip is taken to
## have made a hole; geometry, not tuning.
const CLIP_AREA_REL: float = 0.01
## Core surface kinds of the pads, ramps and the plain deck, and core wall attribute of fences.
const KIND_ROAD: StringName = &"road"
const KIND_PAD: StringName = &"boost_pad"
const KIND_RAMP: StringName = &"trick_ramp"
const WALL_STANDARD: StringName = &"standard"


## Result of bake_doc(): the data (null when [member problem] is set), notes on what was approximated
## and counts.
class BakeResult:
	extends RefCounted
	var data: TrackCollisionData = null
	var problem: String = ""
	var notes: PackedStringArray = PackedStringArray()
	var stats: Dictionary = {}
	## Frozen-step vertices of the decks as (lower, upper) pairs at one XZ (step_cast_problem()).
	var step_points: PackedVector3Array = PackedVector3Array()
	## Seam-coverage probes (seam_cast_problem()): x, the holding deck's frozen height, z; and per probe
	## the other deck's height when it legitimately holds the point too (NAN otherwise).
	var seam_points: PackedVector3Array = PackedVector3Array()
	var seam_alt: PackedFloat32Array = PackedFloat32Array()


## One path (centre line) of the JSON, with the frozen per-sample arrays and the frozen
## interpolation (TrackModel.Path).
class BakePath:
	extends RefCounted
	var index: int = -1
	var id: String = ""
	var closed: bool = false
	var curb: float = 0.0
	var length: float = 0.0
	var wall_drag_mult: float = 1.0
	var points: PackedVector2Array = PackedVector2Array()
	var y: PackedFloat32Array = PackedFloat32Array()
	var bank: PackedFloat32Array = PackedFloat32Array()
	var half: PackedFloat32Array = PackedFloat32Array()
	var wall_pos: PackedFloat32Array = PackedFloat32Array()
	var wall_neg: PackedFloat32Array = PackedFloat32Array()
	var opening: PackedByteArray = PackedByteArray()
	var cumulative: PackedFloat32Array = PackedFloat32Array()
	var vtx_normal: PackedVector2Array = PackedVector2Array()
	## Frozen query window (TrackData.query_window): segments searched each side for the barrier.
	var window: int = 14
	var bounds: Rect2 = Rect2()

	func seg_count() -> int:
		return points.size() if closed else points.size() - 1

	func nxt(i: int) -> int:
		return (i + 1) % points.size()

	## lerpf that returns the end values exactly at f = 0 and f = 1, so the two segments either side
	## of a sample compute bit-identical values there.
	static func lx(a: float, b: float, f: float) -> float:
		if f <= 0.0:
			return a
		if f >= 1.0:
			return b
		return lerpf(a, b, f)

	func center(seg: int, f: float) -> Vector2:
		if f <= 0.0:
			return points[seg]
		if f >= 1.0:
			return points[nxt(seg)]
		return points[seg].lerp(points[nxt(seg)], f)

	## Lateral offset direction at (seg, f), scaled so that offset lat lands lat m from the segment's
	## line: the lerp of the two mitre vectors (unit bisector / cos(half turn)). On the inside of a
	## turn this is exactly where the frozen offsets of the two segments meet; on the outside it
	## covers the frozen corner fan.
	func normal(seg: int, f: float) -> Vector2:
		if f <= 0.0:
			return vtx_normal[seg]
		if f >= 1.0:
			return vtx_normal[nxt(seg)]
		return vtx_normal[seg].lerp(vtx_normal[nxt(seg)], f)

	func reach(seg: int, f: float) -> float:
		return lx(half[seg], half[nxt(seg)], f) + curb

	## Frozen surface height (TrackModel.Path.surface_y) at segment [param seg], fraction [param f].
	func height(seg: int, f: float, lat: float) -> float:
		var r: float = reach(seg, f)
		return lx(y[seg], y[nxt(seg)], f) + clampf(lat, -r, r) * tan(lx(bank[seg], bank[nxt(seg)], f))

	func centre_height(seg: int, f: float) -> float:
		return lx(y[seg], y[nxt(seg)], f)

	func wall(seg: int, f: float, side: int) -> float:
		var arr: PackedFloat32Array = wall_pos if side >= 0 else wall_neg
		return lx(arr[seg], arr[nxt(seg)], f)

	func along_of(seg: int, f: float) -> float:
		return cumulative[seg] + (cumulative[seg + 1] - cumulative[seg]) * f

	## Segment (x) and fraction (y) at [param along] m (wraps when closed, clamps when open).
	func seg_t_at(along: float) -> Vector2:
		var sv: float = fposmod(along, length) if closed else clampf(along, 0.0, length)
		var lo: int = 0
		var hi: int = seg_count() - 1
		while lo < hi:
			var mid: int = (lo + hi + 1) >> 1
			if cumulative[mid] <= sv:
				lo = mid
			else:
				hi = mid - 1
		var seg_len: float = cumulative[lo + 1] - cumulative[lo]
		return Vector2(lo, (sv - cumulative[lo]) / seg_len if seg_len > 0.0 else 0.0)

	## Nearest centre-line point to [param p]: [seg, t, distance, side (+1 normal side, -1 other)].
	## Searches [param window] segments each side of [param hint] (a closed path), or the whole path
	## when [param window] < 0. Segments whose centre-line height there is outside [y_lo, y_hi] are
	## skipped; seg is -1 when none is left.
	func nearest(p: Vector2, hint: int, window: int, y_lo: float = -INF, y_hi: float = INF) -> PackedFloat32Array:
		var count: int = seg_count()
		var whole: bool = window < 0 or window * 2 + 1 >= count
		var lo: int = 0 if whole else -window
		var hi: int = count - 1 if whole else window
		var best_i: int = -1
		var best_t: float = 0.0
		var best_d: float = INF
		for o in range(lo, hi + 1):
			var i: int = o if whole else hint + o
			if not whole:
				if closed:
					i = posmod(i, count)
				elif i < 0 or i >= count:
					continue
			var a: Vector2 = points[i]
			var ab: Vector2 = points[nxt(i)] - a
			var l2: float = ab.length_squared()
			var t: float = clampf((p - a).dot(ab) / l2, 0.0, 1.0) if l2 > 0.0 else 0.0
			var d: float = p.distance_squared_to(a + ab * t)
			if d >= best_d:
				continue
			var yc: float = centre_height(i, t)
			if yc < y_lo or yc > y_hi:
				continue
			best_d = d
			best_i = i
			best_t = t
		if best_i < 0:
			return PackedFloat32Array([-1.0, 0.0, INF, 1.0])
		var a2: Vector2 = points[best_i]
		var ab2: Vector2 = points[nxt(best_i)] - a2
		var side: float = 1.0 if (p - (a2 + ab2 * best_t)).dot(Vector2(-ab2.y, ab2.x)) >= 0.0 else -1.0
		return PackedFloat32Array([float(best_i), best_t, sqrt(best_d), side])

	## Clamped projection of [param p] onto segment [param seg] alone: [t, distance, side]. Inside
	## the cells of a segment (between its two mitre lines) this is the frozen nearest point, also on
	## the inside of a turn, where the frozen surface steps at the mitre line (two feet).
	func project(seg: int, p: Vector2) -> PackedFloat32Array:
		var a: Vector2 = points[seg]
		var ab: Vector2 = points[nxt(seg)] - a
		var l2: float = ab.length_squared()
		var t: float = clampf((p - a).dot(ab) / l2, 0.0, 1.0) if l2 > 0.0 else 0.0
		var foot: Vector2 = a if t <= 0.0 else (points[nxt(seg)] if t >= 1.0 else a + ab * t)
		var side: float = 1.0 if (p - foot).dot(Vector2(-ab.y, ab.x)) >= 0.0 else -1.0
		return PackedFloat32Array([t, p.distance_to(foot), side])

	## How far [param p] is past this road's wall (negative = inside its corridor), counting only
	## segments at the level [y_lo, y_hi]; INF when none is.
	func excess(p: Vector2, y_lo: float, y_hi: float) -> float:
		if not bounds.has_point(p):
			return INF
		var h: PackedFloat32Array = nearest(p, -1, -1, y_lo, y_hi)
		if h[0] < 0.0:
			return INF
		return h[2] - wall(int(h[0]), h[1], int(h[3]))

	## How far [param p] is past this road's deck edge (negative = on the deck), at the level.
	func deck_excess(p: Vector2, y_lo: float, y_hi: float) -> float:
		if not bounds.has_point(p):
			return INF
		var h: PackedFloat32Array = nearest(p, -1, -1, y_lo, y_hi)
		if h[0] < 0.0:
			return INF
		return h[2] - reach(int(h[0]), h[1])


## A surface region a deck triangle is clipped against (a pad or a zone).
class Region:
	extends RefCounted
	var polygon: PackedVector2Array = PackedVector2Array()
	var bounds: Rect2 = Rect2()
	var surface_id: int = 0
	## Level test: pad (|h - pad_height| <= tol) or zone (TrackModel.surface_zone_at rules).
	var is_pad: bool = false
	var pad_height: float = 0.0
	var h_min: float = 0.0
	var h_max: float = 0.0
	var vertex_heights: PackedFloat32Array = PackedFloat32Array()
	var triangles: PackedInt32Array = PackedInt32Array()
	var flat_height: float = 0.0


## Ground and wall accumulators of one bake.
class Acc:
	extends RefCounted
	var ground: PackedVector3Array = PackedVector3Array()
	var surf: PackedInt32Array = PackedInt32Array()
	var walls: Dictionary = {}  # wall attr id (int) -> PackedVector3Array
	var clipped: int = 0
	var fallback: int = 0
	var walls_dropped_junction: int = 0
	var walls_dropped_opening: int = 0
	var fences_dropped: int = 0
	var deck_dropped_overlap: int = 0
	var deck_cut: int = 0
	var walls_clipped: int = 0
	var walls_clipped_junction: int = 0
	var edges_outer: int = 0
	var edges_end: int = 0
	var edges_step: int = 0
	var edges_bad: PackedStringArray = PackedStringArray()
	var edges_bad_count: int = 0
	## Frozen-step vertices: pairs (lower, upper) at the same XZ, for the runner's cast check.
	var step_points: PackedVector3Array = PackedVector3Array()
	## Seam-coverage probes: points next to an ownership cut, or inside a dropped cell, with the
	## frozen height of the road that must hold them there.
	var seam_points: PackedVector3Array = PackedVector3Array()
	## Per seam probe, the other deck's frozen height there when its deck also holds the point (else NAN).
	var seam_alt: PackedFloat32Array = PackedFloat32Array()
	var seam_splits: int = 0
	var refined: int = 0
	var tj_fixed: int = 0
	var wall_refined: int = 0


func _initialize() -> void:
	var in_dir: String = DEFAULT_IN
	var tracks: PackedStringArray = DEFAULT_TRACKS
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--in="):
			in_dir = arg.substr(5)
		elif arg.begins_with("--tracks="):
			tracks = arg.substr(9).split(",", false)
	var surfaces: SurfaceSet = SurfaceSet.load_checked(SurfaceSet.CORE_PATH)
	var walls: WallAttrSet = WallAttrSet.load_checked(WallAttrSet.CORE_PATH)
	if surfaces == null or walls == null:
		print("FAIL core registries do not load")
		quit(1)
		return
	var failures: int = 0
	for id in tracks:
		var doc: Dictionary = load_doc(in_dir.path_join("%s.json" % id))
		if doc.is_empty():
			print("FAIL %s: no JSON (run tools/legacy_track_export.gd first)" % id)
			failures += 1
			continue
		var baked: BakeResult = bake_doc(doc, surfaces, walls)
		if not baked.problem.is_empty():
			print("FAIL %s bake: %s" % [id, baked.problem])
			failures += 1
			continue
		print("BAKED %s: %s" % [id, JSON.stringify(baked.stats)])
		for note in baked.notes:
			print("  note: %s" % note)
		for variant in ["normal", "mirrored"]:
			var data: TrackCollisionData = baked.data if variant == "normal" else baked.data.mirrored()
			var checked: CollisionBootCheck.CheckedQuery = CollisionBootCheck.checked_query(data, surfaces, walls, PROBE_MAX_DROP)
			if checked.problem.is_empty():
				print("PASS %s %s: checked_query built the query and the load checks passed" % [id, variant])
				if variant == "normal":
					var seam: String = seam_cast_problem(checked.query, baked)
					if seam.is_empty():
						print("PASS %s: all %d seam probes land on the holding deck" % [id, baked.seam_points.size()])
					else:
						print("FAIL %s: %s" % [id, seam])
						failures += 1
					var step: String = step_cast_problem(checked.query, baked)
					if step.is_empty():
						print("PASS %s: none of the %d step-vertex casts falls through the deck" % [id, baked.step_points.size() / 2])
					else:
						print("FAIL %s: %s" % [id, step])
						failures += 1
				checked.query.dispose()
			else:
				print("FAIL %s %s: %s" % [id, variant, checked.problem])
				failures += 1
	quit(0 if failures == 0 else 1)


## Reads and parses the JSON at [param path] (res:// or absolute). Returns {} when it is missing
## or not a JSON object.
static func load_doc(path: String) -> Dictionary:
	var abs_path: String = ProjectSettings.globalize_path(path)
	if not FileAccess.file_exists(abs_path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(abs_path))
	return parsed if parsed is Dictionary else {}


## Bakes the parsed extractor document [param doc] into a TrackCollisionData, with ids from
## [param surfaces] and [param walls] (the core registries). Never builds a query. Allocates:
## tool time only. Main thread only (Geometry2D is thread-safe, but keep tools simple).
static func bake_doc(doc: Dictionary, surfaces: SurfaceSet, walls: WallAttrSet) -> BakeResult:
	var result: BakeResult = BakeResult.new()
	if surfaces == null or walls == null:
		result.problem = "no core SurfaceSet / WallAttrSet"
		return result
	if str(doc.get("format", "")) != FORMAT_NAME or int(doc.get("version", -1)) != FORMAT_VERSION:
		result.problem = "not a %s v%d document (format %s, version %s)" % [FORMAT_NAME, FORMAT_VERSION, doc.get("format"), doc.get("version")]
		return result
	for key in ["paths", "ramps", "pads", "zones", "movers", "ground_y", "level_separation", "surface_height_tolerance", "pad_height_tolerance", "deck_thickness"]:
		if not doc.has(key):
			result.problem = "document has no '%s'" % key
			return result
	var road_id: int = _surface_id(surfaces, KIND_ROAD)
	var pad_id: int = _surface_id(surfaces, KIND_PAD)
	var ramp_id: int = _surface_id(surfaces, KIND_RAMP)
	var standard: WallAttr = walls.attr_of(WALL_STANDARD)
	if road_id < 0 or pad_id < 0 or ramp_id < 0 or standard == null:
		result.problem = "core registries lack road / boost_pad / trick_ramp / standard"
		return result
	var paths: Array[BakePath] = []
	for pd in doc["paths"]:
		var bp: BakePath = _path_from(pd)
		if bp != null:
			bp.window = int(doc.get("query_window", bp.window))
		if bp == null:
			result.problem = "path %s is malformed" % str((pd as Dictionary).get("id", "?"))
			return result
		paths.append(bp)
	if paths.is_empty() or paths[0].index != -1 or not paths[0].closed:
		result.problem = "the first path must be the closed main loop (index -1)"
		return result
	var regions: Array[Region] = []
	for pad in doc["pads"]:
		regions.append(_pad_region(pad, pad_id))
	var zones: Array = doc["zones"]
	var zone_regions: Array[Region] = []
	for z in zones:
		var kind: StringName = StringName(str(z["kind"]))
		var sid: int = _surface_id(surfaces, kind)
		if sid < 0:
			result.problem = "zone %s has kind %s, not in the core SurfaceSet" % [z["id"], kind]
			return result
		var zr: Region = _zone_region(z, sid)
		regions.append(zr)
		zone_regions.append(zr)
	var level_tol: float = float(doc["surface_height_tolerance"])
	var pad_tol: float = float(doc["pad_height_tolerance"])
	var sep: float = float(doc["level_separation"])
	var ground_y: float = float(doc["ground_y"])
	var acc: Acc = Acc.new()
	var removed: Dictionary = _gate_deck_spans(doc["movers"])
	for bp in paths:
		_bake_deck(bp, removed.get(bp.index, PackedVector2Array()), regions, paths, float(doc["level_separation"]),
				float(doc.get("road_keep_band", 0.0)), float(doc.get("branch_switch_margin", 0.0)), level_tol, pad_tol, road_id, acc)
	for rp in doc["ramps"]:
		var ri: int = int(rp["path"])
		var bp: BakePath = _path_of(paths, ri)
		if bp == null:
			result.problem = "ramp on unknown path %d" % ri
			return result
		_bake_ramp(bp, rp, ramp_id, acc)
	for zi in zones.size():
		if not bool(zones[zi]["on_road"]):
			_bake_zone_ground(zone_regions[zi], acc)
	_bake_floor(paths, ground_y, road_id, acc)
	for bp in paths:
		var attr: WallAttr = _nearest_attr(walls, bp.wall_drag_mult)
		if absf(attr.scrape_drag_mult - bp.wall_drag_mult) > AREA_EPS:
			result.notes.append("path %s wall_drag_mult %s has no exact core attribute; used %s (%s)" % [bp.id, bp.wall_drag_mult, attr.name, attr.scrape_drag_mult])
		_bake_walls(bp, paths, sep, ground_y, attr.id, acc)
	for zi in zones.size():
		if bool(zones[zi]["fence"]):
			_bake_fence(zones[zi], zone_regions[zi], paths, sep, standard.id, acc)
	_fix_t_junctions(acc)
	var data: TrackCollisionData = TrackCollisionData.new()
	data.ground_faces = acc.ground
	data.surface_of_face = acc.surf
	var wall_faces: Array[PackedVector3Array] = []
	var wall_ids: PackedInt32Array = PackedInt32Array()
	var attr_ids: Array = acc.walls.keys()
	attr_ids.sort()
	for aid in attr_ids:
		var faces: PackedVector3Array = acc.walls[aid]
		if faces.is_empty():
			continue
		wall_faces.append(faces)
		wall_ids.append(int(aid))
	data.wall_faces = wall_faces
	data.wall_attr_ids = wall_ids
	var movers: Array[MoverDef] = []
	var mover_docs: Array = doc["movers"]
	for mi in mover_docs.size():
		var md: MoverDef = _mover_from(mover_docs[mi], mi + 1, float(doc["deck_thickness"]), road_id, standard.id)
		if md == null:
			result.problem = "mover %s (kind %s) cannot be converted" % [mover_docs[mi].get("id"), mover_docs[mi].get("kind")]
			return result
		movers.append(md)
	data.movers = movers
	var main: BakePath = paths[0]
	var c0: Vector2 = main.center(0, 0.0)
	data.probe_point = Vector3(c0.x, main.height(0, 0.0, 0.0) + PROBE_LIFT, c0.y)
	data.probe_surface_id = road_id
	var layout: String = data.layout_error()
	if not layout.is_empty():
		result.problem = "baked data layout: %s" % layout
		return result
	for e in acc.edges_bad:
		result.notes.append("open deck edge (watertightness): %s" % e)
	if acc.fallback > 0:
		result.notes.append("%d deck triangles classified by centroid (a clip made a hole or a piece did not triangulate)" % acc.fallback)
	for bp in paths:
		if not is_equal_approx(_path_floor_drag(doc, bp.index), 1.0):
			result.notes.append("path %s floor_drag_mult %s is a road property with no core surface; baked as its surfaces (story 026 parity gap)" % [bp.id, _path_floor_drag(doc, bp.index)])
	result.stats = {
		"ground_triangles": data.ground_triangle_count(), "clipped_triangles": acc.clipped,
		"wall_shapes": wall_ids.size(), "wall_attr_ids": Array(wall_ids),
		"wall_triangles": wall_faces.map(func(f: PackedVector3Array) -> int: return int(f.size() / 3.0)),
		"walls_dropped_opening": acc.walls_dropped_opening, "wall_chords_clipped": acc.walls_clipped, "walls_clipped_junction": acc.walls_clipped_junction, "walls_dropped_junction": acc.walls_dropped_junction,
		"fence_pieces_dropped": acc.fences_dropped,
		"deck_triangles_dropped_overlap": acc.deck_dropped_overlap, "seam_splits": acc.seam_splits, "cells_refined": acc.refined, "t_junction_triangles_fixed": acc.tj_fixed, "wall_pieces_refined": acc.wall_refined,
		"seam_probes": acc.seam_points.size(), "deck_triangles_cut_at_seam": acc.deck_cut,
		"deck_open_edges": {"outer": acc.edges_outer, "path_end_or_gate": acc.edges_end, "frozen_step": acc.edges_step,
				"unexpected": acc.edges_bad_count}, "movers": movers.size(),
		"solid_movers": movers.filter(func(m: MoverDef) -> bool: return m.solid).size(),
	}
	result.step_points = acc.step_points
	result.seam_points = acc.seam_points
	result.seam_alt = acc.seam_alt
	result.data = data
	return result


## Casts straight down at every seam-coverage probe of [param baked] (next to an ownership cut on the
## kept side, or inside a cell given to another road) and returns "" when each lands within
## SEAM_CAST_TOL of the deck the frozen game assigns the point to, or of the other deck when that
## one legitimately holds the point too; else the count and the first few. The watertightness
## check of the cut mesh: a seam gap shows up here.
static func seam_cast_problem(query: CollisionQuery, baked: BakeResult) -> String:
	var cursor: QueryCursor = QueryCursor.new()
	var hit: GroundHit = GroundHit.new()
	var bad: PackedStringArray = PackedStringArray()
	var n_bad: int = 0
	for k in baked.seam_points.size():
		var p: Vector3 = baked.seam_points[k]
		var alt: float = baked.seam_alt[k]
		var top: float = maxf(p.y, alt) if is_finite(alt) else p.y
		var low: float = minf(p.y, alt) if is_finite(alt) else p.y
		var got: bool = query.cast_ground(cursor, Vector3(p.x, top + STEP_CAST_START, p.z), Vector3.DOWN,
				STEP_CAST_START + (top - low) + SEAM_CAST_TOL * 2.0, 0.0, hit)
		var on_holder: bool = got and absf(hit.point.y - p.y) <= SEAM_CAST_TOL
		var on_alt: bool = got and is_finite(alt) and absf(hit.point.y - alt) <= SEAM_CAST_TOL
		if not (on_holder or on_alt):
			n_bad += 1
			if bad.size() < EDGES_LISTED:
				bad.append("%s (holding deck %.4f, %s)" % [Vector2(p.x, p.z), p.y, "hit %.4f" % hit.point.y if got else "no hit"])
	if n_bad == 0:
		return ""
	return "%d of %d seam probes missed the holding deck: %s" % [n_bad, baked.seam_points.size(), ", ".join(bad)]


## Casts straight down exactly at every frozen-step vertex of [param baked] (where two segments'
## rows meet at two heights) and returns "" when no cast falls through the deck (a miss, or a hit
## below the lower side by more than STEP_CAST_EPS), else the count and the first few. The
## watertightness check of a step that a topology count cannot see. A hit above the upper side
## (another surface over the deck there) is not a fall-through; the equivalence run measures heights.
static func step_cast_problem(query: CollisionQuery, baked: BakeResult) -> String:
	var cursor: QueryCursor = QueryCursor.new()
	var hit: GroundHit = GroundHit.new()
	var bad: PackedStringArray = PackedStringArray()
	var n_bad: int = 0
	var pts: PackedVector3Array = baked.step_points
	for i in range(0, pts.size() - 1, 2):
		var lo: Vector3 = pts[i]
		var hi: Vector3 = pts[i + 1]
		var start: Vector3 = Vector3(lo.x, hi.y + STEP_CAST_START, lo.z)
		var got: bool = query.cast_ground(cursor, start, Vector3.DOWN, STEP_CAST_START + (hi.y - lo.y) + STEP_CAST_EPS, 0.0, hit)
		if not got or hit.point.y < lo.y - STEP_CAST_EPS:
			n_bad += 1
			if bad.size() < EDGES_LISTED:
				bad.append("%s (step %.4f..%.4f, %s)" % [Vector2(lo.x, lo.z), lo.y, hi.y, "hit %s" % hit.point if got else "no hit"])
	if n_bad == 0:
		return ""
	return "%d of %d step-vertex casts fell through the deck: %s" % [n_bad, pts.size() / 2, ", ".join(bad)]


static func _surface_id(surfaces: SurfaceSet, kind: StringName) -> int:
	var t: SurfaceType = surfaces.type_of(kind)
	return t.id if t != null else -1


static func _nearest_attr(walls: WallAttrSet, mult: float) -> WallAttr:
	var best: WallAttr = null
	for a in walls.attrs:
		if a != null and (best == null or absf(a.scrape_drag_mult - mult) < absf(best.scrape_drag_mult - mult)):
			best = a
	return best


static func _path_floor_drag(doc: Dictionary, index: int) -> float:
	for pd in doc["paths"]:
		if int(pd["index"]) == index:
			return float(pd.get("floor_drag_mult", 1.0))
	return 1.0


static func _path_of(paths: Array[BakePath], index: int) -> BakePath:
	for bp in paths:
		if bp.index == index:
			return bp
	return null


static func _v2s(flat: Array) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	@warning_ignore("integer_division")
	out.resize(flat.size() / 2)
	for i in out.size():
		out[i] = Vector2(float(flat[i * 2]), float(flat[i * 2 + 1]))
	return out


static func _f32(a: Array) -> PackedFloat32Array:
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(a.size())
	for i in a.size():
		out[i] = float(a[i])
	return out


static func _path_from(pd: Dictionary) -> BakePath:
	var bp: BakePath = BakePath.new()
	bp.index = int(pd["index"])
	bp.id = str(pd["id"])
	bp.closed = bool(pd["closed"])
	bp.curb = float(pd["curb"])
	bp.length = float(pd["length"])
	bp.wall_drag_mult = float(pd.get("wall_drag_mult", 1.0))
	bp.points = _v2s(pd["points"])
	bp.y = _f32(pd["y"])
	bp.bank = _f32(pd["bank"])
	bp.half = _f32(pd["half"])
	bp.wall_pos = _f32(pd["wall_pos"])
	bp.wall_neg = _f32(pd["wall_neg"])
	bp.cumulative = _f32(pd["cumulative"])
	var op: Array = pd.get("opening", [])
	bp.opening = PackedByteArray(op.map(func(v: Variant) -> int: return int(v)))
	var n: int = bp.points.size()
	if n < 2 or bp.y.size() != n or bp.bank.size() != n or bp.half.size() != n or bp.wall_pos.size() != n \
			or bp.wall_neg.size() != n or bp.cumulative.size() != bp.seg_count() + 1 \
			or (not bp.opening.is_empty() and bp.opening.size() != n):
		return null
	var seg_n: PackedVector2Array = PackedVector2Array()
	seg_n.resize(bp.seg_count())
	var last: Vector2 = Vector2.ZERO
	for i in bp.seg_count():
		var d: Vector2 = bp.points[bp.nxt(i)] - bp.points[i]
		if d.length_squared() > 0.0:
			last = Vector2(-d.y, d.x).normalized()
		seg_n[i] = last
	bp.vtx_normal.resize(n)
	var widest: float = 0.0
	var lo: Vector2 = bp.points[0]
	var hi: Vector2 = bp.points[0]
	for i in n:
		var a: Vector2
		var b: Vector2
		if bp.closed:
			a = seg_n[(i - 1 + n) % n]
			b = seg_n[i]
		else:
			a = seg_n[maxi(i - 1, 0)]
			b = seg_n[mini(i, n - 2)]
		var m: Vector2 = a + b
		var bis: Vector2 = m.normalized() if m.length_squared() > 0.0 else b
		bp.vtx_normal[i] = bis / maxf(bis.dot(b), MIN_MITRE_COS)
		widest = maxf(widest, maxf(bp.wall_pos[i], bp.wall_neg[i]))
		lo = Vector2(minf(lo.x, bp.points[i].x), minf(lo.y, bp.points[i].y))
		hi = Vector2(maxf(hi.x, bp.points[i].x), maxf(hi.y, bp.points[i].y))
	var pad: float = widest + 1.0
	bp.bounds = Rect2(lo - Vector2(pad, pad), hi - lo + Vector2(pad, pad) * 2.0)
	return bp


static func _pad_region(pad: Dictionary, pad_id: int) -> Region:
	var c: Vector2 = Vector2(float(pad["center"][0]), float(pad["center"][1]))
	var t: Vector2 = Vector2(float(pad["dir"][0]), float(pad["dir"][1]))
	var h: Vector2 = Vector2(float(pad["half"][0]), float(pad["half"][1]))
	var n: Vector2 = Vector2(-t.y, t.x)
	var r: Region = Region.new()
	r.polygon = PackedVector2Array([c - t * h.x - n * h.y, c + t * h.x - n * h.y, c + t * h.x + n * h.y, c - t * h.x + n * h.y])
	r.bounds = _rect_of(r.polygon)
	r.surface_id = pad_id
	r.is_pad = true
	r.pad_height = float(pad["height"])
	return r


static func _zone_region(z: Dictionary, sid: int) -> Region:
	var r: Region = Region.new()
	r.polygon = _v2s(z["polygon"])
	r.bounds = _rect_of(r.polygon)
	r.surface_id = sid
	r.h_min = float(z["height_min"])
	r.h_max = float(z["height_max"])
	r.flat_height = float(z["height"])
	r.vertex_heights = _f32(z["vertex_heights"])
	r.triangles = PackedInt32Array((z["triangles"] as Array).map(func(v: Variant) -> int: return int(v)))
	if r.vertex_heights.size() != r.polygon.size() or r.triangles.is_empty():
		r.vertex_heights = PackedFloat32Array()
		r.triangles = Geometry2D.triangulate_polygon(r.polygon)
	return r


## Ground height of zone [param r] at [param p] (TrackModel.zone_height_at).
static func _zone_height(r: Region, p: Vector2) -> float:
	if r.vertex_heights.is_empty():
		return r.flat_height
	var poly: PackedVector2Array = r.polygon
	for k in range(0, r.triangles.size(), 3):
		var a: Vector2 = poly[r.triangles[k]]
		var b: Vector2 = poly[r.triangles[k + 1]]
		var c: Vector2 = poly[r.triangles[k + 2]]
		if not Geometry2D.point_is_inside_triangle(p, a, b, c):
			continue
		var den: float = (b.y - c.y) * (a.x - c.x) + (c.x - b.x) * (a.y - c.y)
		if absf(den) < AREA_EPS * AREA_EPS:
			break
		var wa: float = ((b.y - c.y) * (p.x - c.x) + (c.x - b.x) * (p.y - c.y)) / den
		var wb: float = ((c.y - a.y) * (p.x - c.x) + (a.x - c.x) * (p.y - c.y)) / den
		return wa * r.vertex_heights[r.triangles[k]] + wb * r.vertex_heights[r.triangles[k + 1]] \
				+ (1.0 - wa - wb) * r.vertex_heights[r.triangles[k + 2]]
	var best: int = 0
	var best_d: float = INF
	for i in poly.size():
		var d: float = p.distance_squared_to(poly[i])
		if d < best_d:
			best_d = d
			best = i
	return r.vertex_heights[best]


## True when a kart at height [param h] over [param p] is on region [param r]'s level.
static func _region_level(r: Region, p: Vector2, h: float, level_tol: float, pad_tol: float) -> bool:
	if r.is_pad:
		return absf(h - r.pad_height) <= pad_tol
	if h < r.h_min - level_tol or h > r.h_max + level_tol:
		return false
	return r.vertex_heights.is_empty() or absf(h - _zone_height(r, p)) <= level_tol


static func _rect_of(poly: PackedVector2Array) -> Rect2:
	var r: Rect2 = Rect2(poly[0], Vector2.ZERO)
	for p in poly:
		r = r.expand(p)
	return r


## Along ranges (path index -> PackedVector2Array of (from, to)) of the drawbridge-style gate decks.
static func _gate_deck_spans(movers: Array) -> Dictionary:
	var out: Dictionary = {}
	for m in movers:
		if str(m["kind"]) != "gate" or str(m["hit_effect"]) == "stop":
			continue
		var pi: int = int(m["path"])
		var spans: PackedVector2Array = out.get(pi, PackedVector2Array())
		spans.append(Vector2(float(m["path_from"]), float(m["path_to"])))
		out[pi] = spans
	return out


## Height of a deck vertex at [param p] of a cell of segment [param seg]: the frozen formula at its
## foot on that segment (TrackModel.Path.surface_y). Both cross-sections of a segment use that
## segment, so on the inside of a turn the deck steps at the mitre line exactly as the frozen
## surface does (two feet there). Writes the distance to the foot to [param out_dist][0].
## [param f] is unused (kept for the call sites).
static func _deck_height(bp: BakePath, p: Vector2, seg: int, f: float, out_dist: PackedFloat32Array) -> float:
	var h: PackedFloat32Array = bp.project(seg, p)
	out_dist[0] = h[1]
	return bp.height(seg, h[0], h[1] * h[2])


## A deck vertex at cross-section (seg, f), lateral [param lat] (ramp wedges): XZ from the lerped
## mitre cross-section, height from the frozen formula at its own nearest centre-line point.
static func _deck_vertex(bp: BakePath, seg: int, f: float, lat: float) -> Vector3:
	var p: Vector2 = bp.center(seg, f) + bp.normal(seg, f) * lat
	var dist: PackedFloat32Array = PackedFloat32Array([0.0])
	return Vector3(p.x, _deck_height(bp, p, seg, f, dist), p.y)


## The frozen barrier on side [param side] (+1 normal side) of cross-section (seg, f): searching out
## from the centre line along the cross-section, the first point where the frozen road's own excess
## turns positive. Excess is the distance to the nearest centre-line point within the frozen query
## window minus the reach there (deck edge: on_deck) or the wall offset there ([param is_wall]: the
## lateral clamp). This is where the frozen query stops a kart, also on the inside of a turn, at a
## width taper and where the offset folds back. A walled deck edge then runs EDGE_SKIRT on under the
## wall. Falls back to the mitre point when no barrier is found in reach.
static func _barrier(bp: BakePath, seg: int, f: float, side: int, is_wall: bool) -> Vector2:
	var c: Vector2 = bp.center(seg, f)
	var dir: Vector2 = bp.normal(seg, f)
	var u: Vector2 = dir.normalized() * float(side)
	var nominal: float = bp.wall(seg, f, side) if is_wall else bp.reach(seg, f)
	var s_max: float = nominal * dir.length() + ROOT_SPAN
	var found: float = -1.0
	var prev: float = 0.0
	var s_at: float = ROOT_MARCH
	while s_at <= s_max:
		if _excess_at(bp, c + u * s_at, seg, is_wall) > 0.0:
			var lo: float = prev
			var hi: float = s_at
			for it in ROOT_BISECT:
				var mid: float = (lo + hi) * 0.5
				if _excess_at(bp, c + u * mid, seg, is_wall) > 0.0:
					hi = mid
				else:
					lo = mid
			found = (lo + hi) * 0.5
			break
		prev = s_at
		s_at += ROOT_MARCH
	var p: Vector2 = c + u * found if found >= 0.0 else c + dir * (nominal * float(side))
	if not is_wall and bp.wall(seg, f, side) <= bp.reach(seg, f) + OPEN_EPS:
		p += u * EDGE_SKIRT
	return p


## Frozen excess of [param p] on road [param bp]: distance to the nearest centre-line point in the
## query window around [param seg] minus the reach (or the wall offset) there.
static func _excess_at(bp: BakePath, p: Vector2, seg: int, is_wall: bool) -> float:
	var h: PackedFloat32Array = bp.nearest(p, seg, bp.window)
	if h[0] < 0.0:
		return INF
	var target: float = bp.wall(int(h[0]), h[1], int(h[3])) if is_wall else bp.reach(int(h[0]), h[1])
	return h[2] - target


## Cross-section positions: m_lat + 1 points from the left barrier to the right barrier.
static func _row_xz(bp: BakePath, seg: int, f: float, m_lat: int) -> PackedVector2Array:
	var left: Vector2 = _barrier(bp, seg, f, -1, false)
	var right: Vector2 = _barrier(bp, seg, f, 1, false)
	var xz: PackedVector2Array = PackedVector2Array()
	xz.resize(m_lat + 1)
	for j in m_lat + 1:
		xz[j] = left if j == 0 else (right if j == m_lat else left.lerp(right, float(j) / float(m_lat)))
	return xz


## Deck vertices at [param xz], heights from segment [param seg].
static func _row_vertices(bp: BakePath, seg: int, xz: PackedVector2Array) -> PackedVector3Array:
	var row: PackedVector3Array = PackedVector3Array()
	row.resize(xz.size())
	var dist: PackedFloat32Array = PackedFloat32Array([0.0])
	for j in xz.size():
		row[j] = Vector3(xz[j].x, _deck_height(bp, xz[j], seg, 0.0, dist), xz[j].y)
	return row


## Per vertex 1 when another road owns it (_owned_by_other).
static func _row_cov(bp: BakePath, seg: int, f: float, xz: PackedVector2Array, others: Array[BakePath], sep: float,
		keep_band: float, switch_margin: float) -> PackedByteArray:
	var cov: PackedByteArray = PackedByteArray()
	cov.resize(xz.size())
	var yc: float = bp.centre_height(seg, f)
	for j in xz.size():
		cov[j] = 1 if _owned_by_other(bp, xz[j], seg, yc, others, sep, keep_band, switch_margin) else 0
	return cov


static func _bake_deck(bp: BakePath, skip: PackedVector2Array, regions: Array[Region], paths: Array[BakePath],
		sep: float, keep_band: float, switch_margin: float, level_tol: float, pad_tol: float, road_id: int, acc: Acc) -> void:
	var max_reach: float = 0.0
	for i in bp.points.size():
		max_reach = maxf(max_reach, bp.half[i] + bp.curb)
	var m_lat: int = maxi(1, ceili(2.0 * max_reach / LAT_STEP))
	var local: Array[Region] = []
	for r in regions:
		if r.bounds.intersects(bp.bounds):
			local.append(r)
	var others: Array[BakePath] = []
	for other in paths:
		if other != bp and other.bounds.intersects(bp.bounds):
			others.append(other)
	# Boundary rows, shared by the two segments either side of a sample: vertex index ->
	# [xz, vertices, cov, uses]. Steps: "vi:j" for a boundary vertex where the frozen surface steps.
	var boundary: Dictionary = {}
	var steps: Dictionary = {}
	# Watertightness bookkeeping over the base cell grid (every cell, before ownership and clipping).
	var vid: Dictionary = {}
	var vpos: PackedVector3Array = PackedVector3Array()
	var edge_count: Dictionary = {}
	var edge_meta: Dictionary = {}  # edge key -> Vector3i(code, vi, j): code 0 interior, 1 outer, 2 boundary row
	for seg in bp.seg_count():
		var mid_along: float = (bp.cumulative[seg] + bp.cumulative[seg + 1]) * 0.5
		var skipped: bool = false
		for span in skip:
			if mid_along >= span.x and mid_along <= span.y:
				skipped = true
		if skipped:
			continue
		var k_n: int = maxi(1, ceili((bp.cumulative[seg + 1] - bp.cumulative[seg]) / ALONG_STEP))
		var b0: Array = _boundary_row(bp, seg, 0.0, seg, m_lat, others, sep, keep_band, switch_margin, boundary, steps, acc.step_points)
		var prev: PackedVector3Array = b0[0]
		var prev_cov: PackedByteArray = b0[1]
		var prev_vi: int = seg
		for a in k_n:
			var f1: float = float(a + 1) / float(k_n)
			var row: PackedVector3Array
			var row_cov: PackedByteArray
			var row_vi: int = -1
			if a + 1 == k_n:
				var b1: Array = _boundary_row(bp, seg, 1.0, bp.nxt(seg), m_lat, others, sep, keep_band, switch_margin, boundary, steps, acc.step_points)
				row = b1[0]
				row_cov = b1[1]
				row_vi = bp.nxt(seg)
			else:
				var xz: PackedVector2Array = _row_xz(bp, seg, f1, m_lat)
				row = _row_vertices(bp, seg, xz)
				row_cov = _row_cov(bp, seg, f1, xz, others, sep, keep_band, switch_margin)
			var yc: float = bp.centre_height(seg, (float(a) + 0.5) / float(k_n))
			for j in m_lat:
				var tris: Array = [[prev[j], row[j], prev[j + 1], prev_cov[j], row_cov[j], prev_cov[j + 1]],
						[prev[j + 1], row[j], row[j + 1], prev_cov[j + 1], row_cov[j], row_cov[j + 1]]]
				_count_edge(vid, vpos, edge_count, edge_meta, prev[j], row[j], Vector3i(1 if j == 0 else 0, -1, -1))
				_count_edge(vid, vpos, edge_count, edge_meta, row[j], prev[j + 1], Vector3i(0, -1, -1))
				_count_edge(vid, vpos, edge_count, edge_meta, prev[j + 1], prev[j], Vector3i(2 if prev_vi >= 0 else 0, prev_vi, j))
				_count_edge(vid, vpos, edge_count, edge_meta, prev[j + 1], row[j], Vector3i(0, -1, -1))
				_count_edge(vid, vpos, edge_count, edge_meta, row[j], row[j + 1], Vector3i(2 if row_vi >= 0 else 0, row_vi, j))
				_count_edge(vid, vpos, edge_count, edge_meta, row[j + 1], prev[j + 1], Vector3i(1 if j + 1 == m_lat else 0, -1, -1))
				for tr in tris:
					var n_own: int = int(tr[3]) + int(tr[4]) + int(tr[5])
					if n_own == 0:
						var rv: Array[Vector3] = [tr[0], tr[1], tr[2]]
						_refine_tri(bp, seg, rv, 0, local, level_tol, pad_tol, road_id, acc)
					else:
						var sv: Array[Vector3] = [tr[0], tr[1], tr[2]]
						var sf: Array[int] = [int(tr[3]), int(tr[4]), int(tr[5])]
						_seam_tri(bp, seg, yc, sv, sf, 0, others, sep, keep_band, switch_margin, local, level_tol, pad_tol, road_id, acc)
			prev = row
			prev_cov = row_cov
			prev_vi = row_vi
	_check_edges(bp, edge_count, edge_meta, vpos, boundary, steps, acc)


## The boundary row at sample [param vi] seen from segment [param seg] (f = 0 or 1): positions,
## ownership and the vertices are computed once and shared; a vertex whose height from this segment
## differs from the stored one by more than STEP_EPS is a frozen step and keeps this segment's height.
## Returns [vertices, cov].
static func _boundary_row(bp: BakePath, seg: int, f: float, vi: int, m_lat: int, others: Array[BakePath], sep: float,
		keep_band: float, switch_margin: float, boundary: Dictionary, steps: Dictionary,
		step_points: PackedVector3Array) -> Array:
	if not boundary.has(vi):
		var xz: PackedVector2Array = _row_xz(bp, seg, f, m_lat)
		var v: PackedVector3Array = _row_vertices(bp, seg, xz)
		var cov: PackedByteArray = _row_cov(bp, seg, f, xz, others, sep, keep_band, switch_margin)
		boundary[vi] = [xz, v, cov, 1]
		return [v, cov]
	var e: Array = boundary[vi]
	e[3] = int(e[3]) + 1
	var stored: PackedVector3Array = e[1]
	var own: PackedVector3Array = _row_vertices(bp, seg, e[0])
	var merged: PackedVector3Array = PackedVector3Array()
	merged.resize(own.size())
	# A step vertex moves STEP_OVERLAP into the other segment's cells, so this segment's cell overlaps
	# the other's by that sliver instead of meeting it on a zero-width line a ray can slip through.
	var t2: Vector2 = (bp.points[bp.nxt(seg)] - bp.points[seg]).normalized()
	var into: Vector2 = -t2 if f <= 0.0 else t2
	for j in own.size():
		if absf(own[j].y - stored[j].y) <= STEP_EPS:
			merged[j] = stored[j]
		else:
			merged[j] = Vector3(own[j].x + into.x * STEP_OVERLAP, own[j].y, own[j].z + into.y * STEP_OVERLAP)
			steps["%d:%d" % [vi, j]] = true
			if j > 0 and j < own.size() - 1 and (e[2] as PackedByteArray)[j] == 0:
				# Interior step vertices this deck keeps: an edge vertex sits on the deck's outer
				# boundary, and a vertex another road owns is that road's deck to hold.
				step_points.append(Vector3(stored[j].x, minf(own[j].y, stored[j].y), stored[j].z))
				step_points.append(Vector3(stored[j].x, maxf(own[j].y, stored[j].y), stored[j].z))
	return [merged, e[2]]


static func _count_edge(vid: Dictionary, vpos: PackedVector3Array, edge_count: Dictionary, edge_meta: Dictionary,
		a: Vector3, b: Vector3, meta: Vector3i) -> void:
	var ia: int = _vertex_id(vid, vpos, a)
	var ib: int = _vertex_id(vid, vpos, b)
	var key: int = mini(ia, ib) * 1048576 + maxi(ia, ib)
	edge_count[key] = int(edge_count.get(key, 0)) + 1
	if not edge_meta.has(key) or meta.x != 0:
		edge_meta[key] = meta


static func _vertex_id(vid: Dictionary, vpos: PackedVector3Array, v: Vector3) -> int:
	if vid.has(v):
		return vid[v]
	var id: int = vpos.size()
	vid[v] = id
	vpos.append(v)
	return id


## Watertightness of one deck's base cell grid: every edge must be shared by exactly two cells,
## except the outer edges, the rows at a path end or a gate deck, and frozen steps. Anything else
## (a crack between rows, an overlap) is counted and listed.
static func _check_edges(bp: BakePath, edge_count: Dictionary, edge_meta: Dictionary, vpos: PackedVector3Array,
		boundary: Dictionary, steps: Dictionary, acc: Acc) -> void:
	for key in edge_count:
		var n: int = edge_count[key]
		if n == 2:
			continue
		var meta: Vector3i = edge_meta[key]
		var why: String = ""
		if n > 2:
			why = "shared by %d cells" % n
		elif meta.x == 1:
			acc.edges_outer += 1
			continue
		elif meta.x == 2 and boundary.has(meta.y) and int(boundary[meta.y][3]) == 1:
			acc.edges_end += 1
			continue
		elif meta.x == 2 and (steps.has("%d:%d" % [meta.y, meta.z]) or steps.has("%d:%d" % [meta.y, meta.z + 1])):
			acc.edges_step += 1
			continue
		else:
			why = "open (crack)"
		acc.edges_bad_count += 1
		if acc.edges_bad.size() < EDGES_LISTED:
			@warning_ignore("integer_division")
			var ia: int = int(key) / 1048576
			var ib: int = int(key) % 1048576
			acc.edges_bad.append("path %s edge %s - %s %s" % [bp.id, vpos[ia], vpos[ib], why])


## True when the frozen hint-free query gives [param p] (on road [param bp], centre-line height
## [param yc]) to another road whose deck holds it (_frozen_prefers).
static func _owned_by_other(bp: BakePath, p: Vector2, seg: int, yc: float, others: Array[BakePath], sep: float,
		keep_band: float, switch_margin: float) -> bool:
	return not _owner_of(bp, p, seg, yc, others, sep, keep_band, switch_margin, -1, -1).is_empty()


## The road that owns [param p] instead of [param bp]: [index into others, its nearest segment], or
## [] when bp keeps it. With [param only] >= 0, only others[only] is tested, searched within
## 2 x NEAREST_WINDOW segments of [param hint] (the seam cut's bisection).
static func _owner_of(bp: BakePath, p: Vector2, seg: int, yc: float, others: Array[BakePath], sep: float,
		keep_band: float, switch_margin: float, only: int, hint: int) -> PackedInt32Array:
	if others.is_empty():
		return PackedInt32Array()
	var own: PackedFloat32Array = bp.nearest(p, seg, NEAREST_WINDOW)
	if own[0] < 0.0:
		return PackedInt32Array()
	var own_ex: float = own[2] - bp.wall(int(own[0]), own[1], int(own[3]))
	for oi in others.size():
		if only >= 0 and oi != only:
			continue
		var other: BakePath = others[oi]
		if not other.bounds.has_point(p):
			continue
		var h: PackedFloat32Array = other.nearest(p, hint, 2 * NEAREST_WINDOW, yc - sep, yc + sep) if only >= 0 \
				else other.nearest(p, -1, -1, yc - sep, yc + sep)
		if h[0] < 0.0 or h[2] > other.reach(int(h[0]), h[1]):
			continue
		var other_ex: float = h[2] - other.wall(int(h[0]), h[1], int(h[3]))
		if _frozen_prefers(other.index, h[2], other_ex, bp.index, own[2], own_ex, keep_band, switch_margin):
			return PackedInt32Array([oi, int(h[0])])
	return PackedInt32Array()


## T-junction repair over every ground triangle with edges up to TJ_MAX_EDGE: inserts the vertices
## that lie on its edges (TJ_EPS in XZ, TJ_HEIGHT_TOL in height) and re-triangulates it as a fan
## around its centroid, keeping its surface id and facing.
static func _fix_t_junctions(acc: Acc) -> void:
	var g: PackedVector3Array = acc.ground
	var seen: Dictionary = {}
	var grid: Dictionary = {}
	for v in g:
		if seen.has(v):
			continue
		seen[v] = true
		var key: Vector2i = Vector2i(floori(v.x / TJ_CELL), floori(v.z / TJ_CELL))
		if not grid.has(key):
			grid[key] = PackedVector3Array()
		var list: PackedVector3Array = grid[key]
		list.append(v)
		grid[key] = list
	var out_g: PackedVector3Array = PackedVector3Array()
	var out_s: PackedInt32Array = PackedInt32Array()
	for t in acc.surf.size():
		var tri: Array[Vector3] = [g[t * 3], g[t * 3 + 1], g[t * 3 + 2]]
		var poly: Array[Vector3] = []
		var inserted: bool = false
		for e in 3:
			var a: Vector3 = tri[e]
			var b: Vector3 = tri[(e + 1) % 3]
			poly.append(a)
			var a2: Vector2 = Vector2(a.x, a.z)
			var b2: Vector2 = Vector2(b.x, b.z)
			var len2: float = a2.distance_to(b2)
			if len2 > TJ_MAX_EDGE or len2 < TJ_EPS:
				continue
			var found: Array = []  # [s, vertex]
			var lo: Vector2i = Vector2i(floori(minf(a.x, b.x) / TJ_CELL), floori(minf(a.z, b.z) / TJ_CELL))
			var hi: Vector2i = Vector2i(floori(maxf(a.x, b.x) / TJ_CELL), floori(maxf(a.z, b.z) / TJ_CELL))
			for cx in range(lo.x, hi.x + 1):
				for cz in range(lo.y, hi.y + 1):
					var key2: Vector2i = Vector2i(cx, cz)
					if not grid.has(key2):
						continue
					for v in grid[key2]:
						if v == a or v == b:
							continue
						var v2: Vector2 = Vector2(v.x, v.z)
						var sp: float = (v2 - a2).dot(b2 - a2) / (len2 * len2)
						if sp <= TJ_EPS / len2 or sp >= 1.0 - TJ_EPS / len2:
							continue
						if v2.distance_to(a2.lerp(b2, sp)) > TJ_EPS:
							continue
						if absf(v.y - lerpf(a.y, b.y, sp)) > TJ_HEIGHT_TOL:
							continue
						found.append([sp, v])
			if not found.is_empty():
				found.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0])
				for f in found:
					poly.append(f[1])
				inserted = true
		if not inserted:
			out_g.append_array(PackedVector3Array(tri))
			out_s.append(acc.surf[t])
			continue
		acc.tj_fixed += 1
		var c: Vector3 = (tri[0] + tri[1] + tri[2]) / 3.0
		var front: Vector3 = (tri[2] - tri[0]).cross(tri[1] - tri[0])
		for i in poly.size():
			var p0: Vector3 = poly[i]
			var p1: Vector3 = poly[(i + 1) % poly.size()]
			if (p0 - c).cross(p1 - c).length_squared() < AREA_EPS * AREA_EPS * AREA_EPS:
				continue
			_facing_tri(out_g, c, p0, p1, front)
			out_s.append(acc.surf[t])
	acc.ground = out_g
	acc.surf = out_s


## Emits deck triangle [param v] of segment [param seg], split in four while the frozen height at an
## edge midpoint or the centroid is more than REFINE_TOL off its plane (REFINE_DEPTH levels).
## Mid heights come from the same segment, so the frozen surface is sampled exactly.
static func _refine_tri(bp: BakePath, seg: int, v: Array[Vector3], depth: int, local: Array[Region],
		level_tol: float, pad_tol: float, road_id: int, acc: Acc) -> void:
	if depth < REFINE_DEPTH:
		var dist: PackedFloat32Array = PackedFloat32Array([0.0])
		var mids: Array[Vector3] = []
		var worst: float = 0.0
		for i in 3:
			var a: Vector3 = v[i]
			var b: Vector3 = v[(i + 1) % 3]
			var m2: Vector2 = Vector2((a.x + b.x) * 0.5, (a.z + b.z) * 0.5)
			var hm: float = _deck_height(bp, m2, seg, 0.0, dist)
			mids.append(Vector3(m2.x, hm, m2.y))
			worst = maxf(worst, absf(hm - (a.y + b.y) * 0.5))
		var c2: Vector2 = Vector2((v[0].x + v[1].x + v[2].x) / 3.0, (v[0].z + v[1].z + v[2].z) / 3.0)
		worst = maxf(worst, absf(_deck_height(bp, c2, seg, 0.0, dist) - (v[0].y + v[1].y + v[2].y) / 3.0))
		if worst > REFINE_TOL:
			acc.refined += 1
			var kids: Array = [[v[0], mids[0], mids[2]], [mids[0], v[1], mids[1]], [mids[2], mids[1], v[2]], [mids[0], mids[1], mids[2]]]
			for k in kids:
				var kv: Array[Vector3] = [k[0], k[1], k[2]]
				_refine_tri(bp, seg, kv, depth + 1, local, level_tol, pad_tol, road_id, acc)
			return
	_ground_tri(v[0], v[1], v[2], local, level_tol, pad_tol, road_id, acc)


## A deck triangle at least one corner of which another road owns. Ownership is not convex inside a
## cell (it is bounded by the other deck's edge and the frozen keep band, two lines that can cross
## at a shallow angle), so a cell whose three corners are all owned can still hold a sliver this
## road keeps. While the edge midpoints or the centroid disagree with the corners, the triangle is
## split in four (SEAM_DEPTH levels, mid heights from this segment); a leaf is then kept, cut on the
## ownership line (_cut_tri) or dropped. Every leaf records seam-coverage probes (step_cast check).
static func _seam_tri(bp: BakePath, seg: int, yc: float, v: Array[Vector3], flags: Array[int], depth: int,
		others: Array[BakePath], sep: float, keep_band: float, switch_margin: float, local: Array[Region],
		level_tol: float, pad_tol: float, road_id: int, acc: Acc, oi: int = -1, oseg: int = -1) -> void:
	var dist: PackedFloat32Array = PackedFloat32Array([0.0])
	if oi < 0:
		# The owning road and its segment near this cell, found once (whole search), then searched in a
		# window by every probe of the cell's subdivision.
		for i in 3:
			if flags[i] == 1:
				var found: PackedInt32Array = _owner_of(bp, Vector2(v[i].x, v[i].z), seg, yc, others, sep, keep_band, switch_margin, -1, -1)
				if not found.is_empty():
					oi = found[0]
					oseg = found[1]
					break
	if depth < SEAM_DEPTH:
		var mids: Array[Vector3] = []
		var mflags: Array[int] = []
		var uniform: bool = flags[0] == flags[1] and flags[1] == flags[2]
		for i in 3:
			var m2: Vector2 = (Vector2(v[i].x, v[i].z) + Vector2(v[(i + 1) % 3].x, v[(i + 1) % 3].z)) * 0.5
			mids.append(Vector3(m2.x, _deck_height(bp, m2, seg, 0.0, dist), m2.y))
			var mf: int = 1 if _owned_at(bp, m2, seg, yc, others, sep, keep_band, switch_margin, oi, oseg) else 0
			mflags.append(mf)
			if mf != flags[0]:
				uniform = false
		var c2: Vector2 = (Vector2(v[0].x, v[0].z) + Vector2(v[1].x, v[1].z) + Vector2(v[2].x, v[2].z)) / 3.0
		if (1 if _owned_at(bp, c2, seg, yc, others, sep, keep_band, switch_margin, oi, oseg) else 0) != flags[0]:
			uniform = false
		if uniform and oi >= 0:
			# Samples can step over a thin wedge of the other ownership. Every quantity the ownership
			# rule compares is a distance or a difference of two, so it changes by at most 2 m per m:
			# when the smallest of them at the centroid is under twice the cell's radius, an
			# ownership boundary may cross the cell, and it is split.
			var radius: float = 0.0
			for i in 3:
				radius = maxf(radius, c2.distance_to(Vector2(v[i].x, v[i].z)))
			if _seam_margin(bp, c2, seg, yc, others[oi], oseg, sep, keep_band, switch_margin) < 2.0 * radius:
				uniform = false
		if not uniform:
			acc.seam_splits += 1
			var kids: Array = [[v[0], mids[0], mids[2], flags[0], mflags[0], mflags[2]],
					[mids[0], v[1], mids[1], mflags[0], flags[1], mflags[1]],
					[mids[2], mids[1], v[2], mflags[2], mflags[1], flags[2]],
					[mids[0], mids[1], mids[2], mflags[0], mflags[1], mflags[2]]]
			for k in kids:
				var kv: Array[Vector3] = [k[0], k[1], k[2]]
				var kf: Array[int] = [int(k[3]), int(k[4]), int(k[5])]
				if kf[0] + kf[1] + kf[2] == 0 and depth + 1 >= SEAM_DEPTH:
					_ground_tri(kv[0], kv[1], kv[2], local, level_tol, pad_tol, road_id, acc)
				else:
					_seam_tri(bp, seg, yc, kv, kf, depth + 1, others, sep, keep_band, switch_margin, local, level_tol, pad_tol, road_id, acc, oi, oseg)
			return
	var n_own: int = flags[0] + flags[1] + flags[2]
	if n_own == 0:
		_ground_tri(v[0], v[1], v[2], local, level_tol, pad_tol, road_id, acc)
	elif n_own == 3:
		acc.deck_dropped_overlap += 1
		# The owning road must cover this cell: probe its centroid at that road's frozen height.
		var c3: Vector2 = (Vector2(v[0].x, v[0].z) + Vector2(v[1].x, v[1].z) + Vector2(v[2].x, v[2].z)) / 3.0
		if oi >= 0:
			_seam_probe(bp, seg, yc, c3, others[oi], oseg, sep, keep_band, switch_margin, acc)
	else:
		_cut_tri(bp, seg, yc, v, flags, others, sep, keep_band, switch_margin, local, level_tol, pad_tol, road_id, acc)


## The smallest absolute value at [param p] of the quantities the ownership rule between road
## [param bp] and road [param o] compares (_frozen_prefers and the deck test of _owner_of): the other
## deck's edge, both excesses, the main road's keep band, the nearer-centre-line and switch-margin
## differences. Ownership cannot change within this distance / 2 of p.
static func _seam_margin(bp: BakePath, p: Vector2, seg: int, yc: float, o: BakePath, oseg: int, sep: float,
		keep_band: float, switch_margin: float) -> float:
	var own: PackedFloat32Array = bp.nearest(p, seg, NEAREST_WINDOW)
	var oh: PackedFloat32Array = o.nearest(p, oseg, 2 * NEAREST_WINDOW, yc - sep, yc + sep)
	if own[0] < 0.0 or oh[0] < 0.0:
		return 0.0
	var a_d: float = own[2]
	var b_d: float = oh[2]
	var a_ex: float = a_d - bp.wall(int(own[0]), own[1], int(own[3]))
	var b_ex: float = b_d - o.wall(int(oh[0]), oh[1], int(oh[3]))
	var m: float = absf(b_d - o.reach(int(oh[0]), oh[1]))
	m = minf(m, absf(a_ex))
	m = minf(m, absf(b_ex))
	m = minf(m, absf(a_d - b_d))
	m = minf(m, absf(a_ex - b_ex))
	var main_ex: float = a_ex if bp.index == -1 else b_ex
	var main_d: float = a_d if bp.index == -1 else b_d
	var br_ex: float = b_ex if bp.index == -1 else a_ex
	var br_d: float = b_d if bp.index == -1 else a_d
	m = minf(m, absf(main_ex + keep_band))
	m = minf(m, absf(br_d + switch_margin - main_d))
	m = minf(m, absf(main_ex - br_ex - switch_margin))
	return m


## Ownership of [param p] by others[oi] (windowed at [param oseg]) when the cell's owner is known,
## else by any other road (whole search).
static func _owned_at(bp: BakePath, p: Vector2, seg: int, yc: float, others: Array[BakePath], sep: float,
		keep_band: float, switch_margin: float, oi: int, oseg: int) -> bool:
	if oi < 0:
		return _owned_by_other(bp, p, seg, yc, others, sep, keep_band, switch_margin)
	return not _owner_of(bp, p, seg, yc, others, sep, keep_band, switch_margin, oi, oseg).is_empty()


## Records a seam-coverage probe at [param p] between road [param bp] (segment [param seg]) and
## road [param o] (near [param oseg]). The holding deck is the one the frozen hint-free query gives
## the point to at exactly this xz (_frozen_prefers, the same rule the cut uses), when that road's
## deck holds it; a point the frozen game puts off every deck is not probed. The other road's height
## is kept as a legitimate alternative when its deck holds the point too.
static func _seam_probe(bp: BakePath, seg: int, yc: float, p: Vector2, o: BakePath, oseg: int, sep: float,
		keep_band: float, switch_margin: float, acc: Acc) -> void:
	var own: PackedFloat32Array = bp.nearest(p, seg, NEAREST_WINDOW)
	var oh: PackedFloat32Array = o.nearest(p, oseg, 2 * NEAREST_WINDOW, yc - sep, yc + sep)
	if own[0] < 0.0 or oh[0] < 0.0:
		return
	var own_seg: int = int(own[0])
	var o_seg: int = int(oh[0])
	var own_ex: float = own[2] - bp.wall(own_seg, own[1], int(own[3]))
	var o_ex: float = oh[2] - o.wall(o_seg, oh[1], int(oh[3]))
	var own_deck: bool = own[2] <= bp.reach(own_seg, own[1])
	var o_deck: bool = oh[2] <= o.reach(o_seg, oh[1])
	var own_h: float = bp.height(own_seg, own[1], own[2] * own[3])
	var o_h: float = o.height(o_seg, oh[1], oh[2] * oh[3])
	var o_wins: bool = _frozen_prefers(o.index, oh[2], o_ex, bp.index, own[2], own_ex, keep_band, switch_margin)
	if o_wins and o_deck:
		acc.seam_points.append(Vector3(p.x, o_h, p.y))
		acc.seam_alt.append(own_h if own_deck else NAN)
	elif not o_wins and own_deck:
		acc.seam_points.append(Vector3(p.x, own_h, p.y))
		acc.seam_alt.append(o_h if o_deck else NAN)


## Emits the part of deck triangle [param v] (vertex ownership flags [param own_flags], 1 = owned by
## another road) that this road keeps: each edge whose ends disagree is cut where the frozen
## ownership flips (bisection), so two overlapping decks meet on the frozen switch line with no gap
## and no double deck (the frozen surface steps there).
static func _cut_tri(bp: BakePath, seg: int, yc: float, v: Array[Vector3], own_flags: Array[int], others: Array[BakePath],
		sep: float, keep_band: float, switch_margin: float, local: Array[Region], level_tol: float, pad_tol: float,
		road_id: int, acc: Acc) -> void:
	var poly: Array[Vector3] = []
	var dist: PackedFloat32Array = PackedFloat32Array([0.0])
	for i in 3:
		var k: int = (i + 1) % 3
		if own_flags[i] == 0:
			poly.append(v[i])
		if own_flags[i] != own_flags[k]:
			var keep_p: Vector2 = Vector2(v[i].x, v[i].z) if own_flags[i] == 0 else Vector2(v[k].x, v[k].z)
			var drop_p: Vector2 = Vector2(v[k].x, v[k].z) if own_flags[i] == 0 else Vector2(v[i].x, v[i].z)
			var owner: PackedInt32Array = _owner_of(bp, drop_p, seg, yc, others, sep, keep_band, switch_margin, -1, -1)
			if owner.is_empty():
				# No owner found at the flagged end (float edge case): keep the whole edge, never a hole.
				keep_p = drop_p
			for it in CUT_ITERATIONS:
				if owner.is_empty():
					break
				var mid: Vector2 = (keep_p + drop_p) * 0.5
				if not _owner_of(bp, mid, seg, yc, others, sep, keep_band, switch_margin, owner[0], owner[1]).is_empty():
					drop_p = mid
				else:
					keep_p = mid
			var cut_p: Vector2 = keep_p.move_toward(drop_p, SEAM_OVERLAP)
			poly.append(Vector3(cut_p.x, _deck_height(bp, cut_p, seg, 0.0, dist), cut_p.y))
			# Seam probe just on this road's side of the cut point, at this road's frozen height.
			var inward: Vector2 = Vector2(v[i].x, v[i].z) if own_flags[i] == 0 else Vector2(v[k].x, v[k].z)
			if inward.distance_to(keep_p) > SEAM_PROBE_IN * 2.0 and not owner.is_empty():
				var q2: Vector2 = keep_p.move_toward(inward, SEAM_PROBE_IN)
				_seam_probe(bp, seg, yc, q2, others[owner[0]], owner[1], sep, keep_band, switch_margin, acc)
	acc.deck_cut += 1
	for i in range(1, poly.size() - 1):
		_ground_tri(poly[0], poly[i], poly[i + 1], local, level_tol, pad_tol, road_id, acc)


## True when the frozen hint-free TrackModel.query gives a point to road [param b_index] (distance
## [param b_dist] to its centre line, excess [param b_ex] past its wall) rather than road
## [param a_index]: inside beats outside, the nearer centre line wins among inside roads, and the
## main road (the query's current road without a hint) keeps the point while the kart is
## keep_band inside it or within switch_margin (TrackModel.query and _better).
static func _frozen_prefers(b_index: int, b_dist: float, b_ex: float, a_index: int, a_dist: float, a_ex: float,
		keep_band: float, switch_margin: float) -> bool:
	var b_in: bool = b_ex <= 0.0
	var a_in: bool = a_ex <= 0.0
	var b_better: bool = b_in if b_in != a_in else (b_dist < a_dist if b_in else b_ex < a_ex)
	if a_index == -1:
		# a is the current road: b must beat it and survive the keep rules.
		if not b_better:
			return false
		if a_ex <= -keep_band:
			return false
		if a_in and b_in and b_dist + switch_margin > a_dist:
			return false
		if b_ex > 0.0 and a_ex - b_ex <= switch_margin:
			return false
		return true
	if b_index == -1:
		# b is the current road: it keeps the point unless a beats it past the keep rules.
		if not (not b_better):
			return true
		if b_ex <= -keep_band:
			return true
		if b_in and a_in and a_dist + switch_margin > b_dist:
			return true
		if a_ex > 0.0 and b_ex - a_ex <= switch_margin:
			return true
		return false
	return b_better


## Emits deck triangle (a, b, c), clipped into its surface regions.
static func _ground_tri(a: Vector3, b: Vector3, c: Vector3, local: Array[Region], level_tol: float,
		pad_tol: float, road_id: int, acc: Acc) -> void:
	var a2: Vector2 = Vector2(a.x, a.z)
	var b2: Vector2 = Vector2(b.x, b.z)
	var c2: Vector2 = Vector2(c.x, c.z)
	var tri: PackedVector2Array = PackedVector2Array([a2, b2, c2])
	var tb: Rect2 = _rect_of(tri)
	var centroid: Vector2 = (a2 + b2 + c2) / 3.0
	var hc: float = (a.y + b.y + c.y) / 3.0
	var hits: Array[Region] = []
	for r in local:
		if r.bounds.intersects(tb, true) and _region_level(r, centroid, hc, level_tol, pad_tol):
			hits.append(r)
	if hits.is_empty():
		_emit_up(acc, a, b, c, road_id)
		return
	acc.clipped += 1
	var pieces: Array = []  # [PackedVector2Array, id]
	var remaining: Array[PackedVector2Array] = [tri]
	for r in hits:
		var next_rem: Array[PackedVector2Array] = []
		for poly in remaining:
			var area_in: float = 0.0
			for piece in Geometry2D.intersect_polygons(poly, r.polygon):
				pieces.append([piece, r.surface_id])
				area_in += absf(_area(piece))
			var area_out: float = 0.0
			for rest in Geometry2D.clip_polygons(poly, r.polygon):
				next_rem.append(rest)
				area_out += absf(_area(rest))
			var area_all: float = absf(_area(poly))
			if absf(area_in + area_out - area_all) > maxf(AREA_EPS, CLIP_AREA_REL * area_all):
				# A hole (region enclosed by the triangle): classify the triangle by its centroid.
				acc.fallback += 1
				_emit_up(acc, a, b, c, _centroid_id(centroid, hits, road_id))
				return
		remaining = next_rem
	for poly in remaining:
		pieces.append([poly, road_id])
	var tris: Array = []  # [PackedVector2Array, PackedInt32Array, id]
	for pc in pieces:
		var poly2: PackedVector2Array = pc[0]
		if absf(_area(poly2)) < AREA_EPS * AREA_EPS:
			continue
		var idx: PackedInt32Array = Geometry2D.triangulate_polygon(poly2)
		if idx.is_empty():
			# A piece Geometry2D cannot triangulate: classify the whole triangle by its centroid.
			acc.fallback += 1
			_emit_up(acc, a, b, c, _centroid_id(centroid, hits, road_id))
			return
		tris.append([poly2, idx, pc[1]])
	for tr in tris:
		var poly2: PackedVector2Array = tr[0]
		var idx: PackedInt32Array = tr[1]
		for k in range(0, idx.size(), 3):
			_emit_up(acc, _lift(poly2[idx[k]], a, b, c), _lift(poly2[idx[k + 1]], a, b, c), _lift(poly2[idx[k + 2]], a, b, c), int(tr[2]))


static func _centroid_id(centroid: Vector2, hits: Array[Region], road_id: int) -> int:
	for r in hits:
		if Geometry2D.is_point_in_polygon(centroid, r.polygon):
			return r.surface_id
	return road_id


static func _area(poly: PackedVector2Array) -> float:
	var s: float = 0.0
	for i in poly.size():
		s += poly[i].cross(poly[(i + 1) % poly.size()])
	return s * 0.5


## Point [param q] (XZ) on the plane of triangle (a, b, c).
static func _lift(q: Vector2, a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	var v0: Vector2 = Vector2(b.x - a.x, b.z - a.z)
	var v1: Vector2 = Vector2(c.x - a.x, c.z - a.z)
	var v2: Vector2 = q - Vector2(a.x, a.z)
	var den: float = v0.cross(v1)
	if absf(den) < AREA_EPS * AREA_EPS:
		return Vector3(q.x, a.y, q.y)
	var wb: float = v2.cross(v1) / den
	var wc: float = v0.cross(v2) / den
	return Vector3(q.x, a.y + wb * (b.y - a.y) + wc * (c.y - a.y), q.y)


static func _emit_up(acc: Acc, a: Vector3, b: Vector3, c: Vector3, sid: int) -> void:
	if (b - a).cross(c - a).length_squared() < AREA_EPS * AREA_EPS:
		return
	_facing_tri(acc.ground, a, b, c, Vector3.UP)
	acc.surf.append(sid)


## Appends (a, b, c) or (a, c, b), whichever has its Godot front ((c - a) x (b - a)) along facing.
static func _facing_tri(faces: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3, facing: Vector3) -> void:
	if (c - a).cross(b - a).dot(facing) > 0.0:
		faces.append(a)
		faces.append(b)
		faces.append(c)
	else:
		faces.append(a)
		faces.append(c)
		faces.append(b)


static func _bake_ramp(bp: BakePath, rp: Dictionary, ramp_id: int, acc: Acc) -> void:
	var from: float = float(rp["from"])
	var length: float = float(rp["length"])
	var lip: float = float(rp["lip"])
	var lat_c: float = float(rp["lateral"])
	var half_w: float = float(rp["half"])
	if length <= 0.0:
		return
	var k_n: int = maxi(1, ceili(length / RAMP_STEP))
	var max_w: float = 2.0 * half_w
	if half_w <= 0.0:
		for i in bp.points.size():
			max_w = maxf(max_w, 2.0 * (bp.half[i] + bp.curb))
	var m_lat: int = maxi(1, ceili(max_w / LAT_STEP))
	var tops: Array[PackedVector3Array] = []
	var bases: Array[PackedVector3Array] = []
	var fwd: Vector3 = Vector3.ZERO
	var nrm: Vector3 = Vector3.ZERO
	for k in k_n + 1:
		var u: float = length * float(k) / float(k_n)
		var st: Vector2 = bp.seg_t_at(from + u)
		var seg: int = int(st.x)
		var r: float = bp.reach(seg, st.y)
		var lo: float = lat_c - half_w if half_w > 0.0 else -r
		var hi: float = lat_c + half_w if half_w > 0.0 else r
		var top: PackedVector3Array = PackedVector3Array()
		var base: PackedVector3Array = PackedVector3Array()
		for j in m_lat + 1:
			var v: Vector3 = _deck_vertex(bp, seg, st.y, lerpf(lo, hi, float(j) / float(m_lat)))
			base.append(v + Vector3.UP * RAMP_LIFT)
			top.append(v + Vector3.UP * (RAMP_LIFT + lip * u / length))
		tops.append(top)
		bases.append(base)
		var t2: Vector2 = (bp.points[bp.nxt(seg)] - bp.points[seg]).normalized()
		fwd = Vector3(t2.x, 0.0, t2.y)
		var n2: Vector2 = bp.normal(seg, st.y).normalized()
		nrm = Vector3(n2.x, 0.0, n2.y)
	for k in k_n:
		for j in m_lat:
			_emit_up(acc, tops[k][j], tops[k + 1][j], tops[k][j + 1], ramp_id)
			_emit_up(acc, tops[k][j + 1], tops[k + 1][j], tops[k + 1][j + 1], ramp_id)
		# Side faces at the low and high lateral edge.
		_facing_quad(acc, bases[k][0], bases[k + 1][0], tops[k][0], tops[k + 1][0], -nrm, ramp_id)
		_facing_quad(acc, bases[k][m_lat], bases[k + 1][m_lat], tops[k][m_lat], tops[k + 1][m_lat], nrm, ramp_id)
	for j in m_lat:
		_facing_quad(acc, bases[k_n][j], bases[k_n][j + 1], tops[k_n][j], tops[k_n][j + 1], fwd, ramp_id)


## Ground quad (b0, b1 bottom; t0, t1 top) facing [param facing].
static func _facing_quad(acc: Acc, b0: Vector3, b1: Vector3, t0: Vector3, t1: Vector3, facing: Vector3, sid: int) -> void:
	if (t0 - b0).length_squared() < AREA_EPS * AREA_EPS and (t1 - b1).length_squared() < AREA_EPS * AREA_EPS:
		return
	for tri in [[b0, t0, b1], [b1, t0, t1]]:
		if (tri[1] - tri[0]).cross(tri[2] - tri[0]).length_squared() < AREA_EPS * AREA_EPS:
			continue
		_facing_tri(acc.ground, tri[0], tri[1], tri[2], facing)
		acc.surf.append(sid)


static func _bake_zone_ground(r: Region, acc: Acc) -> void:
	for k in range(0, r.triangles.size(), 3):
		var v: Array[Vector3] = []
		for e in 3:
			var p: Vector2 = r.polygon[r.triangles[k + e]]
			var h: float = r.vertex_heights[r.triangles[k + e]] if not r.vertex_heights.is_empty() else r.flat_height
			v.append(Vector3(p.x, h, p.y))
		_emit_up(acc, v[0], v[1], v[2], r.surface_id)


static func _bake_floor(paths: Array[BakePath], ground_y: float, road_id: int, acc: Acc) -> void:
	var r: Rect2 = paths[0].bounds
	for bp in paths:
		r = r.merge(bp.bounds)
	r = r.grow(FLOOR_MARGIN)
	var a: Vector3 = Vector3(r.position.x, ground_y, r.position.y)
	var b: Vector3 = Vector3(r.end.x, ground_y, r.position.y)
	var c: Vector3 = Vector3(r.end.x, ground_y, r.end.y)
	var d: Vector3 = Vector3(r.position.x, ground_y, r.end.y)
	_emit_up(acc, a, b, c, road_id)
	_emit_up(acc, a, c, d, road_id)


static func _wall_faces(acc: Acc, attr_id: int) -> PackedVector3Array:
	if not acc.walls.has(attr_id):
		acc.walls[attr_id] = PackedVector3Array()
	return acc.walls[attr_id]


static func _bake_walls(bp: BakePath, paths: Array[BakePath], sep: float, ground_y: float, attr_id: int, acc: Acc) -> void:
	var faces: PackedVector3Array = _wall_faces(acc, attr_id)
	var shared: Dictionary = {}  # "vi:side" -> barrier point, shared by the two segments of a sample
	for seg in bp.seg_count():
		var k_n: int = maxi(1, ceili((bp.cumulative[seg + 1] - bp.cumulative[seg]) / WALL_STEP))
		for side in [1, -1]:
			if not bp.opening.is_empty() and (bp.opening[seg] & (1 if side > 0 else 2)) != 0:
				acc.walls_dropped_opening += k_n
				continue
			var p_prev: Vector2 = _wall_point(bp, seg, 0.0, side, shared, seg)
			for a in k_n:
				var f0: float = float(a) / float(k_n)
				var f1: float = float(a + 1) / float(k_n)
				var p0: Vector2 = p_prev
				var p1: Vector2 = _wall_point(bp, seg, f1, side, shared, bp.nxt(seg) if a + 1 == k_n else -1)
				p_prev = p1
				var leaves: Array = []
				_wall_refine(bp, seg, side, f0, p0, f1, p1, 0, leaves, acc)
				for lf in leaves:
					_wall_piece(bp, paths, sep, ground_y, seg, side, lf[0], lf[2], lf[1], lf[3], faces, acc)
	acc.walls[attr_id] = faces


## Fraction (0..1) of the way from [param a] (outside every other corridor) toward [param b] where
## the wall piece enters another road's corridor (_inside_other); bisection. Searches up to the
## middle when [param b] itself is outside (the piece dips in and out).
static func _junction_fraction(bp: BakePath, paths: Array[BakePath], a: Vector2, b: Vector2, h: float, sep: float) -> float:
	var hi: float = 1.0 if _inside_other(bp, paths, b, h, sep) else 0.5
	var lo: float = 0.0
	if not _inside_other(bp, paths, a.lerp(b, hi), h, sep):
		return hi
	for it in ROOT_BISECT:
		var mid: float = (lo + hi) * 0.5
		if _inside_other(bp, paths, a.lerp(b, mid), h, sep):
			hi = mid
		else:
			lo = mid
	return lo


## Fraction (0..0.5) of the way from [param a] (on the barrier) toward [param b] where the chord
## enters the road's corridor (frozen excess below -JUNCTION_EPS); bisection.
static func _clip_fraction(bp: BakePath, a: Vector2, b: Vector2, seg: int) -> float:
	var lo: float = 0.0
	var hi: float = 0.5
	if _excess_at(bp, a.lerp(b, hi), seg, true) >= -JUNCTION_EPS:
		return hi
	for it in ROOT_BISECT:
		var mid: float = (lo + hi) * 0.5
		if _excess_at(bp, a.lerp(b, mid), seg, true) >= -JUNCTION_EPS:
			lo = mid
		else:
			hi = mid
	return lo


## Splits wall piece (fa, pa) - (fb, pb) of segment [param seg] while the frozen barrier at its
## middle is more than WALL_REFINE_TOL off its chord (WALL_REFINE_DEPTH levels); appends
## [fa, pa, fb, pb] leaves to [param out].
static func _wall_refine(bp: BakePath, seg: int, side: int, fa: float, pa: Vector2, fb: float, pb: Vector2, depth: int,
		out: Array, acc: Acc) -> void:
	if depth < WALL_REFINE_DEPTH:
		var fm: float = (fa + fb) * 0.5
		var pm: Vector2 = _barrier(bp, seg, fm, side, true)
		if pm.distance_to((pa + pb) * 0.5) > WALL_REFINE_TOL:
			acc.wall_refined += 1
			_wall_refine(bp, seg, side, fa, pa, fm, pm, depth + 1, out, acc)
			_wall_refine(bp, seg, side, fm, pm, fb, pb, depth + 1, out, acc)
			return
	out.append([fa, pa, fb, pb])


## Emits one wall piece p0 (cross-section f0) - p1 (f1) of segment [param seg] on [param side]:
## clipped at a junction with another road's corridor and where its chord cuts back into the road.
static func _wall_piece(bp: BakePath, paths: Array[BakePath], sep: float, ground_y: float, seg: int, side: int,
		f0: float, f1: float, p0: Vector2, p1: Vector2, faces: PackedVector3Array, acc: Acc) -> void:
	var w0: float = bp.wall(seg, f0, side)
	var w1: float = bp.wall(seg, f1, side)
	var h0: float = bp.height(seg, f0, w0 * side)
	var h1: float = bp.height(seg, f1, w1 * side)
	var mid: Vector2 = (p0 + p1) * 0.5
	var hm: float = (bp.centre_height(seg, f0) + bp.centre_height(seg, f1)) * 0.5
	var in0: bool = _inside_other(bp, paths, p0, hm, sep)
	var in1: bool = _inside_other(bp, paths, p1, hm, sep)
	var in_m: bool = _inside_other(bp, paths, mid, hm, sep)
	if in0 and in1 and in_m:
		acc.walls_dropped_junction += 1
		return
	if in0 or in1 or in_m:
		# Partly inside another road's corridor: keep the parts outside it, so the wall
		# runs exactly up to the junction (clipped, not dropped).
		acc.walls_clipped_junction += 1
		var cw0: float = 0.0 if in0 else _junction_fraction(bp, paths, p0, p1, hm, sep)
		var cw1: float = 0.0 if in1 else _junction_fraction(bp, paths, p1, p0, hm, sep)
		var nn: Vector2 = bp.normal(seg, (f0 + f1) * 0.5).normalized() * float(-side)
		var jb0: Vector3 = Vector3(p0.x, h0 - WALL_BELOW, p0.y)
		var jb1: Vector3 = Vector3(p1.x, h1 - WALL_BELOW, p1.y)
		var jt0: Vector3 = Vector3(p0.x, h0 + WALL_HEIGHT, p0.y)
		var jt1: Vector3 = Vector3(p1.x, h1 + WALL_HEIGHT, p1.y)
		if cw0 > 0.0:
			_wall_quad(faces, jb0, jb0.lerp(jb1, cw0), jt0, jt0.lerp(jt1, cw0), Vector3(nn.x, 0.0, nn.y))
		if cw1 > 0.0:
			_wall_quad(faces, jb1.lerp(jb0, cw1), jb1, jt1.lerp(jt0, cw1), jt1, Vector3(nn.x, 0.0, nn.y))
		return
	var open: bool = w0 > bp.reach(seg, f0) + OPEN_EPS or w1 > bp.reach(seg, f1) + OPEN_EPS
	var bot0: float = minf(h0, ground_y) - WALL_BELOW if open else h0 - WALL_BELOW
	var bot1: float = minf(h1, ground_y) - WALL_BELOW if open else h1 - WALL_BELOW
	var n2: Vector2 = bp.normal(seg, (f0 + f1) * 0.5).normalized() * float(-side)
	var b0: Vector3 = Vector3(p0.x, bot0, p0.y)
	var b1: Vector3 = Vector3(p1.x, bot1, p1.y)
	var t0: Vector3 = Vector3(p0.x, h0 + WALL_HEIGHT, p0.y)
	var t1: Vector3 = Vector3(p1.x, h1 + WALL_HEIGHT, p1.y)
	if _excess_at(bp, mid, seg, true) < -JUNCTION_EPS:
		# The chord between two barrier points cuts back into the road (a corner tighter than
		# the wall offset): keep only its two ends up to where they enter the corridor.
		acc.walls_clipped += 1
		var u0: float = _clip_fraction(bp, p0, p1, seg)
		var u1: float = _clip_fraction(bp, p1, p0, seg)
		if u0 > 0.0:
			_wall_quad(faces, b0, b0.lerp(b1, u0), t0, t0.lerp(t1, u0), Vector3(n2.x, 0.0, n2.y))
		if u1 > 0.0:
			_wall_quad(faces, b1.lerp(b0, u1), b1, t1.lerp(t0, u1), t1, Vector3(n2.x, 0.0, n2.y))
		return
	_wall_quad(faces, b0, b1, t0, t1, Vector3(n2.x, 0.0, n2.y))


## The wall point (frozen barrier, _barrier) of cross-section (seg, f) on [param side]; at a sample
## ([param vi] >= 0) computed once and shared by both segments, so consecutive wall pieces meet.
static func _wall_point(bp: BakePath, seg: int, f: float, side: int, shared: Dictionary, vi: int) -> Vector2:
	if vi < 0:
		return _barrier(bp, seg, f, side, true)
	var key: String = "%d:%d" % [vi, side]
	if not shared.has(key):
		shared[key] = _barrier(bp, seg, f, side, true)
	return shared[key]


## True when [param p] (centre-line height [param h]) lies inside another road's corridor at its level.
static func _inside_other(bp: BakePath, paths: Array[BakePath], p: Vector2, h: float, sep: float) -> bool:
	for other in paths:
		if other == bp:
			continue
		if other.excess(p, h - sep, h + sep) < -JUNCTION_EPS:
			return true
	return false


static func _wall_quad(faces: PackedVector3Array, b0: Vector3, b1: Vector3, t0: Vector3, t1: Vector3, facing: Vector3) -> void:
	_facing_tri(faces, b0, t0, b1, facing)
	_facing_tri(faces, b1, t0, t1, facing)


static func _bake_fence(z: Dictionary, r: Region, paths: Array[BakePath], sep: float, attr_id: int, acc: Acc) -> void:
	var faces: PackedVector3Array = _wall_faces(acc, attr_id)
	var edges: PackedVector2Array = _v2s(z["fence_edges"])
	for e in range(0, edges.size() - 1, 2):
		var a: Vector2 = edges[e]
		var b: Vector2 = edges[e + 1]
		var n_piece: int = maxi(1, ceili(a.distance_to(b) / WALL_STEP))
		var d: Vector2 = (b - a).normalized()
		var n2: Vector2 = Vector2(-d.y, d.x)
		var probe: Vector2 = (a + b) * 0.5 + n2 * JUNCTION_EPS
		if not Geometry2D.is_point_in_polygon(probe, r.polygon):
			n2 = -n2
		for k in n_piece:
			var p0: Vector2 = a.lerp(b, float(k) / float(n_piece))
			var p1: Vector2 = a.lerp(b, float(k + 1) / float(n_piece))
			var mid: Vector2 = (p0 + p1) * 0.5
			var h0: float = _zone_height(r, p0)
			var h1: float = _zone_height(r, p1)
			var hm: float = (h0 + h1) * 0.5
			var drop: bool = false
			for bp in paths:
				if bp.deck_excess(mid, hm - sep, hm + sep) <= 0.0 or (bp.index >= 0 and bp.excess(mid, hm - sep, hm + sep) < -JUNCTION_EPS):
					drop = true
					break
			if drop:
				acc.fences_dropped += 1
				continue
			_wall_quad(faces, Vector3(p0.x, h0 - WALL_BELOW, p0.y), Vector3(p1.x, h1 - WALL_BELOW, p1.y),
					Vector3(p0.x, h0 + WALL_HEIGHT, p0.y), Vector3(p1.x, h1 + WALL_HEIGHT, p1.y), Vector3(n2.x, 0.0, n2.y))
	acc.walls[attr_id] = faces


## The MoverDef of mover doc [param m] with id [param id], or null for an unknown kind.
static func _mover_from(m: Dictionary, id: int, deck_thickness: float, road_id: int, wall_id: int) -> MoverDef:
	var md: MoverDef = MoverDef.new()
	md.id = id
	md.period = float(m["period"])
	md.surface_id = road_id
	md.wall_attr_id = wall_id
	var kind: String = str(m["kind"])
	var key_t: Array = m["key_t"]
	var pos: Array = m["key_pos"]
	var prog: Array = m["key_progress"]
	var tan_k: Array = m["key_tangent"]
	var dist: Array = m["key_distance"]
	var kt: PackedFloat32Array = PackedFloat32Array()
	var kp: PackedVector3Array = PackedVector3Array()
	var kr: PackedVector4Array = PackedVector4Array()
	for i in key_t.size():
		var p3: Vector3 = Vector3(float(pos[i * 3]), float(pos[i * 3 + 1]), float(pos[i * 3 + 2]))
		var t2: Vector2 = Vector2(float(tan_k[i * 2]), float(tan_k[i * 2 + 1]))
		var progress: float = float(prog[i])
		var basis: Basis = Basis.IDENTITY
		var centre: Vector3 = p3
		match kind:
			"gate":
				if str(m["hit_effect"]) == "stop":
					var lt: Vector2 = Vector2(float(m["line_tangent"][0]), float(m["line_tangent"][1]))
					var lp: Array = m["line_point"]
					basis = _road_basis(lt)
					md.shape = MoverDef.Shape.BOX
					md.half_extents = Vector3(float(m["line_wall_offset"]), float(m["grille_height"]) * 0.5,
							maxf((float(m["path_to"]) - float(m["path_from"])) * 0.5, MIN_GRILLE_HALF))
					centre = Vector3(float(lp[0]), float(lp[1]), float(lp[2])) \
							+ Vector3.UP * (float(m["lift_height"]) * (1.0 - progress) + float(m["grille_height"]) * 0.5)
					md.solid = true
				else:
					var ht: Vector2 = Vector2(float(m["hinge_tangent"][0]), float(m["hinge_tangent"][1]))
					var span: float = float(m["path_to"]) - float(m["path_from"])
					var theta: float = deg_to_rad(float(m["raised_angle_deg"]) * progress)
					basis = _road_basis(ht) * Basis(Vector3.RIGHT, -theta)
					md.shape = MoverDef.Shape.BOX
					md.half_extents = Vector3(float(m["deck_half_width"]), deck_thickness * 0.5, span * 0.5)
					centre = p3 + basis * Vector3(0.0, -deck_thickness * 0.5, span * 0.5)
					md.solid = true
			"barrel":
				var r: float = float(m["body_radius"])
				var tn: Vector3 = Vector3(t2.x, 0.0, t2.y)
				var lat3: Vector3 = Vector3(-t2.y, 0.0, t2.x)
				basis = Basis(tn, lat3, tn.cross(lat3)) * Basis(Vector3.UP, -float(dist[i]) / maxf(r, AREA_EPS))
				md.shape = MoverDef.Shape.CYLINDER
				md.radius = r
				md.half_height = float(m["body_length"]) * 0.5
				centre = p3 + Vector3.UP * r
				md.solid = bool(m["solid_body"])
			"burst":
				md.shape = MoverDef.Shape.CYLINDER
				md.radius = float(m["column_radius"])
				md.half_height = float(m["column_height"]) * 0.5
				centre = Vector3(p3.x, float(m["vent_height"]) + float(m["column_height"]) * (progress - 0.5), p3.z)
				md.solid = bool(m["solid_body"])
			"cart":
				basis = _road_basis(t2)
				md.shape = MoverDef.Shape.BOX
				md.half_extents = Vector3(float(m["cart_width"]) * 0.5, float(m["cart_height"]) * 0.5, float(m["cart_length"]) * 0.5)
				centre = p3 + Vector3.UP * float(m["cart_height"]) * 0.5
				md.solid = bool(m["solid_body"])
			_:
				return null
		var q: Quaternion = basis.orthonormalized().get_rotation_quaternion().normalized()
		kt.append(float(key_t[i]))
		kp.append(centre)
		kr.append(Vector4(q.x, q.y, q.z, q.w))
	md.key_t = kt
	md.key_pos = kp
	md.key_rot = kr
	return md


## Basis with local x = the road's left normal, y = up, z = x cross y (= minus the road tangent
## [param t2], XZ).
static func _road_basis(t2: Vector2) -> Basis:
	var x: Vector3 = Vector3(-t2.y, 0.0, t2.x).normalized()
	return Basis(x, Vector3.UP, x.cross(Vector3.UP))
