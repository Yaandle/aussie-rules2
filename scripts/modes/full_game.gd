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

## Per-team lateral stagger for the full-18 formation spawn. TeamFormation
## is a single mirrored layout, so without this HOME's back line resolves
## to the exact same world points as AWAY's forward line (full-back on
## full-forward, CHB on CHF, …) and the two coincident capsules blow the
## solver up on the first physics tick. Shifting each side ±this along the
## ground line puts paired opponents ~2x this apart — a defender goal-side
## of their opponent, not standing in them. Not an AFL number; just enough
## clearance that no two bodies ever spawn on one point.
const FORMATION_TEAM_STAGGER := 2.0

@onready var _field: Field = $Field
@onready var _ball: Ball = $Ball
@onready var _camera: BroadcastCamera = $BroadcastCamera
@onready var _hud: DebugHud = $DebugHud
@onready var _scoreboard: Scoreboard = $Scoreboard

var _home_players: Array[PlayerController] = []
var _away_players: Array[PlayerController] = []

## Only populated for a Career match (GameState.career_active) — the
## generated opponent roster for the current fixture, same shape and
## roster-spawn order as CareerProfile.roster. See _spawn_teams().
var _away_roster: Array[Dictionary] = []

## Each team's player whose last disposal was a kick — the only way to
## attribute a goal to a kicker, since Field's own `scored` signal carries
## just (team, is_goal), not who kicked it (see _on_scored). Overwritten
## on every kick, not cleared between them: the ball is "live" between a
## kick and whatever next touches it, and if that's a goal this is still
## the right attribution. Tracked for every match since the cost is one
## dictionary write per kick, but only ever read when GameState.
## career_active (roster_id is empty otherwise, see _on_scored).
var _last_kicker := {Tuning.Team.HOME: null, Tuning.Team.AWAY: null}
var _crosshair: KickCrosshair
var _mark_prompt: MarkPrompt
var _controlled_ring: ControlledPlayerRing

## The two ruckmen in the current live ruck contest (set in _release_ruck_
## contest). Cleared the instant a hit-out connects so the on-ballers are
## freed to gather the tap — see _on_hit_out_resolved and
## PlayerController.ruck_contest_locked.
var _ruck_contestants: Array[PlayerController] = []

var _pause_timer := 0.0
var _pause_callback := Callable()

## Kick after the siren (playtest: "took a mark before the end of the
## quarter but couldn't take the shot"). Set when the clock runs out while
## someone holds the ball under mark/free-kick protection; the quarter then
## waits for that one kick — see _update_after_siren.
var _after_siren_kicker: PlayerController = null
var _after_siren_kicked := false
var _after_siren_flight := 0.0

## Last frame's ball position, tracked every frame the ball is live so the
## exact boundary crossing can be bisected out of it — see
## _check_out_of_bounds(). Reset to invalid across any stoppage, so a stale
## position from before it can never be bisected against a new one.
var _prev_ball_pos := Vector3.ZERO
var _prev_ball_pos_valid := false

## Seconds until "call for the ball" can be used again — see
## Tuning.CALL_FOR_BALL_COOLDOWN. Only ever non-zero in
## Settings.PlayerControlMode.SINGLE_PLAYER, since that's the only mode the
## action is routed in at all.
var _call_for_ball_cooldown := 0.0


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
	_camera.zoom = Settings.camera_zoom
	Settings.camera_zoom_changed.connect(func(zoom: float) -> void: _camera.zoom = zoom)

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

	_controlled_ring = ControlledPlayerRing.new()
	# _apply_camera_mode() ran above, before this existed — seed the state
	# it would have set, then it keeps it live on any mid-match change.
	_controlled_ring.active = Settings.full_game_camera_mode \
		== Settings.FullGameCameraMode.FULL_SIDE
	add_child(_controlled_ring)

	_spawn_teams()
	_start_match()


func _physics_process(delta: float) -> void:
	_check_out_of_bounds()
	# Ticked ahead of the pause gate below, not inside the live-play branch:
	# a call made just before a goal/ball-up shouldn't stay on cooldown for
	# the whole stoppage as well.
	_call_for_ball_cooldown = maxf(0.0, _call_for_ball_cooldown - delta)

	if _pause_timer > 0.0:
		_pause_timer = maxf(0.0, _pause_timer - delta)
		if _pause_timer <= 0.0 and _pause_callback.is_valid():
			var callback := _pause_callback
			_pause_callback = Callable()
			callback.call()
		return

	if is_instance_valid(_after_siren_kicker):
		_update_after_siren(delta)
		return

	if MatchState.clock_running and MatchState.seconds_remaining <= 0.0:
		var kicker := _after_siren_candidate()
		if kicker != null:
			_begin_after_siren(kicker)
		else:
			_end_quarter()


# ── Kick after the siren ─────────────────────────────────────────────
# Real AFL: a player who marked or was awarded a free kick before the
# siren still takes the kick; the quarter ends once that kick is decided.
# Everything else in play stops mattering — only this ball's outcome does.

## Whoever is holding the ball under mark/free-kick protection at the
## siren, or null.
func _after_siren_candidate() -> PlayerController:
	for player in _home_players + _away_players:
		if player.is_carrying() and player.is_protected():
			return player
	return null


## Clock stays at zero; the kicker gets the full shot clock (the 5s mark
## window may be nearly spent by the siren) and play carries on in PLAY so
## they can walk back, line up and kick.
func _begin_after_siren(kicker: PlayerController) -> void:
	MatchState.clock_running = false
	_after_siren_kicker = kicker
	_after_siren_kicked = false
	_after_siren_flight = 0.0
	kicker.grant_protection(Tuning.SET_SHOT_CLOCK)
	AudioManager.play_whistle()
	_scoreboard.flash("SIREN — KICK AFTER THE SIREN", Tuning.AFTER_SIREN_MAX_FLIGHT)


## Ends the quarter once the kick is decided: the kicker plays on or runs
## out the shot clock without kicking; or the kicked ball is gathered or
## marked by anyone, lands, or has been live AFTER_SIREN_MAX_FLIGHT. A
## score or the ball going out ends it through _on_scored /
## _trigger_out_of_bounds / _trigger_out_on_the_full instead.
func _update_after_siren(delta: float) -> void:
	var kicker := _after_siren_kicker
	if not _after_siren_kicked:
		if kicker.is_carrying():
			if not kicker.is_protected():
				_finish_after_siren()
			return
		_after_siren_kicked = true
		return
	_after_siren_flight += delta
	if _ball.is_held or not _ball.is_kick_flight() \
			or _after_siren_flight >= Tuning.AFTER_SIREN_MAX_FLIGHT:
		_finish_after_siren()


func _after_siren_active() -> bool:
	return is_instance_valid(_after_siren_kicker)


func _finish_after_siren() -> void:
	_after_siren_kicker = null
	_after_siren_kicked = false
	_end_quarter()


## FULL_TEAM control (Settings.player_control_mode, the quick-play pregame's
## choice) — never in Career, which is single-player by design: you are
## your created player for the whole match. Every FULL_TEAM-only behaviour
## in this file asks here rather than reading the setting, so a Career
## match can't inherit whatever the quick-play pregame last saved.
func _full_team_control() -> bool:
	return not GameState.career_active \
		and Settings.player_control_mode == Settings.PlayerControlMode.FULL_TEAM


