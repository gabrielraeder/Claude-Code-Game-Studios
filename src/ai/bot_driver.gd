class_name BotDriver
extends AutopilotDriver
## Host-owned bot (story 005). A bot is just another input source: it fills KartInput and the
## KartSim races it under the same rules as any kart. Built on the autopilot's route helpers
## (centerline, shortcut branches, rail-less entrances) and adds, all from data (BotSet and
## BotPersonality): an outside-in-out racing line, drifting only where it pays, per-lap shortcut
## plans that can be missed, avoidance of karts ahead, stuck recovery, item use through
## KartInput.item, and a small rubber-band multiplier on the bot's own top speed.

## The character this bot drives with.
var personality: BotPersonality
## Kart id this driver steers.
var kart_id: int = 0
## Laps in the race (for the finish line of the debug log).
var lap_target: int = 3
## Stuck events this race (read by the debug log).
var stuck_events: int = 0
## Longest time (seconds) the bot was barely moving in one go.
var stuck_longest: float = 0.0

## What _open_edge_side returns when both edges of the road are open.
const OPEN_BOTH: float = 2.0
## A ramp passed again after this many seconds is a new jump (a new trick roll); not a tuning value.
const TRICK_REROLL_TIME: float = 3.0

var _set: BotSet
var _seed: int = 0
# Story 008 trick jumps: ramp index of the current roll (-1 = none), when it was rolled, whether this
# jump gets the hop, and how many rolls so far (part of the roll's hash).
var _trick_ramp: int = -1
var _trick_roll_t: float = -99.0
var _trick_go: bool = false
var _trick_rolls: int = 0
var _ctx: BotContext
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _base_max: float = 0.0
var _mult: float = 1.0
var _mult_sum: float = 0.0
var _ticks: int = 0
var _race_ticks: int = 0
var _ai_us: int = 0
var _race_t: float = 0.0
var _crossings: int = 0
var _prev_s: float = -1.0
var _lap_start_t: float = 0.0
var _lap_times: PackedFloat32Array = PackedFloat32Array()
var _finished: bool = false
var _plan: Dictionary = {}
var _plan_crossings: int = -99
var _was_missed: bool = false
var _prev_path: int = -1
var _lat: float = 0.0
var _press_before: float = 0.0
var _wander_phase: float = 0.0
var _corner_state: int = 0
var _anchor: Vector2 = Vector2.ZERO
var _anchor_t: float = 0.0
var _recover_t: float = 0.0
var _stuck_since: float = -1.0
var _av_id: int = -1
var _av_dir: float = 0.0
var _hold_t: float = 0.0
var _item_timer: float = 0.0
var _state: String = ""
var _was_sinking: bool = false
var _gate_branch: int = -1
var _gate_speed: float = 0.0
var _speed_checked: int = -1
var _timing_checked: int = -1
var _barrel_trace_next: float = 0.0
var _barrel_near: bool = false
var _barrel_conflict: bool = false
var _calm_until: float = -1.0
var _trace: bool = false
var _trace_next: float = 0.0
# Debug (--bot-stuck-test=ID): 0 = not this bot, 1 = waiting for the pin, 2 = pinned (throttle into
# the wall until the stuck recovery starts), 3 = done.
var _stuck_test: int = 0
var _pin_pos: Vector2 = Vector2.ZERO
var _pin_yaw: float = 0.0
var _last_speed: float = 0.0
var _last_bump_t: float = -99.0
var _last_hit_t: float = -99.0
var _bump_hooked: bool = false
var _prev_spin: float = 0.0
## Sinks this race (read by the debug log).
var sink_count: int = 0


## Builds the driver for [param id] from [param set] ([param laps] = laps in the race).
## [param race_seed] is the host's race seed, so plans and rolls differ per race but match on every PC.
static func create(set: BotSet, id: int, ctx: BotContext, laps: int, race_seed: int) -> BotDriver:
	var d := BotDriver.new()
	d._set = set
	d._ctx = ctx
	d.kart_id = id
	d.lap_target = laps
	d.personality = set.personality_for(id)
	d._rng.seed = hash([id, race_seed, 7919])
	d._seed = race_seed
	for a in OS.get_cmdline_user_args():
		if a == "--bot-stuck-test=%d" % id:
			d._stuck_test = 1
		elif a == "--bot-trace":
			d._trace = true
	d._press_before = maxf(d.personality.start_press_before_go
			+ d._rng.randf_range(-d.personality.start_press_spread, d.personality.start_press_spread), 0.0)
	d._wander_phase = d._rng.randf() * TAU
	return d


# Story 008: before a ramp lip on the bot's own road, let go of drift, then hop just before the lip
# for the trick boost, on trick_chance of the jumps. The roll is a hash (not _rng), so it never
# shifts the bot's other rolls and is the same on every PC.
func _trick_hop(input: KartInput, sim: KartSim, track: TrackModel) -> void:
	if not sim.grounded:
		return
	var lead: float = maxf(sim.speed, 1.0) * sim.stats.trick_window * _set.trick_hop_lead_frac
	for i in track.ramp_lip_s.size():
		if track.ramp_paths[i] != sim.track_path:
			continue
		var to_lip: float = wrapf(track.ramp_lip_s[i] - sim.track_s, -track.length * 0.5, track.length * 0.5)
		if to_lip <= 0.0 or to_lip > lead + _set.trick_release_meters:
			continue
		if _trick_ramp != i or _race_t - _trick_roll_t > TRICK_REROLL_TIME:
			_trick_ramp = i
			_trick_roll_t = _race_t
			_trick_rolls += 1
			_trick_go = float(absi(hash([kart_id, _seed, _trick_rolls, i])) % 1000) < _set.trick_chance * 1000.0
			if _trick_go:
				_state = " trick"
		if not _trick_go:
			return
		input.drift = to_lip <= lead
		return


