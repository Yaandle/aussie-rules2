class_name AIBrain
extends PlayerBrain

## Full-game AI (design doc §7 priority 1): chase the loose ball, run a
## carry toward goal, dispose of it, press the opposing carrier, otherwise
## drift toward a kickoff slot. Still not a team-tactics / zone-coverage
## system, but no longer "no decision-making beyond the state machine":
## _best_disposal_target scores teammates (distance / how forward / how
## open / a cheap pass-lane check) so a carry that can't shoot looks for
## the right player to give it to instead of firing every disposal down its
## own run line, and _think_carrying bounces on the run so it keeps inside
## the 15 m rule (PlayerController.run_too_far_called). Team Edit dials —
## lateral_bias and press_intensity — still apply; both default to this
## file's original un-tuned numbers, so an AIBrain nobody configures
## behaves as before apart from the disposal/bounce additions.
##
## Aims the same way a human does: by facing a direction and firing the
## same kick/handball PlayerController already has. There is no separate
## "AI aims perfectly" path — a kick under pressure is exactly as good as
## the body it left, which is the project's whole physical-not-scripted
## stance (see RULES_REFERENCE.md §3). A targeted disposal is aimed by
## turning the body onto the receiver for a few physics frames before the
## release (_pass_to), the same lead-the-release trick request_handball_to
## already used.

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

## Drill-only dial: multiplies the gait a carrying brain runs for goal at
## in _think_carrying (1.0 is this file's original un-tuned behaviour).
## Added for the old chase-from-behind tackling drill — a straight foot
## race between two bodies with identical accel/top speed keeps whatever
## gap they started at constant forever, so the rival needed easing to a
## beatable pace. That drill is now a guided tutorial (TackleTutorial)
## driving the rival with TutorialDummyBrain instead, so nothing currently
## sets this — it stays at 1.0 and every carrying AIBrain runs exactly as
## it always has. Kept (rather than removed) as the ready hook if a paced-
## carrier drill comes back.
var carry_gait_scale := 1.0

var _move_dir := Vector3.ZERO
var _gait := 0.0
var _kick_pressed := false
var _handball_pressed := false
var _tackle_wanted := false
## Basic marking stub: AI only ever attempts the Safe tier, never Running
## or Aggressive — proving the contest resolves correctly is this pass's
## job, not giving AI good judgement about which tier to pick.
var _mark_safe_wanted := false

## Set by _think_carrying once carry_distance passes BOUNCE_INTERVAL *
## AI_BOUNCE_AT_FRACTION, so a carrying AI bounces before it can ever
## concede the 15 m free kick. Overrides wants_bounce() (base false).
## Reset every update().
var _bounce_pressed := false

## Whether this frame's decision was a live job — carrying, chasing a
## loose ball this player is closest to, or pressing the carrier — rather
## than idle drift. CommandBrain reads it: a queued "lead here" order
## overrides drift, but never a live contest. Reset every update().
var _decision_committed := false

## Simulates holding LT (stance) for _kick_hold_timer seconds, then
## tapping RT for exactly one frame — PlayerController now fires on that
## execute pulse, not on a hold->release edge, so this needs both signals
## rather than just one boolean. Kept as separate state from is_carrying()
## because the action's windup keeps is_carrying() true well past release.
var _kick_committed := false
var _kick_hold_timer := 0.0
var _kick_execute_pressed := false

## Where a committed kick is aimed (the goal for a shot, a teammate for a
## pass) and the gait to run while the charge holds — a pass to a nearby
## teammate must not sprint through them the way a shot at a distant goal
## runs on. Both read by _think_carrying's _kick_committed branch.
var _kick_aim_point := Vector3.ZERO
var _kick_hold_gait := 1.0

## Was the ball held last frame, so a held->loose edge can be caught and
## turned into a reaction delay (see AI_LOOSE_BALL_REACTION_MIN/MAX).
var _ball_was_held := true
var _reaction_timer := 0.0

## An aimed disposal winding up — the receiver, how many physics frames of
## the turn-then-release sequence are left (AI_AIM_TURN_FRAMES_*), and
## whether it releases as a kick or a handball. Set by _pass_to
## (_think_carrying's own target pick) or request_handball_to (an external
## call for the ball). Zero frames means nothing is winding up.
var _call_receiver: PlayerController = null
var _call_frames := 0
var _call_use_kick := false


