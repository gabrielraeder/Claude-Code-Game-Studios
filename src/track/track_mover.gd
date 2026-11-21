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
## Travel speed in m/s along the road (barrel, cart). 0 = stands still (gate, burst). For a
## shuttle this is the average speed of one run (it eases in and out at the ends).
@export var speed: float = 0.0
## How a traveler moves: "run" (waits at path_from during the warning, rolls to path_to, then is
## hidden until the next warning: the barrels) or "shuttle" (back and forth between path_from and
## path_to, easing in and out, standing at each end for the rest of half a period: the mine cart).
## A shuttle is always there and always solid.
@export var motion: StringName = &"run"
## Footprint outline as (x, z) points (burst); empty = none.
@export var footprint: PackedVector2Array = PackedVector2Array()
## Height range (Y, meters) a kart must be in for a footprint hit.
@export var footprint_y_min: float = -1.0
@export var footprint_y_max: float = 4.0
## A burst: the centre of its vent (x, z) and the road height there (the column stands on it).
@export var vent_center: Vector2 = Vector2.ZERO
@export var vent_height: float = 0.0
## A traveler (barrel) waits at path_from for warning_lead seconds before it rolls, rising out of
## its cellar; it is solid (hits) only for the last solid_lead seconds of that wait, so a kart that
## happens to be on the spot when it appears is not hit by surprise.
@export var solid_lead: float = 0.75
## Hit radius in meters around a moving body (barrel, cart): the body's radius plus a kart's.
@export var hit_radius: float = 1.0
## Sideways offset in meters of a traveling body (barrel, cart) from its road's centerline, on the
## road's normal side (left positive, like TrackModel.Query.lateral): the body's lane.
@export var lane_offset: float = 0.0
## A kart is hit by a traveling body only when its height is within this many meters of the
## body's road height (a road above or below is not hit).
@export var hit_height: float = 1.5
## Tools (tools/track_check.gd): a traveling body must always leave a free gap at least this wide
## (meters) across the road it rolls on, so it never blocks the road completely.
@export var min_free_gap: float = 3.0
## Tools: id of another gate that must never be blocked at the same time as this one (two
## shortcuts are not closed together). Empty = no such rule.
@export var out_of_phase_with: StringName = &""

@export_group("Hit")
## What a hit does: "sink" (falls in the water and is put back on the main road), "spin" (spin out
## with a hit-slowdown profile, as an item hit) or "stop" (a gate in an enclosed road, the
## portcullis: the kart is stopped against it like a wall and bounced back).
@export var hit_effect: StringName = &"sink"
## A traveling body that is solid (the mine cart): a kart that touches it is also pushed back out
## of its hit circle every tick (spinning or not) and loses the speed it had into it, as off a wall.
@export var solid_body: bool = false
## A solid body spins a kart only when they close on each other at this speed (m/s) or more; a
## slower touch (a kart standing against the parked cart) is only pushed back, never spun again.
@export var spin_min_speed: float = 4.0
## Index into VehicleStats.hit_slowdown_profiles for a "spin" hit.
@export var hit_profile: int = 1
## Water or lava look/sound of a "sink" hit (TrackHazard kind).
@export var sink_kind: StringName = &"water"
## Puff the victim's kart shows on a "spin" hit: "scorch" (the lava scorch puff, a burst) or empty.
@export var hit_puff: StringName = &""
## A "stop" hit: the kart is pushed back off the gate and rolls back at this share of the speed it
## hit with (capped by its reverse top speed).
@export_range(0.0, 1.0) var stop_rebound: float = 0.15

@export_group("Look and sound")
## Visual kind: drawbridge (deck on chains), portcullis (an iron grille that drops in a stone
## frame), barrel (a rolling wooden barrel with iron bands), burst (a glowing vent and a lava
## column), cart (an ore cart on the rails).
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
## Audio events (AudioSet.events) played at the start of the warning and when the deck is down
## (back to idle). Empty = none.
@export var sound_warn: StringName = &"drawbridge_up"
@export var sound_down: StringName = &"drawbridge_down"
## Audio event played when the mover becomes active (a barrel is released, a portcullis slams
## down). Empty = none.
@export var sound_active: StringName = &""