## One line about what the bot is doing (debug labels).
func describe() -> String:
	var held: StringName = _ctx.held_fn.call(kart_id) if _ctx != null else &""
	return "%s%s%s" % [personality.display_name, ("  [" + String(held) + "]") if held != &"" else "", _state]


## Fills [param input] for the next tick (see KartDriver).
func drive(input: KartInput, sim: KartSim, track: TrackModel, dt: float) -> void:
	var t0: int = Time.get_ticks_usec()
	_drive(input, sim, track, dt)
	if time_to_go <= 0.0 and not sim.is_sinking():
		_trick_hop(input, sim, track)
	_ai_us += Time.get_ticks_usec() - t0
	_ticks += 1


func _drive(input: KartInput, sim: KartSim, track: TrackModel, dt: float) -> void:
	if _base_max <= 0.0:
		_base_max = sim.stats.max_speed
		_branch = -1
	input.item = false
	input.brake = 0.0
	if time_to_go > 0.0:
		input.drift = false
		input.steer = 0.0
		input.throttle = 1.0 if time_to_go <= _press_before else 0.0
		return
	_race_t += dt
	_race_ticks += 1
	if not _bump_hooked:
		_bump_hooked = true
		sim.kart_bumped.connect(func(_strength: float) -> void: _last_bump_t = _race_t)
		# The kart is bound through a WeakRef: a connection stored in the kart's own signal that
		# held the kart strongly would be a reference cycle (the KartSim never freed, a crash at
		# exit when the engine tears the leaked objects down).
		sim.mover_hit.connect(_on_mover_hit.bind(weakref(sim)))
	if sim.spin_time > _prev_spin:
		_last_hit_t = _race_t
	_prev_spin = sim.spin_time
	if sim.is_sinking() and not _was_sinking:
		sink_count += 1
		print("[bot] SINK kart=%d name=%s s=%.0f path=%s hazard=%s speed=%.1f lat=%.1f bump=%d hit=%d t=%.2f" % [
				kart_id, personality.display_name, sim.track_s,
				track.data.branches[sim.track_path].id if sim.track_path >= 0 else "main",
				sim.hazard_kind, _last_speed, sim.lateral,
				1 if _race_t - _last_bump_t < 1.0 else 0, 1 if _race_t - _last_hit_t < 1.5 else 0, _race_t])
	if _was_sinking and not sim.is_sinking():
		_calm_until = _race_t + _set.respawn_calm_time
		_lat = 0.0
	_was_sinking = sim.is_sinking()
	_last_speed = sim.speed
	_track_laps(sim, track)
	if sim.is_sinking():
		_anchor = sim.position
		_anchor_t = 0.0
		_state = " sinking"
		return
	_select_branch(track, sim)
	_update_missed(track, sim)
	_log_branch_events(track, sim)
	_rubber(sim, track, dt)

	var on_open: int = _open_branch_phase(track, sim)
	var deck: bool = sim.track_path >= 0 and track.data.branches[sim.track_path].open_edge_reach > 0.0
	var calm: bool = _race_t < _calm_until
	var narrow: bool = deck or (sim.road_half_width > 0.0 and sim.road_half_width < _set.narrow_half_width)
	var speed: float = maxf(sim.speed, 0.0)
	var look: float = _set.look_base + speed * _set.look_per_speed
	if on_open > 0 or narrow:
		look = OPEN_LOOK_BASE + speed * OPEN_LOOK_PER_SPEED
	var route_branch: int = _route_branch(track, sim)
	var near_t: Vector2 = _route_tangent(track, sim, _set.corner_near)
	var mid_t: Vector2 = _route_tangent(track, sim, _set.corner_mid)
	var far_t: Vector2 = _route_tangent(track, sim, _set.corner_far)
	# Positive = the track bends toward yaw+ (the autopilot's "left").
	var turn: float = -near_t.angle_to(mid_t)
	var turn_far: float = -mid_t.angle_to(far_t)

	# Usable half width for the line, and the line itself.
	var half: float = sim.road_half_width if sim.road_half_width > 0.0 else track.half_width_at(sim.track_s)
	if sim.track_path == TrackModel.MAIN_PATH and route_branch < 0:
		half = minf(half, track.half_width_at(sim.track_s + look))
	var usable: float = maxf(half - _set.wall_margin, 0.0)
	# A rail-less deck (planned or not), the approach to a planned one, and the seconds after a
	# respawn: centerline only (no line offset, no dodge).
	if deck or calm or (on_open > 0):
		usable = 0.0
	var desired: float = _line_offset(track, sim, turn, turn_far, usable, route_branch, narrow)
	_scan_traffic(sim, usable)
	desired += _av_shift
	desired = _barrel_lane(track, sim, desired, usable)
	if _barrel_near:
		# Steer at a nearer point so the kart is in the chosen lane where the barrel is (a far
		# pursuit point cuts the inside of the market S-bend, into the barrel lanes).
		look = minf(look, _set.barrel_steer_look)
	var open_side: float = _open_edge_side(track, sim) if sim.track_path == TrackModel.MAIN_PATH else 0.0
	var lim_neg: float = usable
	var lim_pos: float = usable
	if open_side < 0.0 or open_side >= OPEN_BOTH:
		lim_neg = minf(usable, _set.open_edge_keep)
	if open_side > 0.0:
		lim_pos = minf(usable, _set.open_edge_keep)
	_lat = move_toward(_lat, clampf(desired, -lim_neg, lim_pos), _set.lateral_rate * dt)
	_lat = clampf(_lat, -lim_neg, lim_pos)
	var rp: Vector2 = _route_point(track, sim, look)
	var rt: Vector2 = _route_tangent(track, sim, look)
	var target: Vector2 = rp + Vector2(-rt.y, rt.x) * _lat
	var to: Vector2 = target - sim.position
	var diff: float = wrapf(atan2(-to.x, -to.y) - sim.yaw, -PI, PI)

	input.throttle = 1.0
	input.steer = clampf(diff * _set.steer_gain, -1.0, 1.0)
	input.drift = false
	if _trace and (_race_t < _calm_until or open_side != 0.0) and _race_t >= _trace_next:
		_trace_next = _race_t + 0.1
		var tq: TrackModel.Query = track.query(target, -1)
		print("[bot-trace] kart=%d t=%.2f path=%d s=%.1f lat=%.2f speed=%.1f yaw_err=%.2f steer=%.2f route_branch=%d target_path=%d target_s=%.1f target_lat=%.2f _lat=%.2f drift=%s boost=%.2f spin=%.2f" % [
				kart_id, _race_t, sim.track_path, sim.track_s, sim.lateral, sim.speed, diff, input.steer,
				route_branch, tq.path, tq.s, tq.lateral, _lat, str(sim.drifting), sim.boost_time, sim.spin_time])

	if _stuck_test == 1 and _race_t >= 3.0:
		_pin_against_wall(sim, track)
	if _stuck_test == 2:
		sim.position = _pin_pos
		sim.yaw = _pin_yaw
		sim.speed = 0.0
		sim.velocity = Vector2.ZERO
		input.throttle = 1.0
		input.steer = 0.0
		input.drift = false
	if _check_stuck(sim, dt):
		if _stuck_test == 2:
			_stuck_test = 3
		_state = " recover"
		input.throttle = 0.0
		input.brake = 1.0
		input.steer = -clampf(diff * _set.steer_gain, -1.0, 1.0)
		_drifting_intent = false
		return
	_state = ""

	if on_open > 0 or deck:
		_drifting_intent = false
		if on_open == 2 and sim.speed > _set.open_entry_speed:
			input.throttle = 0.0
			input.brake = 1.0 if sim.speed > _set.open_entry_speed + 1.0 else 0.0
		elif on_open != 2 and sim.speed > _set.open_deck_speed:
			input.throttle = 0.0
	elif _gate_on_route(track, sim) or calm or _barrel_near:
		# No drift with a barrel near: a drifting kart cannot hold the free lane.
		_drifting_intent = false
	else:
		_drive_drift(input, sim, track, diff, look, turn, open_side)
	input.drift = _drifting_intent and on_open == 0

	# A barrel close ahead in the kart's lane: lift (never brake) while the dodge clears it, but only
	# while fast (a kart slowed by a hit must drive on, not stand behind the barrel).
	if _barrel_conflict and sim.speed > _set.barrel_lift_min_speed:
		input.throttle = 0.0
	# Traffic: lift or brake when a slower kart is in the way and the dodge has not cleared it.
	if _av_brake:
		input.throttle = 0.0
		input.brake = 1.0
		input.drift = false
		_drifting_intent = false
	elif _av_lift:
		input.throttle = 0.0
	_think_items(input, sim, turn, dt)


