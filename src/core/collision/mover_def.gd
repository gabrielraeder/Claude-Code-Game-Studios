@tool
class_name MoverDef
extends Resource
## One moving collider of a track (ADR-0002 "Moving colliders"; schema in core-rebuild story 003,
## evaluated by CollisionQuery.mover_pose / mover_point_velocity and tested by cast_ground /
## sweep_walls from story 005). A mover is not a Jolt body: it is a primitive shape centred on the
## origin of a keyframed pose curve, looped over [member period], so its pose is a pure function of
## time. Serialised as a sub-resource of TrackCollisionData (.res).
## A kart riding a mover is carried by the pose delta between ticks (story 021, ADR-0003), not by
## integrating the hit's collider_velocity.
## Plain data: read-only after load, safe to read from any thread.
## [codeblock]
## var gate: MoverDef = MoverDef.new()
## gate.id = 1
## gate.shape = MoverDef.Shape.BOX
## gate.half_extents = Vector3(2.0, 1.0, 0.25)
## gate.period = 4.0
## gate.key_t = PackedFloat32Array([0.0, 2.0])
## gate.key_pos = PackedVector3Array([Vector3.ZERO, Vector3(0.0, 2.0, 0.0)])
## gate.key_rot = PackedVector4Array([Vector4(0, 0, 0, 1), Vector4(0, 0, 0, 1)])
## assert(gate.layout_error().is_empty())
## data.movers.append(gate)
## [/codeblock]

## Primitive shape of a mover. Capsule and cylinder axes run along Godot local +Y.
enum Shape { BOX, CAPSULE, CYLINDER }

## Fewest keys a mover may have (Track Collision GDD 4.4: key_t has >= 2 keys). A format rule, not
## tuning.
const MIN_KEYS: int = 2
## Largest |q|^2 - 1 a key rotation may have to count as a unit quaternion (float32 keys normalise
## to ~1e-7). A numerical tolerance, not tuning.
const UNIT_QUAT_TOLERANCE: float = 0.00001

## Schema version of pack_native(); the native CollisionQuery asserts the same number
## (CollisionQuery.PACKED_SCHEMA_VERSION). A format number, not tuning.
const NATIVE_SCHEMA_VERSION: int = 1

## Largest mover id: the native CollisionQuery stores ids as int32 (CollisionQuery.MAX_MOVER_ID). A format
## limit, not tuning.
const MAX_MOVER_ID: int = 2147483647

## Mover id, >= 1 for a valid mover (0 always means static geometry; 0 here = not set).
@export var id: int = 0
## Loop length of the pose curve, seconds (> 0 for a valid mover).
@export var period: float = 0.0
## False: a non-solid mover (for example a rolling barrel: a spin, no push). cast_ground and
## sweep_walls skip it; only Track Hazards test it, through mover_pose.
@export var solid: bool = true
## Stable surface id (SurfaceType.id, 0..SurfaceSet.MAX_ID) a ground hit on this mover reports.
## Default 0 = road. The load check (story 006) tests it against the SurfaceSet.
@export var surface_id: int = 0
## Stable wall-attribute id (WallAttr.id, 0..WallAttrSet.MAX_ID) a wall sweep hit on this mover
## reports. Default 0 = standard. The load check (story 006) tests it against the WallAttrSet.
@export var wall_attr_id: int = 0
## Primitive shape, centred on the pose origin.
@export var shape: Shape = Shape.BOX
## Half extents of a BOX, Godot local axes, metres.
@export var half_extents: Vector3 = Vector3.ZERO
## Radius of a CAPSULE or CYLINDER, metres.
@export var radius: float = 0.0
## Half-length of the SEGMENT of a CAPSULE or CYLINDER, metres (Godot's CapsuleShape3D.height is the
## total height, not this).
@export var half_height: float = 0.0
## Key times, seconds, strictly ascending, within [0, period). After the last key the curve runs
## back to the first key, reached again at key_t[0] + period (the loop segment).
@export var key_t: PackedFloat32Array = PackedFloat32Array()
## Key positions (piecewise linear between keys), one per key time; finite.
@export var key_pos: PackedVector3Array = PackedVector3Array()
## Key rotations as unit quaternions (x, y, z, w; shortest-path slerp between keys), one per key
## time.
@export var key_rot: PackedVector4Array = PackedVector4Array()


