class_name TeamListScreen
extends CanvasLayer

## Team List screen: a top-down whiteboard preview of a team's starting
## layout (FormationWhiteboard, driven by TeamFormation's fixed 18
## slots). Reached from the main menu via the "team_menu" action (T),
## same as character_menu (C) reaches CharacterScreen — see main_menu.gd.
##
## Deliberately its own visual identity again — a chunky neomorphism x
## brutalist retro-'90s treatment (thick near-black borders, hard offset
## drop shadows instead of SoftBrutalist's blurred ones, a warm parchment
## card fill) rather than the rest of the game's Soft Brutalist system.
## Only the card shell changes: layout, the legend content, and
## FormationWhiteboard itself are untouched — see _card() below, which is
## a drop-in replacement for what used to be a plain _card() built on
## SoftBrutalist.panel_style()/soften().
##
## Roster editing (which named real player fills which of the 18 slots) is
## still out of scope — the project has no multi-player roster/persistence
## system yet (see character_screen.gd's own header). What IS editable
## (Team Edit expansion): three real tactics settings, each a Row (reusing
## SettingsScreen's own Row class rather than a second copy of the same
## title/options/index/cycle shape) that actually changes how a real match
## plays, not just a preview:
##   - MATCHDAY FORMATION — which of Settings.FORMATION_PRESETS' curated
##     4-a-side shapes HOME spawns into (FullGame._kickoff_slot()). Also
##     drives the whiteboard's own depth offset — see FormationWhiteboard.
##   - BALL MOVEMENT — corridor/mutual/boundary; read by AIBrain.
##     _lateral_target_z() to bias where a HOME carrier aims a disposal and
##     where an off-ball HOME teammate runs to support. Also drives the
##     whiteboard's width offset.
##   - DEFENSIVE PRESSURE — loose/balanced/tight; read by AIBrain.
##     _think_defend() to scale a HOME defender's chase gait and tackle-
##     commit range. Also pulls the whiteboard's own markers toward/away
##     from their mirrored opponent (see FormationWhiteboard.PRESSURE_GAP).
## Up/down (move_forward/ui_up, move_back/ui_down — same actions settings_
## screen.gd's own row list already uses) selects which row; left/right
## cycles its value; Settings.save() on exit persists all three the same
## way settings_screen.gd's rows already do. `toggle_opposition` (O) shows/
## hides a static mirrored 18-marker reference side on the board — a view
## toggle, not a persisted setting.
##
## The board itself moves its own markers to reflect these three dials —
## a FIFA/NBA 2K-style tactics board — rather than the retired design of
## drawing all 18 named AFL slots and ringing whichever 4 the preset used
## (see docs/HANDOVER.md for that design's own history).
##
## ── Layout ──────────────────────────────────────────────────────────
## One centred content column, not a full-width spread. The board is a
## portrait oval and it sizes itself to the available *height*, so when
## its panel was given every pixel of width left over after the legend
## column, the drawing ended up about 410px wide inside a 960px panel —
## two thirds of the screen's largest card was empty. Sizing that panel
## to the board it holds and centring the pair instead turns that dead
## area into margin, which reads as deliberate space rather than as a
## card someone forgot to fill.
##
## The tactics card's height (TACTICS_CARD_HEIGHT) is a hand-computed
## estimate against the same left-column budget the legend card already
## shares with the whiteboard's height — not visually confirmed, same
## "no GUI in this environment" limitation every screen in this project
## has shipped under. If it overflows the card in an actual editor
## session, shrink TACTICS_ROW_HEIGHT/TACTICS_ROW_GAP first.

const SCREEN_MARGIN := SoftBrutalist.SPACE_4        ## 32
const BAND_GAP := int(SoftBrutalist.SPACE_2)        ## 16
const PANEL_GAP := int(SoftBrutalist.SPACE_3)       ## 24
## Tall enough for a 30px title over a 13px subtitle *plus* the card's own
## padding. At 84 the two lines measured 61px against 36px of usable box
## and the subtitle printed through the bottom border.
const HEADER_HEIGHT := 104.0
const HINT_HEIGHT := 24.0
const COLUMN_WIDTH := 320.0
const CARD_PAD := SoftBrutalist.SPACE_3             ## 24

## Board panel width. The board draws itself to a portrait AFL aspect
## (Tuning's half-width over half-length) fitted to whatever height it is
## given, so this is that aspect applied to the tallest band this screen
## can offer, plus the board's own inset — i.e. the width at which the
## panel is exactly full rather than padded with empty cream.
const BOARD_ASPECT := 0.818
const BOARD_BAND_HEIGHT := 720.0 - SCREEN_MARGIN * 2.0 - HEADER_HEIGHT - HINT_HEIGHT \
	- float(BAND_GAP) * 2.0