# ---------------------------------------------------------------- laps and log

func _track_laps(sim: KartSim, track: TrackModel) -> void:
	var s: float = sim.track_s
	if _prev_s >= 0.0:
		if _prev_s > track.length * 0.75 and s < track.length * 0.25:
			_crossings += 1
			if _crossings >= 2 and not _finished:
				_lap_times.append(_race_t - _lap_start_t)
				print("[bot] LAP kart=%d name=%s lap=%d time=%.2f t=%.2f" % [
						kart_id, personality.display_name, _crossings - 1, _lap_times[-1], _race_t])
			_lap_start_t = _race_t
			if _crossings == lap_target + 1 and not _finished:
				_finished = true
				print("[bot] FINISH kart=%d name=%s total=%.2f stuck=%d stuck_longest=%.2f rubber_mean=%.4f ai_us_per_tick=%.1f" % [
						kart_id, personality.display_name, _race_t, stuck_events, stuck_longest,
						_mult_sum / maxf(float(_race_ticks), 1.0), float(_ai_us) / maxf(float(_ticks), 1.0)])
		elif _prev_s < track.length * 0.25 and s > track.length * 0.75:
			_crossings -= 1
	_prev_s = s


func _log_branch_events(track: TrackModel, sim: KartSim) -> void:
	if _missed and not _was_missed and _branch >= 0:
		print("[bot] BRANCH kart=%d name=%s lap=%d id=%s ev=miss" % [
				kart_id, personality.display_name, _crossings - 1, track.data.branches[_branch].id])
	_was_missed = _missed
	var path: int = sim.track_path
	if path != _prev_path and path >= 0:
		print("[bot] BRANCH kart=%d name=%s lap=%d id=%s ev=enter planned=%d" % [
				kart_id, personality.display_name, _crossings - 1, track.data.branches[path].id,
				1 if path == _branch else 0])
	_prev_path = path


