class_name KartSim
extends RefCounted
## Kart simulation: a kinematic arcade model on the XZ plane (no physics engine).
## Pure logic with no nodes, so it can run headless, be driven by any KartDriver, or have
## its state overwritten by interpolated network data (story 002).
##
## Implements design/game-brief.md, Features item 1: accelerate / brake / steer, drift that
## locks direction, 3 charge tiers paying a boost on release, boosts that never exceed the
## cap. All numbers come from the injected VehicleStats resource.
## Coordinates: position is (x, z). Heading [member yaw] 0 faces -Z, positive turns left.

## Emitted when a drift begins; [param direction] is +1 left, -1 right.
signal drift_started(direction: int)
## Emitted when a drift ends. [param tier] 0 means it did not reach tier 1 (no boost).
signal drift_ended(tier: int, boost_seconds: float)
## Emitted when the kart touches a wall; [param hard] is true if it cost speed.
signal wall_bumped(hard: bool)
## Bumped another kart; [param strength] is 0..1 (closing speed over bump_full_impact_speed).
signal kart_bumped(strength: float)
## Entered a hazard (moat water) and started sinking (story 003).
signal sank()
## Put back on the road after sinking (story 003).
signal respawned()
## Drove onto a boost pad (story 003).
signal pad_boosted()
## Left the ground (a ramp lip or a ledge, story 008). [param trick] is true when the drift hop
## was pressed inside the trick window before it.
signal took_off(trick: bool)
## Back on the ground after [param airtime] seconds in the air, hitting it at [param impact] m/s
## (vertical speed relative to the surface).
signal landed(airtime: float, impact: float)
## A trick jump paid its boost on landing.
signal trick_boosted()

## hazard_kind of a fall off the track (story 008): the kart falls instead of sinking.
const FALL_KIND: StringName = &"fall"

## Handling data for this kart.
var stats: VehicleStats

var position: Vector2 = Vector2.ZERO
var velocity: Vector2 = Vector2.ZERO
var yaw: float = 0.0
## Signed speed along the heading in m/s.
var speed: float = 0.0

var drifting: bool = false
## +1 left, -1 right, 0 when not drifting.
var drift_dir: int = 0
var drift_time: float = 0.0
## Tier reached by the current drift, 0..3.
var drift_tier: int = 0
var boost_time: float = 0.0
var spin_time: float = 0.0
## Seconds left in which the throttle is dead (too-early start). Brake still works.
var stall_time: float = 0.0
## Start boost level applied at GO, 0..3 (for logs and the HUD).
var start_boost_level: int = 0
## Seconds of hit immunity left (exposed for story 004; nothing sets it yet).
var hit_immunity_time: float = 0.0
## Last steering input, -1..1 (left positive); read by the visual for the drift pose.
var last_steer: float = 0.0
## Longitudinal acceleration in m/s^2 over the last tick (visual lean).
var accel_long: float = 0.0
## Lateral (centripetal) acceleration in m/s^2, positive when turning left (visual lean).
var accel_lat: float = 0.0

## Distance along the centerline, from the last track query.
var track_s: float = 0.0
## Signed lateral offset from the centerline (left positive).
var lateral: float = 0.0
## Road the kart is on: TrackModel.MAIN_PATH (-1) or a branch index (story 003).
var track_path: int = -1
## Half the road surface width where the kart is (from the last track query).
var road_half_width: float = 0.0
## Seconds left sinking in a hazard (0 = not sinking). The kart is frozen meanwhile.
var sink_time: float = 0.0
## 0 while not sinking, rising to 1 as the kart sinks (visual; sent to other PCs).
var sink_progress: float = 0.0
## Number of respawns since the last reset (logs and track_check).
var respawn_count: int = 0

## Height of the kart above the world origin plane in meters (story 008): it follows the road
## surface through a damped spring (VehicleStats.ride_*). The planar model above is unchanged.
var height: float = 0.0
## Vertical speed in m/s (positive = rising). Sent to other PCs.
var vertical_velocity: float = 0.0
## True while the kart rides on a surface; false in the air (off a ramp lip or a ledge).
var grounded: bool = true
## Seconds in the air so far (0 while grounded).
var air_time: float = 0.0
## Height of what holds the kart up under it, from the last query (TrackModel.Query.support).
var support_height: float = 0.0
## Road surface height beside or under the kart, from the last query (TrackModel.Query.height).
var road_height: float = 0.0
## False past an open edge (off the road's deck), from the last query.
var on_deck: bool = true
## Number of takeoffs, landings and trick boosts since the last reset (logs).
var jump_count: int = 0
var trick_count: int = 0
## Number of falls off the track since the last reset (logs and track_check).
var fall_count: int = 0
## Unit normal of the surface the kart stands on (from the last track query).
var surface_normal: Vector3 = Vector3.UP
## Bank of the road under the kart in radians (positive = banked into a left turn).
var surface_bank: float = 0.0

