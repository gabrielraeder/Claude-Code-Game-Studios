# PROTOTYPE - NOT FOR PRODUCTION
# Question: Can 2+ PCs race smoothly over host/join with owner-authoritative karts?
# Date: 2026-11-19
#
# Net model under test (copied track/items/bots from prototypes/kart-concept/main.gd):
#   - One player HOSTS (ENet server on UDP 24680), others JOIN by IP. The host also
#     owns the bots.
#   - Owner-authoritative: each PC simulates only the karts it owns and sends their state
#     30x/s (unreliable). Other karts are drawn 100 ms in the past, interpolated between
#     snapshots (extrapolated briefly if snapshots run late).
#   - Items: the firer spawns and announces (reliable); every PC simulates them; only the
#     VICTIM's PC decides a hit and announces it. Item boxes: the taker announces.
#   - Fake network: --lag=ms (added one-way delay per send), --jitter=ms, --loss=% (unreliable only).
# Args (after --): --host | --join=IP   --players=N (humans to wait for, default 2)
#   --bots=N (default 2)  --autopilot  --quit-after-race  --shots=DIR  --netlog=PATH
extends Node3D

const KartScript := preload("res://kart.gd")

const PORT := 24680
const SEND_HZ := 30.0
const PING_INTERVAL := 0.5
const VIEW_DELAY_MIN := 0.05
const VIEW_DELAY_MAX := 0.35
const MAX_EXTRAP := 0.25
const MAX_KARTS := 4
const KART_NAMES := ["Red", "Blue", "Green", "Yellow"]
const KART_COLORS := [Color(0.95, 0.2, 0.2), Color(0.25, 0.5, 1.0), Color(0.25, 0.8, 0.35), Color(1.0, 0.85, 0.2)]
const BOT_SKILL := 0.97
const SLOTS := [[-6.0, 3.5], [-6.0, -3.5], [-12.0, 3.5], [-12.0, -3.5]]

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
const ITEM_ROWS := [0.22, 0.5, 0.78]
const ITEM_RESPAWN := 3.0
const ROULETTE_TIME := 1.0
const NITRO_TIME := 1.5
const BOUNCER_SPEED := 45.0
const BOUNCER_LIFE := 6.0
const OIL_LIFE := 25.0

var wall_offset := ROAD_HALF_WIDTH + CURB_WIDTH
var pts := PackedVector2Array()
var cum := PackedFloat32Array()
var track_len := 0.0

# Config from args
var role := "host"
var join_ip := ""
var want_players := 2
var bot_count := 2
var lag_ms := 0.0
var jitter_ms := 0.0
var loss_pct := 0.0
var autopilot := false
var quit_after_race := false
var shot_dir := ""
var shot_times := [2.0, 12.0, 30.0, 60.0]
var net_log_path := ""

# Network state
var my_id := 1
var connected := false
var status := ""
var lobby_peers: Array[int] = [1]
var send_queue: Array = []        # {at_ms, fn}
var last_reliable_at := 0
var send_accum := 0.0
var ping_accum := 0.0
var rtt := 0.0
var rtt_max := 0.0
var start_pending := -1.0         # host: seconds until rpc_start is sent
# Adaptive view delay: remote karts are drawn this far in the past, sized from how late
# snapshots arrive (one-way latency) plus jitter, so interpolation rarely runs dry.
var view_delay := 0.1
var late_avg := 0.0
var late_dev := 0.0
var leader_candidate = null
var leader_candidate_time := 0.0

# Race state
var karts: Array = []
var karts_by_id: Dictionary = {}
var my_kart = null
var race_time := -COUNTDOWN
var race_active := false          # countdown or racing
var race_started := false         # past GO (karts read this)
var race_over := false
var over_time := 0.0
var leader = null
var lead_changes := 0
var item_boxes: Array = []
var items: Dictionary = {}        # id -> {kind, pos, vel, seg, life, owner, grace, node}
var item_counter := 0
var roulette_names := ["Nitro", "Bouncer", "Oil slick"]

# Net quality stats: per second (log rows) and per race (summary)
var sec_accum := 0.0
var st_snaps := 0
var st_frames := 0
var st_extrap := 0
var st_err_sum := 0.0
var st_err_n := 0
var st_err_max := 0.0
var race_stats := {"snaps": 0, "frames": 0, "extrap": 0, "err_sum": 0.0, "err_n": 0, "err_max": 0.0, "rtt_sum": 0.0, "rtt_n": 0, "seconds": 0}

var camera: Camera3D
var cam_pos := Vector3.ZERO
var hud_left: Label
var hud_pos: Label
var hud_item: Label
var hud_center: Label
var hud_net: Label
var drift_bar: ColorRect
var minimap: Control


