@tool
extends EditorScript
## Hot-reload observation for the native core (core-rebuild story 066, ADR-0007 Verification Required 3).
## In the GUI editor: File > Run (Ctrl+Shift+X) with this script open, before and after a rebuild.
## It prints the native text, the build target and the first 12 characters of the full hash, so a hot
## reload shows as a changed text and hash without the editor restarting.
## Instructions: production/qa/evidence/core-rebuild-story-066/hot-reload-owner-instructions.md


func _run() -> void:
	print("HOT_RELOAD_PROBE text='", DogworksCore.hot_reload_text(), "' target=", DogworksCore.build_target(), " build_hash=", DogworksCore.build_hash().substr(0, 12))
