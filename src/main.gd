extends Node3D
## Main scene: runs the flat test loop. Offline it is one local kart with the 3-2-1 start
## (story 001). Online (story 002) it also hosts or joins an ENet race: this PC simulates its
## own kart (and, on the host, the bots), sends their state about 30 times a second, and
## draws every other kart from interpolated snapshots (RemoteKart).
## Wires the pieces together with injected references (no autoloads): VehicleStats,
## TrackData and NetConfig come in as exported resources; the network layer is a child node.

## Emitted once when the local kart finishes the last lap.
signal race_finished(total_time: float)

## Where this PC is in the online flow. SOLO is the default offline path.
enum Mode { SOLO, HOST_LOBBY, CLIENT_LOBBY, NET_RACE }

## Handling data for the vehicles.
@export var vehicle_stats: VehicleStats
## Track to race on.
@export var track_data: TrackData
## Network tuning data.
@export var net_config: NetConfig

## Race clock in seconds. Offline it is the driving time since GO. Online it is the host's
## clock as best this PC knows it: negative during the countdown, 0 at GO.
var race_time: float = 0.0
## Bumps the local kart has taken or given this race (read by the debug harness).
var bump_count: int = 0

# Contact measurements for the bump test (debug: printed as [bump-summary] on exit).
var _pen_max: float = 0.0
var _pen_max_owned: float = 0.0
var _pen_max_remote: float = 0.0
var _deep_remote_frames: int = 0
var _contact_frames: int = 0
var _deep_frames: int = 0
var _race_frames: int = 0
var _knock_max: float = 0.0
var _bump_start: Vector2 = Vector2.ZERO
var _had_net_race: bool = false
var _bump_summary_done: bool = false

var _options: DebugOptions
var _net_opts: NetOptions
var _track: TrackModel
var _local: Racer
var _sim: KartSim
var _input: KartInput
var _laps: LapCounter
var _start: StartSequence
var _camera: ChaseCamera
var _hud: RaceHud
var _menu: PauseMenu
var _net: NetSession
var _net_stats: NetStats = NetStats.new()
var _ranking: RaceRanking
var _mode: Mode = Mode.SOLO
var _racers: Array[Racer] = []
var _by_id: Dictionary = {}
var _cli_net: bool = false
var _want_players: int = 0
var _lobby_timer: float = 0.0
var _send_accum: float = 0.0
var _over_time: float = 0.0
var _summary_printed: bool = false
var _lead_seq: Array[int] = []
var _log_accum: float = 0.0
var _log_file: FileAccess
var _bw_out: float = 0.0
var _bw_in: float = 0.0


## The 3-2-1 countdown and start result (read by the HUD and the debug harness).
var start_sequence: StartSequence:
	get:
		return _start


## True while an online race is running (the debug harness leaves quitting to Main then).
var net_active: bool:
	get:
		return _mode == Mode.NET_RACE


