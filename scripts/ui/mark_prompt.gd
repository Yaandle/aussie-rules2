class_name MarkPrompt
extends CanvasLayer

## Madden-style contest prompt (polish-pass brief): a small row of coloured
## button badges — (A) green Safe, (X) blue Running/RAC, (Y) yellow
## Aggressive — floating above the human-controlled player's head whenever
## a mark is actually live for them, so "what can I press right now" reads
## at a glance instead of living only in muscle memory or the key-hint bar
## at the bottom of the screen. Same instantiate-and-assign-fields pattern
## as KickCrosshair/DebugHud — owned and updated by whichever mode has a
## human-controlled player, not wired through autoload state.
##
## Which tiers are "live" is decided by PlayerController.live_mark_prompts()
## against the real reach tests the contest itself resolves with — this
## component only projects that answer to screen space and draws it, it
## never re-derives eligibility on its own.

const BADGE_RADIUS := 15.0
const BADGE_GAP := 36.0          ## centre-to-centre spacing between stacked badges
const LABEL_SIZE := 16

var player: PlayerController = null
var ball: Ball = null

var _canvas: Control
var _live: Array[Tuning.Action] = []
var _screen_pos := Vector2.ZERO
var _visible_this_frame := false


func _ready() -> void:
	layer = 4
	var canvas := Control.new()
	canvas.name = "Badges"
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.draw.connect(_draw_badges.bind(canvas))
	add_child(canvas)
	_canvas = canvas


func _process(_delta: float) -> void:
	_visible_this_frame = false
	if is_instance_valid(player) and is_instance_valid(ball):
		var camera := player.camera as Camera3D
		if is_instance_valid(camera):
			_live = player.live_mark_prompts(ball)
			if not _live.is_empty():
				var world := player.global_position + Vector3.UP * Tuning.MARK_PROMPT_HEIGHT
				if not camera.is_position_behind(world):
					_screen_pos = camera.unproject_position(world)
					_visible_this_frame = true
	_canvas.queue_redraw()


func _draw_badges(canvas: Control) -> void:
	if not _visible_this_frame:
		return
	var font := SoftBrutalist.font(SoftBrutalist.WEIGHT_HEAVY)
	# Stacked bottom-to-top in tier order so Safe (the one most likely to
	# actually connect right now) sits closest to the player's head, same
	# reading order Madden's own stacked catch-icon uses.
	for i in _live.size():
		var tier := _live[i]
		var centre := _screen_pos + Vector2(0.0, -BADGE_GAP * float(_live.size() - 1 - i))
		var colour := _badge_colour(tier)
		canvas.draw_circle(centre, BADGE_RADIUS, colour)
		canvas.draw_circle(centre, BADGE_RADIUS, SoftBrutalist.INK, false, 2.0, true)
		var label := _badge_label(tier)
		var size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, LABEL_SIZE)
		canvas.draw_string(font, centre - size * 0.5 + Vector2(0.0, size.y * 0.5),
			label, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE, SoftBrutalist.PANEL)


func _badge_colour(tier: Tuning.Action) -> Color:
	match tier:
		Tuning.Action.MARK_RUNNING:
			return SoftBrutalist.BUTTON_X
		Tuning.Action.MARK_AGGRESSIVE:
			return SoftBrutalist.BUTTON_Y
		_:
			return SoftBrutalist.BUTTON_A


func _badge_label(tier: Tuning.Action) -> String:
	match tier:
		Tuning.Action.MARK_RUNNING:
			return "X"
		Tuning.Action.MARK_AGGRESSIVE:
			return "Y"
		_:
			return "A"
