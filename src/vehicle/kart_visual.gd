class_name KartVisual
extends Node3D
## Draws a KartSim: placeholder box-and-sphere cart, drift tilt and hop, tier-colored
## sparks, boost flame, spin-out. Reads simulation state only; never writes it, so the
## same node can show a local kart or an interpolated remote copy.
## Implements design/game-brief.md, Features item 1 ("Look and references" placeholders).

const HOP_HEIGHT: float = 0.35
const HOP_DECAY: float = 1.6
const DRIFT_TILT: float = 0.4
const TILT_SMOOTHING: float = 10.0
const SPIN_SPEED: float = 14.0
const SPARK_PULSE_RATE: float = 30.0
const FLAME_PULSE_RATE: float = 50.0

var _sim: KartSim
var _body: Node3D
var _spin_root: Node3D
var _sparks: Array[MeshInstance3D] = []
var _spark_mat: StandardMaterial3D
var _flame: MeshInstance3D
var _hop: float = 0.0
var _spin_angle: float = 0.0
var _clock: float = 0.0


## Binds this visual to [param sim] and builds the meshes using its stats.
func bind(sim: KartSim) -> void:
	_sim = sim
	_sim.drift_started.connect(_on_drift_started)
	_build()


func _on_drift_started(_direction: int) -> void:
	_hop = HOP_HEIGHT


func _process(delta: float) -> void:
	if _sim == null:
		return
	_clock += delta
	var fraction: float = Engine.get_physics_interpolation_fraction()
	var p: Vector2 = _sim.interpolated_position(fraction)
	position = Vector3(p.x, 0.0, p.y)
	rotation.y = _sim.interpolated_yaw(fraction)

	var tilt: float = _sim.drift_dir * DRIFT_TILT if _sim.drifting else 0.0
	_body.rotation.y = lerp_angle(_body.rotation.y, tilt, 1.0 - exp(-TILT_SMOOTHING * delta))
	_hop = maxf(0.0, _hop - delta * HOP_DECAY)
	_body.position.y = sin(_hop / HOP_HEIGHT * PI) * HOP_HEIGHT if _hop > 0.0 else 0.0
	_spin_angle = _spin_angle + delta * SPIN_SPEED if _sim.spin_time > 0.0 else 0.0
	_spin_root.rotation.y = _spin_angle

	for sp in _sparks:
		sp.visible = _sim.drifting
	if _sim.drifting:
		var colors: PackedColorArray = _sim.stats.spark_colors
		_spark_mat.albedo_color = colors[mini(_sim.drift_tier, colors.size() - 1)]
		var pulse: float = 1.0 + 0.2 * sin(_clock * SPARK_PULSE_RATE) + 0.2 * _sim.drift_tier
		for sp in _sparks:
			sp.scale = Vector3.ONE * pulse
	_flame.visible = _sim.boost_time > 0.0
	if _flame.visible:
		_flame.scale = Vector3(1, 1.0 + 0.3 * sin(_clock * FLAME_PULSE_RATE), 1)


func _build() -> void:
	_spin_root = Node3D.new()
	add_child(_spin_root)
	_body = Node3D.new()
	_spin_root.add_child(_body)
	var paint := StandardMaterial3D.new()
	paint.albedo_color = _sim.stats.paint_color
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.12, 0.12, 0.14)
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.95, 0.85, 0.7)

	_box(_body, Vector3(1.3, 0.4, 2.0), Vector3(0, 0.45, 0), paint)
	_box(_body, Vector3(1.0, 0.25, 0.6), Vector3(0, 0.55, -1.15), paint)
	_box(_body, Vector3(1.5, 0.12, 0.35), Vector3(0, 0.75, 1.05), dark)
	_sphere(_body, 0.3, 0.6, false, Vector3(0, 1.1, 0.2), skin)
	_sphere(_body, 0.33, 0.4, true, Vector3(0, 1.15, 0.2), paint)
	var wheel := CylinderMesh.new()
	wheel.top_radius = 0.32
	wheel.bottom_radius = 0.32
	wheel.height = 0.3
	for wp: Vector3 in [Vector3(-0.75, 0.32, -0.7), Vector3(0.75, 0.32, -0.7),
			Vector3(-0.75, 0.32, 0.75), Vector3(0.75, 0.32, 0.75)]:
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
	spark_mesh.radius = 0.14
	spark_mesh.height = 0.28
	for sx: float in [-0.75, 0.75]:
		var sp := MeshInstance3D.new()
		sp.mesh = spark_mesh
		sp.material_override = _spark_mat
		sp.position = Vector3(sx, 0.25, 1.1)
		sp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		sp.visible = false
		_spin_root.add_child(sp)
		_sparks.append(sp)

	_flame = MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.35
	cone.height = 1.4
	_flame.mesh = cone
	var flame_mat := StandardMaterial3D.new()
	flame_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flame_mat.albedo_color = Color(1.0, 0.55, 0.1)
	_flame.material_override = flame_mat
	_flame.rotation.x = PI / 2
	_flame.position = Vector3(0, 0.5, 1.7)
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
