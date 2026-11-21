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

## Handling data of the default vehicle (the armored cart); the full list is VEHICLE_SET_PATH.
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
var _world: Node3D
var _debug_cam: Camera3D
var _grid_shot_done: bool = false
var _grid_shot_timer: float = 0.0
var _local: Racer
var _sim: KartSim
var _input: KartInput
var _laps: LapCounter
var _start: StartSequence
var _camera: ChaseCamera
var _hud: RaceHud
var _ui: RaceFlowUi
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
# Per-second performance window for the netlog (story 006 perf pass): worst real frame time and
# worst process / physics times seen since the last log row.
var _perf_last_us: int = 0
var _perf_frame_max_us: int = 0
var _perf_proc_max_ms: float = 0.0
var _perf_phys_max_ms: float = 0.0
var _items: ItemManager
## Sound (story 007 part 2): the director plays everything; RaceSound maps race moments to it.
const AUDIO_SET_PATH: String = "res://assets/data/audio/audio_set.tres"
var _audio: AudioDirector
var _race_sound: RaceSound
# Reused per frame for the minimap (no allocation per frame).
var _map_pos: PackedVector2Array = PackedVector2Array()
var _map_yaw: PackedFloat32Array = PackedFloat32Array()
var _map_col: PackedColorArray = PackedColorArray()

## Item data (story 004): five items, odds table, box timings.
const ITEM_SET_PATH: String = "res://assets/data/items/item_set.tres"
## Bot AI data (story 005): personalities, names, rubber band, traffic, stuck and item tuning.
const BOT_SET_PATH: String = "res://assets/data/ai/bot_set.tres"
var _bot_set: BotSet
## Vehicles (cart, bike) and the eight dogs (story 006), plus the pennant look.
const VEHICLE_SET_PATH: String = "res://assets/data/vehicles/vehicle_set.tres"
const RACER_SET_PATH: String = "res://assets/data/racers/racer_set.tres"
var _vehicle_set: VehicleSet
var _racer_set: RacerSet
## This PC's choice: x = racer index, y = vehicle index (from --racer= and --vehicle= until the pick screen).
var _my_loadout: Vector2i = Vector2i.ZERO
## Host: loadouts clients reported, by peer id.
var _peer_loadouts: Dictionary = {}
## Host: a start was requested but a client's loadout is still missing (see NetConfig.loadout_wait).
var _begin_pending: bool = false
var _begin_requested_ms: int = -1
## Menu-driven online flow (lobby screen, results screen); false for the --host / --join command line paths.
var _ui_flow: bool = false
## Results screens are shown (not for the --autopilot / --host / --join command line paths).
var _results_enabled: bool = false
var _results_open: bool = false
var _solo_results_timer: float = 0.0
## Lobby state: the host's own copy (host) or the last one received (client).
var _lobby: LobbyState = LobbyState.new()
## Host: ready marks clients reported, by peer id.
var _peer_ready: Dictionary = {}
## Loadout (x racer, y vehicle) of every kart of the current race, by kart id (for the results).
var _kart_loadouts: Dictionary = {}
## What the local kart's stats and visual are built for (a lobby pick may differ until the race starts).
var _built_loadout: Vector2i = Vector2i.ZERO
var _joining_address: String = ""
## Kart id the local Racer carries while spectating (no kart of the race has it).
const SPECTATOR_KART_ID: int = -1
## Controls file loaded at start and saved by the controls screen (--controls-file= overrides).
var _controls_path: String = InputBindings.DEFAULT_PATH
## Host: the start info of the race running now (sent to late joiners with "spectate").
var _race_info: Dictionary = {}
## Host: the results last published (a joiner who arrives on the results screen gets them).
var _last_results: Array = []
## Host: peers that joined during the current race and watch it; they race the next one.
var _spectators: Dictionary = {}
## Client: this PC watches the running race (no own kart) and joins the next round.
var _spectating: bool = false
## Spectator: the place the camera follows (1 = the leader); steer left / right change it.
var _spec_place: int = 1
var _spec_target: int = -2
var _spec_follow_key: String = ""
var _spec_follow_text: String = ""
var _spec_time: float = 0.0
var _spec_shots: int = 0


## The 3-2-1 countdown and start result (read by the HUD and the debug harness).
var start_sequence: StartSequence:
	get:
		return _start


## The item system (read by the debug harness).
var items: ItemManager:
	get:
		return _items


## Kart id of this PC's kart (debug shots).
var local_kart_id: int:
	get:
		return _local.kart_id


## True while an online race is running (the debug harness leaves quitting to Main then).
var net_active: bool:
	get:
		return _mode == Mode.NET_RACE


