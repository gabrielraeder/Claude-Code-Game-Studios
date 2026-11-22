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

@export_group("Model (story 006)")
## glb of the vehicle (root "Vehicle", children "Seat" and "PennantMount", wheels named
## Wheel_FL/FR/RL/RR or Wheel_F/Wheel_R). Empty or missing = the box-and-sphere placeholder.
@export var model_path: String = ""
## Added to the Seat node position (meters): nudges the dog up, down or back.
@export var seat_offset: Vector3 = Vector3.ZERO
## Uniform scale of the dog model on this vehicle.
@export var dog_scale: float = 1.0
## Rider pitch in degrees (positive leans forward, over the handlebars).
@export var rider_pitch_deg: float = 0.0
## Extra rider roll into a turn at full lateral acceleration, in degrees (on top of the body lean).
@export var rider_lean_deg: float = 4.0
## Pennant pole length = this times the height of vehicle and rider (so it is always tallest).
@export var pennant_height_mult: float = 1.2
## Pennant pole base when the model has no "PennantMount" (and in the placeholder body).
@export var pennant_mount_fallback: Vector3 = Vector3(0, 0.75, 1.0)
## Degrees the front wheel(s) turn at full steer (looks only).
@export var front_steer_deg: float = 14.0
## Dog head bob: height in meters, rate in rad/s (scaled by speed).
@export var head_bob_amount: float = 0.025
@export var head_bob_rate: float = 16.0
## Ears stream back this many degrees while boosting.
@export var ear_boost_deg: float = 28.0
## Ears flop this many degrees (back and forth) during a spin-out, at ear_flop_rate rad/s.
@export var ear_spin_flop_deg: float = 35.0
@export var ear_flop_rate: float = 24.0
## Rate (1/s) the ears follow their target.
@export var ear_smoothing: float = 12.0
## Model nodes that cast no shadow (small parts: the shadow pass draws every part again).
@export var no_shadow_parts: PackedStringArray = PackedStringArray(["Ear_L", "Ear_R", "Tail", "Handlebar", "Prow"])

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

@export_group("Surface (story 008)")
## Rate (1/s) at which the kart's pitch and roll follow the road surface normal.
@export var surface_tilt_smoothing: float = 14.0
## Share of the road's bank angle the chase camera rolls by (0 = no roll).
@export var camera_bank_roll_factor: float = 0.3
## Largest camera roll in degrees.
@export var camera_bank_roll_max_deg: float = 4.0
## Rate (1/s) at which the camera roll follows its target.
@export var camera_bank_roll_smoothing: float = 4.0
## Story 008 part 3: the chase camera stays at least this many meters above the road (or ground)
## under it, so it never dips under a road that climbs behind the kart.
@export var camera_min_clearance: float = 1.2
## ... and this many meters below the underside of a road deck above it (a bridge over the kart).
@export var camera_ceiling_margin: float = 0.5
## Rate (1/s) at which the camera eases onto those limits (a hard floor still applies at once).
@export var camera_clamp_smoothing: float = 10.0

@export_group("Air (story 008)")
## Landing squash: the body is flattened by up to this share of its height (0.25 = 25 %) ...
@export var land_squash_amount: float = 0.22
## ... at this landing speed (m/s, vertical, relative to the surface) or more; softer landings squash less.
@export var land_squash_full_speed: float = 8.0
## Seconds the squash takes to spring back.
@export var land_squash_time: float = 0.28
## Remote karts (no local landing event): a landing is seen when the vertical speed from the wire
## jumps up by more than this (m/s) from a fall faster than it.
@export var land_detect_speed: float = 2.0
