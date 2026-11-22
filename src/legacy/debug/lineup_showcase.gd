class_name LineupShowcase
extends Node3D
## DEBUG AID (--lineup=DIR). Builds a no-race line-up: all 8 dogs on the cart in one row, on the
## bike in a second row, and a row of 12 karts showing the 12 slot colors and pennants. Takes
## chase-camera-like and close 3/4 pictures into DIR as PNGs, then quits. Evidence for story 006.
## Uses the same KartVisual as a race; the sims are never ticked.

const SPACING: float = 4.0
const CART_ROW: int = 0
const BIKE_ROW: int = 1
const SLOT_ROW: int = 2
const FRAMES_TO_SETTLE: int = 4

var _vehicles: VehicleSet
var _racers: RacerSet
var _config: NetConfig
var _dir: String = ""
var _cam: Camera3D
## Per row: Array of {visual, pos, slug}.
var _rows: Array[Array] = [[], [], []]
var _row_nodes: Array[Node3D] = []
var _sheet: Node3D


## Builds the scene and runs the pictures; quits the game when done.
func run(vehicles: VehicleSet, racers: RacerSet, config: NetConfig, out_dir: String) -> void:
	_vehicles = vehicles
	_racers = racers
	_config = config
	_dir = out_dir
	DirAccess.make_dir_recursive_absolute(_dir)
	_build_scene()
	for row in 3:
		var node := Node3D.new()
		add_child(node)
		_row_nodes.append(node)
	for i in _racers.count():
		_add_kart(CART_ROW, i, 0, i, i, _racers.racer_at(i))
		_add_kart(BIKE_ROW, i, 1, i, i, _racers.racer_at(i))
	for slot in _config.kart_colors.size():
		_add_kart(SLOT_ROW, slot, slot % 2, slot, slot, _racers.racer_at(slot))
	_build_pennant_sheet()
	await _shots()
	get_tree().quit()


func _build_scene() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.45, 0.68, 0.9)
	sky_mat.sky_horizon_color = Color(0.75, 0.87, 0.95)
	sky_mat.ground_horizon_color = Color(0.7, 0.8, 0.7)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.78, 0.85)
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
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(300, 300)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.44, 0.63, 0.35)
	ground.material_override = gm
	add_child(ground)
	_cam = Camera3D.new()
	_cam.far = 600.0
	add_child(_cam)
	_cam.current = true


# Twelve bare pennants side by side, flags face-on to a camera on +X: the 12 slot patterns.
func _build_pennant_sheet() -> void:
	_sheet = Node3D.new()
	_sheet.position = Vector3(0, 0, 40.0)
	add_child(_sheet)
	for slot in _config.kart_colors.size():
		var pen := Pennant.new()
		pen.position = Vector3(0, 0, (float(slot) - 5.5) * 1.7 - 0.5)
		_sheet.add_child(pen)
		pen.build(_racers.pennant, 1.9, slot, _config.kart_colors[slot])
	_sheet.visible = false


func _row_z(row: int) -> float:
	return [0.0, -9.0, 10.0][row]


func _add_kart(row: int, index: int, vehicle: int, slot: int, _unused: int, racer: RacerDef) -> void:
	var stats: VehicleStats = _vehicles.vehicle_at(vehicle).duplicate()
	var color: Color = _config.kart_colors[slot % _config.kart_colors.size()]
	stats.paint_color = color
	var sim := KartSim.new(stats)
	var count: int = _racers.count() if row != SLOT_ROW else _config.kart_colors.size()
	var x: float = (float(index) - float(count - 1) * 0.5) * SPACING
	sim.position = Vector2(x, _row_z(row))
	sim.yaw = 0.0
	sim._prev_position = sim.position
	sim._prev_yaw = 0.0
	var visual := KartVisual.new()
	_row_nodes[row].add_child(visual)
	visual.bind(sim, racer, _racers.pennant)
	visual.apply_identity(slot, color)
	_rows[row].append({"visual": visual, "pos": Vector3(x, 0.0, _row_z(row)), "slug": String(racer.slug),
			"vehicle": String(stats.vehicle_id), "slot": slot})


func _show_only(row: int, index: int = -1) -> void:
	_sheet.visible = false
	for r in 3:
		_row_nodes[r].visible = r == row
		for k in _rows[r].size():
			(_rows[r][k].visual as KartVisual).visible = index < 0 or k == index


func _frame(name_: String) -> void:
	for i in FRAMES_TO_SETTLE:
		await get_tree().process_frame
	var path: String = "%s/%s.png" % [_dir, name_]
	var err: Error = get_viewport().get_texture().get_image().save_png(path)
	print("[lineup] %s (err %d)" % [path, err])


func _shots() -> void:
	# Whole rows from behind and above, like a chase camera pulled back to fit the row.
	for row in 2:
		var z: float = _row_z(row)
		_show_only(row)
		_cam.fov = 72.0
		_cam.look_at_from_position(Vector3(0, 4.5, z + 17.0), Vector3(0, 1.0, z))
		await _frame("row_%s_chase" % ("cart" if row == CART_ROW else "bike"))
		_cam.look_at_from_position(Vector3(0, 5.0, z - 17.0), Vector3(0, 1.0, z))
		await _frame("row_%s_front" % ("cart" if row == CART_ROW else "bike"))
	_row_nodes[CART_ROW].visible = true
	_row_nodes[BIKE_ROW].visible = true
	_row_nodes[SLOT_ROW].visible = false
	_cam.fov = 70.0
	_cam.look_at_from_position(Vector3(0, 11.0, 19.0), Vector3(0, 0.5, -4.5))
	await _frame("both_rows")
	_show_only(SLOT_ROW)
	var zs: float = _row_z(SLOT_ROW)
	_cam.fov = 78.0
	_cam.look_at_from_position(Vector3(0, 4.5, zs + 19.0), Vector3(0, 1.2, zs))
	await _frame("slots12_chase")
	_cam.look_at_from_position(Vector3(0, 15.0, zs + 14.0), Vector3(0, 1.0, zs))
	await _frame("slots12_high")
	_sheet.visible = true
	for r in 3:
		_row_nodes[r].visible = false
	_cam.fov = 60.0
	_cam.look_at_from_position(Vector3(17.0, 1.7, 40.0), Vector3(0, 1.2, 40.0))
	await _frame("pennant_sheet")
	# Per kart: a chase-camera view (behind, like the game camera) and a close 3/4 from the front.
	for row in 2:
		for k in _rows[row].size():
			var info: Dictionary = _rows[row][k]
			var p: Vector3 = info.pos
			_show_only(row, k)
			_cam.fov = 68.0
			_cam.look_at_from_position(p + Vector3(0, 2.7, 6.0), p + Vector3(0, 1.0, -4.0))
			await _frame("chase_%s_%s" % [info.vehicle, info.slug])
			_cam.fov = 50.0
			_cam.look_at_from_position(p + Vector3(2.6, 1.9, -3.6), p + Vector3(0, 1.0, 0.2))
			await _frame("close34_%s_%s" % [info.vehicle, info.slug])
