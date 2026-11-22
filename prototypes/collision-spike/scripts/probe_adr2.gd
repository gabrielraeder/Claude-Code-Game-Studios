## Scratch probe for ADR-0002 review. Run with --path prototypes/collision-spike -s <abs path>
extends SceneTree

const R: float = 0.6
var _frame: int = 0

func _floor_faces(with_degenerate: bool) -> PackedVector3Array:
	var f := PackedVector3Array()
	if with_degenerate:
		f.append_array([Vector3(0, 0, 0), Vector3(0, 0, 0), Vector3(1, 0, 0)])  # degenerate, idx 0
		f.append_array([Vector3(50, 0, 50), Vector3(51, 0, 50), Vector3(50, 0, 50)])  # degenerate, idx 1
	# up-facing quad around origin (front = (c-a)x(b-a))
	var h: float = 10.0
	f.append_array([Vector3(-h, 0, -h), Vector3(h, 0, -h), Vector3(-h, 0, h)])
	f.append_array([Vector3(h, 0, -h), Vector3(h, 0, h), Vector3(-h, 0, h)])
	return f

func _wall_faces(x: float, front_pos_x: bool) -> PackedVector3Array:
	var a := Vector3(x, 0, -10)
	var b := Vector3(x, 3, -10)
	var c := Vector3(x, 0, 10)
	var d := Vector3(x, 3, 10)
	var f := PackedVector3Array()
	for tri: Array in [[a, b, c], [c, b, d]]:
		var n: Vector3 = (tri[2] - tri[0]).cross(tri[1] - tri[0])
		if (n.x > 0.0) == front_pos_x:
			f.append_array([tri[0], tri[1], tri[2]])
		else:
			f.append_array([tri[0], tri[2], tri[1]])
	return f

func _body(space: RID, shapes: Array, layer: int, space_first: bool = false) -> RID:
	var b: RID = PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(b, PhysicsServer3D.BODY_MODE_STATIC)
	if space_first:
		PhysicsServer3D.body_set_space(b, space)
	for s: RID in shapes:
		PhysicsServer3D.body_add_shape(b, s)
	PhysicsServer3D.body_set_collision_layer(b, layer)
	PhysicsServer3D.body_set_collision_mask(b, 0)
	if not space_first:
		PhysicsServer3D.body_set_space(b, space)
	return b

func _ray(st: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3, mask: int = 0xFFFFFFFF, back: bool = false) -> String:
	var q := PhysicsRayQueryParameters3D.create(from, to, mask)
	q.hit_back_faces = back
	var r := PhysicsIntersectRayResult3D.new()
	if not st.intersect_ray_into(q, r):
		return "MISS"
	return "hit y=%.2f n=%s face=%d shape=%d id=%d" % [r.position.y, r.normal, r.collider_face_index, r.collider_shape, r.collider_id]

func _rest(st: PhysicsDirectSpaceState3D, at: Vector3, mask: int = 0xFFFFFFFF) -> String:
	var sph := SphereShape3D.new()
	sph.radius = R
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = sph
	q.transform = Transform3D(Basis.IDENTITY, at)
	q.collision_mask = mask
	var r := PhysicsGetRestInfoResult3D.new()
	if not st.get_rest_info_into(q, r):
		return "none"
	return "n=%s p=%s shape=%d rid=%s id=%d" % [r.normal, r.point, r.collider_shape, r.collider_rid, r.collider_id]

func _cast(st: PhysicsDirectSpaceState3D, from: Vector3, motion: Vector3, mask: int = 0xFFFFFFFF) -> String:
	var sph := SphereShape3D.new()
	sph.radius = R
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = sph
	q.transform = Transform3D(Basis.IDENTITY, from)
	q.motion = motion
	q.collision_mask = mask
	var r := PhysicsCastMotionResult3D.new()
	var ok: bool = st.cast_motion_into(q, r)
	return "ret=%s safe=%.3f unsafe=%.3f" % [ok, r.safe_fraction, r.unsafe_fraction]

func _initialize() -> void:
	var mode: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "main"
	print("mode=", mode, " face_index setting=", ProjectSettings.get_setting("physics/jolt_physics_3d/queries/enable_ray_cast_face_index"))
	if mode == "free_space_first":
		_free_space_first()
		quit()
		return
	if mode == "use_after_dispose":
		_use_after_dispose()
		quit()
		return
	if mode == "main":
		ProjectSettings.set_setting("physics/jolt_physics_3d/queries/enable_ray_cast_face_index", true)

