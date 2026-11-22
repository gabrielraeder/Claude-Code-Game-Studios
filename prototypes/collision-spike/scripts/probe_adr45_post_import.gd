## PROTOTYPE - NOT FOR PRODUCTION. ADR-0005 probes NV-2/3/4/5/6/7/8/14 + per-surface materials.
## Used as import_script/path by import_adr45/<case>/fixture.glb.import. Behaviour by folder:
##   off/, on/ : dump, then (off only) save a package .res next to the glb (temp + rename), return scene
##   null/     : read res://out/probe_adr45_null_mode.txt ("good" or "null"); return scene or null
@tool
extends EditorScenePostImport

const RUNS_LOG: String = "res://out/probe_adr45_post_import_runs.txt"
const FAR_X0: float = 1995.123457
const FAR_X1: float = 1999.987654
const FAR_Y0: float = 1900.5
const FAR_Y1: float = 1910.25
const FAR_Z: float = 3.333333
const NEG_X0: float = -1999.987654
const NEG_Y0: float = -1999.75

var lines: PackedStringArray = []

func _p(s: String) -> void:
	lines.append(s)
	print("ADR45 " + s)

func _global(n: Node3D) -> Transform3D:
	var t: Transform3D = n.transform
	var p: Node = n.get_parent()
	while p != null and p is Node3D:
		t = (p as Node3D).transform * t
		p = p.get_parent()
	return t

func _walk(root: Node, n: Node, counts: Dictionary) -> void:
	counts[n.get_class()] = int(counts.get(n.get_class(), 0)) + 1
	var meta: Dictionary = {}
	for k: StringName in n.get_meta_list():
		var v: Variant = n.get_meta(k)
		if v is Dictionary:
			var d: Dictionary = {}
			for kk: Variant in (v as Dictionary):
				var vv: Variant = (v as Dictionary)[kk]
				d[kk] = ("<String len=%d>" % (vv as String).length()) if vv is String and (vv as String).length() > 64 else vv
			meta[k] = d
		else:
			meta[k] = v
	var line: String = "NODE %s (%s) meta=%s" % [root.get_path_to(n), n.get_class(), meta]
	if n is Node3D:
		var g: Transform3D = _global(n as Node3D)
		line += " origin=%s det=%.3f" % [g.origin, g.basis.determinant()]
	_p(line)
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		var mesh: Mesh = mi.mesh
		var g: Transform3D = _global(mi)
		_p("  mesh %s class=%s surfaces=%d" % [mesh.resource_name, mesh.get_class(), mesh.get_surface_count()])
		for si: int in mesh.get_surface_count():
			var mat: Material = mesh.surface_get_material(si)
			var arr: Array = mesh.surface_get_arrays(si)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var fmt: int = (mesh as ArrayMesh).surface_get_format(si) if mesh is ArrayMesh else -1
			var compressed: bool = fmt >= 0 and (fmt & Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES) != 0
			var lods: int = 0
			var normals: PackedStringArray = []
			for t: int in idx.size() / 3:
				var a: Vector3 = g * verts[idx[3 * t]]
				var b: Vector3 = g * verts[idx[3 * t + 1]]
				var c: Vector3 = g * verts[idx[3 * t + 2]]
				normals.append(str((c - a).cross(b - a).normalized().snappedf(0.001)))
			_p("  surface %d material=%s compressed_flag=%s format=0x%x verts=%d tris=%d godot_front_normals=%s" % [si, mat.resource_name if mat else "<none>", compressed, fmt, verts.size(), idx.size() / 3, normals])
			if mi.name == "Road":
				_precision(verts, g)
	for ch: Node in n.get_children():
		_walk(root, ch, counts)

func _precision(verts: PackedVector3Array, g: Transform3D) -> void:
	# expected Godot coordinates of the far quads: Blender (x, y, z) -> (x, z, -y)
	var expect: Array[Vector3] = [Vector3(FAR_X0, FAR_Z, -FAR_Y0), Vector3(FAR_X1, FAR_Z, -FAR_Y0), Vector3(FAR_X1, FAR_Z, -FAR_Y1), Vector3(FAR_X0, FAR_Z, -FAR_Y1), Vector3(NEG_X0, 0.0, -NEG_Y0)]
	for e: Vector3 in expect:
		var best: Vector3 = Vector3.INF
		var bd: float = INF
		for v: Vector3 in verts:
			var w: Vector3 = g * v
			if w.distance_to(e) < bd:
				bd = w.distance_to(e)
				best = w
		_p("  PRECISION expected=(%.6f, %.6f, %.6f) got=(%.6f, %.6f, %.6f) exact=%s err_m=%.6f" % [e.x, e.y, e.z, best.x, best.y, best.z, best == e, bd])

