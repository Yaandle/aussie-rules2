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
## Deliberately shows only what has a real clip. Spoil stays a pure physics
## reaction today (knockback — see PlayerController._try_spoil) with no
## AnimationTree state behind it (and no Tuning.Action of its own to hang
## one on); player_animation.gd's ACTION_STATES map is the source of truth
## for which Tuning.Action values actually animate. It shows as a disabled
## button here rather than being left out silently, so this screen stays an
## honest map of what exists versus what's still physics-only.
##
## Every tackle-family clip (TACKLED, TACKLE_GRAB, TACKLE_HELD, TACKLE_
## TAKEDOWN, KNOCKED_BACK, SMOTHERED, SMOTHER_DIVE) is an OUTCOME of a real
## contest, not a canned pose — none of them have their own button in the
## plain ACTIONS list below. Instead the CONTESTS
## group spawns a second, real PlayerController (design brief: "if I select
## the tackle features just generate another character in and run the
## simulation of the player doing the action") and runs a short, fixed,
## non-interactive scripted approach through the same real gameplay code
## every contest resolves through in a match (_resolve_tackle_contact,
## _try_bump_contact, _try_smother_contact) — not a simplified stand-in.
## This replaces the previous pass's free-roam "Tackle Sandbox" mode
## entirely (full field, switch_player, live human input) — deliberately
## removed per direct feedback: this screen is a fixed preview you click and
## watch, the same shape as every other button here, not a second thing to
## learn how to drive.

const STAND_ON := Vector3.ZERO

const CAMERA_DISTANCE := 4.0
const CAMERA_HEIGHT := 1.0

## How far left of the subject the camera sits — pushes the figure right of
## centre in frame (same trick character_backdrop.gd uses via its own
## CAMERA_SIDESTEP) so it clears the three button columns on the left
## rather than standing directly behind them.
const CAMERA_SIDESTEP := 1.5

## Pulled back and raised from the single-subject framing above — a contest
## needs room for two bodies and a few metres of approach, not a portrait
## crop of one standing figure.
const CONTEST_CAMERA_DISTANCE := 8.0
const CONTEST_CAMERA_HEIGHT := 1.6
const CONTEST_CAMERA_SIDESTEP := 1.5

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
## ACTION_STATES minus the tackle-family entries (TACKLED/TACKLE_GRAB/
## SMOTHERED/SMOTHER_DIVE) — those are contest outcomes, not standalone
## poses, and live in the CONTESTS group below instead.
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
]

## No AnimationTree state exists for this yet (see class doc) — listed so
## the gap is visible on the screen itself rather than a silent omission.
const UNIMPLEMENTED := ["SPOIL"]

## Contest scenarios: label -> ContestKind. Each spawns/reuses a second real
## PlayerController and runs a short scripted approach ending in the real
## contest resolver, exactly the "generate another character and run the
## simulation" the brief asked for.
enum ContestKind { TACKLE_SLIDE, TACKLE_LUNGE, BUMP_CLEAN, BUMP_MISS, SMOTHER }

const CONTESTS := [
	["TACKLE — SLIDE", ContestKind.TACKLE_SLIDE],
	["TACKLE — LUNGE", ContestKind.TACKLE_LUNGE],
	["BUMP — CLEAN HIT", ContestKind.BUMP_CLEAN],
	["BUMP — MISS", ContestKind.BUMP_MISS],
	["SMOTHER", ContestKind.SMOTHER],
]

## Bump has no brain-mediated trigger (_update_bump reads InputManager.
## flick_vector() directly, a raw device gesture — see that function's own
## doc comment) — a scripted vignette has no device to generate one, so
## BUMP_CLEAN/BUMP_MISS below inject the dash fields directly instead, the
## same "assign the private fields, no headless device to fake" approach
## this project's own scratch physics tests already use. This is the delay
## (seconds since launch) before that injection fires, giving the carrier
## time to close some real distance and speed first so the assist has
## something genuine to correct rather than firing at point-blank range.
const BUMP_CONTEST_TRIGGER_DELAY := 0.6

