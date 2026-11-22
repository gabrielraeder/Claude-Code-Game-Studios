class_name CollisionQuery
extends RefCounted
## The track's collision queries (ADR-0002; core-rebuild story 003: construction, cast_ground,
## dispose; story 004: sweep_walls; story 005: movers). Jolt Physics, used only through
## PhysicsServer3D: this object creates and owns a private space (never activated: an inactive space
## answers queries and is never stepped), the server-side concave shapes and the static bodies.
##   - Ground (layer 1): one body, ONE concave shape holding every ground triangle; the surface id
##     of a hit is surface_of_face[face_index].
##   - Walls (layer 2): one body, one concave shape per wall attribute (wall shape k carries
##     wall_attr_ids[k]).
##   - Movers: NOT Jolt bodies. Each MoverDef is a primitive on a looped keyframed pose curve; this
##     object is the single evaluator (mover_pose, mover_point_velocity) and tests the solid movers
##     analytically in cast_ground and sweep_walls.
## No collision nodes are used.
##
## Time convention: every query takes t, the caller's tick time n x SIM_DT (ADR-0001 section 5;
## presentation may pass the continuous synced time to mover_pose). No clock is read here. A mover
## is frozen at mover_pose(id, t) for the whole query. A kart riding a mover is carried by the pose
## delta between ticks (story 021, ADR-0003), not by integrating a hit's collider_velocity.
##
## Lifetime: the composition root calls dispose() at track unload. dispose() frees the bodies, then
## the shapes, then the space (freeing the space first crashes later, ADR-0002 Verified 8). It is
## idempotent. If the last reference drops without it, the object disposes itself and push_warnings.
##
## Threading: main thread only. The mover code keeps per-object scratch fields and a pose cache
## (each mover's pose, inverse and velocities at the last t it was evaluated at; story 007) shared by
## every query method, so no two queries of one CollisionQuery may run at once. The setting
## physics/3d/run_on_separate_thread stays false (pinned in project.godot).
## Needs physics/jolt_physics_3d/queries/enable_ray_cast_face_index = true (pinned in project.godot;
## asserted at boot by CollisionBootCheck.assert_boot_settings(), story 006), otherwise every ground
## hit reports SURFACE_NONE. At track load the composition root runs CollisionBootCheck.load_error(),
## whose probe cast (probe_error) catches that and a missing mirror winding flip.
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
## var gate_pose: Transform3D = query.mover_pose(gate_id, t)   # presentation, hazards
## # ... at track unload:
## query.dispose()
## [/codeblock]

## Collision layer bit of the ground body (layer 1). Part of the ADR-0002 layout, not tuning.
const GROUND_LAYER: int = 1
## Collision layer bit of the wall body (layer 2, bit value 2). Part of the ADR-0002 layout.
const WALL_LAYER: int = 2
## surface_id reported when a static ground hit has no usable face index. Not a registered id
## (ids >= 0). A mover hit reports its MoverDef.surface_id instead.
const SURFACE_NONE: int = -1
## wall_attr reported when a static wall contact has no usable shape index. Not a registered id
## (ids >= 0). A mover contact reports its MoverDef.wall_attr_id instead.
const WALL_ATTR_NONE: int = -1
## Length (m) at which the analytic mover sweep stops refining the first contact: the reported
## fraction is safe (no overlap) and at most this far short of the true contact along the motion. A
## touch (fraction 1.0) needs the end itself in contact and the first contact within this length of
## the end. A numerical tolerance (Jolt's own safe/unsafe gap is ~1/4096 of the motion), not tuning.
const MOVER_SWEEP_TOLERANCE: float = 0.0001
## Iteration cap of each refinement loop of the analytic mover sweep (Newton steps, bisection).
## A safety bound only: Newton from the start converges monotonically and the bisection halves a
## bracket, so the tolerance above ends both loops first for any motion under ~100 km. Reaching the
## Newton cap fails closed: a blocking hit at the last safe fraction and one push_error per query.
const MOVER_SWEEP_MAX_ITERATIONS: int = 64
## Sentinel of _sweep_local's bracket end while no probe is in contact yet (the cap case). Not tuning.
const NEWTON_CAPPED: float = -2.0
## Extra length (m) along the motion of the second static rest check when the one exactly at the
## cast's unsafe point finds nothing (story 007: on 4.8-beta3 Jolt can report the cast's unsafe
## point inside its cast tolerance while a rest check there finds no contact; 0.0001 m was enough
## in the probe, 0.00001 m was not). A numerical tolerance, not tuning.
const UNSAFE_RETRY_LENGTH: float = 0.001
## Margin (m) added to the mover cull radii so float32 rounding never culls a real contact.
## Numerical, not tuning.
const MOVER_CULL_MARGIN: float = 0.01
## Below this, a ray direction component counts as parallel to a slab / axis. Numerical, not tuning.
const PARALLEL_EPSILON: float = 0.000001
## Below this vector-part length, a key-to-key rotation counts as small and its angular velocity uses
## the small-angle form 2 * (x, y, z) / span. Numerical, not tuning.
const SMALL_ROTATION_EPSILON: float = 0.000001
## Time (s) of the load-time probe cast (story 005 LP review). Authoring rule: no solid mover stands
## over TrackCollisionData.probe_point at this time. A fixed check time, not tuning.
const PROBE_T: float = 0.0
## The project setting ground surface ids need (ADR-0002): with it off, Jolt reports no face index.
const FACE_INDEX_SETTING: String = "physics/jolt_physics_3d/queries/enable_ray_cast_face_index"

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
## The data's movers in data order (shared MoverDef references: plain data, read-only after load).
## Empty when the layout was rejected, and after dispose().
var _movers: Array[MoverDef] = []
## Mover id -> index in _movers.
var _mover_slot: Dictionary[int, int] = {}
## Radius of the sphere around mover k's pose origin that holds its shape.
var _mover_shape_bound: PackedFloat64Array = PackedFloat64Array()
## Centre of a sphere holding every key position of mover k (the pose origin never leaves the
## convex hull of the key positions: position is piecewise linear).
var _mover_path_centre: PackedVector3Array = PackedVector3Array()
## Radius of that sphere plus _mover_shape_bound[k] plus MOVER_CULL_MARGIN: a time-free cull.
var _mover_path_reach: PackedFloat64Array = PackedFloat64Array()
## Slots of the solid movers, in data order: the only movers cast_ground and sweep_walls test.
var _solid_slots: PackedInt32Array = PackedInt32Array()
## Pose cache (story 007, TD-012): mover k evaluated at time _pc_t[k] (NAN = never). Every _pc_*
## array has one entry per mover: appended in _add_mover (load), cleared in dispose().
## The cache key is the exact float t: _eval_slot reuses an entry only when t == _pc_t[k]. That is
## valid, and pays, only because every query of one tick passes the identical t (n x SIM_DT computed
## once by the caller); a different t, however close, re-evaluates. A cached entry holds exactly
## what an evaluation at that t computes, so results stay bit-identical.
var _pc_t: PackedFloat64Array = PackedFloat64Array()
## Cached pose and its inverse.
var _pc_pose: Array[Transform3D] = []
var _pc_inv: Array[Transform3D] = []
## Cached linear velocity (m/s) of the active key segment.
var _pc_lin: PackedVector3Array = PackedVector3Array()
## Cached angular velocity (rad/s), valid only when _pc_ang_ok[k] == 1: computed lazily, on a hit.
var _pc_ang: PackedVector3Array = PackedVector3Array()
var _pc_ang_ok: PackedByteArray = PackedByteArray()
## Cached active key pair and segment span (for the lazy angular velocity).
var _pc_seg_i: PackedInt32Array = PackedInt32Array()
var _pc_seg_j: PackedInt32Array = PackedInt32Array()
var _pc_span: PackedFloat64Array = PackedFloat64Array()
## Cached direct state of _space. null after dispose().
var _state: PhysicsDirectSpaceState3D = null
## True once dispose() ran.
var _disposed: bool = false
## Newton step cap of the mover sweep (MOVER_SWEEP_MAX_ITERATIONS). A test seam: tests lower it to
## exercise the fail-closed path; game code never changes it.
var _newton_cap: int = MOVER_SWEEP_MAX_ITERATIONS
## True once this query push_errored a capped mover sweep (the error is reported once per query).
var _cap_error_reported: bool = false

