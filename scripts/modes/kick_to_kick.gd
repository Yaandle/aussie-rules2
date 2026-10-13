extends Node3D

## Solo free-roam practice (reached via the character screen's PLAY row):
## one player, one ball, the full field, no AI, no clock, no scoring —
## just movement and disposal with an unlimited ball reset. Functionally
## the milestone-1 sandbox (scripts/main.gd) with two differences: it's
## reachable from the menu/character-screen flow instead of being the
## boot scene, and it applies whatever SPEED/HEIGHT the character screen
## was left on (CharacterProfile) to the player it spawns.
##
## Also where the training coaches live (design brief): walk up to a coach,
## X to talk, confirm to start a challenge. All three planned coaches are
## here — kicking (kick at a downfield target), marking (catch the coach's
## deliveries) and tackling (run down and tackle the rival before it gets
## rid of the ball) — sharing one CoachKind-parameterised prompt/dialogue/
## challenge state machine rather than one copy per coach. kick_to_kick
## only for now — wiring any of this into Full Game is later work.
## See docs/HANDOVER.md for the full writeup, including which pieces here
## are rough placeholders standing in for UI this agent doesn't own.

const BALL_RESET_AHEAD := 3.0

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const COACH_SCENE := preload("res://scenes/mechanics/coach_npc.tscn")
const KICK_CHALLENGE_SCENE := preload("res://scenes/mechanics/kick_challenge.tscn")
const MARK_CHALLENGE_SCENE := preload("res://scenes/mechanics/mark_challenge.tscn")
const TACKLE_TUTORIAL_SCENE := preload("res://scenes/mechanics/tackle_tutorial.tscn")
const TACKLE_BAG_SCENE := preload("res://scenes/props/tackle_bag.tscn")
const PAUSE_SCREEN_SCENE := preload("res://scenes/ui/pause_screen.tscn")

enum CoachState { NONE, PROMPT, DIALOGUE, CHALLENGE }

## Which coach _coach_state currently refers to. A player can only be in
## interact range of one coach at a time (they stand well apart), so one
## shared prompt/dialogue/challenge state machine serves all three rather
## than duplicating it per coach — see _setup_coach/_spawn_coach and every
## _active_coach branch below.
enum CoachKind { KICKING, MARKING, TACKLING }

## Per-coach copy for the dialogue card (eyebrow drill name + one-line pitch).
const COACH_COPY := {
	CoachKind.KICKING: {
		"drill": "KICKING",
		"body": "Let's work on your kicking technique.",
	},
	CoachKind.MARKING: {
		"drill": "MARKING",
		"body": "Let's work on your marking.",
	},
	CoachKind.TACKLING: {
		"drill": "TACKLING",
		"body": "Let's work on your tackling technique.",
	},
}

## Shown by the hint label while the player is in range of a coach.
const PROMPT_TEXT := "X  Talk to coach"

@onready var _field: Field = $Field
@onready var _ball: Ball = $Ball
@onready var _player: PlayerController = $Player
@onready var _camera: BroadcastCamera = $BroadcastCamera
@onready var _hud: DebugHud = $DebugHud

var _kicking_coach: CoachNPC
var _marking_coach: CoachNPC
var _tackling_coach: CoachNPC
var _challenge: KickChallenge
var _mark_challenge: MarkChallenge
var _tackle_tutorial: TackleTutorial
var _coach_state := CoachState.NONE
var _active_coach: CoachKind = CoachKind.KICKING
var _crosshair: KickCrosshair
var _mark_prompt: MarkPrompt
var _rival: PlayerController

## The tackling tutorial's step card (built in _build_tutorial_card). While
## visible, play is frozen (InputManager.gameplay_input_enabled = false) and
## `confirm` starts the rep / `decline` skips the step — see _unhandled_input.
var _tutorial_card: Control
var _tutorial_card_title: Label
var _tutorial_card_body: Label
var _tutorial_card_kb: KeyHintBar
var _tutorial_card_pad: KeyHintBar