func _ready() -> void:
	InputActions.register()
	var args: PackedStringArray = OS.get_cmdline_user_args()
	_options = DebugOptions.parse(args)
	_net_opts = NetOptions.parse(args)
	if _net_opts.port > 0:
		net_config = net_config.duplicate()
		net_config.port = _net_opts.port
	_track = TrackModel.new(track_data)
	_local = Racer.new()
	_local.sim = KartSim.new(vehicle_stats)
	_local.laps = LapCounter.new(_laps_for_race(), _track.length)
	if _options.ram:
		var ram := RamDriver.new()
		ram.target_fn = _nearest_other_position
		_local.driver = ram
	elif _options.park:
		_local.driver = KartDriver.new()
	else:
		_local.driver = AutopilotDriver.new() if _options.autopilot else PlayerInputDriver.new()
	_sim = _local.sim
	_sim.kart_bumped.connect(func(_strength: float) -> void: bump_count += 1)
	_laps = _local.laps
	_start = _local.start
	_input = _local.input
	_racers.append(_local)
	_ranking = RaceRanking.new(net_config.rank_debounce, net_config.rank_pass_margin)
	_ranking.lead_changed.connect(func(new_leader: int, _old: int) -> void: _lead_seq.append(new_leader))
	_build_environment()
	var mesh := TrackMesh.new()
	add_child(mesh)
	mesh.build(_track)
	_local.visual = _make_visual(_sim)
	_camera = ChaseCamera.new()
	_camera.far = 1500.0
	add_child(_camera)
	_hud = RaceHud.new()
	add_child(_hud)
	_menu = PauseMenu.new()
	add_child(_menu)
	_menu.resume_requested.connect(_resume)
	_menu.restart_requested.connect(_restart)
	_menu.quit_requested.connect(func() -> void: get_tree().quit())
	_menu.menu_requested.connect(_back_to_menu)
	_menu.host_requested.connect(_on_menu_host)
	_menu.join_requested.connect(_on_menu_join)
	_net = NetSession.new()
	_net.name = &"NetSession"
	add_child(_net)
	_net.setup(net_config, _net_opts.lag_ms, _net_opts.jitter_ms, _net_opts.loss_pct)
	_net.race_clock = func() -> float: return race_time
	_net.race_active = func() -> bool: return _mode == Mode.NET_RACE
	_net.peer_joined.connect(_on_peer_joined)
	_net.peer_left.connect(_on_peer_left)
	_net.connected_to_host.connect(_on_connected_to_host)
	_net.connection_failed.connect(func() -> void: _leave_network("Could not connect to the host."))
	_net.host_lost.connect(func() -> void: _leave_network("Lost the connection to the host."))
	_net.race_start_received.connect(_on_race_start_received)
	_net.state_received.connect(_on_state_received)
	_net.pong_received.connect(_on_pong)
	_net.bump_received.connect(_on_bump_received)
	_laps.finished.connect(func(total: float) -> void: race_finished.emit(total))
	_reset_race()
	_camera.follow(_sim)
	if _options.needs_harness():
		var harness := DebugHarness.new()
		add_child(harness)
		harness.setup(_options, self, _sim, _laps)
	if _options.time_scale > 0.0:
		Engine.time_scale = _options.time_scale
	_cli_net = _net_opts.host or _net_opts.join != ""
	if _cli_net:
		get_tree().paused = false
		if _net_opts.host:
			_begin_hosting(_net_opts.players)
		else:
			_begin_joining(_net_opts.join)
	elif _options.autopilot:
		get_tree().paused = false
	else:
		_open_menu("Dogworks Racing: Kennel Kingdom", true)


## True while the start or pause menu is showing.
func menu_is_open() -> bool:
	return _menu.is_open()


func _physics_process(dt: float) -> void:
	match _mode:
		Mode.SOLO:
			if _tick_owned(_local, dt, false):
				race_time += dt
				_laps.update(_sim.track_s, race_time)
		Mode.NET_RACE:
			_net_tick(dt)


func _process(delta: float) -> void:
	if _mode == Mode.HOST_LOBBY and _want_players > 0 \
			and _net.peer_ids().size() + 1 >= _want_players:
		_lobby_timer += delta
		if _lobby_timer >= net_config.start_delay:
			_host_begin_race()
	else:
		_lobby_timer = 0.0
	_hud.refresh(_sim, _laps, race_time, _start, _mode == Mode.SOLO)
	if _mode == Mode.NET_RACE:
		_hud.show_place(_ranking.place_of(_local.kart_id), _ranking.count())
		_hud.set_net_info("rtt %d ms   view delay %d ms   karts %d" % [
				int(_net_stats.rtt * 1000.0), int(_net_stats.view_delay * 1000.0), _racers.size()])


func _unhandled_input(event: InputEvent) -> void:
	if _mode == Mode.SOLO and _laps.is_finished and (event.is_action_pressed(InputActions.RESTART) \
			or event.is_action_pressed(&"ui_accept")):
		# Finish screen: Start / A / Enter restarts. No restart key during a race.
		_restart()
	elif event.is_action_pressed(InputActions.PAUSE) and not _menu.is_open():
		_open_menu("Paused", false)


# ---------------------------------------------------------------- ticking

