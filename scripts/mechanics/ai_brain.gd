class_name AIBrain
extends PlayerBrain

## Deliberately simple full-game AI (design doc §7 priority 1): chase the
## loose ball, run a carry toward goal and dispose of it, press the
## opposing carrier, otherwise drift toward a kickoff slot. Still not a
## real tactics system — no positional awareness, no passing lanes, no
## decision-making beyond the state machine below — but Team Edit
## (polish-pass brief) now gives it two real dials rather than none:
## lateral_bias (where a carry aims/where support runs — corridor vs
## boundary) and press_intensity (how hard a defender closes and commits
## to a tackle). Both default to this file's own original, un-tuned
## numbers, so an AIBrain nobody configures behaves exactly as before.
##
## Aims the same way a human does: by facing a direction and firing the
## same kick/handball PlayerController already has. There is no separate
## "AI aims perfectly" path — a kick under pressure is exactly as good as
## the body it left, which is the project's whole physical-not-scripted
## stance (see RULES_REFERENCE.md §3).

var ball: Ball
var home_position := Vector3.ZERO
var attack_direction := 1.0     ## +1 attacks +X (HOME's goal), -1 attacks -X

## Team Edit expansion: 0 keeps a carry's disposal aim and a support run's
## target dead through the corridor (world Z 0); 1 commits fully to
## whichever boundary the player already happens to be nearer to. See
## _lateral_target_z(), the one place this is actually consumed. Set by
## whoever spawns/hands back this brain (FullGame._configure_ai_brain)
## from Settings.home_lateral_bias() — left at 0.0 (this file's original
## dead-centre behaviour) for anyone that doesn't.
var lateral_bias := 0.0

## Team Edit expansion: multiplies both a defender's chase gait and the
## distance it commits to an actual tackle attempt from (_think_defend) —
## 1.0 is this file's original, un-tuned behaviour. Set from Settings.
## home_press_intensity() the same way lateral_bias is.
var press_intensity := 1.0

var _move_dir := Vector3.ZERO
var _gait := 0.0
var _kick_pressed := false
var _handball_pressed := false
var _tackle_wanted := false
## Basic marking stub: AI only ever attempts the Safe tier, never Running
## or Aggressive — proving the contest resolves correctly is this pass's
## job, not giving AI good judgement about which tier to pick.
var _mark_safe_wanted := false

## Simulates holding LT (stance) for _kick_hold_timer seconds, then
## tapping RT for exactly one frame — PlayerController now fires on that
## execute pulse, not on a hold->release edge, so this needs both signals
## rather than just one boolean. Kept as separate state from is_carrying()
## because the action's windup keeps is_carrying() true well past release.
var _kick_committed := false
var _kick_hold_timer := 0.0
var _kick_execute_pressed := false

## Was the ball held last frame, so a held->loose edge can be caught and
## turned into a reaction delay (see AI_LOOSE_BALL_REACTION_MIN/MAX).
var _ball_was_held := true
var _reaction_timer := 0.0


func update(controller: PlayerController, delta: float) -> void:
	_handball_pressed = false
	_tackle_wanted = false
	_kick_execute_pressed = false
	_mark_safe_wanted = false

	if ball == null:
		_move_dir = Vector3.ZERO
		_gait = 0.0
		_kick_pressed = false
		return

	if not controller.is_carrying():
		_kick_committed = false
		_kick_pressed = false

	var pos := controller.global_position
	var team := controller.team

	if controller.is_carrying():
		_ball_was_held = true
		_think_carrying(controller, delta, pos)
		return

	var holder := ball.holder() as PlayerController
	var is_held := holder != null
	if not is_held and _ball_was_held:
		_reaction_timer = randf_range(
			Tuning.AI_LOOSE_BALL_REACTION_MIN, Tuning.AI_LOOSE_BALL_REACTION_MAX)
	_ball_was_held = is_held

	if holder == null:
		if _reaction_timer > 0.0:
			_reaction_timer -= delta
			_move_toward(home_position, pos, 0.5)
		else:
			_think_loose_ball(controller, pos, team)
	elif holder.team == team:
		_think_support(pos)
	else:
		_think_defend(controller, holder, pos)


func wish_direction(_controller: PlayerController) -> Vector3:
	return _move_dir


func gait() -> float:
	return _gait


func wants_kick() -> bool:
	return _kick_pressed


func wants_kick_execute() -> bool:
	return _kick_execute_pressed


func wants_handball() -> bool:
	return _handball_pressed


func wants_tackle() -> bool:
	return _tackle_wanted


func wants_mark_safe() -> bool:
	return _mark_safe_wanted


# ── Decisions ────────────────────────────────────────────────────────