func _apply_camera_mode(setting: Settings.FullGameCameraMode) -> void:
	var full_side := setting == Settings.FullGameCameraMode.FULL_SIDE
	_camera.set_mode(BroadcastCamera.Mode.FULL_SIDE if full_side else BroadcastCamera.Mode.CHASE)
	# The foot ring only earns its keep in the wide view — in CHASE the
	# camera is already sitting behind the controlled player.
	if is_instance_valid(_controlled_ring):
		_controlled_ring.active = full_side


## The two player-control modes (Settings.PlayerControlMode, chosen on the
## Full Game pregame screen) differ here and nowhere else: FULL_TEAM keeps
## switch_player, SINGLE_PLAYER swaps it for call_for_ball. Gated at the
## input site rather than inside each handler so the split is readable in
## one place — which action even exists in which mode is the whole setting.
## Note this is Settings.PlayerControlMode, NOT ControlMode.Scheme: both
## teams stay registered as ControlMode.Scheme.SINGLE_PLAYER regardless,
## exactly as before this pass.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"switch_player"):
		if _full_team_control():
			_switch_human_player()
	elif event.is_action_pressed(&"call_for_ball"):
		if not _full_team_control():
			_call_for_ball()
	elif event.is_action_pressed(&"toggle_control_scheme"):
		# TEAM_COMMAND drives the whole side; Career is one player.
		if not GameState.career_active:
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
## has ever had — nothing meaningful to move away from — so the camera
## snaps via recenter(). Every subsequent change, whether a switch or a
## TEAM_COMMAND selection change, goes through switch_target(), which snaps
## the focus onto the new player and does a brisk reorient behind them
## (soft-pan feedback: the old easing barely read as a switch at all).
func _on_focus_changed(team: Tuning.Team, previous: PlayerController, next: PlayerController) -> void:
	if team != Tuning.Team.HOME:
		return

	if is_instance_valid(previous) and previous != next:
		previous.camera = null
		previous.camera_rig = null

	if is_instance_valid(next):
		next.camera = _camera.camera()
		next.camera_rig = _camera
		if previous == null:
			_camera.target = next
			_camera.recenter()
		else:
			_camera.switch_target(next)

	_hud.player = next
	_crosshair.player = next
	_mark_prompt.player = next
	_controlled_ring.player = next


## Esc used to hard-cut straight to the main menu, discarding a match in
## progress with zero confirmation — PauseScreen already existed fully
## built and simply wasn't wired to anything (see FEATURE_AUDIT.md (archived)).
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
	# Career's own HOME roster is already generated and persisted
	# (CareerProfile.roster); the opponent's isn't — generated here,
	# lazily, from the current fixture's name (seeded off that name and the
	# career's seed, so this is reproducible but never persisted, see
	# roster_generator.gd's own header).
	if GameState.career_active:
		_away_roster = CareerProfile.opponent_roster()
	_home_players = _spawn_team(Tuning.Team.HOME, 1.0)
	_away_players = _spawn_team(Tuning.Team.AWAY, -1.0)

	# ControlMode (control-mode pass) is the single source of truth for
	# "who's driving" from here on — this mode script still builds the
	# actual brains (only it knows the AI config: ball ref, home position,
	# attack direction), but which player is focused, and telling the
	# camera/HUD/crosshair/mark-prompt about it, is centralised in
	# _on_focus_changed() rather than repeated at every call site that
	# used to hand-roll it (see HANDOVER.md (archived, see docs/LESSONS.md)'s control-mode entry).
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
	# SINGLE_PLAYER position pick (Settings.home_human_slot, chosen on the
	# pregame screen; default 1 = centre) — or in Career, your created
	# player's own slot, so the human is always the body carrying your name
	# and stats. Re-clamped to the live roster so a stale save can't index
	# past the spawned team. _bounce_off() still rucks _home_players[0]
	# regardless — see its comment.
	var human_idx := CareerProfile.player_roster_index() if GameState.career_active \
		else Settings.home_human_slot
	human_idx = clampi(human_idx, 0, _home_players.size() - 1)
	_home_players[human_idx].set_brain(HumanBrain.new())
	ControlMode.set_controlled_player(Tuning.Team.HOME, _home_players[human_idx])
	if GameState.career_active:
		_apply_career_rosters()
	else:
		_apply_character_profile(human_idx)

	for player in _home_players + _away_players:
		player.field_ball_up_called.connect(_on_field_ball_up)
		player.holding_the_ball_called.connect(_on_holding_the_ball)
		player.run_too_far_called.connect(_on_run_too_far)
		player.infringed.connect(_on_infringed.bind(player))
		player.hit_out_resolved.connect(_on_hit_out_resolved)
		# FULL_TEAM auto-carrier control — jump the human onto whoever HOME
		# wins the ball. ball_gathered covers marks too (_finish_mark_catch
		# routes through _complete_gather), so it's the one "now has it"
		# hook. Bound with the player since the signal only carries the ball.
		player.ball_gathered.connect(_on_home_gained_possession.bind(player))
		# Box-score stats (FEATURE_AUDIT.md (archived)) — bound with the player
		# itself since neither signal carries a reference to who disposed/
		# marked, only what happened.
		player.ball_disposed.connect(_on_player_disposed.bind(player))
		player.mark_caught.connect(_on_player_marked.bind(player))
		player.tackle_committed.connect(_on_player_tackle_landed.bind(player))


## Quick play only (a Career match uses _apply_career_rosters below).
## Push the CharacterProfile stats onto HOME. CharacterProfile.apply_all
## picks the scope: every HOME player, or (false) only the pregame
## start-position slot — deliberately fixed to that slot, it does NOT
## follow the controlled player across FULL_TEAM carrier switches (see
## _assign_human_to). AWAY is never touched. Mirrors kick_to_kick.gd's
## per-field assignment.
func _apply_character_profile(start_idx: int) -> void:
	for i in _home_players.size():
		if not CharacterProfile.apply_all and i != start_idx:
			continue
		_apply_stats(_home_players[i], CharacterProfile.speed, CharacterProfile.agility,
			CharacterProfile.kick_power, CharacterProfile.kick_accuracy, CharacterProfile.height)


## Career matches: every player plays to their own roster entry's
## attributes (both teams — RosterGenerator gives every generated player
## real speed/agility/kick/height values). That includes the Career
## player: CareerProfile keeps its roster entry in sync with its current
## levels and position on every save. Before this a Career match ran
## _apply_character_profile like quick play, so the quick-play profile's
## stats went onto HOME (all 18 by default) and the created Career
## player's stats were never used.
func _apply_career_rosters() -> void:
	for pair: Array in [[_home_players, CareerProfile.roster], [_away_players, _away_roster]]:
		var players: Array[PlayerController] = pair[0]
		var roster: Array[Dictionary] = pair[1]
		for i in mini(players.size(), roster.size()):
			var entry := roster[i]
			_apply_stats(players[i],
				float(entry.get("speed", Tuning.CHARACTER_SPEED_DEFAULT)),
				float(entry.get("agility", Tuning.CHARACTER_AGILITY_DEFAULT)),
				float(entry.get("kick_power", Tuning.CHARACTER_KICK_POWER_DEFAULT)),
				float(entry.get("kick_accuracy", Tuning.CHARACTER_KICK_ACCURACY_DEFAULT)),
				float(entry.get("height", Tuning.CHARACTER_HEIGHT_DEFAULT)))
			# Weight was flavour only until tackles weighed the two players
			# (TackleBalance's mass ratio, the ragdoll's segment masses).
			players[i].body_mass = float(entry.get("weight", Tuning.PLAYER_DEFAULT_MASS_KG))


