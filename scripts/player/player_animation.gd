class_name PlayerAnimation
extends Node

## The AnimationTree: a BlendSpace2D for locomotion inside a state
## machine for discrete actions (design doc §5).
##
## The blend space is keyed on (strafe, forward speed) exactly as the
## brief specifies, and both axes come straight off the character's
## actual velocity in body space — not off the input. That distinction is
## the whole reason this is worth building: when a sprinting player
## throws the stick sideways, the facing snaps round faster than the
## momentum does, the velocity spends half a second pointing off to one
## side of the body, and the strafe axis genuinely lights up. The
## animation is reporting the physics, not decorating it.
##
## WHY THE TREE IS BUILT IN CODE: there are no animation assets yet, so
## the clips are generated at load (humanoid_animations.gd) and the
## graph has to be assembled around them at the same moment. Once real
## mocap/Mixamo-style clips are imported this whole `_build_*` half goes
## away and `tree_root` gets authored in the editor instead — the blend
## point layout, the state names and the public methods below are already
## the ones it will use, so nothing outside this file changes. The rig
## itself (humanoid_rig.gd) already exposes a Skeleton3D whose bone names
## match Godot's SkeletonProfileHumanoid, so an imported clip's bone
## tracks land on it without renaming.
##
## NOT YET WIRED: root motion. §5 wants tackles and marks driven by root
## motion so a contest visibly decides where bodies end up, with
## locomotion staying code-driven. That needs contest mechanics and a
## second player to exist first; the hook is AnimationTree.root_motion_
## track plus get_root_motion_position() in the controller's move step.

## Blend point layout. Must agree with the clip names in
## HumanoidAnimations.GAITS. x = strafe (-1 left, +1 right),
## y = forward speed (-1 backpedal, +1 full sprint), both normalised
## against Tuning.SPRINT_SPEED.
const BLEND_POINTS := [
	[Vector2(0.0, 0.0), &"idle"],
	[Vector2(0.0, 0.55), &"jog_fwd"],
	[Vector2(0.0, 1.0), &"run_fwd"],
	[Vector2(0.0, -1.0), &"run_back"],
	[Vector2(-1.0, 0.0), &"strafe_l"],
	[Vector2(1.0, 0.0), &"strafe_r"],
	[Vector2(-0.75, 0.75), &"run_fwd_l"],
	[Vector2(0.75, 0.75), &"run_fwd_r"],
]

## Tackle-attempt and tackled-reaction states join this list when the
## mechanics that trigger them exist.
const ACTION_STATES := {
	Tuning.Action.KICK: &"kick",
	Tuning.Action.HANDBALL: &"handball",
	Tuning.Action.BOUNCE: &"bounce",
	Tuning.Action.MARK_SAFE: &"mark_safe",
	Tuning.Action.MARK_RUNNING: &"mark_running",
	Tuning.Action.MARK_AGGRESSIVE: &"mark_aggressive",
}

const LOCOMOTION_STATE := &"locomotion"
const BLEND_SMOOTHING := 14.0     ## exponential rate; stops the blend snapping
const ACTION_BLEND_IN := 0.10     ## s
const ACTION_BLEND_OUT := 0.18    ## s

@export var rig_path: NodePath = ^"../Rig"
@export var animation_player_path: NodePath = ^"../AnimationPlayer"
@export var animation_tree_path: NodePath = ^"../AnimationTree"

var _rig: Node3D
var _player: AnimationPlayer
var _tree: AnimationTree
var _playback: AnimationNodeStateMachinePlayback
var _blend := Vector2.ZERO
var _blend_parameter := ""


