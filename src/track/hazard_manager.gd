class_name HazardManager
extends Node
## Evaluates the track's timed moving hazards (TrackData.movers) from the synced race time
## (story 009). Every state is a pure function of the time, so every PC shows the same thing with no
## extra messages; the owner of a kart tests its own kart (victim decides, as for item hits).
## Created and injected by Main like ItemManager; the track tools create one too.
## Implements production/epics/dogworks-racing-kennel-kingdom/story-009-moving-hazards.md.

## A mover entered a new phase (sound and logs). [param position] is where it is (hinge or body).
signal phase_changed(mover_index: int, phase: int, position: Vector3)

## Phases of a scheduled mover.
enum Phase { IDLE, WARNING, RISING, ACTIVE, FALLING }

## Phase names for logs.
const PHASE_NAMES: PackedStringArray = ["idle", "warning", "rising", "active", "falling"]
## Smallest period or span treated as non-zero, not tuning.
const EPSILON: float = 0.0001

## The race time the manager last evaluated (set by [method update]); what a kart is tested at.
var time: float = 0.0
## Debug only (--hazard-time-offset=): seconds added to the race time, to meet a state on demand.
var debug_time_offset: float = 0.0
## Print one "[hazard]" line per race second (netlog runs compare PCs with them).
var log_enabled: bool = false

var _track: TrackModel
var _movers: Array[TrackMover] = []
var _paths: PackedInt32Array = PackedInt32Array()
var _last_phase: PackedInt32Array = PackedInt32Array()
var _last_log_second: int = -1000000
# Karts currently on a gate's deck stretch ((instance id, mover index) -> true), for the span log.
var _in_span: Dictionary = {}


## Builds the manager for [param track]. Call again when the track changes.
func setup(track: TrackModel) -> void:
	_track = track
	_movers.clear()
	_paths = PackedInt32Array()
	_last_phase = PackedInt32Array()
	_last_log_second = -1000000
	for m in track.data.movers:
		var err: String = m.validate()
		if err != "":
			push_warning(err)
		_movers.append(m)
		_paths.append(MAIN_PATH_INDEX if m.path == &"main" else track.branch_index(m.path))
		_last_phase.append(-1)


## TrackModel.MAIN_PATH, named here for the lookup above.
const MAIN_PATH_INDEX: int = TrackModel.MAIN_PATH


## Number of movers.
func count() -> int:
	return _movers.size()


## Mover [param i].
func mover(i: int) -> TrackMover:
	return _movers[i]


## Index of the mover with [param id], or -1.
func index_of(id: StringName) -> int:
	for i in _movers.size():
		if _movers[i].id == id:
			return i
	return -1


## Index of the first gate mover on road [param path_index] (MAIN_PATH or a branch), or -1.
func gate_on_path(path_index: int) -> int:
	for i in _movers.size():
		if _movers[i].kind == &"gate" and _paths[i] == path_index:
			return i
	return -1


## Road index (TrackModel.MAIN_PATH or a branch index) of mover [param i].
func path_index(i: int) -> int:
	return _paths[i]


## Advances the manager to race time [param race_time]: stores it and emits phase changes. Logs
## once per race second when [member log_enabled].
func update(race_time: float) -> void:
	time = race_time + debug_time_offset
	for i in _movers.size():
		var ph: int = phase_at(_movers[i], time)
		if ph != _last_phase[i]:
			if _last_phase[i] >= 0:
				phase_changed.emit(i, ph, anchor_position(i))
			_last_phase[i] = ph
	if log_enabled and race_time >= 0.0:
		var sec: int = floori(race_time)
		if sec != _last_log_second:
			_last_log_second = sec
			for i in _movers.size():
				print(log_line(i, race_time))


## The "[hazard]" log line of mover [param i] at [param race_time] (the same text on every PC).
func log_line(i: int, race_time: float) -> String:
	var m: TrackMover = _movers[i]
	var t: float = race_time + debug_time_offset
	var line: String = "[hazard] t=%.1f mover=%s phase=%s progress=%.2f angle=%.1f blocked=%d" % [race_time, m.id,
			PHASE_NAMES[phase_at(m, t)], progress_at(m, t), angle_deg_at(m, t), 1 if is_active(m, t) else 0]
	if m.is_traveler():
		var p: Vector3 = pose_at(m, t)
		line += " d=%.2f x=%.2f y=%.2f z=%.2f" % [distance_at(m, t), p.x, p.y, p.z]
	return line


## Cycle position of the mover at time [param t] (0 when it has no schedule).
func cycle_pos(m: TrackMover, t: float) -> float:
	if m.period <= EPSILON:
		return 0.0
	return fposmod(t + m.phase, m.period)


## Seconds since the active window started, in [0, period), or -1 when there is no schedule.
func _since_start(m: TrackMover, t: float) -> float:
	if m.period <= EPSILON:
		return -1.0
	return fposmod(cycle_pos(m, t) - m.active_start, m.period)


