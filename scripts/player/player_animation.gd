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

## ── Situational marking variants (MarkVariants) ─────────────────────
## Which variant of a mark clip plays is decided HERE, from the catch's
## context, never in PlayerController: the catch itself is already resolved
## (Safe/Running) or the leap already committed (Aggressive) by the time
## play_action() runs, so these thresholds only ever change what the body
## looks like, not whether it caught the ball. PlayerController hands over
## the ball's state at that instant via note_mark_ball(), before the gather
## snaps the ball into the hands. Presentation-only numbers, kept local for
## the same reason MarkPrompt keeps its ring timings out of Tuning.
## Unplaytested feel guesses.
##
## Ball height (above the player's feet) below which a Safe/Running take is
## a low, knee-to-waist scoop, and above which it's taken overhead.
## 6thbuild's base clips take the ball at ~1.4-1.5 m.
const MARK_LOW_HEIGHT := 1.15
const MARK_OVERHEAD_HEIGHT := 1.85
## Over-the-shoulder (Running only): the flight is travelling the way the
## player faces — the ball is coming from behind, Madden's catch running
## with the flight — and hasn't got in front of them. Dot of the ball's
## flat velocity with the facing, and the most it may be ahead of the chest.
const MARK_SHOULDER_DOT := 0.35
const MARK_SHOULDER_MAX_AHEAD := 0.30
## The aggressive miss cross-fade: plays mark_aggressive_miss from the
## contact instant on (see _build_state_machine), blending out of the leap.
const MARK_MISS_BLEND := 0.08
## Context older than this many physics frames is stale (a _begin() that
## was blocked never consumed it).
const MARK_CONTEXT_FRAMES := 2

## ── Ragdoll get-ups (PlayerRagdoll) ─────────────────────────────────
## The second half of the two canned falls, entered straight from a landed
## ragdoll: state -> source clip. TACKLED lands face down, KNOCKED_BACK face
## up. Each starts where its clip stops lying still — the last frame the
## Hips are within GETUP_LYING_TOLERANCE of their lowest — found from the
## clip's own Hips track at build time, so a re-authored clip moves it.
const GETUP_STATES := {&"getup_face_down": &"tackled", &"getup_face_up": &"knocked_back"}
const GETUP_LYING_TOLERANCE := 0.04
const GETUP_SAMPLE_STEP := 1.0 / 60.0
const HIPS_TRACK := ^"Skeleton3D:Hips"

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

## Snapshot from note_mark_ball() (ball relative to the player, its flight,
## the nearest opponent's side), consumed by the next play_action().
var _mark_context := {}
## What the last mark selection picked and why — for the animation viewer's
## readout and headless checks.
var _last_mark_selection := {}

## state -> {"time", "remaining", "hips_position", "hips_up"} (skeleton
## space) for each GETUP_STATES entry this rig's library could build.
var _getups := {}

## True while a ragdoll owns the skeleton (PlayerRagdoll sets it): the foot
## clamp below would otherwise lift the hips of a body lying on the turf.
var ragdoll_active := false


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

	var controller := get_parent() as PlayerController
	if controller != null:
		controller.mark_missed.connect(_on_mark_missed)


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
	if _rig == null or ragdoll_active:
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
	if state == &"":
		return
	match action:
		Tuning.Action.MARK_SAFE, Tuning.Action.MARK_RUNNING, Tuning.Action.MARK_AGGRESSIVE:
			state = _select_mark_state(action, state)
	_mark_context = {}
	_playback.travel(state)


## Plays any state by name if the graph has it (the animation viewer's
## variant buttons). Returns whether it did.
func play_state(state: StringName) -> bool:
	if _playback == null or _player == null or not _player.has_animation(state):
		return false
	_playback.travel(state)
	return true


func has_state(state: StringName) -> bool:
	return _player != null and _player.has_animation(state)


func last_mark_selection() -> Dictionary:
	return _last_mark_selection


## Called by PlayerController the instant a mark is decided (Safe/Running,
## before the gather moves the ball) or a leap is committed (Aggressive) —
## see the "Situational marking variants" constants above. Cosmetic only.
func note_mark_ball(ball: Ball) -> void:
	var body := get_parent() as Node3D
	if body == null or not is_instance_valid(ball):
		_mark_context = {}
		return
	var to_local := body.global_basis.inverse()
	var body_vel := Vector3.ZERO
	if body is CharacterBody3D:
		body_vel = (body as CharacterBody3D).velocity
		body_vel.y = 0.0
	var context := {
		"frame": Engine.get_physics_frames(),
		# Player-local: +X right, +Y up, -Z forward. Where the flight WOULD
		# meet the player, not where the ball is now — see _flight_crossing.
		"rel": to_local * _flight_crossing(ball.global_position - body.global_position,
			ball.linear_velocity - body_vel),
		"vel": to_local * ball.linear_velocity,
		"opponent_side": 0,
	}
	var controller := body as PlayerController
	if controller != null:
		var opponent := SpatialQuery.nearest_opponent(controller, Tuning.MARK_CONTEST_RANGE)
		if opponent != null:
			var side := (to_local * (opponent.global_position - body.global_position)).x
			context.opponent_side = 1 if side >= 0.0 else -1
	_mark_context = context


