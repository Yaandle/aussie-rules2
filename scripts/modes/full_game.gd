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
const PAUSE_SCREEN_SCENE := preload("res://scenes/ui/pause_screen.tscn")
const MATCH_END_SCREEN_PATH := "res://scenes/ui/match_end_screen.tscn"

const KICKOFF_DEPTH := 30.0     ## m from centre each team lines up at

@onready var _field: Field = $Field
@onready var _ball: Ball = $Ball
@onready var _camera: BroadcastCamera = $BroadcastCamera
@onready var _hud: DebugHud = $DebugHud
@onready var _scoreboard: Scoreboard = $Scoreboard

var _home_players: Array[PlayerController] = []
var _away_players: Array[PlayerController] = []
var _crosshair: KickCrosshair
var _mark_prompt: MarkPrompt

var _pause_timer := 0.0
var _pause_callback := Callable()

## Last frame's ball position while a live kick flight is being watched for
## crossing the boundary in the air — see _check_out_on_the_full(). Reset
## to invalid whenever that watch isn't active, so a stale position from a
## previous kick can never be bisected against a new one.
var _prev_ball_pos := Vector3.ZERO
var _prev_ball_pos_valid := false


func _ready() -> void:
	GameState.mode = GameState.Mode.FULL_GAME
	MatchState.reset()

	_field.scored.connect(_on_scored)
	AudioManager.register_field(_field)

	# Full Game is the one mode this option applies to (see Settings'
	# own doc comment on full_game_camera_mode) — read the saved choice
	# now, and keep it live if changed mid-match from a paused settings
	# screen rather than only taking effect on the next match.
	_apply_camera_mode(Settings.full_game_camera_mode)
	Settings.camera_mode_changed.connect(_apply_camera_mode)

	# Created before _spawn_teams() so the very first ControlMode.
	# focus_changed emission (fired synchronously by _spawn_teams()'s
	# initial set_controlled_player() call) has real nodes to bind to
	# rather than needing a separate first-assignment code path.
	_hud.ball = _ball

	_crosshair = KickCrosshair.new()
	add_child(_crosshair)

	_mark_prompt = MarkPrompt.new()
	_mark_prompt.ball = _ball
	add_child(_mark_prompt)

	_spawn_teams()
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


func _apply_camera_mode(setting: Settings.FullGameCameraMode) -> void:
	_camera.set_mode(BroadcastCamera.Mode.FULL_SIDE \
		if setting == Settings.FullGameCameraMode.FULL_SIDE else BroadcastCamera.Mode.CHASE)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"switch_player"):
		_switch_human_player()
	elif event.is_action_pressed(&"toggle_control_scheme"):
		_toggle_control_scheme()
	elif event.is_action_pressed(&"issue_command"):
		_issue_team_command()
	elif event.is_action_pressed(&"pause"):
		_open_pause_menu()
	elif event.is_action_pressed(&"debug_reset"):
		_reset_ball()


## Central reaction to ControlMode's one signal — every place that used to
## be told "here's the newly controlled/selected player" individually
## (camera, HUD, crosshair, mark-prompt) now just re-binds here instead.
## Only HOME is ever handled: AWAY never gets a focus_changed emission in
## today's modes (nothing ever calls ControlMode.set_controlled_player for
## it), but the guard keeps this correct the day something does, rather
## than silently pointing the human's own camera/UI at an AWAY player.
##
## Camera decision (documented per TASK's request not to silently pick
## one): `previous == null` means this is the very first focus this match
## has ever had — nothing meaningful to pan away from — so the camera
## snaps via recenter(). Every subsequent change, whether a SINGLE_PLAYER
## switch or a TEAM_COMMAND selection change, pans via switch_target(),
## matching the pan behaviour _switch_human_player already had before this
## pass and extending it to the new scheme rather than special-casing it.
func _on_focus_changed(team: Tuning.Team, previous: PlayerController, next: PlayerController) -> void:
	if team != Tuning.Team.HOME:
		return

	if is_instance_valid(previous) and previous != next:
		previous.camera = null

	if is_instance_valid(next):
		next.camera = _camera.camera()
		if previous == null:
			_camera.target = next
			_camera.recenter()
		else:
			_camera.switch_target(next)

	_hud.player = next
	_crosshair.player = next
	_mark_prompt.player = next


## Esc used to hard-cut straight to the main menu, discarding a match in
## progress with zero confirmation — PauseScreen already existed fully
## built and simply wasn't wired to anything (see docs/FEATURE_AUDIT.md).
## Pushed as a real paused overlay: PROCESS_MODE_ALWAYS is what lets it
## keep receiving input while get_tree().paused freezes everything else
## (players, ball, this node's own _physics_process) exactly where they are.
func _open_pause_menu() -> void:
	var pause_screen := PAUSE_SCREEN_SCENE.instantiate()
	pause_screen.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(pause_screen)
	get_tree().paused = true