## The coach dialogue card (built in _build_dialogue_card). Shown during
## CoachState.DIALOGUE; confirm/decline are routed in _unhandled_input.
var _dialogue_card: Control
var _dialogue_eyebrow: Label
var _dialogue_body: Label

## Plain hint label: the in-range prompt and in-drill/result messages. The
## dialogue itself lives in the styled card above. Built in code rather than
## a scene so it's trivially replaceable.
var _prompt_label: Label


func _ready() -> void:
	GameState.mode = GameState.Mode.KICK_TO_KICK
	GameState.phase = GameState.Phase.PLAY

	_player.speed_scale = CharacterProfile.speed_scale()
	_player.agility_scale = CharacterProfile.agility_scale()
	_player.kick_power_scale = CharacterProfile.kick_power
	_player.kick_accuracy = CharacterProfile.kick_accuracy
	(_player.get_node("Rig") as Node3D).scale = Vector3.ONE * CharacterProfile.height_scale()
	AudioManager.register_player(_player)

	_camera.target = _player
	_camera.ball = _ball
	_camera.recenter()
	_player.camera = _camera.camera()

	_hud.player = _player
	_hud.ball = _ball

	_crosshair = KickCrosshair.new()
	_crosshair.player = _player
	add_child(_crosshair)

	_mark_prompt = MarkPrompt.new()
	_mark_prompt.player = _player
	_mark_prompt.ball = _ball
	add_child(_mark_prompt)

	_player.ball_disposed.connect(_on_ball_disposed)

	_spawn_rival()

	_ball.reset_at(_field.centre())
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	_setup_coach()
	_setup_tackle_ground()
	_build_placeholder_prompt()
	_build_tutorial_card()
	_build_dialogue_card()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"pause"):
		_open_pause_menu()
		return
	if event.is_action_pressed(&"debug_reset"):
		_reset_ball()
		return

	# The tackling tutorial's step card owns input while it's up: play is
	# frozen behind it, confirm starts the rep, decline skips the step.
	if is_instance_valid(_tutorial_card) and _tutorial_card.visible:
		if event.is_action_pressed(&"confirm"):
			_dismiss_tutorial_card()
			_tackle_tutorial.begin_rep()
		elif event.is_action_pressed(&"decline"):
			_dismiss_tutorial_card()
			_tackle_tutorial.skip_step()
		return

	match _coach_state:
		CoachState.PROMPT:
			if event.is_action_pressed(&"interact"):
				_begin_dialogue()
		CoachState.DIALOGUE:
			if event.is_action_pressed(&"confirm"):
				_accept_challenge()
			elif event.is_action_pressed(&"decline"):
				_end_dialogue()


## Esc used to hard-cut straight to the main menu — PauseScreen already
## existed fully built and simply wasn't wired to anything (see
## docs/FEATURE_AUDIT.md). Same paused-overlay shape full_game.gd now
## uses; the one difference here is the mouse capture this scene sets in
## _ready(), which has to be released while the (keyboard/gamepad-only)
## pause menu is up and re-captured on resume.
func _open_pause_menu() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	var pause_screen := PAUSE_SCREEN_SCENE.instantiate()
	pause_screen.process_mode = Node.PROCESS_MODE_ALWAYS
	pause_screen.resumed.connect(func() -> void:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED))
	add_child(pause_screen)
	get_tree().paused = true


