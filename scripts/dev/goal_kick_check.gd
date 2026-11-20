extends Node3D

## Dev check: how well the AI kicks for goal from where it should score.
## Runs an all-AI Full Game headless (kick_turnover_check's setup) and
## stages shots one at a time, the way highlight_generator does: the
## nearest player of a side gets the ball at a spot, protected as after a
## mark, faced toward goal, and his AIBrain does what it does. Each shot is
## followed to its result:
##
##   goal / behind - Field.scored
##   short         - the ball came down before the goal line
##   wide          - it crossed the goal line wide of the behind posts
##   no_shot       - he handballed or kicked somewhere else (a pass)
##   smothered     - it never got near the line (a smother, a touch)
##
## and, for every kick at goal, where it crossed the goal line (metres off
## centre, + the far side) or how far short it came down. The grid is every
## STAGE_DISTANCES x STAGE_LATERAL spot, from both ends, ROUNDS times.
##
## --live instead plays the match untouched for --seconds and follows every
## kick a player takes toward the goal he attacks from within LIVE_RANGE of
## it: the shots the AI takes on its own, on the run and under pressure,
## which is what a match shows. Staged shots start square to goal; live
## ones are the real test.
##
## Written for the 2026-11-21 note "the AI misses even when within range".
##
##   Godot_console.exe --headless --path . res://scenes/dev/goal_kick_check.tscn --fixed-fps 60 -- --rounds=2 --seed=1
##   Godot_console.exe --headless --path . res://scenes/dev/goal_kick_check.tscn --fixed-fps 60 -- --live --seconds=600 --seed=1

const FULL_GAME := "res://scenes/modes/full_game.tscn"
const STAGE_DISTANCES := [15.0, 25.0, 35.0, 45.0]
const STAGE_LATERAL := [0.0, 10.0, 20.0]
## How long a shot is followed before it counts as finished (s).
const FOLLOW_TIME := 7.0
## --live: a kick toward goal from this close (m from the goal line) is a shot.
const LIVE_RANGE := 55.0

var _rounds := 2
var _live := false
var _seconds := 600.0
var _sim := 0.0
var _verbose := false
var _game: Node
var _ball: Ball
var _field: Field
var _queue: Array = []        # [team, distance, lateral]
var _shot := {}               # the shot being followed
var _wait := 2.0
var _results: Array = []
var _last_aim := {}           # player -> its brain's last kick target


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		var kv := arg.trim_prefix("--").split("=", true, 1)
		match kv[0]:
			"rounds": _rounds = int(kv[1])
			"seed": seed(int(kv[1]))
			"verbose": _verbose = true
			"live": _live = true
			"seconds": _seconds = float(kv[1])
	HighlightPrefs.transient = true
	GameState.career_active = false
	Settings.player_control_mode = Settings.PlayerControlMode.SINGLE_PLAYER
	_game = (load(FULL_GAME) as PackedScene).instantiate()
	add_child(_game)
	var human := ControlMode.controlled_player(Tuning.Team.HOME)
	if human != null:
		var slot: int = (_game.get("_home_players") as Array).find(human)
		human.set_brain(_game.call("_configure_ai_brain", AIBrain.new(), Tuning.Team.HOME, 1.0,
			_game.call("_kickoff_slot", slot, 1.0, Tuning.Team.HOME)))
		ControlMode.set_controlled_player(Tuning.Team.HOME, null)
	_ball = _game.get("_ball") as Ball
	_field = _game.get("_field") as Field
	_field.scored.connect(_on_scored)
	for p: PlayerController in PlayerRegistry.all():
		p.ball_disposed.connect(_on_disposed.bind(p))
	if _live:
		return
	for r in _rounds:
		for d: float in STAGE_DISTANCES:
			for z: float in STAGE_LATERAL:
				for team in [Tuning.Team.HOME, Tuning.Team.AWAY]:
					_queue.append([team, d, z if r % 2 == 0 else -z])


