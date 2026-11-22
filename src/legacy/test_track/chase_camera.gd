class_name ChaseCamera
extends Camera3D
## Third-person camera that follows a KartSim from behind, with speed and boost FOV.
## Presentation only. All numbers come from the followed kart's VehicleStats.visual
## (camera_* fields). Implements design/game-brief.md, "Look and references".

## On narrow roads (the secret passage, the plank bridge) the camera rises above the walls
## (the passage walls are 1.3 m) and follows the road from behind, looking down into the
## corridor, so a wall can never hide the kart. Blended in over TIGHT_BLEND_RATE.
const NARROW_HALF_WIDTH: float = 3.0
const TIGHT_DISTANCE: float = 5.0
const TIGHT_HEIGHT: float = 4.2
const TIGHT_BLEND_RATE: float = 4.0
## The camera stays this far inside the road corridors (meters), so it never sits in a wall.
const WALL_MARGIN: float = 0.6
## On a narrow branch the camera looks at this point ahead of the kart along the road.
const ROAD_LOOK_AHEAD: float = 1.5
## Points tested along the line from the kart to the camera for a wall in between.
const SIGHT_SAMPLES: int = 10

## Track used to keep the camera inside the road corridors (walls have no collision, so
## without this the camera ends up behind a wall in tight bends). Optional.
var track: TrackModel

var _target: KartSim
var _tight: float = 0.0
var _vs: VehicleVisualStats
var _smoothed_position: Vector3 = Vector3.ZERO
# Current camera roll in radians (follows the road bank a little).
var _roll: float = 0.0
# Story 008 part 3: smoothed camera height limits from the surface (floor) and a deck above
# (ceiling); NAN until first set.
var _floor_y: float = NAN
var _ceil_y: float = NAN
## Debug counters (story 008 part 3, read by DebugHarness): lowest height of the follow position
## above the surface under it before the clamp, frames the floor or the ceiling moved it, and the
## lowest final height above the surface.
var debug_min_raw_clearance: float = INF
var debug_min_clearance: float = INF
var debug_floor_frames: int = 0
var debug_ceiling_frames: int = 0


## Sets the kart to follow and snaps the camera behind it.
func follow(target: KartSim) -> void:
	_target = target
	_vs = target.stats.visual
	snap()


## Jumps straight to the follow position (use after a restart).
func snap() -> void:
	if _target == null:
		return
	_smoothed_position = _desired_position(_target.position, _target.forward(), _target.height)
	_floor_y = NAN
	_ceil_y = NAN
	_clamp_height(_target.height, 0.0)
	fov = _vs.camera_base_fov
	_roll = _bank_roll_target()
	_apply(_target.position, _target.forward(), _target.height)


func _process(delta: float) -> void:
	if _target == null:
		return
	var fraction: float = Engine.get_physics_interpolation_fraction()
	var pos: Vector2 = _target.interpolated_position(fraction)
	var yaw: float = _target.interpolated_yaw(fraction)
	var height: float = _target.interpolated_height(fraction)
	var fwd: Vector2 = Vector2(-sin(yaw), -cos(yaw))
	var narrow: bool = _target.road_half_width > 0.0 and _target.road_half_width < NARROW_HALF_WIDTH
	_tight = move_toward(_tight, 1.0 if narrow else 0.0, TIGHT_BLEND_RATE * delta)
	_smoothed_position = _smoothed_position.lerp(_desired_position(pos, fwd, height),
			1.0 - exp(-_vs.camera_position_smoothing * delta))
	_keep_inside_corridor(pos)
	_clamp_height(height, delta)
	_roll = lerpf(_roll, _bank_roll_target(), 1.0 - exp(-_vs.camera_bank_roll_smoothing * delta))
	_apply(pos, fwd, height)
	var speed_frac: float = clampf(_target.speed / _target.stats.max_speed, 0.0, 1.4)
	var target_fov: float = _vs.camera_base_fov + _vs.camera_speed_fov_gain * speed_frac \
			+ (_vs.camera_boost_fov_gain if _target.boost_time > 0.0 else 0.0)
	fov = lerpf(fov, target_fov, 1.0 - exp(-_vs.camera_fov_smoothing * delta))


# Camera roll that follows the road bank under the kart: a share of the bank, capped.
func _bank_roll_target() -> float:
	var cap: float = deg_to_rad(_vs.camera_bank_roll_max_deg)
	return clampf(_target.surface_bank * _vs.camera_bank_roll_factor, -cap, cap)