func _physics_process(_delta: float) -> void:
	# Safety net, same as the sandbox's — the ball is a real rigid body,
	# so it can genuinely be lost off the map.
	var where := _ball.global_position
	if where.y < Tuning.BALL_LOST_BELOW \
			or absf(where.x) > Tuning.FIELD_HALF_LENGTH + Field.SURROUND_MARGIN \
			or absf(where.z) > Tuning.FIELD_HALF_WIDTH + Field.SURROUND_MARGIN:
		_reset_ball()

	# CoachNPC only reports enter/exit edges, so a player who walked up
	# already carrying the ball (prompt correctly withheld — see
	# _on_coach_range_entered) and then dropped/disposed it while still
	# standing there needs a live re-check, not just the one-shot signal.
	if _coach_state == CoachState.NONE and not _player.is_carrying():
		if not _check_coach_in_range(CoachKind.KICKING) and not _check_coach_in_range(CoachKind.MARKING):
			_check_coach_in_range(CoachKind.TACKLING)

	# Frozen for the duration of any coach dialogue/challenge so a drill stays
	# a clean 1-on-0 loop — resumes the instant the coach state clears. One
	# deliberate exception: the tackling tutorial's rival is the dummy that
	# jogs at the player during a rep, so it stays live for exactly that —
	# TackleTutorial.rep_active() is false while a step card is up or during
	# the between-steps beat, so the dummy holds still until the player
	# dismisses the card.
	if is_instance_valid(_rival):
		var rival_active := _coach_state == CoachState.NONE \
			or (_coach_state == CoachState.CHALLENGE and _active_coach == CoachKind.TACKLING \
				and is_instance_valid(_tackle_tutorial) and _tackle_tutorial.rep_active())
		_rival.set_physics_process(rival_active)


func _reset_ball() -> void:
	if is_instance_valid(_challenge):
		_challenge.force_miss()
	if is_instance_valid(_mark_challenge):
		_mark_challenge.force_miss()
	if is_instance_valid(_tackle_tutorial):
		_tackle_tutorial.force_miss()
	_player.drop_ball()
	if is_instance_valid(_rival):
		_rival.drop_ball()
	var ahead := -_player.global_transform.basis.z * BALL_RESET_AHEAD
	_ball.reset_at(_player.global_position + ahead + Vector3.UP * 0.3)


## A live sparring partner (design brief: "build out kick-to-kick so we can
## use this for testing"), not just the coaches' scripted deliveries —
## reuses AIBrain wholesale (see Tuning's own comment) rather than a bespoke
## behaviour, positioned clear of both coach zones so it never interferes
## with a drill while free-roaming (it's frozen outright during one anyway
## — see _physics_process).
func _spawn_rival() -> void:
	var rival := PLAYER_SCENE.instantiate() as PlayerController
	rival.team = Tuning.Team.AWAY
	# Set before add_child(), same reasoning full_game.gd's own spawn code
	# documents: HumanoidRig._ready() reads away_kit on its first build, and
	# the physics server latches the spawn transform at add_child() time.
	(rival.get_node("Rig") as HumanoidRig).away_kit = true
	var stand := _field.centre() + Tuning.KICK_TO_KICK_RIVAL_OFFSET
	rival.position = stand
	add_child(rival)
	AudioManager.register_player(rival)

	var brain := AIBrain.new()
	brain.ball = _ball
	brain.home_position = stand
	brain.attack_direction = 1.0
	rival.set_brain(brain)

	_rival = rival


func _check_coach_in_range(kind: CoachKind) -> bool:
	var coach := _coach_node(kind)
	if not is_instance_valid(coach) or coach.player_in_range() != _player:
		return false
	_coach_state = CoachState.PROMPT
	_active_coach = kind
	_set_hint_text(PROMPT_TEXT)
	return true


func _on_ball_disposed(action: Tuning.Action) -> void:
	if action == Tuning.Action.KICK:
		_camera.punch(Tuning.CAM_PUNCH_KICK)
	if is_instance_valid(_challenge):
		_challenge.notify_disposed(action)


# ── Training coach ───────────────────────────────────────────────────