func _ready() -> void:
	InputActions.register()
	var args: PackedStringArray = OS.get_cmdline_user_args()
	_options = DebugOptions.parse(args)
	if _options.controls_file != "":
		_controls_path = _options.controls_file
	var loaded: int = InputBindings.load_saved(_controls_path)
	if loaded > 0:
		print("[controls] loaded %d action binding(s) from %s" % [loaded, _controls_path])
	_net_opts = NetOptions.parse(args)
	if _net_opts.port > 0:
		net_config = net_config.duplicate()
		net_config.port = _net_opts.port
	var wanted_id: String = _options.track_id if _options.track_id != "" else TrackLibrary.DEFAULT_ID
	var chosen: TrackData = TrackLibrary.load_track(wanted_id)
	if chosen == null:
		push_warning("Unknown track '%s'; using %s." % [wanted_id, TrackLibrary.DEFAULT_ID])
		chosen = TrackLibrary.load_track(TrackLibrary.DEFAULT_ID)
	if chosen != null:
		track_data = chosen
	_track = TrackModel.new(track_data)
	if _camera != null:
		_camera.track = _track
	_load_rosters()
	_local = Racer.new()
	_local.sim = KartSim.new(_stats_for(_my_loadout.y, 0))
	_local.laps = LapCounter.new(_laps_for_race(), _track.length, _track.checkpoint_s)
	if _options.ram:
		var ram := RamDriver.new()
		ram.target_fn = _nearest_other_position
		_local.driver = ram
	elif _options.park:
		_local.driver = KartDriver.new()
	else:
		if _options.autopilot:
			var ap := AutopilotDriver.new()
			ap.shortcut_id = StringName(_options.shortcut)
			ap.dunk_s = _options.dunk_s
			_local.driver = ap
		else:
			_local.driver = PlayerInputDriver.new()
	_sim = _local.sim
	_sim.kart_bumped.connect(func(_strength: float) -> void: bump_count += 1)
	_laps = _local.laps
	_start = _local.start
	_input = _local.input
	_racers.append(_local)
	_ranking = RaceRanking.new(net_config.rank_debounce, net_config.rank_pass_margin)
	_ranking.lead_changed.connect(func(new_leader: int, _old: int) -> void: _lead_seq.append(new_leader))
	_build_world()
	_local.visual = _make_visual(_sim, _my_loadout.x, 0)
	_camera = ChaseCamera.new()
	_camera.far = 1500.0
	add_child(_camera)
	_ui = RaceFlowUi.new()
	add_child(_ui)
	_ui.setup(_racer_set, _vehicle_set, net_config.kart_colors, net_config.max_racers)
	_ui.controls.save_path = _controls_path if _options.ui_shot == "" else ""
	_hud = RaceHud.new()
	add_child(_hud)
	_hud.setup(_ui.theme_data)
	_hud.set_track(_track)
	_setup_audio()
	_wire_ui()
	_net = NetSession.new()
	_net.name = &"NetSession"
	add_child(_net)
	_net.setup(net_config, _net_opts.lag_ms, _net_opts.jitter_ms, _net_opts.loss_pct)
	if _net_opts.version_override > 0:
		_net.advertised_version = _net_opts.version_override
		print("[net] version check uses %d instead of %d (--net-version-override)" % [
				_net_opts.version_override, KartWire.VERSION])
	_net.handshake_failed.connect(_on_handshake_failed)
	_net.race_clock = func() -> float: return race_time
	_net.race_active = func() -> bool: return _mode == Mode.NET_RACE
	_net.peer_joined.connect(_on_peer_joined)
	_net.peer_left.connect(_on_peer_left)
	_net.connected_to_host.connect(_on_connected_to_host)
	_net.connection_failed.connect(func() -> void: _leave_network("Could not connect to the host."))
	_net.host_lost.connect(func() -> void: _leave_network("Lost the connection to the host."))
	_net.race_start_received.connect(_on_race_start_received)
	_net.state_received.connect(_on_state_received)
	_net.loadout_received.connect(_on_loadout_received)
	_net.lobby_state_received.connect(_on_lobby_state_received)
	_net.lobby_pick_received.connect(_on_lobby_pick_received)
	_net.race_results_received.connect(_on_race_results_received)
	_net.pong_received.connect(_on_pong)
	_net.bump_received.connect(_on_bump_received)
	_laps.finished.connect(func(total: float) -> void: race_finished.emit(total))
	_items = ItemManager.new()
	_items.name = &"ItemManager"
	add_child(_items)
	var item_set: ItemSet = load(ITEM_SET_PATH) as ItemSet
	_items.setup(item_set, func() -> Array: return _racers, func() -> Racer: return _local,
			func(id: int) -> int: return _ranking.place_of(id),
			func(place: int) -> int: return _ranking.id_at_place(place),
			func() -> bool: return _mode == Mode.NET_RACE, _net)
	_items.sound_cue.connect(_on_item_sound_cue)
	_bot_set = load(BOT_SET_PATH) as BotSet
	if _bot_set == null:
		push_error("Bot data missing: %s" % BOT_SET_PATH)
		_bot_set = BotSet.new()
	elif _bot_set.validate() != "":
		push_warning(_bot_set.validate())
	_items.debug_give = -2 if _options.give_item == "all" else (item_set.index_of(StringName(_options.give_item)) if _options.give_item != "" else -1)
	_items.auto_interval = _options.item_interval if _options.autopilot else 0.0
	_items.debug_box_check = _options.autopilot
	if "--bot-labels" in args or "--bot-shots=" in " ".join(args) or "--bot-cam=" in " ".join(args):
		var bd := BotDebug.new()
		add_child(bd)
		bd.setup(func() -> Array: return _racers, _items, args)
	_reset_race()
	_camera.track = _track
	_camera.follow(_sim)
	if _options.needs_harness():
		var harness := DebugHarness.new()
		add_child(harness)
		harness.setup(_options, self, _sim, _laps)
	if _options.time_scale > 0.0:
		Engine.time_scale = _options.time_scale
	_cli_net = _net_opts.host or _net_opts.join != ""
	_results_enabled = not _cli_net and (not _options.autopilot or _options.auto_ui != "")
	_built_loadout = _my_loadout
	if _options.ui_shot != "":
		_run_ui_shot()
		return
	if _options.auto_ui != "":
		var auto := AutoUiDriver.new()
		add_child(auto)
		auto.setup(_options, _ui)
		auto.spectating_fn = func() -> bool: return _spectating
	if _options.overview_shot:
		_run_overview_shot()
		return
	if _options.lineup_dir != "":
		_run_lineup()
		return
	if _cli_net:
		get_tree().paused = false
		if _net_opts.host:
			_begin_hosting(_net_opts.players)
		else:
			_begin_joining(_net_opts.join)
	elif _options.autopilot and _options.auto_ui == "":
		get_tree().paused = false
	else:
		_show_main_menu("")


## True while the main menu, lobby, results or pause menu is showing.
func menu_is_open() -> bool:
	return _ui.any_open()


func _physics_process(dt: float) -> void:
	match _mode:
		Mode.SOLO:
			if _tick_owned(_local, dt, false):
				race_time += dt
				_laps.update(_sim.track_s, race_time)
			_items.update(dt, race_time)
		Mode.NET_RACE:
			_net_tick(dt)


func _process(delta: float) -> void:
	_perf_sample()
	if _begin_pending and (_mode == Mode.HOST_LOBBY or _results_open):
		_host_begin_race()
	_solo_results_tick(delta)
	if _mode == Mode.HOST_LOBBY and _want_players > 0 \
			and _net.peer_ids().size() + 1 >= _want_players:
		_lobby_timer += delta
		if _lobby_timer >= net_config.start_delay:
			_host_begin_race()
	else:
		_lobby_timer = 0.0
	_hud.refresh(_sim, _laps, race_time, _start, _mode == Mode.SOLO)
	_hud.set_item(_items.hud_icon())
	_update_minimap()
	var racing: bool = (_mode == Mode.SOLO or _mode == Mode.NET_RACE) and not get_tree().paused 			and not _ui.flow_open()
	_race_sound.update(_racers, _local, _start, _track, racing)
	if _debug_cam != null and not _grid_shot_done and _start.is_counting():
		_grid_shot_timer += delta
		if _grid_shot_timer > 1.5:
			_grid_shot_done = true
			_debug_save("grid")
	if _spectating:
		_spectate_tick(delta)
	if _mode == Mode.NET_RACE:
		_hud.show_place(_ranking.place_of(_spec_target if _spectating else _local.kart_id), _ranking.count())
		var net_line: String = "rtt %d ms   view delay %d ms   karts %d" % [
				int(_net_stats.rtt * 1000.0), int(_net_stats.view_delay * 1000.0), _racers.size() - (1 if _spectating else 0)]
		if _net.is_host() and not _spectators.is_empty():
			net_line += "\n" + _ui.theme_data.t("spec_waiting_host", [_spectators.size()])
		_hud.set_net_info(net_line)


func _unhandled_input(event: InputEvent) -> void:
	if _mode == Mode.SOLO and _laps.is_finished and not _ui.any_open() and (event.is_action_pressed(InputActions.RESTART) \
			or event.is_action_pressed(&"ui_accept")):
		# Finish screen: Start / A / Enter restarts. No restart key during a race.
		_restart()
	elif event.is_action_pressed(InputActions.PAUSE) and not _ui.any_open():
		_open_pause()
	elif _spectating and not _ui.any_open() and (event.is_action_pressed(InputActions.STEER_LEFT) \
			or event.is_action_pressed(InputActions.STEER_RIGHT)) and not event.is_echo():
		# Spectator: the next / previous racer by place.
		_spec_place += -1 if event.is_action_pressed(InputActions.STEER_LEFT) else 1
		_spec_place = posmod(_spec_place - 1, maxi(_ranking.count(), 1)) + 1


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
	_separate_karts()
	_measure_contacts()
	_items.update(dt, race_time)
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
		if not r.owned or r.dropped or r.sim.is_sinking():
			continue
		for o in _racers:
			if o == r or o.dropped or o.sim.is_sinking():
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