## How long an APPROACH phase waits for a contest to resolve before giving
## up and holding anyway (a missed cue shouldn't hang the screen forever).
const CONTEST_TIMEOUT := 3.0

## Synthetic vertical hop, independent of the skeleton — there is no jump
## clip to preview (MARK — AGGRESSIVE is the only clip with a jump built
## in, and it already has its own button). Arbitrary dev-tool timing, not
## a gameplay number — does not touch Tuning.
const JUMP_HEIGHT := 0.45
const JUMP_RISE_TIME := 0.28
const JUMP_FALL_TIME := 0.32

const PlayerScene := preload("res://scenes/player/player.tscn")
const BallScene := preload("res://scenes/ball/ball.tscn")

@onready var _camera: Camera3D = $Camera3D
@onready var _ui: Control = $Overlay/UI

var _subject: Node3D
var _rig: HumanoidRig
var _player_animation: PlayerAnimation
var _current_blend := Vector2.ZERO
var _state_label: Label
var _blend_label: Label
var _jump_tween: Tween

var _preview_columns: HBoxContainer
var _studio_floor: MeshInstance3D

## Non-input brain for both contest characters — every want is a plain
## field this script sets directly, the scripted-choreography equivalent
## of HumanBrain reading real Input/InputManager. wish_direction() returns
## world space unconverted (no camera to be relative to; every scenario's
## approach direction below is already authored in world space).
class ContestBrain extends PlayerBrain:
	var wish_dir := Vector3.ZERO
	var gait_value := 0.0
	var tackle_wanted := false
	var lunge_wanted := false
	var smother_wanted := false
	var kick_wanted := false

	func wish_direction(_controller: PlayerController) -> Vector3:
		return wish_dir

	func gait() -> float:
		return gait_value

	func wants_tackle() -> bool:
		return tackle_wanted

	func wants_lunge_tackle() -> bool:
		return lunge_wanted

	func wants_smother() -> bool:
		return smother_wanted

	func wants_kick() -> bool:
		return kick_wanted


## Lazily built on the first CONTESTS button press — most sessions only
## ever look at a handful of plain clips, no reason to pay for two extra
## PlayerControllers/a Ball/a collision floor before they're wanted.
var _contest_built := false
var _contest_floor: StaticBody3D
var _contest_ball: Ball
var _contest_a: PlayerController
var _contest_b: PlayerController
var _brain_a: ContestBrain
var _brain_b: ContestBrain
var _contest_status_label: Label

enum ContestStage { NONE, APPROACH, HOLD }
var _contest_kind := ContestKind.TACKLE_SLIDE
var _contest_stage := ContestStage.NONE
var _contest_timer := 0.0
var _contest_bump_triggered := false


func _ready() -> void:
	_studio_floor = _build_studio_floor()
	add_child(_studio_floor)
	_build_subject()
	_camera.rotation = Vector3.ZERO
	_camera.position = STAND_ON + Vector3(-CAMERA_SIDESTEP, CAMERA_HEIGHT, CAMERA_DISTANCE)
	_build_ui()


func _process(delta: float) -> void:
	if _subject.visible and _player_animation != null:
		_player_animation.drive(_current_blend, delta)
		_state_label.text = "STATE: %s" % String(_player_animation.current_state()).to_upper()
		var b := _player_animation.blend_position()
		_blend_label.text = "BLEND: %.2f, %.2f" % [b.x, b.y]
	_step_contest(delta)


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

	_preview_columns = HBoxContainer.new()
	_preview_columns.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview_columns.add_theme_constant_override(&"separation", 56)
	root.add_child(_preview_columns)

	_preview_columns.add_child(_build_locomotion_group())
	_preview_columns.add_child(_build_action_group())
	_preview_columns.add_child(_build_contest_group())
	_preview_columns.add_child(_build_misc_group())

	var hints := KeyHintBar.new()
	hints.position = Vector2(24.0, 674.0)
	hints.set_hints([
		{"keys": "Esc / C", "label": "Back to menu"},
		{"keys": "Click a CONTESTS button", "label": "Spawn an opponent and run that contest"},
	])
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
		button.pressed.connect(func() -> void:
			_show_single_subject()
			_current_blend = blend)
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
		button.pressed.connect(func() -> void:
			_show_single_subject()
			_player_animation.play_action(action))
		group.add_child(button)
	return group