func _setup_coach() -> void:
	_kicking_coach = _spawn_coach(Tuning.COACH_STAND_OFFSET, CoachKind.KICKING)
	_challenge = KICK_CHALLENGE_SCENE.instantiate()
	add_child(_challenge)
	_challenge.challenge_ended.connect(_on_kick_challenge_ended)
	_challenge.hint_changed.connect(_set_hint_text)

	_marking_coach = _spawn_coach(Tuning.MARK_COACH_STAND_OFFSET, CoachKind.MARKING)
	_mark_challenge = MARK_CHALLENGE_SCENE.instantiate()
	add_child(_mark_challenge)
	_mark_challenge.challenge_ended.connect(_on_mark_challenge_ended)
	_mark_challenge.hint_changed.connect(_set_hint_text)

	_tackling_coach = _spawn_coach(Tuning.TACKLE_COACH_STAND_OFFSET, CoachKind.TACKLING)
	_tackle_tutorial = TACKLE_TUTORIAL_SCENE.instantiate()
	add_child(_tackle_tutorial)
	_tackle_tutorial.challenge_ended.connect(_on_tackle_tutorial_ended)
	_tackle_tutorial.hint_changed.connect(_set_hint_text)
	_tackle_tutorial.step_changed.connect(_show_tutorial_card)


## Training-ground dressing: a few padded tackle bags standing by the
## tackling coach so that corner of the field reads as a drills area rather
## than bare turf. Pure scenery — TackleBag carries no PlayerController and
## sits on the "world" layer, so it's solid to run into but invisible to
## every contest query. Same "position before add_child(), Y from a feet-at-
## origin rig" convention as _spawn_coach.
func _setup_tackle_ground() -> void:
	var base := _field.centre() + Tuning.TACKLE_COACH_STAND_OFFSET
	base.y = 0.0
	for i in Tuning.TACKLE_BAG_OFFSETS.size():
		var bag := TACKLE_BAG_SCENE.instantiate() as TackleBag
		bag.position = base + Tuning.TACKLE_BAG_OFFSETS[i]
		# Index 0 stands by the coach; the rest lie on the ground.
		if i > 0:
			bag.lying = true
			bag.lie_yaw = Tuning.TACKLE_BAG_LIE_YAWS[i - 1]
		add_child(bag)


## Position before add_child(), same reasoning full_game.gd documents for
## spawning players: KickToKick sits at identity, so .position and
## .global_position agree, and the coach never exists at the origin for
## even one physics tick before landing where it belongs.
## X/Z only from centre() — its Y (0.5) is tuned for resting a ball
## there, not for a standing rig whose own origin already means "feet
## on the ground"; reusing it wholesale floated the coach half a metre up.
func _spawn_coach(stand_offset: Vector3, kind: CoachKind) -> CoachNPC:
	var coach := COACH_SCENE.instantiate()
	var stand := _field.centre()
	stand.y = 0.0
	coach.position = stand + stand_offset
	add_child(coach)
	coach.face_toward(_field.centre())
	coach.player_entered_range.connect(_on_coach_range_entered.bind(kind))
	coach.player_left_range.connect(_on_coach_range_left.bind(kind))
	return coach


func _coach_node(kind: CoachKind) -> CoachNPC:
	match kind:
		CoachKind.MARKING:
			return _marking_coach
		CoachKind.TACKLING:
			return _tackling_coach
		_:
			return _kicking_coach


func _on_coach_range_entered(player: PlayerController, kind: CoachKind) -> void:
	if _coach_state != CoachState.NONE or player != _player or player.is_carrying():
		return
	_coach_state = CoachState.PROMPT
	_active_coach = kind
	_set_hint_text(PROMPT_TEXT)


func _on_coach_range_left(_player_left: PlayerController, kind: CoachKind) -> void:
	if _coach_state == CoachState.PROMPT and _active_coach == kind:
		_coach_state = CoachState.NONE
		_set_hint_text("")


func _begin_dialogue() -> void:
	_coach_state = CoachState.DIALOGUE
	InputManager.gameplay_input_enabled = false
	var coach := _coach_node(_active_coach)
	coach.face_toward(_player.global_position)
	_camera.enter_dialogue(coach, _player)
	# The styled card replaces the old bracketed "< Y: Yes >" hint text.
	# confirm/decline routing is unchanged (see _unhandled_input).
	_set_hint_text("")
	_show_dialogue_card(_active_coach)


