# PROTOTYPE - NOT FOR PRODUCTION
# Question: Can 2+ PCs race smoothly over host/join with owner-authoritative karts?
# Date: 2026-11-19
#
# One kart, copied from prototypes/kart-concept/kart.gd. A LOCAL kart is simulated here
# (tick). A REMOTE kart is never ticked: main.gd interpolates it from network snapshots
# and writes the same fields, so the visuals are identical.
extends Node3D

# --- Handling tuning (hardcoded on purpose) ---
const MAX_SPEED := 26.0          # m/s (~94 km/h)
const ACCEL := 14.0
const BRAKE := 32.0
const REVERSE_MAX := 8.0
const COAST_DRAG := 5.0
const TURN_RATE := 2.3           # rad/s at full steer, low speed
const GRIP := 9.0                # how fast velocity snaps to heading
const DRIFT_GRIP := 2.2
const DRIFT_MIN_SPEED := 12.0
const DRIFT_YAW_BASE := 1.25     # drifting always turns this much in the drift direction...
const DRIFT_YAW_RANGE := 0.85    # ...steering tightens or widens it by this much
const DRIFT_TIERS := [0.9, 1.9, 3.0]          # seconds of drift for blue / orange / purple
const DRIFT_BOOST := [0.0, 0.7, 1.1, 1.6]     # boost seconds per tier reached
const BOOST_SPEED_MULT := 1.35
const BOOST_ACCEL_MULT := 3.0
const SPIN_TIME := 1.1
const RADIUS := 1.0
const TIER_COLORS := [Color(1, 1, 1, 0.6), Color(0.3, 0.7, 1.0), Color(1.0, 0.6, 0.1), Color(0.8, 0.3, 1.0)]

var game                          # main.gd, set before add_child
var is_player := false
var kart_name := ""
var color := Color.RED
var skill := 1.0                  # bots: base top-speed multiplier
var lane_seed := 0.0

# Network identity
var kart_id := 0
var owner_peer := 1
var is_local := true
var is_bot := false
var buffer: Array = []           # remote only: [{t, d}] snapshots, oldest first

# Simulation state
var pos := Vector2.ZERO           # (x, z)
var vel := Vector2.ZERO
var yaw := 0.0
var speed := 0.0
var seg := 0
var s := 0.0
var lat := 0.0
var lap := 0
var max_lap := 0
var finished := false
var finish_time := 0.0
var lap_times: Array[float] = []
var lap_start_time := 0.0
var top_speed_mult := 1.0

# Inputs, written each tick by the player or the bot brain
var in_throttle := 0.0
var in_brake := 0.0
var in_steer := 0.0               # +1 = left
var in_drift := false
var in_item := false
var item_prev := false

var drifting := false
var drift_dir := 0
var drift_time := 0.0
var drift_tier := 0
var boost_time := 0.0
var spin_time := 0.0
var item := ""                    # "", "nitro", "bouncer", "oil"
var roulette_time := 0.0
var item_held_time := 0.0
var wall_cooldown := 0.0

# Stats for the race log
var boosts := [0, 0, 0]
var items_used := 0
var hits_given := 0
var hits_taken := 0
var wall_hits := 0

var visual: Node3D
var body: Node3D
var sparks: Array[MeshInstance3D] = []
var spark_mat: StandardMaterial3D
var flame: MeshInstance3D
var hop := 0.0
var spin_angle := 0.0


func _ready() -> void:
	visual = Node3D.new()
	add_child(visual)
	body = Node3D.new()
	visual.add_child(body)
	var paint := StandardMaterial3D.new()
	paint.albedo_color = color
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.12, 0.12, 0.14)
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.95, 0.85, 0.7)

	_box(body, Vector3(1.3, 0.4, 2.0), Vector3(0, 0.45, 0), paint)          # chassis
	_box(body, Vector3(1.0, 0.25, 0.6), Vector3(0, 0.55, -1.15), paint)     # nose (front is -Z)
	_box(body, Vector3(1.5, 0.12, 0.35), Vector3(0, 0.75, 1.05), dark)      # rear wing
	var head := MeshInstance3D.new()
	var hm := SphereMesh.new()
	hm.radius = 0.3
	hm.height = 0.6
	head.mesh = hm
	head.material_override = skin
	head.position = Vector3(0, 1.1, 0.2)
	body.add_child(head)
	var helmet := MeshInstance3D.new()
	var hel := SphereMesh.new()
	hel.radius = 0.33
	hel.height = 0.4
	hel.is_hemisphere = true
	helmet.mesh = hel
	helmet.material_override = paint
	helmet.position = Vector3(0, 1.15, 0.2)
	body.add_child(helmet)
	var wm := CylinderMesh.new()
	wm.top_radius = 0.32
	wm.bottom_radius = 0.32
	wm.height = 0.3
	for wp in [Vector3(-0.75, 0.32, -0.7), Vector3(0.75, 0.32, -0.7), Vector3(-0.75, 0.32, 0.75), Vector3(0.75, 0.32, 0.75)]:
		var w := MeshInstance3D.new()
		w.mesh = wm
		w.material_override = dark
		w.position = wp
		w.rotation.z = PI / 2
		body.add_child(w)

	spark_mat = StandardMaterial3D.new()
	spark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spark_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var sm := SphereMesh.new()
	sm.radius = 0.14
	sm.height = 0.28
	for sx in [-0.75, 0.75]:
		var sp := MeshInstance3D.new()
		sp.mesh = sm
		sp.material_override = spark_mat
		sp.position = Vector3(sx, 0.25, 1.1)
		sp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		sp.visible = false
		visual.add_child(sp)
		sparks.append(sp)

	flame = MeshInstance3D.new()
	var fm := CylinderMesh.new()
	fm.top_radius = 0.0
	fm.bottom_radius = 0.35
	fm.height = 1.4
	flame.mesh = fm
	var fmat := StandardMaterial3D.new()
	fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fmat.albedo_color = Color(1.0, 0.55, 0.1)
	flame.material_override = fmat
	flame.rotation.x = PI / 2      # cone tip points backwards (+Z)
	flame.position = Vector3(0, 0.5, 1.7)
	flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flame.visible = false
	body.add_child(flame)