func _build_contest_group() -> VBoxContainer:
	var group := VBoxContainer.new()
	group.mouse_filter = Control.MOUSE_FILTER_IGNORE
	group.add_theme_constant_override(&"separation", 8)
	group.add_child(UIStyle.label("CONTESTS — SPAWNS AN OPPONENT", UIStyle.SIZE_LABEL,
		UIStyle.TEXT_MUTED, UIStyle.WEIGHT_BOLD, UIStyle.TRACK_LABEL))

	for entry: Array in CONTESTS:
		var label: String = entry[0]
		var kind: ContestKind = entry[1]
		var button := Button.new()
		button.text = label
		button.custom_minimum_size = Vector2(220.0, 32.0)
		button.pressed.connect(func() -> void: _launch_contest(kind))
		group.add_child(button)

	_contest_status_label = UIStyle.label("", UIStyle.SIZE_LABEL, UIStyle.TEXT_MUTED)
	group.add_child(_contest_status_label)
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
	jump_button.pressed.connect(func() -> void:
		_show_single_subject()
		_on_jump_pressed())
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


## Swaps which subject is visible/live — the bare single-figure rig for
## every plain locomotion/action/jump button, or the two-body contest for
## CONTESTS. Both keep existing once built (contest bodies keep simulating
## physics even while hidden — there are only ever these three bodies in
## this scene, no ambiguity for _nearest_player's group scan to trip over,
## same reasoning the old sandbox mode already relied on), this just picks
## which one is on screen and getting driven by _process.
func _show_single_subject() -> void:
	_subject.visible = true
	_camera.position = STAND_ON + Vector3(-CAMERA_SIDESTEP, CAMERA_HEIGHT, CAMERA_DISTANCE)
	_camera.rotation = Vector3.ZERO
	if _contest_built:
		_contest_a.visible = false
		_contest_b.visible = false
		_contest_ball.visible = false
	_contest_stage = ContestStage.NONE


func _show_contest() -> void:
	_subject.visible = false
	_contest_a.visible = true
	_contest_b.visible = true
	_contest_ball.visible = true
	_camera.position = STAND_ON \
		+ Vector3(-CONTEST_CAMERA_SIDESTEP, CONTEST_CAMERA_HEIGHT, CONTEST_CAMERA_DISTANCE)
	_camera.rotation = Vector3.ZERO


# ── Contests: real PlayerController/Ball physics, two bodies, a short
# scripted approach through the real gameplay resolvers, fixed camera —
# not a free-roam sandbox. See ContestKind/CONTESTS above. ───────────────

func _ensure_contest_built() -> void:
	if _contest_built:
		return
	_contest_built = true

	_contest_floor = _build_contest_floor()
	add_child(_contest_floor)

	# Same-frame-construction-race workaround (docs/HANDOVER.md, Tackle
	# Sandbox + TACKLED entries): a handful of throwaway PlayerControllers
	# spawned and freed first, ahead of the two that actually matter.
	for i in 3:
		var throwaway := PlayerScene.instantiate()
		add_child(throwaway)
		throwaway.queue_free()

	_contest_ball = BallScene.instantiate()
	add_child(_contest_ball)

	_contest_a = PlayerScene.instantiate()
	_contest_a.team = Tuning.Team.HOME
	add_child(_contest_a)
	_contest_a.global_position = Vector3(-2.0, 0.0, 0.0)
	_brain_a = ContestBrain.new()
	_contest_a.set_brain(_brain_a)

	_contest_b = PlayerScene.instantiate()
	_contest_b.team = Tuning.Team.AWAY
	(_contest_b.get_node("Rig") as HumanoidRig).away_kit = true
	add_child(_contest_b)
	_contest_b.global_position = Vector3(2.0, 0.0, 0.0)   # distinct from A's spot from frame 0
	_brain_b = ContestBrain.new()
	_contest_b.set_brain(_brain_b)


