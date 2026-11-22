class_name CollisionQuery
extends RefCounted
## The track's collision queries (ADR-0002; core-rebuild story 003: construction, cast_ground,
## dispose; story 004: sweep_walls; movers are story 005). Jolt Physics, used only through
## PhysicsServer3D: this object creates and owns a private space (never activated: an inactive space
## answers queries and is never stepped), the server-side concave shapes and the static bodies.
##   - Ground (layer 1): one body, ONE concave shape holding every ground triangle; the surface id
##     of a hit is surface_of_face[face_index].
##   - Walls (layer 2): one body, one concave shape per wall attribute (wall shape k carries
##     wall_attr_ids[k]).
## No collision nodes are used.
##
## Lifetime: the composition root calls dispose() at track unload. dispose() frees the bodies, then
## the shapes, then the space (freeing the space first crashes later, ADR-0002 Verified 8). It is
## idempotent. If the last reference drops without it, the object disposes itself and push_warnings.
##
## Threading: main thread only. physics/3d/run_on_separate_thread stays false (pinned in
## project.godot); queries must not run on any other thread.
## Needs physics/jolt_physics_3d/queries/enable_ray_cast_face_index = true (pinned in project.godot;
## asserted at boot from story 006), otherwise every ground hit reports SURFACE_NONE.
## [codeblock]
## var query: CollisionQuery = CollisionQuery.new(track_data)
## var cursor: QueryCursor = QueryCursor.new()      # once per kart
## var hit: GroundHit = GroundHit.new()             # once per probe
## if query.cast_ground(cursor, wheel_origin, Vector3.DOWN, max_drop, t, hit):
##     surface_ids[n_hit] = hit.surface_id
##     hit_points[n_hit] = hit.point
##     n_hit += 1
## var kart_surface: int = CollisionQuery.majority_surface(surface_ids, hit_points, n_hit,
##         centre_of_mass, kart_up, previous_surface)
## var wall: WallHit = WallHit.new()                # once per kart
## if query.sweep_walls(cursor, from, to, kart_radius, t, wall):
##     var wall_attr: int = wall.wall_attr          # WallAttr.id of the wall hit
## # ... at track unload:
## query.dispose()
## [/codeblock]

## Collision layer bit of the ground body (layer 1). Part of the ADR-0002 layout, not tuning.
const GROUND_LAYER: int = 1
## Collision layer bit of the wall body (layer 2, bit value 2). Part of the ADR-0002 layout.
const WALL_LAYER: int = 2
## surface_id reported when a ground hit has no usable face index. Not a registered id (ids >= 0).
const SURFACE_NONE: int = -1
## wall_attr reported when a wall contact has no usable shape index. Not a registered id (ids >= 0).
const WALL_ATTR_NONE: int = -1

## The private space (inactive). RID() after dispose().
var _space: RID = RID()
## Every body created, in creation order (ground first when present, then walls).
var _bodies: Array[RID] = []
## Every shape created: the ground shape (when present), then wall shape 0..N-1.
var _shapes: Array[RID] = []
## The ground body, or RID() when the data has no ground triangles.
var _ground_body: RID = RID()
## The wall body, or RID() when the data has no walls.
var _wall_body: RID = RID()
## Copy of TrackCollisionData.surface_of_face (copy-on-write: shares the data's buffer).
var _surface_of_face: PackedInt32Array = PackedInt32Array()
## Copy of TrackCollisionData.wall_attr_ids (copy-on-write): wall shape k carries
## _wall_attr_ids[k]. Read by sweep_walls.
var _wall_attr_ids: PackedInt32Array = PackedInt32Array()
## Cached direct state of _space. null after dispose().
var _state: PhysicsDirectSpaceState3D = null
## True once dispose() ran.
var _disposed: bool = false


