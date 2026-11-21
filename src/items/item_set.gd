class_name ItemSet
extends Resource
## All item data for story 004: the five ItemDefs, the odds table and the box timings.

## Item order is the column order of [member odds].
@export var items: Array[ItemDef] = []
## One row per place (row 0 = 1st). Columns follow [member items]. Weights, not percentages.
## A race with more racers than rows uses the last row.
@export var odds: Array[PackedFloat32Array] = []
## Seconds until a taken box is back.
@export var box_respawn: float = 5.0
## Seconds the HUD roulette spins before the item shows.
@export var roulette_time: float = 1.0
## Seconds per icon change during the roulette.
@export var roulette_tick: float = 0.08
## Radius of a kart for picking up boxes and for item contact tests.
@export var box_pickup_radius: float = 2.2
## Seconds before a client repeats a box request the host did not answer with a taken (the box
## was not free on the host yet, e.g. a respawn a few ms apart). Bugfix 2026-11-20.
@export var box_ask_retry: float = 1.0
@export var kart_hit_radius: float = 1.0
## Items act only on karts at a similar height (story 008): a kart more than this many meters
## above or below an item (one under a bridge, one in the air) is not hit by it.
@export var hit_height_tolerance: float = 2.0
## Hit slowdown profile index (story 001 data) applied after a hit.
@export var hit_slowdown_profile: int = 0


## Index of the item with [param item_id], or -1.
func index_of(item_id: StringName) -> int:
	for i in items.size():
		if items[i].id == item_id:
			return i
	return -1


## Picks an item index for [param place] (1-based) using [param rng].
func roll(place: int, rng: RandomNumberGenerator) -> int:
	var row: PackedFloat32Array = odds[clampi(place - 1, 0, odds.size() - 1)]
	var total: float = 0.0
	for w in row:
		total += w
	var pick: float = rng.randf() * total
	for i in row.size():
		pick -= row[i]
		if pick < 0.0:
			return i
	return row.size() - 1