# Runs one owned kart for a tick. Returns true when the kart was past GO (a driving tick).
# [param synced] makes the countdown follow the synced race clock instead of its own timer.
func _tick_owned(r: Racer, dt: float, synced: bool) -> bool:
	var start: StartSequence = r.start
	if synced and start.is_counting():
		# race_time was already advanced for this tick; update() subtracts dt again.
		start.time_to_go = maxf(dt - race_time, 0.0)
	r.driver.time_to_go = start.time_to_go if start.is_counting() else 0.0
	r.driver.drive(r.input, r.sim, _track, dt)
	if r.laps.is_finished:
		r.input.clear()
	if start.is_counting():
		# The kart is held during the countdown; only whether accelerate is down matters.
		var held: bool = r.input.throttle > 0.0
		r.input.clear()
		if not start.update(dt, held):
			r.sim.tick(dt, r.input, _track)
			return false
		r.sim.apply_start(start.level, start.stalled)
	else:
		start.update(dt, false)
	r.sim.tick(dt, r.input, _track)
	return true


func _net_tick(dt: float) -> void:
	race_time += dt
	var keys: Dictionary = {}
	for r in _racers:
		if r.dropped:
			# A kart whose player left after finishing keeps its place in the results.
			if r.is_finished():
				keys[r.kart_id] = _rank_key(r)
			continue
		if r.owned:
			if _tick_owned(r, dt, true):
				r.laps.update(r.sim.track_s, race_time)
		else:
			r.remote.update_view(race_time)
		keys[r.kart_id] = _rank_key(r)
	_ranking.update(dt, keys)
	_resolve_kart_contacts()
	_separate_remote_karts()
	_measure_contacts()
	_send_accum += dt
	var interval: float = 1.0 / net_config.send_hz
	if _send_accum >= interval:
		_send_accum = fmod(_send_accum, interval)
		for r in _racers:
			if r.owned and not r.dropped:
				_net.send_state(r.kart_id, race_time, KartWire.pack(r.sim, r.laps))
	_net_log_tick(dt)
	_finish_check(dt)


# Kart-to-kart bumping: each PC pushes only the karts it owns (its player, and the host's
# bots) out of every other kart it can see; remote karts move through their owner's updates.
# Debug measurement of what this PC shows: the deepest overlap between any two karts,
# frames with karts touching, frames with a deep overlap (> 0.25 m), and the local knock.
func _measure_contacts() -> void:
	_had_net_race = true
	if _race_frames == 0:
		_bump_start = _sim.position
	_race_frames += 1
	_knock_max = maxf(_knock_max, _sim.knock.length())
	var touching: bool = false
	var deep: bool = false
	var remote_deep: bool = false
	for i in _racers.size():
		var a: Racer = _racers[i]
		if a.dropped:
			continue
		for j in range(i + 1, _racers.size()):
			var b: Racer = _racers[j]
			if b.dropped:
				continue
			var gap: float = KartSim.body_gap(a.sim, b.sim)
			if gap < 0.02:
				touching = true
			if gap < 0.0:
				_pen_max = maxf(_pen_max, -gap)
				if a.owned or b.owned:
					_pen_max_owned = maxf(_pen_max_owned, -gap)
				else:
					_pen_max_remote = maxf(_pen_max_remote, -gap)
					if -gap > 0.25:
						remote_deep = true
				if -gap > 0.25:
					deep = true
	if touching:
		_contact_frames += 1
	if deep:
		_deep_frames += 1
	if remote_deep:
		_deep_remote_frames += 1


# Debug (--ram): the nearest other kart's position, humans before bots; null if none.
func _nearest_other_position() -> Variant:
	var best: Variant = null
	var best_d: float = INF
	for pass_bots in [false, true]:
		for r in _racers:
			if r == _local or r.dropped or r.is_bot != pass_bots:
				continue
			var d: float = r.sim.position.distance_to(_sim.position)
			if d < best_d:
				best_d = d
				best = r.sim.position
		if best != null:
			return best
	return best


func _exit_tree() -> void:
	_print_bump_summary()


# Debug: prints the [bump-summary] line once per run (before a reset can hide the numbers).
func _print_bump_summary() -> void:
	if _had_net_race and not _bump_summary_done:
		_bump_summary_done = true
		print("[bump-summary] role=%s frames=%d contact_frames=%d deep_frames=%d pen_max=%.3fm (own-vs-any %.3fm, remote-vs-remote %.3fm, deep remote frames %d) bumps=%d knock_max=%.2fm/s moved=%.2fm" % [
				_role(), _race_frames, _contact_frames, _deep_frames, _pen_max, _pen_max_owned, _pen_max_remote, _deep_remote_frames, bump_count,
				_knock_max, _sim.position.distance_to(_bump_start)])