# ── Setup ────────────────────────────────────────────────────────────

func _spawn_teams() -> void:
	_home_players = _spawn_team(Tuning.Team.HOME, 1.0)
	_away_players = _spawn_team(Tuning.Team.AWAY, -1.0)

	# ControlMode (control-mode pass) is the single source of truth for
	# "who's driving" from here on — this mode script still builds the
	# actual brains (only it knows the AI config: ball ref, home position,
	# attack direction), but which player is focused, and telling the
	# camera/HUD/crosshair/mark-prompt about it, is centralised in
	# _on_focus_changed() rather than repeated at every call site that
	# used to hand-roll it (see docs/HANDOVER.md's control-mode entry).
	ControlMode.reset()
	ControlMode.register_team(Tuning.Team.HOME, _home_players, ControlMode.Scheme.SINGLE_PLAYER)
	# AWAY is registered with no human ever assigned (controlled_player
	# stays null) rather than skipped — a router that only knows about
	# teams a human might drive can't answer "is anyone controlling this
	# team" for AWAY at all, and future local-multiplayer needs that
	# question answerable for every team, not just HOME's.
	ControlMode.register_team(Tuning.Team.AWAY, _away_players, ControlMode.Scheme.SINGLE_PLAYER)
	ControlMode.focus_changed.connect(_on_focus_changed)

	_camera.ball = _ball
	_home_players[0].set_brain(HumanBrain.new())
	ControlMode.set_controlled_player(Tuning.Team.HOME, _home_players[0])

	for player in _home_players + _away_players:
		player.field_ball_up_called.connect(_on_field_ball_up)
		player.holding_the_ball_called.connect(_on_holding_the_ball)
		# Box-score stats (docs/FEATURE_AUDIT.md) — bound with the player
		# itself since neither signal carries a reference to who disposed/
		# marked, only what happened.
		player.ball_disposed.connect(_on_player_disposed.bind(player))
		player.mark_caught.connect(_on_player_marked.bind(player))


func _spawn_team(team: Tuning.Team, attack_direction: float) -> Array[PlayerController]:
	var players: Array[PlayerController] = []
	for i in Tuning.TEAM_SIZE:
		var instance := PLAYER_SCENE.instantiate() as PlayerController
		instance.team = team
		# Set before add_child(), so HumanoidRig._ready() builds with
		# the right kit colour the first time round.
		(instance.get_node("Rig") as HumanoidRig).away_kit = team == Tuning.Team.AWAY

		# Position before add_child(), not after. A CharacterBody3D that
		# joins the tree registers its collision body with the physics
		# server at whatever transform it already has — the scene's
		# authored origin — and that registration isn't visible to script
		# as "wrong" but does not retroactively move once add_child()
		# returns: the physics server only picks up a transform set
		# afterward on its next flush, one full physics tick later. With
		# TEAM_SIZE*2 players all instantiated at the origin and moved to
		# their kickoff slot only after add_child(), every one of them sat
		# on top of the ball (also at the origin) for that first tick —
		# eight overlapping capsules and a ball resolved by the solver in
		# one step threw the ball across the map at thousands of m/s
		# before the match even started. Setting the transform first means
		# the body is created already at its slot; there is no origin to
		# flash through.
		# `position`, not `global_position` — the node isn't in the tree
		# yet, so there's no parent transform to resolve a global position
		# against. FullGame itself sits at identity, so the two are the
		# same value once this becomes its child.
		var slot := _kickoff_slot(i, attack_direction, team)
		instance.position = slot
		add_child(instance)
		AudioManager.register_player(instance)

		instance.set_brain(_configure_ai_brain(AIBrain.new(), team, attack_direction, slot))

		players.append(instance)
	return players


## Threads Team Edit's ball-movement/defensive-pressure tactics (formation
## is handled separately, via _kickoff_slot — this is the other half) into
## a freshly-created AIBrain. Used both here and by _switch_human_player()'s
## own hand-back AIBrain, so the two call sites can't drift about which
## settings a HOME player's AI actually gets the moment nobody's driving
## them. AWAY always keeps AIBrain's own un-tuned defaults — only the
## human's own team is something Team Edit lets them shape.
func _configure_ai_brain(brain: AIBrain, team: Tuning.Team, attack_direction: float,
		home_position: Vector3) -> AIBrain:
	brain.ball = _ball
	brain.home_position = home_position
	brain.attack_direction = attack_direction
	if team == Tuning.Team.HOME:
		brain.lateral_bias = Settings.home_lateral_bias()
		brain.press_intensity = Settings.home_press_intensity()
	return brain