var _prev_position: Vector2 = Vector2.ZERO
var _prev_yaw: float = 0.0
var _prev_height: float = 0.0
# Road height and slope seen by the last query, for the suspension feed-forward and slope gravity.
var _surface_target: float = 0.0
var _road_slope: float = 0.0
var _road_tangent: Vector2 = Vector2.ZERO
var _segment_hint: int = -1
var _wall_cooldown: float = 0.0
var _bump_cooldown: float = 0.0
# Wall drag multiplier of the road the kart is on (rough passage walls grind harder).
var _wall_drag_mult: float = 1.0
# Floor drag multiplier of the road the kart is on (sleepers of the mine rail; 1 = smooth).
var _floor_drag_mult: float = 1.0
## Kind of the hazard (water, lava) the kart last sank in; picks the sink visual. FALL_KIND after
## falling off the track (story 008).
var hazard_kind: StringName = &"water"
# True when the sink was in a speed-gated hazard: the respawn then uses the main road.
var _gate_sink: bool = false
## Knock from kart bumps (m/s): moves the kart on top of its driving velocity and fades
## out (stats.bump_knock_decay), so grip cannot cancel a shove at once.
var knock: Vector2 = Vector2.ZERO
## Strength (0..1) of the last kart bump this kart detected.
var last_bump_strength: float = 0.0
# Recent bump knock per other kart id, so the same contact is not felt twice.
var _pair_bumps: Dictionary = {}
var _pair_timers: Dictionary = {}
var _wall_slide_time: float = 0.0
var _turnback_rate: float = 0.0
var _slow_time: float = 0.0
var _slow_profile: HitSlowdownProfile
# Last point the kart drove on a road surface: road index and meters along it.
var _safe_path: int = -1
var _safe_along: float = 0.0
# Last point driven on the main road itself (fallback when respawning on a branch repeats).
var _main_safe_along: float = 0.0
# True when this sink started while still immune from the previous respawn.
var _repeat_sink: bool = false
var _on_pad: bool = false
var _sink_total: float = 1.0
# Air state (story 008): yaw rate in the air, the yaw rate of the last grounded tick, seconds
# since drift was last pressed on the ground, the drift button last tick, a pending trick, and
# seconds in the air off the road's deck.
var _air_yaw_rate: float = 0.0
var _ground_yaw_rate: float = 0.0
var _since_hop: float = INF
var _prev_drift_btn: bool = false
var _trick_pending: bool = false
var _off_deck_air: float = 0.0


func _init(vehicle_stats: VehicleStats) -> void:
	stats = vehicle_stats


## Resets all state and places the kart [param distance] meters along the centerline
## (wraps), offset [param lateral_offset] sideways, facing along the track.
func reset_to(track: TrackModel, distance: float, lateral_offset: float) -> void:
	position = track.point_at(distance) + track.normal_at(distance) * lateral_offset
	var t: Vector2 = track.tangent_at(distance)
	yaw = atan2(-t.x, -t.y)
	velocity = Vector2.ZERO
	speed = 0.0
	drifting = false
	drift_dir = 0
	drift_time = 0.0
	drift_tier = 0
	boost_time = 0.0
	spin_time = 0.0
	_wall_cooldown = 0.0
	_bump_cooldown = 0.0
	knock = Vector2.ZERO
	_pair_bumps.clear()
	_pair_timers.clear()
	_wall_slide_time = 0.0
	_turnback_rate = 0.0
	_slow_time = 0.0
	_slow_profile = null
	stall_time = 0.0
	start_boost_level = 0
	hit_immunity_time = 0.0
	last_steer = 0.0
	accel_long = 0.0
	accel_lat = 0.0
	sink_time = 0.0
	sink_progress = 0.0
	respawn_count = 0
	_on_pad = false
	air_time = 0.0
	jump_count = 0
	trick_count = 0
	fall_count = 0
	_air_yaw_rate = 0.0
	_ground_yaw_rate = 0.0
	_since_hop = INF
	_prev_drift_btn = false
	_trick_pending = false
	_off_deck_air = 0.0
	hazard_kind = &"water"
	# Story 008 part 3: the grid slot is on the road at the start's own level (a crossover near the
	# start never puts the kart on the other road).
	var q: TrackModel.Query = track.query(position, -1, track.height_at(distance))
	_segment_hint = q.segment
	track_s = q.s
	track_path = q.path
	lateral = q.lateral
	road_half_width = q.half_width
	_safe_path = q.path
	_safe_along = q.along
	_main_safe_along = q.s
	_prev_position = position
	_prev_yaw = yaw
	_snap_to_surface(q)


