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
## Half the branch road width in meters.
@export var half_width: float = 2.5
## Rail or wall thickness in meters; the wall stands at half_width + curb_width.
@export var curb_width: float = 0.3
## Multiplies wall drag on this road (rough stone that grinds a kart sliding along it > 1).
@export var wall_drag_mult: float = 1.0
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
