class_name KartDriver
extends RefCounted
## Base class for anything that produces KartInput: the player, an autopilot, later
## bots or a network replay. KartSim never knows which one is driving.


## Fills [param _input] for the next simulation tick. Override in subclasses.
func drive(_input: KartInput, _sim: KartSim, _track: TrackModel, _dt: float) -> void:
	pass
