class_name PlayerInputDriver
extends KartDriver
## Reads the keyboard and controller actions (see InputActions) into KartInput.


## Fills [param input] from the current action states.
func drive(input: KartInput, _sim: KartSim, _track: TrackModel, _dt: float) -> void:
	input.throttle = Input.get_action_strength(InputActions.ACCEL)
	input.brake = Input.get_action_strength(InputActions.BRAKE)
	input.steer = Input.get_action_strength(InputActions.STEER_LEFT) \
			- Input.get_action_strength(InputActions.STEER_RIGHT)
	input.drift = Input.is_action_pressed(InputActions.DRIFT)
	input.item = Input.is_action_pressed(InputActions.ITEM)
