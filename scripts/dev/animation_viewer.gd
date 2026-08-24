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

const FIELD_SCENE := preload("res://scenes/field/field.tscn")

## Same offset character_backdrop.gd uses: stands just inside the centre
## square's boundary line so the only marking in shot is one hairline
## stripe, not the centre circles.
const STAND_ON := Vector3(Tuning.CENTRE_SQUARE_SIZE * 0.5 - 1.6, 0.0, 0.0)

const CAMERA_DISTANCE := 3.75
const CAMERA_HEIGHT := 1.05

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
	add_child(FIELD_SCENE.instantiate())
	_build_subject()
	_camera.rotation = Vector3.ZERO
	_camera.position = STAND_ON + Vector3(0.0, CAMERA_HEIGHT, CAMERA_DISTANCE)
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
