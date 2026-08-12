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


func _ready() -> void:
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
	_was_airborne = airborne


## Aerodynamics. Applied here rather than in _physics_process so the
## forces land inside the same integration step Jolt is about to run.
func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	var v := state.linear_velocity
	var speed := v.length()
	if speed < 0.05:
		return

	# F_drag = -0.5 * rho * Cd * A * |v| * v, with the constants folded
	# into BALL_DRAG_COEFF.
	state.apply_central_force(-v * speed * Tuning.BALL_DRAG_COEFF)

	# F_magnus = S * (omega x v). Zero when the ball is not spinning, so
	# a shanked wobbler is unaffected and a clean torpedo holds its line.
	var omega := state.angular_velocity
	if omega.length_squared() > 0.01:
		state.apply_central_force(omega.cross(v) * Tuning.BALL_MAGNUS_COEFF)


## Send the ball. `direction` need not be normalised.
func launch(direction: Vector3, speed: float, spin: Vector3, from: Node3D = null) -> void:
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


func is_airborne() -> bool:
	return not is_held and global_position.y > Tuning.BALL_SEMI_MINOR * 2.5


func is_settled() -> bool:
	return not is_held and (sleeping or linear_velocity.length() < Tuning.BALL_SLEEP_SPEED)


func reset_at(position: Vector3) -> void:
	detach()
	if is_instance_valid(_carrier):
		remove_collision_exception_with(_carrier)
	_carrier = null
	_release_grace = 0.0
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
