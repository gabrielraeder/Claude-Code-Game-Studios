## PROTOTYPE - NOT FOR PRODUCTION. Collision spike. Q1/Q2 API probe.
## Run: godot --headless --path . -s res://scripts/probe_api.gd
extends SceneTree

const SPACE_CLASS: String = "PhysicsDirectSpaceState3D"
const KEYWORDS: Array[String] = ["_into", "intersect", "cast", "collide", "rest_info"]

func _print_methods(cls: String, filter_words: Array[String]) -> void:
	for m: Dictionary in ClassDB.class_get_method_list(cls, true):
		var name: String = m["name"]
		var keep: bool = filter_words.is_empty()
		for w: String in filter_words:
			if name.contains(w):
				keep = true
		if not keep:
			continue
		var args: PackedStringArray = []
		for a: Dictionary in m["args"]:
			var t: String = type_string(a["type"])
			if a["class_name"] != "":
				t = a["class_name"]
			args.append("%s: %s" % [a["name"], t])
		var defaults: Array = m["default_args"]
		var ret: Dictionary = m["return"]
		var rt: String = type_string(ret["type"]) if ret["class_name"] == "" else ret["class_name"]
		print("  %s.%s(%s) -> %s   defaults=%s" % [cls, name, ", ".join(args), rt, str(defaults)])

func _initialize() -> void:
	print("=== ENGINE ===")
	print("version: ", Engine.get_version_info()["string"])
	print("physics/3d/physics_engine = ", ProjectSettings.get_setting("physics/3d/physics_engine"))
	print("PhysicsServer3D singleton class = ", PhysicsServer3D.get_class())
	print("=== SETTINGS matching jolt / face ===")
	for p: Dictionary in ProjectSettings.get_property_list():
		var n: String = p["name"]
		if n.begins_with("physics/jolt") or n.contains("face_index"):
			print("  ", n, " = ", ProjectSettings.get_setting(n), "  (default ", ProjectSettings.property_get_revert(n), ")")
	print("=== %s methods ===" % SPACE_CLASS)
	_print_methods(SPACE_CLASS, KEYWORDS)
	print("=== classes containing Result / Query (3D) ===")
	for c: String in ClassDB.get_class_list():
		if (c.contains("Result") or c.contains("Query")) and c.contains("3D"):
			print("  class ", c, " extends ", ClassDB.get_parent_class(c))
			for pr: Dictionary in ClassDB.class_get_property_list(c, true):
				print("     prop ", pr["name"], ": ", type_string(pr["type"]), " ", pr["class_name"])
			_print_methods(c, [])
	quit()
