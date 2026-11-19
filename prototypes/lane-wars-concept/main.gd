# PROTOTYPE - NOT FOR PRODUCTION
# Question: Is building a tower maze in one lane fun and readable from an angled 3D camera?
# Date: 2026-11-19
#
# Everything is built from code in this one script: hardcoded values, no architecture.
# Run: C:/Godot/Godot_v4.8-beta3_win64.exe --path prototypes/lane-wars-concept
# Debug: append `-- --demo` to start with a sample maze and wave 1 running.
extends Node3D

# --- Tuning (all hardcoded on purpose: this is a throwaway prototype) ---
const W := 11
const H := 22
const SPAWN := Vector2i(5, 0)
const GOAL := Vector2i(5, 21)
const TOWER_COST := 10
const START_GOLD := 100
const START_LIVES := 20
const KILL_GOLD := 1
const WAVE_BONUS_BASE := 20
const WAVE_BONUS_PER_WAVE := 5
const WAVES := 10
const CREEP_SPEED := 2.0
const CREEP_HP_BASE := 30.0
const CREEP_HP_GROWTH := 1.35
const CREEPS_BASE := 10
const CREEPS_PER_WAVE := 2
const SPAWN_INTERVAL := 0.8
const TOWER_DAMAGE := 10.0
const TOWER_RANGE := 2.5
const TOWER_COOLDOWN := 1.0
const BULLET_SPEED := 12.0
const SELL_REFUND_DURING_WAVE := 0.5
const CAM_PITCH_DEG := 55.0
const NO_CELL := Vector2i(-1, -1)

var astar := AStarGrid2D.new()
var towers: Dictionary = {}   # Vector2i -> {"node", "cooldown"}
var creeps: Array = []        # of {"node", "bar", "hp", "max_hp", "path", "idx", "dead"}
var bullets: Array = []       # of {"node", "target"}
var current_path: Array[Vector2i] = []
var preview_len := -1

var gold := START_GOLD
var lives := START_LIVES
var wave := 0
var in_wave := false
var finished := false
var spawn_left := 0
var spawn_timer := 0.0

# Playtest evidence counters
var built_since_wave := 0
var sold_since_wave := 0
var snap_path_len := 0
var snap_towers := 0
var snap_built := 0
var snap_sold := 0
var kills_this_wave := 0
var leaks_this_wave := 0
var log_path := ""

var hover_cell := NO_CELL
var cam_target := Vector3(W / 2.0, 0.0, H / 2.0 + 2.5)
var cam_dist := 27.0
var message := ""
var message_time := 0.0

var camera: Camera3D
var hud: Label
var msg_label: Label
var help_label: Label
var ghost: MeshInstance3D
var range_ring: MeshInstance3D
var path_mesh := ImmediateMesh.new()
var preview_mesh := ImmediateMesh.new()

var mat_path: StandardMaterial3D
var mat_preview: StandardMaterial3D
var mat_ghost_ok: StandardMaterial3D
var mat_ghost_bad: StandardMaterial3D
var mat_tower_base: StandardMaterial3D
var mat_tower_top: StandardMaterial3D
var mat_creep: StandardMaterial3D
var mat_hp: StandardMaterial3D
var mat_bullet: StandardMaterial3D
var mat_range: StandardMaterial3D

var tower_base_mesh := BoxMesh.new()
var tower_top_mesh := CylinderMesh.new()
var creep_mesh := SphereMesh.new()
var hp_mesh := BoxMesh.new()
var bullet_mesh := SphereMesh.new()


func _ready() -> void:
	astar.region = Rect2i(0, 0, W, H)
	astar.cell_size = Vector2(1, 1)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	astar.update()

	_make_materials()
	_build_world()
	_build_hud()
	_open_log()
	_recompute_path()
	_say("Build a maze: make the creeps walk the long way. Press Space to send wave 1.", 8.0)

	if OS.get_cmdline_user_args().has("--demo"):
		_build_demo_maze()
		_start_wave()


# ---------------------------------------------------------------- setup