## Builds the query from [param data]. When [param data] is null or its layout_error() is not
## empty, push_errors and builds an empty query (every cast misses) instead of half the geometry,
## so a broken bake degrades to "no collision" and never to wrong surfaces.
## Allocates (server objects, one-off): call at track load, not per tick. Main thread only.
## [codeblock]
## var query: CollisionQuery = CollisionQuery.new(data)
## [/codeblock]
func _init(data: TrackCollisionData) -> void:
	_space = PhysicsServer3D.space_create()
	_state = PhysicsServer3D.space_get_direct_state(_space)
	if data == null:
		push_error("CollisionQuery: data is null; the query has no geometry")
		return
	var problem: String = data.layout_error()
	if not problem.is_empty():
		push_error("CollisionQuery: %s; the query has no geometry" % problem)
		return
	_surface_of_face = data.surface_of_face
	_wall_attr_ids = data.wall_attr_ids
	if data.ground_faces.size() > 0:
		var ground_shape: RID = _make_concave_shape(data.ground_faces)
		_ground_body = _make_static_body(GROUND_LAYER)
		PhysicsServer3D.body_add_shape(_ground_body, ground_shape)
	if data.wall_faces.size() > 0:
		_wall_body = _make_static_body(WALL_LAYER)
		for faces in data.wall_faces:
			PhysicsServer3D.body_add_shape(_wall_body, _make_concave_shape(faces))


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and not _disposed:
		push_warning("CollisionQuery freed without dispose(); disposing now (call dispose() at track unload)")
		# During PREDELETE a RefCounted's self is already a null instance, so an instance method
		# (dispose()) cannot be called here; the static helper only needs the RIDs.
		_disposed = true
		_state = null
		CollisionQuery._free_server_objects(_bodies, _shapes, _space)


## Frees every server object this query owns, in the fixed order bodies, then shapes, then the
## space, and drops the cached direct state. Idempotent: a second call does nothing. After it,
## every query method asserts in debug builds and returns false (a miss) in release builds.
## Main thread only.
## [codeblock]
## query.dispose()
## query.dispose()  # safe: does nothing
## [/codeblock]
func dispose() -> void:
	if _disposed:
		return
	_disposed = true
	_state = null
	CollisionQuery._free_server_objects(_bodies, _shapes, _space)
	_bodies.clear()
	_shapes.clear()
	_space = RID()
	_ground_body = RID()
	_wall_body = RID()


## True once dispose() ran.
## [codeblock]
## if not query.is_disposed():
##     query.dispose()
## [/codeblock]
func is_disposed() -> bool:
	return _disposed


## Casts a ray against the static ground (layer 1 only: walls and wall tops are not ground) from
## [param origin] along [param dir] (unit length) for [param max_dist] metres. Back faces are
## never hit. On a hit, writes [param out] (point, normal, surface_id = surface_of_face[face_index],
## collider_id 0, collider_velocity zero) and returns true; on a miss returns false and leaves
## [param out] untouched. [param _t] is the simulation time used for movers from story 005 (unused
## until then). Allocation-free: uses only [param cursor]'s reused objects.
## Main thread only.
## [codeblock]
## var down_hit: bool = query.cast_ground(cursor, Vector3(4.0, 2.0, -3.0), Vector3.DOWN, 3.0, t, hit)
## [/codeblock]
func cast_ground(cursor: QueryCursor, origin: Vector3, dir: Vector3, max_dist: float, _t: float, out: GroundHit) -> bool:
	assert(not _disposed, "CollisionQuery.cast_ground after dispose()")
	assert(dir.is_normalized(), "CollisionQuery.cast_ground: dir must be unit length")
	if _disposed:
		return false
	var params: PhysicsRayQueryParameters3D = cursor.ray_params
	params.from = origin
	params.to = origin + dir * max_dist
	params.collision_mask = GROUND_LAYER
	params.hit_back_faces = false
	var result: PhysicsIntersectRayResult3D = cursor.ray_result
	if not _state.intersect_ray_into(params, result):
		return false
	var face: int = result.collider_face_index
	out.point = result.position
	out.normal = result.normal
	if face >= 0 and face < _surface_of_face.size():
		out.surface_id = _surface_of_face[face]
	else:
		out.surface_id = SURFACE_NONE
	out.collider_id = 0
	out.collider_velocity = Vector3.ZERO
	return true


