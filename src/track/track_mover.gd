class_name TrackMover
extends Resource
## One timed moving hazard described in data (story 009): a drawbridge deck that rises and
## lowers, later rolling barrels, a portcullis, lava bursts, a mine cart. Everything about it is a
## pure function of the synced race time (see HazardManager), so every PC agrees without messages.
## Implements production/epics/dogworks-racing-kennel-kingdom/story-009-moving-hazards.md.

## Identifier (logs, signal lookup).
@export var id: StringName = &""
## Kind: gate (a road section that is blocked while active: drawbridge, portcullis), barrel and
## cart (move along a road), burst (a footprint that is dangerous while active).
@export var kind: StringName = &"gate"

@export_group("Schedule")
## Length of one cycle in seconds. 0 = always active (no schedule).
@export var period: float = 20.0
## Seconds into the cycle where the active window starts (the gate begins to rise, a burst fires).
@export var active_start: float = 12.0
## Seconds the active window lasts (rising and fully up for a gate), counted from active_start.
## active_time + transition_time must not exceed period.
@export var active_time: float = 8.0
## Seconds the gate takes to rise (at active_start) and to lower (at the end of the window).
@export var transition_time: float = 1.2
## Cycle offset in seconds: the cycle position is (race_time + phase) mod period.
@export var phase: float = 0.0
## Seconds before active_start during which the warning shows (lantern flashes, horn sounds).
@export var warning_lead: float = 1.5
## Track tool limits (tools/track_check.gd): a gate that is a shortcut must be open at least this
## share of the time and blocked at least min_blocked_fraction of it (else it is no gamble).
@export_range(0.0, 1.0) var min_open_fraction: float = 0.4
@export_range(0.0, 1.0) var min_blocked_fraction: float = 0.2
## The mover blocks / hurts once its progress (0 down .. 1 fully active) reaches this.
@export_range(0.0, 1.0) var block_progress: float = 0.25

@export_group("Where")
## Road the mover belongs to: "main" or a TrackBranch id.
@export var path: StringName = &"main"
## Distance range along that road in meters. A gate: the movable deck (hinge at path_to). A
## barrel or cart: the stretch it travels, wrapping from path_to back to path_from.
@export var path_from: float = 0.0
@export var path_to: float = 0.0
## Travel speed in m/s along the road (barrel, cart). 0 = stands still (gate, burst).
@export var speed: float = 0.0
## Footprint outline as (x, z) points (burst); empty = none.
@export var footprint: PackedVector2Array = PackedVector2Array()
## Height range (Y, meters) a kart must be in for a footprint hit.
@export var footprint_y_min: float = -1.0
@export var footprint_y_max: float = 4.0
## Hit radius in meters around a moving body (barrel, cart).
@export var hit_radius: float = 1.0

@export_group("Hit")
## What a hit does: "sink" (falls in the water and is put back on the main road) or "spin" (spin out
## with a hit-slowdown profile, as an item hit).
@export var hit_effect: StringName = &"sink"
## Index into VehicleStats.hit_slowdown_profiles for a "spin" hit.
@export var hit_profile: int = 1
## Water or lava look/sound of a "sink" hit (TrackHazard kind).
@export var sink_kind: StringName = &"water"

@export_group("Look and sound")
## Visual kind: drawbridge (deck on chains), later barrel, portcullis, burst, cart.
@export var visual: StringName = &"drawbridge"
## Angle in degrees the deck stands at when fully raised.
@export var raised_angle_deg: float = 78.0
## Half width of the deck in meters.
@export var deck_half_width: float = 2.5
## Deck plank colors.
@export var deck_color: Color = Color(0.55, 0.36, 0.2)
@export var deck_alt_color: Color = Color(0.46, 0.29, 0.16)
## Gate posts with the signal lantern stand at this distance along the road (where it is clearly
## out over the water, before the deck), this far beside the road centerline, this tall.
@export var signal_along: float = 0.0
@export var signal_side: float = 4.6
@export var signal_height: float = 3.2
## Lantern colors: open (green), warning (amber), blocked (red).
@export var color_open: Color = Color(0.25, 1.0, 0.35)
@export var color_warn: Color = Color(1.0, 0.75, 0.15)
@export var color_blocked: Color = Color(1.0, 0.15, 0.1)
## Warning lantern blink rate in flashes per second.
@export var warn_blink_hz: float = 4.0
## Where the chains hang from: height above the ground at the hinge end and distance beyond the
## hinge (toward the gatehouse), in meters.
@export var chain_anchor_height: float = 6.0
@export var chain_anchor_beyond: float = 1.5
## Audio events (AudioSet.events) played at the start of the warning and when the deck is down.
@export var sound_warn: StringName = &"drawbridge_up"
@export var sound_down: StringName = &"drawbridge_down"


## First and last segment index (inclusive) of [param road] whose middle lies on the movable
## stretch path_from..path_to, or (-1, -1). The static road mesh skips them; the deck draws them.
func deck_segments(road: TrackModel.Path) -> Vector2i:
	var first: int = -1
	var last: int = -1
	for i in road.points.size() - 1:
		var mid: float = (road.cumulative[i] + road.cumulative[i + 1]) * 0.5
		if mid >= path_from and mid <= path_to:
			if first < 0:
				first = i
			last = i
	return Vector2i(first, last)


## Returns an empty string when the schedule is consistent, else the problem.
func validate() -> String:
	if period > 0.0 and active_time + transition_time > period:
		return "mover %s: active_time + transition_time exceeds period" % id
	if transition_time <= 0.0 and period > 0.0:
		return "mover %s: transition_time must be above 0" % id
	return ""