## Unit vector the kart faces, in (x, z).
func forward() -> Vector2:
	return Vector2(-sin(yaw), -cos(yaw))


## True while the kart can be driven (not spinning out).
func can_drive() -> bool:
	return spin_time <= 0.0


## Speed cap right now: max_speed, times the boost multiplier while boosting.
func current_speed_cap() -> float:
	if boost_time > 0.0:
		return stats.max_speed * stats.boost_speed_mult
	return stats.max_speed / maxf(_floor_drag_mult, 1.0)


## Position blended between the last two ticks, for smooth rendering.
func interpolated_position(fraction: float) -> Vector2:
	return _prev_position.lerp(position, fraction)


## Height blended between the last two ticks, for smooth rendering.
func interpolated_height(fraction: float) -> float:
	return lerpf(_prev_height, height, fraction)


## Reads the road surface under the kart (surface normal, bank) without moving it. Used for
## karts drawn from network data, whose height comes from the wire: on a road deck the drawn
## height never goes below the surface (interpolating between two snapshots across a ramp lip
## or a landing could otherwise dip under the road).
func sample_surface(track: TrackModel) -> void:
	var q: TrackModel.Query = track.query(position, _segment_hint, height)
	_segment_hint = q.segment
	support_height = q.support
	road_height = q.height
	on_deck = q.on_deck
	if q.on_deck and height < q.support:
		height = q.support
	if height - q.support <= stats.ride_max_gap:
		surface_normal = q.surface_normal
		surface_bank = q.bank


## Yaw blended between the last two ticks, for smooth rendering.
func interpolated_yaw(fraction: float) -> float:
	return lerp_angle(_prev_yaw, yaw, fraction)


## True when karts [param a] and [param b] are at different heights (more than
## VehicleStats.bump_max_height_diff apart): one on a bridge and one under it, or one flying over
## the other. Such karts never touch (story 008).
static func levels_apart(a: KartSim, b: KartSim) -> bool:
	return absf(a.height - b.height) > minf(a.stats.bump_max_height_diff, b.stats.bump_max_height_diff)


## Distance between the two karts' body capsules (negative = overlapping, in meters). INF when
## they are at different heights (see [method levels_apart]).
static func body_gap(a: KartSim, b: KartSim) -> float:
	if levels_apart(a, b):
		return INF
	var af: Vector2 = a.forward() * a.stats.bump_half_length
	var bf: Vector2 = b.forward() * b.stats.bump_half_length
	var pts: PackedVector2Array = Geometry2D.get_closest_points_between_segments(
			a.position + af, a.position - af, b.position + bf, b.position - bf)
	return pts[0].distance_to(pts[1]) - a.stats.bump_radius - b.stats.bump_radius


## Moves two karts apart when their bodies overlap: [param a] takes [param a_part] of the
## overlap and [param b] takes [param b_part] (owned karts: their weight shares; a remote
## kart against an owned one: 0, since its owner moves it; two remote karts: half each,
## display only). Position only, no bump effects.
static func push_apart(a: KartSim, b: KartSim, a_part: float, b_part: float) -> void:
	if levels_apart(a, b):
		return
	var af: Vector2 = a.forward() * a.stats.bump_half_length
	var bf: Vector2 = b.forward() * b.stats.bump_half_length
	var pts: PackedVector2Array = Geometry2D.get_closest_points_between_segments(
			a.position + af, a.position - af, b.position + bf, b.position - bf)
	var d: Vector2 = pts[0] - pts[1]
	var overlap: float = a.stats.bump_radius + b.stats.bump_radius - d.length()
	if overlap <= 0.0:
		return
	var n: Vector2 = d.normalized() if d.length() > 0.0001 else (a.position - b.position).normalized()
	if n == Vector2.ZERO:
		n = a.forward().orthogonal()
	a.position += n * overlap * a_part
	b.position -= n * overlap * b_part


## Puts the kart back inside the walls (position only, no wall effects). Used after karts
## are pushed apart, so a push can never leave a kart inside a wall.
func clamp_to_walls(track: TrackModel) -> void:
	var q: TrackModel.Query = track.query(position, _segment_hint, height)
	_segment_hint = q.segment
	var limit: float = q.wall_offset - stats.radius
	if absf(q.lateral) > limit:
		position -= q.normal * signf(q.lateral) * (absf(q.lateral) - limit)


