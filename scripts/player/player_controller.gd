class_name PlayerController
extends CharacterBody3D

## Velocity-based movement with real momentum (design doc §5).
##
## Prototype 1 moved a player by adding `speed * dt` to a position every
## frame — instant starts, instant stops, instant reversals. Everything
## here exists to take that away:
##
##   - speed changes through an acceleration, and braking is faster than
##     accelerating, so a body has to be got going and got stopped
##   - the turn rate falls off as speed rises, so a sprint commits you to
##     an arc while a standstill lets you pivot
##   - running against your own momentum drives target speed toward zero,
##     which brakes you, which raises your turn rate, which swings you
##     round and lets you go again
##
## That last one is the whole plant-and-pivot move, and it is not a
## special case anywhere in this file — it falls out of the first two
## rules being coupled. Which is the point: weight should be a property
## of the simulation, not an animation played on top of a teleport.
##
## The rig's facing turns faster than the velocity heading does, so the
## body leads and the velocity lags. That lag is the strafe axis the
## blend space reads (see player_animation.gd) — the animation system is
## being driven by the physical state, not running alongside it.

signal action_started(action: Tuning.Action)
signal ball_gathered(ball: Ball)
signal ball_disposed(action: Tuning.Action)
signal mark_caught(tier: Tuning.Action, legal_mark: bool)
signal mark_missed(tier: Tuning.Action)

## Fired from _get_tackled only when the tackled player had already had
## Tuning.PRIOR_OPPORTUNITY_GRACE seconds of personal possession — a real
## holding-the-ball ruling (RULES_REFERENCE.md §4), as opposed to the
## neutral case (tackled inside the grace window), which stays silent since
## nothing about it differs from a plain tackle today. Nothing consumes
## this yet: awarding the actual free kick needs a set-shot/free-kick
## apparatus this project doesn't have — the ruling is decided correctly,
## the consequence is the next piece.
signal holding_the_ball_called(tackler: PlayerController)

## Fired from _get_tackled only in the *neutral* case — tackled inside
## Tuning.PRIOR_OPPORTUNITY_GRACE, the mirror image of
## holding_the_ball_called above (RULES_REFERENCE.md §4: "tackled inside
## the grace window is neutral, a ball-up"). Whoever owns match flow
## resolves the actual ball-up through the shared ruck contest — see
## FullGame._begin_ruck_contest.
signal field_ball_up_called(tackler: PlayerController, tackled: PlayerController)

## Fired when a ruck contest's Hit-Out resolves — see _resolve_hit_out.
## `connected` is false on a clean miss (nothing about the ball changes).
signal hit_out_resolved(player: PlayerController, connected: bool)

## Fired on the bumper when a Bump connects (design brief priority 7).
## `clean` reflects timing (Tuning.BUMP_APPROACH_DOT_MIN), not legality —
## whether contact was *dangerous* enough to warrant a free kick is a real
## AFL rule this project has no numbers for yet (RULES_REFERENCE.md has no
## distance/angle/force/timing threshold for "high contact"), so nothing
## here judges that. This signal exists so a future pass that *does* have
## real numbers has an event to hook rather than needing to re-derive one.
signal bump_landed(bumper: PlayerController, carrier: PlayerController, clean: bool)

@export var team: Tuning.Team = Tuning.Team.HOME

## Uniform multiplier over WALK/JOG/SPRINT_SPEED — 1.0 leaves Full Game
## and the sandbox exactly as tuned. The character screen's SPEED stat
## (CharacterProfile.speed_scale()) is the only thing that sets this to
## anything else, on whichever player it hands off to.
var speed_scale := 1.0

## Multiplier on KICK_MIN/MAX_SPEED — see _kick_parameters(). 1.0 leaves
## Full Game/the sandbox exactly as tuned, same as speed_scale above.
var kick_power_scale := 1.0

## 0..1, where 1.0 is pinpoint and 0.0 is KICK_ACCURACY_MAX_SPREAD_DEG of
## random aim error — see _dispose()'s KICK branch, the only place this
## is actually rolled.
var kick_accuracy := 1.0

## Set by whatever owns the view — movement is camera-relative, as every
## third-person game's is. Left null the player still works, just in
## world axes, which keeps this node testable headless.
var camera: Node3D = null

@onready var _animation: PlayerAnimation = $PlayerAnimation
@onready var _carry_point: Marker3D = $CarryPoint
@onready var _boot_point: Marker3D = $BootPoint
@onready var _gather_zone: Area3D = $GatherZone
@onready var _kick_trajectory: KickTrajectory = $KickTrajectory

## Defaults to a HumanBrain so a bare instance (the milestone-1 sandbox,
## scenes/main.tscn) behaves exactly as it always did. Full Game assigns
## AIBrain to everyone but the one human-controlled player.
var _brain: PlayerBrain = HumanBrain.new()

## Seconds left unable to move or act after being tackled. Zero the rest
## of the time.
var _stun_timer := 0.0

## Seconds left immune to _try_tackle() after taking a legal mark — the
## stand-the-mark protection window (Tuning.MARK_HOLD_DURATION). Cleared
## early the instant this player disposes of the ball; also doubles as the
## protection mechanism a future kick-in's goal square will use.
var _protected_timer := 0.0

## Seconds left frozen in place — the *other* half of stand-the-mark
## (RULES_REFERENCE.md's MARK_STAND_MIN_DISTANCE entry): a legal mark
## doesn't just protect the taker from being tackled, it obliges the
## nearest opponent to stand where they are until the mark-taker plays on.
## Purely a movement freeze (see _update_locomotion) — unlike _stun_timer,
## a frozen player can still act, they just can't reposition. Set on the
## OPPONENT by _apply_stand_the_mark(), not on the mark-taker themselves.
var _frozen_timer := 0.0

## Every opponent this player is currently obliging to hold position, for
## whatever reason — the one direct opponent standing the mark exactly
## (_apply_stand_the_mark) plus anyone else caught inside the 10m retreat
## radius (grant_protection's own _apply_retreat_freeze) — kept so a
## disposal can release all of them early (real AFL: everyone's free to
## move the instant the kick is taken or the mark-taker plays on, not just
## once the full 5s window lapses). Cleared alongside _protected_timer in
## _dispose()/drop_ball().
var _frozen_opponents: Array[PlayerController] = []

## True for exactly one physics frame: set by _begin_aggressive_mark(),
## consumed by the gravity block in _physics_process so the jump impulse
## lands after the floor-snap/gravity assignment rather than being
## immediately overwritten by it.
var _pending_jump := false

## Held-stance flag for a Safe Mark, exactly parallel to _charging for a
## kick — true only while the ball is airborne, in reach range hasn't
## resolved yet, and the brain still wants it. Read by _update_locomotion
## for MARK_SAFE_SPEED_SCALE, same mechanism KICK_STANCE_SPEED_SCALE uses.
var _mark_readying := false

## Seconds left before another Punch/Spoil attempt can connect — a tap
## action with no windup, so this is the only thing stopping it being held
## down for a continuous battering (see _try_spoil).
var _spoil_cooldown := 0.0

## True while nominated into a live ruck contest (centre bounce / field
## ball-up / boundary throw-in — see FullGame._begin_ruck_contest and
## set_ruck_contestant below) — the only context RB reads as a Hit-Out.
## Self-expires via _ruck_contest_timer so it can never linger past the
## one contest it was armed for.
var _is_ruck_contestant := false
var _ruck_contest_timer := 0.0

## Seconds left before another Bump attempt can commit — a real hit-stick
## commitment, not spammable (see _try_bump).
var _bump_cooldown := 0.0

## Tackle lunge (see _update_tackle_lunge): while _lunge_timer is positive,
## _update_locomotion overrides normal input-driven movement with a
## committed dash toward _lunge_direction, same "external velocity owns the
## body for a window" shape _knockback already uses below.
var _lunge_timer := 0.0
var _lunge_cooldown := 0.0
var _lunge_direction := Vector3.FORWARD
var _tackle_was_pressed := false

## Residual horizontal knockback velocity from being bumped, decaying via
## BRAKING each frame — see _update_locomotion's early branch and
## receive_bump(). While nonzero this overrides normal input-driven
## movement entirely: the hit is what's moving the body, not the stick.
var _knockback := Vector3.ZERO

## Seconds this player personally has held the ball since their own last
## gather/mark. Distinct from MatchState.possession_seconds(), which
## tracks the whole TEAM's unbroken hold and does not reset on a same-team
## handball — holding-the-ball's "prior opportunity" (RULES_REFERENCE.md
## §4) is about this individual player's own chance to dispose, so
## _get_tackled reads this instead.
var _possession_held_seconds := 0.0

## Unit XZ direction the body is actually travelling. Kept as state
## rather than re-derived from velocity every frame so it survives a
## complete stop — you keep facing where you were going.
var _heading := Vector3.FORWARD
var _wish_dir := Vector3.ZERO
var _speed := 0.0
var _facing_yaw := 0.0

## True while reading the play backward — see the Backpedal section of
## Tuning. Feet answer the stick directly (heading = wish_dir, no turn-rate
## sweep); facing is deliberately left alone by _update_facing while this
## is true, which is the whole mechanic: eyes stay on the play, only the
## feet move.
var _backpedaling := false

## Seconds left of the acceleration spike that fires the instant a
## backpedal resolves into a real direction (Tuning.TURN_BURST_*) — see
## _update_locomotion.
var _turn_burst_timer := 0.0

var _carried_ball: Ball = null
var _gather_cooldown := 0.0
var _carry_distance := 0.0

var _action: Tuning.Action = Tuning.Action.NONE
var _action_elapsed := 0.0
var _action_fired := false
var _kick_charge := 0.0
var _charging := false

## World-space yaw the kick is currently aimed along, decoupled from body
## facing (design brief's CONTROLS section: "aim is fully decoupled from
## movement/facing"). Snapped to _facing_yaw when stance begins, then
## nudged by the right stick/mouse for a human for as long as stance
## holds — see _update_kick_aim(). Frozen the instant the swing begins,
## same as _kick_charge, so waggling the stick after committing can't
## retroactively change where an already-struck kick goes.
var _kick_aim_yaw := 0.0

