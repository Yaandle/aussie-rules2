class_name Ball
extends RigidBody3D

## The football, simulated for real (design doc §5).
##
## Prototype 1's ball was a scripted lerp along a flight path with a
## cosmetic two-hop bounce bolted onto the landing, and every outcome was
## decided the instant the lerp finished. Nothing about it was physical.
## This one is a RigidBody3D: a kick is an impulse, the arc is drag and
## gravity, and where it ends up is wherever it ends up.
##
## Three things do most of the work of making it read as a football
## rather than a beach ball:
##   1. A prolate-spheroid convex hull, not a sphere. The erratic bounce
##      off a pointed end is the single most recognisable thing a footy
##      does, and it falls straight out of the collision shape.
##   2. Quadratic air drag. Linear damping makes a kick look like it is
##      moving through syrup; v^2 drag gives the real asymmetric arc —
##      lazy up, steep down.
##   3. Magnus force, so spin actually curves the flight.

signal gathered(by: Node3D)
signal landed(speed: float)

## Hull resolution. Higher is smoother; the erratic bounce comes from the
## shape being an ellipsoid, not from the facets, so this only needs to be
## fine enough that it does not visibly bounce off a corner.
const HULL_RINGS := 8
const HULL_SEGMENTS := 14

@onready var _collision: CollisionShape3D = $CollisionShape3D
@onready var _mesh: MeshInstance3D = $MeshInstance3D

var is_held: bool:
	get:
		return _carry_point != null

var _carry_point: Node3D = null
var _carrier: Node3D = null
var _release_grace := 0.0
var _was_airborne := false

## Set true only by a launch() that came off a KICK disposal, and cleared
## the instant the ball touches down or is gathered — the live "is this
## still an uninterrupted kick flight" state is_mark_eligible() reads.
## Handballs/bounces/hit-outs never set this, so they can never be marked,
## same as real AFL.
var _is_kick_flight := false
var _flight_origin := Vector3.ZERO

## Which team kicked the ball currently in flight — set alongside
## _is_kick_flight, read by whoever adjudicates "out on the full"
## (RULES_REFERENCE.md §4: a free kick to the *other* side). Meaningless
## whenever _is_kick_flight is false; not eagerly read in that case.
var _kick_team: Tuning.Team = Tuning.Team.NONE


func _ready() -> void:
	add_to_group(&"ball")
	mass = Tuning.BALL_MASS
	continuous_cd = true
	can_sleep = true
	contact_monitor = false
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = Tuning.BALL_LINEAR_DAMP
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp = Tuning.BALL_ANGULAR_DAMP

	var material := PhysicsMaterial.new()
	material.friction = Tuning.BALL_FRICTION
	material.bounce = Tuning.BALL_BOUNCE
	material.rough = true
	physics_material_override = material

	_collision.shape = _build_hull()
	_shape_mesh()


func _physics_process(delta: float) -> void:
	if _release_grace > 0.0:
		_release_grace = maxf(0.0, _release_grace - delta)
		if is_zero_approx(_release_grace) and is_instance_valid(_carrier):
			remove_collision_exception_with(_carrier)
			_carrier = null

	if _carry_point != null:
		if not is_instance_valid(_carry_point):
			detach()
			return
		global_transform = _carry_point.global_transform
		return

	# One-shot "it came down" notice, for camera framing and audio later.
	var airborne := is_airborne()
	if _was_airborne and not airborne:
		landed.emit(linear_velocity.length())
		# Touched down without being marked — no longer a live mark chance,
		# same as a kick that bounces before anyone takes it in real AFL.
		_is_kick_flight = false
		_kick_team = Tuning.Team.NONE
	_was_airborne = airborne


## Aerodynamics. Applied here rather than in _physics_process so the
## forces land inside the same integration step Jolt is about to run.
func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	var v := state.linear_velocity
	var speed := v.length()
	if speed >= 0.05:
		# F_drag = -0.5 * rho * Cd * A * |v| * v, with the constants folded
		# into BALL_DRAG_COEFF.
		state.apply_central_force(-v * speed * Tuning.BALL_DRAG_COEFF)

		# F_magnus = S * (omega x v). Zero when the ball is not spinning, so
		# a shanked wobbler is unaffected and a clean torpedo holds its line.
		var omega := state.angular_velocity
		if omega.length_squared() > 0.01:
			state.apply_central_force(omega.cross(v) * Tuning.BALL_MAGNUS_COEFF)

	_apply_catch_gravity(state)