func _ready() -> void:
	_rig = get_node_or_null(rig_path) as Node3D
	_player = get_node_or_null(animation_player_path) as AnimationPlayer
	_tree = get_node_or_null(animation_tree_path) as AnimationTree
	if _rig == null or _player == null or _tree == null:
		push_error("PlayerAnimation: rig / AnimationPlayer / AnimationTree not found")
		return

	# Track paths are authored relative to the rig root, so both mixers
	# have to resolve against it.
	_player.root_node = _player.get_path_to(_rig)
	_tree.root_node = _tree.get_path_to(_rig)

	# PLACEHOLDER: delete this line once real mocap clips are imported —
	# HumanoidAnimations writes bone tracks against the same
	# SkeletonProfileHumanoid-compatible names a real import would use, so
	# swapping this call for an authored AnimationLibrary needs no other
	# change here.
	_player.add_animation_library(&"", HumanoidAnimations.build_library(
		HumanoidRig.HIP_HEIGHT))

	_tree.tree_root = _build_state_machine()
	_tree.anim_player = _tree.get_path_to(_player)
	_tree.active = true
	_playback = _tree.get("parameters/playback")
	_blend_parameter = "parameters/%s/blend_position" % LOCOMOTION_STATE


## Called every physics frame by the controller with the body-space
## velocity from PlayerController.locomotion_blend().
func drive(blend: Vector2, delta: float) -> void:
	if _tree == null or not _tree.active:
		return
	_blend = _blend.lerp(blend, 1.0 - exp(-BLEND_SMOOTHING * delta))
	_tree.set(_blend_parameter, _blend)


func play_action(action: Tuning.Action) -> void:
	if _playback == null:
		return
	var state: StringName = ACTION_STATES.get(action, &"")
	if state != &"":
		_playback.travel(state)


func current_state() -> StringName:
	if _playback == null:
		return &""
	return _playback.get_current_node()


func blend_position() -> Vector2:
	return _blend


# ── Graph construction ───────────────────────────────────────────────

func _build_state_machine() -> AnimationNodeStateMachine:
	var machine := AnimationNodeStateMachine.new()
	machine.add_node(LOCOMOTION_STATE, _build_blend_space(), Vector2(260.0, 140.0))
	machine.add_transition(&"Start", LOCOMOTION_STATE,
		_transition(0.0, AnimationNodeStateMachineTransition.SWITCH_MODE_IMMEDIATE,
			AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO))

	var row := 0
	for action in ACTION_STATES:
		var state: StringName = ACTION_STATES[action]
		var clip := AnimationNodeAnimation.new()
		clip.animation = state
		machine.add_node(state, clip, Vector2(560.0, 40.0 + 110.0 * row))
		row += 1

		# Entered on demand via playback.travel(); leaves on its own the
		# moment the clip finishes, so no caller has to remember to exit.
		machine.add_transition(LOCOMOTION_STATE, state,
			_transition(ACTION_BLEND_IN,
				AnimationNodeStateMachineTransition.SWITCH_MODE_IMMEDIATE,
				AnimationNodeStateMachineTransition.ADVANCE_MODE_ENABLED))
		machine.add_transition(state, LOCOMOTION_STATE,
			_transition(ACTION_BLEND_OUT,
				AnimationNodeStateMachineTransition.SWITCH_MODE_AT_END,
				AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO))
	return machine


func _build_blend_space() -> AnimationNodeBlendSpace2D:
	var space := AnimationNodeBlendSpace2D.new()
	space.min_space = Vector2(-1.0, -1.0)
	space.max_space = Vector2(1.0, 1.0)
	space.snap = Vector2(0.05, 0.05)
	space.blend_mode = AnimationNodeBlendSpace2D.BLEND_MODE_INTERPOLATED
	space.auto_triangles = true
	space.x_label = "strafe"
	space.y_label = "forward"
	for point: Array in BLEND_POINTS:
		var clip := AnimationNodeAnimation.new()
		clip.animation = point[1] as StringName
		space.add_blend_point(clip, point[0] as Vector2)
	return space


func _transition(xfade: float, switch_mode: int,
		advance_mode: int) -> AnimationNodeStateMachineTransition:
	var transition := AnimationNodeStateMachineTransition.new()
	transition.xfade_time = xfade
	transition.switch_mode = switch_mode
	transition.advance_mode = advance_mode
	return transition