func _box(parent: Node3D, size: Vector3, at: Vector3, m: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	mi.position = at
	parent.add_child(mi)


func forward() -> Vector2:
	return Vector2(-sin(yaw), -cos(yaw))


func progress() -> float:
	var base: float = lap * game.track_len + s
	if not is_local and not buffer.is_empty():
		# Remote state is from the past: project it to now so rankings compare like with like.
		base += speed * clampf(game.race_time - buffer.back().t, 0.0, 0.5)
	return base


func can_drive() -> bool:
	return spin_time <= 0.0 and game.race_started


# ---------------------------------------------------------------- simulation tick

func tick(dt: float) -> void:
	var control := can_drive()
	var steer := in_steer if control else 0.0
	var throttle := in_throttle if control else 0.0
	var brake := in_brake if control else 0.0

	# Drift: hold the drift button while steering at speed. The direction locks in.
	if not drifting and control and in_drift and absf(steer) > 0.3 and speed > DRIFT_MIN_SPEED:
		drifting = true
		drift_dir = 1 if steer > 0.0 else -1
		drift_time = 0.0
		drift_tier = 0
		hop = 0.35
	if drifting and (not in_drift or speed < DRIFT_MIN_SPEED * 0.7 or not control):
		_end_drift()

	# Speed
	var boosting := boost_time > 0.0
	var max_s := MAX_SPEED * top_speed_mult * (BOOST_SPEED_MULT if boosting else 1.0)
	# Accelerate up to the cap, never past it. Above the cap (a boost just ended),
	# the block below eases back down.
	var push := ACCEL * BOOST_ACCEL_MULT if boosting else ACCEL * throttle
	if push > 0.0 and speed < max_s:
		speed = minf(speed + push * dt, max_s)
	if brake > 0.0:
		if speed > 0.0:
			speed -= BRAKE * brake * dt
		else:
			speed -= ACCEL * 0.6 * brake * dt
	if throttle <= 0.0 and brake <= 0.0 and not boosting:
		speed = move_toward(speed, 0.0, COAST_DRAG * dt)
	if speed > max_s:
		speed = move_toward(speed, max_s, 18.0 * dt)
	speed = maxf(speed, -REVERSE_MAX)
	if spin_time > 0.0:
		speed *= exp(-2.5 * dt)

	# Steering
	var yaw_rate := 0.0
	if drifting:
		yaw_rate = drift_dir * (DRIFT_YAW_BASE + DRIFT_YAW_RANGE * clampf(steer * drift_dir, -1.0, 1.0))
	else:
		var low_speed := clampf(absf(speed) / 6.0, 0.0, 1.0)
		var high_speed_damp := 1.0 - 0.3 * clampf(speed / MAX_SPEED, 0.0, 1.0)
		yaw_rate = steer * TURN_RATE * low_speed * high_speed_damp * (1.0 if speed >= 0.0 else -1.0)
	yaw += yaw_rate * dt

	var grip := DRIFT_GRIP if drifting else GRIP
	vel = vel.lerp(forward() * speed, clampf(grip * dt, 0.0, 1.0))
	pos += vel * dt

	# Drift charge: tighter drifts charge faster.
	if drifting:
		drift_time += dt * (1.0 + 0.6 * maxf(steer * drift_dir, 0.0))
		drift_tier = 0
		for i in DRIFT_TIERS.size():
			if drift_time >= DRIFT_TIERS[i]:
				drift_tier = i + 1

	boost_time = maxf(0.0, boost_time - dt)
	spin_time = maxf(0.0, spin_time - dt)
	wall_cooldown = maxf(0.0, wall_cooldown - dt)

	# Items: roulette, then use on button press.
	if roulette_time > 0.0:
		roulette_time -= dt
		if roulette_time <= 0.0:
			item = game.roll_item(self)
			item_held_time = 0.0
	elif item != "":
		item_held_time += dt
	var pressed := in_item and not item_prev
	item_prev = in_item
	if pressed and item != "" and roulette_time <= 0.0 and control:
		game.use_item(self, item)
		item = ""
		items_used += 1

	_constrain_to_track()


func _end_drift() -> void:
	if drift_tier > 0:
		boost_time = maxf(boost_time, DRIFT_BOOST[drift_tier])
		boosts[drift_tier - 1] += 1
	drifting = false
	drift_dir = 0
	drift_time = 0.0
	drift_tier = 0


func _constrain_to_track() -> void:
	var q: Dictionary = game.track_query(pos, seg)
	seg = q.seg
	lat = q.lat
	var limit: float = game.wall_offset - RADIUS
	if absf(lat) > limit:
		var outward: Vector2 = q.nrm * signf(lat)
		pos -= outward * (absf(lat) - limit)
		var vn := vel.dot(outward)
		if vn > 0.0:
			vel -= outward * vn * 1.4
			if vn > 5.0 and wall_cooldown <= 0.0:
				speed *= 0.7
				wall_hits += 1
				wall_cooldown = 0.5
			else:
				speed *= 1.0 - 0.8 * get_physics_process_delta_time()

	# Laps: crossing s=0 forwards counts, backwards uncounts.
	var new_s: float = q.s
	var ds := new_s - s
	if ds < -game.track_len * 0.5:
		lap += 1
		# Only a lap never reached before counts (reversing over the line and back is not a lap).
		if lap > max_lap:
			max_lap = lap
			game.on_lap(self)
	elif ds > game.track_len * 0.5:
		lap -= 1
	s = new_s


func hit() -> bool:
	if spin_time > 0.0 or finished:
		return false
	spin_time = SPIN_TIME
	drifting = false
	drift_dir = 0
	drift_time = 0.0
	drift_tier = 0
	boost_time = 0.0
	hits_taken += 1
	return true


# ---------------------------------------------------------------- visuals (per render frame)

func update_visual(delta: float) -> void:
	position = Vector3(pos.x, 0.0, pos.y)
	rotation.y = yaw
	var tilt := 0.0
	if drifting:
		tilt = drift_dir * 0.4
	body.rotation.y = lerp_angle(body.rotation.y, tilt, 1.0 - exp(-10.0 * delta))
	hop = maxf(0.0, hop - delta * 1.6)
	body.position.y = sin(hop / 0.35 * PI) * 0.35 if hop > 0.0 else 0.0
	if spin_time > 0.0:
		spin_angle += delta * 14.0
	else:
		spin_angle = 0.0
	visual.rotation.y = spin_angle
	for sp in sparks:
		sp.visible = drifting
	if drifting:
		spark_mat.albedo_color = TIER_COLORS[drift_tier]
		var pulse := 1.0 + 0.2 * sin(Time.get_ticks_msec() * 0.03) + 0.2 * drift_tier
		for sp in sparks:
			sp.scale = Vector3.ONE * pulse
	flame.visible = boost_time > 0.0
	if flame.visible:
		flame.scale = Vector3(1, 1.0 + 0.3 * sin(Time.get_ticks_msec() * 0.05), 1)


# ---------------------------------------------------------------- network state

func net_state() -> PackedFloat32Array:
	return PackedFloat32Array([pos.x, pos.y, vel.x, vel.y, yaw, speed,
		1.0 if drifting else 0.0, drift_dir, drift_tier, boost_time, spin_time,
		lap, s, 1.0 if finished else 0.0, finish_time])


func apply_fields(d: PackedFloat32Array) -> void:
	# Everything except position and heading, which the interpolator sets.
	speed = d[5]
	drifting = d[6] > 0.5
	drift_dir = int(d[7])
	drift_tier = int(d[8])
	boost_time = d[9]
	spin_time = d[10]
	lap = int(d[11])
	s = d[12]
	finished = d[13] > 0.5
	finish_time = d[14]


func reset_for_race(p: Vector2, y: float, q: Dictionary) -> void:
	pos = p
	vel = Vector2.ZERO
	yaw = y
	speed = 0.0
	seg = q.seg
	s = q.s
	lap = 0
	max_lap = 0
	finished = false
	finish_time = 0.0
	lap_times.clear()
	lap_start_time = 0.0
	drifting = false
	drift_dir = 0
	drift_time = 0.0
	drift_tier = 0
	boost_time = 0.0
	spin_time = 0.0
	item = ""
	roulette_time = 0.0
	boosts = [0, 0, 0]
	items_used = 0
	hits_given = 0
	hits_taken = 0
	wall_hits = 0
	buffer.clear()
