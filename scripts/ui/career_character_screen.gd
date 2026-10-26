class_name CareerCharacterScreen
extends Node

## Career mode's character creation screen — reached from the main menu's
## CAREER card when there's no career yet, and from the Dashboard's New
## Career. Visually the same "retro windowed console" shell as
## character_screen.gd (reuses CharacterBackdrop/RetroWindow/StatRow/
## ActionButton/UIStyle directly, no duplication of those), but its own
## script/scene: the draft here binds to CareerProfile instead of
## CharacterProfile.
##
## docs/CAREER_AUDIT.md Phase 6 (playtest brief): the card asks only for
## NAME, POSITION, NUMBER and FOOT — no attribute rows, because attributes
## are earned now — then a divider and CAREER SETTINGS: DIFFICULTY, Easy
## or Hard, which sets where every attribute starts (CareerProfile.
## start_level(): one square on Easy, none on Hard) and is fixed for the
## career. HEIGHT follows POSITION (CareerProfile.height_for_role()), so the
## preview resizes as you pick one.
##
## CUSTOMISE PLAYER floats under the player, as CUSTOMISE does on the
## CHARACTER screen (C): Y / Tab or a click swaps the card's rows for that
## screen's own CUSTOMISE_ROWS (model and kit colours, from its SWATCHES)
## and eases the camera in; B or the button again comes back. The kit is
## Career's own (CareerProfile's colour fields), which TeamKit already uses
## in Career matches.
##
## The player stands in the middle of the right third of the screen on
## Field 2, the bush oval (CharacterBackdrop.subject_screen_x and
## dress_field_2, set on this scene's backdrop instance).
##
## CONFIRM writes the draft to CareerProfile and calls its start_career()
## (start levels, an 18-player roster with this character spliced into
## their POSITION's slot, a 12-round season, persisted), then launches the
## Career Dashboard.

## `kind` picks how _nudge()/_activate()/_row_value_text() treat the row:
## "text" (NAME, edited via a hidden LineEdit — see _build_name_edit),
## "role" (cycles TeamFormation.Role), "int" (NUMBER, ±1 clamped 1..99),
## "foot" (two-value LEFT/RIGHT toggle). The Customise panel's rows are
## CharacterScreen.CUSTOMISE_ROWS ("model" and "swatch" kinds).
const CAREER_ROWS := [
	{"key": "player_name", "icon": &"figure", "name": "NAME", "kind": "text", "bar": false},
	{"key": "position", "icon": &"gear", "name": "POSITION", "kind": "role", "bar": false},
	{"key": "number", "icon": &"gear", "name": "NUMBER", "kind": "int", "bar": false},
	{"key": "foot", "icon": &"foot", "name": "FOOT", "kind": "foot", "bar": false},
]

const TITLE := "CREATE YOUR PLAYER"
const SUBTITLE := "JUNIORS U18s CAREER"
const ACTION_TEXT := "CONFIRM — START CAREER"
const SETTINGS_TITLE := "CAREER SETTINGS"
const CUSTOMISE_TEXT := "CUSTOMISE PLAYER"
const BACK_TEXT := "BACK"
const DEFAULT_NAME := "PLAYER"
const NAME_MAX_LENGTH := 20

# ── Left column geometry, in design-resolution px (1280x720) ─────────
# Same derivation as character_screen.gd's own CARD_* consts: four rows,
# then the CAREER SETTINGS block, then the button.
const LEFT_MARGIN := 58.0
const HEADER_TOP := 62.0
const STAT_TOP := 160.0
const ROW_SEPARATION := 8
const ROW_PITCH := StatRow.HEIGHT + ROW_SEPARATION
const SETTINGS_TOP := STAT_TOP + ROW_PITCH * 4.0 + 8.0
const BUTTON_TOP := SETTINGS_TOP + 140.0

