class_name TrackWallOpening
extends Resource
## A stretch of the main road where the wall is absent on one side, so a kart can leave the road
## there onto a surface zone (story 011). The opening only removes the wall: the zone polygons beside
## it are the drivable ground, a kart that is off the road in an opening is held inside them
## (TrackModel.zone_escape) and a low fence is drawn along the zone edges that do not touch the road.

## Main-loop distance (meters) where the opening starts (0 <= s_from <= s_to <= track length).
@export var s_from: float = 0.0
## Main-loop distance (meters) where it ends.
@export var s_to: float = 0.0
## +1 = the normal side of TrackModel, -1 = the other.
@export var side: int = 1
## How far (meters) beyond the curb the wall is absent. Must reach past the farthest edge of the zones.
@export var depth: float = 40.0
