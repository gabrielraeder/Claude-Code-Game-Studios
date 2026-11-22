@tool
class_name TrackCollisionData
extends Resource
## The collision geometry of one track (ADR-0002 "TrackCollisionData"; core-rebuild story 003), the
## schema ADR-0005 bakes into a binary .res. CollisionQuery.create(data.pack_native()) builds the Jolt-side query
## from it. Never mutated after load (ResourceLoader caches it); a mirrored race uses mirrored()
## (story 006), which returns a new object. At load the composition root also runs
## CollisionBootCheck.load_error() (layout, ids against the core registries, probe cast).
## Plain data: read-only after load, safe to read from any thread.
## [codeblock]
## var data: TrackCollisionData = TrackCollisionData.new()
## # One up-facing ground triangle on surface id 1 (grass). Godot-front winding: the front of
## # (a, b, c) faces along (c - a) x (b - a).
## data.ground_faces = PackedVector3Array([Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)])
## data.surface_of_face = PackedInt32Array([1])
## var query: CollisionQuery = CollisionQuery.create(data.pack_native())
## # ... race ...
## query.dispose()
## [/codeblock]

## Schema version; bumped on any schema change. Part of ADR-0005's bake_key. A format number, not
## tuning.
const FORMAT_VERSION: int = 1

## Schema version of pack_native(); the native CollisionQuery asserts the same number
## (CollisionQuery.PACKED_SCHEMA_VERSION). A format number, not tuning.
const NATIVE_SCHEMA_VERSION: int = 1

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
## A known road point for the load check (story 006): cast_ground straight down from here at
## t = 0 (CollisionQuery.PROBE_T), within the caller's max drop, must return probe_surface_id with
## normal.y > 0 from the static ground. Authoring rule: no solid mover stands over this point at
## t = 0. Mirrored with the track.
@export var probe_point: Vector3 = Vector3.ZERO
## Surface id the load-check probe must find.
@export var probe_surface_id: int = 0


## The plain data the native CollisionQuery consumes (ADR-0007 section 2): CollisionQuery.create(packed)
## and CollisionQuery.validate_packed(packed) take it. A Dictionary of fixed keys, in this order:
## schema_version (int), ground_faces (PackedVector3Array, m, 3 per triangle), surface_of_face
## (PackedInt32Array, one surface id per triangle), wall_faces (Array of PackedVector3Array, one per wall
## shape), wall_attr_ids (PackedInt32Array, one per wall shape) and movers (Array of MoverDef.pack_native()
## Dictionaries, in data order; a null mover packs as null, which validation refuses). The probe fields
## are not packed: the probe is a GDScript argument of CollisionQuery.probe_error. The arrays are shared
## copy-on-write, not copied. Load time only.
## [codeblock]
## var packed: Dictionary = data.pack_native()
## var problem: String = CollisionQuery.validate_packed(packed)
## [/codeblock]
func pack_native() -> Dictionary:
	var walls: Array = []
	for faces in wall_faces:
		walls.append(faces)
	var packed_movers: Array = []
	for mover in movers:
		packed_movers.append(mover.pack_native() if mover != null else null)
	return {
		"schema_version": NATIVE_SCHEMA_VERSION,
		"ground_faces": ground_faces,
		"surface_of_face": surface_of_face,
		"wall_faces": walls,
		"wall_attr_ids": wall_attr_ids,
		"movers": packed_movers,
	}


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