# Push-apart passes after the bumps of this tick: clusters (a pile-up in a hairpin) need
# more than one pass. Own karts move by weight share (against a remote kart: all of it, its
# owner moves the other); two remote karts are drawn apart half each, display only. Own
# karts are then put back inside the walls so a push never leaves one in a wall.
func _separate_karts() -> void:
	for p in net_config.contact_passes:
		for i in _racers.size():
			var a: Racer = _racers[i]
			if a.dropped:
				continue
			for j in range(i + 1, _racers.size()):
				var b: Racer = _racers[j]
				if b.dropped:
					continue
				if a.owned and b.owned:
					var pa: float = _push_of(a, b)
					var pb: float = _push_of(b, a)
					var total: float = maxf(pa + pb, 0.0001)
					KartSim.push_apart(a.sim, b.sim, pb / total, pa / total)
				elif a.owned:
					KartSim.push_apart(a.sim, b.sim, 1.0, 0.0)
				elif b.owned:
					KartSim.push_apart(a.sim, b.sim, 0.0, 1.0)
				else:
					KartSim.push_apart(a.sim, b.sim, 0.5, 0.5)
		for r in _racers:
			if r.owned and not r.dropped:
				r.sim.clamp_to_walls(_track)
	# An own kart pinned between a wall and a remote kart cannot move further: draw the
	# remote kart aside instead (display only; its owner moves it through the bump message).
	for a in _racers:
		if not a.owned or a.dropped:
			continue
		for b in _racers:
			if b.owned or b.dropped:
				continue
			KartSim.push_apart(a.sim, b.sim, 0.0, 1.0)


# How hard [param r]'s kart pushes [param against]'s (bots push humans less).
func _push_of(r: Racer, against: Racer) -> float:
	var push: float = r.sim.stats.bump_push_mult
	if r.is_bot and not against.is_bot:
		push *= net_config.bot_push_mult
	return push


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
	if done and _results_enabled and not _results_open and _net.is_host():
		_publish_results()
	if done and _options.quit_after_race:
		get_tree().quit()


# ---------------------------------------------------------------- menu and lobby flow

# Connects the screens' signals to the flow below.
func _wire_ui() -> void:
	_ui.pause.resume_requested.connect(_resume)
	_ui.pause.restart_requested.connect(_restart)
	_ui.pause.quit_requested.connect(func() -> void: get_tree().quit())
	_ui.pause.menu_requested.connect(_back_to_menu)
	_ui.menu.solo_requested.connect(_start_solo)
	_ui.menu.host_requested.connect(_on_menu_host)
	_ui.menu.join_requested.connect(_on_menu_join)
	_ui.menu.quit_requested.connect(func() -> void: get_tree().quit())
	_ui.lobby.pick_changed.connect(_on_lobby_pick_changed)
	_ui.lobby.ready_toggled.connect(_on_lobby_ready_toggled)
	_ui.lobby.track_stepped.connect(_on_track_stepped)
	_ui.lobby.bots_stepped.connect(_on_bots_stepped)
	_ui.lobby.laps_stepped.connect(_on_laps_stepped)
	_ui.lobby.start_requested.connect(_on_lobby_start)
	_ui.lobby.leave_requested.connect(func() -> void: _leave_network(""))
	_ui.results.rematch_requested.connect(_on_rematch)
	_ui.results.lobby_requested.connect(_on_back_to_lobby)
	_ui.results.restart_requested.connect(_restart)
	_ui.results.menu_requested.connect(_back_to_menu)
	_ui.menu.sound_toggle_requested.connect(_toggle_mute)
	_ui.pause.sound_toggle_requested.connect(_toggle_mute)
	_ui.mute_requested.connect(_toggle_mute)
	_ui.bindings_changed.connect(_hud.refresh_hints)
	_ui.bindings_changed.connect(func() -> void: _spec_follow_key = "")


# Creates the one AudioDirector (music from the start: menu, lobby and races share the loop) and
# the race sound wiring; UI screens play their sounds through it.
func _setup_audio() -> void:
	var audio_set: AudioSet = load(AUDIO_SET_PATH) as AudioSet
	if audio_set == null:
		push_error("Audio data missing: %s" % AUDIO_SET_PATH)
		audio_set = AudioSet.new()
	_audio = AudioDirector.new()
	_audio.name = &"AudioDirector"
	add_child(_audio)
	_audio.setup(audio_set)
	_race_sound = RaceSound.new(_audio, audio_set)
	_race_sound.watch_owned(_local, true)
	_race_sound.watch_laps(_laps)
	_ui.set_sound_player(func(ev: StringName) -> void: _audio.play_event(ev))
	_ui.set_sound_state(_audio.is_muted())
	_audio.mute_changed.connect(_ui.set_sound_state)
	_audio.start_music()


func _toggle_mute() -> void:
	_audio.toggle_mute()


func _on_item_sound_cue(kind: StringName, kart_id: int) -> void:
	var r: Racer = _by_id.get(kart_id)
	if r == null and kart_id == _local.kart_id:
		r = _local
	_race_sound.item_cue(kind, r, r == _local)


# Minimap markers: every racer's sim position, heading and slot colour; the local kart and the
# leader (online ranking) are marked.
func _update_minimap() -> void:
	var n: int = 0
	var local_i: int = -1
	var leader_i: int = -1
	var leader_id: int = _ranking.leader() if _mode == Mode.NET_RACE else -1
	_map_pos.resize(_racers.size())
	_map_yaw.resize(_racers.size())
	_map_col.resize(_racers.size())
	for r in _racers:
		if r.dropped or r.sim == null:
			continue
		_map_pos[n] = r.sim.position
		_map_yaw[n] = r.sim.yaw
		_map_col[n] = _slot_color(r.kart_id)
		if r == _local or (_spectating and r.kart_id == _spec_target):
			local_i = n
		if r.kart_id == leader_id:
			leader_i = n
		n += 1
	_map_pos.resize(n)
	_map_yaw.resize(n)
	_map_col.resize(n)
	_hud.set_minimap_racers(_map_pos, _map_yaw, _map_col, local_i, leader_i)


# The start screen (offline, paused behind it). [param message] shows under the panels.
func _show_main_menu(message: String) -> void:
	get_tree().paused = true
	_ui.show_menu(message)


func _open_pause() -> void:
	if _mode == Mode.SOLO:
		get_tree().paused = true
	_ui.pause.open_pause(_mode == Mode.SOLO)


func _resume() -> void:
	_ui.pause.close()
	get_tree().paused = false


func _restart() -> void:
	if _mode != Mode.SOLO:
		return
	_ui.close_all()
	get_tree().paused = false
	_reset_race()
	_camera.snap()


func _start_solo() -> void:
	_ui.close_all()
	get_tree().paused = false
	_reset_race()
	_camera.snap()