func _ready() -> void:
	_parse_args()
	_setup_input()
	_build_centerline()
	_build_world()
	_build_track_mesh()
	_spawn_item_boxes()
	_build_hud()
	_open_net_log()
	_start_network()


func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		if a == "--host":
			role = "host"
		elif a.begins_with("--join="):
			role = "client"
			join_ip = a.substr(7)
		elif a.begins_with("--players="):
			want_players = clampi(int(a.substr(10)), 1, MAX_KARTS)
		elif a.begins_with("--bots="):
			bot_count = clampi(int(a.substr(7)), 0, MAX_KARTS - 1)
		elif a.begins_with("--lag="):
			lag_ms = float(a.substr(6))
		elif a.begins_with("--jitter="):
			jitter_ms = float(a.substr(9))
		elif a.begins_with("--loss="):
			loss_pct = float(a.substr(7))
		elif a == "--autopilot":
			autopilot = true
		elif a == "--quit-after-race":
			quit_after_race = true
		elif a.begins_with("--shots="):
			shot_dir = a.substr(8)
		elif a.begins_with("--netlog="):
			net_log_path = a.substr(9)


# ---------------------------------------------------------------- network setup

func _start_network() -> void:
	var peer := ENetMultiplayerPeer.new()
	if role == "host":
		var err := peer.create_server(PORT, MAX_KARTS)
		if err != OK:
			status = "Could not host on UDP %d (error %d). Is another copy already hosting?" % [PORT, err]
			return
		multiplayer.multiplayer_peer = peer
		my_id = 1
		connected = true
		multiplayer.peer_connected.connect(_on_peer_connected)
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
		print("[net] hosting on UDP %d, local addresses: %s" % [PORT, ", ".join(_lan_addresses())])
	else:
		var err := peer.create_client(join_ip, PORT)
		if err != OK:
			status = "Could not start connecting to %s (error %d)" % [join_ip, err]
			return
		multiplayer.multiplayer_peer = peer
		multiplayer.connected_to_server.connect(_on_connected)
		multiplayer.connection_failed.connect(func(): status = "Could not reach %s:%d. Check the IP and the host's firewall." % [join_ip, PORT])
		multiplayer.server_disconnected.connect(func(): status = "Host left the game.")
		status = "Connecting to %s:%d ..." % [join_ip, PORT]


func _lan_addresses() -> Array[String]:
	var out: Array[String] = []
	for a in IP.get_local_addresses():
		if a.count(".") == 3 and not a.begins_with("127.") and not a.begins_with("169.254."):
			out.append(a)
	return out


func _on_peer_connected(id: int) -> void:
	print("[net] peer %d connected" % id)
	if not race_active and not lobby_peers.has(id) and lobby_peers.size() < MAX_KARTS:
		lobby_peers.append(id)
	if lobby_peers.size() >= want_players and karts.is_empty():
		start_pending = 1.5


func _on_peer_disconnected(id: int) -> void:
	print("[net] peer %d disconnected" % id)
	lobby_peers.erase(id)


func _on_connected() -> void:
	my_id = multiplayer.get_unique_id()
	connected = true
	status = "Connected. Waiting for the host to start."
	print("[net] connected as peer %d" % my_id)


# Every send goes through here so fake lag / jitter / loss apply to all of it.
func _send(fn: Callable, reliable: bool) -> void:
	if not reliable and loss_pct > 0.0 and randf() * 100.0 < loss_pct:
		return
	var delay := lag_ms + (randf() * jitter_ms if jitter_ms > 0.0 else 0.0)
	if delay <= 0.0:
		_call_if_connected(fn)
		return
	var at := Time.get_ticks_msec() + int(delay)
	if reliable:
		at = maxi(at, last_reliable_at)   # reliable stays in order even with jitter
		last_reliable_at = at
	send_queue.append({"at": at, "fn": fn})


func _call_if_connected(fn: Callable) -> void:
	var mp := multiplayer.multiplayer_peer
	if mp != null and mp.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		fn.call()


func _flush_send_queue() -> void:
	var now := Time.get_ticks_msec()
	var i := 0
	while i < send_queue.size():
		if send_queue[i].at <= now:
			var fn: Callable = send_queue[i].fn
			send_queue.remove_at(i)
			_call_if_connected(fn)
		else:
			i += 1


# ---------------------------------------------------------------- RPCs

