class_name CareerCharacterScreen
extends Node

## Career mode's character creation screen — reached from the main menu's
## CAREER card. Visually the same "retro windowed console" shell as
## character_screen.gd (reuses CharacterBackdrop/RetroWindow/StatRow/
## ActionButton/KeyHintBar/UIStyle directly, no duplication of those), but
## its own script/scene: the draft here binds to CareerProfile instead of
## CharacterProfile, and the row list is different — NAME/POSITION/NUMBER/
## FOOT ahead of the attribute rows.
##
## CONFIRM writes the draft to CareerProfile and calls its start_career()
## (an 18-player roster with this character spliced into their POSITION's
## slot, a 12-round season, persisted), then launches the Career
## Dashboard. There is no Customise panel here (model/kit colours) yet —
## CareerProfile carries those fields for when that's added.
##
## Attributes move one square at a time: CareerProfile stores them as
## levels (one per StatRow square), not free floats. HEIGHT isn't
## adjustable — it follows POSITION (CareerProfile.height_for_role()).

## `kind` picks how _nudge()/_activate()/_row_value_text() treat the row:
## "text" (NAME, edited via a hidden LineEdit — see _build_name_edit),
## "role" (cycles TeamFormation.Role), "int" (NUMBER, ±1 clamped 1..99),
## "foot" (two-value LEFT/RIGHT toggle), "stat" (±1 level of a
## CareerProfile attribute), "height" (read-only, follows POSITION).
const CAREER_ROWS := [
	{"key": "player_name", "icon": &"figure", "name": "NAME", "kind": "text", "bar": false},
	{"key": "position", "icon": &"gear", "name": "POSITION", "kind": "role", "bar": false},
	{"key": "number", "icon": &"gear", "name": "NUMBER", "kind": "int", "bar": false},
	{"key": "foot", "icon": &"foot", "name": "FOOT", "kind": "foot", "bar": false},
	{"key": "speed", "icon": &"speed", "name": "SPEED", "kind": "stat"},
	{"key": "kick_power", "icon": &"kick", "name": "KICKING POWER", "kind": "stat"},
	{"key": "kick_accuracy", "icon": &"accuracy", "name": "KICKING ACCURACY", "kind": "stat"},
	{"key": "agility", "icon": &"agility", "name": "AGILITY", "kind": "stat"},
	{"key": "height", "icon": &"height", "name": "HEIGHT", "kind": "height"},
]

const TITLE := "CREATE YOUR PLAYER"
const SUBTITLE := "JUNIORS U18s CAREER"
const ACTION_TEXT := "CONFIRM — START CAREER"
const DEFAULT_NAME := "PLAYER"
const NAME_MAX_LENGTH := 20

# ── Left column geometry, in design-resolution px (1280x720) ─────────
# Same derivation as character_screen.gd's own CARD_* consts, just with
# BUTTON_TOP pushed down to clear nine rows instead of eight-plus-APPLY.
const LEFT_MARGIN := 58.0
const HEADER_TOP := 62.0
const STAT_TOP := 160.0
const ROW_SEPARATION := 8
const BUTTON_TOP := 600.0

const CARD_PAD := 24.0
const CARD_LEFT := LEFT_MARGIN - CARD_PAD
const CARD_TOP := HEADER_TOP - CARD_PAD
## Includes the selected row's right-hand nudge arrow, which StatRow
## draws past its own WIDTH (ARROW_RIGHT_X) — without it the arrow sat on
## the card's 4px border.
const CARD_WIDTH := StatRow.WIDTH + StatRow.ARROW_GAP + StatRow.ARROW_SIZE + CARD_PAD * 2.0
const CARD_HEIGHT := BUTTON_TOP + ActionButton.HEIGHT - CARD_TOP + CARD_PAD

const HINTS_TOP := CARD_TOP + CARD_HEIGHT + RetroWindow.SHADOW_OFFSET.y + 6.0


@onready var _ui: Control = $Overlay/UI
@onready var _backdrop: CharacterBackdrop = $CharacterBackdrop

var _stat_formats := {}
var _draft := {}
var _rows: Array[StatRow] = []
var _play: ActionButton
var _hints: DeviceHintBar
var _name_edit: LineEdit
var _selected := 0
var _busy := false   ## true while a wipe is in flight — input is inert
var _editing_name := false   ## true while _name_edit holds keyboard focus


func _ready() -> void:
	_stat_formats = {
		"speed": "%.2f m/s",
		"kick_power": "%.2fx",
		"kick_accuracy": "%.0f%%",
		"agility": "%.2fx",
	}
	# Stat rows hold levels in the draft, not values.
	_draft = {
		"player_name": CareerProfile.player_name,
		"position": int(CareerProfile.position),
		"number": CareerProfile.number,
		"foot": CareerProfile.foot,
	}
	for key: String in CareerProfile.ATTRIBUTE_RANGES:
		_draft[key] = CareerProfile.level(key)
	_build()
	_sync_backdrop_height()
	_backdrop.set_model(CareerProfile.model_id)
	_backdrop.set_kit_colors(_resolved_hex(CareerProfile.skin_color),
		_resolved_hex(CareerProfile.jersey_color), _resolved_hex(CareerProfile.shorts_color),
		_resolved_hex(CareerProfile.boot_color), _resolved_hex(CareerProfile.socks_color))
	_refresh()


