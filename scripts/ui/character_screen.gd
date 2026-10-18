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
##
## Cosmetic *build* changes (muscle size etc.) are a later pass, once
## there's a second body shape to vary — out of scope alongside the
## colour-only Customise panel below (see CUSTOMISE_ROWS).
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
## Present in both ATTRIBUTE_ROWS and CUSTOMISE_ROWS modes — MODEL/colours
## are drafted the same way a stat is, so leaving Customise shouldn't lose
## an edit any more than leaving a stat row does.
const APPLY_MODE_TEXT := {true: "ALL PLAYERS", false: "START PLAYER"}

## CUSTOMISE / BACK toggle, floating over the 3D preview in the preview's
## own right-hand region (the stat card occupies CARD_LEFT..CARD_LEFT+
## CARD_WIDTH on the left) — the same ActionButton shape PLAY already
## uses, so it inherits the one mouse-click mechanism already proven to
## work on this screen rather than being its own one-off widget.
const CUSTOMISE_BUTTON_POSITION := Vector2(860.0, 650.0)
const CUSTOMISE_TEXT := "CUSTOMISE"
const BACK_TEXT := "BACK"

## Customise panel rows, shown instead of ATTRIBUTE_ROWS while
## _customising is true — the MODEL row (existing CharacterProfile.
## model_id machinery) plus four colour rows. `kind` picks how _nudge()/
## _row_value_text() treat the row: "model" cycles _model_ids, "swatch"
## cycles one of the SWATCHES lists below by name.
const CUSTOMISE_ROWS := [
	{"key": "model_id", "icon": &"figure", "name": "MODEL", "kind": "model", "bar": false},
	{"key": "skin_color", "icon": &"swatch", "name": "SKIN", "kind": "swatch", "bar": false},
	{"key": "jersey_color", "icon": &"swatch", "name": "JERSEY", "kind": "swatch", "bar": false},
	{"key": "shorts_color", "icon": &"swatch", "name": "SHORTS", "kind": "swatch", "bar": false},
	{"key": "boot_color", "icon": &"foot", "name": "SHOES", "kind": "swatch", "bar": false},
]

## Fixed swatch palettes for the "swatch"-kind CUSTOMISE_ROWS, by key. Only
## ever visible on the procedural body — an imported model brings its own
## baked materials (see humanoid_rig.gd's kit_* header note) and a swatch
## here previews no change on one, same existing limitation kit_torso has.
const SWATCHES := {
	"skin_color": [
		{"name": "FAIR", "color": Color("#ecc9a0")},
		{"name": "LIGHT", "color": Color("#d9ae7e")},
		{"name": "TAN", "color": Color("#b98655")},
		{"name": "DEEP", "color": Color("#8a5a35")},
		{"name": "DARK", "color": Color("#5c3a22")},
	],
	"jersey_color": [
		{"name": "GOLD", "color": Color("#e9c95e")},
		{"name": "CRIMSON", "color": Color("#c0392b")},
		{"name": "BLUE", "color": Color("#2e5fa3")},
		{"name": "GREEN", "color": Color("#2e7d4f")},
		{"name": "PURPLE", "color": Color("#6a3d9a")},
		{"name": "BLACK", "color": Color("#1c1a17")},
		{"name": "WHITE", "color": Color("#f0ece0")},
	],
	"shorts_color": [
		{"name": "CHARCOAL", "color": Color("#2a2c33")},
		{"name": "BLACK", "color": Color("#1c1a17")},
		{"name": "WHITE", "color": Color("#f0ece0")},
		{"name": "NAVY", "color": Color("#1f2d4a")},
		{"name": "CRIMSON", "color": Color("#c0392b")},
	],
	"boot_color": [
		{"name": "BLACK", "color": Color("#22241d")},
		{"name": "WHITE", "color": Color("#f0ece0")},
		{"name": "CRIMSON", "color": Color("#c0392b")},
		{"name": "GOLD", "color": Color("#e9c95e")},
	],
}

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

var _draft := {}
var _rows: Array[StatRow] = []
var _model_ids: Array[String] = ["procedural"]   ## + HumanoidRig.CHARACTER_MODELS.keys(), in _ready()
var _apply_row: StatRow          ## APPLY TO toggle, at index _apply_index()
var _play: ActionButton
var _customise_button: ActionButton
var _hints: DeviceHintBar
var _selected := 0
var _busy := false   ## true while a wipe is in flight — input is inert

