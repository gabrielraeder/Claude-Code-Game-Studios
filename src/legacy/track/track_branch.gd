class_name TrackBranch
extends Resource
## A shortcut branch: its own open centerline that leaves the main road at main-loop distance
## [member s_in] and rejoins it at [member s_out]. Progress on a branch maps linearly onto
## [s_in, s_out], so a shorter branch advances track_s faster per meter driven.
## Implements design/game-brief.md, Features item 4 (shortcuts that cost skill).

## Identifier used by --shortcut= and by drivers (for example "drawbridge").
@export var id: StringName = &""
## Kind of shortcut: drawbridge, secret_passage, later mine_rail, lava_jump.
@export var type: StringName = &""
## Open centerline control points as (x, z). The first and last are snapped onto the main
## centerline at s_in and s_out by TrackModel, whatever is written here.
@export var control_points: PackedVector2Array = PackedVector2Array()
## Half the branch road width in meters (used where [member half_widths] is empty).
@export var half_width: float = 2.5
## Half width per control point, interpolated; empty = the constant [member half_width].
@export var half_widths: PackedFloat32Array = PackedFloat32Array()
## Greater than 0 makes both edges open (no rails, a plank bridge over water): the corridor
## reaches this far beyond the deck and the off-deck part must lie in a TrackHazard.
@export var open_edge_reach: float = 0.0
## True for a covered corridor (the secret passage): TrackScenery puts a dark roof over it.
@export var roofed: bool = false
## Rail or wall thickness in meters; the wall stands at half_width + curb_width.
@export var curb_width: float = 0.3
## Multiplies wall drag on this road (rough stone that grinds a kart sliding along it > 1).
@export var wall_drag_mult: float = 1.0
## Floor drag multiplier (rough mine-cart sleepers). Above 1 the kart's top speed on this road
## is divided by it unless it is boosting (boost keeps its full speed). 1 = smooth.
@export var floor_drag_mult: float = 1.0
## Mine rail (story 009): sideways offset in meters of the cart's rails from the road centerline
## (left positive, like TrackModel.Query.lateral). The ore cart rides there; the rest of the road
## is the lane karts pass it in.
@export var rail_lane: float = 0.0
## Main-loop distance where the branch leaves the main road.
@export var s_in: float = 0.0
## Main-loop distance where the branch rejoins the main road (greater than s_in).
@export var s_out: float = 0.0
## Spline samples between two control points.
@export var samples_per_segment: int = 12
## Plank or floor colors (alternating per segment).
@export var deck_color: Color = Color(0.55, 0.36, 0.2)
@export var deck_alt_color: Color = Color(0.46, 0.29, 0.16)
## Rail or wall colors (alternating) and height in meters.
@export var wall_color: Color = Color(0.4, 0.26, 0.14)
@export var wall_alt_color: Color = Color(0.5, 0.33, 0.18)
@export var wall_height: float = 0.6
## Fills the area between this branch and the main road it bypasses (the moat). Alpha 0 = none.
@export var fill_color: Color = Color(0, 0, 0, 0)
## True to build a stone arch at both ends.
@export var arch_ends: bool = false
## Road height (Y, meters) at each control point. Empty = the height follows the main road,
## blending smoothly from its height at s_in to its height at s_out. When set, the first and
## last entries are replaced by the main road's height at s_in and s_out (story 008).
@export var heights: PackedFloat32Array = PackedFloat32Array()
## Bank in degrees at each control point (same sign as TrackData.banks). Empty = blends from the
## main road's bank at s_in to its bank at s_out. The first and last entries are replaced like heights.
@export var banks: PackedFloat32Array = PackedFloat32Array()