func _mat(c: Color, unshaded := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	if c.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _make_materials() -> void:
	mat_path = _mat(Color(1.0, 0.85, 0.2), true)
	mat_preview = _mat(Color(0.3, 0.9, 1.0, 0.75), true)
	mat_ghost_ok = _mat(Color(0.4, 0.8, 1.0, 0.45))
	mat_ghost_bad = _mat(Color(1.0, 0.25, 0.25, 0.45))
	mat_tower_base = _mat(Color(0.35, 0.45, 0.75))
	mat_tower_top = _mat(Color(0.75, 0.82, 0.95))
	mat_creep = _mat(Color(0.95, 0.45, 0.15))
	mat_hp = _mat(Color(0.3, 1.0, 0.3), true)
	mat_bullet = _mat(Color(1.0, 1.0, 0.7), true)
	mat_range = _mat(Color(0.4, 0.8, 1.0, 0.18), true)

	tower_base_mesh.size = Vector3(0.86, 0.5, 0.86)
	tower_top_mesh.top_radius = 0.18
	tower_top_mesh.bottom_radius = 0.26
	tower_top_mesh.height = 0.5
	creep_mesh.radius = 0.26
	creep_mesh.height = 0.52
	hp_mesh.size = Vector3(0.6, 0.06, 0.06)
	bullet_mesh.radius = 0.08
	bullet_mesh.height = 0.16


func _build_world() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.08, 0.10, 0.13)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.8, 0.9)
	env.ambient_light_energy = 0.55
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -35, 0)
	sun.shadow_enabled = true
	add_child(sun)

	camera = Camera3D.new()
	camera.fov = 50.0
	add_child(camera)
	_update_camera()

	# Grid tiles: checkerboard so cells are countable from the angled camera.
	var tile_mesh := BoxMesh.new()
	tile_mesh.size = Vector3(0.96, 0.1, 0.96)
	var m_a := _mat(Color(0.30, 0.42, 0.28))
	var m_b := _mat(Color(0.26, 0.37, 0.24))
	var m_spawn := _mat(Color(0.25, 0.6, 0.35))
	var m_goal := _mat(Color(0.7, 0.25, 0.25))
	for x in W:
		for z in H:
			var c := Vector2i(x, z)
			var t := MeshInstance3D.new()
			t.mesh = tile_mesh
			if c == SPAWN:
				t.material_override = m_spawn
			elif c == GOAL:
				t.material_override = m_goal
			else:
				t.material_override = m_a if (x + z) % 2 == 0 else m_b
			t.position = _cell_center(c, -0.05)
			add_child(t)

	# Lane walls, spawn portal, base.
	var wall_mesh := BoxMesh.new()
	wall_mesh.size = Vector3(0.3, 0.5, H + 0.6)
	var m_wall := _mat(Color(0.45, 0.42, 0.38))
	for wx in [-0.15, W + 0.15]:
		var wall := MeshInstance3D.new()
		wall.mesh = wall_mesh
		wall.material_override = m_wall
		wall.position = Vector3(wx, 0.25, H / 2.0)
		add_child(wall)

	var portal_mesh := BoxMesh.new()
	portal_mesh.size = Vector3(1.6, 1.2, 0.3)
	var portal := MeshInstance3D.new()
	portal.mesh = portal_mesh
	portal.material_override = _mat(Color(0.3, 0.9, 0.5))
	portal.position = Vector3(SPAWN.x + 0.5, 0.6, -0.3)
	add_child(portal)

	var base_mesh := BoxMesh.new()
	base_mesh.size = Vector3(2.4, 1.4, 1.2)
	var base := MeshInstance3D.new()
	base.mesh = base_mesh
	base.material_override = _mat(Color(0.85, 0.3, 0.3))
	base.position = Vector3(GOAL.x + 0.5, 0.7, H + 0.7)
	add_child(base)

	# Path ribbons.
	var path_mi := MeshInstance3D.new()
	path_mi.mesh = path_mesh
	path_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(path_mi)
	var prev_mi := MeshInstance3D.new()
	prev_mi.mesh = preview_mesh
	prev_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(prev_mi)

	# Placement ghost and range ring.
	ghost = MeshInstance3D.new()
	ghost.mesh = tower_base_mesh
	ghost.material_override = mat_ghost_ok
	ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ghost.visible = false
	add_child(ghost)
	var ring_mesh := CylinderMesh.new()
	ring_mesh.top_radius = TOWER_RANGE
	ring_mesh.bottom_radius = TOWER_RANGE
	ring_mesh.height = 0.02
	range_ring = MeshInstance3D.new()
	range_ring.mesh = ring_mesh
	range_ring.material_override = mat_range
	range_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	range_ring.visible = false
	add_child(range_ring)


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Label.new()
	hud.position = Vector2(16, 12)
	hud.add_theme_font_size_override("font_size", 20)
	hud.add_theme_color_override("font_outline_color", Color.BLACK)
	hud.add_theme_constant_override("outline_size", 6)
	layer.add_child(hud)
	msg_label = Label.new()
	msg_label.position = Vector2(16, 110)
	msg_label.add_theme_font_size_override("font_size", 22)
	msg_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.4))
	msg_label.add_theme_color_override("font_outline_color", Color.BLACK)
	msg_label.add_theme_constant_override("outline_size", 6)
	layer.add_child(msg_label)
	help_label = Label.new()
	help_label.text = "LMB build (%dg)\nRMB sell (100%% between waves, 50%% during)\nSpace send wave\nWheel zoom   WASD pan\nF speed x2" % TOWER_COST
	help_label.anchor_top = 1.0
	help_label.anchor_bottom = 1.0
	help_label.offset_left = 16
	help_label.offset_top = -150
	help_label.add_theme_font_size_override("font_size", 18)
	help_label.add_theme_color_override("font_color", Color(0.85, 0.88, 0.95))
	help_label.add_theme_color_override("font_outline_color", Color.BLACK)
	help_label.add_theme_constant_override("outline_size", 5)
	layer.add_child(help_label)