## Where a HANDBALL launches, captured once in _begin() at the moment the
## button is pressed — not read fresh in _dispose(), which fires later at
## the animation's contact time and would otherwise pick up wherever the
## stick had drifted to by then.
var _handball_aim_dir := Vector3.FORWARD

## True for exactly the one KICK currently in flight through _action, set
## when it was fired as a hip-fire (RT with no prior LT) rather than an
## aimed one — _dispose() reads this once to decide whether the extra
## hip-fire scatter applies, then clears it.
var _hip_fire_kick := false


func _ready() -> void:
	add_to_group(&"players")

	_facing_yaw = rotation.y
	_heading = -global_transform.basis.z
	_heading.y = 0.0
	_heading = _heading.normalized()

	# Own the gather shape rather than editing the one in the .tscn, so
	# GATHER_RADIUS stays single-sourced in Tuning and instances of this
	# scene do not share a mutated resource. Sized to the largest reach a
	# sprinting player could ever get (GATHER_LUNGE_MAX) rather than the
	# base radius — the physics shape only has to generate candidates, the
	# real speed-scaled cutoff is an explicit distance test in
	# _try_gather(), same pattern _update_ground_pickup already uses. That
	# avoids resizing a live Area3D shape and querying its (one-physics-
	# -step-stale) overlap list in the same frame.
	var reach := SphereShape3D.new()
	reach.radius = Tuning.GATHER_RADIUS + Tuning.GATHER_LUNGE_MAX
	($GatherZone/CollisionShape3D as CollisionShape3D).shape = reach


func set_brain(brain: PlayerBrain) -> void:
	_brain = brain


func brain() -> PlayerBrain:
	return _brain


## Every cooldown/timer field on this controller follows this same
## "subtract delta, clamp at zero" shape — shared here so they can't drift
## out of sync with each other (see _update_tackle_lunge, the one timer
## that used to decrement without the clamp).
func _tick_down(value: float, delta: float) -> float:
	return maxf(0.0, value - delta)


func _physics_process(delta: float) -> void:
	_brain.update(self, delta)

	_gather_cooldown = _tick_down(_gather_cooldown, delta)
	_stun_timer = _tick_down(_stun_timer, delta)
	_protected_timer = _tick_down(_protected_timer, delta)
	_frozen_timer = _tick_down(_frozen_timer, delta)
	_spoil_cooldown = _tick_down(_spoil_cooldown, delta)
	_bump_cooldown = _tick_down(_bump_cooldown, delta)
	_lunge_cooldown = _tick_down(_lunge_cooldown, delta)
	_possession_held_seconds = _possession_held_seconds + delta if is_carrying() else 0.0
	if _is_ruck_contestant:
		_ruck_contest_timer = maxf(0.0, _ruck_contest_timer - delta)
		if _ruck_contest_timer <= 0.0:
			_is_ruck_contestant = false

	_update_charge(delta)
	_update_marking(delta)
	_update_ruck_contest(delta)
	_update_bump(delta)
	_update_tackle_lunge(delta)
	_update_action(delta)

	if is_on_floor():
		velocity.y = -0.5   # a little bite into the floor keeps is_on_floor stable
	else:
		velocity.y -= Tuning.GRAVITY * delta
	if _pending_jump:
		# Applied after the floor-snap above, not before — is_on_floor() is
		# still true for one more frame at the instant a jump is triggered
		# (the physics server hasn't seen us leave the ground yet), so
		# setting this any earlier would just get overwritten by the -0.5
		# floor bite on the very frame that matters.
		velocity.y = Tuning.MARK_AGGRESSIVE_JUMP_SPEED
		_pending_jump = false

	_update_locomotion(delta)

	var before := global_position
	move_and_slide()
	_push_rigid_bodies()
	_contain_to_field()

	_update_facing(delta)
	_track_carry_distance(before)
	_try_gather()
	_try_tackle()
	_try_smother()

	_animation.drive(locomotion_blend(), delta)


# ── Locomotion ───────────────────────────────────────────────────────

func _update_locomotion(delta: float) -> void:
	# A bump's knockback overrides normal input-driven movement entirely
	# while it's still decaying — the hit is what's moving this body right
	# now, not the stick (see receive_bump()). Applied here, before
	# anything reads velocity for _speed/_heading, so the knocked-back
	# motion is what the rest of this frame (animation blend included)
	# actually sees.
	if _knockback.length_squared() > 0.0001:
		velocity.x = _knockback.x
		velocity.z = _knockback.z
		_knockback = _knockback.move_toward(Vector3.ZERO, Tuning.BRAKING * delta)
		var horizontal_kb := Vector3(velocity.x, 0.0, velocity.z)
		_speed = horizontal_kb.length()
		if _speed > Tuning.PIVOT_SPEED_THRESHOLD:
			_heading = horizontal_kb / _speed
		return

	# Tackle lunge owns the body the same way knockback does above, just
	# driving forward at a fixed speed instead of decaying — a committed
	# dash, not a bounce being absorbed. See _update_tackle_lunge.
	if _lunge_timer > 0.0:
		_heading = _lunge_direction
		_speed = Tuning.TACKLE_LUNGE_SPEED
		velocity.x = _heading.x * _speed
		velocity.z = _heading.z * _speed
		return

	# Stand-the-mark: this player has been obliged to hold their ground by
	# an opponent's legal mark (see _apply_stand_the_mark). Input is simply
	# ignored for movement purposes — facing/actions are untouched, only
	# repositioning is blocked, same as the real rule.
	if _frozen_timer > 0.0:
		_speed = 0.0
		velocity.x = 0.0
		velocity.z = 0.0
		return

	var wish := _brain.wish_direction(self)
	var gait := 0.0 if _stun_timer > 0.0 else _brain.gait()

	# move_and_slide()'s own collision response can leave `velocity` with a
	# sub-millimetre horizontal residue even for a player standing dead
	# still on flat ground (the floor-snap "bite" below re-triggers a
	# resting contact every physics frame, and each contact's slide
	# resolution can nudge velocity by a hair). That residue is otherwise
	# read straight into _speed/_heading, which locomotion_blend() then
	# reports to the AnimationTree as genuine motion — a standing player
	# would visibly twitch toward whatever clip that phantom direction
	# blends in. Snapping it to exact zero below the threshold nothing
	# gameplay-relevant ever needs kills the feedback loop at its source,
	# for every player this runs on, not just one screen's preview.
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	if horizontal.length_squared() < Tuning.LOCOMOTION_VELOCITY_DEADZONE ** 2:
		horizontal = Vector3.ZERO
		velocity.x = 0.0
		velocity.z = 0.0
	_speed = horizontal.length()
	if _speed > Tuning.PIVOT_SPEED_THRESHOLD:
		_heading = horizontal / _speed

	_turn_burst_timer = maxf(0.0, _turn_burst_timer - delta)

	var target_speed := 0.0
	if wish.length_squared() > 0.000001:
		_wish_dir = wish.normalized()

		# Backpedal gate: how far behind where the body is currently
		# *facing* (not travelling) the new input is. Hysteresis between
		# ENTER/EXIT so a diagonal push near the threshold doesn't flicker
		# in and out every frame.
		var facing_alignment := _yaw_direction(_facing_yaw).dot(_wish_dir)
		if facing_alignment <= Tuning.BACKPEDAL_ENTER_DOT \
				and _speed <= Tuning.JOG_SPEED + Tuning.BACKPEDAL_ENTRY_SPEED_MARGIN:
			_backpedaling = true
		elif facing_alignment >= Tuning.BACKPEDAL_EXIT_DOT:
			if _backpedaling:
				# _heading was tracking the *old* (backward) wish_dir every
				# frame of the backpedal, not this frame's new one — left
				# stale it would read as a full reversal against the new
				# wish_dir below (alignment -1, REVERSE_SPEED_SCALE braking,
				# exactly the plant-and-pivot's brake instead of a drive-off).
				# Snap it to the new direction now: facing is already there
				# (that is what just triggered the exit), so there is
				# nothing left to turn through, only to drive off from —
				# that drive-off is the burst.
				_heading = _wish_dir
				_turn_burst_timer = Tuning.TURN_BURST_DURATION
			_backpedaling = false
		# Else: inside the hysteresis band — hold whatever state we're already in.

		if _backpedaling:
			# A defensive shuffle, not a sprint commitment: feet answer the
			# stick directly every frame, capped at BACKPEDAL_SPEED
			# regardless of gait input — you cannot backpedal at a sprint
			# with any control. _update_facing() leaves facing alone while
			# this is true.
			_heading = _wish_dir
			# _stun_timer forces gait to 0 above for every other path via
			# Tuning.speed_for_gait(0) == 0; BACKPEDAL_SPEED is a flat
			# constant that never reads gait, so it needs the same guard
			# explicitly or a stunned player could still shuffle backward.
			target_speed = Tuning.BACKPEDAL_SPEED * speed_scale if _stun_timer <= 0.0 else 0.0
		else:
			# From a near standstill there is no momentum to fight, so the
			# heading just snaps to intent. Without this a player stopped
			# facing north who presses south would compute a target speed
			# of zero forever and never get moving.
			if _speed <= Tuning.PIVOT_SPEED_THRESHOLD:
				_heading = _wish_dir

			# How much of your requested speed you get, given how far off
			# your current momentum it is. Dead ahead is full, square
			# across is half, straight back is REVERSE_SPEED_SCALE — this
			# is the plant-and-pivot case, a full-speed reversal, distinct
			# from the backpedal shuffle above.
			var alignment := _heading.dot(_wish_dir)
			target_speed = Tuning.speed_for_gait(gait) * speed_scale \
				* remap(alignment, -1.0, 1.0, Tuning.REVERSE_SPEED_SCALE, 1.0)

			var speed_ratio := clampf(_speed / Tuning.SPRINT_SPEED, 0.0, 1.0)
			var turn_rate := deg_to_rad(
				lerpf(Tuning.TURN_RATE_STANDING, Tuning.TURN_RATE_SPRINT, speed_ratio))
			var to_turn := _heading.signed_angle_to(_wish_dir, Vector3.UP)
			var step := clampf(to_turn, -turn_rate * delta, turn_rate * delta)
			_heading = _heading.rotated(Vector3.UP, step).normalized()
	else:
		_wish_dir = Vector3.ZERO
		_backpedaling = false

	# Planting to kick or handball costs you your legs for a moment; the
	# kick stance ahead of that (LT held, still aiming/repositioning) costs
	# less, same relationship as ADS-walk vs. firing in a shooter. Each mark
	# tier costs its own amount — see Tuning.action_speed_scale — and
	# readying a Safe Mark (held, not yet resolved) costs the same as the
	# mark itself will, so there's no free lunch in holding it early.
	if _action != Tuning.Action.NONE:
		target_speed *= Tuning.action_speed_scale(_action)
	elif _charging:
		target_speed *= Tuning.KICK_STANCE_SPEED_SCALE
	elif _mark_readying:
		target_speed *= Tuning.MARK_SAFE_SPEED_SCALE

	var accel: float
	if _backpedaling:
		accel = Tuning.BACKPEDAL_ACCELERATION
	elif not is_on_floor():
		accel = Tuning.AIR_ACCELERATION
	else:
		accel = Tuning.ACCELERATION if target_speed > _speed else Tuning.BRAKING
	if _turn_burst_timer > 0.0 and target_speed > _speed:
		accel *= Tuning.TURN_BURST_ACCEL_MULT
	_speed = move_toward(_speed, target_speed, accel * delta)

	velocity.x = _heading.x * _speed
	velocity.z = _heading.z * _speed


