class_name VehicleVisualStats
extends Resource
## Presentation numbers for one vehicle type: KartVisual look and animation, plus the
## chase camera. Lives inside VehicleStats (the .tres of the vehicle). Defaults match the
## first-round look; the shipped values are in assets/data/vehicles/.
## Implements story 001 round 2 (visual constants to data).

@export_group("Drift pose")
## Seconds the drift hop lasts (from the user's notes: drift entry time).
@export var hop_duration: float = 0.4
## Peak height of the drift hop in meters.
@export var hop_height: float = 0.35
## Body yaw against the path while drifting, in degrees, when steering out of the turn.
@export var drift_body_yaw_min_deg: float = 25.0
## Body yaw while drifting with neutral steering, in degrees.
@export var drift_body_yaw_default_deg: float = 45.0
## Body yaw while drifting with full steering into the turn, in degrees.
@export var drift_body_yaw_max_deg: float = 55.0
## Rate (1/s) at which the body pose follows its target.
@export var tilt_smoothing: float = 10.0
## Spin-out turn speed in rad/s.
@export var spin_speed: float = 14.0

@export_group("Body lean")
## Longitudinal acceleration (m/s^2) that gives the full pitch (notes: weight transfer 20).
@export var lean_long_norm: float = 20.0
## Lateral acceleration (m/s^2) that gives the full roll (notes: weight transfer 30).
@export var lean_lat_norm: float = 30.0
## Pitch at full longitudinal acceleration, in degrees.
@export var lean_pitch_max_deg: float = 4.0
## Roll at full lateral acceleration, in degrees.
@export var lean_roll_max_deg: float = 6.0

@export_group("Model")
## Wheel radius in meters (from the notes).
@export var wheel_radius: float = 0.35
## Wheel width in meters.
@export var wheel_width: float = 0.3
## Wheel center offsets: x sideways, z front (negative) and rear (positive).
@export var wheel_offset_x: float = 0.75
@export var wheel_front_z: float = -0.7
@export var wheel_rear_z: float = 0.75
## Dark parts color (wheels, wing) and driver skin color.
@export var dark_color: Color = Color(0.12, 0.12, 0.14)
@export var skin_color: Color = Color(0.95, 0.85, 0.7)

@export_group("Sparks and flame")
## Spark sphere radius and position (x is mirrored left/right).
@export var spark_radius: float = 0.14
@export var spark_offset: Vector3 = Vector3(0.75, 0.25, 1.1)
## Spark pulse speed (rad/s), pulse amount, and extra size per drift tier.
@export var spark_pulse_rate: float = 30.0
@export var spark_pulse_amount: float = 0.2
@export var spark_tier_growth: float = 0.2
## Boost flame cone size, color and position.
@export var flame_radius: float = 0.35
@export var flame_length: float = 1.4
@export var flame_color: Color = Color(1.0, 0.55, 0.1)
@export var flame_position: Vector3 = Vector3(0, 0.5, 1.7)
## Flame flicker speed (rad/s) and amount.
@export var flame_pulse_rate: float = 50.0
@export var flame_pulse_amount: float = 0.3

@export_group("Chase camera")
## Meters behind the kart.
@export var camera_distance: float = 6.0
## Camera height in meters.
@export var camera_height: float = 2.7
## Meters ahead of the kart the camera looks at.
@export var camera_look_ahead: float = 4.0
## Height of the look-at point.
@export var camera_look_height: float = 1.0
## Position smoothing rate (1/s).
@export var camera_position_smoothing: float = 11.0
## FOV at standstill, degrees.
@export var camera_base_fov: float = 68.0
## Extra FOV at top speed, degrees.
@export var camera_speed_fov_gain: float = 10.0
## Extra FOV while boosting, degrees.
@export var camera_boost_fov_gain: float = 6.0
## FOV smoothing rate (1/s).
@export var camera_fov_smoothing: float = 5.0
