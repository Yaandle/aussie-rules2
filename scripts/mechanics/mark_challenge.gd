class_name MarkChallenge
extends Node3D

## The marking coach's mini-game (design brief priority 2): unlike
## KickChallenge, the coach is the one disposing the ball here — each
## delivery is a real KICK-flight launch() aimed to land near the player
## with a generous arc, and the player's own PlayerController.mark_caught/
## mark_missed signals (fired by the marking system in player_controller.gd)
## report whether it was taken. No target zone needed: success is "did the
## player catch it", not "did the ball reach a spot".
##
## Deliveries are timed on their own pacing (unlike KickChallenge, which is
## purely reactive to player-initiated kicks) since the coach — not the
## player — decides when the next ball goes up.

const RANGE_SIM_STEP := 0.02      ## s per integration step in _predicted_range
const RANGE_SIM_MAX_STEPS := 400  ## safety cap so a freak guess can't loop forever

signal challenge_started(attempts_total: int)
signal mark_hit(hits: int, attempts_used: int, legal_mark: bool)
signal mark_dropped(attempts_used: int)
signal challenge_ended(hits: int, attempts_total: int)
signal hint_changed(text: String)

var _ball: Ball
var _player: PlayerController
var _coach_position := Vector3.ZERO

var _attempts_used := 0
var _hits := 0
var _active := false

## True from the moment a delivery leaves the coach until it resolves
## (caught, dropped, or force-ended) — mirrors KickChallenge's _armed, same
## purpose: stops one delivery being counted twice or a stray settle from
## an earlier one being counted again.
var _armed := false

var _timer := 0.0
var _pending_callback := Callable()


func begin(ball: Ball, player: PlayerController, coach_position: Vector3) -> void:
	_ball = ball
	_player = player
	_coach_position = coach_position
	_attempts_used = 0
	_hits = 0
	_active = true
	_armed = false
	_connect_player()
	challenge_started.emit(Tuning.MARK_CHALLENGE_ATTEMPTS)
	hint_changed.emit("Marking practice — hold G for a safe mark, tap Q on the run, tap H to go up for it. Watch the ring above your head and time your press to when it closes.")
	_schedule(Tuning.MARK_CHALLENGE_DELIVERY_DELAY, _deliver)


## Called by kick_to_kick.gd whenever it has to reposition the ball out
## from under an in-flight delivery (out of bounds, manual debug reset)
## instead of letting it settle on its own. Not strictly required for
## correctness — the next _physics_process tick would catch a reset ball
## via is_settled() anyway — but ends the attempt on the same frame as the
## reset rather than one tick later.
func force_miss() -> void:
	if not _active or not _armed:
		return
	_resolve(false, false)


func _physics_process(delta: float) -> void:
	if not _active:
		return
	if _timer > 0.0:
		_timer = maxf(0.0, _timer - delta)
		if _timer <= 0.0 and _pending_callback.is_valid():
			var callback := _pending_callback
			_pending_callback = Callable()
			callback.call()
		return

	# Fallback drop detection, same shape as KickChallenge's miss check: if
	# the ball we launched has come down without mark_caught/mark_missed
	# ever firing (it sailed past, bounced, whatever), the attempt is over.
	if _armed and is_instance_valid(_ball) and _ball.is_settled():
		_resolve(false, false)


func _deliver() -> void:
	if not is_instance_valid(_player) or not is_instance_valid(_ball):
		return

	var target := _player.global_position + Vector3(
		randf_range(-Tuning.MARK_CHALLENGE_TARGET_SPREAD, Tuning.MARK_CHALLENGE_TARGET_SPREAD),
		0.0,
		randf_range(-Tuning.MARK_CHALLENGE_TARGET_SPREAD, Tuning.MARK_CHALLENGE_TARGET_SPREAD))

	var to_target := target - _coach_position
	to_target.y = 0.0
	var direction := to_target.normalized() if to_target.length_squared() > 0.01 else Vector3.FORWARD
	var distance := clampf(to_target.length(),
		Tuning.MARK_CHALLENGE_MIN_DISTANCE, Tuning.MARK_CHALLENGE_MAX_DISTANCE)

	var elevation := deg_to_rad(Tuning.MARK_CHALLENGE_ELEVATION_DEG)
	var speed := _launch_speed_for(distance, elevation)
	var launch_dir := (direction * cos(elevation) + Vector3.UP * sin(elevation)).normalized()

	var origin := _coach_position + Vector3.UP * 1.4 + direction * 0.6
	var up_reference := Vector3.UP if absf(launch_dir.y) < 0.98 else Vector3.FORWARD
	_ball.global_transform = Transform3D(Basis.looking_at(-launch_dir, up_reference), origin)
	# `is_kick_disposal = true`: a coach's feed counts the same as a real
	# kick for mark eligibility (Ball.is_mark_eligible), same as anyone
	# else's boot — see PlayerController._dispose()'s own KICK branch.
	_ball.launch(launch_dir, speed, Vector3.ZERO, null, true)

	_armed = true
	hint_changed.emit("Ball's coming — attempt %d/%d" % [
		_attempts_used + 1, Tuning.MARK_CHALLENGE_ATTEMPTS])


