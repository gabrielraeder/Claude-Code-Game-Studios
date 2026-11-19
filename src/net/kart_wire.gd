class_name KartWire
extends RefCounted
## Wire format of one kart state update: a PackedFloat32Array of FIELD_COUNT floats.
## Receivers accept arrays at least FIELD_COUNT long, so later versions may append fields.

## Bumped when the meaning of an existing field or of a message changes.
const VERSION: int = 1
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
const FIELD_COUNT: int = 18


## Packs the state of an owned kart. [param laps] supplies lap and finish data.
static func pack(sim: KartSim, laps: LapCounter) -> PackedFloat32Array:
	return PackedFloat32Array([sim.position.x, sim.position.y, sim.velocity.x + sim.knock.x, sim.velocity.y + sim.knock.y,
		sim.yaw, sim.speed, 1.0 if sim.drifting else 0.0, float(sim.drift_dir),
		float(sim.drift_tier), sim.boost_time, sim.spin_time, float(laps.lap), sim.track_s,
		1.0 if laps.is_finished else 0.0, laps.finish_race_time if laps.is_finished else 0.0,
		sim.last_steer, sim.accel_long, sim.accel_lat])