const CARD_PAD := 24.0
const CARD_LEFT := LEFT_MARGIN - CARD_PAD
const CARD_TOP := HEADER_TOP - CARD_PAD
## Includes the selected row's right-hand nudge arrow, which StatRow
## draws past its own WIDTH (ARROW_RIGHT_X) — without it the arrow sat on
## the card's 4px border.
const CARD_WIDTH := StatRow.WIDTH + StatRow.ARROW_GAP + StatRow.ARROW_SIZE + CARD_PAD * 2.0
const CARD_HEIGHT := BUTTON_TOP + ActionButton.HEIGHT - CARD_TOP + CARD_PAD

const HINTS_TOP := CARD_TOP + CARD_HEIGHT + RetroWindow.SHADOW_OFFSET.y + 6.0

## Under the player: the middle of the right third (the backdrop's
## subject_screen_x), low enough to clear the Customise zoom's shoes.
const CUSTOMISE_CENTRE := Vector2(1280.0 * 0.833, 664.0)


@onready var _ui: Control = $Overlay/UI
@onready var _backdrop: CharacterBackdrop = $CharacterBackdrop

var _draft := {}
var _model_ids: Array[String] = ["procedural"]
var _rows: Array[StatRow] = []   ## pool, sized for the longer of the two row lists
var _settings_block: Control
var _difficulty_row: StatRow
var _difficulty_caption: Label
var _play: ActionButton
var _customise_button: ActionButton
var _hints: DeviceHintBar
var _name_edit: LineEdit
var _selected := 0
var _customising := false
var _busy := false   ## true while a wipe is in flight — input is inert
var _editing_name := false   ## true while _name_edit holds keyboard focus


func _ready() -> void:
	_model_ids.append_array(HumanoidRig.CHARACTER_MODELS.keys())
	_draft = {
		"player_name": CareerProfile.player_name,
		"position": int(CareerProfile.position),
		"number": CareerProfile.number,
		"foot": CareerProfile.foot,
		"difficulty": CareerProfile.difficulty,
		"model_id": CareerProfile.model_id,
		"skin_color": CareerProfile.skin_color,
		"jersey_color": CareerProfile.jersey_color,
		"shorts_color": CareerProfile.shorts_color,
		"boot_color": CareerProfile.boot_color,
		"socks_color": CareerProfile.socks_color,
	}
	_build()
	_sync_backdrop_height()
	_backdrop.set_model(_draft["model_id"])
	_apply_kit_preview()
	_apply_row_mode()
	_refresh()


func _draft_height() -> float:
	return CareerProfile.height_for_role(_draft["position"])


func _sync_backdrop_height() -> void:
	_backdrop.set_height_scale(_draft_height() / Tuning.CHARACTER_HEIGHT_DEFAULT)


func _unhandled_input(event: InputEvent) -> void:
	if _busy or _editing_name:
		return
	if _is_customise_press(event):
		_toggle_customise()
	elif _customising and event.is_action_pressed(&"decline"):
		_toggle_customise()
	elif event.is_action_pressed(&"move_forward") or event.is_action_pressed(&"ui_up"):
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


## Y on a pad, Tab on a keyboard — the CHARACTER screen's own Customise
## keys, read raw for the same reason it gives (character_screen.gd).
func _is_customise_press(event: InputEvent) -> bool:
	if event is InputEventJoypadButton:
		return event.is_pressed() and (event as InputEventJoypadButton).button_index == JOY_BUTTON_Y
	if event is InputEventKey:
		var key := event as InputEventKey
		return key.is_pressed() and not key.echo and key.physical_keycode == KEY_TAB
	return false


# ── Cursor ───────────────────────────────────────────────────────────

func _active_rows() -> Array:
	return CharacterScreen.CUSTOMISE_ROWS if _customising else CAREER_ROWS


## The DIFFICULTY row's place in the cursor order, -1 while customising
## (the CAREER SETTINGS block is hidden then).
func _difficulty_index() -> int:
	return -1 if _customising else CAREER_ROWS.size()


func _confirm_index() -> int:
	return _active_rows().size() + (0 if _customising else 1)


func _row_count() -> int:
	return _confirm_index() + 1


func _move(step: int) -> void:
	_selected = (_selected + step + _row_count()) % _row_count()
	_refresh()


