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

## Spoil stays a pure physics reaction (no Tuning.Action of its own — see
## PlayerController._try_spoil) and joins this list if that ever changes.
## Bump's own dash (_update_bump) is still a pure movement mechanic like
## Slide's dive-in, with no Action of its own; only its outcomes reuse
## existing clips — a clean connect plays Action.KNOCKED_BACK on the
## carrier, a whiffed dash plays Action.TACKLED on the bumper themselves
## (see _resolve_bump_contact/_resolve_bump_miss), a mistimed/glancing
## connect stays animation-free. Tackle now splits by type: a Slide
## connect plays TACKLE_GRAB/TACKLE_HELD (tackler/target, both stay
## standing); a Lunge connect plays TACKLE_TAKEDOWN/TACKLED (tackler/
## target, target goes all the way down) — see Action.TACKLE_HELD's own
## comment for why the two read differently.
const ACTION_STATES := {
	Tuning.Action.KICK: &"kick",
	Tuning.Action.HANDBALL: &"handball",
	Tuning.Action.BOUNCE: &"bounce",
	Tuning.Action.MARK_SAFE: &"mark_safe",
	Tuning.Action.MARK_RUNNING: &"mark_running",
	Tuning.Action.MARK_AGGRESSIVE: &"mark_aggressive",
	Tuning.Action.MARK_SAFE_MISS: &"mark_safe_miss",
	Tuning.Action.MARK_RUNNING_MISS: &"mark_running_miss",
	Tuning.Action.HIT_OUT: &"hit_out",
	Tuning.Action.TACKLED: &"tackled",
	Tuning.Action.TACKLE_GRAB: &"tackle_grab",
	Tuning.Action.TACKLE_HELD: &"tackle_held",
	Tuning.Action.TACKLE_TAKEDOWN: &"tackle_takedown",
	Tuning.Action.KNOCKED_BACK: &"knocked_back",
	Tuning.Action.SMOTHERED: &"smothered",
	Tuning.Action.SMOTHER_DIVE: &"smother_dive",
}

const LOCOMOTION_STATE := &"locomotion"
const BLEND_SMOOTHING := 14.0     ## exponential rate; stops the blend snapping
const ACTION_BLEND_IN := 0.10     ## s
const ACTION_BLEND_OUT := 0.18    ## s

## HumanoidRig's own Boot mesh sits 0.07m below the ankle (Foot) bone
## (_box_on("Boot"..., size.y=0.07, offset.y=-0.035) — a box centred 0.035m
## below the bone with half-height 0.035m puts its bottom edge there), not
## a separately eyeballed number. Below this, the boot mesh is visibly
## through the flat y=0 ground plane every mode's Field actually uses.
##
## FLAGGED FOR 4A/4C: this number is specific to the PROCEDURAL Boot mesh
## and does not re-derive itself from an imported character (humanoid_rig.
## gd's "Import swap" — a Blender model's own sole-to-ankle-bone distance
## will almost never be exactly 0.07m). Once a real import exists and feet
## clip through or float above the turf, this is the constant to recheck/
## recalibrate against the new model's actual geometry — not a bug in the
## clamp logic itself.
const BOOT_GROUND_CLEARANCE := 0.07
const GROUND_CLAMP_FEET: Array[StringName] = [&"LeftFoot", &"RightFoot"]

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

	_player.add_animation_library(&"", _build_merged_library())

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


## Runs on the render frame (AnimationTree's own default process timing,
## decoupled from PlayerController's physics-frame drive() above) so it
## sees this frame's already-mixed skeleton pose — see _clamp_feet_to_
## ground()'s own doc comment for what it does and why it's a whole-body
## lift rather than real per-leg IK. Node order matters: this only sees a
## fresh pose because AnimationTree is an earlier sibling than
## PlayerAnimation under both player.tscn and animation_viewer.gd's
## equivalent (Godot processes siblings in child order), so its mixing has
## already run for this same frame by the time this fires.
func _process(_delta: float) -> void:
	_clamp_feet_to_ground()


## A deliberately simple ground-contact fix, not full per-leg IK: the
## ground here is always flat (no terrain), so the only correction a
## clipping foot actually needs is "move up until it isn't clipping" —
## lifting the whole rig by whichever foot is clipping worst does that
## without re-solving each leg's hip/knee angles to replant that exact
## foot in place (real two-bone IK needs a pole vector to avoid ever
## bending a knee the wrong way, which isn't worth the risk here for a
## correction whose only job is "stop going through the floor"). That
## preserves every authored pose's shape exactly; the trade-off is it
## can't independently re-plant one foot while the other stays put, so it
## stops clipping rather than fully locking a stance foot to the ground.
func _clamp_feet_to_ground() -> void:
	if _rig == null:
		return
	var skeleton := _rig.get_node_or_null(^"Skeleton3D") as Skeleton3D
	if skeleton == null:
		return
	var hips_idx := skeleton.find_bone(&"Hips")
	if hips_idx < 0:
		return
	var deepest := 0.0
	for bone_name: StringName in GROUND_CLAMP_FEET:
		var idx := skeleton.find_bone(bone_name)
		if idx < 0:
			continue
		var ankle_y := skeleton.get_bone_global_pose(idx).origin.y
		deepest = minf(deepest, ankle_y - BOOT_GROUND_CLEARANCE)
	if deepest >= 0.0:
		return
	var hips_pos := skeleton.get_bone_pose_position(hips_idx)
	skeleton.set_bone_pose_position(hips_idx, hips_pos + Vector3(0.0, -deepest, 0.0))


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


# ── Clip library ─────────────────────────────────────────────────────

## Starts from HumanoidAnimations' generated set (always complete — every
## BLEND_POINTS/ACTION_STATES name has an entry) and overrides individual
## clips with whatever HumanoidRig pulled out of the imported model's own
## AnimationPlayer (see humanoid_rig.gd's _extract_imported_animations),
## keyed by the same clip names. A clip not yet authored in Blender keeps
## its procedural fallback; nothing else here has to know which is which.
func _build_merged_library() -> AnimationLibrary:
	var library := HumanoidAnimations.build_library(HumanoidRig.HIP_HEIGHT)
	var rig := _rig as HumanoidRig
	if rig == null:
		return library
	for clip_name: String in rig.imported_animations():
		var anim: Animation = rig.imported_animations()[clip_name]
		if library.has_animation(clip_name):
			library.remove_animation(clip_name)
		library.add_animation(clip_name, anim)
	return library


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
	# Without this, each blended-in clip advances its own timeline by real
	# elapsed time independent of the others — since every gait clip here is
	# built by the same _gait_pose(phase, g) generator but scaled to its own
	# `cycle` length (jog_fwd 0.72s vs run_fwd 0.58s, say), the same wall-
	# clock instant lands at a *different* phase (different foot position)
	# in each. Mid-transition, when two clips are both weighted, that phase
	# mismatch is what reads as feet slipping/juddering rather than a clean
	# cross-fade. `sync` keeps every blended point's internal playback
	# locked to a shared normalised phase instead.
	space.sync = true
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