func _update_facing(delta: float) -> void:
	# The whole backpedal mechanic: the body keeps reading the play instead
	# of chasing the direction the feet are shuffling in. Facing simply
	# doesn't move — see _update_locomotion for where the feet do.
	if _backpedaling:
		return
	var desired := _heading
	if _speed <= Tuning.PIVOT_SPEED_THRESHOLD and _wish_dir != Vector3.ZERO:
		desired = _wish_dir
	# A node's forward is -Z, so the yaw that points -Z along `desired`.
	var target_yaw := atan2(-desired.x, -desired.z)
	_facing_yaw = rotate_toward(
		_facing_yaw, target_yaw, deg_to_rad(Tuning.FACING_TURN_RATE) * delta)
	rotation.y = _facing_yaw


## (strafe, forward) in -1..1, relative to where the body is facing.
## Non-zero on the strafe axis exactly when the velocity has fallen
## behind the facing — i.e. mid-turn — which is what makes the blend
## space earn its keep even in a game where you mostly run forwards.
func locomotion_blend() -> Vector2:
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	# This is called after move_and_slide() has already run for the frame
	# (see _physics_process), so `velocity` here is move_and_slide's own
	# collision-response output, not the value _update_locomotion() set —
	# a standing player's velocity can pick up sub-millimetre horizontal
	# noise from the floor-contact slide resolution even when nothing is
	# actually moving. The deadzone in _update_locomotion() guards a
	# different, earlier read of velocity and does not catch this one;
	# this is the read that actually feeds the AnimationTree, so it needs
	# its own guard, applied at the one place its output is used, rather
	# than trusting an upstream snap that runs before move_and_slide has
	# had its say.
	if horizontal.length_squared() < Tuning.LOCOMOTION_VELOCITY_DEADZONE ** 2:
		horizontal = Vector3.ZERO
	var forward := -global_transform.basis.z
	var right := global_transform.basis.x
	return Vector2(
		clampf(right.dot(horizontal) / Tuning.SPRINT_SPEED, -1.0, 1.0),
		clampf(forward.dot(horizontal) / Tuning.SPRINT_SPEED, -1.0, 1.0))


## CharacterBody3D does not shove rigid bodies on its own. Running
## through a loose ball has to actually move it, or the ball reads as
## scenery.
func _push_rigid_bodies() -> void:
	for i in get_slide_collision_count():
		var collision := get_slide_collision(i)
		var body := collision.get_collider() as RigidBody3D
		if body == null:
			continue
		if body is Ball and (body as Ball).is_held:
			continue
		var push := -collision.get_normal()
		push.y = 0.0
		if push.length_squared() < 0.000001:
			continue
		var strength := Tuning.PLAYER_PUSH_FORCE * body.mass \
			* clampf(_speed / Tuning.SPRINT_SPEED, 0.15, 1.0)
		body.apply_impulse(
			push.normalized() * strength,
			collision.get_position() - body.global_position)


## Nothing about CharacterBody3D's collision stops it walking off the
## ground slab's edge into the void — the slab is finite (Field.SURROUND_
## MARGIN past the oval boundary) but there is no wall there. Keep every
## player (human or AI) inside that slab, a small buffer short of its
## true edge. AI never deliberately paths past the boundary, but a chase
## or a plant-and-pivot can carry it there anyway, so this is enforced for
## both brains in one place rather than trusted to AI target selection.
const FIELD_CONTAINMENT_BUFFER := 1.5   # m short of the slab's true edge

func _contain_to_field() -> void:
	var limit_x := Tuning.FIELD_HALF_LENGTH + Field.SURROUND_MARGIN - FIELD_CONTAINMENT_BUFFER
	var limit_z := Tuning.FIELD_HALF_WIDTH + Field.SURROUND_MARGIN - FIELD_CONTAINMENT_BUFFER
	var pos := global_position
	var nx := pos.x / limit_x
	var nz := pos.z / limit_z
	var radial := sqrt(nx * nx + nz * nz)
	if radial > 1.0:
		global_position.x = pos.x / radial
		global_position.z = pos.z / radial


# ── Possession ───────────────────────────────────────────────────────

func is_carrying() -> bool:
	return is_instance_valid(_carried_ball) and _carried_ball.is_held


func carried_ball() -> Ball:
	return _carried_ball


## True while a stand-the-mark protection window (Tuning.MARK_HOLD_DURATION)
## from a legal mark is still running — _try_tackle() skips a protected
## carrier entirely. Also the hook a future protected kick-in state reuses
## for goal-square immunity (see docs' Priority 5).
func is_protected() -> bool:
	return _protected_timer > 0.0


## Grants tackle immunity for `duration` seconds — the exact same
## _protected_timer a legal mark already uses (design brief priority 5:
## "do not build a new protection system... reuse _protected_timer/
## is_protected() directly"), for a protected kick-in's goal-square
## immunity. Already clears itself early the moment this player disposes
## (_dispose()'s existing "playing on forfeits protection" line) — a
## kick-in that plays on loses its immunity exactly like a mark that does,
## with no extra code needed here for that.
func grant_protection(duration: float) -> void:
	_protected_timer = maxf(_protected_timer, duration)
	_apply_retreat_freeze(duration)


## True while obliged to stand the mark — see _frozen_timer.
func is_standing_the_mark() -> bool:
	return _frozen_timer > 0.0


## Called on the opponent by whoever just took a legal mark
## (_apply_stand_the_mark) — freezes movement for `duration` seconds.
func stand_the_mark(duration: float) -> void:
	_frozen_timer = maxf(_frozen_timer, duration)


## Releases early — called on every entry in _frozen_opponents the instant
## the mark-taker/free-kick-taker disposes, so a frozen player isn't held
## past the moment the rule actually requires (real AFL: free to move once
## the kick is taken or the mark-taker plays on, not just once the full
## window lapses).
func release_stand_the_mark() -> void:
	_frozen_timer = 0.0


## Public entry point onto the same shared attach/possession/signal path
## every other way of gaining the ball already goes through
## (_complete_gather) — for placements that hand a player the ball outright
## rather than having them reach for it, like a protected kick-in.
func give_possession(ball: Ball) -> void:
	_complete_gather(ball)


## Let go without disposing — for resets and, later, for a tackle
## stripping the ball.
func drop_ball() -> void:
	if is_instance_valid(_carried_ball):
		_carried_ball.detach()
	_carried_ball = null
	_carry_distance = 0.0
	_kick_charge = 0.0
	_charging = false
	# Otherwise a hip-fire windup broken by a tackle before it reaches
	# _dispose() would leave this stuck true — the next kick to actually
	# fire, possibly a properly-aimed one with a fresh ball, would wrongly
	# inherit hip-fire's extra scatter.
	_hip_fire_kick = false
	_gather_cooldown = Tuning.GATHER_COOLDOWN
	_protected_timer = 0.0
	_release_frozen_opponents()
	if MatchState.possession == team:
		MatchState.possession = Tuning.Team.NONE


## Metres run since the last bounce. AFL requires a bounce every 15m
## (Tuning.BOUNCE_INTERVAL, unchanged from Prototype 1's already-correct
## BOUNCE_INTERVAL). Tracked now because it shapes how running with the
## ball feels; the free kick for running too far is a match rule and
## waits for the milestone that owns match rules.
func carry_distance() -> float:
	return _carry_distance


func bounce_overdue() -> bool:
	return is_carrying() and _carry_distance >= Tuning.BOUNCE_INTERVAL


func speed() -> float:
	return _speed


## Diagnostic — see DebugHud. True while reading the play backward (see the
## Backpedal section of Tuning / _update_locomotion).
func is_backpedaling() -> bool:
	return _backpedaling


func kick_charge() -> float:
	return _kick_charge


func animation_state() -> StringName:
	return _animation.current_state()


func _track_carry_distance(previous_position: Vector3) -> void:
	if not is_carrying():
		_carry_distance = 0.0
		return
	var moved := global_position - previous_position
	moved.y = 0.0
	_carry_distance += moved.length()


