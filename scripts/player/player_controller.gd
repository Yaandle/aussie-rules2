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

## Unit XZ direction the body is actually travelling. Kept as state
## rather than re-derived from velocity every frame so it survives a
## complete stop — you keep facing where you were going.
var _heading := Vector3.FORWARD
var _wish_dir := Vector3.ZERO
var _speed := 0.0
var _facing_yaw := 0.0

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
	# scene do not share a mutated resource.
	var reach := SphereShape3D.new()
	reach.radius = Tuning.GATHER_RADIUS
	($GatherZone/CollisionShape3D as CollisionShape3D).shape = reach


func set_brain(brain: PlayerBrain) -> void:
	_brain = brain


func _physics_process(delta: float) -> void:
	_brain.update(self, delta)

	_gather_cooldown = maxf(0.0, _gather_cooldown - delta)
	_stun_timer = maxf(0.0, _stun_timer - delta)

	_update_charge(delta)
	_update_action(delta)

	if is_on_floor():
		velocity.y = -0.5   # a little bite into the floor keeps is_on_floor stable
	else:
		velocity.y -= Tuning.GRAVITY * delta

	_update_locomotion(delta)

	var before := global_position
	move_and_slide()
	_push_rigid_bodies()
	_contain_to_field()

	_update_facing(delta)
	_track_carry_distance(before)
	_try_gather()
	_try_tackle()

	_animation.drive(locomotion_blend(), delta)


# ── Locomotion ───────────────────────────────────────────────────────

func _update_locomotion(delta: float) -> void:
	var wish := _brain.wish_direction(self)
	var gait := 0.0 if _stun_timer > 0.0 else _brain.gait()

	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	_speed = horizontal.length()
	if _speed > Tuning.PIVOT_SPEED_THRESHOLD:
		_heading = horizontal / _speed

	var target_speed := 0.0
	if wish.length_squared() > 0.000001:
		_wish_dir = wish.normalized()

		# From a near standstill there is no momentum to fight, so the
		# heading just snaps to intent. Without this a player stopped
		# facing north who presses south would compute a target speed of
		# zero forever and never get moving.
		if _speed <= Tuning.PIVOT_SPEED_THRESHOLD:
			_heading = _wish_dir

		# How much of your requested speed you get, given how far off your
		# current momentum it is. Dead ahead is full, square across is
		# half, straight back is REVERSE_SPEED_SCALE.
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

	# Planting to kick or handball costs you your legs for a moment; the
	# kick stance ahead of that (LT held, still aiming/repositioning) costs
	# less, same relationship as ADS-walk vs. firing in a shooter.
	if _action != Tuning.Action.NONE:
		target_speed *= Tuning.ACTION_SPEED_SCALE
	elif _charging:
		target_speed *= Tuning.KICK_STANCE_SPEED_SCALE

	var accel := Tuning.ACCELERATION if target_speed > _speed else Tuning.BRAKING
	if not is_on_floor():
		accel = Tuning.AIR_ACCELERATION
	_speed = move_toward(_speed, target_speed, accel * delta)

	velocity.x = _heading.x * _speed
	velocity.z = _heading.z * _speed


func _update_facing(delta: float) -> void:
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


func _try_gather() -> void:
	if is_carrying() or _gather_cooldown > 0.0 or _action != Tuning.Action.NONE \
			or _stun_timer > 0.0:
		return
	for body in _gather_zone.get_overlapping_bodies():
		if not (body is Ball):
			continue
		var ball := body as Ball
		if ball.is_held:
			continue
		if ball.linear_velocity.length() > Tuning.GATHER_MAX_BALL_SPEED:
			continue
		ball.attach_to(_carry_point, self)
		_carried_ball = ball
		_carry_distance = 0.0
		MatchState.possession = team
		if _brain is HumanBrain:
			InputManager.rumble(Tuning.RUMBLE_GATHER)
		ball_gathered.emit(ball)
		return


# ── Contests ─────────────────────────────────────────────────────────
# Design doc §5: a tackle is decided by getting into range and timing it,
# not by a dice roll. No holding-the-ball adjudication yet (free kick vs
# ball-up) — see RULES_REFERENCE.md §4 — a successful tackle always spills
# the ball loose for a fresh contest.

func _try_tackle() -> void:
	if is_carrying() or _stun_timer > 0.0 or _action != Tuning.Action.NONE:
		return
	if not _brain.wants_tackle():
		return
	for node in get_tree().get_nodes_in_group(&"players"):
		var other := node as PlayerController
		if other == null or other == self or other.team == team:
			continue
		if not other.is_carrying():
			continue
		if global_position.distance_to(other.global_position) > Tuning.TACKLE_RADIUS:
			continue
		other._get_tackled(self)
		return


## Called on the tackled player, by the tackler.
func _get_tackled(by: PlayerController) -> void:
	var ball := _carried_ball
	drop_ball()
	_stun_timer = Tuning.TACKLE_STUN_DURATION
	_action = Tuning.Action.NONE
	_action_elapsed = 0.0
	_action_fired = false
	if is_instance_valid(ball):
		var scatter := global_position - by.global_position
		scatter.y = 0.0
		scatter = scatter.normalized() if scatter.length_squared() > 0.0001 else Vector3.FORWARD
		ball.apply_central_impulse(scatter * Tuning.TACKLE_SPILL_SPEED * ball.mass)


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
			_kick_aim_yaw = _facing_yaw
		var override := _brain.kick_charge_override()
		if override >= 0.0:
			# Power is wherever the trajectory line currently reaches to —
			# a gamepad's right stick sets it directly and live, not a
			# value that only ever ramps up with no way back down.
			_kick_charge = override
		else:
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
		# Fresh body-facing every time, not whatever _kick_aim_yaw was last
		# left at by an earlier cancelled ADS attempt — _kick_parameters()
		# reads _kick_aim_yaw unconditionally, so this is what actually
		# makes a hip-fire go "wherever the body's facing" rather than
		# some stale aim.
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
## the aim yaw independently of where the body is facing or heading.
## AI has nothing to feed this, so it simply never moves past the
## body-forward snapshot _update_charge took when stance began — which is
## exactly its old always-body-forward kick, just captured a moment
## earlier now.
func _update_kick_aim(delta: float) -> void:
	if not (_brain is HumanBrain):
		return
	var stick := InputManager.get_look_vector()
	var mouse := InputManager.take_mouse_look()
	_kick_aim_yaw -= stick.x * deg_to_rad(Tuning.KICK_AIM_YAW_SPEED) * delta \
		+ deg_to_rad(mouse.x)
	_apply_aim_assist(delta)


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
	ball.launch(launch_velocity, launch_velocity.length(), spin, self)

	_carried_ball = null
	_carry_distance = 0.0
	_gather_cooldown = Tuning.GATHER_COOLDOWN
	if _action != Tuning.Action.BOUNCE:
		MatchState.possession = Tuning.Team.NONE
	if _brain is HumanBrain:
		InputManager.rumble(Tuning.RUMBLE_KICK)
	ball_disposed.emit(_action)
	_kick_charge = 0.0