# Per-call scratch: multi-value returns of the mover helpers without allocating. Shared by every
# query method of this object: main thread only, never two queries at once.
## _find_segment output: the active key pair, its start time, span and fraction.
var _seg_i: int = 0
var _seg_j: int = 0
var _seg_span: float = 1.0
var _seg_alpha: float = 0.0
## _closest_* output: nearest surface point and outward unit normal, mover-local.
var _cl_point: Vector3 = Vector3.ZERO
var _cl_normal: Vector3 = Vector3.UP
## _ray_* output: entry distance along the ray and entry normal (mover-local).
var _ray_dist: float = 0.0
var _ray_normal: Vector3 = Vector3.UP
## _sweep_local output: fraction (1.0 = touch at the end), contact point and normal, mover-local.
var _sw_fraction: float = 1.0
var _sw_point: Vector3 = Vector3.ZERO
var _sw_normal: Vector3 = Vector3.UP
## _test_ground_movers output: nearest mover hit (slot -1 = none), distance, world normal, velocity.
var _gm_slot: int = -1
var _gm_dist: float = 0.0
var _gm_normal: Vector3 = Vector3.UP
var _gm_velocity: Vector3 = Vector3.ZERO
## _test_movers_for_sweep pass 1 -> pass 2: the movers in reach that do not overlap at `from`
## (slot, local start, local motion, start gap, start slope d gap / d fraction). Every _rs_* array
## has one entry per mover: appended in _add_mover (load), cleared in dispose(); _rs_count entries
## are used per sweep.
var _rs_count: int = 0
var _rs_slot: PackedInt32Array = PackedInt32Array()
var _rs_from: PackedVector3Array = PackedVector3Array()
var _rs_motion: PackedVector3Array = PackedVector3Array()
var _rs_gap: PackedFloat64Array = PackedFloat64Array()
var _rs_slope: PackedFloat64Array = PackedFloat64Array()
## _test_movers_for_sweep output, deepest overlap at `from`: slot (-1 = none), depth, world contact
## (point and normal are mover-local until the end of pass 1).
var _ov_slot: int = -1
var _ov_depth: float = 0.0
var _ov_point: Vector3 = Vector3.ZERO
var _ov_normal: Vector3 = Vector3.UP
var _ov_velocity: Vector3 = Vector3.ZERO
## _test_movers_for_sweep output, first swept contact: slot (-1 = none), fraction, world contact.
var _sm_slot: int = -1
var _sm_fraction: float = 1.0
var _sm_point: Vector3 = Vector3.ZERO
var _sm_normal: Vector3 = Vector3.UP
var _sm_velocity: Vector3 = Vector3.ZERO


## Builds the query from [param data]. When [param data] is null or its layout_error() is not
## empty (which includes every mover check), push_errors and builds an empty query (every cast
## misses, no movers) instead of half the geometry, so a broken bake degrades to "no collision" and
## never to wrong surfaces.
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
	for mover in data.movers:
		_add_mover(mover)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and not _disposed:
		push_warning("CollisionQuery freed without dispose(); disposing now (call dispose() at track unload)")
		# During PREDELETE a RefCounted's self is already a null instance, so an instance method
		# (dispose()) cannot be called here; the static helper only needs the RIDs.
		_disposed = true
		_state = null
		CollisionQuery._free_server_objects(_bodies, _shapes, _space)


## Frees every server object this query owns, in the fixed order bodies, then shapes, then the
## space, and drops the cached direct state and every mover reference and cull array. Idempotent: a
## second call does nothing. After it, every query method (including mover_pose and
## mover_point_velocity) asserts in debug builds and returns a miss / identity / zero in release
## builds. Main thread only.
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
	_movers.clear()
	_mover_slot.clear()
	_mover_shape_bound.clear()
	_mover_path_centre.clear()
	_mover_path_reach.clear()
	_solid_slots.clear()
	_pc_t.clear()
	_pc_pose.clear()
	_pc_inv.clear()
	_pc_lin.clear()
	_pc_ang.clear()
	_pc_ang_ok.clear()
	_pc_seg_i.clear()
	_pc_seg_j.clear()
	_pc_span.clear()
	_rs_count = 0
	_rs_slot.clear()
	_rs_from.clear()
	_rs_motion.clear()
	_rs_gap.clear()
	_rs_slope.clear()


## True once dispose() ran.
## [codeblock]
## if not query.is_disposed():
##     query.dispose()
## [/codeblock]
func is_disposed() -> bool:
	return _disposed


## True when the query built any geometry: a ground body, a wall body or a mover. Every mover counts,
## NON-SOLID ones included, though cast_ground and sweep_walls skip non-solid movers: a query whose
## only geometry is non-solid movers has geometry but no ground the probe can hit. False for a query
## whose data was null or rejected by layout_error() (it push_errored and built nothing), for data
## with no geometry at all, and after dispose(). For the precise load-check message (story 003 LP
## review). Main thread only.
## [codeblock]
## if not query.has_geometry():
##     push_error("the track has no collision: see the CollisionQuery error above")
## [/codeblock]
func has_geometry() -> bool:
	return _ground_body.is_valid() or _wall_body.is_valid() or not _movers.is_empty()


