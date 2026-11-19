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

@export_group("Start")
## Seconds of the 3-2-1 countdown before GO.
@export var start_countdown_time: float = 3.0
## Accelerate last pressed this many seconds or less before GO = perfect start (level 3).
@export var start_perfect_window: float = 0.15
## ... good start (level 2).
@export var start_good_window: float = 0.35
## ... ok start (level 1). Pressed (and held) earlier than this = stall.
@export var start_ok_window: float = 0.6
## Seconds the throttle is dead after a too-early start.
@export var start_stall_time: float = 1.0
## Start boost seconds by level; index 0 is "no boost", then levels 1, 2, 3.
@export var start_boost_times: PackedFloat32Array = PackedFloat32Array([0.0, 1.4, 1.7, 2.0])
## Seconds the GO! and start result messages stay on screen.
@export var start_message_time: float = 1.5

@export_group("Collision")
## Seconds the vehicle spins out and cannot be driven after a hit.
@export var spin_time: float = 1.1
## Speed decay rate (1/s) while spinning.
@export var spin_drag: float = 2.5
## Collision radius in meters.
@export var radius: float = 1.0
## Wall knock-back: the velocity component into the wall is reversed times this (1 = dead stop, 2 = perfect bounce).
@export var bump_knockback: float = 1.4
## Kart body for kart-to-kart contact: a capsule along the heading. Half the distance
## between its two end-circle centers, in meters (body length = 2 * (half_length + radius)).
@export var bump_half_length: float = 0.5
## Radius of the body capsule, in meters (body width = 2 * radius).
@export var bump_radius: float = 0.85
## Kart-to-kart push strength (the user's notes, weight classes: light 0.5, medium 1.0,
## heavy 1.5). When two karts overlap, each is pushed out in proportion to the OTHER's push.
@export var bump_push_mult: float = 1.5
## Fraction of speed lost in a full-strength kart bump (notes: light 0.9, medium 0.5, heavy 0.1).
@export var bump_speed_loss: float = 0.1
## Closing speed (m/s) at which a kart bump costs the full bump_speed_loss; slower bumps cost less.
@export var bump_full_impact_speed: float = 10.0
## Bounciness of kart bumps: 0 = karts just stop closing, 1 = they bounce apart fully.
@export var bump_restitution: float = 0.4
## How fast a bump knock fades (1/s). Knock distance is about impulse / decay.
@export var bump_knock_decay: float = 6.0
## Seconds before another kart bump can cost speed again.
@export var bump_cooldown: float = 0.3
## Seconds before another wall impact can cost speed.
@export var wall_hit_cooldown: float = 0.5
## Speed lost per second (fraction) while touching a wall, before the scrape multiplier.
@export var wall_friction_drag: float = 0.8
## Angle of incidence (degrees, 0 = parallel to the wall) range of a scrape.
@export var wall_scrape_min_angle: float = 10.0
@export var wall_scrape_max_angle: float = 40.0
## Wall friction multiplier while scraping.
@export var wall_scrape_friction_mult: float = 0.45
## From this angle up a contact is an impact; below it (and above the scrape minimum) a scrape.
## The scrape multiplier fades back to 1 between this angle and wall_scrape_max_angle.
@export var wall_impact_threshold_angle: float = 25.0
## Impact angle range (degrees); the speed loss scales from 0 at the min to the max loss at the max.
@export var wall_impact_min_angle: float = 15.0
@export var wall_impact_max_angle: float = 85.0
## Largest share of speed an impact removes (at wall_impact_max_angle).
@export var wall_impact_max_speed_loss: float = 0.6
## Seconds the kart slides (low grip) after an impact.
@export var wall_impact_slide_time: float = 0.25
## Grip (1/s) during that slide.
@export var wall_slide_grip: float = 2.2
## The wall turns the kart back toward the track at this rate range (degrees/s), by angle.
@export var wall_turnback_min_rate: float = 30.0
@export var wall_turnback_max_rate: float = 90.0
## Light / medium / heavy hit-slowdown profiles (index 0, 1, 2).
@export var hit_slowdown_profiles: Array[HitSlowdownProfile] = []
## Seconds of immunity after a hit (applied by the item system in story 004).
@export var hit_immunity_time: float = 0.6

@export_group("Look")
## Body paint color.
@export var paint_color: Color = Color(0.95, 0.2, 0.2)
## Spark colors while drifting: index 0 before tier 1, then tiers 1, 2, 3.
@export var spark_colors: PackedColorArray = PackedColorArray([
	Color(1, 1, 1, 0.6), Color(0.3, 0.7, 1.0), Color(1.0, 0.6, 0.1), Color(0.8, 0.3, 1.0)])

@export_group("Visual")
## Presentation numbers (model, drift pose, lean, flame, sparks, chase camera).
@export var visual: VehicleVisualStats = VehicleVisualStats.new()
