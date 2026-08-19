class_name CharacterBackdrop
extends Node3D

## Live 3D preview behind the character screen: one player standing in a
## glowing ring on the turf, fixed close framing — P1's
## character_render.py used exactly this ("the camera never moves, but
## still ticks every frame like every other mode's rig"). Reuses
## menu_backdrop.gd's pattern (Field + PlayerController instanced with a
## static PlayerBrain) rather than inventing a second way to stand a
## player on the ground.
##
## The dark navy-over-green look is entirely
## `materials/character_studio_environment.tres` plus the dimmed Sun in
## the .tscn — nothing here touches the turf shader or its material,
## which are shared with the match scenes and would drag a gameplay
## regression along behind a UI change if they were poked at.

const FIELD_SCENE := preload("res://scenes/field/field.tscn")
const PLAYER_SCENE := preload("res://scenes/player/player.tscn")

## Stood just inside the centre square's own boundary line rather than at
## the origin. The origin has the centre circles around it, which fill
## this framing with two big white ellipses fighting the selection ring;
## out here the only marking in shot is one straight line running away
## from camera — the faint stripe the design reference has.
##
## The 1.6m offset keeps that line to the subject's right instead of
## under their feet: a line the camera is standing on runs at the viewer
## and fans into a white wedge across the whole foreground, which is a
## much louder thing than the reference's hairline.
const STAND_ON := Vector3(Tuning.CENTRE_SQUARE_SIZE * 0.5 - 1.6, 0.0, 0.0)

## Sits just above the field's own markings (Field.MARKING_HEIGHT).
const RING_HEIGHT := 0.03

## Visual layer the previewed player is moved onto, so the .tscn's two
## lights can be aimed at the figure and the pitch separately (see the
## comment on the Sun/Key nodes there). Only ever applied to the instance
## this scene spawns, so nothing about the shared player scene changes.
const SUBJECT_LAYER := 2

## Framing: far enough back that the figure fills a little under half the
## frame height, low enough that the eye line is roughly chest height.
## The camera is deliberately level (no pitch) — it puts the horizon
## across the middle of frame and keeps the ring a clean ellipse instead
## of a keystoned one.
const CAMERA_DISTANCE := 4.15
const CAMERA_HEIGHT := 1.0

## How far left of the player the camera sits. The stat column owns the
## left ~45% of the screen, so the subject is pushed right of centre by
## shifting the camera rather than by turning it, which would skew the
## ground plane.
const CAMERA_SIDESTEP := 0.46

@onready var _camera: Camera3D = $Camera3D
@onready var _ring: MeshInstance3D = $SelectionRing

var _rig_holder: HumanoidRig


func _ready() -> void:
	add_child(FIELD_SCENE.instantiate())

	var instance := PLAYER_SCENE.instantiate() as PlayerController
	instance.team = Tuning.Team.HOME
	var rig := instance.get_node("Rig") as HumanoidRig
	rig.away_kit = false
	instance.position = STAND_ON
	instance.rotation.y = deg_to_rad(180.0)   # face the camera
	add_child(instance)
	instance.set_brain(PlayerBrain.new())
	_rig_holder = rig

	# After add_child, so HumanoidRig._ready() has actually built the
	# boxes there are meshes to move. owned=false because they are made at
	# runtime and so belong to no scene.
	for mesh in instance.find_children("*", "MeshInstance3D", true, false):
		(mesh as MeshInstance3D).layers = SUBJECT_LAYER

	# The skeleton wireframe overlay: this is a preview screen where one
	# figure is looked at up close, so it's the one place in the project
	# that pays for it — see SkeletonWireframe's own header for why this
	# is deliberately not added to on-field players.
	var wireframe := SkeletonWireframe.new()
	wireframe.layers = SUBJECT_LAYER
	wireframe.track(rig.skeleton())
	add_child(wireframe)

	_ring.position = STAND_ON + Vector3(0.0, RING_HEIGHT, 0.0)

	_camera.rotation = Vector3.ZERO   # identity basis already looks down -Z
	_camera.position = STAND_ON + Vector3(-CAMERA_SIDESTEP, CAMERA_HEIGHT, CAMERA_DISTANCE)


## Cosmetic rig scale so the portrait reflects the draft HEIGHT value
## while it's being edited — matches character_render.py's height_mult
## sprite scaling. Called by character_screen.gd, not driven from here,
## so the preview updates live as the stat is nudged.
func set_height_scale(scale: float) -> void:
	if is_instance_valid(_rig_holder):
		_rig_holder.scale = Vector3.ONE * scale