# ---------------------------------------------------------------- shortcuts

# A kart on a rail-less deck, planned or not, follows that deck to its end. (The autopilot's
# version only does so once the kart is outside the main corridor; near the deck's mouth the two
# overlap, the route fell back to the main road or to another planned branch, and the look-ahead
# point landed across the gap.)
func _route_branch(track: TrackModel, sim: KartSim) -> int:
	var p: int = sim.track_path
	if p >= 0 and track.data.branches[p].open_edge_reach > 0.0:
		return p
	return super(track, sim)


# Rail-less shortcut: missed (given up until its end) once the kart is on the main road past the
# mouth and not on the deck, so a respawn or a miss never aims across the gap.
func _update_missed(track: TrackModel, sim: KartSim) -> void:
	if _branch < 0 or track.data.branches[_branch].open_edge_reach <= 0.0:
		super(track, sim)
		return
	var b: TrackModel.Path = track.branches[_branch]
	var s: float = sim.track_s
	if _missed:
		if s > b.s_out or s < b.s_in - _set.open_entry_before:
			_missed = false
		return
	if sim.track_path == TrackModel.MAIN_PATH and s > b.s_in + _set.open_mouth_len and s < b.s_out \
			and track.distance_to_path(sim.position, _branch) > b.wall_offset + _set.open_off_deck_margin:
		_missed = true


# Like the autopilot's phase (0 = not near a rail-less branch on the route, 1 = on its deck,
# 2 = in its entrance zone) but with the braking distance from data.
func _open_branch_phase(track: TrackModel, sim: KartSim) -> int:
	if _branch < 0 or _missed or track.data.branches[_branch].open_edge_reach <= 0.0:
		return 0
	var b: TrackModel.Path = track.branches[_branch]
	var s: float = sim.track_s
	if s < b.s_in - _set.open_entry_before or s > b.s_out:
		return 0
	if s < b.s_in:
		return 2
	return 2 if track.branch_distance_for_s(_branch, s) < OPEN_ENTRY_AFTER else 1

func _roll_plan(track: TrackModel) -> void:
	_plan.clear()
	var n: int = track.branch_count()
	var ids: PackedStringArray = PackedStringArray()
	for bi in n:
		var type: StringName = track.data.branches[bi].type
		var f: float = float(_set.branch_factor.get(type, _set.branch_factor.get(String(type), 1.0)))
		_plan[bi] = _rng.randf() < personality.shortcut_chance * f
	# Branches over the same stretch (two lanes): one at most.
	for i in n:
		for j in range(i + 1, n):
			if _plan[i] and _plan[j]:
				var a: TrackModel.Path = track.branches[i]
				var b: TrackModel.Path = track.branches[j]
				if a.s_in < b.s_out and b.s_in < a.s_out:
					_plan[i if _rng.randf() < 0.5 else j] = false
	for bi in n:
		if _plan[bi]:
			ids.append(String(track.data.branches[bi].id))
	print("[bot] PLAN kart=%d name=%s lap=%d seed=%d take=%s" % [
			kart_id, personality.display_name, _crossings - 1, _seed, ",".join(ids)])


