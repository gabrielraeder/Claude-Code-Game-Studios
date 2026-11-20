class_name TrackHazard
extends Resource
## An open hazard area on a track (moat water, later lava). A kart whose center is inside
## [member polygon] and not on any road surface sinks and is put back on the road (KartSim).
## Roads that cross the area (a bridge deck) stay safe: only the off-road part is a hazard.
## Implements story 003 ("open edges with respawn") and design/references/track-design-reference.md section 6.

## Identifier (for logs and debug).
@export var id: StringName = &""
## Kind of hazard: water (moat), later lava. Picks the look in TrackMesh.
@export var kind: StringName = &"water"
## Closed outline as (x, z) points.
@export var polygon: PackedVector2Array = PackedVector2Array()