## Sweeps a sphere of [param radius] (> 0) against the static walls (layer 2 only: the sweep never
## sees ground triangles) from [param from] to [param to]. Walls are one-sided: a sphere coming
## from a wall's back side passes through it. On a hit, writes every field of [param out] and
## returns true; on a miss returns false and leaves [param out] untouched. wall_attr is
## wall_attr_ids[collider_shape] (the stable WallAttr.id), collider_id 0, collider_velocity zero.
## ADR-0002 order, every call:
##   1. Rest check at [param from], unconditional. An overlap (a flush contact counts) returns at
##      once: started_inside = true, fraction = 0, point / normal / wall_attr from the overlap, and
##      no cast runs (a cast from an overlapped start is blind to that wall).
##   2. Cast from [param from] to [param to] (skipped when they are equal: nothing moves).
##   3. A hit whose first contact is before the end of the motion (unsafe fraction < 1): rest check
##      at the unsafe point; fraction = the cast's safe fraction.
##   4. Otherwise (a clear cast, or a first contact exactly at the end, which Jolt reports as a hit
##      with unsafe fraction 1): rest check at [param to]. A contact there is a touch:
##      fraction = 1.0, started_inside = false.
## [param _t] is the simulation time for movers (story 005; unused until then).
## Allocation-free: uses only [param cursor]'s reused objects; the sphere radius is only written
## when it changes. Main thread only.
## [codeblock]
## if query.sweep_walls(cursor, kart_centre, kart_centre + motion, 1.0, t, wall):
##     if wall.started_inside:
##         pass  # push out along the wall normal, then sweep again
##     elif wall.fraction < 1.0:
##         kart_centre += motion * wall.fraction  # then slide along wall.normal
## [/codeblock]
func sweep_walls(cursor: QueryCursor, from: Vector3, to: Vector3, radius: float, _t: float, out: WallHit) -> bool:
	assert(not _disposed, "CollisionQuery.sweep_walls after dispose()")
	assert(radius > 0.0, "CollisionQuery.sweep_walls: radius must be > 0")
	if _disposed:
		return false
	var params: PhysicsShapeQueryParameters3D = cursor.shape_params
	if cursor.sphere.radius != radius:
		cursor.sphere.radius = radius
	params.collision_mask = WALL_LAYER
	params.motion = Vector3.ZERO
	params.transform = Transform3D(Basis.IDENTITY, from)
	var rest: PhysicsGetRestInfoResult3D = cursor.rest_result
	# Step 1: the unconditional rest check at from (closes the start-overlap tunnelling hole).
	if _state.get_rest_info_into(params, rest):
		_write_wall_contact(rest, 0.0, true, out)
		return true
	# STORY 005 HOOK (movers, not implemented here): the analytic mover overlap at `from` belongs
	# here. It also sets started_inside and returns at once; when a static wall and a mover both
	# overlap, the deeper one wins, so the static rest check above must then be compared with the
	# mover overlap instead of returning straight away. The analytic mover sweep (ADR-0002 step 5)
	# is merged with the static result below, nearest fraction first.
	var motion: Vector3 = to - from
	if motion == Vector3.ZERO:
		return false
	# Step 2: the cast.
	params.motion = motion
	var cast: PhysicsCastMotionResult3D = cursor.cast_result
	var cast_hit: bool = _state.cast_motion_into(params, cast)
	params.motion = Vector3.ZERO
	if cast_hit and cast.unsafe_fraction < 1.0:
		# Step 3: the first contact is inside the motion.
		_write_blocked_hit(cursor, from, motion, radius, out)
		return true
	# Step 4: clear cast, or the first contact is at the very end: a contact at `to` is a touch.
	params.transform = Transform3D(Basis.IDENTITY, to)
	if _state.get_rest_info_into(params, rest):
		_write_wall_contact(rest, 1.0, false, out)
		return true
	return false


