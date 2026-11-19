# PROTOTYPE - NOT FOR PRODUCTION
# Question: Do drift-for-boost handling plus items make races feel skillful and chaotic?
# Date: 2026-11-19
#
# Everything except the kart lives here: track generation, race rules, bots, items,
# camera, HUD, minimap and the race log. Hardcoded values, no architecture.
# Run: play.bat, or  & "C:/Godot/Godot_v4.8-beta3_win64.exe" --path prototypes/kart-concept
# Debug args (after --): --demo (the player kart drives itself), --overview (top-down camera)
extends Node3D

const KartScript := preload("res://kart.gd")

# --- Race and track tuning ---
const LAPS := 3
const ROAD_HALF_WIDTH := 7.0
const CURB_WIDTH := 1.2
const SAMPLES_PER_SEG := 20
const CTRL := [
	Vector2(-40, 0), Vector2(60, 0), Vector2(130, 15), Vector2(160, 70),
	Vector2(130, 125), Vector2(70, 130), Vector2(40, 95), Vector2(0, 110),
	Vector2(-50, 150), Vector2(-110, 130), Vector2(-120, 70), Vector2(-90, 25),
]
const COUNTDOWN := 3.0
const ITEM_ROWS := [0.22, 0.5, 0.78]          # fraction of the lap
const ITEM_RESPAWN := 3.0
const ROULETTE_TIME := 1.0
const NITRO_TIME := 1.5
const BOUNCER_SPEED := 45.0
const BOUNCER_LIFE := 6.0
const OIL_LIFE := 25.0
const BOT_NAMES := ["Rook", "Vela", "Tamsin"]
const BOT_COLORS := [Color(0.25, 0.5, 1.0), Color(0.25, 0.8, 0.35), Color(1.0, 0.85, 0.2)]
const BOT_SKILL := [0.97, 0.95, 0.99]

var wall_offset := ROAD_HALF_WIDTH + CURB_WIDTH

# Track data (XZ plane as Vector2)
var pts := PackedVector2Array()
var cum := PackedFloat32Array()
var track_len := 0.0

var karts: Array = []
var player
var mode := "race"                 # "race" or "time_trial"
var demo := false
var overview := false
var race_time := -COUNTDOWN
var race_started := false
var race_over := false
var leader = null
var lead_changes := 0
var item_boxes: Array = []        # {pos, node, respawn}
var bouncers: Array = []          # {pos, vel, seg, life, owner, node}
var oils: Array = []              # {pos, life, owner, grace, node}
var roulette_names := ["Nitro", "Bouncer", "Oil slick"]

var camera: Camera3D
var cam_pos := Vector3.ZERO
var hud_left: Label
var hud_pos: Label
var hud_item: Label
var hud_center: Label
var hud_help: Label
var drift_bar: ColorRect
var drift_bar_bg: ColorRect
var minimap: Control
var log_path := ""
var shot_dir := ""                 # debug: --shots=<dir> saves screenshots at SHOT_TIMES
var shot_times := [9.0, 13.0, 17.0, 21.0, 40.0, 60.0]


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	demo = args.has("--demo")
	overview = args.has("--overview")
	for a in args:
		if a.begins_with("--shots="):
			shot_dir = a.substr(8)
	if args.has("--fast"):
		Engine.time_scale = 3.0
	mode = Engine.get_meta("kart_mode", "race")
	_setup_input()
	_build_centerline()
	_build_world()
	_build_track_mesh()
	_spawn_karts()
	if mode == "race":
		_spawn_item_boxes()
	_build_hud()
	_open_log()
	cam_pos = _chase_target()


# ---------------------------------------------------------------- input

func _setup_input() -> void:
	_action("accel", [KEY_W, KEY_UP], [], [[JOY_AXIS_TRIGGER_RIGHT, 1.0]])
	_action("brake", [KEY_S, KEY_DOWN], [], [[JOY_AXIS_TRIGGER_LEFT, 1.0]])
	_action("steer_left", [KEY_A, KEY_LEFT], [], [[JOY_AXIS_LEFT_X, -1.0]])
	_action("steer_right", [KEY_D, KEY_RIGHT], [], [[JOY_AXIS_LEFT_X, 1.0]])
	_action("drift", [KEY_SPACE, KEY_SHIFT], [JOY_BUTTON_RIGHT_SHOULDER, JOY_BUTTON_B], [])
	_action("item", [KEY_E, KEY_CTRL], [JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_X], [])
	_action("restart", [KEY_R], [JOY_BUTTON_START], [])
	_action("toggle_mode", [KEY_T], [JOY_BUTTON_BACK], [])


