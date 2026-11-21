extends SceneTree
## Self-check for src/audio. Run: godot [--headless] --path . -s res://tools/audio_check.gd
## Plays every event, drives 12 fake karts, toggles mute, prints OK/ERR lines. Exit code 1 on failure.
## Uses user://audio_check.cfg so the player's real audio settings are untouched.

var _fails: int = 0


func _ok(cond: bool, label: String) -> void:
	if cond:
		print("OK  ", label)
	else:
		print("ERR ", label)
		_fails += 1


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var loaded: AudioSet = load("res://assets/data/audio/audio_set.tres") as AudioSet
	_ok(loaded != null, "audio_set.tres loads")
	var aset: AudioSet = loaded.duplicate() as AudioSet
	aset.config_path = "user://audio_check.cfg"
	var director: AudioDirector = AudioDirector.new()
	root.add_child(director)
	director.setup(aset)
	print("driver: ", AudioServer.get_driver_name())
	_ok(AudioServer.get_bus_index(aset.music_bus) != -1 and AudioServer.get_bus_index(aset.sfx_bus) != -1, "Music and Sfx buses exist")
	var missing: int = 0
	for def: AudioEventDef in aset.events:
		if def.stream == null:
			missing += 1
		director.play_event(def.event)
		director.play_event(def.event, Vector3(5, 0, 5), 3)
	_ok(missing == 0, "all %d events have streams and played (2D and 3D)" % aset.events.size())
	for i in 40:
		director.play_event(&"bump", Vector3(i, 0, 0), -1)
	director.play_event(&"no_such_event")
	director.play_countdown_beep(3)
	director.play_countdown_beep(0)
	for frame in 30:
		for kart in 12:
			director.set_engine(kart, float(frame) / 30.0, kart == 0, kart % 3 == 0, kart % 5 == 0, Vector3(kart * 6, 0, 0))
		await process_frame
	_ok(director.get_active_engine_voice_count() <= aset.engine_max_other_voices + 1, "engine voices capped (%d)" % director.get_active_engine_voice_count())
	director.start_music()
	director.start_music()
	await process_frame
	director.stop_music()
	director.start_music()
	director.set_music_volume(0.5)
	director.set_sfx_volume(0.25)
	director.set_master_volume(0.6)
	_ok(not director.is_muted(), "starts unmuted")
	_ok(director.toggle_mute() and director.is_muted(), "toggle -> muted")
	_ok(AudioServer.is_bus_mute(AudioServer.get_bus_index(aset.master_bus)), "Master bus muted")
	_ok(not director.toggle_mute() and not director.is_muted(), "toggle -> unmuted")
	director.set_muted(true)
	var reload: AudioDirector = AudioDirector.new()
	root.add_child(reload)
	reload.setup(aset)
	_ok(reload.is_muted() and is_equal_approx(reload.get_music_volume(), 0.5), "settings persisted and reloaded")
	reload.set_muted(false)
	director.set_muted(false)
	await create_timer(0.3).timeout  # engines time out
	await process_frame
	_ok(director.get_active_engine_voice_count() == 0, "stale engines released")
	director.clear_all_engines()
	print("RESULT: ", "PASS" if _fails == 0 else "FAIL (%d)" % _fails)
	quit(1 if _fails > 0 else 0)