## Passive walk-over gather (design brief: bringing the ball to hand must be
## affected by the player's speed at the moment of contact rather than being
## independent of movement). The Area3D shape is sized generously (see
## _ready()); the real cutoff is this explicit distance test against the
## current speed-scaled reach, so a player running through a bounce
## genuinely gets more reach than one standing still over it — not by much,
## GATHER_LUNGE_MAX keeps it well short of the deliberate GROUND_PICKUP
## reach, but real.
func _try_gather() -> void:
	if is_carrying() or _gather_cooldown > 0.0 or _action != Tuning.Action.NONE \
			or _stun_timer > 0.0:
		return
	var reach := Tuning.GATHER_RADIUS \
		+ minf(_speed * Tuning.GATHER_LUNGE_PER_SPEED, Tuning.GATHER_LUNGE_MAX)
	for body in _gather_zone.get_overlapping_bodies():
		if not (body is Ball):
			continue
		var ball := body as Ball
		if ball.is_held:
			continue
		if ball.linear_velocity.length() > Tuning.GATHER_MAX_BALL_SPEED:
			continue
		if _carry_point.global_position.distance_to(ball.global_position) > reach:
			continue
		_complete_gather(ball)
		return


## Shared attach/possession/signal path for every way of gaining the ball —
## the passive walk-over gather just above, an explicit ground pickup and
## every mark tier (see the Marking section below) — so none of them can
## drift out of sync about what "gained possession" actually does.
func _complete_gather(ball: Ball) -> void:
	ball.attach_to(_carry_point, self)
	_carried_ball = ball
	_carry_distance = 0.0
	MatchState.possession = team
	if _brain is HumanBrain:
		InputManager.rumble(Tuning.RUMBLE_GATHER)
	ball_gathered.emit(ball)


# ── Contests ─────────────────────────────────────────────────────────
# Design doc §5: a tackle is decided by getting into range and timing it,
# not by a dice roll. No holding-the-ball adjudication yet (free kick vs
# ball-up) — see RULES_REFERENCE.md §4 — a successful tackle always spills
# the ball loose for a fresh contest.

## FIFA-style ball-steal assist (polish-pass brief: "it's a bit hard to get
## the ball off the AI"). See Tuning's own "Tackle lunge" comment for the
## actual diagnosis (AI_PRESSURE_RADIUS forces a disposal outside
## TACKLE_RADIUS, so a defender closing at normal run speed rarely gets
## there in time) and why this is a speed burst rather than a radius/chance
## change. Triggers on the tackle button's rising edge, not the held state
## _try_tackle() reads directly — holding tackle at standing range still
## works exactly as it always has; this only adds a commit option the one
## time it's actually needed, just out of that reach.
func _update_tackle_lunge(delta: float) -> void:
	var pressed := _brain.wants_tackle()
	var just_pressed := pressed and not _tackle_was_pressed
	_tackle_was_pressed = pressed

	if _lunge_timer > 0.0:
		_lunge_timer = _tick_down(_lunge_timer, delta)
		return
	if _lunge_cooldown > 0.0 or is_carrying() or _stun_timer > 0.0 or _action != Tuning.Action.NONE:
		return

	# A press landing a frame or two before the guards above actually
	# cleared shouldn't just vanish (fundamentals-pass input buffering) —
	# fall back to InputManager's short buffer window before giving up on
	# this frame. Checked only after every other blocking guard, so a
	# buffered press is never consumed on a frame it wouldn't actually
	# fire on. Human only: AI's wants_tackle() is a fresh proximity
	# decision every physics frame, not a real button press — there's
	# nothing to buffer for it.
	if not just_pressed \
			and not (_brain is HumanBrain and InputManager.consume_buffered_press(&"tackle")):
		return

	var carrier := _nearest_opposing_carrier()
	if carrier == null or carrier.is_protected():
		return
	var to_carrier := carrier.global_position - global_position
	to_carrier.y = 0.0
	var dist := to_carrier.length()
	if dist <= Tuning.TACKLE_RADIUS or dist > Tuning.TACKLE_LUNGE_RANGE:
		return   # already close enough for a standing tackle, or too far to commit to
	var direction := to_carrier / dist
	if (-global_transform.basis.z).dot(direction) < Tuning.TACKLE_LUNGE_MIN_DOT:
		return   # not roughly facing them — no lunging sideways or backward

	_lunge_direction = direction
	_lunge_timer = Tuning.TACKLE_LUNGE_DURATION
	_lunge_cooldown = Tuning.TACKLE_LUNGE_COOLDOWN


func _try_tackle() -> void:
	if is_carrying() or _stun_timer > 0.0 or _action != Tuning.Action.NONE or _mark_readying:
		return
	# A lunge in progress is a commitment — it still has to land the same
	# proximity test below, but it doesn't need the button held throughout,
	# same as an aggressive mark's jump or a bump's flick don't need theirs
	# held either once launched.
	if not _brain.wants_tackle() and _lunge_timer <= 0.0:
		return
	var target := _nearest_player(Tuning.TACKLE_RADIUS, func(other: PlayerController) -> bool:
		return other.team != team and other.is_carrying() and not other.is_protected())
	if target != null:
		target._get_tackled(self)


## Called on the tackled player, by the tackler.
func _get_tackled(by: PlayerController) -> void:
	var ball := _carried_ball
	# Captured before drop_ball() resets anything, though drop_ball() itself
	# doesn't touch this timer — is_carrying() going false next frame is what
	# actually zeroes it (see _physics_process) — read now regardless, so
	# there's no dependency on exactly when that reset happens to land.
	var holding_the_ball := _possession_held_seconds >= Tuning.PRIOR_OPPORTUNITY_GRACE
	drop_ball()
	_stun_timer = Tuning.TACKLE_STUN_DURATION
	_action = Tuning.Action.NONE
	_action_elapsed = 0.0
	_action_fired = false
	if is_instance_valid(ball):
		ball.apply_central_impulse(_scatter_from(by, 0.0) * Tuning.TACKLE_SPILL_SPEED * ball.mass)
	if holding_the_ball:
		holding_the_ball_called.emit(by)
	else:
		field_ball_up_called.emit(by, self)


## Smother (X tap, not carrying): close down an opponent before their kick
## leaves the boot. Targets anyone still carrying whose kick hasn't fired
## yet — either still in stance (is_kick_aiming()) or mid-swing but before
## contact (is_mid_kick_swing()) — since a kick already gone is nothing a
## smother can do anything about.
func _try_smother() -> void:
	if is_carrying() or _stun_timer > 0.0 or _action != Tuning.Action.NONE:
		return
	if not _brain.wants_smother():
		return
	var target := _nearest_player(Tuning.SMOTHER_RADIUS, func(other: PlayerController) -> bool:
		return other.team != team and other.is_carrying() \
			and (other.is_kick_aiming() or other.is_mid_kick_swing()))
	if target != null:
		target._get_smothered(self)


## Shared spill-direction math for _get_tackled/_get_smothered: away from
## whoever caused it, flattened and re-lifted by `up_bias` (a smother pops
## the ball up slightly at the boot; a tackle spills it flat), falling back
## to straight ahead on the (near-impossible) exact-same-position case
## rather than normalizing a zero vector.
func _scatter_from(attacker: PlayerController, up_bias: float) -> Vector3:
	var scatter := global_position - attacker.global_position
	scatter.y = up_bias
	return scatter.normalized() if scatter.length_squared() > 0.0001 else Vector3.FORWARD


## Called on the smothered player, by the smotherer. Cancels the kick
## outright — whatever stage the swing was at, it doesn't complete — and
## the ball drops right at their feet rather than spilling like a tackle:
## blocked at the boot means it barely moves.
func _get_smothered(by: PlayerController) -> void:
	var ball := _carried_ball
	drop_ball()
	_action = Tuning.Action.NONE
	_action_elapsed = 0.0
	_action_fired = false
	if is_instance_valid(ball):
		ball.knock(_scatter_from(by, 0.3) * Tuning.SMOTHER_SPILL_SPEED * ball.mass)


# ── Bump ─────────────────────────────────────────────────────────────
# Design brief priority 7: LB hold + Right Stick flick, Madden's hit-stick
# model. Out-of-possession only, same as tackle/spoil/smother. The flick
# gesture itself lives in InputManager (a raw device primitive that didn't
# exist before this pass); this section only decides what a completed
# flick, while stance is held, actually does.

func _update_bump(_delta: float) -> void:
	if is_carrying() or _stun_timer > 0.0 or _action != Tuning.Action.NONE:
		return
	if not _brain.wants_bump_stance():
		return
	var flick := InputManager.flick_vector()
	if flick == Vector2.ZERO:
		return
	_try_bump(flick)


## `flick_raw` is the stick's raw (x, y) at the instant the gesture
## completed — converted to a world-space direction the same camera-
## relative way HumanBrain.wish_direction() already converts movement
## input, so "flick right" means the same thing on screen a bump does as
## it does for running.
func _flick_world_direction(flick_raw: Vector2) -> Vector3:
	var forward := Vector3.FORWARD
	var right := Vector3.RIGHT
	if is_instance_valid(camera):
		var flat := -camera.global_transform.basis.z
		flat.y = 0.0
		if flat.length_squared() > 0.000001:
			forward = flat.normalized()
			right = Vector3(-forward.z, 0.0, forward.x)
	var dir := right * flick_raw.x + forward * flick_raw.y
	return dir.normalized() if dir.length_squared() > 0.0001 else forward


## No target to lock onto ahead of time — a bump is a physical swing, not a
## selection. Range/cone gate whether the flick actually connected with
## whoever's nearby, the same "physically doing the right thing is what
## resolves it" stance every other contest here already takes.
func _try_bump(flick_raw: Vector2) -> void:
	if _bump_cooldown > 0.0:
		return
	var carrier := _nearest_opposing_carrier()
	if carrier == null:
		return
	var to_carrier := carrier.global_position - global_position
	to_carrier.y = 0.0
	if to_carrier.length() > Tuning.BUMP_RANGE or to_carrier.length_squared() < 0.0001:
		return

	var flick_dir := _flick_world_direction(flick_raw)
	var aim_error := flick_dir.angle_to(to_carrier.normalized())
	if aim_error > deg_to_rad(Tuning.BUMP_CONE_DEG):
		return   # swung at empty air — physically nothing to connect with, no signal

	_bump_cooldown = Tuning.BUMP_COOLDOWN

	# "Timing relative to the ball carrier's approach determines the
	# outcome" (design brief): landed while they're genuinely closing on
	# the bumper is clean; landed on someone stationary or moving away
	# still connects (they were in range and in the cone) but glances
	# rather than lands properly.
	var carrier_velocity := Vector3(carrier.velocity.x, 0.0, carrier.velocity.z)
	var approach_dot := 0.0
	if carrier_velocity.length_squared() > 0.01:
		approach_dot = carrier_velocity.normalized().dot(-to_carrier.normalized())
	var clean := approach_dot >= Tuning.BUMP_APPROACH_DOT_MIN
	var scale := 1.0 if clean else Tuning.BUMP_MISTIMED_SCALE

	carrier.receive_bump(flick_dir * Tuning.BUMP_KNOCKBACK_SPEED * scale,
		Tuning.BUMP_STUN_DURATION * scale, self)
	bump_landed.emit(self, carrier, clean)


