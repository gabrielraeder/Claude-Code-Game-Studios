class_name ModelBatcher
extends RefCounted
## Cuts the draw calls of a kart model without changing its look (story 006 performance pass).
## An imported glb mesh has one surface (one draw call) per material. [method batch] rebuilds
## each mesh so all its flat-coloured surfaces become ONE surface that carries its colours as
## vertex colours under one shared material, while the surfaces whose material is named in
## [param keep] (the identity-colour "paint" / "tabard" panels) stay separate so each kart can
## still override them. The imported resources are never changed; converted meshes are cached,
## so a model is converted once per run however many karts use it. Node names, transforms and
## animation (wheels, head, ears) are untouched.
## Implements the art bible section 8 budget (each racer <= 4 materials, <= 2000 draw calls).

## Roughness of the shared material when a source material gives none.
const DEFAULT_ROUGHNESS: float = 0.8

static var _converted: Dictionary = {}
static var _shared: StandardMaterial3D


## One material for every flat-coloured part: colours come from vertex colours.
static func shared_material() -> StandardMaterial3D:
	if _shared == null:
		_shared = StandardMaterial3D.new()
		_shared.vertex_color_use_as_albedo = true
		_shared.vertex_color_is_srgb = true
		_shared.roughness = DEFAULT_ROUGHNESS
		_shared.metallic = 0.0
	return _shared


## Replaces the mesh of every MeshInstance3D under [param root] by its batched version.
## [param keep] lists material names that must stay separate surfaces.
static func batch(root: Node, keep: PackedStringArray) -> void:
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = n as MeshInstance3D
		if mi.mesh != null:
			mi.mesh = batched_mesh(mi.mesh, keep)


## The batched copy of [param mesh] (cached).
static func batched_mesh(mesh: Mesh, keep: PackedStringArray) -> Mesh:
	if _converted.has(mesh):
		return _converted[mesh]
	var flat: Dictionary = new_flat()
	var kept: Array[Dictionary] = []
	for i in mesh.get_surface_count():
		var mat: Material = mesh.surface_get_material(i)
		var arrays: Array = mesh.surface_get_arrays(i)
		var is_tri: bool = mesh.surface_get_primitive_type(i) == Mesh.PRIMITIVE_TRIANGLES
		if not is_tri or (mat != null and keep.has(mat.resource_name)):
			kept.append({"arrays": arrays, "mat": mat, "type": mesh.surface_get_primitive_type(i)})
			continue
		var color: Color = Color.WHITE
		if mat is BaseMaterial3D:
			color = (mat as BaseMaterial3D).albedo_color
		append_flat(flat, arrays, color, Vector3.ZERO)
	var out: ArrayMesh = flat_to_mesh(flat)
	if out == null:
		out = ArrayMesh.new()
	for k in kept:
		out.add_surface_from_arrays(k.type, k.arrays)
		out.surface_set_material(out.get_surface_count() - 1, k.mat)
	out.resource_name = mesh.resource_name
	_converted[mesh] = out
	return out


## An empty accumulator for [method append_flat].
static func new_flat() -> Dictionary:
	return {"v": PackedVector3Array(), "n": PackedVector3Array(), "c": PackedColorArray(), "i": PackedInt32Array()}


## Appends a triangle surface ([param arrays] as from Mesh.surface_get_arrays or
## PrimitiveMesh.get_mesh_arrays) moved by [param offset], all in [param color].
static func append_flat(flat: Dictionary, arrays: Array, color: Color, offset: Vector3) -> void:
	# Packed arrays are values: copy out, append, store back.
	var all_v: PackedVector3Array = flat.v
	var all_n: PackedVector3Array = flat.n
	var all_c: PackedColorArray = flat.c
	var all_i: PackedInt32Array = flat.i
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var count: int = verts.size()
	var base: int = all_v.size()
	for j in count:
		all_v.append(verts[j] + offset)
	var normals: Variant = arrays[Mesh.ARRAY_NORMAL]
	var has_normals: bool = normals is PackedVector3Array and (normals as PackedVector3Array).size() == count
	for j in count:
		all_n.append((normals as PackedVector3Array)[j] if has_normals else Vector3.UP)
		all_c.append(color)
	var index: Variant = arrays[Mesh.ARRAY_INDEX]
	if index is PackedInt32Array and (index as PackedInt32Array).size() > 0:
		for idx: int in (index as PackedInt32Array):
			all_i.append(base + idx)
	else:
		for j in count:
			all_i.append(base + j)
	flat.v = all_v
	flat.n = all_n
	flat.c = all_c
	flat.i = all_i


## Turns an accumulator into a mesh with the shared material, or null when it is empty.
static func flat_to_mesh(flat: Dictionary) -> ArrayMesh:
	if (flat.v as PackedVector3Array).is_empty():
		return null
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = flat.v
	arrays[Mesh.ARRAY_NORMAL] = flat.n
	arrays[Mesh.ARRAY_COLOR] = flat.c
	arrays[Mesh.ARRAY_INDEX] = flat.i
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, shared_material())
	return mesh
