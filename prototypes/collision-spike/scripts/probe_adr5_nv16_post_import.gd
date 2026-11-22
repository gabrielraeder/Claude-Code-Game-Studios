## PROTOTYPE - NOT FOR PRODUCTION. ADR-0005 NV-16 probe.
## Used as import_script/path by import_adr45/nv16/fixture.glb.import.
## Inside _post_import: a RefCounted baker makes a private PhysicsServer3D space,
## puts the scene's triangles (global space) in one ConcavePolygonShape3D body and a
## synthetic floor+deck in a second body (two shapes), casts rays with
## intersect_ray_into, checks every hit against a GDScript front-face reference
## ray cast, then frees bodies -> shapes -> space. Appends to res://out/probe_adr5_nv16.txt.
@tool
extends EditorScenePostImport

const OUT_PATH: String = "res://out/probe_adr5_nv16.txt"
const RAY_HALF: float = 5.0
const POS_TOL: float = 0.002
const NORMAL_TOL: float = 0.999
const SYN_Y: float = -50.0
const SYN_HALF: float = 10.0
const DECK_Y: float = -48.0


## Owns every RID it creates; free_all() releases them in order bodies -> shapes -> space.
class Baker extends RefCounted:
	var space: RID
	var shapes: Array[RID] = []
	var bodies: Array[RID] = []
	var notes: PackedStringArray = []

	func make_space() -> void:
		space = PhysicsServer3D.space_create()
		PhysicsServer3D.space_set_active(space, true)

	func make_concave(faces: PackedVector3Array) -> RID:
		var s: RID = PhysicsServer3D.concave_polygon_shape_create()
		PhysicsServer3D.shape_set_data(s, {"faces": faces, "backface_collision": false})
		shapes.append(s)
		return s

	func make_body(shape_list: Array[RID], xforms: Array[Transform3D]) -> RID:
		var b: RID = PhysicsServer3D.body_create()
		PhysicsServer3D.body_set_mode(b, PhysicsServer3D.BODY_MODE_STATIC)
		for i: int in shape_list.size():
			PhysicsServer3D.body_add_shape(b, shape_list[i], xforms[i])
		PhysicsServer3D.body_set_space(b, space)
		bodies.append(b)
		return b

	func state() -> PhysicsDirectSpaceState3D:
		return PhysicsServer3D.space_get_direct_state(space)

	func free_all() -> void:
		for b: RID in bodies:
			PhysicsServer3D.free_rid(b)
		notes.append("freed %d bodies" % bodies.size())
		bodies.clear()
		for s: RID in shapes:
			PhysicsServer3D.free_rid(s)
		notes.append("freed %d shapes" % shapes.size())
		shapes.clear()
		PhysicsServer3D.free_rid(space)
		notes.append("freed space")
		space = RID()


var lines: PackedStringArray = []
var fails: int = 0
var checks: int = 0


func _p(s: String) -> void:
	lines.append(s)
	print("NV16 " + s)


func _global(n: Node3D) -> Transform3D:
	var t: Transform3D = n.transform
	var p: Node = n.get_parent()
	while p != null and p is Node3D:
		t = (p as Node3D).transform * t
		p = p.get_parent()
	return t


func _collect(n: Node, out: PackedVector3Array, owners: PackedStringArray) -> void:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		var mi := n as MeshInstance3D
		var g: Transform3D = _global(mi)
		var mesh: Mesh = mi.mesh
		for si: int in mesh.get_surface_count():
			var arr: Array = mesh.surface_get_arrays(si)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			for t: int in idx.size() / 3:
				out.append_array([g * verts[idx[3 * t]], g * verts[idx[3 * t + 1]], g * verts[idx[3 * t + 2]]])
				owners.append("%s/s%d/t%d" % [mi.name, si, t])
	for ch: Node in n.get_children():
		_collect(ch, out, owners)