# The route's branch is the next planned one whose end is still ahead.
func _select_branch(track: TrackModel, sim: KartSim) -> void:
	if _plan_crossings != _crossings:
		_plan_crossings = _crossings
		_gate_branch = -1
		_speed_checked = -1
		_timing_checked = -1
		_roll_plan(track)
	var best: int = -1
	var best_in: float = INF
	for bi in _plan.keys():
		if not _plan[bi]:
			continue
		var b: TrackModel.Path = track.branches[bi]
		if b.s_out > sim.track_s and b.s_in < best_in:
			best = bi
			best_in = b.s_in
	if best == _branch and best >= 0 and _gate_branch != best and track.data.branches[best].open_edge_reach > 0.0 \
			and sim.track_s >= track.branches[best].s_in - _set.branch_gate_dist:
		_gate_branch = best
		var crowd: int = 0
		for r: Racer in _ctx.racers_fn.call():
			if r.kart_id != kart_id and not r.dropped and r.sim != null and not r.is_finished() \
					and r.sim.position.distance_to(sim.position) < _set.branch_clear_radius:
				crowd += 1
		if crowd > 0:
			_plan[best] = false
			print("[bot] BRANCH kart=%d name=%s lap=%d id=%s ev=skip_crowded" % [
					kart_id, personality.display_name, _crossings - 1, track.data.branches[best].id])
			_select_branch(track, sim)
			return
	# Story 009: a branch with a timed gate (the drawbridge) is taken only when the gate will be open
	# while the bot crosses it. Otherwise the bot stays on the main road and never waits.
	if best == _branch and best >= 0 and _timing_checked != best \
			and sim.track_s >= track.branches[best].s_in - _set.branch_gate_dist:
		_timing_checked = best
		if not _gate_timing_ok(track, sim, best):
			_plan[best] = false
			print("[bot] BRANCH kart=%d name=%s lap=%d id=%s ev=skip_timing" % [
					kart_id, personality.display_name, _crossings - 1, track.data.branches[best].id])
			_select_branch(track, sim)
			return
	if best == _branch and best >= 0 and _gate_speed > 0.0 and _speed_checked != best \
			and sim.track_s >= track.branches[best].s_in - _set.branch_gate_dist:
		_speed_checked = best
		if sim.speed < _gate_speed - _set.gate_speed_slack:
			_plan[best] = false
			print("[bot] BRANCH kart=%d name=%s lap=%d id=%s ev=skip_slow speed=%.1f" % [
					kart_id, personality.display_name, _crossings - 1, track.data.branches[best].id, sim.speed])
			_select_branch(track, sim)
			return
	if best == _branch:
		return
	_branch = best
	_missed = false
	_was_missed = false
	_gate_route = false
	_gate_speed = 0.0
	if best >= 0:
		for i in track.hazard_gates.size():
			if track.hazard_gates[i] > 0.0 and track.distance_to_path(track.hazard_bounds[i].get_center(), best) < 8.0:
				_gate_route = true
				_gate_speed = maxf(_gate_speed, track.hazard_gates[i])


# True when the timed gate on branch [param bi] (if any) stays open from the bot's estimated arrival
# at the deck's start to its estimated exit, with a margin. The estimate uses BotSet.gate_eta_speed;
# a risk-taking personality has a smaller margin and a noisier estimate, so it can mis-time.
func _gate_timing_ok(track: TrackModel, sim: KartSim, bi: int) -> bool:
	if not _ctx.time_fn.is_valid() or not _ctx.gate_blocked_fn.is_valid():
		return true
	var id: StringName = track.data.branches[bi].id
	for m in track.data.movers:
		if m.kind != &"gate" or m.path != id:
			continue
		var t: float = _ctx.time_fn.call()
		var to_entry: float = track.branches[bi].s_in - sim.track_s
		var v: float = maxf(_set.gate_eta_speed, 0.1)
		var err: float = _rng.randf_range(-1.0, 1.0) * _set.gate_eta_error * personality.gate_risk
		var margin: float = _set.gate_margin * (1.0 - personality.gate_risk)
		var t0: float = t + (to_entry + m.path_from) / v + err - margin
		var t1: float = t + (to_entry + m.path_to) / v + err + margin
		if _ctx.gate_blocked_fn.call(id, t0, t1):
			return false
	return _cart_timing_ok(track, sim, bi)


# Story 009 part 3: a traveler on branch [param bi] (the mine cart): predicts from the closed-form
# hazard state whether it will meet the bot on the branch, at BotSet.gate_eta_speed. A meeting
# turns only a careful bot (gate_risk below BotSet.cart_pass_risk) away; the others pass it by lane.
func _cart_timing_ok(track: TrackModel, sim: KartSim, bi: int) -> bool:
	if not _ctx.time_fn.is_valid() or not _ctx.travelers_fn.is_valid() or personality.gate_risk >= _set.cart_pass_risk:
		return true
	var id: StringName = track.data.branches[bi].id
	var has_cart: bool = false
	for m in track.data.movers:
		if m.path == id and m.is_traveler():
			has_cart = true
	if not has_cart:
		return true
	var t: float = _ctx.time_fn.call()
	var to_entry: float = track.branches[bi].s_in - sim.track_s
	var v: float = maxf(_set.gate_eta_speed, 0.1)
	var a: float = 0.0
	var length: float = track.branch_length(bi)
	while a <= length:
		var ta: float = t + (to_entry + a) / v
		var near: PackedVector3Array = _ctx.travelers_fn.call(bi, a - _set.cart_meet_step, a + _set.cart_meet_step, ta)
		for b in near:
			if absf(b.x - a) <= b.z + _set.cart_meet_margin:
				print("[bot] CART kart=%d name=%s meet at %.1f m of %s in %.2f s" % [kart_id, personality.display_name, a, id, ta - t])
				return false
		a += maxf(_set.cart_meet_step, 0.1)
	return true


# Story 009 log: a timed hazard hit this bot's kart ([param sim_ref] is a WeakRef to its KartSim).
func _on_mover_hit(mover_index: int, sim_ref: WeakRef) -> void:
	var sim: KartSim = sim_ref.get_ref() as KartSim
	if sim == null:
		return
	print("[bot] HAZARD_HIT kart=%d name=%s mover=%d s=%.0f lat=%.1f speed=%.1f t=%.2f" % [
			kart_id, personality.display_name, mover_index, sim.track_s, sim.lateral, sim.speed, _race_t])