## Checks every stable id against the core registries (ADR-0002 "Load check (ids)"; story 006;
## the story 003 LP review: blocking, so a face with SURFACE_NONE never reaches Driving). Returns ""
## when every id is known, otherwise one sentence naming the first problem: [param surfaces] or
## [param walls] null; an id of surface_of_face that is not a SurfaceType.id of [param surfaces]
## (SURFACE_NONE = -1 included); an id of wall_attr_ids that is not a WallAttr.id of [param walls],
## or one used by two wall shapes (wall shapes are dense, one per attribute); a mover's surface_id
## or wall_attr_id not in its registry; probe_surface_id not in [param surfaces]. Null movers are
## left to layout_error(). The registries are expected to come from load_checked() (their own ids
## unique and within 0..255); an entry with an id outside 0..255 is ignored.
## Allocates two 256-entry tables: call at load, not per tick. Reads only; safe from any thread.
## [codeblock]
## var surfaces: SurfaceSet = SurfaceSet.load_checked(SurfaceSet.CORE_PATH)
## var walls: WallAttrSet = WallAttrSet.load_checked(WallAttrSet.CORE_PATH)
## var problem: String = data.id_error(surfaces, walls)
## assert(problem.is_empty(), problem)  # the composition root refuses the track
## [/codeblock]
func id_error(surfaces: SurfaceSet, walls: WallAttrSet) -> String:
	if surfaces == null:
		return "no SurfaceSet to check the surface ids against"
	if walls == null:
		return "no WallAttrSet to check the wall-attribute ids against"
	var surface_known: PackedByteArray = TrackCollisionData._surface_table(surfaces)
	var wall_known: PackedByteArray = TrackCollisionData._wall_table(walls)
	var problem: String = _surface_id_error(surface_known)
	if problem.is_empty():
		problem = _wall_id_error(wall_known)
	if problem.is_empty():
		problem = _mover_id_error(surface_known, wall_known)
	if problem.is_empty() and not TrackCollisionData._known(surface_known, probe_surface_id):
		problem = "probe_surface_id is %d, not a surface id of the SurfaceSet" % probe_surface_id
	return problem


## The surface_of_face part of id_error(): "" or the first face whose id [param surface_known]
## does not flag.
func _surface_id_error(surface_known: PackedByteArray) -> String:
	for f in surface_of_face.size():
		if not TrackCollisionData._known(surface_known, surface_of_face[f]):
			return "surface_of_face[%d] is %d, not a surface id of the SurfaceSet" % [f, surface_of_face[f]]
	return ""


## The wall_attr_ids part of id_error(): "" or the first wall shape whose id [param wall_known]
## does not flag, or whose id an earlier wall shape already uses.
func _wall_id_error(wall_known: PackedByteArray) -> String:
	var wall_used: PackedByteArray = PackedByteArray()
	wall_used.resize(WallAttrSet.MAX_ID + 1)
	wall_used.fill(0)
	for k in wall_attr_ids.size():
		var wall_id: int = wall_attr_ids[k]
		if not TrackCollisionData._known(wall_known, wall_id):
			return "wall_attr_ids[%d] is %d, not a wall-attribute id of the WallAttrSet" % [k, wall_id]
		if wall_used[wall_id] != 0:
			return "wall_attr_ids[%d] repeats wall-attribute id %d (one wall shape per attribute)" % [k, wall_id]
		wall_used[wall_id] = 1
	return ""


## The mover part of id_error(): "" or the first non-null mover whose surface_id
## [param surface_known] or wall_attr_id [param wall_known] does not flag.
func _mover_id_error(surface_known: PackedByteArray, wall_known: PackedByteArray) -> String:
	for k in movers.size():
		var mover: MoverDef = movers[k]
		if mover == null:
			continue
		if not TrackCollisionData._known(surface_known, mover.surface_id):
			return "movers[%d] (id %d) has surface_id %d, not a surface id of the SurfaceSet" % [k, mover.id, mover.surface_id]
		if not TrackCollisionData._known(wall_known, mover.wall_attr_id):
			return "movers[%d] (id %d) has wall_attr_id %d, not a wall-attribute id of the WallAttrSet" % [k, mover.id, mover.wall_attr_id]
	return ""


