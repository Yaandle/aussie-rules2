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
const SIM_STEP_TIME := 0.05      ## s of simulated flight per integration step
const MAX_SIM_SECONDS := 8.0     ## safety cap so a freak launch can't loop forever
const DOT_RADIUS := 0.045
const RING_RADIUS := 0.5
const RING_THICKNESS := 0.07
const GROUND_HEIGHT := 0.05       ## simulation stops once the ball would be this low

## Dot trail tapering: boot-end dashes start smaller/dimmer, landing-end
## dashes finish larger/brighter, so the arc reads as a directional trail
## pointing at the landing spot rather than a static row of identical balls.
const DOT_SCALE_NEAR := 0.55
const DOT_SCALE_FAR := 1.35
const DOT_ALPHA_NEAR := 0.35
const DOT_ALPHA_FAR := 1.0

## Landing ring pulse: subtle scale/alpha breathing so the landing zone
## reads as "live" without competing with the dashed arc for attention.
const RING_PULSE_SPEED := 2.0
const RING_PULSE_SCALE_AMOUNT := 0.04
const RING_PULSE_ALPHA_AMOUNT := 0.12

## Colour source: res://scripts/ui/soft_brutalist.gd, SoftBrutalist.ACCENT_PRIMARY
## (#4E9F5B). The raw UI hex reads muddy/low-contrast as an unshaded overlay on
## grass (green-on-green), so it's lightened and desaturated slightly toward
## yellow here purely for outdoor 3D legibility — same accent family, tuned
## for this context rather than matched pixel-for-pixel to the UI swatch.
var _colour: Color = SoftBrutalist.ACCENT_PRIMARY.lightened(0.35)

var _inner_ring_material: StandardMaterial3D
var _outer_ring_material: StandardMaterial3D
var _dot_material: StandardMaterial3D
var _time := 0.0

@onready var _dots: MultiMeshInstance3D = $Dots
@onready var _ring: MeshInstance3D = $LandingRing


func _ready() -> void:
	visible = false

	_dot_material = StandardMaterial3D.new()
	_dot_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_dot_material.albedo_color = _colour
	_dot_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_dot_material.vertex_color_use_as_albedo = true   # lets per-instance MultiMesh colours modulate the shared mesh

	var dot_mesh := SphereMesh.new()
	dot_mesh.radius = DOT_RADIUS
	dot_mesh.height = DOT_RADIUS * 2.0
	dot_mesh.radial_segments = 8
	dot_mesh.rings = 4
	dot_mesh.material = _dot_material

	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = dot_mesh
	multimesh.instance_count = MAX_DOTS
	multimesh.visible_instance_count = 0
	_dots.multimesh = multimesh

	# Two-layer "landing zone" look: a soft, wider outer ring plus a
	# brighter, thinner inner ring, combined as two surfaces of one
	# ArrayMesh so a single MeshInstance3D can still carry both.
	_outer_ring_material = StandardMaterial3D.new()
	_outer_ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_outer_ring_material.albedo_color = Color(_colour.r, _colour.g, _colour.b, _colour.a * 0.35)
	_outer_ring_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	_inner_ring_material = StandardMaterial3D.new()
	_inner_ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_inner_ring_material.albedo_color = _colour
	_inner_ring_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	var outer_torus := TorusMesh.new()
	outer_torus.inner_radius = RING_RADIUS - RING_THICKNESS * 1.8
	outer_torus.outer_radius = RING_RADIUS + RING_THICKNESS * 0.6

	var inner_torus := TorusMesh.new()
	inner_torus.inner_radius = RING_RADIUS - RING_THICKNESS * 0.55
	inner_torus.outer_radius = RING_RADIUS

	var ring_mesh := ArrayMesh.new()
	ring_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, outer_torus.get_mesh_arrays())
	ring_mesh.surface_set_material(0, _outer_ring_material)
	ring_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, inner_torus.get_mesh_arrays())
	ring_mesh.surface_set_material(1, _inner_ring_material)
	_ring.mesh = ring_mesh


