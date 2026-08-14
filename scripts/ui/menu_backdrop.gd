class_name MenuBackdrop
extends Node3D

## Decorative background for the mode-select menu: three fixed camera moves
## on a loop — a wide pan across the ground, a low pan along the goal line,
## a close pan past a standing player — each holding a few seconds before a
## hard cut to the next, broadcast-montage style. Purely cosmetic; nothing
## here is wired to gameplay, the two players are static (base PlayerBrain,
## never told to move) and the ball just settles under real gravity once
## and stays put.

const FIELD_SCENE := preload("res://scenes/field/field.tscn")
const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const BALL_SCENE := preload("res://scenes/ball/ball.tscn")

const SHOT_DURATION := 3.5   ## s each framing holds before the next hard cut

class Shot:
	var from: Vector3
	var to: Vector3
	var look_at: Vector3

	func _init(p_from: Vector3, p_to: Vector3, p_look_at: Vector3) -> void:
		from = p_from
		to = p_to
		look_at = p_look_at


var _shots: Array[Shot] = []
var _shot_index := 0
var _shot_t := 0.0

@onready var _camera: Camera3D = $Camera3D


func _ready() -> void:
	add_child(FIELD_SCENE.instantiate())

	var ball := BALL_SCENE.instantiate() as Ball
	add_child(ball)
	ball.reset_at(Vector3(4.0, 3.0, -1.0))

	_spawn_player(Tuning.Team.HOME, Vector3(6.0, 0.0, -2.0), 150.0)
	_spawn_player(Tuning.Team.AWAY, Vector3(-3.0, 0.0, 4.0), -40.0)

	var goal_x := Tuning.FIELD_HALF_LENGTH - 1.5   # Field.GOAL_LINE_INSET
	_shots = [
		# Wide broadcast flyover of the whole ground.
		Shot.new(Vector3(-70.0, 48.0, 60.0), Vector3(70.0, 40.0, -55.0), Vector3.ZERO),
		# Low pan along one end's goal line.
		Shot.new(Vector3(goal_x - 14.0, 4.0, -18.0), Vector3(goal_x - 14.0, 5.5, 18.0),
			Vector3(goal_x, 3.0, 0.0)),
		# Close pan past the standing players.
		Shot.new(Vector3(3.0, 2.2, 9.0), Vector3(-2.0, 1.8, 2.0), Vector3(2.0, 1.4, -1.0)),
	]
	_cut_to_shot()


func _process(delta: float) -> void:
	if _shots.is_empty():
		return
	_shot_t += delta
	var shot := _shots[_shot_index]
	var fraction := clampf(_shot_t / SHOT_DURATION, 0.0, 1.0)
	_camera.global_position = shot.from.lerp(shot.to, fraction)
	_camera.look_at(shot.look_at, Vector3.UP)
	if _shot_t >= SHOT_DURATION:
		_shot_index = (_shot_index + 1) % _shots.size()
		_shot_t = 0.0
		_cut_to_shot()


func _cut_to_shot() -> void:
	var shot := _shots[_shot_index]
	_camera.global_position = shot.from
	_camera.look_at(shot.look_at, Vector3.UP)


func _spawn_player(team: Tuning.Team, spawn_position: Vector3, facing_deg: float) -> void:
	var instance := PLAYER_SCENE.instantiate() as PlayerController
	instance.team = team
	# Set before add_child(), so PlaceholderRig._ready() builds with the
	# right kit colour, and so the initial facing sticks (PlayerController
	# recomputes its facing state from `rotation` the moment it enters the
	# tree; changing rotation afterwards would just get overridden back).
	(instance.get_node("Rig") as PlaceholderRig).away_kit = team == Tuning.Team.AWAY
	instance.position = spawn_position
	instance.rotation.y = deg_to_rad(facing_deg)
	add_child(instance)
	instance.set_brain(PlayerBrain.new())
