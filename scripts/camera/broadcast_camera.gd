class_name BroadcastCamera
extends Node3D

## Dynamic third-person broadcast rig (design doc §6).
##
## Same focus-follow idea Prototype 1's HeroCamera had — a point of
## interest, smoothed, with a zoom that reacts to the moment — rebuilt as
## a real 3D rig: a yaw/pitch gimbal on a SpringArm3D so the camera
## climbs over obstructions instead of clipping through them, with
## look-ahead into the direction of travel and an FOV that opens up as
## the player winds up.
##
## The focus point is not simply the player. Once the ball is properly in
## the air it pulls the focus toward itself, in proportion to how far it
## has gone — so a long kick is framed as a long kick rather than as the
## back of a jumper. That is the "follows the ball/play focus point" line
## in §6, in the smallest honest form it can take before there is a
## second team to have a play focus between.

## CHASE is the rig described above — this is Full Game's "3rd Person"
## option. FULL_SIDE is a real broadcast full-ground rig: mounted outside
## the boundary and elevated, panning to track play rather than orbiting
## behind one player — offered as a Full Game settings option
## (Settings.full_game_camera_mode) alongside it, not a replacement for it.
## See _update_full_side().
enum Mode { CHASE, FULL_SIDE }

@export var distance := Tuning.CAM_DISTANCE

## What the rig frames. Set by whoever owns the scene.
var target: Node3D = null
var ball: Ball = null
var mode: Mode = Mode.CHASE

@onready var _yaw_pivot: Node3D = $Yaw
@onready var _pitch_pivot: Node3D = $Yaw/Pitch
@onready var _arm: SpringArm3D = $Yaw/Pitch/SpringArm3D
@onready var _camera: Camera3D = $Yaw/Pitch/SpringArm3D/Camera3D

var _yaw := 0.0
var _pitch := deg_to_rad(Tuning.CAM_PITCH_DEFAULT)
var _focus := Vector3.ZERO
var _ball_weight := 0.0
var _punch := 0.0

## Counts down from CAM_SWITCH_PAN_DURATION after switch_target() — while
## positive, _update_rotation() eases yaw/pitch toward the new target's
## facing instead of reading stick/mouse input. See switch_target().
var _switch_timer := 0.0

## Training-coach two-shot (see Tuning's "Training coaches" section): a
## fixed side-on framing of two parties instead of the follow-cam's spring
## arm behind one target, entered/exited explicitly rather than falling
## out of the normal focus/rotation update.
var _dialogue_left: Node3D = null
var _dialogue_right: Node3D = null


func _ready() -> void:
	_arm.spring_length = distance
	_camera.fov = Tuning.CAM_FOV_BASE
	recenter()


func _process(delta: float) -> void:
	if not is_instance_valid(target):
		return
	_switch_timer = maxf(0.0, _switch_timer - delta)
	if is_instance_valid(_dialogue_left) and is_instance_valid(_dialogue_right):
		_update_dialogue_framing(delta)
	elif mode == Mode.FULL_SIDE:
		_update_full_side(delta)
	else:
		_update_rotation(delta)
		_update_focus(delta)
		_update_fov(delta)
	_clamp_camera_height()


## Switches the rig's behaviour. Safe to call at any time, including
## mid-match — the target mode's own update function fully repositions
## the rig on its very next _process(), so there is nothing to hand off
## explicitly between modes beyond what recenter() already resets.
func set_mode(new_mode: Mode) -> void:
	if mode == new_mode:
		return
	mode = new_mode
	recenter()


## The SpringArm3D's own shapecast keeps the camera from clipping through
## geometry *in front of* it, but nothing stops a steep upward-look pitch
## from swinging the lens *below* the ground plane behind/under the rig —
## concretely, CAM_PITCH_MAX combined with the arm's length and the focus
## point's chest-height offset can put the camera's own Y below zero, so
## the pitch itself was never the bug, just one of several inputs (pitch,
## dialogue's collapsed arm, a future mode) that can produce the same
## underground lens. Clamping the one thing that actually matters — the
## rendered lens height — after every mode's update runs is robust to all
## of them at once, rather than re-deriving a safe bound for each. Pushes
## the whole rig up by the shortfall rather than editing the camera's own
## local transform directly, so yaw/pitch/arm framing stays exactly as
## each mode computed it, just translated clear of the ground.
const MIN_CAMERA_HEIGHT := 0.4   # m

