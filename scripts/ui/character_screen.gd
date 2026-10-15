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
## MODEL (CharacterProfile.model_id — see _model_ids, built in _ready()
## since HumanoidRig.CHARACTER_MODELS.keys() isn't a constant expression)
## is a separate small switcher under the 3D preview instead of a row in
## this list — see _build_model_switch().
const APPLY_MODE_TEXT := {true: "ALL PLAYERS", false: "START PLAYER"}

## Small MODEL switcher card, floating over the 3D preview rather than in
## the stat list — centred under the previewed figure, in the preview's
## own right-hand region (the stat card occupies CARD_LEFT..CARD_LEFT+
## CARD_WIDTH on the left). Independent of the stat card's own fixed
## geometry above, so it never risks pushing BUTTON_TOP/HINTS_TOP off the
## bottom of the 720px design canvas the way adding a ninth stat row
## would have.
const MODEL_SWITCH_SIZE := Vector2(280.0, 76.0)
const MODEL_SWITCH_PAD := 14.0
const MODEL_SWITCH_POSITION := Vector2(821.0, 628.0)
const MODEL_SWITCH_BUTTON := 28.0

const TITLE := "PLAYER PROFILE"
const SUBTITLE := "CUSTOMISE YOUR CHARACTER"
const ACTION_TEXT := "PLAY — OPEN FIELD"

# ── Left column geometry, in design-resolution px (1280x720) ─────────
const LEFT_MARGIN := 58.0
const HEADER_TOP := 62.0
const STAT_TOP := 160.0
const ROW_SEPARATION := 8
const BUTTON_TOP := 613.0

## Retro card shell behind the left column — the same windowed-console
## treatment (parchment fill, thick near-black border, hard offset shadow)
## team_list_screen.gd and the dev animation/ML-experiments viewers already
## use, so this screen reads as the same family instead of its rows sitting
## bare on the live 3D backdrop. Only the shell is new: StatRow,
## ActionButton and KeyHintBar are untouched, same content just framed.
## Derived from the existing row geometry above (CARD_PAD in from
## LEFT_MARGIN/HEADER_TOP) rather than a second hand-tuned layout.
const CARD_PAD := 24.0
const CARD_LEFT := LEFT_MARGIN - CARD_PAD
const CARD_TOP := HEADER_TOP - CARD_PAD
const CARD_WIDTH := StatRow.WIDTH + CARD_PAD * 2.0
const CARD_HEIGHT := BUTTON_TOP + ActionButton.HEIGHT - CARD_TOP + CARD_PAD