func _open_log() -> void:
	log_path = ProjectSettings.globalize_path("res://playtest_log.csv")
	var f: FileAccess
	if FileAccess.file_exists(log_path):
		f = FileAccess.open(log_path, FileAccess.READ_WRITE)
		f.seek_end()
	else:
		f = FileAccess.open(log_path, FileAccess.WRITE)
		f.store_line("session,wave,result,path_len,straight_line,towers,built_before_wave,sold_before_wave,kills,leaks,lives_after,gold_after")
	f.close()


func _build_demo_maze() -> void:
	# A simple serpentine: alternate walls with a gap on the left, then the right.
	for row in [4, 8, 12, 16]:
		var gap_left: bool = (row / 4) % 2 == 1
		for x in W:
			if (gap_left and x == 0) or (not gap_left and x == W - 1):
				continue
			gold += TOWER_COST
			_try_place(Vector2i(x, row))


# ---------------------------------------------------------------- frame loop

func _process(delta: float) -> void:
	_pan_camera(delta)
	_update_hover()
	if not finished:
		if in_wave:
			_update_spawning(delta)
		_update_creeps(delta)
		_update_towers(delta)
		_update_bullets(delta)
		if in_wave and spawn_left == 0 and creeps.is_empty():
			_end_wave()
	message_time -= delta
	_update_hud()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and not finished:
			_try_place(_mouse_cell())
		elif mb.button_index == MOUSE_BUTTON_RIGHT and not finished:
			_try_sell(_mouse_cell())
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			cam_dist = maxf(10.0, cam_dist - 1.5)
			_update_camera()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			cam_dist = minf(40.0, cam_dist + 1.5)
			_update_camera()
	elif event is InputEventKey and event.pressed and not event.echo:
		var k := event as InputEventKey
		if k.keycode == KEY_SPACE:
			_start_wave()
		elif k.keycode == KEY_F:
			Engine.time_scale = 1.0 if Engine.time_scale > 1.0 else 2.0


# ---------------------------------------------------------------- camera and hover

func _update_camera() -> void:
	var pitch := deg_to_rad(CAM_PITCH_DEG)
	camera.position = cam_target + Vector3(0.0, sin(pitch) * cam_dist, cos(pitch) * cam_dist)
	camera.look_at(cam_target, Vector3.UP)


func _pan_camera(delta: float) -> void:
	var d := Vector3.ZERO
	if Input.is_key_pressed(KEY_W): d.z -= 1
	if Input.is_key_pressed(KEY_S): d.z += 1
	if Input.is_key_pressed(KEY_A): d.x -= 1
	if Input.is_key_pressed(KEY_D): d.x += 1
	if d == Vector3.ZERO:
		return
	# Unscaled speed so panning does not change with the x2 toggle.
	cam_target += d.normalized() * 10.0 * delta / Engine.time_scale
	cam_target.x = clampf(cam_target.x, 0.0, W)
	cam_target.z = clampf(cam_target.z, 0.0, H + 2.0)
	_update_camera()


