class_name RacerSet
extends Resource
## The eight knight-dog racers plus the pennant look. Loaded from assets/data/racers/racer_set.tres.
## Implements design/game-brief.md, Features item 6 (racers; the pick screen is story 007).

## Racers in index order (0 = the Dogworks mascot).
@export var racers: Array[RacerDef] = []
## Pennant shape, colours and wave (shared by all karts).
@export var pennant: PennantStyle = PennantStyle.new()


## Number of racers.
func count() -> int:
	return racers.size()


## Racer [param index] clamped into range (an empty set returns null).
func racer_at(index: int) -> RacerDef:
	if racers.is_empty():
		return null
	return racers[clampi(index, 0, racers.size() - 1)]


## True when [param index] is a valid racer index.
func is_valid_index(index: int) -> bool:
	return index >= 0 and index < racers.size()


## The dog a bot uses when nothing was chosen: kart id modulo the roster.
func default_bot_racer(kart_id: int) -> int:
	return kart_id % maxi(racers.size(), 1)
