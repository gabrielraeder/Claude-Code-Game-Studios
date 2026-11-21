extends SceneTree
## DEBUG TOOL (story 008 part 5). Runs the real ItemManager headless with real KartSims on a track
## whose main loop crosses itself (Castle Circuit's Barbican Spiral over the gate arch) and logs
## every item hit, to show that items act only on their own level:
##   spill_deck_kart_below   a spill lying on the gatehouse deck right over the gate road; a kart
##                           drives under it through the gate (expected: no hit)
##   spill_deck_kart_on_deck the same spill; a kart drives over it on the deck (control: a hit)
##   falcon_deck_kart_below  an untargeted falcon released on the deck before the crossing flies over
##                           a kart driving through the gate below (expected: no hit)
##   falcon_gate_to_deck     a falcon released on the gate road targets a kart ahead on the deck; it
##                           follows the road up the spiral (control: a hit, at the deck's height)
## The crossing is found from the track (the main samples closest in plan with the loop distance far
## apart). Usage: godot --headless --path . -s res://tools/item_level_probe.gd [-- --track=castle_circuit]
## Observations only: always exits 0.

const DT: float = 1.0 / 60.0
## Seconds each case runs.
const CASE_TIME: float = 9.0
## Meters ahead along the road the steering aims at.
const AIM_AHEAD: float = 10.0
## Loop distance (m) two samples must be apart to count as the two passes of a crossing.
const PASS_GAP: float = 60.0

var _track: TrackModel
var _items: ItemSet
var _stats: VehicleStats
var _racers: Array[Racer] = []
var _im: ItemManager
var _t: float = 0.0
var _low_s: float = 0.0
var _high_s: float = 0.0


func _initialize() -> void:
	var id: String = "castle_circuit"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--track="):
			id = a.substr("--track=".length())
	_track = TrackModel.new(TrackLibrary.load_track(id))
	_items = load("res://assets/data/items/item_set.tres")
	_stats = load("res://assets/data/vehicles/armored_cart.tres")
	if not _find_crossing():
		print("track=%s: the main loop does not cross itself" % id)
		quit(0)
		return
	print("track=%s crossing: lower s=%.1f h=%.2f, upper s=%.1f h=%.2f, hit_height_tolerance %.2f" % [
			id, _low_s, _track.height_at(_low_s), _high_s, _track.height_at(_high_s), _items.hit_height_tolerance])
	_case_spill(false)
	_case_spill(true)
	_case_falcon_over()
	_case_falcon_up()
	quit(0)


# The two main-loop distances where the loop passes over itself (closest samples in plan).
func _find_crossing() -> bool:
	var m: TrackModel.Path = _track.main
	var best: float = INF
	for i in range(0, m.points.size(), 2):
		for j in range(i + 1, m.points.size(), 2):
			var gap: float = absf(m.cumulative[j] - m.cumulative[i])
			if minf(gap, m.length - gap) < PASS_GAP:
				continue
			var d: float = m.points[i].distance_to(m.points[j])
			if d < best:
				best = d
				_low_s = m.cumulative[i]
				_high_s = m.cumulative[j]
	if best > 3.0:
		return false
	if _track.height_at(_low_s) > _track.height_at(_high_s):
		var tmp: float = _low_s
		_low_s = _high_s
		_high_s = tmp
	return true


func _setup(karts: Array) -> void:
	_racers.clear()
	for k in karts.size():
		var r := Racer.new()
		r.kart_id = k
		r.sim = KartSim.new(_stats)
		r.sim.reset_to(_track, float(karts[k]), 0.0)
		r.laps = LapCounter.new(3, _track.length, _track.checkpoint_s)
		_racers.append(r)
	if _im != null:
		_im.queue_free()
	_im = ItemManager.new()
	root.add_child(_im)
	_im.setup(_items, func() -> Array: return _racers, func() -> Racer: return _racers[0],
			func(_kid: int) -> int: return 1, func(_place: int) -> int: return -1, func() -> bool: return false, null)
	_im.reset(_track, 1)
	_t = 0.0


func _item_index(item_id: StringName) -> int:
	for i in _items.items.size():
		if _items.items[i].id == item_id:
			return i
	return -1


