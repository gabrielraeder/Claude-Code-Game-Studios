class_name BotSet
extends Resource
## All bot AI data (story 005): the personality list and every shared tuning value. Loaded from
## assets/data/ai/bot_set.tres. No numbers live in the bot code.

## Personalities, assigned by kart id (see [method personality_for]).
@export var personalities: Array[BotPersonality] = []

@export_group("Line following")
## Look-ahead distance = base + speed * per_speed (meters).
@export var look_base: float = 8.0
@export var look_per_speed: float = 0.6
## Distances ahead (meters) where the route heading is sampled to measure corners.
@export var corner_near: float = 5.0
@export var corner_mid: float = 45.0
@export var corner_far: float = 95.0
## Heading change (rad) that counts as a full corner for the line plan.
@export var corner_ref_turn: float = 0.9
## Meters kept between the line and the wall (on top of the kart radius).
@export var wall_margin: float = 2.2
## Fastest sideways change of the line target, m/s.
@export var lateral_rate: float = 4.0
## Steering gain on the heading error when not drifting.
@export var steer_gain: float = 2.5
## Roads narrower than this half width (meters) keep the line on the centerline.
@export var narrow_half_width: float = 3.4
## Meters before a planned shortcut where the line is centered.
@export var branch_center_before: float = 60.0

@export_group("Drift")
## Extra speed over the vehicle's drift minimum needed to start a drift.
@export var drift_speed_margin: float = 1.0
## Heading change that keeps a drift going.
@export var drift_keep_turn: float = 0.2
## Heading change under which a drift at its max tier is released.
@export var drift_release_turn: float = 0.45
## A drift is released this close (meters) to the wall.
@export var drift_wall_margin: float = 3.0
## A corner is over (the drift choice resets) when the heading change falls under this.
@export var corner_end_turn: float = 0.15
## A corner starts when the heading change reaches this share of the personality's drift_start_turn.
@export var corner_start_share: float = 0.7

@export_group("Open edges")
## On a main-road stretch with an unwalled edge (over water or lava) the line stays at most this
## many meters from the centerline toward that edge.
@export var open_edge_keep: float = 0.0
## A drift is released when this far (meters) from the centerline toward an open edge.
@export var open_edge_drift_abort: float = 1.0
## False = no drift starts while an unwalled edge is near (a drift slides toward the outside of the
## corner and its release boost carries the kart over the edge; story 006 bike/cart sinks at the Castle moat).
@export var open_edge_allow_drift_start: bool = false
## The open edge counts from this many meters before and until this many meters after the kart.
@export var open_edge_behind: float = 10.0
@export var open_edge_ahead: float = 45.0

@export_group("After a respawn")
## Seconds after coming back from a sink with the centerline only: no line offset, no dodge, no drift.
@export var respawn_calm_time: float = 2.5

@export_group("Rail-less decks")
## Braking for a rail-less shortcut (the drawbridge) starts this many meters before its entrance,
## down to the entry speed, which also holds for the first deck meters (the autopilot's value is
## 15 m and 23 m/s). After that the speed is held at the deck speed until the deck ends.
@export var open_entry_before: float = 40.0
@export var open_entry_speed: float = 21.0
@export var open_deck_speed: float = 22.5
## A planned rail-less shortcut counts as missed once the kart is on the main road this many
## meters past its entrance and off the deck: the bot then stays on the main road and never aims
## across the gap (the water or lava between the road and the deck).
@export var open_mouth_len: float = 3.0
## Off the deck means farther than the deck's wall offset plus this many meters from its centerline.
@export var open_off_deck_margin: float = 1.0

@export_group("Shortcuts")
## A planned rail-less shortcut is skipped when another kart is within this many meters of the
## bot when it is this many meters before the entrance (a crowded plank pushes karts off).
@export var branch_gate_dist: float = 50.0
@export var branch_clear_radius: float = 12.0
## A speed-gated shortcut (the lava gap) is skipped when the bot is slower than the gate speed
## minus this many m/s at that point (a bump or a hit just before it). On the route the bot uses
## its full top speed (no personality or handicap reduction) so it clears the gate.
@export var gate_speed_slack: float = 6.0
## Per shortcut type (TrackBranch.type) factor on the personality's shortcut chance.
@export var branch_factor: Dictionary = {}