## Display only: moves two remote karts apart (half each) when they are drawn overlapping.
## Their owners keep them apart; the overlap comes from showing them slightly in the past.
## Remote positions are rebuilt from network updates every tick, so nothing accumulates.
static func separate_for_display(a: KartSim, b: KartSim) -> void:
	if levels_apart(a, b):
		return
	var af: Vector2 = a.forward() * a.stats.bump_half_length
	var bf: Vector2 = b.forward() * b.stats.bump_half_length
	var pts: PackedVector2Array = Geometry2D.get_closest_points_between_segments(
			a.position + af, a.position - af, b.position + bf, b.position - bf)
	var d: Vector2 = pts[0] - pts[1]
	var overlap: float = a.stats.bump_radius + b.stats.bump_radius - d.length()
	if overlap <= 0.0:
		return
	var n: Vector2 = d.normalized() if d.length() > 0.0001 else (a.position - b.position).normalized()
	a.position += n * overlap * 0.5
	b.position -= n * overlap * 0.5


## Pushes this kart out of [param other] when their bodies overlap, and applies the bump.
## Each kart's body is a capsule along its heading (stats.bump_half_length, bump_radius).
## Only owned karts call this: each PC moves its own karts, and remote karts move through
## their owner's updates. [param full_separation] (against a kart another PC owns) removes
## the whole overlap here, since the other PC sees this kart slightly in the past and may not
## see the contact; otherwise (both karts on this PC) each takes its weight share.
## [param other_push] is the other kart's push on this one and [param my_push] this kart's
## push on the other (both already scaled for bots). Returns the knock the OTHER kart should
## get (its owner applies it through apply_received_bump), or Vector2.ZERO.
func resolve_kart_contact(other: KartSim, other_id: int, other_push: float, my_push: float,
		full_separation: bool) -> Vector2:
	if levels_apart(self, other):
		return Vector2.ZERO
	var a0: Vector2 = position + forward() * stats.bump_half_length
	var a1: Vector2 = position - forward() * stats.bump_half_length
	var of: Vector2 = other.forward()
	var b0: Vector2 = other.position + of * other.stats.bump_half_length
	var b1: Vector2 = other.position - of * other.stats.bump_half_length
	var pts: PackedVector2Array = Geometry2D.get_closest_points_between_segments(a0, a1, b0, b1)
	var d: Vector2 = pts[0] - pts[1]
	var min_dist: float = stats.bump_radius + other.stats.bump_radius
	var dist: float = d.length()
	if dist >= min_dist:
		return Vector2.ZERO
	var n: Vector2 = d / dist if dist > 0.0001 else (position - other.position).normalized()
	if n == Vector2.ZERO:
		n = forward().orthogonal()
	var share: float = other_push / maxf(my_push + other_push, 0.0001)
	position += n * (min_dist - dist) * (1.0 if full_separation else share)
	var closing: float = (velocity + knock - other.velocity - other.knock).dot(n)
	if closing >= 0.0:
		return Vector2.ZERO
	var strength: float = clampf(-closing / maxf(stats.bump_full_impact_speed, 0.0001), 0.0, 1.0)
	last_bump_strength = strength
	_take_bump(other_id, -n * closing * share * (1.0 + stats.bump_restitution), strength)
	return n * closing * (1.0 - share) * (1.0 + stats.bump_restitution)


## Applies a bump another PC detected between [param from_id]'s kart and this one (it
## sees the contact before this PC does). A bump this kart already took from the same kart
## in the last bump_cooldown seconds counts against it, so a contact is never felt twice.
func apply_received_bump(from_id: int, impulse: Vector2, strength: float) -> void:
	_take_bump(from_id, impulse, strength)


func _take_bump(from_id: int, impulse: Vector2, strength: float) -> void:
	var already: float = float(_pair_bumps.get(from_id, 0.0))
	var mag: float = impulse.length()
	if mag > already:
		knock += impulse * ((mag - already) / mag)
		# Pile-ups add several bumps at once: cap the total so a kart is never launched.
		knock = knock.limit_length(stats.bump_knock_max)
		_pair_bumps[from_id] = mag
		_pair_timers[from_id] = stats.bump_cooldown
	if _bump_cooldown <= 0.0:
		speed *= 1.0 - stats.bump_speed_loss * strength
		_bump_cooldown = stats.bump_cooldown
		kart_bumped.emit(strength)


## Spins the kart out (used by items in story 004). Returns false if already spinning.
func hit() -> bool:
	if spin_time > 0.0:
		return false
	spin_time = stats.spin_time
	_end_drift(false)
	boost_time = 0.0
	return true


## Applies the start result decided at GO: a start boost of [param level] (1..3, 0 = none)
## using stats.start_boost_times, or a throttle stall when [param stalled].
func apply_start(level: int, stalled: bool) -> void:
	start_boost_level = level
	if level > 0 and level < stats.start_boost_times.size():
		boost_time = maxf(boost_time, stats.start_boost_times[level])
	if stalled:
		stall_time = stats.start_stall_time


