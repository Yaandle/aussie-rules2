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
## The plain-field look is entirely
## `materials/character_studio_environment.tres` plus the dimmed Sun in
## the .tscn (a dressed Field 1 swaps in the match's sky and sun instead;
## see dress_field) — nothing here touches the turf shader or its material,
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
## Up to frame the whole body, head to boots (the APPEARANCE rows include
## the boots), at that distance: at 1.0 the top of a tall player's head was
## out of frame. Still level, so it's the same angle stepped in.
const ZOOM_CAMERA_HEIGHT := 1.2
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


## -1 keeps CAMERA_SIDESTEP (the CHARACTER screen's framing). 0..1 instead
## puts the player at that fraction of the screen's width at every zoom —
## the sidestep is worked out from the camera's FOV, the window's aspect and
## the distance (_sidestep()), so zoom_in() doesn't push them off the edge.
## Career's Create/Edit screen uses 0.833, the middle of the right third,
## clear of its card. Set on the scene instance, before _ready().
@export var subject_screen_x := -1.0

## Dress the ground as one of the real fields instead of the plain
## generated one: 1 is Field 1, the park (the CHARACTER screen, playtest
## 2026-11-09: "update the area the player is standing so it is on field 1
## and not the procedural generated field ... with the white fog/gradient.
## same camera angle just replace the background"); 2 is Field 2, the bush
## oval (Career's Create/Edit screens: "show the player standing on field
## 2"). Done here rather than through Field.follow_field_style, which
## follows the player's FIELD setting. Set on the scene instance.
@export_enum("Generated", "Field 1 park", "Field 2 bush") var dress_field := 0
const FIELD_2_FOG_BEGIN := 90.0    # m — just past the far boundary fence
const FIELD_2_FOG_END := 320.0     # m

## Field 1 is lit and fogged as a match is (broadcast_environment.tres and
## full_game.tscn's sun strength): the studio box's white fog, 6 m to 48 m,
## swallowed the park whole, which is the gradient the playtest asked to
## lose. The ground light casts shadows there so the park's trees and the
## fence sit on the grass; the subject's own key light is unchanged.
const MATCH_ENVIRONMENT := preload("res://materials/broadcast_environment.tres")
const FIELD_1_SUN_ENERGY := 1.05
## The subject sits under the match sky's brighter ambient on Field 1, so
## its key comes down a little to keep the same modelling as on the studio
## box (an unplaytested look guess).
const FIELD_1_KEY_ENERGY := 0.55

## The preview stands in the model's own idle clip (Build 7's: arms hanging
## at the sides, a slow breath; tools/blender/author_7thbuild_idle.py),
## looping. Without it the rig sat in its rest pose, an A-pose with the
## arms held out, which read as a T-pose waiting to be rigged (playtest
## 2026-11-09). A bare AnimationPlayer on the rig, not PlayerAnimation:
## there's no locomotion, ball or ground contact to drive here.
const IDLE_CLIP := &"idle"


func _ready() -> void:
	var field := FIELD_SCENE.instantiate()
	if dress_field != 0:
		field.build_fence = false
		field.build_trees = false
	add_child(field)
	if dress_field != 0:
		(field.get_node("Ground/Turf") as MeshInstance3D).visible = false
		var path := Field.PARK_SCENE_PATH if dress_field == 1 else Field.OVAL1_SCENE_PATH
		field.add_child((load(path) as PackedScene).instantiate())
	if dress_field == 1:
		($WorldEnvironment as WorldEnvironment).environment = MATCH_ENVIRONMENT
		var sun := $Sun as DirectionalLight3D
		sun.light_energy = FIELD_1_SUN_ENERGY
		sun.shadow_enabled = true
		($Key as DirectionalLight3D).light_energy = FIELD_1_KEY_ENERGY
	elif dress_field == 2:
		# The studio box fogs out completely by 48 m, and the bush oval's
		# fence and gum ring start ~80 m away: push the fog past them on a
		# copy, so the shared environment resource is left alone.
		var world := $WorldEnvironment as WorldEnvironment
		var environment := world.environment.duplicate() as Environment
		environment.fog_depth_begin = FIELD_2_FOG_BEGIN
		environment.fog_depth_end = FIELD_2_FOG_END
		world.environment = environment
	_build_rig(CharacterProfile.model_id)

	_ring.position = STAND_ON + Vector3(0.0, RING_HEIGHT, 0.0)

	_camera.rotation = Vector3.ZERO   # identity basis already looks down -Z
	_camera.position = _camera_target(CAMERA_DISTANCE)


func _camera_target(distance: float, height := CAMERA_HEIGHT) -> Vector3:
	return STAND_ON + Vector3(-_sidestep(distance), height, distance)


## How far left of the player the camera stands so they appear at
## subject_screen_x. The camera is level and keeps its height (Godot's
## default KEEP_HEIGHT), so half the visible width at the player's depth is
## tan(fov / 2) × aspect × distance.
func _sidestep(distance: float) -> float:
	if subject_screen_x < 0.0:
		return CAMERA_SIDESTEP
	var view := get_viewport().get_visible_rect().size
	var aspect := view.x / maxf(view.y, 1.0)
	var half_width := tan(deg_to_rad(_camera.fov) * 0.5) * aspect * distance
	return (subject_screen_x * 2.0 - 1.0) * half_width


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
	_tween_camera_to(ZOOM_CAMERA_DISTANCE, ZOOM_CAMERA_HEIGHT)


func zoom_out() -> void:
	_tween_camera_to(CAMERA_DISTANCE, CAMERA_HEIGHT)


func _tween_camera_to(distance: float, height: float) -> void:
	var target := _camera_target(distance, height)
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
	_play_idle(rig)


## Loops the rig's idle (see IDLE_CLIP): the imported model's own clip, or
## the procedural rig's generated one. Track paths are relative to the rig
## root on both (HumanoidRig retargets imported tracks to its skeleton).
func _play_idle(rig: HumanoidRig) -> void:
	var idle: Animation = rig.imported_animations().get(String(IDLE_CLIP))
	if idle == null:
		var generated := HumanoidAnimations.build_library(HumanoidRig.HIP_HEIGHT)
		if not generated.has_animation(IDLE_CLIP):
			return
		idle = generated.get_animation(IDLE_CLIP)
	var library := AnimationLibrary.new()
	library.add_animation(IDLE_CLIP, idle)
	var player := AnimationPlayer.new()
	player.name = "PreviewIdle"
	rig.add_child(player)
	player.root_node = player.get_path_to(rig)
	player.add_animation_library(&"", library)
	player.play(IDLE_CLIP)
