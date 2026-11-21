class_name KartWire
extends RefCounted
## Wire format of one kart state update: a PackedFloat32Array of FIELD_COUNT floats.
## Receivers accept arrays at least FIELD_COUNT long, so later versions may append fields.

## Bumped when the meaning of an existing field or of a message changes.
## 4 (story 006): the race start info carries each kart's loadout, and clients send theirs.
## 5 (bugfix 2026-11-20): box take carries wants_item; box taken with item -1 = broken, no item.
## 6 (story 007 part 1): lobby messages (state, pick) and the race results message.
## 7 (story 007 part 3): a race start with "spectate" true lets a late joiner watch the running
##   race; lobby entries carry "new".
## 8 (story 007 part 3): version handshake through SceneMultiplayer authentication before any
##   RPC (NetHandshake), so a build with a different RPC set is refused cleanly.
## 9 (story 008 part 1): kart state carries height and vertical velocity (HEIGHT, VY; FIELD_COUNT 21).
const VERSION: int = 9
const X: int = 0
const Z: int = 1
const VX: int = 2
const VZ: int = 3
const YAW: int = 4
const SPEED: int = 5
const DRIFTING: int = 6
const DRIFT_DIR: int = 7
const DRIFT_TIER: int = 8
const BOOST_TIME: int = 9
const SPIN_TIME: int = 10
const LAP: int = 11
const TRACK_S: int = 12
const FINISHED: int = 13
const FINISH_TIME: int = 14
const LAST_STEER: int = 15
const ACCEL_LONG: int = 16
const ACCEL_LAT: int = 17
## 0..1 while the kart sinks in a hazard (story 003), 0 otherwise. Added in VERSION 3.
const SINK: int = 18
## Kart height above the world plane in meters (story 008). Added in VERSION 9.
const HEIGHT: int = 19
## Vertical speed in m/s (story 008). Added in VERSION 9.
const VY: int = 20
const FIELD_COUNT: int = 21


## Packs the state of an owned kart. [param laps] supplies lap and finish data.
static func pack(sim: KartSim, laps: LapCounter) -> PackedFloat32Array:
	return PackedFloat32Array([sim.position.x, sim.position.y, sim.velocity.x + sim.knock.x, sim.velocity.y + sim.knock.y,
		sim.yaw, sim.speed, 1.0 if sim.drifting else 0.0, float(sim.drift_dir),
		float(sim.drift_tier), sim.boost_time, sim.spin_time, float(laps.lap), sim.track_s,
		1.0 if laps.is_finished else 0.0, laps.finish_race_time if laps.is_finished else 0.0,
		sim.last_steer, sim.accel_long, sim.accel_lat, sim.sink_progress, sim.height, sim.vertical_velocity])