## The surface under a kart: the majority of the surface ids its probes hit (Track Collision GDD
## 4.1, AC-4). [param ids] and [param points] hold the surface id and the contact point of each probe
## that HIT, in probe order (front-left, front-right, rear-left, rear-right; misses left out); only
## the first [param count] entries of each are read.
## Tie (owner decision C12, 2026-11-22; the same rule as the ADR-0003 support): when two or more
## kinds share the most votes, the winner is the kind of the tied-kind probe whose contact point is
## nearest [param centre_of_mass], measured on the plane normal to [param up] (unit length; the
## height along up is ignored). Probes at exactly equal distance go to the lowest probe index.
## With no hit (count <= 0: airborne) it returns [param previous_id] unchanged.
## Allocation-free, pure (no state): safe from any thread.
## [codeblock]
## var ids: PackedInt32Array = PackedInt32Array([0, 1, 1, 1])   # road, grass, grass, grass
## var pts: PackedVector3Array = PackedVector3Array([Vector3(-0.5, 0, -0.7), Vector3(0.5, 0, -0.7),
##         Vector3(-0.5, 0, 0.7), Vector3(0.5, 0, 0.7)])
## CollisionQuery.majority_surface(ids, pts, 4, Vector3.ZERO, Vector3.UP, 0)   # 1 (grass)
## ids = PackedInt32Array([1, 0, 0, 1])                          # 2-2 tie
## CollisionQuery.majority_surface(ids, pts, 4, Vector3(0.4, 0, -0.5), Vector3.UP, 0)
## # 0: front-right (road) is nearest the centre of mass
## [/codeblock]
static func majority_surface(ids: PackedInt32Array, points: PackedVector3Array, count: int,
		centre_of_mass: Vector3, up: Vector3, previous_id: int) -> int:
	var n: int = mini(count, mini(ids.size(), points.size()))
	if n <= 0:
		return previous_id
	# Pass 1: the largest vote count.
	var best_votes: int = 0
	for i in n:
		var votes: int = _votes(ids, n, ids[i])
		if votes > best_votes:
			best_votes = votes
	# Pass 2: among probes whose kind has best_votes, the one nearest the centre of mass on the up
	# plane. Strictly less: an equal distance never displaces a lower-index probe.
	var best_id: int = previous_id
	var best_dist_sq: float = INF
	for i in n:
		if _votes(ids, n, ids[i]) != best_votes:
			continue
		var offset: Vector3 = points[i] - centre_of_mass
		var planar: Vector3 = offset - up * offset.dot(up)
		var dist_sq: float = planar.length_squared()
		if dist_sq < best_dist_sq:
			best_dist_sq = dist_sq
			best_id = ids[i]
	return best_id


## The server objects this query owns, in the order dispose() frees them: bodies, then shapes,
## then the space. Empty after dispose(). For tests, tools and leak checks; allocates, so never
## call it per tick.
## [codeblock]
## var rids: Array[RID] = query.owned_rids()
## [/codeblock]
func owned_rids() -> Array[RID]:
	var rids: Array[RID] = []
	rids.append_array(_bodies)
	rids.append_array(_shapes)
	if _space.is_valid():
		rids.append(_space)
	return rids


## The private space, or RID() after dispose(). For tests and tools.
## [codeblock]
## assert(not PhysicsServer3D.space_is_active(query.space_rid()))
## [/codeblock]
func space_rid() -> RID:
	return _space


## The ground body, or RID() when there is no ground or after dispose(). For tests and tools.
## [codeblock]
## var layer: int = PhysicsServer3D.body_get_collision_layer(query.ground_body_rid())  # 1
## [/codeblock]
func ground_body_rid() -> RID:
	return _ground_body