func _desired_position(pos: Vector2, fwd: Vector2, kart_height: float) -> Vector3:
	var p: Vector2 = pos - fwd * lerpf(_vs.camera_distance, TIGHT_DISTANCE, _tight)
	if _on_narrow_branch():
		# Follow the road, not the kart's heading: a point on the corridor's centerline behind
		# the kart stays inside the corridor even right after a 90-degree bend.
		var along: float = track.branch_along(_target.track_path, pos)
		p = p.lerp(track.branch_point_at(_target.track_path, along - TIGHT_DISTANCE), _tight)
	return Vector3(p.x, kart_height + lerpf(_vs.camera_height, TIGHT_HEIGHT, _tight), p.y)


func _on_narrow_branch() -> bool:
	return track != null and _target.track_path >= 0 and _tight > 0.0


# Pulls the camera in toward the kart until the line from the kart to the camera stays
# inside the road corridors (no wall between them, and the camera not inside a wall).
func _keep_inside_corridor(kart: Vector2) -> void:
	if track == null or (_on_narrow_branch() and _tight > 0.5):
		return  # above the corridor walls: nothing to avoid
	var cam: Vector2 = Vector2(_smoothed_position.x, _smoothed_position.z)
	var safe: float = 1.0
	for i in range(1, SIGHT_SAMPLES + 1):
		var t: float = float(i) / SIGHT_SAMPLES
		if _excess(kart.lerp(cam, t)) > -WALL_MARGIN:
			safe = float(i - 1) / SIGHT_SAMPLES
			break
	if safe < 1.0:
		var p: Vector2 = kart.lerp(cam, safe)
		_smoothed_position = Vector3(p.x, _smoothed_position.y, p.y)


# Story 008 part 3: keeps the camera above the road or ground under it (camera_min_clearance) and
# under the deck of a road passing over it (camera_ceiling_margin below its underside), so it
# never goes under a road that climbs behind the kart nor into a bridge at a crossover. The limits
# ease in at camera_clamp_smoothing; the surface itself is a hard floor at once. Kept clear of a
# ceiling first only when both cannot hold (the floor wins: never under the road).
func _clamp_height(kart_height: float, delta: float) -> void:
	if track == null:
		return
	var cam: Vector2 = Vector2(_smoothed_position.x, _smoothed_position.z)
	var surface: float = track.floor_under(cam, kart_height)
	var floor_target: float = surface + _vs.camera_min_clearance
	var ceil_target: float = track.deck_above(cam, kart_height, WALL_MARGIN) - _vs.camera_ceiling_margin
	var k: float = 1.0 if delta <= 0.0 else 1.0 - exp(-_vs.camera_clamp_smoothing * delta)
	_floor_y = floor_target if is_nan(_floor_y) else lerpf(_floor_y, floor_target, k)
	if is_inf(ceil_target):
		_ceil_y = INF
	elif is_nan(_ceil_y) or is_inf(_ceil_y):
		_ceil_y = maxf(ceil_target, _smoothed_position.y) if delta > 0.0 else ceil_target
	else:
		_ceil_y = lerpf(_ceil_y, ceil_target, k)
	var y: float = _smoothed_position.y
	debug_min_raw_clearance = minf(debug_min_raw_clearance, y - surface)
	if y > _ceil_y:
		y = _ceil_y
		debug_ceiling_frames += 1
	if y < _floor_y:
		y = _floor_y
		debug_floor_frames += 1
	y = maxf(y, surface + 0.3)
	debug_min_clearance = minf(debug_min_clearance, y - surface)
	_smoothed_position.y = y


# On a branch (the passage, the bridge, a lane) only that road counts, so the camera never
# looks through the wall between two roads; on the main road any road corridor counts.
func _excess(p: Vector2) -> float:
	if _target.track_path >= 0:
		return track.excess_on_path(p, _target.track_path)
	return track.excess_at(p)


func _apply(pos: Vector2, fwd: Vector2, kart_height: float) -> void:
	position = _smoothed_position
	var look: Vector2 = pos + fwd * _vs.camera_look_ahead
	if _on_narrow_branch():
		var along: float = track.branch_along(_target.track_path, pos)
		look = look.lerp(track.branch_point_at(_target.track_path, along + ROAD_LOOK_AHEAD), _tight)
	look_at(Vector3(look.x, kart_height + _vs.camera_look_height, look.y), Vector3.UP)
	rotate_object_local(Vector3(0, 0, 1), _roll)
