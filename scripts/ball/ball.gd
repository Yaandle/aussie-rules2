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

## "Not available to be played" rather than literally "in a player's
## hands" — a carrier is holding it, and so is the umpire before a
## throw-up (see lock_at()). Every reader of this wants the same answer in
## both cases: no gathering it, not airborne, not settled out of bounds,
## not markable.
var is_held: bool:
	get:
		return _carry_point != null or _locked or _unplayable

## True between the umpire picking the ball up for a stoppage and actually
## throwing it. See lock_at()/lock_to()/unlock(). `_lock_point` is set only
## by lock_to(): the ball then rides that node every frame, which is what
## puts it in the umpire's hands through the whole throw-up rather than
## hovering at the spot in front of him.
var _locked := false
var _lock_point: Node3D = null
var _lock_position := Vector3.ZERO

## "Dead, but let it finish travelling" — set after a goal/behind so the
## ball flies through the posts under its own physics (real, not frozen
## on the line) while still counting as is_held: nobody gathers or marks
## it, and FullGame's out-of-bounds watch ignores it, during the
## celebration. Unlike _locked it does NOT pin the transform. Cleared by
## the next thing that puts the ball anywhere — unlock()/lock_at()/
## attach_to() all reset it.
var _unplayable := false

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

## Set true only by a launch() from a HANDBALL disposal — the "is this
## flight a handball" state LandingShadow reads to hide its cue for one
## (a handball can never be marked, so the "where's this about to come
## down" shadow reads as a false marking promise there — playtest report:
## "the marking cue appears even if it is a handball"). Cleared on
## knock()/landing/gather same as _is_kick_flight: once touched or settled
## it's just a loose ball again, not specifically "a handball in flight".
var _is_handball_flight := false

## Set true only by a launch() from a manual BOUNCE disposal (see
## PlayerController._dispose). While true, _physics_process scripts one
## clean rebound off the turf instead of trusting the prolate hull, which
## scrubs a steep nose-first strike to near-nothing at random — fine for a
## loose ball, wrong for a bounce the carrier is meant to run onto.
## Cleared the instant that rebound is applied (or on gather/reset).
var _is_bounce_flight := false
var _bounce_rebounded := false

## Who launched the current flight — separate from `_carrier` above, which
## exists for a different purpose (the collision-exception the launcher
## needs so the ball doesn't immediately foul their own body) and is
## deliberately wiped to null once _release_grace elapses (see
## _physics_process). `_last_disposer` is set the same moment but never
## auto-clears, so last_disposer() below still answers correctly for the
## rest of the flight — this used to just read _carrier directly, which
## meant it silently went back to "nobody" a fraction of a second into
## every kick, right when Tuning.MARK_SELF_CLEAR_DISTANCE/self-catch-
## gravity-exclusion actually needed to know.
var _last_disposer: Node3D = null

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

	# Held by an official rather than carried by a player — see lock_at()/
	# lock_to(). Pinned by hand every frame rather than by freezing the
	# body: freezing works, but coming *out* of it in the same frame the
	# launch velocity is assigned loses that velocity (the body is still
	# kinematic when the assignment lands), which is exactly what a
	# throw-up does. Re-pinning position and zeroing velocity has the same
	# effect — nothing can nudge it, since any nudge is undone the same
	# frame — with no freeze transition to get wrong.
	if _locked:
		if is_instance_valid(_lock_point):
			_lock_position = _lock_point.global_position
		global_position = _lock_position
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
		return

	# Manual bounce: script one clean rebound off the turf rather than let
	# the prolate hull scrub it flat (see _is_bounce_flight). The first
	# frame this flight is back down near the ground and still falling, set
	# a deterministic upward speed and keep whatever horizontal it earned,
	# so the carrier runs onto a hands-high rebound every time instead of a
	# random dribbler. Same "scripted assist layered on the real sim" shape
	# as _apply_catch_gravity below.
	if _is_bounce_flight and not _bounce_rebounded and linear_velocity.y < 0.0 \
			and global_position.y <= Tuning.BOUNCE_REBOUND_HEIGHT:
		_bounce_rebounded = true
		_is_bounce_flight = false
		# Forward speed follows the bouncer, who keeps running through a
		# bounce now (Tuning's "Bouncing at pace"): MATCH of their own pace
		# along the bounce plus a little LEAD, so it comes up just ahead of
		# them while they close on it gently at any speed. A fixed cap
		# could only suit one pace, and an 11 m/s sprinter ran straight
		# into a 3.8 m/s ball at thigh height. Without a bouncer to read,
		# it keeps a cut of its own speed, capped (the old rule).
		var horizontal := Vector3(linear_velocity.x, 0.0, linear_velocity.z)
		var bouncer := _last_disposer as CharacterBody3D
		if is_instance_valid(bouncer) and horizontal.length_squared() > 0.0001:
			var along := maxf(0.0, Vector3(bouncer.velocity.x, 0.0, bouncer.velocity.z).dot(horizontal.normalized()))
			horizontal = horizontal.normalized() * (along * Tuning.BOUNCE_REBOUND_MATCH + Tuning.BOUNCE_REBOUND_LEAD)
		else:
			horizontal = (horizontal * Tuning.BOUNCE_REBOUND_KEEP).limit_length(Tuning.BOUNCE_REBOUND_MAX_AHEAD)
		linear_velocity = Vector3(horizontal.x, Tuning.BOUNCE_REBOUND_UP_SPEED, horizontal.z)

	# One-shot "it came down" notice, for camera framing and audio later.
	var airborne := is_airborne()
	if _was_airborne and not airborne:
		landed.emit(linear_velocity.length())
		# Touched down without being marked — no longer a live mark chance,
		# same as a kick that bounces before anyone takes it in real AFL.
		_is_kick_flight = false
		_is_handball_flight = false
		# A rebounded bounce that comes back down untaken is just a loose
		# ball now (see awaiting_own_bounce).
		_bounce_rebounded = false
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