## Below the card's own hard shadow (RetroWindow.SHADOW_OFFSET.y), clear of
## the card entirely rather than sitting on its edge the way the old
## HINTS_TOP (inside the card's old footprint) did.
const HINTS_TOP := CARD_TOP + CARD_HEIGHT + RetroWindow.SHADOW_OFFSET.y + 6.0


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
var _model_ids: Array[String] = ["procedural"]   ## + HumanoidRig.CHARACTER_MODELS.keys(), in _ready()
var _model_label: Label          ## MODEL switch value text — see _build_model_switch()
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
	_model_ids.append_array(HumanoidRig.CHARACTER_MODELS.keys())
	_draft = {
		"speed": CharacterProfile.speed,
		"height": CharacterProfile.height,
		"kick_power": CharacterProfile.kick_power,
		"kick_accuracy": CharacterProfile.kick_accuracy,
		"agility": CharacterProfile.agility,
		"apply_all": CharacterProfile.apply_all,
		"model_id": CharacterProfile.model_id,
	}
	_hint_sets = {
		InputManager.Device.KEYBOARD: [
			{"keys": "W / S", "label": "Select"},
			{"keys": "A / D", "label": "Adjust"},
			{"keys": "Enter", "label": "Play"},
			{"keys": "B / Esc / C", "label": "Back"},
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
	elif event.is_action_pressed(&"pause") or event.is_action_pressed(&"character_menu") \
			or event.is_action_pressed(&"decline"):
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


## Steps the draft model selection forward/back through _model_ids and
## live-previews it on the backdrop — same "draft until PLAY/back-out
## commits it" relationship every stat row already has, via
## CharacterBackdrop.set_model() rather than CharacterProfile directly.
func _cycle_model(direction: int) -> void:
	var idx := _model_ids.find(_draft["model_id"])
	idx = (idx + direction + _model_ids.size()) % _model_ids.size()
	_draft["model_id"] = _model_ids[idx]
	_backdrop.set_model(_draft["model_id"])
	_refresh()


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
	CharacterProfile.model_id = _draft["model_id"]
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
	# Retro card shell (see CARD_* above) — shell() rather than card() since
	# every child below is positioned by hand with raw .position offsets,
	# same reason settings_screen.gd/pause_screen.gd use it instead of a
	# layout container.
	var card_panel := RetroWindow.shell(_ui, Vector2(CARD_WIDTH, CARD_HEIGHT))
	(card_panel.get_parent() as Control).position = Vector2(CARD_LEFT, CARD_TOP)

	var header := VBoxContainer.new()
	header.position = Vector2(CARD_PAD, CARD_PAD)
	header.add_theme_constant_override(&"separation", 2)
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(UIStyle.label(TITLE, UIStyle.SIZE_TITLE, UIStyle.TEXT_PRIMARY,
		UIStyle.WEIGHT_HEAVY, UIStyle.TRACK_TITLE))

	# The same short rust-coloured rule team_list_screen.gd prints under its
	# own title — the one "printed card" flourish, now shared.
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
	_play.position = Vector2(CARD_PAD, BUTTON_TOP - CARD_TOP)
	card_panel.add_child(_play)

	_hints = KeyHintBar.new()
	_hints.position = Vector2(LEFT_MARGIN, HINTS_TOP)
	_ui.add_child(_hints)
	_apply_hints()

	_build_model_switch()


## Small floating card under the 3D preview: ‹ MODEL name › — click either
## arrow to step through _model_ids and live-preview the result on
## _backdrop (see _cycle_model). Mouse-only; unlike the stat rows this
## isn't part of the keyboard up/down list, so it has no selection state.
func _build_model_switch() -> void:
	var inner := RetroWindow.card(_ui, MODEL_SWITCH_SIZE, MODEL_SWITCH_PAD)
	var wrapper := inner.get_parent().get_parent() as Control
	wrapper.position = MODEL_SWITCH_POSITION

	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(row)

	var prev_btn := _make_switch_button("<")
	prev_btn.pressed.connect(func() -> void: _cycle_model(-1))
	row.add_child(prev_btn)

	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.alignment = BoxContainer.ALIGNMENT_CENTER
	mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(mid)

	var caption := UIStyle.label("MODEL", UIStyle.SIZE_HINT, UIStyle.TEXT_MUTED,
		UIStyle.WEIGHT_BOLD, UIStyle.TRACK_LABEL)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mid.add_child(caption)

	_model_label = UIStyle.label("", UIStyle.SIZE_LABEL, UIStyle.TEXT_PRIMARY, UIStyle.WEIGHT_BOLD)
	_model_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mid.add_child(_model_label)

	var next_btn := _make_switch_button(">")
	next_btn.pressed.connect(func() -> void: _cycle_model(1))
	row.add_child(next_btn)

	_model_label.text = (_draft["model_id"] as String).to_upper()


## Square retro-styled arrow button for the MODEL switcher — sharp corners,
## near-black border, accent fill while pressed, same palette as the retro
## card shell but a one-off stylebox rather than a shared helper since
## nothing else on this screen needs a button this small.
func _make_switch_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(MODEL_SWITCH_BUTTON, MODEL_SWITCH_BUTTON)
	b.focus_mode = Control.FOCUS_NONE

	var normal := StyleBoxFlat.new()
	normal.bg_color = RetroWindow.PANEL.darkened(0.05)
	normal.border_color = RetroWindow.BORDER
	normal.set_border_width_all(2)
	var pressed := StyleBoxFlat.new()
	pressed.bg_color = RetroWindow.ACCENT
	pressed.border_color = RetroWindow.BORDER
	pressed.set_border_width_all(2)
	b.add_theme_stylebox_override(&"normal", normal)
	b.add_theme_stylebox_override(&"hover", normal)
	b.add_theme_stylebox_override(&"pressed", pressed)
	b.add_theme_stylebox_override(&"hover_pressed", pressed)
	b.add_theme_stylebox_override(&"focus", StyleBoxEmpty.new())
	b.add_theme_font_size_override(&"font_size", UIStyle.SIZE_LABEL)
	b.add_theme_color_override(&"font_color", UIStyle.TEXT_PRIMARY)
	b.add_theme_color_override(&"font_hover_color", UIStyle.TEXT_PRIMARY)
	b.add_theme_color_override(&"font_pressed_color", Color.BLACK)
	b.add_theme_color_override(&"font_hover_pressed_color", Color.BLACK)
	return b


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
	if _model_label != null:
		_model_label.text = (_draft["model_id"] as String).to_upper()
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