func update(controller: PlayerController, delta: float) -> void:
	_handball_pressed = false
	_tackle_wanted = false
	_kick_execute_pressed = false
	_mark_safe_wanted = false
	_bounce_pressed = false
	_decision_committed = false

	if ball == null:
		_move_dir = Vector3.ZERO
		_gait = 0.0
		_kick_pressed = false
		return

	if not controller.is_carrying():
		_kick_committed = false
		_kick_pressed = false
		# A tackle (or any other lost-possession mid-windup) leaves an aimed
		# disposal half-done — clear it so the next carry doesn't inherit a
		# stale receiver and fire at them on the frame it gains the ball.
		_call_frames = 0
		_call_receiver = null
		_call_use_kick = false

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

	# Hold the line — don't chase or support the ball — in either of two
	# stoppage situations:
	#  1. The umpire has it (Ball.lock_at/lock_to). is_held is true but
	#     holder() is null since no *player* has it; without this guard that
	#     combination reads as a loose ball and the whole side sprints at
	#     the umpire's hands and stands on top of him.
	#  2. A ruck contest is live and this player is NOT one of the two
	#     nominated ruckmen. ball.is_held goes false the instant the
	#     throw-up is released (FullGame._release_ruck_contest), so without
	#     this every nearby AI would immediately crash the pack — only the
	#     two ruckmen should contest. PlayerController.ruck_contest_locked()
	#     already self-clears on a connected hit-out
	#     (FullGame._on_hit_out_resolved) or when RUCK_CONTEST_WINDOW
	#     lapses, so normal chasing resumes after the tap on its own.
	# Control-mode agnostic: this also keeps SINGLE_PLAYER's non-ruck AI
	# spread when the human is playing a non-ruck position.
	if (holder == null and ball.is_held) \
			or (not controller.is_ruck_contestant() and controller.ruck_contest_locked()):
		_move_toward(home_position, pos, 0.5)
		return

	if holder == null:
		if _reaction_timer > 0.0:
			_reaction_timer -= delta
			_move_toward(home_position, pos, 0.5)
		else:
			_think_loose_ball(controller, pos, team)
	elif holder.team == team:
		_think_support(controller, pos)
	else:
		_think_defend(controller, holder, pos)


## "Call for the ball" (Settings.PlayerControlMode.SINGLE_PLAYER — see
## FullGame._call_for_ball, which is the only caller and which has already
## decided the call succeeded by the time this is reached). Asks a carrying
## brain to handball to `receiver` instead of continuing its own carry.
##
## Deliberately routed through _think_carrying's existing _handball_pressed
## path rather than launching the ball directly: PlayerController._begin()
## captures a handball's aim from _wish_dir at the instant of the press, so
## pointing this brain's own movement intent at the receiver first IS the
## aiming mechanism. There is no second way to aim a handball, and building
## one would be a parallel disposal system with its own accuracy.
##
## The turn-then-release ordering is load-bearing: _wish_dir is written by
## PlayerController._update_locomotion, which runs *after* _update_charge
## reads wants_handball() within the same physics frame. A handball pressed
## on the same frame the aim changes would fire along the previous frame's
## _wish_dir — straight at goal, the direction _think_carrying was already
## running. The wind-up frames turn the intent first; the last one releases
## into it. Routed through the shared _pass_to so this and _think_carrying's
## own target pick can't drift on how an aimed disposal is aimed.
##
## Any kick this brain had committed to is abandoned: the two are mutually
## exclusive disposals and _update_charge would otherwise still be holding
## stance while the handball fires.
func request_handball_to(receiver: PlayerController) -> void:
	_pass_to(receiver, false)
	_kick_committed = false
	_kick_pressed = false


## True while an aimed disposal (a call for the ball, or the brain's own
## target pick) is still winding up — keeps "is one in flight" answerable
## without exposing the frame counter itself.
func has_pending_call() -> bool:
	return _call_frames > 0 and is_instance_valid(_call_receiver)


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


func wants_bounce() -> bool:
	return _bounce_pressed


# ── Decisions ────────────────────────────────────────────────────────