@rpc("authority", "call_local", "reliable")
func rpc_setup(slot_list: Array) -> void:
	for k in karts:
		k.queue_free()
	karts.clear()
	karts_by_id.clear()
	my_kart = null
	for slot in slot_list:
		var k = KartScript.new()
		k.game = self
		k.kart_id = slot[0]
		k.owner_peer = slot[1]
		k.is_bot = slot[3]
		k.is_local = k.owner_peer == my_id
		k.is_player = k.is_local and not k.is_bot
		k.kart_name = slot[2]
		k.color = KART_COLORS[k.kart_id]
		k.skill = BOT_SKILL if k.is_bot else 1.0
		k.lane_seed = k.kart_id * 2.1
		add_child(k)
		karts.append(k)
		karts_by_id[k.kart_id] = k
		if k.is_player:
			my_kart = k
	_reset_race()


@rpc("authority", "call_local", "reliable")
func rpc_start(host_time: float) -> void:
	_reset_race()
	race_time = host_time + (rtt * 0.5 if role == "client" else 0.0)
	race_active = true
	status = ""


@rpc("any_peer", "call_remote", "unreliable_ordered")
func rpc_state(kart_id: int, t: float, d: PackedFloat32Array) -> void:
	var k = karts_by_id.get(kart_id)
	if k == null or k.is_local:
		return
	st_snaps += 1
	if not k.buffer.is_empty():
		var last: Dictionary = k.buffer.back()
		if t <= last.t:
			return
		var ld: PackedFloat32Array = last.d
		var predicted: Vector2 = Vector2(ld[0], ld[1]) + Vector2(ld[2], ld[3]) * (t - last.t)
		var err: float = predicted.distance_to(Vector2(d[0], d[1]))
		st_err_sum += err
		st_err_n += 1
		st_err_max = maxf(st_err_max, err)
	var lateness := race_time - t
	late_avg = lateness if late_avg == 0.0 else lerpf(late_avg, lateness, 0.05)
	late_dev = lerpf(late_dev, absf(lateness - late_avg), 0.05)
	view_delay = clampf(late_avg + 2.0 * late_dev + 1.0 / SEND_HZ, VIEW_DELAY_MIN, VIEW_DELAY_MAX)
	k.buffer.append({"t": t, "d": d})
	if k.buffer.size() > 40:
		k.buffer.pop_front()
	k.apply_fields(d)


@rpc("any_peer", "call_remote", "unreliable")
func rpc_ping(client_t: int) -> void:
	var from := multiplayer.get_remote_sender_id()
	var host_t := race_time
	_send(func(): rpc_pong.rpc_id(from, client_t, host_t, race_active), false)


@rpc("authority", "call_remote", "unreliable")
func rpc_pong(client_t: int, host_race_time: float, host_active: bool) -> void:
	var sample := (Time.get_ticks_msec() - client_t) / 1000.0
	rtt = sample if rtt == 0.0 else lerpf(rtt, sample, 0.2)
	rtt_max = maxf(rtt_max, sample)
	if race_active and host_active:
		# Keep the race clock close to the host's (host time + half the round trip).
		var target := host_race_time + sample * 0.5
		if absf(race_time - target) > 0.02:
			race_time = lerpf(race_time, target, 0.15)


@rpc("any_peer", "call_remote", "reliable")
func rpc_item_spawn(item_id: int, kind: String, p: Vector2, v: Vector2, owner_id: int, t: float) -> void:
	var owner = karts_by_id.get(owner_id)
	if owner == null:
		return
	var elapsed := clampf(race_time - t, 0.0, 0.5)
	_spawn_item(item_id, kind, p + v * elapsed, v, owner)


@rpc("any_peer", "call_remote", "reliable")
func rpc_item_gone(item_id: int, victim_id: int) -> void:
	if items.has(item_id):
		var it = items[item_id]
		if it.owner.is_local and victim_id != it.owner.kart_id:
			it.owner.hits_given += 1
		it.node.queue_free()
		items.erase(item_id)


@rpc("any_peer", "call_remote", "reliable")
func rpc_box_taken(index: int) -> void:
	var box = item_boxes[index]
	box.respawn = ITEM_RESPAWN
	box.node.visible = false


@rpc("authority", "call_local", "reliable")
func rpc_restart() -> void:
	race_active = false
	race_over = false
	_reset_race()
	if role == "host":
		start_pending = 1.5


# ---------------------------------------------------------------- input

