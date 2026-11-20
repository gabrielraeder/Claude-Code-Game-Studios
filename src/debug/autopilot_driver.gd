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
## On roads narrower than that, a drift is released at this share of the local half width.
const DRIFT_ABORT_WIDTH_FRAC: float = 0.6

## Rail-less branches (TrackBranch.open_edge_reach > 0, the drawbridge): the careful line.
## Speed held from this far before the entrance until this far onto the branch (meters).
const OPEN_ENTRY_SPEED: float = 23.0
const OPEN_ENTRY_BEFORE: float = 15.0
const OPEN_ENTRY_AFTER: float = 22.0
## Roads narrower than this half width (passage, bridge) also use the short look-ahead.
const NARROW_HALF_WIDTH: float = 3.0
## Shorter look-ahead on such a branch so the kart follows the deck instead of cutting across.
const OPEN_LOOK_BASE: float = 4.0
const OPEN_LOOK_PER_SPEED: float = 0.3

## A branch counts as missed when the kart is on the main road this far (meters) past its
## entrance and this far outside the branch corridor.
const MISS_MARGIN: float = 4.0
## No new drift starts this many meters before a rail-less entrance on the route.
const NO_DRIFT_BEFORE_OPEN: float = 70.0

## Branch to take (a TrackBranch id or type such as drawbridge); empty = stay on the main line.
var shortcut_id: StringName = &""

## Debug (--dunk-at=S): once, on the main road from this main-loop distance, steer off the
## open edge into the hazard (for the respawn screenshot). Negative = off.
var dunk_s: float = -1.0
var _dunked: bool = false

## False makes a sloppy driver: full throttle, plain steering, never drifts (track check).
var allow_drift: bool = true
## Sloppy driver: steering is held straight for this many meters of main-loop progress from
## just before the chosen branch's entrance (0 = off). Track check only.
var blind_entrance: float = 0.0

var _branch: int = -2
# True when the chosen branch carries a speed-gated hazard (the lava gap): the autopilot then holds
# its speed (no drift) from just before the entrance until the branch ends.
var _gate_route: bool = false
# True after the chosen branch was missed this lap (see _update_missed).
var _missed: bool = false
var _drifting_intent: bool = false
var _drift_sign: float = 0.0


func drive(input: KartInput, sim: KartSim, track: TrackModel, _dt: float) -> void:
	if _branch == -2:
		_branch = track.branch_index(shortcut_id) if shortcut_id != &"" else -1
		if _branch >= 0:
			for i in track.hazard_gates.size():
				if track.hazard_gates[i] > 0.0 and track.distance_to_path(track.hazard_bounds[i].get_center(), _branch) < 8.0:
					_gate_route = true
	_update_missed(track, sim)
	var on_open: int = _open_branch_phase(track, sim)
	var look: float = LOOK_BASE + maxf(sim.speed, 0.0) * LOOK_PER_SPEED
	if on_open > 0 or (sim.road_half_width > 0.0 and sim.road_half_width < NARROW_HALF_WIDTH):
		look = OPEN_LOOK_BASE + maxf(sim.speed, 0.0) * OPEN_LOOK_PER_SPEED
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
	if dunk_s >= 0.0 and not _dunked and not track.data.open_edges.is_empty():
		if sim.is_sinking():
			_dunked = true
		elif sim.track_path == TrackModel.MAIN_PATH and sim.track_s >= dunk_s and sim.track_s < dunk_s + 60.0:
			input.steer = -track.data.open_edges[0].z
			input.drift = false
			return
	if blind_entrance > 0.0 and _branch >= 0:
		var bb: TrackModel.Path = track.branches[_branch]
		if sim.track_s >= bb.s_in - 12.0 and sim.track_s <= bb.s_in + blind_entrance:
			input.steer = 0.0
	if on_open > 0:
		# Careful line onto a plank with no rails: no drift, brake to the entry speed.
		_drifting_intent = false
		input.drift = false
		if on_open == 2 and sim.speed > OPEN_ENTRY_SPEED:
			input.throttle = 0.0
			input.brake = 1.0 if sim.speed > OPEN_ENTRY_SPEED + 1.0 else 0.0
		return
	if not allow_drift or _gate_on_route(track, sim):
		_drifting_intent = false
		input.drift = false
		return

	# Narrow roads (bridge, lanes, passage) abort a drift sooner.
	var abort_lat: float = minf(DRIFT_ABORT_LATERAL, maxf(sim.road_half_width * DRIFT_ABORT_WIDTH_FRAC, 1.0))
	if not sim.drifting:
		_drifting_intent = false
		if _near_open_entry(track, sim):
			input.drift = false
			return
		if absf(turn) > DRIFT_START_TURN and sim.speed > sim.stats.drift_min_speed + DRIFT_SPEED_MARGIN \
				and absf(sim.lateral) < abort_lat:
			_drifting_intent = true
			_drift_sign = signf(turn)
			input.steer = _drift_sign
	else:
		if absf(turn) < DRIFT_KEEP_TURN or signf(turn) != _drift_sign \
				or absf(sim.lateral) > abort_lat:
			_drifting_intent = false
		# Pure pursuit: the yaw rate that reaches the look-ahead point, mapped onto the
		# drift's steerable yaw-rate range.
		var rate: float = 2.0 * sin(diff) * maxf(sim.speed, 1.0) / look
		var st: VehicleStats = sim.stats
		input.steer = clampf((rate * _drift_sign - st.drift_yaw_base) / st.drift_yaw_range, -1.0, 1.0) \
				* _drift_sign
	input.drift = _drifting_intent