# Back to the start screen: leaves an online race or lobby, or abandons a solo race.
func _back_to_menu() -> void:
	if _mode == Mode.SOLO:
		get_tree().paused = false
		_reset_race()
		_camera.snap()
		_show_main_menu("")
	else:
		_leave_network("")


func _on_menu_host() -> void:
	_begin_hosting(0)


func _on_menu_join(address: String) -> void:
	if _mode == Mode.CLIENT_LOBBY:
		_net.close()  # still connecting to an earlier address: try this one instead
		_mode = Mode.SOLO
	_begin_joining(address)


func _begin_hosting(want_players: int) -> void:
	_begin_pending = false
	_begin_requested_ms = -1
	_want_players = want_players
	var err: Error = _net.host()
	if err != OK:
		_show_lobby_text("Could not host on port %d (error %d)." % [net_config.port, err])
		return
	_mode = Mode.HOST_LOBBY
	_lobby_timer = 0.0
	_hud.set_lobby(true)
	if _cli_net:
		_refresh_host_text()
		return
	_ui_flow = true
	_peer_ready.clear()
	_lobby = LobbyState.new()
	_lobby.version = KartWire.VERSION
	_lobby.track = String(track_data.track_id)
	_lobby.bots = _net_opts.bots if _net_opts.bots >= 0 else net_config.default_bots
	_lobby.laps = _net_opts.laps if _net_opts.laps > 0 else track_data.lap_count
	_ui.lobby.reset_ready()
	_ui.lobby.set_pick(_my_loadout.x, _my_loadout.y)
	_ui.lobby.set_info(_ui.theme_data.t("lobby_hosting", [net_config.port]))
	_ui.show_lobby()
	_publish_lobby()


func _begin_joining(address: String) -> void:
	var err: Error = _net.join(address)
	if err != OK:
		_show_lobby_text("Could not join %s (error %d)." % [address, err])
		return
	_mode = Mode.CLIENT_LOBBY
	_hud.set_lobby(true)
	if _cli_net:
		_show_lobby_text("Connecting to %s ..." % address)
		return
	_ui_flow = true
	_joining_address = address
	_ui.menu.set_status(_ui.theme_data.t("menu_connecting", [address]))


func _refresh_host_text() -> void:
	var count: int = _net.peer_ids().size() + 1
	var text: String = "Hosting on UDP %d: %d player(s) joined" % [net_config.port, count]
	if _want_players > 0:
		text += " (starting at %d)" % _want_players
	_show_lobby_text(text)


# A message for the command line paths (HUD banner) or, from the menu, under the main menu panels.
func _show_lobby_text(text: String) -> void:
	_hud.set_banner(text)
	if _ui.menu.is_open():
		_ui.menu.set_status(text)


func _on_connected_to_host() -> void:
	_show_lobby_text("Connected. Waiting for the host to start.")
	_net.send_loadout(_my_loadout.x, _my_loadout.y)
	if _ui_flow:
		_net.send_lobby_pick(_my_loadout.x, _my_loadout.y, false)
		RecentHosts.remember(_ui.theme_data.recent_file, _joining_address, _ui.theme_data.default_address, _ui.theme_data.recent_max)


# The version check before any RPC failed (KartWire.VERSION 8): back to the menu with the reason.
# [param host_version] -1 = the host gave no valid answer in time (an older build).
func _on_handshake_failed(host_version: int) -> void:
	var mine: int = _net.advertised_version
	if host_version >= 0:
		_leave_network("The host runs a different version of the game (host v%d, you v%d). Update to the same build." % [
				host_version, mine])
	else:
		_leave_network("The host did not answer the version check; it may run an older build of the game (you v%d). Update to the same build." % mine)


# Host: remembers what a client chose (values are clamped, a bad message never crashes).
func _on_loadout_received(peer_id: int, racer: int, vehicle: int) -> void:
	var lo := Vector2i(clampi(racer, 0, maxi(_racer_set.count() - 1, 0)),
			clampi(vehicle, 0, maxi(_vehicle_set.count() - 1, 0)))
	_peer_loadouts[peer_id] = lo
	print("[loadout] peer %d chose racer %d vehicle %d" % [peer_id, lo.x, lo.y])


func _on_peer_joined(id: int) -> void:
	if not _net.is_host():
		return
	if _mode == Mode.HOST_LOBBY:
		if _ui_flow:
			_publish_lobby()
		else:
			_refresh_host_text()
	else:
		_add_spectator(id)


func _on_peer_left(id: int) -> void:
	_peer_loadouts.erase(id)
	_peer_ready.erase(id)
	_spectators.erase(id)
	if _mode == Mode.HOST_LOBBY:
		if _ui_flow:
			_publish_lobby()
		else:
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
	_peer_loadouts.clear()
	_peer_ready.clear()
	_ui_flow = false
	_results_open = false
	_begin_pending = false
	_begin_requested_ms = -1
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
	_show_main_menu(message)


# ---------------------------------------------------------------- starting a networked race

func _host_begin_race() -> void:
	var peers: Array[int] = _net.peer_ids()
	peers.sort()
	# Every client's racer/vehicle choice must be here before the start info is built, or that
	# client would be shown with defaults on the other PCs; after the wait it starts without it.
	if _begin_requested_ms < 0:
		_begin_requested_ms = Time.get_ticks_msec()
	var missing: Array[int] = []
	for p in peers:
		if not _peer_loadouts.has(p):
			missing.append(p)
	if not missing.is_empty() and float(Time.get_ticks_msec() - _begin_requested_ms) < net_config.loadout_wait * 1000.0:
		_begin_pending = true
		return
	if not missing.is_empty():
		push_warning("No loadout from peer(s) %s after %.1f s; they get the default racer and cart." % [str(missing), net_config.loadout_wait])
	_begin_pending = false
	_begin_requested_ms = -1
	var slots: Array = [[0, 1, "Player 1", false]]
	var next_id: int = 1
	for p in peers:
		slots.append([next_id, p, "Player %d" % (next_id + 1), false])
		next_id += 1
	var bots: int = _net_opts.bots if _net_opts.bots >= 0 else net_config.default_bots
	if _ui_flow:
		bots = _lobby.bots
	bots = clampi(bots, 0, net_config.max_racers - slots.size())
	for b in bots:
		slots.append([next_id, 1, _bot_set.bot_name(b), true])
		next_id += 1
	var race_seed: int = _debug_race_seed()
	var loadouts: Dictionary = {}
	for slot: Array in slots:
		var id: int = slot[0]
		if slot[3]:
			loadouts[id] = [_racer_set.default_bot_racer(id), _vehicle_set.bot_vehicle(race_seed, id)]
		elif slot[1] == 1:
			loadouts[id] = [_my_loadout.x, _my_loadout.y]
		else:
			var lo: Vector2i = _peer_loadouts.get(slot[1], Vector2i.ZERO)
			loadouts[id] = [lo.x, lo.y]
	var info: Dictionary = {
		"version": KartWire.VERSION,
		"loadouts": loadouts,
		"slots": slots,
		"laps": _laps_for_race(),
		"track": String(track_data.track_id),
		"host_time": -_sim.stats.start_countdown_time,
		"seed": race_seed,
	}
	_race_info = info
	_last_results = []
	if not _spectators.is_empty():
		print("[spectate] host: %d watcher(s) join this race as racers: peers %s" % [_spectators.size(), str(_spectators.keys())])
	_spectators.clear()
	_net.broadcast_race_start(info)
	_apply_race_start(info)


