class_name KartDriver
extends RefCounted
## Base class for anything that produces KartInput: the player, an autopilot, later
## bots or a network replay. KartSim never knows which one is driving.


## Seconds until GO during the start countdown, 0 when racing. Set by the owner each
## tick; only drivers that time the start (the autopilot) read it.
var time_to_go: float = 0.0


## Fills [param _input] for the next simulation tick. Override in subclasses.
func drive(_input: KartInput, _sim: KartSim, _track: TrackModel, _dt: float) -> void:
	pass
