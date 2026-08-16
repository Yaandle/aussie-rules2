class_name AiTestScreen
extends CanvasLayer

## Config screen for the AI testing mode (scripts/modes/ai_test.gd):
## team size, which team/slot is human-controlled (or neither, for an
## AI-vs-AI spectator run), formation-start vs the kickoff spread, and
## per-team AI freeze — the levers that make this a testing mode rather
## than Full Game with extra menus.
##
## Same keyboard-list shape as main_menu.gd (up/down moves a row cursor,
## left/right adjusts the selected row's value, Enter on the last row
## launches) rather than character_screen.gd's StatRow/bar treatment —
## these are discrete settings, not scalar stats with a range worth
## drawing a bar for.

const ROW_COUNT := 7   # 6 settings + START
const START_ROW := 6

const COLOUR_TITLE := "f4f1e0"
const COLOUR_SELECTED := "e9c95e"
const COLOUR_NORMAL := "c9c9bd"
const COLOUR_HINT := "9a9a90"

@onready var _label: RichTextLabel = $Label

var _index := 0
var _busy := false


func _ready() -> void:
	AiTestConfig.team_size = clampi(AiTestConfig.team_size, AiTestConfig.MIN_TEAM_SIZE,
		AiTestConfig.MAX_TEAM_SIZE)
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if _busy:
		return
	if event.is_action_pressed(&"move_forward") or event.is_action_pressed(&"ui_up"):
		_move(-1)
	elif event.is_action_pressed(&"move_back") or event.is_action_pressed(&"ui_down"):
		_move(1)
	elif event.is_action_pressed(&"move_left") or event.is_action_pressed(&"ui_left"):
		_adjust(-1)
	elif event.is_action_pressed(&"move_right") or event.is_action_pressed(&"ui_right"):
		_adjust(1)
	elif event.is_action_pressed(&"ui_accept"):
		_activate()
	elif event.is_action_pressed(&"pause") or event.is_action_pressed(&"team_menu"):
		_exit_to_menu()


func _move(step: int) -> void:
	_index = (_index + step + ROW_COUNT) % ROW_COUNT
	_refresh()


func _adjust(direction: int) -> void:
	match _index:
		0:
			AiTestConfig.team_size += direction
		1:
			var next := int(AiTestConfig.controlled_team) + direction
			AiTestConfig.controlled_team = wrapi(next, 0, Tuning.Team.size())
		2:
			if AiTestConfig.controlled_team != Tuning.Team.NONE:
				AiTestConfig.controlled_index = wrapi(
					AiTestConfig.controlled_index + direction, 0, AiTestConfig.team_size)
		3:
			AiTestConfig.use_formation_start = not AiTestConfig.use_formation_start
		4:
			AiTestConfig.freeze_home = not AiTestConfig.freeze_home
		5:
			AiTestConfig.freeze_away = not AiTestConfig.freeze_away
	_refresh()


func _activate() -> void:
	if _index == START_ROW:
		_launch()


func _launch() -> void:
	if _busy:
		return
	_busy = true
	SceneWipe.change_scene("res://scenes/modes/ai_test.tscn")


func _exit_to_menu() -> void:
	if _busy:
		return
	_busy = true
	SceneWipe.change_scene("res://scenes/ui/main_menu.tscn")


func _refresh() -> void:
	var lines: Array[String] = []
	lines.append("[color=#%s]AI TEST MODE[/color]" % COLOUR_TITLE)
	lines.append("")
	_row(lines, 0, "TEAM SIZE", "%d a side" % AiTestConfig.team_size)
	_row(lines, 1, "CONTROLLED TEAM", _team_name(AiTestConfig.controlled_team))
	_row(lines, 2, "CONTROLLED SLOT", "—" if AiTestConfig.controlled_team == Tuning.Team.NONE
		else "#%d" % AiTestConfig.controlled_index)
	_row(lines, 3, "START POSITIONS",
		"FORMATION" if AiTestConfig.use_formation_start else "KICKOFF SPREAD")
	_row(lines, 4, "FREEZE HOME AI", "ON" if AiTestConfig.freeze_home else "OFF")
	_row(lines, 5, "FREEZE AWAY AI", "ON" if AiTestConfig.freeze_away else "OFF")
	lines.append("")
	var selected := _index == START_ROW
	var colour := COLOUR_SELECTED if selected else COLOUR_NORMAL
	var cursor := "> " if selected else "  "
	lines.append("[color=#%s]%sSTART[/color]" % [colour, cursor])
	lines.append("")
	lines.append("[color=#%s]W/S choose   A/D adjust   Enter start   Esc/T back[/color]"
		% COLOUR_HINT)
	_label.text = "\n".join(lines)


func _row(lines: Array[String], index: int, label_text: String, value_text: String) -> void:
	var selected := _index == index
	var colour := COLOUR_SELECTED if selected else COLOUR_NORMAL
	var cursor := "> " if selected else "  "
	lines.append("[color=#%s]%s%s: %s[/color]" % [colour, cursor, label_text, value_text])


func _team_name(team: Tuning.Team) -> String:
	match team:
		Tuning.Team.HOME:
			return "HOME"
		Tuning.Team.AWAY:
			return "AWAY"
		_:
			return "NONE (spectate)"
