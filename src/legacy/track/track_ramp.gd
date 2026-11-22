class_name TrackRamp
extends Resource
## A jump ramp lying on a road (story 008): a wedge that rises from the road surface at
## [member distance] to [member lip_height] at the lip, [member length] meters further on, then
## drops straight back to the road. A kart that drives over the lip faster than the road falls
## away leaves the ground (KartSim, VehicleStats air_*). TrackModel adds the wedge to the road
## height and slope; TrackMesh draws it.
## Implements design/game-brief.md, Features item 4 (tracks: jumps).

## Road the ramp lies on: empty = the main road, otherwise a TrackBranch id.
@export var road: StringName = &""
## Meters along that road where the wedge starts (on the main road this is main-loop distance).
@export var distance: float = 0.0
## Length of the rising wedge in meters (start to lip).
@export var length: float = 9.0
## Height of the lip above the road in meters. The launch angle is atan(lip_height / length).
@export var lip_height: float = 1.6
## Sideways offset of the ramp center from the road's centerline (TrackModel normal side positive).
@export var lateral: float = 0.0
## Half the ramp width in meters; 0 = the whole road including the curbs (wall to wall).
@export var half_width: float = 0.0
## Top surface colors (alternating stripes) and the side and lip faces. Story 011 visual language:
## every trick ramp is red-and-cream hay stripes (track-features catalog #45); the sides may take the
## track's stone.
@export var color_a: Color = Color(0.78, 0.25, 0.17)
@export var color_b: Color = Color(0.96, 0.92, 0.82)
@export var side_color: Color = Color(0.4, 0.26, 0.14)
## Stripes across the top surface.
@export var stripes: int = 6