## A NEW TrackCollisionData: this track reflected through the plane x = 0 (ADR-0001 section 7,
## ADR-0002 "Mirror"; story 006). Every vertex x -> -x and every triangle's winding flipped (b and c
## swapped), so each face keeps its Godot front (a reflection alone turns every ground face away
## from the downward rays: prototypes/collision-spike/out/q5_mirror.txt); surface_of_face and
## wall_attr_ids copied in face order; movers mirrored by MoverDef.mirrored() (new sub-resources:
## duplicate(false) would share them with the cached source); probe_point x -> -x; probe_surface_id
## copied. Collision carries no left/right labels, so nothing else swaps. Never mutates this object
## (ResourceLoader caches it, and the next non-mirrored race reads it). A trailing partial triangle
## (bad layout) is mirrored vertex by vertex and left for layout_error() to reject.
## Called once at track load (story 040: TrackLoader), never per query. Allocates; reads only, safe
## from any thread.
## [codeblock]
## var data: TrackCollisionData = load(collision_path) as TrackCollisionData
## if race_config.mirror:
##     data = data.mirrored()  # the cached resource stays as it was
## var query: CollisionQuery = CollisionQuery.create(data.pack_native())
## [/codeblock]
func mirrored() -> TrackCollisionData:
	var out: TrackCollisionData = TrackCollisionData.new()
	out.ground_faces = TrackCollisionData._mirror_faces(ground_faces)
	out.surface_of_face = surface_of_face.duplicate()
	var walls_out: Array[PackedVector3Array] = []
	for faces in wall_faces:
		walls_out.append(TrackCollisionData._mirror_faces(faces))
	out.wall_faces = walls_out
	out.wall_attr_ids = wall_attr_ids.duplicate()
	var movers_out: Array[MoverDef] = []
	for mover in movers:
		movers_out.append(mover.mirrored() if mover != null else null)
	out.movers = movers_out
	out.probe_point = Vector3(-probe_point.x, probe_point.y, probe_point.z)
	out.probe_surface_id = probe_surface_id
	return out


## [param faces] reflected x -> -x, each whole triangle (a, b, c) written as (a', c', b').
static func _mirror_faces(faces: PackedVector3Array) -> PackedVector3Array:
	var n: int = faces.size()
	var out: PackedVector3Array = PackedVector3Array()
	out.resize(n)
	var whole: int = n - n % 3
	for i in range(0, whole, 3):
		var a: Vector3 = faces[i]
		var b: Vector3 = faces[i + 1]
		var c: Vector3 = faces[i + 2]
		out[i] = Vector3(-a.x, a.y, a.z)
		out[i + 1] = Vector3(-c.x, c.y, c.z)
		out[i + 2] = Vector3(-b.x, b.y, b.z)
	for i in range(whole, n):
		var p: Vector3 = faces[i]
		out[i] = Vector3(-p.x, p.y, p.z)
	return out


## Table of SurfaceSet.MAX_ID + 1 entries: 1 where [param surfaces] has a type with that id.
static func _surface_table(surfaces: SurfaceSet) -> PackedByteArray:
	var table: PackedByteArray = PackedByteArray()
	table.resize(SurfaceSet.MAX_ID + 1)
	table.fill(0)
	for t in surfaces.types:
		if t != null and t.id >= 0 and t.id <= SurfaceSet.MAX_ID:
			table[t.id] = 1
	return table


## Table of WallAttrSet.MAX_ID + 1 entries: 1 where [param walls] has an attribute with that id.
static func _wall_table(walls: WallAttrSet) -> PackedByteArray:
	var table: PackedByteArray = PackedByteArray()
	table.resize(WallAttrSet.MAX_ID + 1)
	table.fill(0)
	for a in walls.attrs:
		if a != null and a.id >= 0 and a.id <= WallAttrSet.MAX_ID:
			table[a.id] = 1
	return table


## True when [param id] is inside [param table] and flagged.
static func _known(table: PackedByteArray, id: int) -> bool:
	return id >= 0 and id < table.size() and table[id] != 0
