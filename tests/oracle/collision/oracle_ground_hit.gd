class_name GroundHit
extends RefCounted
## The result of one CollisionQuery.cast_ground (ADR-0002 "Queries per kart per tick"; core-rebuild
## stories 003, 005). The caller allocates one per probe once (usually inside its QueryCursor's owner) and
## reuses it every tick: cast_ground writes the fields only when it returns true, and leaves them
## untouched on a miss.
## Not thread-safe: one GroundHit belongs to one caller on the main thread.
## [codeblock]
## var hit: GroundHit = GroundHit.new()        # once, at setup
## if query.cast_ground(cursor, origin, Vector3.DOWN, max_drop, t, hit):
##     var floor_y: float = hit.point.y
##     var surface_id: int = hit.surface_id  # Driving & Drift looks the SurfaceType up by id
## [/codeblock]

## World position of the hit.
var point: Vector3 = Vector3.ZERO
## Surface normal at the hit (unit length, facing the ray: ground rays never hit back faces).
var normal: Vector3 = Vector3.UP
## Stable surface id (SurfaceType.id) of the triangle hit, or CollisionQuery.SURFACE_NONE when the
## face index is unavailable (the face-index project setting is off; the load check catches it).
## For a mover hit (collider_id >= 1) it is that mover's MoverDef.surface_id.
var surface_id: int = CollisionQuery.SURFACE_NONE
## 0 = static ground; otherwise the id (>= 1) of the mover hit (MoverDef.id). Never Jolt's
## collider_id.
var collider_id: int = 0
## Velocity of the collider at the hit point (zero for static ground; for a mover,
## CollisionQuery.mover_point_velocity(collider_id, t, point)). Informational: a kart riding a mover
## is carried by the mover's pose delta (story 021, ADR-0003), not by integrating this.
var collider_velocity: Vector3 = Vector3.ZERO


## Resets every field to its default (a miss-like state). Allocation-free.
## [codeblock]
## hit.clear()
## [/codeblock]
func clear() -> void:
	point = Vector3.ZERO
	normal = Vector3.UP
	surface_id = CollisionQuery.SURFACE_NONE
	collider_id = 0
	collider_velocity = Vector3.ZERO
