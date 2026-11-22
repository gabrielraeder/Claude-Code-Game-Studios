## PROTOTYPE - NOT FOR PRODUCTION. Collision spike. Q4: compare (1) the editor-imported scene
## loaded at runtime with (2) runtime GLTFDocument loading of the same .glb.
extends SceneTree

const SceneDump := preload("res://scripts/scene_dump.gd")
const GLB: String = "res://import_test/track_piece.glb"
const REPORT: String = "res://out/q4_runtime.txt"

func _initialize() -> void:
	var lines: PackedStringArray = []
	lines.append("=== (1) editor-imported scene, load(\"%s\") ===" % GLB)
	var ps: PackedScene = load(GLB)
	var inst: Node = ps.instantiate()
	lines.append("root meta: " + str(inst.get_meta_list()))
	SceneDump.dump(inst, lines)
	SceneDump.ray_test(inst, lines)
	inst.free()
	lines.append("=== (2) runtime GLTFDocument.append_from_file + generate_scene ===")
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var t0: int = Time.get_ticks_usec()
	var err: Error = doc.append_from_file(ProjectSettings.globalize_path(GLB), state)
	var root: Node = doc.generate_scene(state)
	lines.append("append_from_file err=%s, %.2f ms" % [error_string(err), (Time.get_ticks_usec() - t0) / 1000.0])
	SceneDump.dump(root, lines)
	SceneDump.ray_test(root, lines)
	lines.append("GLTFState.json node[0] extras: %s" % str((state.json["nodes"] as Array)[0].get("extras", "<none>")))
	var gn: GLTFNode = state.get_nodes()[0]
	lines.append("GLTFNode[0] %s meta=%s" % [gn.resource_name, str(gn.get_meta_list())])
	root.free()
	var f := FileAccess.open(REPORT, FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	print("\n".join(lines))
	quit()