# Debug: --race-seed=N makes the host use seed N, to replay a logged race (otherwise random).
func _debug_race_seed() -> int:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--race-seed="):
			return int(a.substr("--race-seed=".length()))
	return randi()


func _on_race_start_received(info: Dictionary) -> void:
	if _net.is_host():
		return
	if _mode == Mode.NET_RACE and not _results_open and (not _spectating or bool(info.get("spectate", false))):
		return
	if int(info.get("version", -1)) != KartWire.VERSION:
		_leave_network("The host runs a different network version.")
		return
	var host_track: String = str(info.get("track", ""))
	if not _ensure_track(host_track):
		_leave_network("The host chose a track this game does not have ('%s')." % host_track)
		return
	_apply_race_start(info)


# Builds every racer from the host's slot list and starts the synced countdown.
func _apply_race_start(info: Dictionary) -> void:
	var build_start_us: int = Time.get_ticks_usec()
	_clear_others()
	var spectate: bool = bool(info.get("spectate", false))
	if spectate:
		_begin_spectating()
	var my_id: int = _net.my_id()
	var laps_n: int = int(info.laps)
	var slots: Array = info.slots
	var loadouts: Dictionary = info.get("loadouts", {})
	var ids: Array[int] = []
	_kart_loadouts.clear()
	_results_open = false
	_laps.lap_target = laps_n
	for slot: Array in slots:
		var kart_id: int = slot[0]
		var peer: int = slot[1]
		var is_bot: bool = slot[3]
		var dist: float = _track.length - track_data.start_distance_behind_line \
				- float(kart_id / 2) * net_config.grid_row_spacing
		var lateral: float = net_config.grid_lateral * (1.0 if kart_id % 2 == 0 else -1.0)
		ids.append(kart_id)
		var lo: Vector2i = _loadout_of(loadouts, kart_id, is_bot, int(info.get("seed", 0)))
		_kart_loadouts[kart_id] = lo
		print("[loadout] kart=%d peer=%d bot=%s racer=%d vehicle=%s" % [kart_id, peer, str(is_bot),
				lo.x, _vehicle_set.vehicle_at(lo.y).vehicle_id])
		if not is_bot and peer == my_id:
			_local.kart_id = kart_id
			_local.owner_peer = peer
			_local.display_name = slot[2]
			_local.dropped = false
			# The host's start info is the truth for every PC: take its loadout for this kart.
			if lo != _my_loadout:
				push_warning("The host set this kart's loadout to racer %d vehicle %d (asked for %d/%d); using the host's." % [
						lo.x, lo.y, _my_loadout.x, _my_loadout.y])
				_my_loadout = lo
			if lo != _built_loadout:
				_built_loadout = lo
				_sim.stats = _stats_for(lo.y, kart_id)
				_local.visual.queue_free()
				_local.visual = _make_visual(_sim, lo.x, kart_id)
				_camera.follow(_sim)
			# Same color and pennant for this kart on every PC: its slot's palette entry.
			_local.visual.apply_identity(_slot_of(kart_id), _slot_color(kart_id))
			_sim.reset_to(_track, dist, lateral)
			_laps.reset(_sim.track_s)
			_input.clear()
			_start.begin(_sim.stats)
			_by_id[kart_id] = _local
			continue
		var r := Racer.new()
		r.kart_id = kart_id
		r.owner_peer = peer
		r.display_name = slot[2]
		r.is_bot = is_bot
		var stats: VehicleStats = _stats_for(lo.y, kart_id)
		if is_bot and _net.is_host():
			r.owned = true
			r.sim = KartSim.new(stats)
			r.driver = BotDriver.create(_bot_set, kart_id, _bot_context(), laps_n, int(info.get("seed", 0)))
			r.laps = LapCounter.new(laps_n, _track.length, _track.checkpoint_s)
			r.sim.reset_to(_track, dist, lateral)
			r.laps.reset(r.sim.track_s)
			r.start.begin(stats)
			_race_sound.watch_owned(r, false)
		else:
			r.owned = false
			r.remote = RemoteKart.new(stats, net_config, _net_stats)
			r.sim = r.remote
			r.remote.reset_to(_track, dist, lateral)
			r.remote.clear_snapshots()
		r.visual = _make_visual(r.sim, lo.x, kart_id)
		_racers.append(r)
		_by_id[kart_id] = r
	_ranking.reset(ids)
	_items.reset(_track, int(info.get("seed", 0)))
	_race_sound.reset()
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
	_ui.close_all()
	get_tree().paused = false
	_camera.snap()
	if _options.grid_shot:
		_place_grid_camera()
	if spectate:
		_hud.set_spectating(true)
		print("[spectate] watching the running race: %d karts, race clock %.1f s, %d laps" % [slots.size(), race_time, laps_n])
	print("[net] built %d karts in %.1f ms" % [slots.size(), float(Time.get_ticks_usec() - build_start_us) / 1000.0])
	print("[net] race start: %d karts, %d laps, role=%s peer=%d kart=%d" % [
			slots.size(), laps_n, _role(), my_id, _local.kart_id])


# What a bot may ask about the race (story 005): racers, progress, place, held item, threats.
func _bot_context() -> BotContext:
	var c := BotContext.new()
	c.racers_fn = func() -> Array: return _racers
	c.progress_fn = func(id: int) -> float:
		var r: Racer = _by_id.get(id)
		return _rank_key(r) if r != null else 0.0
	c.place_fn = func(id: int) -> int: return _ranking.place_of(id)
	c.held_fn = func(id: int) -> StringName: return _items.held_id_of(id)
	c.threat_fn = func(id: int) -> float: return _items.threat_distance(id)
	return c


func _clear_others() -> void:
	if _spectating:
		_end_spectating()
	for r in _racers:
		if r != _local and r.visual != null:
			r.visual.queue_free()
	_racers = [_local]
	_local.visual.apply_identity(_slot_of(_local.kart_id), _slot_color(_local.kart_id))
	_by_id.clear()
	_by_id[_local.kart_id] = _local


# Loads the vehicle and racer sets (story 006) and reads this PC's --racer= / --vehicle= choice.
func _load_rosters() -> void:
	_vehicle_set = load(VEHICLE_SET_PATH) as VehicleSet
	if _vehicle_set == null or _vehicle_set.count() == 0:
		push_error("Vehicle set missing: %s" % VEHICLE_SET_PATH)
		_vehicle_set = VehicleSet.new()
		_vehicle_set.vehicles.append(vehicle_stats)
	_racer_set = load(RACER_SET_PATH) as RacerSet
	if _racer_set == null or _racer_set.count() == 0:
		push_error("Racer set missing: %s" % RACER_SET_PATH)
		_racer_set = RacerSet.new()
		_racer_set.racers.append(RacerDef.new())
	var racer: int = 0
	if _options.racer >= 0:
		if _racer_set.is_valid_index(_options.racer):
			racer = _options.racer
		else:
			push_warning("--racer=%d is not a racer (0..%d); using 0." % [_options.racer, _racer_set.count() - 1])
	var vehicle: int = 0
	if _options.vehicle != "":
		vehicle = _vehicle_set.index_of(_options.vehicle)
		if vehicle < 0:
			push_warning("--vehicle=%s is not a vehicle; using the cart." % _options.vehicle)
			vehicle = 0
	_my_loadout = Vector2i(racer, vehicle)
	Pennant.prewarm(_racer_set.pennant, net_config.kart_colors)
	KartVisual.prewarm(_vehicle_set, _racer_set)


