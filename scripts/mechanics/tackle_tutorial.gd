class_name TackleTutorial
extends CoachChallenge

## The tackling coach's drill, reworked from a scored chase-from-behind
## challenge into a guided, step-by-step tutorial (user brief). Each step:
##
##   1. The mode script freezes play and shows the binding for one control —
##      keyboard/mouse AND controller, both at once (step_changed carries
##      both hint sets).
##   2. The player dismisses the card; the mode calls begin_rep().
##   3. The kick-to-kick rival — driven here by TutorialDummyBrain, NOT its
##      usual AIBrain (which would run for its own goal and dispose the ball
##      under pressure) — is handed the ball and jogs straight at the player.
##   4. The player applies the taught control; the matching outcome signal
##      clears the step and the next card comes up.
##
## Five steps, in order: close the gap (sprint) / slide dive-in / standing
## slide / lunge / hit-stick bump. No score and no fail state — a rep that
## produces nothing within TACKLE_TUTORIAL_STALE_REP_TIME just resets and
## runs again. Still a CoachChallenge subclass: challenge_started/
## challenge_ended/hint_changed and the _schedule/_tick_schedule timer are
## all reused unchanged (challenge_ended fires once, at the end, as the
## "tutorial complete" event). `_hits` is repurposed as the cleared-step
## count; `_armed`/`_attempts_used` from the base are unused here.

signal step_changed(step: Dictionary)
signal step_cleared(index: int, total: int)

enum Kind { SPRINT, SLIDE_DIVE, SLIDE_STANDING, LUNGE, BUMP }

## Card content per step. `kb`/`pad` are arrays of {keys, label} dicts, the
## exact shape KeyHintBar.set_hints() takes. Bindings mirror project.godot's
## input map (tackle = E / pad B, lunge_tackle = Q / pad X, bump_stance =
## L / pad LB with the flick on the camera/right-stick axes, sprint = Shift
## / pad RT).
const STEPS: Array[Dictionary] = [
	{
		"kind": Kind.SPRINT,
		"title": "Close the gap",
		"instruction": "Sprint out to the ball-carrier and pull up alongside them. You can't tackle what you can't catch.",
		"kb": [{"keys": "Shift", "label": "Sprint"}, {"keys": "W A S D", "label": "Steer"}],
		"pad": [{"keys": "RT", "label": "Sprint"}, {"keys": "Left Stick", "label": "Steer"}],
	},
	{
		"kind": Kind.SLIDE_DIVE,
		"title": "Slide tackle — dive in",
		"instruction": "From just outside arm's reach, hold the tackle: you commit to a dive that closes the last step and wraps them up.",
		"kb": [{"keys": "Hold E", "label": "Slide tackle"}],
		"pad": [{"keys": "Hold B", "label": "Slide tackle"}],
	},
	{
		"kind": Kind.SLIDE_STANDING,
		"title": "Standing slide tackle",
		"instruction": "At point-blank range, hold the tackle to grab and hold the carrier up — the ball is stripped, nobody goes down.",
		"kb": [{"keys": "Hold E", "label": "Slide tackle"}],
		"pad": [{"keys": "Hold B", "label": "Slide tackle"}],
	},
	{
		"kind": Kind.LUNGE,
		"title": "Lunge tackle",
		"instruction": "A quick tap at close range — a faster strip than the slide, and it takes the carrier all the way to ground.",
		"kb": [{"keys": "Tap Q", "label": "Lunge tackle"}],
		"pad": [{"keys": "Tap X", "label": "Lunge tackle"}],
	},
	{
		"kind": Kind.BUMP,
		"title": "Hit stick — bump",
		"instruction": "Hold bump stance, then flick toward the carrier to shoulder-charge them off the ball. Timing matters.",
		"kb": [{"keys": "Hold L", "label": "Bump stance"}, {"keys": "Flick ← ↑ → ↓", "label": "Bump"}],
		"pad": [{"keys": "Hold LB", "label": "Bump stance"}, {"keys": "Flick Right Stick", "label": "Bump"}],
	},
]

var _ball: Ball
var _player: PlayerController
var _rival: PlayerController

## The rival's real brain, parked for the duration and restored on finish.
var _saved_brain: PlayerBrain
var _dummy_brain: TutorialDummyBrain

var _step_index := 0
var _rep_running := false
var _stale_timer := 0.0


func begin(ball: Ball, player: PlayerController, rival: PlayerController) -> void:
	_ball = ball
	_player = player
	_rival = rival
	_step_index = 0
	_hits = 0
	_active = true
	_rep_running = false

	if is_instance_valid(_rival):
		_saved_brain = _rival.brain()
		_dummy_brain = TutorialDummyBrain.new()
		_dummy_brain.target = _player
		_rival.set_brain(_dummy_brain)
		_rival.drop_ball()

	_connect_outcomes()
	challenge_started.emit(STEPS.size())
	_present_step()


## True only while a live rep is in progress — kick_to_kick.gd's rival-freeze
## gate reads this so the dummy sits still while a card is up or during the
## between-steps beat, and only moves once the player has dismissed the card.
func rep_active() -> bool:
	return _rep_running


## Called by kick_to_kick.gd once the player dismisses the step card.
func begin_rep() -> void:
	if not _active:
		return
	_rep_running = true
	_stale_timer = Tuning.TACKLE_TUTORIAL_STALE_REP_TIME
	_position_dummy()
	var step: Dictionary = STEPS[_step_index]
	hint_changed.emit("%s — go." % step["title"])