## Customise panel open/closed — picks ATTRIBUTE_ROWS vs CUSTOMISE_ROWS
## for every row-list method below (_row_count/_nudge/_refresh/…), and
## which half of the 3D preview's zoom the backdrop currently sits at.
var _customising := false


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
		"skin_color": CharacterProfile.skin_color,
		"jersey_color": CharacterProfile.jersey_color,
		"shorts_color": CharacterProfile.shorts_color,
		"boot_color": CharacterProfile.boot_color,
	}
	_build()
	_backdrop.set_height_scale(_draft["height"] / Tuning.CHARACTER_HEIGHT_DEFAULT)
	_apply_kit_preview()
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


## ATTRIBUTE_ROWS normally, CUSTOMISE_ROWS while the Customise panel is
## open — every row-list method below reads this instead of ATTRIBUTE_ROWS
## directly, so the two panels share one cursor/nudge/refresh path.
func _active_rows() -> Array:
	return CUSTOMISE_ROWS if _customising else ATTRIBUTE_ROWS


## Index of the APPLY TO toggle row, then the PLAY row, in the up/down list
## that runs past the stat rows.
func _apply_index() -> int:
	return _active_rows().size()


func _play_index() -> int:
	return _active_rows().size() + 1


func _row_count() -> int:
	return _active_rows().size() + 2   # + the APPLY TO toggle and the PLAY action row


func _move(step: int) -> void:
	_selected = (_selected + step + _row_count()) % _row_count()
	_refresh()


func _nudge(direction: int) -> void:
	if _selected == _apply_index():
		# Two-value toggle — either direction just flips it.
		_draft["apply_all"] = not _draft["apply_all"]
		_refresh()
		return
	var rows := _active_rows()
	if _selected >= rows.size():
		return
	var row: Dictionary = rows[_selected]
	match row.get("kind", "stat"):
		"model":
			_cycle_model(direction)
		"swatch":
			_cycle_swatch(row["key"], direction)
			_refresh()
		_:
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
	_apply_kit_preview()   # set_model() rebuilt the rig — reapply the kit draft to it
	_refresh()


## Index of `key`'s current draft colour within SWATCHES[key] — 0 (the
## palette's first entry) if the draft is unset or names something that
## isn't in the fixed list, same "fall back to a safe default" spirit
## CharacterProfile._load_hex() already has for a stale file.
func _swatch_index(key: String) -> int:
	var hex: String = _draft[key]
	if hex.is_empty():
		return 0
	var palette: Array = SWATCHES[key]
	for i in palette.size():
		if ("#" + (palette[i]["color"] as Color).to_html(false)).to_lower() == hex.to_lower():
			return i
	return 0


## Steps `key`'s draft colour through its fixed SWATCHES list and
## live-previews the result — the "swatch" row's equivalent of
## _cycle_model() above.
func _cycle_swatch(key: String, direction: int) -> void:
	var palette: Array = SWATCHES[key]
	var idx := (_swatch_index(key) + direction + palette.size()) % palette.size()
	_draft[key] = "#" + (palette[idx]["color"] as Color).to_html(false)
	_apply_kit_preview()


## "" (unset) resolves to alpha 0, which HumanoidRig/CharacterBackdrop
## both already treat as "use the built-in default" — see their kit_*
## header notes.
func _resolved_kit_color(key: String) -> Color:
	var hex: String = _draft[key]
	return Color(hex) if not hex.is_empty() else Color(0.0, 0.0, 0.0, 0.0)


func _apply_kit_preview() -> void:
	_backdrop.set_kit_colors(
		_resolved_kit_color("skin_color"),
		_resolved_kit_color("jersey_color"),
		_resolved_kit_color("shorts_color"),
		_resolved_kit_color("boot_color"))


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
	CharacterProfile.skin_color = _draft["skin_color"]
	CharacterProfile.jersey_color = _draft["jersey_color"]
	CharacterProfile.shorts_color = _draft["shorts_color"]
	CharacterProfile.boot_color = _draft["boot_color"]
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

	_hints = DeviceHintBar.new()
	_hints.position = Vector2(LEFT_MARGIN, HINTS_TOP)
	_ui.add_child(_hints)
	_hints.set_hint_sets({
		InputManager.Device.KEYBOARD: [
			{"keys": "W / S", "label": "Select"},
			{"keys": "A / D", "label": "Adjust"},
			{"keys": "Enter", "label": "Play"},
			{"keys": "B / Esc / C", "label": "Back"},
		],
		InputManager.Device.GAMEPAD: [
			{"keys": "D-Pad ↕", "label": "Select"},
			{"keys": "D-Pad ↔", "label": "Adjust"},
			{"keys": "A", "label": "Play"},
			{"keys": "B", "label": "Back"},
		],
	})

	_build_customise_button()
	_apply_row_mode()