## HOME (Team Edit expansion, polish-pass brief) lines up in whichever of
## Settings.FORMATION_PRESETS the Team List screen last left selected —
## TeamFormation.SLOTS' own depth/lateral fractions, the same data the
## whiteboard preview draws from, so choosing a formation there now
## actually changes where the human side kicks off from here. AWAY keeps
## the old even spread — a simple "not stacked on the centre circle"
## baseline, not a real formation, and not worth letting the human edit
## since it's an opponent, not their own side.
func _kickoff_slot(index: int, attack_direction: float, team: Tuning.Team) -> Vector3:
	if team == Tuning.Team.HOME:
		var slots := Settings.home_formation_slots()
		if index < slots.size():
			return TeamFormation.world_position(TeamFormation.SLOTS[slots[index]], attack_direction)
	var spread := Tuning.FIELD_WIDTH * 0.6
	var z := lerpf(-spread * 0.5, spread * 0.5,
		float(index) / maxf(1.0, float(Tuning.TEAM_SIZE - 1)))
	var x := -attack_direction * KICKOFF_DEPTH
	return Vector3(x, 0.0, z)


## Real AFL only allows one ruck plus three on-ballers per team inside the
## centre square for a bounce — everyone else has to be outside it. This
## project's TEAM_SIZE (4) happens to equal exactly that "1 ruck + 3
## on-ballers" allowance, so at this roster size a centre-bounce formation
## and "the whole team gathers at the circle" are the same thing; the
## generic KICKOFF_DEPTH spread above is deliberately not reused here — a
## bounce needs two rucks planted either side of the exact centre spot
## the umpire bounces the ball, not a line 30m back.
const RUCK_CONTEST_OFFSET := 1.3   ## m either side of centre, ruck vs ruck
const ON_BALLER_RING_RADIUS := 7.0 ## m from centre — outside CENTRE_CIRCLE_OUTER (5m),
                                    ## inside CENTRE_SQUARE_SIZE (50m)
const ON_BALLER_ANGLES_DEG: Array[float] = [-55.0, 0.0, 55.0]

## `index` 0 is the ruck; 1..3 are the three on-ballers ringed around the
## circle. `attack_direction` biases each team to its own half of the
## circle so the two teams' arcs don't overlap — sign-symmetric the same
## way _kickoff_slot's own attack_direction split already is.
func _centre_bounce_slot(index: int, attack_direction: float) -> Vector3:
	if index == 0:
		return Vector3(-attack_direction * RUCK_CONTEST_OFFSET, 0.0, 0.0)
	var angle := deg_to_rad(ON_BALLER_ANGLES_DEG[(index - 1) % ON_BALLER_ANGLES_DEG.size()])
	return Vector3(-attack_direction * ON_BALLER_RING_RADIUS * cos(angle), 0.0,
		ON_BALLER_RING_RADIUS * sin(angle))


## Every centre-bounce moment (kickoff, after a goal, each quarter start)
## also re-anchors each AI's off-ball drift target (AIBrain.home_position)
## to its current MATCHDAY FORMATION slot via _kickoff_slot — the same
## call _spawn_team used to set it initially, just re-run here so it can't
## go stale. Without this, home_position was only ever set once at spawn:
## a formation preset's effect on shape would fade over the match as
## _switch_human_player's own hand-back re-anchors a player to wherever
## they physically were (not their formation slot) each time control
## passes, and nothing ever corrected it back. Re-running it at every
## stoppage means whichever preset is selected keeps shaping the team for
## the whole match, not just the opening bounce.
func _reposition_kickoff() -> void:
	for i in _home_players.size():
		var player := _home_players[i]
		player.global_position = _centre_bounce_slot(i, 1.0)
		var ai := player.brain() as AIBrain
		if ai != null:
			ai.home_position = _kickoff_slot(i, 1.0, Tuning.Team.HOME)
	for i in _away_players.size():
		var player := _away_players[i]
		player.global_position = _centre_bounce_slot(i, -1.0)
		var ai := player.brain() as AIBrain
		if ai != null:
			ai.home_position = _kickoff_slot(i, -1.0, Tuning.Team.AWAY)


# ── Match flow ───────────────────────────────────────────────────────

func _start_match() -> void:
	MatchState.start_quarter(1)
	_prepare_centre_bounce()


func _prepare_centre_bounce() -> void:
	GameState.phase = GameState.Phase.CENTRE_BOUNCE
	MatchState.clock_running = false
	_drop_all_balls()
	_reposition_kickoff()
	_ball.reset_at(_field.centre())
	_start_pause(Tuning.CENTRE_BOUNCE_DELAY, _bounce_off)


