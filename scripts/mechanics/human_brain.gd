class_name HumanBrain
extends PlayerBrain

## The default brain — reads InputManager/Input exactly as
## PlayerController used to do directly. PlayerController defaults every
## instance to one of these if nothing else assigns a brain, so the
## milestone-1 sandbox (scenes/main.tscn) needed no changes at all for
## this to land.
##
## Movement is relative to `controller.camera` — the field
## PlayerController already exposed for this — not to a camera this brain
## owns, so switching who's human-controlled is just handing a different
## controller the same camera reference (see FullGame._switch_human_player).


func wish_direction(controller: PlayerController) -> Vector3:
	var input := InputManager.get_move_vector()
	var forward := Vector3.FORWARD
	var right := Vector3.RIGHT
	var camera := controller.camera
	if is_instance_valid(camera):
		var flat := -camera.global_transform.basis.z
		flat.y = 0.0
		if flat.length_squared() > 0.000001:
			forward = flat.normalized()
			right = Vector3(-forward.z, 0.0, forward.x)
	return right * input.x + forward * input.y


func gait() -> float:
	return InputManager.get_gait()


func wants_kick() -> bool:
	return Input.is_action_pressed(&"kick_stance")


func wants_kick_execute() -> bool:
	return Input.is_action_just_pressed(&"kick_execute")


func wants_handball() -> bool:
	return Input.is_action_just_pressed(&"handball")


func wants_bounce() -> bool:
	return Input.is_action_just_pressed(&"bounce")


func wants_tackle() -> bool:
	return Input.is_action_pressed(&"tackle")