## Stand-the-mark (RULES_REFERENCE.md's MARK_STAND_MIN_DISTANCE entry): a
## legal mark obliges the nearest opponent — no player-marking assignment
## exists in this project, so "nearest at the moment of the mark" stands in
## for "whoever the umpire would call the mark against" — to hold their
## ground until this player disposes. Scoped to marks only, not free kicks/
## kick-ins: those already reuse _protected_timer for the taker's own
## immunity, but the broader "every other opponent retreats 10m" rule is a
## separate, bigger piece of work (see docs/FEATURE_AUDIT.md) left for when
## the rest of the free-kick/set-shot apparatus gets built.
func _apply_stand_the_mark() -> void:
	var opponent := _nearest_opponent()
	if opponent == null:
		return
	opponent.stand_the_mark(Tuning.MARK_HOLD_DURATION)
	if opponent not in _frozen_opponents:
		_frozen_opponents.append(opponent)


## The general "get back 10 metres" rule (Tuning.FREE_KICK_RETREAT_
## DISTANCE) — every opponent within range of THIS player's current
## position, not just the one _apply_stand_the_mark() names. Called from
## grant_protection() itself so all four moments that grant it (a legal
## mark, a protected kick-in, a holding-the-ball free kick, an out-on-the-
## full free kick) get the same retreat for free, with nothing extra
## needed at any of those call sites.
func _apply_retreat_freeze(duration: float) -> void:
	for node in get_tree().get_nodes_in_group(&"players"):
		var other := node as PlayerController
		if other == null or other == self or other.team == team:
			continue
		if global_position.distance_to(other.global_position) > Tuning.FREE_KICK_RETREAT_DISTANCE:
			continue
		other.stand_the_mark(duration)
		if other not in _frozen_opponents:
			_frozen_opponents.append(other)


func _release_frozen_opponents() -> void:
	for opponent in _frozen_opponents:
		if is_instance_valid(opponent):
			opponent.release_stand_the_mark()
	_frozen_opponents.clear()


## Shared "closest player matching a filter" search behind every tackle/
## smother/bump/stand-the-mark lookup — one place to change if the filter
## itself ever needs to (e.g. excluding stunned players), instead of six
## separately-maintained copies of the same get_nodes_in_group loop.
## `max_dist` is INF for callers that want the nearest regardless of range
## and apply their own distance test afterward (e.g. tackle lunge's wider
## commit range vs. the standing tackle radius).
func _nearest_player(max_dist: float, predicate: Callable) -> PlayerController:
	var best: PlayerController = null
	var best_dist := max_dist
	for node in get_tree().get_nodes_in_group(&"players"):
		var other := node as PlayerController
		if other == null or other == self or not predicate.call(other):
			continue
		var dist := global_position.distance_to(other.global_position)
		if dist < best_dist:
			best_dist = dist
			best = other
	return best


func _nearest_opponent() -> PlayerController:
	return _nearest_player(INF, func(other: PlayerController) -> bool: return other.team != team)


func _nearest_opposing_carrier() -> PlayerController:
	return _nearest_player(INF, func(other: PlayerController) -> bool:
		return other.team != team and other.is_carrying())


## Called on the bumped player, by the bumper. A knockback that overrides
## normal movement until it decays (see _update_locomotion) plus a short
## stun — distinct from a tackle, which strips the ball outright; a bump
## only ever disrupts balance (real AFL: dispossession is a tackle's job).
func receive_bump(impulse: Vector3, stun_duration: float, _by: PlayerController) -> void:
	_knockback = Vector3(impulse.x, 0.0, impulse.z)
	_stun_timer = maxf(_stun_timer, stun_duration)


# ── Marking ──────────────────────────────────────────────────────────
# Design brief priority 2: a three-tier contextual catch, resolved by a
# reach-radius/timing test against the ball's live position rather than a
# probability roll (RULES_REFERENCE.md §3, same physical-not-scripted
# stance tackling already follows). Safe (A, held) plants and waits for the
# ball to arrive; Running (X, tapped) snap-grabs at pace with a tighter
# margin; Aggressive (Y, tapped) commits to a real jump. The same A button
# becomes a ground pickup once the ball isn't airborne — the brief's "ball
# state + player state + proximity + input, not just the button" framing.

## Every condition that makes a mark attempt a non-starter regardless of
## ball state — shared between _update_marking (the real resolution path)
## and live_mark_prompt (the UI hint) so the two can't silently disagree
## about when a mark is actually live. They used to: live_mark_prompt had
## its own, incomplete copy of this that never checked _gather_cooldown
## (0.45s "before you can regather your own kick," set on every disposal —
## see _dispose()), so the badge/ring briefly read as live for a player
## standing right where they just kicked from, before the ball had gone
## anywhere. _update_marking already enforced this correctly; the prompt
## just wasn't asking the same question.
func _mark_attempt_blocked() -> bool:
	return is_carrying() or _stun_timer > 0.0 or _action != Tuning.Action.NONE \
		or _gather_cooldown > 0.0


func _update_marking(delta: float) -> void:
	if _mark_attempt_blocked():
		_mark_readying = false
		return

	var ball := _live_ball()
	if not is_instance_valid(ball) or ball.is_held:
		_mark_readying = false
		return

	if ball.is_airborne():
		_try_spoil(ball)
		_update_aerial_contest(ball, delta)
	else:
		# The one Safe-miss detection point: this player was genuinely
		# holding (readying) a Safe attempt and the ball has now touched
		# down uncaught — a real drop, worth the same feedback trio a
		# failed Running/Aggressive attempt gets. Deliberately scoped to
		# just this common case, not every theoretical way a held Safe
		# attempt can end (stunned mid-hold, an opponent beats them to a
		# loose ball first) — those stay silent, same as they already are
		# today, rather than chasing every exit path for a tier whose whole
		# point is staying simple.
		if _mark_readying and _brain is HumanBrain:
			InputManager.rumble(Tuning.RUMBLE_MARK_MISS)
			mark_missed.emit(Tuning.Action.MARK_SAFE)
			_begin(Tuning.Action.MARK_SAFE_MISS)
			_mark_readying = false
			return   # whiff reaction owns this frame — don't also attempt a ground pickup under it
		_mark_readying = false
		_update_ground_pickup(ball, delta)


## Punch/Spoil (LT tap, not carrying, near an aerial contest): knocks a
## contestable ball off its line rather than controlling it. No target
## player to name — physically deflecting the ball is enough on its own to
## spoil whoever else was about to mark it, since their own reach test
## (_ball_in_catch_reach) reads the ball's real position/velocity, which
## this has just changed. wants_spoil() is already edge-triggered (one tap,
## one attempt); the cooldown on top of that is what stops a volley of fast
## repeat taps from re-punching the same ball again a few frames later,
## faster than a real swing could reset.
func _try_spoil(ball: Ball) -> void:
	if _spoil_cooldown > 0.0 or not _brain.wants_spoil():
		return
	if ball.global_position.distance_to(_carry_point.global_position) > Tuning.SPOIL_RADIUS:
		return
	_spoil_cooldown = Tuning.SPOIL_COOLDOWN
	var away := ball.global_position - global_position
	away.y = 0.4   # a real punch knocks it up and away, not flat along the ground
	away = away.normalized() if away.length_squared() > 0.0001 else Vector3.UP
	ball.knock(away * Tuning.SPOIL_IMPULSE_SPEED * ball.mass)


## Safe branch splits on brain type — a HumanBrain gets the graded timing
## treatment (press rumble on the rising edge of the hold, reach narrowed
## by how well the hold's timing lines up — see mark_timing_offset), an
## AIBrain gets the exact original unconditional-reach check, byte for
## byte. Deliberate, not an oversight: AI marking is a documented, minimal
## stub (docs/FEATURE_AUDIT.md) that this feature isn't meant to touch, and
## AI never taps Running/Aggressive at all (AIBrain never overrides
## wants_mark_running()/wants_mark_aggressive()), so only Safe needs the
## split.
func _update_aerial_contest(ball: Ball, _delta: float) -> void:
	if _brain.wants_mark_safe():
		if _brain is HumanBrain:
			# _mark_readying still holds *last* frame's value here — reading
			# it before the unconditional assignment below is what makes
			# this a rising-edge check with no extra state of its own.
			if not _mark_readying:
				InputManager.rumble(Tuning.RUMBLE_MARK_PRESS)
			_mark_readying = true
			var mult := _timing_reach_mult(mark_timing_offset(ball),
				Tuning.MARK_SAFE_IDEAL_WINDOW, Tuning.MARK_SAFE_OK_WINDOW)
			if mult > 0.0 and _ball_in_catch_reach(ball, Tuning.MARK_SAFE_REACH_SCALE * mult):
				_complete_mark(ball, Tuning.Action.MARK_SAFE)
		else:
			_mark_readying = true
			if _ball_in_catch_reach(ball, Tuning.MARK_SAFE_REACH_SCALE):
				_complete_mark(ball, Tuning.Action.MARK_SAFE)
		return
	_mark_readying = false

	if _brain.wants_mark_running():
		_attempt_running_mark(ball)
		return

	if _brain.wants_mark_aggressive() and ball.global_position.distance_to(
			_carry_point.global_position) <= Tuning.MARK_CONTEST_RANGE:
		_begin_aggressive_mark()


