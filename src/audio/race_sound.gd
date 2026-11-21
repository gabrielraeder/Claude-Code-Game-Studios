class_name RaceSound
extends RefCounted
## Wires race moments to the AudioDirector (story 007 part 2): per-frame engine and drift loops
## for every racer (the local kart 2D, the others 3D), one-shots found by watching each racer's
## state change (boost, spin-out, sinking: works for remote karts too), signal-driven one-shots
## of owned karts (hard wall hits, bumps), item cues, lap and finish, and the countdown horn.
## Which moment plays which event is data (AudioSet group "Race events"). Plays sound only;
## changes no game state.

## Last seen state of one kart, for edge detection.
class KartMemo:
	extends RefCounted
	var spinning: bool = false
	var sinking: bool = false
	var boost_time: float = 0.0

var _director: AudioDirector
var _set: AudioSet
var _memo: Dictionary = {}  # kart_id -> KartMemo
var _beep_last: int = -1
var _was_counting: bool = false


## [param director] must already be set up with [param audio_set].
func _init(director: AudioDirector, audio_set: AudioSet) -> void:
	_director = director
	_set = audio_set


## Forgets every kart's remembered state (call when a race is built or reset).
func reset() -> void:
	_memo.clear()
	_beep_last = -1
	_was_counting = false
	_director.clear_all_engines()


## Listens to an owned kart's wall and bump signals. [param local] plays them 2D; otherwise at
## the kart's position at the time. Call once per KartSim object. The kart is bound through a
## WeakRef so the connection never keeps the kart alive (no reference cycle).
func watch_owned(racer: Racer, local: bool) -> void:
	var sim: KartSim = racer.sim
	sim.wall_bumped.connect(_on_wall.bind(weakref(sim), racer.kart_id, local))
	sim.kart_bumped.connect(_on_bump.bind(weakref(sim), racer.kart_id, local))


## Lap and finish fanfares of the local kart's lap counter. Call once per LapCounter object.
func watch_laps(laps: LapCounter) -> void:
	laps.lap_started.connect(_on_lap_started)
	laps.finished.connect(_on_finished)


## An ItemManager.sound_cue: plays the matching event at [param racer] (null = 2D).
func item_cue(kind: StringName, racer: Racer, local: bool) -> void:
	var ev: StringName = &""
	match kind:
		&"box":
			ev = _set.box_event
		&"roulette_land":
			ev = _set.roulette_land_event
		&"hit":
			ev = _set.item_hit_event
		&"shield_break":
			ev = _set.shield_break_event
		_:
			ev = StringName(str(_set.item_use_events.get(kind, &"")))
	if ev == &"":
		return
	if racer == null:
		_director.play_event(ev)
	else:
		_play_at(ev, racer, local)


## Per frame. [param active] false (menu, lobby, results, paused) lets every engine fall
## silent and resets the countdown tracking.
func update(racers: Array[Racer], local: Racer, start: StartSequence, track: TrackModel, active: bool) -> void:
	_countdown(start, active)
	if not active:
		return
	for r: Racer in racers:
		if r.dropped or r.sim == null:
			continue
		var sim: KartSim = r.sim
		var is_local: bool = r == local
		var top: float = maxf(sim.stats.max_speed, 0.1)
		var pos: Vector3 = Vector3.INF if is_local else _pos3(sim)
		_director.set_engine(r.kart_id, absf(sim.speed) / top, is_local, sim.drifting, sim.boost_time > 0.0, pos)
		var m: KartMemo = _memo.get(r.kart_id) as KartMemo
		var spinning: bool = sim.spin_time > 0.0
		var sinking: bool = sim.is_sinking()
		if m == null:
			m = KartMemo.new()
			m.spinning = spinning
			m.sinking = sinking
			m.boost_time = sim.boost_time
			_memo[r.kart_id] = m
			continue
		if spinning and not m.spinning:
			_play_at(_set.spin_event, r, is_local)
		if sinking and not m.sinking:
			var ev: StringName = StringName(str(_set.hazard_events.get(_hazard_kind(r, track), &"")))
			if ev != &"":
				_play_at(ev, r, is_local)
		if sim.boost_time > m.boost_time + _set.boost_rise_min_s:
			_play_at(_set.boost_event, r, is_local)
		m.spinning = spinning
		m.sinking = sinking
		m.boost_time = sim.boost_time


# Horn on each new countdown number (3, 2, 1) and the long horn at GO.
func _countdown(start: StartSequence, active: bool) -> void:
	if not active:
		_beep_last = -1
		_was_counting = false
		return
	if start.is_counting():
		var n: int = start.display_number()
		if n != _beep_last and n > 0:
			_director.play_countdown_beep(n)
		_beep_last = n
		_was_counting = true
	elif _was_counting:
		_was_counting = false
		_beep_last = -1
		_director.play_countdown_beep(0)


func _play_at(ev: StringName, racer: Racer, local: bool) -> void:
	_play_sim(ev, racer.sim, racer.kart_id, local)


func _play_sim(ev: StringName, sim: KartSim, kart_id: int, local: bool) -> void:
	if local or sim == null:
		_director.play_event(ev, Vector3.INF, kart_id)
	else:
		_director.play_event(ev, _pos3(sim), kart_id)


func _on_wall(hard: bool, sim_ref: WeakRef, kart_id: int, local: bool) -> void:
	if hard:
		_play_sim(_set.wall_event, sim_ref.get_ref() as KartSim, kart_id, local)


func _on_bump(strength: float, sim_ref: WeakRef, kart_id: int, local: bool) -> void:
	if strength >= _set.bump_min_strength:
		_play_sim(_set.bump_event, sim_ref.get_ref() as KartSim, kart_id, local)


func _on_lap_started(lap: int) -> void:
	if lap >= 2:
		_director.play_event(_set.lap_event)


func _on_finished(_total: float) -> void:
	_director.play_event(_set.finish_event)


func _pos3(sim: KartSim) -> Vector3:
	return Vector3(sim.position.x, _set.kart_sound_height, sim.position.y)


# Hazard kind under a sinking kart: owned karts know it; for a remote kart look it up.
func _hazard_kind(r: Racer, track: TrackModel) -> StringName:
	if r.owned or track == null:
		return r.sim.hazard_kind
	var i: int = track.hazard_index(r.sim.position, null, 0.0)
	return track.hazard_kinds[i] if i >= 0 else r.sim.hazard_kind