func _process(_d: float) -> bool:
	_frame += 1
	if _frame == 2:
		_main()
		quit()
	return false

func _main() -> void:
	print("face_index setting now=", ProjectSettings.get_setting("physics/jolt_physics_3d/queries/enable_ray_cast_face_index"))
	# T1 inactive space
	var sp_inactive: RID = PhysicsServer3D.space_create()
	var fs := PhysicsServer3D.concave_polygon_shape_create()
	PhysicsServer3D.shape_set_data(fs, {"faces": _floor_faces(true), "backface_collision": false})
	var b_in: RID = _body(sp_inactive, [fs], 1)
	var st_in: PhysicsDirectSpaceState3D = PhysicsServer3D.space_get_direct_state(sp_inactive)
	print("T1 inactive space: direct_state=", st_in != null, " ray=", _ray(st_in, Vector3(1, 5, 1), Vector3(1, -5, 1)) if st_in else "")
	# T2 degenerate triangles: real quads are indices 2,3 in set_faces order
	print("T2 degenerate first: ray at (5,_,-5) (tri idx2) ", _ray(st_in, Vector3(5, 5, -5), Vector3(5, -5, -5)), " | at (5,_,5) (tri idx3) ", _ray(st_in, Vector3(5, 5, 5), Vector3(5, -5, 5)))
	# T10 body_set_space before add_shape
	var sp2: RID = PhysicsServer3D.space_create()
	var fs2 := PhysicsServer3D.concave_polygon_shape_create()
	PhysicsServer3D.shape_set_data(fs2, {"faces": _floor_faces(false), "backface_collision": false})
	var b2: RID = _body(sp2, [fs2], 1, true)
	print("T10 space set before shapes, inactive: ", _ray(PhysicsServer3D.space_get_direct_state(sp2), Vector3(1, 5, 1), Vector3(1, -5, 1)))
	# T3 multi-shape wall body: shape idx -> attr ; and separate bodies
	var sp3: RID = PhysicsServer3D.space_create()
	var w0 := ConcavePolygonShape3D.new(); w0.set_faces(_wall_faces(0.0, true))
	var w1 := ConcavePolygonShape3D.new(); w1.set_faces(_wall_faces(20.0, true))
	var w2 := ConcavePolygonShape3D.new(); w2.set_faces(_wall_faces(40.0, true))
	var bw: RID = _body(sp3, [w0.get_rid(), w1.get_rid(), w2.get_rid()], 2)
	var g3 := ConcavePolygonShape3D.new(); g3.set_faces(_floor_faces(false))
	var bg3: RID = _body(sp3, [g3.get_rid()], 1)
	var st3: PhysicsDirectSpaceState3D = PhysicsServer3D.space_get_direct_state(sp3)
	print("T3 rest walls mask=2 near shape0: ", _rest(st3, Vector3(0.3, 1, 0), 2))
	print("T3 rest walls mask=2 near shape1: ", _rest(st3, Vector3(20.3, 1, 0), 2))
	print("T3 rest walls mask=2 near shape2: ", _rest(st3, Vector3(40.3, 1, 0), 2))
	print("T3 rest mask=1 near shape2 (should be none, floor far): ", _rest(st3, Vector3(40.3, 1, 0), 1))
	print("T3 rest mask=3 at floor+wall corner (0.3,0.3,0): ", _rest(st3, Vector3(0.3, 0.3, 0), 3))
	print("T3 ray mask=1 through wall: ", _ray(st3, Vector3(5, 1, 0), Vector3(-5, 1, 0), 1), " mask=2: ", _ray(st3, Vector3(5, 1, 0), Vector3(-5, 1, 0), 2))
	print("   wall body id=", PhysicsServer3D.body_get_object_instance_id(bw), " ground id=", PhysicsServer3D.body_get_object_instance_id(bg3))
	# T4 backface_collision=true wall, sphere on back side
	for bf: bool in [false, true]:
		var sp4: RID = PhysicsServer3D.space_create()
		var ws := ConcavePolygonShape3D.new()
		ws.backface_collision = bf
		ws.set_faces(_wall_faces(0.0, true))  # front +X
		var b4: RID = _body(sp4, [ws.get_rid()], 2)
		var st4: PhysicsDirectSpaceState3D = PhysicsServer3D.space_get_direct_state(sp4)
		print("T4 backface_collision=", bf)
		print("   front: far->toward ", _cast(st4, Vector3(2, 1, 0), Vector3(-1.5, 0, 0)))
		print("   back : far->toward ", _cast(st4, Vector3(-2, 1, 0), Vector3(1.5, 0, 0)), " rest@unsafe-ish(-0.5) ", _rest(st4, Vector3(-0.5, 1, 0)))
		print("   front: center crosses plane 0.3 -> -1.0 ", _cast(st4, Vector3(0.3, 1, 0), Vector3(-1.3, 0, 0)), " rest@to ", _rest(st4, Vector3(-1.0, 1, 0)))
		print("   front: from 1.0 through to -2.0 ", _cast(st4, Vector3(1.0, 1, 0), Vector3(-3.0, 0, 0)))
		print("   start overlap front 0.3 toward ", _cast(st4, Vector3(0.3, 1, 0), Vector3(-0.2, 0, 0)), " rest@from ", _rest(st4, Vector3(0.3, 1, 0)))
		print("   start overlap back -0.3 ", _rest(st4, Vector3(-0.3, 1, 0)))
		print("   ray back side hit_back_faces=false ", _ray(st4, Vector3(-5, 1, 0), Vector3(5, 1, 0), 0xFFFFFFFF, false), " true ", _ray(st4, Vector3(-5, 1, 0), Vector3(5, 1, 0), 0xFFFFFFFF, true))
		PhysicsServer3D.free_rid(b4)
		PhysicsServer3D.free_rid(sp4)
	# T5 drop the Shape3D resource while the body uses it
	var sp5: RID = PhysicsServer3D.space_create()
	var s5 := ConcavePolygonShape3D.new(); s5.set_faces(_floor_faces(false))
	var b5: RID = _body(sp5, [s5.get_rid()], 1)
	var st5: PhysicsDirectSpaceState3D = PhysicsServer3D.space_get_direct_state(sp5)
	print("T5 before drop: ", _ray(st5, Vector3(1, 5, 1), Vector3(1, -5, 1)), " shape_count=", PhysicsServer3D.body_get_shape_count(b5))
	s5 = null
	print("T5 after drop:  ", _ray(st5, Vector3(1, 5, 1), Vector3(1, -5, 1)), " shape_count=", PhysicsServer3D.body_get_shape_count(b5))
	# cleanup (server shapes freed explicitly; bodies before spaces)
	for r: RID in [b_in, b2, bw, bg3, b5]:
		PhysicsServer3D.free_rid(r)
	for r: RID in [fs, fs2]:
		PhysicsServer3D.free_rid(r)
	for r: RID in [sp_inactive, sp2, sp3, sp5]:
		PhysicsServer3D.free_rid(r)
	print("T6 done main; orphan RIDs check via --verbose at exit")

