## Scratch probe for ADR-0003 review (godot-specialist). PROTOTYPE - NOT FOR PRODUCTION.
## ClassDB facts the ADR relies on: is there a per-space manual step on PhysicsServer3D,
## what the rest-info result carries, which *_into query methods exist on 4.8-beta3.
## Run: godot --headless --path prototypes/collision-spike -s res://scripts/probe_adr3_api.gd
extends SceneTree


func _names(cls: String, filt: String) -> PackedStringArray:
	var out := PackedStringArray()
	for m: Dictionary in ClassDB.class_get_method_list(cls, true):
		var n: String = m["name"]
		if filt == "" or n.contains(filt):
			out.append(n)
	out.sort()
	return out


func _initialize() -> void:
	print("engine=", Engine.get_version_info().string)
	print("PhysicsServer3D methods containing 'step': ", _names("PhysicsServer3D", "step"))
	print("PhysicsServer3D methods containing 'space_': ", _names("PhysicsServer3D", "space_"))
	print("PhysicsServer3D methods containing 'active': ", _names("PhysicsServer3D", "active"))
	print("PhysicsDirectSpaceState3D methods: ", _names("PhysicsDirectSpaceState3D", ""))
	for cls: String in ["PhysicsGetRestInfoResult3D", "PhysicsCastMotionResult3D", "PhysicsIntersectRayResult3D"]:
		var props := PackedStringArray()
		for p: Dictionary in ClassDB.class_get_property_list(cls, true):
			props.append("%s:%s" % [p["name"], type_string(p["type"])])
		print(cls, " props: ", props)
	print("Geometry3D segment methods: ", _names("Geometry3D", "segment"))
	print("CharacterBody3D 'floor'/'safe_margin' props present: ", ClassDB.class_has_method("CharacterBody3D", "set_safe_margin"), " ", ClassDB.class_has_method("CharacterBody3D", "apply_floor_snap"))
	quit()