## The wall body, or RID() when there are no walls or after dispose(). For tests and tools.
## [codeblock]
## var n_wall_shapes: int = PhysicsServer3D.body_get_shape_count(query.wall_body_rid())
## [/codeblock]
func wall_body_rid() -> RID:
	return _wall_body


## Number of the first [param n] entries of [param ids] equal to [param id].
static func _votes(ids: PackedInt32Array, n: int, id: int) -> int:
	var votes: int = 0
	for j in n:
		if ids[j] == id:
			votes += 1
	return votes


## ADR-0002 sweep step 3, after a cast that hit with unsafe fraction < 1 (in [param cursor]'s
## cast_result): a rest check at the unsafe point gives the contact; fraction = the safe fraction.
## If that rest check finds nothing (not seen in the tests; the probes never checked rest at the
## unsafe point), the hit is kept so the sphere is blocked rather than let through: a contact
## straight ahead along [param motion], wall_attr = WALL_ATTR_NONE, and a push_warning in debug
## builds.
func _write_blocked_hit(cursor: QueryCursor, from: Vector3, motion: Vector3, radius: float, out: WallHit) -> void:
	var params: PhysicsShapeQueryParameters3D = cursor.shape_params
	var cast: PhysicsCastMotionResult3D = cursor.cast_result
	var safe: float = cast.safe_fraction
	var unsafe_centre: Vector3 = from + motion * cast.unsafe_fraction
	params.transform = Transform3D(Basis.IDENTITY, unsafe_centre)
	if _state.get_rest_info_into(params, cursor.rest_result):
		_write_wall_contact(cursor.rest_result, safe, false, out)
		return
	if OS.is_debug_build():
		push_warning("CollisionQuery.sweep_walls: no rest contact at the unsafe point; reporting a blocking hit with WALL_ATTR_NONE")
	var dir: Vector3 = motion.normalized()
	out.point = unsafe_centre + dir * radius
	out.normal = -dir
	out.wall_attr = WALL_ATTR_NONE
	out.fraction = safe
	out.started_inside = false
	out.collider_id = 0
	out.collider_velocity = Vector3.ZERO


## Writes a static-wall contact from [param rest] (a rest check that returned true) into
## [param out]. wall_attr is _wall_attr_ids[collider_shape] (WALL_ATTR_NONE when out of range).
func _write_wall_contact(rest: PhysicsGetRestInfoResult3D, fraction: float, started_inside: bool, out: WallHit) -> void:
	var shape: int = rest.collider_shape
	out.point = rest.point
	out.normal = rest.normal
	if shape >= 0 and shape < _wall_attr_ids.size():
		out.wall_attr = _wall_attr_ids[shape]
	else:
		out.wall_attr = WALL_ATTR_NONE
	out.fraction = fraction
	out.started_inside = started_inside
	out.collider_id = 0
	out.collider_velocity = Vector3.ZERO


## Frees [param bodies], then [param shapes], then [param space]: the one place that fixes the
## ADR-0002 order (freeing the space first crashes later). Static so the PREDELETE fallback can
## call it.
static func _free_server_objects(bodies: Array[RID], shapes: Array[RID], space: RID) -> void:
	for body in bodies:
		PhysicsServer3D.free_rid(body)
	for shape in shapes:
		PhysicsServer3D.free_rid(shape)
	if space.is_valid():
		PhysicsServer3D.free_rid(space)


func _make_concave_shape(faces: PackedVector3Array) -> RID:
	var shape: RID = PhysicsServer3D.concave_polygon_shape_create()
	PhysicsServer3D.shape_set_data(shape, {"faces": faces, "backface_collision": false})
	_shapes.append(shape)
	return shape


func _make_static_body(layer: int) -> RID:
	var body: RID = PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_set_collision_layer(body, layer)
	PhysicsServer3D.body_set_collision_mask(body, 0)
	PhysicsServer3D.body_set_space(body, _space)
	_bodies.append(body)
	return body
