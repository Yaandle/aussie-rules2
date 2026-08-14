extends Node3D

## Full Game mode (design doc §7 priority 1): a small-sided match with a
## real clock, quarters, scoring, tackling and AI.
##
## Milestone 1 proved one player's physics felt weighty. This proves the
## same physics holds up as an actual game: Tuning.TEAM_SIZE a side, AI
## (ai_brain.gd) everywhere the human isn't, contests resolved physically
## via PlayerController's tackle handling, goals/behinds detected by
## Field's trigger zones. See docs/RULES_REFERENCE.md for what's a real
## AFL rule here and what's a deliberate MVP simplification.
##
## Owns the whole match state machine: kickoff formation -> centre bounce
## -> play -> (score -> pause -> re-bounce) | (quarter ends -> next
## quarter or full time). MatchState/GameState hold the data; this drives
## it, all through one pause-timer-and-callback mechanism rather than
## coroutines, so it stays simple to reason about headless.

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")

const KICKOFF_DEPTH := 30.0     ## m from centre each team lines up at

@onready var _field: Field = $Field
@onready var _ball: Ball = $Ball
@onready var _camera: BroadcastCamera = $BroadcastCamera
@onready var _hud: DebugHud = $DebugHud
@onready var _scoreboard: Scoreboard = $Scoreboard

var _home_players: Array[PlayerController] = []
var _away_players: Array[PlayerController] = []
var _controlled_index := 0

var _pause_timer := 0.0
var _pause_callback := Callable()


func _ready() -> void:
	GameState.mode = GameState.Mode.FULL_GAME
	MatchState.reset()

	_field.scored.connect(_on_scored)

	_spawn_teams()
	_hud.player = _home_players[_controlled_index]
	_hud.ball = _ball

	_start_match()


func _physics_process(delta: float) -> void:
	_check_out_of_bounds()

	if _pause_timer > 0.0:
		_pause_timer = maxf(0.0, _pause_timer - delta)
		if _pause_timer <= 0.0 and _pause_callback.is_valid():
			var callback := _pause_callback
			_pause_callback = Callable()
			callback.call()
		return

	if MatchState.clock_running and MatchState.seconds_remaining <= 0.0:
		_end_quarter()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"switch_player"):
		_switch_human_player()
	elif event.is_action_pressed(&"pause"):
		get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")


# ── Setup ────────────────────────────────────────────────────────────

func _spawn_teams() -> void:
	_home_players = _spawn_team(Tuning.Team.HOME, 1.0)
	_away_players = _spawn_team(Tuning.Team.AWAY, -1.0)

	_home_players[0].set_brain(HumanBrain.new())
	_home_players[0].camera = _camera.camera()
	_camera.target = _home_players[0]
	_camera.ball = _ball
	_camera.recenter()


func _spawn_team(team: Tuning.Team, attack_direction: float) -> Array[PlayerController]:
	var players: Array[PlayerController] = []
	for i in Tuning.TEAM_SIZE:
		var instance := PLAYER_SCENE.instantiate() as PlayerController
		instance.team = team
		# Set before add_child(), so PlaceholderRig._ready() builds with
		# the right kit colour the first time round.
		(instance.get_node("Rig") as PlaceholderRig).away_kit = team == Tuning.Team.AWAY
		add_child(instance)

		var slot := _kickoff_slot(i, attack_direction)
		instance.global_position = slot

		var brain := AIBrain.new()
		brain.ball = _ball
		brain.home_position = slot
		brain.attack_direction = attack_direction
		instance.set_brain(brain)

		players.append(instance)
	return players


## A simple spread in the team's own half — not a real formation, just
## enough that a kickoff doesn't start with everyone stacked on the
## centre circle. TEAM_SIZE evenly spans the width at one depth.
func _kickoff_slot(index: int, attack_direction: float) -> Vector3:
	var spread := Tuning.FIELD_WIDTH * 0.6
	var z := lerpf(-spread * 0.5, spread * 0.5,
		float(index) / maxf(1.0, float(Tuning.TEAM_SIZE - 1)))
	var x := -attack_direction * KICKOFF_DEPTH
	return Vector3(x, 0.0, z)