func _clamp_camera_height() -> void:
	var shortfall := MIN_CAMERA_HEIGHT - _camera.global_position.y
	if shortfall > 0.0:
		global_position.y += shortfall


## Side-on two-shot of `left` and `right` (design brief: coach on one side,
## player on the other, a chat bubble's worth of space between them) —
## called by kick_to_kick.gd when a coach conversation starts.
func enter_dialogue(left: Node3D, right: Node3D) -> void:
	_dialogue_left = left
	_dialogue_right = right


## Drops straight back to the normal follow-cam behind `target` — the
## brief's "pans the camera back out behind the player" is just this: stop
## framing the conversation and recentre on the player like any other time
## the rig snaps back to them.
func exit_dialogue() -> void:
	_dialogue_left = null
	_dialogue_right = null
	recenter()


## Snap the view round to look where the player is looking, and drop the
## focus straight back onto them — "camera, get back on me".
func recenter() -> void:
	if not is_instance_valid(target):
		return
	var forward := -target.global_transform.basis.z
	_yaw = atan2(-forward.x, -forward.z)
	_pitch = deg_to_rad(Tuning.CAM_PITCH_DEFAULT)
	_ball_weight = 0.0
	_focus = _target_focus()
	global_position = _focus
	_yaw_pivot.rotation.y = _yaw
	_pitch_pivot.rotation.x = _pitch
	# Undoes the dialogue framing's collapsed arm/tightened FOV, if either
	# was left mid-lerp — recenter() is the one path every camera state
	# funnels back through (exit_dialogue included), so it's the one place
	# that has to restore both rather than just rotation/focus.
	_arm.spring_length = distance
	_camera.fov = Tuning.CAM_FOV_BASE


## Swings the rig across onto `new_target` instead of recenter()'s instant
## cut — the human-controlled-player switch's own entry point, not a second
## way to do what recenter() already does. Position needs nothing special:
## _update_focus()'s existing per-frame lerp (CAM_FOLLOW_RATE) carries
## global_position across to the new focus point smoothly all by itself the
## moment `target` changes, since nothing here calls recenter() to hard-set
## it. Only yaw/pitch need help — normal play never re-aims them except from
## stick/mouse input, so left alone they would keep facing wherever they
## last pointed, at whatever stale angle that was to the new target, for as
## long as nobody touched the camera stick. _switch_timer gates a short
## window (CAM_SWITCH_PAN_DURATION) where _update_rotation() eases them
## toward the new target's facing instead, then hands control back.
func switch_target(new_target: Node3D) -> void:
	target = new_target
	_ball_weight = 0.0
	_switch_timer = Tuning.CAM_SWITCH_PAN_DURATION


## A transient FOV nudge on a key moment — §6's "tightens on contests and
## goals". Negative tightens.
func punch(amount: float) -> void:
	_punch += amount


func camera() -> Camera3D:
	return _camera


func _update_rotation(delta: float) -> void:
	# While the player is in kick stance, the right stick/mouse drives kick
	# aim instead (PlayerController._update_kick_aim) — so the camera has
	# to stop consuming that input for the duration, not fight over it.
	# Holding last orientation is correct here: _update_focus/_update_fov
	# keep running unaffected, so the rig still tracks position and speed,
	# it just stops re-orienting from stick/mouse until aiming ends.
	if _is_target_aiming():
		return

	if Input.is_action_just_pressed(&"camera_recenter"):
		recenter()
		return

	if _switch_timer > 0.0:
		_ease_toward_switch_target(delta)
		return

	var stick := InputManager.get_look_vector()
	var mouse := InputManager.take_mouse_look()

	_yaw -= stick.x * deg_to_rad(Tuning.CAM_YAW_SPEED) * delta + deg_to_rad(mouse.x)
	_pitch += stick.y * deg_to_rad(Tuning.CAM_PITCH_SPEED) * delta - deg_to_rad(mouse.y)
	_pitch = clampf(_pitch,
		deg_to_rad(Tuning.CAM_PITCH_MIN), deg_to_rad(Tuning.CAM_PITCH_MAX))

	var rate := 1.0 - exp(-Tuning.CAM_ROTATE_RATE * delta)
	_yaw_pivot.rotation.y = lerp_angle(_yaw_pivot.rotation.y, _yaw, rate)
	_pitch_pivot.rotation.x = lerpf(_pitch_pivot.rotation.x, _pitch, rate)


