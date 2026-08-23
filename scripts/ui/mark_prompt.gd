class_name MarkPrompt
extends CanvasLayer

## Madden-style contest prompt: a single coloured button badge — (A) green
## Safe, (X) blue Running/RAC, (Y) yellow Aggressive — floating above the
## human-controlled player's head whenever a mark is live for them, so
## "what do I press right now" reads at a glance instead of living only in
## muscle memory or the key-hint bar at the bottom of the screen. Same
## instantiate-and-assign-fields pattern as KickCrosshair/DebugHud — owned
## and updated by whichever mode has a human-controlled player, not wired
## through autoload state.
##
## Exactly one badge, not one per live tier — an earlier version stacked
## every tier PlayerController.live_mark_prompt() considered "would
## connect if pressed", but Safe's reach always covers Running's narrower
## one and Aggressive's MARK_CONTEST_RANGE is wider again, so nearly every
## live moment showed all three stacked at once. live_mark_prompt() (now
## singular) already picks the one actually relevant tier; this component
## only projects that single answer to screen space and draws it, it never
## re-derives eligibility or re-ranks tiers on its own.
##
## Timing ring (user brief: a shrinking-ring cue synced to the ball's real
## arrival, not a fixed timer): a second ring around the same badge that
## closes in from RING_OPEN_RADIUS toward BADGE_RADIUS as PlayerController.
## mark_timing_offset(ball) — the exact live number the real catch
## resolution grades presses against, not a re-derived copy of it — counts
## down toward each tier's own "press now" instant. That instant isn't
## always offset zero: Safe/Running resolve the same physics frame as the
## press, but Aggressive's jump takes a fixed ACTION_CONTACT[MARK_
## AGGRESSIVE] seconds to peak, so its "press now" is that far *before* the
## ball's closest approach — see _press_target_offset().

const BADGE_RADIUS := 15.0
const LABEL_SIZE := 16

## How wide open the ring starts (px) and how many seconds of live offset
## that corresponds to — purely presentational, so kept local to this file
## rather than Tuning.gd, same precedent as KickTrajectory's own local
## RING_PULSE_*/DOT_SCALE_* constants (that file's cosmetic dials aren't in
## Tuning either, even though the kick itself is heavily Tuning-defined).
const RING_OPEN_RADIUS := 30.0
const RING_LEAD_TIME := 1.0        ## s of live offset mapped across the ring's full close
const RING_THICKNESS := 3.0

## Brief post-resolution flash so the result reads as clearly as the
## countdown did — connects directly to the player's own mark_caught/
## mark_missed signals rather than the badge/ring needing any new state
## threaded through from PlayerController.
const FLASH_DURATION := 0.30
const FLASH_RING_GROW := 10.0      ## px the ring briefly pops outward by on a hit

var player: PlayerController = null:
	set(value):
		if value == player:
			return
		_disconnect_player()
		player = value
		_connect_player()

var ball: Ball = null

var _canvas: Control
var _tier := Tuning.Action.NONE
var _screen_pos := Vector2.ZERO
var _visible_this_frame := false
var _ring_visible_this_frame := false
var _ring_progress := 0.0   ## 0 = closed/press-now, 1 = fully open

## 0 = no flash, 1 = just caught, -1 = just missed — decays via _flash_timer.
var _flash_sign := 0
var _flash_timer := 0.0


func _ready() -> void:
	layer = 4
	var canvas := Control.new()
	canvas.name = "Badge"
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.draw.connect(_draw_badge.bind(canvas))
	add_child(canvas)
	_canvas = canvas


func _process(delta: float) -> void:
	_flash_timer = maxf(0.0, _flash_timer - delta)
	if _flash_timer <= 0.0:
		_flash_sign = 0

	_visible_this_frame = false
	_ring_visible_this_frame = false
	if is_instance_valid(player) and is_instance_valid(ball):
		var camera := player.camera as Camera3D
		if is_instance_valid(camera):
			_tier = player.live_mark_prompt(ball)
			if _tier != Tuning.Action.NONE:
				var world := player.global_position + Vector3.UP * Tuning.MARK_PROMPT_HEIGHT
				if not camera.is_position_behind(world):
					_screen_pos = camera.unproject_position(world)
					_visible_this_frame = true
					_update_ring()
	_canvas.queue_redraw()