## Raw stats (the same units CharacterProfile/CareerProfile/roster entries
## store) onto one player, as the scales PlayerController reads.
func _apply_stats(p: PlayerController, speed: float, agility: float, kick_power: float,
		kick_accuracy: float, height: float) -> void:
	p.speed_scale = speed / Tuning.CHARACTER_SPEED_DEFAULT
	p.agility_scale = agility / Tuning.CHARACTER_AGILITY_DEFAULT
	p.kick_power_scale = kick_power
	p.kick_accuracy = kick_accuracy
	(p.get_node("Rig") as Node3D).scale = Vector3.ONE * (height / Tuning.CHARACTER_HEIGHT_DEFAULT)


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
		# Spawn on the imminent _reposition_kickoff target (the centre-
		# bounce slot), not the raw formation slot: at 18-a-side roster
		# index 1 (Centre) resolves to world origin, and two capsules plus
		# the ball coincident there for even one physics tick is exactly
		# the solver blow-up described above.
		var formation_slot := _kickoff_slot(i, attack_direction, team)
		instance.position = _centre_bounce_slot(i, attack_direction, team)
		if GameState.career_active:
			var roster := CareerProfile.roster if team == Tuning.Team.HOME else _away_roster
			instance.roster_name = roster[i]["name"]
			instance.roster_id = "H%d" % int(roster[i].get("id", i)) if team == Tuning.Team.HOME \
				else "A%d" % i
		add_child(instance)
		AudioManager.register_player(instance)

		instance.set_brain(_configure_ai_brain(AIBrain.new(), team, attack_direction, formation_slot))

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


## At the full 18-a-side roster BOTH teams line up in the real
## TeamFormation layout, roster index mapped through
## TeamFormation.ROSTER_ORDER (on-ball unit first). world_position() folds
## in attack_direction, so AWAY's -1.0 mirrors HOME across the centre line
## — which lands HOME's back line on top of AWAY's forward line (see
## FORMATION_TEAM_STAGGER), so each team is also shifted ±that along the
## ground line to keep paired opponents from spawning on one point.
## Below a full roster (reduced-size testing) HOME instead uses whichever
## of Settings.FORMATION_PRESETS the Team List screen last left selected —
## a curated "pick 4 of 18" shape that would collide two HOME players onto
## shared slots at the full 18 — and AWAY/overflow fall back to a plain
## even spread 30 m back, a "not stacked on the centre circle" baseline
## rather than a real formation.
func _kickoff_slot(index: int, attack_direction: float, team: Tuning.Team) -> Vector3:
	if Tuning.TEAM_SIZE >= TeamFormation.SLOTS.size():
		var slot := TeamFormation.world_position(TeamFormation.roster_slot(index), attack_direction)
		slot.z += attack_direction * FORMATION_TEAM_STAGGER
		return slot
	if team == Tuning.Team.HOME:
		var slots := Settings.home_formation_slots()
		if index < slots.size():
			return TeamFormation.world_position(TeamFormation.SLOTS[slots[index]], attack_direction)
	var spread := Tuning.FIELD_WIDTH * 0.6
	var z := lerpf(-spread * 0.5, spread * 0.5,
		float(index) / maxf(1.0, float(Tuning.TEAM_SIZE - 1)))
	var x := -attack_direction * KICKOFF_DEPTH
	return Vector3(x, 0.0, z)


## Real AFL centre-square law: at a centre bounce a maximum of four players
## per team — the ruck plus three midfielders ("on-ballers") — may be
## inside the 50 m centre square until the ball is bounced; everyone else
## must start outside it. So roster indices 0-3 go on the ruck-contest
## ring at the centre and indices 4+ hold their normal matchday formation
## slot (_kickoff_slot). TeamFormation.ROSTER_ORDER front-loads the four
## slots that sit inside the square (ruck, centre, the two rovers), so
## indices 4+ are outside it by construction.
## The generic KICKOFF_DEPTH spread is still not reused for the ring: a
## bounce needs two rucks planted either side of the exact spot the umpire
## bounces the ball, not a line 30 m back. At TEAM_SIZE 4 the ring is the
## whole team and indices 4+ never occur.
const RUCK_CONTEST_OFFSET := 1.3   ## m either side of centre, ruck vs ruck
const ON_BALLER_RING_RADIUS := 7.0 ## m from centre — outside CENTRE_CIRCLE_OUTER (5m),
                                    ## inside CENTRE_SQUARE_SIZE (50m)
const ON_BALLER_ANGLES_DEG: Array[float] = [-55.0, 0.0, 55.0]

## `index` 0 is the ruck; 1..3 are the three on-ballers ringed around the
## circle; 4+ hold their matchday formation slot (see the comment above).
## `attack_direction` biases each team to its own half so the two teams
## never overlap — sign-symmetric the same way _kickoff_slot's own
## attack_direction split already is.
func _centre_bounce_slot(index: int, attack_direction: float, team: Tuning.Team) -> Vector3:
	if index == 0:
		return Vector3(-attack_direction * RUCK_CONTEST_OFFSET, 0.0, 0.0)
	if index < 4:
		# (index - 1) % size() is defensive — index is always 1..3 here.
		var angle := deg_to_rad(ON_BALLER_ANGLES_DEG[(index - 1) % ON_BALLER_ANGLES_DEG.size()])
		return Vector3(-attack_direction * ON_BALLER_RING_RADIUS * cos(angle), 0.0,
			ON_BALLER_RING_RADIUS * sin(angle))
	return _kickoff_slot(index, attack_direction, team)


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
		player.global_position = _centre_bounce_slot(i, 1.0, Tuning.Team.HOME)
		var ai := player.brain() as AIBrain
		if ai != null:
			ai.home_position = _kickoff_home_position(i, 1.0, Tuning.Team.HOME)
	for i in _away_players.size():
		var player := _away_players[i]
		player.global_position = _centre_bounce_slot(i, -1.0, Tuning.Team.AWAY)
		var ai := player.brain() as AIBrain
		if ai != null:
			ai.home_position = _kickoff_home_position(i, -1.0, Tuning.Team.AWAY)


## The off-ball drift anchor an AI holds at during (and after) a centre
## bounce. For the three non-ruck on-ballers (roster indices 1-3) it's
## their spot on the ruck-contest ring, NOT their matchday formation slot:
## the on-ball unit's formation slots sit on/beside the exact centre spot,
## so anchoring there walked AIBrain's "hold the line" step straight into
## the middle of the contest (a rover ending up inside the centre circle
## while the ruckmen were still going up). Everyone else keeps their real
## formation slot so a chosen preset still shapes the team all match.
func _kickoff_home_position(index: int, attack_direction: float, team: Tuning.Team) -> Vector3:
	if index >= 1 and index < 4:
		return _centre_bounce_slot(index, attack_direction, team)
	return _kickoff_slot(index, attack_direction, team)


# ── Match flow ───────────────────────────────────────────────────────

func _start_match() -> void:
	MatchState.start_quarter(1)
	_prepare_centre_bounce()


## `delay` is the gap between the reset finishing and the ball actually
## going up — a quarter start uses the standard CENTRE_BOUNCE_DELAY, a
## restart after a goal a longer one (see Tuning.GOAL_RESTART_BOUNCE_DELAY,
## rulebook §3: everyone has just walked back to the middle and the moment
## read as rushed).
## Pin the ball on the turf at `spot` for a stoppage's pre-throw wait —
## every stoppage (centre bounce, field ball-up, boundary throw-in) parks
## the ball while the teams reset, and it was doing that a floating
## 0.4–0.5 m off the ground, so for the two-to-four seconds before the
## umpire picked it up it just hung in mid-air over the spot. A settled
## ball sits on the ground; y is the ball's own semi-minor so it rests on
## the turf rather than half-sunk. Still a hard lock (Ball.lock_at) — a
## dead-ball pause, nobody may collect it — just at a believable height.
func _rest_ball_at(spot: Vector3) -> void:
	_ball.lock_at(Vector3(spot.x, Tuning.BALL_SEMI_MINOR, spot.z))