## Excludes the disposer of THIS flight while it's still within
## Tuning.MARK_SELF_CLEAR_DISTANCE of where they let it go (same window
## PlayerController._mark_attempt_blocked() gates the prompt/attempt on —
## see its own comment). Without this, a kicker is trivially the nearest
## uncontested player to their own kick for the first instant of its
## flight, so this force was actively pulling their own ball straight back
## toward them — not just a UI/prompt bug, a genuine physical drift back
## into the kicker's hands that the distance/time gates elsewhere couldn't
## fix on their own, since the ball never actually got anywhere for those
## gates to measure.
func _nearest_uncontested_catcher() -> PlayerController:
	var best: PlayerController = null
	var best_dist := Tuning.CATCH_GRAVITY_RADIUS
	# PlayerRegistry, not a per-frame get_nodes_in_group scan — this runs
	# every physics tick the ball is airborne (docs/MECHANICS_AUDIT.md A1).
	# Keeps its own 3D distance: the ball has real height here and catch
	# reach is a sphere, unlike SpatialQuery's ground-plane queries.
	for player in PlayerRegistry.all():
		if player.is_carrying():
			continue
		if player == _last_disposer and distance_since_launch() < Tuning.MARK_SELF_CLEAR_DISTANCE:
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
		is_kick_disposal: bool = false, is_bounce: bool = false,
		is_handball: bool = false) -> void:
	unlock()
	detach()
	if from != null:
		# Usually already excluded from carrying it; only swap if the ball
		# is being struck by someone who was not holding it.
		if _carrier != from:
			if is_instance_valid(_carrier):
				remove_collision_exception_with(_carrier)
			_carrier = from
			add_collision_exception_with(from)
		# A bounce is run onto, so the bouncer's legs would otherwise kick
		# it on the way back up (Tuning's "Bouncing at pace").
		_release_grace = Tuning.BOUNCE_RELEASE_GRACE if is_bounce else Tuning.RELEASE_GRACE
	_last_disposer = from
	freeze = false
	sleeping = false
	linear_velocity = direction.normalized() * speed
	angular_velocity = spin
	_was_airborne = is_airborne()
	_is_kick_flight = is_kick_disposal
	_is_bounce_flight = is_bounce
	_is_handball_flight = is_handball
	_bounce_rebounded = false
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
	_is_bounce_flight = false
	_is_handball_flight = false
	_kick_team = Tuning.Team.NONE
	if is_instance_valid(_carrier) and _carrier != holder:
		remove_collision_exception_with(_carrier)
	_carrier = holder
	_release_grace = 0.0
	_unplayable = false
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


