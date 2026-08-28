class_name Umpire
extends Node3D

## Match officials (docs/RULES_REFERENCE.md, Core rulebook v1 §10) — the
## field umpire who throws the ball up, a boundary umpire either side, and
## a goal umpire at each end, so a match looks officiated rather than
## unattended.
##
## Deliberately cosmetic. They have no collision shape at all: a player can
## run straight through one, and the ball is never deflected by one. That
## is a conscious simplification, not an oversight — this project has no
## adjudication *actor* (rulings are made by FullGame and PlayerController,
## and always have been), so giving an umpire a body that could interfere
## with play would add a whole class of physics bug for no rules benefit.
## The two things they actually do — the field umpire's throw-up and the
## goal umpire's flag raise — are performances of decisions already made
## elsewhere, not the decisions themselves. In particular, throw_up() below
## does not launch the ball; FullGame does, when the throw reaches its
## release point.
##
## Built entirely in code from the same HumanoidRig the players use, via
## its kit_* overrides — no separate rig, no imported art, consistent with
## everything else in this project. Bones are posed directly rather than
## through an AnimationPlayer: an umpire has one moving part at a time and
## nothing to blend against, so a whole AnimationTree would be machinery
## for a pair of lerps.

enum Role {
	FIELD,      ## black and white vertical stripes; throws the ball up at every stoppage
	BOUNDARY,   ## same stripes, stands on the boundary line
	GOAL,       ## white overalls, two white flags
}

## Field and boundary umpires: white with black vertical stripes.
const COLOUR_STRIPE_BASE := Color("#eae7dd")
const COLOUR_STRIPE := Color("#1b1c20")
const STRIPE_COUNT := 5

## Goal umpire: white overalls, top and bottom the same.
const COLOUR_OVERALLS := Color("#f2efe6")
const COLOUR_FLAG := Color("#f6f4ee")
const COLOUR_FLAG_POLE := Color("#6b5a42")

const FLAG_POLE_LENGTH := 0.42
const FLAG_POLE_RADIUS := 0.012
const FLAG_CLOTH := Vector3(0.20, 0.16, 0.008)

## How long both flags stay up after a goal. Comfortably longer than
## Tuning.SCORE_PAUSE_DURATION's own 3.0s celebration so the signal is
## still up while the teams walk back for the restart, and it comes down
## during the (now longer, see Tuning.GOAL_RESTART_BOUNCE_DELAY) wait for
## the ball-up rather than the instant the flash clears.
const FLAG_HOLD_DURATION := 4.0

## Seconds the arms take to sweep up, and back down again. Short enough to
## read as a deliberate signal rather than a drift.
const FLAG_RAISE_TIME := 0.28
const FLAG_LOWER_TIME := 0.45

## Arm pitch is in radians about the upper-arm bone's own X axis, the same
## axis and sign convention every arm pose in HumanoidAnimations uses:
## positive swings the arm forward and up from hanging at the side, so
## PI/2 is straight out horizontally and PI is straight overhead.
##
## Rest is arms down. Raised (goal umpire) is both arms held dead straight
## out and up, in a shallow V so the two flags read as two flags rather
## than one — a goal umpire signals with the flags out and visible, not
## tucked back over the shoulders.
const ARM_REST_PITCH := 0.0
const ARM_RAISED_PITCH := 2.20
const ARM_RAISED_SPREAD := 0.42   ## rad about Z, outward — the V between the two flags

## The field umpire's throw-up, as fractions of the whole beat (whatever
## duration throw_up() is handed — Tuning.BALL_UP_THROW_DURATION in a
## match). Crouch down over the ball, hold it a moment so the moment reads,
## then a fast sweep up to the release, then settle back.
const THROW_CROUCH_END := 0.35
const THROW_HOLD_END := 0.62
const THROW_RELEASE_END := 0.78

## Poses at each of those. Crouched is both arms down and forward over the
## ball with the torso folded; released is both arms thrown straight up.
const THROW_CROUCH_PITCH := 0.55
const THROW_RELEASE_PITCH := 2.95
const THROW_ARM_SPREAD := 0.10
const THROW_CROUCH_LEAN := 0.45   ## rad, spine folded forward over the ball
const THROW_RELEASE_LEAN := -0.12 ## rad, a slight arch back on the toss

## Distance between the two hands, used to sit the ball on the centreline
## between them — HumanoidRig.SHOULDER_WIDTH is what actually sets it, and
## the arms hang straight down from there.
const HAND_SPAN := 0.42