## The load-time probe (ADR-0002 "Boot and load checks"; story 006): cast_ground straight down from
## [param probe_point] for [param max_drop] metres (> 0; ADR-0005's probe_max_drop_m) at t = PROBE_T
## must hit the STATIC ground with surface id [param probe_surface_id] and normal.y > 0. Returns ""
## on success, otherwise one sentence naming the reason: the query is disposed; max_drop not > 0;
## a miss on a query with no geometry (has_geometry() false: its data was rejected); a miss with
## geometry (no ground there, or ground facing away: a mirror without the winding flip; also a query
## whose only geometry is non-solid movers, which has_geometry() counts); a hit on a
## solid mover (the authoring rule above); a hit with no face index (SURFACE_NONE: names
## FACE_INDEX_SETTING and its current value); another surface id; a normal that is not up.
## It runs on every load, an empty query included, and also warms Jolt's lazily built broadphase.
## Allocates one QueryCursor and one GroundHit: load time only. Main thread only.
## [codeblock]
## var problem: String = query.probe_error(data.probe_point, data.probe_surface_id, limits.probe_max_drop_m)
## assert(problem.is_empty(), problem)
## [/codeblock]
func probe_error(probe_point: Vector3, probe_surface_id: int, max_drop: float) -> String:
	if _disposed:
		return "load probe: the query is disposed"
	if not (max_drop > 0.0):
		return "load probe: max_drop is %s (must be > 0)" % max_drop
	var hit: GroundHit = GroundHit.new()
	if not cast_ground(QueryCursor.new(), probe_point, Vector3.DOWN, max_drop, PROBE_T, hit):
		if not has_geometry():
			return "load probe at %s missed: the query has no geometry (its data was null or rejected; see the CollisionQuery error)" % probe_point
		return "load probe at %s found no ground within %s m below (ground missing there, or facing away: a mirror without the winding flip; has_geometry() counts non-solid movers, which the probe never hits)" % [probe_point, max_drop]
	if hit.collider_id != 0:
		return "load probe at %s hit mover %d at t = %s (no solid mover may stand over the probe point at t = 0)" % [probe_point, hit.collider_id, PROBE_T]
	if hit.surface_id == SURFACE_NONE:
		return "load probe at %s hit ground with no face index (SURFACE_NONE): %s is %s (must be true)" % [probe_point, FACE_INDEX_SETTING, ProjectSettings.get_setting(FACE_INDEX_SETTING, false)]
	if hit.surface_id != probe_surface_id:
		return "load probe at %s found surface id %d, not probe_surface_id %d" % [probe_point, hit.surface_id, probe_surface_id]
	if not (hit.normal.y > 0.0):
		return "load probe at %s hit a normal %s that is not up (normal.y must be > 0)" % [probe_point, hit.normal]
	return ""


## Casts a ray from [param origin] along [param dir] (unit length) for [param max_dist] metres
## against the static ground (layer 1 only: walls and wall tops are not ground) and the solid
## movers. [param t] is the tick time n x SIM_DT (ADR-0001 section 5); each mover is frozen at
## mover_pose(id, t) for the whole cast. The nearest hit wins; at an exactly equal distance the
## static ground wins, and between movers the first in data order. Back faces are never hit, and a
## ray starting inside a mover does not hit that mover.
## On a hit, writes every field of [param out] and returns true:
##   - static ground: point, normal, surface_id = surface_of_face[face_index], collider_id 0,
##     collider_velocity zero;
##   - a mover: point, normal (the face entered), surface_id = MoverDef.surface_id, collider_id =
##     the mover id, collider_velocity = mover_point_velocity(id, t, point) (informational: riding
##     is by pose delta, story 021).
## On a miss returns false and leaves [param out] untouched. Allocation-free: uses only
## [param cursor]'s reused objects and this query's scratch fields. Main thread only.
## [codeblock]
## var down_hit: bool = query.cast_ground(cursor, Vector3(4.0, 2.0, -3.0), Vector3.DOWN, 3.0, t, hit)
## if down_hit and hit.collider_id != 0:
##     var deck_id: int = hit.collider_id   # standing on a mover
## [/codeblock]
func cast_ground(cursor: QueryCursor, origin: Vector3, dir: Vector3, max_dist: float, t: float, out: GroundHit) -> bool:
	assert(not _disposed, "CollisionQuery.cast_ground after dispose()")
	assert(dir.is_normalized(), "CollisionQuery.cast_ground: dir must be unit length")
	if _disposed:
		return false
	var params: PhysicsRayQueryParameters3D = cursor.ray_params
	params.from = origin
	params.to = origin + dir * max_dist
	# collision_mask (GROUND_LAYER) and hit_back_faces (false) are fixed once by QueryCursor._init.
	var result: PhysicsIntersectRayResult3D = cursor.ray_result
	var static_hit: bool = _state.intersect_ray_into(params, result)
	var best_dist: float = max_dist
	if static_hit:
		_write_ground_contact(result, out)
		best_dist = (out.point - origin).dot(dir)
	if _solid_slots.is_empty() or not _test_ground_movers(origin, dir, max_dist, best_dist, static_hit, t):
		return static_hit
	var mover: MoverDef = _movers[_gm_slot]
	out.point = origin + dir * _gm_dist
	out.normal = _gm_normal
	out.surface_id = mover.surface_id
	out.collider_id = mover.id
	out.collider_velocity = _gm_velocity
	return true


