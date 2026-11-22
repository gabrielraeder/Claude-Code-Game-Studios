extends SceneTree
## Runs src/core/native_boot_check.gd once and reports the result (story 066 negative and positive runs).
##   godot --headless --path . -s res://tools/native_boot_check_run.gd
## Prints "BOOT_CHECK problem='...' hash_usec=N" and exits 0 when the check passes, 3 when it refuses.
## Loads the check with load() so this script names no native type either.


func _initialize() -> void:
	var boot: GDScript = load("res://src/core/native_boot_check.gd")
	var problem: String = boot.check()
	print("BOOT_CHECK problem='", problem, "' hash_usec=", boot.last_hash_usec)
	quit(0 if problem.is_empty() else 3)