var role := Role.FIELD

var _rig: HumanoidRig
var _skeleton: Skeleton3D
var _arm_bones: Array[int] = []
var _spine_bone := -1

var _flag_timer := 0.0
var _raise := 0.0            ## 0 = arms down, 1 = flags fully up

var _throw_elapsed := 0.0
var _throw_duration := 0.0
var _ball_point: Node3D = null


func _ready() -> void:
	_rig = HumanoidRig.new()
	match role:
		Role.FIELD, Role.BOUNDARY:
			_rig.kit_torso = COLOUR_STRIPE_BASE
			_rig.kit_shorts = COLOUR_STRIPE
			_rig.kit_stripes = STRIPE_COUNT
			_rig.kit_stripe_colour = COLOUR_STRIPE
		Role.GOAL:
			_rig.kit_torso = COLOUR_OVERALLS
			_rig.kit_shorts = COLOUR_OVERALLS
	add_child(_rig)
	_skeleton = _rig.skeleton()

	_arm_bones = [
		_skeleton.find_bone("LeftUpperArm"),
		_skeleton.find_bone("RightUpperArm"),
	]
	_spine_bone = _skeleton.find_bone("Spine")

	if role == Role.GOAL:
		_build_flag("LeftHand")
		_build_flag("RightHand")
	elif role == Role.FIELD:
		_build_ball_point()
	_apply_pose(ARM_REST_PITCH, 0.0, 0.0)
	# The boundary umpire is the one official with nothing to perform.
	set_process(role != Role.BOUNDARY)


## Stand at `spot`, facing `look_at` (both world-space; only the XZ plane
## is used). Called by FullGame to bring the field umpire to wherever the
## next stoppage is — a centre bounce, a field ball-up or a boundary
## throw-in all happen somewhere different.
func stand_at(spot: Vector3, look_at: Vector3) -> void:
	global_position = Vector3(spot.x, 0.0, spot.z)
	var to_target := Vector3(look_at.x - spot.x, 0.0, look_at.z - spot.z)
	if to_target.length_squared() > 0.0001:
		# A node's forward is -Z.
		rotation.y = atan2(-to_target.x, -to_target.z)


## Perform the throw-up over `duration` seconds. Purely the performance —
## the ball is launched by FullGame at its own release point, timed against
## the same duration (see Tuning.BALL_UP_THROW_DURATION). Restartable: a
## second call mid-throw simply begins again, so back-to-back stoppages
## can't leave the umpire frozen halfway through a crouch.
func throw_up(duration: float) -> void:
	if role != Role.FIELD:
		return
	_throw_duration = maxf(duration, 0.01)
	_throw_elapsed = 0.0


## Raise both flags — the goal umpire's signal that a goal has been
## scored. Called by Field when its own `scored` fires at this end with
## is_goal true; a behind is one flag waved in the real game, which this
## does not model (see the class doc on how far the officials go here).
func signal_goal() -> void:
	if role != Role.GOAL:
		return
	_flag_timer = FLAG_HOLD_DURATION


func _process(delta: float) -> void:
	if role == Role.GOAL:
		_process_flags(delta)
	else:
		_process_throw(delta)


func _process_flags(delta: float) -> void:
	var target := 1.0 if _flag_timer > 0.0 else 0.0
	_flag_timer = maxf(0.0, _flag_timer - delta)
	if is_equal_approx(_raise, target):
		return
	var rate := 1.0 / (FLAG_RAISE_TIME if target > _raise else FLAG_LOWER_TIME)
	_raise = move_toward(_raise, target, rate * delta)
	_apply_pose(lerpf(ARM_REST_PITCH, ARM_RAISED_PITCH, _raise),
		ARM_RAISED_SPREAD * _raise, 0.0)


