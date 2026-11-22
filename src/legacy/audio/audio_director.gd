class_name AudioDirector
extends Node
## Plays all race sound: pooled one-shots (2D or 3D), per-kart engine/drift loops,
## the music loop, buses (Master/Music/Sfx created at runtime), mute and saved volumes.
## No autoload: create one, add it to the tree, then call setup(audio_set).
## Under --headless it plays nothing (no voice is started), so automation quits cleanly.
## Implements: production/epics/dogworks-racing-kennel-kingdom/story-007-race-flow-hud-sound.md (basic sound).

## Emitted when mute changes.
signal mute_changed(muted: bool)

## Per-kart engine voice state.
class EngineVoice:
	extends RefCounted
	var kart_id: int = -1
	var engine: Node
	var drift: Node
	var pitch: float = 1.0
	var vol: float = 0.0
	var drift_vol: float = 0.0

## Latest engine request for one kart.
class EngineRequest:
	extends RefCounted
	var speed_frac: float = 0.0
	var is_local: bool = false
	var drifting: bool = false
	var boosting: bool = false
	var position: Vector3 = Vector3.INF
	var stamp_s: float = 0.0

const _SILENT_DB: float = -80.0

var _set: AudioSet
var _defs: Dictionary = {}  # StringName -> AudioEventDef
var _pool2d: Dictionary = {}  # StringName -> Array of AudioStreamPlayer
var _pool3d: Dictionary = {}  # StringName -> Array of AudioStreamPlayer3D
var _last_play_s: Dictionary = {}  # int key -> float
var _requests: Dictionary = {}  # kart_id -> EngineRequest
var _local_voice: EngineVoice
var _other_voices: Array[EngineVoice] = []
var _music: AudioStreamPlayer
var _music_wanted: bool = false
var _muted: bool = false
var _master_volume: float = 1.0
var _music_volume: float = 1.0
var _sfx_volume: float = 1.0
var _engine_stream: AudioStream
var _drift_stream: AudioStream
var _clock_s: float = 0.0
var _ready_ok: bool = false
# Headless (the automation): every voice stays stopped. Nothing can be heard there, and a voice
# still playing when the tree quits is reported as a leaked resource at exit.
var _silent: bool = false


## Builds buses, loads saved settings, prepares loops. Call once, after adding to the tree.
func setup(audio_set: AudioSet) -> void:
	if audio_set == null:
		push_error("AudioDirector.setup: audio_set is null")
		return
	_set = audio_set
	process_mode = Node.PROCESS_MODE_ALWAYS
	_silent = DisplayServer.get_name() == "headless"
	_defs.clear()
	for def: AudioEventDef in _set.events:
		if def != null and def.event != &"":
			_defs[def.event] = def
	_ensure_bus(_set.music_bus)
	_ensure_bus(_set.sfx_bus)
	_engine_stream = _make_loop(_set.engine_stream)
	_drift_stream = _make_loop(_set.drift_stream)
	_music = AudioStreamPlayer.new()
	_music.name = "Music"
	_music.stream = _make_loop(_set.music_stream)
	_music.bus = _set.music_bus
	_music.volume_db = _set.music_volume_db
	add_child(_music)
	_local_voice = _make_voice(false)
	for i in _set.engine_max_other_voices:
		_other_voices.append(_make_voice(true))
	_load_settings()
	_ready_ok = true


## Plays a one-shot event. With a position (not Vector3.INF) it is 3D, otherwise 2D.
## kart_id (>= 0) lets the per-event min interval apply per kart.
func play_event(event: StringName, position: Vector3 = Vector3.INF, kart_id: int = -1) -> void:
	if not _ready_ok:
		return
	var def: AudioEventDef = _defs.get(event) as AudioEventDef
	if def == null or def.stream == null:
		return
	var now_s: float = _clock_s
	var key: int = hash(event) * 31 + kart_id
	if def.min_interval_s > 0.0 and _last_play_s.has(key) and now_s - float(_last_play_s[key]) < def.min_interval_s:
		return
	if _count_playing_total() >= _set.max_total_oneshot_voices:
		return
	if _silent:
		_last_play_s[key] = now_s
		return
	var positional: bool = position != Vector3.INF and position.is_finite()
	var player: Node = _acquire(def, positional)
	if player == null:
		return
	_last_play_s[key] = now_s
	var pitch: float = randf_range(minf(def.pitch_min, def.pitch_max), maxf(def.pitch_min, def.pitch_max))
	if positional:
		var p3: AudioStreamPlayer3D = player as AudioStreamPlayer3D
		p3.global_position = position
		p3.pitch_scale = pitch
		p3.volume_db = def.volume_db
		p3.play()
	else:
		var p2: AudioStreamPlayer = player as AudioStreamPlayer
		p2.pitch_scale = pitch
		p2.volume_db = def.volume_db
		p2.play()


