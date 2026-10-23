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
## Timing cue (user brief: a loading-circle cue synced to the ball's real
## arrival, not a fixed timer, that "should click Y on a full rotation of
## the circle a little before the ball hits players"): a fixed-radius ring
## around the badge sweeps clockwise from empty to a complete lap as
## PlayerController.mark_timing_offset(ball) — the exact live number the
## real catch resolution grades presses against, not a re-derived copy of
## it — counts down toward each tier's own "press now" instant. A full
## rotation *is* press-now, which reads far more directly as "the loading
## bar just finished, go" than the previous version's shrinking-radius ring
## did. That instant isn't always offset zero: Safe/Running resolve the
## same physics frame as the press, but Aggressive's jump takes a fixed
## ACTION_CONTACT[MARK_AGGRESSIVE] seconds to peak, so its "press now" is
## that far *before* the ball's closest approach — see
## _press_target_offset().
##
## The instant the sweep completes its lap, MarkPrompt fires one rumble
## pulse (Tuning.RUMBLE_MARK_TIMING_CUE) and a brief radius pop of its
## own — a physical "now" cue on top of the visual one, once per live
## window (_ring_completed guards against repeating it every frame the
## ring stays full while the ball's still arriving).

const BADGE_RADIUS := 15.0
const LABEL_SIZE := 16

## Fixed ring radius (no longer animated in/out — see this file's own
## header) and how many seconds of live offset the sweep's full lap spans.
## Purely presentational, so kept local to this file rather than Tuning.gd,
## same precedent as KickTrajectory's own local RING_PULSE_*/DOT_SCALE_*
## constants (that file's cosmetic dials aren't in Tuning either, even
## though the kick itself is heavily Tuning-defined).
const RING_RADIUS := BADGE_RADIUS + 9.0
## Widened from 1.0 (user report: "improve the quality of the timing cue
## more, start it earlier and have a longer animation") — at 1.0s the sweep
## only had about a second to read and react to before the press-now
## instant, which is a tight ask for a cue that's meant to be teaching
## timing rather than testing reflexes on top of it. A longer lead gives
## the sweep room to start well before the ball is even close and still
## finish its lap at the same honest instant (mark_timing_offset() is
## unchanged — only how much runway the sweep gets to visualise it grew).
const RING_LEAD_TIME := 1.8        ## s of live offset mapped across the sweep's full lap
const RING_THICKNESS := 3.0
const RING_SEGMENTS := 40
const RING_SWEEP_START := -PI / 2.0   ## 12 o'clock; sweeps clockwise from there

## Brief post-resolution flash so the result reads as clearly as the
## countdown did — connects directly to the player's own mark_caught/
## mark_missed signals rather than the badge/ring needing any new state
## threaded through from PlayerController. Kept alive through _screen_pos/
## _tier holding their last-live values (see _process()) so the flash is
## actually visible even on the same frame the tier itself goes NONE
## (catching/missing changes player state — is_carrying(), a fresh
## gather_cooldown — which is exactly what makes live_mark_prompt() stop
## recommending anything the instant the outcome lands).
const FLASH_DURATION := 0.30
const FLASH_RING_GROW := 10.0      ## px the ring briefly pops outward by on a hit

## The completion pop — distinct from FLASH_RING_GROW above (that one is
## the catch/miss *outcome*; this one is "the sweep just finished", before
## the outcome is even known).
const CUE_DURATION := 0.18
const CUE_RING_GROW := 6.0

var player: PlayerController = null:
	set(value):
		if value == player:
			return
		_disconnect_player()
		player = value
		_connect_player()

var ball: Ball = null

## Which countdown the ring sweeps on — a MarkCueModel.CueSource. Real
## matches get Tuning.MARK_CUE_SOURCE (the shipped analytic ring unless the
## user changes it); a dev page can set its own instance's without touching
## matches. See MarkCueModel.cue_time_to_press.
var cue_source: int = Tuning.MARK_CUE_SOURCE

var _canvas: Control
var _tier := Tuning.Action.NONE
var _screen_pos := Vector2.ZERO
var _visible_this_frame := false
var _ring_visible_this_frame := false
var _ring_progress := 0.0   ## 0 = sweep just started, 1 = a full lap — press now

