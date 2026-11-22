class_name LapCounter
extends RefCounted
## Counts laps from the kart's distance along the track. Crossing the start line forward
## counts, crossing it backward un-counts, and a lap only counts the first time it is
## reached, so reversing over the line and back is never a lap. With checkpoints, a forward
## crossing of the line counts only when every checkpoint was passed in order since the
## last crossing (shortcut branches map onto the main s range, so s sweeps through the
## checkpoints they cover).
## Implements the story-001 lap rule and story 003 checkpoint integrity.

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
## Forward crossings of the line that were refused because a checkpoint was missing.
var rejected_crossings: int = 0

var _last_s: float = 0.0
var _checkpoints: PackedFloat32Array = PackedFloat32Array()
var _cp_next: int = 0
var _invalid_wraps: int = 0


func _init(target_laps: int, loop_length: float, checkpoint_s: PackedFloat32Array = PackedFloat32Array()) -> void:
	lap_target = target_laps
	track_length = loop_length
	_checkpoints = checkpoint_s


## Switches to another track: new loop length and checkpoint distances (all interior
## checkpoints, ascending, not including the line itself). Call reset() afterwards.
func configure_track(loop_length: float, checkpoint_s: PackedFloat32Array) -> void:
	track_length = loop_length
	_checkpoints = checkpoint_s


## Clears all progress; [param start_s] is the kart's distance along the track at the start.
func reset(start_s: float) -> void:
	lap = 0
	max_lap = 0
	lap_times.clear()
	lap_start_time = 0.0
	is_finished = false
	finish_race_time = 0.0
	rejected_crossings = 0
	_invalid_wraps = 0
	_last_s = start_s
	_cp_next = 0
	while _cp_next < _checkpoints.size() and _checkpoints[_cp_next] <= start_s:
		_cp_next += 1


## Sets the position without counting anything (used after a teleport). The checkpoint
## state is kept, so a kart placed past a checkpoint it never passed still has to pass it.
func resync(s: float) -> void:
	_last_s = s


## Checkpoints passed since the last line crossing.
func checkpoints_passed() -> int:
	return _cp_next


## Number of interior checkpoints.
func checkpoint_total() -> int:
	return _checkpoints.size()


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
	var prev: float = _last_s
	var ds: float = s - prev
	_last_s = s
	if ds < -track_length * 0.5:
		# Forward across the line.
		if _cp_next >= _checkpoints.size():
			lap += 1
			if lap > max_lap:
				max_lap = lap
				_reached_new_lap(race_time)
		else:
			rejected_crossings += 1
			_invalid_wraps += 1
		_cp_next = 0
		_pass_forward(0.0, s)
	elif ds > track_length * 0.5:
		# Backward across the line.
		if _invalid_wraps > 0:
			_invalid_wraps -= 1
		else:
			lap -= 1
		_cp_next = _checkpoints.size()
		_pass_backward(track_length, s)
	elif ds > 0.0:
		_pass_forward(prev, s)
	elif ds < 0.0:
		_pass_backward(prev, s)


func _pass_forward(from_s: float, to_s: float) -> void:
	while _cp_next < _checkpoints.size() and from_s < _checkpoints[_cp_next] and to_s >= _checkpoints[_cp_next]:
		_cp_next += 1


func _pass_backward(from_s: float, to_s: float) -> void:
	while _cp_next > 0 and from_s >= _checkpoints[_cp_next - 1] and to_s < _checkpoints[_cp_next - 1]:
		_cp_next -= 1


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
