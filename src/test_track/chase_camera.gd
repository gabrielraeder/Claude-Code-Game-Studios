class_name ChaseCamera
extends Camera3D
## Third-person camera that follows a KartSim from behind, with speed and boost FOV.
## Presentation only. All numbers come from the followed kart's VehicleStats.visual
## (camera_* fields). Implements design/game-brief.md, "Look and references".

var _target: KartSim
var _vs: VehicleVisualStats
var _smoothed_position: Vector3 = Vector3.ZERO


## Sets the kart to follow and snaps the camera behind it.
func follow(target: KartSim) -> void:
	_target = target
	_vs = target.stats.visual
	snap()


## Jumps straight to the follow position (use after a restart).
func snap() -> void:
	if _target == null:
		return
	_smoothed_position = _desired_position(_target.position, _target.forward())
	fov = _vs.camera_base_fov
	_apply(_target.position, _target.forward())


func _process(delta: float) -> void:
	if _target == null:
		return
	var fraction: float = Engine.get_physics_interpolation_fraction()
	var pos: Vector2 = _target.interpolated_position(fraction)
	var yaw: float = _target.interpolated_yaw(fraction)
	var fwd: Vector2 = Vector2(-sin(yaw), -cos(yaw))
	_smoothed_position = _smoothed_position.lerp(_desired_position(pos, fwd),
			1.0 - exp(-_vs.camera_position_smoothing * delta))
	_apply(pos, fwd)
	var speed_frac: float = clampf(_target.speed / _target.stats.max_speed, 0.0, 1.4)
	var target_fov: float = _vs.camera_base_fov + _vs.camera_speed_fov_gain * speed_frac \
			+ (_vs.camera_boost_fov_gain if _target.boost_time > 0.0 else 0.0)
	fov = lerpf(fov, target_fov, 1.0 - exp(-_vs.camera_fov_smoothing * delta))


func _desired_position(pos: Vector2, fwd: Vector2) -> Vector3:
	var p: Vector2 = pos - fwd * _vs.camera_distance
	return Vector3(p.x, _vs.camera_height, p.y)


func _apply(pos: Vector2, fwd: Vector2) -> void:
	position = _smoothed_position
	var look: Vector2 = pos + fwd * _vs.camera_look_ahead
	look_at(Vector3(look.x, _vs.camera_look_height, look.y), Vector3.UP)
