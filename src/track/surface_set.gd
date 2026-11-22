class_name SurfaceSet
extends Resource
## The table of surface kinds (story 011): one SurfaceType per kind, plus the look of the fence along
## a wall opening and the cap on cosmetic particles. Shipped as assets/data/surfaces/surface_set.tres;
## a TrackData may point to its own (TrackData.surface_set), otherwise TrackModel loads DEFAULT_PATH.
##
## One visual language for track features (story 011, track-features catalog #45, art bible section 4);
## each feature type looks the same on every track:
## [codeblock]
## Feature          | Look                                                        | Where it is set
## Boost pad        | cyan #22E6E0 plate, white chevron pointing along the road   | TrackTheme.pad_color_a / _b
## Trick ramp       | red-and-cream hay stripes on the wedge                      | TrackRamp.color_a / _b
## Off-road         | flat ground in the kind's colour with a BROWN speckle,      | SurfaceType ground/pattern,
##   (grass, sand,  |   low timber-and-parchment striped fence on its outer edge, |   SurfaceSet fence_*
##    mud, rubble)  |   dust / mud / gravel puffs                                 |
## Shallow water    | pale blue-cyan ground with white wave stripes, splash       | SurfaceType (shallows)
## Slick            | glossy dark blue-grey overlay on the road, slanted streaks  | SurfaceType (slick)
## Incoming hazard  | pulsing amber ember ring on the road where it strikes,      | TrackMover.warn_ring*,
##                  |   plus the gate lanterns (green / flashing amber / red)     |   color_warn
## [/codeblock]

## Resource path of the shipped set.
const DEFAULT_PATH: String = "res://assets/data/surfaces/surface_set.tres"

## One entry per kind.
@export var types: Array[SurfaceType] = []
## Height (meters) of the fence along a wall opening.
@export var fence_height: float = 0.5
## Thickness (meters) of the fence.
@export var fence_thickness: float = 0.25
## Fence colours, alternating by stripe (timber and parchment: a soft fence, not a wall).
@export var fence_color_a: Color = Color(0.62, 0.45, 0.28)
@export var fence_color_b: Color = Color(0.96, 0.92, 0.82)
## Segments per fence colour stripe.
@export var fence_stripe_segments: int = 3
## Height (meters) a zone's ground is drawn above its height (above the floor, under the road deck).
@export var ground_lift: float = 0.02
## Height (meters) an on-road overlay is drawn above the road surface.
@export var overlay_lift: float = 0.03
## Height (meters) the pattern marks are drawn above the ground.
@export var pattern_lift: float = 0.012
## Most pattern marks drawn per zone (keeps big zones cheap).
@export var pattern_max_marks: int = 2500
## Most puff particles any one kart emits at once (a cap over every SurfaceType.puff_amount).
@export var puff_max_amount: int = 14

var _by_kind: Dictionary = {}


## The SurfaceType of [param kind], or null when the set has none.
func type_of(kind: StringName) -> SurfaceType:
	if _by_kind.size() != types.size():
		_by_kind.clear()
		for t in types:
			if t != null:
				_by_kind[t.kind] = t
	return _by_kind.get(kind) as SurfaceType