func _physics_process(delta: float) -> void:
	_sim += delta
	# The brain's kick target, remembered while it's set: it clears on the
	# execute frame, before the ball leaves the boot.
	for p: PlayerController in PlayerRegistry.all():
		var t: Variant = p.brain().kick_aim_point()
		if t != null:
			_last_aim[p] = t
		elif not p.is_carrying():
			_last_aim.erase(p)
	if _live and _sim >= _seconds and _shot.is_empty():
		_report()
		return
	if _shot.is_empty() and _live:
		return
	if _shot.is_empty():
		_wait -= delta
		if _wait <= 0.0:
			if _queue.is_empty():
				_report()
				return
			_stage()
		return
	_shot.t += delta
	var dir: float = _shot.dir
	var line: float = _field.goal_line_x(int(dir))
	if _shot.has("kicked") and not _shot.has("result"):
		var p := _ball.global_position
		if (p.x - line) * dir >= 0.0 and not _shot.has("cross"):
			_shot.cross = p.z * signf(_shot.lateral if _shot.lateral != 0.0 else 1.0)
			_shot.cross_y = p.y
		elif not _ball.is_airborne() and _shot.t - float(_shot.kicked) > 0.3 and not _shot.has("cross"):
			_shot.short = absf(line - p.x)
			_finish("short")
			return
	if _shot.t >= FOLLOW_TIME and not _shot.has("result"):
		if not _shot.has("kicked"):
			_finish("no_kick")
		elif _shot.has("cross"):
			_finish("wide")
		else:
			_finish("smothered")


func _stage() -> void:
	if GameState.phase != GameState.Phase.PLAY or MatchState.seconds_remaining < 20.0 \
			or _game.call("_after_siren_active"):
		_wait = 1.0
		return
	var item: Array = _queue.pop_front()
	var team: Tuning.Team = item[0]
	var dir := 1.0 if team == Tuning.Team.HOME else -1.0
	var line := _field.goal_line_x(int(dir))
	var spot := Vector3(line - dir * float(item[1]), 0.0, float(item[2]))
	var squad: Array = _game.get("_home_players") if team == Tuning.Team.HOME else _game.get("_away_players")
	var shooter: PlayerController = _game.call("_nearest_player", squad, spot)
	shooter.global_position = spot
	shooter.velocity = Vector3.ZERO
	shooter.face_toward(Vector3(line, 0.0, 0.0))
	_game.call("_award_possession_at", spot, shooter, false)
	_shot = {"team": team, "dir": dir, "distance": item[1], "lateral": item[2], "shooter": shooter, "t": 0.0}


func _on_disposed(action: Tuning.Action, by: PlayerController) -> void:
	if _live and _shot.is_empty() and action == Tuning.Action.KICK:
		var d := 1.0 if by.team == Tuning.Team.HOME else -1.0
		var from_line := absf(_field.goal_line_x(int(d)) - by.global_position.x)
		var v := _ball.linear_velocity
		v.y = 0.0
		# Only the brain's own shots: a kick whose target was the goal's
		# centre, not a forward pass.
		if from_line <= LIVE_RANGE and _is_shot(by):
			# Bucketed to the staged grid's distances for the report.
			var bucket: float = STAGE_DISTANCES[-1]
			for b: float in STAGE_DISTANCES:
				if from_line <= b + 5.0:
					bucket = b
					break
			if from_line > STAGE_DISTANCES[-1] + 5.0:
				bucket = 55.0
			_shot = {"team": by.team, "dir": d, "distance": bucket, "lateral": by.global_position.z,
				"shooter": by, "t": 0.0}
	if _shot.is_empty() or _shot.has("kicked") or by != _shot.shooter:
		return
	if action != Tuning.Action.KICK:
		_finish("no_shot")
		return
	# A kick at goal heads for the posts: one that goes backwards or across
	# is a pass.
	var dir: float = _shot.dir
	var fwd := Vector3(dir, 0.0, 0.0)
	var v := _ball.linear_velocity
	v.y = 0.0
	if v.length() < 0.1 or v.normalized().dot(fwd) < 0.5 or not _is_shot(by):
		_finish("no_shot")
		return
	_shot.kicked = _shot.t
	_shot.charge = by.kick_charge()
	# The flat line of the kick against the line to the goal's centre.
	var to_goal := Vector3(_field.goal_line_x(int(dir)), 0.0, 0.0) - by.global_position
	to_goal.y = 0.0
	_shot.aim_err = rad_to_deg(v.normalized().signed_angle_to(to_goal.normalized(), Vector3.UP))