## Sweeps a sphere of [param radius] (> 0) from [param from] to [param to] against the static
## walls (layer 2 only: the sweep never sees ground triangles) and the solid movers. [param t] is
## the tick time n x SIM_DT (ADR-0001 section 5); each mover is frozen at mover_pose(id, t) for the
## whole sweep. Walls are one-sided: a sphere coming from a wall's back side passes through it. On a
## hit, writes every field of [param out] and returns true; on a miss returns false and leaves
## [param out] untouched.
## Static wall: wall_attr = wall_attr_ids[collider_shape] (the stable WallAttr.id), collider_id 0,
## collider_velocity zero. Mover: wall_attr = MoverDef.wall_attr_id, collider_id = the mover id,
## collider_velocity = mover_point_velocity(id, t, point), normal from the mover toward the centre.
## ADR-0002 order, every call:
##   1. Overlap at [param from], unconditional: the static rest check and the analytic mover
##      overlap (a flush contact counts). Any overlap returns at once: started_inside = true,
##      fraction = 0, point / normal / ids from the overlap, and no cast runs. When a static wall
##      and a mover both overlap, the deeper wins (static depth = radius - (from - p) . n of its
##      rest contact; mover depth = radius - signed distance from the centre to the mover); at an
##      equal depth the static wall wins. Among movers, the deepest wins (data order on a tie).
##   2. Cast from [param from] to [param to] (skipped when they are equal: nothing moves).
##   3. A hit whose first contact is before the end of the motion (unsafe fraction < 1): rest check
##      at the unsafe point; fraction = the cast's safe fraction.
##   4. Otherwise (a clear cast, or a first contact exactly at the end, which Jolt reports as a hit
##      with unsafe fraction 1): rest check at [param to]. A contact there is a touch:
##      fraction = 1.0, started_inside = false.
##   5. The analytic mover sweep: the first contact with any solid mover along the motion, with the
##      same blocking (safe fraction < 1) / touch (fraction 1.0) meaning: a mover touch needs the
##      end position itself in contact (penetrating by at most MOVER_SWEEP_TOLERANCE); a first
##      contact near the end with the end clear is a blocking hit. The smaller fraction of
##      the static result and the mover result wins; at an equal fraction the static wall wins.
## Allocation-free: uses only [param cursor]'s reused objects and this query's scratch fields; the
## sphere radius is only written when it changes. Main thread only.
## [codeblock]
## if query.sweep_walls(cursor, kart_centre, kart_centre + motion, 1.0, t, wall):
##     if wall.started_inside:
##         pass  # push out along the wall normal, then sweep again
##     elif wall.fraction < 1.0:
##         kart_centre += motion * wall.fraction  # then slide along wall.normal
## [/codeblock]
func sweep_walls(cursor: QueryCursor, from: Vector3, to: Vector3, radius: float, t: float, out: WallHit) -> bool:
	assert(not _disposed, "CollisionQuery.sweep_walls after dispose()")
	assert(radius > 0.0, "CollisionQuery.sweep_walls: radius must be > 0")
	if _disposed:
		return false
	var params: PhysicsShapeQueryParameters3D = cursor.shape_params
	if cursor.sphere.radius != radius:
		cursor.sphere.radius = radius
	# collision_mask (WALL_LAYER) is fixed once by QueryCursor._init, and motion is zero between
	# calls (only _sweep_static sets it, and resets it right after its cast).
	params.transform = Transform3D(Basis.IDENTITY, from)
	var rest: PhysicsGetRestInfoResult3D = cursor.rest_result
	var motion: Vector3 = to - from
	# Step 1, static: the unconditional rest check at from (closes the start-overlap tunnelling hole).
	var static_inside: bool = _state.get_rest_info_into(params, rest)
	# Step 1, movers: the deepest overlap at from. The same pass runs the mover sweep (step 5) when
	# nothing overlaps statically and the sphere moves; its result is used only if nothing overlaps.
	if _solid_slots.is_empty():
		_ov_slot = -1
		_sm_slot = -1
	else:
		_test_movers_for_sweep(from, motion, radius, t, not static_inside and motion != Vector3.ZERO)
	if static_inside or _ov_slot >= 0:
		if _ov_slot >= 0 and (not static_inside or _ov_depth > radius - (from - rest.point).dot(rest.normal)):
			_write_mover_wall_contact(_ov_slot, _ov_point, _ov_normal, _ov_velocity, 0.0, true, out)
		else:
			_write_wall_contact(rest, 0.0, true, out)
		return true
	if motion == Vector3.ZERO:
		return false
	var static_hit: bool = _sweep_static(cursor, from, to, motion, radius, out)
	# Step 5: merge the mover sweep, smaller fraction first (static wins a tie).
	if _sm_slot >= 0 and (not static_hit or _sm_fraction < out.fraction):
		_write_mover_wall_contact(_sm_slot, _sm_point, _sm_normal, _sm_velocity, _sm_fraction, false, out)
		return true
	return static_hit


## Pose of mover [param id] at time [param t] (seconds; the tick time n x SIM_DT in simulation, the
## continuous synced race time in presentation; never a clock read here): position piecewise linear
## and rotation shortest-path slerp between keys, looped over the mover's period (Track Collision
## GDD 4.4). After the last key the curve runs back to the first key, reached at key_t[0] + period.
## The single evaluator: simulation, Track Hazards and presentation call this, so equal [param t]
## gives a bit-identical pose. Works for solid and non-solid movers. An unknown id push_errors and
## returns Transform3D.IDENTITY. Allocation-free. Uses the same scratch fields as the other query
## methods: main thread only, not reentrant.
## [codeblock]
## var gate_pose: Transform3D = query.mover_pose(gate_id, t)
## gate_mesh.global_transform = gate_pose
## [/codeblock]
func mover_pose(id: int, t: float) -> Transform3D:
	assert(not _disposed, "CollisionQuery.mover_pose after dispose()")
	if _disposed:
		return Transform3D.IDENTITY
	var k: int = _slot_of(id)
	if k < 0:
		push_error("CollisionQuery.mover_pose: no mover with id %d" % id)
		return Transform3D.IDENTITY
	_eval_slot(k, t)
	return _pc_pose[k]


## Velocity (m/s) at world point [param p] of the body of mover [param id] at time [param t] (as
## for mover_pose): v + omega x (p - origin), where v and omega are the exact derivatives of the
## active key segment (v = key position difference / segment time; omega = axis x angle of the
## shortest key-to-key rotation / segment time; Track Collision GDD 4.4) and origin is
## mover_pose(id, t).origin. At a key time it is the velocity of the segment starting there. An
## unknown id push_errors and returns Vector3.ZERO. Allocation-free. Uses the same scratch fields as
## the other query methods: main thread only, not reentrant.
## [codeblock]
## var push: Vector3 = query.mover_point_velocity(hammer_id, t, contact_point)
## [/codeblock]
func mover_point_velocity(id: int, t: float, p: Vector3) -> Vector3:
	assert(not _disposed, "CollisionQuery.mover_point_velocity after dispose()")
	if _disposed:
		return Vector3.ZERO
	var k: int = _slot_of(id)
	if k < 0:
		push_error("CollisionQuery.mover_point_velocity: no mover with id %d" % id)
		return Vector3.ZERO
	_eval_slot(k, t)
	return _pc_lin[k] + _ang_of(k).cross(p - _pc_pose[k].origin)


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


## Writes a static ground hit from [param result] (a ray cast that returned true) into every field
## of [param out]. surface_id is _surface_of_face[face_index] (SURFACE_NONE when out of range).
func _write_ground_contact(result: PhysicsIntersectRayResult3D, out: GroundHit) -> void:
	var face: int = result.collider_face_index
	out.point = result.position
	out.normal = result.normal
	if face >= 0 and face < _surface_of_face.size():
		out.surface_id = _surface_of_face[face]
	else:
		out.surface_id = SURFACE_NONE
	out.collider_id = 0
	out.collider_velocity = Vector3.ZERO


## ADR-0002 sweep steps 2-4 against the static walls (the sphere did not overlap at [param from];
## [param motion] is not zero). Writes every field of [param out] and returns true on a blocking hit
## or a touch at [param to]; returns false and leaves [param out] untouched otherwise.
func _sweep_static(cursor: QueryCursor, from: Vector3, to: Vector3, motion: Vector3, radius: float, out: WallHit) -> bool:
	var params: PhysicsShapeQueryParameters3D = cursor.shape_params
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
	if _state.get_rest_info_into(params, cursor.rest_result):
		_write_wall_contact(cursor.rest_result, 1.0, false, out)
		return true
	return false