func _bounce_off() -> void:
	# Index 0 of each team is the designated ruck for a centre bounce (see
	# _centre_bounce_slot) — the same shared contest every stoppage in this
	# file now goes through, see _begin_ruck_contest.
	_begin_ruck_contest(_field.centre(), _home_players[0], _away_players[0])


# ── Ruck contests ────────────────────────────────────────────────────
# Design brief priority 4: one shared mechanic for the centre bounce
# (above), a field ball-up (a tackle inside the prior-opportunity grace —
# the neutral case, RULES_REFERENCE.md §4) and a boundary throw-in (see
# _resume_after_out_of_bounds). They differ only in where the contest
# happens and which two players are nominated into it — never in how the
# contest itself resolves (Tuning's "Ruck contests" section /
# PlayerController._update_ruck_contest own that).

## The one place every stoppage's bounce/throw-up actually launches from.
## Nominates the two contestants to read RB as a Hit-Out for
## Tuning.RUCK_CONTEST_WINDOW and bounces the ball straight up between
## them — exactly the same physical launch _bounce_off() always used, now
## shared rather than duplicated at each call site.
func _begin_ruck_contest(spot: Vector3, contestant_a: PlayerController,
		contestant_b: PlayerController) -> void:
	contestant_a.set_ruck_contestant(true)
	contestant_b.set_ruck_contestant(true)
	_ball.reset_at(spot + Vector3.UP * 0.4)
	_ball.launch(Vector3.UP, Tuning.BOUNCE_SPEED, Vector3.ZERO, null)
	GameState.phase = GameState.Phase.PLAY
	MatchState.clock_running = true


## The neutral half of holding-the-ball (RULES_REFERENCE.md §4): tackled
## before PRIOR_OPPORTUNITY_GRACE elapses is nobody's fault, so instead of
## just leaving the tackle's own spill to a free-for-all scramble (the old
## behaviour — this signal previously had no listener at all), it becomes
## a real, brief stoppage at the tackle spot, contested by the two players
## who were already right there. The free-kick half (holding_the_ball_
## called) is a separate, harder problem — see docs/HANDOVER.md.
func _on_player_disposed(action: Tuning.Action, player: PlayerController) -> void:
	MatchState.record_disposal(player.team, action)


func _on_player_marked(_tier: Tuning.Action, _legal_mark: bool, player: PlayerController) -> void:
	MatchState.record_mark(player.team)


func _on_field_ball_up(tackler: PlayerController, tackled: PlayerController) -> void:
	if GameState.phase != GameState.Phase.PLAY:
		return
	MatchState.record_tackle(tackler.team)
	var spot := tackled.global_position
	MatchState.clock_running = false
	GameState.phase = GameState.Phase.STOPPAGE
	_scoreboard.flash("BALL UP", Tuning.CENTRE_BOUNCE_DELAY)
	AudioManager.play_whistle()
	# Freeze the ball at the stoppage spot immediately, same shape
	# _prepare_centre_bounce() already uses (reposition/settle before the
	# pause, not after) — otherwise the ball would keep tumbling from the
	# tackle's own spill impulse for the whole pause, and whoever it rolls
	# to would have a scramble, not a ball-up.
	_ball.reset_at(spot + Vector3.UP * 0.5)
	_start_pause(Tuning.CENTRE_BOUNCE_DELAY, _begin_ruck_contest.bind(spot, tackler, tackled))


## The free-kick half of holding-the-ball (RULES_REFERENCE.md §4, design
## brief priority 8). The *ruling* already fires correctly
## (PlayerController._get_tackled) — nothing consumed it before this pass.
## Deliberately minimal, reusing exactly what the protected kick-in already
## reuses (give_possession/grant_protection): no separate set-shot
## apparatus (aiming for goal on a shot clock, opponents actually retreating
## a real distance) exists in this project, so this stops at "the tackler
## gets the ball back where the infringement happened, protected long
## enough to dispose of it" — the same primitive an earlier pass on this
## project explicitly flagged as the natural next step here.
func _on_holding_the_ball(tackler: PlayerController) -> void:
	if GameState.phase != GameState.Phase.PLAY:
		return
	MatchState.record_tackle(tackler.team)
	var spot := tackler.global_position
	MatchState.clock_running = false
	GameState.phase = GameState.Phase.STOPPAGE
	_scoreboard.flash("HOLDING THE BALL — FREE KICK", Tuning.CENTRE_BOUNCE_DELAY)
	AudioManager.play_whistle()
	_start_pause(Tuning.CENTRE_BOUNCE_DELAY, _award_free_kick.bind(spot, tackler))


func _award_free_kick(spot: Vector3, tackler: PlayerController) -> void:
	_award_possession_at(spot, tackler)