const BOARD_PANEL_WIDTH := (BOARD_BAND_HEIGHT - FormationWhiteboard.MARGIN * 2.0) \
	* BOARD_ASPECT + FormationWhiteboard.MARGIN * 2.0
const CONTENT_WIDTH := COLUMN_WIDTH + float(PANEL_GAP) + BOARD_PANEL_WIDTH

## ── Retro neomorphism x brutalist card shell ───────────────────────────
## The shared RetroWindow shell (see retro_window.gd) — sharp, unrounded
## corners and a hard offset shadow, like a windowed retro pixel-game
## console rather than SoftBrutalist's soft blurred rounding. Also used by
## settings_screen.gd and pause_screen.gd now, so all three read as one
## consistent design language instead of drifting apart.
const RETRO_PANEL := RetroWindow.PANEL
const RETRO_BORDER := RetroWindow.BORDER
const RETRO_SHADOW := RetroWindow.SHADOW
const RETRO_ACCENT := RetroWindow.ACCENT

## Six legend rows plus their heading and the card padding. Fixed rather
## than expanding: a legend stretched to the full height of the board
## beside it is mostly empty card, and the slack reads better as space
## between two compact cards.
const LEGEND_HEIGHT := 296.0

const TACTICS_ROW_HEIGHT := 30.0
const TACTICS_ROW_GAP := 6.0
## 3 rows + 2 inter-row gaps + the card's own CARD_PAD top/bottom — no
## separate section heading (each row's own title, e.g. "DEFENSIVE
## PRESSURE", already says what it is; a "TEAM TACTICS" caption over the
## top of that would just repeat itself while costing real height in a
## card that is already tight against the left column's budget).
const TACTICS_CARD_HEIGHT := TACTICS_ROW_HEIGHT * 3.0 + TACTICS_ROW_GAP * 2.0 \
	+ CARD_PAD * 2.0

var _busy := false
var _whiteboard: FormationWhiteboard

var _rows: Array[SettingsScreen.Row] = []
var _row_index := 0
var _row_panels: Array[Panel] = []
var _row_value_labels: Array[Label] = []


func _ready() -> void:
	_rows = [
		SettingsScreen.Row.new("MATCHDAY FORMATION",
			["BALANCED", "ATTACKING", "DEFENSIVE"], Settings.home_formation_index,
			_set_formation),
		SettingsScreen.Row.new("BALL MOVEMENT",
			["CORRIDOR", "MUTUAL", "BOUNDARY"], Settings.home_ball_movement,
			_set_ball_movement),
		SettingsScreen.Row.new("DEFENSIVE PRESSURE",
			["LOOSE", "BALANCED", "TIGHT"], Settings.home_defensive_pressure,
			_set_defensive_pressure),
	]

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	root.add_child(SoftBrutalist.backdrop())

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override(StringName("margin_" + side), int(SCREEN_MARGIN))
	root.add_child(margin)

	var bands := VBoxContainer.new()
	bands.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bands.add_theme_constant_override(&"separation", BAND_GAP)
	margin.add_child(bands)

	_build_header(bands)
	_build_body(bands)
	_build_hint(bands)

	_refresh_rows()
	_sync_whiteboard()


func _unhandled_input(event: InputEvent) -> void:
	if _busy:
		return
	if event.is_action_pressed(&"pause") or event.is_action_pressed(&"team_menu") \
			or event.is_action_pressed(&"decline"):
		_exit_to_menu()
	elif event.is_action_pressed(&"move_forward") or event.is_action_pressed(&"ui_up"):
		_move_row(-1)
	elif event.is_action_pressed(&"move_back") or event.is_action_pressed(&"ui_down"):
		_move_row(1)
	elif event.is_action_pressed(&"ui_left"):
		_rows[_row_index].cycle(-1)
		_refresh_rows()
	elif event.is_action_pressed(&"ui_right"):
		_rows[_row_index].cycle(1)
		_refresh_rows()
	elif event.is_action_pressed(&"toggle_opposition"):
		if is_instance_valid(_whiteboard):
			_whiteboard.show_opposition = not _whiteboard.show_opposition


func _exit_to_menu() -> void:
	if _busy:
		return
	_busy = true
	Settings.save()
	SceneWipe.change_scene("res://scenes/ui/main_menu.tscn")


func _move_row(step: int) -> void:
	_row_index = (_row_index + step + _rows.size()) % _rows.size()
	_refresh_rows()


# ── Tactics rows ─────────────────────────────────────────────────────

func _set_formation(index: int) -> void:
	Settings.home_formation_index = index
	_sync_whiteboard()


func _set_ball_movement(index: int) -> void:
	Settings.home_ball_movement = index as Settings.BallMovementPreference
	_sync_whiteboard()


