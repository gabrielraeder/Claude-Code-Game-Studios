class_name KartVisual
extends Node3D
## Draws a KartSim: the vehicle glb with the racer's dog seated on it and the slot pennant on
## a pole (placeholder box-and-sphere body when a glb is missing), drift body angle and hop,
## small acceleration lean, tier-colored sparks, boost flame, spin-out, wheel spin, front-wheel
## steer, dog head bob and ear secondary motion. Reads simulation state only; never writes it,
## so the same node can show a local kart or an interpolated copy.
## Every number comes from VehicleStats.visual (VehicleVisualStats) and PennantStyle.
## Implements design/game-brief.md, Features items 1 and 6 (model contract in story 006:
## vehicle "Seat"/"PennantMount", Wheel_* nodes, material "paint"; dog "Head", "Ear_L/R", "tabard").

const PAINT_MATERIAL: String = "paint"
const TABARD_MATERIAL: String = "tabard"

## Paths already reported missing (one warning each, not one per kart).
static var _warned: Dictionary = {}
## Microseconds all KartVisual._process calls took since the last [method take_cost_usec].
static var _cost_usec: int = 0
## Spark spheres and flame cones by size, shared by every kart (never edited after creation;
## a PrimitiveMesh costs ~0.5 ms to create with a renderer, so 12 karts must not each make two).
static var _fx_meshes: Dictionary = {}

var _sim: KartSim
var _vs: VehicleVisualStats
var _body: Node3D
var _spin_root: Node3D
var _sparks: Array[MeshInstance3D] = []
var _spark_mat: StandardMaterial3D
var _flame: MeshInstance3D
var _hop_t: float = -1.0
# Landing squash (story 008): seconds since the last landing (-1 = none) and its strength 0..1.
var _land_t: float = -1.0
var _land_strength: float = 0.0
var _spin_angle: float = 0.0
var _clock: float = 0.0
var _pitch: float = 0.0
var _roll: float = 0.0
# Smoothed pitch and roll of the road surface under the kart (whole-kart lean).
var _surface_pitch: float = 0.0
var _surface_roll: float = 0.0
var _lean_n: float = 0.0
var _paint: StandardMaterial3D
var _racer: RacerDef
var _style: PennantStyle
var _slot: int = 0
var _color: Color = Color.WHITE
var _paint_mats: Array[BaseMaterial3D] = []
var _pennant: Pennant
var _wheels: Array[Dictionary] = []
var _wheel_angle: float = 0.0
var _dog_root: Node3D
var _head: Node3D
var _head_rest_y: float = 0.0
var _ears: Array[Node3D] = []
var _ear_rest: Array[float] = []
var _ear_angle: float = 0.0


## Binds this visual to [param sim] and builds the meshes using its stats. [param racer] picks
## the dog (null = a placeholder dog), [param style] is the pennant look (null = defaults),
## [param slot] picks the pennant pattern (the colour is the sim stats' paint_color), so the
## pennant is built once with the right look.
func bind(sim: KartSim, racer: RacerDef = null, style: PennantStyle = null, slot: int = 0) -> void:
	_slot = slot
	_sim = sim
	_vs = sim.stats.visual
	_racer = racer
	_style = style if style != null else PennantStyle.new()
	_color = sim.stats.paint_color
	_sim.drift_started.connect(_on_drift_started)
	_sim.landed.connect(_on_landed)
	_build()


## Loads and batches every vehicle and dog model and makes the spark and flame meshes ahead of a
## race (the pennant parts are Pennant.prewarm), so
## the 12 karts of a race start do not each pay for first-time loading in the same frame.
static func prewarm(vehicles: VehicleSet, racers: RacerSet) -> void:
	var paths: Array[Array] = []
	for v in vehicles.vehicles:
		paths.append([v.visual.model_path, PAINT_MATERIAL])
		_spark_mesh(v.visual)
		_flame_mesh(v.visual)
	for r in racers.racers:
		paths.append([r.model_path, TABARD_MATERIAL])
	for entry in paths:
		var path: String = entry[0]
		if path == "" or not ResourceLoader.exists(path):
			continue
		var scene: PackedScene = load(path) as PackedScene
		if scene == null:
			continue
		var node: Node = scene.instantiate()
		ModelBatcher.batch(node, PackedStringArray([entry[1]]))
		node.free()


