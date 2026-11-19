class_name AutopilotDriver
extends KartDriver
## DEBUG AID. Follows the centerline with pure pursuit and drifts through corners (holding
## the drift so tiers charge, releasing at the corner exit or near a wall to collect the
## boost). Used by the --autopilot command-line switch so a run can be observed without a
## human. Not part of the game.

## Look-ahead distance = base + speed * per_speed, in meters.
const LOOK_BASE: float = 8.0
const LOOK_PER_SPEED: float = 0.6
## Steering gain on the heading error (rad) when not drifting.
const STEER_GAIN: float = 2.5
## Distances (meters ahead) between which the track's heading change is measured.
const CORNER_NEAR: float = 5.0
const CORNER_FAR: float = 45.0
## Heading change (rad) over that span that starts a drift / keeps it going.
const DRIFT_START_TURN: float = 0.5
const DRIFT_KEEP_TURN: float = 0.2
## Extra speed above drift_min_speed needed before starting a drift.
const DRIFT_SPEED_MARGIN: float = 1.0
## A drift is released when this far from the centerline (meters), to stay off the walls.
const DRIFT_ABORT_LATERAL: float = 4.5

var _drifting_intent: bool = false
var _drift_sign: float = 0.0


func drive(input: KartInput, sim: KartSim, track: TrackModel, _dt: float) -> void:
	var look: float = LOOK_BASE + maxf(sim.speed, 0.0) * LOOK_PER_SPEED
	var target: Vector2 = track.point_at(sim.track_s + look)
	var to: Vector2 = target - sim.position
	var want: float = atan2(-to.x, -to.y)
	var diff: float = wrapf(want - sim.yaw, -PI, PI)
	var near_t: Vector2 = track.tangent_at(sim.track_s + CORNER_NEAR)
	var far_t: Vector2 = track.tangent_at(sim.track_s + CORNER_FAR)
	# Positive = the track bends left ahead.
	var turn: float = -near_t.angle_to(far_t)

	# During the countdown press accelerate inside the perfect start window only.
	input.throttle = 1.0 if time_to_go <= sim.stats.start_perfect_window * 0.5 else 0.0
	input.brake = 0.0
	input.steer = clampf(diff * STEER_GAIN, -1.0, 1.0)

	if not sim.drifting:
		_drifting_intent = false
		if absf(turn) > DRIFT_START_TURN and sim.speed > sim.stats.drift_min_speed + DRIFT_SPEED_MARGIN \
				and absf(sim.lateral) < DRIFT_ABORT_LATERAL:
			_drifting_intent = true
			_drift_sign = signf(turn)
			input.steer = _drift_sign
	else:
		if absf(turn) < DRIFT_KEEP_TURN or signf(turn) != _drift_sign \
				or absf(sim.lateral) > DRIFT_ABORT_LATERAL:
			_drifting_intent = false
		# Pure pursuit: the yaw rate that reaches the look-ahead point, mapped onto the
		# drift's steerable yaw-rate range.
		var rate: float = 2.0 * sin(diff) * maxf(sim.speed, 1.0) / look
		var st: VehicleStats = sim.stats
		input.steer = clampf((rate * _drift_sign - st.drift_yaw_base) / st.drift_yaw_range, -1.0, 1.0) \
				* _drift_sign
	input.drift = _drifting_intent
