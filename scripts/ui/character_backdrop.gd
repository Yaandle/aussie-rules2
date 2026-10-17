class_name CharacterBackdrop
extends Node3D

## Live 3D preview behind the character screen: one player standing in a
## glowing ring on the turf, fixed close framing — P1's
## character_render.py used exactly this ("the camera never moves, but
## still ticks every frame like every other mode's rig").
##
## Deliberately minimal: a bare HumanoidRig stood in place, not a full
## PlayerController. This screen used to instance the real physics scene
## (CharacterBody3D + PlayerBrain + move_and_slide every physics frame),
## which stood still under a neutral brain but still ran full locomotion
## physics against the field's collider each tick — visible up close as a
## constant low-amplitude jitter. A static preview has no business paying
## for gravity/floor-snap/collision resolution at all, so this now just
## builds the rig and poses it once.
##
## The dark navy-over-green look is entirely
## `materials/character_studio_environment.tres` plus the dimmed Sun in
## the .tscn — nothing here touches the turf shader or its material,
## which are shared with the match scenes and would drag a gameplay
## regression along behind a UI change if they were poked at.

const FIELD_SCENE := preload("res://scenes/field/field.tscn")

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
	_build_rig(CharacterProfile.model_id)

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


## Swaps the previewed body to `model_id` ("procedural" or a HumanoidRig.
## CHARACTER_MODELS key) without touching CharacterProfile — the character
## screen calls this as the MODEL row is nudged, same "live preview of an
## uncommitted draft" relationship set_height_scale already has with the
## HEIGHT stat. Rebuilds the rig outright rather than mutating one in
## place: swapping the procedural/imported path only happens in _build(),
## which only ever runs once per instance (see HumanoidRig._ready()).
func set_model(model_id: String) -> void:
	var previous_scale := Vector3.ONE
	if is_instance_valid(_rig_holder):
		previous_scale = _rig_holder.scale
		_rig_holder.queue_free()
	_build_rig(model_id, previous_scale)


func _build_rig(model_id: String, scale := Vector3.ONE) -> void:
	var rig := HumanoidRig.new()
	rig.away_kit = false
	rig.character_model_override = model_id
	rig.position = STAND_ON
	rig.rotation.y = deg_to_rad(180.0)   # face the camera
	rig.scale = scale
	add_child(rig)
	_rig_holder = rig

	# After add_child, so HumanoidRig._ready() has actually built the
	# meshes/skeleton there are to move.
	for mesh in rig.find_children("*", "MeshInstance3D", true, false):
		(mesh as MeshInstance3D).layers = SUBJECT_LAYER
