class_name QueryCursor
extends RefCounted
## The reused query objects of one caller (one kart, one projectile, one tool) for CollisionQuery
## (ADR-0002 "Reuse rules"; core-rebuild stories 003-004). Built once, passed to every query, so
## per-tick collision code allocates nothing: PhysicsRayQueryParameters3D.create() and the
## Dictionary query forms are forbidden in per-tick code.
##
## Story 003 added the ray objects used by cast_ground. Story 004 added the shape-query parameters,
## the cast and rest results and the SphereShape3D used by sweep_walls. The sphere is this cursor's
## own, so karts with different radii never share one; sweep_walls only writes its radius when the
## radius passed in differs from the current one.
## Not thread-safe: a cursor belongs to one caller on the main thread; never share one between two
## callers that interleave queries.
## [codeblock]
## var cursor: QueryCursor = QueryCursor.new()   # once per kart, at setup
## var ground: GroundHit = GroundHit.new()
## var wall: WallHit = WallHit.new()
## query.cast_ground(cursor, origin, Vector3.DOWN, max_drop, t, ground)
## query.sweep_walls(cursor, from, to, stats.radius, t, wall)
## [/codeblock]

## Ray parameters, reused. CollisionQuery sets from and to on every cast; collision_mask
## (CollisionQuery.GROUND_LAYER) and the flags are fixed here once (ground rays never hit back faces,
## ADR-0002 Geometry layout; story 007 moved the mask here from every cast). Never change them.
var ray_params: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.new()
## Ray result, reused. Only valid right after a cast that returned true (a miss leaves the
## previous hit's values in it).
var ray_result: PhysicsIntersectRayResult3D = PhysicsIntersectRayResult3D.new()
## The sweep sphere, reused. sweep_walls sets its radius (only when it changes).
var sphere: SphereShape3D = SphereShape3D.new()
## Shape-query parameters for sweep_walls, reused. Its shape is [member sphere] and its
## collision_mask CollisionQuery.WALL_LAYER (both set once here; never change them); CollisionQuery
## sets transform on every sweep and motion only around its cast, resetting it to zero right
## after, so motion is zero between calls (story 007: sweep_walls relies on it). margin stays 0.
var shape_params: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
## Cast result, reused. Every cast_motion_into writes it (a clear cast writes 1.0 / 1.0).
var cast_result: PhysicsCastMotionResult3D = PhysicsCastMotionResult3D.new()
## Rest-info result, reused. Only valid right after a rest check that returned true.
var rest_result: PhysicsGetRestInfoResult3D = PhysicsGetRestInfoResult3D.new()


func _init() -> void:
	ray_params.collision_mask = CollisionQuery.GROUND_LAYER
	ray_params.hit_back_faces = false
	ray_params.hit_from_inside = false
	ray_params.collide_with_areas = false
	ray_params.collide_with_bodies = true
	shape_params.shape = sphere
	shape_params.collision_mask = CollisionQuery.WALL_LAYER
	shape_params.margin = 0.0
	shape_params.collide_with_areas = false
	shape_params.collide_with_bodies = true