func _think_carrying(controller: PlayerController, delta: float, pos: Vector3) -> void:
	_decision_committed = true

	# 15 m rule (RULES_REFERENCE.md §1): bounce well before the umpire would
	# ping it (PlayerController.run_too_far_called fires at BOUNCE_INTERVAL).
	# Keep running the carry line — a bounce is taken on the move.
	if controller.carry_distance() >= Tuning.BOUNCE_INTERVAL * Tuning.AI_BOUNCE_AT_FRACTION:
		_bounce_pressed = true
		_move_toward(_goal_point(pos), pos, carry_gait_scale)
		return

	# An aimed disposal winding up — an accepted call for the ball
	# (request_handball_to) or this brain's own target pick (_pass_to). Turn
	# onto the receiver every frame of the wind-up; never fall through to
	# the goal-ward move below, or the disposal fires back toward goal on
	# the release frame (see _pass_to). A handball is a quick pivot (gait 0);
	# a kick jogs onto the line so the body keeps coming around.
	if _call_frames > 0:
		if not is_instance_valid(_call_receiver):
			_call_frames = 0
			_call_use_kick = false
		else:
			_call_frames -= 1
			_move_toward(_call_receiver.global_position, pos,
				0.35 if _call_use_kick else 0.0)
			if _call_frames <= 0:
				if _call_use_kick:
					_commit_kick(Tuning.AI_PASS_KICK_CHARGE,
						_call_receiver.global_position, 0.3)
				else:
					_handball_pressed = true
				_call_receiver = null
				_call_use_kick = false
		return

	if _kick_committed:
		_move_toward(_kick_aim_point, pos, _kick_hold_gait)
		if _kick_hold_timer > 0.0:
			_kick_pressed = true
			_kick_hold_timer -= delta
		else:
			# Stay "in stance" one last tick and pulse execute together, so
			# PlayerController sees wants_kick() and wants_kick_execute()
			# true on the same frame, as a human holding LT and tapping RT
			# would land it.
			_kick_pressed = true
			_kick_execute_pressed = true
			_kick_committed = false
		return

	var goal_point := _goal_point(pos)
	_move_toward(goal_point, pos, carry_gait_scale)

	# Straight-line distance to the goal LINE, not to the (possibly
	# lateral-biased) aim point — otherwise a strong boundary bias would
	# inflate this whenever the carrier isn't already over near that wing,
	# wrongly reading as "too far to shoot" for a player well within range
	# straight down the middle.
	var dist := absf(attack_direction * Tuning.FIELD_HALF_LENGTH - pos.x)
	var pressured := _nearest_opponent_distance(controller, pos) < Tuning.AI_PRESSURE_RADIUS

	# A runnable, unpressured shot still beats going looking for a pass.
	if dist <= Tuning.AI_KICK_RANGE and not pressured:
		_commit_kick(0.75, goal_point, carry_gait_scale)
		return

	# Otherwise look for the best teammate to give it to (see
	# _best_disposal_target). Handball inside AI_HANDBALL_MAX, kick past it.
	var mate := _best_disposal_target(controller, pos, pressured)
	if mate != null:
		_pass_to(mate, pos.distance_to(mate.global_position) > Tuning.AI_HANDBALL_MAX)
		return

	# Nothing worth aiming at — the original blind fallback, unchanged.
	if pressured:
		if dist <= Tuning.AI_KICK_RANGE * 1.4:
			_commit_kick(0.4, goal_point, carry_gait_scale)
		else:
			_handball_pressed = true