func _action(name: String, keys: Array, buttons: Array, axes: Array) -> void:
	if InputMap.has_action(name):
		return
	InputMap.add_action(name, 0.2)
	for k in keys:
		var e := InputEventKey.new()
		e.physical_keycode = k
		InputMap.action_add_event(name, e)
	for b in buttons:
		var e := InputEventJoypadButton.new()
		e.button_index = b
		InputMap.action_add_event(name, e)
	for a in axes:
		var e := InputEventJoypadMotion.new()
		e.axis = a[0]
		e.axis_value = a[1]
		InputMap.action_add_event(name, e)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("restart"):
		Engine.time_scale = 1.0
		get_tree().reload_current_scene()
	elif event.is_action_pressed("toggle_mode"):
		Engine.set_meta("kart_mode", "time_trial" if mode == "race" else "race")
		get_tree().reload_current_scene()


# ---------------------------------------------------------------- track

func _catmull(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)


func _build_centerline() -> void:
	var n := CTRL.size()
	for i in n:
		var p0: Vector2 = CTRL[(i - 1 + n) % n]
		var p1: Vector2 = CTRL[i]
		var p2: Vector2 = CTRL[(i + 1) % n]
		var p3: Vector2 = CTRL[(i + 2) % n]
		for k in SAMPLES_PER_SEG:
			pts.append(_catmull(p0, p1, p2, p3, float(k) / SAMPLES_PER_SEG))
	cum.resize(pts.size() + 1)
	cum[0] = 0.0
	for i in pts.size():
		cum[i + 1] = cum[i] + pts[i].distance_to(pts[(i + 1) % pts.size()])
	track_len = cum[pts.size()]


func track_query(p: Vector2, hint: int) -> Dictionary:
	var n := pts.size()
	var best_i := hint
	var best_d := INF
	var best_t := 0.0
	var window := 14 if hint >= 0 else n
	var start := hint if hint >= 0 else 0
	for o in range(-window, window + 1):
		var i := posmod(start + o, n)
		var a := pts[i]
		var ab := pts[(i + 1) % n] - a
		var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		var d := p.distance_squared_to(a + ab * t)
		if d < best_d:
			best_d = d
			best_i = i
			best_t = t
	var a2 := pts[best_i]
	var b2 := pts[(best_i + 1) % n]
	var tan := (b2 - a2).normalized()
	var nrm := Vector2(-tan.y, tan.x)
	var proj := a2.lerp(b2, best_t)
	return {"seg": best_i, "s": cum[best_i] + a2.distance_to(b2) * best_t,
		"lat": (p - proj).dot(nrm), "tan": tan, "nrm": nrm}


func point_at(dist: float) -> Vector2:
	var sv := fposmod(dist, track_len)
	var lo := 0
	var hi := pts.size() - 1
	while lo < hi:
		var mid := (lo + hi + 1) >> 1
		if cum[mid] <= sv:
			lo = mid
		else:
			hi = mid - 1
	var a := pts[lo]
	var b := pts[(lo + 1) % pts.size()]
	return a.lerp(b, (sv - cum[lo]) / (cum[lo + 1] - cum[lo]))


func tangent_at(dist: float) -> Vector2:
	return (point_at(dist + 1.0) - point_at(dist - 1.0)).normalized()


func normal_at(dist: float) -> Vector2:
	var t := tangent_at(dist)
	return Vector2(-t.y, t.x)


func _v3(p: Vector2, y := 0.0) -> Vector3:
	return Vector3(p.x, y, p.y)


# ---------------------------------------------------------------- world building

