extends SceneTree
## Legacy track extractor (core-rebuild story 008; ADR-0004 section 15; ADR-0001 section 9 as
## amended 2026-11-22). DEBUG TOOL, not game code. Retired at A3 (story 065).
##
## Runs the frozen 2.5D game's TrackModel (and its HazardManager for the movers) headless for each
## generator track and writes what that model computes as neutral JSON: the sampled centre lines
## with their per-sample heights, banks, widths and wall offsets, the ramps, pads, surface zones,
## hazards and the mover poses sampled at every sim tick. The JSON names no script, no resource
## path and no src/legacy file: its consumers (tools/legacy_test_bake.gd now; CourseAuthoring in
## story 034; tools/blender/legacy_to_blend.py in story 042) read data, not the frozen game.
## Nothing under src/ may load this tool or its output (tools/core_greps.sh).
##
## Run (from the repo root):
##   godot --headless --path . -s res://tools/legacy_track_export.gd -- [--out=DIR] [--tracks=a,b]
##   DIR defaults to res://build/legacy_tracks (gitignored, outside assets/, with a .gdignore so
##   Godot never imports it). Tracks default to castle_circuit,dungeon_depths.
## Prints one line per track and exits 0, or 1 when a track fails to load or to write.
## [codeblock]
## # Output: build/legacy_tracks/castle_circuit.json
## # { "format": "dogworks-legacy-track", "version": 1, "track_id": "castle_circuit",
## #   "paths": [...], "ramps": [...], "pads": [...], "zones": [...], "hazards": [...], "movers": [...] }
## [/codeblock]

## JSON format name and version; bumped on any schema change. A format number, not tuning.
const FORMAT_NAME: String = "dogworks-legacy-track"
const FORMAT_VERSION: int = 1
## Default output folder and tracks.
const DEFAULT_OUT: String = "res://build/legacy_tracks"
const DEFAULT_TRACKS: PackedStringArray = ["castle_circuit", "dungeon_depths"]
## Mover poses are sampled at every sim tick (ADR-0001 section 5: 60 Hz), so a piecewise-linear
## MoverDef built from them equals the frozen pose at every tick time n x SIM_DT.
const KEY_DT: float = 1.0 / 60.0
## Period (s) given to a mover with no schedule and no travel (always active, standing still):
## two equal keys. Any positive value gives the same constant pose.
const STATIC_PERIOD: float = 1.0
## Smallest period or span treated as non-zero (matches HazardManager.EPSILON); not tuning.
const EPSILON: float = 0.0001
## Strings the output must not contain (ADR-0004 section 15: no src/legacy reference).
const FORBIDDEN_OUTPUT: PackedStringArray = ["src/legacy", "res://", ".gd", ".tres"]


func _initialize() -> void:
	var out_dir: String = DEFAULT_OUT
	var tracks: PackedStringArray = DEFAULT_TRACKS
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.substr(6)
		elif arg.begins_with("--tracks="):
			tracks = arg.substr(9).split(",", false)
	var abs_dir: String = ProjectSettings.globalize_path(out_dir)
	var failures: int = 0
	if DirAccess.make_dir_recursive_absolute(abs_dir) != OK:
		print("FAIL cannot create %s" % abs_dir)
		quit(1)
		return
	var ignore: FileAccess = FileAccess.open(abs_dir.path_join(".gdignore"), FileAccess.WRITE)
	if ignore == null:
		print("FAIL cannot write %s/.gdignore" % abs_dir)
		failures += 1
	else:
		ignore.close()
	for id in tracks:
		var problem: String = _export_track(id, abs_dir)
		if problem.is_empty():
			continue
		print("FAIL %s: %s" % [id, problem])
		failures += 1
	quit(0 if failures == 0 else 1)