func _nudge(direction: int) -> void:
	if _selected == _difficulty_index():
		_draft["difficulty"] = CareerProfile.DIFFICULTY_HARD \
			if _draft["difficulty"] == CareerProfile.DIFFICULTY_EASY else CareerProfile.DIFFICULTY_EASY
		_refresh()
		return
	var rows := _active_rows()
	if _selected >= rows.size():
		return
	var row: Dictionary = rows[_selected]
	match row.get("kind", ""):
		"role":
			var count: int = TeamFormation.Role.size()
			_draft["position"] = (_draft["position"] + direction + count) % count
			_sync_backdrop_height()   # HEIGHT follows POSITION
		"int":
			_draft["number"] = clampi(_draft["number"] + direction, 1, 99)
		"foot":
			_draft["foot"] = CareerProfile.FOOT_LEFT if _draft["foot"] == CareerProfile.FOOT_RIGHT \
				else CareerProfile.FOOT_RIGHT
		"model":
			_cycle_model(direction)
		"swatch":
			_cycle_swatch(row["key"], direction)
		_:
			return   # NAME is edited via Enter (_activate), not A/D
	_refresh()


func _activate() -> void:
	if _selected == _confirm_index():
		_confirm_and_create()
		return
	var rows := _active_rows()
	if _selected < rows.size() and rows[_selected].get("kind", "") == "text":
		_name_edit.grab_focus()


# ── Customise ────────────────────────────────────────────────────────

func _toggle_customise() -> void:
	_customising = not _customising
	_customise_button.set_text(BACK_TEXT if _customising else CUSTOMISE_TEXT)
	_customise_button.set_icon(&"arrow_right" if _customising else &"gear")
	if _customising:
		_backdrop.zoom_in()
	else:
		_backdrop.zoom_out()
	_selected = 0
	_apply_row_mode()
	_refresh()


## The shared StatRow pool shows whichever list is active and hides the
## rest; the CAREER SETTINGS block only shows outside Customise.
func _apply_row_mode() -> void:
	var rows := _active_rows()
	for i in _rows.size():
		_rows[i].visible = i < rows.size()
		if i < rows.size():
			var entry: Dictionary = rows[i]
			# NAME is edited via Enter (grabs _name_edit), not A/D, so it's the
			# one row without the left/right arrow cue.
			_rows[i].configure(entry["icon"], entry["name"], false, entry.get("bar", true),
				entry.get("kind", "") != "text")
	_settings_block.visible = not _customising


func _cycle_model(direction: int) -> void:
	var idx := _model_ids.find(_draft["model_id"])
	idx = (idx + direction + _model_ids.size()) % _model_ids.size()
	_draft["model_id"] = _model_ids[idx]
	_backdrop.set_model(_draft["model_id"])
	_apply_kit_preview()   # set_model() rebuilt the rig — reapply the kit draft to it


## Index of `key`'s draft colour within CharacterScreen.SWATCHES[key], 0
## if unset or not in the list — the same fallback character_screen.gd's
## own _swatch_index() has.
func _swatch_index(key: String) -> int:
	var hex: String = _draft[key]
	if hex.is_empty():
		return 0
	var palette: Array = CharacterScreen.SWATCHES[key]
	for i in palette.size():
		if ("#" + (palette[i]["color"] as Color).to_html(false)).to_lower() == hex.to_lower():
			return i
	return 0


func _cycle_swatch(key: String, direction: int) -> void:
	var palette: Array = CharacterScreen.SWATCHES[key]
	var idx := (_swatch_index(key) + direction + palette.size()) % palette.size()
	_draft[key] = "#" + (palette[idx]["color"] as Color).to_html(false)
	_apply_kit_preview()


func _resolved_hex(hex: String) -> Color:
	return Color(hex) if not hex.is_empty() else Color(0.0, 0.0, 0.0, 0.0)


func _apply_kit_preview() -> void:
	_backdrop.set_kit_colors(_resolved_hex(_draft["skin_color"]),
		_resolved_hex(_draft["jersey_color"]), _resolved_hex(_draft["shorts_color"]),
		_resolved_hex(_draft["boot_color"]), _resolved_hex(_draft["socks_color"]))