func _build_world() -> void:
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

	var center := Vector2.ZERO
	for c in CTRL:
		center += c
	center /= CTRL.size()
	var ground := MeshInstance3D.new()
	var gm := PlaneMesh.new()
	gm.size = Vector2(700, 700)
	ground.mesh = gm
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.32, 0.55, 0.25)
	ground.material_override = gmat
	ground.position = _v3(center, -0.05)
	add_child(ground)

	camera = Camera3D.new()
	camera.fov = 70.0
	camera.far = 1500.0
	add_child(camera)


func _build_track_mesh() -> void:
	var n := pts.size()
	var normals: Array[Vector2] = []
	for i in n:
		var t := (pts[(i + 1) % n] - pts[(i - 1 + n) % n]).normalized()
		normals.append(Vector2(-t.y, t.x))

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	var road := Color(0.22, 0.22, 0.25)
	for i in n:
		var j := (i + 1) % n
		var a := pts[i]
		var b := pts[j]
		var na := normals[i]
		var nb := normals[j]
		# Road
		_quad(st, a + na * ROAD_HALF_WIDTH, a - na * ROAD_HALF_WIDTH, b - nb * ROAD_HALF_WIDTH, b + nb * ROAD_HALF_WIDTH, 0.0, road)
		# Curbs, striped red and white
		var curb := Color(0.85, 0.15, 0.15) if (i / 2) % 2 == 0 else Color(0.95, 0.95, 0.95)
		_quad(st, a + na * wall_offset, a + na * ROAD_HALF_WIDTH, b + nb * ROAD_HALF_WIDTH, b + nb * wall_offset, 0.01, curb)
		_quad(st, a - na * ROAD_HALF_WIDTH, a - na * wall_offset, b - nb * wall_offset, b - nb * ROAD_HALF_WIDTH, 0.01, curb)
	# Start/finish line: checkered strip across the road at s = 0.
	var t0 := tangent_at(0.0)
	var n0 := normal_at(0.0)
	var cells := 10
	for r in 2:
		for c in cells:
			var w0 := -ROAD_HALF_WIDTH + c * (2.0 * ROAD_HALF_WIDTH / cells)
			var w1 := w0 + 2.0 * ROAD_HALF_WIDTH / cells
			var d0 := -1.0 + r * 1.0
			var d1 := d0 + 1.0
			var col := Color.WHITE if (r + c) % 2 == 0 else Color(0.05, 0.05, 0.05)
			var p0 := pts[0] + n0 * w0 + t0 * d0
			var p1 := pts[0] + n0 * w1 + t0 * d0
			var p2 := pts[0] + n0 * w1 + t0 * d1
			var p3 := pts[0] + n0 * w0 + t0 * d1
			_quad(st, p0, p1, p2, p3, 0.02, col)
	var mesh := st.commit()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	add_child(mi)

	# Low walls along both edges.
	var ws := SurfaceTool.new()
	ws.begin(Mesh.PRIMITIVE_TRIANGLES)
	var wall_col := Color(0.75, 0.75, 0.78)
	for i in n:
		var j := (i + 1) % n
		for side in [1.0, -1.0]:
			var a: Vector2 = pts[i] + normals[i] * wall_offset * side
			var b: Vector2 = pts[j] + normals[j] * wall_offset * side
			ws.set_normal(_v3(-normals[i] * side))
			ws.set_color(wall_col if (i / 4) % 2 == 0 else Color(0.6, 0.6, 0.65))
			ws.add_vertex(_v3(a, 0.0))
			ws.add_vertex(_v3(b, 0.0))
			ws.add_vertex(_v3(b, 0.9))
			ws.add_vertex(_v3(a, 0.0))
			ws.add_vertex(_v3(b, 0.9))
			ws.add_vertex(_v3(a, 0.9))
	var wmi := MeshInstance3D.new()
	wmi.mesh = ws.commit()
	var wm := StandardMaterial3D.new()
	wm.vertex_color_use_as_albedo = true
	wm.cull_mode = BaseMaterial3D.CULL_DISABLED
	wmi.material_override = wm
	add_child(wmi)