## CUSTOMISE / BACK toggle — the only mouse-interactive thing outside the
## card besides PLAY, built the exact same way (an ActionButton with its
## mouse_filter explicitly set to STOP and gui_input connected directly)
## rather than as its own one-off Button, since that's the one mechanism
## already proven to take a click on this screen.
func _build_customise_button() -> void:
	_customise_button = ActionButton.new(CUSTOMISE_TEXT)
	_customise_button.set_icon(&"gear")
	_customise_button.mouse_filter = Control.MOUSE_FILTER_STOP
	_customise_button.gui_input.connect(_on_customise_gui_input)
	_customise_button.position = CUSTOMISE_BUTTON_POSITION
	_ui.add_child(_customise_button)


func _on_customise_gui_input(event: InputEvent) -> void:
	if _busy:
		return
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		_toggle_customise()


## Swaps the stat card between ATTRIBUTE_ROWS and CUSTOMISE_ROWS and eases
## the 3D preview camera in/out to match (see CharacterBackdrop.zoom_in/
## zoom_out). The cursor resets to row 0 of whichever list just became
## active rather than carrying over an index that may now point at a
## differently-kinded row.
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


## Reconfigures the shared pool of StatRow nodes (built once in _build()
## from ATTRIBUTE_ROWS, the longer of the two lists) to show whichever
## list _active_rows() currently returns, hiding whatever's left over —
## CUSTOMISE_ROWS is shorter, so the last few rows just go invisible
## rather than needing a second pool of nodes.
func _apply_row_mode() -> void:
	var rows := _active_rows()
	for i in _rows.size():
		if i < rows.size():
			var entry: Dictionary = rows[i]
			_rows[i].configure(entry["icon"], entry["name"], entry["key"] == null,
				entry.get("bar", true))
			_rows[i].visible = true
		else:
			_rows[i].visible = false


func _on_play_gui_input(event: InputEvent) -> void:
	if _busy:
		return
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		_selected = _play_index()
		_confirm_and_play()


# ── Refresh ──────────────────────────────────────────────────────────

func _refresh() -> void:
	var rows := _active_rows()
	for i in rows.size():
		var entry: Dictionary = rows[i]
		_rows[i].set_state(i == _selected, _filled_segments(entry), _row_value_text(entry))
	_apply_row.set_state(_selected == _apply_index(), 0,
		APPLY_MODE_TEXT[_draft["apply_all"]])
	_play.set_selected(_selected == _play_index())


## Where the stat sits between its own min and max, quantised to the
## row's squares. A locked row has no backing stat yet, so it reads zero
## — the bar is not hidden and not faked, it just has nothing to show
## until something in CharacterProfile drives it. MODEL/swatch rows never
## show a bar at all (see CUSTOMISE_ROWS' "bar": false), so this is moot
## for them, but stays null-safe either way.
func _filled_segments(entry: Dictionary) -> int:
	var key = entry["key"]
	if key == null or entry.has("kind"):
		return 0
	var config: Dictionary = _stat_config[key]
	var vmin := float(config["min"])
	var vmax := float(config["max"])
	if vmax <= vmin:
		return 0
	var fraction := clampf((float(_draft[key]) - vmin) / (vmax - vmin), 0.0, 1.0)
	return int(round(fraction * StatRow.SEGMENTS))


## Empty for the locked attribute rows: they have no assigned number, and
## a "—" placeholder would just be noise in a column that is otherwise
## all real readings. MODEL/swatch rows read their current draft choice's
## display name instead of a formatted number.
func _row_value_text(entry: Dictionary) -> String:
	var key = entry["key"]
	if key == null:
		return ""
	match entry.get("kind", "stat"):
		"model":
			return (_draft[key] as String).to_upper()
		"swatch":
			return SWATCHES[key][_swatch_index(key)]["name"]
		_:
			var config: Dictionary = _stat_config[key]
			var value: float = _draft[key]
			# kick_accuracy is stored 0..1 and shown as a percentage;
			# everything else is already in its display unit.
			var display_value := value * 100.0 if key == "kick_accuracy" else value
			return (config["format"] as String) % display_value
