class_name QueryCursor
extends RefCounted
## The reused query objects of one caller (one kart, one projectile, one tool) for CollisionQuery
## (ADR-0002 "Reuse rules"; core-rebuild story 003). Built once, passed to every query, so per-tick
## collision code allocates nothing: PhysicsRayQueryParameters3D.create() and the Dictionary query
## forms are forbidden in per-tick code.
##
## Story 003 holds the ray objects used by cast_ground. Story 004 adds the shape-query parameters,
## the cast and rest results and the SphereShape3D used by sweep_walls.
## Not thread-safe: a cursor belongs to one caller on the main thread; never share one between two
## callers that interleave queries.
## [codeblock]
## var cursor: QueryCursor = QueryCursor.new()   # once per kart, at setup
## var hit: GroundHit = GroundHit.new()
## query.cast_ground(cursor, origin, Vector3.DOWN, max_drop, t, hit)
## [/codeblock]

## Ray parameters, reused. CollisionQuery sets from, to and collision_mask on every cast; the flags
## below are fixed here once (ground rays never hit back faces, ADR-0002 Geometry layout).
var ray_params: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.new()
## Ray result, reused. Only valid right after a cast that returned true (a miss leaves the
## previous hit's values in it).
var ray_result: PhysicsIntersectRayResult3D = PhysicsIntersectRayResult3D.new()


func _init() -> void:
	ray_params.hit_back_faces = false
	ray_params.hit_from_inside = false
	ray_params.collide_with_areas = false
	ray_params.collide_with_bodies = true
