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

## Customise mode framing — closer in, same level eye line, so the camera
## reads as "stepping in" rather than cutting to a different shot.
const ZOOM_CAMERA_DISTANCE := 2.6
const ZOOM_DURATION := 0.45

## How far left of the player the camera sits. The stat column owns the
## left ~45% of the screen, so the subject is pushed right of centre by
## shifting the camera rather than by turning it, which would skew the
## ground plane.
const CAMERA_SIDESTEP := 0.46

@onready var _camera: Camera3D = $Camera3D
@onready var _ring: MeshInstance3D = $SelectionRing

var _rig_holder: HumanoidRig
var _current_model_id := "procedural"

## Customise draft colours, alpha-0-means-unset exactly like HumanoidRig's
## own kit_torso/kit_shorts contract (see _build_rig) — not resolved to a
## concrete colour here, just carried through to the next rig build.
var _kit_skin := Color(0.0, 0.0, 0.0, 0.0)
var _kit_jersey := Color(0.0, 0.0, 0.0, 0.0)
var _kit_shorts := Color(0.0, 0.0, 0.0, 0.0)
var _kit_boot := Color(0.0, 0.0, 0.0, 0.0)
var _kit_socks := Color(0.0, 0.0, 0.0, 0.0)


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


## Live-preview the Customise draft's colour rows. Alpha 0 (the default)
## means "unset" and falls through to HumanoidRig's own constants, same as
## kit_torso/kit_shorts always have. Kit slots recolour imported models too
## (HumanoidRig._recolour_imported); skin only does once it's set.
## Rebuilds the rig outright rather than mutating it in place, since
## HumanoidRig only reads its kit_* exports at build time (set_model()
## already pays this same cost for a model change).
func set_kit_colors(skin: Color, jersey: Color, shorts: Color, boot: Color,
		socks := Color(0.0, 0.0, 0.0, 0.0)) -> void:
	_kit_skin = skin
	_kit_jersey = jersey
	_kit_shorts = shorts
	_kit_boot = boot
	_kit_socks = socks
	set_model(_current_model_id)


## Eases the preview camera in for Customise mode, or back out of it.
## Deliberately a plain position tween, not a reparent/look_at — the camera
## is already level with no pitch (see the header note), so moving it
## straight along its own forward axis keeps the ground plane unskewed.
func zoom_in() -> void:
	_tween_camera_to(ZOOM_CAMERA_DISTANCE)


func zoom_out() -> void:
	_tween_camera_to(CAMERA_DISTANCE)


func _tween_camera_to(distance: float) -> void:
	var target := STAND_ON + Vector3(-CAMERA_SIDESTEP, CAMERA_HEIGHT, distance)
	var tween := create_tween()
	tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(_camera, "position", target, ZOOM_DURATION)


func _build_rig(model_id: String, scale := Vector3.ONE) -> void:
	_current_model_id = model_id
	var rig := HumanoidRig.new()
	rig.away_kit = false
	rig.character_model_override = model_id
	rig.kit_skin = _kit_skin
	rig.kit_torso = _kit_jersey
	rig.kit_shorts = _kit_shorts
	rig.kit_boot = _kit_boot
	rig.kit_socks = _kit_socks
	rig.position = STAND_ON
	rig.rotation.y = deg_to_rad(180.0)   # face the camera
	rig.scale = scale
	add_child(rig)
	_rig_holder = rig

	# After add_child, so HumanoidRig._ready() has actually built the
	# meshes/skeleton there are to move.
	for mesh in rig.find_children("*", "MeshInstance3D", true, false):
		(mesh as MeshInstance3D).layers = SUBJECT_LAYER
