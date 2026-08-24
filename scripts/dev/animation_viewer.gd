class_name AnimationViewer
extends Node3D

## Dev-only viewer for the placeholder animation set (docs/FEATURE_AUDIT.md
## "unbuilt but planned" tooling): a bare HumanoidRig driven by the real
## AnimationTree, standing still, with buttons to force each locomotion
## blend point and fire each discrete action clip in isolation. Not reachable
## from the main menu — open scenes/dev/animation_viewer.tscn directly in the
## editor and press F6, same precedent as scenes/main.tscn's own sandbox.
##
## Locomotion is previewed "on the spot" by driving PlayerAnimation's blend
## space directly rather than moving a CharacterBody3D — the locomotion
## clips only ever write hip bob + joint rotation tracks (see
## player_animation.gd's own "NOT YET WIRED: root motion" note), so nothing
## about the rig's own position needs to change for a gait to read.
##
## Deliberately shows only what has a real clip. Tackle/bump/spoil/smother/
## hit-out resolve through pure physics reactions today (knockback, stun,
## lunge — see player_controller.gd) with no AnimationTree state behind
## them; player_animation.gd's ACTION_STATES map is the source of truth for
## which Tuning.Action values actually animate. Those show as disabled
## buttons here rather than being left out silently, so this screen stays
## an honest map of what exists versus what's still physics-only.

const STAND_ON := Vector3.ZERO

const CAMERA_DISTANCE := 4.0
const CAMERA_HEIGHT := 1.0

## How far left of the subject the camera sits — pushes the figure right of
## centre in frame (same trick character_backdrop.gd uses via its own
## CAMERA_SIDESTEP) so it clears the three button columns on the left
## rather than standing directly behind them.
const CAMERA_SIDESTEP := 1.5

## Wireframe floor grid, drawn in code with ImmediateMesh (same technique
## as skeleton_wireframe.gd, which this scene also attaches to the rig —
## no turf here, just a bounded reference square so the figure reads
## against something instead of floating in flat white).
const GRID_HALF_EXTENT := 1.6
const GRID_STEP := 0.4
const GRID_COLOUR := Color(0.72, 0.75, 0.79)

## Locomotion buttons: label -> blend target. Must agree with
## PlayerAnimation.BLEND_POINTS.
const LOCOMOTION := [
	["IDLE", Vector2(0.0, 0.0)],
	["JOG FWD", Vector2(0.0, 0.55)],
	["RUN FWD", Vector2(0.0, 1.0)],
	["RUN BACK", Vector2(0.0, -1.0)],
	["STRAFE L", Vector2(-1.0, 0.0)],
	["STRAFE R", Vector2(1.0, 0.0)],
	["RUN FWD L", Vector2(-0.75, 0.75)],
	["RUN FWD R", Vector2(0.75, 0.75)],
]

## Action buttons: label -> Tuning.Action. Matches player_animation.gd's
## ACTION_STATES exactly.
const ACTIONS := [
	["KICK", Tuning.Action.KICK],
	["HANDBALL", Tuning.Action.HANDBALL],
	["BOUNCE", Tuning.Action.BOUNCE],
	["MARK — SAFE", Tuning.Action.MARK_SAFE],
	["MARK — RUNNING", Tuning.Action.MARK_RUNNING],
	["MARK — AGGRESSIVE", Tuning.Action.MARK_AGGRESSIVE],
	["MARK — SAFE MISS", Tuning.Action.MARK_SAFE_MISS],
	["MARK — RUNNING MISS", Tuning.Action.MARK_RUNNING_MISS],
]

## No AnimationTree state exists for these yet (see class doc) — listed so
## the gap is visible on the screen itself rather than a silent omission.
const UNIMPLEMENTED := ["TACKLE", "BUMP", "SPOIL", "SMOTHER", "HIT-OUT"]

## Synthetic vertical hop, independent of the skeleton — there is no jump
## clip to preview (MARK — AGGRESSIVE is the only clip with a jump built
## in, and it already has its own button). Arbitrary dev-tool timing, not
## a gameplay number — does not touch Tuning.
const JUMP_HEIGHT := 0.45
const JUMP_RISE_TIME := 0.28
const JUMP_FALL_TIME := 0.32

@onready var _camera: Camera3D = $Camera3D
@onready var _ui: Control = $Overlay/UI

var _subject: Node3D
var _rig: HumanoidRig
var _player_animation: PlayerAnimation
var _current_blend := Vector2.ZERO
var _state_label: Label
var _blend_label: Label
var _jump_tween: Tween