func _draft_height() -> float:
	return CareerProfile.height_for_role(_draft["position"])


func _sync_backdrop_height() -> void:
	_backdrop.set_height_scale(_draft_height() / Tuning.CHARACTER_HEIGHT_DEFAULT)


func _resolved_hex(hex: String) -> Color:
	return Color(hex) if not hex.is_empty() else Color(0.0, 0.0, 0.0, 0.0)


func _unhandled_input(event: InputEvent) -> void:
	if _busy or _editing_name:
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
	elif event.is_action_pressed(&"pause") or event.is_action_pressed(&"character_menu") \
			or event.is_action_pressed(&"decline"):
		_exit_to_menu()


func _confirm_index() -> int:
	return CAREER_ROWS.size()


func _row_count() -> int:
	return CAREER_ROWS.size() + 1   # + the CONFIRM action row


func _move(step: int) -> void:
	_selected = (_selected + step + _row_count()) % _row_count()
	_refresh()


func _nudge(direction: int) -> void:
	if _selected >= CAREER_ROWS.size():
		return
	var row: Dictionary = CAREER_ROWS[_selected]
	match row.get("kind", "stat"):
		"text":
			pass   # edited via Enter (_activate), not A/D
		"role":
			var count: int = TeamFormation.Role.size()
			_draft["position"] = (_draft["position"] + direction + count) % count
			_sync_backdrop_height()   # HEIGHT follows POSITION
			_refresh()
		"int":
			_draft["number"] = clampi(_draft["number"] + direction, 1, 99)
			_refresh()
		"foot":
			_draft["foot"] = CareerProfile.FOOT_LEFT if _draft["foot"] == CareerProfile.FOOT_RIGHT \
				else CareerProfile.FOOT_RIGHT
			_refresh()
		"stat":
			var key: String = row["key"]
			_draft[key] = clampi(_draft[key] + direction, 0, Tuning.CAREER_ATTRIBUTE_LEVELS)
			_refresh()


func _activate() -> void:
	if _selected == _confirm_index():
		_confirm_and_create()
		return
	var row: Dictionary = CAREER_ROWS[_selected]
	if row.get("kind", "stat") == "text":
		_name_edit.grab_focus()


## Writes the draft to CareerProfile, starts the career (roster, season,
## save — see CareerProfile.start_career()), and launches the Dashboard.
## An empty NAME falls back to DEFAULT_NAME rather than blocking — no
## validation-dialog machinery exists on this screen, and a lean fallback
## beats building one just for this.
func _confirm_and_create() -> void:
	if _busy:
		return
	_busy = true

	var player_name: String = _draft["player_name"]
	if player_name.strip_edges().is_empty():
		player_name = DEFAULT_NAME

	CareerProfile.player_name = player_name
	CareerProfile.position = _draft["position"]
	CareerProfile.number = _draft["number"]
	CareerProfile.foot = _draft["foot"]
	for key: String in CareerProfile.ATTRIBUTE_RANGES:
		CareerProfile.set_level(key, _draft[key])
	CareerProfile.start_career()

	SceneWipe.change_scene("res://scenes/ui/career_dashboard_screen.tscn")


## Back to the Dashboard when a career is already in progress (you came
## here from its New Career, and backing out keeps that career), else the
## main menu.
func _exit_to_menu() -> void:
	if _busy:
		return
	_busy = true
	SceneWipe.change_scene("res://scenes/ui/career_dashboard_screen.tscn" if CareerProfile.has_career()
		else "res://scenes/ui/main_menu.tscn")


# ── Build ────────────────────────────────────────────────────────────

