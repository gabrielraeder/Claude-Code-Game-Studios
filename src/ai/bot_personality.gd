class_name BotPersonality
extends Resource
## One bot character (story 005): how it picks its racing line, when it drifts, whether it takes
## shortcuts, and how it uses items. Pure data; the BotDriver reads it. Every number here is a
## tuning knob; the values live in assets/data/ai/bot_set.tres.

@export var id: StringName = &""
@export var display_name: String = ""

@export_group("Racing line")
## Share of the usable road half width the outside-in-out swing may use (0 = centerline).
@export_range(0.0, 1.0) var line_amount: float = 0.6
## How hard the bot cuts toward the inside of the corner it is in (0..1).
@export_range(0.0, 1.0) var inside_gain: float = 1.0
## How far it swings to the outside before a corner it sees ahead (0..1).
@export_range(0.0, 1.0) var outside_gain: float = 0.6
## Constant sideways share of the usable half width (-1 = one wall, +1 = the other).
@export_range(-1.0, 1.0) var lane_bias: float = 0.0
## Slow weaving: amplitude as a share of the usable half width, and its period in meters.
@export_range(0.0, 1.0) var wander_amount: float = 0.0
@export var wander_period: float = 140.0

@export_group("Drift")
## Chance (0..1) that the bot drifts a given corner at all.
@export_range(0.0, 1.0) var drift_chance: float = 0.8
## Heading change (rad, 5 m to 45 m ahead) that starts a drift. Higher = only the sharp corners.
@export var drift_start_turn: float = 0.5
## A drift is released at this tier (1 blue, 2 orange, 3 purple) once the corner relaxes.
@export_range(1, 3) var drift_max_tier: int = 3

@export_group("Shortcuts")
## Chance (0..1) per lap that the bot plans to take a given shortcut (scaled by the
## per-type factor in BotSet.branch_factor). A planned shortcut can still be missed.
@export_range(0.0, 1.0) var shortcut_chance: float = 0.6

@export_group("Pace")
## Share of the vehicle's top speed this bot can use (1 = full). Below 1 makes a slower driver.
@export_range(0.9, 1.0) var speed_factor: float = 1.0
## Start: seconds before GO that the bot presses accelerate (0.15 or less = perfect start,
## up to 0.35 good, up to 0.6 ok, above 0.6 stalls) and the random +- spread added to it.
@export var start_press_before_go: float = 0.08
@export var start_press_spread: float = 0.05

@export_group("Items")
## Seconds a new item is held before the bot may use it.
@export var item_reaction: float = 0.6
## Seconds after which any item except the shield is used even without a good target.
@export var item_hold_max: float = 10.0
## Seconds after which the shield is used even without a threat.
@export var shield_hold_max: float = 14.0
## Scale on the item ranges in BotSet (stone, spill, threat). Above 1 = fires from farther.
@export var item_range_scale: float = 1.0

@export_group("Traffic")
## Scale on the sideways dodge distance around karts ahead (1 = normal, below = bolder).
@export var dodge_scale: float = 1.0