func _resolve_kart_contacts() -> void:
	for r in _racers:
		if not r.owned or r.dropped:
			continue
		for o in _racers:
			if o == r or o.dropped:
				continue
			var other_push: float = o.sim.stats.bump_push_mult
			if o.is_bot and not r.is_bot:
				other_push *= net_config.bot_push_mult
			var my_push: float = r.sim.stats.bump_push_mult
			if r.is_bot and not o.is_bot:
				my_push *= net_config.bot_push_mult
			var to_other: Vector2 = r.sim.resolve_kart_contact(o.sim, o.kart_id, other_push, my_push, not o.owned)
			if to_other != Vector2.ZERO and not o.owned:
				# The other kart's PC sees this contact late (or not at all): tell it.
				_net.send_bump(o.owner_peer, o.kart_id, r.kart_id, to_other, r.sim.last_bump_strength)


# Display only: two remote karts drawn inside each other are moved apart (see
# KartSim.separate_for_display). Runs after their views are updated for this tick.
func _separate_remote_karts() -> void:
	for i in _racers.size():
		var a: Racer = _racers[i]
		if a.owned or a.dropped:
			continue
		for j in range(i + 1, _racers.size()):
			var b: Racer = _racers[j]
			if b.owned or b.dropped:
				continue
			KartSim.separate_for_display(a.sim, b.sim)


# Another PC detected a bump on a kart this PC owns.
func _on_bump_received(kart_id: int, from_kart: int, impulse: Vector2, strength: float) -> void:
	var r: Racer = _by_id.get(kart_id)
	if r != null and r.owned and not r.dropped and _mode == Mode.NET_RACE:
		r.sim.apply_received_bump(from_kart, impulse, strength)


func _rank_key(r: Racer) -> float:
	if r.is_finished():
		# Equal finish times tie-break by kart id so every PC orders them the same way.
		return RaceRanking.FINISHED_BASE - r.finish_time() - float(r.kart_id) * 0.0001
	if r.owned:
		return float(r.laps.lap - 1) * _track.length + r.sim.track_s
	return r.remote.projected_progress(race_time, _track.length)


func _finish_check(dt: float) -> void:
	if not _laps.is_finished:
		return
	_over_time += dt
	var humans_done: bool = true
	for r in _racers:
		if not r.is_bot and not r.dropped and not r.is_finished():
			humans_done = false
	var done: bool = (humans_done and _over_time > net_config.finish_linger) \
			or _over_time > net_config.finish_timeout
	if done and not _summary_printed:
		_print_summary()
	if done and _options.quit_after_race:
		get_tree().quit()


# ---------------------------------------------------------------- menu and lobby flow

func _open_menu(title: String, start_screen: bool) -> void:
	if _mode == Mode.SOLO:
		get_tree().paused = true
	_menu.open(title, start_screen)
	_menu.set_restart_visible(_mode == Mode.SOLO)


func _resume() -> void:
	if _mode == Mode.HOST_LOBBY:
		_host_begin_race()
		return
	_menu.close()
	get_tree().paused = false


func _restart() -> void:
	if _mode != Mode.SOLO:
		return
	_menu.close()
	get_tree().paused = false
	_reset_race()
	_camera.snap()


# Back to the start screen: leaves an online race or lobby, or abandons a solo race.
func _back_to_menu() -> void:
	if _mode == Mode.SOLO:
		get_tree().paused = false
		_reset_race()
		_camera.snap()
		_open_menu("Dogworks Racing: Kennel Kingdom", true)
	else:
		_leave_network("")


func _on_menu_host() -> void:
	_begin_hosting(0)


func _on_menu_join(address: String) -> void:
	_begin_joining(address)


func _begin_hosting(want_players: int) -> void:
	_want_players = want_players
	var err: Error = _net.host()
	if err != OK:
		_show_lobby_text("Could not host on port %d (error %d)." % [net_config.port, err])
		return
	_mode = Mode.HOST_LOBBY
	_lobby_timer = 0.0
	_hud.set_lobby(true)
	_menu.set_net_buttons_visible(false)
	_menu.set_primary_button("Start race", true)
	_refresh_host_text()