## Was this kick the brain's own shot at goal (its target the goal's
## centre), not a pass? Needs AIBrain.kick_aim_point (2026-11-21); an older
## brain without it counts every forward kick, so compare like with like.
func _is_shot(by: PlayerController) -> bool:
	if not by.brain().has_method("kick_aim_point"):
		return true
	var target: Variant = _last_aim.get(by, null)
	var d := 1.0 if by.team == Tuning.Team.HOME else -1.0
	return target is Vector3 and absf((target as Vector3).z) < 0.01 		and absf(absf((target as Vector3).x) - absf(_field.goal_line_x(int(d)))) < 0.01


func _on_scored(team: Tuning.Team, is_goal: bool) -> void:
	if _shot.is_empty() or _shot.has("result") or team != _shot.team:
		return
	_finish("goal" if is_goal else "behind")


func _finish(result: String) -> void:
	_shot.result = result
	_shot.erase("shooter")
	_results.append(_shot)
	if _verbose:
		print("GOAL_KICK %s d=%.0f z=%.0f %s charge=%.2f aim_err=%s cross=%s short=%s" % [
			"HOME" if _shot.team == Tuning.Team.HOME else "AWAY", _shot.distance, _shot.lateral, result,
			float(_shot.get("charge", -1.0)), str(snappedf(float(_shot.get("aim_err", 0.0)), 0.1)),
			str(snappedf(float(_shot.get("cross", 99.0)), 0.1)), str(snappedf(float(_shot.get("short", -1.0)), 0.1))])
	_shot = {}
	_wait = 3.0


func _report() -> void:
	set_physics_process(false)
	var by_d := {}
	for s: Dictionary in _results:
		var row: Dictionary = by_d.get(s.distance, {})
		row[s.result] = int(row.get(s.result, 0)) + 1
		row["n"] = int(row.get("n", 0)) + 1
		by_d[s.distance] = row
	var total := {}
	for d: float in STAGE_DISTANCES + ([55.0] if _live else []):
		var row: Dictionary = by_d.get(d, {})
		var line := ("GOAL_KICK %2.0f m:" % d) if not _live else ("GOAL_KICK live <=%2.0f m:" % (d + 5.0))
		for k in ["goal", "behind", "wide", "short", "smothered", "no_shot", "no_kick"]:
			if row.has(k):
				line += " %s %d" % [k, row[k]]
				total[k] = int(total.get(k, 0)) + int(row[k])
		line += "  (n %d)" % int(row.get("n", 0))
		print(line)
	var n := _results.size()
	var line := "GOAL_KICK all:"
	for k in total:
		line += " %s %d" % [k, total[k]]
	print(line + "  goals %.0f%% of %d" % [100.0 * int(total.get("goal", 0)) / maxf(n, 1.0), n])
	var errs := []
	for s: Dictionary in _results:
		if s.has("aim_err"):
			errs.append(absf(float(s.aim_err)))
	errs.sort()
	if not errs.is_empty():
		print("GOAL_KICK aim error |deg|: median %.1f, worst %.1f" % [errs[errs.size() / 2], errs[-1]])
	get_tree().quit()