## Shared tail of every "possession + immunity at a spot" restart (free
## kick, protected kick-in, out on the full) — see docs/HANDOVER.md for why
## this exact give_possession()/grant_protection() triad is the one
## established pattern instead of a parallel state machine per restart type.
## MARK_HOLD_DURATION is reused rather than a new invented threshold: the
## same duration a legal mark protects its taker for is "safe to take your
## time with the footy in hand" everywhere in this project, not just marks.
func _award_possession_at(spot: Vector3, receiver: PlayerController) -> void:
	_drop_all_balls()
	_ball.reset_at(spot + Vector3.UP * 0.3)
	receiver.give_possession(_ball)
	receiver.grant_protection(Tuning.MARK_HOLD_DURATION)
	GameState.phase = GameState.Phase.PLAY
	MatchState.clock_running = true


## Every stoppage (bounce/ball-up/free-kick/out-of-bounds/reset) clears
## whoever's currently holding the ball first — was the same five-line loop
## copy-pasted at each call site.
func _drop_all_balls() -> void:
	for player in _home_players + _away_players:
		player.drop_ball()


func _nearest_player(players: Array[PlayerController], spot: Vector3) -> PlayerController:
	var best: PlayerController = null
	var best_dist := INF
	for player in players:
		var dist := player.global_position.distance_to(spot)
		if dist < best_dist:
			best_dist = dist
			best = player
	return best


func _on_scored(team: Tuning.Team, is_goal: bool) -> void:
	if GameState.phase == GameState.Phase.SCORE:
		return   # the ball can clip the trigger again while it settles
	MatchState.clock_running = false
	MatchState.score(team, is_goal)
	GameState.phase = GameState.Phase.SCORE
	var label := "GOAL" if is_goal else "BEHIND"
	_scoreboard.flash("%s! %s" % [label, _team_name(team)], Tuning.SCORE_PAUSE_DURATION)
	_camera.punch(Tuning.CAM_PUNCH_KICK)
	# AFL restarts a GOAL with a centre bounce; a BEHIND restarts with a
	# protected kick-in by the team that conceded it (design brief
	# priority 5) — not another centre bounce, which is what every score
	# used to get here regardless of which it was.
	if is_goal:
		_start_pause(Tuning.SCORE_PAUSE_DURATION, _prepare_centre_bounce)
	else:
		_start_pause(Tuning.SCORE_PAUSE_DURATION, _prepare_kick_in.bind(team))


## Protected kick-in (design brief priority 5): the team that just conceded
## the behind gets the ball back from inside their own goal square, immune
## to being tackled until they play on — reuses PlayerController's existing
## _protected_timer/is_protected() and give_possession() directly rather
## than a parallel state machine. `scoring_team` is who was credited with
## the behind; the kick-in goes to the other side, from the goal square at
## the same end (the one they were just defending).
func _prepare_kick_in(scoring_team: Tuning.Team) -> void:
	GameState.phase = GameState.Phase.STOPPAGE
	var defending_team := Tuning.Team.AWAY if scoring_team == Tuning.Team.HOME else Tuning.Team.HOME
	var direction := 1 if scoring_team == Tuning.Team.HOME else -1
	var defenders := _home_players if defending_team == Tuning.Team.HOME else _away_players
	var square_centre := Vector3(
		_field.goal_line_x(direction) - float(direction) * Tuning.GOAL_SQUARE_DEPTH * 0.5,
		0.0, 0.0)

	var kicker := _nearest_player(defenders, square_centre)
	kicker.global_position = square_centre
	_award_possession_at(square_centre, kicker)


func _end_quarter() -> void:
	MatchState.clock_running = false
	if MatchState.quarter >= Tuning.QUARTERS_PER_MATCH:
		_finish_match()
		return
	GameState.phase = GameState.Phase.STOPPAGE
	_scoreboard.flash("END OF QUARTER %d" % MatchState.quarter, Tuning.QUARTER_BREAK_DURATION)
	AudioManager.play_whistle()
	_start_pause(Tuning.QUARTER_BREAK_DURATION, _next_quarter)


func _next_quarter() -> void:
	MatchState.start_quarter(MatchState.quarter + 1)
	_prepare_centre_bounce()


## Used to flash "FULL TIME" forever with no way onward — MatchEndScreen
## already existed fully built and simply wasn't wired to anything (see
## docs/FEATURE_AUDIT.md). Holds the scoreboard flash for a beat so the
## result actually registers, then hands off to the real screen, which
## reads the same MatchState.scoreline() fresh in its own _ready() — untouched
## by anything in between, since nothing resets MatchState until a new match
## starts.
func _finish_match() -> void:
	GameState.phase = GameState.Phase.FINISHED
	_scoreboard.flash("FULL TIME   %s - %s" % [
		MatchState.scoreline(Tuning.Team.HOME), MatchState.scoreline(Tuning.Team.AWAY)],
		Tuning.MATCH_END_FLASH_DURATION)
	AudioManager.play_full_time()
	_start_pause(Tuning.MATCH_END_FLASH_DURATION, _show_match_end_screen)