## Returns the per-frame cost of every kart visual (microseconds) since the last call, and resets it
## (story 006 perf pass; written to the netlog each second).
static func take_cost_usec() -> int:
	var c: int = _cost_usec
	_cost_usec = 0
	return c


## Repaints the kart (keeps the slot pattern).
func set_paint(color: Color) -> void:
	apply_identity(_slot, color)


## Sets the kart's identity: [param slot] picks the pennant pattern, [param color] paints the
## vehicle panels, the dog's tabard and the pennant (online, every kart takes its slot's color
## on every PC).
func apply_identity(slot: int, color: Color) -> void:
	_slot = slot
	_color = color
	if _paint != null:
		_paint.albedo_color = color
	for m in _paint_mats:
		m.albedo_color = color
	if _pennant != null:
		_pennant.apply_identity(slot, color)


## Pennant pole length in meters (0 before bind).
func pennant_height() -> float:
	return _pennant.pole_height() if _pennant != null else 0.0


func _on_drift_started(_direction: int) -> void:
	_hop_t = 0.0


func _on_landed(_airtime: float, impact: float) -> void:
	_land_strength = clampf(impact / maxf(_vs.land_squash_full_speed, 0.01), 0.0, 1.0)
	if _land_strength > 0.0:
		_land_t = 0.0


## How far (meters) a kart sinking in a hazard drops below the surface (story 003).
const SINK_DEPTH: float = 1.6
var _was_sinking: bool = false


## Lava sink (art bible section 4): a cartoon "scorch puff", a burst of orange-to-black smoke
## balls, never fire or burning. One-shot, freed after it fades.
func _spawn_scorch_puff() -> void:
	var puff := CPUParticles3D.new()
	var ball := SphereMesh.new()
	ball.radius = 0.35
	ball.height = 0.7
	ball.radial_segments = 8
	ball.rings = 4
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ball.material = mat
	puff.mesh = ball
	puff.amount = 22
	puff.lifetime = 1.1
	puff.one_shot = true
	puff.explosiveness = 0.85
	puff.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	puff.emission_sphere_radius = 0.7
	puff.direction = Vector3.UP
	puff.spread = 35.0
	puff.initial_velocity_min = 2.0
	puff.initial_velocity_max = 4.5
	puff.gravity = Vector3(0, -1.5, 0)
	puff.scale_amount_min = 0.8
	puff.scale_amount_max = 1.8
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.85, 0.3, 0.06, 1.0))
	ramp.set_color(1, Color(0.06, 0.04, 0.04, 0.0))
	puff.color_ramp = ramp
	puff.position = Vector3(0, 1.2 + SINK_DEPTH * 0.3, 0)
	add_child(puff)
	puff.emitting = true
	get_tree().create_timer(2.0).timeout.connect(puff.queue_free)