## "Catch gravity" (user-requested marking assist): a genuine small
## attractive force toward whichever uncontested player is nearest while
## this is still in flight — a real force through the same integration
## drag/Magnus above already use, not a scripted snap onto a player.
## Strongest at point-blank range, zero at CATCH_GRAVITY_RADIUS, so it
## nudges a near-miss into a catch without visibly bending a kick's arc
## from a distance.
func _apply_catch_gravity(state: PhysicsDirectBodyState3D) -> void:
	if not is_airborne():
		return
	var puller := _nearest_uncontested_catcher()
	if puller == null:
		return
	var to_puller := puller.catch_point_position() - global_position
	var dist := to_puller.length()
	if dist < 0.05 or dist > Tuning.CATCH_GRAVITY_RADIUS:
		return
	var pull := 1.0 - dist / Tuning.CATCH_GRAVITY_RADIUS
	state.apply_central_force(to_puller.normalized() * Tuning.CATCH_GRAVITY_ACCEL * pull * mass)


func _nearest_uncontested_catcher() -> PlayerController:
	var best: PlayerController = null
	var best_dist := Tuning.CATCH_GRAVITY_RADIUS
	for node in get_tree().get_nodes_in_group(&"players"):
		var player := node as PlayerController
		if player == null or player.is_carrying():
			continue
		var dist := global_position.distance_to(player.catch_point_position())
		if dist < best_dist:
			best_dist = dist
			best = player
	return best


## Send the ball. `direction` need not be normalised. `is_kick_disposal` marks
## this flight as mark-eligible (see is_mark_eligible()) — only
## PlayerController._dispose()'s KICK branch should ever pass true; every
## other caller (handball, bounce, hit-out, the centre bounce) leaves it
## false, since none of those can ever be marked.
func launch(direction: Vector3, speed: float, spin: Vector3, from: Node3D = null,
		is_kick_disposal: bool = false) -> void:
	detach()
	if from != null:
		# Usually already excluded from carrying it; only swap if the ball
		# is being struck by someone who was not holding it.
		if _carrier != from:
			if is_instance_valid(_carrier):
				remove_collision_exception_with(_carrier)
			_carrier = from
			add_collision_exception_with(from)
		_release_grace = Tuning.RELEASE_GRACE
	freeze = false
	sleeping = false
	linear_velocity = direction.normalized() * speed
	angular_velocity = spin
	_was_airborne = is_airborne()
	_is_kick_flight = is_kick_disposal
	_flight_origin = global_position
	_kick_team = (from as PlayerController).team \
		if is_kick_disposal and from is PlayerController else Tuning.Team.NONE


## Carry the ball at `point`, following it exactly. Kept as a kinematic
## frozen body rather than reparented so it never leaves the physics
## world — the moment it is released it is already where it looks like it
## is, with no transform hand-off to get wrong.
func attach_to(point: Node3D, holder: Node3D) -> void:
	if _carry_point == point:
		return
	_carry_point = point
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	freeze = true
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	_is_kick_flight = false
	_kick_team = Tuning.Team.NONE
	if is_instance_valid(_carrier) and _carrier != holder:
		remove_collision_exception_with(_carrier)
	_carrier = holder
	_release_grace = 0.0
	add_collision_exception_with(holder)
	global_transform = point.global_transform
	gathered.emit(holder)


func detach() -> void:
	if _carry_point == null:
		return
	_carry_point = null
	freeze = false
	sleeping = false


## The current carrier, or null if the ball is loose. Distinct from
## `_carrier` staying set through the release-grace window after a
## disposal — this only reports a live hold.
func holder() -> Node3D:
	return _carrier if is_held else null


func is_airborne() -> bool:
	return not is_held and global_position.y > Tuning.BALL_SEMI_MINOR * 2.5