func _build() -> void:
	var card_panel := RetroWindow.shell(_ui, Vector2(CARD_WIDTH, CARD_HEIGHT))
	(card_panel.get_parent() as Control).position = Vector2(CARD_LEFT, CARD_TOP)

	var header := VBoxContainer.new()
	header.position = Vector2(CARD_PAD, CARD_PAD)
	header.add_theme_constant_override(&"separation", 2)
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(UIStyle.label(TITLE, UIStyle.SIZE_TITLE, UIStyle.TEXT_PRIMARY,
		UIStyle.WEIGHT_HEAVY, UIStyle.TRACK_TITLE))

	var underline := Panel.new()
	underline.custom_minimum_size = Vector2(56.0, 4.0)
	underline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var underline_style := StyleBoxFlat.new()
	underline_style.bg_color = RetroWindow.ACCENT
	underline.add_theme_stylebox_override(&"panel", underline_style)
	header.add_child(underline)

	header.add_child(UIStyle.label(SUBTITLE, UIStyle.SIZE_SUBTITLE, UIStyle.TEXT_MUTED,
		UIStyle.WEIGHT_REGULAR, UIStyle.TRACK_SUBTITLE))
	card_panel.add_child(header)

	var list := VBoxContainer.new()
	list.position = Vector2(CARD_PAD, STAT_TOP - CARD_TOP)
	list.add_theme_constant_override(&"separation", ROW_SEPARATION)
	list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card_panel.add_child(list)
	for entry: Dictionary in CAREER_ROWS:
		var row := StatRow.new()
		list.add_child(row)
		# NAME is edited via Enter (grabs _name_edit), not A/D, and HEIGHT
		# follows POSITION — the arrow cue would say "left/right changes
		# this" for a row that A/D does nothing on, so those two are
		# configured non-adjustable.
		var adjustable: bool = not (entry.get("kind", "stat") in ["text", "height"])
		row.configure(entry["icon"], entry["name"], false, entry.get("bar", true), adjustable)
		_rows.append(row)

	_play = ActionButton.new(ACTION_TEXT)
	_play.mouse_filter = Control.MOUSE_FILTER_STOP
	_play.gui_input.connect(_on_play_gui_input)
	_play.position = Vector2(CARD_PAD, BUTTON_TOP - CARD_TOP)
	card_panel.add_child(_play)

	_hints = DeviceHintBar.new()
	_hints.position = Vector2(LEFT_MARGIN, HINTS_TOP)
	_ui.add_child(_hints)
	_hints.set_hint_sets({
		InputManager.Device.KEYBOARD: [
			{"keys": "W / S", "label": "Select"},
			{"keys": "A / D", "label": "Adjust"},
			{"keys": "Enter", "label": "Edit / Confirm"},
			{"keys": "B / Esc", "label": "Back"},
		],
		InputManager.Device.GAMEPAD: [
			{"keys": "D-Pad ↕", "label": "Select"},
			{"keys": "D-Pad ↔", "label": "Adjust"},
			{"keys": "A", "label": "Confirm"},
			{"keys": "B", "label": "Back"},
		],
	})

	_build_name_edit()


## A LineEdit that's never actually seen — invisible (alpha 0) and
## MOUSE_FILTER_IGNORE, so it's never a click target, but it can still be
## grab_focus()'d programmatically from _activate() to capture real text
## input while the NAME row is selected. The NAME StatRow's own value
## column shows the live text instead (see _row_value_text), so there's
## no second visible text box to keep aligned with the row underneath it.
func _build_name_edit() -> void:
	_name_edit = LineEdit.new()
	_name_edit.text = _draft["player_name"]
	_name_edit.max_length = NAME_MAX_LENGTH
	_name_edit.modulate = Color(1.0, 1.0, 1.0, 0.0)
	_name_edit.size = Vector2(1.0, 1.0)
	_name_edit.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name_edit.text_changed.connect(_on_name_text_changed)
	_name_edit.text_submitted.connect(_on_name_text_submitted)
	_name_edit.focus_entered.connect(func() -> void: _editing_name = true)
	_name_edit.focus_exited.connect(func() -> void: _editing_name = false)
	_ui.add_child(_name_edit)


func _on_name_text_changed(new_text: String) -> void:
	_draft["player_name"] = new_text
	_refresh()


func _on_name_text_submitted(_new_text: String) -> void:
	_name_edit.release_focus()


func _on_play_gui_input(event: InputEvent) -> void:
	if _busy:
		return
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		_selected = _confirm_index()
		_confirm_and_create()


# ── Refresh ──────────────────────────────────────────────────────────

func _refresh() -> void:
	for i in CAREER_ROWS.size():
		var entry: Dictionary = CAREER_ROWS[i]
		_rows[i].set_state(i == _selected, _filled_segments(entry), _row_value_text(entry))
	_play.set_selected(_selected == _confirm_index())


func _filled_segments(entry: Dictionary) -> int:
	match entry.get("kind", "stat"):
		"stat":
			return _draft[entry["key"]]
		"height":
			var fraction := inverse_lerp(Tuning.CHARACTER_HEIGHT_MIN, Tuning.CHARACTER_HEIGHT_MAX,
				_draft_height())
			return roundi(clampf(fraction, 0.0, 1.0) * StatRow.SEGMENTS)
	return 0


func _row_value_text(entry: Dictionary) -> String:
	var key: String = entry["key"]
	match entry.get("kind", "stat"):
		"text":
			var text: String = _draft[key]
			return text if not text.is_empty() else "—"
		"role":
			var role_name: String = TeamFormation.Role.keys()[_draft[key]]
			return role_name.replace("_", " ")
		"int":
			return "#%d" % _draft[key]
		"foot":
			return _draft[key]
		"height":
			return "%.0f cm" % _draft_height()
		_:
			var value := CareerProfile.level_value(key, _draft[key])
			var display_value := value * 100.0 if key == "kick_accuracy" else value
			return (_stat_formats[key] as String) % display_value