func _setup_input() -> void:
	_action("accel", [KEY_W, KEY_UP], [], [[JOY_AXIS_TRIGGER_RIGHT, 1.0]])
	_action("brake", [KEY_S, KEY_DOWN], [], [[JOY_AXIS_TRIGGER_LEFT, 1.0]])
	_action("steer_left", [KEY_A, KEY_LEFT], [], [[JOY_AXIS_LEFT_X, -1.0]])
	_action("steer_right", [KEY_D, KEY_RIGHT], [], [[JOY_AXIS_LEFT_X, 1.0]])
	_action("drift", [KEY_SPACE, KEY_SHIFT], [JOY_BUTTON_RIGHT_SHOULDER, JOY_BUTTON_B], [])
	_action("item", [KEY_E, KEY_CTRL], [JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_X], [])
	_action("start_or_restart", [KEY_ENTER, KEY_KP_ENTER, KEY_R], [JOY_BUTTON_START], [])


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
	if role != "host" or not event.is_action_pressed("start_or_restart"):
		return
	if karts.is_empty():
		start_pending = 0.01            # start now with whoever is connected
	elif race_over:
		_send(func(): rpc_restart.rpc(), true)


func _host_setup_and_start() -> void:
	if karts.is_empty():
		var slot_list: Array = []
		var idx := 0
		for pid in lobby_peers:
			slot_list.append([idx, pid, KART_NAMES[idx] + (" (host)" if pid == 1 else ""), false])
			idx += 1
		for b in bot_count:
			if idx >= MAX_KARTS:
				break
			slot_list.append([idx, 1, KART_NAMES[idx] + " bot", true])
			idx += 1
		_send(func(): rpc_setup.rpc(slot_list), true)
	_send(func(): rpc_start.rpc(-COUNTDOWN), true)


# ---------------------------------------------------------------- track (copied from kart-concept)

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
	var best_i := 0
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


# ---------------------------------------------------------------- world building (copied)

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
	var road := Color(0.22, 0.22, 0.25)
	for i in n:
		var j := (i + 1) % n
		var a := pts[i]
		var b := pts[j]
		var na := normals[i]
		var nb := normals[j]
		_quad(st, a + na * ROAD_HALF_WIDTH, a - na * ROAD_HALF_WIDTH, b - nb * ROAD_HALF_WIDTH, b + nb * ROAD_HALF_WIDTH, 0.0, road)
		var curb := Color(0.85, 0.15, 0.15) if (i / 2) % 2 == 0 else Color(0.95, 0.95, 0.95)
		_quad(st, a + na * wall_offset, a + na * ROAD_HALF_WIDTH, b + nb * ROAD_HALF_WIDTH, b + nb * wall_offset, 0.01, curb)
		_quad(st, a - na * ROAD_HALF_WIDTH, a - na * wall_offset, b - nb * wall_offset, b - nb * ROAD_HALF_WIDTH, 0.01, curb)
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
			_quad(st, pts[0] + n0 * w0 + t0 * d0, pts[0] + n0 * w1 + t0 * d0, pts[0] + n0 * w1 + t0 * d1, pts[0] + n0 * w0 + t0 * d1, 0.02, col)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	add_child(mi)
	var ws := SurfaceTool.new()
	ws.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in n:
		var j := (i + 1) % n
		for side in [1.0, -1.0]:
			var a: Vector2 = pts[i] + normals[i] * wall_offset * side
			var b: Vector2 = pts[j] + normals[j] * wall_offset * side
			ws.set_normal(_v3(-normals[i] * side))
			ws.set_color(Color(0.75, 0.75, 0.78) if (i / 4) % 2 == 0 else Color(0.6, 0.6, 0.65))
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


func _reset_race() -> void:
	for id in items:
		items[id].node.queue_free()
	items.clear()
	for box in item_boxes:
		box.respawn = 0.0
		box.node.visible = true
	race_time = -COUNTDOWN
	race_started = false
	race_over = false
	leader = null
	lead_changes = 0
	race_stats = {"snaps": 0, "frames": 0, "extrap": 0, "err_sum": 0.0, "err_n": 0, "err_max": 0.0, "rtt_sum": 0.0, "rtt_n": 0, "seconds": 0}
	for k in karts:
		var slot: Array = SLOTS[k.kart_id]
		var sd: float = track_len + slot[0]
		var p: Vector2 = point_at(sd) + normal_at(sd) * slot[1]
		var t := tangent_at(sd)
		k.reset_for_race(p, atan2(-t.x, -t.y), track_query(p, -1))
	if my_kart != null:
		cam_pos = _chase_target()


# ---------------------------------------------------------------- simulation

