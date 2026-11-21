class_name TrackSurface
extends Resource
## One surface zone on a track: a polygon of drivable terrain (grass, sand, mud, rubble, shallows)
## beside the road, reached through a TrackWallOpening, or an on-road patch (slick). What the zone
## does to a kart comes from the SurfaceType of [member kind] in the track's SurfaceSet.
## Implements story 011 (design/references/track-features-catalog.md features 1-4 and 45).

## Identifier (for logs and debug).
@export var id: StringName = &""
## Kind: grass, sand, mud, rubble, shallows or slick (a SurfaceType.kind of the SurfaceSet).
@export var kind: StringName = &"grass"
## Closed outline as (x, z) points.
@export var polygon: PackedVector2Array = PackedVector2Array()
## Height (Y, meters) of the zone's ground. A kart touches the zone only when its own height is within
## TrackData.surface_height_tolerance of it, and a kart on the zone is held up at this height. An
## on-road patch (SurfaceType.on_road) is drawn on the road at the road's own height instead.
@export var height: float = 0.0
## Draw a low fence along the edges of this zone that do not touch the road (the zone's outer boundary).
@export var fence: bool = true