func _begin_joining(address: String) -> void:
	var err: Error = _net.join(address)
	if err != OK:
		_show_lobby_text("Could not join %s (error %d)." % [address, err])
		return
	_mode = Mode.CLIENT_LOBBY
	_hud.set_lobby(true)
	_menu.set_net_buttons_visible(false)
	_menu.set_primary_button("Start", false)
	_show_lobby_text("Connecting to %s ..." % address)


func _refresh_host_text() -> void:
	var count: int = _net.peer_ids().size() + 1
	var text: String = "Hosting on UDP %d: %d player(s) joined" % [net_config.port, count]
	if _want_players > 0:
		text += " (starting at %d)" % _want_players
	_show_lobby_text(text)


func _show_lobby_text(text: String) -> void:
	_hud.set_banner(text)
	_menu.set_status(text)


func _on_connected_to_host() -> void:
	_show_lobby_text("Connected. Waiting for the host to start.")


func _on_peer_joined(id: int) -> void:
	if not _net.is_host():
		return
	if _mode == Mode.HOST_LOBBY:
		_refresh_host_text()
	else:
		_net.kick(id)


func _on_peer_left(id: int) -> void:
	if _mode == Mode.HOST_LOBBY:
		_refresh_host_text()
		return
	if _mode != Mode.NET_RACE:
		return
	for r in _racers:
		if not r.is_bot and r.owner_peer == id and r != _local and not r.dropped:
			r.dropped = true
			if r.visual != null:
				r.visual.queue_free()
				r.visual = null
			if r.is_finished():
				print("[net] peer %d left after finishing; kart %d keeps its place" % [id, r.kart_id])
			else:
				_ranking.remove(r.kart_id)
				print("[net] peer %d left; kart %d removed" % [id, r.kart_id])


# Back to the offline start menu (host lost, connect failed, version mismatch).
func _leave_network(message: String) -> void:
	print("[net] leaving network: %s" % message)
	if _mode == Mode.NET_RACE and not _summary_printed:
		_print_summary()
	_print_bump_summary()
	var was_cli: bool = _cli_net
	_net.close()
	_clear_others()
	_mode = Mode.SOLO
	_hud.set_lobby(false)
	_hud.set_banner("")
	_hud.show_place(0, 0)
	_hud.set_net_info("")
	if was_cli and _options.quit_after_race:
		get_tree().quit()
		return
	_laps.lap_target = _laps_for_race()
	_reset_race()
	_camera.snap()
	_open_menu("Dogworks Racing: Kennel Kingdom", true)
	_menu.set_status(message)


# ---------------------------------------------------------------- starting a networked race

func _host_begin_race() -> void:
	var peers: Array[int] = _net.peer_ids()
	peers.sort()
	var slots: Array = [[0, 1, "Player 1", false]]
	var next_id: int = 1
	for p in peers:
		slots.append([next_id, p, "Player %d" % (next_id + 1), false])
		next_id += 1
	var bots: int = _net_opts.bots if _net_opts.bots >= 0 else net_config.default_bots
	bots = clampi(bots, 0, net_config.max_racers - slots.size())
	for b in bots:
		slots.append([next_id, 1, "Bot %d" % (b + 1), true])
		next_id += 1
	var info: Dictionary = {
		"version": KartWire.VERSION,
		"slots": slots,
		"laps": _laps_for_race(),
		"host_time": -vehicle_stats.start_countdown_time,
	}
	_net.broadcast_race_start(info)
	_apply_race_start(info)


func _on_race_start_received(info: Dictionary) -> void:
	if _net.is_host() or _mode == Mode.NET_RACE:
		return
	if int(info.get("version", -1)) != KartWire.VERSION:
		_leave_network("The host runs a different network version.")
		return
	_apply_race_start(info)