# ── Confirm / leave ──────────────────────────────────────────────────

## Writes the draft to CareerProfile, starts the career (start levels,
## roster, season, save — see CareerProfile.start_career()), and launches
## the Dashboard. An empty NAME falls back to DEFAULT_NAME rather than
## blocking — no validation-dialog machinery exists on this screen, and a
## lean fallback beats building one just for this.
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
	CareerProfile.difficulty = _draft["difficulty"]
	_write_kit()
	CareerProfile.start_career()
	SceneWipe.change_scene("res://scenes/ui/career_dashboard_screen.tscn")


func _write_kit() -> void:
	CareerProfile.model_id = _draft["model_id"]
	for key in ["skin_color", "jersey_color", "shorts_color", "boot_color", "socks_color"]:
		CareerProfile.set(key, _draft[key])


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
	header.add_child(UIStyle.label(_title(), UIStyle.SIZE_TITLE, UIStyle.TEXT_PRIMARY,
		UIStyle.WEIGHT_HEAVY, UIStyle.TRACK_TITLE))
	var underline := Panel.new()
	underline.custom_minimum_size = Vector2(56.0, 4.0)
	underline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var underline_style := StyleBoxFlat.new()
	underline_style.bg_color = RetroWindow.ACCENT
	underline.add_theme_stylebox_override(&"panel", underline_style)
	header.add_child(underline)
	header.add_child(UIStyle.label(_subtitle(), UIStyle.SIZE_SUBTITLE, UIStyle.TEXT_MUTED,
		UIStyle.WEIGHT_REGULAR, UIStyle.TRACK_SUBTITLE))
	card_panel.add_child(header)

	var list := VBoxContainer.new()
	list.position = Vector2(CARD_PAD, STAT_TOP - CARD_TOP)
	list.add_theme_constant_override(&"separation", ROW_SEPARATION)
	list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card_panel.add_child(list)
	for i in maxi(CAREER_ROWS.size(), CharacterScreen.CUSTOMISE_ROWS.size()):
		var row := StatRow.new()
		list.add_child(row)
		_rows.append(row)

	_build_settings_block(card_panel)

	_play = ActionButton.new(ACTION_TEXT)
	_play.mouse_filter = Control.MOUSE_FILTER_STOP
	_play.gui_input.connect(_on_play_gui_input)
	_play.position = Vector2(CARD_PAD, BUTTON_TOP - CARD_TOP)
	card_panel.add_child(_play)

	_customise_button = ActionButton.new(CUSTOMISE_TEXT)
	_customise_button.set_icon(&"gear")
	_customise_button.mouse_filter = Control.MOUSE_FILTER_STOP
	_customise_button.gui_input.connect(func(event: InputEvent) -> void:
		if not _busy and event is InputEventMouseButton and event.pressed \
				and event.button_index == MOUSE_BUTTON_LEFT:
			_toggle_customise())
	# Centred under the player once it knows its own width (ActionButton
	# sizes itself to its label after layout).
	_customise_button.resized.connect(func() -> void:
		_customise_button.position = CUSTOMISE_CENTRE - Vector2(_customise_button.size.x * 0.5, 0.0))
	_customise_button.position = CUSTOMISE_CENTRE
	_ui.add_child(_customise_button)

	_hints = DeviceHintBar.new()
	_hints.position = Vector2(LEFT_MARGIN, HINTS_TOP)
	_ui.add_child(_hints)
	_hints.set_hint_sets({
		InputManager.Device.KEYBOARD: [
			{"keys": "W / S", "label": "Select"},
			{"keys": "A / D", "label": "Adjust"},
			{"keys": "Enter", "label": "Edit / Confirm"},
			{"keys": "Tab", "label": "Customise"},
			{"keys": "Esc", "label": "Back"},
		],
		InputManager.Device.GAMEPAD: [
			{"keys": "D-Pad ↕", "label": "Select"},
			{"keys": "D-Pad ↔", "label": "Adjust"},
			{"keys": "A", "label": "Confirm"},
			{"keys": "Y", "label": "Customise"},
			{"keys": "B", "label": "Back"},
		],
	})

	_build_name_edit()


