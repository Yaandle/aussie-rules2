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

const RADIUS := 4.0
const IDLE_ALPHA := 0.35
const AIM_ALPHA := 0.85
const FADE_RATE := 10.0   ## higher = snappier idle<->aiming transition

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
	var aiming := is_instance_valid(player) and player.is_kick_aiming()
	var target := AIM_ALPHA if aiming else IDLE_ALPHA
	_alpha = lerpf(_alpha, target, 1.0 - exp(-FADE_RATE * delta))
	_dot.queue_redraw()


func _draw_dot(dot: Control) -> void:
	var colour := _colour
	colour.a = _alpha
	dot.draw_circle(dot.size * 0.5, RADIUS, colour)