# The loadout of [param kart_id] from the host's start info. A missing or bad entry falls back to
# the defaults: a bot gets kart_id % racers and a seed-picked vehicle, a human the mascot and cart.
func _loadout_of(loadouts: Dictionary, kart_id: int, is_bot: bool, race_seed: int) -> Vector2i:
	var entry: Variant = loadouts.get(kart_id)
	if entry is Array and (entry as Array).size() >= 2:
		var r: int = int((entry as Array)[0])
		var v: int = int((entry as Array)[1])
		if _racer_set.is_valid_index(r) and v >= 0 and v < _vehicle_set.count():
			return Vector2i(r, v)
	if is_bot:
		return Vector2i(_racer_set.default_bot_racer(kart_id), _vehicle_set.bot_vehicle(race_seed, kart_id))
	return Vector2i.ZERO


# Identity slot of a kart (12 slots, one per kart id) and its palette color.
func _slot_of(kart_id: int) -> int:
	return posmod(kart_id, maxi(net_config.kart_colors.size(), 1))


func _slot_color(kart_id: int) -> Color:
	if net_config.kart_colors.is_empty():
		return Color.WHITE
	return net_config.kart_colors[_slot_of(kart_id)]


# A private copy of vehicle [param vehicle]'s stats for one kart (the bot driver scales max_speed),
# painted with the kart's slot color.
func _stats_for(vehicle: int, kart_id: int) -> VehicleStats:
	var s: VehicleStats = _vehicle_set.vehicle_at(vehicle).duplicate()
	s.paint_color = _slot_color(kart_id)
	return s


func _make_visual(sim: KartSim, racer: int, kart_id: int) -> KartVisual:
	var v := KartVisual.new()
	add_child(v)
	v.bind(sim, _racer_set.racer_at(racer), _racer_set.pennant, _slot_of(kart_id))
	v.apply_identity(_slot_of(kart_id), _slot_color(kart_id))
	return v


func _laps_for_race() -> int:
	if _ui_flow and _mode != Mode.SOLO:
		return _lobby.laps
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
	_log_file.store_line("wall_time,role,peer,race_time,rtt_ms,lag_ms,jitter_ms,loss_pct,snaps_per_s,extrap_pct,pred_err_avg_m,pred_err_max_m,view_delay_ms,kb_out,kb_in,fps,draw_calls,objects,primitives,frame_max_ms,proc_max_ms,phys_max_ms,visual_us")


# Tracks the worst frame of the current netlog window (an average fps hides one long frame).
func _perf_sample() -> void:
	var now_us: int = Time.get_ticks_usec()
	if _perf_last_us > 0:
		_perf_frame_max_us = maxi(_perf_frame_max_us, now_us - _perf_last_us)
	_perf_last_us = now_us
	_perf_proc_max_ms = maxf(_perf_proc_max_ms, Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
	_perf_phys_max_ms = maxf(_perf_phys_max_ms, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)


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
		_log_file.store_line("%.1f,%s,%d,%.2f,%d,%d,%d,%d,%d,%.1f,%.3f,%.3f,%d,%.1f,%.1f,%d,%d,%d,%d,%.1f,%.2f,%.2f,%d" % [
				Time.get_unix_time_from_system(), _role(), _net.my_id(), race_time,
				int(_net_stats.rtt * 1000.0), int(_net_opts.lag_ms), int(_net_opts.jitter_ms),
				int(_net_opts.loss_pct), w.snaps, w.extrap_pct, w.err_avg, w.err_max,
				int(_net_stats.view_delay * 1000.0), bw.x / 1024.0, bw.y / 1024.0,
				int(Engine.get_frames_per_second()),
					int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
					int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
					int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
					_perf_frame_max_us / 1000.0, _perf_proc_max_ms, _perf_phys_max_ms,
					KartVisual.take_cost_usec()])
		_log_file.flush()
	_perf_frame_max_us = 0
	_perf_proc_max_ms = 0.0
	_perf_phys_max_ms = 0.0


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
	_results_open = false
	_solo_results_timer = 0.0
	_start.begin(_sim.stats)
	if _items != null:
		_items.reset(_track, 0)
	if _race_sound != null:
		_race_sound.reset()


# Loads [param id] when it is not the current track (a client follows the host's choice).
# Returns false when the id is empty or unknown.
func _ensure_track(id: String) -> bool:
	if id != "" and id == String(track_data.track_id):
		return true
	var data: TrackData = TrackLibrary.load_track(id)
	if data == null:
		return false
	track_data = data
	_track = TrackModel.new(data)
	if _camera != null:
		_camera.track = _track
	_laps.configure_track(_track.length, _track.checkpoint_s)
	if _hud != null:
		_hud.set_track(_track)
	_build_world()
	_reset_race()
	print("[net] loaded track %s from the host" % id)
	return true


# Builds sky, light, ground, road meshes and scenery for the current track inside _world.
func _build_world() -> void:
	if _world != null:
		remove_child(_world)
		_world.queue_free()
	_world = Node3D.new()
	_world.name = "World"
	add_child(_world)
	var th: TrackTheme = _track.theme
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = th.sky_top_color
	sky_mat.sky_horizon_color = th.sky_horizon_color
	sky_mat.ground_horizon_color = th.ground_horizon_color
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = th.ambient_color
	env.ambient_light_energy = th.ambient_energy
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	if th.fog_enabled:  # Dungeon Depths: purple-brown fog from the theme
		env.fog_enabled = true
		env.fog_light_color = th.fog_color
		env.fog_density = th.fog_density
	var we := WorldEnvironment.new()
	we.environment = env
	_world.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 40, 0)
	sun.light_color = th.sun_color
	sun.light_energy = th.sun_energy
	sun.shadow_enabled = true
	sun.visible = th.sun_energy > 0.0  # a dungeon has no sun
	sun.directional_shadow_max_distance = 120.0
	_world.add_child(sun)
	var center: Vector2 = _track.main.bounds.get_center()
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(th.ground_size, th.ground_size)
	ground.mesh = pm
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = th.ground_color
	ground.material_override = gmat
	ground.position = Vector3(center.x, -0.05, center.y)
	_world.add_child(ground)
	var mesh := TrackMesh.new()
	_world.add_child(mesh)
	mesh.build(_track)
	var scenery := TrackScenery.new()
	_world.add_child(scenery)
	scenery.build(_track)


# ---------------------------------------------------------------- lobby and results flow (menu-driven online)

