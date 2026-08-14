class_name CharacterBackdrop
extends Node3D

## Decorative background for the character screen: one standing player on
## the turf, a fixed close camera framing — P1's character_render.py used
## exactly this ("the camera never moves, but still ticks every frame
## like every other mode's rig"). Reuses menu_backdrop.gd's pattern
## (Field + PlayerController instanced with a static PlayerBrain) rather
## than inventing a second way to stand a player on the ground.

const FIELD_SCENE := preload("res://scenes/field/field.tscn")
const PLAYER_SCENE := preload("res://scenes/player/player.tscn")

@onready var _camera: Camera3D = $Camera3D

var _rig_holder: PlaceholderRig


func _ready() -> void:
	add_child(FIELD_SCENE.instantiate())

	var instance := PLAYER_SCENE.instantiate() as PlayerController
	instance.team = Tuning.Team.HOME
	var rig := instance.get_node("Rig") as PlaceholderRig
	rig.away_kit = false
	instance.position = Vector3.ZERO
	instance.rotation.y = deg_to_rad(180.0)   # face the camera
	add_child(instance)
	instance.set_brain(PlayerBrain.new())
	_rig_holder = rig

	_camera.global_position = Vector3(0.0, 1.35, 3.4)
	_camera.look_at(Vector3(0.0, 1.0, 0.0), Vector3.UP)


## Cosmetic rig scale so the portrait reflects the draft HEIGHT value
## while it's being edited — matches character_render.py's height_mult
## sprite scaling. Called by character_screen.gd, not driven from here,
## so the preview updates live as the stat is nudged.
func set_height_scale(scale: float) -> void:
	if is_instance_valid(_rig_holder):
		_rig_holder.scale = Vector3.ONE * scale