func _mouse_cell() -> Vector2i:
	var mp := get_viewport().get_mouse_position()
	var o := camera.project_ray_origin(mp)
	var d := camera.project_ray_normal(mp)
	var hit = Plane(Vector3.UP, 0.0).intersects_ray(o, d)
	if hit == null:
		return NO_CELL
	var c := Vector2i(floori(hit.x), floori(hit.z))
	return c if _in_bounds(c) else NO_CELL


func _update_hover() -> void:
	var c := _mouse_cell()
	if c == hover_cell:
		return
	hover_cell = c
	_refresh_hover()


func _refresh_hover() -> void:
	preview_mesh.clear_surfaces()
	preview_len = -1
	ghost.visible = false
	range_ring.visible = false
	var c := hover_cell
	if c == NO_CELL or finished:
		return
	range_ring.position = _cell_center(c, 0.02)
	range_ring.visible = true
	if towers.has(c):
		return
	ghost.position = _cell_center(c, 0.25)
	ghost.visible = true
	var problem := _placement_problem(c)
	ghost.material_override = mat_ghost_ok if problem == "" else mat_ghost_bad
	if problem == "" or problem == "Not enough gold":
		# Show the path as it would be after building here: the "clever" moment.
		astar.set_point_solid(c, true)
		var p: Array[Vector2i] = astar.get_id_path(SPAWN, GOAL)
		astar.set_point_solid(c, false)
		if not p.is_empty() and p != current_path:
			_draw_ribbon(preview_mesh, p, mat_preview, 0.05, 0.12)
			preview_len = p.size() - 1


# ---------------------------------------------------------------- building

func _placement_problem(c: Vector2i) -> String:
	if not _in_bounds(c):
		return "Outside the lane"
	if c == SPAWN or c == GOAL:
		return "Can't build on the entrance or the base"
	if towers.has(c):
		return "Already a tower here"
	for cr in creeps:
		if _creep_cells(cr).has(c):
			return "A creep is standing there"
	astar.set_point_solid(c, true)
	var ok := not astar.get_id_path(SPAWN, GOAL).is_empty()
	if ok:
		for cr in creeps:
			if astar.get_id_path(cr.path[cr.idx], GOAL).is_empty():
				ok = false
				break
	astar.set_point_solid(c, false)
	if not ok:
		return "That would block the path - creeps must always have a way through"
	if gold < TOWER_COST:
		return "Not enough gold"
	return ""


func _try_place(c: Vector2i) -> void:
	if c == NO_CELL:
		return
	var problem := _placement_problem(c)
	if problem != "":
		_say(problem)
		return
	gold -= TOWER_COST
	astar.set_point_solid(c, true)
	var n := Node3D.new()
	var b := MeshInstance3D.new()
	b.mesh = tower_base_mesh
	b.material_override = mat_tower_base
	b.position.y = 0.25
	n.add_child(b)
	var t := MeshInstance3D.new()
	t.mesh = tower_top_mesh
	t.material_override = mat_tower_top
	t.position.y = 0.75
	n.add_child(t)
	n.position = _cell_center(c, 0.0)
	add_child(n)
	towers[c] = {"node": n, "cooldown": 0.0}
	built_since_wave += 1
	_on_maze_changed()


func _try_sell(c: Vector2i) -> void:
	if not towers.has(c):
		return
	var refund := TOWER_COST if not in_wave else int(TOWER_COST * SELL_REFUND_DURING_WAVE)
	gold += refund
	towers[c].node.queue_free()
	towers.erase(c)
	astar.set_point_solid(c, false)
	sold_since_wave += 1
	_on_maze_changed()


func _on_maze_changed() -> void:
	_recompute_path()
	for cr in creeps:
		var np: Array[Vector2i] = astar.get_id_path(cr.path[cr.idx], GOAL)
		if not np.is_empty():
			cr.path = np
			cr.idx = 0
	_refresh_hover()