func _post_import(scene: Node) -> Object:
	var src: String = get_source_file()
	var case_name: String = src.get_base_dir().get_file()
	var log_f := FileAccess.open(RUNS_LOG, FileAccess.READ_WRITE) if FileAccess.file_exists(RUNS_LOG) else FileAccess.open(RUNS_LOG, FileAccess.WRITE)
	log_f.seek_end()
	log_f.store_line("%s post_import ran source=%s case=%s" % [Time.get_datetime_string_from_system(), src, case_name])
	log_f.close()
	_p("source=%s case=%s engine=%s editor_hint=%s" % [src, case_name, Engine.get_version_info().string, Engine.is_editor_hint()])
	var counts: Dictionary = {}
	_walk(scene, scene, counts)
	_p("CLASS_COUNTS %s" % counts)
	var collision_like: int = 0
	for k: String in counts:
		if ClassDB.is_parent_class(k, "CollisionObject3D") or ClassDB.is_parent_class(k, "CollisionShape3D") or ClassDB.is_parent_class(k, "NavigationRegion3D"):
			collision_like += int(counts[k])
	_p("COLLISION_NODES %d" % collision_like)
	# NV-8: long string extra
	var track: Node = scene.find_child("Track", true, false)
	if track and track.has_meta("extras"):
		var ex: Dictionary = track.get_meta("extras")
		var keys: String = ex.get("kk_keys", "")
		_p("NV8 kk_keys type=%s len=%d head=%s tail=%s kk_schema=%s(%s) kk_float=%s kk_bool=%s(%s)" % [type_string(typeof(ex.get("kk_keys"))), keys.length(), keys.substr(0, 24), keys.substr(keys.length() - 24), ex.get("kk_schema"), type_string(typeof(ex.get("kk_schema"))), ex.get("kk_float"), ex.get("kk_bool"), type_string(typeof(ex.get("kk_bool")))])
	# NV-7: non-@tool script classes used from this @tool script
	var nv7: PackedStringArray = []
	var c: Adr45Course = Adr45Course.make_fixture()
	nv7.append("static make_fixture ok gates=%d" % c.gate_xform.size())
	nv7.append("instance gate_count()=%s" % str(c.gate_count()))
	nv7.append("instance route_half_sum()=%s" % str(c.route_half_sum()))
	var r := Adr45Route.new()
	r.half_left = PackedFloat32Array([1.0, 2.0])
	nv7.append("Adr45Route.new().total_half()=%s script=%s" % [str(r.total_half()), r.get_script()])
	_p("NV7 " + "; ".join(nv7))
	if case_name == "null":
		var mode: String = FileAccess.get_file_as_string("res://out/probe_adr45_null_mode.txt").strip_edges()
		_p("NV5 null case mode=%s" % mode)
		_flush(case_name)
		if mode == "null":
			return null
		scene.set_meta("adr45_null_case_good", true)
		return scene
	if case_name == "off":
		# NV-6: save a package into res:// during the headless import (temp then rename)
		var pkg: Adr45Course = c
		pkg.stats = {"source": src, "sha256": FileAccess.get_sha256(src), "stamp": Time.get_datetime_string_from_system()}
		var final_path: String = src.get_base_dir().path_join("fixture.track.res")
		var tmp_path: String = src.get_base_dir().path_join("fixture.track.tmp.res")
		var existed: bool = FileAccess.file_exists(final_path)
		var e_save: Error = ResourceSaver.save(pkg, tmp_path)
		var e_ren: Error = DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp_path), ProjectSettings.globalize_path(final_path))
		_p("NV6 save tmp err=%d rename err=%d (target existed before=%s) final exists=%s tmp exists=%s sha256(src)=%s" % [e_save, e_ren, existed, FileAccess.file_exists(final_path), FileAccess.file_exists(tmp_path), pkg.stats["sha256"]])
		var back: Adr45Course = ResourceLoader.load(final_path, "", ResourceLoader.CACHE_MODE_IGNORE) as Adr45Course
		_p("NV6 reload in post_import: %s gates=%d stamp=%s" % [back != null, back.gate_xform.size() if back else -1, back.stats.get("stamp") if back else "-"])
	# meta persistence: scalar vs Resource-valued meta
	scene.set_meta("adr45_scalar_meta", 7)
	scene.set_meta("adr45_resource_meta", Adr45Route.new())
	_flush(case_name)
	return scene

func _flush(case_name: String) -> void:
	var f := FileAccess.open("res://out/probe_adr45_post_import_%s.txt" % case_name, FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
