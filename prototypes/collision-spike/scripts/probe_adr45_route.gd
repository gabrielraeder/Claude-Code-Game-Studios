## PROTOTYPE - NOT FOR PRODUCTION. ADR-0004 probe: stand-in for CourseRoute (non-@tool on purpose).
class_name Adr45Route
extends Resource

@export var id: StringName = &""
@export var kind: StringName = &""
@export var closed: bool = false
@export var length: float = 0.0
@export var pos: PackedVector3Array = PackedVector3Array()
@export var half_left: PackedFloat32Array = PackedFloat32Array()
@export var edge_flags: PackedInt32Array = PackedInt32Array()

## instance method, for the NV-7 probe (called from an @tool post-import script)
func total_half() -> float:
	var s: float = 0.0
	for v: float in half_left:
		s += v
	return s