func _process(delta: float) -> void:
	if _sim == null:
		return
	var t0: int = Time.get_ticks_usec()
	_clock += delta
	var sinking: bool = _sim.is_sinking()
	if sinking and not _was_sinking and _sim.hazard_kind == &"lava":
		_spawn_scorch_puff()
	_was_sinking = sinking
	var fraction: float = Engine.get_physics_interpolation_fraction()
	var p: Vector2 = _sim.interpolated_position(fraction)
	# Sinking in a hazard (story 003): the kart drops below the water surface.
	position = Vector3(p.x, _sim.interpolated_height(fraction) - _sim.sink_progress * SINK_DEPTH, p.y)
	var yaw: float = _sim.interpolated_yaw(fraction)
	rotation.y = yaw
	# The whole kart leans with the road surface (story 008): pitch with the slope, roll with the
	# bank, taken from the surface normal in the kart's own frame and smoothed.
	var local_n: Vector3 = _sim.surface_normal.rotated(Vector3.UP, -yaw)
	var surface_follow: float = 1.0 - exp(-_vs.surface_tilt_smoothing * delta)
	_surface_pitch = lerpf(_surface_pitch, atan2(local_n.z, local_n.y), surface_follow)
	_surface_roll = lerpf(_surface_roll, -atan2(local_n.x, local_n.y), surface_follow)
	rotation.x = _surface_pitch
	rotation.z = _surface_roll

	var follow: float = 1.0 - exp(-_vs.tilt_smoothing * delta)
	# Drift body angle: neutral steering = default, into the turn up to max, out down to min.
	var body_yaw: float = 0.0
	if _sim.drifting:
		var s: float = clampf(_sim.last_steer * _sim.drift_dir, -1.0, 1.0)
		var end_deg: float = _vs.drift_body_yaw_max_deg if s > 0.0 else _vs.drift_body_yaw_min_deg
		body_yaw = _sim.drift_dir * deg_to_rad(lerpf(_vs.drift_body_yaw_default_deg, end_deg, absf(s)))
	_body.rotation.y = lerp_angle(_body.rotation.y, body_yaw, follow)
	# Lean from acceleration: nose up when accelerating, roll outward in a turn.
	var pitch_target: float = clampf(_sim.accel_long / _vs.lean_long_norm, -1.0, 1.0) \
			* deg_to_rad(_vs.lean_pitch_max_deg)
	var roll_target: float = -clampf(_sim.accel_lat / _vs.lean_lat_norm, -1.0, 1.0) \
			* deg_to_rad(_vs.lean_roll_max_deg)
	_pitch = lerpf(_pitch, pitch_target, follow)
	_roll = lerpf(_roll, roll_target, follow)
	_body.rotation.x = _pitch
	_body.rotation.z = _roll
	if _hop_t >= 0.0:
		_hop_t += delta
		if _hop_t >= _vs.hop_duration:
			_hop_t = -1.0
	_body.position.y = sin(_hop_t / _vs.hop_duration * PI) * _vs.hop_height if _hop_t >= 0.0 else 0.0
	# Landing squash (story 008): flattened at touchdown, springing back over land_squash_time.
	var squash: float = 0.0
	if _land_t >= 0.0:
		_land_t += delta
		var u: float = _land_t / maxf(_vs.land_squash_time, 0.01)
		if u >= 1.0:
			_land_t = -1.0
		else:
			squash = _vs.land_squash_amount * _land_strength * (1.0 - u) * (1.0 - u)
	_body.scale = Vector3(1.0 + squash * 0.5, 1.0 - squash, 1.0 + squash * 0.5)
	_animate_parts(delta, follow)
	_spin_angle = _spin_angle + delta * _vs.spin_speed if _sim.spin_time > 0.0 else 0.0
	_spin_root.rotation.y = _spin_angle

	for sp in _sparks:
		sp.visible = _sim.drifting
	if _sim.drifting:
		var colors: PackedColorArray = _sim.stats.spark_colors
		_spark_mat.albedo_color = colors[mini(_sim.drift_tier, colors.size() - 1)]
		var pulse: float = 1.0 + _vs.spark_pulse_amount * sin(_clock * _vs.spark_pulse_rate) \
				+ _vs.spark_tier_growth * _sim.drift_tier
		for sp in _sparks:
			sp.scale = Vector3.ONE * pulse
	_flame.visible = _sim.boost_time > 0.0
	if _flame.visible:
		_flame.scale = Vector3(1, 1.0 + _vs.flame_pulse_amount * sin(_clock * _vs.flame_pulse_rate), 1)
	_cost_usec += Time.get_ticks_usec() - t0