@export_group("Portcullis look")
## Height in meters the grille's bottom rises above the road when fully up (clear of the karts).
@export var lift_height: float = 2.8
## Height of the grille in meters; the frame's lintel sits above lift_height + grille_height.
@export var grille_height: float = 2.6
## Spacing of the grille's vertical bars and its bar thickness, meters.
@export var bar_spacing: float = 0.45
@export var bar_size: float = 0.12
## Grille (iron) and frame (stone) colors.
@export var grille_color: Color = Color(0.18, 0.18, 0.2)
@export var frame_color: Color = Color(0.5, 0.49, 0.5)

@export_group("Barrel look")
## Barrel radius and length (along its roll axis) in meters.
@export var body_radius: float = 0.55
@export var body_length: float = 1.1
## Wood and iron band colors.
@export var body_color: Color = Color(0.52, 0.33, 0.17)
@export var band_color: Color = Color(0.22, 0.22, 0.24)
## The body shrinks over this many meters before the end of its run (into the cellar at the
## bottom); at the top it grows during the warning until it is solid (see solid_lead).
@export var appear_distance: float = 2.0
## How much darker than body_color the stave that shows the barrel turning is (Color.darkened).
@export_range(0.0, 1.0) var stave_darken: float = 0.45

@export_group("Burst look")
## Radius in meters of the glowing vent (the crack in the road edge) and of the lava column.
@export var vent_radius: float = 2.6
@export var column_radius: float = 1.6
## Height in meters of the column at full eruption.
@export var column_height: float = 6.0
## Vent colours: dull (idle) and bright (warning, eruption); column colour and how much it glows.
@export var vent_idle_color: Color = Color(0.35, 0.1, 0.04)
@export var vent_hot_color: Color = Color(1.0, 0.62, 0.15)
@export var column_color: Color = Color(1.0, 0.45, 0.1)
@export var column_glow: float = 2.5
## Vent glow (emission energy) when idle and at the peak of the warning; the warning pulses at
## warn_blink_hz.
@export var vent_glow_idle: float = 0.4
@export var vent_glow_warn: float = 3.0
## During the warning a lava dome bubbles up out of the vent, pulsing, up to this share of
## column_height (it reads from far away, where the flat vent is a thin sliver).
@export_range(0.0, 1.0) var warn_dome: float = 0.15

@export_group("Cart look")
## Ore cart body: width, height and length in meters; wheel radius; ore heap colour. The wood is
## body_color, the iron bands and wheels band_color.
@export var cart_width: float = 1.3
@export var cart_height: float = 0.9
@export var cart_length: float = 1.9
@export var wheel_radius: float = 0.3
@export var ore_color: Color = Color(0.3, 0.42, 0.62)


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
	if transition_time <= 0.0 and period > 0.0 and speed <= 0.0:
		return "mover %s: transition_time must be above 0" % id
	if speed > 0.0 and solid_lead > warning_lead:
		return "mover %s: solid_lead exceeds warning_lead" % id
	if is_shuttle():
		if period > 0.0 and 2.0 * travel_time() + 2.0 * warning_lead > period:
			return "mover %s: two runs (%.2f s each) and two warnings exceed the period" % [id, travel_time()]
		return ""
	if speed > 0.0 and period > 0.0 and (path_to - path_from) / speed + warning_lead > period:
		return "mover %s: the run (%.2f s) and the warning exceed the period" % [id, (path_to - path_from) / speed]
	if kind == &"burst" and footprint.size() < 3:
		return "mover %s: a burst needs a footprint" % id
	return ""


## True for a body that travels along its road (barrel, cart) rather than a gate or a footprint.
func is_traveler() -> bool:
	return speed > 0.0 and kind != &"gate"


## True for a traveler that goes back and forth (motion "shuttle").
func is_shuttle() -> bool:
	return is_traveler() and motion == &"shuttle"


## Seconds a traveling body takes from path_from to path_to (0 when it does not travel).
func travel_time() -> float:
	return (path_to - path_from) / speed if is_traveler() else 0.0