# Ticks every kart in [param drivers] (kart id -> true) along the main road, then the items.
func _run(drivers: Array, label: String, stop_s: float = INF) -> void:
	var min_gap: float = INF
	var input := KartInput.new()
	input.throttle = 1.0
	var hits_at: PackedStringArray = PackedStringArray()
	_im.item_event.connect(func(kind: StringName, _text: String) -> void:
		if kind == &"hit":
			for k in drivers:
				hits_at.append("kart %d hit at s=%.1f h=%.2f" % [k, _racers[k].sim.track_s, _racers[k].sim.height]))
	while _t < CASE_TIME and _racers[drivers[0]].sim.track_s < stop_s:
		for k in drivers:
			var sim: KartSim = _racers[k].sim
			var aim_s: float = sim.track_s + AIM_AHEAD
			var d: Vector2 = _track.point_at(aim_s) - sim.position
			input.steer = clampf(wrapf(atan2(-d.x, -d.y) - sim.yaw, -PI, PI) * 2.0, -1.0, 1.0)
			sim.tick(DT, input, _track)
		_t += DT
		_im.update(DT, _t)
		for ai in _im._active:
			for k in drivers:
				var sim2: KartSim = _racers[k].sim
				min_gap = minf(min_gap, sim2.position.distance_to(ai.pos))
	var heights: PackedStringArray = PackedStringArray()
	for k in drivers:
		heights.append("kart %d s=%.1f h=%.2f" % [k, _racers[k].sim.track_s, _racers[k].sim.height])
	print("== %s: hits %d %s %s; closest kart-item distance in plan %.2f m; ran %.2f s; end %s" % [label, _im.hit_log.size(),
			str(_im.hit_log), str(hits_at), min_gap, _t, ", ".join(heights)])


# A spill on the deck over the gate road; a kart drives through the gate under it, or over it.
func _case_spill(on_deck: bool) -> void:
	var start: float = (_high_s if on_deck else _low_s) - 24.0
	_setup([_high_s, start])
	var owner: Racer = _racers[0]
	var p: Vector2 = _track.point_at(_high_s)
	_im._spawn(1, _item_index(&"spill"), 0, 0.0, p, _track.tangent_at(_high_s), -1)
	owner.dropped = true  # the owner leaves; only kart 1 drives
	var ai: ItemManager.ActiveItem = _im._active[0] if not _im._active.is_empty() else null
	print("   spill at (%.1f, %.1f) y=%.2f" % [p.x, p.y, ai.y if ai != null else NAN])
	# The kart below stops 30 m past the crossing: driven on, it climbs the spiral onto the deck and
	# meets the spill there (a hit at its own level, not the case under test).
	_run([1], "spill_deck_kart_on_deck" if on_deck else "spill_deck_kart_below", INF if on_deck else _low_s + 30.0)


# An untargeted falcon released on the deck 15 m before the crossing; a kart drives under it.
func _case_falcon_over() -> void:
	_setup([_high_s - 15.0, _low_s - 1.0])
	var owner: Racer = _racers[0]
	var p: Vector2 = _track.point_at(_high_s - 15.0)
	_im._spawn(1, _item_index(&"falcon"), 0, 0.0, p, _track.tangent_at(_high_s - 15.0), -1)
	owner.dropped = true
	var ai: ItemManager.ActiveItem = _im._active[0] if not _im._active.is_empty() else null
	print("   falcon at s=%.1f y=%.2f" % [ai.s if ai != null else NAN, ai.y if ai != null else NAN])
	_run([1], "falcon_deck_kart_below", _low_s + 30.0)


# A falcon released on the gate road targets a kart ahead, up the spiral on the deck.
func _case_falcon_up() -> void:
	_setup([_low_s - 5.0, _high_s - 20.0])
	var owner: Racer = _racers[0]
	var p: Vector2 = _track.point_at(_low_s - 5.0)
	_im._spawn(1, _item_index(&"falcon"), 0, 0.0, p, _track.tangent_at(_low_s - 5.0), 1)
	owner.dropped = true
	_run([1], "falcon_gate_to_deck")