func _end_dialogue() -> void:
	_hide_dialogue_card()
	InputManager.gameplay_input_enabled = true
	_camera.exit_dialogue()
	# Still standing next to the coach after declining — re-offer the
	# prompt immediately rather than making them step out of range and
	# back in just to see it again.
	var coach := _coach_node(_active_coach)
	if is_instance_valid(coach) and coach.player_in_range() == _player:
		_coach_state = CoachState.PROMPT
		_set_hint_text(PROMPT_TEXT)
	else:
		_coach_state = CoachState.NONE
		_set_hint_text("")


func _accept_challenge() -> void:
	_coach_state = CoachState.CHALLENGE
	InputManager.gameplay_input_enabled = true
	_camera.exit_dialogue()
	_hide_dialogue_card()
	_set_hint_text("")
	# Coach interaction only ever triggers while not carrying (see
	# _on_coach_range_entered), so the player is guaranteed empty-handed
	# right here — nothing to kick unless a fresh ball is put in their
	# hands, same placement _reset_ball()'s safety net already uses.
	_reset_ball()
	match _active_coach:
		CoachKind.MARKING:
			_mark_challenge.begin(_ball, _player, _coach_node(CoachKind.MARKING).global_position)
		CoachKind.TACKLING:
			_tackle_tutorial.begin(_ball, _player, _rival)
		_:
			_challenge.begin(_ball, _pick_target_position())


func _pick_target_position() -> Vector3:
	var forward := -_player.global_transform.basis.z
	var candidate := _player.global_position + forward * Tuning.KICK_CHALLENGE_TARGET_DISTANCE
	candidate.y = 0.0
	if _field.is_inside_oval(candidate, 5.0):
		return candidate
	return _field.centre()


func _on_kick_challenge_ended(hits: int, attempts_total: int) -> void:
	_coach_state = CoachState.NONE
	_set_hint_text("Practice done — %d/%d on target. Walk back to the coach to go again."
		% [hits, attempts_total])


func _on_mark_challenge_ended(hits: int, attempts_total: int) -> void:
	_coach_state = CoachState.NONE
	_set_hint_text("Practice done — %d/%d marked. Walk back to the coach to go again."
		% [hits, attempts_total])


func _on_tackle_tutorial_ended(cleared: int, steps_total: int) -> void:
	_coach_state = CoachState.NONE
	_dismiss_tutorial_card()
	InputManager.gameplay_input_enabled = true
	_set_hint_text("Tackling tutorial done — %d/%d steps. Walk back to the coach to run it again."
		% [cleared, steps_total])


# ── Hint label ──────────────────────────────────────────────────────
# Plain text for the in-range prompt and drill/result messages. The coach
# conversation itself is the styled card below.

func _build_placeholder_prompt() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)

	var label := Label.new()
	label.name = "CoachPromptPlaceholder"
	label.anchor_left = 0.5
	label.anchor_right = 0.5
	label.anchor_top = 1.0
	label.anchor_bottom = 1.0
	label.offset_left = -420.0
	label.offset_right = 420.0
	label.offset_top = -170.0
	label.offset_bottom = -70.0
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override(&"font_size", 22)
	label.add_theme_color_override(&"font_color", Color.WHITE)
	label.add_theme_color_override(&"font_shadow_color", Color.BLACK)
	label.add_theme_constant_override(&"shadow_offset_x", 2)
	label.add_theme_constant_override(&"shadow_offset_y", 2)
	layer.add_child(label)
	_prompt_label = label


func _set_hint_text(text: String) -> void:
	if is_instance_valid(_prompt_label):
		_prompt_label.text = text


# ── Coach dialogue card ─────────────────────────────────────────────
# Bottom-centre card shown while talking to a coach. Same UIStyle look as
# the tackling tutorial card, but no full-screen dim: the dialogue camera
# already frames the coach, so the field stays visible behind it.