func _reposition_kickoff() -> void:
	for i in _home_players.size():
		_home_players[i].global_position = _kickoff_slot(i, 1.0)
	for i in _away_players.size():
		_away_players[i].global_position = _kickoff_slot(i, -1.0)


# ── Match flow ───────────────────────────────────────────────────────

func _start_match() -> void:
	MatchState.start_quarter(1)
	_prepare_centre_bounce()


func _prepare_centre_bounce() -> void:
	GameState.phase = GameState.Phase.CENTRE_BOUNCE
	MatchState.clock_running = false
	for player in _home_players + _away_players:
		player.drop_ball()
	_reposition_kickoff()
	_ball.reset_at(_field.centre())
	_start_pause(Tuning.CENTRE_BOUNCE_DELAY, _bounce_off)


func _bounce_off() -> void:
	_ball.launch(Vector3.UP, Tuning.BOUNCE_SPEED, Vector3.ZERO, null)
	GameState.phase = GameState.Phase.PLAY
	MatchState.clock_running = true


func _on_scored(team: Tuning.Team, is_goal: bool) -> void:
	if GameState.phase == GameState.Phase.SCORE:
		return   # the ball can clip the trigger again while it settles
	MatchState.clock_running = false
	MatchState.score(team, is_goal)
	GameState.phase = GameState.Phase.SCORE
	var label := "GOAL" if is_goal else "BEHIND"
	_scoreboard.flash("%s! %s" % [label, _team_name(team)], Tuning.SCORE_PAUSE_DURATION)
	_camera.punch(Tuning.CAM_PUNCH_KICK)
	_start_pause(Tuning.SCORE_PAUSE_DURATION, _prepare_centre_bounce)


func _end_quarter() -> void:
	MatchState.clock_running = false
	if MatchState.quarter >= Tuning.QUARTERS_PER_MATCH:
		_finish_match()
		return
	GameState.phase = GameState.Phase.STOPPAGE
	_scoreboard.flash("END OF QUARTER %d" % MatchState.quarter, Tuning.QUARTER_BREAK_DURATION)
	_start_pause(Tuning.QUARTER_BREAK_DURATION, _next_quarter)


func _next_quarter() -> void:
	MatchState.start_quarter(MatchState.quarter + 1)
	_prepare_centre_bounce()


func _finish_match() -> void:
	GameState.phase = GameState.Phase.FINISHED
	_scoreboard.flash("FULL TIME   %s - %s" % [
		MatchState.scoreline(Tuning.Team.HOME), MatchState.scoreline(Tuning.Team.AWAY)],
		999999.0)


func _team_name(team: Tuning.Team) -> String:
	return "HOME" if team == Tuning.Team.HOME else "AWAY"


func _start_pause(duration: float, on_complete: Callable) -> void:
	_pause_timer = duration
	_pause_callback = on_complete


# ── Ball out of bounds ───────────────────────────────────────────────
# No throw-in ritual (design doc scope for this milestone, see
# RULES_REFERENCE.md) — the ball is placed back just inside the boundary
# at roughly the point it left and stays live, contestable by whoever's
# nearest.

func _check_out_of_bounds() -> void:
	if _ball.is_held or not _ball.is_settled():
		return
	var pos := _ball.global_position
	if _field.is_inside_oval(pos):
		return
	var radial := sqrt(pow(pos.x / Tuning.FIELD_HALF_LENGTH, 2.0)
		+ pow(pos.z / Tuning.FIELD_HALF_WIDTH, 2.0))
	var scale := 0.97 / maxf(radial, 0.001)
	_ball.reset_at(Vector3(pos.x * scale, 0.3, pos.z * scale))


# ── Human control ────────────────────────────────────────────────────

func _switch_human_player() -> void:
	var count := _home_players.size()
	if count <= 1:
		return
	var previous := _home_players[_controlled_index]
	_controlled_index = (_controlled_index + 1) % count
	var next := _home_players[_controlled_index]

	var ai := AIBrain.new()
	ai.ball = _ball
	ai.home_position = previous.global_position
	ai.attack_direction = 1.0
	previous.set_brain(ai)
	previous.camera = null

	next.set_brain(HumanBrain.new())
	next.camera = _camera.camera()
	_camera.target = next
	_camera.recenter()

	_hud.player = next
