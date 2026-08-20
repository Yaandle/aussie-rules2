class_name LandingShadow
extends MeshInstance3D

## A small ground marker at the ball's estimated landing point, visible
## any time it is genuinely in flight — not just while a human is
## charging their own kick (KickTrajectory already covers that, before
## the ball has even left the boot). This is the "where is that thing
## about to come down" cue a real shadow gives a fielder: useful for
## judging a mark on someone else's kick, an AI's kick, a spoiled
## deflection back into the air — anything, not only your own.
##
## Reuses the exact simple gravity+drag step KickTrajectory already
## hand-rolls rather than a second implementation of the same
## approximation (see that file's own header for why it doesn't reuse
## real Jolt physics for a preview) — just run from the ball's actual
## live position/velocity each frame instead of a hypothetical pre-kick
## one. Lives as a child of Ball in ball.tscn, so there is exactly one of
## these per ball regardless of how many players are on the field — the
## cost does not scale with team size, which matters given this project's
## own stated direction toward full 16-a-side sides.

const SIM_STEP_TIME := 0.05
const MAX_SIM_SECONDS := 8.0
const GROUND_HEIGHT := 0.05
const MARKER_HALF_WIDTH := 0.42   ## m, how wide the chevron's two arms spread
const MARKER_ARM_LENGTH := 0.58   ## m, apex to tip
const MARKER_THICKNESS := 0.09    ## m, stroke width of each arm
const MARKER_HEIGHT := 0.03       ## m off the turf, same reasoning as Field's line markings
const PULSE_SPEED := 2.4
const PULSE_ALPHA_AMOUNT := 0.25

## Same accent family as KickTrajectory's own preview, so a live shadow
## and a pre-kick aim preview read as one visual language rather than two
## unrelated overlay systems — see that file's colour comment for why the
## raw UI hex is lightened for outdoor legibility.
var _colour: Color = SoftBrutalist.ACCENT_PRIMARY.lightened(0.35)
var _material: StandardMaterial3D
var _time := 0.0


func _ready() -> void:
	visible = false
	top_level = true   # world-space marker, not rotated/scaled by the ball's own spin

	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.albedo_color = _colour
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh = _build_marker_mesh()
	material_override = _material


func _process(delta: float) -> void:
	var ball := get_parent() as Ball
	if ball == null or not ball.is_airborne():
		visible = false
		return

	visible = true
	_time += delta
	var landing := _estimate_landing(ball.global_position, ball.linear_velocity)
	landing.y = MARKER_HEIGHT
	global_position = landing

	var pulse := sin(_time * PULSE_SPEED)
	_material.albedo_color = Color(_colour.r, _colour.g, _colour.b,
		clampf(_colour.a * (1.0 + pulse * PULSE_ALPHA_AMOUNT), 0.0, 1.0))


## Same integration KickTrajectory._simulate uses, just walked from a live
## in-flight position/velocity instead of a not-yet-launched one, and
## only the final resting point is kept — nothing here needs the whole
## path, only where it ends.
func _estimate_landing(origin: Vector3, velocity: Vector3) -> Vector3:
	var pos := origin
	var vel := velocity
	var steps := ceili(MAX_SIM_SECONDS / SIM_STEP_TIME)
	for i in steps:
		var speed := vel.length()
		if speed > 0.05:
			vel += (-vel * speed * Tuning.BALL_DRAG_COEFF / Tuning.BALL_MASS) * SIM_STEP_TIME
		vel.y -= Tuning.GRAVITY * SIM_STEP_TIME
		pos += vel * SIM_STEP_TIME
		if pos.y <= GROUND_HEIGHT:
			break
	return pos


## A flat "(v)" chevron in the XZ plane, apex at the origin marking the
## exact estimated spot, both arms flaring away from it — built once as
## static geometry since only its position/alpha change frame to frame,
## not its shape.
func _build_marker_mesh() -> ArrayMesh:
	var arms := [
		Vector3(-MARKER_HALF_WIDTH, 0.0, MARKER_ARM_LENGTH),
		Vector3(MARKER_HALF_WIDTH, 0.0, MARKER_ARM_LENGTH),
	]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for tip: Vector3 in arms:
		var dir := tip.normalized()
		var side := Vector3(dir.z, 0.0, -dir.x) * (MARKER_THICKNESS * 0.5)
		var p0 := -side
		var p1 := side
		var p2 := tip + side
		var p3 := tip - side
		st.add_vertex(p0)
		st.add_vertex(p1)
		st.add_vertex(p2)
		st.add_vertex(p0)
		st.add_vertex(p2)
		st.add_vertex(p3)
	return st.commit()