# Secondary motion (story 006), all small: wheel roll and front-wheel steer, rider lean,
# head bob, ears streaming back on boost and flopping in a spin-out, pennant wave.
func _animate_parts(delta: float, follow: float) -> void:
	var speed_frac: float = clampf(_sim.speed / maxf(_sim.stats.max_speed, 0.01), -1.0, 1.4)
	if _pennant != null:
		_pennant.set_speed(speed_frac)
	_wheel_angle = fposmod(_wheel_angle - _sim.speed / maxf(_vs.wheel_radius, 0.05) * delta, TAU)
	var steer: float = deg_to_rad(_vs.front_steer_deg) * clampf(_sim.last_steer, -1.0, 1.0)
	for w in _wheels:
		var node: Node3D = w.node
		var spin := Basis(Vector3.RIGHT, _wheel_angle)
		var turn := Basis(Vector3.UP, steer if w.front else 0.0)
		node.basis = turn * spin * (w.base as Basis)
	_lean_n = lerpf(_lean_n, clampf(_sim.accel_lat / _vs.lean_lat_norm, -1.0, 1.0), follow)
	if _dog_root != null:
		_dog_root.rotation.z = -_lean_n * deg_to_rad(_vs.rider_lean_deg)
	if _head != null:
		_head.position.y = _head_rest_y + sin(_clock * _vs.head_bob_rate) * _vs.head_bob_amount \
				* clampf(speed_frac, 0.0, 1.0)
	var ear_target: float = 0.0
	if _sim.spin_time > 0.0:
		ear_target = sin(_clock * _vs.ear_flop_rate) * deg_to_rad(_vs.ear_spin_flop_deg)
	elif _sim.boost_time > 0.0:
		ear_target = deg_to_rad(_vs.ear_boost_deg)
	_ear_angle = lerpf(_ear_angle, ear_target, 1.0 - exp(-_vs.ear_smoothing * delta))
	for i in _ears.size():
		_ears[i].rotation.x = _ear_rest[i] + _ear_angle


func _build() -> void:
	_spin_root = Node3D.new()
	add_child(_spin_root)
	_body = Node3D.new()
	_spin_root.add_child(_body)
	var mount: Vector3 = _vs.pennant_mount_fallback
	var vehicle: Node3D = _instance_glb(_vs.model_path)
	if vehicle != null:
		ModelBatcher.batch(vehicle, PackedStringArray([PAINT_MATERIAL]))
		_apply_no_shadow(vehicle)
		_body.add_child(vehicle)
		_collect_paint(vehicle, PAINT_MATERIAL)
		_warn_once(_paint_mats.is_empty(), "Paint", "vehicle model has no '%s' material; the identity color will not show on the vehicle" % PAINT_MATERIAL)
		_collect_wheels(vehicle)
		var seat: Node3D = vehicle.find_child("Seat", true, false) as Node3D
		_warn_once(seat == null, "Seat", "vehicle model has no 'Seat' node; using a default seat position")
		_warn_once(_wheels.is_empty(), "Wheels", "vehicle model has no 'Wheel_*' nodes")
		var seat_pos: Vector3 = (_to_body(seat).origin if seat != null else Vector3(0, 0.9, 0.2)) \
				+ _vs.seat_offset
		var mount_node: Node3D = vehicle.find_child("PennantMount", true, false) as Node3D
		_warn_once(mount_node == null, "Mount", "vehicle model has no 'PennantMount' node; using pennant_mount_fallback")
		if mount_node != null:
			mount = _to_body(mount_node).origin
		_build_dog(seat_pos)
	else:
		_build_placeholder_body()
	# The pole is the tallest thing: pennant_height_mult times the top of vehicle and rider.
	var pole: float = maxf(_top_y(_body) * _vs.pennant_height_mult - mount.y, 0.5)
	_pennant = Pennant.new()
	_pennant.position = mount
	_body.add_child(_pennant)
	_pennant.build(_style, pole, _slot, _color)

	_spark_mat = StandardMaterial3D.new()
	_spark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_spark_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var spark_mesh: SphereMesh = _spark_mesh(_vs)
	for side: float in [-1.0, 1.0]:
		var sp := MeshInstance3D.new()
		sp.mesh = spark_mesh
		sp.material_override = _spark_mat
		sp.position = Vector3(_vs.spark_offset.x * side, _vs.spark_offset.y, _vs.spark_offset.z)
		sp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		sp.visible = false
		_spin_root.add_child(sp)
		_sparks.append(sp)

	_flame = MeshInstance3D.new()
	_flame.mesh = _flame_mesh(_vs)
	var flame_mat := StandardMaterial3D.new()
	flame_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flame_mat.albedo_color = _vs.flame_color
	_flame.material_override = flame_mat
	_flame.rotation.x = PI / 2
	_flame.position = _vs.flame_position
	_flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flame.visible = false
	_body.add_child(_flame)


