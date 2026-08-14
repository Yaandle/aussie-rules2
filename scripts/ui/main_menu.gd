class_name MainMenu
extends CanvasLayer

## Mode-select screen (design doc §7's front door).
##
## One reusable keyboard/gamepad-navigable list, matching Prototype 1's
## menu.py pattern: up/down moves a row index, Enter/accept selects, a
## locked row is shown muted with a " · LOCKED" suffix and Enter is a no-op
## on it. P1 kept exactly one such list component and had render.py mirror
## it for drawing; here there is only one place the rows are defined
## (_ENTRIES below) and the label draws directly from it, so there is
## nothing to keep in sync.

class Entry:
	var title: String
	var subtitle: String
	var scene_path: String
	var unlocked: bool

	func _init(p_title: String, p_subtitle: String, p_scene_path: String,
			p_unlocked: bool) -> void:
		title = p_title
		subtitle = p_subtitle
		scene_path = p_scene_path
		unlocked = p_unlocked


var _entries: Array[Entry] = [
	Entry.new("FULL GAME", "4-a-side, real clock, quarters, scoring",
		"res://scenes/modes/full_game.tscn", true),
	Entry.new("SCENARIO", "Practice a set situation", "", false),
	Entry.new("GOAL KICKING", "Shots on goal from the arc", "", false),
]

var _index := 0

const COLOUR_TITLE := "f4f1e0"
const COLOUR_SELECTED := "f4f1e0"
const COLOUR_NORMAL := "c9c9bd"
const COLOUR_LOCKED := "7a7a72"
const COLOUR_HINT := "9a9a90"

@onready var _label: RichTextLabel = $Label


func _ready() -> void:
	GameState.mode = GameState.Mode.SANDBOX
	GameState.phase = GameState.Phase.MENU
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"move_forward") or event.is_action_pressed(&"ui_up"):
		_move(-1)
	elif event.is_action_pressed(&"move_back") or event.is_action_pressed(&"ui_down"):
		_move(1)
	elif event.is_action_pressed(&"ui_accept"):
		_select()


func _move(step: int) -> void:
	_index = (_index + step + _entries.size()) % _entries.size()
	_refresh()


func _select() -> void:
	var entry := _entries[_index]
	if not entry.unlocked:
		return
	get_tree().change_scene_to_file(entry.scene_path)


func _refresh() -> void:
	var lines: Array[String] = []
	lines.append("[color=#%s]AUSSIE RULES 2[/color]" % COLOUR_TITLE)
	lines.append("")
	for i in _entries.size():
		var entry := _entries[i]
		var selected := i == _index
		var cursor := "> " if selected else "  "
		var suffix := "" if entry.unlocked else " · LOCKED"
		var colour := COLOUR_NORMAL if entry.unlocked else COLOUR_LOCKED
		if selected and entry.unlocked:
			colour = COLOUR_SELECTED
		lines.append("[color=#%s]%s%s%s[/color]" % [colour, cursor, entry.title, suffix])
		if selected:
			var subtitle := entry.subtitle if entry.unlocked else "Not built yet"
			lines.append("[color=#%s]    %s[/color]" % [COLOUR_HINT, subtitle])
	lines.append("")
	lines.append("[color=#%s]W/S or arrows to choose   Enter to select[/color]" % COLOUR_HINT)
	_label.text = "\n".join(lines)
