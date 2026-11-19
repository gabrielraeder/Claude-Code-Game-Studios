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

## Distance along the centerline, from the last track query.
var track_s: float = 0.0
## Signed lateral offset from the centerline (left positive).
var lateral: float = 0.0

var _prev_position: Vector2 = Vector2.ZERO
var _prev_yaw: float = 0.0
var _segment_hint: int = -1
var _wall_cooldown: float = 0.0


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


## Spins the kart out (used by items in story 004). Returns false if already spinning.
func hit() -> bool:
	if spin_time > 0.0:
		return false
	spin_time = stats.spin_time
	_end_drift(false)
	boost_time = 0.0
	return true


## Advances the simulation by [param dt] seconds using [param input] on [param track].
func tick(dt: float, input: KartInput, track: TrackModel) -> void:
	_prev_position = position
	_prev_yaw = yaw
	var control: bool = can_drive()
	var steer: float = input.steer if control else 0.0
	var throttle: float = input.throttle if control else 0.0
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

	var grip: float = stats.drift_grip if drifting else stats.grip
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
	if absf(lateral) > limit:
		var outward: Vector2 = q.normal * signf(lateral)
		position -= outward * (absf(lateral) - limit)
		var into_wall: float = velocity.dot(outward)
		if into_wall > 0.0:
			velocity -= outward * into_wall * stats.bump_knockback
			if into_wall > stats.wall_hard_hit_speed and _wall_cooldown <= 0.0:
				speed *= stats.wall_hard_hit_speed_keep
				_wall_cooldown = stats.wall_hit_cooldown
				wall_bumped.emit(true)
			else:
				speed *= 1.0 - stats.wall_scrape_drag * dt
				wall_bumped.emit(false)