func _quad(st: SurfaceTool, a: Vector2, b: Vector2, c: Vector2, d: Vector2, y: float, col: Color) -> void:
	st.set_color(col)
	st.set_normal(Vector3.UP)
	st.add_vertex(_v3(a, y))
	st.add_vertex(_v3(b, y))
	st.add_vertex(_v3(c, y))
	st.add_vertex(_v3(a, y))
	st.add_vertex(_v3(c, y))
	st.add_vertex(_v3(d, y))


func _spawn_karts() -> void:
	# 2x2 grid behind the line. The player starts at the back.
	var slots := [[-6.0, 3.5], [-6.0, -3.5], [-12.0, 3.5], [-12.0, -3.5]]
	var count := 4 if mode == "race" else 1
	for i in count:
		var k = KartScript.new()
		k.game = self
		var is_p := i == count - 1
		k.is_player = is_p
		if is_p:
			k.kart_name = "You"
			k.color = Color(0.95, 0.2, 0.2)
		else:
			k.kart_name = BOT_NAMES[i]
			k.color = BOT_COLORS[i]
			k.skill = BOT_SKILL[i]
			k.lane_seed = i * 2.1
		var slot: Array = slots[i] if count > 1 else [-6.0, 0.0]
		var sd: float = track_len + slot[0]
		k.pos = point_at(sd) + normal_at(sd) * slot[1]
		var t := tangent_at(sd)
		k.yaw = atan2(-t.x, -t.y)
		var q := track_query(k.pos, -1)
		k.seg = q.seg
		k.s = q.s
		k.lap = 0
		add_child(k)
		karts.append(k)
		if is_p:
			player = k


func _spawn_item_boxes() -> void:
	var bm := BoxMesh.new()
	bm.size = Vector3(1.2, 1.2, 1.2)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.6, 0.3, 1.0, 0.75)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(0.5, 0.2, 0.9)
	mat.emission_energy_multiplier = 0.8
	for frac in ITEM_ROWS:
		var d: float = track_len * frac
		for off in [-4.5, -1.5, 1.5, 4.5]:
			var p: Vector2 = point_at(d) + normal_at(d) * off
			var node := MeshInstance3D.new()
			node.mesh = bm
			node.material_override = mat
			node.position = _v3(p, 1.0)
			add_child(node)
			item_boxes.append({"pos": p, "node": node, "respawn": 0.0})


# ---------------------------------------------------------------- simulation

func _physics_process(dt: float) -> void:
	race_time += dt
	if not race_started and race_time >= 0.0:
		race_started = true
	for k in karts:
		if k.is_player and not demo and not k.finished:
			_read_player_input(k)
		else:
			_bot_think(k)
		k.top_speed_mult = _rubber_band(k)
	for k in karts:
		k.tick(dt)
	_kart_collisions()
	_update_item_boxes(dt)
	_update_bouncers(dt)
	_update_oils(dt)
	_track_leader()


func _read_player_input(k) -> void:
	k.in_throttle = Input.get_action_strength("accel")
	k.in_brake = Input.get_action_strength("brake")
	k.in_steer = Input.get_action_strength("steer_left") - Input.get_action_strength("steer_right")
	k.in_drift = Input.is_action_pressed("drift")
	k.in_item = Input.is_action_pressed("item")


func _bot_think(k) -> void:
	var look := 8.0 + maxf(k.speed, 0.0) * 0.6
	var lane := sin(race_time * 0.3 + k.lane_seed) * 3.0
	var target := point_at(k.s + look) + normal_at(k.s + look) * lane
	var to: Vector2 = target - k.pos
	var want := atan2(-to.x, -to.y)
	var diff := wrapf(want - k.yaw, -PI, PI)
	k.in_steer = clampf(diff * 2.5, -1.0, 1.0)
	k.in_throttle = 1.0
	k.in_brake = 0.4 if absf(diff) > 0.7 and k.speed > 14.0 else 0.0
	# Bots drift only through the sharpest moment of a corner: it looks right, but they
	# rarely charge a boost. Drift boosts are the human player's edge; rubber-banding
	# (see _rubber_band) keeps the bots close. (Bots that drift whole corners slid
	# into walls and lapped ~2.4x slower in testing.)
	if k.drifting:
		k.in_drift = absf(diff) > 0.05 and signf(diff) == float(k.drift_dir)
	else:
		k.in_drift = absf(diff) > 0.22 and k.speed > 15.0
	# Item use
	k.in_item = false
	if k.item == "" or k.roulette_time > 0.0:
		return
	match k.item:
		"nitro":
			k.in_item = absf(diff) < 0.15
		"bouncer":
			for o in karts:
				if o == k:
					continue
				var gap: float = o.progress() - k.progress()
				if gap > 3.0 and gap < 45.0:
					var dir: Vector2 = (o.pos - k.pos).normalized()
					if dir.dot(k.forward()) > 0.95:
						k.in_item = true
			if k.item_held_time > 7.0:
				k.in_item = true
		"oil":
			for o in karts:
				if o == k:
					continue
				var gap: float = k.progress() - o.progress()
				if gap > 2.0 and gap < 14.0:
					k.in_item = true
			if k.item_held_time > 9.0:
				k.in_item = true