## Countdown horn: step 3, 2, 1 = low horn, step 0 (GO) = long high horn.
func play_countdown_beep(step: int) -> void:
	if _set == null:
		return
	play_event(_set.countdown_go_event if step <= 0 else _set.countdown_event)


## Per-kart per-frame engine update. speed_frac 0..1 of top speed. The local kart is 2D and
## louder; others are 3D at position (only the nearest engine_max_other_voices are audible).
func set_engine(kart_id: int, speed_frac: float, is_local: bool, drifting: bool, boosting: bool, position: Vector3 = Vector3.INF) -> void:
	var req: EngineRequest = _requests.get(kart_id) as EngineRequest
	if req == null:
		req = EngineRequest.new()
		_requests[kart_id] = req
	req.speed_frac = clampf(speed_frac, 0.0, 1.0) if is_finite(speed_frac) else 0.0
	req.is_local = is_local
	req.drifting = drifting
	req.boosting = boosting
	req.position = position
	req.stamp_s = _clock_s


## Removes a kart's engine (e.g. finished or left the race).
func clear_engine(kart_id: int) -> void:
	_requests.erase(kart_id)


## Silences every engine voice and forgets all karts (call between races).
func clear_all_engines() -> void:
	_requests.clear()


## Starts the music loop (no-op if already playing).
func start_music() -> void:
	_music_wanted = true
	if _music != null and _music.stream != null and not _music.playing and not _silent:
		_music.play()


## Stops the music.
func stop_music() -> void:
	_music_wanted = false
	if _music != null:
		_music.stop()


## Mutes or unmutes everything (Master bus) and saves.
func set_muted(muted: bool) -> void:
	if _set == null:
		return
	_muted = muted
	_apply_volumes()
	_save_settings()
	mute_changed.emit(_muted)


## True when muted.
func is_muted() -> bool:
	return _muted


## Flips mute; returns the new state. The UI binds the M key to this.
func toggle_mute() -> bool:
	set_muted(not _muted)
	return _muted


## Master volume, linear 0..1.
func set_master_volume(linear: float) -> void:
	_master_volume = clampf(linear, 0.0, 1.0)
	_apply_volumes()
	_save_settings()


## Music volume, linear 0..1.
func set_music_volume(linear: float) -> void:
	_music_volume = clampf(linear, 0.0, 1.0)
	_apply_volumes()
	_save_settings()


## Effects volume, linear 0..1.
func set_sfx_volume(linear: float) -> void:
	_sfx_volume = clampf(linear, 0.0, 1.0)
	_apply_volumes()
	_save_settings()


## Master volume, linear 0..1.
func get_master_volume() -> float:
	return _master_volume


## Music volume, linear 0..1.
func get_music_volume() -> float:
	return _music_volume


## Effects volume, linear 0..1.
func get_sfx_volume() -> float:
	return _sfx_volume


## Number of engine voices currently audible (for diagnostics).
func get_active_engine_voice_count() -> int:
	var n: int = 0
	for v: EngineVoice in _all_voices():
		if v.kart_id != -1:
			n += 1
	return n


## Stops every voice and drops the streams (also done when the director leaves the tree), so
## quitting while sounds play leaves no playback behind.
func shutdown() -> void:
	_ready_ok = false
	for c: Node in get_children():
		if c is AudioStreamPlayer:
			(c as AudioStreamPlayer).stop()
			(c as AudioStreamPlayer).stream = null
		elif c is AudioStreamPlayer3D:
			(c as AudioStreamPlayer3D).stop()
			(c as AudioStreamPlayer3D).stream = null


func _exit_tree() -> void:
	shutdown()


func _process(delta: float) -> void:
	if not _ready_ok:
		return
	_clock_s += delta
	_update_engines(delta)


# ------------------------------------------------------------------ engines
func _all_voices() -> Array[EngineVoice]:
	var all: Array[EngineVoice] = [_local_voice]
	all.append_array(_other_voices)
	return all