## Bound to `decline` while a card is up: drop this step, move on.
func skip_step() -> void:
	if not _active:
		return
	_rep_running = false
	if is_instance_valid(_rival):
		_rival.drop_ball()
	_advance()


## Same contract as the other challenges' force_miss(): kick_to_kick.gd calls
## this when it has to yank the ball out (out of bounds, debug reset). Here
## it just ends the whole tutorial cleanly.
func force_miss() -> void:
	if not _active:
		return
	_finish()


func _physics_process(delta: float) -> void:
	if not _active:
		return
	# The between-steps beat (callback = _present_step).
	_tick_schedule(delta)
	if not _rep_running:
		return

	var step: Dictionary = STEPS[_step_index]
	if not is_instance_valid(_player) or not is_instance_valid(_rival):
		return

	var gap := _player.global_position.distance_to(_rival.global_position)

	if step["kind"] == Kind.SPRINT:
		if gap <= Tuning.TACKLE_TUTORIAL_SPRINT_CLEAR_RANGE:
			_clear_step()
		return

	# Contact steps: a rep that produced nothing just resets and runs again
	# (a tutorial retries, it doesn't fail).
	_stale_timer -= delta
	if _stale_timer <= 0.0:
		_position_dummy()
		_stale_timer = Tuning.TACKLE_TUTORIAL_STALE_REP_TIME


func _position_dummy() -> void:
	if not is_instance_valid(_player) or not is_instance_valid(_rival) or not is_instance_valid(_ball):
		return
	var step: Dictionary = STEPS[_step_index]
	var is_sprint: bool = step["kind"] == Kind.SPRINT
	var forward := -_player.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized() if forward.length_squared() > 0.0001 else Vector3.FORWARD
	var lead := Tuning.TACKLE_TUTORIAL_APPROACH_DISTANCE if is_sprint else Tuning.TACKLE_TUTORIAL_CONTACT_LEAD
	var start := _player.global_position + forward * lead
	start.y = 0.0

	_rival.drop_ball()
	_rival.global_position = start
	_ball.reset_at(start + Vector3.UP * 0.3)
	_rival.give_possession(_ball)

	_dummy_brain.target = _player
	# SPRINT: the dummy stands still and the player does the running. Every
	# other step: it jogs straight in. SLIDE_DIVE holds it just outside a
	# standing tackle's reach so only the dive-in can close the gap.
	_dummy_brain.run_gait = 0.0 if is_sprint else Tuning.TACKLE_TUTORIAL_DUMMY_GAIT
	_dummy_brain.stop_distance = Tuning.TACKLE_TUTORIAL_DIVE_HOLD_DISTANCE \
		if step["kind"] == Kind.SLIDE_DIVE else 0.0


func _present_step() -> void:
	if not _active:
		return
	step_changed.emit(STEPS[_step_index])


func _clear_step() -> void:
	if not _rep_running:
		return
	_rep_running = false
	_hits += 1
	if is_instance_valid(_rival):
		_rival.drop_ball()
	step_cleared.emit(_step_index, STEPS.size())
	_advance()


func _advance() -> void:
	_step_index += 1
	if _step_index >= STEPS.size():
		_finish()
	else:
		_schedule(Tuning.TACKLE_TUTORIAL_STEP_GAP, _present_step)


func _finish() -> void:
	if not _active:
		return
	_active = false
	_rep_running = false
	_disconnect_outcomes()
	if is_instance_valid(_rival):
		_rival.drop_ball()
		if _saved_brain != null:
			_rival.set_brain(_saved_brain)
	challenge_ended.emit(_hits, STEPS.size())


# ── Outcome wiring ───────────────────────────────────────────────────
# The player's own tackle_committed(is_slide) tells a slide rep from a lunge
# rep; bump_landed covers the hit-stick step. The dummy-side holding-the-
# ball/ball-up signals aren't needed — tackle_committed already fires on the
# same connect and carries the slide/lunge bit these steps care about.

func _connect_outcomes() -> void:
	if not is_instance_valid(_player):
		return
	if not _player.tackle_committed.is_connected(_on_tackle_committed):
		_player.tackle_committed.connect(_on_tackle_committed)
	if not _player.bump_landed.is_connected(_on_bump_landed):
		_player.bump_landed.connect(_on_bump_landed)


func _disconnect_outcomes() -> void:
	if not is_instance_valid(_player):
		return
	if _player.tackle_committed.is_connected(_on_tackle_committed):
		_player.tackle_committed.disconnect(_on_tackle_committed)
	if _player.bump_landed.is_connected(_on_bump_landed):
		_player.bump_landed.disconnect(_on_bump_landed)


func _on_tackle_committed(is_slide: bool) -> void:
	if not _active or not _rep_running:
		return
	match STEPS[_step_index]["kind"]:
		Kind.SLIDE_DIVE, Kind.SLIDE_STANDING:
			if is_slide:
				_clear_step()
		Kind.LUNGE:
			if not is_slide:
				_clear_step()


func _on_bump_landed(_bumper: PlayerController, _carrier: PlayerController, _clean: bool) -> void:
	if not _active or not _rep_running:
		return
	if STEPS[_step_index]["kind"] == Kind.BUMP:
		_clear_step()