## Four beats across the one duration — see the THROW_* fractions. Written
## as explicit segments rather than a curve so each beat's timing is
## legible and separately tunable, the same way the animation clips in
## HumanoidAnimations lay their keys out around a contact time.
func _process_throw(delta: float) -> void:
	if _throw_duration <= 0.0:
		return
	_throw_elapsed += delta
	var progress := _throw_elapsed / _throw_duration
	var pitch := ARM_REST_PITCH
	var lean := 0.0
	if progress < THROW_CROUCH_END:
		var t := progress / THROW_CROUCH_END
		pitch = lerpf(ARM_REST_PITCH, THROW_CROUCH_PITCH, t)
		lean = lerpf(0.0, THROW_CROUCH_LEAN, t)
	elif progress < THROW_HOLD_END:
		pitch = THROW_CROUCH_PITCH
		lean = THROW_CROUCH_LEAN
	elif progress < THROW_RELEASE_END:
		var t := (progress - THROW_HOLD_END) / (THROW_RELEASE_END - THROW_HOLD_END)
		pitch = lerpf(THROW_CROUCH_PITCH, THROW_RELEASE_PITCH, t)
		lean = lerpf(THROW_CROUCH_LEAN, THROW_RELEASE_LEAN, t)
	elif progress < 1.0:
		var t := (progress - THROW_RELEASE_END) / (1.0 - THROW_RELEASE_END)
		pitch = lerpf(THROW_RELEASE_PITCH, ARM_REST_PITCH, t)
		lean = lerpf(THROW_RELEASE_LEAN, 0.0, t)
	else:
		_throw_duration = 0.0
	_apply_pose(pitch, THROW_ARM_SPREAD, lean)


## Both upper arms plus the spine. The rig is otherwise left in its rest
## pose, which is already a figure standing still.
func _apply_pose(pitch: float, spread: float, lean: float) -> void:
	for side in _arm_bones.size():
		var bone: int = _arm_bones[side]
		if bone < 0:
			continue
		# side 0 is the left arm, which spreads the other way.
		var sign_z := 1.0 if side == 0 else -1.0
		_skeleton.set_bone_pose_rotation(bone,
			Quaternion(Basis.from_euler(Vector3(pitch, 0.0, spread * sign_z))))
	if _spine_bone >= 0:
		_skeleton.set_bone_pose_rotation(_spine_bone,
			Quaternion(Basis.from_euler(Vector3(lean, 0.0, 0.0))))


## Where the ball sits while the field umpire has it — Ball.lock_to() rides
## this node, so the ball is genuinely in his hands through the crouch and
## the sweep up rather than hovering at the spot in front of him.
##
## Hung off the left hand and offset toward the other one, so it lands
## between the two. That offset survives the whole throw because the throw
## only rotates the arms about their own X axis (see _apply_pose), and a
## rotation about X leaves the local X axis alone — the point stays on the
## centreline no matter how far up the arms have swung.
func _build_ball_point() -> void:
	var attachment := BoneAttachment3D.new()
	attachment.name = "BallGrip"
	attachment.bone_name = "LeftHand"
	_skeleton.add_child(attachment)
	_ball_point = Node3D.new()
	_ball_point.name = "BallPoint"
	_ball_point.position = Vector3(-HAND_SPAN * 0.5, -0.06, 0.0)
	attachment.add_child(_ball_point)


## Null for anyone but the field umpire.
func ball_hold_point() -> Node3D:
	return _ball_point


## One flag: a short pole down the hand's grip with the cloth at the top.
## Hung off a BoneAttachment3D of its own rather than through HumanoidRig's
## own mesh helpers — those are private to the rig and specific to building
## a player, and this is the one thing an umpire has that a player doesn't.
func _build_flag(bone_name: String) -> void:
	var attachment := BoneAttachment3D.new()
	attachment.name = "Flag_" + bone_name
	attachment.bone_name = bone_name
	_skeleton.add_child(attachment)

	var pole := MeshInstance3D.new()
	var pole_mesh := CylinderMesh.new()
	pole_mesh.top_radius = FLAG_POLE_RADIUS
	pole_mesh.bottom_radius = FLAG_POLE_RADIUS
	pole_mesh.height = FLAG_POLE_LENGTH
	pole_mesh.radial_segments = 6
	pole.mesh = pole_mesh
	pole.material_override = _material(COLOUR_FLAG_POLE)
	pole.position = Vector3(0.0, -FLAG_POLE_LENGTH * 0.25, 0.0)
	attachment.add_child(pole)

	var cloth := MeshInstance3D.new()
	var cloth_mesh := BoxMesh.new()
	cloth_mesh.size = FLAG_CLOTH
	cloth.mesh = cloth_mesh
	cloth.material_override = _material(COLOUR_FLAG)
	# Hangs off one side of the pole's upper end, the way a flag on a stick
	# actually sits.
	cloth.position = Vector3(FLAG_CLOTH.x * 0.5, FLAG_POLE_LENGTH * 0.35, 0.0)
	attachment.add_child(cloth)


func _material(colour: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.roughness = 0.72
	return material
