extends Node3D

## Milestone 1 harness (design doc §11).
##
## One CharacterBody3D player with blend-space locomotion, one physically
## simulated ball, one oval, one broadcast camera. No AI, no second team,
## no match rules — that ordering is the brief's, and it is the same
## "cut complexity before adding it" order Prototype 1's own cleanup pass
## followed.
##
## What to feel for:
##   - sprint flat out, then demand a 180. The player should plant, lose
##     the speed, come round in an arc and rebuild it. If that happens
##     without the animation sliding, the weight model is working.
##   - hold K to full charge and let go. The ball should climb lazily and
##     come down steeply — that asymmetry is the air drag, and it is what
##     a scripted flight path can never give you.
##   - run onto a stationary ball at pace. It should be knocked on, not
##     absorbed.

const BALL_RESET_AHEAD := 3.0

@onready var _field: Field = $Field
@onready var _ball: Ball = $Ball
@onready var _player: PlayerController = $Player
@onready var _camera: BroadcastCamera = $BroadcastCamera
@onready var _hud: DebugHud = $DebugHud


func _ready() -> void:
	GameState.mode = GameState.Mode.SANDBOX
	GameState.phase = GameState.Phase.PLAY

	_camera.target = _player
	_camera.ball = _ball
	_camera.recenter()
	# Movement is relative to the Camera3D itself, not the rig root — the
	# rig root never rotates, its yaw gimbal does.
	_player.camera = _camera.camera()
	_player.camera_rig = _camera

	_hud.player = _player
	_hud.ball = _ball

	AudioManager.register_player(_player)
	_player.ball_disposed.connect(_on_ball_disposed)

	_ball.reset_at(_field.centre())
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"pause"):
		_toggle_mouse_capture()
	elif event.is_action_pressed(&"debug_reset"):
		_reset_ball()


func _physics_process(_delta: float) -> void:
	# Safety net: the ball is a real rigid body now, so it can genuinely
	# be lost off the map.
	var where := _ball.global_position
	if where.y < Tuning.BALL_LOST_BELOW \
			or absf(where.x) > Tuning.FIELD_HALF_LENGTH + Field.SURROUND_MARGIN \
			or absf(where.z) > Tuning.FIELD_HALF_WIDTH + Field.SURROUND_MARGIN:
		_reset_ball()


func _reset_ball() -> void:
	_player.drop_ball()
	var ahead := -_player.global_transform.basis.z * BALL_RESET_AHEAD
	_ball.reset_at(_player.global_position + ahead + Vector3.UP * 0.3)


func _on_ball_disposed(action: Tuning.Action) -> void:
	if action == Tuning.Action.KICK:
		_camera.punch(Tuning.CAM_PUNCH_KICK)


func _toggle_mouse_capture() -> void:
	if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
