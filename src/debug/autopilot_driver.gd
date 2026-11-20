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

## Branch to take (a TrackBranch id or type such as drawbridge); empty = stay on the main line.
var shortcut_id: StringName = &""

## False makes a sloppy driver: full throttle, plain steering, never drifts (track check).
var allow_drift: bool = true
## Sloppy driver: steering is held straight for this many meters of main-loop progress from
## just before the chosen branch's entrance (0 = off). Track check only.
var blind_entrance: float = 0.0

var _branch: int = -2
var _drifting_intent: bool = false
var _drift_sign: float = 0.0


func drive(input: KartInput, sim: KartSim, track: TrackModel, _dt: float) -> void:
	if _branch == -2:
		_branch = track.branch_index(shortcut_id) if shortcut_id != &"" else -1
	var look: float = LOOK_BASE + maxf(sim.speed, 0.0) * LOOK_PER_SPEED
	var target: Vector2 = _route_point(track, sim, look)
	var to: Vector2 = target - sim.position
	var want: float = atan2(-to.x, -to.y)
	var diff: float = wrapf(want - sim.yaw, -PI, PI)
	var near_t: Vector2 = _route_tangent(track, sim, CORNER_NEAR)
	var far_t: Vector2 = _route_tangent(track, sim, CORNER_FAR)
	# Positive = the track bends left ahead.
	var turn: float = -near_t.angle_to(far_t)

	# During the countdown press accelerate inside the perfect start window only.
	input.throttle = 1.0 if time_to_go <= sim.stats.start_perfect_window * 0.5 else 0.0
	input.brake = 0.0
	input.steer = clampf(diff * STEER_GAIN, -1.0, 1.0)
	if blind_entrance > 0.0 and _branch >= 0:
		var bb: TrackModel.Path = track.branches[_branch]
		if sim.track_s >= bb.s_in - 12.0 and sim.track_s <= bb.s_in + blind_entrance:
			input.steer = 0.0
	if not allow_drift:
		_drifting_intent = false
		input.drift = false
		return

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


# Point [param ahead] meters further along the intended route: the main line, or the chosen
# branch from [s_in - ahead] on, continuing on the main line after the branch ends.
func _route_point(track: TrackModel, sim: KartSim, ahead: float) -> Vector2:
	var s: float = sim.track_s
	if _branch < 0:
		return track.point_at(s + ahead)
	var b: TrackModel.Path = track.branches[_branch]
	if s < b.s_in - ahead or s > b.s_out:
		return track.point_at(s + ahead)
	var u: float = track.branch_distance_for_s(_branch, s) if s >= b.s_in else (s - b.s_in)
	var target_u: float = u + ahead
	if target_u < 0.0:
		return track.point_at(s + ahead)
	if target_u <= b.length:
		return track.branch_point_at(_branch, target_u)
	return track.point_at(b.s_out + (target_u - b.length))


func _route_tangent(track: TrackModel, sim: KartSim, ahead: float) -> Vector2:
	return (_route_point(track, sim, ahead + TrackModel.TANGENT_STEP) 			- _route_point(track, sim, ahead - TrackModel.TANGENT_STEP)).normalized()