## Starts a hit slowdown with profile [param profile_index] (0 light, 1 medium, 2 heavy):
## decelerates at the profile's rate for its duration, never below its minimum speed.
## Unused until story 004 (items). Out-of-range indices are ignored.
func apply_hit_slowdown(profile_index: int) -> void:
	if profile_index < 0 or profile_index >= stats.hit_slowdown_profiles.size():
		return
	_slow_profile = stats.hit_slowdown_profiles[profile_index]
	_slow_time = _slow_profile.duration


## Starts the post-hit immunity timer (stats.hit_immunity_time). Nothing calls it yet.
func start_hit_immunity() -> void:
	hit_immunity_time = stats.hit_immunity_time


## True while hit immunity is running.
func is_hit_immune() -> bool:
	return hit_immunity_time > 0.0


## True while the kart is sinking in a hazard (frozen, waiting for its respawn).
func is_sinking() -> bool:
	return sink_time > 0.0 or sink_progress > 0.0


## Advances the simulation by [param dt] seconds using [param input] on [param track].
func tick(dt: float, input: KartInput, track: TrackModel) -> void:
	_prev_position = position
	_prev_yaw = yaw
	_prev_height = height
	if sink_time > 0.0:
		sink_time = maxf(0.0, sink_time - dt)
		if hazard_kind == FALL_KIND:
			# Fell off the track: no sinking, the kart just keeps falling to the ground.
			vertical_velocity -= stats.air_gravity * dt
			height += vertical_velocity * dt
			if height <= track.data.ground_y:
				height = track.data.ground_y
				vertical_velocity = 0.0
		else:
			sink_progress = 1.0 - sink_time / maxf(_sink_total, 0.001)
		speed = 0.0
		velocity = Vector2.ZERO
		knock = Vector2.ZERO
		accel_long = 0.0
		accel_lat = 0.0
		if sink_time <= 0.0:
			_respawn(track)
		return
	var control: bool = can_drive()
	var steer: float = input.steer if control else 0.0
	var throttle: float = input.throttle if control and stall_time <= 0.0 else 0.0
	last_steer = steer
	var speed_before: float = speed
	var brake: float = input.brake if control else 0.0
	# Trick jump timing: seconds since drift (the hop) was last pressed on the ground.
	if grounded:
		_since_hop = 0.0 if (input.drift and not _prev_drift_btn) else _since_hop + dt
	_prev_drift_btn = input.drift

	# Drift: hold the button while steering at speed. The direction locks in. A drift starts on
	# the ground only; one held into a jump carries on through the air.
	if not drifting and control and grounded and input.drift and absf(steer) > stats.drift_start_steer \
			and speed > stats.drift_min_speed:
		drifting = true
		drift_dir = 1 if steer > 0.0 else -1
		drift_time = 0.0
		drift_tier = 0
		drift_started.emit(drift_dir)
	if drifting and (not input.drift or speed < stats.drift_min_speed * stats.drift_end_speed_frac \
			or not control):
		_end_drift(true)

	# In the air the planar velocity is kept: no throttle, brake, drag or grip (story 008).
	if grounded:
		_update_speed(dt, throttle, brake)

	var yaw_rate: float = 0.0
	if not grounded:
		# Air control (notes 3.8): the yaw rate eases toward the steer at a limited rate.
		_air_yaw_rate = move_toward(_air_yaw_rate, steer * stats.air_yaw_max, stats.air_yaw_accel * dt)
		yaw_rate = _air_yaw_rate
	elif drifting:
		yaw_rate = drift_dir * (stats.drift_yaw_base
				+ stats.drift_yaw_range * clampf(steer * drift_dir, -1.0, 1.0))
	else:
		var low_speed: float = clampf(absf(speed) / stats.full_steer_speed, 0.0, 1.0)
		var damp: float = 1.0 - stats.high_speed_steer_damp * clampf(speed / stats.max_speed, 0.0, 1.0)
		yaw_rate = steer * stats.turn_rate * low_speed * damp * (1.0 if speed >= 0.0 else -1.0)
	if grounded:
		_ground_yaw_rate = yaw_rate
	yaw += yaw_rate * dt
	accel_long = (speed - speed_before) / dt if dt > 0.0 else 0.0
	accel_lat = yaw_rate * speed if grounded else 0.0

	if grounded:
		var grip: float = stats.drift_grip if drifting else stats.grip
		if stats.bank_grip_gain > 0.0:
			grip *= 1.0 + stats.bank_grip_gain * absf(sin(surface_bank))
		if _wall_slide_time > 0.0:
			grip = minf(grip, stats.wall_slide_grip)
		velocity = velocity.lerp(forward() * speed, clampf(grip * dt, 0.0, 1.0))
	position += (velocity + knock) * dt
	knock *= exp(-stats.bump_knock_decay * dt)

	# Tighter drifts charge faster.
	if drifting:
		drift_time += dt * (1.0 + stats.drift_charge_steer_bonus * maxf(steer * drift_dir, 0.0))
		drift_tier = 0
		for i in stats.drift_tier_times.size():
			if drift_time >= stats.drift_tier_times[i]:
				drift_tier = i + 1

	boost_time = maxf(0.0, boost_time - dt)
	spin_time = maxf(0.0, spin_time - dt)
	_wall_cooldown = maxf(0.0, _wall_cooldown - dt)
	_bump_cooldown = maxf(0.0, _bump_cooldown - dt)
	for k in _pair_timers.keys():
		_pair_timers[k] = float(_pair_timers[k]) - dt
		if float(_pair_timers[k]) <= 0.0:
			_pair_timers.erase(k)
			_pair_bumps.erase(k)
	_wall_slide_time = maxf(0.0, _wall_slide_time - dt)
	stall_time = maxf(0.0, stall_time - dt)
	hit_immunity_time = maxf(0.0, hit_immunity_time - dt)
	_constrain_to_track(dt, track)


