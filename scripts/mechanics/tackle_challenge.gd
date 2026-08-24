class_name TackleChallenge
extends CoachChallenge

## The tackling coach's mini-game (design brief's third and final planned
## coach): the player has to run down and tackle a live opponent before
## they get the ball away, not react to a stationary target
## (KickChallenge) or a lobbed delivery (MarkChallenge). Reuses kick_to_
## kick.gd's existing rival — a stock AIBrain-driven PlayerController,
## already proven as a sparring partner (see Tuning's own "Kick-to-kick
## rival" comment) — as the tackling dummy rather than spawning a second,
## dedicated one. kick_to_kick.gd un-freezes it specifically for this
## challenge (see its own _physics_process comment) instead of the
## "frozen for every coach drill" default the kicking/marking coaches
## still get, since here the rival running around is the whole point.
##
## No target zone or "did it land" check the way the other two have —
## success is "the rival got tackled": PlayerController.holding_the_ball_
## called/field_ball_up_called firing ON the rival, both real tackle
## outcomes per those signals' own doc comments (either one means a tackle
## landed; which one only distinguishes the holding-the-ball ruling from
## the neutral case, irrelevant to this drill). An attempt fails one of two
## ways: the rival disposes of the ball before being tackled (ball_disposed
## firing on the rival first), or a timer runs out — the safety valve every
## other challenge here gets for free from Ball.is_settled(); a live AI
## carrier never settles, so this needs its own.
##
## The base class's _timer is dual-purpose here: counts down the pause
## between attempts (with _pending_callback set) while not armed, and
## counts down the catch-them-before-they-escape window (no callback, just
## a plain countdown _physics_process reads directly) once armed. Never
## both at once.

signal tackle_hit(hits: int, attempts_used: int)
signal tackle_missed(attempts_used: int, reason: String)

var _ball: Ball
var _player: PlayerController
var _rival: PlayerController


func begin(ball: Ball, player: PlayerController, rival: PlayerController) -> void:
	_ball = ball
	_player = player
	_rival = rival
	_attempts_used = 0
	_hits = 0
	_active = true
	_armed = false
	_connect_rival()
	challenge_started.emit(Tuning.TACKLE_CHALLENGE_ATTEMPTS)
	hint_changed.emit("Tackling practice — run the rival down and hold E to tackle before they get rid of it.")
	_deliver()


## Same purpose as KickChallenge/MarkChallenge's own force_miss(): kick_to_
## kick.gd calls this whenever it has to yank the ball out from under an
## armed attempt (out of bounds, manual debug reset) instead of letting it
## resolve on its own.
func force_miss() -> void:
	if not _active or not _armed:
		return
	_resolve(false, "reset")


func _physics_process(delta: float) -> void:
	if not _active:
		return
	if not _armed:
		_tick_schedule(delta)
		return
	_timer = maxf(0.0, _timer - delta)
	if _timer <= 0.0:
		_resolve(false, "got away")


## Positions the rival ahead of the player along the rival's own attack
## direction — i.e. the direction it will actually run once carrying — so
## a real chase is what closes the gap, not a coincidence of which way the
## AI happens to run. give_possession() is the same shared hand-the-ball-
## outright entry point every protected restart in full_game.gd already
## uses (see PlayerController.give_possession's own doc comment).
func _deliver() -> void:
	if not is_instance_valid(_player) or not is_instance_valid(_rival) or not is_instance_valid(_ball):
		return
	var lateral := randf_range(-Tuning.TACKLE_CHALLENGE_LATERAL_SPREAD, Tuning.TACKLE_CHALLENGE_LATERAL_SPREAD)
	var lead := Vector3(Tuning.TACKLE_CHALLENGE_LEAD_DISTANCE, 0.0, lateral)
	var start := _player.global_position + lead
	_rival.drop_ball()
	_rival.global_position = start
	_ball.reset_at(start + Vector3.UP * 0.3)
	_rival.give_possession(_ball)
	_armed = true
	_timer = Tuning.TACKLE_CHALLENGE_TIME_LIMIT
	hint_changed.emit("Run them down! Attempt %d/%d" % [_attempts_used + 1, Tuning.TACKLE_CHALLENGE_ATTEMPTS])


func _on_rival_tackled(_tackler: PlayerController) -> void:
	if _active and _armed:
		_resolve(true, "")


func _on_rival_ball_up(_tackler: PlayerController, _tackled: PlayerController) -> void:
	if _active and _armed:
		_resolve(true, "")


func _on_rival_disposed(_action: Tuning.Action) -> void:
	if _active and _armed:
		_resolve(false, "got the disposal away")


func _resolve(hit: bool, reason: String) -> void:
	_armed = false
	_attempts_used += 1
	if hit:
		_hits += 1
		tackle_hit.emit(_hits, _attempts_used)
		hint_changed.emit("Tackled!   %d/%d" % [_hits, Tuning.TACKLE_CHALLENGE_ATTEMPTS])
	else:
		tackle_missed.emit(_attempts_used, reason)
		hint_changed.emit("Missed (%s) — %d left." % [reason, Tuning.TACKLE_CHALLENGE_ATTEMPTS - _attempts_used])

	if _attempts_used >= Tuning.TACKLE_CHALLENGE_ATTEMPTS:
		_active = false
		_disconnect_rival()
		challenge_ended.emit(_hits, Tuning.TACKLE_CHALLENGE_ATTEMPTS)
	else:
		_schedule(Tuning.TACKLE_CHALLENGE_NEXT_DELAY, _deliver)


func _connect_rival() -> void:
	if not is_instance_valid(_rival):
		return
	if not _rival.holding_the_ball_called.is_connected(_on_rival_tackled):
		_rival.holding_the_ball_called.connect(_on_rival_tackled)
	if not _rival.field_ball_up_called.is_connected(_on_rival_ball_up):
		_rival.field_ball_up_called.connect(_on_rival_ball_up)
	if not _rival.ball_disposed.is_connected(_on_rival_disposed):
		_rival.ball_disposed.connect(_on_rival_disposed)


func _disconnect_rival() -> void:
	if not is_instance_valid(_rival):
		return
	if _rival.holding_the_ball_called.is_connected(_on_rival_tackled):
		_rival.holding_the_ball_called.disconnect(_on_rival_tackled)
	if _rival.field_ball_up_called.is_connected(_on_rival_ball_up):
		_rival.field_ball_up_called.disconnect(_on_rival_ball_up)
	if _rival.ball_disposed.is_connected(_on_rival_disposed):
		_rival.ball_disposed.disconnect(_on_rival_disposed)