func _physics_process(dt: float) -> void:
	_flush_send_queue()
	if role == "host" and start_pending > 0.0:
		start_pending -= dt
		if start_pending <= 0.0:
			_host_setup_and_start()
	if role == "client" and connected:
		ping_accum += dt
		if ping_accum >= PING_INTERVAL:
			ping_accum = 0.0
			var now := Time.get_ticks_msec()
			_send(func(): rpc_ping.rpc_id(1, now), false)
	if role == "host" and lobby_peers.size() > 1:
		# Host RTT: ENet's own round-trip estimate to the first client.
		var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
		var pp: ENetPacketPeer = enet.get_peer(lobby_peers[1]) if enet != null else null
		if pp != null:
			var sample := pp.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME) / 1000.0
			rtt = sample
			rtt_max = maxf(rtt_max, sample)
	if not race_active:
		return

	race_time += dt
	race_started = race_time >= 0.0
	for k in karts:
		if not k.is_local:
			continue
		if k.is_bot or autopilot or k.finished:
			_bot_think(k)
		else:
			_read_player_input(k)
		k.top_speed_mult = _rubber_band(k)
		k.tick(dt)
	for k in karts:
		if not k.is_local:
			_interpolate_remote(k)
	_kart_collisions()
	_update_item_boxes(dt)
	_update_items(dt)
	_track_leader()

	send_accum += dt
	if send_accum >= 1.0 / SEND_HZ:
		send_accum = 0.0
		var t := race_time
		for k in karts:
			if k.is_local:
				var id: int = k.kart_id
				var d: PackedFloat32Array = k.net_state()
				_send(func(): rpc_state.rpc(id, t, d), false)

	_net_stats_tick(dt)
	if race_over:
		over_time += dt
		# Test harness: leave once every human has finished (or 30 s after we did),
		# so the other PC is never left racing alone.
		var humans_done := true
		for k in karts:
			if not k.is_bot and not k.finished:
				humans_done = false
		if quit_after_race and ((humans_done and over_time > 3.0) or over_time > 30.0):
			get_tree().quit()


func _interpolate_remote(k) -> void:
	st_frames += 1
	var buf: Array = k.buffer
	if buf.is_empty():
		return
	var rt := race_time - view_delay
	var newest: Dictionary = buf.back()
	if rt >= newest.t:
		# Snapshots are late: extrapolate along the last velocity, but not too far.
		st_extrap += 1
		var d: PackedFloat32Array = newest.d
		var ahead := minf(rt - newest.t, MAX_EXTRAP)
		k.pos = Vector2(d[0], d[1]) + Vector2(d[2], d[3]) * ahead
		k.vel = Vector2(d[2], d[3])
		k.yaw = d[4]
		return
	for i in range(buf.size() - 1, 0, -1):
		var a: Dictionary = buf[i - 1]
		var b: Dictionary = buf[i]
		if a.t <= rt and rt <= b.t:
			var f: float = (rt - a.t) / maxf(b.t - a.t, 0.0001)
			var da: PackedFloat32Array = a.d
			var db: PackedFloat32Array = b.d
			k.pos = Vector2(da[0], da[1]).lerp(Vector2(db[0], db[1]), f)
			k.vel = Vector2(da[2], da[3]).lerp(Vector2(db[2], db[3]), f)
			k.yaw = lerp_angle(da[4], db[4], f)
			return
	var oldest: PackedFloat32Array = buf[0].d
	k.pos = Vector2(oldest[0], oldest[1])
	k.yaw = oldest[4]


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
	if k.drifting:
		k.in_drift = absf(diff) > 0.05 and signf(diff) == float(k.drift_dir)
	else:
		k.in_drift = absf(diff) > 0.22 and k.speed > 15.0
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
				if gap > 3.0 and gap < 45.0 and (o.pos - k.pos).normalized().dot(k.forward()) > 0.95:
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
	if not k.is_bot:
		return 1.0
	var best_human := -INF
	for o in karts:
		if not o.is_bot:
			best_human = maxf(best_human, o.progress())
	if best_human == -INF:
		return k.skill
	return k.skill * (1.0 + clampf((best_human - k.progress()) / 150.0, -0.06, 0.1))


func _kart_collisions() -> void:
	# Each PC only moves the karts it owns; the other PC does the same for its own.
	for a in karts:
		if not a.is_local:
			continue
		for b in karts:
			if b == a:
				continue
			var d: Vector2 = a.pos - b.pos
			var dist := d.length()
			var min_d: float = 2.0 * KartScript.RADIUS
			if dist < min_d and dist > 0.001:
				var nrm := d / dist
				a.pos += nrm * (min_d - dist) * (0.5 if b.is_local else 1.0)
				var rel: float = a.vel.dot(nrm)
				if rel < 0.0:
					a.vel -= nrm * rel * 0.5


func on_lap(k) -> void:
	if k.lap == 1:
		k.lap_start_time = race_time
	elif k.lap >= 2 and k.lap_times.size() < LAPS:
		k.lap_times.append(race_time - k.lap_start_time)
		k.lap_start_time = race_time
	if k.lap > LAPS and not k.finished:
		k.finished = true
		k.finish_time = race_time
		if k == my_kart or (my_kart == null and k.is_local):
			race_over = true
			over_time = 0.0
			_write_summary()