func _rubber_band(k) -> float:
	if k.is_player and not demo:
		return 1.0
	if mode != "race" or k.is_player:
		return k.skill
	var gap: float = player.progress() - k.progress()
	return k.skill * (1.0 + clampf(gap / 150.0, -0.06, 0.1))


func _kart_collisions() -> void:
	for i in karts.size():
		for j in range(i + 1, karts.size()):
			var a = karts[i]
			var b = karts[j]
			var d: Vector2 = b.pos - a.pos
			var dist := d.length()
			var min_d: float = 2.0 * KartScript.RADIUS
			if dist < min_d and dist > 0.001:
				var nrm := d / dist
				var push := (min_d - dist) * 0.5
				a.pos -= nrm * push
				b.pos += nrm * push
				var rel: float = (b.vel - a.vel).dot(nrm)
				if rel < 0.0:
					a.vel += nrm * rel * 0.5
					b.vel -= nrm * rel * 0.5


func on_lap(k) -> void:
	if k.lap == 1:
		k.lap_start_time = race_time
	elif k.lap >= 2 and k.lap_times.size() < LAPS:
		k.lap_times.append(race_time - k.lap_start_time)
		k.lap_start_time = race_time
	if k.lap > LAPS and not k.finished:
		k.finished = true
		k.finish_time = race_time
		if k == player:
			_on_player_finished()


func _track_leader() -> void:
	if not race_started or mode != "race":
		return
	var best = null
	for k in karts:
		if best == null or k.progress() > best.progress():
			best = k
	if leader != null and best != leader and race_time > 3.0 and not race_over:
		lead_changes += 1
	leader = best


func ranking() -> Array:
	var r := karts.duplicate()
	r.sort_custom(func(a, b):
		if a.finished and b.finished:
			return a.finish_time < b.finish_time
		if a.finished != b.finished:
			return a.finished
		return a.progress() > b.progress())
	return r


# ---------------------------------------------------------------- items

func roll_item(k) -> String:
	var place := ranking().find(k)          # 0 = first
	var weights: Array
	match place:
		0: weights = [5, 35, 60]
		1: weights = [20, 45, 35]
		2: weights = [35, 45, 20]
		_: weights = [50, 35, 15]
	var r := randi_range(1, 100)
	if r <= weights[0]:
		return "nitro"
	if r <= weights[0] + weights[1]:
		return "bouncer"
	return "oil"


func use_item(k, what: String) -> void:
	match what:
		"nitro":
			k.boost_time = maxf(k.boost_time, NITRO_TIME)
		"bouncer":
			var node := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.5
			sm.height = 1.0
			node.mesh = sm
			var m := StandardMaterial3D.new()
			m.albedo_color = Color(0.2, 1.0, 0.4)
			m.emission_enabled = true
			m.emission = Color(0.1, 0.8, 0.3)
			node.material_override = m
			add_child(node)
			var p: Vector2 = k.pos + k.forward() * 2.5
			bouncers.append({"pos": p, "vel": k.forward() * maxf(BOUNCER_SPEED, k.speed + 20.0),
				"seg": k.seg, "life": BOUNCER_LIFE, "owner": k, "grace": 0.6, "node": node})
		"oil":
			var node := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 1.4
			cm.bottom_radius = 1.4
			cm.height = 0.04
			node.mesh = cm
			var m := StandardMaterial3D.new()
			m.albedo_color = Color(0.05, 0.05, 0.08)
			m.metallic = 0.6
			m.roughness = 0.1
			node.material_override = m
			var p: Vector2 = k.pos - k.forward() * 2.6
			node.position = _v3(p, 0.03)
			add_child(node)
			oils.append({"pos": p, "life": OIL_LIFE, "owner": k, "grace": 1.0, "node": node})