## Running's tap and its resolution are the same instant (unlike Aggressive,
## whose jump defers resolution to a later contact frame — see
## _resolve_aggressive_mark), so timing is graded right here, once. A tap
## that fails outside MARK_CONTEST_RANGE is treated as no attempt at all
## (silent, matching today) rather than a graded miss — the range gate is
## the same "is this even live" test _update_aerial_contest's own
## Aggressive branch already uses, not a new number.
func _attempt_running_mark(ball: Ball) -> void:
	var mult := _timing_reach_mult(mark_timing_offset(ball),
		Tuning.MARK_RUNNING_IDEAL_WINDOW, Tuning.MARK_RUNNING_OK_WINDOW)
	if mult > 0.0 and _ball_in_catch_reach(ball, Tuning.MARK_RUNNING_REACH_SCALE * mult):
		_complete_mark(ball, Tuning.Action.MARK_RUNNING)
		return
	if ball.global_position.distance_to(_carry_point.global_position) <= Tuning.MARK_CONTEST_RANGE:
		if _brain is HumanBrain:
			InputManager.rumble(Tuning.RUMBLE_MARK_MISS)
		mark_missed.emit(Tuning.Action.MARK_RUNNING)
		_begin(Tuning.Action.MARK_RUNNING_MISS)


## A — Ground Pickup once the ball is loose rather than in flight (design
## brief): a deliberate reach, wider and speed-responsive versus the
## passive walk-over _try_gather() above, not an instant snap onto the ball.
func _update_ground_pickup(ball: Ball, _delta: float) -> void:
	if not _brain.wants_mark_safe():
		return
	if ball.linear_velocity.length() > Tuning.GATHER_MAX_BALL_SPEED:
		return
	var reach := Tuning.GROUND_PICKUP_RADIUS + _speed * Tuning.GROUND_PICKUP_LUNGE_PER_SPEED
	var to_ball := ball.global_position - _carry_point.global_position
	to_ball.y = 0.0
	if to_ball.length() <= reach:
		_complete_gather(ball)


## Resolved immediately rather than deferred through the _action/contact
## machinery below: Safe/Running only ever call this once they already know
## the catch connects, so the "attempt" and the "outcome" are the same
## event. _begin() just plays the catch/cradle animation after the fact.
func _complete_mark(ball: Ball, tier: Tuning.Action) -> void:
	_finish_mark_catch(ball, tier)
	_mark_readying = false
	_begin(tier)


## Shared tail for a legal-or-not catch once the gather itself has already
## happened — protection + stand-the-mark (only on a legal mark), rumble,
## and the outcome signal. _complete_mark (Safe/Running) and
## _resolve_aggressive_mark differ only in what leads up to the catch: the
## former already knows it connects before calling this, the latter is
## still mid-air and resolves contact here.
func _finish_mark_catch(ball: Ball, tier: Tuning.Action) -> void:
	var legal_mark := ball.is_mark_eligible()
	_complete_gather(ball)
	if legal_mark:
		grant_protection(Tuning.MARK_HOLD_DURATION)
		_apply_stand_the_mark()
	if _brain is HumanBrain:
		InputManager.rumble(Tuning.RUMBLE_MARK)
	mark_caught.emit(tier, legal_mark)


## Y commits to the jump the instant it's pressed, whether or not it will
## actually connect — that commitment is the entire risk of an aggressive
## attempt. The vertical impulse goes through _pending_jump so it survives
## this frame's floor-snap (see _physics_process); everything after that is
## the same gravity integration every other airborne frame already uses —
## no separate jump-arc code, the arc just falls out of it.
func _begin_aggressive_mark() -> void:
	if _brain is HumanBrain:
		InputManager.rumble(Tuning.RUMBLE_MARK_PRESS)
	_pending_jump = true
	_begin(Tuning.Action.MARK_AGGRESSIVE)


## Fires at the jump's contact instant (Tuning.ACTION_CONTACT), timed to
## land near its peak reach — see _update_action's dispatch. A clean miss
## leaves the ball untouched: no contact happened, so nothing about its
## flight changes.
##
## Timing is graded *here*, fresh, rather than captured back at the tap in
## _begin_aggressive_mark — the jump always takes the same fixed
## ACTION_CONTACT[MARK_AGGRESSIVE] seconds to reach this instant, so "good
## timing" for this tier really means "the ball's offset is near zero by
## the time the jump peaks," which is exactly what re-reading
## mark_timing_offset() right now measures. That also makes it automatically
## reward the real skill (committing with the right lead time before the
## ball arrives, not stabbing the button as it lands) with no extra state
## carried between the two functions.
func _resolve_aggressive_mark() -> void:
	var ball := _live_ball()
	var mult := 0.0
	if is_instance_valid(ball) and not ball.is_held:
		mult = _timing_reach_mult(mark_timing_offset(ball),
			Tuning.MARK_AGGRESSIVE_IDEAL_WINDOW, Tuning.MARK_AGGRESSIVE_OK_WINDOW)
	if mult > 0.0 and _ball_in_catch_reach(ball, Tuning.MARK_AGGRESSIVE_REACH_SCALE * mult):
		_finish_mark_catch(ball, Tuning.Action.MARK_AGGRESSIVE)
	else:
		if _brain is HumanBrain:
			InputManager.rumble(Tuning.RUMBLE_MARK_MISS)
		mark_missed.emit(Tuning.Action.MARK_AGGRESSIVE)


## MARK_ASSIST_RADIUS_BONUS is added after the per-tier scale, not before —
## a flat metres bonus applied uniformly to Safe/Running/Aggressive keeps
## their relative difficulty spread intact rather than compressing it.
func _ball_in_catch_reach(ball: Ball, reach_scale: float) -> bool:
	if not ball.is_airborne():
		return false
	var reach := Tuning.MARK_CATCH_RADIUS * reach_scale + Tuning.MARK_ASSIST_RADIUS_BONUS
	return ball.global_position.distance_to(_carry_point.global_position) <= reach


## Live estimate of seconds until the ball reaches this player's hands —
## negative while it's still closing (counting up to zero), or the flat
## Tuning.MARK_TIMING_PAST_PEAK_OFFSET sentinel once it no longer is
## (already arrived, or drifting past/away). Recomputed fresh from the
## ball's current position/velocity on every call rather than predicted
## once ahead of time and cached: this project already has three
## independent hand-rolled forward-simulation copies for three different
## purposes (Ball._integrate_forces itself, KickTrajectory._simulate's
## preview stepper, MarkChallenge._predicted_range's inverse-ballistics
## guess) and a fourth wasn't worth adding here — a live reactive estimate
## is simpler and self-corrects every physics frame if the ball's flight is
## perturbed after launch (catch gravity, a spoil), which a one-shot
## prediction committed to in advance wouldn't.
##
## Public (no leading underscore) because MarkPrompt needs the same number
## the resolution logic uses to draw an honest countdown — same convention
## as live_mark_prompt()/catch_point_position() below, both also written
## for an outside caller.
func mark_timing_offset(ball: Ball) -> float:
	var to_catch := ball.global_position - _carry_point.global_position
	var dist := to_catch.length()
	if dist < 0.001:
		return 0.0
	# Relative to this player's own motion, not just the ball's — matters
	# for a Running mark taken at pace, where closing the gap is a joint
	# effort between the ball's flight and the player's own sprint toward
	# it, not the ball's velocity alone.
	var closing_speed := -to_catch.normalized().dot(ball.linear_velocity - velocity)
	if closing_speed > Tuning.MARK_TIMING_MIN_CLOSING_SPEED:
		return -dist / closing_speed
	return Tuning.MARK_TIMING_PAST_PEAK_OFFSET


## The physical (never probabilistic — RULES_REFERENCE.md §3) consequence
## of timing accuracy: full reach inside the ideal band, a narrowed one
## inside the wider "contested" band, none at all outside it. One shared
## step function behind all three tiers' timing grading, so they can't
## drift out of sync about what "inside the window" actually means.
func _timing_reach_mult(offset: float, ideal_window: float, ok_window: float) -> float:
	var magnitude := absf(offset)
	if magnitude <= ideal_window:
		return 1.0
	if magnitude <= ok_window:
		return Tuning.MARK_TIMING_OK_REACH_MULT
	return Tuning.MARK_TIMING_MISS_REACH_SCALE


## World position of this player's catch point (their hands, for marking
## purposes) — the same Marker3D carrying already uses. Exposed so Ball's
## catch-gravity assist (_apply_catch_gravity) can find the nearest live
## target without needing its own copy of where "the hands" are.
func catch_point_position() -> Vector3:
	return _carry_point.global_position


## Madden-style contest prompt (polish-pass brief) — the single tier
## actually relevant right now, not every tier that would technically
## connect (an early version of this showed all three simultaneously,
## since Safe's reach always covers Running's narrower one and Aggressive's
## MARK_CONTEST_RANGE is wider again — nearly every live moment had all
## three "live" at once, which is correct but not useful as a prompt).
##
## Reuses the exact reach tests _update_aerial_contest itself resolves
## against, picking exactly one to recommend by the same speed-scale
## reasoning the tiers themselves are already built on (Tuning's "Safe
## plants you properly; Running barely interrupts your stride" comment):
## Running is only the natural read while actually moving at pace: Safe is
## the default the instant you're not; Aggressive is only ever the one
## live option while the ball hasn't reached normal catching reach yet —
## once it has, a leap stops being the natural action even though it
## would still technically connect, so it stops being recommended.
func live_mark_prompt(ball: Ball) -> Tuning.Action:
	if not is_instance_valid(ball) or _mark_attempt_blocked() or not ball.is_airborne():
		return Tuning.Action.NONE
	var running_live := _ball_in_catch_reach(ball, Tuning.MARK_RUNNING_REACH_SCALE)
	if running_live and _speed > Tuning.JOG_SPEED:
		return Tuning.Action.MARK_RUNNING
	if _ball_in_catch_reach(ball, Tuning.MARK_SAFE_REACH_SCALE):
		return Tuning.Action.MARK_SAFE
	if running_live:
		return Tuning.Action.MARK_RUNNING
	if ball.global_position.distance_to(_carry_point.global_position) <= Tuning.MARK_CONTEST_RANGE:
		return Tuning.Action.MARK_AGGRESSIVE
	return Tuning.Action.NONE