func _think_carrying(controller: PlayerController, delta: float, pos: Vector3) -> void:
	var goal_point := Vector3(
		attack_direction * Tuning.FIELD_HALF_LENGTH, 0.0, _lateral_target_z(pos))
	_move_toward(goal_point, pos, 1.0)

	if _kick_committed:
		if _kick_hold_timer > 0.0:
			_kick_pressed = true
			_kick_hold_timer -= delta
		else:
			# Same frame: stay "in stance" one last tick and pulse execute,
			# so PlayerController sees both wants_kick() and
			# wants_kick_execute() true together, exactly as a human
			# holding LT and tapping RT would land it.
			_kick_pressed = true
			_kick_execute_pressed = true
			_kick_committed = false
		return

	# Straight-line distance to the goal LINE, not to the (possibly
	# lateral-biased) aim point above — otherwise a strong boundary bias
	# would inflate this whenever the carrier isn't already over near that
	# wing, wrongly reading as "too far to shoot" for a player who is
	# actually well within range straight down the middle.
	var dist := absf(attack_direction * Tuning.FIELD_HALF_LENGTH - pos.x)
	var pressured := _nearest_opponent_distance(controller, pos) < Tuning.AI_PRESSURE_RADIUS

	if dist <= Tuning.AI_KICK_RANGE and not pressured:
		_commit_kick(0.75)
	elif pressured:
		if dist <= Tuning.AI_KICK_RANGE * 1.4:
			_commit_kick(0.4)
		else:
			_handball_pressed = true


func _think_loose_ball(controller: PlayerController, pos: Vector3, team: Tuning.Team) -> void:
	if _is_closest_teammate_to(controller, team, ball.global_position):
		_move_toward(ball.global_position, pos, 1.0)
		# Close enough to a ball still in the air that holding up for a
		# catch beats running through where it currently is — the same
		# reach test PlayerController._update_aerial_contest itself uses,
		# just gated a little earlier by range so the AI commits from a
		# sensible distance rather than at the very last instant.
		if ball.is_airborne() and pos.distance_to(ball.global_position) <= Tuning.MARK_CONTEST_RANGE:
			_mark_safe_wanted = true
	else:
		_move_toward(home_position, pos, 0.5)


func _think_support(pos: Vector3) -> void:
	var target := home_position.lerp(ball.global_position, Tuning.AI_SUPPORT_PULL)
	# Half-weighted, not a full lean onto _lateral_target_z(pos) — a
	# support run is already anchored between home_position and the ball;
	# fully overriding its own Z with the boundary lean would fight that
	# anchor rather than just colouring it toward the team's preference.
	target.z = lerpf(target.z, _lateral_target_z(pos), 0.5)
	_move_toward(target, pos, 0.6)


func _think_defend(controller: PlayerController, holder: PlayerController, pos: Vector3) -> void:
	if _is_closest_teammate_to(controller, controller.team, holder.global_position):
		_move_toward(holder.global_position, pos, minf(press_intensity, 1.0))
		_tackle_wanted = pos.distance_to(holder.global_position) \
			<= Tuning.TACKLE_RADIUS * 1.2 * press_intensity
	else:
		_move_toward(home_position, pos, 0.5)


## Team Edit expansion (Ball Movement preference — see Settings.
## BallMovementPreference): pulls a lateral world Z target toward whichever
## boundary `pos` is already nearer to, scaled by lateral_bias — 0 keeps it
## dead through the corridor, 1 commits fully to that wing. Shared by
## _think_carrying (where a carrier aims to dispose) and _think_support
## (where an off-ball teammate runs) so one number governs both halves of
## "how this team prefers to move the ball" instead of two independently-
## tuned ones.
func _lateral_target_z(pos: Vector3) -> float:
	var side := signf(pos.z) if absf(pos.z) > 0.01 else 1.0
	var boundary_z := side * Tuning.FIELD_HALF_WIDTH * Tuning.AI_BOUNDARY_LEAN_FRACTION
	return lerpf(0.0, boundary_z, lateral_bias)


func _commit_kick(charge_fraction: float) -> void:
	_kick_committed = true
	_kick_hold_timer = Tuning.KICK_CHARGE_TIME * charge_fraction
	_kick_pressed = true


# ── Spatial helpers ──────────────────────────────────────────────────

func _move_toward(target: Vector3, pos: Vector3, gait_value: float) -> void:
	var to_target := target - pos
	to_target.y = 0.0
	if to_target.length_squared() > 0.04:   # ~0.2m dead zone so it stops rather than jitters
		_move_dir = to_target.normalized()
		_gait = gait_value
	else:
		_move_dir = Vector3.ZERO
		_gait = 0.0


func _nearest_opponent_distance(controller: PlayerController, pos: Vector3) -> float:
	var best := INF
	for node in controller.get_tree().get_nodes_in_group(&"players"):
		var other := node as PlayerController
		if other == null or other == controller or other.team == controller.team:
			continue
		best = minf(best, pos.distance_to(other.global_position))
	return best


## True if `controller` is the closest player on `team` to `point` — used
## both to pick who chases a loose ball and who presses the carrier, so
## a whole team doesn't converge on the same spot at once.
func _is_closest_teammate_to(controller: PlayerController, team: Tuning.Team,
		point: Vector3) -> bool:
	var mine := controller.global_position.distance_to(point)
	for node in controller.get_tree().get_nodes_in_group(&"players"):
		var other := node as PlayerController
		if other == null or other == controller or other.team != team:
			continue
		if other.global_position.distance_to(point) < mine:
			return false
	return true
