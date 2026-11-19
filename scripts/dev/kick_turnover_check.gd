extends Node3D

## Dev check: how often an AI kick is picked up by the other side. Runs an
## all-AI Full Game headless (the generator's setup, no recorder or export)
## and follows every kick to the next player who gathers or marks the ball:
## the other team = a turnover. Kicks are split by where they were taken:
## the kicker's back 50 (kick-ins included), the rest of the back half, and
## the front half. Scoring kicks are dropped once they score.
##
## Written for the 2026-11-16 playtest note "a lot of intercepts from their
## kick-outs and back-50 kicks". AI v AI is not a human reading the play, so
## the numbers compare one build with another; they don't predict a match.
## Baseline (2026-11-16, 300 s, seeds 1 and 2): 16/39 and 16/35 kicks turned
## over; back 50 + rest of the back half 9/23 both times. A tried fix (pass
## kicks charged to the receiver's distance + an openness test that counted
## the flight) gave 11/22 and 6/12, no better, and was reverted. One run is
## about 35 kicks, so differences under ~15 points are noise: use several
## seeds.
##
##   Godot_console.exe --headless --path . res://scenes/dev/kick_turnover_check.tscn --fixed-fps 60 -- --seconds=360 --seed=1

const FULL_GAME := "res://scenes/modes/full_game.tscn"

var _seconds := 360.0
var _game: Node
var _ball: Ball
var _sim := 0.0
## The kick being followed: [team, zone, length so far unknown] or empty.
var _pending := {}
var _counts := {}   # zone -> [kicks, turnovers]


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		var kv := arg.trim_prefix("--").split("=", true, 1)
		if kv.size() != 2:
			continue
		match kv[0]:
			"seconds": _seconds = float(kv[1])
			"seed": seed(int(kv[1]))
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
	_ball.gathered.connect(_on_gathered)
	MatchState.score_changed.connect(func(_t: Tuning.Team) -> void: _pending = {})
	for p: PlayerController in PlayerRegistry.all():
		p.ball_disposed.connect(_on_disposed.bind(p))
	for zone in ["back50", "back_half", "front_half"]:
		_counts[zone] = [0, 0]


func _on_disposed(action: Tuning.Action, by: PlayerController) -> void:
	_pending = {}
	if action != Tuning.Action.KICK:
		return
	# HOME defends -X. Distance from the kicker's own goal line.
	var own_goal_x := -Tuning.FIELD_HALF_LENGTH if by.team == Tuning.Team.HOME else Tuning.FIELD_HALF_LENGTH
	var from_own := absf(by.global_position.x - own_goal_x)
	var zone := "back50" if from_own <= 50.0 else ("back_half" if from_own <= Tuning.FIELD_HALF_LENGTH else "front_half")
	_pending = {"team": by.team, "zone": zone}
	_counts[zone][0] += 1


func _on_gathered(by: Node3D) -> void:
	if _pending.is_empty() or not (by is PlayerController):
		return
	if (by as PlayerController).team != _pending.team:
		_counts[_pending.zone][1] += 1
	_pending = {}


func _physics_process(delta: float) -> void:
	_sim += delta
	if _sim >= _seconds:
		var line := "KICK_TURNOVER seconds=%d" % int(_seconds)
		var all := [0, 0]
		for zone: String in _counts:
			var c: Array = _counts[zone]
			all[0] += c[0]
			all[1] += c[1]
			line += "  %s %d/%d" % [zone, c[1], c[0]]
		line += "  all %d/%d (%.0f%%)" % [all[1], all[0], 100.0 * all[1] / maxf(all[0], 1.0)]
		print(line)
		set_physics_process(false)
		get_tree().quit()
