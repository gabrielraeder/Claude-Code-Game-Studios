class_name VehicleStats
extends Resource
## Handling data for one vehicle type (one .tres per vehicle, see assets/data/vehicles/).
##
## Implements design/game-brief.md, Features item 1 (driving and 3-tier drift boost).
## A new vehicle (for example the war-bike) is a new resource file with different
## numbers; no code change is needed. Defaults here only make a freshly created
## resource usable; the shipped values live in the .tres files.

@export var display_name: String = "Vehicle"

@export_group("Speed")
## Top speed in m/s without a boost.
@export var max_speed: float = 26.0
## Acceleration in m/s^2 while the throttle is held.
@export var accel: float = 14.0
## Braking deceleration in m/s^2 while moving forward.
@export var brake: float = 32.0
## Top reverse speed in m/s (positive number).
@export var reverse_max: float = 8.0
## Deceleration in m/s^2 when neither throttle nor brake is held.
@export var coast_drag: float = 5.0
## Fraction of accel used as reverse acceleration when braking from a stop.
@export var reverse_accel_frac: float = 0.6
## Deceleration in m/s^2 that eases speed back down to the cap when above it.
@export var overspeed_decel: float = 18.0

@export_group("Steering")
## Yaw rate in rad/s at full steer, below the top speed.
@export var turn_rate: float = 2.3
## Speed in m/s at which steering reaches full effect (below it steering is scaled down).
@export var full_steer_speed: float = 6.0
## Fraction of steering lost at top speed (0 = none).
@export var high_speed_steer_damp: float = 0.3
## How fast velocity snaps to the heading while not drifting (1/s).
@export var grip: float = 9.0

@export_group("Drift")
## Grip while drifting (1/s). Lower slides more.
@export var drift_grip: float = 2.2
## Minimum speed in m/s needed to start a drift.
@export var drift_min_speed: float = 12.0
## Steering magnitude (0..1) needed to start a drift.
@export var drift_start_steer: float = 0.3
## The drift ends when speed falls under drift_min_speed times this.
@export var drift_end_speed_frac: float = 0.7
## Yaw rate in rad/s a drift always turns at, in the drift direction.
@export var drift_yaw_base: float = 1.25
## Steering into the turn adds this much yaw rate, steering out removes it.
@export var drift_yaw_range: float = 0.85
## Extra charge speed when steering into the drift (tighter charges faster).
@export var drift_charge_steer_bonus: float = 0.6
## Seconds of (charge) time to reach tier 1, 2 and 3.
@export var drift_tier_times: PackedFloat32Array = PackedFloat32Array([0.9, 1.9, 3.0])
## Boost seconds paid on release; index 0 is "no tier", then tier 1, 2, 3.
@export var drift_boost_times: PackedFloat32Array = PackedFloat32Array([0.0, 0.7, 1.1, 1.6])

@export_group("Boost")
## While boosting the speed cap is max_speed times this.
@export var boost_speed_mult: float = 1.35
## While boosting, acceleration is accel times this.
@export var boost_accel_mult: float = 3.0

@export_group("Collision")
## Seconds the vehicle spins out and cannot be driven after a hit.
@export var spin_time: float = 1.1
## Speed decay rate (1/s) while spinning.
@export var spin_drag: float = 2.5
## Collision radius in meters.
@export var radius: float = 1.0
## Wall bump: the velocity component into the wall is reversed times this (1 = dead stop, 2 = perfect bounce).
@export var bump_knockback: float = 1.4
## Wall impacts faster than this (m/s into the wall) cost speed.
@export var wall_hard_hit_speed: float = 5.0
## Speed multiplier kept after a hard wall impact.
@export var wall_hard_hit_speed_keep: float = 0.7
## Seconds before another hard wall impact can cost speed.
@export var wall_hit_cooldown: float = 0.5
## Speed lost per second (fraction) while scraping a wall.
@export var wall_scrape_drag: float = 0.8

@export_group("Look")
## Body paint color.
@export var paint_color: Color = Color(0.95, 0.2, 0.2)
## Spark colors while drifting: index 0 before tier 1, then tiers 1, 2, 3.
@export var spark_colors: PackedColorArray = PackedColorArray([
	Color(1, 1, 1, 0.6), Color(0.3, 0.7, 1.0), Color(1.0, 0.6, 0.1), Color(0.8, 0.3, 1.0)])
