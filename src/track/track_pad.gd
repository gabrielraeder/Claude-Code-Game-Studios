class_name TrackPad
extends Resource
## A boost pad lying on a road. Driving over it gives the kart a boost of
## TrackData.boost_pad_time seconds through the normal boost mechanism (KartSim.boost_time).
## Implements design/references/track-design-reference.md section 6 ("Boost pads").

## Road the pad lies on: empty = the main road, otherwise a TrackBranch id.
@export var road: StringName = &""
## Meters along that road (on the main road this is main-loop distance).
@export var distance: float = 0.0
## Sideways offset of the pad center from that road's centerline (TrackModel normal side positive).
@export var lateral: float = 0.0
## Pad size along the road, in meters.
@export var length: float = 6.0
## Pad size across the road, in meters.
@export var width: float = 3.0