func _update_item_boxes(dt: float) -> void:
	for box in item_boxes:
		var node: MeshInstance3D = box.node
		node.rotate_y(dt * 1.5)
		if box.respawn > 0.0:
			box.respawn -= dt
			node.visible = box.respawn <= 0.0
			continue
		for k in karts:
			if k.pos.distance_to(box.pos) < 1.9:
				box.respawn = ITEM_RESPAWN
				node.visible = false
				if k.item == "" and k.roulette_time <= 0.0:
					k.roulette_time = ROULETTE_TIME
				break


func _update_bouncers(dt: float) -> void:
	for i in range(bouncers.size() - 1, -1, -1):
		var b = bouncers[i]
		b.life -= dt
		b.grace -= dt
		b.pos += b.vel * dt
		var q := track_query(b.pos, b.seg)
		b.seg = q.seg
		var limit := wall_offset - 0.5
		if absf(q.lat) > limit:
			var outward: Vector2 = q.nrm * signf(q.lat)
			b.pos -= outward * (absf(q.lat) - limit)
			var vn: float = b.vel.dot(outward)
			if vn > 0.0:
				b.vel -= outward * vn * 2.0
		var node: MeshInstance3D = b.node
		node.position = _v3(b.pos, 0.5)
		var gone: bool = b.life <= 0.0
		if not gone:
			for k in karts:
				if (k == b.owner and b.grace > 0.0) or k.pos.distance_to(b.pos) > 1.5:
					continue
				if k.hit() and k != b.owner:
					b.owner.hits_given += 1
				gone = true
				break
		if gone:
			node.queue_free()
			bouncers.remove_at(i)


func _update_oils(dt: float) -> void:
	for i in range(oils.size() - 1, -1, -1):
		var o = oils[i]
		o.life -= dt
		o.grace -= dt
		var gone: bool = o.life <= 0.0
		if not gone:
			for k in karts:
				if (k == o.owner and o.grace > 0.0) or k.pos.distance_to(o.pos) > 1.6:
					continue
				if k.hit() and k != o.owner:
					o.owner.hits_given += 1
				gone = true
				break
		if gone:
			o.node.queue_free()
			oils.remove_at(i)


# ---------------------------------------------------------------- per-frame: camera and HUD

func _process(delta: float) -> void:
	for k in karts:
		k.update_visual(delta)
	if overview:
		var c := Vector2.ZERO
		for p in CTRL:
			c += p
		c /= CTRL.size()
		camera.position = _v3(c, 330.0)
		camera.look_at(_v3(c), Vector3.FORWARD)
	else:
		cam_pos = cam_pos.lerp(_chase_target(), 1.0 - exp(-11.0 * delta))
		camera.position = cam_pos
		var f: Vector2 = player.forward()
		camera.look_at(_v3(player.pos + f * 4.0, 1.0), Vector3.UP)
		var speed_frac := clampf(player.speed / KartScript.MAX_SPEED, 0.0, 1.4)
		var target_fov := 68.0 + 10.0 * speed_frac + (6.0 if player.boost_time > 0.0 else 0.0)
		camera.fov = lerpf(camera.fov, target_fov, 1.0 - exp(-5.0 * delta))
	_update_hud()
	minimap.queue_redraw()
	if shot_dir != "" and not shot_times.is_empty() and race_time >= shot_times[0]:
		var t: float = shot_times.pop_front()
		get_viewport().get_texture().get_image().save_png("%s/race_t%03d.png" % [shot_dir, int(t)])
	if shot_dir != "" and race_over:
		print("[demo] player finished; quitting")
		get_tree().quit()


