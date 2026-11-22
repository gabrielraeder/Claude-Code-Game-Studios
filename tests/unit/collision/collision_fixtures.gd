extends RefCounted
## Fixtures for the core-rebuild story 003 (ground) and story 004 (walls) collision tests. Everything is built in code: no file
## I/O, no randomness. Preload it from a test:
## [codeblock]
## const Fixtures = preload("res://tests/unit/collision/collision_fixtures.gd")
## var data: TrackCollisionData = Fixtures.one_triangle_per_kind(Fixtures.non_contiguous_registry())
## [/codeblock]

## Kinds of the non-contiguous fixture registry, in registry (array) order.
const REGISTRY_KINDS: Array[StringName] = [
	&"grass", &"sand", &"road", &"mud", &"rubble", &"shallows", &"slick", &"boost_pad", &"trick_ramp",
]
## Ids of the fixture registry, parallel to REGISTRY_KINDS. Non-contiguous, and no id equals its
## array index or the face index its triangle gets in one_triangle_per_kind (faces run in reverse
## registry order).
const REGISTRY_IDS: Array[int] = [7, 3, 0, 42, 12, 6, 200, 9, 1]
## Leg length (m) of each fixture ground triangle.
const TRI_LEG: float = 4.0
## Distance (m) along +X between the fixture triangles' corners.
const TRI_SPACING: float = 10.0
## Height (m) above the ground the downward casts start from.
const CAST_HEIGHT: float = 5.0
## Length (m) of the downward casts.
const CAST_LENGTH: float = 10.0
## Half-size (m) of each quadrant of the probe-majority ground (quadrants span 0..2 m from the
## origin on each axis).
const QUADRANT_SIZE: float = 2.0
## Wheel probe points of the probe-majority fixture, in probe order (front-left, front-right,
## rear-left, rear-right; Godot forward is -Z). Offsets are asymmetric (0.5 m, 0.7 m) so no probe lies
## on a quad diagonal.
const PROBE_POINTS: Array[Vector3] = [
	Vector3(-0.5, 0.0, -0.7), Vector3(0.5, 0.0, -0.7), Vector3(-0.5, 0.0, 0.7), Vector3(0.5, 0.0, 0.7),
]
## Bike probes (2), in probe order: front, rear. Both sit in the left column (x < 0), so the front
## probe lands on quadrant 0 (front-left) and the rear probe on quadrant 2 (rear-left).
const BIKE_PROBE_POINTS: Array[Vector3] = [Vector3(-0.5, 0.0, -0.7), Vector3(-0.5, 0.0, 0.7)]
## Kart centre of mass off-centre toward the front-right probe: planar squared distances to the
## probes are FL 0.85, FR 0.05, RL 2.25, RR 1.45, so "nearest CoM" (FR) and "lowest index" (FL)
## disagree.
const COM_NEAR_FRONT_RIGHT: Vector3 = Vector3(0.4, 0.0, -0.5)
## Kart centre of mass at the centre of the four probes: all four are at the same planar distance.
const COM_CENTRE: Vector3 = Vector3(0.0, 0.0, 0.0)
## Bike centre of mass toward the rear probe (planar distance 0.4 rear, 1.0 front).
const COM_BIKE_NEAR_REAR: Vector3 = Vector3(-0.5, 0.0, 0.3)
## Bike centre of mass midway between its probes (both at planar distance 0.7).
const COM_BIKE_MIDWAY: Vector3 = Vector3(-0.5, 0.0, 0.0)
## Where the degenerate (zero-area) fixture triangles sit: far from every probe.
const DEGENERATE_AT: Vector3 = Vector3(50.0, 0.0, 50.0)
## Surface id written for the degenerate triangles (trick_ramp's fixture id): never a quadrant's.
const DEGENERATE_SURFACE_ID: int = 1
## Height (m) of the "wall top" triangle of the layer fixture, above the ground at y = 0.
const WALL_TOP_Y: float = 1.0
## Wall-attribute ids of the fixture walls (non-contiguous on purpose).
const WALL_ATTR_IDS: Array[int] = [5, 2]
## Names of the fixture wall registry (story 004), in registry (array) order.
const WALL_REGISTRY_NAMES: Array[StringName] = [&"standard", &"rough", &"stone"]
## Ids parallel to WALL_REGISTRY_NAMES: non-contiguous, and none equals its registry index or the
## shape index its wall gets in attr_walls.
const WALL_REGISTRY_IDS: Array[int] = [4, 17, 9]
## Wall shape order of attr_walls: shape k is the wall named WALL_SHAPE_ORDER[k] (rough is shape 0,
## registry index 1, id 17; stone shape 1, index 2, id 9; standard shape 2, index 0, id 4).
const WALL_SHAPE_ORDER: Array[StringName] = [&"rough", &"stone", &"standard"]
## Sweep sphere radius (m) of the wall tests (the cart's radius, ADR-0003).
const SWEEP_RADIUS: float = 1.0
## Height (m) of the fixture walls (from y = 0).
const WALL_HEIGHT: float = 4.0
## Height (m) of the sweep centre in the wall tests: mid-wall, far from the top and bottom edges.
const SWEEP_Y: float = 2.0
## Length (m) of each attr_walls wall along Z, and of each inner_corner wall.
const WALL_LENGTH: float = 10.0
## Distance (m) along Z between the starts of the attr_walls walls (gaps keep them apart).
const WALL_SPACING: float = 20.0


