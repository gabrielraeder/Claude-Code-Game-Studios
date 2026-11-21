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
## Main-road edges with no wall: one (s_from, s_to, side) per stretch, where side +1 is
## TrackModel's normal side and -1 the other. The kart can leave the road there: over a hazard it
## sinks; over a drop (a raised road, story 008) it falls and is put back (fall_respawn_*).
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

@export_group("Elevation")
## Road height (Y, meters) of the centerline at each control point. Empty = flat at 0. Must
## have one entry per control point when set. Interpolated with the same Catmull-Rom parameter
## as the centerline (story 008).
@export var heights: PackedFloat32Array = PackedFloat32Array()
## Bank (roll) in degrees at each control point. Positive = banked into a LEFT turn: the road's
## normal side (TrackModel.Query.lateral > 0, the driver's right) is the high side, so the
## surface height is centerline + lateral * tan(bank). Negative = banked into a right turn
## (on a left bend that is off-camber). Empty = flat. One entry per control point when set.
@export var banks: PackedFloat32Array = PackedFloat32Array()
## Y of the world floor (the ground plane) and the level the support columns reach down to.
@export var ground_y: float = -0.05
## Distance (meters along the road) between support columns under raised road.
@export var pillar_spacing: float = 12.0
## Half the side of a square support column in meters.
@export var pillar_half_width: float = 0.7
## Road further than this above the ground (meters) gets support columns.
@export var pillar_min_height: float = 1.0
## Color of the support columns.
@export var pillar_color: Color = Color(0.45, 0.42, 0.4)
## Thickness (meters) of a raised road deck: the underside and edge faces drawn under road that
## is more than pillar_min_height above the ground, so a bridge reads as solid from below.
@export var deck_thickness: float = 0.6
## Color of the deck underside and edge faces.
@export var deck_under_color: Color = Color(0.36, 0.33, 0.31)

@export_group("Jumps and falls (story 008)")
## Jump ramps on the roads. See TrackRamp.
@export var ramps: Array[TrackRamp] = []
## Roads stacked closer than this in height (meters) are told apart by height: a query with the
## kart's height picks the road whose surface is within this of it (a bridge over a road), and
## no support column of an upper road stands in a road this far below it.
@export var level_separation: float = 3.0
## A kart off the road (past an open edge over a drop) that is this many meters below the road
## surface beside it has fallen off the track: it is put back like a hazard respawn.
@export var fall_respawn_depth: float = 2.5
## ... or that has been in the air off the road this many seconds.
@export var fall_respawn_time: float = 1.2
## Seconds between falling off the track and being put back on the road (the kart keeps falling
## meanwhile). The respawn itself uses respawn_back_off, respawn_speed_frac, respawn_immunity_time.
@export var fall_respawn_delay: float = 0.8

@export_group("Height-aware track objects (story 008 part 3)")
## A kart sinks in a hazard only when its height is at most the hazard's surface_height plus this
## (meters): one on a bridge or in the air over the water stays dry until it falls in.
@export var hazard_sink_margin: float = 0.3
## A boost pad fires only for a grounded kart within this many meters (height) of the road at the
## pad's center: not for one on a bridge above it or a road below it.
@export var pad_height_tolerance: float = 2.0