func _chase_target() -> Vector3:
	var f: Vector2 = player.forward()
	return _v3(player.pos - f * 6.0, 2.7)


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	hud_left = _label(layer, Vector2(20, 16), 24, Color.WHITE)
	hud_pos = _label(layer, Vector2(20, 16), 64, Color(1, 0.9, 0.3))
	hud_pos.anchor_left = 1.0
	hud_pos.anchor_right = 1.0
	hud_pos.offset_left = -520
	hud_pos.offset_top = 250
	hud_pos.offset_right = -20
	hud_pos.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hud_item = _label(layer, Vector2(20, 130), 30, Color(0.8, 0.95, 1.0))
	hud_center = _label(layer, Vector2.ZERO, 44, Color(1, 1, 1))
	hud_center.anchor_left = 0.5
	hud_center.anchor_right = 0.5
	hud_center.anchor_top = 0.3
	hud_center.offset_left = -600
	hud_center.offset_right = 600
	hud_center.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud_help = _label(layer, Vector2.ZERO, 17, Color(0.9, 0.92, 0.95))
	hud_help.anchor_top = 1.0
	hud_help.anchor_bottom = 1.0
	hud_help.offset_left = 20
	hud_help.offset_top = -120
	hud_help.text = "W/S or RT/LT  drive / brake      A/D or stick  steer\nSpace/Shift or RB  hold to drift (steer into the turn)\nE/Ctrl or LB  use item      R  restart      T  race / time trial"
	drift_bar_bg = ColorRect.new()
	drift_bar_bg.color = Color(0, 0, 0, 0.45)
	drift_bar_bg.position = Vector2(20, 180)
	drift_bar_bg.size = Vector2(300, 18)
	layer.add_child(drift_bar_bg)
	drift_bar = ColorRect.new()
	drift_bar.position = Vector2(20, 180)
	drift_bar.size = Vector2(0, 18)
	layer.add_child(drift_bar)
	minimap = Control.new()
	minimap.anchor_left = 1.0
	minimap.anchor_right = 1.0
	minimap.offset_left = -250
	minimap.offset_top = 16
	minimap.offset_right = -20
	minimap.offset_bottom = 246
	minimap.draw.connect(_draw_minimap)
	layer.add_child(minimap)


func _label(parent: Node, at: Vector2, size: int, col: Color) -> Label:
	var l := Label.new()
	l.position = at
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 8)
	parent.add_child(l)
	return l


func _fmt(t: float) -> String:
	if t < 0.0:
		return "--:--.--"
	return "%d:%05.2f" % [int(t) / 60, fmod(t, 60.0)]


func _update_hud() -> void:
	var p = player
	var lap_shown := clampi(p.lap, 1, LAPS)
	var cur_lap: float = race_time - p.lap_start_time if p.lap >= 1 and not p.finished else -1.0
	var best := -1.0
	for t in p.lap_times:
		if best < 0.0 or t < best:
			best = t
	var lines: Array[String] = []
	lines.append("Lap %d/%d     %s     %d km/h" % [lap_shown, LAPS, _fmt(maxf(race_time, 0.0)), int(absf(p.speed) * 3.6)])
	lines.append("This lap %s     Best %s     %s" % [_fmt(cur_lap), _fmt(best), "TIME TRIAL" if mode == "time_trial" else ""])
	hud_left.text = "\n".join(lines)

	if mode == "race":
		var place := ranking().find(p) + 1
		hud_pos.text = ["", "1st", "2nd", "3rd", "4th"][place] + "/4"
	else:
		hud_pos.text = ""

	if p.roulette_time > 0.0:
		hud_item.text = "Item: " + roulette_names[int(Time.get_ticks_msec() / 80) % 3] + " ..."
	elif p.item != "":
		hud_item.text = "Item: " + {"nitro": "Nitro", "bouncer": "Bouncer", "oil": "Oil slick"}[p.item] + "   (E / LB)"
	else:
		hud_item.text = "Item: -" if mode == "race" else ""

	if p.drifting:
		drift_bar.size.x = 300.0 * clampf(p.drift_time / KartScript.DRIFT_TIERS[2], 0.0, 1.0)
		drift_bar.color = KartScript.TIER_COLORS[p.drift_tier]
	else:
		drift_bar.size.x = 0.0
	if p.boost_time > 0.0:
		drift_bar.size.x = 300.0
		drift_bar.color = Color(1.0, 0.55, 0.1)

	if race_time < 0.0:
		hud_center.text = str(int(ceil(-race_time)))
	elif race_time < 1.0:
		hud_center.text = "GO!"
	elif p.spin_time > 0.0:
		hud_center.text = "SPUN OUT!"
	elif race_over:
		hud_center.text = _results_text()
	else:
		hud_center.text = ""