func _prepare_centre_bounce(delay := Tuning.CENTRE_BOUNCE_DELAY) -> void:
	GameState.phase = GameState.Phase.CENTRE_BOUNCE
	MatchState.clock_running = false
	_drop_all_balls()
	_reposition_kickoff()
	_hand_human_the_ruck()
	# Locked, not just placed — nobody may pick it up off the centre circle
	# while the teams are still walking back. Sits on the centre rather than
	# hovering over it; released by the throw-up at the end of the chain
	# (_release_ruck_contest).
	_rest_ball_at(_field.centre())
	_start_pause(delay, _bounce_off)


func _bounce_off() -> void:
	# Roster index 0 of each team is the designated ruck for a centre bounce
	# (TeamFormation.ROSTER_ORDER front-loads the ruck slot, and
	# _centre_bounce_slot plants index 0 on the contest spot) — the same
	# shared contest every stoppage in this file goes through, see
	# _begin_ruck_contest. This stays index 0 regardless of
	# Settings.home_human_slot: pick a non-ruck position and index 0 keeps
	# its AIBrain and rucks; pick slot 0 (or play FULL TEAM, which hands
	# the human the ruckman) and the human rucks in person with RB.
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
## Playtest feedback: a ball-up ran too fast to see what had happened — the
## ball simply appeared in the air. There is now a real throw-up in front
## of it: the field umpire walks to the spot and performs the crouch,
## wind-up and toss over Tuning.BALL_UP_THROW_DURATION, and only then does
## the ball actually go up (_release_ruck_contest below). Play stays dead
## for that whole beat.
func _begin_ruck_contest(spot: Vector3, contestant_a: PlayerController,
		contestant_b: PlayerController) -> void:
	GameState.phase = GameState.Phase.STOPPAGE
	MatchState.clock_running = false
	_drop_all_balls()
	# Locked, not just parked: a settled rigid body on the turf is still a
	# ball, and players were gathering it off the ground before it had been
	# thrown up. Ball.is_held() covers the lock, so gathering, marking and
	# hit-outs all refuse until it's released.
	_ball.lock_at(spot + Vector3.UP * 0.4)

	# Only ruckmen ruck (playtest: "if I am in single player control and NOT
	# ruckman I shouldn't go into ruck if I am rover"). Every caller passes
	# roster index 0 of each team, the RUCK slot (TeamFormation.ROSTER_
	# ORDER), so a field ball-up or throw-in no longer drafts the tackler
	# and tackled or whoever was nearest. They're placed either side of the
	# spot the way _centre_bounce_slot places them for a centre bounce (a
	# stoppage cut, like _reposition_kickoff), HOME on its defensive (-X)
	# side.
	contestant_a.global_position = spot + Vector3(-RUCK_CONTEST_OFFSET, 0.0, 0.0)
	contestant_b.global_position = spot + Vector3(RUCK_CONTEST_OFFSET, 0.0, 0.0)
	contestant_a.velocity = Vector3.ZERO
	contestant_b.velocity = Vector3.ZERO
	# Nominated now, at the start of the throw-up, with a window that still
	# runs RUCK_CONTEST_WINDOW past the release: RB pressed during the toss
	# latches (PlayerController._update_ruck_contest) and the Chase camera
	# eases side-on while the umpire throws.
	var release := Tuning.BALL_UP_THROW_DURATION * Umpire.THROW_RELEASE_END
	contestant_a.set_ruck_contestant(true, release + Tuning.RUCK_CONTEST_WINDOW)
	contestant_b.set_ruck_contestant(true, release + Tuning.RUCK_CONTEST_WINDOW)
	_ruck_contestants = [contestant_a, contestant_b]
	# FULL_TEAM: the human takes the HOME ruckman for the contest (normally
	# already done when the stoppage was called — _hand_human_the_ruck).
	_hand_human_the_ruck(contestant_a if contestant_a.team == Tuning.Team.HOME else contestant_b)

	var umpire := _field.field_umpire()
	if is_instance_valid(umpire):
		# Beside the contest, facing it — not between the two ruckmen.
		var beside := (contestant_a.global_position - contestant_b.global_position) \
			.cross(Vector3.UP)
		beside = beside.normalized() if beside.length_squared() > 0.0001 else Vector3.BACK
		umpire.stand_at(spot + beside * Field.UMPIRE_CENTRE_OFFSET, spot)
		umpire.throw_up(Tuning.BALL_UP_THROW_DURATION)
		# In his hands for the whole performance rather than hovering at the
		# spot in front of him: the ball rides the grip point between the two
		# hands, so it goes down into the crouch and up with the arms.
		var grip := umpire.ball_hold_point()
		if is_instance_valid(grip):
			_ball.lock_to(grip)

	# Released when the arms reach the top of the sweep, not at the end of
	# the whole beat — the last stretch of the clip is him following through
	# and settling back, which happens after the ball has already gone.
	_start_pause(release, _release_ruck_contest.bind(spot, contestant_a, contestant_b))


## The ball actually leaving the umpire's hands — a gentle lob (see
## Tuning.BALL_UP_TOSS_SPEED) between the two ruckmen, not the hard drive
## _bounce_off() once borrowed from BOUNCE_SPEED. The two contestants are
## nominated here rather than at the top of the throw so
## Tuning.RUCK_CONTEST_WINDOW starts when the ball does, instead of burning
## down through the wind-up.
func _release_ruck_contest(spot: Vector3, contestant_a: PlayerController,
		contestant_b: PlayerController) -> void:
	contestant_a.set_ruck_contestant(true)
	contestant_b.set_ruck_contestant(true)
	_ruck_contestants = [contestant_a, contestant_b]
	# Thrown from wherever his hands actually are, arcing to come down at
	# the contest spot — he stands beside it, so a launch straight up would
	# drop the ball beside the two ruckmen rather than between them. Solves
	# the plain projectile for the horizontal speed that covers the gap in
	# the time the toss spends in the air; drag is ignored, which over the
	# metre or so involved is nothing.
	var from := _ball.global_position
	var target := spot + Vector3.UP * 0.4
	var rise := Tuning.BALL_UP_TOSS_SPEED
	var drop := maxf(from.y - target.y, 0.0)
	var flight := (rise + sqrt(rise * rise + 2.0 * Tuning.GRAVITY * drop)) / Tuning.GRAVITY
	var across := Vector3(target.x - from.x, 0.0, target.z - from.z) / maxf(flight, 0.05)
	var toss := across + Vector3.UP * rise
	_ball.reset_at(from)
	_ball.launch(toss.normalized(), toss.length(), Vector3.ZERO, null)
	GameState.phase = GameState.Phase.PLAY
	MatchState.clock_running = true


## FULL_TEAM: put the human on HOME's ruckman. Called the moment a ruck
## stoppage is called (centre bounce — quarter start or after a goal —
## field ball-up, boundary throw-in), not only once the umpire starts the
## throw-up: playtest, "at the end of quarter or score the player control
## stays on the player I have". The whole reset is then watched from the
## ruckman, and RB is live for the contest from its first frame.
func _hand_human_the_ruck(ruckman: PlayerController = null) -> void:
	if not _full_team_control() \
			or ControlMode.scheme_for(Tuning.Team.HOME) != ControlMode.Scheme.SINGLE_PLAYER:
		return
	if ruckman == null and not _home_players.is_empty():
		ruckman = _home_players[0]
	_assign_human_to(ruckman)