# Story 009: a rolling barrel ahead on the main road within BotSet.barrel_look meters: aim for the
# free lane nearest the wanted line (the wanted line itself when it is already clear of every barrel
# by BotSet.barrel_clear). With no free lane the line is kept. Pure lateral choice, never a brake.
func _barrel_lane(track: TrackModel, sim: KartSim, desired: float, usable: float) -> float:
	_barrel_near = false
	_barrel_conflict = false
	if not _ctx.travelers_fn.is_valid() or usable <= 0.0:
		return desired
	# Along the road the kart is on: the main road's s, or the distance along a branch (the cart on
	# the mine rail is passed the same way as a barrel).
	var along: float = sim.track_s
	if sim.track_path != TrackModel.MAIN_PATH:
		along = track.branch_along(sim.track_path, sim.position)
	var ahead: PackedVector3Array = _ctx.travelers_fn.call(sim.track_path, along - _set.barrel_behind,
			along + _set.barrel_look, -1.0)
	if ahead.is_empty():
		return desired
	_barrel_near = true
	for b in ahead:
		if b.x > along and b.x - along < _set.barrel_lift_dist and absf(sim.lateral - b.y) < b.z + _set.barrel_clear:
			_barrel_conflict = true
	var n: int = maxi(_set.barrel_lane_samples, 2)
	var best: float = desired
	var best_cost: float = INF
	for k in n + 1:
		var x: float = clampf(desired, -usable, usable) if k == n else lerpf(-usable, usable, float(k) / float(n - 1))
		var clear: bool = true
		for b in ahead:
			if absf(x - b.y) < b.z + _set.barrel_clear:
				clear = false
				break
		# The free lane nearest where the kart is (least steering), then nearest the wanted line.
		var cost: float = absf(x - sim.lateral) + absf(x - desired) * _set.barrel_line_weight
		if clear and cost < best_cost:
			best_cost = cost
			best = x
	if _trace and _race_t >= _barrel_trace_next:
		_barrel_trace_next = _race_t + 0.1
		print("[bot-barrel] kart=%d t=%.2f s=%.1f lat=%.2f usable=%.2f desired=%.2f chosen=%.2f _lat=%.2f lift=%d barrels=%s" % [
				kart_id, _race_t, sim.track_s, sim.lateral, usable, desired, best, _lat, 1 if _barrel_conflict else 0, str(ahead)])
	return best


# ---------------------------------------------------------------- racing line

# Side (+1 normal side, -1 the other, 2 both, 0 none) of an unwalled main-road edge near the kart.
func _open_edge_side(track: TrackModel, sim: KartSim) -> float:
	var s: float = sim.track_s
	var neg: bool = false
	var pos: bool = false
	for e in track.data.open_edges.size():
		var edge: Vector3 = track.data.open_edges[e]
		if s >= edge.x - _set.open_edge_ahead and s <= edge.y + _set.open_edge_behind:
			if edge.z < 0.0:
				neg = true
			else:
				pos = true
	return 2.0 if (neg and pos) else (-1.0 if neg else (1.0 if pos else 0.0))

func _line_offset(track: TrackModel, sim: KartSim, turn: float, turn_far: float, usable: float,
		route_branch: int, narrow: bool) -> float:
	var p: BotPersonality = personality
	var s: float = sim.track_s
	if route_branch >= 0 or sim.track_path != TrackModel.MAIN_PATH or narrow:
		return 0.0
	if _branch >= 0 and not _missed:
		var b: TrackModel.Path = track.branches[_branch]
		if s >= b.s_in - _set.branch_center_before and s <= b.s_out:
			return 0.0
	var u_in: float = clampf(turn / _set.corner_ref_turn, -1.0, 1.0)
	var u_out: float = clampf(turn_far / _set.corner_ref_turn, -1.0, 1.0) * (1.0 - absf(u_in))
	# The inside of a corner that bends toward +turn is on the negative lateral side.
	var frac: float = p.line_amount * (-p.inside_gain * u_in + p.outside_gain * u_out) + p.lane_bias
	if p.wander_amount > 0.0:
		frac += p.wander_amount * sin(TAU * s / maxf(p.wander_period, 1.0) + _wander_phase)
	return clampf(frac, -1.0, 1.0) * usable


# ---------------------------------------------------------------- drift

func _drive_drift(input: KartInput, sim: KartSim, track: TrackModel, diff: float, look: float, turn: float,
		open_side: float) -> void:
	var p: BotPersonality = personality
	var aturn: float = absf(turn)
	if aturn < _set.corner_end_turn:
		_corner_state = 0
	elif _corner_state == 0 and aturn >= p.drift_start_turn * _set.corner_start_share:
		_corner_state = 1 if _rng.randf() < p.drift_chance else 2
	var abort_lat: float = maxf(sim.road_half_width - _set.drift_wall_margin, 1.0)
	var open_abort: bool = false
	if open_side >= OPEN_BOTH:
		open_abort = absf(sim.lateral) > _set.open_edge_drift_abort
	elif open_side != 0.0:
		open_abort = sim.lateral * open_side > _set.open_edge_drift_abort
	if not sim.drifting:
		_drifting_intent = false
		if _near_open_entry(track, sim):
			return
		if open_side != 0.0 and not _set.open_edge_allow_drift_start:
			return
		if _corner_state == 1 and not open_abort and aturn > p.drift_start_turn \
				and sim.speed > sim.stats.drift_min_speed + _set.drift_speed_margin \
				and absf(sim.lateral) < abort_lat:
			_drifting_intent = true
			_drift_sign = signf(turn)
			input.steer = _drift_sign
	else:
		if aturn < _set.drift_keep_turn or signf(turn) != _drift_sign or absf(sim.lateral) > abort_lat or open_abort \
				or (sim.drift_tier >= p.drift_max_tier and aturn < _set.drift_release_turn):
			_drifting_intent = false
		var rate: float = 2.0 * sin(diff) * maxf(sim.speed, 1.0) / look
		var st: VehicleStats = sim.stats
		input.steer = clampf((rate * _drift_sign - st.drift_yaw_base) / st.drift_yaw_range, -1.0, 1.0) \
				* _drift_sign


