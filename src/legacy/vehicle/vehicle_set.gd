class_name VehicleSet
extends Resource
## The vehicle types a kart can use (armored cart, war-bike). Loaded from
## assets/data/vehicles/vehicle_set.tres. Handling and look come from each VehicleStats.
## Implements design/game-brief.md, Features item 6.

## Vehicles in index order (0 = cart, 1 = bike).
@export var vehicles: Array[VehicleStats] = []


## Number of vehicles.
func count() -> int:
	return vehicles.size()


## Vehicle [param index] clamped into range (an empty set returns null).
func vehicle_at(index: int) -> VehicleStats:
	if vehicles.is_empty():
		return null
	return vehicles[clampi(index, 0, vehicles.size() - 1)]


## Index for a CLI/lobby token: a vehicle id ("cart", "bike") or a number. -1 when unknown.
func index_of(token: String) -> int:
	var t: String = token.strip_edges().to_lower()
	for i in vehicles.size():
		if String(vehicles[i].vehicle_id) == t:
			return i
	if t.is_valid_int():
		var n: int = t.to_int()
		if n >= 0 and n < vehicles.size():
			return n
	return -1


## The vehicle a bot gets when nothing was chosen: a hash of the race seed and the kart id,
## so the same race always gives the same mix of carts and bikes.
func bot_vehicle(race_seed: int, kart_id: int) -> int:
	return absi(hash([race_seed, kart_id, 4217])) % maxi(vehicles.size(), 1)
