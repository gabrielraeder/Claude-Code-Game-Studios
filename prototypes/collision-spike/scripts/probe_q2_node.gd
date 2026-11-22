## PROTOTYPE - NOT FOR PRODUCTION. Collision spike. Q2: does a node StaticBody3D added mid-frame
## answer queries in the same call (outside _physics_process)? Also: does
## setting enable_ray_cast_face_index at runtime take effect?
extends SceneTree

const SETTING: String = "physics/jolt_physics_3d/queries/enable_ray_cast_face_index"
const HALF: float = 10.0
var _frames: int = 0
var _body: StaticBody3D

func _faces() -> PackedVector3Array:
	return PackedVector3Array([Vector3(-HALF, 0, -HALF), Vector3(HALF, 0, -HALF), Vector3(-HALF, 0, HALF)])

func _ray(tag: String) -> void:
	var q := PhysicsRayQueryParameters3D.create(Vector3(-5, 5, -5), Vector3(-5, -5, -5))
	var d: Dictionary = root.get_world_3d().direct_space_state.intersect_ray(q)
	print("  ", tag, ": ", "MISS" if d.is_empty() else "hit y=%.2f face_index=%d" % [d.position.y, d.face_index])

func _initialize() -> void:
	print("setting at start: ", ProjectSettings.get_setting(SETTING))
	ProjectSettings.set_setting(SETTING, true)
	print("setting after runtime set_setting(true): ", ProjectSettings.get_setting(SETTING))

func _process(_d: float) -> bool:
	_frames += 1
	if _frames == 1:
		print("frame 1 (_process): root inside tree=", root.is_inside_tree(), "  Engine.is_in_physics_frame=", Engine.is_in_physics_frame())
		_body = StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var s := ConcavePolygonShape3D.new()
		s.set_faces(_faces())
		cs.shape = s
		_body.add_child(cs)
		root.add_child(_body)
		print("  body inside tree right after add_child: ", _body.is_inside_tree())
		_ray("same _process call as add_child")
		# blocking loop, many queries, no frames in between
		var hits: int = 0
		for i: int in 1000:
			var q := PhysicsRayQueryParameters3D.create(Vector3(-5, 5, -5), Vector3(-5, -5, -5))
			if not root.get_world_3d().direct_space_state.intersect_ray(q).is_empty():
				hits += 1
		print("  1000 queries in a blocking loop, same call: hits=", hits)
		# move the body and query immediately
		_body.global_position = Vector3(0, 1, 0)
		_ray("after moving the body +1 y, same call")
	if _frames == 2:
		_ray("frame 2")
		return true
	return false
