class_name AudioEventDef
extends Resource
## One sound-effect event: which stream, how loud, how much pitch variation and how many
## copies may play at once. Listed in AudioSet.events.
## Implements: production/epics/dogworks-racing-kennel-kingdom/story-007-race-flow-hud-sound.md (basic sound).

## Event name used by AudioDirector.play_event(), e.g. &"bump".
@export var event: StringName = &""
## The sound to play.
@export var stream: AudioStream
## Volume of this event in dB (on top of the bus volume).
@export_range(-60.0, 12.0, 0.1) var volume_db: float = 0.0
## Lowest random pitch scale per play.
@export_range(0.25, 4.0, 0.01) var pitch_min: float = 1.0
## Highest random pitch scale per play.
@export_range(0.25, 4.0, 0.01) var pitch_max: float = 1.0
## Most simultaneous voices of this event; extra triggers are dropped.
@export_range(1, 16) var max_voices: int = 4
## Minimum seconds between two plays of this event (per kart when a kart id is given). 0 = no limit.
@export_range(0.0, 5.0, 0.01) var min_interval_s: float = 0.0
## Bus to play on. Empty = the SFX bus named in AudioSet.
@export var bus: StringName = &""