func _recompute_path() -> void:
	current_path = astar.get_id_path(SPAWN, GOAL)
	_draw_ribbon(path_mesh, current_path, mat_path, 0.03, 0.2)


# ---------------------------------------------------------------- waves and creeps

func _start_wave() -> void:
	if in_wave or finished:
		return
	wave += 1
	in_wave = true
	spawn_left = CREEPS_BASE + CREEPS_PER_WAVE * (wave - 1)
	spawn_timer = 0.0
	snap_path_len = current_path.size() - 1
	snap_towers = towers.size()
	snap_built = built_since_wave
	snap_sold = sold_since_wave
	built_since_wave = 0
	sold_since_wave = 0
	kills_this_wave = 0
	leaks_this_wave = 0
	_say("Wave %d: %d creeps" % [wave, spawn_left], 3.0)


func _end_wave() -> void:
	in_wave = false
	var bonus := WAVE_BONUS_BASE + WAVE_BONUS_PER_WAVE * wave
	gold += bonus
	_write_log("cleared")
	if wave >= WAVES:
		finished = true
		_say("All %d waves survived with %d lives. Results: playtest_log.csv" % [WAVES, lives], 9999.0)
	else:
		_say("Wave %d cleared, +%d gold. Reshape your maze (selling refunds 100%% now), then press Space." % [wave, bonus], 9999.0)


func _update_spawning(delta: float) -> void:
	if spawn_left <= 0:
		return
	spawn_timer -= delta
	if spawn_timer > 0.0:
		return
	spawn_timer = SPAWN_INTERVAL
	spawn_left -= 1
	var hp := CREEP_HP_BASE * pow(CREEP_HP_GROWTH, wave - 1)
	var n := Node3D.new()
	var body := MeshInstance3D.new()
	body.mesh = creep_mesh
	body.material_override = mat_creep
	body.position.y = 0.3
	n.add_child(body)
	var bar := MeshInstance3D.new()
	bar.mesh = hp_mesh
	bar.material_override = mat_hp
	bar.position.y = 0.75
	n.add_child(bar)
	n.position = _cell_center(SPAWN, 0.0)
	add_child(n)
	creeps.append({"node": n, "bar": bar, "hp": hp, "max_hp": hp,
		"path": current_path.duplicate(), "idx": mini(1, current_path.size() - 1), "dead": false})


func _update_creeps(delta: float) -> void:
	for i in range(creeps.size() - 1, -1, -1):
		var cr = creeps[i]
		var n: Node3D = cr.node
		var target := _cell_center(cr.path[cr.idx], 0.0)
		var to := target - n.position
		var step := CREEP_SPEED * delta
		if to.length() <= step:
			n.position = target
			cr.idx += 1
			if cr.idx >= cr.path.size():
				_leak(cr)
		else:
			n.position += to.normalized() * step


func _creep_cells(cr) -> Array:
	var p: Vector3 = cr.node.position
	return [Vector2i(floori(p.x), floori(p.z)), cr.path[mini(cr.idx, cr.path.size() - 1)]]


func _leak(cr) -> void:
	lives -= 1
	leaks_this_wave += 1
	_remove_creep(cr)
	if lives <= 0 and not finished:
		finished = true
		in_wave = false
		_write_log("base destroyed")
		_say("Base destroyed on wave %d. Results: playtest_log.csv" % wave, 9999.0)


func _damage(cr, dmg: float) -> void:
	if cr.dead:
		return
	cr.hp -= dmg
	var bar: MeshInstance3D = cr.bar
	bar.scale.x = maxf(cr.hp / cr.max_hp, 0.01)
	if cr.hp <= 0.0:
		gold += KILL_GOLD
		kills_this_wave += 1
		_remove_creep(cr)


func _remove_creep(cr) -> void:
	cr.dead = true
	cr.node.queue_free()
	for j in creeps.size():
		if is_same(creeps[j], cr):
			creeps.remove_at(j)
			break


# ---------------------------------------------------------------- towers and bullets

