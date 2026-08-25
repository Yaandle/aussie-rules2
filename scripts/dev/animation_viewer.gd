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
## Deliberately shows only what has a real clip. Bump/spoil/smother resolve
## through pure physics reactions today (knockback — see player_controller.gd)
## with no AnimationTree state behind them (and no Tuning.Action of their own
## to hang one on); player_animation.gd's ACTION_STATES map is the source of
## truth for which Tuning.Action values actually animate. Those show as
## disabled buttons here rather than being left out silently, so this screen
## stays an honest map of what exists versus what's still physics-only. A
## real tackle connecting (Slide or Lunge, not a bump) is no longer in that
## group — see Tuning.Action.TACKLED and its TACKLED button below.
##
## A second mode, TACKLE SANDBOX, sits alongside the clip preview for
## exactly the physics-only contests the preview can't show: two real
## PlayerController instances (the same player.tscn/ball.tscn/field.tscn
## full_game.gd and kick_to_kick.gd instantiate, not a bespoke stand-in),
## so Slide/Lunge resolve through the real _resolve_tackle_contact —
## closing speed, approach angle, stun/cooldown, all of it. kick_to_kick's
## AI rival always sprints once it has the ball (AIBrain._think_carrying),
## which is exactly what makes deliberately setting up a tackle attempt
## there hard — here, whichever player ISN'T currently controlled gets a
## plain idle PlayerBrain (wish_direction always ZERO) instead of an
## AIBrain, so it just stands wherever it was last driven to rather than
## running off, and switch_player (the same action full_game.gd's human-
## slot cycling already uses) swaps which one has HumanBrain.

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
	["HIT-OUT", Tuning.Action.HIT_OUT],
	["TACKLED", Tuning.Action.TACKLED],
]

## No AnimationTree state exists for these yet (see class doc) — listed so
## the gap is visible on the screen itself rather than a silent omission.
## Tackle moved out of this list once Action.TACKLED landed — bump/spoil/
## smother stay physics-only reactions with no clip of their own.
const UNIMPLEMENTED := ["BUMP", "SPOIL", "SMOTHER"]

## Synthetic vertical hop, independent of the skeleton — there is no jump
## clip to preview (MARK — AGGRESSIVE is the only clip with a jump built
## in, and it already has its own button). Arbitrary dev-tool timing, not
## a gameplay number — does not touch Tuning.
const JUMP_HEIGHT := 0.45
const JUMP_RISE_TIME := 0.28
const JUMP_FALL_TIME := 0.32

enum ViewMode { CLIP_PREVIEW, TACKLE_SANDBOX }

const PlayerScene := preload("res://scenes/player/player.tscn")
const BallScene := preload("res://scenes/ball/ball.tscn")
const FieldScene := preload("res://scenes/field/field.tscn")
const BroadcastCameraScene := preload("res://scenes/camera/broadcast_camera.tscn")

## Starting gap for RESET — close enough that either side can reach a
## tackle attempt in a couple of steps, far enough that a Slide's dive-in
## (TACKLE_SLIDE_DIVE_RANGE) has room to actually fire instead of always
## starting already inside TACKLE_RADIUS.
const SANDBOX_START_GAP := 3.0

@onready var _camera: Camera3D = $Camera3D
@onready var _ui: Control = $Overlay/UI

var _mode := ViewMode.CLIP_PREVIEW

var _subject: Node3D
var _rig: HumanoidRig
var _player_animation: PlayerAnimation
var _current_blend := Vector2.ZERO
var _state_label: Label
var _blend_label: Label
var _jump_tween: Tween

var _preview_columns: HBoxContainer
var _sandbox_panel: VBoxContainer

var _sandbox_field: Node3D
var _sandbox_camera: BroadcastCamera
var _player_a: PlayerController
var _player_b: PlayerController
var _sandbox_ball: Ball
var _active_index := 0   # 0 = player A has HumanBrain, 1 = player B does

var _sandbox_status_label: Label
var _studio_floor: MeshInstance3D


func _ready() -> void:
	_studio_floor = _build_studio_floor()
	add_child(_studio_floor)
	_build_subject()
	_camera.rotation = Vector3.ZERO
	_camera.position = STAND_ON + Vector3(-CAMERA_SIDESTEP, CAMERA_HEIGHT, CAMERA_DISTANCE)
	_build_tackle_sandbox()
	_build_ui()
	_set_mode(ViewMode.CLIP_PREVIEW)


