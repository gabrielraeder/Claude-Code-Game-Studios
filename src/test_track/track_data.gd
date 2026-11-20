class_name TrackData
extends Resource
## Data describing a looping track: the whole interface a track must provide.
## One closed main road plus optional shortcut branches, a look (theme) and item-box spots.
## Implements design/game-brief.md, Features items 1 and 4.

## Short identifier, also sent over the network so every PC loads the same track.
@export var track_id: StringName = &"test_loop"
## Name shown to players.
@export var display_name: String = "Test Loop"
## Look of the track; null falls back to the plain default TrackTheme.
@export var theme: TrackTheme
## Shortcut branches (open side roads that leave and rejoin the main loop).
@export var branches: Array[TrackBranch] = []
## Checkpoints around the main loop; a lap counts only when all were passed in order.
@export var checkpoint_count: int = 8
## Item-box spots: x = main-loop distance in meters, y = sideways offset. Data only (story 004).
@export var item_box_spots: PackedVector2Array = PackedVector2Array()
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
## When two roads overlap, a kart switches road only if the other centerline is this much
## closer (meters), so it does not flicker at a junction.
@export var branch_switch_margin: float = 0.75
## A kart stays on its current road while it is more than this far (meters) inside that
## road's wall, so following the main road past a branch entrance never captures it; nearer
## the wall, the nearest centerline decides (that is how a kart steers into a shortcut).
@export var road_keep_band: float = 1.5
## Largest change of track_s per meter actually moved (keeps progress smooth at junctions).
@export var progress_rate_cap: float = 1.95