func _draw_minimap() -> void:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in pts:
		lo = lo.min(p)
		hi = hi.max(p)
	var size := minimap.size
	var scale_f := minf((size.x - 20.0) / (hi.x - lo.x), (size.y - 20.0) / (hi.y - lo.y))
	var to_map := func(p: Vector2) -> Vector2:
		return (p - lo) * scale_f + Vector2(10, 10)
	minimap.draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.35))
	var poly := PackedVector2Array()
	for p in pts:
		poly.append(to_map.call(p))
	poly.append(poly[0])
	minimap.draw_polyline(poly, Color(0.85, 0.85, 0.9), 4.0)
	minimap.draw_circle(to_map.call(pts[0]), 4.0, Color.WHITE)
	for b in bouncers:
		minimap.draw_circle(to_map.call(b.pos), 3.0, Color(0.2, 1.0, 0.4))
	for o in oils:
		minimap.draw_circle(to_map.call(o.pos), 3.0, Color(0.1, 0.1, 0.1))
	for k in karts:
		minimap.draw_circle(to_map.call(k.pos), 7.0 if k.is_player else 5.0, k.color)


# ---------------------------------------------------------------- results and log

func _on_player_finished() -> void:
	race_over = true
	_write_log()


func _results_text() -> String:
	var lines: Array[String] = ["FINISHED"]
	if mode == "race":
		var r := ranking()
		for i in r.size():
			var k = r[i]
			var t: String = _fmt(k.finish_time) if k.finished else "racing"
			lines.append("%d. %s  %s" % [i + 1, k.kart_name, t])
	else:
		lines.append(_fmt(player.finish_time))
	lines.append("R to race again   T to switch race / time trial")
	return "\n".join(lines)


func _open_log() -> void:
	log_path = ProjectSettings.globalize_path("res://race_log.csv")
	if not FileAccess.file_exists(log_path):
		var f := FileAccess.open(log_path, FileAccess.WRITE)
		f.store_line("session,mode,finish_pos,total_time,lap1,lap2,lap3,best_lap,boost_blue,boost_orange,boost_purple,items_used,hits_given,hits_taken,lead_changes,wall_hits")
		f.close()


func _write_log() -> void:
	var p = player
	if demo:
		# Demo runs are for screenshots, not playtest evidence: print, don't log.
		print("[demo] place %d time %.2f laps %s lead changes %d bot hits taken by player %d boosts %s" % [
			ranking().find(p) + 1, p.finish_time, str(p.lap_times), lead_changes, p.hits_taken, str(p.boosts)])
		return
	var laps: Array[String] = []
	var best := INF
	for i in LAPS:
		var t: float = p.lap_times[i] if i < p.lap_times.size() else -1.0
		laps.append("%.2f" % t)
		if t > 0.0:
			best = minf(best, t)
	var place := ranking().find(p) + 1 if mode == "race" else 1
	var f := FileAccess.open(log_path, FileAccess.READ_WRITE)
	f.seek_end()
	f.store_line("%s,%s,%d,%.2f,%s,%.2f,%d,%d,%d,%d,%d,%d,%d,%d" % [
		Time.get_datetime_string_from_system(), mode, place, p.finish_time, ",".join(laps), best,
		p.boosts[0], p.boosts[1], p.boosts[2], p.items_used, p.hits_given, p.hits_taken,
		lead_changes, p.wall_hits])
	f.close()
	print("[race] %s place %d time %.2f laps %s | boosts %s | items %d hits %d/%d | lead changes %d | walls %d" % [
		mode, place, p.finish_time, ",".join(laps), str(p.boosts), p.items_used, p.hits_given,
		p.hits_taken, lead_changes, p.wall_hits])
