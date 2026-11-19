class_name TrackMesh
extends Node3D
## Builds the visible track (road, curbs, start line, walls) from a TrackModel.
## Presentation only: collision is done by lateral clamping in KartSim.

const ROAD_COLOR: Color = Color(0.22, 0.22, 0.25)
const CURB_RED: Color = Color(0.85, 0.15, 0.15)
const CURB_WHITE: Color = Color(0.95, 0.95, 0.95)
const WALL_LIGHT: Color = Color(0.75, 0.75, 0.78)
const WALL_DARK: Color = Color(0.6, 0.6, 0.65)
const LINE_WHITE: Color = Color.WHITE
const LINE_BLACK: Color = Color(0.05, 0.05, 0.05)
const WALL_HEIGHT: float = 0.9
const START_LINE_CELLS: int = 10
const START_LINE_ROWS: int = 2
const CURB_STRIPE_SEGMENTS: int = 2
const WALL_STRIPE_SEGMENTS: int = 4


## Creates the meshes for [param track] as children of this node.
func build(track: TrackModel) -> void:
	var half: float = track.data.road_half_width
	var wall: float = track.wall_offset
	var pts: PackedVector2Array = track.points
	var n: int = pts.size()
	var normals: Array[Vector2] = []
	for i in n:
		var t: Vector2 = (pts[(i + 1) % n] - pts[(i - 1 + n) % n]).normalized()
		normals.append(Vector2(-t.y, t.x))

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in n:
		var j: int = (i + 1) % n
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[j]
		var na: Vector2 = normals[i]
		var nb: Vector2 = normals[j]
		_quad(st, a + na * half, a - na * half, b - nb * half, b + nb * half, 0.0, ROAD_COLOR)
		var curb: Color = CURB_RED if ((i / CURB_STRIPE_SEGMENTS) % 2) == 0 else CURB_WHITE
		_quad(st, a + na * wall, a + na * half, b + nb * half, b + nb * wall, 0.01, curb)
		_quad(st, a - na * half, a - na * wall, b - nb * wall, b - nb * half, 0.01, curb)
	# Start/finish line at s = 0.
	var t0: Vector2 = track.tangent_at(0.0)
	var n0: Vector2 = track.normal_at(0.0)
	var cell_w: float = 2.0 * half / START_LINE_CELLS
	for r in START_LINE_ROWS:
		for c in START_LINE_CELLS:
			var w0: float = -half + c * cell_w
			var w1: float = w0 + cell_w
			var d0: float = -1.0 + r
			var d1: float = d0 + 1.0
			var col: Color = LINE_WHITE if (r + c) % 2 == 0 else LINE_BLACK
			_quad(st, pts[0] + n0 * w0 + t0 * d0, pts[0] + n0 * w1 + t0 * d0,
					pts[0] + n0 * w1 + t0 * d1, pts[0] + n0 * w0 + t0 * d1, 0.02, col)
	add_child(_instance(st.commit()))

	var ws := SurfaceTool.new()
	ws.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in n:
		var j: int = (i + 1) % n
		for side in [1.0, -1.0]:
			var a: Vector2 = pts[i] + normals[i] * wall * side
			var b: Vector2 = pts[j] + normals[j] * wall * side
			ws.set_normal(_v3(-normals[i] * side, 0.0))
			ws.set_color(WALL_LIGHT if ((i / WALL_STRIPE_SEGMENTS) % 2) == 0 else WALL_DARK)
			ws.add_vertex(_v3(a, 0.0))
			ws.add_vertex(_v3(b, 0.0))
			ws.add_vertex(_v3(b, WALL_HEIGHT))
			ws.add_vertex(_v3(a, 0.0))
			ws.add_vertex(_v3(b, WALL_HEIGHT))
			ws.add_vertex(_v3(a, WALL_HEIGHT))
	add_child(_instance(ws.commit()))


func _instance(mesh: Mesh) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	return mi


func _v3(p: Vector2, y: float) -> Vector3:
	return Vector3(p.x, y, p.y)


func _quad(st: SurfaceTool, a: Vector2, b: Vector2, c: Vector2, d: Vector2, y: float, col: Color) -> void:
	st.set_color(col)
	st.set_normal(Vector3.UP)
	st.add_vertex(_v3(a, y))
	st.add_vertex(_v3(b, y))
	st.add_vertex(_v3(c, y))
	st.add_vertex(_v3(a, y))
	st.add_vertex(_v3(c, y))
	st.add_vertex(_v3(d, y))
