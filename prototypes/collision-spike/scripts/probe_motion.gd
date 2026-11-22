## PROTOTYPE - NOT FOR PRODUCTION. Collision spike. cast_motion(_into) semantics vs a one-sided wall.
## Wall: vertical quad in plane x = 0, front normal +X (faces the sphere at x > 0).
extends SceneTree

const R: float = 0.6

func _wall_faces(front_pos_x: bool) -> PackedVector3Array:
	var a := Vector3(0, 0, -10)
	var b := Vector3(0, 3, -10)
	var c := Vector3(0, 0, 10)
	var d := Vector3(0, 3, 10)
	var f := PackedVector3Array()
	# want normal (c-a)x(b-a) = +X for the front-facing version
	for tri: Array in [[a, b, c], [c, b, d]]:
		var n: Vector3 = (tri[2] - tri[0]).cross(tri[1] - tri[0])
		if (n.x > 0.0) == front_pos_x:
			f.append_array([tri[0], tri[1], tri[2]])
		else:
			f.append_array([tri[0], tri[2], tri[1]])
	return f

func _case(st: PhysicsDirectSpaceState3D, label: String, from: Vector3, motion: Vector3) -> void:
	var q := PhysicsShapeQueryParameters3D.new()
	var sph := SphereShape3D.new()
	sph.radius = R
	q.shape = sph
	q.transform = Transform3D(Basis.IDENTITY, from)
	q.motion = motion
	var arr: PackedFloat32Array = st.cast_motion(q)
	var res := PhysicsCastMotionResult3D.new()
	var ok: bool = st.cast_motion_into(q, res)
	var q2 := PhysicsShapeQueryParameters3D.new()
	q2.shape = sph
	q2.transform = Transform3D(Basis.IDENTITY, from)
	var rest: Dictionary = st.get_rest_info(q2)
	var col: Array = st.collide_shape(q2, 4)
	print("  %-38s cast_motion=%s  into: ret=%s safe=%.3f unsafe=%.3f | rest@from=%s | collide_shape@from n=%d" % [label, arr, ok, res.safe_fraction, res.unsafe_fraction, "none" if rest.is_empty() else "n=%s p=%s" % [rest.normal, rest.point], col.size() / 2])

func _initialize() -> void:
	for front: bool in [true, false]:
		var sp: RID = PhysicsServer3D.space_create()
		PhysicsServer3D.space_set_active(sp, true)
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(_wall_faces(front))
		var b: RID = PhysicsServer3D.body_create()
		PhysicsServer3D.body_set_mode(b, PhysicsServer3D.BODY_MODE_STATIC)
		PhysicsServer3D.body_add_shape(b, shape.get_rid())
		PhysicsServer3D.body_set_space(b, sp)
		var st: PhysicsDirectSpaceState3D = PhysicsServer3D.space_get_direct_state(sp)
		print("wall front normal ", "+X (faces sphere)" if front else "-X (sphere sees back face)")
		_case(st, "far, moving toward (2.0 -> 0.5)", Vector3(2.0, 1, 0), Vector3(-1.5, 0, 0))
		_case(st, "far, moving away", Vector3(2.0, 1, 0), Vector3(1.0, 0, 0))
		_case(st, "far, no contact (2.0 -> 1.0)", Vector3(2.0, 1, 0), Vector3(-1.0, 0, 0))
		_case(st, "overlap 0.3, moving parallel", Vector3(0.3, 1, 0), Vector3(0, 0, 0.5))
		_case(st, "overlap 0.3, moving toward", Vector3(0.3, 1, 0), Vector3(-0.2, 0, 0.5))
		_case(st, "overlap 0.3, moving away", Vector3(0.3, 1, 0), Vector3(0.2, 0, 0.5))
		_case(st, "zero motion, overlap 0.3", Vector3(0.3, 1, 0), Vector3.ZERO)
		_case(st, "zero motion, no overlap", Vector3(2.0, 1, 0), Vector3.ZERO)
		PhysicsServer3D.free_rid(b)
		PhysicsServer3D.free_rid(sp)
	quit()
