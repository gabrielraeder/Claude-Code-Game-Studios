class_name TrackLibrary
extends RefCounted
## Lists the tracks by id and loads their TrackData. The host picks an id (--track= for now,
## the lobby later in story 007) and every PC loads the same one.

## Track used when nothing is chosen.
const DEFAULT_ID: String = "castle_circuit"
## Track id -> TrackData resource path.
const TRACKS: Dictionary = {
	"castle_circuit": "res://assets/tracks/castle_circuit/castle_circuit.tres",
	"dungeon_depths": "res://assets/tracks/dungeon_depths/dungeon_depths.tres",
	"test_loop": "res://src/test_track/test_loop.tres",
}


## All known track ids.
static func ids() -> Array:
	return TRACKS.keys()


## True when [param id] names a known track.
static func has_track(id: String) -> bool:
	return TRACKS.has(id)


## Loads the TrackData for [param id], or null when the id is unknown or fails to load.
static func load_track(id: String) -> TrackData:
	if not TRACKS.has(id):
		return null
	return load(String(TRACKS[id])) as TrackData