## Checks this mover's own layout (ADR-0002 Geometry layout; Track Collision GDD 4.4; story 003
## review). Returns "" when sound, otherwise one sentence naming the first problem: id < 1;
## id above MAX_MOVER_ID (2147483647); period not > 0 or not finite; surface_id or wall_attr_id outside 0..255 (their registry
## membership is the story 006 load check); shape not BOX / CAPSULE / CYLINDER; extents invalid for
## the shape (BOX: every half extent > 0; CAPSULE: radius > 0 and half_height >= 0, 0 being a
## sphere; CYLINDER: radius > 0 and half_height > 0); key arrays of different lengths or fewer than
## MIN_KEYS keys; key_t not strictly ascending within [0, period); a key_pos not finite; a key_rot
## not a unit quaternion (within UNIT_QUAT_TOLERANCE). Id uniqueness across movers is checked by
## TrackCollisionData.layout_error(). Reads only; safe from any thread.
## [codeblock]
## var problem: String = mover.layout_error()
## if not problem.is_empty():
##     push_error("mover %d: %s" % [mover.id, problem])
## [/codeblock]
func layout_error() -> String:
	if id < 1:
		return "id is %d (mover ids are >= 1; 0 means static geometry)" % id
	if id > MAX_MOVER_ID:
		return "id is %d (mover ids are <= %d, the native int32 limit)" % [id, MAX_MOVER_ID]
	if not (period > 0.0) or not is_finite(period):
		return "period is %s (must be > 0)" % period
	if surface_id < 0 or surface_id > SurfaceSet.MAX_ID:
		return "surface_id is %d, outside 0..%d" % [surface_id, SurfaceSet.MAX_ID]
	if wall_attr_id < 0 or wall_attr_id > WallAttrSet.MAX_ID:
		return "wall_attr_id is %d, outside 0..%d" % [wall_attr_id, WallAttrSet.MAX_ID]
	var problem: String = _shape_error()
	if not problem.is_empty():
		return problem
	return _key_error()


## A NEW MoverDef: this mover reflected through the plane x = 0 (ADR-0001 section 7, ADR-0002
## "Mirror"; story 005 LP review; called by TrackCollisionData.mirrored()). Every pose basis B
## becomes M.B.M with M = diag(-1, 1, 1), so the mirrored pose is still a rotation and its sense
## flips: key positions x -> -x, key rotations (x, y, z, w) -> (x, -y, -z, w). Every other field is
## copied unchanged: id, period, solid, surface_id, wall_attr_id, shape, half_extents, radius,
## half_height and key_t (each primitive is symmetric about its local x = 0 plane, so its extents
## hold in the mirrored local frame). The key arrays are new arrays; this object is never mutated.
## A new @export field must be added here, and to the property walk of
## tests/unit/collision/collision_load_and_mirror_test.gd, which fails on a field it does not know.
## Load time only (allocates). Reads only; safe from any thread.
## [codeblock]
## var right_gate: MoverDef = gate.mirrored()
## assert(right_gate.key_pos[0].x == -gate.key_pos[0].x)
## assert(right_gate != gate)  # a new sub-resource, never the cached one
## [/codeblock]
func mirrored() -> MoverDef:
	var out: MoverDef = MoverDef.new()
	out.id = id
	out.period = period
	out.solid = solid
	out.surface_id = surface_id
	out.wall_attr_id = wall_attr_id
	out.shape = shape
	out.half_extents = half_extents
	out.radius = radius
	out.half_height = half_height
	out.key_t = key_t.duplicate()
	var pos: PackedVector3Array = PackedVector3Array()
	pos.resize(key_pos.size())
	for i in key_pos.size():
		var p: Vector3 = key_pos[i]
		pos[i] = Vector3(-p.x, p.y, p.z)
	out.key_pos = pos
	var rot: PackedVector4Array = PackedVector4Array()
	rot.resize(key_rot.size())
	for i in key_rot.size():
		var q: Vector4 = key_rot[i]
		rot[i] = Vector4(q.x, -q.y, -q.z, q.w)
	out.key_rot = rot
	return out