## ADR-0002 sweep step 3, after a cast that hit with unsafe fraction < 1 (in [param cursor]'s
## cast_result): a rest check at the unsafe point gives the contact; fraction = the safe fraction.
## If that rest check finds nothing (not seen in the tests; the probes never checked rest at the
## unsafe point; story 007 found it on the bench mesh and added the UNSAFE_RETRY_LENGTH retry, which
## finds it), the hit is kept so the sphere is blocked rather than let through: a contact
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
	# Jolt can place the unsafe point inside its cast tolerance but short of a rest contact (story
	# 007): check again UNSAFE_RETRY_LENGTH further along the motion.
	var retry: float = minf(1.0, cast.unsafe_fraction + UNSAFE_RETRY_LENGTH / motion.length())
	params.transform = Transform3D(Basis.IDENTITY, from + motion * retry)
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


## Writes a mover contact (world point, normal and point velocity) of mover slot [param slot] into
## every field of [param out]; wall_attr is that mover's MoverDef.wall_attr_id.
func _write_mover_wall_contact(slot: int, point: Vector3, normal: Vector3, velocity: Vector3,
		fraction: float, started_inside: bool, out: WallHit) -> void:
	var mover: MoverDef = _movers[slot]
	out.point = point
	out.normal = normal
	out.wall_attr = mover.wall_attr_id
	out.fraction = fraction
	out.started_inside = started_inside
	out.collider_id = mover.id
	out.collider_velocity = velocity


## Index of mover [param id] in _movers, or -1. Typed access, no Variant.
func _slot_of(id: int) -> int:
	if not _mover_slot.has(id):
		return -1
	return _mover_slot[id]


## Registers [param mover] (already layout-checked) and precomputes its cull spheres. Load time.
func _add_mover(mover: MoverDef) -> void:
	var bound: float = 0.0
	match mover.shape:
		MoverDef.Shape.BOX:
			bound = mover.half_extents.length()
		MoverDef.Shape.CAPSULE:
			bound = mover.radius + mover.half_height
		MoverDef.Shape.CYLINDER:
			bound = sqrt(mover.radius * mover.radius + mover.half_height * mover.half_height)
	var lo: Vector3 = mover.key_pos[0]
	var hi: Vector3 = mover.key_pos[0]
	for p: Vector3 in mover.key_pos:
		lo = Vector3(minf(lo.x, p.x), minf(lo.y, p.y), minf(lo.z, p.z))
		hi = Vector3(maxf(hi.x, p.x), maxf(hi.y, p.y), maxf(hi.z, p.z))
	var centre: Vector3 = (lo + hi) * 0.5
	var path_radius: float = 0.0
	for p: Vector3 in mover.key_pos:
		path_radius = maxf(path_radius, centre.distance_to(p))
	var slot: int = _movers.size()
	_mover_slot[mover.id] = slot
	_movers.append(mover)
	_mover_shape_bound.append(bound)
	_mover_path_centre.append(centre)
	_mover_path_reach.append(path_radius + bound + MOVER_CULL_MARGIN)
	if mover.solid:
		_solid_slots.append(slot)
	_pc_t.append(NAN)
	_pc_pose.append(Transform3D.IDENTITY)
	_pc_inv.append(Transform3D.IDENTITY)
	_pc_lin.append(Vector3.ZERO)
	_pc_ang.append(Vector3.ZERO)
	_pc_ang_ok.append(0)
	_pc_seg_i.append(0)
	_pc_seg_j.append(0)
	_pc_span.append(1.0)
	_rs_slot.append(0)
	_rs_from.append(Vector3.ZERO)
	_rs_motion.append(Vector3.ZERO)
	_rs_gap.append(0.0)
	_rs_slope.append(0.0)


## Finds the active key segment of [param key_t] (layout-checked: >= 2 keys, strictly ascending in
## [0, [param period])) at time [param t] into _seg_i, _seg_j, _seg_span and _seg_alpha. The
## comparison of bsearch runs in float32 (the keys' precision), so a t equal to a key time that is
## not float32-exact (3.7, n / 60) can sit a hair below that key in float64: alpha then clamps to 0
## and the pose is that key's, never the loop segment's.
func _find_segment(key_t: PackedFloat32Array, period: float, t: float) -> void:
	var n: int = key_t.size()
	var u: float = fposmod(t, period)
	var i: int = key_t.bsearch(u, false) - 1
	var t0: float = 0.0
	var t1: float = 0.0
	if i >= 0 and i < n - 1:
		_seg_j = i + 1
		t0 = key_t[i]
		t1 = key_t[i + 1]
	else:
		# The loop segment: last key -> first key, reached again at key_t[0] + period. Only a u
		# before the first key (no key at or before it) moves into the second lap.
		if i < 0 and u < key_t[0]:
			u += period
		i = n - 1
		_seg_j = 0
		t0 = key_t[i]
		t1 = key_t[0] + period
	_seg_i = i
	_seg_span = t1 - t0
	_seg_alpha = clampf((u - t0) / _seg_span, 0.0, 1.0)


## Evaluates mover slot [param k] at time [param t] into the pose cache (Track Collision GDD 4.4),
## unless the cache already holds that slot at exactly this t. The mover is layout-checked (unit
## key rotations). The angular velocity is left for _ang_of (lazy: only a hit needs it).
func _eval_slot(k: int, t: float) -> void:
	if _pc_t[k] == t:
		return
	var mover: MoverDef = _movers[k]
	_find_segment(mover.key_t, mover.period, t)
	var p0: Vector3 = mover.key_pos[_seg_i]
	var p1: Vector3 = mover.key_pos[_seg_j]
	var r0: Vector4 = mover.key_rot[_seg_i]
	var r1: Vector4 = mover.key_rot[_seg_j]
	var q0: Quaternion = Quaternion(r0.x, r0.y, r0.z, r0.w)
	var q1: Quaternion = Quaternion(r1.x, r1.y, r1.z, r1.w)
	if q0.dot(q1) < 0.0:
		# The shortest path, as slerp takes it; also keeps the angle of _ang_of in [0, pi].
		q1 = Quaternion(-q1.x, -q1.y, -q1.z, -q1.w)
	var pose: Transform3D = Transform3D(Basis(q0.slerp(q1, _seg_alpha)), p0.lerp(p1, _seg_alpha))
	_pc_pose[k] = pose
	_pc_inv[k] = pose.inverse()
	_pc_lin[k] = (p1 - p0) / _seg_span
	_pc_ang_ok[k] = 0
	_pc_seg_i[k] = _seg_i
	_pc_seg_j[k] = _seg_j
	_pc_span[k] = _seg_span
	_pc_t[k] = t