# Builds every racer from the host's slot list and starts the synced countdown.
func _apply_race_start(info: Dictionary) -> void:
	_clear_others()
	var my_id: int = _net.my_id()
	var laps_n: int = int(info.laps)
	var slots: Array = info.slots
	var ids: Array[int] = []
	_laps.lap_target = laps_n
	for slot: Array in slots:
		var kart_id: int = slot[0]
		var peer: int = slot[1]
		var is_bot: bool = slot[3]
		var dist: float = _track.length - track_data.start_distance_behind_line \
				- float(kart_id / 2) * net_config.grid_row_spacing
		var lateral: float = net_config.grid_lateral * (1.0 if kart_id % 2 == 0 else -1.0)
		ids.append(kart_id)
		if not is_bot and peer == my_id:
			_local.kart_id = kart_id
			_local.owner_peer = peer
			_local.display_name = slot[2]
			_local.dropped = false
			# Same color for this kart on every PC: its slot's palette color.
			_local.visual.set_paint(_stats_for(kart_id).paint_color)
			_sim.reset_to(_track, dist, lateral)
			_laps.reset(_sim.track_s)
			_input.clear()
			_start.begin(vehicle_stats)
			_by_id[kart_id] = _local
			continue
		var r := Racer.new()
		r.kart_id = kart_id
		r.owner_peer = peer
		r.display_name = slot[2]
		r.is_bot = is_bot
		var stats: VehicleStats = _stats_for(kart_id)
		if is_bot and _net.is_host():
			r.owned = true
			r.sim = KartSim.new(stats)
			r.driver = BotDriver.new()
			r.laps = LapCounter.new(laps_n, _track.length)
			r.sim.reset_to(_track, dist, lateral)
			r.laps.reset(r.sim.track_s)
			r.start.begin(stats)
		else:
			r.owned = false
			r.remote = RemoteKart.new(stats, net_config, _net_stats)
			r.sim = r.remote
			r.remote.reset_to(_track, dist, lateral)
			r.remote.clear_snapshots()
		r.visual = _make_visual(r.sim)
		_racers.append(r)
		_by_id[kart_id] = r
	_ranking.reset(ids)
	_lead_seq = [_ranking.leader()]
	_net_stats.reset_race()
	_send_accum = 0.0
	_over_time = 0.0
	_summary_printed = false
	_log_accum = 0.0
	_bw_out = 0.0
	_bw_in = 0.0
	_open_log()
	race_time = float(info.host_time)
	if not _net.is_host():
		race_time += _net_stats.rtt * 0.5
	_mode = Mode.NET_RACE
	_hud.set_lobby(false)
	_hud.set_banner("")
	_menu.close()
	get_tree().paused = false
	_camera.snap()
	print("[net] race start: %d karts, %d laps, role=%s peer=%d kart=%d" % [
			slots.size(), laps_n, _role(), my_id, _local.kart_id])


func _clear_others() -> void:
	for r in _racers:
		if r != _local and r.visual != null:
			r.visual.queue_free()
	_racers = [_local]
	_local.visual.set_paint(vehicle_stats.paint_color)
	_by_id.clear()
	_by_id[_local.kart_id] = _local


func _stats_for(kart_id: int) -> VehicleStats:
	var s: VehicleStats = vehicle_stats.duplicate()
	if not net_config.kart_colors.is_empty():
		s.paint_color = net_config.kart_colors[kart_id % net_config.kart_colors.size()]
	return s


func _make_visual(sim: KartSim) -> KartVisual:
	var v := KartVisual.new()
	add_child(v)
	v.bind(sim)
	return v


func _laps_for_race() -> int:
	return _net_opts.laps if _net_opts.laps > 0 else track_data.lap_count


# ---------------------------------------------------------------- incoming network data

func _on_state_received(kart_id: int, t: float, d: PackedFloat32Array) -> void:
	if _mode != Mode.NET_RACE:
		return
	var r: Racer = _by_id.get(kart_id)
	if r == null or r.owned or r.dropped:
		return
	r.remote.push_snapshot(t, d, race_time)


func _on_pong(host_race_time: float, host_active: bool, rtt_sample: float) -> void:
	_net_stats.record_rtt(rtt_sample, net_config)
	if _mode == Mode.NET_RACE and host_active:
		# Keep the race clock close to the host's (host time + half the round trip).
		var target: float = host_race_time + rtt_sample * 0.5
		if absf(race_time - target) > net_config.clock_correct_threshold:
			race_time = lerpf(race_time, target, net_config.clock_correct_rate)


# ---------------------------------------------------------------- net log and summary