func _process(delta: float) -> void:
	if _player_animation != null:
		_player_animation.drive(_current_blend, delta)
		_state_label.text = "STATE: %s" % String(_player_animation.current_state()).to_upper()
		var b := _player_animation.blend_position()
		_blend_label.text = "BLEND: %.2f, %.2f" % [b.x, b.y]
	if _mode == ViewMode.TACKLE_SANDBOX:
		_update_sandbox_status()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"pause") or event.is_action_pressed(&"character_menu"):
		SceneWipe.change_scene("res://scenes/ui/main_menu.tscn")
		return
	if _mode == ViewMode.TACKLE_SANDBOX and event.is_action_pressed(&"switch_player"):
		_set_active_player(1 - _active_index)


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

	root.add_child(_build_mode_toggle())

	var status := HBoxContainer.new()
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status.add_theme_constant_override(&"separation", 24)
	root.add_child(status)
	_state_label = UIStyle.label("STATE: —", UIStyle.SIZE_LABEL, UIStyle.TEXT_MUTED)
	_blend_label = UIStyle.label("BLEND: 0.00, 0.00", UIStyle.SIZE_LABEL, UIStyle.TEXT_MUTED)
	status.add_child(_state_label)
	status.add_child(_blend_label)

	_preview_columns = HBoxContainer.new()
	_preview_columns.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview_columns.add_theme_constant_override(&"separation", 56)
	root.add_child(_preview_columns)

	_preview_columns.add_child(_build_locomotion_group())
	_preview_columns.add_child(_build_action_group())
	_preview_columns.add_child(_build_misc_group())

	_sandbox_panel = _build_sandbox_ui()
	root.add_child(_sandbox_panel)

	var hints := KeyHintBar.new()
	hints.position = Vector2(24.0, 674.0)
	hints.set_hints([
		{"keys": "Esc / C", "label": "Back to menu"},
		{"keys": "Move / Tackle (hold) / Lunge (tap)", "label": "Sandbox: active player"},
		{"keys": "Tab", "label": "Sandbox: switch control"},
	])
	_ui.add_child(hints)


func _build_mode_toggle() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override(&"separation", 12)

	var toggle_group := ButtonGroup.new()
	var preview_button := Button.new()
	preview_button.text = "CLIP PREVIEW"
	preview_button.toggle_mode = true
	preview_button.button_group = toggle_group
	preview_button.button_pressed = true
	preview_button.custom_minimum_size = Vector2(180.0, 32.0)
	preview_button.pressed.connect(func() -> void: _set_mode(ViewMode.CLIP_PREVIEW))
	row.add_child(preview_button)

	var sandbox_button := Button.new()
	sandbox_button.text = "TACKLE SANDBOX"
	sandbox_button.toggle_mode = true
	sandbox_button.button_group = toggle_group
	sandbox_button.custom_minimum_size = Vector2(180.0, 32.0)
	sandbox_button.pressed.connect(func() -> void: _set_mode(ViewMode.TACKLE_SANDBOX))
	row.add_child(sandbox_button)

	return row


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


# ── Tackle sandbox: real PlayerController/Ball/Field physics, two bodies,
# whichever one isn't currently controlled just stands idle instead of
# running off like kick_to_kick's AIBrain rival does the moment it has the
# ball. ─────────────────────────────────────────────────────────────────

func _build_tackle_sandbox() -> void:
	_sandbox_field = FieldScene.instantiate()
	add_child(_sandbox_field)

	_sandbox_ball = BallScene.instantiate()
	add_child(_sandbox_ball)

	_player_a = PlayerScene.instantiate()
	_player_a.team = Tuning.Team.HOME
	add_child(_player_a)

	_player_b = PlayerScene.instantiate()
	_player_b.team = Tuning.Team.AWAY
	(_player_b.get_node("Rig") as HumanoidRig).away_kit = true
	add_child(_player_b)

	# target must be valid before add_child — _ready() calls recenter()
	# immediately, which no-ops on a null target.
	_sandbox_camera = BroadcastCameraScene.instantiate()
	_sandbox_camera.ball = _sandbox_ball
	_sandbox_camera.target = _player_a
	add_child(_sandbox_camera)

	_reset_sandbox()


## Fresh start line, ball to B, A in control — same "RESET" a dev reaches
## for after any attempt, successful or not, rather than hunting down every
## timer a tackle attempt could have touched by hand. Facing each other, not
## away — a straight-line first step toward the other player is the whole
## point of a tackle-testing sandbox, not a 180-degree turn before either
## body starts moving anywhere useful.
func _reset_sandbox() -> void:
	_player_a.global_position = Vector3(0.0, 0.0, -SANDBOX_START_GAP * 0.5)
	_player_a.rotation.y = deg_to_rad(180.0)
	_player_a.velocity = Vector3.ZERO
	_player_a._stun_timer = 0.0
	_player_a._lunge_tap_cooldown = 0.0

	_player_b.global_position = Vector3(0.0, 0.0, SANDBOX_START_GAP * 0.5)
	_player_b.rotation.y = 0.0
	_player_b.velocity = Vector3.ZERO
	_player_b._stun_timer = 0.0
	_player_b._lunge_tap_cooldown = 0.0

	_player_a.drop_ball()
	_player_b.drop_ball()
	_player_b.give_possession(_sandbox_ball)

	_active_index = 0
	_apply_active_brain()
	_sandbox_camera.recenter()


