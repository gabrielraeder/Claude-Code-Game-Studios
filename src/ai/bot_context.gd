class_name BotContext
extends RefCounted
## What a bot may ask about the rest of the race (story 005). Injected by Main as callables so
## the bot code needs no autoloads and no node paths.

## () -> Array of Racer: every racer, the bot's own included.
var racers_fn: Callable
## (kart_id: int) -> float: race progress in meters (laps * length + s); finished karts are huge.
var progress_fn: Callable
## (kart_id: int) -> int: shown place, 1 = first.
var place_fn: Callable
## (kart_id: int) -> StringName: id of the item the kart holds ("" = none).
var held_fn: Callable
## (kart_id: int) -> float: distance in meters to the nearest hostile item coming for the kart.
var threat_fn: Callable
## () -> float: the race time the timed hazards are evaluated at (story 009).
var time_fn: Callable
## (road_id: StringName, from_t: float, to_t: float) -> bool: true when the timed gate on that
## branch (the drawbridge) is blocked at any moment of the time range.
var gate_blocked_fn: Callable