func _set_defensive_pressure(index: int) -> void:
	Settings.home_defensive_pressure = index as Settings.DefensivePressure
	_sync_whiteboard()


## Pushes all three tactics dials into the board in one pass — cheap even
## when only one actually changed (see FormationWhiteboard._retarget()),
## and means whichever row's on_change fires doesn't need to know which of
## the three the board actually cares about.
func _sync_whiteboard() -> void:
	if not is_instance_valid(_whiteboard):
		return
	_whiteboard.formation_index = Settings.home_formation_index
	_whiteboard.ball_movement = Settings.home_ball_movement
	_whiteboard.defensive_pressure = Settings.home_defensive_pressure


func _refresh_rows() -> void:
	for i in _rows.size():
		var selected := i == _row_index
		_row_panels[i].add_theme_stylebox_override(&"panel", _row_panel_style(selected))
		_row_value_labels[i].text = _rows[i].value()


## Transparent when not selected (the row reads as plain text sitting on
## the card's own parchment fill, no visible box), a soft accent tint when
## selected — the one thing that has to carry "this is the row up/down
## just moved to", since these rows aren't separate _card() shells with
## their own shadow/elevation to animate the way settings_screen.gd's
## SoftBrutalist rows are.
func _row_panel_style(selected: bool) -> StyleBoxFlat:
	return RetroWindow.row_style(selected)


# ── Build ────────────────────────────────────────────────────────────

## Thin wrapper over RetroWindow.card() — kept as a local method since
## every call site here already reads `_card(parent, size)`, and the
## external footprint (CONTENT_WIDTH, BOARD_PANEL_WIDTH etc., all
## hand-tuned against this screen's own CARD_PAD) doesn't change.
func _card(parent: Control, minimum: Vector2) -> MarginContainer:
	return RetroWindow.card(parent, minimum, CARD_PAD)


func _build_header(parent: Control) -> void:
	var inner := _card(parent, Vector2(CONTENT_WIDTH, HEADER_HEIGHT))
	# Two levels up: inner -> panel -> wrapper. Size flags have to land on
	# the wrapper, since that's the node actually parented into `parent`'s
	# layout — panel and shadow are just anchored full-rect inside it now.
	(inner.get_parent().get_parent() as Control).size_flags_horizontal = \
		Control.SIZE_SHRINK_CENTER

	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override(&"separation", 2)
	inner.add_child(column)
	column.add_child(SoftBrutalist.label("TEAM LIST", SoftBrutalist.SIZE_TITLE,
		RETRO_BORDER, SoftBrutalist.WEIGHT_HEAVY, SoftBrutalist.TRACK_TITLE))

	# The one "printed card" flourish: a short rust-coloured rule under the
	# title, the retro touch a plain type-only header didn't have.
	var underline := Panel.new()
	underline.custom_minimum_size = Vector2(56.0, 4.0)
	underline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var underline_style := StyleBoxFlat.new()
	underline_style.bg_color = RETRO_ACCENT
	underline.add_theme_stylebox_override(&"panel", underline_style)
	column.add_child(underline)
	column.add_child(SoftBrutalist.label("STARTING FORMATION PREVIEW",
		SoftBrutalist.SIZE_LABEL, SoftBrutalist.MUTED, SoftBrutalist.WEIGHT_REGULAR,
		SoftBrutalist.TRACK_LABEL))


func _build_body(parent: Control) -> void:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Neither child expands, so ALIGNMENT_CENTER centres the pair as a
	# group and the leftover width becomes even margin on both sides.
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override(&"separation", PANEL_GAP)
	parent.add_child(row)

	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.custom_minimum_size.x = COLUMN_WIDTH
	column.add_theme_constant_override(&"separation", PANEL_GAP)
	row.add_child(column)

	_build_legend(column)

	# Pushes the tactics card down to sit level with the board panel's
	# bottom edge, so the left column reads as two anchored cards rather
	# than two floating ones.
	var spacer := Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(spacer)

	_build_tactics_card(column)
	_build_whiteboard(row)