func _track_leader() -> void:
	if not race_started:
		return
	var best = null
	for k in karts:
		if best == null or k.progress() > best.progress():
			best = k
	# A new leader must hold the lead for 0.5 s to count (no flicker from close racing).
	if best != leader_candidate:
		leader_candidate = best
		leader_candidate_time = race_time
	elif best != leader and race_time - leader_candidate_time >= 0.5:
		if leader != null and race_time > 3.0 and not race_over:
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


# ---------------------------------------------------------------- items (networked)

func roll_item(k) -> String:
	var place := ranking().find(k)
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
	if what == "nitro":
		k.boost_time = maxf(k.boost_time, NITRO_TIME)
		return
	item_counter += 1
	var item_id := my_id * 100000 + item_counter
	var p: Vector2
	var v := Vector2.ZERO
	if what == "bouncer":
		p = k.pos + k.forward() * 2.5
		v = k.forward() * maxf(BOUNCER_SPEED, k.speed + 20.0)
	else:
		p = k.pos - k.forward() * 2.6
	_spawn_item(item_id, what, p, v, k)
	var owner_id: int = k.kart_id
	var t := race_time
	_send(func(): rpc_item_spawn.rpc(item_id, what, p, v, owner_id, t), true)


func _spawn_item(item_id: int, kind: String, p: Vector2, v: Vector2, owner) -> void:
	var node := MeshInstance3D.new()
	var m := StandardMaterial3D.new()
	if kind == "bouncer":
		var sm := SphereMesh.new()
		sm.radius = 0.5
		sm.height = 1.0
		node.mesh = sm
		m.albedo_color = Color(0.2, 1.0, 0.4)
		m.emission_enabled = true
		m.emission = Color(0.1, 0.8, 0.3)
	else:
		var cm := CylinderMesh.new()
		cm.top_radius = 1.4
		cm.bottom_radius = 1.4
		cm.height = 0.04
		node.mesh = cm
		m.albedo_color = Color(0.05, 0.05, 0.08)
		m.metallic = 0.6
		m.roughness = 0.1
	node.material_override = m
	node.position = _v3(p, 0.5 if kind == "bouncer" else 0.03)
	add_child(node)
	items[item_id] = {"kind": kind, "pos": p, "vel": v, "seg": track_query(p, -1).seg,
		"life": BOUNCER_LIFE if kind == "bouncer" else OIL_LIFE,
		"owner": owner, "grace": 0.6 if kind == "bouncer" else 1.0, "node": node}


func _update_item_boxes(dt: float) -> void:
	for i in item_boxes.size():
		var box = item_boxes[i]
		var node: MeshInstance3D = box.node
		node.rotate_y(dt * 1.5)
		if box.respawn > 0.0:
			box.respawn -= dt
			node.visible = box.respawn <= 0.0
			continue
		for k in karts:
			if not k.is_local or k.pos.distance_to(box.pos) >= 1.9:
				continue
			box.respawn = ITEM_RESPAWN
			node.visible = false
			if k.item == "" and k.roulette_time <= 0.0:
				k.roulette_time = ROULETTE_TIME
			var index := i
			_send(func(): rpc_box_taken.rpc(index), true)
			break


func _update_items(dt: float) -> void:
	for id in items.keys():
		var it = items[id]
		it.life -= dt
		it.grace -= dt
		if it.kind == "bouncer":
			it.pos += it.vel * dt
			var q := track_query(it.pos, it.seg)
			it.seg = q.seg
			var limit := wall_offset - 0.5
			if absf(q.lat) > limit:
				var outward: Vector2 = q.nrm * signf(q.lat)
				it.pos -= outward * (absf(q.lat) - limit)
				var vn: float = it.vel.dot(outward)
				if vn > 0.0:
					it.vel -= outward * vn * 2.0
			it.node.position = _v3(it.pos, 0.5)
		if it.life <= 0.0:
			it.node.queue_free()
			items.erase(id)
			continue
		# Victim decides: only karts this PC owns are checked.
		var radius := 1.5 if it.kind == "bouncer" else 1.6
		for k in karts:
			if not k.is_local:
				continue
			if (k == it.owner and it.grace > 0.0) or k.pos.distance_to(it.pos) > radius:
				continue
			k.hit()
			if it.owner.is_local and k != it.owner:
				it.owner.hits_given += 1
			it.node.queue_free()
			items.erase(id)
			var victim: int = k.kart_id
			var item_id: int = id
			_send(func(): rpc_item_gone.rpc(item_id, victim), true)
			break


