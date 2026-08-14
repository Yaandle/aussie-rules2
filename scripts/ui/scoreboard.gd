class_name Scoreboard
extends CanvasLayer

## Always-visible match state: score, clock, quarter.
##
## Distinct from DebugHud, which is a toggleable diagnostic overlay for
## judging feel — this is what a player is actually meant to read while
## playing, so unlike DebugHud it has no visibility toggle.

@onready var _label: Label = $Label

## While > 0, a transient message (see flash()) is showing instead of the
## normal readout — used for "GOAL!", "QUARTER TIME", "FULL TIME".
var _banner_timer := 0.0


func _ready() -> void:
	MatchState.score_changed.connect(func(_team: Tuning.Team) -> void: _refresh())
	MatchState.clock_changed.connect(func(_seconds: float) -> void: _refresh())
	MatchState.quarter_changed.connect(func(_quarter: int) -> void: _refresh())
	_refresh()


func _process(delta: float) -> void:
	if _banner_timer <= 0.0:
		return
	_banner_timer = maxf(0.0, _banner_timer - delta)
	if _banner_timer <= 0.0:
		_refresh()


## Replaces the readout with `text` for `duration` seconds, then reverts.
func flash(text: String, duration := 2.5) -> void:
	_label.text = text
	_banner_timer = duration


func _refresh() -> void:
	if _banner_timer > 0.0:
		return
	_label.text = _compose()


func _compose() -> String:
	var total := maxi(int(ceil(MatchState.seconds_remaining)), 0)
	var minutes := total / 60
	var seconds := total % 60
	return "HOME  %s      Q%d   %02d:%02d      %s  AWAY" % [
		MatchState.scoreline(Tuning.Team.HOME), MatchState.quarter, minutes, seconds,
		MatchState.scoreline(Tuning.Team.AWAY)]
