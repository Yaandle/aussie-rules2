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
const BALL_LOST_BELOW := -5.0

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

	_hud.player = _player
	_hud.ball = _ball

	_player.ball_disposed.connect(_on_ball_disposed)

	_ball.reset_at(_field.centre())
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	if OS.get_cmdline_user_args().has("--smoke"):
		_smoke_test.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"pause"):
		_toggle_mouse_capture()
	elif event.is_action_pressed(&"debug_reset"):
		_reset_ball()


func _physics_process(_delta: float) -> void:
	# Safety net: the ball is a real rigid body now, so it can genuinely
	# be lost off the map.
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


func _smoke_test() -> void:
	var tree := get_node("Player/AnimationTree") as AnimationTree
	var ap := get_node("Player/AnimationPlayer") as AnimationPlayer
	print("TREE active=", tree.active, " root=", tree.tree_root)
	print("CLIPS ", ap.get_animation_list())
	var sm := tree.tree_root as AnimationNodeStateMachine
	print("STATES ", sm.get_node_list() if sm else "NO STATE MACHINE")
	var bs := sm.get_node(&"locomotion") as AnimationNodeBlendSpace2D
	print("BLEND POINTS ", bs.get_blend_point_count() if bs else -1)
	print("RIG deep node ", _player.get_node_or_null("Rig/Hips/HipL/KneeL/AnkleL"))
	var hull := _ball.get_node("CollisionShape3D").shape
	print("BALL shape=", hull.get_class(), " pts=",
		hull.points.size() if hull is ConvexPolygonShape3D else 0)
	var marks := _field.get_node_or_null("Markings") as MeshInstance3D
	print("MARKINGS verts=", marks.mesh.surface_get_array_len(0) if marks else -1)
	print("GOAL POSTS ", _field.get_node("Goals").get_child_count())

	await get_tree().create_timer(0.5).timeout
	print("SETTLED player_y=%.3f on_floor=%s ball_y=%.3f anim=%s" % [
		_player.global_position.y, _player.is_on_floor(),
		_ball.global_position.y, _player.animation_state()])

	# Drive the disposal path directly: gather, then kick at full charge.
	_ball.reset_at(_player.global_position - _player.global_transform.basis.z * 0.6
		+ Vector3.UP * 0.2)
	await get_tree().physics_frame
	await get_tree().physics_frame
	print("GATHERED ", _player.is_carrying())
	_player.set("_kick_charge", 1.0)
	_player.call("_begin", Tuning.Action.KICK)
	var peak := 0.0
	var flight := 0.0
	var start := _ball.global_position
	for i in 260:
		await get_tree().physics_frame
		peak = maxf(peak, _ball.global_position.y)
		if _ball.global_position.y > 0.3:
			flight += 1.0 / 60.0
	var travel := Vector2(_ball.global_position.x - start.x,
		_ball.global_position.z - start.z).length()
	print("KICK peak=%.1fm hang=%.2fs travel=%.1fm anim=%s" % [
		peak, flight, travel, _player.animation_state()])
	get_tree().quit()


func _toggle_mouse_capture() -> void:
	if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
