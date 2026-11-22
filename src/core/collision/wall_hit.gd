class_name WallHit
extends RefCounted
## The result of one CollisionQuery.sweep_walls (ADR-0002 "Queries per kart per tick"; core-rebuild
## story 004). The caller allocates one per kart once and reuses it every tick: sweep_walls writes
## every field when it returns true, and leaves them untouched on a miss.
##
## Three kinds of hit, told apart by fraction and started_inside:
##   - started_inside = true, fraction = 0: the sphere already overlapped a wall at `from`; no cast
##     ran, and point / normal / wall_attr come from that overlap. The caller pushes out and sweeps
##     again (ADR-0003 section 6).
##   - started_inside = false, fraction = 1.0: a touch. The move completes; the sphere ends in
##     contact with the wall at `to`. The caller does not slide (ADR-0003 touch rule).
##   - started_inside = false, 0 <= fraction < 1: a blocking hit. The sphere can move fraction x the
##     motion without touching; point / normal are the first contact.
## Not thread-safe: one WallHit belongs to one caller on the main thread.
## [codeblock]
## var hit: WallHit = WallHit.new()            # once, at setup
## if query.sweep_walls(cursor, from, to, radius, t, hit):
##     if hit.started_inside:
##         pass  # push out along hit.normal, then sweep again
##     elif hit.fraction == 1.0:
##         pass  # touch: keep the full move, no slide
##     else:
##         var safe_move: Vector3 = (to - from) * hit.fraction
## [/codeblock]

## World position of the contact, on the wall surface.
var point: Vector3 = Vector3.ZERO
## Contact normal (unit length), pointing from the wall toward the sphere centre. Walls are
## one-sided, so it is the wall's front side for a flat wall; at an edge it points from the edge.
## Unreliable when the sphere centre lies exactly on the wall plane: the rest normal is then not the
## wall's (probe_adr3_rest.txt A, centre on the plane: (0, -1, 0) for a +X wall). In normal driving
## this is unreachable, because walls are one-sided and a centre that reached the plane has already
## been reported from the front. It is also unreliable when wall_attr is WALL_ATTR_NONE.
var normal: Vector3 = Vector3.ZERO
## Stable wall-attribute id (WallAttr.id) of the wall hit: TrackCollisionData.wall_attr_ids of the
## wall shape hit, or CollisionQuery.WALL_ATTR_NONE (-1) when the engine gave no usable contact.
## WALL_ATTR_NONE means "use the default wall attribute"; the normal is unreliable then (it is the
## reverse of the motion, not the wall normal). Never a shape index or a WallAttrSet array index.
var wall_attr: int = CollisionQuery.WALL_ATTR_NONE
## Fraction (0..1) of the motion from -> to the sphere can travel before the contact: 0 when
## started_inside, 1.0 for a touch, otherwise the engine's safe fraction.
## A touch (fraction 1.0) does not guarantee zero depth: the sphere at `to` may overlap the wall
## slightly. A blocking hit can have fraction 0 with started_inside false (a sphere a hair in front
## of a wall, moving into it), so callers branch on started_inside, never on fraction == 0.
var fraction: float = 1.0
## True when the sphere already overlapped a wall at `from` (no cast ran).
var started_inside: bool = false
## 0 = static wall; otherwise the id (>= 1) of the mover hit (movers: story 005). Never Jolt's
## collider_id.
var collider_id: int = 0
## Velocity of the collider at the contact point (zero for static walls).
var collider_velocity: Vector3 = Vector3.ZERO


## Resets every field to its default (a miss-like state: no wall, full move). Allocation-free.
## [codeblock]
## hit.clear()
## [/codeblock]
func clear() -> void:
	point = Vector3.ZERO
	normal = Vector3.ZERO
	wall_attr = CollisionQuery.WALL_ATTR_NONE
	fraction = 1.0
	started_inside = false
	collider_id = 0
	collider_velocity = Vector3.ZERO
