class_name CoachChallenge
extends Node3D

## Shared shape behind kick_challenge.gd/mark_challenge.gd/tackle_challenge.gd:
## every coach mini-game tracks the same attempts/hits/active/armed
## bookkeeping and the same delay-then-fire-callback timer. Each subclass's
## own header comment explains why delivery/resolution logic stays separate
## rather than being folded fully together — this base only lifts the parts
## that were byte-for-byte identical across all three.

signal challenge_started(attempts_total: int)
signal challenge_ended(hits: int, attempts_total: int)
signal hint_changed(text: String)

var _attempts_used := 0
var _hits := 0
var _active := false

## True from the moment an attempt is launched (kick struck, ball delivered,
## rival handed the ball) until it resolves — the gate that stops one
## attempt being counted twice or a stray settle from an earlier attempt
## being counted again.
var _armed := false

var _timer := 0.0
var _pending_callback := Callable()


func _schedule(delay: float, callback: Callable) -> void:
	_timer = delay
	_pending_callback = callback


## Ticks the delay-then-callback timer one physics step. Returns true if the
## timer was running (caller should stop processing this frame), matching
## the "if _timer > 0.0: ...; return" shape every caller used inline before.
func _tick_schedule(delta: float) -> bool:
	if _timer <= 0.0:
		return false
	_timer = maxf(0.0, _timer - delta)
	if _timer <= 0.0 and _pending_callback.is_valid():
		var callback := _pending_callback
		_pending_callback = Callable()
		callback.call()
	return true