## A SurfaceSet built in code with the kinds of REGISTRY_KINDS and the ids of REGISTRY_IDS.
static func non_contiguous_registry() -> SurfaceSet:
	var surfaces: SurfaceSet = SurfaceSet.new()
	for i in REGISTRY_KINDS.size():
		var t: SurfaceType = SurfaceType.new()
		t.kind = REGISTRY_KINDS[i]
		t.id = REGISTRY_IDS[i]
		surfaces.types.append(t)
	return surfaces


## Registry index of the kind on fixture triangle [param face] of one_triangle_per_kind (faces run
## in reverse registry order, so face index, registry index and id all differ).
static func registry_index_of_face(face: int) -> int:
	return REGISTRY_KINDS.size() - 1 - face


## Ground with ONE up-facing triangle per kind of [param surfaces], face k carrying the id of
## registry entry registry_index_of_face(k). Triangle k has its right-angle corner at
## (k * TRI_SPACING, 0, 0) and legs TRI_LEG along +X and +Z.
static func one_triangle_per_kind(surfaces: SurfaceSet) -> TrackCollisionData:
	var data: TrackCollisionData = TrackCollisionData.new()
	var faces: PackedVector3Array = PackedVector3Array()
	var ids: PackedInt32Array = PackedInt32Array()
	for k in surfaces.types.size():
		var x0: float = k * TRI_SPACING
		# Godot-front winding: the front of (a, b, c) faces along (c - a) x (b - a) = +Y here.
		faces.append(Vector3(x0, 0.0, 0.0))
		faces.append(Vector3(x0 + TRI_LEG, 0.0, 0.0))
		faces.append(Vector3(x0, 0.0, TRI_LEG))
		ids.append(surfaces.types[registry_index_of_face(k)].id)
	data.ground_faces = faces
	data.surface_of_face = ids
	return data


## Centroid of fixture triangle [param face] of one_triangle_per_kind.
static func triangle_centroid(face: int) -> Vector3:
	return Vector3(face * TRI_SPACING + TRI_LEG / 3.0, 0.0, TRI_LEG / 3.0)


## A flat ground at y = 0 split into four quadrants around the origin, one surface id each, in probe
## order: [param ids][0] front-left (x < 0, z < 0), [1] front-right (x > 0, z < 0), [2] rear-left
## (x < 0, z > 0), [3] rear-right (x > 0, z > 0). Each quadrant is one quad (two triangles).
static func quadrant_ground(ids: Array[int]) -> TrackCollisionData:
	var data: TrackCollisionData = TrackCollisionData.new()
	var faces: PackedVector3Array = PackedVector3Array()
	var surface_ids: PackedInt32Array = PackedInt32Array()
	var x_ranges: Array[Vector2] = [Vector2(-QUADRANT_SIZE, 0.0), Vector2(0.0, QUADRANT_SIZE)]
	var z_ranges: Array[Vector2] = [Vector2(-QUADRANT_SIZE, 0.0), Vector2(0.0, QUADRANT_SIZE)]
	for q in 4:
		var xr: Vector2 = x_ranges[q % 2]
		@warning_ignore("integer_division")
		var zr: Vector2 = z_ranges[q / 2]
		_append_up_quad(faces, xr.x, xr.y, zr.x, zr.y)
		surface_ids.append(ids[q])
		surface_ids.append(ids[q])
	data.ground_faces = faces
	data.surface_of_face = surface_ids
	return data