## A ruckman has palmed the ball away — the contest is over, so drop the
## "only the two ruckmen may gather" lock (PlayerController._ruck_contest_
## locked) immediately rather than making the on-ballers wait out the rest
## of RUCK_CONTEST_WINDOW. A missed hit-out leaves the lock to self-expire.
func _on_hit_out_resolved(player: PlayerController, connected: bool) -> void:
	if not connected:
		return
	MatchState.record_player_stat(player.roster_id, player.roster_name, "hitouts")
	for contestant in _ruck_contestants:
		if is_instance_valid(contestant):
			contestant.set_ruck_contestant(false)
	_ruck_contestants.clear()


## The neutral half of holding-the-ball (RULES_REFERENCE.md §4): tackled
## before PRIOR_OPPORTUNITY_GRACE elapses is nobody's fault, so instead of
## just leaving the tackle's own spill to a free-for-all scramble (the old
## behaviour — this signal previously had no listener at all), it becomes
## a real, brief stoppage at the tackle spot, contested by the two players
## who were already right there. The free-kick half (holding_the_ball_
## called) is a separate, harder problem — see HANDOVER.md (archived, see docs/LESSONS.md).
func _on_player_disposed(action: Tuning.Action, player: PlayerController) -> void:
	MatchState.record_disposal(player.team, action)
	if action == Tuning.Action.KICK or action == Tuning.Action.HANDBALL:
		MatchState.record_player_stat(player.roster_id, player.roster_name,
			"kicks" if action == Tuning.Action.KICK else "handballs")
	if action == Tuning.Action.KICK:
		_last_kicker[player.team] = player
	if action == Tuning.Action.KICK:
		_on_home_kick_disposed(player)


## FULL_TEAM: the instant the human's own kick leaves the boot there is
## nothing left to control at the kicker's own feet while the ball is in
## the air — jump straight to whoever on HOME is nearest the kick's
## predicted landing spot (user report: "after I kick it, I should control
## the player closest to the ball's landing trajectory"). Same "control
## whoever matters" idea _on_home_gained_possession already applies once
## someone actually gathers the ball, just applied immediately instead of
## waiting for that gather — Ball.predicted_landing_position() is the same
## simple-projectile estimate LandingShadow already shows on screen, so
## this follows the same cue the player can see.
##
## Only for the human's own kick — an AI teammate disposing of the ball
## should not drag the human's control away from whatever they're doing —
## and not for a shot at goal (playtest: "this should not happen if the ball
## is going for a score"): you stay on the kicker to watch it go through.
func _on_home_kick_disposed(kicker: PlayerController) -> void:
	if GameState.phase != GameState.Phase.PLAY:
		return
	if not _full_team_control():
		return
	if ControlMode.scheme_for(Tuning.Team.HOME) != ControlMode.Scheme.SINGLE_PLAYER:
		return
	if kicker.team != Tuning.Team.HOME \
			or ControlMode.controlled_player(Tuning.Team.HOME) != kicker:
		return
	var landing := _ball.predicted_landing_position()
	if _is_shot_at_goal(_ball.global_position, landing, 1):
		return
	var next := ControlMode.next_in_roster(Tuning.Team.HOME, kicker, landing)
	_assign_human_to(next)


## Whether a flight from `from` to `landing` crosses the goal line at the
## `direction` end (+1 is HOME's attacking end) between the behind posts —
## a shot at goal, whatever comes of it. Straight-line between the two
## points, which over the length of a kick is close enough to the arc's own
## crossing for a which-side-of-the-post call.
func _is_shot_at_goal(from: Vector3, landing: Vector3, direction: int) -> bool:
	var line_x := _field.goal_line_x(direction)
	if (landing.x - line_x) * float(direction) <= 0.0 or is_equal_approx(landing.x, from.x):
		return false
	var t := clampf((line_x - from.x) / (landing.x - from.x), 0.0, 1.0)
	var cross_z := lerpf(from.z, landing.z, t)
	return absf(cross_z) <= Tuning.GOAL_POST_SEPARATION * 0.5 + Tuning.BEHIND_POST_OFFSET


func _on_player_marked(_tier: Tuning.Action, legal_mark: bool, player: PlayerController) -> void:
	MatchState.record_mark(player.team)
	if legal_mark:
		MatchState.record_player_stat(player.roster_id, player.roster_name, "marks")


## Career's per-player TACKLES: PlayerController.tackle_committed fires on
## the tackler only when an on-the-ball tackle connects and holds.
func _on_player_tackle_landed(_is_slide: bool, player: PlayerController) -> void:
	MatchState.record_player_stat(player.roster_id, player.roster_name, "tackles")


func _on_field_ball_up(tackler: PlayerController, tackled: PlayerController) -> void:
	if GameState.phase != GameState.Phase.PLAY:
		return
	if _after_siren_active():
		return   # only the kick after the siren matters now
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
	# to would have a scramble, not a ball-up. Rests on the turf, not
	# hovering over the spot.
	_rest_ball_at(spot)
	# Each team's ruckman contests it, not the tackler and tackled (see
	# _begin_ruck_contest).
	_hand_human_the_ruck()
	_start_pause(Tuning.CENTRE_BOUNCE_DELAY,
		_begin_ruck_contest.bind(spot, _home_players[0], _away_players[0]))


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
	if _after_siren_active():
		return   # only the kick after the siren matters now
	MatchState.record_tackle(tackler.team)
	var spot := tackler.global_position
	MatchState.clock_running = false
	GameState.phase = GameState.Phase.STOPPAGE
	_scoreboard.flash("HOLDING THE BALL — FREE KICK", Tuning.CENTRE_BOUNCE_DELAY)
	AudioManager.play_whistle()
	_start_pause(Tuning.CENTRE_BOUNCE_DELAY, _award_free_kick.bind(spot, tackler))


func _award_free_kick(spot: Vector3, tackler: PlayerController) -> void:
	_award_possession_at(spot, tackler)


## The 15 m run rule (RULES_REFERENCE.md §1: "Bounce every 15m while
## running" — BOUNCE_INTERVAL, a real AFL law, not a P1 feel number).
## PlayerController tracks the carry distance and fires run_too_far_called
## the instant it passes 15 m with no bounce. Same handling as
## _on_holding_the_ball: whistle, brief stoppage, free kick to the nearest
## opponent at the spot, reusing _award_possession_at's shared possession +
## protection tail. AIBrain bounces well before 15 m
## (Tuning.AI_BOUNCE_AT_FRACTION), so in practice this only catches a human
## who didn't bounce.
func _on_run_too_far(carrier: PlayerController) -> void:
	if GameState.phase != GameState.Phase.PLAY:
		return
	if _after_siren_active():
		return   # only the kick after the siren matters now
	var opponents := _away_players if carrier.team == Tuning.Team.HOME else _home_players
	var receiver := _nearest_player(opponents, carrier.global_position)
	if receiver == null:
		return
	var spot := carrier.global_position
	MatchState.clock_running = false
	GameState.phase = GameState.Phase.STOPPAGE
	_scoreboard.flash("RUNNING TOO FAR — FREE KICK", Tuning.CENTRE_BOUNCE_DELAY)
	AudioManager.play_whistle()
	_start_pause(Tuning.CENTRE_BOUNCE_DELAY, _award_possession_at.bind(spot, receiver))