func _update_towers(delta: float) -> void:
	for c in towers:
		var t = towers[c]
		t.cooldown -= delta
		if t.cooldown > 0.0:
			continue
		var tp := _cell_center(c, 0.0)
		var best = null
		var best_rem := 1 << 30
		for cr in creeps:
			var cp: Vector3 = cr.node.position
			if tp.distance_to(cp) <= TOWER_RANGE:
				var rem: int = cr.path.size() - cr.idx
				if rem < best_rem:
					best_rem = rem
					best = cr
		if best == null:
			continue
		t.cooldown = TOWER_COOLDOWN
		var b := MeshInstance3D.new()
		b.mesh = bullet_mesh
		b.material_override = mat_bullet
		b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		b.position = _cell_center(c, 0.95)
		add_child(b)
		bullets.append({"node": b, "target": best})


func _update_bullets(delta: float) -> void:
	for i in range(bullets.size() - 1, -1, -1):
		var b = bullets[i]
		var tgt = b.target
		var bn: MeshInstance3D = b.node
		if tgt.dead:
			bn.queue_free()
			bullets.remove_at(i)
			continue
		var tn: Node3D = tgt.node
		var aim := tn.position + Vector3(0.0, 0.3, 0.0)
		var to := aim - bn.position
		var step := BULLET_SPEED * delta
		if to.length() <= step:
			bn.queue_free()
			bullets.remove_at(i)
			_damage(tgt, TOWER_DAMAGE)
		else:
			bn.position += to.normalized() * step


# ---------------------------------------------------------------- HUD, log, helpers

func _update_hud() -> void:
	var straight := GOAL.y - SPAWN.y
	var path_len := current_path.size() - 1
	var lines: Array[String] = []
	lines.append("Wave %d/%d    Lives %d    Gold %d    Towers %d    Speed x%d" % [wave, WAVES, lives, gold, towers.size(), int(Engine.time_scale)])
	var path_line := "Path: %d cells  (straight line = %d, maze adds +%d%%)" % [path_len, straight, int(round(100.0 * (path_len - straight) / straight))]
	if preview_len >= 0:
		path_line += "    build here -> %d (%+d)" % [preview_len, preview_len - path_len]
	lines.append(path_line)
	if finished:
		lines.append("Done.")
	elif in_wave:
		lines.append("WAVE %d - %d creeps on the field, %d still to come" % [wave, creeps.size(), spawn_left])
	else:
		lines.append("BUILD PHASE - press Space to send wave %d" % (wave + 1))
	hud.text = "\n".join(lines)
	msg_label.text = message if message_time > 0.0 else ""


func _say(text: String, seconds := 2.5) -> void:
	message = text
	message_time = seconds


func _write_log(result: String) -> void:
	if OS.get_cmdline_user_args().has("--demo"):
		return  # Demo runs are for screenshots, not playtest evidence.
	var f := FileAccess.open(log_path, FileAccess.READ_WRITE)
	f.seek_end()
	f.store_line("%s,%d,%s,%d,%d,%d,%d,%d,%d,%d,%d,%d" % [
		Time.get_datetime_string_from_system(), wave, result, snap_path_len, GOAL.y - SPAWN.y,
		snap_towers, snap_built, snap_sold, kills_this_wave, leaks_this_wave, lives, gold])
	f.close()
	print("[playtest] wave %d %s | path %d | towers %d | built %d sold %d before wave | kills %d leaks %d | lives %d gold %d" % [
		wave, result, snap_path_len, snap_towers, snap_built, snap_sold, kills_this_wave, leaks_this_wave, lives, gold])


func _draw_ribbon(im: ImmediateMesh, path: Array[Vector2i], m: Material, y: float, width: float) -> void:
	im.clear_surfaces()
	if path.size() < 2:
		return
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES, m)
	for i in range(path.size() - 1):
		var a := _cell_center(path[i], y)
		var b := _cell_center(path[i + 1], y)
		var d := (b - a).normalized()
		var side := Vector3(-d.z, 0.0, d.x) * width * 0.5
		a -= d * width * 0.5
		b += d * width * 0.5
		im.surface_add_vertex(a + side)
		im.surface_add_vertex(b + side)
		im.surface_add_vertex(b - side)
		im.surface_add_vertex(a + side)
		im.surface_add_vertex(b - side)
		im.surface_add_vertex(a - side)
	im.surface_end()


func _cell_center(c: Vector2i, y: float) -> Vector3:
	return Vector3(c.x + 0.5, y, c.y + 0.5)


func _in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.x < W and c.y >= 0 and c.y < H
