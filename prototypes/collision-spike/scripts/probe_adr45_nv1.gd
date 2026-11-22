## PROTOTYPE - NOT FOR PRODUCTION. ADR-0005 NV-1: the .blend import setting and the .blend files' import state.
## Run: godot --headless --path prototypes/collision-spike -s res://scripts/probe_adr45_nv1.gd -- <label>
extends SceneTree

func _initialize() -> void:
	var label: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "?"
	var key: String = "filesystem/import/blender/enabled"
	var s: String = "[%s] has_setting(%s)=%s value=%s default=%s | blend_plain/t.blend.import exists=%s | blend_ignored/t.blend.import exists=%s | ResourceLoader.exists(plain)=%s" % [
		label, key, ProjectSettings.has_setting(key), ProjectSettings.get_setting(key, "<none>"), ProjectSettings.property_get_revert(key),
		FileAccess.file_exists("res://import_adr45/blend_plain/t.blend.import"), FileAccess.file_exists("res://import_adr45/blend_ignored/t.blend.import"),
		ResourceLoader.exists("res://import_adr45/blend_plain/t.blend")]
	print(s)
	var f := FileAccess.open("res://out/probe_adr45_nv1.txt", FileAccess.READ_WRITE) if FileAccess.file_exists("res://out/probe_adr45_nv1.txt") else FileAccess.open("res://out/probe_adr45_nv1.txt", FileAccess.WRITE)
	f.seek_end()
	f.store_line(s)
	f.close()
	quit(0)
