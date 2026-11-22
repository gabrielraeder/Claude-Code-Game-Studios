class_name Racer
extends RefCounted
## One kart in a race. [member owned] racers are simulated on this PC (the local player or
## autopilot, plus host bots) and have a driver, input, start sequence and lap counter;
## remote racers have a RemoteKart that network snapshots fill in. Holds state only.

var kart_id: int = 0
## Network peer that owns the kart (1 = host; bots belong to the host).
var owner_peer: int = 1
var display_name: String = ""
var is_bot: bool = false
## True when this PC simulates the kart.
var owned: bool = true
var sim: KartSim
## Same object as [member sim] when the kart is remote, otherwise null.
var remote: RemoteKart
var driver: KartDriver
var input: KartInput = KartInput.new()
var start: StartSequence = StartSequence.new()
var laps: LapCounter
var visual: KartVisual
## True after the owner left; the kart is hidden and no longer ranked.
var dropped: bool = false


## True when the kart has completed the race.
func is_finished() -> bool:
	if owned:
		return laps != null and laps.is_finished
	return remote != null and remote.finished


## Race time at which the kart finished (valid when [method is_finished]).
func finish_time() -> float:
	if owned:
		return laps.finish_race_time
	return remote.finish_time
