class_name HitSlowdownProfile
extends Resource
## One hit-slowdown profile (light / medium / heavy). Used by KartSim.apply_hit_slowdown().
## Numbers follow the user's notes (01-veiculos-e-fisica.md) scaled to a share of top speed.
## Implements story 001 round 2 (wall and hit response as data); applied by items in story 004.

## Seconds the slowdown lasts.
@export var duration: float = 0.3
## Speed floor as a share of max_speed; the slowdown never takes speed below it.
@export_range(0.0, 1.0) var min_speed_frac: float = 0.52
## Deceleration as a share of max_speed lost per second.
@export var decel_frac: float = 0.65