# ── Ruck contests ────────────────────────────────────────────────────
# Design brief priority 4: centre bounce, field ball-up and boundary
# throw-in all resolve through the same contest — see Tuning's own "Ruck
# contests" section and FullGame._begin_ruck_contest, which is the one
# place that decides *where* a contest happens and *who* contests it. This
# section only knows how to contest one, the same way regardless of which
# situation nominated it.

## Called by whoever is orchestrating a contest (FullGame._begin_ruck_
## contest) on exactly the two nominated players. Self-expiring — see
## _ruck_contest_timer in _physics_process — so a ruckman can't hold RB's
## Hit-Out meaning past the one contest they were nominated into.
func set_ruck_contestant(value: bool) -> void:
	_is_ruck_contestant = value
	_ruck_contest_timer = Tuning.RUCK_CONTEST_WINDOW if value else 0.0


func is_ruck_contestant() -> bool:
	return _is_ruck_contestant


func _update_ruck_contest(_delta: float) -> void:
	if not _is_ruck_contestant or is_carrying() or _stun_timer > 0.0 \
			or _action != Tuning.Action.NONE:
		return
	var ball := _live_ball()
	if not is_instance_valid(ball) or ball.is_held or not ball.is_airborne():
		return
	if not _brain.wants_hit_out():
		return
	if ball.global_position.distance_to(_carry_point.global_position) > Tuning.RUCK_CONTEST_JUMP_RANGE:
		return
	_begin_hit_out()


## Commits to the leap immediately, exactly like _begin_aggressive_mark —
## same _pending_jump hand-off into the existing gravity integration, no
## separate arc code (design brief: "reuse the existing aggressive-mark
## jump impulse pattern... let the existing gravity integration handle the
## jump arc").
func _begin_hit_out() -> void:
	_pending_jump = true
	_begin(Tuning.Action.HIT_OUT)


## Fires at the jump's contact instant, same timing as an aggressive mark's
## own resolution (Tuning.ACTION_CONTACT — HIT_OUT copies MARK_AGGRESSIVE's
## row verbatim, see Tuning's comment there). A palm, not a catch: knocks
## the ball away rather than gathering it, same knock() primitive spoil/
## smother already use for "an external hit that doesn't take control".
## Facing-directed — a tap has no separate aim source the way a kick does.
func _resolve_hit_out() -> void:
	var ball := _live_ball()
	var connected := is_instance_valid(ball) and not ball.is_held \
		and ball.global_position.distance_to(_carry_point.global_position) <= Tuning.RUCK_HIT_OUT_REACH
	if connected:
		var direction := -global_transform.basis.z
		ball.knock(direction * Tuning.RUCK_HIT_OUT_SPEED + Vector3.UP * Tuning.RUCK_HIT_OUT_UP_SPEED)
	hit_out_resolved.emit(self, connected)


## The one ball in the scene, found by group rather than a wired reference —
## every mode's Ball adds itself to the "ball" group (see Ball._ready()), so
## this needs no per-mode setup the way AIBrain.ball does.
func _live_ball() -> Ball:
	var nodes := get_tree().get_nodes_in_group(&"ball")
	return nodes[0] as Ball if not nodes.is_empty() else null


# ── Disposal ─────────────────────────────────────────────────────────

## LT-hold-stance / RT-tap-execute (design brief's CONTROLS section), not
## the old single-button hold-then-release-to-fire: wants_kick() (LT) only
## ever charges and aims; wants_kick_execute() (RT) is the one thing that
## actually fires the kick. Releasing LT without ever tapping RT cancels —
## no kick, charge discarded — where the old model would have fired on
## release regardless.
##
## RT on its own (never having held LT this attempt) doesn't no-op any
## more — it hip-fires: whatever the body's facing, fixed power, extra
## scatter. Matches P1's actual structure for the aimed case (LT/enter_
## aim_mode gates the aim cursor there too, confirmed by re-reading it —
## this was never meant to lose that gate); the hip-fire option itself has
## no P1 equivalent, it's this project's own ADS-vs-hip-fire addition.
func _update_charge(delta: float) -> void:
	if _action != Tuning.Action.NONE or _stun_timer > 0.0:
		_kick_trajectory.update_preview(false, Vector3.ZERO, Vector3.ZERO)
		return

	if _brain.wants_kick() and is_carrying():
		if not _charging:
			_charging = true
			# Wherever the camera/crosshair is currently pointing, not body
			# facing — see _current_look_yaw(). Camera turned toward goals
			# while still running a different line, then pull the trigger:
			# the kick starts aimed at goals, not wherever your legs
			# happened to be carrying you.
			_kick_aim_yaw = _current_look_yaw()
		var override := _brain.kick_charge_override()
		if override >= 0.0:
			# Power is wherever the trajectory line currently reaches to —
			# a gamepad's right stick sets it directly and live, not a
			# value that only ever ramps up with no way back down.
			_kick_charge = override
		elif not (_brain is HumanBrain):
			# AI has no stick/mouse to read a live position from, so it
			# keeps the original hold-duration ramp. A human on keyboard/
			# mouse gets a live, reversible read too now — see
			# _update_kick_aim(), just below, not a ramp at all any more.
			_kick_charge = minf(1.0, _kick_charge + delta / Tuning.KICK_CHARGE_TIME)
		_update_kick_aim(delta)
		if _brain.wants_kick_execute():
			_charging = false
			_begin(Tuning.Action.KICK)
	elif _charging:
		# LT released without RT — cancel, no kick.
		_charging = false
		_kick_charge = 0.0
	elif _brain.wants_kick_execute() and is_carrying():
		_hip_fire_kick = true
		_kick_charge = Tuning.KICK_HIP_FIRE_CHARGE
		# Fresh body-facing every time — deliberately _facing_yaw, not
		# _current_look_yaw(): hip-fire is specifically "didn't aim down
		# sights," so it stays tied to the body the way it always has,
		# not wherever the camera happens to be pointed. Also not whatever
		# _kick_aim_yaw was last left at by an earlier cancelled ADS
		# attempt — _kick_parameters() reads _kick_aim_yaw unconditionally,
		# so this is what actually makes a hip-fire go "wherever the
		# body's facing" rather than some stale aim.
		_kick_aim_yaw = _facing_yaw
		_begin(Tuning.Action.KICK)

	if _brain.wants_handball() and is_carrying():
		_begin(Tuning.Action.HANDBALL)
	elif _brain.wants_bounce() and is_carrying():
		_begin(Tuning.Action.BOUNCE)

	# Only the human player gets the on-screen cue — an AI doesn't need to
	# see its own aim, and it'd be a lot of idle preview updates for
	# nothing on every AI-controlled player every frame.
	if _charging and _brain is HumanBrain:
		var params := _kick_parameters(_kick_charge)
		_kick_trajectory.update_preview(true, params.origin, params.launch_velocity)
	else:
		_kick_trajectory.update_preview(false, Vector3.ZERO, Vector3.ZERO)


## Right stick (or mouse, off the same look input the camera would
## otherwise be reading — see BroadcastCamera._is_target_aiming) swings
## the aim yaw independently of where the body is facing or heading. AI
## has nothing to feed this, and no camera assigned either (see
## _current_look_yaw()'s fallback), so it simply never moves past the
## body-forward snapshot _update_charge took when stance began — exactly
## its old always-body-forward kick, unchanged by any of this.
func _update_kick_aim(delta: float) -> void:
	if not (_brain is HumanBrain):
		return
	var stick := InputManager.get_look_vector()
	var mouse := InputManager.take_mouse_look()
	_kick_aim_yaw -= stick.x * deg_to_rad(Tuning.KICK_AIM_YAW_SPEED) * delta \
		+ deg_to_rad(mouse.x)
	if InputManager.device != InputManager.Device.GAMEPAD:
		# No stick position for kick_charge_override() to read on keyboard
		# (see that function) — power comes from here instead, the same
		# per-axis split as aim yaw just above: arrow up/down is a held
		# rate (stick.y, the same vector's other axis, paced the same as
		# the hold-ramp everyone else still uses), mouse is a raw
		# per-frame delta. Both push the reach up AND down live, same
		# spirit as a gamepad's stick position — replaces holding K alone
		# auto-ramping power up with no way back down.
		_kick_charge = clampf(_kick_charge
			+ stick.y * delta / Tuning.KICK_CHARGE_TIME
			- mouse.y * Tuning.KICK_MOUSE_REACH_SENSITIVITY, 0.0, 1.0)
	_apply_aim_assist(delta)


## Where the camera (and the on-screen crosshair — see KickCrosshair,
## instantiated by whichever mode owns this scene) is currently pointing,
## flattened to yaw. What a freshly-entered aim stance snaps to instead of
## body facing — see _update_charge. Falls back to _facing_yaw with no
## camera assigned (AI, and this node under test headless — same reasoning
## HumanBrain.wish_direction's own camera fallback documents) or if the
## camera happens to be looking close enough to straight down/up that a
## flattened forward has nothing meaningful left to point along.
func _current_look_yaw() -> float:
	if not is_instance_valid(camera):
		return _facing_yaw
	var forward := -camera.global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.000001:
		return _facing_yaw
	return atan2(-forward.x, -forward.z)


