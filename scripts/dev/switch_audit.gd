extends Node

## Auto-switch audit (2026-11-26): on an AI-v-AI Full Game, every kick is
## followed from the boot to where its flight ends (caught, spoiled or
## grounded: "the fall of the ball"). AUTO_SWITCH_DELAY after the kick it
## takes both drop estimates (Ball.predicted_landing_position, which the
## auto-switch used, and Ball.predicted_drop, drag included, at hand
## height) and asks whether the HOME player nearest each estimate is the
## HOME player nearest where the ball really came down.
##
## Godot --headless --fixed-fps 60 --path . res://scenes/dev/switch_audit.tscn -- --seconds=240
## Prints SWITCH_AUDIT lines.

const FULL_GAME := "res://scenes/modes/full_game.tscn"

var _game: Node
var _ball: Ball
var _home: Array = []
var _seconds := 240.0
var _sim := 0.0
var _was_flight := false
var _kick: Dictionary = {}
var _rows: Array[Dictionary] = []


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seconds="):
			_seconds = float(arg.get_slice("=", 1))
	HighlightPrefs.transient = true
	GameState.career_active = false
	Settings.player_control_mode = Settings.PlayerControlMode.SINGLE_PLAYER
	_game = (load(FULL_GAME) as PackedScene).instantiate()
	add_child(_game)
	var human := ControlMode.controlled_player(Tuning.Team.HOME)
	var slot: int = (_game.get("_home_players") as Array).find(human)
	human.set_brain(_game.call("_configure_ai_brain", AIBrain.new(), Tuning.Team.HOME, 1.0,
		_game.call("_kickoff_slot", slot, 1.0, Tuning.Team.HOME)))
	_ball = _game.get("_ball")
	_home = _game.get("_home_players")


func _process(delta: float) -> void:
	_sim += delta
	var flight := _ball.is_kick_flight()
	if flight and not _was_flight:
		_kick = {"t": _sim, "from": _ball.global_position}
	if flight and not _kick.is_empty() and not _kick.has("old") \
			and _sim - float(_kick.t) >= Tuning.AUTO_SWITCH_DELAY:
		_kick["old"] = _ball.predicted_landing_position()
		_kick["new"] = _ball.predicted_drop(Tuning.AUTO_SWITCH_DROP_HEIGHT)
		_kick["pos"] = _home.map(func(p: PlayerController) -> Vector3: return p.global_position)
	if _was_flight and not flight and _kick.has("old"):
		_kick["end"] = _ball.global_position
		_rows.append(_kick)
	if not flight and _was_flight:
		_kick = {}
	_was_flight = flight
	if _sim >= _seconds:
		_report()
		get_tree().quit()


func _report() -> void:
	var n := 0
	var err_old := 0.0
	var err_new := 0.0
	var right_old := 0
	var right_new := 0
	for row in _rows:
		var end: Vector3 = row.end
		var from: Vector3 = row.from
		if Vector2(end.x - from.x, end.z - from.z).length() < 15.0:
			continue   # short kicks: nothing to switch for
		n += 1
		err_old += _flat(row.old, end)
		err_new += _flat(row.new, end)
		var truth := _nearest(row.pos, end)
		right_old += int(_nearest(row.pos, row.old) == truth)
		right_new += int(_nearest(row.pos, row.new) == truth)
	n = maxi(n, 1)
	print("SWITCH_AUDIT kicks=%d (of %d) drop_error_m old=%.1f new=%.1f right_player old=%d%% new=%d%%" % [
		n, _rows.size(), err_old / n, err_new / n, roundi(100.0 * right_old / n), roundi(100.0 * right_new / n)])


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


static func _nearest(positions: Array, spot: Vector3) -> int:
	var best := -1
	var best_d := INF
	for i in positions.size():
		var d := _flat(positions[i], spot)
		if d < best_d:
			best_d = d
			best = i
	return best