## A small, flat collision floor — deliberately not the full 165x135m
## Field scene (design brief: "remove it... instead of me being able to
## move the player around freely it is fixed"); a fixed-camera vignette
## only ever needs a few metres of ground under two bodies, not a full
## oval with markings and goalposts. Same StaticBody3D/BoxShape3D shape
## and collision_layer=1/mask=0 as Field's own "Ground" node, just sized
## for this screen instead.
func _build_contest_floor() -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "ContestFloor"
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20.0, 2.0, 20.0)
	shape.shape = box
	shape.position = Vector3(0.0, -1.0, 0.0)
	body.add_child(shape)
	return body


## Resets both contest bodies' timers/possession/brain wants, then sets up
## whichever scenario `kind` is — see ContestKind. Re-callable: pressing
## the same CONTESTS button again just tears down and re-runs the same
## scenario from scratch, the "generate another character and run the
## simulation" behaviour applying every time, not just the first.
func _launch_contest(kind: ContestKind) -> void:
	_ensure_contest_built()
	_show_contest()

	_contest_a.velocity = Vector3.ZERO
	_contest_b.velocity = Vector3.ZERO
	_contest_a._stun_timer = 0.0
	_contest_b._stun_timer = 0.0
	_contest_a._action = Tuning.Action.NONE
	_contest_b._action = Tuning.Action.NONE
	_contest_a._bump_dash_timer = 0.0
	_contest_a._bump_dash_active = false
	_contest_a._bump_cooldown = 0.0
	_contest_a._lunge_tap_cooldown = 0.0
	_contest_a._smother_dive_timer = 0.0
	_contest_a._smother_dive_cooldown = 0.0
	_contest_a._knockdown_hop_timer = 0.0
	_contest_b._knockdown_hop_timer = 0.0
	_contest_a.drop_ball()
	_contest_b.drop_ball()

	_brain_a.wish_dir = Vector3.ZERO
	_brain_a.gait_value = 0.0
	_brain_a.tackle_wanted = false
	_brain_a.lunge_wanted = false
	_brain_a.smother_wanted = false
	_brain_a.kick_wanted = false
	_brain_b.wish_dir = Vector3.ZERO
	_brain_b.gait_value = 0.0
	_brain_b.tackle_wanted = false
	_brain_b.lunge_wanted = false
	_brain_b.smother_wanted = false
	_brain_b.kick_wanted = false

	match kind:
		ContestKind.TACKLE_SLIDE:
			_contest_a.global_position = Vector3(0.0, 0.0, -3.0)
			_contest_a.rotation.y = deg_to_rad(180.0)
			_contest_b.global_position = Vector3(0.0, 0.0, 0.5)
			_contest_b.rotation.y = 0.0
			_contest_b.give_possession(_contest_ball)
			_brain_a.wish_dir = Vector3(0.0, 0.0, 1.0)
			_brain_a.gait_value = 1.0
			_brain_a.tackle_wanted = true
		ContestKind.TACKLE_LUNGE:
			_contest_a.global_position = Vector3(0.0, 0.0, -1.5)
			_contest_a.rotation.y = deg_to_rad(180.0)
			_contest_b.global_position = Vector3(0.0, 0.0, 0.5)
			_contest_b.rotation.y = 0.0
			_contest_b.give_possession(_contest_ball)
			_brain_a.wish_dir = Vector3(0.0, 0.0, 1.0)
			_brain_a.gait_value = 0.6
			_brain_a.lunge_wanted = true
		ContestKind.BUMP_CLEAN:
			_contest_a.global_position = Vector3(0.0, 0.0, -2.0)
			_contest_a.rotation.y = deg_to_rad(180.0)
			_contest_b.global_position = Vector3(0.0, 0.0, 3.0)
			_contest_b.rotation.y = 0.0
			_contest_b.give_possession(_contest_ball)
			_brain_b.wish_dir = Vector3(0.0, 0.0, -1.0)
			_brain_b.gait_value = 1.0
		ContestKind.BUMP_MISS:
			_contest_a.global_position = Vector3(0.0, 0.0, -2.0)
			_contest_a.rotation.y = deg_to_rad(180.0)
			_contest_b.global_position = Vector3(3.0, 0.0, -2.0)   # off to the side, out of the swing
			_contest_b.rotation.y = 0.0
		ContestKind.SMOTHER:
			_contest_a.global_position = Vector3(0.0, 0.0, -2.5)
			_contest_a.rotation.y = deg_to_rad(180.0)
			_contest_b.global_position = Vector3(0.0, 0.0, 0.3)
			_contest_b.rotation.y = 0.0
			_contest_b.give_possession(_contest_ball)
			_brain_a.smother_wanted = true
			_brain_b.kick_wanted = true

	_contest_kind = kind
	_contest_stage = ContestStage.APPROACH
	_contest_timer = 0.0
	_contest_bump_triggered = false


