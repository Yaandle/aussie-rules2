extends Node

## Score, clock and possession.
##
## Kept separate from GameState on purpose: a scenario or a practice range
## has a phase machine but no meaningful scoreboard, and Full Game has
## both. Prototype 1's audit found its scoreboard silently hardwired the
## opponent's score to zero — one team's score living somewhere different
## from the other's is exactly how that happens. Here both sides go
## through the same call.
##
## Tuning.Team is the canonical team enum. It lives there rather than
## here because an autoload's enums cannot be used as type annotations
## the way a global class's can.

signal score_changed(team: Tuning.Team)
signal clock_changed(seconds_remaining: float)
signal possession_changed(team: Tuning.Team)

## AFL scoring: a goal is 6 points, a behind is 1.
const GOAL_POINTS := 6
const BEHIND_POINTS := 1

## P1 used a 180s single quarter (QUARTER_LENGTH) as a prototype
## compression of a real 20-minute quarter plus time-on. Kept as the
## default until Full Game exists and can justify something longer.
const QUARTER_LENGTH := 180.0

var goals := {Tuning.Team.HOME: 0, Tuning.Team.AWAY: 0}
var behinds := {Tuning.Team.HOME: 0, Tuning.Team.AWAY: 0}

var clock_running := false
var seconds_remaining := QUARTER_LENGTH

var possession: Tuning.Team = Tuning.Team.NONE:
	set(value):
		if possession == value:
			return
		possession = value
		_possession_seconds = 0.0
		possession_changed.emit(possession)

## Seconds since the current carrier gained the ball. Prototype 1's
## possession_held_timer, which its holding-the-ball ruling reads against
## PRIOR_OPPORTUNITY_GRACE (0.5s). Ticks here so the rule has one source
## of truth when tackles land.
var _possession_seconds := 0.0


func _process(delta: float) -> void:
	if possession != Tuning.Team.NONE:
		_possession_seconds += delta
	if clock_running and seconds_remaining > 0.0:
		seconds_remaining = maxf(0.0, seconds_remaining - delta)
		clock_changed.emit(seconds_remaining)


func possession_seconds() -> float:
	return _possession_seconds


func score(team: Tuning.Team, is_goal: bool) -> void:
	if team == Tuning.Team.NONE:
		return
	if is_goal:
		goals[team] += 1
	else:
		behinds[team] += 1
	score_changed.emit(team)


func points(team: Tuning.Team) -> int:
	if team == Tuning.Team.NONE:
		return 0
	return goals[team] * GOAL_POINTS + behinds[team] * BEHIND_POINTS


func scoreline(team: Tuning.Team) -> String:
	if team == Tuning.Team.NONE:
		return "-"
	return "%d.%d (%d)" % [goals[team], behinds[team], points(team)]


func reset() -> void:
	goals = {Tuning.Team.HOME: 0, Tuning.Team.AWAY: 0}
	behinds = {Tuning.Team.HOME: 0, Tuning.Team.AWAY: 0}
	seconds_remaining = QUARTER_LENGTH
	clock_running = false
	possession = Tuning.Team.NONE
	score_changed.emit(Tuning.Team.HOME)
	score_changed.emit(Tuning.Team.AWAY)
	clock_changed.emit(seconds_remaining)
