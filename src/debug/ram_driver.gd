class_name RamDriver
extends KartDriver
## DEBUG AID. Drives straight at another kart to test bumping (--ram). The owner supplies
## [member target_fn], which returns the target's position (Vector2) or null when there is
## none. When the kart is stuck against its target it backs off briefly and rams again.
## Not part of the game.

## Steering gain on the heading error (rad).
const STEER_GAIN: float = 2.5
## Below this speed (m/s) and within STUCK_DISTANCE of the target, the kart counts as stuck.
const STUCK_SPEED: float = 2.0
const STUCK_DISTANCE: float = 4.0
## Seconds stuck before backing off, and seconds spent reversing.
const STUCK_TIME: float = 0.8
const REVERSE_TIME: float = 1.0

## Returns the target position (Vector2) or null.
var target_fn: Callable

var _stuck: float = 0.0
var _reverse: float = 0.0


func drive(input: KartInput, sim: KartSim, _track: TrackModel, dt: float) -> void:
	input.drift = false
	input.brake = 0.0
	if time_to_go > 0.0:
		input.throttle = 1.0 if time_to_go <= sim.stats.start_perfect_window * 0.5 else 0.0
		input.steer = 0.0
		return
	var target: Variant = target_fn.call() if target_fn.is_valid() else null
	if target == null:
		input.throttle = 0.0
		input.steer = 0.0
		return
	var to: Vector2 = (target as Vector2) - sim.position
	var diff: float = wrapf(atan2(-to.x, -to.y) - sim.yaw, -PI, PI)
	if _reverse > 0.0:
		_reverse -= dt
		input.throttle = 0.0
		input.brake = 1.0
		input.steer = -clampf(diff * STEER_GAIN, -1.0, 1.0)
		return
	if absf(sim.speed) < STUCK_SPEED and to.length() < STUCK_DISTANCE:
		_stuck += dt
		if _stuck > STUCK_TIME:
			_stuck = 0.0
			_reverse = REVERSE_TIME
	else:
		_stuck = 0.0
	input.throttle = 1.0
	input.steer = clampf(diff * STEER_GAIN, -1.0, 1.0)