## The switch_target() window's yaw/pitch tail — same lerp shape
## _update_rotation()'s own tail end uses, just easing toward the new
## target's facing (recenter()'s own formula for "behind them looking
## forward") instead of toward stick/mouse input, and at the slower,
## deliberately cinematic CAM_SWITCH_YAW_RATE rather than CAM_ROTATE_RATE.
func _ease_toward_switch_target(delta: float) -> void:
	var forward := -target.global_transform.basis.z
	var desired_yaw := atan2(-forward.x, -forward.z)
	var rate := 1.0 - exp(-Tuning.CAM_SWITCH_YAW_RATE * delta)
	_yaw = lerp_angle(_yaw, desired_yaw, rate)
	_pitch = lerpf(_pitch, deg_to_rad(Tuning.CAM_PITCH_DEFAULT), rate)
	_yaw_pivot.rotation.y = lerp_angle(_yaw_pivot.rotation.y, _yaw, rate)
	_pitch_pivot.rotation.x = lerpf(_pitch_pivot.rotation.x, _pitch, rate)


func _is_target_aiming() -> bool:
	return target is PlayerController and (target as PlayerController).is_kick_aiming()


## Positions the rig off to the side of the left<->right line, level with
## both faces, and points the whole yaw/pitch/spring-arm chain at the
## midpoint between them — with the arm collapsed to ~0, the camera ends
## up sitting essentially at that side position looking at the midpoint,
## which is the two-shot the follow-cam's own spring-arm parameterisation
## has no way to express (it only ever frames one target from behind).
func _update_dialogue_framing(delta: float) -> void:
	var a := _dialogue_left.global_position + Vector3.UP * Tuning.CAM_FOCUS_HEIGHT
	var b := _dialogue_right.global_position + Vector3.UP * Tuning.CAM_FOCUS_HEIGHT
	var mid := (a + b) * 0.5
	var along := b - a
	along.y = 0.0
	along = along.normalized() if along.length_squared() > 0.0001 else Vector3.FORWARD
	var side := Vector3(along.z, 0.0, -along.x)

	var desired_pos := mid + side * Tuning.CAM_DIALOGUE_DISTANCE \
		+ Vector3.UP * Tuning.CAM_DIALOGUE_HEIGHT
	var rate := 1.0 - exp(-Tuning.CAM_FOLLOW_RATE * delta)
	_focus = _focus.lerp(desired_pos, rate)
	global_position = _focus

	var to_mid := mid - global_position
	to_mid.y = 0.0
	var desired_yaw := _yaw
	if to_mid.length_squared() > 0.0001:
		desired_yaw = atan2(-to_mid.x, -to_mid.z)
	_yaw = lerp_angle(_yaw, desired_yaw, rate)
	_pitch = deg_to_rad(Tuning.CAM_DIALOGUE_PITCH)
	_yaw_pivot.rotation.y = _yaw
	_pitch_pivot.rotation.x = lerpf(_pitch_pivot.rotation.x, _pitch, rate)

	_arm.spring_length = lerpf(_arm.spring_length, 0.05, rate)
	_camera.fov = lerpf(_camera.fov, Tuning.CAM_DIALOGUE_FOV, rate)