func _ready() -> void:
	add_child(_build_studio_floor())
	_build_subject()
	_camera.rotation = Vector3.ZERO
	_camera.position = STAND_ON + Vector3(-CAMERA_SIDESTEP, CAMERA_HEIGHT, CAMERA_DISTANCE)
	_build_ui()


func _process(delta: float) -> void:
	if _player_animation == null:
		return
	_player_animation.drive(_current_blend, delta)
	_state_label.text = "STATE: %s" % String(_player_animation.current_state()).to_upper()
	var b := _player_animation.blend_position()
	_blend_label.text = "BLEND: %.2f, %.2f" % [b.x, b.y]


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"pause") or event.is_action_pressed(&"character_menu"):
		SceneWipe.change_scene("res://scenes/ui/main_menu.tscn")


# ── Subject: rig + the same AnimationPlayer/AnimationTree/PlayerAnimation
# trio player.tscn wires up, built in code since there are no other exported
# params to set and the default `../Rig` / `../AnimationPlayer` /
# `../AnimationTree` NodePaths on PlayerAnimation just need matching
# siblings, not a specific scene layout. ─────────────────────────────────

func _build_subject() -> void:
	_subject = Node3D.new()
	_subject.position = STAND_ON
	_subject.rotation.y = deg_to_rad(180.0)   # face the camera
	add_child(_subject)

	_rig = HumanoidRig.new()
	_rig.name = "Rig"
	_rig.away_kit = false
	_subject.add_child(_rig)

	# Bone-line overlay over the mesh — see skeleton_wireframe.gd's own
	# header, which names exactly this kind of single-figure preview as
	# the case it's meant for. Unused everywhere else in the project until
	# now.
	var wireframe := SkeletonWireframe.new()
	wireframe.name = "SkeletonWireframe"
	_subject.add_child(wireframe)
	wireframe.track(_rig.skeleton())

	var player := AnimationPlayer.new()
	player.name = "AnimationPlayer"
	_subject.add_child(player)

	var tree := AnimationTree.new()
	tree.name = "AnimationTree"
	tree.active = false
	_subject.add_child(tree)

	_player_animation = PlayerAnimation.new()
	_player_animation.name = "PlayerAnimation"
	_subject.add_child(_player_animation)


# ── UI ───────────────────────────────────────────────────────────────

func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.position = Vector2(24.0, 20.0)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_theme_constant_override(&"separation", 16)
	_ui.add_child(root)

	root.add_child(UIStyle.label("ANIMATION VIEWER — DEV", UIStyle.SIZE_TITLE,
		UIStyle.TEXT_PRIMARY, UIStyle.WEIGHT_HEAVY, UIStyle.TRACK_TITLE))

	var status := HBoxContainer.new()
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status.add_theme_constant_override(&"separation", 24)
	root.add_child(status)
	_state_label = UIStyle.label("STATE: —", UIStyle.SIZE_LABEL, UIStyle.TEXT_MUTED)
	_blend_label = UIStyle.label("BLEND: 0.00, 0.00", UIStyle.SIZE_LABEL, UIStyle.TEXT_MUTED)
	status.add_child(_state_label)
	status.add_child(_blend_label)

	var columns := HBoxContainer.new()
	columns.mouse_filter = Control.MOUSE_FILTER_IGNORE
	columns.add_theme_constant_override(&"separation", 56)
	root.add_child(columns)

	columns.add_child(_build_locomotion_group())
	columns.add_child(_build_action_group())
	columns.add_child(_build_misc_group())

	var hints := KeyHintBar.new()
	hints.position = Vector2(24.0, 674.0)
	hints.set_hints([{"keys": "Esc / C", "label": "Back to menu"}])
	_ui.add_child(hints)


func _build_locomotion_group() -> VBoxContainer:
	var group := VBoxContainer.new()
	group.mouse_filter = Control.MOUSE_FILTER_IGNORE
	group.add_theme_constant_override(&"separation", 8)
	group.add_child(UIStyle.label("LOCOMOTION — ON THE SPOT", UIStyle.SIZE_LABEL,
		UIStyle.TEXT_MUTED, UIStyle.WEIGHT_BOLD, UIStyle.TRACK_LABEL))

	var toggle_group := ButtonGroup.new()
	for entry: Array in LOCOMOTION:
		var label: String = entry[0]
		var blend: Vector2 = entry[1]
		var button := Button.new()
		button.text = label
		button.toggle_mode = true
		button.button_group = toggle_group
		button.button_pressed = blend == Vector2.ZERO
		button.custom_minimum_size = Vector2(200.0, 32.0)
		button.pressed.connect(func() -> void: _current_blend = blend)
		group.add_child(button)
	return group


