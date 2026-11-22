@tool
class_name TrackCollisionData
extends Resource
## The collision geometry of one track (ADR-0002 "TrackCollisionData"; core-rebuild story 003), the
## schema ADR-0005 bakes into a binary .res. CollisionQuery.new(data) builds the Jolt-side query
## from it. Never mutated after load (ResourceLoader caches it); a mirrored race uses mirrored()
## (story 006), which returns a new object.
## Plain data: read-only after load, safe to read from any thread.
## [codeblock]
## var data: TrackCollisionData = TrackCollisionData.new()
## # One up-facing ground triangle on surface id 1 (grass). Godot-front winding: the front of
## # (a, b, c) faces along (c - a) x (b - a).
## data.ground_faces = PackedVector3Array([Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)])
## data.surface_of_face = PackedInt32Array([1])
## var query: CollisionQuery = CollisionQuery.new(data)
## # ... race ...
## query.dispose()
## [/codeblock]

## Schema version; bumped on any schema change. Part of ADR-0005's bake_key. A format number, not
## tuning.
const FORMAT_VERSION: int = 1

## Ground triangles: 3 vertices per triangle, Godot-front winding. All in ONE concave shape.
@export var ground_faces: PackedVector3Array = PackedVector3Array()
## Stable surface id (SurfaceType.id) of each ground triangle, in ground_faces order (one entry per
## triangle). Never an array index of the SurfaceSet.
@export var surface_of_face: PackedInt32Array = PackedInt32Array()
## Wall triangles, dense: one entry per wall attribute this track uses; entry k becomes wall shape k.
## Each entry holds 3 vertices per triangle, one-sided, front facing the route.
@export var wall_faces: Array[PackedVector3Array] = []
## Stable wall-attribute id (WallAttr.id) of wall shape k; same length as wall_faces.
@export var wall_attr_ids: PackedInt32Array = PackedInt32Array()
## Moving colliders (evaluated from story 005).
@export var movers: Array[MoverDef] = []
## A known road point for the load check (story 006): cast_ground straight down from here must
## return probe_surface_id with an up normal.
@export var probe_point: Vector3 = Vector3.ZERO
## Surface id the load-check probe must find.
@export var probe_surface_id: int = 0


## Number of ground triangles (ground_faces.size() / 3).
## [codeblock]
## assert(data.surface_of_face.size() == data.ground_triangle_count())
## [/codeblock]
func ground_triangle_count() -> int:
	@warning_ignore("integer_division")
	return ground_faces.size() / 3


## Checks the array layout only (not the surface and wall ids, which the load check tests against
## the registries in story 006). Returns "" when the layout is sound, otherwise one sentence naming
## the first problem: ground_faces not a multiple of 3; surface_of_face not one entry per ground
## triangle; wall_faces and wall_attr_ids of different lengths; a wall entry empty or not a multiple
## of 3 (wall shapes are dense, ADR-0002); a null mover; a mover whose MoverDef.layout_error() is
## not empty (id >= 1, period > 0, extents valid for the shape, equal key arrays, key_t ascending
## within [0, period), finite key positions, unit key rotations, surface_id and wall_attr_id in
## 0..255; story 005); or two movers sharing an id.
## Allocates (a small id set when there are movers): call at load, not per tick. Reads only; safe
## from any thread.
## [codeblock]
## var problem: String = data.layout_error()
## if not problem.is_empty():
##     push_error(problem)
## [/codeblock]
func layout_error() -> String:
	if ground_faces.size() % 3 != 0:
		return "ground_faces has %d vertices, not a multiple of 3" % ground_faces.size()
	if surface_of_face.size() != ground_triangle_count():
		return "surface_of_face has %d entries for %d ground triangles" % [surface_of_face.size(), ground_triangle_count()]
	if wall_faces.size() != wall_attr_ids.size():
		return "wall_faces has %d entries but wall_attr_ids has %d" % [wall_faces.size(), wall_attr_ids.size()]
	for k in wall_faces.size():
		var n: int = wall_faces[k].size()
		if n == 0:
			return "wall_faces[%d] is empty (wall shapes are dense)" % k
		if n % 3 != 0:
			return "wall_faces[%d] has %d vertices, not a multiple of 3" % [k, n]
	return _mover_error()


## The mover part of layout_error(): "" or the first null mover, mover layout problem, or repeated
## mover id.
func _mover_error() -> String:
	var slot_of_id: Dictionary[int, int] = {}
	for k in movers.size():
		var mover: MoverDef = movers[k]
		if mover == null:
			return "movers[%d] is null" % k
		var problem: String = mover.layout_error()
		if not problem.is_empty():
			return "movers[%d]: %s" % [k, problem]
		if slot_of_id.has(mover.id):
			return "movers[%d] has id %d, already used by movers[%d] (mover ids are unique)" % [k, mover.id, slot_of_id[mover.id]]
		slot_of_id[mover.id] = k
	return ""
