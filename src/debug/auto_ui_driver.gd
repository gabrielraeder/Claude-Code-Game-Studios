class_name AutoUiDriver
extends Node
## DEBUG AID (--auto-ui=host or --auto-ui=join:ADDRESS). Clicks through the main menu and the
## lobby by calling the same controls a player presses: Host / Join, the racer and vehicle
## rows (--auto-pick=R,V), then as host the track, bots and laps rows (--auto-track=, --auto-bots=,
## --auto-laps=) and Start once every client is ready; as client Ready. On every results screen
## the host presses Rematch until --auto-races races were played, then everyone quits.
## It reads screen state only through the screens' public API.

var _options: DebugOptions
var _ui: RaceFlowUi
var _is_host: bool = false
var _address: String = ""
var _timer: float = 0.0
var _stage: String = "menu"
var _races_seen: int = 0
var _step: float = 0.6


## Attaches to the running screens.
func setup(options: DebugOptions, ui: RaceFlowUi) -> void:
	_options = options
	_ui = ui
	process_mode = Node.PROCESS_MODE_ALWAYS
	_step = ui.theme_data.auto_ui_step
	if options.auto_ui.begins_with("join:"):
		_address = options.auto_ui.substr("join:".length())
	else:
		_is_host = true


func _process(delta: float) -> void:
	_timer += delta
	if _timer < _step:
		return
	_timer = 0.0
	match _stage:
		"menu":
			if _ui.menu.is_open():
				if _is_host:
					_ui.menu.host_button().pressed.emit()
				else:
					_ui.menu.ip_edit().text = _address
					_ui.menu.join_button().pressed.emit()
				_stage = "lobby"
		"lobby":
			if _ui.lobby.is_open() and _ui.lobby.state().humans() > 0:
				_stage = "pick"
		"pick":
			_do_pick()
			_stage = "setup" if _is_host else "ready"
		"setup":
			if _do_setup():
				_stage = "start"
		"ready":
			_ui.lobby.action_button().pressed.emit()
			_stage = "race"
		"start":
			var state: LobbyState = _ui.lobby.state()
			if state.humans() >= _expected_humans() and state.all_ready():
				_ui.lobby.action_button().pressed.emit()
				_stage = "race"
		"race":
			if _ui.results.is_open():
				_races_seen += 1
				print("[auto-ui] results %d of %d shown" % [_races_seen, _options.auto_races])
				_stage = "results"
		"results":
			if _races_seen >= _options.auto_races:
				print("[auto-ui] done")
				get_tree().quit()
			elif _is_host:
				_ui.results.first_button().pressed.emit()
				_stage = "race"
			else:
				_stage = "race"
				_timer = -_step * 4.0  # let the next race start before looking for its results


func _expected_humans() -> int:
	return 2


# Presses the racer and vehicle rows until the wanted pick shows.
func _do_pick() -> void:
	if _options.auto_pick == "":
		return
	var parts: PackedStringArray = _options.auto_pick.split(",")
	if parts.size() < 2:
		return
	var want_r: int = parts[0].to_int()
	var want_v: int = parts[1].to_int()
	var guard: int = 0
	while _ui.lobby.pick().x != want_r and guard < 20:
		_ui.lobby.racer_row().stepped.emit(1)
		guard += 1
	while _ui.lobby.pick().y != want_v and guard < 40:
		_ui.lobby.vehicle_row().stepped.emit(1)
		guard += 1


# Host: sets the track, bots and laps rows. Returns true when done.
func _do_setup() -> bool:
	var lobby: LobbyScreen = _ui.lobby
	var guard: int = 0
	if _options.auto_track != "":
		while lobby.state().track != _options.auto_track and guard < 6:
			lobby.track_row().stepped.emit(1)
			guard += 1
	guard = 0
	while _options.auto_bots >= 0 and lobby.state().bots != _options.auto_bots and guard < 20:
		lobby.bots_row().stepped.emit(1 if lobby.state().bots < _options.auto_bots else -1)
		guard += 1
	guard = 0
	while _options.auto_laps > 0 and lobby.state().laps != _options.auto_laps and guard < 12:
		lobby.laps_row().stepped.emit(1 if lobby.state().laps < _options.auto_laps else -1)
		guard += 1
	return true
