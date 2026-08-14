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

## Set by whatever owns the view — movement is camera-relative, as every
## third-person game's is. Left null the player still works, just in
## world axes, which keeps this node testable headless.
var camera: Node3D = null

@onready var _animation: PlayerAnimation = $PlayerAnimation
@onready var _carry_point: Marker3D = $CarryPoint
@onready var _boot_point: Marker3D = $BootPoint
@onready var _gather_zone: Area3D = $GatherZone

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

	# Planting to kick or handball costs you your legs for a moment.
	if _action != Tuning.Action.NONE:
		target_speed *= Tuning.ACTION_SPEED_SCALE

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

func _update_charge(delta: float) -> void:
	if _action != Tuning.Action.NONE or _stun_timer > 0.0:
		return
	if _brain.wants_kick() and is_carrying():
		_charging = true
		_kick_charge = minf(1.0, _kick_charge + delta / Tuning.KICK_CHARGE_TIME)
	elif _charging:
		_charging = false
		if is_carrying():
			_begin(Tuning.Action.KICK)
		else:
			_kick_charge = 0.0

	if _brain.wants_handball() and is_carrying():
		_begin(Tuning.Action.HANDBALL)
	elif _brain.wants_bounce() and is_carrying():
		_begin(Tuning.Action.BOUNCE)


func _begin(action: Tuning.Action) -> void:
	if _action != Tuning.Action.NONE:
		return
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


func _dispose() -> void:
	if not is_carrying():
		_kick_charge = 0.0
		return

	var ball := _carried_ball
	var forward := -global_transform.basis.z
	var right := global_transform.basis.x

	var origin: Vector3
	var elevation: float
	var speed_out: float
	var spin: Vector3

	match _action:
		Tuning.Action.KICK:
			origin = _boot_point.global_position
			elevation = deg_to_rad(lerpf(
				Tuning.KICK_MIN_ANGLE, Tuning.KICK_MAX_ANGLE, _kick_charge))
			speed_out = lerpf(Tuning.KICK_MIN_SPEED, Tuning.KICK_MAX_SPEED, _kick_charge)
			# Backspin: the top of the ball travels backwards, which for a
			# ball moving along `forward` is a positive spin about `right`.
			spin = right * Tuning.KICK_BACKSPIN
		Tuning.Action.HANDBALL:
			origin = _carry_point.global_position
			elevation = deg_to_rad(Tuning.HANDBALL_ANGLE)
			speed_out = Tuning.HANDBALL_SPEED
			spin = right * Tuning.HANDBALL_SPIN
		Tuning.Action.BOUNCE:
			origin = _carry_point.global_position
			elevation = deg_to_rad(Tuning.BOUNCE_ANGLE)
			speed_out = Tuning.BOUNCE_SPEED
			spin = right * Tuning.HANDBALL_SPIN
		_:
			return

	var direction := (forward * cos(elevation) + Vector3.UP * sin(elevation)).normalized()

	# Carry the player's own momentum into the ball, the way it actually
	# works — a kick on the run goes further than the same kick standing.
	var carried_momentum := Vector3(velocity.x, 0.0, velocity.z) \
		* Tuning.DISPOSAL_MOMENTUM_TRANSFER
	var launch_velocity := direction * speed_out + carried_momentum
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