## Exports track [param id] to [param abs_dir]/<id>.json. Returns "" or the problem.
func _export_track(id: String, abs_dir: String) -> String:
	var data: TrackData = TrackLibrary.load_track(id)
	if data == null:
		return "unknown track or load failure"
	var model: TrackModel = TrackModel.new(data)
	var hazards: HazardManager = HazardManager.new()
	hazards.setup(model)
	var doc: Dictionary = export_model(id, model, hazards)
	hazards.free()
	var text: String = JSON.stringify(doc, "", true, true)
	for bad in FORBIDDEN_OUTPUT:
		if text.contains(bad):
			return "output would contain '%s'" % bad
	var path: String = abs_dir.path_join("%s.json" % id)
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return "cannot write %s" % path
	f.store_string(text)
	f.close()
	var paths: Array = doc["paths"]
	print("EXPORTED %s -> %s (%d bytes; %d paths, main %.1f m, %d ramps, %d pads, %d zones, %d hazards, %d movers)"
			% [id, path, text.length(), paths.size(), model.length, (doc["ramps"] as Array).size(),
			(doc["pads"] as Array).size(), (doc["zones"] as Array).size(),
			(doc["hazards"] as Array).size(), (doc["movers"] as Array).size()])
	return ""


## The neutral document of [param model] (and its movers through [param hazards]): plain
## Dictionaries, Arrays, numbers, bools and strings only. Vectors are flattened ([x, z, x, z ...]
## for 2D, [x, y, z ...] for 3D).
func export_model(id: String, model: TrackModel, hazards: HazardManager) -> Dictionary:
	var data: TrackData = model.data
	var doc: Dictionary = {
		"format": FORMAT_NAME,
		"version": FORMAT_VERSION,
		"track_id": id,
		"main_length": model.length,
		"ground_y": data.ground_y,
		"level_separation": data.level_separation,
		"deck_thickness": data.deck_thickness,
		"surface_height_tolerance": data.surface_height_tolerance,
		"pad_height_tolerance": data.pad_height_tolerance,
		"road_keep_band": data.road_keep_band,
		"query_window": data.query_window,
		"branch_switch_margin": data.branch_switch_margin,
		"checkpoint_s": _floats(model.checkpoint_s),
	}
	var paths: Array = [_path_doc(model.main)]
	for b in model.branches:
		paths.append(_path_doc(b))
	doc["paths"] = paths
	var ramps: Array = []
	for i in model.ramp_paths.size():
		ramps.append({
			"path": model.ramp_paths[i], "from": model.ramp_from[i], "length": model.ramp_len[i],
			"lip": model.ramp_lip[i], "lateral": model.ramp_lat[i], "half": model.ramp_half[i],
		})
	doc["ramps"] = ramps
	var pads: Array = []
	for i in model.pad_centers.size():
		pads.append({
			"center": _v2(model.pad_centers[i]), "dir": _v2(model.pad_dirs[i]),
			"half": _v2(model.pad_halves[i]), "path": model.pad_paths[i], "height": model.pad_heights[i],
		})
	doc["pads"] = pads
	var zones: Array = []
	for i in model.zone_polygons.size():
		zones.append({
			"id": String(model.zone_ids[i]), "kind": String(model.zone_types[i].kind),
			"on_road": model.zone_types[i].on_road, "polygon": _flat2(model.zone_polygons[i]),
			"height": model.zone_heights[i], "vertex_heights": _floats(model.zone_vertex_heights[i]),
			"triangles": Array(model.zone_triangles[i]), "height_min": model.zone_height_min[i],
			"height_max": model.zone_height_max[i], "fence": model.zone_fences[i],
			"fence_edges": _flat2(model.zone_fence_edges[i]),
		})
	doc["zones"] = zones
	var hz: Array = []
	for i in model.hazard_polygons.size():
		hz.append({
			"kind": String(model.hazard_kinds[i]), "polygon": _flat2(model.hazard_polygons[i]),
			"surface_height": model.hazard_heights[i], "min_cross_speed": model.hazard_gates[i],
		})
	doc["hazards"] = hz
	var movers: Array = []
	for i in hazards.count():
		movers.append(_mover_doc(model, hazards, i))
	doc["movers"] = movers
	return doc


func _path_doc(p: TrackModel.Path) -> Dictionary:
	return {
		"index": p.index, "id": String(p.id) if p.index >= 0 else "main", "closed": p.closed,
		"curb": p.curb, "length": p.length, "s_in": p.s_in, "s_out": p.s_out,
		"wall_drag_mult": p.wall_drag_mult, "floor_drag_mult": p.floor_drag_mult,
		"points": _flat2(p.points), "y": _floats(p.y), "bank": _floats(p.bank),
		"half": _floats(p.half), "wall_pos": _floats(p.wall_pos), "wall_neg": _floats(p.wall_neg),
		"opening": Array(p.opening) if not p.opening.is_empty() else [],
		"cumulative": _floats(p.cumulative),
	}


