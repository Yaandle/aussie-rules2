class_name KickTrajectory
extends Node3D

## On-screen cue for a charging kick: a dashed arc from the boot to where
## the ball would land if released right now, plus a landing-point ring.
## Driven by PlayerController._update_charge every frame while charging —
## see there for the origin/launch_velocity it's fed, which come from the
## same _kick_parameters() the real kick uses at release, so the cue
## never shows a path the kick itself couldn't produce.
##
## Shows the AIMED path only. Kicking Accuracy's error is rolled at the
## moment of the actual kick (PlayerController._dispose), not before, so
## there's nothing earlier to preview it with — the cue is what you're
## aiming at, not a guarantee of where it lands.
##
## Doesn't reuse Ball's real Jolt physics — simulating a second rigid
## body every frame just to throw the result away would be wasteful.
## Instead it steps the same gravity + quadratic-drag model Ball.
## _integrate_forces uses by hand (semi-implicit Euler), skipping only
## Magnus (spin curl): close enough for a UI readout, and the spin isn't
## even decided yet at this point since the ball hasn't been struck.

const MAX_DOTS := 22
const DOT_STEP_TIME := 0.05      ## s of simulated flight per dash
const DOT_RADIUS := 0.045
const RING_RADIUS := 0.5
const RING_THICKNESS := 0.07
const GROUND_HEIGHT := 0.05       ## simulation stops once the ball would be this low

const COLOUR := Color(0.95, 0.82, 0.35, 0.9)

@onready var _dots: MultiMeshInstance3D = $Dots
@onready var _ring: MeshInstance3D = $LandingRing


func _ready() -> void:
	visible = false

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = COLOUR
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	var dot_mesh := SphereMesh.new()
	dot_mesh.radius = DOT_RADIUS
	dot_mesh.height = DOT_RADIUS * 2.0
	dot_mesh.radial_segments = 8
	dot_mesh.rings = 4
	dot_mesh.material = material

	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = dot_mesh
	multimesh.instance_count = MAX_DOTS
	multimesh.visible_instance_count = 0
	_dots.multimesh = multimesh

	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = RING_RADIUS - RING_THICKNESS
	ring_mesh.outer_radius = RING_RADIUS
	ring_mesh.material = material
	_ring.mesh = ring_mesh


## `origin`/`launch_velocity` are world-space, matching what
## PlayerController._kick_parameters() returns. Hides everything when
## `active` is false — cheap to call unconditionally every frame.
func update_preview(active: bool, origin: Vector3, launch_velocity: Vector3) -> void:
	visible = active
	if not active:
		return

	var points := _simulate(origin, launch_velocity)
	var multimesh := _dots.multimesh
	var shown := mini(points.size(), MAX_DOTS)
	multimesh.visible_instance_count = shown
	for i in shown:
		# MultiMesh instance transforms are local to _dots, which follows
		# the player like any other child node — to_local() converts the
		# simulation's world-space points into that space so a dash lands
		# exactly at its simulated world position regardless of where the
		# player is standing or facing.
		multimesh.set_instance_transform(i, Transform3D(Basis.IDENTITY, _dots.to_local(points[i])))

	var landing := points[points.size() - 1] if not points.is_empty() else origin
	landing.y = 0.02   # just off the turf, same reasoning as Field's line markings
	_ring.global_position = landing


func _simulate(origin: Vector3, launch_velocity: Vector3) -> Array[Vector3]:
	var points: Array[Vector3] = []
	var pos := origin
	var vel := launch_velocity
	for i in MAX_DOTS:
		var speed := vel.length()
		if speed > 0.05:
			vel += (-vel * speed * Tuning.BALL_DRAG_COEFF / Tuning.BALL_MASS) * DOT_STEP_TIME
		vel.y -= Tuning.GRAVITY * DOT_STEP_TIME
		pos += vel * DOT_STEP_TIME
		points.append(pos)
		if pos.y <= GROUND_HEIGHT:
			break
	return points