func _free_space_first() -> void:
	var sp: RID = PhysicsServer3D.space_create()
	PhysicsServer3D.space_set_active(sp, true)
	var s := ConcavePolygonShape3D.new(); s.set_faces(_floor_faces(false))
	var b: RID = _body(sp, [s.get_rid()], 1)
	print("FSF: freeing space with body inside")
	PhysicsServer3D.free_rid(sp)
	print("FSF: space freed; body_get_space valid=", PhysicsServer3D.body_get_space(b).is_valid())
	PhysicsServer3D.free_rid(b)
	print("FSF: body freed, no crash")

func _use_after_dispose() -> void:
	var sp: RID = PhysicsServer3D.space_create()
	var s := ConcavePolygonShape3D.new(); s.set_faces(_floor_faces(false))
	var b: RID = _body(sp, [s.get_rid()], 1)
	var st: PhysicsDirectSpaceState3D = PhysicsServer3D.space_get_direct_state(sp)
	PhysicsServer3D.free_rid(b)
	PhysicsServer3D.free_rid(sp)
	print("UAD: is_instance_valid(state)=", is_instance_valid(st))
	print("UAD: ray on stale state: ", _ray(st, Vector3(1, 5, 1), Vector3(1, -5, 1)))
	print("UAD: survived")