func _build_dialogue_card() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 6
	add_child(layer)

	var root := MarginContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_theme_constant_override(&"margin_bottom", 48)
	layer.add_child(root)

	var bottom := VBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_END
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bottom)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(560.0, 0.0)
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	panel.add_theme_stylebox_override(
		&"panel",
		UIStyle.rounded(Color(UIStyle.PANEL_FILL, 0.96), UIStyle.CHIP_BORDER, 2)
	)
	bottom.add_child(panel)

	var margin := MarginContainer.new()
	for side in [&"margin_left", &"margin_right"]:
		margin.add_theme_constant_override(side, 28)
	for side in [&"margin_top", &"margin_bottom"]:
		margin.add_theme_constant_override(side, 22)
	panel.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 10)
	margin.add_child(column)

	_dialogue_eyebrow = UIStyle.label(
		"",
		UIStyle.SIZE_HINT,
		UIStyle.TEXT_MUTED,
		UIStyle.WEIGHT_BOLD,
		UIStyle.TRACK_HINT
	)
	column.add_child(_dialogue_eyebrow)

	column.add_child(UIStyle.label(
		"Ready to train?",
		UIStyle.SIZE_TITLE,
		UIStyle.TEXT_PRIMARY,
		UIStyle.WEIGHT_HEAVY,
		UIStyle.TRACK_TITLE
	))

	_dialogue_body = UIStyle.label(
		"",
		UIStyle.SIZE_LABEL,
		UIStyle.TEXT_MUTED
	)
	_dialogue_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_dialogue_body)

	var rule := ColorRect.new()
	rule.color = UIStyle.CHIP_BORDER
	rule.custom_minimum_size = Vector2(0.0, 1.0)
	column.add_child(rule)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override(&"separation", 28)
	column.add_child(footer)

	footer.add_child(UIStyle.label(
		"Y / A   YES, LET'S GO",
		UIStyle.SIZE_HINT,
		UIStyle.TEXT_PRIMARY,
		UIStyle.WEIGHT_BOLD
	))
	footer.add_child(UIStyle.label(
		"N / B   NOT NOW",
		UIStyle.SIZE_HINT,
		UIStyle.TEXT_MUTED,
		UIStyle.WEIGHT_REGULAR
	))

	_dialogue_card = root
	_dialogue_card.visible = false


func _show_dialogue_card(kind: CoachKind) -> void:
	if not is_instance_valid(_dialogue_card):
		return
	var copy: Dictionary = COACH_COPY[kind]
	_dialogue_eyebrow.text = "TRAINING GROUND  /  %s" % copy["drill"]
	_dialogue_body.text = copy["body"]
	_dialogue_card.visible = true


func _hide_dialogue_card() -> void:
	if is_instance_valid(_dialogue_card):
		_dialogue_card.visible = false


# ── Tackling tutorial step card ─────────────────────────────────────
# Freeze-and-teach overlay: one control per step, shown for both schemes at
# once (keyboard/mouse AND controller), play frozen behind it. Built in code
# from the shared UIStyle/KeyHintBar helpers — same no-scene approach as
# _build_placeholder_prompt above, just a real styled panel rather than a
# bare Label since this one is the centre of attention.

