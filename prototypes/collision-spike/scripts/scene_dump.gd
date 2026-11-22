## PROTOTYPE - NOT FOR PRODUCTION. Collision spike. Q4: dumps an imported glTF scene (names,
## transforms, metadata, materials, winding) and ray-casts its collision faces.
extends RefCounted

static func _meta_str(o: Object) -> String:
	var parts: PackedStringArray = []
	for k: StringName in o.get_meta_list():
		parts.append("%s=%s" % [k, str(o.get_meta(k))])
	return "{" + ", ".join(parts) + "}"

static func dump(root: Node, lines: PackedStringArray) -> void:
	_walk(root, root, lines)

static func _walk(root: Node, n: Node, lines: PackedStringArray) -> void:
	var line: String = "NODE %s (%s) meta=%s" % [root.get_path_to(n), n.get_class(), _meta_str(n)]
	if n is Node3D:
		var g: Transform3D = (n as Node3D).global_transform if n.is_inside_tree() else _global(n as Node3D)
		line += " origin=%s forward(-Z)=%s scale=%s" % [g.origin, (g.basis * Vector3(0, 0, -1)).snappedf(0.001), g.basis.get_scale().snappedf(0.001)]
	lines.append(line)
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		var mesh: Mesh = mi.mesh
		lines.append("  mesh resource_name=%s meta=%s surfaces=%d" % [mesh.resource_name, _meta_str(mesh), mesh.get_surface_count()])
		var g: Transform3D = _global(mi)
		for si: int in mesh.get_surface_count():
			var mat: Material = mesh.surface_get_material(si)
			var arr: Array = mesh.surface_get_arrays(si)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			var n_front := Vector3.ZERO
			if idx.size() >= 3:
				var a: Vector3 = g * verts[idx[0]]
				var b: Vector3 = g * verts[idx[1]]
				var c: Vector3 = g * verts[idx[2]]
				n_front = (c - a).cross(b - a).normalized()
			var stored_n: Vector3 = (arr[Mesh.ARRAY_NORMAL] as PackedVector3Array)[idx[0]] if idx.size() > 0 else Vector3.ZERO
			lines.append("  surface %d material=%s (meta=%s, cull=%s) tris=%d godot_front_normal(tri0)=%s stored_vertex_normal=%s" % [si, mat.resource_name if mat else "<none>", _meta_str(mat) if mat else "-", str((mat as BaseMaterial3D).cull_mode) if mat is BaseMaterial3D else "-", idx.size() / 3, n_front.snappedf(0.01), (g.basis * stored_n).normalized().snappedf(0.01)])
			if mesh.resource_name.begins_with("marker") or mi.name.begins_with("Marker"):
				# vertex order is not preserved by export/import, so identify by geometry:
				# tip = the vertex 2 m from the local origin, fin = the vertex 1 m above the plane
				var tip := Vector3.ZERO
				var fin := Vector3.ZERO
				for v: Vector3 in verts:
					if absf(v.length() - 2.0) < 0.01:
						tip = v
					if absf(v.y - 1.0) < 0.01:
						fin = v
				lines.append("  marker tip (Blender local (0,2,0)): godot local=%s world=%s | fin (Blender local (0.5,0,1)): godot local=%s world=%s" % [tip, g * tip, fin, g * fin])
	for c: Node in n.get_children():
		_walk(root, c, lines)

static func _global(n: Node3D) -> Transform3D:
	var t: Transform3D = n.transform
	var p: Node = n.get_parent()
	while p != null and p is Node3D:
		t = (p as Node3D).transform * t
		p = p.get_parent()
	return t

## Builds a ConcavePolygonShape3D from the "track_piece" mesh (Mesh.get_faces) in a
## private space and casts rays down on the road, grass and ramp.
static func ray_test(root: Node, lines: PackedStringArray) -> void:
	var mi: MeshInstance3D = root.find_child("track_piece", true, false) as MeshInstance3D
	if mi == null:
		lines.append("RAY no track_piece MeshInstance3D found")
		return
	var faces: PackedVector3Array = mi.mesh.get_faces()
	var g: Transform3D = _global(mi)
	for i: int in faces.size():
		faces[i] = g * faces[i]
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	var sp: RID = PhysicsServer3D.space_create()
	PhysicsServer3D.space_set_active(sp, true)
	var b: RID = PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(b, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_add_shape(b, shape.get_rid())
	PhysicsServer3D.body_set_space(b, sp)
	var st: PhysicsDirectSpaceState3D = PhysicsServer3D.space_get_direct_state(sp)
	# Godot coordinates: road centre at Blender (0, 20) -> (0, -20); grass Blender x=-9.5; ramp Blender y=35 -> z=-35
	for p: Array in [["road", Vector3(0, 5, -20)], ["grass", Vector3(-9.5, 5, -20)], ["ramp", Vector3(0, 5, -35)]]:
		var q := PhysicsRayQueryParameters3D.create(p[1], p[1] + Vector3(0, -10, 0))
		q.hit_back_faces = false
		var d: Dictionary = st.intersect_ray(q)
		lines.append("RAY down on %s at %s -> %s" % [p[0], p[1], "MISS" if d.is_empty() else "y=%.3f n=%s face=%d" % [d.position.y, d.normal.snappedf(0.001), d.face_index]])
	for p: Array in [["left wall (Godot x=-12) from inside", Vector3(-10, 0.7, -20), Vector3(-14, 0.7, -20)], ["right wall (Godot x=7) from inside", Vector3(5, 0.7, -20), Vector3(9, 0.7, -20)]]:
		var q := PhysicsRayQueryParameters3D.create(p[1], p[2])
		q.hit_back_faces = false
		var d: Dictionary = st.intersect_ray(q)
		lines.append("RAY %s -> %s" % [p[0], "MISS" if d.is_empty() else "x=%.3f n=%s" % [d.position.x, d.normal.snappedf(0.001)]])
	PhysicsServer3D.free_rid(b)
	PhysicsServer3D.free_rid(sp)