## Full-Side (design brief; this project's earlier working title for it
## was "orthodox" — Prototype 1's own camera style is what it started
## from). A real broadcast full-ground rig, not a blimp hovering over the
## ball: the pivot itself sits at a fixed position outside the field
## (Tuning.CAM_FULL_SIDE_SIDE_OFFSET past the boundary, CAM_FULL_SIDE_
## HEIGHT up), panning along the field's length to track which end play is
## at, and looking back across at the play rather than straight down —
## "outside the field in the air", not the old version's steep top-down
## pitch reached by leaning on the spring arm's length. The look-down pitch
## is derived from the real geometry (elevation vs. horizontal distance to
## the play) each frame rather than a fixed guessed angle, so it's never
## aimed above or below the actual ball as play moves along the ground —
## the "do not simply rotate the camera downward" instruction this was
## built against, satisfied by computing the angle instead of picking one.
## Full Game only (see Settings.full_game_camera_mode's own doc comment) —
## kick_to_kick has no second team or tactical shape for this view to
## show, so it keeps the chase cam unconditionally.
func _update_full_side(delta: float) -> void:
	var focus_point := target.global_position
	if is_instance_valid(ball):
		focus_point = focus_point.lerp(ball.global_position, 0.5)
	focus_point.y = 0.0

	var rig_target := Vector3(
		focus_point.x, Tuning.CAM_FULL_SIDE_HEIGHT, Tuning.CAM_FULL_SIDE_SIDE_OFFSET)
	var rate := 1.0 - exp(-Tuning.CAM_FULL_SIDE_FOLLOW_RATE * delta)
	_focus = _focus.lerp(rig_target, rate)
	global_position = _focus

	var to_play := focus_point - Vector3(global_position.x, 0.0, global_position.z)
	var desired_yaw := _yaw
	if to_play.length_squared() > 1.0:
		desired_yaw = atan2(-to_play.x, -to_play.z)
	_yaw = lerp_angle(_yaw, desired_yaw, rate)

	var desired_pitch := -atan2(Tuning.CAM_FULL_SIDE_HEIGHT, maxf(to_play.length(), 1.0))
	_pitch = lerpf(_pitch, desired_pitch, rate)

	_yaw_pivot.rotation.y = _yaw
	_pitch_pivot.rotation.x = _pitch

	_arm.spring_length = lerpf(_arm.spring_length, Tuning.CAM_FULL_SIDE_ARM, rate)
	_camera.fov = lerpf(_camera.fov, Tuning.CAM_FULL_SIDE_FOV,
		1.0 - exp(-Tuning.CAM_FOV_RATE * delta))


func _update_focus(delta: float) -> void:
	var want := 0.0
	if is_instance_valid(ball) and ball.is_airborne():
		var travelled := ball.global_position.distance_to(target.global_position)
		want = Tuning.CAM_BALL_FOCUS_MAX \
			* clampf(travelled / Tuning.CAM_MAX_FRAMING_DISTANCE, 0.0, 1.0)
	_ball_weight = lerpf(_ball_weight, want,
		1.0 - exp(-Tuning.CAM_BALL_FOCUS_RATE * delta))

	var desired := _target_focus()
	if _ball_weight > 0.001 and is_instance_valid(ball):
		desired = desired.lerp(ball.global_position, _ball_weight)

	_focus = _focus.lerp(desired, 1.0 - exp(-Tuning.CAM_FOLLOW_RATE * delta))
	global_position = _focus


## Where on the player the rig points, led by where they are going. The
## look-ahead is what stops a fast turn feeling like the camera is being
## dragged along behind you.
func _target_focus() -> Vector3:
	var point := target.global_position + Vector3.UP * Tuning.CAM_FOCUS_HEIGHT
	var velocity := Vector3.ZERO
	if target is CharacterBody3D:
		velocity = (target as CharacterBody3D).velocity
	var lead := Vector3(velocity.x, 0.0, velocity.z) * Tuning.CAM_LOOKAHEAD_TIME
	if lead.length() > Tuning.CAM_LOOKAHEAD_MAX:
		lead = lead.normalized() * Tuning.CAM_LOOKAHEAD_MAX
	return point + lead


func _update_fov(delta: float) -> void:
	_punch = lerpf(_punch, 0.0, 1.0 - exp(-Tuning.CAM_PUNCH_DECAY * delta))
	var speed := 0.0
	if target is CharacterBody3D:
		var v := (target as CharacterBody3D).velocity
		speed = Vector3(v.x, 0.0, v.z).length()
	var desired := Tuning.CAM_FOV_BASE + _punch \
		+ Tuning.CAM_FOV_SPRINT_GAIN * clampf(speed / Tuning.SPRINT_SPEED, 0.0, 1.0)
	_camera.fov = lerpf(_camera.fov, desired, 1.0 - exp(-Tuning.CAM_FOV_RATE * delta))
