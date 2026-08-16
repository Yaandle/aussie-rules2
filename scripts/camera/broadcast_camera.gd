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

@export var distance := Tuning.CAM_DISTANCE

## What the rig frames. Set by whoever owns the scene.
var target: Node3D = null
var ball: Ball = null

@onready var _yaw_pivot: Node3D = $Yaw
@onready var _pitch_pivot: Node3D = $Yaw/Pitch
@onready var _arm: SpringArm3D = $Yaw/Pitch/SpringArm3D
@onready var _camera: Camera3D = $Yaw/Pitch/SpringArm3D/Camera3D

var _yaw := 0.0
var _pitch := deg_to_rad(Tuning.CAM_PITCH_DEFAULT)
var _focus := Vector3.ZERO
var _ball_weight := 0.0
var _punch := 0.0


func _ready() -> void:
	_arm.spring_length = distance
	_camera.fov = Tuning.CAM_FOV_BASE
	recenter()


func _process(delta: float) -> void:
	if not is_instance_valid(target):
		return
	_update_rotation(delta)
	_update_focus(delta)
	_update_fov(delta)


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

	var stick := InputManager.get_look_vector()
	var mouse := InputManager.take_mouse_look()

	_yaw -= stick.x * deg_to_rad(Tuning.CAM_YAW_SPEED) * delta + deg_to_rad(mouse.x)
	_pitch += stick.y * deg_to_rad(Tuning.CAM_PITCH_SPEED) * delta - deg_to_rad(mouse.y)
	_pitch = clampf(_pitch,
		deg_to_rad(Tuning.CAM_PITCH_MIN), deg_to_rad(Tuning.CAM_PITCH_MAX))

	var rate := 1.0 - exp(-Tuning.CAM_ROTATE_RATE * delta)
	_yaw_pivot.rotation.y = lerp_angle(_yaw_pivot.rotation.y, _yaw, rate)
	_pitch_pivot.rotation.x = lerpf(_pitch_pivot.rotation.x, _pitch, rate)


func _is_target_aiming() -> bool:
	return target is PlayerController and (target as PlayerController).is_kick_aiming()


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