func _build_action_group() -> VBoxContainer:
	var group := VBoxContainer.new()
	group.mouse_filter = Control.MOUSE_FILTER_IGNORE
	group.add_theme_constant_override(&"separation", 8)
	group.add_child(UIStyle.label("ACTIONS", UIStyle.SIZE_LABEL,
		UIStyle.TEXT_MUTED, UIStyle.WEIGHT_BOLD, UIStyle.TRACK_LABEL))

	for entry: Array in ACTIONS:
		var label: String = entry[0]
		var action: Tuning.Action = entry[1]
		var button := Button.new()
		button.text = label
		button.custom_minimum_size = Vector2(220.0, 32.0)
		button.pressed.connect(func() -> void: _player_animation.play_action(action))
		group.add_child(button)
	return group


func _build_misc_group() -> VBoxContainer:
	var group := VBoxContainer.new()
	group.mouse_filter = Control.MOUSE_FILTER_IGNORE
	group.add_theme_constant_override(&"separation", 8)
	group.add_child(UIStyle.label("OTHER", UIStyle.SIZE_LABEL,
		UIStyle.TEXT_MUTED, UIStyle.WEIGHT_BOLD, UIStyle.TRACK_LABEL))

	var jump_button := Button.new()
	jump_button.text = "JUMP"
	jump_button.custom_minimum_size = Vector2(200.0, 32.0)
	jump_button.pressed.connect(_on_jump_pressed)
	group.add_child(jump_button)

	group.add_child(UIStyle.label("PHYSICS-ONLY — NO CLIP YET", UIStyle.SIZE_LABEL,
		UIStyle.TEXT_MUTED, UIStyle.WEIGHT_BOLD, UIStyle.TRACK_LABEL))
	for label: String in UNIMPLEMENTED:
		var button := Button.new()
		button.text = label
		button.disabled = true
		button.custom_minimum_size = Vector2(200.0, 32.0)
		group.add_child(button)
	return group


func _on_jump_pressed() -> void:
	if _jump_tween != null and _jump_tween.is_valid():
		_jump_tween.kill()
	_rig.position.y = 0.0
	_jump_tween = create_tween()
	_jump_tween.tween_property(_rig, "position:y", JUMP_HEIGHT, JUMP_RISE_TIME) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_jump_tween.tween_property(_rig, "position:y", 0.0, JUMP_FALL_TIME) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)


## A bounded reference grid, not an infinite ground plane — a floor with no
## edge gives the eye nothing to judge scale or footing against, which is
## the opposite of what a "does this animation look right" tool needs.
## Drawn as flat lines (PRIMITIVE_LINES, unshaded) rather than a textured
## mesh, matching skeleton_wireframe.gd's own reasoning: this is a
## reference cue, not scenery.
func _build_studio_floor() -> MeshInstance3D:
	var mesh := ImmediateMesh.new()
	var instance := MeshInstance3D.new()
	instance.name = "StudioFloor"
	instance.mesh = mesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.albedo_color = GRID_COLOUR
	instance.material_override = material

	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	mesh.surface_set_color(GRID_COLOUR)

	var e := GRID_HALF_EXTENT
	var steps := int(round(e * 2.0 / GRID_STEP))
	for i in steps + 1:
		var t := -e + i * GRID_STEP
		mesh.surface_add_vertex(Vector3(t, 0.0, -e))
		mesh.surface_add_vertex(Vector3(t, 0.0, e))
		mesh.surface_add_vertex(Vector3(-e, 0.0, t))
		mesh.surface_add_vertex(Vector3(e, 0.0, t))

	# Four corner uprights, open-topped — the "box" the floor grid sits in,
	# tall enough to frame the 1.85m rig with headroom.
	var box_height := 2.3
	for corner in [Vector2(-e, -e), Vector2(e, -e), Vector2(-e, e), Vector2(e, e)]:
		mesh.surface_add_vertex(Vector3(corner.x, 0.0, corner.y))
		mesh.surface_add_vertex(Vector3(corner.x, box_height, corner.y))

	mesh.surface_end()
	return instance
