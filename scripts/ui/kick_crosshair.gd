class_name KickCrosshair
extends CanvasLayer

## A small always-on reticle at screen centre marking where the camera is
## currently pointing. Screen centre is all that's needed — for a
## perspective camera with no lens offset, "straight down the camera's
## forward axis" always projects to exactly the middle of the viewport, so
## there's no 3D->2D projection to do here.
##
## Faint while not aiming (an ambient reference, not a demand for
## attention), brighter while a kick is being charged. The gameplay half
## of what this dot promises lives in PlayerController._current_look_yaw()
## — pulling into kick stance snaps the aim to wherever this dot is
## pointing (the camera's yaw), not the body's facing, so turning the
## camera toward goals while still running a different line and then
## pulling the trigger starts the kick aimed at goals.
##
## Charge/power ring: while aiming, a thin ring sweeps clockwise from 12
## o'clock around the dot as PlayerController.kick_charge() (already a
## public getter — DebugHud's own "charge" readout already reads it, this
## just gives it a real on-screen home) climbs 0→1, completing a full lap
## at maximum reach. Before this there was no way to read power state
## outside the F3 debug overlay — the trajectory arc's length is the only
## other cue, and reading "how charged am I" off arc length alone asks the
## player to judge a relative distance rather than read a simple fill
## level. Same sweep-ring idiom MarkPrompt already uses for its timing cue
## (clockwise from 12 o'clock, empty→full = not-yet→now), reused here for
## visual consistency rather than inventing a second gauge language. A
## short brighten/thicken kicks in once charge is effectively maxed (see
## FULL_CHARGE_THRESHOLD) so "you're at full power" reads at a glance
## instead of requiring a judgment call between "nearly full" and "full."

const RADIUS := 4.0
const IDLE_ALPHA := 0.35
const AIM_ALPHA := 0.85
const FADE_RATE := 10.0   ## higher = snappier idle<->aiming transition

const RING_RADIUS := RADIUS + 7.0
const RING_THICKNESS := 2.5
const RING_SEGMENTS := 36
const RING_SWEEP_START := -PI / 2.0   ## 12 o'clock; sweeps clockwise from there
const FULL_CHARGE_THRESHOLD := 0.98
const FULL_CHARGE_THICKNESS_SCALE := 1.4

## Same source KickTrajectory's dashed line/ring use for their colour
## (SoftBrutalist.ACCENT_PRIMARY, lightened for legibility as an unshaded
## overlay on grass) so the dot reads as part of the same kick-aim system,
## not a separate one. Its own field, not read live off KickTrajectory
## itself — that colour is a per-instance value there now, not something a
## second, independent overlay has any business reaching into.
var _colour: Color = SoftBrutalist.ACCENT_PRIMARY.lightened(0.35)

## Assigned by whichever mode owns the current human-controlled player —
## same pattern as DebugHud.player. Left null the dot just idles, which
## keeps this component harmless to instantiate before a player exists.
var player: PlayerController = null

var _dot: Control
var _alpha := IDLE_ALPHA
var _aiming := false
var _charge := 0.0


func _ready() -> void:
	layer = 4
	var dot := Control.new()
	dot.name = "Dot"
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dot.set_anchors_preset(Control.PRESET_FULL_RECT)
	dot.draw.connect(_draw_dot.bind(dot))
	add_child(dot)
	_dot = dot


func _process(delta: float) -> void:
	_aiming = is_instance_valid(player) and player.is_kick_aiming()
	var target := AIM_ALPHA if _aiming else IDLE_ALPHA
	_alpha = lerpf(_alpha, target, 1.0 - exp(-FADE_RATE * delta))
	# Only meaningful while actually aiming — reading it any other time
	# would just be whatever charge happened to be left over from the last
	# stance (PlayerController zeroes it on cancel/release, but not
	# instantly relative to this being read one frame later).
	_charge = player.kick_charge() if _aiming else 0.0
	_dot.queue_redraw()


func _draw_dot(dot: Control) -> void:
	var centre := dot.size * 0.5
	if _aiming:
		var full := _charge >= FULL_CHARGE_THRESHOLD
		var ring_colour := _colour
		ring_colour.a = _alpha * (1.0 if full else 0.85)
		var thickness := RING_THICKNESS * (FULL_CHARGE_THICKNESS_SCALE if full else 1.0)
		var sweep_end := RING_SWEEP_START + _charge * TAU
		dot.draw_arc(centre, RING_RADIUS, RING_SWEEP_START, sweep_end, RING_SEGMENTS,
			ring_colour, thickness, true)

	var colour := _colour
	colour.a = _alpha
	dot.draw_circle(centre, RADIUS, colour)