func _update_engines(delta: float) -> void:
	# Drop stale karts.
	var stale: Array[int] = []
	for id: int in _requests:
		var r: EngineRequest = _requests[id] as EngineRequest
		if _clock_s - r.stamp_s > _set.engine_request_timeout_s:
			stale.append(id)
	for id: int in stale:
		_requests.erase(id)
	# Choose the local kart and the nearest others.
	var local_id: int = -1
	var others: Array[int] = []
	for id: int in _requests:
		if (_requests[id] as EngineRequest).is_local and local_id == -1:
			local_id = id
		else:
			others.append(id)
	var listener: Vector3 = _listener_position(local_id)
	others.sort_custom(func(a: int, b: int) -> bool:
		return _dist_sq(a, listener) < _dist_sq(b, listener))
	var chosen: Array[int] = others.slice(0, _other_voices.size())
	# Assign voices: keep existing assignments, give free voices to new karts.
	for v: EngineVoice in _other_voices:
		if v.kart_id != -1 and not chosen.has(v.kart_id):
			v.kart_id = -1
	for id: int in chosen:
		var has_voice: bool = false
		for v: EngineVoice in _other_voices:
			if v.kart_id == id:
				has_voice = true
		if not has_voice:
			for v: EngineVoice in _other_voices:
				if v.kart_id == -1:
					v.kart_id = id
					v.vol = 0.0
					break
	_local_voice.kart_id = local_id
	var k: float = clampf(_set.engine_smooth_rate * delta, 0.0, 1.0)
	for v: EngineVoice in _all_voices():
		var is_local: bool = v == _local_voice
		var req: EngineRequest = _requests.get(v.kart_id) as EngineRequest
		_drive_voice(v, req, is_local, k)


func _drive_voice(v: EngineVoice, req: EngineRequest, is_local: bool, k: float) -> void:
	var target_pitch: float = v.pitch
	var target_db: float = _SILENT_DB
	var target_drift_db: float = _SILENT_DB
	if req != null:
		target_pitch = lerpf(_set.engine_pitch_idle, _set.engine_pitch_full, req.speed_frac)
		var base_db: float = _set.engine_local_volume_db if is_local else _set.engine_other_volume_db
		var idle_mul: float = lerpf(_set.engine_idle_volume_frac, 1.0, req.speed_frac)
		target_db = base_db + linear_to_db(maxf(idle_mul, 0.001))
		if req.boosting:
			target_pitch *= _set.engine_boost_pitch_mult
			target_db += _set.engine_boost_volume_db
		if req.drifting:
			target_drift_db = _set.drift_local_volume_db if is_local else _set.drift_other_volume_db
		if not is_local and req.position != Vector3.INF:
			(v.engine as AudioStreamPlayer3D).global_position = req.position
			(v.drift as AudioStreamPlayer3D).global_position = req.position
	v.pitch = lerpf(v.pitch, target_pitch, k)
	v.vol = lerpf(maxf(v.vol, _SILENT_DB), target_db, k)
	v.drift_vol = lerpf(maxf(v.drift_vol, _SILENT_DB), target_drift_db, k)
	_set_loop_player(v.engine, v.vol, v.pitch)
	_set_loop_player(v.drift, v.drift_vol, _set.drift_pitch)


func _set_loop_player(p: Node, db: float, pitch: float) -> void:
	var audible: bool = db > _SILENT_DB + 4.0 and not _silent
	if p is AudioStreamPlayer:
		var p2: AudioStreamPlayer = p as AudioStreamPlayer
		p2.volume_db = db
		p2.pitch_scale = maxf(pitch, 0.05)
		if audible and not p2.playing:
			p2.play()
		elif not audible and p2.playing:
			p2.stop()
	else:
		var p3: AudioStreamPlayer3D = p as AudioStreamPlayer3D
		p3.volume_db = db
		p3.pitch_scale = maxf(pitch, 0.05)
		if audible and not p3.playing:
			p3.play()
		elif not audible and p3.playing:
			p3.stop()


func _dist_sq(id: int, listener: Vector3) -> float:
	var r: EngineRequest = _requests[id] as EngineRequest
	if r.position == Vector3.INF:
		return INF
	return r.position.distance_squared_to(listener)


func _listener_position(local_id: int) -> Vector3:
	var cam: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() and get_viewport() != null else null
	if cam != null:
		return cam.global_position
	if local_id != -1:
		var r: EngineRequest = _requests[local_id] as EngineRequest
		if r.position != Vector3.INF:
			return r.position
	return Vector3.ZERO


func _make_voice(positional: bool) -> EngineVoice:
	var v: EngineVoice = EngineVoice.new()
	if positional:
		v.engine = _new_loop_3d(_engine_stream, _set.sfx_bus)
		v.drift = _new_loop_3d(_drift_stream, _set.sfx_bus)
	else:
		v.engine = _new_loop_2d(_engine_stream, _set.sfx_bus)
		v.drift = _new_loop_2d(_drift_stream, _set.sfx_bus)
	v.vol = _SILENT_DB
	v.drift_vol = _SILENT_DB
	return v


func _new_loop_2d(stream: AudioStream, bus: StringName) -> AudioStreamPlayer:
	var p: AudioStreamPlayer = AudioStreamPlayer.new()
	p.stream = stream
	p.bus = bus
	p.volume_db = _SILENT_DB
	add_child(p)
	return p