func _build_legend(parent: Control) -> void:
	var inner := _card(parent, Vector2(COLUMN_WIDTH, LEGEND_HEIGHT))

	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override(&"separation", int(SoftBrutalist.SPACE_2))
	inner.add_child(column)
	column.add_child(SoftBrutalist.label("POSITION LINES", SoftBrutalist.SIZE_LABEL,
		SoftBrutalist.MUTED, SoftBrutalist.WEIGHT_BOLD, SoftBrutalist.TRACK_LABEL))

	for line: int in TeamFormation.LINE_NAMES.size():
		var line_row := HBoxContainer.new()
		line_row.add_theme_constant_override(&"separation", int(SoftBrutalist.SPACE_2))
		line_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_child(line_row)

		# Rounded, not a bare square: a hard-cornered swatch beside a set
		# of 16px-radius cards is the one element on the screen that does
		# not belong to the shape language.
		var swatch := Panel.new()
		var swatch_style := SoftBrutalist.panel_style(FormationWhiteboard.LINE_COLOURS[line],
			SoftBrutalist.RADIUS_XS, FormationWhiteboard.LINE_COLOURS[line].darkened(0.25))
		swatch.add_theme_stylebox_override(&"panel", swatch_style)
		swatch.custom_minimum_size = Vector2(16.0, 16.0)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line_row.add_child(swatch)

		var name_label := SoftBrutalist.label(TeamFormation.LINE_NAMES[line],
			SoftBrutalist.SIZE_BODY, SoftBrutalist.INK, SoftBrutalist.WEIGHT_REGULAR,
			SoftBrutalist.TRACK_NONE)
		name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		line_row.add_child(name_label)


## Three real pickers (Team Edit expansion): Matchday Formation, Ball
## Movement preference, Defensive Pressure — see this file's own header
## comment for what each actually changes about a match. One shared card
## rather than one each: three separate _card() shells (each paying
## CARD_PAD on all four sides plus its own shadow) would not fit this
## column's height budget the way one card holding three lightweight rows
## does — see TACTICS_CARD_HEIGHT.
func _build_tactics_card(parent: Control) -> void:
	var inner := _card(parent, Vector2(COLUMN_WIDTH, TACTICS_CARD_HEIGHT))

	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override(&"separation", int(TACTICS_ROW_GAP))
	inner.add_child(column)

	for row in _rows:
		_build_tactics_row(column, row)


func _build_tactics_row(parent: Control, row: SettingsScreen.Row) -> void:
	var panel := Panel.new()
	panel.custom_minimum_size = Vector2(0.0, TACTICS_ROW_HEIGHT)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(panel)
	_row_panels.append(panel)

	var inset := MarginContainer.new()
	inset.set_anchors_preset(Control.PRESET_FULL_RECT)
	inset.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side: String in ["left", "right"]:
		inset.add_theme_constant_override(StringName("margin_" + side), 10)
	panel.add_child(inset)

	var line := HBoxContainer.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inset.add_child(line)

	var title_label := SoftBrutalist.label(row.title, SoftBrutalist.SIZE_CAPTION,
		RETRO_BORDER, SoftBrutalist.WEIGHT_BOLD, SoftBrutalist.TRACK_LABEL)
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	line.add_child(title_label)

	var spacer := Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(spacer)

	var value_label := SoftBrutalist.label(row.value(), SoftBrutalist.SIZE_LABEL,
		RETRO_ACCENT, SoftBrutalist.WEIGHT_BOLD, SoftBrutalist.TRACK_NONE)
	value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	value_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	line.add_child(value_label)
	_row_value_labels.append(value_label)


func _build_whiteboard(parent: Control) -> void:
	var inner := _card(parent, Vector2(BOARD_PANEL_WIDTH, 0.0))
	# See _build_header()'s comment — the flag has to land on the wrapper,
	# two levels up from `inner`, for the row to actually stretch it.
	var wrapper := inner.get_parent().get_parent() as Control
	wrapper.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# The board draws its own inset (FormationWhiteboard.MARGIN), so the
	# card's text padding would double it.
	for side: String in ["left", "right", "top", "bottom"]:
		inner.add_theme_constant_override(StringName("margin_" + side), 0)

	_whiteboard = FormationWhiteboard.new()
	_whiteboard.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(_whiteboard)


func _build_hint(parent: Control) -> void:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.custom_minimum_size.y = HINT_HEIGHT
	parent.add_child(row)

	var hints := DeviceHintBar.new()
	hints.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(hints)
	hints.set_hint_sets({
		InputManager.Device.KEYBOARD: [
			{"keys": "↑ / ↓", "label": "Select"},
			{"keys": "← / →", "label": "Change"},
			{"keys": "O", "label": "Opposition"},
			{"keys": "T / Esc", "label": "Back to menu"},
		],
		# toggle_opposition's gamepad binding used to be joypad button 12
		# (JOY_BUTTON_DPAD_DOWN), shadowed by ui_down's own engine-default
		# D-Pad-Down binding — this screen's _unhandled_input checks
		# move_back/ui_down first, so that event always moved the row cursor
		# and toggle_opposition's elif branch below it never ran. Rebound to
		# LB (project.godot, button_index 9) per ui_audit.md's fix.
		InputManager.Device.GAMEPAD: [
			{"keys": "D-Pad ↕", "label": "Select"},
			{"keys": "D-Pad ↔", "label": "Change"},
			{"keys": "LB", "label": "Opposition"},
			{"keys": "B", "label": "Back to menu"},
		],
	})