@export_group("Rubber band")
## Largest speed gain for a bot far behind (share of top speed, 0.03 = +3 percent).
@export var assist_max: float = 0.03
## Gap behind the leader (meters) where the gain starts and where it is full.
@export var assist_start_gap: float = 35.0
@export var assist_full_gap: float = 160.0
## Largest speed loss for a bot far ahead of the second kart.
@export var handicap_max: float = 0.03
@export var handicap_start_gap: float = 25.0
@export var handicap_full_gap: float = 110.0
## How fast the multiplier follows its target (multiplier change per second).
@export var rubber_smoothing: float = 0.03
## Hard ceiling on the multiplier (stays far inside the vehicle's boost cap).
@export var rubber_mult_ceiling: float = 1.05

@export_group("Traffic")
## Karts are noticed this far ahead: base + speed * per_speed (meters).
@export var avoid_range_base: float = 14.0
@export var avoid_range_per_speed: float = 0.9
## A kart this close sideways (meters) is in the way.
@export var avoid_corridor: float = 2.3
## Sideways dodge distance (meters) and how far behind still counts as alongside.
@export var avoid_shift: float = 2.8
@export var avoid_alongside: float = 4.5
## A kart alongside closer than this sideways is given room (meters of push).
@export var avoid_side_gap: float = 3.2
@export var avoid_side_push: float = 1.2
## A kart at least this far to one side (meters) is passed on the other side.
@export var avoid_commit_side: float = 0.8
## Lift the throttle when a slower kart is this close ahead (meters) and in the way.
@export var follow_gap: float = 13.0
## A slower kart ahead only makes the bot lift when it is within this share of avoid_corridor sideways.
@export var follow_corridor_share: float = 0.8
## Brake when a kart is this close ahead and closing fast.
@export var brake_gap: float = 6.0
## Closing speed (m/s) needed to brake.
@export var brake_closing: float = 3.0

@export_group("Stuck recovery")
## Seconds of barely moving (less than stuck_move meters) before the bot reverses out.
@export var stuck_time: float = 1.5
@export var stuck_move: float = 2.0
## Seconds the reverse maneuver lasts.
@export var recover_time: float = 1.1

@export_group("Items")
## Seconds between item decisions.
@export var item_think_interval: float = 0.15
## Stone: fires at a kart between these distances ahead, inside a cone of this half angle.
@export var stone_min_range: float = 6.0
@export var stone_max_range: float = 50.0
@export var stone_cone_deg: float = 9.0
## The stone cone is this many meters wider than its angle (sideways).
@export var stone_cone_slack: float = 1.2
## Spill: dropped when a kart is this close behind (meters) and this near my lane.
@export var spill_range: float = 16.0
@export var spill_lane: float = 3.5
## Horn: counts as a straight when the heading change ahead is under this (rad).
@export var horn_straight_turn: float = 0.15
## Shield: a hostile item within this many meters counts as a threat.
@export var threat_range: float = 30.0


## Display names for bots (dog plus medieval puns), handed out by bot slot. Story 006 can
## replace or extend the list.
@export var bot_names: PackedStringArray = PackedStringArray()


## Name of the bot in bot slot [param slot] (0-based), cycling when there are more bots than names.
func bot_name(slot: int) -> String:
	if bot_names.is_empty():
		return "Bot %d" % (slot + 1)
	return bot_names[slot % bot_names.size()]


## The personality for [param kart_id]: the same on every run and every PC.
func personality_for(kart_id: int) -> BotPersonality:
	if personalities.is_empty():
		return BotPersonality.new()
	return personalities[kart_id % personalities.size()]


## Empty string when the data is usable, otherwise what is wrong.
func validate() -> String:
	if personalities.is_empty():
		return "BotSet has no personalities (bots fall back to default values)"
	for p in personalities:
		if p == null:
			return "BotSet has an empty personality slot"
	if bot_names.is_empty():
		return "BotSet has no bot names (bots are named Bot N)"
	return ""
