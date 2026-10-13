class_name CharacterScreen
extends Node

## Attribute screen ported from Prototype 1's character_state.py /
## character_render.py (hotkey "C" from the main menu there too). P1 also
## had a named-player roster with disk persistence layered on the same
## screen; this port keeps the live SPEED/AGILITY/KICKING POWER/KICKING
## ACCURACY/HEIGHT draft plus P1's APPLY TO ALL / one specific player
## toggle, and drops the roster list / naming screen / disk-vs-session
## prompt (the lean form — see CharacterProfile).
##
## Five adjustable stats, three locked flavour rows kept for the same
## reason P1 kept them: a stat screen that only ever shows a couple of
## live numbers doesn't read as a stat screen. Then an APPLY TO toggle row
## (ALL PLAYERS / START PLAYER — which HOME players Full Game applies the
## profile to) and a PLAY action row that replaces P1's SAVE: confirming
## commits the draft to CharacterProfile, persists it, and launches
## kick_to_kick.tscn.
##
## The whole left column is built here from ATTRIBUTE_ROWS rather than
## laid out in `character_screen.tscn`: eight instances of one row is
## data, and the .tscn holding eight hand-placed copies of it would have
## to be re-edited by hand every time a stat is added or a column moves.
## The .tscn is just the shell — 3D backdrop, scrim, and an empty Control
## to hang this on. Same reasoning as `field.gd` generating its markings
## and `player_animation.gd` assembling its graph in code.

## Row order and content. `key` is the CharacterProfile/_stat_config
## field, or null for a flavour row that is displayed but not adjustable.
## `bar` is false for a stat that has no scale to be part-way along.
const ATTRIBUTE_ROWS := [
	{"key": "speed", "icon": &"speed", "name": "SPEED"},
	{"key": null, "icon": &"jump", "name": "JUMPING"},
	{"key": "kick_power", "icon": &"kick", "name": "KICKING POWER"},
	{"key": "kick_accuracy", "icon": &"accuracy", "name": "KICKING ACCURACY"},
	{"key": "agility", "icon": &"agility", "name": "AGILITY"},
	{"key": "height", "icon": &"height", "name": "HEIGHT"},
	{"key": null, "icon": &"weight", "name": "WEIGHT"},
	{"key": null, "icon": &"foot", "name": "KICKING FOOT", "bar": false},
]

## Trailing interactive rows after the stat list, in order. The APPLY TO
## row cycles CharacterProfile.apply_all; PLAY commits + persists + launches.
const APPLY_MODE_TEXT := {true: "ALL PLAYERS", false: "START PLAYER"}

const TITLE := "PLAYER PROFILE"
const SUBTITLE := "CUSTOMISE YOUR CHARACTER"
const ACTION_TEXT := "PLAY — OPEN FIELD"

# ── Left column geometry, in design-resolution px (1280x720) ─────────
const LEFT_MARGIN := 58.0
const HEADER_TOP := 62.0
const STAT_TOP := 160.0
const ROW_SEPARATION := 8
const BUTTON_TOP := 613.0
const HINTS_TOP := 678.0


@onready var _ui: Control = $Overlay/UI
@onready var _backdrop: CharacterBackdrop = $CharacterBackdrop

## key -> {min, max, step, format}. Built in _ready() rather than as a
## script const so it can freely reference Tuning's constants without
## relying on cross-script const-folding.
var _stat_config := {}

## Control-legend text, keyed by InputManager.Device. Only the keyboard
## set is settled — the Xbox bindings are being defined separately, so
## the controller legend is one more entry in here and nothing else:
## `_apply_hints()` already runs on `device_changed`, and KeyHintBar takes
## whatever strings it is handed. Until that entry exists a plugged-in
## pad shows the keyboard legend, which is what every other screen in the
## project does today.
var _hint_sets := {}

var _draft := {}
var _rows: Array[StatRow] = []
var _apply_row: StatRow          ## APPLY TO toggle, at index _apply_index()
var _play: ActionButton
var _hints: KeyHintBar
var _selected := 0
var _busy := false   ## true while a wipe is in flight — input is inert