func _update_speed(dt: float, throttle: float, brake: float) -> void:
	# Gravity along the slope (stats.slope_gravity): uphill slows, downhill speeds up. A bank adds
	# no sideways force at all: only the component along the road matters.
	if grounded and stats.slope_gravity != 0.0 and _road_tangent != Vector2.ZERO:
		speed -= stats.slope_gravity * sin(atan(_road_slope)) * forward().dot(_road_tangent) * dt
	var boosting: bool = boost_time > 0.0
	var cap: float = current_speed_cap()
	# Accelerate toward the cap, never past it. This is what stops boosts stacking
	# above the cap; above the cap (a boost just ended) speed eases back down below.
	var push: float = stats.accel * stats.boost_accel_mult if boosting else stats.accel * throttle
	if push > 0.0 and speed < cap:
		speed = minf(speed + push * dt, cap)
	if brake > 0.0:
		if speed > 0.0:
			speed -= stats.brake * brake * dt
		else:
			speed -= stats.accel * stats.reverse_accel_frac * brake * dt
	if throttle <= 0.0 and brake <= 0.0 and not boosting:
		speed = move_toward(speed, 0.0, stats.coast_drag * dt)
	if speed > cap:
		speed = move_toward(speed, cap, stats.overspeed_decel * dt)
	speed = maxf(speed, -stats.reverse_max)
	if spin_time > 0.0:
		speed *= exp(-stats.spin_drag * dt)
	if _slow_time > 0.0 and _slow_profile != null:
		var floor_speed: float = _slow_profile.min_speed_frac * stats.max_speed
		if speed > floor_speed:
			speed = maxf(speed - _slow_profile.decel_frac * stats.max_speed * dt, floor_speed)
		_slow_time = maxf(0.0, _slow_time - dt)


func _end_drift(pay_boost: bool) -> void:
	if not drifting:
		return
	var tier: int = drift_tier if pay_boost else 0
	var boost_seconds: float = 0.0
	if tier > 0 and tier < stats.drift_boost_times.size():
		boost_seconds = stats.drift_boost_times[tier]
		boost_time = maxf(boost_time, boost_seconds)
	drifting = false
	drift_dir = 0
	drift_time = 0.0
	drift_tier = 0
	drift_ended.emit(tier, boost_seconds)


func _constrain_to_track(dt: float, track: TrackModel) -> void:
	var q: TrackModel.Query = track.query(position, _segment_hint, height)
	_segment_hint = q.segment
	track_path = q.path
	_wall_drag_mult = q.wall_drag_mult
	_floor_drag_mult = q.floor_drag_mult
	lateral = q.lateral
	var limit: float = q.wall_offset - stats.radius
	var touching: bool = false
	if absf(lateral) > limit:
		var outward: Vector2 = q.normal * signf(lateral)
		position -= outward * (absf(lateral) - limit)
		# A wall stops the part of a bump knock that drives into it.
		knock -= outward * maxf(knock.dot(outward), 0.0)
		var into_wall: float = velocity.dot(outward)
		if into_wall > 0.0:
			touching = true
			var angle: float = rad_to_deg(asin(clampf(into_wall / maxf(velocity.length(), 0.001), 0.0, 1.0)))
			velocity -= outward * into_wall * stats.bump_knockback
			_wall_contact(angle, dt)
	if (touching or _wall_slide_time > 0.0) and _turnback_rate > 0.0 and speed > 0.0:
		# The wall turns the kart back toward the track direction.
		var t: Vector2 = q.tangent
		var want: float = atan2(-t.x, -t.y)
		var step: float = _turnback_rate * dt
		yaw += clampf(wrapf(want - yaw, -PI, PI), -step, step)
	elif not touching:
		_turnback_rate = 0.0
	# Progress follows the road, but never faster than the rate cap allows (smooth at junctions).
	track_s = track.limit_progress(track_s, q.s, position.distance_to(_prev_position))
	_ride_surface(dt, q)
	road_half_width = q.half_width
	# Story 008 part 3: a hazard has a surface height. The kart sinks only at or below it (also
	# when it falls in from a raised road), never on a bridge or in the air above it; over a
	# hazard it is not caught by the fall respawn, it keeps falling until it reaches the surface.
	if track.has_hazards():
		var hz: int = track.hazard_index(position, q, speed, height)
		if hz >= 0:
			hazard_kind = track.hazard_kinds[hz]
			_gate_sink = track.hazard_gates[hz] > 0.0
			_start_sinking(track)
			return
	var over_hazard: bool = not q.on_deck and track.has_hazards() and track.hazard_below(position, height)
	if not over_hazard and _fell_off(dt, q, track):
		return
	if not grounded:
		return  # no safe point or pad while flying
	if absf(lateral) <= q.half_width:
		_safe_path = q.path
		_safe_along = q.along
		if q.path == TrackModel.MAIN_PATH:
			_main_safe_along = q.along
	var pad: int = track.pad_at(position, height)
	if pad >= 0:
		boost_time = maxf(boost_time, track.data.boost_pad_time)
		if not _on_pad:
			pad_boosted.emit()
	_on_pad = pad >= 0


