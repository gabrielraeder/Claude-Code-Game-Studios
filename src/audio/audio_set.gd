class_name AudioSet
extends Resource
## All audio tuning in one data resource: event list, engine/drift/music streams,
## volumes, pitch ranges, voice limits, bus names and the settings file path.
## Instance: res://assets/data/audio/audio_set.tres
## Implements: production/epics/dogworks-racing-kennel-kingdom/story-007-race-flow-hud-sound.md (basic sound).

@export_group("Events")
## One-shot events (see AudioEventDef).
@export var events: Array[AudioEventDef] = []
## Most one-shot voices playing at once across all events.
@export_range(1, 64) var max_total_oneshot_voices: int = 24
## 3D one-shots: distance at which the sound is at its set volume (metres).
@export var positional_unit_size: float = 8.0
## 3D sounds are silent beyond this distance (metres).
@export var positional_max_distance: float = 90.0

@export_group("Loops")
## Engine hum, looped and pitch-scaled by speed.
@export var engine_stream: AudioStream
## Drift scrape/sparks, looped while drifting.
@export var drift_stream: AudioStream
## Race music loop.
@export var music_stream: AudioStream

@export_group("Engine")
## Local kart engine volume (dB, 2D).
@export var engine_local_volume_db: float = -9.0
## Other karts' engine volume (dB, 3D).
@export var engine_other_volume_db: float = -17.0
## Only this many nearest other karts get an engine voice.
@export_range(0, 12) var engine_max_other_voices: int = 4
## Engine pitch scale at speed 0.
@export var engine_pitch_idle: float = 0.7
## Engine pitch scale at full speed.
@export var engine_pitch_full: float = 1.7
## Engine volume multiplier (linear) at speed 0; rises to 1.0 at full speed.
@export_range(0.0, 1.0) var engine_idle_volume_frac: float = 0.5
## Pitch multiplier while boosting.
@export var engine_boost_pitch_mult: float = 1.15
## Extra volume (dB) while boosting.
@export var engine_boost_volume_db: float = 2.0
## Drift voice volume, local kart (dB).
@export var drift_local_volume_db: float = -12.0
## Drift voice volume, other karts (dB).
@export var drift_other_volume_db: float = -20.0
## Drift voice pitch scale.
@export var drift_pitch: float = 1.0
## How fast pitch/volume follow targets (1/s). Higher = snappier.
@export var engine_smooth_rate: float = 10.0
## A kart that has not been updated for this long (s) loses its engine voice.
@export var engine_request_timeout_s: float = 0.25

@export_group("Music")
## Music player volume (dB), under the effects.
@export var music_volume_db: float = -6.0

@export_group("Buses")
## Name of the master bus (always exists).
@export var master_bus: StringName = &"Master"
## Music bus, created at runtime if missing.
@export var music_bus: StringName = &"Music"
## Effects bus, created at runtime if missing.
@export var sfx_bus: StringName = &"Sfx"

@export_group("Settings")
## Where mute and volumes are saved.
@export var config_path: String = "user://audio.cfg"
## Default master volume (linear 0..1).
@export_range(0.0, 1.0) var default_master_volume: float = 0.8
## Default music volume (linear 0..1).
@export_range(0.0, 1.0) var default_music_volume: float = 0.7
## Default effects volume (linear 0..1).
@export_range(0.0, 1.0) var default_sfx_volume: float = 1.0
## Event played for countdown steps 3, 2, 1.
@export var countdown_event: StringName = &"countdown"
## Event played for the GO step (step 0).
@export var countdown_go_event: StringName = &"countdown_go"

@export_group("Race events")
## Which event each race moment plays (story 007 part 2, wired by RaceSound).
## A new or longer boost (drift release, horn, pad, start boost).
@export var boost_event: StringName = &"boost"
## A boost counts as new when the kart's boost time rises by more than this (s).
@export var boost_rise_min_s: float = 0.05
## Kart-kart bump (owned karts) and the weakest bump (0..1) that makes a sound.
@export var bump_event: StringName = &"bump"
@export_range(0.0, 1.0) var bump_min_strength: float = 0.15
## Hard wall hit (scrapes are silent apart from the engine).
@export var wall_event: StringName = &"wall"
## A kart spins out.
@export var spin_event: StringName = &"spin"
## The local kart breaks an item box, and its roulette lands on an item.
@export var box_event: StringName = &"item_pickup"
@export var roulette_land_event: StringName = &"roulette_land"
## Item used, by item id (horn, stone, spill, falcon, shield).
@export var item_use_events: Dictionary = {&"horn": &"item_horn", &"stone": &"stone_launch",
		&"spill": &"spill_splash", &"falcon": &"falcon_screech", &"shield": &"shield_up"}
## An item hits a kart, or a shield blocks it.
@export var item_hit_event: StringName = &"item_hit"
@export var shield_break_event: StringName = &"shield_break"
## A kart starts sinking in a hazard, by hazard kind (TrackHazard.kind).
@export var hazard_events: Dictionary = {&"water": &"splash", &"lava": &"lava_sizzle"}
## The local kart starts a new lap, and finishes the race.
@export var lap_event: StringName = &"lap"
@export var finish_event: StringName = &"finish"
## Height above the road of 3D kart sounds (m).
@export var kart_sound_height: float = 0.6