func _think_loose_ball(controller: PlayerController, pos: Vector3, team: Tuning.Team) -> void:
	# While the ball is still in flight, chase where it's actually going to
	# land rather than where it currently is — a kick can hang for well
	# over a second, and "run at the ball's current position" means
	# chasing a moving target across the ground the whole way instead of
	# meeting it. This is what P1 called converging on the drop zone, and
	# it's the difference between a receiver who's already standing under
	# a long kick when it arrives and one who's still three strides away.
	# Grounded (non-airborne) loose balls have no arc to anticipate, so
	# those still chase the live position.
	var chase_point := ball.predicted_landing_position() if ball.is_airborne() \
		else ball.global_position
	if _is_closest_teammate_to(controller, team, chase_point):
		_decision_committed = true
		# Audit point 5: still go, but don't sprint-commit into a race an
		# opponent has clearly already won — ease to a contain gait so we
		# arrive balanced for the spill instead of overrunning it.
		var lost_race := _nearest_opponent_distance_to(controller, chase_point) \
			< pos.distance_to(chase_point) - Tuning.AI_LOOSE_BALL_CEDE_MARGIN
		_move_toward(chase_point, pos, 0.7 if lost_race else 1.0)
		# Close enough to a ball still in the air that holding up for a
		# catch beats running through where it currently is — the same
		# reach test PlayerController._update_aerial_contest itself uses,
		# just gated a little earlier by range so the AI commits from a
		# sensible distance rather than at the very last instant.
		if ball.is_airborne() and pos.distance_to(ball.global_position) <= Tuning.MARK_CONTEST_RANGE:
			_mark_safe_wanted = true
	else:
		_move_toward(home_position + _spacing_push(controller, pos), pos, 0.5)


func _think_support(controller: PlayerController, pos: Vector3) -> void:
	var target := home_position.lerp(ball.global_position, Tuning.AI_SUPPORT_PULL)
	# Half-weighted, not a full lean onto _lateral_target_z(pos) — a
	# support run is already anchored between home_position and the ball;
	# fully overriding its own Z with the boundary lean would fight that
	# anchor rather than just colouring it toward the team's preference.
	target.z = lerpf(target.z, _lateral_target_z(pos), 0.5)
	# Audit point 4: spread off the nearest teammate so support runs don't
	# stack onto the same point.
	target += _spacing_push(controller, pos)
	_move_toward(target, pos, 0.6)


func _think_defend(controller: PlayerController, holder: PlayerController, pos: Vector3) -> void:
	if _is_closest_teammate_to(controller, controller.team, holder.global_position):
		_decision_committed = true
		_move_toward(holder.global_position, pos, minf(press_intensity, 1.0))
		# Audit point 5: commit the tackle only when in range AND actually
		# staying with the carrier. Lunging at someone pulling away faster
		# than we close is a near-certain miss that just takes us out of the
		# play — hold the chase instead.
		var in_range := pos.distance_to(holder.global_position) \
			<= Tuning.TACKLE_RADIUS * 1.2 * press_intensity
		var keeping_up := controller.speed() + Tuning.AI_TACKLE_CLOSING_MARGIN >= holder.speed()
		_tackle_wanted = in_range and keeping_up
	else:
		_move_toward(home_position + _spacing_push(controller, pos), pos, 0.5)


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


func _commit_kick(charge_fraction: float, aim_point: Vector3, hold_gait: float) -> void:
	_kick_committed = true
	_kick_aim_point = aim_point
	_kick_hold_gait = hold_gait
	_kick_hold_timer = Tuning.KICK_CHARGE_TIME * charge_fraction
	_kick_pressed = true


## The point a carry aims at: the goal line at this player's lateral-biased
## Z (see _lateral_target_z). Extracted because the 15 m-bounce early
## return and the main carry path both build it.
func _goal_point(pos: Vector3) -> Vector3:
	return Vector3(
		attack_direction * Tuning.FIELD_HALF_LENGTH, 0.0, _lateral_target_z(pos))


## Wind up an aimed disposal to `receiver`: point the body at them for a
## few physics frames (AI_AIM_TURN_FRAMES_*) before releasing, because
## PlayerController captures a handball's aim from _wish_dir at the press
## and an AI kick's from body facing at stance start — the turn has to lead
## the release. A kick gets the longer wind-up, since its aim locks the
## instant stance begins and can't be nudged afterward. Shared by
## request_handball_to (external call for the ball) and _think_carrying's
## own target pick.
func _pass_to(receiver: PlayerController, use_kick: bool) -> void:
	_call_receiver = receiver
	_call_frames = Tuning.AI_AIM_TURN_FRAMES_KICK if use_kick \
		else Tuning.AI_AIM_TURN_FRAMES_HANDBALL
	_call_use_kick = use_kick