## A Bike ground: [param front] under the front probe (quadrants 0 and 1), [param rear] under the
## rear probe (quadrants 2 and 3).
static func bike_ground(front: int, rear: int) -> TrackCollisionData:
	return quadrant_ground([front, front, rear, rear])


## quadrant_ground with a degenerate (zero-area, repeated-vertex) triangle inserted at face index 0
## and another at face index 5 (after quadrant 1's two triangles), each with DEGENERATE_SURFACE_ID
## (Track Collision GDD E-18; ADR-0002 Verified 1: face_index keeps set_faces() order). If the
## face indices were renumbered around them, every probe would read a neighbour's id.
static func quadrant_ground_with_degenerates(ids: Array[int]) -> TrackCollisionData:
	var clean: TrackCollisionData = quadrant_ground(ids)
	var data: TrackCollisionData = TrackCollisionData.new()
	var faces: PackedVector3Array = PackedVector3Array()
	var surface_ids: PackedInt32Array = PackedInt32Array()
	var degenerate: PackedVector3Array = PackedVector3Array([DEGENERATE_AT, DEGENERATE_AT, DEGENERATE_AT + Vector3.RIGHT])
	for tri in clean.ground_triangle_count():
		if tri == 0 or tri == 4:
			faces.append_array(degenerate)
			surface_ids.append(DEGENERATE_SURFACE_ID)
		faces.append_array(clean.ground_faces.slice(tri * 3, tri * 3 + 3))
		surface_ids.append(clean.surface_of_face[tri])
	data.ground_faces = faces
	data.surface_of_face = surface_ids
	return data


## quadrant_ground plus two wall shapes (WALL_ATTR_IDS): shape 0 an up-facing "wall top" quad at
## WALL_TOP_Y covering the whole ground, shape 1 a vertical quad facing +X at x = -QUADRANT_SIZE.
## A ground ray from above must pass the wall top and hit the ground (walls are layer 2).
static func ground_with_walls(ids: Array[int]) -> TrackCollisionData:
	var data: TrackCollisionData = quadrant_ground(ids)
	var top: PackedVector3Array = PackedVector3Array()
	_append_up_quad(top, -QUADRANT_SIZE, QUADRANT_SIZE, -QUADRANT_SIZE, QUADRANT_SIZE)
	for i in top.size():
		top[i].y = WALL_TOP_Y
	var side: PackedVector3Array = PackedVector3Array()
	var x: float = -QUADRANT_SIZE
	var a: Vector3 = Vector3(x, 0.0, -QUADRANT_SIZE)
	var b: Vector3 = Vector3(x, WALL_TOP_Y, -QUADRANT_SIZE)
	var c: Vector3 = Vector3(x, 0.0, QUADRANT_SIZE)
	var d: Vector3 = Vector3(x, WALL_TOP_Y, QUADRANT_SIZE)
	# (c - a) x (b - a) = (0,0,2Q) x (0,H,0) = (-2QH, 0, 0): faces -X, so swap b and c for +X.
	side.append_array([a, c, b, c, d, b])
	data.wall_faces = [top, side]
	data.wall_attr_ids = PackedInt32Array(WALL_ATTR_IDS)
	return data


## A WallAttrSet built in code with the names of WALL_REGISTRY_NAMES and the ids of
## WALL_REGISTRY_IDS.
static func wall_registry() -> WallAttrSet:
	var walls: WallAttrSet = WallAttrSet.new()
	for i in WALL_REGISTRY_NAMES.size():
		var a: WallAttr = WallAttr.new()
		a.name = WALL_REGISTRY_NAMES[i]
		a.id = WALL_REGISTRY_IDS[i]
		walls.attrs.append(a)
	return walls