# Branch the route follows now: the chosen one (unless missed), or a rail-less deck the kart
# ended up on outside the main corridor (bumped onto the bridge: cross it, do not steer off).
func _route_branch(track: TrackModel, sim: KartSim) -> int:
	var p: int = sim.track_path
	# A kart that slid into the opening of a rail or gap shortcut it did not choose follows it to
	# its end instead of fighting its walls (lane splits share the main road's progress: skipped).
	if p >= 0 and p != _branch and track.data.branches[p].type != &"lane_split" 			and track.data.branches[p].open_edge_reach <= 0.0 and track.main.nearest(sim.position, -1, 0).excess > 0.0:
		return p
	if p >= 0 and p != _branch and track.data.branches[p].open_edge_reach > 0.0 			and track.main.nearest(sim.position, -1, 0).excess > 0.0:
		return p
	return -1 if (_branch < 0 or _missed) else _branch


# After a respawn on the main road past the entrance (or any miss), the branch is given up until
# the kart is past its exit: the route continues on the main road instead of cutting across.
func _update_missed(track: TrackModel, sim: KartSim) -> void:
	if _branch < 0:
		return
	var b: TrackModel.Path = track.branches[_branch]
	var s: float = sim.track_s
	if _missed:
		if s > b.s_out or s < b.s_in - OPEN_ENTRY_BEFORE:
			_missed = false
		return
	if sim.track_path == TrackModel.MAIN_PATH and s > b.s_in + MISS_MARGIN and s < b.s_out 			and track.distance_to_path(sim.position, _branch) > b.wall_offset + MISS_MARGIN:
		_missed = true


# True in the stretch before a rail-less entrance on the route where no new drift starts (a
# drift released there pays a boost, and a boosting kart cannot brake to the entry speed).
func _near_open_entry(track: TrackModel, sim: KartSim) -> bool:
	if _branch < 0 or _missed or track.data.branches[_branch].open_edge_reach <= 0.0:
		return false
	var b: TrackModel.Path = track.branches[_branch]
	return sim.track_s >= b.s_in - NO_DRIFT_BEFORE_OPEN and sim.track_s < b.s_in


# 0 = not near a rail-less branch on the route; 1 = on it; 2 = in its entrance zone (slow down).
func _open_branch_phase(track: TrackModel, sim: KartSim) -> int:
	if _branch < 0 or _missed or track.data.branches[_branch].open_edge_reach <= 0.0 or blind_entrance > 0.0:
		return 0
	var b: TrackModel.Path = track.branches[_branch]
	var s: float = sim.track_s
	if s < b.s_in - OPEN_ENTRY_BEFORE or s > b.s_out:
		return 0
	if s < b.s_in:
		return 2
	var u: float = track.branch_distance_for_s(_branch, s)
	return 2 if u < OPEN_ENTRY_AFTER else 1


# Point [param ahead] meters further along the intended route: the main line, or the chosen
# branch from [s_in - ahead] on, continuing on the main line after the branch ends.
func _route_point(track: TrackModel, sim: KartSim, ahead: float) -> Vector2:
	var s: float = sim.track_s
	var bi: int = _route_branch(track, sim)
	if bi < 0:
		return track.point_at(s + ahead)
	var b: TrackModel.Path = track.branches[bi]
	if s < b.s_in - ahead or s > b.s_out:
		return track.point_at(s + ahead)
	var u: float = track.branch_distance_for_s(bi, s) if s >= b.s_in else (s - b.s_in)
	var target_u: float = u + ahead
	if target_u < 0.0:
		return track.point_at(s + ahead)
	if target_u <= b.length:
		return track.branch_point_at(bi, target_u)
	return track.point_at(b.s_out + (target_u - b.length))


func _route_tangent(track: TrackModel, sim: KartSim, ahead: float) -> Vector2:
	return (_route_point(track, sim, ahead + TrackModel.TANGENT_STEP) 			- _route_point(track, sim, ahead - TrackModel.TANGENT_STEP)).normalized()


# True from 40 m before a gated branch's entrance until its end, on that route (see _gate_route).
func _gate_on_route(track: TrackModel, sim: KartSim) -> bool:
	if not _gate_route or _branch < 0 or _missed:
		return false
	var b: TrackModel.Path = track.branches[_branch]
	return sim.track_s >= b.s_in - 40.0 and sim.track_s <= b.s_out
