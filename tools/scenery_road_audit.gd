extends SceneTree
## Scenery-on-the-road audit (bugfix 2026-11-20). Run:
##   godot --headless --path . -s res://tools/scenery_road_audit.gd [-- --track=ID]
## Builds each track's TrackScenery headless (all tracks unless --track= is given) and lists every
## scenery mesh instance whose footprint overlaps the drivable area (inside the walls of the main
## road or any branch, the same corridor test as TrackScenery._clearance) while part of it is at
## kart height. The kart sim only collides with road walls, so such a prop is driven through.
## Item boxes, boost pads and hazards are not scenery (ItemManager and TrackMesh draw them).
## Observations only: it prints what it finds and always exits 0.
##
## Footprint = convex hull of the mesh's transformed vertices in the x-z plane (all scenery
## meshes are convex); height = the vertices' y range. Groups in the output:
##   ON ROAD    y range meets KART_BAND: a kart drives through it (must be 0 after the fix)
##   FLAT       top at or below FLAT_TOP: drive-over surface detail (rail sleepers), listed only
##   OVERHEAD   bottom at or above KART_BAND.y: above the karts (arch tops, beams), counted only
## --tag=NAME prints every piece of one prop tag with its smallest excess (positive = clear).

## Kart height band in meters (bottom, top) the audit checks.
const KART_BAND: Vector2 = Vector2(0.0, 2.0)
## A piece whose top is at or below this is flat surface detail (drive-over).
const FLAT_TOP: float = 0.3
## Boundary sample spacing of a footprint, meters.
const SAMPLE_STEP: float = 0.25
## A footprint whose centre is this much farther from the corridor than its radius is skipped.
const FAR_SLACK: float = 1.0

var _track: TrackModel
## --tag=NAME: also print every piece with that prop tag and its smallest corridor excess.
var _show_tag: String = ""


func _init() -> void:
	var ids: Array = TrackLibrary.ids()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--track="):
			ids = [a.substr("--track=".length())]
		elif a.begins_with("--tag="):
			_show_tag = a.substr("--tag=".length())
	var total_on: int = 0
	for id in ids:
		total_on += _audit(String(id))
	print("== TOTAL on-road scenery pieces at kart height: %d" % total_on)
	quit(0)


func _audit(id: String) -> int:
	var data: TrackData = TrackLibrary.load_track(id)
	if data == null:
		print("== %s: could not load" % id)
		return 0
	_track = TrackModel.new(data)
	var scenery := TrackScenery.new()
	scenery.audit_mode = true
	var t0: int = Time.get_ticks_msec()
	scenery.build(_track)
	var on_road: Array[String] = []
	var flat: Array[String] = []
	var overhead: Dictionary = {}
	var pieces: int = 0
	var per_tag: Dictionary = {}
	for child in scenery.get_children():
		if child is MultiMeshInstance3D:
			var mmi: MultiMeshInstance3D = child
			var mm: MultiMesh = mmi.multimesh
			var faces: PackedVector3Array = mm.mesh.get_faces()
			var tags: PackedStringArray = mmi.get_meta(&"prop_tags", PackedStringArray())
			var xforms: Array = mmi.get_meta(&"prop_xforms", [])
			for i in xforms.size():
				pieces += 1
				var tag: String = tags[i] if i < tags.size() else "?"
				per_tag[tag] = int(per_tag.get(tag, 0)) + 1
				_check(id, tag, String(mmi.name), i, mmi.transform * (xforms[i] as Transform3D), faces, on_road, flat, overhead)
		elif child is MeshInstance3D:
			var mi: MeshInstance3D = child
			pieces += 1
			_check(id, String(mi.name), "mesh", 0, mi.transform, mi.mesh.get_faces(), on_road, flat, overhead)
	print("== %s (%s): %d scenery pieces, built and checked in %d ms" % [data.display_name, id, pieces, Time.get_ticks_msec() - t0])
	var tag_counts: PackedStringArray = PackedStringArray()
	for tag in per_tag.keys():
		tag_counts.append("%s=%d" % [tag, int(per_tag[tag])])
	print("-- pieces per tag: " + ", ".join(tag_counts))
	if scenery.has_method(&"road_report"):
		print("-- TrackScenery road guard: " + String(scenery.call(&"road_report")))
	print("-- ON ROAD at kart height (y %.1f..%.1f m): %d" % [KART_BAND.x, KART_BAND.y, on_road.size()])
	for line in on_road:
		print("   " + line)
	print("-- FLAT surface detail over the road (top <= %.2f m, drive-over): %d" % [FLAT_TOP, flat.size()])
	for line in flat:
		print("   " + line)
	print("-- OVERHEAD over the road (bottom >= %.1f m), per tag: count, lowest bottom" % KART_BAND.y)
	for tag in overhead.keys():
		print("   %s: %d, lowest %.2f m" % [tag, int(overhead[tag][0]), float(overhead[tag][1])])
	scenery.free()
	return on_road.size()


