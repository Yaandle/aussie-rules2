class_name CharacterScreen
extends CanvasLayer

## Attribute screen ported from Prototype 1's character_state.py /
## character_render.py (hotkey "C" from the main menu there too). P1 also
## had a named-player roster with disk persistence layered on the same
## screen; this port keeps the part that actually changes gameplay right
## now — the single live SPEED/HEIGHT draft (design doc's "APPLY TO ALL
## PLAYERS" default, see CharacterProfile) — and drops the roster, since
## there's nowhere yet that more than one saved profile would matter.
##
## Two adjustable stats (Speed, Height), six locked flavour rows kept for
## the same reason P1 kept them: a stat screen that only ever shows two
## live numbers doesn't read as a stat screen. A PLAY action row replaces
## P1's SAVE — confirming here launches kick_to_kick.tscn instead of
## writing to disk.

const ATTRIBUTE_ROWS := [
	{"key": "speed", "name": "SPEED"},
	{"key": null, "name": "JUMPING"},
	{"key": null, "name": "KICKING POWER"},
	{"key": null, "name": "KICKING ACCURACY"},
	{"key": null, "name": "STRENGTH"},
	{"key": "height", "name": "HEIGHT"},
	{"key": null, "name": "WEIGHT"},
	{"key": null, "name": "KICKING FOOT"},
]

const COLOUR_TITLE := "f4f1e0"
const COLOUR_SELECTED := "f4f1e0"
const COLOUR_NORMAL := "c9c9bd"
const COLOUR_LOCKED := "7a7a72"
const COLOUR_HINT := "9a9a90"
const COLOUR_GOLD := "e9c95e"

const BAR_SEGMENTS := 16

@onready var _label: RichTextLabel = $Label
@onready var _backdrop: CharacterBackdrop = $BackdropContainer/SubViewport/CharacterBackdrop

var _speed := Tuning.CHARACTER_SPEED_DEFAULT
var _height := Tuning.CHARACTER_HEIGHT_DEFAULT
var _selected := 0
var _busy := false   ## true while a wipe is in flight — input is inert


func _ready() -> void:
	_speed = CharacterProfile.speed
	_height = CharacterProfile.height
	_backdrop.set_height_scale(_height / Tuning.CHARACTER_HEIGHT_DEFAULT)
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if _busy:
		return
	if event.is_action_pressed(&"move_forward") or event.is_action_pressed(&"ui_up"):
		_move(-1)
	elif event.is_action_pressed(&"move_back") or event.is_action_pressed(&"ui_down"):
		_move(1)
	elif event.is_action_pressed(&"move_left") or event.is_action_pressed(&"ui_left"):
		_nudge(-1)
	elif event.is_action_pressed(&"move_right") or event.is_action_pressed(&"ui_right"):
		_nudge(1)
	elif event.is_action_pressed(&"ui_accept"):
		_activate()
	elif event.is_action_pressed(&"pause") or event.is_action_pressed(&"character_menu"):
		_exit_to_menu()


func _row_count() -> int:
	return ATTRIBUTE_ROWS.size() + 1   # + the PLAY action row


func _move(step: int) -> void:
	_selected = (_selected + step + _row_count()) % _row_count()
	_refresh()


func _nudge(direction: int) -> void:
	if _selected >= ATTRIBUTE_ROWS.size():
		return
	var row: Dictionary = ATTRIBUTE_ROWS[_selected]
	if row["key"] == "speed":
		_speed = clampf(_speed + direction * Tuning.CHARACTER_SPEED_STEP,
			Tuning.CHARACTER_SPEED_MIN, Tuning.CHARACTER_SPEED_MAX)
	elif row["key"] == "height":
		_height = clampf(_height + direction * Tuning.CHARACTER_HEIGHT_STEP,
			Tuning.CHARACTER_HEIGHT_MIN, Tuning.CHARACTER_HEIGHT_MAX)
		_backdrop.set_height_scale(_height / Tuning.CHARACTER_HEIGHT_DEFAULT)
	_refresh()


func _activate() -> void:
	if _selected == ATTRIBUTE_ROWS.size():
		_confirm_and_play()


func _confirm_and_play() -> void:
	if _busy:
		return
	_busy = true
	CharacterProfile.speed = _speed
	CharacterProfile.height = _height
	SceneWipe.change_scene("res://scenes/modes/kick_to_kick.tscn")


func _exit_to_menu() -> void:
	if _busy:
		return
	_busy = true
	SceneWipe.change_scene("res://scenes/ui/main_menu.tscn")


func _refresh() -> void:
	var lines: Array[String] = []
	lines.append("[color=#%s]CHARACTER[/color]" % COLOUR_TITLE)
	lines.append("[color=#%s]SPEED / HEIGHT ADJUSTABLE  ·  REST LOCKED[/color]" % COLOUR_HINT)
	lines.append("")
	for i in ATTRIBUTE_ROWS.size():
		lines.append(_stat_line(i))
	lines.append("")
	var action_selected := _selected == ATTRIBUTE_ROWS.size()
	var action_colour := COLOUR_SELECTED if action_selected else COLOUR_NORMAL
	lines.append("[color=#%s]%sPLAY — OPEN FIELD[/color]" % [
		action_colour, "> " if action_selected else "  "])
	lines.append("")
	lines.append("[color=#%s]W/S select   A/D adjust   Enter play   Esc/C back[/color]"
		% COLOUR_HINT)
	_label.text = "\n".join(lines)


func _stat_line(i: int) -> String:
	var row: Dictionary = ATTRIBUTE_ROWS[i]
	var selected := i == _selected
	var locked: bool = row["key"] == null
	var cursor := "> " if selected else "  "
	var colour := COLOUR_LOCKED if locked else (COLOUR_SELECTED if selected else COLOUR_NORMAL)
	var suffix := "  · LOCKED" if locked else ""
	var line := "[color=#%s]%s%s%s[/color]" % [colour, cursor, row["name"], suffix]
	if locked:
		return line
	var value: float = _speed if row["key"] == "speed" else _height
	var vmin: float = Tuning.CHARACTER_SPEED_MIN if row["key"] == "speed" \
		else Tuning.CHARACTER_HEIGHT_MIN
	var vmax: float = Tuning.CHARACTER_SPEED_MAX if row["key"] == "speed" \
		else Tuning.CHARACTER_HEIGHT_MAX
	var text := ("%.2f m/s" % value) if row["key"] == "speed" else ("%.0f cm" % value)
	var value_colour := COLOUR_GOLD if selected else COLOUR_NORMAL
	return "%s   [color=#%s]%s %s[/color]" % [line, value_colour, _bar(value, vmin, vmax), text]


func _bar(value: float, vmin: float, vmax: float) -> String:
	var frac := 0.0 if vmax <= vmin else (value - vmin) / (vmax - vmin)
	var filled := int(round(clampf(frac, 0.0, 1.0) * BAR_SEGMENTS))
	return "[%s%s]" % ["#".repeat(filled), "·".repeat(BAR_SEGMENTS - filled)]