func _ready() -> void:
	_stat_config = {
		"speed": {"min": Tuning.CHARACTER_SPEED_MIN, "max": Tuning.CHARACTER_SPEED_MAX,
			"step": Tuning.CHARACTER_SPEED_STEP, "format": "%.2f m/s"},
		"height": {"min": Tuning.CHARACTER_HEIGHT_MIN, "max": Tuning.CHARACTER_HEIGHT_MAX,
			"step": Tuning.CHARACTER_HEIGHT_STEP, "format": "%.0f cm"},
		"kick_power": {"min": Tuning.CHARACTER_KICK_POWER_MIN, "max": Tuning.CHARACTER_KICK_POWER_MAX,
			"step": Tuning.CHARACTER_KICK_POWER_STEP, "format": "%.2fx"},
		"kick_accuracy": {"min": Tuning.CHARACTER_KICK_ACCURACY_MIN,
			"max": Tuning.CHARACTER_KICK_ACCURACY_MAX,
			"step": Tuning.CHARACTER_KICK_ACCURACY_STEP, "format": "%.0f%%"},
		"agility": {"min": Tuning.CHARACTER_AGILITY_MIN, "max": Tuning.CHARACTER_AGILITY_MAX,
			"step": Tuning.CHARACTER_AGILITY_STEP, "format": "%.2fx"},
	}
	_draft = {
		"speed": CharacterProfile.speed,
		"height": CharacterProfile.height,
		"kick_power": CharacterProfile.kick_power,
		"kick_accuracy": CharacterProfile.kick_accuracy,
		"agility": CharacterProfile.agility,
		"apply_all": CharacterProfile.apply_all,
	}
	_hint_sets = {
		InputManager.Device.KEYBOARD: [
			{"keys": "W / S", "label": "Select"},
			{"keys": "A / D", "label": "Adjust"},
			{"keys": "Enter", "label": "Play"},
			{"keys": "Esc / C", "label": "Back"},
		],
	}

	_build()
	InputManager.device_changed.connect(_on_device_changed)
	_backdrop.set_height_scale(_draft["height"] / Tuning.CHARACTER_HEIGHT_DEFAULT)
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
	elif event.is_action_pressed(&"ui_accept") or event.is_action_pressed(&"confirm"):
		_activate()
	elif event.is_action_pressed(&"pause") or event.is_action_pressed(&"character_menu"):
		_exit_to_menu()


## Index of the APPLY TO toggle row, then the PLAY row, in the up/down list
## that runs past the stat rows.
func _apply_index() -> int:
	return ATTRIBUTE_ROWS.size()


func _play_index() -> int:
	return ATTRIBUTE_ROWS.size() + 1


func _row_count() -> int:
	return ATTRIBUTE_ROWS.size() + 2   # + the APPLY TO toggle and the PLAY action row


func _move(step: int) -> void:
	_selected = (_selected + step + _row_count()) % _row_count()
	_refresh()


func _nudge(direction: int) -> void:
	if _selected == _apply_index():
		# Two-value toggle — either direction just flips it.
		_draft["apply_all"] = not _draft["apply_all"]
		_refresh()
		return
	if _selected >= ATTRIBUTE_ROWS.size():
		return
	var row: Dictionary = ATTRIBUTE_ROWS[_selected]
	var key = row["key"]
	if key == null:
		return
	var config: Dictionary = _stat_config[key]
	_draft[key] = clampf(_draft[key] + direction * float(config["step"]),
		float(config["min"]), float(config["max"]))
	if key == "height":
		_backdrop.set_height_scale(_draft["height"] / Tuning.CHARACTER_HEIGHT_DEFAULT)
	_refresh()


func _activate() -> void:
	if _selected == _apply_index():
		_draft["apply_all"] = not _draft["apply_all"]
		_refresh()
	elif _selected == _play_index():
		_confirm_and_play()


## Copy the whole draft onto CharacterProfile and persist it. Shared by
## PLAY and by backing out (the lean screen has no separate SAVE row, so
## an edit shouldn't be lost just because you left via Esc).
func _commit_draft() -> void:
	CharacterProfile.speed = _draft["speed"]
	CharacterProfile.height = _draft["height"]
	CharacterProfile.kick_power = _draft["kick_power"]
	CharacterProfile.kick_accuracy = _draft["kick_accuracy"]
	CharacterProfile.agility = _draft["agility"]
	CharacterProfile.apply_all = _draft["apply_all"]
	CharacterProfile.save()


