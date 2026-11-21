class_name RaceFlowUi
extends Node
## Owns the menu screens of story 007 part 1 (main menu, lobby, results, pause) and the
## [UiTheme] they share, so Main only wires signals. It holds no game state.

## Where the screen look and text live.
const THEME_PATH: String = "res://assets/data/ui/ui_theme.tres"

## The mute action (M / controller Back) was pressed, on any screen or in a race.
signal mute_requested

## The look and text data.
var theme_data: UiTheme
var menu: MainMenu
var lobby: LobbyScreen
var results: ResultsScreen
var pause: PauseMenu


## Builds every screen (hidden). [param colors] is the 12-slot kart palette.
func setup(racers: RacerSet, vehicles: VehicleSet, colors: PackedColorArray, max_racers: int) -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	theme_data = load(THEME_PATH) as UiTheme
	if theme_data == null:
		push_error("UI theme missing: %s" % THEME_PATH)
		theme_data = UiTheme.new()
	menu = MainMenu.new()
	add_child(menu)
	menu.setup(theme_data)
	lobby = LobbyScreen.new()
	add_child(lobby)
	lobby.setup_lobby(theme_data, racers, vehicles, colors, max_racers)
	results = ResultsScreen.new()
	add_child(results)
	results.setup_results(theme_data, racers, vehicles, colors)
	pause = PauseMenu.new()
	add_child(pause)
	pause.setup(theme_data)


# Mute works everywhere, also while the tree is paused behind a menu. A text field that has
# the focus keeps its letters (the GUI handles the key first).
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(InputActions.MUTE) and not event.is_echo():
		get_viewport().set_input_as_handled()
		mute_requested.emit()


## True while any screen is showing.
func any_open() -> bool:
	return menu.is_open() or lobby.is_open() or results.is_open() or pause.is_open()


## True while the main menu, lobby or results is showing (the pause menu is not counted).
func flow_open() -> bool:
	return menu.is_open() or lobby.is_open() or results.is_open()


## Hides every screen.
func close_all() -> void:
	menu.close()
	lobby.close()
	results.close()
	pause.close()


## Shows the main menu alone, with [param message] under the panels (empty = none).
func show_menu(message: String) -> void:
	close_all()
	menu.set_status(message)
	menu.open()


## Shows the lobby alone.
func show_lobby() -> void:
	close_all()
	lobby.open()


## Shows the results over the race.
func show_results(entries: Array, my_kart: int, viewer: ResultsScreen.Viewer) -> void:
	close_all()
	results.show_results(entries, my_kart, viewer)
	results.open()


## Routes every screen's UI sounds to [param play_fn] (event name -> plays it), e.g.
## AudioDirector.play_event.
func set_sound_player(play_fn: Callable) -> void:
	for screen: UiScreen in [menu, lobby, results, pause]:
		screen.sound_fn = play_fn


## Shows the mute state on the screens' "Sound: On/Off" buttons.
func set_sound_state(muted: bool) -> void:
	for screen: UiScreen in [menu, lobby, results, pause]:
		screen.set_sound_state(muted)
