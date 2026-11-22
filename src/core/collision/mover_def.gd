@tool
class_name MoverDef
extends Resource
## One moving collider of a track (ADR-0002 "Moving colliders"; schema only in core-rebuild story
## 003, evaluated by CollisionQuery.mover_pose / mover_point_velocity in story 005). A mover is not a
## Jolt body: it is a primitive shape on a keyframed pose curve, looped over [member period], so its
## pose is a pure function of time. Serialised as a sub-resource of TrackCollisionData (.res).
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
## data.movers.append(gate)
## [/codeblock]

## Primitive shape of a mover. Capsule and cylinder axes run along Godot local +Y.
enum Shape { BOX, CAPSULE, CYLINDER }

## Mover id, >= 1 for a valid mover (0 always means static geometry; 0 here = not set).
@export var id: int = 0
## Loop length of the pose curve, seconds (> 0 for a valid mover).
@export var period: float = 0.0
## False: a non-solid mover (for example a rolling barrel: a spin, no push). cast_ground and
## sweep_walls skip it; only Track Hazards test it, through mover_pose.
@export var solid: bool = true
## Primitive shape.
@export var shape: Shape = Shape.BOX
## Half extents of a BOX, Godot local axes, metres.
@export var half_extents: Vector3 = Vector3.ZERO
## Radius of a CAPSULE or CYLINDER, metres.
@export var radius: float = 0.0
## Half-length of the SEGMENT of a CAPSULE or CYLINDER, metres (Godot's CapsuleShape3D.height is the
## total height, not this).
@export var half_height: float = 0.0
## Key times, seconds, ascending, within [0, period).
@export var key_t: PackedFloat32Array = PackedFloat32Array()
## Key positions (piecewise linear between keys), one per key time.
@export var key_pos: PackedVector3Array = PackedVector3Array()
## Key rotations as quaternions (x, y, z, w; slerp between keys), one per key time.
@export var key_rot: PackedVector4Array = PackedVector4Array()
