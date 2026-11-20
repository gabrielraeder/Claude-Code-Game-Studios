class_name RaceRanking
extends RefCounted
## Shown race order with debounce. Callers pass a "how far ahead" key per kart each tick
## (progress projected to now; finished karts get a huge key so they sit at the front).
## A kart passes the one in front only after being ahead of it continuously for the debounce
## time, so shown places do not flicker when karts run side by side. Pure logic.

## Finished karts get a key of FINISHED_BASE minus their finish time.
const FINISHED_BASE: float = 1.0e6
## Keys at or above this belong to finished karts: they swap at once, with no debounce
## and no pass margin (finish times decide the order exactly).
const FINISHED_MIN: float = FINISHED_BASE * 0.5

## The first place changed.
signal lead_changed(new_leader: int, old_leader: int)

var _order: Array[int] = []
var _timers: Dictionary = {}
var _debounce: float = 0.5
var _pass_margin: float = 0.0


## [param debounce_seconds]: how long a kart must stay ahead before a swap.
## [param pass_margin]: how far ahead (in key units, meters) it must be during that time.
func _init(debounce_seconds: float, pass_margin: float = 0.0) -> void:
	_debounce = debounce_seconds
	_pass_margin = pass_margin


## Starts a race with [param ids] in the given order.
func reset(ids: Array[int]) -> void:
	_order = ids.duplicate()
	_timers.clear()


## Removes a kart (it left the race).
func remove(id: int) -> void:
	_order.erase(id)
	_timers.erase(id)


## Current leader, or -1.
func leader() -> int:
	return _order[0] if not _order.is_empty() else -1


## 1-based shown place of [param id], 0 if unknown.
func place_of(id: int) -> int:
	return _order.find(id) + 1


## Kart id at 1-based shown [param place], or -1 when there is none.
func id_at_place(place: int) -> int:
	return _order[place - 1] if place >= 1 and place <= _order.size() else -1


## Number of ranked karts.
func count() -> int:
	return _order.size()


## Advances the debounce timers by [param dt]; [param keys] maps kart id to its key.
func update(dt: float, keys: Dictionary) -> void:
	var old_leader: int = leader()
	var i: int = 0
	while i < _order.size() - 1:
		var a: int = _order[i]
		var b: int = _order[i + 1]
		var ka: float = float(keys.get(a, 0.0))
		var kb: float = float(keys.get(b, 0.0))
		var b_finished: bool = kb >= FINISHED_MIN
		if (b_finished and kb > ka) or kb > ka + _pass_margin:
			var t: float = float(_timers.get(b, 0.0)) + dt
			if t >= _debounce or b_finished:
				_order[i] = b
				_order[i + 1] = a
				_timers[b] = 0.0
				_timers[a] = 0.0
				i += 1
			else:
				_timers[b] = t
		else:
			_timers[b] = 0.0
		i += 1
	var new_leader: int = leader()
	if new_leader != old_leader and old_leader != -1:
		lead_changed.emit(new_leader, old_leader)