# The drift spark sphere for [param vs] (cached by size).
static func _spark_mesh(vs: VehicleVisualStats) -> SphereMesh:
	var key: String = "spark_%.4f" % vs.spark_radius
	if not _fx_meshes.has(key):
		var m := SphereMesh.new()
		m.radius = vs.spark_radius
		m.height = vs.spark_radius * 2.0
		_fx_meshes[key] = m
	return _fx_meshes[key]


# The boost flame cone for [param vs] (cached by size).
static func _flame_mesh(vs: VehicleVisualStats) -> CylinderMesh:
	var key: String = "flame_%.4f_%.4f" % [vs.flame_radius, vs.flame_length]
	if not _fx_meshes.has(key):
		var m := CylinderMesh.new()
		m.top_radius = 0.0
		m.bottom_radius = vs.flame_radius
		m.height = vs.flame_length
		_fx_meshes[key] = m
	return _fx_meshes[key]


# The old box-and-sphere body (kept as the fallback when a glb is missing).
func _build_placeholder_body() -> void:
	var paint := StandardMaterial3D.new()
	paint.albedo_color = _color
	_paint = paint
	var dark := StandardMaterial3D.new()
	dark.albedo_color = _vs.dark_color
	_box(_body, Vector3(1.3, 0.4, 2.0), Vector3(0, 0.45, 0), paint)
	_box(_body, Vector3(1.0, 0.25, 0.6), Vector3(0, 0.55, -1.15), paint)
	_box(_body, Vector3(1.5, 0.12, 0.35), Vector3(0, 0.75, 1.05), dark)
	_build_placeholder_dog(Vector3(0, 1.1, 0.2), paint)
	var wheel := CylinderMesh.new()
	wheel.top_radius = _vs.wheel_radius
	wheel.bottom_radius = _vs.wheel_radius
	wheel.height = _vs.wheel_width
	var wx: float = _vs.wheel_offset_x
	for wp: Vector3 in [Vector3(-wx, _vs.wheel_radius, _vs.wheel_front_z),
			Vector3(wx, _vs.wheel_radius, _vs.wheel_front_z),
			Vector3(-wx, _vs.wheel_radius, _vs.wheel_rear_z),
			Vector3(wx, _vs.wheel_radius, _vs.wheel_rear_z)]:
		var w := MeshInstance3D.new()
		w.mesh = wheel
		w.material_override = dark
		w.position = wp
		w.rotation.z = PI / 2
		_body.add_child(w)


# Two spheres (face and helmet) where the dog model would sit.
func _build_placeholder_dog(at: Vector3, helmet: Material) -> void:
	var skin := StandardMaterial3D.new()
	skin.albedo_color = _vs.skin_color
	_sphere(_body, 0.3, 0.6, false, at, skin)
	_sphere(_body, 0.33, 0.4, true, at + Vector3(0, 0.05, 0), helmet)


# Seats the racer's dog at [param seat_pos] (body space), or a placeholder dog when the
# racer or its glb is missing.
func _build_dog(seat_pos: Vector3) -> void:
	var path: String = _racer.model_path if _racer != null else ""
	var dog: Node3D = _instance_glb(path)
	if dog == null:
		var paint := StandardMaterial3D.new()
		paint.albedo_color = _color
		_paint = paint
		_build_placeholder_dog(seat_pos + Vector3(0, 0.2, 0), paint)
		return
	_dog_root = Node3D.new()
	_dog_root.position = seat_pos
	_dog_root.rotation.x = -deg_to_rad(_vs.rider_pitch_deg)
	_dog_root.scale = Vector3.ONE * _vs.dog_scale
	_body.add_child(_dog_root)
	ModelBatcher.batch(dog, PackedStringArray([TABARD_MATERIAL]))
	_apply_no_shadow(dog)
	_dog_root.add_child(dog)
	var before: int = _paint_mats.size()
	_collect_paint(dog, TABARD_MATERIAL)
	_warn_once(_paint_mats.size() == before, "Tabard", "dog model has no '%s' material; the identity color will not show on the dog" % TABARD_MATERIAL)
	_head = dog.find_child("Head", true, false) as Node3D
	_warn_once(_head == null, "Head", "dog model has no 'Head' node (no head bob)")
	if _head != null:
		_head_rest_y = _head.position.y
	for ear_name: String in ["Ear_L", "Ear_R"]:
		var ear: Node3D = dog.find_child(ear_name, true, false) as Node3D
		if ear != null:
			_ears.append(ear)
			_ear_rest.append(ear.rotation.x)
	_warn_once(_ears.is_empty(), "Ears", "dog model has no 'Ear_L'/'Ear_R' nodes (no ear motion)")