func _on_mark_caught(tier: Tuning.Action, legal_mark: bool) -> void:
	if not _active or not _armed:
		return
	_resolve(true, legal_mark, tier)


func _on_mark_missed(_tier: Tuning.Action) -> void:
	if not _active or not _armed:
		return
	_resolve(false, false)


func _resolve(caught: bool, legal_mark: bool, tier: Tuning.Action = Tuning.Action.NONE) -> void:
	_armed = false
	_attempts_used += 1
	if caught:
		_hits += 1
		mark_hit.emit(_hits, _attempts_used, legal_mark)
		var tier_name := "Safe" if tier == Tuning.Action.MARK_SAFE \
			else ("Running" if tier == Tuning.Action.MARK_RUNNING else "Aggressive")
		var quality := "mark!" if legal_mark else "take — a bit short of 15m for a mark, but good hands"
		hint_changed.emit("%s %s   %d/%d" % [
			tier_name, quality, _hits, Tuning.MARK_CHALLENGE_ATTEMPTS])
	else:
		mark_dropped.emit(_attempts_used)
		hint_changed.emit("Dropped — %d left." % (Tuning.MARK_CHALLENGE_ATTEMPTS - _attempts_used))

	if _attempts_used >= Tuning.MARK_CHALLENGE_ATTEMPTS:
		_active = false
		_disconnect_player()
		challenge_ended.emit(_hits, Tuning.MARK_CHALLENGE_ATTEMPTS)
	else:
		_schedule(Tuning.MARK_CHALLENGE_NEXT_DELAY, _deliver)


func _connect_player() -> void:
	if not is_instance_valid(_player):
		return
	if not _player.mark_caught.is_connected(_on_mark_caught):
		_player.mark_caught.connect(_on_mark_caught)
	if not _player.mark_missed.is_connected(_on_mark_missed):
		_player.mark_missed.connect(_on_mark_missed)


func _disconnect_player() -> void:
	if not is_instance_valid(_player):
		return
	if _player.mark_caught.is_connected(_on_mark_caught):
		_player.mark_caught.disconnect(_on_mark_caught)
	if _player.mark_missed.is_connected(_on_mark_missed):
		_player.mark_missed.disconnect(_on_mark_missed)


func _schedule(delay: float, callback: Callable) -> void:
	_timer = delay
	_pending_callback = callback


## Inverse-ballistics helper: KickTrajectory forward-simulates a known
## launch to preview where it lands; this needs the opposite (a target
## distance -> a launch speed), so it starts from the no-drag closed form
## R = v^2 sin(2*theta) / g and applies one simulated correction pass,
## rather than a full iterative solver — plenty accurate for a training
## delivery that only needs to arrive somewhere the player can read and
## react to, not land on an exact mark.
func _launch_speed_for(distance: float, elevation_rad: float) -> float:
	var g := Tuning.GRAVITY
	var guess := sqrt(maxf(distance, 1.0) * g / sin(2.0 * elevation_rad))
	var actual := _predicted_range(guess, elevation_rad)
	if actual > 0.5:
		guess *= distance / actual
	return guess


## Same gravity + quadratic-drag stepping Ball._integrate_forces uses,
## collapsed to a 2D (horizontal distance, height) plane since only the
## landing range is needed here, not the full 3D arc.
func _predicted_range(speed: float, elevation_rad: float) -> float:
	var vx := speed * cos(elevation_rad)
	var vy := speed * sin(elevation_rad)
	var x := 0.0
	var y := 0.0
	for i in RANGE_SIM_MAX_STEPS:
		var v := Vector2(vx, vy)
		var spd := v.length()
		if spd > 0.05:
			vx += (-vx * spd * Tuning.BALL_DRAG_COEFF / Tuning.BALL_MASS) * RANGE_SIM_STEP
			vy += (-vy * spd * Tuning.BALL_DRAG_COEFF / Tuning.BALL_MASS) * RANGE_SIM_STEP
		vy -= Tuning.GRAVITY * RANGE_SIM_STEP
		x += vx * RANGE_SIM_STEP
		y += vy * RANGE_SIM_STEP
		if y <= 0.0 and i > 2:
			return x
	return x
