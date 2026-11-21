class_name MaterialPrewarm
extends Node3D
## Draws one tiny copy of every distinct mesh-and-material pair of the race world in front of the
## camera for a few frames while the race is loading and counting down, so the renderer compiles
## each shader pipeline (lava, water, pads, ramps, deck sides, scenery variants) before the race
## and a first sight never compiles one mid-race (story 008 part 4: a 248 ms first-sight hitch).
## Presentation only; it frees itself.
## Implements design/game-brief.md, Technical (60 fps with 12 racers).

## Frames the copies stay visible: the first draws them, the rest cover pipelines compiled a frame late.
const FRAMES: int = 4
## Distance (meters) in front of the camera and scale of each copy: inside the view, a few pixels.
const AHEAD: float = 1.5
const SCALE: float = 0.002

var _left: int = FRAMES


## Adds a prewarm under [param camera] with copies of every distinct geometry found under
## [param root]. Returns the node (already in the tree), or null when nothing was found.
static func warm(root: Node, camera: Camera3D) -> MaterialPrewarm:
	if root == null or camera == null:
		return null
	var seen: Dictionary = {}
	var node := MaterialPrewarm.new()
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		var copy: GeometryInstance3D = _copy_of(n, seen)
		if copy != null:
			copy.position = Vector3(0.0, 0.0, -AHEAD)
			copy.scale = Vector3.ONE * SCALE
			node.add_child(copy)
	if node.get_child_count() == 0:
		node.free()
		return null
	camera.add_child(node)
	print("[prewarm] %d mesh/material pairs drawn for %d frames" % [node.get_child_count(), FRAMES])
	return node


# A copy of [param n] when it is a mesh or multimesh instance whose (mesh, material) pair was not
# seen yet; null otherwise. The copy shares the mesh (same vertex format, same pipeline).
static func _copy_of(n: Node, seen: Dictionary) -> GeometryInstance3D:
	if n is MeshInstance3D:
		var mi: MeshInstance3D = n
		if mi.mesh == null:
			return null
		var key: String = "m%d/%d" % [mi.mesh.get_instance_id(), mi.material_override.get_instance_id() if mi.material_override != null else 0]
		if seen.has(key):
			return null
		seen[key] = true
		var c := MeshInstance3D.new()
		c.mesh = mi.mesh
		c.material_override = mi.material_override
		c.cast_shadow = mi.cast_shadow
		return c
	if n is MultiMeshInstance3D:
		var mmi: MultiMeshInstance3D = n
		if mmi.multimesh == null or mmi.multimesh.mesh == null:
			return null
		var mm: MultiMesh = mmi.multimesh
		var key2: String = "mm%d/%d/%s" % [mm.mesh.get_instance_id(), mmi.material_override.get_instance_id() if mmi.material_override != null else 0, str(mm.use_colors)]
		if seen.has(key2):
			return null
		seen[key2] = true
		var one := MultiMesh.new()
		one.transform_format = mm.transform_format
		one.use_colors = mm.use_colors
		one.use_custom_data = mm.use_custom_data
		one.mesh = mm.mesh
		one.instance_count = 1
		one.set_instance_transform(0, Transform3D.IDENTITY)
		if mm.use_colors:
			one.set_instance_color(0, Color.WHITE)
		var c2 := MultiMeshInstance3D.new()
		c2.multimesh = one
		c2.material_override = mmi.material_override
		c2.cast_shadow = mmi.cast_shadow
		return c2
	return null


func _process(_delta: float) -> void:
	_left -= 1
	if _left <= 0:
		queue_free()
