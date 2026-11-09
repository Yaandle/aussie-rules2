class_name DrillBrain
extends PlayerBrain

## A drill bot (DrillRunner): does one thing at a time, as the drill's beat
## tells it — run to a spot, kick or handball to a teammate — and, when
## it's the one the ball is going to, runs to where it'll come down and
## takes it (LeadBrain's chase). Everything goes through PlayerController
## the way any brain's input does, so a bot's kick is a real kick off the
## same model as yours and can miss.

enum Task { IDLE, RUN_TO, KICK_TO, HANDBALL_TO }

## Within this of a run_to spot counts as there.
const ARRIVE_DISTANCE := 1.0
## Inside this they slow from the drill's gait to a walk, so they pull up
## on the spot instead of running through it.
const EASE_DISTANCE := 3.0
## Physics frames between squaring up and taking the stance, and between
## the stance and the kick (AIBrain waits similarly before a kick).
const STANCE_FRAMES := 2
const KICK_FRAMES := 8
const HANDBALL_FRAMES := 3
## How far ahead of a running receiver a kick is aimed: about a short
## kick's hang time.
const LEAD_SECONDS := 1.3

var ball: Ball = null
var task := Task.IDLE
var point := Vector3.ZERO
var gait_scale := 0.8
var target: PlayerController = null
## True while this bot is who the beat's ball is going to.
var expect_ball := false

var _frames := 0
var _dir := Vector3.ZERO
var _gait := 0.0
var _kick := false
var _execute := false
var _handball := false
var _mark := false
var _charge := -1.0


func run_to(where: Vector3, gait_value: float) -> void:
	task = Task.RUN_TO
	point = where
	gait_scale = gait_value


func kick_to(receiver: PlayerController) -> void:
	task = Task.KICK_TO
	target = receiver
	_frames = 0


func handball_to(receiver: PlayerController) -> void:
	task = Task.HANDBALL_TO
	target = receiver
	_frames = 0


func idle() -> void:
	task = Task.IDLE


func arrived(controller: PlayerController) -> bool:
	if task != Task.RUN_TO:
		return true
	var to_point := point - controller.global_position
	to_point.y = 0.0
	return to_point.length() <= ARRIVE_DISTANCE


func update(controller: PlayerController, _delta: float) -> void:
	_dir = Vector3.ZERO
	_gait = 0.0
	_kick = false
	_execute = false
	_handball = false
	_mark = false
	_charge = -1.0

	if expect_ball and not controller.is_carrying() and _chase(controller):
		return
	match task:
		Task.RUN_TO:
			var to_point := point - controller.global_position
			to_point.y = 0.0
			var dist := to_point.length()
			if dist > ARRIVE_DISTANCE * 0.5:
				_dir = to_point / dist
				_gait = gait_scale if dist > EASE_DISTANCE else 0.3
		Task.KICK_TO:
			_step_kick(controller)
		Task.HANDBALL_TO:
			_step_handball(controller)


## Toward where a ball in flight from someone else comes down, holding the
## safe mark once it's close. False when there's no such ball.
func _chase(controller: PlayerController) -> bool:
	if not is_instance_valid(ball) or ball.is_held or ball.last_disposer() == controller:
		return false
	if not (ball.is_kick_flight() or ball.is_handball_flight() or ball.is_airborne()):
		# On the ground: go and pick it up.
		var to_ball := ball.global_position - controller.global_position
		to_ball.y = 0.0
		if to_ball.length() > 0.3:
			_dir = to_ball.normalized()
			_gait = 0.7
		_mark = to_ball.length() < 2.0
		return true
	var land := ball.predicted_landing_position(LeadBrain.CATCH_HEIGHT)
	var to_land := land - controller.global_position
	to_land.y = 0.0
	if to_land.length() > 0.3:
		_dir = to_land.normalized()
		_gait = 1.0 if to_land.length() > LeadBrain.SETTLE_DISTANCE else 0.35
	_mark = controller.global_position.distance_to(ball.global_position) <= LeadBrain.MARK_RANGE
	return true


func _step_kick(controller: PlayerController) -> void:
	if not controller.is_carrying() or not is_instance_valid(target):
		task = Task.IDLE
		return
	_frames += 1
	var aim := _lead_point(controller)
	# Square up every frame until the stance is actually up: a bot that has
	# just marked walks back off it first (MARK_RETREAT_DISTANCE), turning as
	# it goes, and the kick is aimed along the facing the stance starts with.
	if not controller.is_kick_aiming():
		controller.face_toward(aim)
		_frames = mini(_frames, STANCE_FRAMES)
	if _frames >= STANCE_FRAMES:
		_kick = true
		var flat := aim - controller.global_position
		flat.y = 0.0
		_charge = controller.charge_for_distance(flat.length())
	if _frames >= STANCE_FRAMES + KICK_FRAMES:
		_execute = true


func _step_handball(controller: PlayerController) -> void:
	if not controller.is_carrying() or not is_instance_valid(target):
		task = Task.IDLE
		return
	_frames += 1
	# A handball goes along the move intent at the press, so point it first.
	var to_target := _lead_point(controller) - controller.global_position
	to_target.y = 0.0
	if to_target.length_squared() > 0.0001:
		_dir = to_target.normalized()
	if _frames >= HANDBALL_FRAMES:
		_handball = true


## Where the receiver will be by the time it gets there, roughly.
func _lead_point(_controller: PlayerController) -> Vector3:
	var run := Vector3(target.velocity.x, 0.0, target.velocity.z)
	return target.global_position + run * (LEAD_SECONDS if task == Task.KICK_TO else 0.4)


func wish_direction(_controller: PlayerController) -> Vector3:
	return _dir


func gait() -> float:
	return _gait


func wants_kick() -> bool:
	return _kick


func wants_kick_execute() -> bool:
	return _execute


func kick_charge_override() -> float:
	return _charge


func wants_handball() -> bool:
	return _handball


func wants_mark_safe() -> bool:
	return _mark