# ---------------------------------------------------------------- per-frame: camera and HUD

func _process(delta: float) -> void:
	_flush_send_queue()
	for k in karts:
		k.update_visual(delta)
	if my_kart != null:
		cam_pos = cam_pos.lerp(_chase_target(), 1.0 - exp(-11.0 * delta))
		camera.position = cam_pos
		var f: Vector2 = my_kart.forward()
		camera.look_at(_v3(my_kart.pos + f * 4.0, 1.0), Vector3.UP)
		var speed_frac := clampf(my_kart.speed / KartScript.MAX_SPEED, 0.0, 1.4)
		var target_fov := 68.0 + 10.0 * speed_frac + (6.0 if my_kart.boost_time > 0.0 else 0.0)
		camera.fov = lerpf(camera.fov, target_fov, 1.0 - exp(-5.0 * delta))
	else:
		var sp := point_at(track_len - 30.0)
		camera.position = _v3(sp, 12.0)
		camera.look_at(_v3(point_at(10.0), 0.0), Vector3.UP)
	_update_hud()
	minimap.queue_redraw()
	if shot_dir != "" and DisplayServer.get_name() != "headless" and not shot_times.is_empty() and race_active and race_time >= shot_times[0]:
		var t: float = shot_times.pop_front()
		get_viewport().get_texture().get_image().save_png("%s/%s_t%03d.png" % [shot_dir, role, int(t)])


func _chase_target() -> Vector3:
	var f: Vector2 = my_kart.forward()
	return _v3(my_kart.pos - f * 6.0, 2.7)


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	hud_left = _label(layer, Vector2(20, 16), 24, Color.WHITE)
	hud_pos = _label(layer, Vector2.ZERO, 64, Color(1, 0.9, 0.3))
	hud_pos.anchor_left = 1.0
	hud_pos.anchor_right = 1.0
	hud_pos.offset_left = -520
	hud_pos.offset_top = 250
	hud_pos.offset_right = -20
	hud_pos.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hud_item = _label(layer, Vector2(20, 130), 30, Color(0.8, 0.95, 1.0))
	hud_center = _label(layer, Vector2.ZERO, 40, Color.WHITE)
	hud_center.anchor_left = 0.5
	hud_center.anchor_right = 0.5
	hud_center.anchor_top = 0.28
	hud_center.offset_left = -700
	hud_center.offset_right = 700
	hud_center.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud_net = _label(layer, Vector2.ZERO, 18, Color(0.7, 1.0, 0.8))
	hud_net.anchor_top = 1.0
	hud_net.anchor_bottom = 1.0
	hud_net.offset_left = 20
	hud_net.offset_top = -60
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.45)
	bg.position = Vector2(20, 180)
	bg.size = Vector2(300, 18)
	layer.add_child(bg)
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
	var net := "%s  peer %d  |  players %d/%d  |  RTT %d ms  |  fake lag %d ms, jitter %d ms, loss %d%%  |  view delay %d ms" % [
		role.to_upper(), my_id, lobby_peers.size() if role == "host" else karts.size(), want_players,
		int(rtt * 1000.0), int(lag_ms), int(jitter_ms), int(loss_pct), int(view_delay * 1000.0)]
	hud_net.text = net
	if my_kart == null:
		hud_left.text = ""
		hud_pos.text = ""
		hud_item.text = ""
		if role == "host":
			hud_center.text = "HOSTING on UDP %d\nYour IP: %s\nWaiting for players (%d/%d). Press Enter to start now.\n%s" % [
				PORT, "  ".join(_lan_addresses()), lobby_peers.size(), want_players, status]
		else:
			hud_center.text = status
		return
	var p = my_kart
	var cur_lap: float = race_time - p.lap_start_time if p.lap >= 1 and not p.finished else -1.0
	hud_left.text = "Lap %d/%d     %s     %d km/h\nThis lap %s" % [clampi(p.lap, 1, LAPS), LAPS, _fmt(maxf(race_time, 0.0)), int(absf(p.speed) * 3.6), _fmt(cur_lap)]
	var place := ranking().find(p) + 1
	hud_pos.text = ["", "1st", "2nd", "3rd", "4th"][place] + "/%d" % karts.size()
	if p.roulette_time > 0.0:
		hud_item.text = "Item: " + roulette_names[int(Time.get_ticks_msec() / 80) % 3] + " ..."
	elif p.item != "":
		hud_item.text = "Item: " + {"nitro": "Nitro", "bouncer": "Bouncer", "oil": "Oil slick"}[p.item] + "   (E / LB)"
	else:
		hud_item.text = "Item: -"
	if p.boost_time > 0.0:
		drift_bar.size.x = 300.0
		drift_bar.color = Color(1.0, 0.55, 0.1)
	elif p.drifting:
		drift_bar.size.x = 300.0 * clampf(p.drift_time / KartScript.DRIFT_TIERS[2], 0.0, 1.0)
		drift_bar.color = KartScript.TIER_COLORS[p.drift_tier]
	else:
		drift_bar.size.x = 0.0
	if not race_active:
		hud_center.text = status if status != "" else "Get ready..."
	elif race_time < 0.0:
		hud_center.text = str(int(ceil(-race_time)))
	elif race_time < 1.0:
		hud_center.text = "GO!"
	elif p.spin_time > 0.0:
		hud_center.text = "SPUN OUT!"
	elif race_over:
		var lines: Array[String] = ["FINISHED"]
		var r := ranking()
		for i in r.size():
			var k = r[i]
			lines.append("%d. %s  %s" % [i + 1, k.kart_name, _fmt(k.finish_time) if k.finished else "racing"])
		if role == "host":
			lines.append("Enter / R: race again")
		hud_center.text = "\n".join(lines)
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
	for id in items:
		minimap.draw_circle(to_map.call(items[id].pos), 3.0, Color(0.2, 1.0, 0.4) if items[id].kind == "bouncer" else Color(0.1, 0.1, 0.1))
	for k in karts:
		minimap.draw_circle(to_map.call(k.pos), 7.0 if k == my_kart else 5.0, k.color)