func _build_tutorial_card() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 6
	add_child(layer)

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)

	# Dim the field without hiding the training environment.
	var dim := ColorRect.new()
	dim.color = Color(0.04, 0.04, 0.05, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)

	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(centre)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(660.0, 0.0)
	panel.add_theme_stylebox_override(
		&"panel",
		UIStyle.rounded(
			Color(UIStyle.PANEL_FILL, 0.99),
			UIStyle.CHIP_BORDER,
			2
		)
	)
	centre.add_child(panel)

	var margin := MarginContainer.new()
	for side in [&"margin_left", &"margin_right"]:
		margin.add_theme_constant_override(side, 32)
	for side in [&"margin_top", &"margin_bottom"]:
		margin.add_theme_constant_override(side, 28)
	panel.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 18)
	margin.add_child(column)

	# Small section label.
	var eyebrow := UIStyle.label(
		"TRAINING GROUND  /  TACKLING",
		UIStyle.SIZE_HINT,
		UIStyle.TEXT_MUTED,
		UIStyle.WEIGHT_BOLD,
		UIStyle.TRACK_HINT
	)
	column.add_child(eyebrow)

	# Main step title.
	_tutorial_card_title = UIStyle.label(
		"",
		UIStyle.SIZE_TITLE,
		UIStyle.TEXT_PRIMARY,
		UIStyle.WEIGHT_HEAVY,
		UIStyle.TRACK_TITLE
	)
	_tutorial_card_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_tutorial_card_title)

	# Clear separation between title and instruction.
	var rule := ColorRect.new()
	rule.color = UIStyle.CHIP_BORDER
	rule.custom_minimum_size = Vector2(0.0, 2.0)
	column.add_child(rule)

	_tutorial_card_body = UIStyle.label(
		"",
		UIStyle.SIZE_LABEL,
		UIStyle.TEXT_PRIMARY
	)
	_tutorial_card_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tutorial_card_body.custom_minimum_size = Vector2(580.0, 64.0)
	column.add_child(_tutorial_card_body)

	# Controls.
	var controls_label := UIStyle.label(
		"CONTROLS",
		UIStyle.SIZE_HINT,
		UIStyle.TEXT_MUTED,
		UIStyle.WEIGHT_BOLD,
		UIStyle.TRACK_HINT
	)
	column.add_child(controls_label)

	_tutorial_card_kb = _card_control_row(column, "KEYBOARD / MOUSE")
	_tutorial_card_pad = _card_control_row(column, "CONTROLLER")

	# Footer separated from the control instructions.
	var footer_rule := ColorRect.new()
	footer_rule.color = UIStyle.CHIP_BORDER
	footer_rule.custom_minimum_size = Vector2(0.0, 1.0)
	column.add_child(footer_rule)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override(&"separation", 24)
	column.add_child(footer)

	var start_hint := UIStyle.label(
		"A  Start rep",
		UIStyle.SIZE_HINT,
		UIStyle.TEXT_PRIMARY,
		UIStyle.WEIGHT_BOLD
	)
	footer.add_child(start_hint)

	var skip_hint := UIStyle.label(
		"B  Skip step",
		UIStyle.SIZE_HINT,
		UIStyle.TEXT_MUTED,
		UIStyle.WEIGHT_REGULAR
	)
	footer.add_child(skip_hint)

	_tutorial_card = root
	_tutorial_card.visible = false


## One labelled row of the card: a fixed-width caption ("Controller") next to
## a KeyHintBar the step fills with that scheme's chips.
func _card_control_row(parent: VBoxContainer, caption: String) -> KeyHintBar:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 18)
	parent.add_child(row)

	var caption_label := UIStyle.label(
		caption,
		UIStyle.SIZE_HINT,
		UIStyle.TEXT_MUTED,
		UIStyle.WEIGHT_BOLD,
		UIStyle.TRACK_HINT
	)
	caption_label.custom_minimum_size = Vector2(155.0, 42.0)
	caption_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	caption_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(caption_label)

	var bar := KeyHintBar.new()
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(bar)

	return bar


func _show_tutorial_card(step: Dictionary) -> void:
	if not is_instance_valid(_tutorial_card):
		return
	_tutorial_card_title.text = String(step.get("title", ""))
	_tutorial_card_body.text = String(step.get("instruction", ""))
	_tutorial_card_kb.set_hints(step.get("kb", []))
	_tutorial_card_pad.set_hints(step.get("pad", []))
	_tutorial_card.visible = true
	InputManager.gameplay_input_enabled = false


func _dismiss_tutorial_card() -> void:
	if is_instance_valid(_tutorial_card):
		_tutorial_card.visible = false
	InputManager.gameplay_input_enabled = true