## Where this ball would land if gravity were the only force acting on it
## from here — ignores drag/Magnus (both real forces on the actual flight,
## see this file's own header) since this exists to steer AIBrain's
## receivers toward a sensible spot in real time, not to reproduce the
## exact physics trajectory. Standard projectile time-to-ground: solves
## y0 + vy*t - 0.5*g*t^2 = 0 for the positive root, then carries the
## current horizontal velocity for that long. Falls back to the current
## position if the ball is already on/below the ground or has no more
## downward closing (grazing along near-zero height), where the quadratic
## has no meaningful positive root.
func predicted_landing_position() -> Vector3:
	var y0 := global_position.y
	var vy := linear_velocity.y
	if y0 <= 0.0:
		return global_position
	var discriminant := vy * vy + 2.0 * Tuning.GRAVITY * y0
	if discriminant <= 0.0:
		return global_position
	var t := (vy + sqrt(discriminant)) / Tuning.GRAVITY
	var landing := global_position + Vector3(linear_velocity.x, 0.0, linear_velocity.z) * t
	landing.y = 0.0
	return landing


func is_settled() -> bool:
	return not is_held and (sleeping or linear_velocity.length() < Tuning.BALL_SLEEP_SPEED)


## True while this is still an uninterrupted kick flight that has covered
## Tuning.MARK_STAND_MIN_DISTANCE — the real AFL test for a legal mark, as
## opposed to just a good take (see PlayerController._complete_mark, which
## reads this to decide whether to grant mark protection). Distance is
## straight-line from where it left the boot: that's what a kick's
## displacement actually is, regardless of the shape of the arc it flew.
func is_mark_eligible() -> bool:
	return _is_kick_flight and not is_held \
		and global_position.distance_to(_flight_origin) >= Tuning.MARK_STAND_MIN_DISTANCE


## True while this is still an uninterrupted kick flight, with no minimum-
## distance requirement — unlike is_mark_eligible() above, which layers
## MARK_STAND_MIN_DISTANCE on top of the same _is_kick_flight flag. "Out on
## the full" (RULES_REFERENCE.md §4) has no such distance floor: a short
## kick that clears the boundary is out on the full exactly the same as a
## long one.
func is_kick_flight() -> bool:
	return _is_kick_flight and not is_held


## Which team's kick is currently in flight — Tuning.Team.NONE if this
## isn't a live, uninterrupted kick flight. Only meaningful while
## is_kick_flight() is true.
func kick_team() -> Tuning.Team:
	return _kick_team


## An external hit that doesn't control the ball — a spoil, later a bump.
## Clears mark eligibility the same way landing does (see
## is_mark_eligible()): a touched ball is no longer a clean, uninterrupted
## kick, even if it's still in the air afterward. Kept here rather than
## left to callers reaching into _is_kick_flight directly, so this
## invariant can't be forgotten at a new call site later.
func knock(impulse: Vector3) -> void:
	_is_kick_flight = false
	_kick_team = Tuning.Team.NONE
	apply_central_impulse(impulse)


func reset_at(position: Vector3) -> void:
	detach()
	if is_instance_valid(_carrier):
		remove_collision_exception_with(_carrier)
	_carrier = null
	_release_grace = 0.0
	_is_kick_flight = false
	_kick_team = Tuning.Team.NONE
	freeze = false
	sleeping = false
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	global_transform = Transform3D(Basis.IDENTITY, position)


## A prolate spheroid, long axis on local Z. Built here rather than baked
## into the scene so the two semi-axes stay single-sourced in Tuning and
## the .tscn stays readable.
func _build_hull() -> ConvexPolygonShape3D:
	var points := PackedVector3Array()
	var a := Tuning.BALL_SEMI_MAJOR
	var b := Tuning.BALL_SEMI_MINOR
	points.append(Vector3(0.0, 0.0, a))
	points.append(Vector3(0.0, 0.0, -a))
	for ring in range(1, HULL_RINGS):
		var phi := PI * float(ring) / float(HULL_RINGS)
		var z := a * cos(phi)
		var r := b * sin(phi)
		for seg in HULL_SEGMENTS:
			var theta := TAU * float(seg) / float(HULL_SEGMENTS)
			points.append(Vector3(r * cos(theta), r * sin(theta), z))
	var hull := ConvexPolygonShape3D.new()
	hull.points = points
	return hull


## The visual is a plain sphere stretched on Z — non-uniform scale is
## fine on a MeshInstance3D, and it keeps the mesh resource trivial.
func _shape_mesh() -> void:
	var stretch := Tuning.BALL_SEMI_MAJOR / Tuning.BALL_SEMI_MINOR
	_mesh.scale = Vector3(1.0, 1.0, stretch)
