class_name UiShotRunner
extends Node
## DEBUG AID (--ui-shot=NAME --shots=DIR). Opens one menu screen with made-up sample data,
## saves a PNG named NAME_WIDTHxHEIGHT.png and quits. Names: menu, lobby, lobby-client,
## results, results-client, results-solo, pause. Evidence for story 007 part 1.

const SETTLE_FRAMES: int = 30
const SAMPLE_HUMANS: int = 9
const SAMPLE_BOTS: int = 3
const SAMPLE_RESULTS: int = 12
const SAMPLE_MY_KART: int = 4
const SAMPLE_FIRST_TIME: float = 142.37
const SAMPLE_TIME_STEP: float = 3.9
const SAMPLE_DNF: int = 2
const BOT_NAMES: PackedStringArray = ["Biscuit", "Rex", "Pip", "Mochi", "Waffles", "Ziggy"]


## Shows [param shot_name] with sample data, saves the picture into [param dir] and quits.
func run(shot_name: String, dir: String, ui: RaceFlowUi, racers: RacerSet, vehicles: VehicleSet, config: NetConfig) -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(dir)
	match shot_name:
		"menu":
			ui.show_menu("")
		"lobby", "lobby-client":
			var is_host: bool = shot_name == "lobby"
			var state: LobbyState = _sample_lobby(racers, vehicles, config)
			ui.lobby.set_pick(int(state.entries[2].racer), int(state.entries[2].vehicle))
			ui.lobby.set_info(ui.theme_data.t("lobby_hosting", [config.port]))
			ui.show_lobby()
			ui.lobby.show_state(state, LobbyState.HOST_PEER if is_host else int(state.entries[2].peer), is_host)
		"results", "results-client", "results-solo":
			var entries: Array = _sample_results(racers, vehicles, ui, shot_name == "results-solo")
			var viewer: ResultsScreen.Viewer = ResultsScreen.Viewer.HOST
			if shot_name == "results-client":
				viewer = ResultsScreen.Viewer.CLIENT
			elif shot_name == "results-solo":
				viewer = ResultsScreen.Viewer.SOLO
			ui.show_results(entries, SAMPLE_MY_KART if shot_name != "results-solo" else 0, viewer)
		"pause":
			ui.pause.open_pause(true)
		_:
			printerr("[ui-shot] unknown screen '%s'" % shot_name)
			get_tree().quit(1)
			return
	for i in SETTLE_FRAMES:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var size: Vector2i = Vector2i(get_viewport().get_visible_rect().size)
	var path: String = "%s/%s_%dx%d.png" % [dir, shot_name, size.x, size.y]
	var err: Error = get_viewport().get_texture().get_image().save_png(path)
	print("[ui-shot] %s (err %d)" % [path, err])
	get_tree().quit()


func _sample_lobby(racers: RacerSet, vehicles: VehicleSet, config: NetConfig) -> LobbyState:
	var s := LobbyState.new()
	s.version = KartWire.VERSION
	s.track = "castle_circuit"
	s.bots = mini(SAMPLE_BOTS, config.max_racers - SAMPLE_HUMANS)
	s.laps = 3
	for i in SAMPLE_HUMANS:
		var peer: int = LobbyState.HOST_PEER if i == 0 else 1000 + i
		s.entries.append(LobbyState.make_entry(peer, (i * 3) % racers.count(), i % vehicles.count(), i % 3 != 1))
	return s


func _sample_results(racers: RacerSet, vehicles: VehicleSet, ui: RaceFlowUi, solo: bool) -> Array:
	var out: Array = []
	var count: int = 1 if solo else SAMPLE_RESULTS
	for i in count:
		var kart: int = (SAMPLE_MY_KART + i * 5) % SAMPLE_RESULTS if not solo else 0
		if solo:
			kart = 0
		var is_human: bool = kart < SAMPLE_HUMANS - 3
		var racer_name: String = ui.theme_data.t("player_name", [kart + 1]) if is_human else BOT_NAMES[kart % BOT_NAMES.size()]
		var dnf: bool = i >= count - SAMPLE_DNF and not solo
		out.append({"place": i + 1, "kart_id": kart, "name": racer_name, "racer": (kart * 3) % racers.count(),
				"vehicle": kart % vehicles.count(), "time": -1.0 if dnf else SAMPLE_FIRST_TIME + float(i) * SAMPLE_TIME_STEP,
				"bot": not is_human})
	return out