func _new_loop_3d(stream: AudioStream, bus: StringName) -> AudioStreamPlayer3D:
	var p: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
	p.stream = stream
	p.bus = bus
	p.volume_db = _SILENT_DB
	p.unit_size = _set.positional_unit_size
	p.max_distance = _set.positional_max_distance
	add_child(p)
	return p


# ------------------------------------------------------------------ one-shot pool
func _acquire(def: AudioEventDef, positional: bool) -> Node:
	var pools: Dictionary = _pool3d if positional else _pool2d
	var list: Array = pools.get(def.event, []) as Array
	pools[def.event] = list
	var busy: int = 0
	for p: Node in list:
		if not _is_playing(p):
			p.set("stream", def.stream)
			return p
		busy += 1
	# Cap counts both 2D and 3D voices of this event.
	if _count_playing_event(def.event) >= def.max_voices:
		return null
	var bus: StringName = def.bus if def.bus != &"" else _set.sfx_bus
	var fresh: Node
	if positional:
		fresh = _new_loop_3d(def.stream, bus)
	else:
		fresh = _new_loop_2d(def.stream, bus)
	list.append(fresh)
	return fresh


func _is_playing(p: Node) -> bool:
	return bool(p.get("playing"))


func _count_playing_event(event: StringName) -> int:
	var n: int = 0
	for pools: Dictionary in [_pool2d, _pool3d]:
		for p: Node in pools.get(event, []) as Array:
			if _is_playing(p):
				n += 1
	return n


func _count_playing_total() -> int:
	var n: int = 0
	for pools: Dictionary in [_pool2d, _pool3d]:
		for ev: StringName in pools:
			for p: Node in pools[ev] as Array:
				if _is_playing(p):
					n += 1
	return n


# ------------------------------------------------------------------ buses / settings
func _ensure_bus(bus_name: StringName) -> void:
	if AudioServer.get_bus_index(bus_name) != -1:
		return
	AudioServer.add_bus()
	var idx: int = AudioServer.bus_count - 1
	AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(idx, _set.master_bus)


func _make_loop(stream: AudioStream) -> AudioStream:
	var wav: AudioStreamWAV = stream as AudioStreamWAV
	if wav == null:
		return stream
	if wav.loop_mode != AudioStreamWAV.LOOP_DISABLED:
		return wav
	# Loop end in sample frames, from the length in seconds: valid for every import format
	# (the default QOA compression makes the byte count unrelated to the frame count).
	var copy: AudioStreamWAV = wav.duplicate() as AudioStreamWAV
	copy.loop_mode = AudioStreamWAV.LOOP_FORWARD
	copy.loop_begin = 0
	copy.loop_end = int(round(copy.get_length() * float(copy.mix_rate)))
	return copy


func _apply_volumes() -> void:
	_set_bus_db(_set.master_bus, _master_volume)
	_set_bus_db(_set.music_bus, _music_volume)
	_set_bus_db(_set.sfx_bus, _sfx_volume)
	var idx: int = AudioServer.get_bus_index(_set.master_bus)
	if idx != -1:
		AudioServer.set_bus_mute(idx, _muted)


func _set_bus_db(bus_name: StringName, linear: float) -> void:
	var idx: int = AudioServer.get_bus_index(bus_name)
	if idx != -1:
		AudioServer.set_bus_volume_db(idx, linear_to_db(linear) if linear > 0.0 else _SILENT_DB)


func _load_settings() -> void:
	_master_volume = _set.default_master_volume
	_music_volume = _set.default_music_volume
	_sfx_volume = _set.default_sfx_volume
	_muted = false
	var cfg: ConfigFile = ConfigFile.new()
	if cfg.load(_set.config_path) == OK:
		_muted = bool(cfg.get_value("audio", "muted", false))
		_master_volume = clampf(float(cfg.get_value("audio", "master", _master_volume)), 0.0, 1.0)
		_music_volume = clampf(float(cfg.get_value("audio", "music", _music_volume)), 0.0, 1.0)
		_sfx_volume = clampf(float(cfg.get_value("audio", "sfx", _sfx_volume)), 0.0, 1.0)
	_apply_volumes()


func _save_settings() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	cfg.set_value("audio", "muted", _muted)
	cfg.set_value("audio", "master", _master_volume)
	cfg.set_value("audio", "music", _music_volume)
	cfg.set_value("audio", "sfx", _sfx_volume)
	var err: Error = cfg.save(_set.config_path)
	if err != OK:
		push_warning("AudioDirector: could not save %s (error %d)" % [_set.config_path, err])