## Phase of [param m] at time [param t]. A traveler (barrel, cart) is ACTIVE while it rolls from
## path_from to path_to, WARNING for warning_lead before its release and IDLE (hidden) otherwise.
func phase_at(m: TrackMover, t: float) -> int:
	var u: float = _since_start(m, t)
	if u < 0.0:
		return Phase.ACTIVE
	if m.is_traveler():
		if u < m.travel_time():
			return Phase.ACTIVE
		return Phase.WARNING if m.period - u <= m.warning_lead else Phase.IDLE
	if u < m.transition_time:
		return Phase.RISING
	if u < m.active_time:
		return Phase.ACTIVE
	if u < m.active_time + m.transition_time:
		return Phase.FALLING
	if m.period - u <= m.warning_lead:
		return Phase.WARNING
	return Phase.IDLE


## 0 (down, idle) to 1 (fully active), linear in time through the rise and the fall.
func progress_at(m: TrackMover, t: float) -> float:
	var u: float = _since_start(m, t)
	if u < 0.0:
		return 1.0
	if m.is_traveler():
		return 1.0 if u < m.travel_time() or m.period - u <= m.solid_lead else 0.0
	if u < m.transition_time:
		return u / m.transition_time
	if u < m.active_time:
		return 1.0
	if u < m.active_time + m.transition_time:
		return 1.0 - (u - m.active_time) / m.transition_time
	return 0.0


## Deck angle in degrees (0 = lying flat) of a gate at time [param t].
func angle_deg_at(m: TrackMover, t: float) -> float:
	return m.raised_angle_deg * progress_at(m, t)


## True while the mover blocks or hurts: its progress has reached block_progress. A traveler hurts
## while it rolls and for the last solid_lead seconds it waits at the top of its run (before that it
## is rising out of its cellar: seen, not solid).
func is_active(m: TrackMover, t: float) -> bool:
	return progress_at(m, t) >= m.block_progress and (m.period <= EPSILON or progress_at(m, t) > 0.0)


## Start and end (cycle seconds, the end may exceed the period) of the blocked window.
func blocked_window(m: TrackMover) -> Vector2:
	if m.is_traveler():
		return Vector2(m.active_start - m.solid_lead, m.active_start + m.travel_time())
	return Vector2(m.active_start + m.block_progress * m.transition_time,
			m.active_start + m.active_time + (1.0 - m.block_progress) * m.transition_time)


## Share of the time (0..1) the mover is blocking.
func blocked_fraction(m: TrackMover) -> float:
	if m.period <= EPSILON:
		return 1.0
	var w: Vector2 = blocked_window(m)
	return clampf((w.y - w.x) / m.period, 0.0, 1.0)


## True when the mover blocks at any moment of [param t0] .. [param t1] (closed form, no sampling).
func blocked_between(m: TrackMover, t0: float, t1: float) -> bool:
	if m.period <= EPSILON:
		return true
	var w: Vector2 = blocked_window(m)
	var k0: int = floori((t0 + m.phase - w.y) / m.period)
	var k1: int = floori((t1 + m.phase - w.x) / m.period)
	for k in range(k0, k1 + 1):
		var a: float = float(k) * m.period - m.phase + w.x
		var b: float = float(k) * m.period - m.phase + w.y
		if a <= t1 and b >= t0:
			return true
	return false


## True when a kart on road [param path_idx] at [param along] meters is on a gate that blocks at
## time [param t] (the deck is up).
func blocks(path_idx: int, along: float, t: float) -> bool:
	for i in _movers.size():
		var m: TrackMover = _movers[i]
		if m.kind == &"gate" and _paths[i] == path_idx and along >= m.path_from and along <= m.path_to \
				and is_active(m, t):
			return true
	return false


## The "stop" gate (portcullis) that a kart on road [param path_idx] at [param along] meters runs
## into at time [param t], as (mover index, along to push the kart back to, side it stays on: -1
## before the gate, +1 past it), or (-1, 0, 0). [param prev_along] / [param prev_path] are where
## the kart was the tick before (its side of the gate); [param reach] is the kart's radius.
func stop_test(path_idx: int, along: float, prev_path: int, prev_along: float, reach: float, t: float) -> Vector3:
	for i in _movers.size():
		var m: TrackMover = _movers[i]
		if m.kind != &"gate" or m.hit_effect != &"stop" or _paths[i] != path_idx or not is_active(m, t):
			continue
		var line: float = (m.path_from + m.path_to) * 0.5
		var half: float = (m.path_to - m.path_from) * 0.5 + reach
		var side: float = signf(prev_along - line) if prev_path == path_idx else signf(along - line)
		if side == 0.0:
			side = -1.0
		if (along - line) * side < half:
			return Vector3(i, line + side * half, side)
	return Vector3(-1, 0, 0)


