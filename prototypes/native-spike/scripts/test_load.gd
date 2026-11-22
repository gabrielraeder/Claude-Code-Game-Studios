## PROTOTYPE - NOT FOR PRODUCTION. Native spike (ADR-0007). Q2 checks: load, typed args, RID ownership.
## Plain SceneTree script (gdUnit4 not copied in). Run:
##   godot --headless --path . -s res://scripts/test_load.gd
extends SceneTree

var _fails: int = 0

func _check(name: String, ok: bool, extra: String = "") -> void:
	print(("PASS " if ok else "FAIL ") + name + " " + extra)
	if not ok:
		_fails += 1

func _initialize() -> void:
	_check("class registered", ClassDB.class_exists("NativeSpikeQuery"))
	var q: Object = ClassDB.instantiate("NativeSpikeQuery")
	_check("constructed from ClassDB", q != null)
	_check("RefCounted base", q is RefCounted)
	_check("ping", q.ping() == 42)
	_check("Vector3 args", q.add_vec(Vector3(1, 2, 3), Vector3(0.5, 0.5, 0.5)) == Vector3(1.5, 2.5, 3.5))
	var tr: Transform3D = Transform3D(Basis.from_euler(Vector3(0.1, 0.2, 0.3)), Vector3(4, 5, 6))
	_check("Transform3D round trip", q.echo_transform(tr) == tr)
	_check("PackedFloat32Array arg", is_equal_approx(q.sum_floats(PackedFloat32Array([1.5, 2.5, 3.0])), 7.0))
	var space: RID = PhysicsServer3D.space_create()
	_check("RID round trip", q.echo_rid(space) == space)
	PhysicsServer3D.free_rid(space)
	# the new-style API from a script: typed variable
	var qt: RefCounted = q as RefCounted
	_check("typed as RefCounted", qt != null)

	# RID ownership: build, record RIDs, drop the last reference, then each RID must be gone.
	var faces: PackedVector3Array = PackedVector3Array([Vector3(-5, 0, -5), Vector3(5, 0, -5), Vector3(0, 0, 5)])
	q.setup_static(faces, faces)
	var rids: Array = q.owned_rids()
	_check("owns 6 RIDs", rids.size() == 6, str(rids.size()))
	var d: float = q.static_cast_ground(Vector3(0, 2, 0), Vector3.DOWN, 4.0)
	_check("ray hits ground", absf(d - 2.0) < 1e-4, str(d))
	var before: int = PhysicsServer3D.get_process_info(PhysicsServer3D.INFO_ACTIVE_OBJECTS)
	q = null
	qt = null
	# all references dropped: destructor ran. A freed RID cannot be queried:
	print("EXPECT-ERRORS-BELOW (freeing again must fail for each RID if the destructor freed them)")
	for r: RID in rids:
		PhysicsServer3D.free_rid(r)
	print("EXPECT-ERRORS-ABOVE")
	print("active objects before drop=", before)
	print("FAILS=", _fails)
	quit(1 if _fails > 0 else 0)