## The plain data the native CollisionQuery consumes (ADR-0007 section 2: native code never reads a
## script property). A Dictionary of fixed keys, in this order: schema_version (int), id (int),
## period (float, s), solid (bool), surface_id (int), wall_attr_id (int), shape (int: 0 BOX, 1 CAPSULE,
## 2 CYLINDER), half_extents (Vector3, m), radius (float, m), half_height (float, m), key_t
## (PackedFloat32Array, s), key_pos (PackedVector3Array, m), key_rot (PackedVector4Array, unit
## quaternions x, y, z, w). The arrays are shared copy-on-write, not copied. Load time only. A new
## @export field is added here, in the native validation and in tests/unit/collision/pack_native_test.gd.
## [codeblock]
## var packed: Dictionary = mover.pack_native()
## [/codeblock]
func pack_native() -> Dictionary:
	return {
		"schema_version": NATIVE_SCHEMA_VERSION,
		"id": id,
		"period": period,
		"solid": solid,
		"surface_id": surface_id,
		"wall_attr_id": wall_attr_id,
		"shape": int(shape),
		"half_extents": half_extents,
		"radius": radius,
		"half_height": half_height,
		"key_t": key_t,
		"key_pos": key_pos,
		"key_rot": key_rot,
	}


## The shape part of layout_error(): "" or the first problem with the shape value or its extents.
func _shape_error() -> String:
	match shape:
		Shape.BOX:
			if not (half_extents.x > 0.0 and half_extents.y > 0.0 and half_extents.z > 0.0):
				return "BOX half_extents %s must all be > 0" % half_extents
		Shape.CAPSULE:
			if not (radius > 0.0 and half_height >= 0.0):
				return "CAPSULE needs radius > 0 and half_height >= 0 (radius %s, half_height %s)" % [radius, half_height]
		Shape.CYLINDER:
			if not (radius > 0.0 and half_height > 0.0):
				return "CYLINDER needs radius > 0 and half_height > 0 (radius %s, half_height %s)" % [radius, half_height]
		_:
			return "shape %d is not BOX, CAPSULE or CYLINDER" % shape
	return ""


## The key part of layout_error(): "" or the first problem with the key arrays.
func _key_error() -> String:
	var n: int = key_t.size()
	if key_pos.size() != n or key_rot.size() != n:
		return "key arrays differ in length (key_t %d, key_pos %d, key_rot %d)" % [n, key_pos.size(), key_rot.size()]
	if n < MIN_KEYS:
		return "has %d keys (at least %d)" % [n, MIN_KEYS]
	if not (key_t[0] >= 0.0):
		return "key_t[0] is %s (key times lie in [0, period))" % key_t[0]
	for i in range(1, n):
		if not (key_t[i] > key_t[i - 1]):
			return "key_t[%d] = %s is not after key_t[%d] = %s (key times strictly ascend)" % [i, key_t[i], i - 1, key_t[i - 1]]
	if not (key_t[n - 1] < period):
		return "key_t[%d] = %s is not before period %s (key times lie in [0, period))" % [n - 1, key_t[n - 1], period]
	for i in n:
		if not key_pos[i].is_finite():
			return "key_pos[%d] = %s is not finite" % [i, key_pos[i]]
		if not (absf(key_rot[i].length_squared() - 1.0) < UNIT_QUAT_TOLERANCE):
			return "key_rot[%d] = %s is not a unit quaternion" % [i, key_rot[i]]
	return ""
