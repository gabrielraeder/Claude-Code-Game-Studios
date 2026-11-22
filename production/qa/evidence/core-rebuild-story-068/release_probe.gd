extends SceneTree
func _init() -> void:
	print("RELEASE_BUILD target=", DogworksCore.build_target(), " has_debug=", OS.has_feature("debug"))
	quit(0)
