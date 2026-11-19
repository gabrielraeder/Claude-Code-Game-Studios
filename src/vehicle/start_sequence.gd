class_name StartSequence
extends RefCounted
## The 3-2-1 countdown and the start boost judgement. Pure logic (no nodes): the owner
## calls update() every physics tick with whether accelerate is held, and applies the
## result to the KartSim when update() returns true (the GO tick).
## Implements story 001 round 2, item 2. All windows and times come from VehicleStats.
##
## Timing: the last accelerate press is measured in seconds before GO. Within the perfect
## window = level 3, good = 2, ok = 1; held from before the ok window = stall (no boost).
## Not holding accelerate at GO = no boost, no stall.

## Seconds until GO. Counts down to 0; stays 0 afterwards.
var time_to_go: float = 0.0
## Seconds since GO; negative while counting down.
var since_go: float = -1.0
## Start boost level 0..3 decided at GO.
var level: int = 0
## True when the player held accelerate too early.
var stalled: bool = false

var _stats: VehicleStats
var _press_offset: float = -1.0
var _prev_held: bool = false


## Starts (or restarts) the countdown.
func begin(stats: VehicleStats) -> void:
	_stats = stats
	time_to_go = stats.start_countdown_time
	since_go = -1.0
	level = 0
	stalled = false
	_press_offset = -1.0
	_prev_held = false


## True until GO has happened.
func is_counting() -> bool:
	return since_go < 0.0


## The number to show (3, 2, 1) while counting, otherwise 0.
func display_number() -> int:
	return ceili(time_to_go) if is_counting() else 0


## Advances by [param dt]. Returns true on the tick GO happens (level and stalled are then set).
func update(dt: float, accelerate_held: bool) -> bool:
	if not is_counting():
		since_go += dt
		return false
	if accelerate_held and not _prev_held:
		_press_offset = time_to_go
	_prev_held = accelerate_held
	time_to_go -= dt
	if time_to_go > 0.0:
		return false
	time_to_go = 0.0
	since_go = 0.0
	if accelerate_held:
		if _press_offset <= _stats.start_perfect_window:
			level = 3
		elif _press_offset <= _stats.start_good_window:
			level = 2
		elif _press_offset <= _stats.start_ok_window:
			level = 1
		else:
			stalled = true
	return true
