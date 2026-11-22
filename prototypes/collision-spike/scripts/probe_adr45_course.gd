## PROTOTYPE - NOT FOR PRODUCTION. ADR-0004 probe: stand-in for CourseData (non-@tool on purpose).
class_name Adr45Course
extends Resource

@export var format_version: int = 1
@export var lap_length: float = 0.0
@export var gate_xform: Array[Transform3D] = []
@export var gate_half: PackedVector2Array = PackedVector2Array()
@export var gate_group: PackedInt32Array = PackedInt32Array()
@export var gate_s: PackedFloat32Array = PackedFloat32Array()
@export var routes: Array[Adr45Route] = []
@export var stats: Dictionary = {}
## not exported: shows whether a plain var is stored (it should not be)
var plain_not_exported: int = 0

func gate_count() -> int:
	return gate_xform.size()

func route_half_sum() -> float:
	var s: float = 0.0
	for r: Adr45Route in routes:
		s += r.total_half()
	return s

## builds a deterministic fixture
static func make_fixture() -> Adr45Course:
	var c := Adr45Course.new()
	c.lap_length = 1234.5678
	for i: int in 8:
		var b := Basis(Vector3.UP, 0.3 * i).rotated(Vector3.RIGHT, 0.01 * i)
		c.gate_xform.append(Transform3D(b, Vector3(1999.987 - i * 0.001, 12.3456 + i, -1999.123 + i * 17.25)))
		c.gate_half.append(Vector2(7.0 + i * 0.1, 3.0))
		c.gate_group.append(i / 2)
		c.gate_s.append(i * 154.321)
	for k: int in 2:
		var r := Adr45Route.new()
		r.id = StringName("route_%d" % k)
		r.kind = &"main" if k == 0 else &"branch"
		r.closed = k == 0
		r.length = 999.75 + k
		for i: int in 1000:
			r.pos.append(Vector3(1999.9 - i * 0.37, sin(i * 0.1) * 3.0, -1999.9 + i * 0.731))
			r.half_left.append(6.5 + 0.001 * i)
			r.edge_flags.append(i % 16)
		c.routes.append(r)
	c.stats = {"tris_ground": 154000, "tris_walls": 3000}
	c.plain_not_exported = 42
	return c
