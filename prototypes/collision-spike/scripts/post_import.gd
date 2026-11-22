## PROTOTYPE - NOT FOR PRODUCTION. Collision spike. Q4: EditorScenePostImport for track_piece.glb.
## Dumps what the importer produced (before the scene is saved) to out/q4_post_import.txt
## and tags every node so we can see whether post-import metadata survives saving.
@tool
extends EditorScenePostImport

const SceneDump := preload("res://scripts/scene_dump.gd")
const REPORT: String = "res://out/q4_post_import.txt"

func _post_import(scene: Node) -> Object:
	var lines: PackedStringArray = ["source: " + get_source_file()]
	SceneDump.dump(scene, lines)
	SceneDump.ray_test(scene, lines)
	scene.set_meta("kk_post_import_ran", true)
	var f := FileAccess.open(REPORT, FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	print("\n".join(lines))
	return scene