func _show_match_end_screen() -> void:
	SceneWipe.change_scene(MATCH_END_SCREEN_PATH)


func _team_name(team: Tuning.Team) -> String:
	return "HOME" if team == Tuning.Team.HOME else "AWAY"


func _start_pause(duration: float, on_complete: Callable) -> void:
	_pause_timer = duration
	_pause_callback = on_complete


# ── Ball out of bounds ───────────────────────────────────────────────
# A real (if simplified) boundary throw-in: no separate umpire/possession
# model (design doc scope for this milestone, see RULES_REFERENCE.md —
# there is no "deliberate out of bounds" free kick either, since that
# needs the same adjudication apparatus holding-the-ball's ruling is
# already waiting on, per an earlier session's note), but the moment now
# actually stops play rather than the ball just quietly sliding back in
# under everyone's feet mid-contest with zero signal that anything
# happened — same STOPPAGE phase / pause-and-callback shape every other
# dead-ball moment in this file already uses (goals, quarter breaks),
# not a bespoke third mechanism.

func _check_out_of_bounds() -> void:
	# Mid-pause (this stoppage, a goal, a quarter break) the ball is either
	# already being handled or about to be reset elsewhere — re-entering
	# here would re-trigger on the same still-out-of-bounds position every
	# remaining frame of the pause.
	if _pause_timer > 0.0 or _ball.is_held:
		_prev_ball_pos_valid = false
		return
	var pos := _ball.global_position

	# Catches a ball that has fallen through geometry or been knocked clean
	# off the ground slab's finite extent. Checked unconditionally — a
	# ball in freefall past the edge of the world never settles (gravity
	# keeps accelerating it), so gating this on is_settled() like the
	# in-bounds case below would mean it's never caught.
	if pos.y < Tuning.BALL_LOST_BELOW \
			or absf(pos.x) > Tuning.FIELD_HALF_LENGTH + Field.SURROUND_MARGIN \
			or absf(pos.z) > Tuning.FIELD_HALF_WIDTH + Field.SURROUND_MARGIN:
		_reset_ball()
		_prev_ball_pos_valid = false
		return

	if _check_out_on_the_full(pos):
		return

	if not _ball.is_settled() or _field.is_inside_oval(pos):
		return
	_trigger_out_of_bounds(pos)


## "Out on the full" (RULES_REFERENCE.md §4): a KICK that crosses the
## boundary while still airborne and uninterrupted is a free kick to the
## *other* side, taken from the crossing point — distinct from a ball that
## comes down and rolls out, which _trigger_out_of_bounds (a neutral
## throw-in contest) already handles. Only a live kick flight is watched
## (Ball.is_kick_flight()) — a handball/bounce/hit-out/spoiled deflection
## that happens to sail out isn't a "kick out on the full" under the real
## rule.
##
## Checked every physics frame a kick is in flight, per this project's own
## memory of Prototype 1's approach: bisect the segment between last
## frame's (inside) and this frame's (outside) position rather than just
## accepting whichever frame happened to land outside — at up to ~24 m/s
## plus carried momentum a single frame's overshoot is small but not free,
## and the bisection only ever runs while a kick is actually in flight, so
## it costs nothing the rest of the time. Returns true if a crossing was
## caught and handled this frame, so the caller skips the settled/rolled-
## out check for the same frame (the ball's already been dealt with).
func _check_out_on_the_full(pos: Vector3) -> bool:
	if not _ball.is_airborne() or not _ball.is_kick_flight():
		_prev_ball_pos_valid = false
		return false
	if _prev_ball_pos_valid and _field.is_inside_oval(_prev_ball_pos) \
			and not _field.is_inside_oval(pos):
		var crossing := _bisect_boundary_crossing(_prev_ball_pos, pos)
		_trigger_out_on_the_full(crossing, _ball.kick_team())
		_prev_ball_pos_valid = false
		return true
	_prev_ball_pos = pos
	_prev_ball_pos_valid = true
	return false


func _bisect_boundary_crossing(inside_pos: Vector3, outside_pos: Vector3) -> Vector3:
	var a := inside_pos
	var b := outside_pos
	for i in 8:
		var mid := (a + b) * 0.5
		if _field.is_inside_oval(mid):
			a = mid
		else:
			b = mid
	return (a + b) * 0.5


