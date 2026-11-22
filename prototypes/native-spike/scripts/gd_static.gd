## PROTOTYPE - NOT FOR PRODUCTION. Native spike (ADR-0007).
## GDScript reference for the static path: the same PhysicsServer3D `_into` calls as
## NativeSpikeQuery.static_* in C++, on its own private space.
extends RefCounted

var space: RID
var bodies: Array[RID] = []
var shapes: Array[RID] = []
var sphere: RID
var sphere_radius: float = -1.0
var state: PhysicsDirectSpaceState3D
var ray_params: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.new()
var ray_result: PhysicsIntersectRayResult3D = PhysicsIntersectRayResult3D.new()
var shape_params: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
var cast_result: PhysicsCastMotionResult3D = PhysicsCastMotionResult3D.new()
var rest_result: PhysicsGetRestInfoResult3D = PhysicsGetRestInfoResult3D.new()
var last_normal: Vector3 = Vector3.ZERO
var _out: PackedFloat64Array = PackedFloat64Array()


func setup(ground_faces: PackedVector3Array, wall_faces: PackedVector3Array) -> void:
	space = PhysicsServer3D.space_create()
	PhysicsServer3D.space_set_active(space, true)
	_make_body(ground_faces, 1)
	_make_body(wall_faces, 2)
	sphere = PhysicsServer3D.sphere_shape_create()
	shapes.append(sphere)
	state = PhysicsServer3D.space_get_direct_state(space)
	ray_params.collision_mask = 1
	ray_params.hit_back_faces = false
	shape_params.collision_mask = 2
	shape_params.shape_rid = sphere


func _make_body(faces: PackedVector3Array, layer: int) -> void:
	var shape: RID = PhysicsServer3D.concave_polygon_shape_create()
	PhysicsServer3D.shape_set_data(shape, {"faces": faces, "backface_collision": false})
	shapes.append(shape)
	var body: RID = PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_set_collision_layer(body, layer)
	PhysicsServer3D.body_set_collision_mask(body, 0)
	PhysicsServer3D.body_add_shape(body, shape)
	PhysicsServer3D.body_set_space(body, space)
	bodies.append(body)


func dispose() -> void:
	for b in bodies:
		PhysicsServer3D.free_rid(b)
	for s in shapes:
		PhysicsServer3D.free_rid(s)
	PhysicsServer3D.free_rid(space)
	bodies.clear()
	shapes.clear()


func cast_ground(origin: Vector3, dir: Vector3, max_dist: float) -> float:
	ray_params.from = origin
	ray_params.to = origin + dir * max_dist
	if not state.intersect_ray_into(ray_params, ray_result):
		return -1.0
	last_normal = ray_result.normal
	return (ray_result.position - origin).dot(dir)


func sweep(from: Vector3, to: Vector3, radius: float) -> float:
	if sphere_radius != radius:
		PhysicsServer3D.shape_set_data(sphere, radius)
		sphere_radius = radius
	var motion: Vector3 = to - from
	shape_params.transform = Transform3D(Basis.IDENTITY, from)
	if state.get_rest_info_into(shape_params, rest_result):
		last_normal = rest_result.normal
		return 0.0
	if motion == Vector3.ZERO:
		return -1.0
	shape_params.motion = motion
	var cast_hit: bool = state.cast_motion_into(shape_params, cast_result)
	shape_params.motion = Vector3.ZERO
	if cast_hit and cast_result.unsafe_fraction < 1.0:
		var safe: float = cast_result.safe_fraction
		shape_params.transform = Transform3D(Basis.IDENTITY, from + motion * cast_result.unsafe_fraction)
		if state.get_rest_info_into(shape_params, rest_result):
			last_normal = rest_result.normal
		return safe
	shape_params.transform = Transform3D(Basis.IDENTITY, to)
	if state.get_rest_info_into(shape_params, rest_result):
		last_normal = rest_result.normal
		return 1.0
	return -1.0


func tick(ray_origins: PackedVector3Array, ray_dirs: PackedVector3Array, ray_len: float,
		sweep_from: PackedVector3Array, sweep_to: PackedVector3Array, radius: float) -> PackedFloat64Array:
	var nr: int = ray_origins.size()
	var ns: int = sweep_from.size()
	var per_kart: int = nr / ray_dirs.size()
	if _out.size() != nr + ns:
		_out.resize(nr + ns)
	for i in nr:
		_out[i] = cast_ground(ray_origins[i], ray_dirs[i / per_kart], ray_len)
	for i in ns:
		_out[nr + i] = sweep(sweep_from[i], sweep_to[i], radius)
	return _out
