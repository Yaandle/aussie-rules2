class_name MenuBackdrop
extends Node3D

## Decorative background for the mode-select menu: a loop of slow camera
## moves around our oval, each holding a few seconds before a hard cut to
## the next, broadcast-montage style. The ground is the one the player
## picked in Settings (Field.follow_field_style, the same dressing Full Game
## and Kick to Kick use), so the menu shows the actual fields rather than
## field.gd's bare procedural ground. The shots are low and late-afternoon
## to match the menu reference image: behind the goal posts, along the
## wing, past the players. Purely cosmetic; nothing here is wired to
## gameplay, the two players are static (base PlayerBrain, never told to
## move) and the ball just settles under real gravity once and stays put.

const FIELD_SCENE := preload("res://scenes/field/field.tscn")
const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const BALL_SCENE := preload("res://scenes/ball/ball.tscn")

const SHOT_DURATION := 4.5   ## s each framing holds before the next hard cut (slower dollies read calmer behind the cards)

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
	var field := FIELD_SCENE.instantiate() as Field
	# Before add_child(): Field._ready() reads it to swap in the oval.
	field.follow_field_style = true
	add_child(field)

	var ball := BALL_SCENE.instantiate() as Ball
	add_child(ball)
	ball.reset_at(Vector3(4.0, 3.0, -1.0))

	_spawn_player(Tuning.Team.HOME, Vector3(6.0, 0.0, -2.0), 150.0)
	_spawn_player(Tuning.Team.AWAY, Vector3(-3.0, 0.0, 4.0), -40.0)

	var goal_x := Tuning.FIELD_HALF_LENGTH - 1.5   # Field.GOAL_LINE_INSET
	# Each shot is a slow dolly from -> to, aimed at look_at the whole way.
	_shots = [
		# Low behind the goal posts, sliding across, looking down the ground
		# with the posts framing the shot (the reference image's angle).
		Shot.new(Vector3(goal_x + 6.0, 1.7, -9.0), Vector3(goal_x + 6.0, 2.0, 9.0),
			Vector3(0.0, 5.0, 0.0)),
		# Low on the wing, tracking along the boundary past the players.
		Shot.new(Vector3(16.0, 1.3, 26.0), Vector3(-8.0, 1.5, 26.0), Vector3(2.0, 1.2, 0.0)),
		# Wide broadcast flyover of the whole oval and its trees.
		Shot.new(Vector3(-70.0, 38.0, 62.0), Vector3(70.0, 32.0, -55.0), Vector3.ZERO),
		# Slow pan past the standing players from a few metres off, so they
		# read whole below the card row rather than as legs under it.
		Shot.new(Vector3(14.0, 1.4, 16.0), Vector3(6.0, 1.4, 17.0), Vector3(2.0, 1.6, 0.0)),
		# From the centre square, pushing in towards the far goals.
		Shot.new(Vector3(-24.0, 2.0, -12.0), Vector3(-12.0, 2.2, -10.0),
			Vector3(goal_x, 5.0, 0.0)),
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
	# Set before add_child(), so HumanoidRig._ready() builds with the
	# right kit colour, and so the initial facing sticks (PlayerController
	# recomputes its facing state from `rotation` the moment it enters the
	# tree; changing rotation afterwards would just get overridden back).
	(instance.get_node("Rig") as HumanoidRig).away_kit = team == Tuning.Team.AWAY
	instance.position = spawn_position
	instance.rotation.y = deg_to_rad(facing_deg)
	add_child(instance)
	instance.set_brain(PlayerBrain.new())
