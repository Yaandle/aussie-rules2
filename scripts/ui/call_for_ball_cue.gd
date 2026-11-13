class_name CallForBallCue
extends CanvasLayer

## Call-for-ball indicator (6V, playtest note: "when a player calls for the
## ball in single-player control, draw three small lines under them, like
## / | \"). Three short strokes fanning down from just under the caller's
## feet, on screen, for DURATION after the call, fading out at the end.
## FullGame._call_for_ball shows it for every call, heard or not, the same
## as the ring's flash: the shout happened either way.

const DURATION := 0.9
const FADE := 0.3                ## s at the end it fades over
const GAP := 14.0                ## px below the feet the strokes start (apart enough not to touch)
const LENGTH := 14.0             ## px
const SPREAD_DEG := 38.0         ## the outer two strokes lean
const WIDTH := 3.0
const OUTLINE := 2.0             ## px of ink around each stroke
const COLOUR := Color("#F4EFE6")

var _target: Node3D = null
var _time := 0.0
var _canvas: Control


func _ready() -> void:
	layer = 5
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_strokes)
	add_child(_canvas)


func show_for(player: Node3D) -> void:
	_target = player
	_time = DURATION
	_canvas.queue_redraw()


func _process(delta: float) -> void:
	if _time <= 0.0:
		return
	_time = maxf(0.0, _time - delta)
	_canvas.queue_redraw()


func _draw_strokes() -> void:
	if _time <= 0.0 or _target == null or not is_instance_valid(_target):
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var feet := _target.global_position
	if camera.is_position_behind(feet):
		return
	var at := camera.unproject_position(feet)
	var alpha := clampf(_time / FADE, 0.0, 1.0)
	var ink := Color(SoftBrutalist.INK, alpha)
	var fill := Color(COLOUR, alpha)
	for lean in [-SPREAD_DEG, 0.0, SPREAD_DEG]:
		var a := deg_to_rad(lean)
		# Down the screen is +y; a negative lean goes down-left, a "/".
		var dir := Vector2(sin(a), cos(a))
		var from := at + dir * GAP
		var to := at + dir * (GAP + LENGTH)
		_canvas.draw_line(from, to, ink, WIDTH + OUTLINE * 2.0, true)
		_canvas.draw_line(from, to, fill, WIDTH, true)
