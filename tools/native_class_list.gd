extends SceneTree
## Prints one "NATIVE_CLASS <name>" line for every class the extensions register in ClassDB (core-rebuild
## story 067). tools/core_greps.sh reads the output (NATIVE_CLASSES_FILE) to check that no GDScript
## class_name matches a native class name. Run headless:
##   godot --headless --path . -s res://tools/native_class_list.gd > classes.txt


func _init() -> void:
	var names: PackedStringArray = ClassDB.get_class_list()
	names.sort()
	for n in names:
		if ClassDB.class_get_api_type(n) == ClassDB.API_EXTENSION:
			print("NATIVE_CLASS %s" % n)
	quit(0)