func _title() -> String:
	return TITLE


func _subtitle() -> String:
	return SUBTITLE


## A rule across the card, "CAREER SETTINGS", the DIFFICULTY row and a line
## saying what the choice means.
func _build_settings_block(card_panel: Control) -> void:
	_settings_block = VBoxContainer.new()
	_settings_block.position = Vector2(CARD_PAD, SETTINGS_TOP - CARD_TOP)
	_settings_block.add_theme_constant_override(&"separation", 8)
	_settings_block.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card_panel.add_child(_settings_block)

	var rule := ColorRect.new()
	rule.color = Color(RetroWindow.BORDER, 0.35)
	rule.custom_minimum_size = Vector2(StatRow.WIDTH, 2.0)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_settings_block.add_child(rule)
	_settings_block.add_child(UIStyle.label(SETTINGS_TITLE, UIStyle.SIZE_SUBTITLE, UIStyle.TEXT_MUTED,
		UIStyle.WEIGHT_BOLD, UIStyle.TRACK_SUBTITLE))
	_difficulty_row = StatRow.new()
	_settings_block.add_child(_difficulty_row)
	_difficulty_row.configure(&"gear", "DIFFICULTY", false, false, true)
	_difficulty_caption = UIStyle.label("", UIStyle.SIZE_SUBTITLE, UIStyle.TEXT_MUTED,
		UIStyle.WEIGHT_REGULAR, 0)
	_settings_block.add_child(_difficulty_caption)


## A LineEdit that's never actually seen — invisible (alpha 0) and
## MOUSE_FILTER_IGNORE, so it's never a click target, but it can still be
## grab_focus()'d programmatically from _activate() to capture real text
## input while the NAME row is selected. The NAME StatRow's own value
## column shows the live text instead (see _row_value_text).
func _build_name_edit() -> void:
	_name_edit = LineEdit.new()
	_name_edit.text = _draft["player_name"]
	_name_edit.max_length = NAME_MAX_LENGTH
	_name_edit.modulate = Color(1.0, 1.0, 1.0, 0.0)
	_name_edit.size = Vector2(1.0, 1.0)
	_name_edit.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name_edit.text_changed.connect(func(new_text: String) -> void:
		_draft["player_name"] = new_text
		_refresh())
	_name_edit.text_submitted.connect(func(_new_text: String) -> void: _name_edit.release_focus())
	_name_edit.focus_entered.connect(func() -> void: _editing_name = true)
	_name_edit.focus_exited.connect(func() -> void: _editing_name = false)
	_ui.add_child(_name_edit)


func _on_play_gui_input(event: InputEvent) -> void:
	if _busy:
		return
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		_selected = _confirm_index()
		_confirm_and_create()


# ── Refresh ──────────────────────────────────────────────────────────

func _refresh() -> void:
	var rows := _active_rows()
	for i in rows.size():
		_rows[i].set_state(i == _selected, 0, _row_value_text(rows[i]))
	_difficulty_row.set_state(_selected == _difficulty_index(), 0,
		CareerProfile.DIFFICULTY_NAMES[_draft["difficulty"]])
	_difficulty_caption.text = _difficulty_caption_text()
	_play.set_selected(_selected == _confirm_index())


func _difficulty_caption_text() -> String:
	if _draft["difficulty"] == CareerProfile.DIFFICULTY_HARD:
		return "Every attribute starts at the minimum."
	return "Every attribute starts on one square."


func _row_value_text(entry: Dictionary) -> String:
	var key: String = entry["key"]
	match entry.get("kind", ""):
		"text":
			var text: String = _draft[key]
			return text if not text.is_empty() else "—"
		"role":
			var role_name: String = TeamFormation.Role.keys()[_draft[key]]
			return "%s · %.0f cm" % [role_name.replace("_", " "), _draft_height()]
		"int":
			return "#%d" % _draft[key]
		"foot":
			return _draft[key]
		"model":
			return (_draft[key] as String).to_upper()
		"swatch":
			return CharacterScreen.SWATCHES[key][_swatch_index(key)]["name"]
	return ""
