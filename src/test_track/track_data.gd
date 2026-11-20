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
## Half the road width in meters (used where [member half_widths] is empty).
@export var road_half_width: float = 7.0
## Half road width per control point in meters, interpolated along the spline. Empty = the
## constant [member road_half_width]. Must have one entry per control point when set.
@export var half_widths: PackedFloat32Array = PackedFloat32Array()
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
## Open hazard areas (moat water). See TrackHazard.
@export var hazards: Array[TrackHazard] = []
## Boost pads on the roads. See TrackPad.
@export var boost_pads: Array[TrackPad] = []
## Main-road edges with no wall, over a hazard: one (s_from, s_to, side) per stretch, where side
## +1 is TrackModel's normal side and -1 the other. The kart can leave the road there.
@export var open_edges: PackedVector3Array = PackedVector3Array()
## How far (meters) beyond the curb an open edge lets a kart go before the corridor clamps it.
@export var open_edge_reach: float = 6.0
## Seconds a kart sinks in a hazard before it is put back on the road.
@export var respawn_sink_time: float = 1.0
## Speed after a respawn as a share of the kart's max_speed (user notes 01-veiculos-e-fisica.md
## 7.4: back at 30 mph of a 115 mph top speed).
@export var respawn_speed_frac: float = 0.26
## Seconds of hit immunity after a respawn (same note: 3 s).
@export var respawn_immunity_time: float = 3.0
## The kart reappears this many meters behind the last safe point it drove.
@export var respawn_back_off: float = 4.0
## Seconds of boost a boost pad gives (like a drift tier 2 boost).
@export var boost_pad_time: float = 1.1
## Largest change of track_s per meter actually moved (keeps progress smooth at junctions).
@export var progress_rate_cap: float = 1.95
