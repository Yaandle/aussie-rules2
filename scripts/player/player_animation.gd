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
const JOG_BLEND := 0.55
const BLEND_POINTS := [
	[Vector2(0.0, 0.0), &"idle"],
	[Vector2(0.0, JOG_BLEND), &"jog_fwd"],
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
	Tuning.Action.TACKLE_SLING: &"tackle_sling",
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

## ── Stride matching ─────────────────────────────────────────────────
## The gait clips play at whatever cadence they were authored at, but the
## body moves at whatever the physics says. 6thbuild's run_fwd has its
## stance foot sweeping ~3.4 m/s under the hips while a sprint is 8.4 m/s
## (11 on a fast CHARACTER profile), so the legs read as running through
## treacle while the turf slides past under them. The locomotion blend
## space now plays through a TimeScale (STRIDE_NODE) whose rate is the
## body's real speed over the ground speed the blended clips were authored
## for, so the legs turn over faster the faster the player is going.
## Each clip's authored speed is measured off the clip itself at build time
## (_measure_stride: the planted foot's sweep under the hips), the same way
## the get-ups find their lying frame, so a re-authored clip re-measures
## itself and the procedural rig's much longer stride gets its own numbers.
## The rate is capped by cadence, not by a flat multiple: a short-strided
## clip matched all the way to a sprint would turn over 8-9 steps a second,
## which blurs rather than reads as fast. STRIDE_CADENCE is the most steps
## a second a runner makes at JOG_SPEED and at SPRINT_SPEED (real figures
## are ~3 and ~4.5-5, set a touch over to read quick on short-strided
## clips), extrapolated linearly either side, so past it the feet are left
## to skate a little instead. A backpedal is a short, quick shuffle rather
## than a stride, so going backwards just never plays slower than authored,
## up to STRIDE_BACK_MAX_RATE. Unplaytested feel guesses.
const GAIT_NODE := &"gait"
const STRIDE_NODE := &"stride"
const STRIDE_CLIPS: Array[StringName] = [&"jog_fwd", &"run_fwd", &"run_back"]
const STRIDE_CADENCE := Vector2(3.4, 5.2)
const STRIDE_CADENCE_LIMITS := Vector2(1.8, 5.8)
const STRIDE_MIN_RATE := 0.85
const STRIDE_BACK_MAX_RATE := 1.3
## Blend magnitude under which the rate eases back to 1, so a standing
## player's idle sway plays as authored.
const STRIDE_FADE := 0.08
## How far above its lowest point a foot still counts as planted, and the
## measuring step.
const STRIDE_PLANT_TOLERANCE := 0.03
const STRIDE_SAMPLE_STEP := 1.0 / 60.0

## ── Gait phase lock ─────────────────────────────────────────────────
## A blend space mixes poses, not gaits: two stepping clips blend cleanly
## only while both are at the same point of the stride. Nothing in Godot's
## blend space lines that up — its `sync` only keeps a clip's clock running
## while its weight is zero — so each clip loops on its own length, and
## 6thbuild's don't match: the jog family (jog_fwd, run_back, the strafes)
## is 0.708 s a cycle, the run family (run_fwd and its diagonals) 0.542 s.
## Every 1.2 s of running between jog and sprint pace the two drift half a
## stride apart, and the blend averages a planted foot with a swinging one:
## both feet hover and slide. The strafes and run_back weren't even in step
## at the start (left foot down at 36% / 63% / 12% of their cycles against
## 3% for the forward clips).
## So the stepping clips are rebuilt once per model, before anything else
## reads them: each is stretched to PHASE_LOCK_REFERENCE's length and turned
## round its loop so the middle of its left foot's stance lands at time 0.
## Same length, same start, and `sync` keeping every clock running, they stay
## in step for as long as the player runs. Stride matching measures the
## rebuilt clips, so the cadence it sets is unchanged. The reference is the
## jog: a jog-family clip only turns, and the run family is played back up
## to speed by the stride rate anyway. idle has no stride and keeps its own
## slow loop.
const PHASE_LOCK_CLIPS: Array[StringName] = [&"jog_fwd", &"run_fwd", &"run_back", &"strafe_l",
	&"strafe_r", &"run_fwd_l", &"run_fwd_r"]
const PHASE_LOCK_REFERENCE := &"jog_fwd"
const PHASE_LOCK_SAMPLE_RATE := 60.0

## ── Drive lean ──────────────────────────────────────────────────────
## A runner leans into acceleration and sits back to brake; constant-speed
## clips do neither, so getting going looked like the legs speeding up
## under an upright torso. Added to the Spine after the tree mixes (the same
## post-mix pass as the foot clamp), from the body's change of speed plus a
## little for pace itself, only while running forwards in locomotion.
## Degrees, positive forward. Unplaytested feel guesses.
const LEAN_BONE := &"Spine"
const LEAN_PER_ACCEL_DEG := 1.1     ## per m/s² of speed gained
const LEAN_AT_SPRINT_DEG := 4.0
const LEAN_LIMITS_DEG := Vector2(-6.0, 12.0)
const LEAN_SMOOTHING := 10.0
## Easing back toward upright while still running is slower. Speed climbs at
## a constant Tuning.ACCELERATION and stops dead at the top, so the drive
## lean fell from 12° to 4° in a couple of frames the moment a sprint
## topped out, a visible pop upright. A sprinter rises out of the drive over
## a few strides instead. Leaving locomotion (a kick, a mark) still clears
## the lean at LEAN_SMOOTHING, so it doesn't ride into the action clip.
const LEAN_RELEASE_SMOOTHING := 3.5

## ── Turn bank ───────────────────────────────────────────────────────
## A runner cutting at pace tips into the turn: to stay balanced while the
## feet push sideways, the body leans toward the inside of the curve by
## atan(sideways acceleration / g). The clips all run straight, so a hard
## cut at a sprint swung the legs round under a bolt-upright torso. Taken
## from the body's real sideways acceleration (its velocity changing across
## its facing — the same velocity the blend space reads), at BANK_SHARE of
## the balanced angle (the legs and arms already show some of the turn),
## capped at BANK_MAX_DEG, and rolled into LEAN_BONE in the same post-mix
## pass as the drive lean. A tackle hold, a dash and every other
## non-locomotion state get none. Degrees. Unplaytested feel guesses.
const BANK_SHARE := 0.6
const BANK_MAX_DEG := 14.0
const BANK_SMOOTHING := 8.0

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
var _stride_parameter := ""

## clip -> {"speed" (m/s, skeleton space), "cadence" (steps/s)} for
## STRIDE_CLIPS — see "Stride matching". Every rig on one model has the
## same clips, so it's measured once per model and shared.
static var _stride_cache := {}
## model -> {clip -> Animation}, the phase-locked gait clips (see "Gait
## phase lock"), built once per model and shared like _stride_cache. Shared
## because they must be: an imported clip is the glb's own resource, the same
## object in every rig, so rebuilding in place would stretch it once per
## player.
static var _phase_lock_cache := {}
var _strides := {}
var _stride_rate := 1.0

## See "Drive lean". -1 when the gait clips don't all animate LEAN_BONE
## (the tree wouldn't overwrite it each frame, so the lean would pile up).
var _lean_bone := -1
var _lean_deg := 0.0
var _last_speed := 0.0
## See "Turn bank": degrees, positive = toward the body's right.
var _bank_deg := 0.0
var _last_velocity := Vector3.ZERO

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
	_strides = _measure_strides()
	_lean_bone = _find_lean_bone()

	_tree.tree_root = _build_state_machine()
	_tree.anim_player = _tree.get_path_to(_player)
	_tree.active = true
	_playback = _tree.get("parameters/playback")
	_blend_parameter = "parameters/%s/%s/blend_position" % [LOCOMOTION_STATE, GAIT_NODE]
	_stride_parameter = "parameters/%s/%s/scale" % [LOCOMOTION_STATE, STRIDE_NODE]

	var controller := get_parent() as PlayerController
	if controller != null:
		controller.mark_missed.connect(_on_mark_missed)


## Called every physics frame by the controller with the body-space
## velocity from PlayerController.locomotion_blend() and the body's real
## ground speed (m/s). Without a speed (the animation viewer drives a bare
## blend) it's read off the blend, which is normalised to SPRINT_SPEED.
func drive(blend: Vector2, delta: float, speed := -1.0) -> void:
	if _tree == null or not _tree.active:
		return
	_blend = _blend.lerp(blend, 1.0 - exp(-BLEND_SMOOTHING * delta))
	_tree.set(_blend_parameter, _blend)
	if speed < 0.0:
		speed = blend.length() * Tuning.SPRINT_SPEED
	_stride_rate = _stride_rate_for(speed)
	_tree.set(_stride_parameter, _stride_rate)
	_update_lean(speed, delta)


## The locomotion playback rate right now — see "Stride matching".
func stride_rate() -> float:
	return _stride_rate


## clip -> {"speed", "cadence"} as measured — see "Stride matching".
func stride_measurements() -> Dictionary:
	return _strides


func _stride_rate_for(speed: float) -> float:
	var reach := _blend.length()
	if _strides.is_empty() or reach < 0.0001:
		return 1.0
	reach = minf(reach, 1.0)
	# The ground speed and cadence the blend is showing, from the clips at
	# its anchors: idle -> jog_fwd covers no ground at one end and the jog's
	# at the other, jog_fwd -> run_fwd in between, run_back going backwards.
	# The strafes and diagonals ride along with the forward clips — a turn
	# leaves the body's speed, and so the rate, much where it was.
	var authored := 0.0
	var cadence := 0.0
	var backwards := _blend.y < -absf(_blend.x)
	if backwards:
		var back: Dictionary = _strides.get(&"run_back", {})
		authored = reach * float(back.get("speed", 0.0))
		cadence = float(back.get("cadence", 0.0))
	else:
		var jog: Dictionary = _strides.get(&"jog_fwd", {})
		var run: Dictionary = _strides.get(&"run_fwd", jog)
		if reach <= JOG_BLEND:
			authored = reach / JOG_BLEND * float(jog.get("speed", 0.0))
			cadence = float(jog.get("cadence", 0.0))
		else:
			var t := (reach - JOG_BLEND) / (1.0 - JOG_BLEND)
			authored = lerpf(float(jog.get("speed", 0.0)), float(run.get("speed", 0.0)), t)
			cadence = lerpf(float(jog.get("cadence", 0.0)), float(run.get("cadence", 0.0)), t)
	var skeleton := _rig.get_node_or_null(^"Skeleton3D") as Skeleton3D
	if skeleton != null:
		authored *= skeleton.global_basis.get_scale().x
	if authored < 0.05 or cadence <= 0.0:
		return 1.0
	if backwards:
		return lerpf(1.0, clampf(speed / authored, 1.0, STRIDE_BACK_MAX_RATE), clampf(reach / STRIDE_FADE, 0.0, 1.0))
	var steps := clampf(remap(speed, Tuning.JOG_SPEED, Tuning.SPRINT_SPEED, STRIDE_CADENCE.x, STRIDE_CADENCE.y),
		STRIDE_CADENCE_LIMITS.x, STRIDE_CADENCE_LIMITS.y)
	var rate := clampf(speed / authored, STRIDE_MIN_RATE, maxf(steps / cadence, STRIDE_MIN_RATE))
	return lerpf(1.0, rate, clampf(reach / STRIDE_FADE, 0.0, 1.0))


func _update_lean(speed: float, delta: float) -> void:
	var accel := (speed - _last_speed) / maxf(delta, 0.0001)
	_last_speed = speed
	var running := _blend.y > 0.1 and current_state() == LOCOMOTION_STATE and not ragdoll_active
	var target := 0.0
	if running:
		target = clampf(accel * LEAN_PER_ACCEL_DEG + speed / Tuning.SPRINT_SPEED * LEAN_AT_SPRINT_DEG,
			LEAN_LIMITS_DEG.x, LEAN_LIMITS_DEG.y)
	var rate := LEAN_SMOOTHING
	if running and absf(target) < absf(_lean_deg) and signf(target) != -signf(_lean_deg):
		rate = LEAN_RELEASE_SMOOTHING
	_lean_deg = lerpf(_lean_deg, target, 1.0 - exp(-rate * delta))

	# Turn bank, off the velocity the body really has (a bare blend from the
	# animation viewer has no body, so no bank).
	var body := get_parent() as CharacterBody3D
	var bank := 0.0
	if body != null:
		var velocity := Vector3(body.velocity.x, 0.0, body.velocity.z)
		var sideways := (velocity - _last_velocity).dot(body.global_basis.x.normalized()) / maxf(delta, 0.0001)
		_last_velocity = velocity
		if running:
			bank = clampf(rad_to_deg(atan(sideways / Tuning.GRAVITY)) * BANK_SHARE, -BANK_MAX_DEG, BANK_MAX_DEG)
	_bank_deg = lerpf(_bank_deg, bank, 1.0 - exp(-(BANK_SMOOTHING if running else LEAN_SMOOTHING) * delta))


## The drive lean right now, degrees — see "Drive lean".
func lean_degrees() -> float:
	return _lean_deg


## The turn bank right now, degrees, positive toward the right — see "Turn
## bank".
func bank_degrees() -> float:
	return _bank_deg


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
	_apply_lean()
	_clamp_feet_to_ground()


## Tips the Spine by _lean_deg about the body's own left-right axis and
## rolls it by _bank_deg about its forward axis, on top of whatever the tree
## just wrote — see "Drive lean" and "Turn bank". The tree rewrites the bone
## every frame (_find_lean_bone checked it can), so this never stacks.
func _apply_lean() -> void:
	if _rig == null or ragdoll_active or _lean_bone < 0 \
			or (absf(_lean_deg) < 0.05 and absf(_bank_deg) < 0.05):
		return
	var skeleton := _rig.get_node_or_null(^"Skeleton3D") as Skeleton3D
	var body := get_parent() as Node3D
	if skeleton == null or body == null:
		return
	# The body's axes in skeleton space, then in the bone's parent's frame:
	# a rotation about a skeleton-space axis applied to the bone's global
	# pose is the same rotation about that axis taken into its parent's
	# frame, applied to its local pose. Forward is -Z, so tipping +Y toward
	# it is a negative turn about +X, and tipping it toward +X a positive
	# turn about -Z.
	var to_skeleton := skeleton.global_basis.orthonormalized().inverse()
	var right := (to_skeleton * body.global_basis.x).normalized()
	var forward := (to_skeleton * -body.global_basis.z).normalized()
	var parent := skeleton.get_bone_parent(_lean_bone)
	if parent >= 0:
		var to_parent := skeleton.get_bone_global_pose(parent).basis.orthonormalized().inverse()
		right = (to_parent * right).normalized()
		forward = (to_parent * forward).normalized()
	var turn := Quaternion(right, -deg_to_rad(_lean_deg)) * Quaternion(forward, deg_to_rad(_bank_deg))
	skeleton.set_bone_pose_rotation(_lean_bone, turn * skeleton.get_bone_pose_rotation(_lean_bone))


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


## Measures STRIDE_CLIPS on this rig's skeleton (cached per model — see
## _stride_cache). Poses the skeleton directly, then puts it back to rest
## before the tree takes over; empty if the rig has no skeleton yet.
func _measure_strides() -> Dictionary:
	var skeleton := _rig.get_node_or_null(^"Skeleton3D") as Skeleton3D
	if skeleton == null:
		return {}
	var key := _model_key()
	if _stride_cache.has(key):
		return _stride_cache[key]
	var out := {}
	for clip: StringName in STRIDE_CLIPS:
		if _player.has_animation(clip):
			var measured := _measure_stride(skeleton, _player.get_animation(clip))
			if not measured.is_empty():
				out[clip] = measured
	skeleton.reset_bone_poses()
	if not out.is_empty():
		_stride_cache[key] = out
	return out


## One looping gait clip's authored ground speed and cadence: while a foot is
## planted (within STRIDE_PLANT_TOLERANCE of its own lowest point) it should
## be standing still on the turf, so how fast it sweeps under the hips is how
## fast the clip means the body to travel. Both feet's sweeps over the whole
## cycle, over the time they were planted; two steps a cycle. Skeleton space,
## so unscaled by the rig's height.
static func _measure_stride(skeleton: Skeleton3D, anim: Animation) -> Dictionary:
	var hips := skeleton.find_bone(&"Hips")
	var feet := [skeleton.find_bone(&"LeftFoot"), skeleton.find_bone(&"RightFoot")]
	if hips < 0 or feet.has(-1) or anim.length <= 0.0:
		return {}
	var tracks := []
	for i in anim.get_track_count():
		var type := anim.track_get_type(i)
		if type != Animation.TYPE_ROTATION_3D and type != Animation.TYPE_POSITION_3D:
			continue
		var bone := skeleton.find_bone(String(anim.track_get_path(i).get_concatenated_subnames()))
		if bone >= 0:
			tracks.append([i, bone, type])
	var count := maxi(ceili(anim.length / STRIDE_SAMPLE_STEP), 2)
	var step := anim.length / count
	var samples := []   # per sample: [hips, left foot, right foot], skeleton space
	for s in count + 1:
		var t := step * s
		for track: Array in tracks:
			if track[2] == Animation.TYPE_ROTATION_3D:
				skeleton.set_bone_pose_rotation(track[1], anim.rotation_track_interpolate(track[0], t))
			else:
				skeleton.set_bone_pose_position(track[1], anim.position_track_interpolate(track[0], t))
		samples.append([skeleton.get_bone_global_pose(hips).origin,
			skeleton.get_bone_global_pose(feet[0]).origin, skeleton.get_bone_global_pose(feet[1]).origin])
	var swept := 0.0
	var planted := 0.0
	for f in [1, 2]:
		var lowest := INF
		for sample: Array in samples:
			lowest = minf(lowest, (sample[f] as Vector3).y)
		for s in range(1, samples.size()):
			var a: Array = samples[s - 1]
			var b: Array = samples[s]
			if (a[f] as Vector3).y > lowest + STRIDE_PLANT_TOLERANCE \
					or (b[f] as Vector3).y > lowest + STRIDE_PLANT_TOLERANCE:
				continue
			var moved: Vector3 = ((b[f] as Vector3) - (b[0] as Vector3)) - ((a[f] as Vector3) - (a[0] as Vector3))
			swept += Vector2(moved.x, moved.z).length()
			planted += step
	if planted <= 0.0:
		return {}
	return {"speed": swept / planted, "cadence": 2.0 / anim.length}


## Which model this rig's clips came from, for the per-model caches.
func _model_key() -> String:
	var rig := _rig as HumanoidRig
	return rig.selected_model() if rig != null and rig.is_imported() else "procedural"


## Swaps `library`'s PHASE_LOCK_CLIPS for their phase-locked rebuilds — see
## "Gait phase lock". Leaves the library alone when there's no skeleton to
## measure on or no reference clip.
func _phase_lock(library: AnimationLibrary) -> void:
	var key := _model_key()
	if not _phase_lock_cache.has(key):
		var skeleton := _rig.get_node_or_null(^"Skeleton3D") as Skeleton3D
		if skeleton == null or not library.has_animation(PHASE_LOCK_REFERENCE):
			return
		var length := library.get_animation(PHASE_LOCK_REFERENCE).length
		var locked := {}
		for clip: StringName in PHASE_LOCK_CLIPS:
			if not library.has_animation(clip):
				continue
			var anim := library.get_animation(clip)
			var stance := _stance_phase(skeleton, anim, &"LeftFoot")
			if stance >= 0.0:
				locked[clip] = _relooped(anim, length, stance)
		skeleton.reset_bone_poses()
		_phase_lock_cache[key] = locked
	var locked_clips: Dictionary = _phase_lock_cache[key]
	for clip: StringName in locked_clips:
		library.remove_animation(clip)
		library.add_animation(clip, locked_clips[clip])


## Where `foot`'s stance is centred in one loop of `anim`, 0-1: the middle of
## the longest stretch (round the loop) it spends within
## STRIDE_PLANT_TOLERANCE of its lowest point. -1 if the clip doesn't move it.
static func _stance_phase(skeleton: Skeleton3D, anim: Animation, foot: StringName) -> float:
	var bone := skeleton.find_bone(foot)
	if bone < 0 or anim.length <= 0.0:
		return -1.0
	var tracks := []
	for i in anim.get_track_count():
		var type := anim.track_get_type(i)
		if type != Animation.TYPE_ROTATION_3D and type != Animation.TYPE_POSITION_3D:
			continue
		var target := skeleton.find_bone(String(anim.track_get_path(i).get_concatenated_subnames()))
		if target >= 0:
			tracks.append([i, target, type])
	var count := maxi(ceili(anim.length / STRIDE_SAMPLE_STEP), 4)
	var heights: Array[float] = []
	for s in count:
		var t := anim.length * s / count
		for track: Array in tracks:
			if track[2] == Animation.TYPE_ROTATION_3D:
				skeleton.set_bone_pose_rotation(track[1], anim.rotation_track_interpolate(track[0], t))
			else:
				skeleton.set_bone_pose_position(track[1], anim.position_track_interpolate(track[0], t))
		heights.append(skeleton.get_bone_global_pose(bone).origin.y)
	var lowest: float = heights.min()
	if heights.max() - lowest <= STRIDE_PLANT_TOLERANCE:
		return -1.0
	# Longest run of planted samples, round the loop: start just after an
	# unplanted one so no run is split across the end.
	var start := 0
	while heights[start] <= lowest + STRIDE_PLANT_TOLERANCE:
		start += 1
	var best_from := 0
	var best_len := 0
	var run := 0
	for n in count:
		var s := (start + 1 + n) % count
		if heights[s] <= lowest + STRIDE_PLANT_TOLERANCE:
			run += 1
			if run > best_len:
				best_len = run
				best_from = s - run + 1
		else:
			run = 0
	return fposmod((best_from + (best_len - 1) * 0.5) / count, 1.0)


## A copy of looping `anim`, `length` seconds long, that starts `phase` (0-1)
## of the way into the original: every transform track resampled at
## PHASE_LOCK_SAMPLE_RATE. Any other track keeps its keys, moved the same way.
static func _relooped(anim: Animation, length: float, phase: float) -> Animation:
	var out := Animation.new()
	out.length = length
	out.loop_mode = Animation.LOOP_LINEAR
	var count := maxi(roundi(length * PHASE_LOCK_SAMPLE_RATE), 2)
	var source_offset := phase * anim.length
	for i in anim.get_track_count():
		var type := anim.track_get_type(i)
		var track := out.add_track(type)
		out.track_set_path(track, anim.track_get_path(i))
		out.track_set_interpolation_type(track, anim.track_get_interpolation_type(i))
		out.track_set_interpolation_loop_wrap(track, anim.track_get_interpolation_loop_wrap(i))
		if type == Animation.TYPE_ROTATION_3D or type == Animation.TYPE_POSITION_3D \
				or type == Animation.TYPE_SCALE_3D:
			for s in count + 1:
				var t := length * s / count
				var from := fposmod(source_offset + t / length * anim.length, anim.length)
				match type:
					Animation.TYPE_ROTATION_3D:
						out.rotation_track_insert_key(track, t, anim.rotation_track_interpolate(i, from))
					Animation.TYPE_POSITION_3D:
						out.position_track_insert_key(track, t, anim.position_track_interpolate(i, from))
					_:
						out.scale_track_insert_key(track, t, anim.scale_track_interpolate(i, from))
		else:
			for k in anim.track_get_key_count(i):
				var t := fposmod(anim.track_get_key_time(i, k) - source_offset, anim.length) / anim.length * length
				out.track_insert_key(track, t, anim.track_get_key_value(i, k), anim.track_get_key_transition(i, k))
	return out


## LEAN_BONE's index if every locomotion clip animates its rotation, else -1.
func _find_lean_bone() -> int:
	var skeleton := _rig.get_node_or_null(^"Skeleton3D") as Skeleton3D
	if skeleton == null:
		return -1
	var bone := skeleton.find_bone(LEAN_BONE)
	if bone < 0:
		return -1
	for point: Array in BLEND_POINTS:
		var clip: StringName = point[1]
		if not _player.has_animation(clip):
			return -1
		var anim := _player.get_animation(clip)
		var animated := false
		for i in anim.get_track_count():
			if anim.track_get_type(i) == Animation.TYPE_ROTATION_3D \
					and anim.track_get_path(i).get_concatenated_subnames() == String(LEAN_BONE):
				animated = true
				break
		if not animated:
			return -1
	return bone


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
	_phase_lock(library)
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
	machine.add_node(LOCOMOTION_STATE, _build_locomotion(), Vector2(260.0, 140.0))
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


## The blend space through the stride TimeScale — see "Stride matching".
func _build_locomotion() -> AnimationNodeBlendTree:
	var tree := AnimationNodeBlendTree.new()
	tree.add_node(GAIT_NODE, _build_blend_space(), Vector2(0.0, 0.0))
	tree.add_node(STRIDE_NODE, AnimationNodeTimeScale.new(), Vector2(260.0, 0.0))
	tree.connect_node(STRIDE_NODE, 0, GAIT_NODE)
	tree.connect_node(&"output", 0, STRIDE_NODE)
	return tree


func _build_blend_space() -> AnimationNodeBlendSpace2D:
	var space := AnimationNodeBlendSpace2D.new()
	space.min_space = Vector2(-1.0, -1.0)
	space.max_space = Vector2(1.0, 1.0)
	space.snap = Vector2(0.05, 0.05)
	space.blend_mode = AnimationNodeBlendSpace2D.BLEND_MODE_INTERPOLATED
	space.auto_triangles = true
	# Keeps every clip's clock running while its weight is zero, so a clip
	# blending back in is still where the others are. That's all it does: it
	# doesn't match phases across clips of different lengths, which is why
	# the stepping clips are rebuilt to one length and one start first (see
	# "Gait phase lock"). Without it a clip would pause at weight zero and
	# come back out of step.
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
