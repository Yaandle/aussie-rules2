extends Node3D

## AI testing mode (companion to full_game.gd): the same match loop, but
## driven by AiTestConfig instead of Full Game's fixed TEAM_SIZE/kickoff
## spread, so AI behaviour can actually be iterated on rather than only
## ever played against at the one fixed shape Full Game hard-codes.
##
## Deliberately a near-duplicate of full_game.gd's match state machine
## rather than a shared base class — that machine (kickoff -> bounce ->
## play -> score/quarter loop) is exactly what a testing mode needs too,
## and factoring out a shared base now, before this mode has actually
## been used to tune anything, risks guessing the wrong seam. Revisit if
## the two scripts drift apart in a way worth reconciling.
##
## What's actually different from Full Game:
## - team_size, controlled_team/controlled_index and freeze_home/away all
##   come from AiTestConfig (set by ai_test_screen.gd) instead of being
##   fixed.
## - controlled_team can be Tuning.Team.NONE: no HumanBrain anywhere, both
##   teams run AIBrain, camera just follows the home team's first slot —
##   an AI-vs-AI spectator run.
## - freeze_home/freeze_away swap AIBrain for a plain PlayerBrain (a
##   no-op — see player_brain.gd's base implementation) on that team's AI
##   players, so the other team's behaviour can be watched in isolation.
## - use_formation_start spawns from TeamFormation's positions instead of
##   the even kickoff spread.

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")

const KICKOFF_DEPTH := 30.0     ## m from centre each team lines up at

@onready var _field: Field = $Field
@onready var _ball: Ball = $Ball
@onready var _camera: BroadcastCamera = $BroadcastCamera
@onready var _hud: DebugHud = $DebugHud
@onready var _scoreboard: Scoreboard = $Scoreboard

var _team_size: int
var _controlled_team: Tuning.Team
var _controlled_index: int

var _home_players: Array[PlayerController] = []
var _away_players: Array[PlayerController] = []

var _pause_timer := 0.0
var _pause_callback := Callable()


func _ready() -> void:
	GameState.mode = GameState.Mode.FULL_GAME
	MatchState.reset()

	_team_size = AiTestConfig.team_size
	_controlled_team = AiTestConfig.controlled_team
	_controlled_index = clampi(AiTestConfig.controlled_index, 0, _team_size - 1)

	_field.scored.connect(_on_scored)

	_spawn_teams()

	var controlled_list := _team_list(_controlled_team)
	_hud.player = controlled_list[_controlled_index] if not controlled_list.is_empty() else null
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
		get_tree().change_scene_to_file("res://scenes/ui/ai_test_screen.tscn")
	elif event.is_action_pressed(&"debug_reset"):
		_reset_ball()


# ── Setup ────────────────────────────────────────────────────────────

func _spawn_teams() -> void:
	_home_players = _spawn_team(Tuning.Team.HOME, 1.0, AiTestConfig.freeze_home)
	_away_players = _spawn_team(Tuning.Team.AWAY, -1.0, AiTestConfig.freeze_away)

	var controlled_list := _team_list(_controlled_team)
	if not controlled_list.is_empty():
		var human := controlled_list[_controlled_index]
		human.set_brain(HumanBrain.new())
		human.camera = _camera.camera()
		_camera.target = human
	else:
		# Spectator run: nobody is human-controlled, so the camera just
		# frames the home team's first slot instead of sitting at the
		# origin with nothing to follow.
		_camera.target = _home_players[0] if not _home_players.is_empty() else null

	_camera.ball = _ball
	_camera.recenter()