## The point (relative to the player's feet) where the ball's flight passes
## closest to the player's vertical axis, from its relative position and
## velocity now. A catch resolves the instant the ball enters the tier's
## reach — up to ~2.9 m from the hands for Safe — and Ball.attach_to then
## snaps it into the hands, so the ball's position AT resolution says little
## about how the take should look (measured: a ball aimed to arrive at chest
## height was caught ~2.4 m up, still well out in front). Gravity-only,
## ~1 s look-ahead; good enough to tell a knee-high scoop from a chest mark
## from an overhead grab.
static func _flight_crossing(rel: Vector3, vel: Vector3) -> Vector3:
	const STEP := 1.0 / 60.0
	var best := rel
	var best_d := Vector2(rel.x, rel.z).length()
	for i in 60:
		vel.y -= Tuning.GRAVITY * STEP
		rel += vel * STEP
		var d := Vector2(rel.x, rel.z).length()
		if d < best_d:
			best_d = d
			best = rel
		if rel.y < 0.0:
			break
	return best


## Picks the mark state for `action` from _mark_context, falling back to
## `base` whenever there's no fresh context or the variant isn't in the
## library (procedural rigs have none).
func _select_mark_state(action: Tuning.Action, base: StringName) -> StringName:
	var pick := base
	var reason := "no context"
	var c := _mark_context
	if not c.is_empty() and Engine.get_physics_frames() - int(c.frame) <= MARK_CONTEXT_FRAMES:
		var rel: Vector3 = c.rel
		var vel: Vector3 = c.vel
		var contested: bool = int(c.opponent_side) != 0
		var flat_vel := Vector2(vel.x, vel.z)
		# Facing is -Z locally, so "travelling the way the player faces"
		# is velocity.z < 0.
		var with_flight := flat_vel.length() > 0.5 and -vel.z / flat_vel.length() > MARK_SHOULDER_DOT
		reason = "height %.2f m, %s%s" % [rel.y, "contested" if contested else "uncontested",
			", ball from behind" if with_flight else ""]
		match action:
			Tuning.Action.MARK_SAFE:
				if rel.y < MARK_LOW_HEIGHT:
					pick = &"mark_safe_low"
				elif rel.y > MARK_OVERHEAD_HEIGHT:
					pick = &"mark_safe_overhead"
				elif contested:
					pick = &"mark_safe_contested"
			Tuning.Action.MARK_RUNNING:
				if with_flight and -rel.z < MARK_SHOULDER_MAX_AHEAD:
					pick = &"mark_running_shoulder_r" if rel.x >= 0.0 else &"mark_running_shoulder_l"
				elif rel.y < MARK_LOW_HEIGHT:
					pick = &"mark_running_low"
				elif rel.y > MARK_OVERHEAD_HEIGHT:
					pick = &"mark_running_overhead"
			Tuning.Action.MARK_AGGRESSIVE:
				if contested:
					# Knocked away from the opponent: one on the right pushes
					# from the right.
					pick = &"mark_aggressive_offbalance_r" if int(c.opponent_side) > 0 \
						else &"mark_aggressive_offbalance_l"
	if pick != base and not has_state(pick):
		reason += " (%s not built for this rig)" % pick
		pick = base
	_last_mark_selection = {"action": action, "state": pick, "reason": reason}
	return pick


## An Aggressive leap that came up empty: cross-fade from the leap into its
## empty-handed landing, which starts from the leap's own contact pose (see
## _build_state_machine), so there's no pop. A contested leap is already
## in its off-balance variant and stays there.
func _on_mark_missed(tier: Tuning.Action) -> void:
	if tier != Tuning.Action.MARK_AGGRESSIVE or _playback == null:
		return
	if current_state() == ACTION_STATES[Tuning.Action.MARK_AGGRESSIVE] and has_state(&"mark_aggressive_miss"):
		_playback.travel(&"mark_aggressive_miss")


func current_state() -> StringName:
	if _playback == null:
		return &""
	return _playback.get_current_node()


## The get-up states this rig has (see GETUP_STATES), and for one of them
## where its clip picks up: {"time", "remaining" (s left to play),
## "hips_position", "hips_up"} — the Hips bone's pose at that instant in
## skeleton space, which PlayerRagdoll lines the player up against.
func getup_info(state: StringName) -> Dictionary:
	return _getups.get(state, {})