## Distance along its road of a traveling mover (barrel, cart) at time [param t]. With a schedule
## it waits at path_from during the warning, rolls from there (at active_start) to path_to and stays
## there (hidden) until the next warning; without one it wraps from path_to back to path_from. Closed form in the time.
func distance_at(m: TrackMover, t: float) -> float:
	var span: float = m.path_to - m.path_from
	if span <= EPSILON:
		return m.path_from
	if m.period <= EPSILON:
		return m.path_from + fposmod(m.speed * (t + m.phase), span)
	var u: float = _since_start(m, t)
	if m.period - u <= m.warning_lead:
		return m.path_from
	return m.path_from + clampf(m.speed * u, 0.0, span)


## Seconds until the mover's next active window starts (0 with no schedule).
func time_to_start(m: TrackMover, t: float) -> float:
	var u: float = _since_start(m, t)
	return 0.0 if u < 0.0 else m.period - u


## World (x, z) position of mover [param m] at time [param t]: its body for a traveler (in its
## lane), the hinge or the middle of the span for a gate.
func position_at(m: TrackMover, t: float) -> Vector2:
	var i: int = _movers.find(m)
	var road: TrackModel.Path = _track.path_of(_paths[i] if i >= 0 else MAIN_PATH_INDEX)
	if m.is_traveler():
		var d: float = distance_at(m, t)
		var tn: Vector2 = road.tangent_at(d)
		return road.point_at(d) + Vector2(-tn.y, tn.x) * m.lane_offset
	return road.point_at(m.path_to if m.kind == &"gate" else m.path_from)


## World position of mover [param m] at time [param t] with its road height under it (a
## traveler's body rests on the road surface in its lane, banks and slopes included).
func pose_at(m: TrackMover, t: float) -> Vector3:
	var i: int = _movers.find(m)
	var road: TrackModel.Path = _track.path_of(_paths[i] if i >= 0 else MAIN_PATH_INDEX)
	var d: float = distance_at(m, t) if m.is_traveler() else (m.path_to if m.kind == &"gate" else m.path_from)
	var st: Vector2 = road.seg_t_at(d)
	var p: Vector2 = position_at(m, t)
	var lat: float = m.lane_offset if m.is_traveler() else 0.0
	return Vector3(p.x, road.surface_y(int(st.x), st.y, lat), p.y)


## 3D anchor of mover [param i] for sounds: the hinge of a gate, the body of a traveler.
func anchor_position(i: int) -> Vector3:
	return pose_at(_movers[i], time)


## Rolling bodies (barrels, carts) on road [param path_idx] that are rolling or waiting at time [param t]
## between [param from_along] and [param to_along] meters: one (along, lane offset, hit radius)
## per body. Bots use it to pick a free lane.
func travelers_between(path_idx: int, from_along: float, to_along: float, t: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in _movers.size():
		var m: TrackMover = _movers[i]
		if not m.is_traveler() or _paths[i] != path_idx:
			continue
		var ph: int = phase_at(m, t)
		if ph != Phase.ACTIVE and ph != Phase.WARNING:
			continue
		var d: float = distance_at(m, t)
		if d >= from_along and d <= to_along:
			out.append(Vector3(d, m.lane_offset, m.hit_radius))
	return out


## The mover that hits [param kart] at time [param t], or -1. Only the owner of a kart calls it
## for that kart. [param q] is the kart's track query (road and distance along it).
func hit_test(kart: KartSim, t: float, q: TrackModel.Query) -> int:
	if log_enabled:
		_log_spans(kart, t, q)
	for i in _movers.size():
		var m: TrackMover = _movers[i]
		if not is_active(m, t):
			continue
		match m.kind:
			&"gate":
				if m.hit_effect != &"stop" and q.path == _paths[i] and q.along >= m.path_from and q.along <= m.path_to:
					return i
			&"burst":
				if m.footprint.size() >= 3 and kart.height >= m.footprint_y_min and kart.height <= m.footprint_y_max \
						and Geometry2D.is_point_in_polygon(kart.position, m.footprint):
					return i
			_:
				if m.is_traveler() and kart.position.distance_to(position_at(m, t)) <= m.hit_radius 						and absf(kart.height - pose_at(m, t).y) <= m.hit_height:
					return i
	return -1


# Debug log: a kart entering or leaving a gate's deck stretch, with the gate state at that moment.
func _log_spans(kart: KartSim, t: float, q: TrackModel.Query) -> void:
	for i in _movers.size():
		var m: TrackMover = _movers[i]
		if m.kind != &"gate":
			continue
		var key := Vector2i(kart.get_instance_id(), i)
		var inside: bool = q.path == _paths[i] and q.along >= m.path_from and q.along <= m.path_to
		if inside != _in_span.has(key):
			if inside:
				_in_span[key] = true
			else:
				_in_span.erase(key)
			print("[hazard] kart_%s mover=%s t=%.2f along=%.1f speed=%.1f phase=%s blocked=%d" % [
					"on" if inside else "off", m.id, t, q.along, kart.speed, PHASE_NAMES[phase_at(m, t)],
					1 if is_active(m, t) else 0])
