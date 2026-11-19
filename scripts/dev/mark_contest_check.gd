extends Node3D

## Dev-only headless check of contested marks (6AE, MarkContest) and the
## jump attribute (6AD). Two players stand side by side under a kick and
## both go for it; each case changes one thing and names who should take
## it. Prints each player's MarkContest read and PASS / FAIL per case.
##
##   godot --headless --path . res://scenes/dev/mark_contest_check.tscn --fixed-fps 60
##
## Scripted brains, so marks go down the AI's path (no HumanBrain timing
## grade on Safe). A is on the left (x < 0), B on the right; the kick
## comes at them from in front.

const PlayerScene := preload("res://scenes/player/player.tscn")
const BallScene := preload("res://scenes/ball/ball.tscn")

const GAP := 0.9            # m between the two
const KICK_DISTANCE := 14.0
const FLIGHT := 1.0         # s to the hands
const CHEST := 1.4          # m: CatchPoint's own height
const HIGH := 2.75          # m: out of standing reach, a (Y) leap's ball
const WAIT_FRAMES := 170

## name, expected ("A", "B", "none"), ball height, ball x offset (+ toward B),
## hold (A) (else both press (Y) timed to the ball), then per player
## [mass kg, jump, present].
const CASES := [
	["alone: an uncontested mark is untouched", "A", CHEST, -GAP * 0.5, true, [80.0, 1.0, true], [80.0, 1.0, false]],
	["heavier body holds the spot", "A", CHEST, 0.0, true, [95.0, 1.0, true], [70.0, 1.0, true]],
	["heavier body, other side", "B", CHEST, 0.0, true, [70.0, 1.0, true], [95.0, 1.0, true]],
	["front position: ball nearer B", "B", CHEST, 0.3, true, [80.0, 1.0, true], [80.0, 1.0, true]],
	["front position: ball nearer A", "A", CHEST, -0.3, true, [80.0, 1.0, true], [80.0, 1.0, true]],
	["high ball: B's jump 1.5 over A's 0.7", "B", HIGH, 0.0, false, [80.0, 0.7, true], [80.0, 1.5, true]],
	["high ball: A's jump 1.5 over B's 0.7", "A", HIGH, 0.0, false, [80.0, 1.5, true], [80.0, 0.7, true]],
	["twins: a dead heat goes the same way twice (1)", "same", CHEST, 0.0, true, [80.0, 1.0, true], [80.0, 1.0, true]],
	["twins: a dead heat goes the same way twice (2)", "same", CHEST, 0.0, true, [80.0, 1.0, true], [80.0, 1.0, true]],
]


class ScriptedBrain extends PlayerBrain:
	var hold_safe := false
	var press_aggressive := false

	func wants_mark_safe() -> bool:
		return hold_safe

	func wants_mark_aggressive() -> bool:
		if press_aggressive:
			press_aggressive = false
			return true
		return false


var _caught_by := ""
var _twin_result := ""
var _failures := 0


func _ready() -> void:
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(80.0, 1.0, 80.0)
	shape.shape = box
	shape.position = Vector3(0.0, -0.5, 0.0)
	floor_body.add_child(shape)
	add_child(floor_body)
	for spec: Array in CASES:
		await _run(spec)
	print("mark_contest_check: %d / %d cases as expected" % [CASES.size() - _failures, CASES.size()])
	get_tree().quit(1 if _failures > 0 else 0)


func _run(spec: Array) -> void:
	var players := {}
	var brains := {}
	var peak := {}
	for tag: String in ["A", "B"]:
		var stats: Array = spec[5] if tag == "A" else spec[6]
		if not stats[2]:
			continue
		var p: PlayerController = PlayerScene.instantiate()
		p.team = Tuning.Team.HOME if tag == "A" else Tuning.Team.AWAY
		add_child(p)
		p.global_position = Vector3(-GAP * 0.5 if tag == "A" else GAP * 0.5, 0.0, 0.0)
		p.body_mass = stats[0]
		p.jump_scale = stats[1]
		var brain := ScriptedBrain.new()
		p.set_brain(brain)
		p.mark_caught.connect(func(_tier: Tuning.Action, _legal: bool) -> void:
			if _caught_by == "":
				_caught_by = tag)
		players[tag] = p
		brains[tag] = brain
		peak[tag] = 0.0
	# Let them settle on the floor before the kick.
	for i in 20:
		await get_tree().physics_frame
	var ball := BallScene.instantiate() as Ball
	add_child(ball)
	var target := Vector3(float(spec[3]), float(spec[2]), -0.3)
	var from := Vector3(0.0, 1.0, -KICK_DISTANCE)
	var v := (target - from) / FLIGHT
	v.y += 0.5 * Tuning.GRAVITY * FLIGHT
	ball.global_position = from
	ball.launch(v.normalized(), v.length(), Vector3.ZERO, null, true)
	_caught_by = ""
	var hold: bool = spec[4]
	var press_frame := int(round((FLIGHT - Tuning.action_contact_time(Tuning.Action.MARK_AGGRESSIVE)) * 60.0))
	for frame in WAIT_FRAMES:
		for tag: String in brains:
			var brain: ScriptedBrain = brains[tag]
			brain.hold_safe = hold
			if not hold and frame == press_frame:
				brain.press_aggressive = true
			peak[tag] = maxf(peak[tag], (players[tag] as PlayerController).global_position.y)
		await get_tree().physics_frame
		if _caught_by != "" and frame > press_frame + 40:
			break
	var got := _caught_by if _caught_by != "" else "none"
	var expected: String = spec[1]
	if expected == "same":
		if _twin_result == "":
			_twin_result = got
		expected = _twin_result
	var passed := got == expected and got != "none"
	if not passed:
		_failures += 1
	print("%s  %s -> %s (expected %s)" % ["PASS" if passed else "FAIL", spec[0], got, expected])
	for tag: String in players:
		var read: Dictionary = (players[tag] as PlayerController).last_mark_contest
		if read.is_empty():
			print("      %s  no contest read, peak %.2f m" % [tag, peak[tag]])
		else:
			print("      %s  P %.3f (best %.3f of %d)  timing %.2f position %.2f height %.2f body %.2f  peak %.2f m" % [
				tag, read.rating, read.best, read.contestants, read.timing, read.position,
				read.height, read.body, peak[tag]])
	for tag: String in players:
		(players[tag] as PlayerController).queue_free()
	ball.queue_free()
	for i in 4:
		await get_tree().physics_frame
