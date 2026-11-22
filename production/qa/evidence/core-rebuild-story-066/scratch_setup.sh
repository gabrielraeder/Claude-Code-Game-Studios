#!/usr/bin/env bash
# Builds two throw-away Godot projects for story 066 under a scratch root (argument 1):
#   fresh/   a project with NO .godot/, the built DLLs, and an import-time EditorImportPlugin that calls the
#            native ToolchainProbe while its sample file is imported (Verification Required 6).
#   absent/  a project with the boot check and the shared hash script but NO extension (boot negative run).
# Copies files by name only; never deletes anything.
set -eu
SCRATCH="$1"
REPO="$(cd "$(dirname "$0")/../../../.." && pwd)"
mkdir -p "$SCRATCH/fresh/addons/dogworks_core/bin" "$SCRATCH/fresh/addons/importprobe" \
	"$SCRATCH/absent/addons/dogworks_core" "$SCRATCH/absent/src/core"

cat > "$SCRATCH/fresh/project.godot" <<'EOF'
config_version=5

[application]
config/name="fresh-clone-probe"

[editor_plugins]
enabled=PackedStringArray("res://addons/importprobe/plugin.cfg")

[physics]
common/physics_ticks_per_second=60
EOF
cat > "$SCRATCH/fresh/addons/importprobe/plugin.cfg" <<'EOF'
[plugin]
name="importprobe"
description="Throw-away import-time probe"
author="story 066"
version="1"
script="plugin.gd"
EOF
cat > "$SCRATCH/fresh/addons/importprobe/plugin.gd" <<'EOF'
@tool
extends EditorPlugin

var _importer: EditorImportPlugin = null


func _enter_tree() -> void:
	print("IMPORT_HOOK plugin entered, native class exists=", ClassDB.class_exists("ToolchainProbe"))
	_importer = preload("res://addons/importprobe/importer.gd").new()
	add_import_plugin(_importer)


func _exit_tree() -> void:
	remove_import_plugin(_importer)
	_importer = null
EOF
cat > "$SCRATCH/fresh/addons/importprobe/importer.gd" <<'EOF'
@tool
extends EditorImportPlugin


func _get_importer_name() -> String:
	return "probe.native"


func _get_visible_name() -> String:
	return "Native probe"


func _get_recognized_extensions() -> PackedStringArray:
	return PackedStringArray(["nprobe"])


func _get_save_extension() -> String:
	return "res"


func _get_resource_type() -> String:
	return "Resource"


func _get_priority() -> float:
	return 1.0


func _get_import_order() -> int:
	return 0


func _get_preset_count() -> int:
	return 1


func _get_preset_name(_preset_index: int) -> String:
	return "Default"


func _get_import_options(_path: String, _preset_index: int) -> Array[Dictionary]:
	return []


func _import(_source_file: String, save_path: String, _options: Dictionary, _platform_variants: Array[String], _gen_files: Array[String]) -> Error:
	var exists: bool = ClassDB.class_exists("ToolchainProbe")
	var line: String = "IMPORT_HOOK _import ran, ToolchainProbe exists=%s" % exists
	if exists:
		var probe: Object = ClassDB.class_call_static("ToolchainProbe", "create", PackedFloat64Array([4.0, 0.0]))
		line += ", create returned %s, build_hash=%s" % [probe != null, ClassDB.class_call_static("DogworksCore", "build_hash")]
	print(line)
	return ResourceSaver.save(Resource.new(), save_path + ".res")
EOF
echo "sample" > "$SCRATCH/fresh/sample.nprobe"
cp "$REPO/addons/dogworks_core/dogworks_core.gdextension" "$SCRATCH/fresh/addons/dogworks_core/"
cp "$REPO/addons/dogworks_core/bin/"*.dll "$SCRATCH/fresh/addons/dogworks_core/bin/"

cat > "$SCRATCH/absent/project.godot" <<'EOF'
config_version=5

[application]
config/name="boot-absent-probe"

[physics]
common/physics_ticks_per_second=60
EOF
cp "$REPO/addons/dogworks_core/source_hash.gd" "$SCRATCH/absent/addons/dogworks_core/"
cp "$REPO/src/core/native_boot_check.gd" "$SCRATCH/absent/src/core/"
cat > "$SCRATCH/absent/run_boot.gd" <<'EOF'
extends SceneTree


func _initialize() -> void:
	var boot: GDScript = load("res://src/core/native_boot_check.gd")
	var problem: String = boot.check()
	print("BOOT_CHECK problem='", problem, "'")
	quit(0 if problem.is_empty() else 3)
EOF
echo "scratch projects ready under $SCRATCH"
