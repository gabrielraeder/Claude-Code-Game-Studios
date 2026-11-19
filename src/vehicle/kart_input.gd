class_name KartInput
extends RefCounted
## One tick of driver intent for a kart. Written by a KartDriver (player, autopilot,
## later a bot or network replay), read by KartSim. Holds no logic.
## Implements design/game-brief.md, Features item 1 and Controls.

## Throttle, 0..1.
var throttle: float = 0.0
## Brake / reverse, 0..1.
var brake: float = 0.0
## Steering, -1..1. Positive = left.
var steer: float = 0.0
## Drift button held.
var drift: bool = false
## Item button held (read by the item system in story 004; unused here).
var item: bool = false


## Resets every field to "no input".
func clear() -> void:
	throttle = 0.0
	brake = 0.0
	steer = 0.0
	drift = false
	item = false
