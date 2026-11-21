class_name KartPreview
extends TextureRect
## A slowly turning 3D picture of the chosen dog on the chosen vehicle, drawn by a
## SubViewport with its own World3D so the race scene is not touched. Uses the same KartVisual
## as the race, so what you see is what races. The sim is never ticked.

const CAMERA_POSITION: Vector3 = Vector3(3.1, 1.8, 4.0)
const CAMERA_TARGET: Vector3 = Vector3(0.0, 0.65, 0.0)
const CAMERA_FOV: float = 38.0
const SKY_COLOR: Color = Color(0.36, 0.3, 0.38)
const AMBIENT_COLOR: Color = Color(0.82, 0.8, 0.86)
const AMBIENT_ENERGY: float = 0.8
const PLINTH_RADIUS: float = 2.6
const PLINTH_HEIGHT: float = 0.12

var _ui: UiTheme
var _vehicles: VehicleSet
var _racers: RacerSet
var _viewport: SubViewport
var _pivot: Node3D
var _visual: KartVisual
var _scale: float = 1.0


## Builds the viewport scene. [param colors] is the slot palette.
func setup(ui: UiTheme, vehicles: VehicleSet, racers: RacerSet) -> void:
	_ui = ui
	_vehicles = vehicles
	_racers = racers
	custom_minimum_size = Vector2(ui.preview_size)
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.size = ui.preview_size
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)
	texture = _viewport.get_texture()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = SKY_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = AMBIENT_COLOR
	env.ambient_light_energy = AMBIENT_ENERGY
	var we := WorldEnvironment.new()
	we.environment = env
	_viewport.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, 35, 0)
	_viewport.add_child(sun)
	var cam := Camera3D.new()
	cam.fov = CAMERA_FOV
	_viewport.add_child(cam)
	cam.look_at_from_position(CAMERA_POSITION, CAMERA_TARGET)
	cam.current = true
	_pivot = Node3D.new()
	_viewport.add_child(_pivot)
	var plinth := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = PLINTH_RADIUS
	cyl.bottom_radius = PLINTH_RADIUS
	cyl.height = PLINTH_HEIGHT
	plinth.mesh = cyl
	var mat := StandardMaterial3D.new()
	mat.albedo_color = ui.parchment_dark
	plinth.material_override = mat
	plinth.position = Vector3(0, -PLINTH_HEIGHT * 0.5, 0)
	_viewport.add_child(plinth)


## Resizes the render target for a UI scale of [param factor] so the picture stays sharp.
func set_ui_scale(factor: float) -> void:
	if _viewport == null or is_equal_approx(factor, _scale):
		return
	_scale = factor
	_viewport.size = Vector2i(Vector2(_ui.preview_size) * maxf(factor, 1.0))


## Shows racer [param racer] on vehicle [param vehicle] painted [param color] with pennant [param slot].
func show_pick(racer: int, vehicle: int, slot: int, color: Color) -> void:
	if _visual != null:
		_visual.queue_free()
		_visual = null
	var stats: VehicleStats = _vehicles.vehicle_at(vehicle).duplicate()
	stats.paint_color = color
	var sim := KartSim.new(stats)
	sim.position = Vector2.ZERO
	sim.yaw = 0.0
	sim._prev_position = Vector2.ZERO
	sim._prev_yaw = 0.0
	_visual = KartVisual.new()
	_pivot.add_child(_visual)
	_visual.bind(sim, _racers.racer_at(racer), _racers.pennant, slot)
	_visual.apply_identity(slot, color)


func _process(delta: float) -> void:
	if _pivot != null and is_visible_in_tree():
		_pivot.rotation.y += deg_to_rad(_ui.preview_spin) * delta