# Small parts cast no shadow (named in the vehicle's visual data).
func _apply_no_shadow(root: Node) -> void:
	for part_name in _vs.no_shadow_parts:
		var part: GeometryInstance3D = root.find_child(part_name, true, false) as GeometryInstance3D
		if part != null:
			part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


# One warning per kind of model problem per run (not one per kart).
func _warn_once(condition: bool, key: String, message: String) -> void:
	if not condition:
		return
	var k: String = "%s:%s" % [_vs.model_path, key]
	if _warned.has(k):
		return
	_warned[k] = true
	push_warning("KartVisual: " + message)


# Instances a glb scene, or returns null (one warning per path) when it is missing.
func _instance_glb(path: String) -> Node3D:
	if path == "":
		return null
	if not ResourceLoader.exists(path):
		if not _warned.has(path):
			_warned[path] = true
			push_warning("KartVisual: model '%s' not found; using the placeholder." % path)
		return null
	var scene: PackedScene = load(path) as PackedScene
	if scene == null:
		if not _warned.has(path):
			_warned[path] = true
			push_warning("KartVisual: '%s' is not a scene; using the placeholder." % path)
		return null
	return scene.instantiate() as Node3D


# Gives every mesh surface that uses the material named [param material_name] its own copy
# (the imported resource is shared by all karts and must not change), tinted with the identity color.
func _collect_paint(root: Node, material_name: String) -> void:
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = n as MeshInstance3D
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var m: BaseMaterial3D = mi.mesh.surface_get_material(i) as BaseMaterial3D
			if m != null and m.resource_name == material_name:
				var own: BaseMaterial3D = m.duplicate() as BaseMaterial3D
				own.albedo_color = _color
				mi.set_surface_override_material(i, own)
				_paint_mats.append(own)


# Finds the Wheel_* nodes; Wheel_F* are the steering ones.
func _collect_wheels(root: Node) -> void:
	var found: Array[Node] = root.find_children("Wheel_*", "Node3D", true, false)
	for n in found:
		var node: Node3D = n as Node3D
		# A match inside another match (a hub under a wheel) turns with its parent already.
		var nested: bool = false
		var up: Node = node.get_parent()
		while up != null and up != root:
			if found.has(up):
				nested = true
				break
			up = up.get_parent()
		if nested:
			continue
		_wheels.append({"node": node, "base": node.basis, "front": String(node.name).begins_with("Wheel_F")})


# [param node]'s transform relative to the body node.
func _to_body(node: Node3D) -> Transform3D:
	var t: Transform3D = Transform3D.IDENTITY
	var n: Node = node
	while n != null and n != _body and n is Node3D:
		t = (n as Node3D).transform * t
		n = n.get_parent()
	return t


# Highest point (body space) of every mesh under [param root].
func _top_y(root: Node) -> float:
	var top: float = 0.0
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = n as MeshInstance3D
		if mi.mesh == null:
			continue
		var t: Transform3D = _to_body(mi)
		var box: AABB = mi.mesh.get_aabb()
		for i in 8:
			top = maxf(top, (t * box.get_endpoint(i)).y)
	return top


func _box(parent: Node3D, size: Vector3, at: Vector3, m: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	mi.position = at
	parent.add_child(mi)


func _sphere(parent: Node3D, radius: float, height: float, hemisphere: bool, at: Vector3, m: Material) -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = height
	sm.is_hemisphere = hemisphere
	mi.mesh = sm
	mi.material_override = m
	mi.position = at
	parent.add_child(mi)