## Audit point 1: when a shot at goal isn't on, pick the teammate to give
## it to. Scores every teammate on the three things the brief named —
##   forward:  dot(dir to them, dir to goal) — moves it on, not backwards
##   open:     nearest opponent to THEM — of two mates level, the free one
##   dist:     shorter is safer
## and rejects anyone too close to be a real option, too far to reach,
## behind (unless pressured leaves nothing else), or with an opponent
## standing in the pass line. Returns null when nothing clears
## AI_DISPOSAL_SCORE_FLOOR, and the caller keeps running / falls back to
## its old blind disposal.
func _best_disposal_target(controller: PlayerController, pos: Vector3,
		pressured: bool) -> PlayerController:
	var to_goal := Vector3(attack_direction, 0.0, 0.0)
	var best: PlayerController = null
	var best_score := Tuning.AI_DISPOSAL_SCORE_FLOOR
	for mate in PlayerRegistry.all():
		if mate == controller or mate.team != controller.team:
			continue
		var to_mate := mate.global_position - pos
		to_mate.y = 0.0
		var d := to_mate.length()
		if d < Tuning.AI_DISPOSAL_MIN or d > Tuning.AI_KICK_MAX:
			continue
		var forwardness := (to_mate / d).dot(to_goal)
		if forwardness < Tuning.AI_DISPOSAL_MIN_FORWARD and not pressured:
			continue
		if _lane_blocked(controller, pos, mate.global_position):
			continue
		var openness := clampf(
			_nearest_opponent_distance_to(controller, mate.global_position) \
			/ (Tuning.AI_PRESSURE_RADIUS * 2.0), 0.0, 1.0)
		var dist_term := clampf(1.0 - (d - Tuning.AI_DISPOSAL_MIN) \
			/ (Tuning.AI_KICK_MAX - Tuning.AI_DISPOSAL_MIN), 0.0, 1.0)
		var score := Tuning.AI_DISPOSAL_W_FORWARD * maxf(forwardness, 0.0) \
			+ Tuning.AI_DISPOSAL_W_OPEN * openness \
			+ Tuning.AI_DISPOSAL_W_DIST * dist_term
		if score > best_score:
			best_score = score
			best = mate
	return best


## Cheap "is an opponent standing in the pass lane" test for
## _best_disposal_target — perpendicular distance from each opponent to the
## from->to segment, counting only those whose projection lands between the
## endpoints. Not a physics ray; just enough to stop the AI drilling a
## disposal into someone.
func _lane_blocked(controller: PlayerController, from: Vector3, to: Vector3) -> bool:
	return SpatialQuery.lane_blocked(from, to, Tuning.AI_LANE_BLOCK_RADIUS, controller.team)


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
	return _nearest_opponent_distance_to(controller, pos)


## Distance from an arbitrary `point` (not necessarily the controller's own
## position) to the nearest opponent — used to score how open a prospective
## pass target is. _nearest_opponent_distance defers to this.
func _nearest_opponent_distance_to(controller: PlayerController, point: Vector3) -> float:
	return SpatialQuery.nearest_opponent_distance(controller, point)


## Nearest same-team player to `pos`, excluding the controller itself, or
## null if somehow alone. Feeds the off-ball spacing push.
func _nearest_teammate(controller: PlayerController, pos: Vector3) -> PlayerController:
	return SpatialQuery.nearest_teammate(controller, pos)


## Audit point 4: a light shove away from the nearest teammate when they're
## inside AI_SPACING_RADIUS, added onto an off-ball move target so support
## and drift runners spread rather than pile onto one point. Falls to zero
## at the radius edge — it nudges, it doesn't scatter.
func _spacing_push(controller: PlayerController, pos: Vector3) -> Vector3:
	var mate := _nearest_teammate(controller, pos)
	if mate == null:
		return Vector3.ZERO
	var away := pos - mate.global_position
	away.y = 0.0
	var d := away.length()
	if d < 0.01 or d >= Tuning.AI_SPACING_RADIUS:
		return Vector3.ZERO
	return (away / d) * (Tuning.AI_SPACING_RADIUS - d)


## True if `controller` is the closest player on `team` to `point` — used
## both to pick who chases a loose ball and who presses the carrier, so
## a whole team doesn't converge on the same spot at once.
func _is_closest_teammate_to(controller: PlayerController, team: Tuning.Team,
		point: Vector3) -> bool:
	return SpatialQuery.is_closest_on_team(controller, team, point)