## Drives the running scenario each frame. Bump's dash is injected directly
## (see BUMP_CONTEST_TRIGGER_DELAY's own doc comment); everything else is
## fully brain-mediated — _update_smother/_try_tackle/_try_lunge_tackle all
## fire on their own the moment the scripted approach brings the bodies
## into real range, through the identical resolvers a real match uses.
## Once resolved (or CONTEST_TIMEOUT expires), this goes quiet — the
## contest bodies keep simulating on their own (a knockdown's own Action
## duration naturally plays out the fall AND the recovery with no extra
## logic needed here), it just stops being this function's job.
func _step_contest(delta: float) -> void:
	if _contest_stage == ContestStage.NONE:
		return
	_contest_timer += delta

	if _contest_stage == ContestStage.APPROACH:
		if _contest_kind == ContestKind.BUMP_CLEAN or _contest_kind == ContestKind.BUMP_MISS:
			if not _contest_bump_triggered and _contest_timer >= BUMP_CONTEST_TRIGGER_DELAY:
				_contest_bump_triggered = true
				var dir: Vector3
				if _contest_kind == ContestKind.BUMP_CLEAN:
					dir = _contest_b.global_position - _contest_a.global_position
				else:
					dir = Vector3(1.0, 0.0, 0.0)   # a clean swing at empty air
				dir.y = 0.0
				_contest_a._bump_dash_direction = dir.normalized() if dir.length_squared() > 0.0001 \
					else Vector3.FORWARD
				_contest_a._bump_dash_timer = Tuning.BUMP_DASH_DURATION
				_contest_a._bump_dash_active = true
				_contest_a._bump_cooldown = Tuning.BUMP_COOLDOWN

		# TACKLE_GRAB/TACKLE_TAKEDOWN are safe to treat as "resolved" —
		# _try_tackle()/_try_lunge_tackle() only ever start them in the same
		# call that also resolves the target's own TACKLE_HELD/TACKLED, so
		# each pair is simultaneous. SMOTHER_DIVE is NOT: unlike a tackle,
		# launching the dive only starts a real travel window
		# (Tuning.SMOTHER_DIVE_DURATION) before it either connects or
		# doesn't — treating "started diving" as "resolved" would cut the
		# vignette off mid-flight, before _try_smother_contact() ever gets a
		# chance to actually land it. Bump has no such false-positive: its
		# own dash never sets an Action on the bumper at all while travelling
		# (see _update_bump's own doc comment), only on resolution.
		var resolved := _contest_a._action == Tuning.Action.TACKLED \
			or _contest_a._action == Tuning.Action.TACKLE_GRAB \
			or _contest_a._action == Tuning.Action.TACKLE_TAKEDOWN \
			or _contest_b._action == Tuning.Action.TACKLED \
			or _contest_b._action == Tuning.Action.TACKLE_HELD \
			or _contest_b._action == Tuning.Action.KNOCKED_BACK \
			or _contest_b._action == Tuning.Action.SMOTHERED
		if resolved or _contest_timer > CONTEST_TIMEOUT:
			_contest_stage = ContestStage.HOLD

	_contest_status_label.text = "A: %s   B: %s" % [
		Tuning.Action.keys()[_contest_a._action], Tuning.Action.keys()[_contest_b._action],
	]


# ── Studio floor (single-subject preview only) ────────────────────────

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