## Angular velocity (rad/s, world axis times rate) of mover slot [param k]'s active key segment at
## the cached t (call _eval_slot first). Computed once per cached t.
func _ang_of(k: int) -> Vector3:
	if _pc_ang_ok[k] == 1:
		return _pc_ang[k]
	var mover: MoverDef = _movers[k]
	var r0: Vector4 = mover.key_rot[_pc_seg_i[k]]
	var r1: Vector4 = mover.key_rot[_pc_seg_j[k]]
	var q0: Quaternion = Quaternion(r0.x, r0.y, r0.z, r0.w)
	var q1: Quaternion = Quaternion(r1.x, r1.y, r1.z, r1.w)
	if q0.dot(q1) < 0.0:
		q1 = Quaternion(-q1.x, -q1.y, -q1.z, -q1.w)
	var ang: Vector3 = CollisionQuery._angular_velocity(q0, q1, _pc_span[k])
	_pc_ang[k] = ang
	_pc_ang_ok[k] = 1
	return ang


## World angular velocity of the rotation from [param q0] to [param q1] (unit, same hemisphere)
## over [param span] seconds: axis(dq) x angle(dq) / span, dq = q1 * q0^-1, angle = 2 atan2(|v|, w).
static func _angular_velocity(q0: Quaternion, q1: Quaternion, span: float) -> Vector3:
	var dq: Quaternion = q1 * q0.inverse()
	var v: Vector3 = Vector3(dq.x, dq.y, dq.z)
	var s: float = v.length()
	if s > SMALL_ROTATION_EPSILON:
		return v * (2.0 * atan2(s, dq.w) / (s * span))
	return v * (2.0 / span)


## The time-dependent cull of mover slot [param k] for the segment [param a] -> [param a] +
## [param d] widened by [param radius], after the time-free path-sphere cull (inlined in the
## callers' loops: a call per mover and query cost more than the test). Evaluates slot k at
## [param t] into the pose cache, then returns false when its shape sphere at that pose is out of
## reach.
func _in_reach_at(k: int, a: Vector3, d: Vector3, radius: float, t: float) -> bool:
	_eval_slot(k, t)
	var shape_reach: float = _mover_shape_bound[k] + MOVER_CULL_MARGIN + radius
	return _segment_point_distance_sq(a, d, _pc_pose[k].origin) <= shape_reach * shape_reach


## The mover pass of cast_ground: the nearest solid mover hit strictly nearer than
## [param best_dist] (the static hit distance, or [param max_dist] with no static hit, where a hit
## at exactly max_dist also counts). Writes _gm_* (world) and returns true when a mover wins.
func _test_ground_movers(origin: Vector3, dir: Vector3, max_dist: float, best_dist: float,
		static_hit: bool, t: float) -> bool:
	_gm_slot = -1
	_gm_dist = best_dist
	var ray: Vector3 = dir * max_dist
	var dd: float = ray.length_squared()
	for n in _solid_slots.size():
		var k: int = _solid_slots[n]
		# The time-free path-sphere cull, inlined: keep in sync with _segment_point_distance_sq.
		var reach: float = _mover_path_reach[k] + 0.0
		var ap: Vector3 = _mover_path_centre[k] - origin
		var s: float = 0.0
		if dd > 0.0:
			s = clampf(ap.dot(ray) / dd, 0.0, 1.0)
		if (ap - ray * s).length_squared() > reach * reach or not _in_reach_at(k, origin, ray, 0.0, t):
			continue
		var inv: Transform3D = _pc_inv[k]
		if not _ray_local(_movers[k], inv * origin, inv.basis * dir, _gm_dist):
			continue
		if _ray_dist < _gm_dist or (not static_hit and _gm_slot < 0):
			_gm_slot = k
			_gm_dist = _ray_dist
			_gm_normal = _pc_pose[k].basis * _ray_normal
	if _gm_slot < 0:
		return false
	_gm_velocity = _pc_lin[_gm_slot] + _ang_of(_gm_slot).cross(origin + dir * _gm_dist - _pc_pose[_gm_slot].origin)
	return true


## The mover pass of sweep_walls, over every solid mover in reach. Pass 1: the deepest overlap with
## the sphere at [param from] (into _ov_*, world space), listing each clear mover in reach in _rs_*.
## Pass 2, only when [param do_sweep] and nothing overlaps (an overlap is reported instead of any
## sweep): the first contact along [param motion] (into _sm_*, world space). Movers tie in data
## order in both passes.
# perf waiver (story 007): one function on purpose. Split into pass-1 / pass-2 helpers (and
# _sweep_local into Newton / refine helpers) it cost +7 us p95 (+2.4%) on the castle movers section
# (3 runs each: split 303 us, inline 296 us; runs/opt3-* vs runs/opt3inline-*), over the 2% limit.
func _test_movers_for_sweep(from: Vector3, motion: Vector3, radius: float, t: float, do_sweep: bool) -> void:
	_ov_slot = -1
	_ov_depth = -INF
	_rs_count = 0
	var dd: float = motion.length_squared()
	for n in _solid_slots.size():
		var k: int = _solid_slots[n]
		# The time-free path-sphere cull, inlined: keep in sync with _segment_point_distance_sq.
		var reach: float = _mover_path_reach[k] + radius
		var ap: Vector3 = _mover_path_centre[k] - from
		var s: float = 0.0
		if dd > 0.0:
			s = clampf(ap.dot(motion) / dd, 0.0, 1.0)
		if (ap - motion * s).length_squared() > reach * reach or not _in_reach_at(k, from, motion, radius, t):
			continue
		var inv: Transform3D = _pc_inv[k]
		var local_from: Vector3 = inv * from
		var gap: float = _closest_local(_movers[k], local_from) - radius
		if gap <= 0.0:
			if -gap > _ov_depth:
				_ov_slot = k
				_ov_depth = -gap
				_ov_point = _cl_point
				_ov_normal = _cl_normal
			continue
		if do_sweep and _ov_slot < 0:
			var local_motion: Vector3 = inv.basis * motion
			_rs_slot[_rs_count] = k
			_rs_from[_rs_count] = local_from
			_rs_motion[_rs_count] = local_motion
			_rs_gap[_rs_count] = gap
			_rs_slope[_rs_count] = _cl_normal.dot(local_motion)
			_rs_count += 1
	_sm_slot = -1
	_sm_fraction = INF
	if _ov_slot >= 0:
		var pose0: Transform3D = _pc_pose[_ov_slot]
		_ov_point = pose0 * _ov_point
		_ov_normal = pose0.basis * _ov_normal
		_ov_velocity = _pc_lin[_ov_slot] + _ang_of(_ov_slot).cross(_ov_point - pose0.origin)
		return
	if _rs_count == 0:
		return
	var length: float = motion.length()
	for n in _rs_count:
		var k: int = _rs_slot[n]
		if not _sweep_local(_movers[k], _rs_from[n], _rs_motion[n], length, radius, _rs_gap[n], _rs_slope[n]):
			continue
		if _sw_fraction < _sm_fraction:
			_sm_slot = k
			_sm_fraction = _sw_fraction
			_sm_point = _sw_point
			_sm_normal = _sw_normal
	if _sm_slot >= 0:
		var pose: Transform3D = _pc_pose[_sm_slot]
		_sm_point = pose * _sm_point
		_sm_normal = pose.basis * _sm_normal
		_sm_velocity = _pc_lin[_sm_slot] + _ang_of(_sm_slot).cross(_sm_point - pose.origin)


