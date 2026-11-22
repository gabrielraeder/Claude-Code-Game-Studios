## PROTOTYPE - NOT FOR PRODUCTION. ADR-0005 NV-5/NV-6/G6: what the saved imported scenes and the
## package look like after the headless --import runs (meta persistence, stale scene after null).
## Run: godot --headless --path prototypes/collision-spike -s res://scripts/probe_adr45_load_imported.gd
extends SceneTree

var lines: PackedStringArray = []

func _p(s: String) -> void:
	lines.append(s)
	print(s)

func _initialize() -> void:
	for c: String in ["off", "on", "null"]:
		var path: String = "res://import_adr45/%s/fixture.glb" % c
		var ps: PackedScene = load(path) as PackedScene
		if ps == null:
			_p("%s: load(%s) = null" % [c, path])
			continue
		var root: Node = ps.instantiate()
		var metas: Dictionary = {}
		for k: StringName in root.get_meta_list():
			metas[k] = root.get_meta(k)
		_p("%s: loaded, root meta=%s" % [c, metas])
		var road: MeshInstance3D = root.find_child("Road", true, false) as MeshInstance3D
		if road:
			var v: PackedVector3Array = road.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			var hit: bool = false
			for p: Vector3 in v:
				if p == Vector3(1995.123457, 3.333333, -1900.5):
					hit = true
			_p("%s: saved scene Road far vertex exact float32 present=%s" % [c, hit])
		root.free()
	var pkg: Resource = ResourceLoader.load("res://import_adr45/off/fixture.track.res", "", ResourceLoader.CACHE_MODE_IGNORE)
	_p("package: class=%s script=%s gates=%d routes_typed=%s stats=%s" % [pkg.get_class(), pkg.get_script().resource_path, (pkg as Adr45Course).gate_xform.size(), (pkg as Adr45Course).routes.get_typed_script() == Adr45Route, (pkg as Adr45Course).stats])
	_p("package sha256 field == current glb sha256: %s" % ((pkg as Adr45Course).stats.get("sha256") == FileAccess.get_sha256("res://import_adr45/off/fixture.glb")))
	var f := FileAccess.open("res://out/probe_adr45_load_imported.txt", FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	quit(0)