## Walls only (no ground): one vertical wall per WALL_SHAPE_ORDER entry, all in the plane x = 0
## facing +X, from y = 0 to WALL_HEIGHT. Wall shape k spans z in [k * WALL_SPACING,
## k * WALL_SPACING + WALL_LENGTH] and carries the id [param walls] gives its name (a wall_<name>
## material mapped through the registry, as the importer does).
static func attr_walls(walls: WallAttrSet) -> TrackCollisionData:
	var data: TrackCollisionData = TrackCollisionData.new()
	var shapes: Array[PackedVector3Array] = []
	var ids: PackedInt32Array = PackedInt32Array()
	for k in WALL_SHAPE_ORDER.size():
		var z0: float = k * WALL_SPACING
		var faces: PackedVector3Array = PackedVector3Array()
		_append_wall_quad(faces, Vector3(0.0, 0.0, z0), Vector3(0.0, 0.0, z0 + WALL_LENGTH), WALL_HEIGHT, Vector3.RIGHT)
		shapes.append(faces)
		ids.append(walls.attr_of(WALL_SHAPE_ORDER[k]).id)
	data.wall_faces = shapes
	data.wall_attr_ids = ids
	return data


## Z of the middle of wall shape [param k] of attr_walls.
static func wall_centre_z(k: int) -> float:
	return k * WALL_SPACING + WALL_LENGTH / 2.0


## An inner corner at the origin, walls only: shape 0 the plane x = 0 facing +X for z in
## [0, WALL_LENGTH] (rough), shape 1 the plane z = 0 facing +Z for x in [0, WALL_LENGTH] (stone).
## The drivable side is x > 0, z > 0.
static func inner_corner(walls: WallAttrSet) -> TrackCollisionData:
	var data: TrackCollisionData = TrackCollisionData.new()
	var x_wall: PackedVector3Array = PackedVector3Array()
	_append_wall_quad(x_wall, Vector3.ZERO, Vector3(0.0, 0.0, WALL_LENGTH), WALL_HEIGHT, Vector3.RIGHT)
	var z_wall: PackedVector3Array = PackedVector3Array()
	_append_wall_quad(z_wall, Vector3.ZERO, Vector3(WALL_LENGTH, 0.0, 0.0), WALL_HEIGHT, Vector3.BACK)
	data.wall_faces = [x_wall, z_wall]
	data.wall_attr_ids = PackedInt32Array([walls.attr_of(&"rough").id, walls.attr_of(&"stone").id])
	return data


## quadrant_ground plus ONE wall shape (id WALL_ATTR_IDS[0]): the plane x = -QUADRANT_SIZE facing
## +X for z in [-QUADRANT_SIZE, QUADRANT_SIZE], from the ground (y = 0) up to WALL_HEIGHT: a
## floor/wall corner along the wall's foot.
static func ground_and_side_wall(ids: Array[int]) -> TrackCollisionData:
	var data: TrackCollisionData = quadrant_ground(ids)
	var side: PackedVector3Array = PackedVector3Array()
	_append_wall_quad(side, Vector3(-QUADRANT_SIZE, 0.0, -QUADRANT_SIZE), Vector3(-QUADRANT_SIZE, 0.0, QUADRANT_SIZE),
			WALL_HEIGHT, Vector3.RIGHT)
	data.wall_faces = [side]
	data.wall_attr_ids = PackedInt32Array([WALL_ATTR_IDS[0]])
	return data


## Appends a vertical wall quad (two triangles) with bottom edge [param bottom0] -> [param bottom1],
## [param height] tall, whose front side faces [param facing] (Godot-front winding chosen per
## triangle, so the caller never hand-orders vertices).
static func _append_wall_quad(faces: PackedVector3Array, bottom0: Vector3, bottom1: Vector3, height: float, facing: Vector3) -> void:
	var top0: Vector3 = bottom0 + Vector3.UP * height
	var top1: Vector3 = bottom1 + Vector3.UP * height
	_append_facing_triangle(faces, bottom0, bottom1, top0, facing)
	_append_facing_triangle(faces, bottom1, top1, top0, facing)


## Appends triangle (a, b, c), or (a, c, b), whichever has its Godot front ((c - a) x (b - a))
## along [param facing].
static func _append_facing_triangle(faces: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3, facing: Vector3) -> void:
	if (c - a).cross(b - a).dot(facing) > 0.0:
		faces.append_array([a, b, c])
	else:
		faces.append_array([a, c, b])


## Appends an up-facing quad over [x0, x1] x [z0, z1] at y = 0 as two Godot-front triangles.
static func _append_up_quad(faces: PackedVector3Array, x0: float, x1: float, z0: float, z1: float) -> void:
	faces.append_array([Vector3(x0, 0.0, z0), Vector3(x1, 0.0, z0), Vector3(x0, 0.0, z1)])
	faces.append_array([Vector3(x1, 0.0, z0), Vector3(x1, 0.0, z1), Vector3(x0, 0.0, z1)])