## Squared distance from [param p] to the segment [param a] -> [param a] + [param d].
static func _segment_point_distance_sq(a: Vector3, d: Vector3, p: Vector3) -> float:
	var ap: Vector3 = p - a
	var dd: float = d.length_squared()
	var s: float = 0.0
	if dd > 0.0:
		s = clampf(ap.dot(d) / dd, 0.0, 1.0)
	return (ap - d * s).length_squared()


## Signed distance from mover-local point [param p] to [param mover]'s shape (negative inside,
## 0 on the surface). Writes the nearest surface point to _cl_point and the outward unit normal
## there (from the shape toward p; for p inside, the nearest face's) to _cl_normal, mover-local.
func _closest_local(mover: MoverDef, p: Vector3) -> float:
	match mover.shape:
		MoverDef.Shape.BOX:
			return _closest_box(mover.half_extents, p)
		MoverDef.Shape.CAPSULE:
			return _closest_capsule(mover.radius, mover.half_height, p)
		_:
			# CYLINDER (layout-checked: shape is one of the three).
			return _closest_cylinder(mover.radius, mover.half_height, p)


## _closest_local for a box of half extents [param h].
func _closest_box(h: Vector3, p: Vector3) -> float:
	var q: Vector3 = p.clamp(-h, h)
	if q != p:
		var out_v: Vector3 = p - q
		var d: float = out_v.length()
		_cl_point = q
		_cl_normal = out_v / d
		return d
	# Inside or on the surface: the nearest face (ties go x, then y, then z).
	var face: Vector3 = h - p.abs()
	var axis: int = 0
	if face.y < face[axis]:
		axis = 1
	if face.z < face[axis]:
		axis = 2
	var sign_a: float = 1.0 if p[axis] >= 0.0 else -1.0
	_cl_point = p
	_cl_point[axis] = sign_a * h[axis]
	_cl_normal = Vector3.ZERO
	_cl_normal[axis] = sign_a
	return -face[axis]


## _closest_local for a capsule of radius [param r] around the segment y in [-hh, hh].
func _closest_capsule(r: float, hh: float, p: Vector3) -> float:
	var axis_point: Vector3 = Vector3(0.0, clampf(p.y, -hh, hh), 0.0)
	var v: Vector3 = p - axis_point
	var d: float = v.length()
	if d > 0.0:
		_cl_normal = v / d
	else:
		_cl_normal = Vector3.RIGHT  # on the segment itself: any direction is nearest
	_cl_point = axis_point + _cl_normal * r
	return d - r


## _closest_local for a cylinder of radius [param r], y in [-hh, hh].
func _closest_cylinder(r: float, hh: float, p: Vector3) -> float:
	var rho: float = sqrt(p.x * p.x + p.z * p.z)
	var y_out: float = absf(p.y) - hh
	if rho > r or y_out > 0.0:
		var q: Vector3 = Vector3(p.x, clampf(p.y, -hh, hh), p.z)
		if rho > r:
			q.x *= r / rho
			q.z *= r / rho
		var out_v: Vector3 = p - q
		var d: float = out_v.length()
		_cl_point = q
		_cl_normal = out_v / d
		return d
	var side: float = r - rho
	var cap: float = -y_out
	if cap <= side:
		var sign_y: float = 1.0 if p.y >= 0.0 else -1.0
		_cl_point = Vector3(p.x, sign_y * hh, p.z)
		_cl_normal = Vector3(0.0, sign_y, 0.0)
		return -cap
	var radial: Vector3 = Vector3.RIGHT
	if rho > 0.0:
		radial = Vector3(p.x / rho, 0.0, p.z / rho)
	_cl_point = Vector3(radial.x * r, p.y, radial.z * r)
	_cl_normal = radial
	return -side


## Ray [param o] + s [param d] (mover-local, d unit) against [param mover]'s shape, for
## 0 <= s <= [param max_dist]. A ray starting inside the shape misses (only front faces are hit).
## On a hit writes the entry distance to _ray_dist and the entry normal (local) to _ray_normal.
func _ray_local(mover: MoverDef, o: Vector3, d: Vector3, max_dist: float) -> bool:
	match mover.shape:
		MoverDef.Shape.BOX:
			return _ray_box(mover.half_extents, o, d, max_dist)
		MoverDef.Shape.CAPSULE:
			return _ray_capsule(mover.radius, mover.half_height, o, d, max_dist)
		_:
			return _ray_cylinder(mover.radius, mover.half_height, o, d, max_dist)


## _ray_local for a box of half extents [param h] (three slabs).
func _ray_box(h: Vector3, o: Vector3, d: Vector3, max_dist: float) -> bool:
	var t_in: float = -INF
	var t_out: float = INF
	var n_in: Vector3 = Vector3.ZERO
	for axis in 3:
		var oa: float = o[axis]
		var da: float = d[axis]
		var ha: float = h[axis]
		if absf(da) < PARALLEL_EPSILON:
			if absf(oa) > ha:
				return false
			continue
		var s_low: float = (-ha - oa) / da
		var s_high: float = (ha - oa) / da
		# Entering through the -ha face when moving +axis, through +ha when moving -axis.
		var s0: float = minf(s_low, s_high)
		if s0 > t_in:
			t_in = s0
			n_in = Vector3.ZERO
			n_in[axis] = -1.0 if da > 0.0 else 1.0
		t_out = minf(t_out, maxf(s_low, s_high))
		if t_in > t_out:
			return false
	if t_in < 0.0 or t_in > max_dist:
		return false
	_ray_dist = t_in
	_ray_normal = n_in
	return true


## _ray_local for a capsule of radius [param r] around the segment y in [-hh, hh]: the side
## (infinite cylinder, entry within the segment) or an end sphere, whichever is entered first.
func _ray_capsule(r: float, hh: float, o: Vector3, d: Vector3, max_dist: float) -> bool:
	var o_axis: Vector3 = Vector3(0.0, clampf(o.y, -hh, hh), 0.0)
	if (o - o_axis).length_squared() < r * r:
		return false
	var best: float = INF
	var best_n: Vector3 = Vector3.UP
	var a: float = d.x * d.x + d.z * d.z
	var c: float = o.x * o.x + o.z * o.z - r * r
	if a > PARALLEL_EPSILON and c >= 0.0:
		var b: float = o.x * d.x + o.z * d.z
		var disc: float = b * b - a * c
		if disc >= 0.0:
			var s: float = (-b - sqrt(disc)) / a
			if s >= 0.0 and absf(o.y + d.y * s) <= hh:
				best = s
				best_n = Vector3(o.x + d.x * s, 0.0, o.z + d.z * s) / r
	for end in 2:
		var centre: Vector3 = Vector3(0.0, hh if end == 1 else -hh, 0.0)
		var s2: float = CollisionQuery._ray_sphere(o - centre, d, r)
		if s2 < best:
			best = s2
			best_n = (o - centre + d * s2) / r
	if best > max_dist:
		return false
	_ray_dist = best
	_ray_normal = best_n
	return true