func _check(id: String, tag: String, kind: String, index: int, xf: Transform3D, faces: PackedVector3Array,
		on_road: Array[String], flat: Array[String], overhead: Dictionary) -> void:
	if faces.is_empty():
		return
	var y_lo: float = INF
	var y_hi: float = -INF
	var all_pts := PackedVector2Array()
	var band_pts := PackedVector2Array()
	var world := PackedVector3Array()
	world.resize(faces.size())
	for k in faces.size():
		world[k] = xf * faces[k]
		y_lo = minf(y_lo, world[k].y)
		y_hi = maxf(y_hi, world[k].y)
		all_pts.append(Vector2(world[k].x, world[k].z))
	# The mesh cut to the kart band: every triangle edge clipped to KART_BAND (convex mesh, so the
	# hull of the clipped points is the footprint of the part at kart height).
	for k in range(0, world.size() - 2, 3):
		for e in 3:
			_clip(world[k + e], world[k + (e + 1) % 3], band_pts)
	if band_pts.is_empty():
		if y_lo >= KART_BAND.y and _overlap(all_pts).x < 0.0:
			var o: Array = overhead.get(tag, [0, INF])
			overhead[tag] = [int(o[0]) + 1, minf(float(o[1]), y_lo)]
		return
	var hit: Vector3 = _overlap(band_pts)
	if tag == _show_tag:
		print("   [tag] %s %s#%d pos=(%.1f, %.1f) y=%.2f..%.2f min_excess=%.2f" % [tag, kind, index, hit.y, hit.z, y_lo, y_hi, hit.x])
	if hit.x >= 0.0:
		return
	var c: Vector2 = Vector2(hit.y, hit.z)
	var q: TrackModel.Query = _track.query(c, -1)
	var road: String = "main" if q.path == TrackModel.MAIN_PATH else String(_track.data.branches[q.path].id)
	var size: float = 0.0
	for p in band_pts:
		size = maxf(size, c.distance_to(p) * 2.0)
	var line: String = "%s s=%.1f road=%s tag=%s kind=%s#%d pos=(%.1f, %.1f) y=%.2f..%.2f size=%.1fm into_road=%.2fm%s" % [
		id, q.s, road, tag, kind, index, c.x, c.y, maxf(y_lo, KART_BAND.x), minf(y_hi, KART_BAND.y), size, -hit.x,
		" in_hazard" if _track.in_hazard_area(c) else ""]
	if y_hi <= FLAT_TOP:
		flat.append(line)
	else:
		on_road.append(line)


# Adds the part of segment a-b inside KART_BAND (its end points) to [param out].
func _clip(a: Vector3, b: Vector3, out: PackedVector2Array) -> void:
	var t0: float = 0.0
	var t1: float = 1.0
	var dy: float = b.y - a.y
	if absf(dy) < 0.000001:
		if a.y < KART_BAND.x or a.y > KART_BAND.y:
			return
	else:
		var ta: float = (KART_BAND.x - a.y) / dy
		var tb: float = (KART_BAND.y - a.y) / dy
		t0 = maxf(t0, minf(ta, tb))
		t1 = minf(t1, maxf(ta, tb))
		if t0 > t1:
			return
	var p0: Vector3 = a.lerp(b, t0)
	var p1: Vector3 = a.lerp(b, t1)
	out.append(Vector2(p0.x, p0.z))
	out.append(Vector2(p1.x, p1.z))


# Smallest corridor excess over the footprint (convex hull of [param pts], boundary sampled every
# SAMPLE_STEP m, plus its centre): x = excess (< 0 = overlaps the drivable area), y/z = centre.
func _overlap(pts: PackedVector2Array) -> Vector3:
	var hull: PackedVector2Array = Geometry2D.convex_hull(pts)
	var c := Vector2.ZERO
	for p in hull:
		c += p
	c /= float(maxi(hull.size(), 1))
	var radius: float = 0.0
	for p in hull:
		radius = maxf(radius, c.distance_to(p))
	var worst: float = _track.excess_at(c)
	if worst > radius + FAR_SLACK:
		return Vector3(worst, c.x, c.y)
	for k in hull.size():
		var a: Vector2 = hull[k]
		var b: Vector2 = hull[(k + 1) % hull.size()]
		var n: int = maxi(1, ceili(a.distance_to(b) / SAMPLE_STEP))
		for j in n + 1:
			worst = minf(worst, _track.excess_at(a.lerp(b, float(j) / float(n))))
	return Vector3(worst, c.x, c.y)