## Soft pull toward the nearest teammate roughly in the aim direction — a
## per-frame blend toward their angle, not a snap-to (design brief: "not
## lock on but a small aim assist"). Ported from P1's apply_aim_assist:
## same k = min(1, STRENGTH * dt) blend fraction: dimensionless, so it
## carries over even though P1 blends a 2D screen cursor and this blends
## a yaw angle. Gamepad only, matching P1's controller-only gate — a
## mouse already points exactly where aimed, so assist would only fight
## it, and it's the stick's indirection this is actually compensating for.
func _apply_aim_assist(delta: float) -> void:
	if InputManager.device != InputManager.Device.GAMEPAD:
		return
	var target := _nearest_teammate_for_assist()
	if target == null:
		return
	var to_target := target.global_position - _boot_point.global_position
	to_target.y = 0.0
	if to_target.length_squared() < 0.0001:
		return
	var target_yaw := atan2(-to_target.x, -to_target.z)
	var k := minf(1.0, Tuning.KICK_AIM_ASSIST_STRENGTH * delta)
	_kick_aim_yaw = lerp_angle(_kick_aim_yaw, target_yaw, k)


## Nearest teammate within KICK_AIM_ASSIST_RANGE and KICK_AIM_ASSIST_CONE_
## DEG of the *current* aim direction — cone gates it to "roughly where
## you're already pointing", same spirit as P1's radius gate around the
## cursor, adapted from screen-space pixels to a world-space angle since
## there's no 2D cursor here to measure a pixel radius around.
func _nearest_teammate_for_assist() -> PlayerController:
	var aim_dir := _yaw_direction(_kick_aim_yaw)
	var cone := deg_to_rad(Tuning.KICK_AIM_ASSIST_CONE_DEG)
	var best: PlayerController = null
	var best_dist := Tuning.KICK_AIM_ASSIST_RANGE
	for node in get_tree().get_nodes_in_group(&"players"):
		var other := node as PlayerController
		if other == null or other == self or other.team != team:
			continue
		var to_other := other.global_position - global_position
		to_other.y = 0.0
		var dist := to_other.length()
		if dist < 0.01 or dist > best_dist:
			continue
		if aim_dir.angle_to(to_other.normalized()) > cone:
			continue
		best_dist = dist
		best = other
	return best


func is_kick_aiming() -> bool:
	return _charging


## True from the moment a KICK's swing begins until the ball actually
## leaves at its contact instant — see _try_smother, which reads this
## alongside is_kick_aiming() to find a target whose kick can still be
## blocked.
func is_mid_kick_swing() -> bool:
	return _action == Tuning.Action.KICK and not _action_fired


func is_mark_readying() -> bool:
	return _mark_readying


func protected_seconds() -> float:
	return _protected_timer


func _yaw_direction(yaw: float) -> Vector3:
	return Vector3(-sin(yaw), 0.0, -cos(yaw))


func _begin(action: Tuning.Action) -> void:
	if _action != Tuning.Action.NONE:
		return
	if action == Tuning.Action.HANDBALL:
		# "Toward wherever Left stick is currently held" (CONTROLS section),
		# captured now rather than at _dispose()'s later contact time, and
		# falling back to body-forward if the stick is neutral at the
		# instant of the press.
		_handball_aim_dir = _wish_dir if _wish_dir.length_squared() > 0.0001 \
			else -global_transform.basis.z
	_action = action
	_action_elapsed = 0.0
	_action_fired = false
	_animation.play_action(action)
	action_started.emit(action)


## Disposal fires partway through its animation, not at the start and not
## at the end — the boot meets the ball when the boot meets the ball.
## Right now the contact instant is a constant that the placeholder
## animation is generated to match; once real Mixamo animations land, it
## becomes a call track on the animation itself and these constants go
## away. The rest of this function does not change either way.
func _update_action(delta: float) -> void:
	if _action == Tuning.Action.NONE:
		return
	_action_elapsed += delta

	var contact := Tuning.action_contact_time(_action)
	if not _action_fired and _action_elapsed >= contact:
		_action_fired = true
		match _action:
			Tuning.Action.MARK_AGGRESSIVE:
				_resolve_aggressive_mark()
			Tuning.Action.HIT_OUT:
				_resolve_hit_out()
			Tuning.Action.MARK_SAFE, Tuning.Action.MARK_RUNNING, \
					Tuning.Action.MARK_SAFE_MISS, Tuning.Action.MARK_RUNNING_MISS:
				pass   # already resolved in _update_marking(); this leg is cosmetic only
			_:
				_dispose()

	if _action_elapsed >= Tuning.action_duration(_action):
		_action = Tuning.Action.NONE
		_action_elapsed = 0.0


## Shared elevation/speed -> direction/launch_velocity math every
## disposal action goes through, so kicks, handballs and bounces can't
## quietly diverge in how "how hard, how high" becomes a velocity.
## `horizontal_dir` is the caller's aim source made explicit (kick: the
## free-aim yaw; handball: wherever the stick was held; bounce: body
## facing) — this function no longer assumes body-forward itself, so it
## can't quietly default to the wrong source for whichever action is
## calling it.
func _launch_from(origin: Vector3, horizontal_dir: Vector3, elevation_deg: float,
		speed_out: float) -> Dictionary:
	var elevation := deg_to_rad(elevation_deg)
	var direction := (horizontal_dir * cos(elevation) + Vector3.UP * sin(elevation)).normalized()

	# Carry the player's own momentum into the ball, the way it actually
	# works — a kick on the run goes further than the same kick standing.
	var carried_momentum := Vector3(velocity.x, 0.0, velocity.z) \
		* Tuning.DISPOSAL_MOMENTUM_TRANSFER
	return {
		"origin": origin,
		"launch_velocity": direction * speed_out + carried_momentum,
	}


## The exact KICK launch a release at `charge` (0..1) would produce, sans
## accuracy error — the aimed path, not the executed one. Called both by
## the on-screen trajectory cue (every frame while charging, see
## _update_charge) and by _dispose() (once, at execute) so the two can
## never disagree about what "the aim" actually is. Direction comes from
## _kick_aim_yaw, not body facing — see _update_kick_aim.
func _kick_parameters(charge: float) -> Dictionary:
	var elevation_deg := lerpf(Tuning.KICK_MIN_ANGLE, Tuning.KICK_MAX_ANGLE, charge)
	var speed_out := lerpf(Tuning.KICK_MIN_SPEED, Tuning.KICK_MAX_SPEED, charge) * kick_power_scale
	return _launch_from(_boot_point.global_position, _yaw_direction(_kick_aim_yaw),
		elevation_deg, speed_out)


## Rotates the whole resultant launch vector (aim + carried momentum
## together) by a random amount rather than re-deriving it, so a spread
## kick goes off-line, not further or shorter. Shared by the two things
## that make a kick less than pinpoint — skill (_apply_kick_accuracy) and
## not having aimed down sights at all (the hip-fire spread in
## _dispose()) — so neither can quietly drift out of sync with the other
## about what "how far off" actually means.
func _apply_spread(launch: Dictionary, right: Vector3, spread_deg: float) -> Dictionary:
	if spread_deg <= 0.0:
		return launch
	var spread := deg_to_rad(spread_deg)
	launch.launch_velocity = (launch.launch_velocity as Vector3) \
		.rotated(Vector3.UP, randf_range(-spread, spread)) \
		.rotated(right, randf_range(-spread, spread) * 0.5)
	return launch


## Random aim error from the character's own skill, rolled fresh here
## rather than while charging — the trajectory cue can't show it because
## it isn't knowable ahead of the actual kick. Zero at kick_accuracy ==
## 1.0, up to KICK_ACCURACY_MAX_SPREAD_DEG at 0.0.
func _apply_kick_accuracy(launch: Dictionary, right: Vector3) -> Dictionary:
	var spread_deg := Tuning.KICK_ACCURACY_MAX_SPREAD_DEG \
		* (1.0 - clampf(kick_accuracy, 0.0, 1.0))
	return _apply_spread(launch, right, spread_deg)


func _dispose() -> void:
	if not is_carrying():
		_kick_charge = 0.0
		return

	var ball := _carried_ball
	var right := global_transform.basis.x

	var launch: Dictionary
	var spin: Vector3

	match _action:
		Tuning.Action.KICK:
			launch = _kick_parameters(_kick_charge)
			# Backspin: the top of the ball travels backwards, which for a
			# ball moving along `forward` is a positive spin about `right`.
			spin = right * Tuning.KICK_BACKSPIN
			launch = _apply_kick_accuracy(launch, right)
			if _hip_fire_kick:
				launch = _apply_spread(launch, right, Tuning.KICK_HIP_FIRE_SPREAD_DEG)
			_hip_fire_kick = false
		Tuning.Action.HANDBALL:
			launch = _launch_from(_carry_point.global_position, _handball_aim_dir,
				Tuning.HANDBALL_ANGLE, Tuning.HANDBALL_SPEED)
			spin = right * Tuning.HANDBALL_SPIN
		Tuning.Action.BOUNCE:
			launch = _launch_from(_carry_point.global_position, -global_transform.basis.z,
				Tuning.BOUNCE_ANGLE, Tuning.BOUNCE_SPEED)
			spin = right * Tuning.HANDBALL_SPIN
		_:
			return

	var origin: Vector3 = launch.origin
	var launch_velocity: Vector3 = launch.launch_velocity
	var flight := launch_velocity.normalized()

	# Placed while the ball is still frozen, then launched — a rigid body
	# should not be teleported once it is awake. Pointing the long axis
	# along the flight path matters because the hull is a spheroid: how
	# the ball is oriented on the way down changes how it lands.
	var up_reference := Vector3.UP if absf(flight.y) < 0.98 else Vector3.FORWARD
	ball.global_transform = Transform3D(Basis.looking_at(-flight, up_reference), origin)
	ball.launch(launch_velocity, launch_velocity.length(), spin, self, _action == Tuning.Action.KICK)

	_carried_ball = null
	_carry_distance = 0.0
	_gather_cooldown = Tuning.GATHER_COOLDOWN
	_protected_timer = 0.0   # playing on forfeits stand-the-mark protection
	_release_frozen_opponents()
	if _action != Tuning.Action.BOUNCE:
		MatchState.possession = Tuning.Team.NONE
	if _brain is HumanBrain:
		InputManager.rumble(Tuning.RUMBLE_KICK)
	ball_disposed.emit(_action)
	_kick_charge = 0.0
