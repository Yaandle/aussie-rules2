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

## Exponential smoothing rate for chasing the raw recomputed landing point
## (user report: shadow "jitters at the end of the trajectory"). The raw
## estimate is recomputed from scratch every frame from the ball's live
## position/velocity (see _estimate_landing's own comment on why — no
## cached prediction), which is honest but noisy: any small per-frame
## change in the ball's velocity (drag, a spoil, catch-gravity easing) is a
## forward simulation run all the way out again, and late in the arc, when
## the remaining flight time is short, that noise stops being smoothed out
## by distance/time and starts reading as visible jitter right at the
## point players most need to read it precisely. Smoothing the marker's
## displayed position toward the raw target (rather than snapping to it)
## fixes that without touching the prediction math itself. Same
## exp-decay-toward-target shape used elsewhere for camera/UI easing in
## this project; not physically meaningful, purely a display filter.
const SMOOTHING_RATE := 12.0   # higher = snappier/less lag, lower = smoother/more lag

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
	# A handball can never be marked (see Ball._is_handball_flight's own
	# doc comment), so showing this "go judge the mark" cue for one is a
	# false promise — playtest report: "the marking cue appears even if
	# it is a handball". Still shown for every other kind of airborne
	# ball (someone else's kick, a spoiled deflection, a bounce) exactly
	# as before.
	if ball == null or not ball.is_airborne() or ball.is_handball_flight():
		visible = false
		return

	var was_visible := visible
	visible = true
	_time += delta
	var landing := _estimate_landing(ball.global_position, ball.linear_velocity)
	landing.y = MARKER_HEIGHT
	if was_visible:
		# Damp toward the freshly recomputed target instead of snapping to
		# it — see SMOOTHING_RATE's own comment for why the raw estimate is
		# noisy late in the arc. Frame-rate independent via the standard
		# 1 - exp(-rate*delta) decay, same shape weight_towards()/lerp-per-
		# frame smoothing uses elsewhere in this project.
		var t := 1.0 - exp(-SMOOTHING_RATE * delta)
		global_position = global_position.lerp(landing, t)
	else:
		# Just became visible (ball only just went airborne, or this is the
		# very first frame it's tracked) — jump straight to the real
		# estimate rather than lerping in from wherever the marker was last
		# left (possibly stale, possibly the origin), which would otherwise
		# read as its own visible glide-in.
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