# ---------------------------------------------------------------- traffic

var _av_shift: float = 0.0
var _av_lift: bool = false
var _av_brake: bool = false


func _scan_traffic(sim: KartSim, usable: float) -> void:
	_av_shift = 0.0
	_av_lift = false
	_av_brake = false
	var fwd: Vector2 = sim.forward()
	var nrm: Vector2 = Vector2(-fwd.y, fwd.x)
	var reach: float = _set.avoid_range_base + maxf(sim.speed, 0.0) * _set.avoid_range_per_speed
	var best: Racer = null
	var best_ahead: float = INF
	var best_side: float = 0.0
	var push: float = 0.0
	for r: Racer in _ctx.racers_fn.call():
		if r.kart_id == kart_id or r.dropped or r.sim == null or r.is_finished() or r.sim.is_sinking():
			continue
		if KartSim.levels_apart(sim, r.sim):
			continue  # another level (a bridge above or the road below): not traffic, not a target
		var rel: Vector2 = r.sim.position - sim.position
		if rel.length_squared() > (reach + 10.0) * (reach + 10.0):
			continue
		var ahead: float = rel.dot(fwd)
		var side: float = rel.dot(nrm)
		if absf(ahead) < _set.avoid_alongside and absf(side) < _set.avoid_side_gap:
			push += (-signf(side) if side != 0.0 else (1.0 if kart_id % 2 == 0 else -1.0)) * _set.avoid_side_push
		elif ahead > 0.0 and ahead < reach and absf(side) < _set.avoid_corridor and ahead < best_ahead:
			best = r
			best_ahead = ahead
			best_side = side
	if best == null:
		_av_id = -1
		_av_dir = 0.0
		_av_shift = clampf(push, -_set.avoid_side_push, _set.avoid_side_push)
		return
	if best.kart_id != _av_id:
		_av_id = best.kart_id
		_av_dir = 0.0
	if absf(best_side) >= _set.avoid_commit_side:
		_av_dir = -signf(best_side)
	elif _av_dir == 0.0:
		var room_pos: float = usable - sim.lateral
		var room_neg: float = usable + sim.lateral
		if absf(room_pos - room_neg) < 0.5:
			_av_dir = 1.0 if kart_id % 2 == 0 else -1.0
		else:
			_av_dir = 1.0 if room_pos > room_neg else -1.0
	var weight: float = clampf(1.3 - best_ahead / reach, 0.25, 1.0)
	_av_shift = _av_dir * _set.avoid_shift * personality.dodge_scale * weight \
			+ clampf(push, -_set.avoid_side_push, _set.avoid_side_push)
	var closing: float = sim.speed - best.sim.speed * best.sim.forward().dot(fwd)
	if best_ahead < _set.brake_gap and closing > _set.brake_closing:
		_av_brake = true
	elif best_ahead < _set.follow_gap and closing > 0.0 and absf(best_side) < _set.avoid_corridor * _set.follow_corridor_share:
		_av_lift = true


# ---------------------------------------------------------------- stuck

# Debug only (--bot-stuck-test=ID): holds this bot nose-first against the road's wall, standing,
# with the throttle down, until its stuck recovery starts (an emulated pin).
func _pin_against_wall(sim: KartSim, track: TrackModel) -> void:
	var q: TrackModel.Query = track.query(sim.position, -1)
	var side: float = 1.0 if sim.lateral >= 0.0 else -1.0
	var into: Vector2 = q.normal * side
	_pin_pos = track.point_at(q.s) + q.normal * side * (q.wall_offset - sim.stats.radius - 0.05)
	_pin_yaw = atan2(-into.x, -into.y)
	sim.position = _pin_pos
	sim.yaw = _pin_yaw
	sim.speed = 0.0
	sim.velocity = Vector2.ZERO
	_stuck_test = 2
	print("[bot] STUCKTEST kart=%d pinned at s=%.0f wall side %.0f t=%.2f" % [kart_id, q.s, side, _race_t])