func _spawn_team(team: Tuning.Team, attack_direction: float, frozen: bool) -> Array[PlayerController]:
	var players: Array[PlayerController] = []
	var slots := _kickoff_slots(attack_direction)
	for i in _team_size:
		var instance := PLAYER_SCENE.instantiate() as PlayerController
		instance.team = team
		(instance.get_node("Rig") as PlaceholderRig).away_kit = team == Tuning.Team.AWAY

		# See full_game.gd's _spawn_team for why position is set before
		# add_child(): the same physics-server registration ordering
		# applies here unchanged.
		var slot := slots[i]
		instance.position = slot
		add_child(instance)

		if frozen:
			instance.set_brain(PlayerBrain.new())
		else:
			var brain := AIBrain.new()
			brain.ball = _ball
			brain.home_position = slot
			brain.attack_direction = attack_direction
			instance.set_brain(brain)

		players.append(instance)
	return players


func _kickoff_slots(attack_direction: float) -> Array[Vector3]:
	if AiTestConfig.use_formation_start:
		return TeamFormation.world_positions(_team_size, attack_direction)
	var slots: Array[Vector3] = []
	for i in _team_size:
		slots.append(_kickoff_slot(i, attack_direction))
	return slots


## Same even spread as full_game.gd's _kickoff_slot.
func _kickoff_slot(index: int, attack_direction: float) -> Vector3:
	var spread := Tuning.FIELD_WIDTH * 0.6
	var z := lerpf(-spread * 0.5, spread * 0.5,
		float(index) / maxf(1.0, float(_team_size - 1)))
	var x := -attack_direction * KICKOFF_DEPTH
	return Vector3(x, 0.0, z)


func _reposition_kickoff() -> void:
	var home_slots := _kickoff_slots(1.0)
	var away_slots := _kickoff_slots(-1.0)
	for i in _home_players.size():
		_home_players[i].global_position = home_slots[i]
	for i in _away_players.size():
		_away_players[i].global_position = away_slots[i]


func _team_list(team: Tuning.Team) -> Array[PlayerController]:
	match team:
		Tuning.Team.HOME:
			return _home_players
		Tuning.Team.AWAY:
			return _away_players
		_:
			return []


# ── Match flow ───────────────────────────────────────────────────────
# Identical to full_game.gd — see there for rationale on the
# pause-timer-and-callback shape.

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
		return
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
# Identical to full_game.gd.

const BALL_LOST_BELOW := -5.0

func _check_out_of_bounds() -> void:
	if _ball.is_held:
		return
	var pos := _ball.global_position

	if pos.y < BALL_LOST_BELOW \
			or absf(pos.x) > Tuning.FIELD_HALF_LENGTH + Field.SURROUND_MARGIN \
			or absf(pos.z) > Tuning.FIELD_HALF_WIDTH + Field.SURROUND_MARGIN:
		_reset_ball()
		return

	if not _ball.is_settled() or _field.is_inside_oval(pos):
		return
	var radial := sqrt(pow(pos.x / Tuning.FIELD_HALF_LENGTH, 2.0)
		+ pow(pos.z / Tuning.FIELD_HALF_WIDTH, 2.0))
	var scale := 0.97 / maxf(radial, 0.001)
	_ball.reset_at(Vector3(pos.x * scale, 0.3, pos.z * scale))


func _reset_ball() -> void:
	for player in _home_players + _away_players:
		player.drop_ball()
	_ball.reset_at(_field.centre())


# ── Human control ────────────────────────────────────────────────────

func _switch_human_player() -> void:
	var list := _team_list(_controlled_team)
	if list.size() <= 1:
		return
	var previous := list[_controlled_index]
	_controlled_index = (_controlled_index + 1) % list.size()
	var next := list[_controlled_index]

	var frozen := (_controlled_team == Tuning.Team.HOME and AiTestConfig.freeze_home) \
		or (_controlled_team == Tuning.Team.AWAY and AiTestConfig.freeze_away)
	if frozen:
		previous.set_brain(PlayerBrain.new())
	else:
		var ai := AIBrain.new()
		ai.ball = _ball
		ai.home_position = previous.global_position
		ai.attack_direction = 1.0 if _controlled_team == Tuning.Team.HOME else -1.0
		previous.set_brain(ai)
	previous.camera = null

	next.set_brain(HumanBrain.new())
	next.camera = _camera.camera()
	_camera.target = next
	_camera.recenter()

	_hud.player = next