## Free kick to `receiving_team` from the crossing point — reuses exactly
## the same give_possession()/grant_protection() triad the protected kick-in
## and the holding-the-ball free kick already reuse from each other, per
## this project's own established pattern for "possession + immunity at a
## spot" (see docs/HANDOVER.md). `kicking_team` is read from Ball.kick_team()
## at the instant of crossing, since the ball's own _carrier reference has
## long since been cleared by RELEASE_GRACE for anything but a very short kick.
func _trigger_out_on_the_full(pos: Vector3, kicking_team: Tuning.Team) -> void:
	if kicking_team == Tuning.Team.NONE:
		# Shouldn't happen — _check_out_on_the_full only calls this while
		# Ball.is_kick_flight() is true, which always sets a real team.
		# Falling back to the neutral stoppage rather than awarding a free
		# kick to nobody in particular if it ever does.
		_trigger_out_of_bounds(pos)
		return
	var receiving_team := Tuning.Team.AWAY if kicking_team == Tuning.Team.HOME else Tuning.Team.HOME
	var defenders := _home_players if receiving_team == Tuning.Team.HOME else _away_players
	var spot := _throw_in_point(pos)

	MatchState.clock_running = false
	GameState.phase = GameState.Phase.STOPPAGE
	_scoreboard.flash("OUT ON THE FULL", Tuning.OUT_OF_BOUNDS_PAUSE_DURATION)
	AudioManager.play_whistle()
	# Freeze the ball at the crossing spot immediately, same "settle before
	# the pause, not after" shape every other stoppage in this file uses —
	# otherwise it would keep sailing out over the fence for the whole pause.
	_ball.reset_at(spot + Vector3.UP * 0.5)
	_start_pause(Tuning.OUT_OF_BOUNDS_PAUSE_DURATION,
		_award_out_on_the_full.bind(spot, defenders))


func _award_out_on_the_full(spot: Vector3, defenders: Array[PlayerController]) -> void:
	var kicker := _nearest_player(defenders, spot)
	kicker.global_position = spot
	_award_possession_at(spot, kicker)


## Pulls a boundary-ish point back to just inside the boundary line, along
## the same radial the old silent version used. Shared by two callers now:
## the settled-out-of-bounds case below (a ball that rolled well past the
## line) and _trigger_out_on_the_full's bisected crossing point (already
## almost exactly on the line) — the same radial normalise-and-rescale
## works regardless of how far out the input point actually is.
func _throw_in_point(pos: Vector3) -> Vector3:
	var radial := sqrt(pow(pos.x / Tuning.FIELD_HALF_LENGTH, 2.0)
		+ pow(pos.z / Tuning.FIELD_HALF_WIDTH, 2.0))
	var scale := 0.97 / maxf(radial, 0.001)
	return Vector3(pos.x * scale, 0.3, pos.z * scale)


func _trigger_out_of_bounds(pos: Vector3) -> void:
	var throw_in_point := _throw_in_point(pos)
	MatchState.clock_running = false
	GameState.phase = GameState.Phase.STOPPAGE
	_scoreboard.flash("OUT OF BOUNDS", Tuning.OUT_OF_BOUNDS_PAUSE_DURATION)
	AudioManager.play_whistle()
	_start_pause(Tuning.OUT_OF_BOUNDS_PAUSE_DURATION,
		_resume_after_out_of_bounds.bind(throw_in_point))


## Boundary throw-in, through the same shared contest as the centre bounce
## and a field ball-up (design brief priority 4/6) — "nearest player per
## side" for who contests it, per Prototype 1's own throw-in/ball-up model
## (see this project's memory of P1's contest_minigame.py approach).
func _resume_after_out_of_bounds(throw_in_point: Vector3) -> void:
	_drop_all_balls()
	var home := _nearest_player(_home_players, throw_in_point)
	var away := _nearest_player(_away_players, throw_in_point)
	_begin_ruck_contest(throw_in_point, home, away)


## Manual safety net (bound to "debug_reset", same key as the milestone-1
## sandbox's R) — brings the ball back to the centre if it ever ends up
## somewhere _check_out_of_bounds can't reason about.
func _reset_ball() -> void:
	_drop_all_balls()
	_ball.reset_at(_field.centre())


# ── Human control ────────────────────────────────────────────────────

## SINGLE_PLAYER's own hand-off (design brief's "must stay solid"): brain
## construction stays here (only this mode script knows AI config), but
## who's now focused is reported to ControlMode, which is what fans out to
## camera/HUD/crosshair/mark-prompt via _on_focus_changed() — see that
## function for the camera pan-vs-snap decision.
##
## In TEAM_COMMAND this key instead cycles which teammate is selected
## (directly human-driven) — same physical button, same "move on to the
## next body" meaning, just within the other scheme's own bookkeeping.
func _switch_human_player() -> void:
	if ControlMode.scheme_for(Tuning.Team.HOME) == ControlMode.Scheme.TEAM_COMMAND:
		_cycle_team_command_selection()
		return

	var previous := ControlMode.controlled_player(Tuning.Team.HOME)
	var next := ControlMode.next_in_roster(Tuning.Team.HOME, previous)
	if next == previous:
		return

	var ai := _configure_ai_brain(AIBrain.new(), Tuning.Team.HOME, 1.0, previous.global_position)
	previous.set_brain(ai)

	next.set_brain(HumanBrain.new())
	ControlMode.set_controlled_player(Tuning.Team.HOME, next)