# True while the bot is reversing out. Barely moving for stuck_time seconds starts a recovery.
func _check_stuck(sim: KartSim, dt: float) -> bool:
	if _finished or not sim.can_drive() or sim.stall_time > 0.0:
		_anchor = sim.position
		_anchor_t = 0.0
		return false
	if _recover_t > 0.0:
		_recover_t -= dt
		if _recover_t <= 0.0:
			print("[bot] RECOVER kart=%d name=%s reversed_to s=%.0f lat=%.1f speed=%.1f t=%.2f" % [
					kart_id, personality.display_name, sim.track_s, sim.lateral, sim.speed, _race_t])
		return true
	if sim.position.distance_to(_anchor) > _set.stuck_move:
		if _stuck_since >= 0.0:
			var dur: float = _race_t - _stuck_since
			stuck_longest = maxf(stuck_longest, dur)
			print("[bot] STUCKEND kart=%d name=%s dur=%.2f t=%.2f" % [kart_id, personality.display_name, dur, _race_t])
			_stuck_since = -1.0
		_anchor = sim.position
		_anchor_t = 0.0
		return false
	_anchor_t += dt
	if _anchor_t >= _set.stuck_time:
		if _stuck_since < 0.0:
			_stuck_since = _race_t - _anchor_t
		stuck_events += 1
		print("[bot] STUCK kart=%d name=%s s=%.0f lat=%.1f t=%.2f" % [
				kart_id, personality.display_name, sim.track_s, sim.lateral, _race_t])
		_recover_t = _set.recover_time
		_anchor_t = 0.0
		_anchor = sim.position
		return true
	return false


# ---------------------------------------------------------------- rubber band

func _rubber(sim: KartSim, track: TrackModel, dt: float) -> void:
	var s: BotSet = _set
	var mine: float = float(_ctx.progress_fn.call(kart_id))
	var best_other: float = -INF
	for r: Racer in _ctx.racers_fn.call():
		if r.kart_id == kart_id or r.dropped:
			continue
		var pr: float = float(_ctx.progress_fn.call(r.kart_id))
		if pr >= RaceRanking.FINISHED_MIN:
			continue
		best_other = maxf(best_other, pr)
	var target: float = 1.0
	if best_other > -INF:
		if best_other > mine:
			target += s.assist_max * smoothstep(s.assist_start_gap, s.assist_full_gap, best_other - mine)
		else:
			target -= s.handicap_max * smoothstep(s.handicap_start_gap, s.handicap_full_gap, mine - best_other)
	target = minf(target * personality.speed_factor, s.rubber_mult_ceiling)
	_mult = move_toward(_mult, target, s.rubber_smoothing * dt)
	if _gate_on_route(track, sim):
		_mult = maxf(_mult, 1.0)
	_mult_sum += _mult
	sim.stats.max_speed = _base_max * _mult


# ---------------------------------------------------------------- items

func _think_items(input: KartInput, sim: KartSim, turn: float, dt: float) -> void:
	var held: StringName = _ctx.held_fn.call(kart_id)
	if held == &"":
		_hold_t = 0.0
		return
	_hold_t += dt
	_item_timer -= dt
	if _hold_t < personality.item_reaction or _item_timer > 0.0:
		return
	_item_timer = _set.item_think_interval
	if _should_use(held, sim, turn):
		input.item = true


func _should_use(held: StringName, sim: KartSim, turn: float) -> bool:
	var p: BotPersonality = personality
	var forced: bool = _hold_t >= (p.shield_hold_max if held == &"shield" else p.item_hold_max)
	var sc: float = p.item_range_scale
	match held:
		&"horn":
			return forced or (sim.boost_time <= 0.0 and sim.speed > 0.6 * _base_max and sim.can_drive()
					and absf(turn) < _set.horn_straight_turn)
		&"stone":
			return forced or _kart_in_cone(sim, _set.stone_min_range, _set.stone_max_range * sc)
		&"spill":
			return forced or _kart_behind(sim, _set.spill_range * sc)
		&"falcon":
			return forced or int(_ctx.place_fn.call(kart_id)) > 1
		&"shield":
			return forced or float(_ctx.threat_fn.call(kart_id)) < _set.threat_range * sc
	return true


func _kart_in_cone(sim: KartSim, min_range: float, max_range: float) -> bool:
	var fwd: Vector2 = sim.forward()
	var nrm: Vector2 = Vector2(-fwd.y, fwd.x)
	var slope: float = tan(deg_to_rad(_set.stone_cone_deg))
	for r: Racer in _ctx.racers_fn.call():
		if r.kart_id == kart_id or r.dropped or r.sim == null or r.is_finished() or r.sim.is_sinking():
			continue
		if KartSim.levels_apart(sim, r.sim):
			continue  # another level (a bridge above or the road below): not traffic, not a target
		var rel: Vector2 = r.sim.position - sim.position
		var ahead: float = rel.dot(fwd)
		if ahead >= min_range and ahead <= max_range and absf(rel.dot(nrm)) <= ahead * slope + _set.stone_cone_slack:
			return true
	return false


func _kart_behind(sim: KartSim, reach: float) -> bool:
	var fwd: Vector2 = sim.forward()
	var nrm: Vector2 = Vector2(-fwd.y, fwd.x)
	for r: Racer in _ctx.racers_fn.call():
		if r.kart_id == kart_id or r.dropped or r.sim == null or r.is_finished() or r.sim.is_sinking():
			continue
		if KartSim.levels_apart(sim, r.sim):
			continue  # another level (a bridge above or the road below): not traffic, not a target
		var rel: Vector2 = r.sim.position - sim.position
		var ahead: float = rel.dot(fwd)
		if ahead <= -2.0 and ahead >= -reach and absf(rel.dot(nrm)) <= _set.spill_lane:
			return true
	return false
