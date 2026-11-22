extends SceneTree
## Triangle dump for the generator-baked test mesh (core-rebuild story 008). DEBUG TOOL, not game
## code. Retired at A3 with the bake (story 065).
##
## Bakes one track from the extractor's JSON (tools/legacy_test_bake.gd, no frozen game) and prints
## every ground triangle whose XZ footprint comes within --r= m of the point (--x=, --z=): its index,
## vertices and surface id, plus whether the point lies inside it in XZ. It then casts straight down
## through checked_query at the point and prints the hit.
##
## Run:
##   godot --headless --path . -s res://tools/legacy_bake_tri_dump.gd -- --track=castle_circuit --x=28.2 --z=108.5 [--r=1.0]
## [codeblock]
## # tri 51234 (28.1, 0.13, 108.4) (28.9, 0.13, 108.5) (28.3, 0.12, 109.3) id 0 contains
## # cast from y 10.00: hit (28.2, 0.131, 108.5) surface 0
## [/codeblock]

const Bake = preload("res://tools/legacy_test_bake.gd")
const DEFAULT_RADIUS: float = 1.0
## Cast start height (m) and length (m) of the downward probe.
const CAST_FROM_Y: float = 10.0
const CAST_LENGTH: float = 20.0


func _initialize() -> void:
	var track: String = "castle_circuit"
	var p: Vector2 = Vector2.ZERO
	var r: float = DEFAULT_RADIUS
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--track="):
			track = arg.substr(8)
		elif arg.begins_with("--x="):
			p.x = float(arg.substr(4))
		elif arg.begins_with("--z="):
			p.y = float(arg.substr(4))
		elif arg.begins_with("--r="):
			r = float(arg.substr(4))
	var surfaces: SurfaceSet = SurfaceSet.load_checked(SurfaceSet.CORE_PATH)
	var walls: WallAttrSet = WallAttrSet.load_checked(WallAttrSet.CORE_PATH)
	var baked: Bake.BakeResult = Bake.bake_doc(Bake.load_doc("res://build/legacy_tracks/%s.json" % track), surfaces, walls)
	if not baked.problem.is_empty():
		print("FAIL bake: %s" % baked.problem)
		quit(1)
		return
	var gf: PackedVector3Array = baked.data.ground_faces
	var n: int = 0
	for i in range(0, gf.size(), 3):
		var a: Vector2 = Vector2(gf[i].x, gf[i].z)
		var b: Vector2 = Vector2(gf[i + 1].x, gf[i + 1].z)
		var c: Vector2 = Vector2(gf[i + 2].x, gf[i + 2].z)
		var near: bool = Geometry2D.point_is_inside_triangle(p, a, b, c)
		for e in [[a, b], [b, c], [c, a]]:
			if p.distance_to(Geometry2D.get_closest_point_to_segment(p, e[0], e[1])) <= r:
				near = true
		if not near:
			continue
		@warning_ignore("integer_division")
		var tri: int = i / 3
		print("tri %d %s %s %s id %d%s" % [tri, gf[i], gf[i + 1], gf[i + 2], baked.data.surface_of_face[tri],
				" contains" if Geometry2D.point_is_inside_triangle(p, a, b, c) else ""])
		n += 1
	print("%d triangles within %.2f m of %s" % [n, r, p])
	var checked: CollisionBootCheck.CheckedQuery = CollisionBootCheck.checked_query(baked.data, surfaces, walls, Bake.PROBE_MAX_DROP)
	if not checked.problem.is_empty():
		print("FAIL checked_query: %s" % checked.problem)
		quit(1)
		return
	var hit: GroundHit = GroundHit.new()
	if checked.query.cast_ground(QueryCursor.new(), Vector3(p.x, CAST_FROM_Y, p.y), Vector3.DOWN, CAST_LENGTH, 0.0, hit):
		print("cast from y %.2f: hit %s surface %d" % [CAST_FROM_Y, hit.point, hit.surface_id])
	else:
		print("cast from y %.2f: no hit" % CAST_FROM_Y)
	checked.query.dispose()
	quit(0)