# Height follows the road through a damped spring with the surface's own vertical speed as
# feed-forward (so a steady climb has no lag). The surface is a hard floor, and the kart never
# floats more than stats.ride_max_gap above it.
#
# Story 008: the support is the road deck (with any ramp), or the ground past an open edge. When
# it drops away by more than stats.air_takeoff_gap in one tick (a ramp lip, a ledge) the kart
# takes off with its current vertical speed (the climb rate at the lip) and flies under
# stats.air_gravity until it meets the support again.
func _ride_surface(dt: float, q: TrackModel.Query) -> void:
	support_height = q.support
	road_height = q.height
	on_deck = q.on_deck
	var target: float = q.support
	var target_v: float = clampf((target - _surface_target) / dt, -stats.ride_max_target_speed, stats.ride_max_target_speed) if dt > 0.0 else 0.0
	_surface_target = target
	if grounded and height - target > stats.air_takeoff_gap:
		_take_off()
	if not grounded:
		air_time += dt
		vertical_velocity -= stats.air_gravity * dt
		height += vertical_velocity * dt
		if height > target:
			return
		_land(target, target_v)
	if q.on_deck:
		surface_normal = q.surface_normal
		surface_bank = q.bank
		_road_slope = q.slope
		_road_tangent = q.tangent
	else:
		surface_normal = Vector3.UP
		surface_bank = 0.0
		_road_slope = 0.0
	var acc: float = stats.ride_spring * (target - height) + stats.ride_damping * (target_v - vertical_velocity)
	vertical_velocity += acc * dt
	height += vertical_velocity * dt
	if height < target:
		height = target
		vertical_velocity = maxf(vertical_velocity, target_v)
	elif height > target + stats.ride_max_gap:
		height = target + stats.ride_max_gap
		vertical_velocity = minf(vertical_velocity, target_v)


# Leaves the ground: keeps the vertical speed, starts the air yaw from the last ground yaw rate
# (capped to the air limit) and arms a trick when the hop came inside the trick window.
func _take_off() -> void:
	grounded = false
	air_time = 0.0
	jump_count += 1
	_air_yaw_rate = clampf(_ground_yaw_rate, -stats.air_yaw_max, stats.air_yaw_max)
	_trick_pending = _since_hop <= stats.trick_window
	took_off.emit(_trick_pending)


# Meets the support [param target] (moving at [param target_v]) again: on the ground, and the
# trick boost is paid when the jump was long enough.
func _land(target: float, target_v: float) -> void:
	var impact: float = maxf(target_v - vertical_velocity, 0.0)
	height = target
	vertical_velocity = target_v
	grounded = true
	var airtime: float = air_time
	air_time = 0.0
	_since_hop = INF
	landed.emit(airtime, impact)
	if _trick_pending and airtime >= stats.trick_min_airtime:
		boost_time = maxf(boost_time, stats.trick_boost_time)
		trick_count += 1
		trick_boosted.emit()
	_trick_pending = false


# Off the track (story 008): past an open edge over a drop, a kart that is fall_respawn_depth
# below the road, or in the air off the deck for fall_respawn_time, or standing on the ground
# well below the road, has fallen: it is put back like a hazard respawn. Returns true then.
func _fell_off(dt: float, q: TrackModel.Query, track: TrackModel) -> bool:
	if q.on_deck:
		_off_deck_air = 0.0
		return false
	if not grounded:
		_off_deck_air += dt
	var below: float = q.height - height
	var fallen: bool = below > track.data.fall_respawn_depth or _off_deck_air > track.data.fall_respawn_time \
			or (grounded and below > stats.air_takeoff_gap)
	if not fallen:
		return false
	hazard_kind = FALL_KIND
	_gate_sink = false
	_off_deck_air = 0.0
	fall_count += 1
	_start_sinking(track)
	return true


