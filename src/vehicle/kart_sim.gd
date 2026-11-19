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

var _prev_position: Vector2 = Vector2.ZERO
var _prev_yaw: float = 0.0
var _segment_hint: int = -1
var _wall_cooldown: float = 0.0
var _bump_cooldown: float = 0.0
var _wall_slide_time: float = 0.0
var _turnback_rate: float = 0.0
var _slow_time: float = 0.0
var _slow_profile: HitSlowdownProfile


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
	var q: TrackModel.Query = track.query(position, -1)
	_segment_hint = q.segment
	track_s = q.s
	lateral = q.lateral
	_prev_position = position
	_prev_yaw = yaw


## Unit vector the kart faces, in (x, z).
func forward() -> Vector2:
	return Vector2(-sin(yaw), -cos(yaw))


## True while the kart can be driven (not spinning out).
func can_drive() -> bool:
	return spin_time <= 0.0


## Speed cap right now: max_speed, times the boost multiplier while boosting.
func current_speed_cap() -> float:
	return stats.max_speed * (stats.boost_speed_mult if boost_time > 0.0 else 1.0)


## Position blended between the last two ticks, for smooth rendering.
func interpolated_position(fraction: float) -> Vector2:
	return _prev_position.lerp(position, fraction)


## Yaw blended between the last two ticks, for smooth rendering.
func interpolated_yaw(fraction: float) -> float:
	return lerp_angle(_prev_yaw, yaw, fraction)


## Pushes this kart out of another kart it overlaps and applies the bump to its motion.
## Only owned karts call this: each PC moves its own karts, and remote karts move through
## their owner's updates. Each side takes the share of the separation set by the OTHER
## kart's push, so two karts on two PCs together resolve the whole overlap.
## [param other_push] is the other kart's push strength (already scaled for bots).
## Returns true when the karts touched.
func resolve_kart_contact(other_pos: Vector2, other_vel: Vector2, other_radius: float,
		other_push: float) -> bool:
	var d: Vector2 = position - other_pos
	var min_dist: float = stats.radius + other_radius
	var dist: float = d.length()
	if dist >= min_dist:
		return false
	var n: Vector2 = d / dist if dist > 0.0001 else forward().orthogonal()
	var share: float = other_push / maxf(stats.bump_push_mult + other_push, 0.0001)
	position += n * (min_dist - dist) * share
	var closing: float = (velocity - other_vel).dot(n)
	if closing < 0.0:
		velocity -= n * closing * share * (1.0 + stats.bump_restitution)
		var strength: float = clampf(-closing / maxf(stats.bump_full_impact_speed, 0.0001), 0.0, 1.0)
		if _bump_cooldown <= 0.0:
			speed *= 1.0 - stats.bump_speed_loss * strength
			_bump_cooldown = stats.bump_cooldown
			kart_bumped.emit(strength)
	return true


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


## Advances the simulation by [param dt] seconds using [param input] on [param track].
func tick(dt: float, input: KartInput, track: TrackModel) -> void:
	_prev_position = position
	_prev_yaw = yaw
	var control: bool = can_drive()
	var steer: float = input.steer if control else 0.0
	var throttle: float = input.throttle if control and stall_time <= 0.0 else 0.0
	last_steer = steer
	var speed_before: float = speed
	var brake: float = input.brake if control else 0.0

	# Drift: hold the button while steering at speed. The direction locks in.
	if not drifting and control and input.drift and absf(steer) > stats.drift_start_steer \
			and speed > stats.drift_min_speed:
		drifting = true
		drift_dir = 1 if steer > 0.0 else -1
		drift_time = 0.0
		drift_tier = 0
		drift_started.emit(drift_dir)
	if drifting and (not input.drift or speed < stats.drift_min_speed * stats.drift_end_speed_frac \
			or not control):
		_end_drift(true)

	_update_speed(dt, throttle, brake)

	var yaw_rate: float = 0.0
	if drifting:
		yaw_rate = drift_dir * (stats.drift_yaw_base
				+ stats.drift_yaw_range * clampf(steer * drift_dir, -1.0, 1.0))
	else:
		var low_speed: float = clampf(absf(speed) / stats.full_steer_speed, 0.0, 1.0)
		var damp: float = 1.0 - stats.high_speed_steer_damp * clampf(speed / stats.max_speed, 0.0, 1.0)
		yaw_rate = steer * stats.turn_rate * low_speed * damp * (1.0 if speed >= 0.0 else -1.0)
	yaw += yaw_rate * dt
	accel_long = (speed - speed_before) / dt if dt > 0.0 else 0.0
	accel_lat = yaw_rate * speed

	var grip: float = stats.drift_grip if drifting else stats.grip
	if _wall_slide_time > 0.0:
		grip = minf(grip, stats.wall_slide_grip)
	velocity = velocity.lerp(forward() * speed, clampf(grip * dt, 0.0, 1.0))
	position += velocity * dt

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
	_wall_slide_time = maxf(0.0, _wall_slide_time - dt)
	stall_time = maxf(0.0, stall_time - dt)
	hit_immunity_time = maxf(0.0, hit_immunity_time - dt)
	_constrain_to_track(dt, track)


func _update_speed(dt: float, throttle: float, brake: float) -> void:
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
	var q: TrackModel.Query = track.query(position, _segment_hint)
	_segment_hint = q.segment
	lateral = q.lateral
	track_s = q.s
	var limit: float = track.wall_offset - stats.radius
	var touching: bool = false
	if absf(lateral) > limit:
		var outward: Vector2 = q.normal * signf(lateral)
		position -= outward * (absf(lateral) - limit)
		var into_wall: float = velocity.dot(outward)
		if into_wall > 0.0:
			touching = true
			var angle: float = rad_to_deg(asin(clampf(into_wall / maxf(velocity.length(), 0.001), 0.0, 1.0)))
			velocity -= outward * into_wall * stats.bump_knockback
			_wall_contact(angle, dt)
	if (touching or _wall_slide_time > 0.0) and _turnback_rate > 0.0 and speed > 0.0:
		# The wall turns the kart back toward the track direction.
		var t: Vector2 = track.tangent_at(q.s)
		var want: float = atan2(-t.x, -t.y)
		var step: float = _turnback_rate * dt
		yaw += clampf(wrapf(want - yaw, -PI, PI), -step, step)
	elif not touching:
		_turnback_rate = 0.0


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
	speed *= 1.0 - stats.wall_friction_drag * mult * dt
	wall_bumped.emit(false)