func _confirm_and_play() -> void:
	if _busy:
		return
	_busy = true
	_commit_draft()
	SceneWipe.change_scene("res://scenes/modes/kick_to_kick.tscn")


func _exit_to_menu() -> void:
	if _busy:
		return
	_busy = true
	_commit_draft()
	SceneWipe.change_scene("res://scenes/ui/main_menu.tscn")


# ── Build ────────────────────────────────────────────────────────────

func _build() -> void:
	var header := VBoxContainer.new()
	header.position = Vector2(LEFT_MARGIN, HEADER_TOP)
	header.add_theme_constant_override(&"separation", 2)
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(UIStyle.label(TITLE, UIStyle.SIZE_TITLE, UIStyle.TEXT_PRIMARY,
		UIStyle.WEIGHT_HEAVY, UIStyle.TRACK_TITLE))
	header.add_child(UIStyle.label(SUBTITLE, UIStyle.SIZE_SUBTITLE, UIStyle.TEXT_MUTED,
		UIStyle.WEIGHT_REGULAR, UIStyle.TRACK_SUBTITLE))
	_ui.add_child(header)

	var list := VBoxContainer.new()
	list.position = Vector2(LEFT_MARGIN, STAT_TOP)
	list.add_theme_constant_override(&"separation", ROW_SEPARATION)
	list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(list)
	for entry: Dictionary in ATTRIBUTE_ROWS:
		var row := StatRow.new()
		list.add_child(row)
		row.configure(entry["icon"], entry["name"], entry["key"] == null,
			entry.get("bar", true))
		_rows.append(row)

	# APPLY TO toggle — a StatRow with no bar, its value column carrying the
	# mode text. Selectable and adjustable like a stat row, but flips a bool
	# instead of nudging a number (see _nudge/_activate).
	_apply_row = StatRow.new()
	list.add_child(_apply_row)
	_apply_row.configure(&"gear", "APPLY TO", false, false)

	_play = ActionButton.new(ACTION_TEXT)
	_play.mouse_filter = Control.MOUSE_FILTER_STOP
	_play.gui_input.connect(_on_play_gui_input)
	_play.position = Vector2(LEFT_MARGIN, BUTTON_TOP)
	_ui.add_child(_play)

	_hints = KeyHintBar.new()
	_hints.position = Vector2(LEFT_MARGIN, HINTS_TOP)
	_ui.add_child(_hints)
	_apply_hints()

func _on_play_gui_input(event: InputEvent) -> void:
	if _busy:
		return
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		_selected = _play_index()
		_confirm_and_play()


func _on_device_changed(_device: int) -> void:
	_apply_hints()


func _apply_hints() -> void:
	var keyboard: Array = _hint_sets[InputManager.Device.KEYBOARD]
	_hints.set_hints(_hint_sets.get(InputManager.device, keyboard))


# ── Refresh ──────────────────────────────────────────────────────────

func _refresh() -> void:
	for i in _rows.size():
		var entry: Dictionary = ATTRIBUTE_ROWS[i]
		_rows[i].set_state(i == _selected, _filled_segments(entry["key"]),
			_value_text(entry["key"]))
	_apply_row.set_state(_selected == _apply_index(), 0,
		APPLY_MODE_TEXT[_draft["apply_all"]])
	_play.set_selected(_selected == _play_index())


## Where the stat sits between its own min and max, quantised to the
## row's squares. A locked row has no backing stat yet, so it reads zero
## — the bar is not hidden and not faked, it just has nothing to show
## until something in CharacterProfile drives it.
func _filled_segments(key) -> int:
	if key == null:
		return 0
	var config: Dictionary = _stat_config[key]
	var vmin := float(config["min"])
	var vmax := float(config["max"])
	if vmax <= vmin:
		return 0
	var fraction := clampf((float(_draft[key]) - vmin) / (vmax - vmin), 0.0, 1.0)
	return int(round(fraction * StatRow.SEGMENTS))


## Empty for the locked rows: they have no assigned number, and a "—"
## placeholder would just be noise in a column that is otherwise all
## real readings.
func _value_text(key) -> String:
	if key == null:
		return ""
	var config: Dictionary = _stat_config[key]
	var value: float = _draft[key]
	# kick_accuracy is stored 0..1 and shown as a percentage; everything
	# else is already in its display unit.
	var display_value := value * 100.0 if key == "kick_accuracy" else value
	return (config["format"] as String) % display_value