## Godot front normal (matches Plane(a, b, c)): (c - a) x (b - a).
func _front(a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	return (c - a).cross(b - a).normalized()


## Reference: nearest front-facing triangle hit by segment from->to. Returns [face, pos, normal] or [].
func _ref_cast(faces: PackedVector3Array, from: Vector3, to: Vector3) -> Array:
	var dir: Vector3 = to - from
	var best_t: float = INF
	var best: Array = []
	for f: int in faces.size() / 3:
		var a: Vector3 = faces[3 * f]
		var b: Vector3 = faces[3 * f + 1]
		var c: Vector3 = faces[3 * f + 2]
		var n: Vector3 = _front(a, b, c)
		if n.dot(dir) >= 0.0:
			continue
		var hit: Variant = Geometry3D.segment_intersects_triangle(from, to, a, b, c)
		if hit == null:
			continue
		var t: float = from.distance_to(hit as Vector3)
		if t < best_t:
			best_t = t
			best = [f, hit as Vector3, n]
	return best


func _check(st: PhysicsDirectSpaceState3D, label: String, faces: PackedVector3Array, from: Vector3, to: Vector3, body: RID, expect_shape: int, res: PhysicsIntersectRayResult3D, q: PhysicsRayQueryParameters3D) -> void:
	q.from = from
	q.to = to
	var ok: bool = st.intersect_ray_into(q, res)
	var ref: Array = _ref_cast(faces, from, to)
	checks += 1
	var verdict: String
	if ref.is_empty():
		verdict = "OK" if not ok else "FAIL(unexpected hit)"
	elif not ok:
		verdict = "FAIL(miss)"
	else:
		var good: bool = res.collider_face_index == int(ref[0]) and res.position.distance_to(ref[1] as Vector3) <= POS_TOL and res.normal.dot(ref[2] as Vector3) >= NORMAL_TOL and res.collider_shape == expect_shape
		var rid_v: Variant = res.get("collider_rid")
		if rid_v is RID:
			good = good and (rid_v as RID) == body
		verdict = "OK" if good else "FAIL"
	if verdict != "OK":
		fails += 1
	var got: String = "MISS" if not ok else "face=%d shape=%d pos=%s n=%s rid_match=%s" % [res.collider_face_index, res.collider_shape, res.position, res.normal.snappedf(0.0001), (res.get("collider_rid") == body) if res.get("collider_rid") is RID else "n/a"]
	var want: String = "MISS" if ref.is_empty() else "face=%d shape=%d pos=%s n=%s" % [ref[0], expect_shape, ref[1], (ref[2] as Vector3).snappedf(0.0001)]
	_p("  %s %s | got %s | expect %s" % [verdict, label, got, want])


func _post_import(scene: Node) -> Object:
	var src: String = get_source_file()
	_p("=== run %s source=%s engine=%s editor_hint=%s main_thread=%s" % [Time.get_datetime_string_from_system(), src, Engine.get_version_info().string, Engine.is_editor_hint(), OS.get_thread_caller_id() == OS.get_main_thread_id()])
	_p("setting physics/3d/physics_engine=%s enable_ray_cast_face_index=%s server_class=%s" % [ProjectSettings.get_setting("physics/3d/physics_engine"), ProjectSettings.get_setting("physics/jolt_physics_3d/queries/enable_ray_cast_face_index"), PhysicsServer3D.get_class()])
	var props: PackedStringArray = []
	for pd: Dictionary in ClassDB.class_get_property_list("PhysicsIntersectRayResult3D", true):
		props.append(String(pd["name"]))
	_p("PhysicsIntersectRayResult3D props=%s" % [props])

	var mesh_faces := PackedVector3Array()
	var owners := PackedStringArray()
	_collect(scene, mesh_faces, owners)
	var h: float = SYN_HALF
	var floor_faces := PackedVector3Array([Vector3(-h, 0, -h), Vector3(h, 0, -h), Vector3(-h, 0, h), Vector3(h, 0, -h), Vector3(-h, 0, h), Vector3(h, 0, h)])
	var deck_faces := PackedVector3Array([Vector3(-1, 0, -1), Vector3(1, 0, -1), Vector3(-1, 0, 1)])
	_p("mesh triangles=%d (from %d owners), synthetic floor=2 deck=1" % [mesh_faces.size() / 3, owners.size()])

	var baker := Baker.new()
	baker.make_space()
	var s_mesh: RID = baker.make_concave(mesh_faces)
	var s_floor: RID = baker.make_concave(floor_faces)
	var s_deck: RID = baker.make_concave(deck_faces)
	var b_mesh: RID = baker.make_body([s_mesh] as Array[RID], [Transform3D.IDENTITY] as Array[Transform3D])
	var floor_x := Transform3D(Basis.IDENTITY, Vector3(0, SYN_Y, 0))
	var deck_x := Transform3D(Basis.IDENTITY, Vector3(3, DECK_Y, -4))
	var b_syn: RID = baker.make_body([s_floor, s_deck] as Array[RID], [floor_x, deck_x] as Array[Transform3D])
	_p("rids space=%s shapes=%s bodies=%s" % [baker.space, baker.shapes, baker.bodies])
	var st: PhysicsDirectSpaceState3D = baker.state()
	_p("direct state null=%s" % (st == null))
	if st != null:
		var res := PhysicsIntersectRayResult3D.new()
		var q := PhysicsRayQueryParameters3D.new()
		_p("query defaults hit_back_faces=%s hit_from_inside=%s" % [q.hit_back_faces, q.hit_from_inside])
		# Mesh body: through every centroid, along -front (should hit) and along +front (back face: one-sided, must miss it).
		for f: int in mesh_faces.size() / 3:
			var a: Vector3 = mesh_faces[3 * f]
			var b: Vector3 = mesh_faces[3 * f + 1]
			var c: Vector3 = mesh_faces[3 * f + 2]
			var ctr: Vector3 = (a + b + c) / 3.0
			var n: Vector3 = _front(a, b, c)
			_check(st, "mesh f%d %s front" % [f, owners[f]], mesh_faces, ctr + n * RAY_HALF, ctr - n * RAY_HALF, b_mesh, 0, res, q)
			_check(st, "mesh f%d %s back" % [f, owners[f]], mesh_faces, ctr - n * RAY_HALF, ctr + n * RAY_HALF, b_mesh, 0, res, q)
		# Synthetic body: shape 0 floor faces 0/1, shape 1 deck face 0 above the floor.
		var world_floor := PackedVector3Array()
		for v: Vector3 in floor_faces:
			world_floor.append(floor_x * v)
		var world_deck := PackedVector3Array()
		for v: Vector3 in deck_faces:
			world_deck.append(deck_x * v)
		_check(st, "syn floor f0", world_floor, Vector3(-5, SYN_Y + 5, -5), Vector3(-5, SYN_Y - 5, -5), b_syn, 0, res, q)
		_check(st, "syn floor f1", world_floor, Vector3(5, SYN_Y + 5, 5), Vector3(5, SYN_Y - 5, 5), b_syn, 0, res, q)
		_check(st, "syn deck f0", world_deck, Vector3(2.5, SYN_Y + 5, -4.5), Vector3(2.5, SYN_Y - 5, -4.5), b_syn, 1, res, q)
		_check(st, "syn miss", PackedVector3Array(), Vector3(500, SYN_Y + 5, 500), Vector3(500, SYN_Y - 5, 500), b_syn, 0, res, q)
	baker.free_all()
	for l: String in baker.notes:
		_p(l)
	baker = null
	_p("RESULT checks=%d fails=%d" % [checks, fails])
	scene.set_meta("nv16_checks", checks)
	scene.set_meta("nv16_fails", fails)
	var fo := FileAccess.open(OUT_PATH, FileAccess.READ_WRITE) if FileAccess.file_exists(OUT_PATH) else FileAccess.open(OUT_PATH, FileAccess.WRITE)
	fo.seek_end()
	fo.store_string("\n".join(lines) + "\n")
	fo.close()
	return scene