# ---------------------------------------------------------------- net log

func _open_net_log() -> void:
	if net_log_path == "":
		net_log_path = ProjectSettings.globalize_path("res://net_log_%s.csv" % role)
	if not FileAccess.file_exists(net_log_path):
		var f := FileAccess.open(net_log_path, FileAccess.WRITE)
		f.store_line("wall_time,role,peer,race_time,rtt_ms,lag_ms,jitter_ms,loss_pct,snaps_per_s,extrap_pct,pred_err_avg_m,pred_err_max_m,fps")
		f.close()


func _net_stats_tick(dt: float) -> void:
	sec_accum += dt
	if sec_accum < 1.0:
		return
	var extrap_pct := 100.0 * st_extrap / maxi(st_frames, 1)
	var err_avg := st_err_sum / maxi(st_err_n, 1)
	var f := FileAccess.open(net_log_path, FileAccess.READ_WRITE)
	f.seek_end()
	f.store_line("%s,%s,%d,%.1f,%d,%d,%d,%.1f,%.1f,%.1f,%.3f,%.3f,%d" % [
		Time.get_datetime_string_from_system(), role, my_id, race_time, int(rtt * 1000.0), int(lag_ms), int(jitter_ms),
		loss_pct, st_snaps / sec_accum, extrap_pct, err_avg, st_err_max, Engine.get_frames_per_second()])
	f.close()
	race_stats.snaps += st_snaps
	race_stats.frames += st_frames
	race_stats.extrap += st_extrap
	race_stats.err_sum += st_err_sum
	race_stats.err_n += st_err_n
	race_stats.err_max = maxf(race_stats.err_max, st_err_max)
	race_stats.rtt_sum += rtt
	race_stats.rtt_n += 1
	race_stats.seconds += 1
	sec_accum = 0.0
	st_snaps = 0
	st_frames = 0
	st_extrap = 0
	st_err_sum = 0.0
	st_err_n = 0
	st_err_max = 0.0


func _write_summary() -> void:
	var rs := race_stats
	if rs.get("written", false):
		return
	rs["written"] = true
	var place := ranking().find(my_kart) + 1 if my_kart != null else 0
	print("[net-summary] role=%s peer=%d place=%d finish=%.2f karts=%d | rtt_avg=%dms rtt_max=%dms view_delay=%dms | snaps/s=%.1f | extrap=%.1f%% | pred_err avg=%.3fm max=%.3fm | lag=%d jitter=%d loss=%d%% | lead_changes=%d items_used=%d hits_given=%d hits_taken=%d" % [
		role, my_id, place, my_kart.finish_time if my_kart != null else 0.0, karts.size(),
		int(1000.0 * rs.rtt_sum / maxi(rs.rtt_n, 1)), int(rtt_max * 1000.0), int(view_delay * 1000.0),
		rs.snaps / maxf(rs.seconds, 1.0), 100.0 * rs.extrap / maxi(rs.frames, 1),
		rs.err_sum / maxi(rs.err_n, 1), rs.err_max, int(lag_ms), int(jitter_ms), int(loss_pct),
		lead_changes, my_kart.items_used if my_kart else 0, my_kart.hits_given if my_kart else 0, my_kart.hits_taken if my_kart else 0])