## Jumps straight into a get-up state, no cross-fade — the blend out of the
## ragdoll is the simulator's influence ramp, not the state machine's.
func play_getup(state: StringName) -> bool:
	if _playback == null or not _getups.has(state):
		return false
	_playback.start(state)
	return true


## Back to locomotion at once (a ragdoll that never went down).
func play_locomotion() -> void:
	if _playback != null:
		_playback.start(LOCOMOTION_STATE)


## Finds where a fall clip stops lying still — see GETUP_STATES.
static func _getup_point(anim: Animation) -> Dictionary:
	var pos_track := anim.find_track(HIPS_TRACK, Animation.TYPE_POSITION_3D)
	var rot_track := anim.find_track(HIPS_TRACK, Animation.TYPE_ROTATION_3D)
	if pos_track < 0 or rot_track < 0:
		return {}
	var lowest := INF
	var lowest_t := 0.0
	var t := 0.0
	while t <= anim.length:
		var y := anim.position_track_interpolate(pos_track, t).y
		if y < lowest:
			lowest = y
			lowest_t = t
		t += GETUP_SAMPLE_STEP
	t = lowest_t
	while t + GETUP_SAMPLE_STEP <= anim.length \
			and anim.position_track_interpolate(pos_track, t + GETUP_SAMPLE_STEP).y <= lowest + GETUP_LYING_TOLERANCE:
		t += GETUP_SAMPLE_STEP
	return {
		"time": t,
		"remaining": anim.length - t,
		"hips_position": anim.position_track_interpolate(pos_track, t),
		"hips_up": Basis(anim.rotation_track_interpolate(rot_track, t)).y,
	}


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
	# Situational mark variants, bent off the import's OWN mark clips only —
	# a rig still on the procedural fallbacks gets none, and play_action()
	# falls back to the base state.
	if rig.is_imported():
		var variants := MarkVariants.build(rig.skeleton(), rig.imported_animations())
		for clip_name: String in variants:
			library.add_animation(clip_name, variants[clip_name])
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

	# Mark variants: same in/out wiring as the action states, for whichever
	# ones MarkVariants built for this rig.
	for variant in MarkVariants.variant_names():
		if not _player.has_animation(variant):
			continue
		var clip := AnimationNodeAnimation.new()
		clip.animation = variant
		if variant == "mark_aggressive_miss":
			# Entered mid-leap at the contact instant (_on_mark_missed), so it
			# plays from there on — its first frame is the leap's own contact
			# pose, which is what makes the cross-fade in seamless.
			var contact := Tuning.action_contact_time(Tuning.Action.MARK_AGGRESSIVE)
			clip.use_custom_timeline = true
			clip.start_offset = contact
			clip.timeline_length = _player.get_animation(variant).length - contact
			clip.stretch_time_scale = false
		machine.add_node(variant, clip, Vector2(860.0, 40.0 + 110.0 * row))
		row += 1
		machine.add_transition(LOCOMOTION_STATE, variant,
			_transition(ACTION_BLEND_IN,
				AnimationNodeStateMachineTransition.SWITCH_MODE_IMMEDIATE,
				AnimationNodeStateMachineTransition.ADVANCE_MODE_ENABLED))
		machine.add_transition(variant, LOCOMOTION_STATE,
			_transition(ACTION_BLEND_OUT,
				AnimationNodeStateMachineTransition.SWITCH_MODE_AT_END,
				AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO))
	if _player.has_animation(&"mark_aggressive_miss"):
		machine.add_transition(ACTION_STATES[Tuning.Action.MARK_AGGRESSIVE], &"mark_aggressive_miss",
			_transition(MARK_MISS_BLEND,
				AnimationNodeStateMachineTransition.SWITCH_MODE_IMMEDIATE,
				AnimationNodeStateMachineTransition.ADVANCE_MODE_ENABLED))

	# Ragdoll get-ups: the source clip from its lying point on (the same
	# custom-timeline trick as mark_aggressive_miss), entered with
	# play_getup() and leaving to locomotion when it ends. Imported rigs
	# only — they're the only ones that ragdoll.
	var rig := _rig as HumanoidRig
	for state: StringName in GETUP_STATES:
		var source: StringName = GETUP_STATES[state]
		if rig == null or not rig.is_imported() or not _player.has_animation(source):
			continue
		var info := _getup_point(_player.get_animation(source))
		if info.is_empty() or float(info.remaining) <= 0.0:
			continue
		_getups[state] = info
		var clip := AnimationNodeAnimation.new()
		clip.animation = source
		clip.use_custom_timeline = true
		clip.start_offset = info.time
		clip.timeline_length = info.remaining
		clip.stretch_time_scale = false
		machine.add_node(state, clip, Vector2(1160.0, 40.0 + 110.0 * row))
		row += 1
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