# Host: rebuilds the roster from the connected peers and the saved picks, clamps the bots to the
# free places, shows it and sends it to every client.
func _publish_lobby() -> void:
	var peers: Array[int] = _net.peer_ids()
	peers.sort()
	_lobby.version = KartWire.VERSION
	_lobby.entries.clear()
	_lobby.entries.append(LobbyState.make_entry(LobbyState.HOST_PEER, _my_loadout.x, _my_loadout.y, true))
	for p in peers:
		var lo: Vector2i = _peer_loadouts.get(p, Vector2i.ZERO)
		_lobby.entries.append(LobbyState.make_entry(p, lo.x, lo.y, bool(_peer_ready.get(p, false)), _spectators.has(p)))
	_lobby.bots = clampi(_lobby.bots, 0, _lobby.max_bots(net_config.max_racers))
	_ui.lobby.show_state(_lobby, LobbyState.HOST_PEER, true)
	_net.send_lobby_state(_lobby.to_dict())
	print("[lobby] host roster: %d humans, %d bots, track %s, %d laps | %s" % [_lobby.humans(), _lobby.bots,
			_lobby.track, _lobby.laps, _roster_text(_lobby)])


# "peer:racer/vehicle/ready" per human, the same text on every PC when the roster is the same.
func _roster_text(state: LobbyState) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for e in state.entries:
		parts.append("%d:r%d/v%d/%s" % [int(e.peer), int(e.racer), int(e.vehicle), "ready" if bool(e.ready) else "wait"])
	return " ".join(parts)


# This PC changed its own pick in the lobby.
func _on_lobby_pick_changed(racer: int, vehicle: int) -> void:
	_my_loadout = Vector2i(racer, vehicle)
	if _net.is_host():
		_publish_lobby()
	else:
		_net.send_lobby_pick(racer, vehicle, _ui.lobby.is_ready_local())
		_net.send_loadout(racer, vehicle)


func _on_lobby_ready_toggled(is_ready: bool) -> void:
	_net.send_lobby_pick(_my_loadout.x, _my_loadout.y, is_ready)


# Host: a client's pick or ready mark.
func _on_lobby_pick_received(peer_id: int, racer: int, vehicle: int, is_ready: bool) -> void:
	_on_loadout_received(peer_id, racer, vehicle)
	_peer_ready[peer_id] = is_ready
	print("[lobby] peer %d picked racer %d vehicle %d ready=%s" % [peer_id, racer, vehicle, str(is_ready)])
	if _mode == Mode.HOST_LOBBY and _ui_flow:
		_publish_lobby()


# Client: the host's lobby (also the way back to the lobby after the results).
func _on_lobby_state_received(d: Dictionary) -> void:
	if _net.is_host() or _cli_net:
		return
	var state: LobbyState = LobbyState.from_dict(d)
	if state.version != KartWire.VERSION:
		_leave_network("The host runs a different network version.")
		return
	if _mode == Mode.NET_RACE:
		if not _results_open:
			return
		_enter_client_lobby()
	elif _mode != Mode.CLIENT_LOBBY:
		return
	_lobby = state
	if not _ui.lobby.is_open():
		_ui.lobby.reset_ready()
		_ui.lobby.set_pick(_my_loadout.x, _my_loadout.y)
		_ui.lobby.set_info(_ui.theme_data.t("lobby_joined", [_joining_address]))
		_ui.show_lobby()
	_ui.lobby.show_state(_lobby, _net.my_id(), false)
	print("[lobby] client %d sees: %d humans, %d bots, track %s, %d laps | %s" % [_net.my_id(), state.humans(),
			state.bots, state.track, state.laps, _roster_text(state)])


func _enter_client_lobby() -> void:
	_results_open = false
	_clear_others()
	_laps.lap_target = _lobby.laps
	_reset_race()
	_camera.snap()
	_mode = Mode.CLIENT_LOBBY
	_hud.set_lobby(true)
	_hud.set_banner("")
	_hud.show_place(0, 0)
	_hud.set_net_info("")
	_ui.lobby.reset_ready()


func _on_track_stepped(direction: int) -> void:
	var ids: PackedStringArray = _ui.theme_data.lobby_tracks
	if ids.is_empty():
		return
	var i: int = posmod(ids.find(_lobby.track) + direction, ids.size())
	_lobby.track = ids[i]
	if not _ensure_track(_lobby.track):
		push_warning("Lobby track '%s' failed to load." % _lobby.track)
	_publish_lobby()


func _on_bots_stepped(direction: int) -> void:
	_lobby.bots = clampi(_lobby.bots + direction, 0, _lobby.max_bots(net_config.max_racers))
	_publish_lobby()


func _on_laps_stepped(direction: int) -> void:
	_lobby.laps = clampi(_lobby.laps + direction, _ui.theme_data.laps_min, _ui.theme_data.laps_max)
	_publish_lobby()


func _on_lobby_start() -> void:
	if _mode == Mode.HOST_LOBBY and _lobby.all_ready():
		_host_begin_race()


# Host: same setup and loadouts again, one press.
func _on_rematch() -> void:
	if not _net.is_host():
		return
	print("[lobby] rematch requested")
	_ui.results.close()
	_results_open = false
	_host_begin_race()


# Host: back to the lobby with every client not ready again.
func _on_back_to_lobby() -> void:
	if not _net.is_host():
		return
	_results_open = false
	_clear_others()
	_laps.lap_target = _lobby.laps
	_reset_race()
	_camera.snap()
	_mode = Mode.HOST_LOBBY
	_hud.set_lobby(true)
	_hud.set_banner("")
	_hud.show_place(0, 0)
	_hud.set_net_info("")
	_peer_ready.clear()
	_ui.lobby.reset_ready()
	_ui.lobby.set_pick(_my_loadout.x, _my_loadout.y)
	_ui.show_lobby()
	_publish_lobby()


# Host: the results from the host's race state (ranking and every kart's finish data), sent to clients.
func _publish_results() -> void:
	var entries: Array = []
	for place in range(1, _ranking.count() + 1):
		var id: int = _ranking.id_at_place(place)
		var r: Racer = _by_id.get(id)
		if r == null:
			continue
		var lo: Vector2i = _kart_loadouts.get(id, Vector2i.ZERO)
		entries.append({"place": place, "kart_id": id, "name": r.display_name, "racer": lo.x, "vehicle": lo.y,
				"time": r.finish_time() if r.is_finished() else -1.0, "bot": r.is_bot})
	_results_open = true
	_last_results = entries
	_net.send_race_results(entries)
	_show_results(entries, ResultsScreen.Viewer.HOST)


func _on_race_results_received(entries: Array) -> void:
	if _net.is_host() or _mode != Mode.NET_RACE or not _results_enabled:
		return
	_results_open = true
	_show_results(entries, ResultsScreen.Viewer.CLIENT)


func _show_results(entries: Array, viewer: ResultsScreen.Viewer) -> void:
	for e: Dictionary in entries:
		print("[results] role=%s place=%d kart=%d name=%s racer=%d vehicle=%d time=%.2f%s" % [_role(), int(e.place),
				int(e.kart_id), str(e.name), int(e.racer), int(e.vehicle), float(e.time), " (seen as spectator)" if _spectating else ""])
	_ui.show_results(entries, _local.kart_id, viewer)
	var note: String = ""
	if _spectating:
		note = _ui.theme_data.t("spec_results_you")
	elif _net.is_host() and not _spectators.is_empty():
		note = _ui.theme_data.t("spec_results_note", [_spectators.size()])
	_ui.results.set_note(note)