func _role() -> String:
	if _mode == Mode.SOLO:
		return "solo"
	return "host" if _net.is_host() else "client"


func _open_log() -> void:
	_log_file = null
	if _net_opts.netlog_path == "":
		return
	DirAccess.make_dir_recursive_absolute(_net_opts.netlog_path.get_base_dir())
	_log_file = FileAccess.open(_net_opts.netlog_path, FileAccess.WRITE)
	if _log_file == null:
		printerr("[net] cannot open netlog ", _net_opts.netlog_path)
		return
	_log_file.store_line("wall_time,role,peer,race_time,rtt_ms,lag_ms,jitter_ms,loss_pct,snaps_per_s,extrap_pct,pred_err_avg_m,pred_err_max_m,view_delay_ms,kb_out,kb_in,fps")


func _net_log_tick(dt: float) -> void:
	_log_accum += dt
	if _log_accum < net_config.log_interval:
		return
	_log_accum -= net_config.log_interval
	var w: Dictionary = _net_stats.close_window()
	var bw: Vector2 = _net.pop_bandwidth()
	_bw_out += bw.x
	_bw_in += bw.y
	_net_stats.race_seconds += 1
	if _log_file != null:
		_log_file.store_line("%.1f,%s,%d,%.2f,%d,%d,%d,%d,%d,%.1f,%.3f,%.3f,%d,%.1f,%.1f,%d" % [
				Time.get_unix_time_from_system(), _role(), _net.my_id(), race_time,
				int(_net_stats.rtt * 1000.0), int(_net_opts.lag_ms), int(_net_opts.jitter_ms),
				int(_net_opts.loss_pct), w.snaps, w.extrap_pct, w.err_avg, w.err_max,
				int(_net_stats.view_delay * 1000.0), bw.x / 1024.0, bw.y / 1024.0,
				int(Engine.get_frames_per_second())])
		_log_file.flush()


func _print_summary() -> void:
	_summary_printed = true
	var s: NetStats = _net_stats
	var secs: float = maxf(float(s.race_seconds), 1.0)
	var seq: PackedStringArray = PackedStringArray()
	for id in _lead_seq:
		seq.append(str(id))
	print("[net-summary] role=%s peer=%d place=%d finish=%.2f karts=%d | rtt_avg=%dms rtt_max=%dms view_delay=%dms | snaps/s=%.1f | extrap=%.1f%% | pred_err avg=%.3fm max=%.3fm | lag=%d jitter=%d loss=%d%% | lead_changes=%d lead_seq=%s | kb_out/s=%.1f kb_in/s=%.1f" % [
			_role(), _net.my_id(), _ranking.place_of(_local.kart_id),
			_laps.finish_race_time if _laps.is_finished else -1.0, _racers.size(),
			int(s.rtt_sum / maxf(float(s.rtt_n), 1.0) * 1000.0), int(s.rtt_max * 1000.0),
			int(s.view_delay * 1000.0), s.race_snaps / secs,
			100.0 * s.race_extrap / maxf(float(s.race_frames), 1.0),
			s.race_err_sum / maxf(float(s.race_err_n), 1.0), s.race_err_max,
			int(_net_opts.lag_ms), int(_net_opts.jitter_ms), int(_net_opts.loss_pct),
			_lead_seq.size() - 1, ">".join(seq), _bw_out / 1024.0 / secs, _bw_in / 1024.0 / secs])


# ---------------------------------------------------------------- offline race and scenery

func _reset_race() -> void:
	_sim.reset_to(_track, _track.length - track_data.start_distance_behind_line, 0.0)
	_laps.reset(_sim.track_s)
	_input.clear()
	race_time = 0.0
	_start.begin(vehicle_stats)


func _build_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.25, 0.5, 0.9)
	sky_mat.sky_horizon_color = Color(0.7, 0.82, 0.95)
	sky_mat.ground_horizon_color = Color(0.5, 0.6, 0.45)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 40, 0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 120.0
	add_child(sun)
	var center: Vector2 = Vector2.ZERO
	for c in track_data.control_points:
		center += c
	center /= track_data.control_points.size()
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(700, 700)
	ground.mesh = pm
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.32, 0.55, 0.25)
	ground.material_override = gmat
	ground.position = Vector3(center.x, -0.05, center.y)
	add_child(ground)