## A tackle or bump that wasn't allowed (PlayerController.infringed):
## `fouled` gets a free kick where they stand — or, for a hit on a player
## holding the ball under protection, a 50 m penalty: the mark moves 50 m
## toward the goal `fouled`'s team attacks, stopping just short of the goal
## line (_fifty_metre_spot). Same stoppage shape as holding the ball.
func _on_infringed(fouled: PlayerController, fifty: bool, offender: PlayerController) -> void:
	if GameState.phase != GameState.Phase.PLAY:
		return
	if _after_siren_active():
		return   # only the kick after the siren matters now
	var spot := fouled.global_position
	if fifty:
		spot = _fifty_metre_spot(spot, fouled.team)
	MatchState.clock_running = false
	GameState.phase = GameState.Phase.STOPPAGE
	_scoreboard.flash("50 METRE PENALTY" if fifty else "FREE KICK — OFF THE BALL",
		Tuning.INFRINGEMENT_PAUSE_DURATION)
	AudioManager.play_whistle()
	# Dead ball for the pause, resting where the kick will be taken, while
	# the hit itself plays out (the fouled player may be ragdolling).
	_drop_all_balls()
	_rest_ball_at(spot)
	_start_pause(Tuning.INFRINGEMENT_PAUSE_DURATION, _award_infringement.bind(spot, fouled))


func _award_infringement(spot: Vector3, fouled: PlayerController) -> void:
	fouled.global_position = Vector3(spot.x, fouled.global_position.y, spot.z)
	_award_possession_at(spot, fouled)


## `from` moved Tuning.FIFTY_METRE_PENALTY toward the goal `team` attacks
## (HOME +X, AWAY -X), no closer than FIFTY_METRE_GOAL_LINE_SETBACK to the
## goal line, and pulled back inside the boundary if the move took it out
## (a mark near the wing moved toward a goal at the narrow end).
func _fifty_metre_spot(from: Vector3, team: Tuning.Team) -> Vector3:
	var direction := 1 if team == Tuning.Team.HOME else -1
	var limit := _field.goal_line_x(direction) - float(direction) * Tuning.FIFTY_METRE_GOAL_LINE_SETBACK
	var x := from.x + float(direction) * Tuning.FIFTY_METRE_PENALTY
	if (x - limit) * float(direction) > 0.0:
		x = limit
	var spot := Vector3(x, 0.0, from.z)
	if not _field.is_inside_oval(spot, 2.0):
		spot = _throw_in_point(spot)
		spot.y = 0.0
	return spot


## Shared tail of every "possession + immunity at a spot" restart (free
## kick, protected kick-in, out on the full) — see HANDOVER.md (archived, see docs/LESSONS.md) for why
## this exact give_possession()/grant_protection() triad is the one
## established pattern instead of a parallel state machine per restart type.
## MARK_HOLD_DURATION is reused rather than a new invented threshold: the
## same duration a legal mark protects its taker for is "safe to take your
## time with the footy in hand" everywhere in this project, not just marks.
## `retreat` walks the receiver back off the spot exactly as a legal mark
## does (_finish_mark_catch chains the same call) — a free kick reads like
## a mark and should back away for its run-up the same way. The goal-square
## kick-in is the one caller that passes false: it's already on the line.
func _award_possession_at(spot: Vector3, receiver: PlayerController, retreat := true) -> void:
	_drop_all_balls()
	_ball.reset_at(spot + Vector3.UP * 0.3)
	receiver.give_possession(_ball)
	receiver.grant_protection(Tuning.MARK_HOLD_DURATION)
	if retreat:
		receiver.begin_mark_retreat()
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
	# Goals and behinds go to the scoring team's last kicker. Field's
	# `scored` doesn't say who touched it last, so a rushed behind is
	# credited to that kicker too — an AFL box score credits it to nobody.
	var kicker: PlayerController = _last_kicker.get(team)
	if is_instance_valid(kicker):
		MatchState.record_player_stat(kicker.roster_id, kicker.roster_name,
			"goals" if is_goal else "behinds")
	GameState.phase = GameState.Phase.SCORE
	# Dead from the moment it's a score — nobody may gather it during the
	# celebration — but NOT frozen where it is: a hard lock_at() here
	# snapped the ball to a dead stop on the goal line mid-flight. set_
	# unplayable() keeps is_held true (no gather/mark, and _check_out_of_
	# bounds ignores it) while letting it fly on through the posts under
	# its own physics, the way a real one does. The restart repositions it
	# (a centre bounce's _rest_ball_at, a kick-in's reset_at), both of
	# which clear the flag.
	_ball.set_unplayable(true)
	var label := "GOAL" if is_goal else "BEHIND"
	_scoreboard.flash("%s! %s" % [label, _team_name(team)], Tuning.SCORE_PAUSE_DURATION)
	_camera.punch(Tuning.CAM_PUNCH_KICK)
	# A kick after the siren: the score counts, then the quarter is over —
	# no restart.
	if _after_siren_active():
		_after_siren_kicker = null
		_start_pause(Tuning.SCORE_PAUSE_DURATION, _end_quarter)
		return
	# AFL restarts a GOAL with a centre bounce; a BEHIND restarts with a
	# protected kick-in by the team that conceded it (design brief
	# priority 5) — not another centre bounce, which is what every score
	# used to get here regardless of which it was.
	if is_goal:
		_start_pause(Tuning.SCORE_PAUSE_DURATION,
			_prepare_centre_bounce.bind(Tuning.GOAL_RESTART_BOUNCE_DELAY))
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
	# No walk-back: a kick-in is already on the goal line.
	_award_possession_at(square_centre, kicker, false)


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
## FEATURE_AUDIT.md (archived)). Holds the scoreboard flash for a beat so the
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


## Career's own full-time screen reads MatchState fresh, same as
## MatchEndScreen does — the only thing done here is advancing the season
## (CareerProfile.record_result()) before handing off, so the Dashboard
## afterward already sees the incremented games_played. GameState.
## career_active itself is left set until career_match_end_screen.gd's
## RETURN TO MENU clears it — see that file and GameState.gd's own header
## note on why the clear lives there, not here.
func _show_match_end_screen() -> void:
	if GameState.career_active:
		# Snapshot the result into the save before advancing the fixture, so
		# the full-time screen and the Dashboard's VIEW STATS read the same
		# persisted copy (current_fixture() still names this opponent here).
		CareerProfile.record_result({
			"opponent": CareerProfile.current_fixture(),
			"home_score": MatchState.scoreline(Tuning.Team.HOME),
			"away_score": MatchState.scoreline(Tuning.Team.AWAY),
			"home_points": MatchState.points(Tuning.Team.HOME),
			"away_points": MatchState.points(Tuning.Team.AWAY),
			"goals": MatchState.top_goalkickers(CareerMatchEndScreen.LEADERBOARD_SIZE),
			"disposals": MatchState.top_disposals(CareerMatchEndScreen.LEADERBOARD_SIZE),
			"player_stats": _home_player_stats(),
		})
		SceneWipe.change_scene("res://scenes/ui/career_match_end_screen.tscn")
		return
	SceneWipe.change_scene(MATCH_END_SCREEN_PATH)