# Solo: a moment after the finish line, the results of the one-kart race.
func _solo_results_tick(delta: float) -> void:
	if not _results_enabled or _mode != Mode.SOLO or _results_open or not _laps.is_finished or _ui.any_open():
		return
	_solo_results_timer += delta
	if _solo_results_timer < _ui.theme_data.solo_results_delay:
		return
	_results_open = true
	var entry: Dictionary = {"place": 1, "kart_id": _local.kart_id, "name": _ui.theme_data.t("player_name", [1]),
			"racer": _built_loadout.x, "vehicle": _built_loadout.y, "time": _laps.finish_race_time, "bot": false}
	_show_results([entry], ResultsScreen.Viewer.SOLO)


# ---------------------------------------------------------------- spectators (story 007 part 3)

# Host: [param id] connected while a race runs. It is not kicked: it gets the running race's
# start info (without karts that left) with the host's race clock and "spectate", watches, and
# is a normal player of the next race (rematch or lobby: it is one of the connected peers).
func _add_spectator(id: int) -> void:
	if _race_info.is_empty():
		push_warning("Peer %d joined with no race info to send; it waits for the next race." % id)
		_spectators[id] = true
		return
	_spectators[id] = true
	var info: Dictionary = _race_info.duplicate(true)
	var slots: Array = []
	for slot: Array in info.slots:
		var r: Racer = _by_id.get(int(slot[0]))
		if r != null and r.dropped:
			continue
		slots.append(slot)
	info["slots"] = slots
	info["host_time"] = race_time
	info["spectate"] = true
	_net.send_race_start_to(id, info)
	if _results_open and not _last_results.is_empty():
		_net.send_race_results_to(id, _last_results)
	print("[spectate] host: peer %d joined during the race and watches it (%d watching)%s" % [id, _spectators.size(),
			" - results sent" if _results_open else ""])


# Client: the local kart leaves the race view (hidden, not simulated, no kart id of the race).
func _begin_spectating() -> void:
	_spectating = true
	_spec_place = 1
	_spec_target = -2
	_spec_follow_key = ""
	_spec_time = 0.0
	_by_id.clear()
	_local.kart_id = SPECTATOR_KART_ID
	_local.dropped = true
	_local.visual.visible = false
	_input.clear()


# Client: back to a normal local kart (the next race, the lobby or the menu).
func _end_spectating() -> void:
	_spectating = false
	_local.dropped = false
	_local.kart_id = 0
	_local.visual.visible = true
	_spec_target = -2
	_hud.set_spectating(false)
	_camera.follow(_sim)
	print("[spectate] spectating ended")


# Spectator, per frame: the countdown follows the race clock, the camera follows the racer at
# _spec_place (it switches when that place changes hands), the standings column is refreshed.
func _spectate_tick(delta: float) -> void:
	_spec_time += delta
	if race_time < 0.0:
		_start.since_go = -1.0
		_start.time_to_go = -race_time
	else:
		_start.since_go = race_time
		_start.time_to_go = 0.0
	var n: int = _ranking.count()
	if n == 0:
		return
	_spec_place = clampi(_spec_place, 1, n)
	var id: int = _ranking.id_at_place(_spec_place)
	var target: Racer = _by_id.get(id)
	if id != _spec_target and target != null and target.sim != null:
		_spec_target = id
		_camera.follow(target.sim)
		print("[spectate] camera follows kart %d (%s), place %d" % [id, target.display_name, _spec_place])
	var names: PackedStringArray = PackedStringArray()
	var colors: PackedColorArray = PackedColorArray()
	for place in range(1, n + 1):
		var pid: int = _ranking.id_at_place(place)
		var r: Racer = _by_id.get(pid)
		names.append(r.display_name if r != null else str(pid))
		colors.append(_slot_color(pid))
	var key: String = "%d|%d" % [_spec_target, _spec_place]
	if key != _spec_follow_key:
		_spec_follow_key = key
		var who: String = target.display_name if target != null else ""
		_spec_follow_text = BindingText.fill(_ui.theme_data.t("spec_follow", [who, UiTheme.ordinal(_spec_place)]), _ui.theme_data)
	_hud.set_standings(names, colors, _spec_place - 1, _spec_follow_text)
	# Debug (--shots=): two pictures of the spectator view.
	if _options.shots_dir != "" and _spec_shots < 2 and _spec_time > 6.0 + 8.0 * float(_spec_shots):
		_spec_shots += 1
		_debug_save("spectate_%d" % _spec_shots)


# ---------------------------------------------------------------- debug cameras and shots

func _debug_save(shot_name: String) -> void:
	if _options.shots_dir == "":
		return
	DirAccess.make_dir_recursive_absolute(_options.shots_dir)
	var path: String = "%s/%s.png" % [_options.shots_dir, shot_name]
	var err: Error = get_viewport().get_texture().get_image().save_png(path)
	print("[debug] screenshot %s (err %d)" % [path, err])


# Debug (--overview-shot): a straight-down orthographic view of the whole track, saved once.
func _run_overview_shot() -> void:
	get_tree().paused = false
	_ui.close_all()
	_hud.hide()
	for node in _world.get_children():  # no fog in the top-down picture
		if node is WorldEnvironment:
			(node as WorldEnvironment).environment.fog_enabled = false
	var b: Rect2 = _track.main.bounds
	var cam := Camera3D.new()
	add_child(cam)
	var vp: Vector2 = get_viewport().get_visible_rect().size
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = maxf(b.size.y, b.size.x / (vp.x / vp.y)) * 1.04
	cam.far = 2000.0
	cam.position = Vector3(b.get_center().x, 600.0, b.get_center().y)
	cam.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	cam.current = true
	await get_tree().create_timer(1.5).timeout
	_debug_save("overview")
	get_tree().quit()


# Debug (--ui-shot=NAME): one menu screen with sample data, pictures into --shots=, then quit.
func _run_ui_shot() -> void:
	get_tree().paused = false
	_hud.hide()
	var runner := UiShotRunner.new()
	add_child(runner)
	runner.run(_options.ui_shot, _options.shots_dir, _ui, _racer_set, _vehicle_set, net_config)


# Debug (--lineup=DIR): no race; a line-up of all dogs on both vehicles, pictures into DIR, quit.
func _run_lineup() -> void:
	get_tree().paused = false
	_ui.close_all()
	_hud.hide()
	_world.queue_free()
	_local.visual.hide()
	var showcase := LineupShowcase.new()
	add_child(showcase)
	showcase.run(_vehicle_set, _racer_set, net_config, _options.lineup_dir)


# Debug (--grid-shot): a fixed camera above and behind the start grid.
func _place_grid_camera() -> void:
	if _debug_cam == null:
		_debug_cam = Camera3D.new()
		_debug_cam.far = 1500.0
		_debug_cam.fov = 62.0
		add_child(_debug_cam)
	var center_s: float = _track.length - track_data.start_distance_behind_line - 22.0
	var target: Vector2 = _track.point_at(center_s)
	var back: Vector2 = -_track.tangent_at(center_s) * 30.0
	_debug_cam.look_at_from_position(Vector3(target.x + back.x, 30.0, target.y + back.y),
			Vector3(target.x, 0.0, target.y))
	_debug_cam.current = true
	_grid_shot_timer = 0.0
	_grid_shot_done = false
