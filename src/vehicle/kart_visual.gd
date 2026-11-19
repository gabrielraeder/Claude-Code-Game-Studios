class_name KartVisual
extends Node3D
## Draws a KartSim: placeholder box-and-sphere cart, drift body angle and hop, small
## acceleration lean, tier-colored sparks, boost flame, spin-out. Reads simulation state
## only; never writes it, so the same node can show a local kart or an interpolated copy.
## Every number comes from VehicleStats.visual (VehicleVisualStats).
## Implements design/game-brief.md, Features item 1 ("Look and references" placeholders).

var _sim: KartSim
var _vs: VehicleVisualStats
var _body: Node3D
var _spin_root: Node3D
var _sparks: Array[MeshInstance3D] = []
var _spark_mat: StandardMaterial3D
var _flame: MeshInstance3D
var _hop_t: float = -1.0
var _spin_angle: float = 0.0
var _clock: float = 0.0
var _pitch: float = 0.0
var _roll: float = 0.0


## Binds this visual to [param sim] and builds the meshes using its stats.
func bind(sim: KartSim) -> void:
	_sim = sim
	_vs = sim.stats.visual
	_sim.drift_started.connect(_on_drift_started)
	_build()


func _on_drift_started(_direction: int) -> void:
	_hop_t = 0.0


func _process(delta: float) -> void:
	if _sim == null:
		return
	_clock += delta
	var fraction: float = Engine.get_physics_interpolation_fraction()
	var p: Vector2 = _sim.interpolated_position(fraction)
	position = Vector3(p.x, 0.0, p.y)
	rotation.y = _sim.interpolated_yaw(fraction)

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


func _build() -> void:
	_spin_root = Node3D.new()
	add_child(_spin_root)
	_body = Node3D.new()
	_spin_root.add_child(_body)
	var paint := StandardMaterial3D.new()
	paint.albedo_color = _sim.stats.paint_color
	var dark := StandardMaterial3D.new()
	dark.albedo_color = _vs.dark_color
	var skin := StandardMaterial3D.new()
	skin.albedo_color = _vs.skin_color

	# Placeholder model shapes (box layout) stay as code; see story 006 for real models.
	_box(_body, Vector3(1.3, 0.4, 2.0), Vector3(0, 0.45, 0), paint)
	_box(_body, Vector3(1.0, 0.25, 0.6), Vector3(0, 0.55, -1.15), paint)
	_box(_body, Vector3(1.5, 0.12, 0.35), Vector3(0, 0.75, 1.05), dark)
	_sphere(_body, 0.3, 0.6, false, Vector3(0, 1.1, 0.2), skin)
	_sphere(_body, 0.33, 0.4, true, Vector3(0, 1.15, 0.2), paint)
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

	_spark_mat = StandardMaterial3D.new()
	_spark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_spark_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var spark_mesh := SphereMesh.new()
	spark_mesh.radius = _vs.spark_radius
	spark_mesh.height = _vs.spark_radius * 2.0
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
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = _vs.flame_radius
	cone.height = _vs.flame_length
	_flame.mesh = cone
	var flame_mat := StandardMaterial3D.new()
	flame_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flame_mat.albedo_color = _vs.flame_color
	_flame.material_override = flame_mat
	_flame.rotation.x = PI / 2
	_flame.position = _vs.flame_position
	_flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flame.visible = false
	_body.add_child(_flame)


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