## Guards the completion rumble/pop to firing once per live window, not
## every frame the sweep sits at a full lap waiting for the ball to
## actually arrive. Cleared whenever the prompt goes non-live or the tier
## changes (see _process()).
var _ring_completed := false
var _cue_timer := 0.0

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
	_cue_timer = maxf(0.0, _cue_timer - delta)

	var previous_tier := _tier
	_ring_visible_this_frame = false
	var live_now := false
	if is_instance_valid(player) and is_instance_valid(ball):
		var camera := player.camera as Camera3D
		if is_instance_valid(camera):
			var tier := player.live_mark_prompt(ball)
			if tier != Tuning.Action.NONE:
				var world := player.global_position + Vector3.UP * Tuning.MARK_PROMPT_HEIGHT
				if not camera.is_position_behind(world):
					# _screen_pos/_tier only update while genuinely live, so
					# they hold their last-live values through the post-
					# resolution flash below even once live_mark_prompt()
					# itself has already gone NONE (see FLASH_DURATION's
					# own comment).
					_screen_pos = camera.unproject_position(world)
					_tier = tier
					live_now = true
					_update_ring()
	_visible_this_frame = live_now

	if not live_now or _tier != previous_tier:
		_ring_completed = false
	if _ring_visible_this_frame and _ring_progress >= 1.0 and not _ring_completed:
		_ring_completed = true
		_cue_timer = CUE_DURATION
		InputManager.rumble(Tuning.RUMBLE_MARK_TIMING_CUE)

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


## Only ever called from _process() while `tier` is already known live —
## no redundant re-checks here. `_tier` has already been updated to the
## current live tier by the caller before this runs.
##
## Always marks the ring visible once live — it used to bail out (leaving
## the ring hidden) whenever mark_timing_offset() reported "not
## meaningfully closing yet" (early in the ball's flight, before real
## closing speed builds — see that function's own comment) or "past peak"
## (right at the tail of a live window). That made the ring's first
## appearance a hard pop-in sometime *after* the badge had already been
## showing alone, and — since closing_speed can wobble across that
## MARK_TIMING_MIN_CLOSING_SPEED threshold for a frame or two right around
## a trajectory's apex — could flicker the ring on/off before it settled.
## Reported as "shows static, flickers away, then reappears with the
## timing cue" instead of one continuous cue. Now the ring is part of the
## same live moment as the badge from frame one, just sitting at progress
## 0 (a zero-length arc — effectively invisible, but never toggled off)
## until there's a real countdown to show, so there's no separate
## hide-then-show step left to flicker.
func _update_ring() -> void:
	_ring_visible_this_frame = true
	# `_tier` (updated by the caller just before this runs — see this
	# function's own doc comment) scopes the "basically here" arrived-
	# radius to the tier actually live right now, same as every resolution
	# call site does — see mark_timing_offset()'s own comment for why a
	# generic/tier-agnostic radius drew the ring's own "press now" instant
	# too early for Running.
	#
	# The countdown itself comes from MarkCueModel.cue_time_to_press. Under
	# the ANALYTIC source that's this ring's original arithmetic, unchanged:
	# _press_target_offset(_tier) - mark_timing_offset(), with NAN on the
	# not-closing sentinel.
	var to_press := MarkCueModel.cue_time_to_press(player, ball, _tier, cue_source)
	if is_nan(to_press):
		_ring_progress = 0.0   # nothing meaningful to count down yet — sweep hasn't started
		return
	# 0 at the start of the countdown window, 1 (a full lap) right at the
	# press-now instant — see this file's own header for why a sweep reads
	# more directly as "go" than the old shrinking-ring version did.
	_ring_progress = clampf(1.0 - to_press / RING_LEAD_TIME, 0.0, 1.0)


func _draw_badge(canvas: Control) -> void:
	if not _visible_this_frame and _flash_sign == 0:
		return
	if _flash_sign != 0:
		# Post-resolution flash — a full ring regardless of where the sweep
		# left off, since by now the attempt is already decided. Drawn
		# independently of _ring_visible_this_frame (which is usually
		# already false by this point — catching/missing changes player
		# state, so live_mark_prompt() itself has typically already gone
		# NONE) using the last-live _screen_pos held onto for exactly this.
		var radius := RING_RADIUS + FLASH_RING_GROW * (_flash_timer / FLASH_DURATION)
		canvas.draw_arc(_screen_pos, radius, 0.0, TAU, RING_SEGMENTS, _flash_colour(),
			RING_THICKNESS, true)
	elif _ring_visible_this_frame:
		var radius := RING_RADIUS
		if _cue_timer > 0.0:
			# The completion pop — a quick outward flick right as the sweep
			# finishes its lap, on top of the rumble fired the same instant
			# (see _process()).
			radius += CUE_RING_GROW * (_cue_timer / CUE_DURATION)
		var sweep_end := RING_SWEEP_START + _ring_progress * TAU
		canvas.draw_arc(_screen_pos, radius, RING_SWEEP_START, sweep_end,
			RING_SEGMENTS, _badge_colour(_tier), RING_THICKNESS, true)

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