## Aggressive's catch resolves ACTION_CONTACT[MARK_AGGRESSIVE] seconds
## *after* the jump is committed (see PlayerController._resolve_aggressive_
## mark), so the moment worth pressing at is that far before the ball's
## own closest-approach instant, not at it — jump early enough that the
## fixed-length rise lands you there. Safe/Running resolve the same frame
## as the press, so "press now" for them really is offset zero.
func _press_target_offset(tier: Tuning.Action) -> float:
	if tier == Tuning.Action.MARK_AGGRESSIVE:
		return -Tuning.action_contact_time(Tuning.Action.MARK_AGGRESSIVE)
	return 0.0


## Only ever called from _process() after both player/ball validity and
## camera framing are already confirmed — no redundant re-checks here.
func _update_ring() -> void:
	var offset := player.mark_timing_offset(ball)
	if offset >= Tuning.MARK_TIMING_PAST_PEAK_OFFSET:
		return   # ball's no longer meaningfully closing — nothing left to count down
	var to_press := offset - _press_target_offset(_tier)
	_ring_progress = clampf(-to_press / RING_LEAD_TIME, 0.0, 1.0)
	_ring_visible_this_frame = true


func _draw_badge(canvas: Control) -> void:
	if not _visible_this_frame:
		return
	if _ring_visible_this_frame:
		var radius := lerpf(BADGE_RADIUS + 4.0, RING_OPEN_RADIUS, _ring_progress)
		if _flash_sign != 0:
			radius += FLASH_RING_GROW * (_flash_timer / FLASH_DURATION)
		var ring_colour := _flash_colour() if _flash_sign != 0 else _badge_colour(_tier)
		canvas.draw_arc(_screen_pos, radius, 0.0, TAU, 40, ring_colour, RING_THICKNESS, true)

	var font := SoftBrutalist.font(SoftBrutalist.WEIGHT_HEAVY)
	var colour := _badge_colour(_tier)
	canvas.draw_circle(_screen_pos, BADGE_RADIUS, colour)
	canvas.draw_circle(_screen_pos, BADGE_RADIUS, SoftBrutalist.INK, false, 2.0, true)
	var label := _badge_label(_tier)
	var size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, LABEL_SIZE)
	canvas.draw_string(font, _screen_pos - size * 0.5 + Vector2(0.0, size.y * 0.5),
		label, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE, SoftBrutalist.PANEL)


func _flash_colour() -> Color:
	# No dedicated fail/red anywhere in this palette (soft_brutalist.gd) —
	# a muted grey reads as "missed" without introducing a colour the rest
	# of the UI never uses elsewhere.
	return SoftBrutalist.ACCENT_SECONDARY if _flash_sign > 0 else SoftBrutalist.MUTED


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


func _on_mark_caught(_tier: Tuning.Action, _legal_mark: bool) -> void:
	_flash_sign = 1
	_flash_timer = FLASH_DURATION


func _on_mark_missed(_tier: Tuning.Action) -> void:
	_flash_sign = -1
	_flash_timer = FLASH_DURATION


func _connect_player() -> void:
	if not is_instance_valid(player):
		return
	if not player.mark_caught.is_connected(_on_mark_caught):
		player.mark_caught.connect(_on_mark_caught)
	if not player.mark_missed.is_connected(_on_mark_missed):
		player.mark_missed.connect(_on_mark_missed)


func _disconnect_player() -> void:
	if not is_instance_valid(player):
		return
	if player.mark_caught.is_connected(_on_mark_caught):
		player.mark_caught.disconnect(_on_mark_caught)
	if player.mark_missed.is_connected(_on_mark_missed):
		player.mark_missed.disconnect(_on_mark_missed)
