class_name LapCounter
extends RefCounted
## Counts laps from the kart's distance along the track. Crossing the start line forward
## counts, crossing it backward un-counts, and a lap only counts the first time it is
## reached, so reversing over the line and back is never a lap.
## Implements the story-001 lap rule (design/game-brief.md, Goal and fail state).

## Emitted when lap [param lap] begins (first crossing of the line gives lap 1).
signal lap_started(lap: int)
## Emitted when a lap is completed, with its time in seconds.
signal lap_completed(lap: int, lap_time: float)
## Emitted once when the last lap is completed.
signal finished(total_time: float)

## Laps in the race.
var lap_target: int = 3
## Loop length in meters, used to detect wrap-around.
var track_length: float = 1.0
## Current lap (0 until the line is first crossed).
var lap: int = 0
## Highest lap ever reached; only reaching a new one counts.
var max_lap: int = 0
var lap_times: Array[float] = []
var lap_start_time: float = 0.0
var is_finished: bool = false
## Race clock time (from GO) when the last lap was completed; the finish order uses this.
var finish_race_time: float = 0.0

var _last_s: float = 0.0


func _init(target_laps: int, loop_length: float) -> void:
	lap_target = target_laps
	track_length = loop_length


## Clears all progress; [param start_s] is the kart's distance along the track at the start.
func reset(start_s: float) -> void:
	lap = 0
	max_lap = 0
	lap_times.clear()
	lap_start_time = 0.0
	is_finished = false
	finish_race_time = 0.0
	_last_s = start_s


## Sum of completed lap times.
func total_time() -> float:
	var total: float = 0.0
	for t in lap_times:
		total += t
	return total


## Best completed lap, or -1 if none yet.
func best_lap() -> float:
	var best: float = -1.0
	for t in lap_times:
		if best < 0.0 or t < best:
			best = t
	return best


## Call every tick with the kart's distance along the track and the race clock.
func update(s: float, race_time: float) -> void:
	var ds: float = s - _last_s
	_last_s = s
	if ds < -track_length * 0.5:
		lap += 1
		if lap > max_lap:
			max_lap = lap
			_reached_new_lap(race_time)
	elif ds > track_length * 0.5:
		lap -= 1


func _reached_new_lap(race_time: float) -> void:
	if lap >= 2:
		var t: float = race_time - lap_start_time
		lap_times.append(t)
		lap_completed.emit(lap - 1, t)
	lap_start_time = race_time
	if lap > lap_target:
		is_finished = true
		finish_race_time = race_time
		finished.emit(total_time())
	else:
		lap_started.emit(lap)