## Every HOME player's box score for the season stats, keyed by Career
## roster id — all 18, zeros included, since everyone who played gets the
## game (there's no interchange bench to sit on yet).
func _home_player_stats() -> Dictionary:
	var stats := {}
	for i in mini(_home_players.size(), CareerProfile.roster.size()):
		var player := _home_players[i]
		var row := {}
		for stat: String in MatchState.PLAYER_STATS:
			row[stat] = MatchState.player_stat(player.roster_id, stat)
		stats[int(CareerProfile.roster[i].get("id", i))] = row
	return stats


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
	# off the ground slab's finite extent. Checked first and unconditionally
	# — a ball in freefall past the edge of the world is technically also
	# "out of bounds", but there is no sane crossing point to throw it in
	# from, so it wants the full reset rather than the boundary handling
	# below.
	if pos.y < Tuning.BALL_LOST_BELOW \
			or absf(pos.x) > Tuning.FIELD_HALF_LENGTH + Field.SURROUND_MARGIN \
			or absf(pos.z) > Tuning.FIELD_HALF_WIDTH + Field.SURROUND_MARGIN:
		_reset_ball()
		_prev_ball_pos_valid = false
		return

	# Rulebook §7's decision tree, in the order it's written: the ball
	# leaving play is one call, made the instant it happens; *then* the
	# reason it left decides which restart follows. This used to be two
	# unrelated tests — an every-frame airborne watch for out on the full,
	# and a rolled-out case gated on _ball.is_settled(), i.e. one that only
	# fired once the ball had come to a complete stop somewhere past the
	# line. That's why it worked on obvious kicks and missed a ball rolling
	# or bouncing out in general play: play carried on, sometimes for
	# several seconds, while the ball was already out.
	if not _prev_ball_pos_valid:
		_prev_ball_pos = pos
		_prev_ball_pos_valid = true
		return
	if _is_in_play(pos):
		_prev_ball_pos = pos
		return

	# Out. Bisect the segment between last frame's (in-play) and this
	# frame's (out) position rather than just taking whichever frame
	# happened to land outside — at up to ~24 m/s plus carried momentum a
	# single frame's overshoot is small but not free, and this only ever
	# runs on the one frame a crossing is detected.
	var crossing := pos
	if _is_in_play(_prev_ball_pos):
		crossing = _bisect_boundary_crossing(_prev_ball_pos, pos)
	elif not _ball.is_settled():
		# Already out with no crossing ever observed — the ball was placed
		# or knocked out across a frame this check was skipped. Fall back
		# to waiting for it to stop and using where it came to rest, which
		# is what every rolled-out ball used to get, so it can't sit out of
		# bounds indefinitely with play carrying on around it.
		return
	_prev_ball_pos_valid = false
	# "Is it out on the full?" — only a live, untouched KICK still in the
	# air qualifies (Ball.is_kick_flight() is cleared on landing and on
	# knock()). A handball/bounce/hit-out/spoiled deflection that sails out
	# isn't out on the full under the real rule; it's a throw-in like any
	# other ball out of bounds.
	if _ball.is_airborne() and _ball.is_kick_flight():
		_trigger_out_on_the_full(crossing, _ball.kick_team())
	else:
		_trigger_out_of_bounds(crossing)


## Rulebook §7's "fully rolled over the boundary line" — the ball is out
## when no part of it is still over the line, not when its centre crosses.
## The oval test is expanded by the ball's own longest radius (treating it
## as a sphere of BALL_SEMI_MAJOR, which is the conservative read: it keeps
## a ball that's still fractionally touching the line in play). One
## definition, shared by the crossing test and the bisection that follows
## it, so the two can't disagree about where the line is.
func _is_in_play(pos: Vector3) -> bool:
	return _field.is_inside_oval(pos, -Tuning.BALL_SEMI_MAJOR)


func _bisect_boundary_crossing(inside_pos: Vector3, outside_pos: Vector3) -> Vector3:
	var a := inside_pos
	var b := outside_pos
	for i in 8:
		var mid := (a + b) * 0.5
		if _is_in_play(mid):
			a = mid
		else:
			b = mid
	return (a + b) * 0.5


## Free kick to `receiving_team` from the crossing point — reuses exactly
## the same give_possession()/grant_protection() triad the protected kick-in
## and the holding-the-ball free kick already reuse from each other, per
## this project's own established pattern for "possession + immunity at a
## spot" (see HANDOVER.md (archived, see docs/LESSONS.md)). `kicking_team` is read from Ball.kick_team()
## at the instant of crossing, since the ball's own _carrier reference has
## long since been cleared by RELEASE_GRACE for anything but a very short kick.
func _trigger_out_on_the_full(pos: Vector3, kicking_team: Tuning.Team) -> void:
	if _after_siren_active():
		_finish_after_siren()   # out after the siren: nothing to restart
		return
	if kicking_team == Tuning.Team.NONE:
		# Shouldn't happen — _check_out_of_bounds only calls this while
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
	_ball.lock_at(spot + Vector3.UP * 0.5)
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
	if _after_siren_active():
		_finish_after_siren()
		return
	var throw_in_point := _throw_in_point(pos)
	# Brought back to the line and held there for the pause, the same
	# "settle before the pause, not after" shape out on the full uses —
	# it stops the ball rolling on into the fence, and stops anyone
	# collecting it out of bounds while play is dead. Rests on the turf
	# rather than hovering just inside the line.
	_rest_ball_at(throw_in_point)
	MatchState.clock_running = false
	GameState.phase = GameState.Phase.STOPPAGE
	_scoreboard.flash("OUT OF BOUNDS", Tuning.OUT_OF_BOUNDS_PAUSE_DURATION)
	AudioManager.play_whistle()
	_hand_human_the_ruck()
	_start_pause(Tuning.OUT_OF_BOUNDS_PAUSE_DURATION,
		_resume_after_out_of_bounds.bind(throw_in_point))


## Boundary throw-in, through the same shared contest as the centre bounce
## and a field ball-up (design brief priority 4/6) — "nearest player per
## side" for who contests it, per Prototype 1's own throw-in/ball-up model
## (see this project's memory of P1's contest_minigame.py approach).
func _resume_after_out_of_bounds(throw_in_point: Vector3) -> void:
	_drop_all_balls()
	_begin_ruck_contest(throw_in_point, _home_players[0], _away_players[0])


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
##
## Only reached at all in Settings.PlayerControlMode.FULL_TEAM (see
## _unhandled_input) — Settings.PlayerControlMode.SINGLE_PLAYER leaves the
## human on whichever body _spawn_teams() started them on for the whole
## match and gets _call_for_ball() instead.
##
## FULL_TEAM: the switch goes straight to the HOME player nearest the ball
## (ControlMode.next_in_roster with a reference point) rather than spawn-
## array order. It no longer suppresses auto-carrier control afterwards —
## a switch is now itself just "get me to the ball", the same intent
## _on_home_gained_possession serves, so there is nothing to protect from
## it.
func _switch_human_player() -> void:
	if ControlMode.scheme_for(Tuning.Team.HOME) == ControlMode.Scheme.TEAM_COMMAND:
		_cycle_team_command_selection()
		return

	var previous := ControlMode.controlled_player(Tuning.Team.HOME)
	# Straight to the HOME player nearest the ball — pass the ball as the
	# reference (see ControlMode.next_in_roster). One press puts you on
	# whoever's on the ball; if you're already there this returns the same
	# body and the guard below no-ops.
	var next := ControlMode.next_in_roster(Tuning.Team.HOME, previous, _ball.global_position)
	if next == previous:
		return
	_assign_human_to(next)


