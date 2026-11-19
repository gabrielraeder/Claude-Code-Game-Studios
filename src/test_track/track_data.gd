class_name TrackData
extends Resource
## Data describing a looping track: the whole interface a track must provide.
## Story 003 replaces the test loop by supplying other TrackData resources.
## Implements design/game-brief.md, Features item 1 (flat test loop).

## Closed centerline control points as (x, z); a Catmull-Rom spline runs through them.
@export var control_points: PackedVector2Array = PackedVector2Array()
## Spline samples generated between two control points.
@export var samples_per_segment: int = 20
## Half the road width in meters.
@export var road_half_width: float = 7.0
## Curb width in meters; the wall stands at road_half_width + curb_width.
@export var curb_width: float = 1.2
## Laps in a race on this track.
@export var lap_count: int = 3
## How far behind the start line (meters along the track) the kart starts.
@export var start_distance_behind_line: float = 6.0
## How many centerline samples either side of the last position a query searches.
@export var query_window: int = 14
