extends Node3D

## Solo free-roam practice (reached via the character screen's PLAY row):
## one player, one ball, the full field, no AI, no clock, no scoring —
## just movement and disposal with an unlimited ball reset. Functionally
## the milestone-1 sandbox (scripts/main.gd) with two differences: it's
## reachable from the menu/character-screen flow instead of being the
## boot scene, and it applies whatever SPEED/HEIGHT the character screen
## was left on (CharacterProfile) to the player it spawns.

const BALL_RESET_AHEAD := 3.0
const BALL_LOST_BELOW := -5.0

@onready var _field: Field = $Field
@onready var _ball: Ball = $Ball
@onready var _player: PlayerController = $Player
@onready var _camera: BroadcastCamera = $BroadcastCamera
@onready var _hud: DebugHud = $DebugHud


func _ready() -> void:
	GameState.mode = GameState.Mode.KICK_TO_KICK
	GameState.phase = GameState.Phase.PLAY

	_player.speed_scale = CharacterProfile.speed_scale()
	_player.kick_power_scale = CharacterProfile.kick_power
	_player.kick_accuracy = CharacterProfile.kick_accuracy
	(_player.get_node("Rig") as Node3D).scale = Vector3.ONE * CharacterProfile.height_scale()

	_camera.target = _player
	_camera.ball = _ball
	_camera.recenter()
	_player.camera = _camera.camera()

	_hud.player = _player
	_hud.ball = _ball

	_player.ball_disposed.connect(_on_ball_disposed)

	_ball.reset_at(_field.centre())
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"pause"):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		SceneWipe.change_scene("res://scenes/ui/main_menu.tscn")
	elif event.is_action_pressed(&"debug_reset"):
		_reset_ball()


func _physics_process(_delta: float) -> void:
	# Safety net, same as the sandbox's — the ball is a real rigid body,
	# so it can genuinely be lost off the map.
	var where := _ball.global_position
	if where.y < BALL_LOST_BELOW \
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