## Move the one HumanBrain onto `next`, hand the old body a fresh AI brain,
## and tell ControlMode. Shared by _switch_human_player (manual) and
## _on_home_gained_possession (auto-carrier) so the two can't drift on how
## a hand-off is actually done.
func _assign_human_to(next: PlayerController) -> void:
	var previous := ControlMode.controlled_player(Tuning.Team.HOME)
	if next == previous or not is_instance_valid(next):
		return
	if is_instance_valid(previous):
		previous.set_brain(_configure_ai_brain(
			AIBrain.new(), Tuning.Team.HOME, 1.0, previous.global_position))
	next.set_brain(HumanBrain.new())
	ControlMode.set_controlled_player(Tuning.Team.HOME, next)
	# CharacterProfile stats are NOT moved here — _apply_character_profile
	# bound them to the pregame start slot (or all of HOME) at spawn, and
	# that binding is deliberately fixed regardless of who you're driving.


## FULL_TEAM: every time HOME wins the ball in open play, put the human
## straight onto the carrier — you control whoever has it without hunting
## for the switch key. Fires on every gather/mark (ball_gathered), with no
## post-switch suppression window: a manual switch is itself just "get me
## to the ball" now, so there is no deliberate off-ball pick to protect.
## Only in SINGLE_PLAYER scheme — TEAM_COMMAND has its own selection model.
func _on_home_gained_possession(_ball_ref: Ball, carrier: PlayerController) -> void:
	if not _full_team_control():
		return
	if ControlMode.scheme_for(Tuning.Team.HOME) != ControlMode.Scheme.SINGLE_PLAYER:
		return
	if carrier.team != Tuning.Team.HOME or GameState.phase != GameState.Phase.PLAY:
		return
	_assign_human_to(carrier)


# ── Call for the ball (SINGLE_PLAYER player-control mode) ────────────
# Settings.PlayerControlMode.SINGLE_PLAYER locks the human to one body for
# the whole match, which takes switch_player's escape hatch away: when a
# teammate has the footy there is otherwise nothing at all the human can do
# to influence what happens to it. This is that mode's replacement — lead
# into space, shout for it, and the carrier may or may not give it to you.
# Not an AFL rule (see Tuning's CALL_FOR_BALL_* block), and deliberately a
# request rather than a command: a guaranteed handball would make the AI a
# ball-delivery service and every contest optional.

## No-ops (silently, no cooldown burned) whenever there's nothing to ask
## for: ball loose, AWAY has it, or the human is already the carrier. That
## last case is not a special case worth feedback — the answer to "give me
## the ball" when you're holding it is nothing. Deliberately no toast/
## prompt/SFX on any of these: this project has no general-purpose player-
## feedback channel to reuse (AudioManager's only public cues are the
## umpire's whistle and full time, both of which would read as an actual
## umpiring decision here), and inventing one is UI scope this pass doesn't
## own.
func _call_for_ball() -> void:
	if GameState.phase != GameState.Phase.PLAY or _call_for_ball_cooldown > 0.0:
		return
	var caller := ControlMode.controlled_player(Tuning.Team.HOME)
	if not is_instance_valid(caller) or caller.is_carrying():
		return
	var carrier := _ball.holder() as PlayerController
	if carrier == null or carrier == caller or carrier.team != Tuning.Team.HOME:
		return
	# The carrier is a real HOME teammate, so the shout happens and costs its
	# cooldown from here on, whether or not it works — including the
	# out-of-range case below, which is a call that simply couldn't be heard
	# rather than one that was never made.
	_call_for_ball_cooldown = Tuning.CALL_FOR_BALL_COOLDOWN
	# Placeholder visible feedback for the call itself (user report: "A to
	# call for ball... should be more visibly working" — a real animation
	# can replace this flash later, see ControlledPlayerRing.flash()'s own
	# comment). Fires whether or not the carrier actually gives it up,
	# same as the cooldown above: the shout happened either way.
	if is_instance_valid(_controlled_ring):
		_controlled_ring.flash()

	if caller.global_position.distance_to(carrier.global_position) > Tuning.CALL_FOR_BALL_RANGE:
		return
	# Only an AI-run teammate can be asked. A human-driven carrier can't be
	# (there's only one human body in this mode, and it's the caller), but
	# the cast keeps this correct rather than crashing the day local
	# multiplayer puts a second HumanBrain on the field.
	var carrier_ai := carrier.brain() as AIBrain
	if carrier_ai == null:
		return
	if randf() >= _call_for_ball_success_chance(carrier, caller):
		return   # refused — the carrier just plays on under its own judgement
	carrier_ai.request_handball_to(caller)


## 0..1 chance that `carrier` actually gives it up when `caller` shouts.
## Three factors, all measured off geometry that already exists in this
## match rather than off any invented per-player rating — there is no
## per-teammate stat data in this project to weigh (CharacterProfile is a
## single global profile describing the human's own body, and every AI
## PlayerController is spawned from one identical scene with identical
## Tuning-driven physics), so a "teammate rating" term would be fabricated.
##
## 1. PRESSURE on the carrier — nearest AWAY player's distance to them,
##    against Tuning.AI_PRESSURE_RADIUS. Pressure RAISES the chance, and
##    that direction is chosen to agree with the AI this mechanic is asking
##    a favour of: AIBrain._think_carrying already treats an opponent inside
##    AI_PRESSURE_RADIUS as the trigger to offload immediately (it handballs
##    on its own at that point). A carrier who is already looking to get rid
##    of it takes the option being offered; one running free would rather
##    back itself and shoot, so the call has to be more persuasive. The
##    opposite reading ("too rattled to risk it") would have the mechanic
##    fight the existing state machine instead of reinforcing it, and would
##    make the call useless in exactly the situation a teammate leading into
##    space is most valuable.
## 2. OPENNESS of the caller — nearest AWAY player's distance to THEM.
##    Rewards actually leading into space; a caller with a defender draped
##    on them is a bad option and the carrier treats it as one. Fully open
##    at twice AI_PRESSURE_RADIUS (i.e. at double the range at which the AI
##    itself considers a player pressured), covered at zero.
## 3. RANGE — caller-to-carrier distance against Tuning.CALL_FOR_BALL_RANGE,
##    a mild tax across the band rather than a second cliff; the hard cliff
##    is _call_for_ball()'s own range refusal above.
func _call_for_ball_success_chance(carrier: PlayerController, caller: PlayerController) -> float:
	var pressure := 1.0 - clampf(
		_nearest_opponent_distance(_away_players, carrier.global_position)
		/ Tuning.AI_PRESSURE_RADIUS, 0.0, 1.0)
	var openness := clampf(
		_nearest_opponent_distance(_away_players, caller.global_position)
		/ (Tuning.AI_PRESSURE_RADIUS * 2.0), 0.0, 1.0)
	var reach := clampf(
		carrier.global_position.distance_to(caller.global_position)
		/ Tuning.CALL_FOR_BALL_RANGE, 0.0, 1.0)

	return clampf(
		Tuning.CALL_FOR_BALL_BASE_CHANCE
		+ Tuning.CALL_FOR_BALL_PRESSURE_BONUS * pressure
		+ Tuning.CALL_FOR_BALL_OPENNESS_BONUS * openness
		- Tuning.CALL_FOR_BALL_RANGE_PENALTY * reach,
		Tuning.CALL_FOR_BALL_MIN_CHANCE, Tuning.CALL_FOR_BALL_MAX_CHANCE)


## INF when `players` is empty, so an absent opponent reads as "no pressure
## at all" through the clamps above rather than as zero distance (maximum
## pressure), which is what a plain 0.0 fallback would have meant.
func _nearest_opponent_distance(players: Array[PlayerController], spot: Vector3) -> float:
	var nearest := _nearest_player(players, spot)
	return INF if nearest == null else nearest.global_position.distance_to(spot)


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
