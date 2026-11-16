extends Node3D

## Headless check for the fend-off (6Y) as you see it, after the 2026-11-16
## playtest note "still can't see the fend off animation; I want my player's
## hand in the opponent's chest, pushing them back". Two cases:
##  1. alone: a carrier stands and presses RB with nobody near. The left arm
##     must still come out (PlayerAnimation.fend_blend). It used to be skipped
##     unless a contact was already moving the pose.
##  2. a defender jogs straight at a carrier who fends as they close. The
##     palm should land and the defender should be driven back
##     (PlayerController.receive_fend) and stunned, without a tackle.
## Pass/fail is printed per case; exit code 1 on any failure.
##
##   Godot_console.exe --headless --path . res://scenes/dev/fend_check.tscn --fixed-fps 60

const PlayerScene := preload("res://scenes/player/player.tscn")
const BallScene := preload("res://scenes/ball/ball.tscn")

const PRESS_FRAME := 30
const WATCH_FRAMES := 60


class ScriptedBrain extends PlayerBrain:
	var direction := Vector3.ZERO
	var pace := 0.0
	var fend_now := false

	func wish_direction(_controller: PlayerController) -> Vector3:
		return direction

	func gait() -> float:
		return pace

	func wants_fend() -> bool:
		if fend_now:
			fend_now = false
			return true
		return false


var _failures := 0


func _ready() -> void:
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(80.0, 1.0, 80.0)
	shape.shape = box
	shape.position = Vector3(0.0, -0.5, 0.0)
	floor_body.add_child(shape)
	add_child(floor_body)
	# LESSONS.md's same-frame construction race.
	for i in 3:
		var throwaway := PlayerScene.instantiate()
		add_child(throwaway)
		throwaway.queue_free()
	await get_tree().physics_frame
	await _case_alone()
	await _case_defender()
	print("fend_check: %s" % ("all as expected" if _failures == 0 else "%d failed" % _failures))
	get_tree().quit(1 if _failures > 0 else 0)


func _carrier(at: Vector3) -> Array:
	var carrier: PlayerController = PlayerScene.instantiate()
	carrier.team = Tuning.Team.HOME
	add_child(carrier)
	var brain := ScriptedBrain.new()
	carrier.set_brain(brain)
	carrier.global_position = at
	var ball: Ball = BallScene.instantiate()
	add_child(ball)
	ball.global_position = at + Vector3(0.0, 1.0, 0.0)
	await get_tree().physics_frame
	carrier.give_possession(ball)
	return [carrier, brain, ball]


func _blend(player: PlayerController) -> float:
	var anim := player.get_node_or_null(^"PlayerAnimation")
	if anim == null:
		for child in player.get_children():
			if child.has_method(&"fend_blend"):
				anim = child
	return anim.fend_blend() if anim != null else -1.0


func _case_alone() -> void:
	var made := await _carrier(Vector3(-20.0, 0.0, 0.0))
	var carrier: PlayerController = made[0]
	var brain: ScriptedBrain = made[1]
	var peak := 0.0
	for f in PRESS_FRAME + WATCH_FRAMES:
		if f == PRESS_FRAME:
			brain.fend_now = true
		await get_tree().process_frame
		await get_tree().physics_frame
		peak = maxf(peak, _blend(carrier))
	var ok := carrier.is_carrying() and peak > 0.8
	_report("alone: the arm comes out with nobody near", ok, "arm blend peak %.2f, carrying %s" % [peak, carrier.is_carrying()])
	carrier.queue_free()
	(made[2] as Node).queue_free()


func _case_defender() -> void:
	var made := await _carrier(Vector3(20.0, 0.0, 0.0))
	var carrier: PlayerController = made[0]
	var brain: ScriptedBrain = made[1]
	# The carrier faces -Z (rotation 0); the defender comes from 6 m ahead.
	var defender: PlayerController = PlayerScene.instantiate()
	defender.team = Tuning.Team.AWAY
	add_child(defender)
	var d_brain := ScriptedBrain.new()
	d_brain.direction = Vector3(0.0, 0.0, 1.0)
	d_brain.pace = 0.6
	defender.set_brain(d_brain)
	defender.global_position = carrier.global_position + Vector3(0.0, 0.0, -6.0)
	var pressed := false
	var closest := INF
	var back_speed := 0.0
	var peak := 0.0
	var pushed_to := 0.0
	for f in 240:
		await get_tree().physics_frame
		var gap := (defender.global_position - carrier.global_position) * Vector3(1, 0, 1)
		closest = minf(closest, gap.length())
		if not pressed and gap.length() < 2.0:
			brain.fend_now = true
			pressed = true
		if pressed:
			peak = maxf(peak, _blend(carrier))
			# Moving away from the carrier = negative Z here.
			back_speed = maxf(back_speed, -defender.velocity.z)
		if pressed and back_speed > 0.5:
			pushed_to = maxf(pushed_to, gap.length())
	# The defender's brain keeps walking in, so they come back afterwards:
	# what counts is how far the shove put them out.
	var ok := pressed and back_speed > 1.5 and pushed_to > closest + 0.5 \
		and carrier.is_carrying() and peak > 0.8
	_report("defender jogging in is shoved back", ok,
		"closest %.2f m, pushed out to %.2f m, peak back speed %.2f m/s, arm %.2f, carrier still has it %s"
		% [closest, pushed_to, back_speed, peak, carrier.is_carrying()])


func _report(name: String, ok: bool, detail: String) -> void:
	if not ok:
		_failures += 1
	print("  [%s] %s: %s" % ["ok" if ok else "FAIL", name, detail])
