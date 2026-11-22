@tool
extends EditorPlugin
## Editor-start source-hash check for the native core (ADR-0007 section 7, "The editor-panel gap is
## closed"). When the editor opens on a stale or missing DLL it says so before any gdUnit4 panel run.
## It names no native type; the recompute is the shared addons/dogworks_core/source_hash.gd.

const _SOURCE_HASH = preload("res://addons/dogworks_core/source_hash.gd")


func _enter_tree() -> void:
	var problem: String = _problem()
	if not problem.is_empty():
		push_error("dogworks_core: " + problem)


## "" when the extension is loaded and fresh, otherwise a message that names tools/build_native.sh.
func _problem() -> String:
	if not ClassDB.class_exists(&"DogworksCore"):
		return "native extension is not loaded; run tools/build_native.sh"
	var native_hash: Variant = _SOURCE_HASH.call_static_checked(&"DogworksCore", &"source_hash", TYPE_STRING)
	if native_hash == null:
		return "native build is incompatible: %s; run tools/build_native.sh" % _SOURCE_HASH.last_error
	return _SOURCE_HASH.problem(native_hash)