## `origin`/`launch_velocity` are world-space, matching what
## PlayerController._kick_parameters() returns. Hides everything when
## `active` is false — cheap to call unconditionally every frame.
func update_preview(active: bool, origin: Vector3, launch_velocity: Vector3) -> void:
	visible = active
	if not active:
		return

	# Driven every frame while charging, so this doubles as our pulse clock —
	# no separate _process needed just to keep a hidden node ticking.
	_time += get_process_delta_time()

	var points := _simulate(origin, launch_velocity)
	var shown := _downsample(points, MAX_DOTS)
	var multimesh := _dots.multimesh
	multimesh.visible_instance_count = shown.size()
	var last := shown.size() - 1
	for i in shown.size():
		var t := 0.0 if last <= 0 else float(i) / float(last)
		var scale := lerpf(DOT_SCALE_NEAR, DOT_SCALE_FAR, t)
		var alpha := lerpf(DOT_ALPHA_NEAR, DOT_ALPHA_FAR, t)
		# MultiMesh instance transforms are local to _dots, which follows
		# the player like any other child node — to_local() converts the
		# simulation's world-space points into that space so a dash lands
		# exactly at its simulated world position regardless of where the
		# player is standing or facing.
		var xform := Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * scale), _dots.to_local(shown[i]))
		multimesh.set_instance_transform(i, xform)
		multimesh.set_instance_color(i, Color(_colour.r, _colour.g, _colour.b, _colour.a * alpha))

	var landing := points[points.size() - 1] if not points.is_empty() else origin
	landing.y = 0.02   # just off the turf, same reasoning as Field's line markings
	_ring.global_position = landing

	var pulse := sin(_time * RING_PULSE_SPEED)
	_ring.scale = Vector3.ONE * (1.0 + pulse * RING_PULSE_SCALE_AMOUNT)
	var alpha_mod := 1.0 + pulse * RING_PULSE_ALPHA_AMOUNT
	_inner_ring_material.albedo_color = Color(_colour.r, _colour.g, _colour.b, clampf(_colour.a * alpha_mod, 0.0, 1.0))
	_outer_ring_material.albedo_color = Color(_colour.r, _colour.g, _colour.b, clampf(_colour.a * 0.35 * alpha_mod, 0.0, 1.0))


## Steps the flight all the way to the ground rather than for a fixed
## number of dots' worth — a stronger kick_power_scale or a higher charge
## both mean a longer flight, and the landing ring needs to sit where the
## ball would actually come down, not wherever a fixed time budget ran
## out. MAX_SIM_SECONDS is only a safety valve (real kicks land in ~3s at
## the highest charge/kick_power_scale combination); it should never
## actually bind.
func _simulate(origin: Vector3, launch_velocity: Vector3) -> Array[Vector3]:
	var points: Array[Vector3] = []
	var pos := origin
	var vel := launch_velocity
	var steps := ceili(MAX_SIM_SECONDS / SIM_STEP_TIME)
	for i in steps:
		var speed := vel.length()
		if speed > 0.05:
			vel += (-vel * speed * Tuning.BALL_DRAG_COEFF / Tuning.BALL_MASS) * SIM_STEP_TIME
		vel.y -= Tuning.GRAVITY * SIM_STEP_TIME
		pos += vel * SIM_STEP_TIME
		points.append(pos)
		if pos.y <= GROUND_HEIGHT:
			break
	return points


## Thins a full flight path down to at most `count` points spread evenly
## from boot to landing, so the dashed line always shows the *whole* arc
## no matter how long the real flight is — a rendering concern kept
## separate from _simulate()'s physics one, which has to walk every step
## to land the ring correctly even when that's far more points than are
## worth drawing individually.
func _downsample(points: Array[Vector3], count: int) -> Array[Vector3]:
	if points.size() <= count:
		return points
	var result: Array[Vector3] = []
	for i in count:
		var t := float(i) / float(count - 1)
		result.append(points[roundi(t * float(points.size() - 1))])
	return result