# Places the kart exactly on the surface (reset, respawn): no suspension travel.
func _snap_to_surface(q: TrackModel.Query) -> void:
	height = q.height
	_prev_height = height
	_surface_target = height
	vertical_velocity = 0.0
	grounded = true
	air_time = 0.0
	_off_deck_air = 0.0
	_trick_pending = false
	support_height = q.support
	road_height = q.height
	on_deck = q.on_deck
	surface_normal = q.surface_normal
	surface_bank = q.bank
	_road_slope = q.slope
	_road_tangent = q.tangent


# Entered a hazard: the kart stops, loses its drift and boost, and sinks for
# track.data.respawn_sink_time seconds (see tick), then _respawn puts it back.
func _start_sinking(track: TrackModel) -> void:
	_end_drift(false)
	boost_time = 0.0
	speed = 0.0
	velocity = Vector2.ZERO
	knock = Vector2.ZERO
	# Sinking again before the last respawn's immunity ran out means the branch respawn point
	# did not work for this kart: the next respawn uses the main road instead (no loop).
	_repeat_sink = hit_immunity_time > 0.0 and respawn_count > 0
	_trick_pending = false
	_sink_total = maxf(track.data.fall_respawn_delay if hazard_kind == FALL_KIND else track.data.respawn_sink_time, 0.001)
	sink_time = _sink_total
	sink_progress = 0.0
	sank.emit()


# Back on the centerline of the road last driven safely, respawn_back_off meters behind that
# point, facing along the road, at respawn_speed_frac of max speed with respawn immunity.
func _respawn(track: TrackModel) -> void:
	if (_repeat_sink or _gate_sink) and _safe_path != TrackModel.MAIN_PATH:
		_safe_path = TrackModel.MAIN_PATH
		_safe_along = _main_safe_along
	var pose: Array = track.respawn_pose(_safe_path, _safe_along)
	position = pose[0]
	var t: Vector2 = pose[1]
	yaw = atan2(-t.x, -t.y)
	speed = track.data.respawn_speed_frac * stats.max_speed
	velocity = forward() * speed
	hit_immunity_time = track.data.respawn_immunity_time
	spin_time = 0.0
	sink_progress = 0.0
	var safe_road: TrackModel.Path = track.path_of(_safe_path)
	var st: Vector2 = safe_road.seg_t_at(_safe_along - track.data.respawn_back_off)
	var q: TrackModel.Query = track.query(position, track.hint_for(_safe_path, _safe_along),
			safe_road.height_at(int(st.x), st.y))
	_segment_hint = q.segment
	track_s = q.s
	track_path = q.path
	lateral = q.lateral
	road_half_width = q.half_width
	_snap_to_surface(q)
	_prev_position = position
	_prev_yaw = yaw
	respawn_count += 1
	respawned.emit()


## Wall response by angle of incidence: scrape (friction x multiplier), or impact (speed
## loss scaled by angle, slide, cooldown). See VehicleStats wall_* fields.
func _wall_contact(angle: float, dt: float) -> void:
	var impact: bool = angle >= stats.wall_impact_threshold_angle and _wall_cooldown <= 0.0
	_turnback_rate = deg_to_rad(lerpf(stats.wall_turnback_min_rate, stats.wall_turnback_max_rate,
			clampf(angle / stats.wall_impact_max_angle, 0.0, 1.0)))
	if impact:
		var t: float = clampf(inverse_lerp(stats.wall_impact_min_angle, stats.wall_impact_max_angle, angle), 0.0, 1.0)
		speed *= 1.0 - stats.wall_impact_max_speed_loss * t
		_wall_slide_time = stats.wall_impact_slide_time
		_wall_cooldown = stats.wall_hit_cooldown
		wall_bumped.emit(true)
		return
	var mult: float = 1.0
	if angle >= stats.wall_scrape_min_angle and angle <= stats.wall_scrape_max_angle:
		var fade: float = 0.0
		if angle > stats.wall_impact_threshold_angle:
			fade = inverse_lerp(stats.wall_impact_threshold_angle, stats.wall_scrape_max_angle, angle)
		mult = lerpf(stats.wall_scrape_friction_mult, 1.0, clampf(fade, 0.0, 1.0))
	speed *= 1.0 - stats.wall_friction_drag * mult * _wall_drag_mult * dt
	wall_bumped.emit(false)
