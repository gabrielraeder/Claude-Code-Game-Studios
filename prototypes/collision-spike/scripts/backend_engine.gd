## PROTOTYPE - NOT FOR PRODUCTION. Collision spike. Engine (Jolt) backends (a) and (b).
##
## Built on PhysicsServer3D directly (private space, no nodes), so it can be used
## from a RefCounted and queried right after creation (see probe_query.gd).
##   MODE_FACE  (a): one ConcavePolygonShape3D for all ground, surface = table[face_index]
##                   (needs physics/jolt_physics_3d/queries/enable_ray_cast_face_index=true)
##   MODE_SHAPE (b): one ConcavePolygonShape3D per ground surface id on one body,
##                   surface = table[shape_index]
## Walls are a second body on collision layer WALL_LAYER so that the wall sweep
## never touches the ground.
## API_INTO uses the 4.8 *_into methods with reused result objects; API_DICT the
## classic Dictionary / PackedFloat32Array returning methods.
extends RefCounted

const TrackGen := preload("res://scripts/track_gen.gd")

enum { MODE_FACE, MODE_SHAPE }
enum { API_INTO, API_DICT }

const GROUND_LAYER: int = 1
const WALL_LAYER: int = 2

var mode: int = MODE_FACE
var api: int = API_INTO
var space: RID
var ground_body: RID
var wall_body: RID
var shapes: Array[Shape3D] = []  # keep shapes alive
var surf_by_face := PackedByteArray()
var surf_by_shape := PackedByteArray()
var build_ms: float = 0.0

var _state: PhysicsDirectSpaceState3D
var _ray := PhysicsRayQueryParameters3D.new()
var _ray_res := PhysicsIntersectRayResult3D.new()
var _sphere := SphereShape3D.new()
var _motion := PhysicsShapeQueryParameters3D.new()
var _motion_res := PhysicsCastMotionResult3D.new()
var _rest_res := PhysicsGetRestInfoResult3D.new()

# Output of the last query (caller reads them; no per-call allocation here).
var hit_pos: Vector3
var hit_normal: Vector3
var hit_surf: int = -1
var wall_pos: Vector3
var wall_normal: Vector3
var wall_contact_misses: int = 0  # motion hit but rest info found nothing

func _static_body(shape_list: Array[Shape3D], layer: int) -> RID:
	var b: RID = PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(b, PhysicsServer3D.BODY_MODE_STATIC)
	for s: Shape3D in shape_list:
		PhysicsServer3D.body_add_shape(b, s.get_rid())
	PhysicsServer3D.body_set_collision_layer(b, layer)
	PhysicsServer3D.body_set_collision_mask(b, 0)
	PhysicsServer3D.body_set_space(b, space)
	return b

func setup(tg: TrackGen, p_mode: int, p_api: int, radius: float) -> void:
	mode = p_mode
	api = p_api
	var t0: int = Time.get_ticks_usec()
	space = PhysicsServer3D.space_create()
	PhysicsServer3D.space_set_active(space, true)
	var ground_shapes: Array[Shape3D] = []
	if mode == MODE_FACE:
		var s := ConcavePolygonShape3D.new()
		s.set_faces(tg.ground_faces)
		ground_shapes.append(s)
		surf_by_face = tg.ground_surf
	else:
		var per := []
		for k: int in TrackGen.SURF_COUNT:
			per.append(PackedVector3Array())
		for t: int in tg.ground_tri_count():
			var sid: int = tg.ground_surf[t]
			per[sid].append_array([tg.ground_faces[t * 3], tg.ground_faces[t * 3 + 1], tg.ground_faces[t * 3 + 2]])
		for k: int in TrackGen.SURF_COUNT:
			if (per[k] as PackedVector3Array).is_empty():
				continue
			var s := ConcavePolygonShape3D.new()
			s.set_faces(per[k])
			ground_shapes.append(s)
			surf_by_shape.append(k)
	var ws := ConcavePolygonShape3D.new()
	ws.set_faces(tg.wall_faces)
	var wall_shapes: Array[Shape3D] = [ws]
	shapes.append_array(ground_shapes)
	shapes.append_array(wall_shapes)
	ground_body = _static_body(ground_shapes, GROUND_LAYER)
	wall_body = _static_body(wall_shapes, WALL_LAYER)
	_state = PhysicsServer3D.space_get_direct_state(space)
	_ray.collision_mask = GROUND_LAYER
	_ray.hit_back_faces = false
	_sphere.radius = radius
	_motion.shape = _sphere
	_motion.collision_mask = WALL_LAYER
	build_ms = (Time.get_ticks_usec() - t0) / 1000.0
	# first query forces any lazy build so it is not inside the timed loop
	cast_ground(Vector3(0, 100, 0), Vector3.DOWN, 1.0)

func free_all() -> void:
	PhysicsServer3D.free_rid(ground_body)
	PhysicsServer3D.free_rid(wall_body)
	PhysicsServer3D.free_rid(space)

## Ray from origin along dir (unit) up to max_dist. Writes hit_* on success.
func cast_ground(origin: Vector3, dir: Vector3, max_dist: float) -> bool:
	_ray.from = origin
	_ray.to = origin + dir * max_dist
	if api == API_INTO:
		if not _state.intersect_ray_into(_ray, _ray_res):
			return false
		hit_pos = _ray_res.position
		hit_normal = _ray_res.normal
		if mode == MODE_FACE:
			hit_surf = surf_by_face[_ray_res.collider_face_index]
		else:
			hit_surf = surf_by_shape[_ray_res.collider_shape]
		return true
	var d: Dictionary = _state.intersect_ray(_ray)
	if d.is_empty():
		return false
	hit_pos = d.position
	hit_normal = d.normal
	if mode == MODE_FACE:
		hit_surf = surf_by_face[d.face_index]
	else:
		hit_surf = surf_by_shape[d.shape]
	return true

## Sphere sweep from -> to. cast_motion ignores a sphere that already overlaps a
## face at the start (probe_motion.gd), so when the cast finds nothing the sphere
## is also tested for overlap at `to` with get_rest_info. On contact:
## wall_pos / wall_normal from rest info (at the unsafe fraction, or at `to`).
func sweep_walls(from: Vector3, to: Vector3) -> bool:
	_motion.transform = Transform3D(Basis.IDENTITY, from)
	var motion: Vector3 = to - from
	_motion.motion = motion
	var unsafe: float = 1.0
	if api == API_INTO:
		if _state.cast_motion_into(_motion, _motion_res):
			unsafe = _motion_res.unsafe_fraction
	else:
		var fr: PackedFloat32Array = _state.cast_motion(_motion)
		unsafe = fr[1]
	_motion.transform = Transform3D(Basis.IDENTITY, from + motion * unsafe)
	_motion.motion = Vector3.ZERO
	if api == API_INTO:
		if not _state.get_rest_info_into(_motion, _rest_res):
			if unsafe < 1.0:
				wall_contact_misses += 1
			return false
		wall_pos = _rest_res.point
		wall_normal = _rest_res.normal
		return true
	var info: Dictionary = _state.get_rest_info(_motion)
	if info.is_empty():
		if unsafe < 1.0:
			wall_contact_misses += 1
		return false
	wall_pos = info.point
	wall_normal = info.normal
	return true