func _mover_doc(model: TrackModel, hazards: HazardManager, i: int) -> Dictionary:
	var m: TrackMover = hazards.mover(i)
	var path_index: int = hazards.path_index(i)
	var road: TrackModel.Path = model.path_of(path_index)
	var period: float = m.period
	if period <= EPSILON:
		period = (m.path_to - m.path_from) / m.speed if m.is_traveler() and m.path_to - m.path_from > EPSILON else STATIC_PERIOD
	var line_along: float = (m.path_from + m.path_to) * 0.5
	var line_st: Vector2 = road.seg_t_at(line_along)
	var doc: Dictionary = {
		"id": String(m.id), "kind": String(m.kind), "visual": String(m.visual),
		"hit_effect": String(m.hit_effect), "solid_body": m.solid_body, "path": path_index,
		"path_from": m.path_from, "path_to": m.path_to, "lane_offset": m.lane_offset,
		"schedule_period": m.period, "period": period, "phase": m.phase,
		"traveler": m.is_traveler(), "shuttle": m.is_shuttle(),
		"raised_angle_deg": m.raised_angle_deg, "deck_half_width": m.deck_half_width,
		"lift_height": m.lift_height, "grille_height": m.grille_height,
		"body_radius": m.body_radius, "body_length": m.body_length,
		"column_radius": m.column_radius, "column_height": m.column_height,
		"vent_center": _v2(m.vent_center), "vent_height": m.vent_height,
		"cart_width": m.cart_width, "cart_height": m.cart_height, "cart_length": m.cart_length,
		"footprint": _flat2(m.footprint), "footprint_y_min": m.footprint_y_min,
		"footprint_y_max": m.footprint_y_max,
		"line_point": _v3(Vector3(road.point_at(line_along).x,
				road.surface_y(int(line_st.x), line_st.y, 0.0), road.point_at(line_along).y)),
		"line_tangent": _v2(road.tangent_at(line_along)),
		"line_wall_offset": maxf(road.wall_at(int(line_st.x), line_st.y, 1), road.wall_at(int(line_st.x), line_st.y, -1)),
		"hinge_tangent": _v2(road.tangent_at(m.path_to)),
	}
	var key_t: Array = []
	var key_pos: Array = []
	var key_progress: Array = []
	var key_tangent: Array = []
	var key_slope: Array = []
	var key_distance: Array = []
	var k: int = 0
	while float(k) * KEY_DT < period:
		var t: float = float(k) * KEY_DT
		var pos: Vector3 = hazards.pose_at(m, t)
		var d: float = hazards.distance_at(m, t) if m.is_traveler() else m.path_to
		var st: Vector2 = road.seg_t_at(d)
		key_t.append(t)
		key_pos.append_array(_v3(pos))
		key_progress.append(hazards.progress_at(m, t))
		key_tangent.append_array(_v2(road.tangent_at(d)))
		key_slope.append(road.slope_at(int(st.x), st.y))
		key_distance.append(d)
		k += 1
	if key_t.size() < 2:
		# A period shorter than two ticks: hold the first pose (MoverDef needs two keys).
		key_t.append(period * 0.5)
		key_pos.append_array(key_pos.slice(0, 3))
		key_progress.append(key_progress[0])
		key_tangent.append_array(key_tangent.slice(0, 2))
		key_slope.append(key_slope[0])
		key_distance.append(key_distance[0])
	doc["key_t"] = key_t
	doc["key_pos"] = key_pos
	doc["key_progress"] = key_progress
	doc["key_tangent"] = key_tangent
	doc["key_slope"] = key_slope
	doc["key_distance"] = key_distance
	return doc


static func _floats(a: PackedFloat32Array) -> Array:
	var out: Array = []
	out.resize(a.size())
	for i in a.size():
		out[i] = float(a[i])
	return out


static func _flat2(a: PackedVector2Array) -> Array:
	var out: Array = []
	out.resize(a.size() * 2)
	for i in a.size():
		out[i * 2] = a[i].x
		out[i * 2 + 1] = a[i].y
	return out


static func _v2(v: Vector2) -> Array:
	return [v.x, v.y]


static func _v3(v: Vector3) -> Array:
	return [v.x, v.y, v.z]