func _give_ball_to(player: PlayerController) -> void:
	_player_a.drop_ball()
	_player_b.drop_ball()
	player.give_possession(_sandbox_ball)


func _set_active_player(index: int) -> void:
	_active_index = index
	_apply_active_brain()


## HumanBrain reads real Input/InputManager directly, so the active player
## gets every real binding for free — move, hold Tackle for Slide, tap
## Lunge tackle, exactly the same actions full_game.gd/kick_to_kick.gd
## wire up, nothing sandbox-specific to reimplement. The other player gets
## a bare PlayerBrain (every want defaults false, wish_direction always
## ZERO) rather than an AIBrain — that's the whole point: it stands exactly
## where it was last driven to instead of sprinting off with the ball.
func _apply_active_brain() -> void:
	var active := _player_a if _active_index == 0 else _player_b
	var idle := _player_b if _active_index == 0 else _player_a
	active.set_brain(HumanBrain.new())
	active.camera = _sandbox_camera.camera()
	idle.set_brain(PlayerBrain.new())
	_sandbox_camera.switch_target(active)


func _update_sandbox_status() -> void:
	var active_name := "A" if _active_index == 0 else "B"
	var carrier := "loose"
	if _player_a.is_carrying():
		carrier = "A"
	elif _player_b.is_carrying():
		carrier = "B"
	_sandbox_status_label.text = ("ACTIVE: %s   BALL: %s\n" \
		+ "A  stun=%.2f  lunge cd=%.2f\n" \
		+ "B  stun=%.2f  lunge cd=%.2f") % [
			active_name, carrier,
			_player_a._stun_timer, _player_a._lunge_tap_cooldown,
			_player_b._stun_timer, _player_b._lunge_tap_cooldown,
		]


func _build_sandbox_ui() -> VBoxContainer:
	var group := VBoxContainer.new()
	group.mouse_filter = Control.MOUSE_FILTER_IGNORE
	group.add_theme_constant_override(&"separation", 8)
	group.add_child(UIStyle.label("TACKLE SANDBOX", UIStyle.SIZE_LABEL,
		UIStyle.TEXT_MUTED, UIStyle.WEIGHT_BOLD, UIStyle.TRACK_LABEL))

	_sandbox_status_label = UIStyle.label("ACTIVE: A   BALL: B", UIStyle.SIZE_LABEL, UIStyle.TEXT_MUTED)
	group.add_child(_sandbox_status_label)

	var reset_button := Button.new()
	reset_button.text = "RESET"
	reset_button.custom_minimum_size = Vector2(200.0, 32.0)
	reset_button.pressed.connect(_reset_sandbox)
	group.add_child(reset_button)

	var give_a := Button.new()
	give_a.text = "GIVE BALL TO A"
	give_a.custom_minimum_size = Vector2(200.0, 32.0)
	give_a.pressed.connect(func() -> void: _give_ball_to(_player_a))
	group.add_child(give_a)

	var give_b := Button.new()
	give_b.text = "GIVE BALL TO B"
	give_b.custom_minimum_size = Vector2(200.0, 32.0)
	give_b.pressed.connect(func() -> void: _give_ball_to(_player_b))
	group.add_child(give_b)

	return group


## Swaps which subject is visible/live rather than tearing either down —
## both keep existing (and, for the sandbox pair, keep simulating physics)
## regardless of which is on screen; there are only ever these two bodies
## in this scene so there's no ambiguity for _nearest_player's group scan
## to trip over.
func _set_mode(mode: ViewMode) -> void:
	_mode = mode
	var preview_on := mode == ViewMode.CLIP_PREVIEW

	_subject.visible = preview_on
	_studio_floor.visible = preview_on
	_camera.current = preview_on
	_preview_columns.visible = preview_on

	_sandbox_field.visible = not preview_on
	_player_a.visible = not preview_on
	_player_b.visible = not preview_on
	_sandbox_ball.visible = not preview_on
	_sandbox_camera.camera().current = not preview_on
	_sandbox_panel.visible = not preview_on
	if not preview_on:
		_reset_sandbox()


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
