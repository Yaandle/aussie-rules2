extends Node3D

## Solo free-roam practice (reached via the character screen's PLAY row):
## one player, one ball, the full field, no AI, no clock, no scoring —
## just movement and disposal with an unlimited ball reset. Functionally
## the milestone-1 sandbox (scripts/main.gd) with two differences: it's
## reachable from the menu/character-screen flow instead of being the
## boot scene, and it applies whatever SPEED/HEIGHT the character screen
## was left on (CharacterProfile) to the player it spawns.
##
## Also where the first training coach lives (design brief): walk up to
## the coach, X to talk, confirm to start a kick-at-the-target challenge.
## Kicking coach only for now, kick_to_kick only for now — a marking coach
## and a tackling coach are explicitly later work, and so is wiring any of
## this into Full Game. See docs/HANDOVER.md for the full writeup,
## including which pieces here are rough placeholders standing in for UI
## this agent doesn't own.

const BALL_RESET_AHEAD := 3.0
const BALL_LOST_BELOW := -5.0

const COACH_SCENE := preload("res://scenes/mechanics/coach_npc.tscn")
const KICK_CHALLENGE_SCENE := preload("res://scenes/mechanics/kick_challenge.tscn")

enum CoachState { NONE, PROMPT, DIALOGUE, CHALLENGE }

@onready var _field: Field = $Field
@onready var _ball: Ball = $Ball
@onready var _player: PlayerController = $Player
@onready var _camera: BroadcastCamera = $BroadcastCamera
@onready var _hud: DebugHud = $DebugHud

var _coach: CoachNPC
var _challenge: KickChallenge
var _coach_state := CoachState.NONE

## PLACEHOLDER: a bare Label standing in for the real coach dialogue
## bubble / hint UI (design brief describes a proper chat bubble; UI is
## out of scope for this agent — see docs/HANDOVER.md). Built in code
## rather than a scene so it's trivially deleted once the real thing
## lands; nothing else in this file depends on its styling.
var _prompt_label: Label


func _ready() -> void:
	GameState.mode = GameState.Mode.KICK_TO_KICK
	GameState.phase = GameState.Phase.PLAY

	_player.speed_scale = CharacterProfile.speed_scale()
	_player.kick_power_scale = CharacterProfile.kick_power
	_player.kick_accuracy = CharacterProfile.kick_accuracy
	(_player.get_node("Rig") as Node3D).scale = Vector3.ONE * CharacterProfile.height_scale()

	_camera.target = _player
	_camera.ball = _ball
	_camera.recenter()
	_player.camera = _camera.camera()

	_hud.player = _player
	_hud.ball = _ball

	_player.ball_disposed.connect(_on_ball_disposed)

	_ball.reset_at(_field.centre())
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	_setup_coach()
	_build_placeholder_prompt()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"pause"):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		SceneWipe.change_scene("res://scenes/ui/main_menu.tscn")
		return
	if event.is_action_pressed(&"debug_reset"):
		_reset_ball()
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


func _physics_process(_delta: float) -> void:
	# Safety net, same as the sandbox's — the ball is a real rigid body,
	# so it can genuinely be lost off the map.
	var where := _ball.global_position
	if where.y < BALL_LOST_BELOW \
			or absf(where.x) > Tuning.FIELD_HALF_LENGTH + Field.SURROUND_MARGIN \
			or absf(where.z) > Tuning.FIELD_HALF_WIDTH + Field.SURROUND_MARGIN:
		_reset_ball()

	# CoachNPC only reports enter/exit edges, so a player who walked up
	# already carrying the ball (prompt correctly withheld — see
	# _on_coach_range_entered) and then dropped/disposed it while still
	# standing there needs a live re-check, not just the one-shot signal.
	if _coach_state == CoachState.NONE and is_instance_valid(_coach) \
			and _coach.player_in_range() == _player and not _player.is_carrying():
		_coach_state = CoachState.PROMPT
		_set_hint_text("Press X to talk to the coach")


func _reset_ball() -> void:
	if is_instance_valid(_challenge):
		_challenge.force_miss()
	_player.drop_ball()
	var ahead := -_player.global_transform.basis.z * BALL_RESET_AHEAD
	_ball.reset_at(_player.global_position + ahead + Vector3.UP * 0.3)


func _on_ball_disposed(action: Tuning.Action) -> void:
	if action == Tuning.Action.KICK:
		_camera.punch(Tuning.CAM_PUNCH_KICK)
	if is_instance_valid(_challenge):
		_challenge.notify_disposed(action)


# ── Training coach ───────────────────────────────────────────────────

func _setup_coach() -> void:
	_coach = COACH_SCENE.instantiate()
	# Position before add_child(), same reasoning full_game.gd documents for
	# spawning players: KickToKick sits at identity, so .position and
	# .global_position agree, and the coach never exists at the origin for
	# even one physics tick before landing where it belongs.
	_coach.position = _field.centre() + Tuning.COACH_STAND_OFFSET
	add_child(_coach)
	_coach.face_toward(_field.centre())
	_coach.player_entered_range.connect(_on_coach_range_entered)
	_coach.player_left_range.connect(_on_coach_range_left)

	_challenge = KICK_CHALLENGE_SCENE.instantiate()
	add_child(_challenge)
	_challenge.challenge_ended.connect(_on_challenge_ended)
	_challenge.hint_changed.connect(_set_hint_text)


func _on_coach_range_entered(player: PlayerController) -> void:
	if _coach_state != CoachState.NONE or player != _player or player.is_carrying():
		return
	_coach_state = CoachState.PROMPT
	_set_hint_text("Press X to talk to the coach")


func _on_coach_range_left(_player_left: PlayerController) -> void:
	if _coach_state == CoachState.PROMPT:
		_coach_state = CoachState.NONE
		_set_hint_text("")


func _begin_dialogue() -> void:
	_coach_state = CoachState.DIALOGUE
	InputManager.gameplay_input_enabled = false
	_coach.face_toward(_player.global_position)
	_camera.enter_dialogue(_coach, _player)
	_set_hint_text("Coach: \"Want to practice your kicking?\"   Y: Yes   N: No")


func _end_dialogue() -> void:
	InputManager.gameplay_input_enabled = true
	_camera.exit_dialogue()
	# Still standing next to the coach after declining — re-offer the
	# prompt immediately rather than making them step out of range and
	# back in just to see it again.
	if is_instance_valid(_coach) and _coach.player_in_range() == _player:
		_coach_state = CoachState.PROMPT
		_set_hint_text("Press X to talk to the coach")
	else:
		_coach_state = CoachState.NONE
		_set_hint_text("")


func _accept_challenge() -> void:
	_coach_state = CoachState.CHALLENGE
	InputManager.gameplay_input_enabled = true
	_camera.exit_dialogue()
	_challenge.begin(_ball, _pick_target_position())


func _pick_target_position() -> Vector3:
	var forward := -_player.global_transform.basis.z
	var candidate := _player.global_position + forward * Tuning.KICK_CHALLENGE_TARGET_DISTANCE
	candidate.y = 0.0
	if _field.is_inside_oval(candidate, 5.0):
		return candidate
	return _field.centre()


func _on_challenge_ended(hits: int, attempts_total: int) -> void:
	_coach_state = CoachState.NONE
	_set_hint_text("Practice done — %d/%d on target. Walk back to the coach to go again."
		% [hits, attempts_total])


# ── Placeholder prompt/hint UI ──────────────────────────────────────
# Stands in for the real chat-bubble UI (design brief) until the UI agent
# builds it — plain text, no styling, deliberately disposable.

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