## Debug/prototyping entry point for ControlMode.Scheme.TEAM_COMMAND —
## proves the routing works, per TASK's scope (full command UI/UX is
## explicitly not this pass's job). Swaps HOME between the two schemes,
## keeping whichever player is currently focused as the new scheme's
## starting selection/controlled player so the swap itself never leaves
## anyone mid-air: the same player who had the human's input a moment ago
## still does, just under the other scheme's bookkeeping.
func _toggle_control_scheme() -> void:
	var current_focus := ControlMode.focus_player(Tuning.Team.HOME)
	var next_scheme := ControlMode.Scheme.TEAM_COMMAND \
		if ControlMode.scheme_for(Tuning.Team.HOME) == ControlMode.Scheme.SINGLE_PLAYER \
		else ControlMode.Scheme.SINGLE_PLAYER

	# Give every other HOME player a fresh, mode-appropriate AI brain before
	# switching — TEAM_COMMAND's teammates need CommandBrain (to be able to
	# receive an order), SINGLE_PLAYER's need plain AIBrain, and the brain
	# a player was holding under the *other* scheme is the wrong type
	# either way (a CommandBrain sitting around during SINGLE_PLAYER would
	# just behave like AIBrain since nothing ever issues it a command, but
	# leaving it in place is misleading state to debug later).
	for player in _home_players:
		if player == current_focus:
			continue
		var brain: AIBrain = CommandBrain.new() if next_scheme == ControlMode.Scheme.TEAM_COMMAND \
			else AIBrain.new()
		_configure_ai_brain(brain, Tuning.Team.HOME, 1.0, player.global_position)
		player.set_brain(brain)

	ControlMode.set_scheme(Tuning.Team.HOME, next_scheme)
	current_focus.set_brain(HumanBrain.new())
	if next_scheme == ControlMode.Scheme.TEAM_COMMAND:
		ControlMode.set_selected_player(Tuning.Team.HOME, current_focus)
	else:
		ControlMode.set_controlled_player(Tuning.Team.HOME, current_focus)


func _cycle_team_command_selection() -> void:
	var previous := ControlMode.selected_player(Tuning.Team.HOME)
	var next := ControlMode.next_in_roster(Tuning.Team.HOME, previous)
	if next == previous:
		return

	# The player losing the human's direct input becomes commandable again
	# rather than plain AI — that's the whole point of TEAM_COMMAND over
	# SINGLE_PLAYER, and it must happen on every hand-off, not just the
	# first one, or a few switches in most of the team quietly reverts to
	# uncommandable AIBrain.
	var cmd := CommandBrain.new()
	_configure_ai_brain(cmd, Tuning.Team.HOME, 1.0, previous.global_position)
	previous.set_brain(cmd)

	next.set_brain(HumanBrain.new())
	ControlMode.set_selected_player(Tuning.Team.HOME, next)


## TEAM_COMMAND's minimal "move here/lead here" order (design brief:
## "likely via a selected-player + issued-command model"). No reticle/UI
## exists yet (out of scope — Agent 1's territory), so the target point is
## derived from the selected player's own facing rather than anything
## aimed: a fixed lead distance straight ahead of them. Good enough to
## prove CommandBrain actually picks up and clears an external order; a
## real aimable target is follow-up work once there's a UI pass to carry it.
func _issue_team_command() -> void:
	if ControlMode.scheme_for(Tuning.Team.HOME) != ControlMode.Scheme.TEAM_COMMAND:
		return
	var selected := ControlMode.selected_player(Tuning.Team.HOME)
	if not is_instance_valid(selected):
		return
	var receiver := _nearest_commandable_teammate(selected)
	if receiver == null:
		return

	var forward := -selected.global_transform.basis.z
	var lead_point := selected.global_position + forward * Tuning.COMMAND_LEAD_DISTANCE
	(receiver.brain() as CommandBrain).issue_command(lead_point)


func _nearest_commandable_teammate(from: PlayerController) -> PlayerController:
	var best: PlayerController = null
	var best_dist := INF
	for player in _home_players:
		if player == from or not (player.brain() is CommandBrain):
			continue
		var dist := from.global_position.distance_to(player.global_position)
		if dist < best_dist:
			best_dist = dist
			best = player
	return best