## Entry distance (>= 0) of the ray [param oc] + s [param d] (oc = origin - sphere centre, d unit)
## into a sphere of radius [param r] centred at the origin, or INF when it misses or points away.
static func _ray_sphere(oc: Vector3, d: Vector3, r: float) -> float:
	var b: float = oc.dot(d)
	var c: float = oc.length_squared() - r * r
	var disc: float = b * b - c
	if disc < 0.0 or (c > 0.0 and b > 0.0):
		return INF
	var s: float = -b - sqrt(disc)
	return s if s >= 0.0 else INF


## _ray_local for a cylinder of radius [param r], y in [-hh, hh]: the y slab intersected with the
## infinite cylinder.
func _ray_cylinder(r: float, hh: float, o: Vector3, d: Vector3, max_dist: float) -> bool:
	var t_in: float = -INF
	var t_out: float = INF
	var entry_is_cap: bool = true
	if absf(d.y) < PARALLEL_EPSILON:
		if absf(o.y) > hh:
			return false
	else:
		var s_low: float = (-hh - o.y) / d.y
		var s_high: float = (hh - o.y) / d.y
		t_in = minf(s_low, s_high)
		t_out = maxf(s_low, s_high)
	var a: float = d.x * d.x + d.z * d.z
	var c: float = o.x * o.x + o.z * o.z - r * r
	if a < PARALLEL_EPSILON:
		if c > 0.0:
			return false
	else:
		var b: float = o.x * d.x + o.z * d.z
		var disc: float = b * b - a * c
		if disc < 0.0:
			return false
		var root: float = sqrt(disc)
		if (-b - root) / a > t_in:
			t_in = (-b - root) / a
			entry_is_cap = false
		t_out = minf(t_out, (-b + root) / a)
	if t_in > t_out or t_in < 0.0 or t_in > max_dist:
		return false
	_ray_dist = t_in
	if entry_is_cap:
		_ray_normal = Vector3(0.0, 1.0 if d.y < 0.0 else -1.0, 0.0)
	else:
		_ray_normal = Vector3(o.x + d.x * t_in, 0.0, o.z + d.z * t_in) / r
	return true


## Sweeps a sphere of [param radius] from mover-local [param local_from] along [param local_motion]
## (length [param length] > 0) against [param mover], which does not overlap it at the start:
## [param gap0] = signed distance - radius at the start (> 0) and [param slope0] = its derivative per
## unit fraction there (the outward normal at the start dotted with local_motion).
## f(s) = signed distance - radius along the path is convex (the signed distance to a convex shape
## is convex) and differentiable where f > 0 (its gradient is the outward unit normal), so Newton's
## method from s = 0 never passes the first contact: each tangent root lies below the curve's
## (story 007, TD-012; it replaces story 005's golden-section search and agrees with it within
## MOVER_SWEEP_TOLERANCE: tests/unit/collision/collision_mover_sweep_equivalence_test.gd).
##   - Newton: a slope >= 0 at a clear point proves no contact ahead (convexity); so does a tangent
##     root past the end by more than the tolerance (one within it is clamped to the end). A step
##     shorter than the tolerance (near a grazing contact) becomes one tolerance step; a contact
##     that begins and ends inside such a step can be missed (the old search had the same tolerance).
##   - The first probe in contact closes a bracket; bisection refines it to the tolerance.
##   - Touch (fraction 1.0, the contact at the end) only when the end itself is in contact AND the
##     bracket reaches into the last MOVER_SWEEP_TOLERANCE of the motion (the first contact is within
##     the tolerance of the end, so the end penetrates by at most it), as the static path reports a
##     contact found at `to`. Otherwise a blocking hit at the safe fraction, also when the first
##     contact is near the end but the end itself is clear.
##   - Newton capped at _newton_cap steps without a bracket or a proof of no contact (never seen):
##     fails closed, a blocking hit at the last safe fraction, and one push_error per query object.
## On a hit writes _sw_fraction and the contact point / normal (local) and returns true.
## Deterministic: a pure function of its arguments.
# perf waiver (story 007): one function on purpose, see _test_movers_for_sweep.
func _sweep_local(mover: MoverDef, local_from: Vector3, local_motion: Vector3, length: float,
		radius: float, gap0: float, slope0: float) -> bool:
	var hi: float = NEWTON_CAPPED
	var step_min: float = MOVER_SWEEP_TOLERANCE / length
	var lo: float = 0.0
	var f: float = gap0
	var slope: float = slope0
	for _iteration in _newton_cap:
		if slope >= 0.0:
			return false
		var s: float = lo - f / slope
		if s > 1.0:
			if s - 1.0 > step_min:
				return false
			s = 1.0
		if s - lo < step_min:
			s = minf(lo + step_min, 1.0)
		var fs: float = _closest_local(mover, local_from + local_motion * s) - radius
		if fs <= 0.0:
			hi = s
			break
		if s >= 1.0:
			return false
		lo = s
		f = fs
		slope = _cl_normal.dot(local_motion)
	if hi == NEWTON_CAPPED:
		if not _cap_error_reported:
			_cap_error_reported = true
			push_error("CollisionQuery: the mover sweep reached its iteration cap against mover %d; reporting a blocking hit at the last safe fraction %s (reported once per query)" % [mover.id, lo])
		_sw_fraction = lo
		_closest_local(mover, local_from + local_motion * lo)
		_sw_point = _cl_point
		_sw_normal = _cl_normal
		return true
	var iterations: int = 0
	while (hi - lo) * length > MOVER_SWEEP_TOLERANCE and iterations < MOVER_SWEEP_MAX_ITERATIONS:
		var mid: float = (lo + hi) * 0.5
		if _closest_local(mover, local_from + local_motion * mid) - radius <= 0.0:
			hi = mid
		else:
			lo = mid
		iterations += 1
	if (1.0 - hi) * length < MOVER_SWEEP_TOLERANCE and _closest_local(mover, local_from + local_motion) - radius <= 0.0:
		_sw_fraction = 1.0
	else:
		_sw_fraction = lo
		_closest_local(mover, local_from + local_motion * lo)
	_sw_point = _cl_point
	_sw_normal = _cl_normal
	return true


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