## True while this is still an uninterrupted handball flight — read by
## LandingShadow to hide its landing cue for one (see that flag's own doc
## comment on _is_handball_flight for why: a handball can never be marked,
## so a "where's this about to come down, go judge the mark" shadow on one
## is a false promise).
func is_handball_flight() -> bool:
	return _is_handball_flight and not is_held


## Straight-line distance from wherever this flight was launched — set by
## launch() on every disposal, not just a kick, so this reads sensibly for
## a handball/bounce too. Used by PlayerController to gate an Aggressive
## mark attempt on the ball actually having gone somewhere yet (see
## Tuning.MARK_AGGRESSIVE_MIN_FLIGHT_DISTANCE) rather than reusing
## is_mark_eligible()'s much larger MARK_STAND_MIN_DISTANCE, which is a
## legality threshold, not a "has this even left the boot" one. 0.0 while
## held, same "no flight in progress" convention is_mark_eligible() uses.
func distance_since_launch() -> float:
	if is_held:
		return 0.0
	return global_position.distance_to(_flight_origin)


## True while this is `player`'s own manual bounce and it isn't back up for
## them yet: still going into the turf, or rebounded but below
## Tuning.BOUNCE_REGATHER_HEIGHT and still rising. A bounce has to touch the
## ground, and taking it straight off the turf read as the ball snapping up
## from the shins. PlayerController._try_gather skips it until then, in
## place of the usual GATHER_COOLDOWN (Tuning's "Bouncing at pace").
func awaiting_own_bounce(player: Node3D) -> bool:
	if player != _last_disposer or is_held:
		return false
	if _is_bounce_flight:
		return true
	return _bounce_rebounded and global_position.y < Tuning.BOUNCE_REGATHER_HEIGHT \
		and linear_velocity.y > 0.0


## Whoever most recently launched this flight (see `_last_disposer`'s own
## comment for why this isn't just `_carrier`). Used by PlayerController.
## _mark_attempt_blocked() and this file's own _nearest_uncontested_
## catcher() to gate a player re-marking (or catch-gravity re-pulling) their
## own very-recent disposal, without blocking anyone else's live attempt on
## the same ball.
func last_disposer() -> Node3D:
	return _last_disposer


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
	_is_handball_flight = false
	_kick_team = Tuning.Team.NONE
	apply_central_impulse(impulse)


## Held out of play at `position` until unlock() — the umpire has it. The
## ball is pinned there every physics frame (see _physics_process) rather
## than left as a settled rigid body, because a rigid body sitting on the
## turf can still be nudged by a player running over it, and is_held above
## keeps anyone from gathering, marking or hit-outing it in the meantime.
## Playtest report: players were grabbing the ball off the ground before
## the umpire had thrown it up.
func lock_at(position: Vector3) -> void:
	detach()
	if is_instance_valid(_carrier):
		remove_collision_exception_with(_carrier)
	_carrier = null
	_release_grace = 0.0
	_is_kick_flight = false
	_is_bounce_flight = false
	_is_handball_flight = false
	_kick_team = Tuning.Team.NONE
	freeze = false
	sleeping = false
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	global_transform = Transform3D(Basis.IDENTITY, position)
	_locked = true
	_unplayable = false
	_lock_point = null
	_lock_position = position


## Held out of play in `point`'s hands, riding it every frame — the
## umpire's grip through a throw-up. Same "not available to be played"
## state lock_at() gives, just following something instead of sitting
## still. Deliberately not attach_to(): that one is for a PLAYER carrying
## the ball and adds a collision exception with the carrier's own body,
## which an umpire hasn't got (see Umpire's class doc — officials have no
## collision at all).
func lock_to(point: Node3D) -> void:
	lock_at(point.global_position)
	_lock_point = point


## Back into play. Both reset_at() and launch() call this themselves, so a
## lock can never outlive the next thing that puts the ball anywhere —
## there is no call site that has to remember to unlock.
func unlock() -> void:
	_locked = false
	_unplayable = false
	_lock_point = null


## See _unplayable. After a goal/behind FullGame calls this instead of
## lock_at() so the ball keeps its trajectory through the posts while
## still being un-gatherable for the celebration.
func set_unplayable(on: bool) -> void:
	_unplayable = on


func reset_at(position: Vector3) -> void:
	unlock()
	detach()
	if is_instance_valid(_carrier):
		remove_collision_exception_with(_carrier)
	_carrier = null
	_release_grace = 0.0
	_is_kick_flight = false
	_is_bounce_flight = false
	_is_handball_flight = false
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
