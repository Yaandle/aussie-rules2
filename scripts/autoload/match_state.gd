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
signal quarter_changed(quarter: int)

## AFL scoring: a goal is 6 points, a behind is 1.
const GOAL_POINTS := 6
const BEHIND_POINTS := 1

var goals := {Tuning.Team.HOME: 0, Tuning.Team.AWAY: 0}
var behinds := {Tuning.Team.HOME: 0, Tuning.Team.AWAY: 0}

## Basic AFL box-score stats (design brief: "tally disposals/marks/tackles
## per team by counting the same signals already used for audio" — see
## HANDOVER.md (archived, see docs/LESSONS.md)). Recorded by full_game.gd only (Kick-to-Kick has no
## clock/scoring either, and never calls reset(), so it never touches
## these) via record_disposal/record_mark/record_tackle, read fresh by
## MatchEndScreen the same way it already reads goals/behinds through
## scoreline(). Bounces aren't tracked — not a real AFL box-score stat.
var kicks := {Tuning.Team.HOME: 0, Tuning.Team.AWAY: 0}
var handballs := {Tuning.Team.HOME: 0, Tuning.Team.AWAY: 0}
var marks := {Tuning.Team.HOME: 0, Tuning.Team.AWAY: 0}
var tackles := {Tuning.Team.HOME: 0, Tuning.Team.AWAY: 0}

## Per-player box score for Career mode (id -> {stat: int}, PLAYER_STATS
## below) — the full-time leaderboards and the season stats both come from
## it. Keyed by PlayerController.roster_id, which is only ever non-empty in
## a Career match (see player_controller.gd), so this simply never gains
## an entry outside Career and nothing non-Career reads it. Keyed by id,
## not name: generated names repeat (about 3 matches in 4 have two players
## sharing one), and a name key merged their tallies. player_names maps
## each id back to the name a leaderboard shows. full_game.gd calls
## record_player_stat() alongside the existing team-keyed record_*()/
## score() calls, not instead of them.
const PLAYER_STATS := ["kicks", "handballs", "marks", "tackles", "goals", "behinds", "hitouts"]
var player_stats := {}
var player_names := {}

var quarter := 1
var clock_running := false
var seconds_remaining := Tuning.QUARTER_LENGTH

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


func record_disposal(team: Tuning.Team, action: Tuning.Action) -> void:
	if team == Tuning.Team.NONE:
		return
	match action:
		Tuning.Action.KICK:
			kicks[team] += 1
		Tuning.Action.HANDBALL:
			handballs[team] += 1


## `id`/`name` are a PlayerController's roster_id/roster_name — empty for
## every non-Career spawn, and the team-keyed tallies are what every other
## screen (MatchEndScreen) still reads, so an empty id is simply ignored
## rather than guarded against at every call site. `stat` is one of
## PLAYER_STATS.
func record_player_stat(id: String, name: String, stat: String) -> void:
	if id.is_empty():
		return
	player_names[id] = name
	if not player_stats.has(id):
		player_stats[id] = {}
	var row: Dictionary = player_stats[id]
	row[stat] = int(row.get(stat, 0)) + 1


## One player's count of a PLAYER_STATS entry, or "disposals" (kicks +
## handballs, the AFL box-score total).
func player_stat(id: String, stat: String) -> int:
	var row: Dictionary = player_stats.get(id, {})
	if stat == "disposals":
		return int(row.get("kicks", 0)) + int(row.get("handballs", 0))
	return int(row.get(stat, 0))


## Top `count` {name, value} entries for `stat` among players with at
## least one, highest first, ties broken by name — shared by
## top_goalkickers()/top_disposals() below.
func _top(stat: String, count: int) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for id: String in player_stats:
		var value := player_stat(id, stat)
		if value > 0:
			entries.append({"name": String(player_names.get(id, id)), "value": value})
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["value"] != b["value"]:
			return a["value"] > b["value"]
		return a["name"] < b["name"])
	return entries.slice(0, mini(count, entries.size()))


func top_goalkickers(count: int) -> Array[Dictionary]:
	return _top("goals", count)


func top_disposals(count: int) -> Array[Dictionary]:
	return _top("disposals", count)


func record_mark(team: Tuning.Team) -> void:
	if team != Tuning.Team.NONE:
		marks[team] += 1


func record_tackle(team: Tuning.Team) -> void:
	if team != Tuning.Team.NONE:
		tackles[team] += 1


func reset() -> void:
	goals = {Tuning.Team.HOME: 0, Tuning.Team.AWAY: 0}
	behinds = {Tuning.Team.HOME: 0, Tuning.Team.AWAY: 0}
	kicks = {Tuning.Team.HOME: 0, Tuning.Team.AWAY: 0}
	handballs = {Tuning.Team.HOME: 0, Tuning.Team.AWAY: 0}
	marks = {Tuning.Team.HOME: 0, Tuning.Team.AWAY: 0}
	tackles = {Tuning.Team.HOME: 0, Tuning.Team.AWAY: 0}
	player_stats = {}
	player_names = {}
	quarter = 1
	seconds_remaining = Tuning.QUARTER_LENGTH
	clock_running = false
	possession = Tuning.Team.NONE
	score_changed.emit(Tuning.Team.HOME)
	score_changed.emit(Tuning.Team.AWAY)
	clock_changed.emit(seconds_remaining)
	quarter_changed.emit(quarter)


## Starts `number` with a fresh clock. Does not touch scores — only
## `reset()` (a whole new match) does that.
func start_quarter(number: int) -> void:
	quarter = number
	seconds_remaining = Tuning.QUARTER_LENGTH
	clock_running = false
	quarter_changed.emit(quarter)
	clock_changed.emit(seconds_remaining)


func is_full_time() -> bool:
	return quarter >= Tuning.QUARTERS_PER_MATCH and seconds_remaining <= 0.0
