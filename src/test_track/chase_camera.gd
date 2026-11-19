class_name ChaseCamera
extends Camera3D
## Third-person camera that follows a KartSim from behind, with speed and boost FOV.
## Presentation only. Implements design/game-brief.md, "Look and references".

## Meters behind the kart.
@export var follow_distance: float = 6.0
## Camera height in meters.
@export var follow_height: float = 2.7
## Meters ahead of the kart the camera looks at.
@export var look_ahead: float = 4.0
## Height of the look-at point.
@export var look_height: float = 1.0
## Position smoothing rate (1/s).
@export var position_smoothing: float = 11.0
## FOV at standstill, degrees.
@export var base_fov: float = 68.0
## Extra FOV at top speed.
@export var speed_fov_gain: float = 10.0
## Extra FOV while boosting.
@export var boost_fov_gain: float = 6.0
## FOV smoothing rate (1/s).
@export var fov_smoothing: float = 5.0

var _target: KartSim
var _smoothed_position: Vector3 = Vector3.ZERO


## Sets the kart to follow and snaps the camera behind it.
func follow(target: KartSim) -> void:
	_target = target
	snap()


## Jumps straight to the follow position (use after a restart).
func snap() -> void:
	if _target == null:
		return
	_smoothed_position = _desired_position(_target.position, _target.forward())
	fov = base_fov
	_apply(_target.position, _target.forward())


func _process(delta: float) -> void:
	if _target == null:
		return
	var fraction: float = Engine.get_physics_interpolation_fraction()
	var pos: Vector2 = _target.interpolated_position(fraction)
	var yaw: float = _target.interpolated_yaw(fraction)
	var fwd: Vector2 = Vector2(-sin(yaw), -cos(yaw))
	_smoothed_position = _smoothed_position.lerp(_desired_position(pos, fwd),
			1.0 - exp(-position_smoothing * delta))
	_apply(pos, fwd)
	var speed_frac: float = clampf(_target.speed / _target.stats.max_speed, 0.0, 1.4)
	var target_fov: float = base_fov + speed_fov_gain * speed_frac \
			+ (boost_fov_gain if _target.boost_time > 0.0 else 0.0)
	fov = lerpf(fov, target_fov, 1.0 - exp(-fov_smoothing * delta))


func _desired_position(pos: Vector2, fwd: Vector2) -> Vector3:
	var p: Vector2 = pos - fwd * follow_distance
	return Vector3(p.x, follow_height, p.y)


func _apply(pos: Vector2, fwd: Vector2) -> void:
	position = _smoothed_position
	var look: Vector2 = pos + fwd * look_ahead
	look_at(Vector3(look.x, look_height, look.y), Vector3.UP)
