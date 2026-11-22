@tool
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
## Resource path of the core rebuild's set (core-rebuild story 002): every type has a stable id
## (SurfaceType.id). The frozen game never reads it; the core loads it with load_checked().
const CORE_PATH: String = "res://assets/data/core/surface_set.tres"

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

## Largest surface id: ids travel as a u8 on the ADR-0006 wire (ADR-0002). A format limit, not
## tuning.
const MAX_ID: int = 255
## The handling fields a neutral type keeps at the SurfaceType defaults (Track Collision GDD 3.2.2;
## ADR-0002: the load check asserts that neutral types hold the field defaults).
const NEUTRAL_FIELDS: Array[StringName] = [
	&"max_speed_frac", &"drag", &"grip_mult", &"steer_mult", &"drift_allowed", &"surface_decel",
	&"boost_ignores", &"tail_time", &"bump_yaw", &"bump_cycles_per_m", &"bump_height",
]

## Index kind -> type. load_checked() builds it once; on a set it did not load, type_of() builds it
## on first use.
var _by_kind: Dictionary[StringName, SurfaceType] = {}


## The SurfaceType of [param kind], or null when the set has none.
## Thread safety: on a set returned by load_checked() the index is already built, so this only
## reads and is safe from any thread. On any other set (the frozen game's) the first call builds
## the index: single-thread only.
## [codeblock]
## var mud: SurfaceType = surfaces.type_of(&"mud")
## [/codeblock]
func type_of(kind: StringName) -> SurfaceType:
	if _by_kind.size() != types.size():
		_by_kind.clear()
		for t in types:
			if t != null:
				_by_kind[t.kind] = t
	return _by_kind.get(kind) as SurfaceType


## Loads the SurfaceSet at [param path] for the core rebuild, checks it (ADR-0002) and builds its
## kind index. Returns null, after a push_error naming the path and the problem, when: the path has
## no resource; it is not a SurfaceSet; a type is null; a kind is empty or repeated; an id is
## outside 0..MAX_ID or repeated; or a neutral type has a NEUTRAL_FIELDS value other than the
## SurfaceType default. The frozen game never calls it (its set has no ids).
## Thread safety: call it once, on one thread, before the set is shared (it writes the index of
## the cached resource the first time). The returned set is shared through the resource cache:
## treat it as read-only.
## [codeblock]
## var surfaces: SurfaceSet = SurfaceSet.load_checked(SurfaceSet.CORE_PATH)
## if surfaces == null:
##     return  # the registry is broken: refuse to load the track
## var road_id: int = surfaces.type_of(&"road").id  # 0
## [/codeblock]
static func load_checked(path: String) -> SurfaceSet:
	if not ResourceLoader.exists(path):
		push_error("SurfaceSet.load_checked: %s not found" % path)
		return null
	var loaded: SurfaceSet = load(path) as SurfaceSet
	if loaded == null:
		push_error("SurfaceSet.load_checked: %s is not a SurfaceSet" % path)
		return null
	var by_kind: Dictionary[StringName, SurfaceType] = {}
	var seen_ids: Dictionary[int, bool] = {}
	var defaults: SurfaceType = null
	for i in loaded.types.size():
		var t: SurfaceType = loaded.types[i]
		if t == null:
			push_error("SurfaceSet.load_checked: %s has a null type at index %d" % [path, i])
			return null
		if t.kind.is_empty():
			push_error("SurfaceSet.load_checked: %s has a type with an empty kind at index %d" % [path, i])
			return null
		if by_kind.has(t.kind):
			push_error("SurfaceSet.load_checked: %s repeats kind %s" % [path, t.kind])
			return null
		if t.id < 0 or t.id > MAX_ID:
			push_error("SurfaceSet.load_checked: %s type %s has id %d, outside 0..%d" % [path, t.kind, t.id, MAX_ID])
			return null
		if seen_ids.has(t.id):
			push_error("SurfaceSet.load_checked: %s repeats surface id %d (%s)" % [path, t.id, t.kind])
			return null
		if t.neutral:
			if defaults == null:
				defaults = SurfaceType.new()
			for field in NEUTRAL_FIELDS:
				if t.get(field) != defaults.get(field):
					push_error("SurfaceSet.load_checked: %s neutral type %s has %s = %s, not the default %s"
							% [path, t.kind, field, t.get(field), defaults.get(field)])
					return null
		by_kind[t.kind] = t
		seen_ids[t.id] = true
	if loaded._by_kind.size() != loaded.types.size():
		loaded._by_kind = by_kind
	return loaded
