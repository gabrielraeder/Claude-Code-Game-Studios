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
## Optional height (Y, meters) of each polygon point (same count as [member polygon]); inside, the
## ground is the linear blend over the zone's triangles. Lets a zone beside a climbing or banked
## road meet the curb without a step (story 011 part 2). Empty = flat at [member height].
@export var heights: PackedFloat32Array = PackedFloat32Array()
## Main-loop distance (meters) where a drive across this zone starts: a kart leaving the road here
## and heading for the road point at [member route_to] crosses the zone (story 011 part 2: a boost-cut
## or the moat ford). Negative = the zone is no route (plain off-road beside the road).
@export var route_from: float = -1.0
## Main-loop distance (meters) of the road point the route across the zone heads for.
@export var route_to: float = -1.0
## Optional waypoints (x, z) across the zone, in driving order, for a route that is no straight line
## (the moat ford): the autopilot heads for each in turn, then for the road point at [member route_to].
@export var route_via: PackedVector2Array = PackedVector2Array()
## True: the route is a boost-cut, shorter than the road but slower without a boost (the speed cap);
## a bot takes it only with boost time left and a liking for shortcuts (BotPersonality).
@export var boost_cut: bool = false
## Draw a low fence along the edges of this zone that do not touch the road (the zone's outer boundary).
@export var fence: bool = true
