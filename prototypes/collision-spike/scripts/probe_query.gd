## PROTOTYPE - NOT FOR PRODUCTION. Collision spike. Q1 face_index / Q2 query timing / winding.
## Run: godot --headless --path . -s res://scripts/probe_query.gd
## Face 0 is wound so Godot's Plane(a,b,c) normal points +Y; face 1 is wound the
## other way (normal -Y); face 2 is a small deck above the floor (normal +Y).
extends SceneTree

const FLOOR_HALF: float = 10.0
const RAY_TOP: float = 5.0
const RAY_BOTTOM: float = -5.0
const PROBE_X: float = 3.0
const PROBE_Z: float = -4.0
const DECK_Y: float = 2.0
const B2_OFFSET: Vector3 = Vector3(100, 0, 0)

var _shape: ConcavePolygonShape3D
var _shape_bf: ConcavePolygonShape3D
var _body: StaticBody3D
var _priv_space: RID
var _priv_body: RID
var _priv_space_bf: RID
var _priv_body_bf: RID
var _world_body: RID
var _frames: int = 0
var _physics_frames: int = 0

func _make_faces() -> PackedVector3Array:
	var h: float = FLOOR_HALF
	var f := PackedVector3Array()
	f.append_array([Vector3(-h, 0, -h), Vector3(h, 0, -h), Vector3(-h, 0, h)])
	f.append_array([Vector3(h, 0, -h), Vector3(-h, 0, h), Vector3(h, 0, h)])
	f.append_array([Vector3(PROBE_X - 1, DECK_Y, PROBE_Z - 1), Vector3(PROBE_X + 1, DECK_Y, PROBE_Z - 1), Vector3(PROBE_X - 1, DECK_Y, PROBE_Z + 1)])
	return f

func _fmt_hit(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3, back_faces: bool) -> String:
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.hit_back_faces = back_faces
	var d: Dictionary = space.intersect_ray(q)
	var res := PhysicsIntersectRayResult3D.new()
	var ok: bool = space.intersect_ray_into(q, res)
	var s: String = "dict:" + ("MISS" if d.is_empty() else "y=%.2f n=%s face=%d shape=%d" % [d.position.y, d.normal, d.face_index, d.shape])
	s += " | into:" + ("MISS" if not ok else "y=%.2f n=%s face=%d shape=%d" % [res.position.y, res.normal, res.collider_face_index, res.collider_shape])
	return s

func _down(space: PhysicsDirectSpaceState3D, off: Vector3, x: float, z: float, top: float, back: bool) -> String:
	return _fmt_hit(space, off + Vector3(x, top, z), off + Vector3(x, RAY_BOTTOM, z), back)

func _up(space: PhysicsDirectSpaceState3D, off: Vector3, x: float, z: float, back: bool) -> String:
	return _fmt_hit(space, off + Vector3(x, -3.0, z), off + Vector3(x, 1.0, z), back)

func _probe_space(label: String, space: PhysicsDirectSpaceState3D, off: Vector3) -> void:
	if space == null:
		print("  [", label, "] direct space state is null")
		return
	for back: bool in [false, true]:
		print("  [%s] back=%s down f0(+Y): %s" % [label, back, _down(space, off, -5, -5, RAY_TOP, back)])
		print("  [%s] back=%s down f1(-Y): %s" % [label, back, _down(space, off, 5, 5, RAY_TOP, back)])
		print("  [%s] back=%s down deck  : %s" % [label, back, _down(space, off, PROBE_X - 0.5, PROBE_Z - 0.5, RAY_TOP, back)])
		print("  [%s] back=%s up   f0(+Y): %s" % [label, back, _up(space, off, -5, -5, back)])
		print("  [%s] back=%s up   f1(-Y): %s" % [label, back, _up(space, off, 5, 5, back)])

func _probe_all(label: String) -> void:
	print(" -- ", label, " (frames=", _frames, " physics_frames=", _physics_frames, ", tree body inside_tree=", _body.is_inside_tree(), ")")
	var world_space: PhysicsDirectSpaceState3D = root.get_world_3d().direct_space_state
	_probe_space("node StaticBody3D in world space", world_space, Vector3.ZERO)
	_probe_space("server body in world space", world_space, B2_OFFSET)
	_probe_space("server body in private space", PhysicsServer3D.space_get_direct_state(_priv_space), Vector3.ZERO)
	_probe_space("private space, backface_collision=true", PhysicsServer3D.space_get_direct_state(_priv_space_bf), Vector3.ZERO)

func _server_body(space: RID, shape: Shape3D, xf: Transform3D) -> RID:
	var b: RID = PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(b, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_add_shape(b, shape.get_rid())
	PhysicsServer3D.body_set_state(b, PhysicsServer3D.BODY_STATE_TRANSFORM, xf)
	PhysicsServer3D.body_set_space(b, space)
	return b

func _initialize() -> void:
	print("enable_ray_cast_face_index = ", ProjectSettings.get_setting("physics/jolt_physics_3d/queries/enable_ray_cast_face_index"))
	print("can_instantiate PhysicsIntersectRayResult3D: ", ClassDB.can_instantiate("PhysicsIntersectRayResult3D"))
	print("default hit_back_faces=", PhysicsRayQueryParameters3D.new().hit_back_faces, " hit_from_inside=", PhysicsRayQueryParameters3D.new().hit_from_inside)
	_shape = ConcavePolygonShape3D.new()
	_shape.set_faces(_make_faces())
	_shape_bf = ConcavePolygonShape3D.new()
	_shape_bf.backface_collision = true
	_shape_bf.set_faces(_make_faces())
	print("ConcavePolygonShape3D.backface_collision default=", _shape.backface_collision)
	_body = StaticBody3D.new()
	var cs := CollisionShape3D.new()
	cs.shape = _shape
	_body.add_child(cs)
	root.add_child(_body)
	_world_body = _server_body(root.get_world_3d().space, _shape, Transform3D(Basis.IDENTITY, B2_OFFSET))
	_priv_space = PhysicsServer3D.space_create()
	PhysicsServer3D.space_set_active(_priv_space, true)
	_priv_body = _server_body(_priv_space, _shape, Transform3D.IDENTITY)
	_priv_space_bf = PhysicsServer3D.space_create()
	PhysicsServer3D.space_set_active(_priv_space_bf, true)
	_priv_body_bf = _server_body(_priv_space_bf, _shape_bf, Transform3D.IDENTITY)
	_probe_all("_initialize, same call as creation")

func _physics_process(_delta: float) -> bool:
	_physics_frames += 1
	if _physics_frames == 1:
		_probe_all("first _physics_process")
	return false

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 2:
		_probe_all("second _process")
		for r: RID in [_world_body, _priv_body, _priv_body_bf, _priv_space, _priv_space_bf]:
			PhysicsServer3D.free_rid(r)
		return true
	return false
