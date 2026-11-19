extends Node3D
## Main scene: runs the flat test loop with one player kart.
## Wires the pieces together with injected references (no autoloads): VehicleStats and
## TrackData come in as exported resources; KartSim, a KartDriver, LapCounter and the
## presentation nodes are created here. Implements story 001 (driving and drift).

## Emitted once when the player finishes the last lap.
signal race_finished(total_time: float)

## Handling data for the player's vehicle.
@export var vehicle_stats: VehicleStats
## Track to race on.
@export var track_data: TrackData

## Seconds of driving since the race (re)started.
var race_time: float = 0.0

var _options: DebugOptions
var _track: TrackModel
var _sim: KartSim
var _driver: KartDriver
var _input: KartInput = KartInput.new()
var _laps: LapCounter
var _camera: ChaseCamera
var _hud: RaceHud
var _menu: PauseMenu


func _ready() -> void:
	InputActions.register()
	_options = DebugOptions.parse(OS.get_cmdline_user_args())
	_track = TrackModel.new(track_data)
	_sim = KartSim.new(vehicle_stats)
	_laps = LapCounter.new(track_data.lap_count, _track.length)
	_driver = AutopilotDriver.new() if _options.autopilot else PlayerInputDriver.new()
	_build_environment()
	var mesh := TrackMesh.new()
	add_child(mesh)
	mesh.build(_track)
	var visual := KartVisual.new()
	add_child(visual)
	visual.bind(_sim)
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
	_laps.finished.connect(func(total: float) -> void: race_finished.emit(total))
	_reset_race()
	_camera.follow(_sim)
	if _options.needs_harness():
		var harness := DebugHarness.new()
		add_child(harness)
		harness.setup(_options, self, _sim, _laps)
	if _options.time_scale > 0.0:
		Engine.time_scale = _options.time_scale
	if _options.autopilot:
		get_tree().paused = false
	else:
		_open_menu("Dogworks Racing: Kennel Kingdom", true)


## True while the start or pause menu is showing.
func menu_is_open() -> bool:
	return _menu.is_open()


func _physics_process(dt: float) -> void:
	_driver.drive(_input, _sim, _track, dt)
	if _laps.is_finished:
		_input.clear()
	_sim.tick(dt, _input, _track)
	race_time += dt
	_laps.update(_sim.track_s, race_time)


func _process(_delta: float) -> void:
	_hud.refresh(_sim, _laps, race_time)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(InputActions.RESTART):
		_restart()
	elif event.is_action_pressed(InputActions.PAUSE):
		# Start / Esc: on the finish screen it restarts, otherwise it opens the pause menu.
		if _laps.is_finished:
			_restart()
		else:
			_open_menu("Paused", false)


func _open_menu(title: String, start_screen: bool) -> void:
	get_tree().paused = true
	_menu.open(title, start_screen)


func _resume() -> void:
	_menu.close()
	get_tree().paused = false


func _restart() -> void:
	_menu.close()
	get_tree().paused = false
	_reset_race()
	_camera.snap()


func _reset_race() -> void:
	_sim.reset_to(_track, _track.length - track_data.start_distance_behind_line, 0.0)
	_laps.reset(_sim.track_s)
	_input.clear()
	race_time = 0.0


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
