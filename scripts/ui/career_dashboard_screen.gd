class_name CareerDashboardScreen
extends CanvasLayer

## Career mode's home screen — reached after character creation (Phase 4)
## and again after every full-time screen. Left-anchored, not the centred
## layout main_menu.gd/the rest of the front end uses (the user's own
## note on this: "not everything in our code is centred to avoid ai
## look") — this is the one screen in the whole plan that note actually
## applies to, see career_character_screen.gd's sibling phases for why it
## doesn't apply there too.
##
## This pass only ships game 1: VIEW ROSTER is real (an overlay reading
## CareerProfile.roster, grouped by TeamFormation line same as team_list_
## screen.gd's own legend), VIEW STATS is a locked stub, and once
## CareerProfile.games_played >= 1 the whole dashboard renders behind a
## dimmed scrim with a lock glyph and a single MAIN MENU action — nothing
## past the first game exists yet (see _build_locked_overlay).

const SCREEN_MARGIN_X := SoftBrutalist.SPACE_6
const SCREEN_MARGIN_Y := SoftBrutalist.SPACE_4
const BAND_GAP := SoftBrutalist.SPACE_4
const CARD_PAD := 20.0
const BUTTON_HEIGHT := 48.0
const BUTTON_WIDTH := 200.0
const ICON_SIZE := 22.0

var _locked := false
var _roster_overlay: Control


func _ready() -> void:
	_locked = CareerProfile.games_played >= 1
	_build()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"pause") or event.is_action_pressed(&"decline"):
		_on_main_menu_pressed()


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = CareerTheme.BACKGROUND
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		var value := SCREEN_MARGIN_Y if side in ["top", "bottom"] else SCREEN_MARGIN_X
		margin.add_theme_constant_override(StringName("margin_" + side), int(value))
	add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", int(BAND_GAP))
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(column)

	var header := VBoxContainer.new()
	header.add_theme_constant_override(&"separation", 4)
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(header)
	header.add_child(CareerTheme.label(CareerProfile.team_name, SoftBrutalist.SIZE_TITLE,
		CareerTheme.TEXT, SoftBrutalist.WEIGHT_HEAVY))
	header.add_child(CareerTheme.label("JUNIORS U18s CAREER — %s" % CareerProfile.player_name,
		SoftBrutalist.SIZE_BODY, CareerTheme.TEXT_MUTED))

	column.add_child(_build_next_game_card())

	var button_row := HBoxContainer.new()
	button_row.add_theme_constant_override(&"separation", int(SoftBrutalist.SPACE_4))
	button_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(button_row)
	button_row.add_child(_build_action_button("VIEW ROSTER", &"gear", true,
		_on_view_roster_pressed))
	button_row.add_child(_build_action_button("VIEW STATS", &"lock", false, Callable()))

	if _locked:
		_build_locked_overlay()


## The "NEXT GAME" card: a yellow/black pixel-art exclamation mark beside
## the heading (see ExclamationIcon below), the upcoming fixture's
## generated opponent name, and a click-through to the Career pregame
## screen — a plain Panel with gui_input wired directly, same mechanism
## character_screen.gd's PLAY/CUSTOMISE buttons already proved works.
func _build_next_game_card() -> Control:
	var panel := Panel.new()
	panel.custom_minimum_size = Vector2(520.0, 132.0)
	panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	# Scale grows from the card's own centre, not its top-left corner — see
	# _set_next_game_hover().
	panel.pivot_offset = panel.custom_minimum_size * 0.5
	panel.add_theme_stylebox_override(&"panel", CareerTheme.panel_style())
	if not _locked and not CareerProfile.season_complete():
		panel.mouse_filter = Control.MOUSE_FILTER_STOP
		panel.gui_input.connect(_on_next_game_gui_input)
		panel.mouse_entered.connect(_set_next_game_hover.bind(panel, true))
		panel.mouse_exited.connect(_set_next_game_hover.bind(panel, false))
		# Real Control focus rather than this project's usual hand-rolled
		# cursor index (user asked for this one button to react "for mouse
		# or gamepad" — this screen has no existing gamepad navigation at
		# all to hook into, and Control's own focus traversal already
		# answers ui_up/down/left/right for free). The default focus
		# stylebox is suppressed below so the only visible feedback is this
		# same hover treatment, not a second overlapping outline.
		panel.focus_mode = Control.FOCUS_ALL
		panel.add_theme_stylebox_override(&"focus", StyleBoxEmpty.new())
		panel.focus_entered.connect(_set_next_game_hover.bind(panel, true))
		panel.focus_exited.connect(_set_next_game_hover.bind(panel, false))
	else:
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var inner := MarginContainer.new()
	inner.set_anchors_preset(Control.PRESET_FULL_RECT)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		inner.add_theme_constant_override(StringName("margin_" + side), int(CARD_PAD))
	panel.add_child(inner)

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override(&"separation", 4)
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(rows)

	var heading_row := HBoxContainer.new()
	heading_row.add_theme_constant_override(&"separation", 8)
	heading_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_child(heading_row)
	var icon := ExclamationIcon.new()
	heading_row.add_child(icon)
	heading_row.add_child(CareerTheme.label("NEXT GAME", SoftBrutalist.SIZE_LABEL, CareerTheme.PANEL_TEXT,
		SoftBrutalist.WEIGHT_BOLD, 1))

	var opponent_text := "SEASON COMPLETE" if CareerProfile.season_complete() \
		else CareerProfile.current_fixture()
	rows.add_child(CareerTheme.label(opponent_text, SoftBrutalist.SIZE_TITLE, CareerTheme.PANEL_TEXT,
		SoftBrutalist.WEIGHT_HEAVY))
	var hint_text := "" if CareerProfile.season_complete() else "Click to set up the match"
	if not hint_text.is_empty():
		rows.add_child(CareerTheme.label(hint_text, SoftBrutalist.SIZE_BODY, CareerTheme.PANEL_TEXT.lightened(0.3)))

	return panel


func _on_next_game_gui_input(event: InputEvent) -> void:
	if _locked or CareerProfile.season_complete():
		return
	var clicked: bool = event is InputEventMouseButton and event.pressed \
		and event.button_index == MOUSE_BUTTON_LEFT
	# Control.gui_input also receives key/joypad input once the control has
	# focus (not just mouse events inside its rect) — see the focus_mode
	# this card now sets in _build_next_game_card() — so "confirm" (A on a
	# pad) activates it the same way a click does, for the gamepad
	# navigation that focus_mode exists for in the first place.
	if clicked or event.is_action_pressed(&"confirm"):
		SceneWipe.change_scene("res://scenes/ui/career_pregame_screen.tscn")


## Hover highlight for the NEXT GAME card — user report: "it should
## highlight on hover for mouse or gamepad, just a slight stroke and
## increase size slightly", same stroke language RetroWindow.row_style()
## already uses for a selected list row elsewhere in this project, plus a
## small scale pop borrowed from full_game_pregame_screen.gd's own card-
## hover treatment (CARD_SELECTED_SCALE) rather than inventing a third
## hover language.
const NEXT_GAME_HOVER_SCALE := 1.03
const NEXT_GAME_HOVER_ANIM_DURATION := 0.12

func _set_next_game_hover(panel: Panel, hovering: bool) -> void:
	panel.add_theme_stylebox_override(&"panel",
		CareerTheme.panel_style(CareerTheme.PANEL, CareerTheme.POSITIVE, 2) if hovering
		else CareerTheme.panel_style())
	var tween := panel.create_tween()
	tween.tween_property(panel, "scale",
		Vector2.ONE * (NEXT_GAME_HOVER_SCALE if hovering else 1.0), NEXT_GAME_HOVER_ANIM_DURATION)


## A flat tan tile with an icon + label, mouse-clickable only when
## `enabled` (VIEW STATS stays a dimmed, inert lock glyph for now — see
## the header note). Built with a fixed width rather than ActionButton's
## own measure-after-layout trick (character_screen.gd's PLAY button):
## these are short, known labels, and a fixed width keeps the row's
## spacing predictable.
func _build_action_button(text: String, icon_name: StringName, enabled: bool,
		on_pressed: Callable) -> Control:
	var panel := Panel.new()
	panel.custom_minimum_size = Vector2(BUTTON_WIDTH, BUTTON_HEIGHT)
	panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var fill := CareerTheme.PANEL if enabled else CareerTheme.PANEL.darkened(0.35)
	panel.add_theme_stylebox_override(&"panel", CareerTheme.panel_style(fill))
	if enabled:
		panel.mouse_filter = Control.MOUSE_FILTER_STOP
		panel.gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton and event.pressed \
					and event.button_index == MOUSE_BUTTON_LEFT:
				on_pressed.call())
	else:
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 16.0
	row.offset_right = -16.0
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override(&"separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(row)

	var text_colour := CareerTheme.PANEL_TEXT if enabled else Color(CareerTheme.PANEL_TEXT, 0.5)
	var icon := UIIcon.new()
	icon.icon_name = icon_name
	icon.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
	icon.line_colour = text_colour
	row.add_child(icon)
	row.add_child(CareerTheme.label(text, SoftBrutalist.SIZE_LABEL, text_colour,
		SoftBrutalist.WEIGHT_BOLD, 1))

	return panel


## Toggles a full-page roster table reading CareerProfile.roster — a
## plain spreadsheet (#, NAME, POS, HEIGHT, WEIGHT, OVERALL), not a small
## popup card over a dimmed dashboard, per the user's own "basic
## streamlit-like spreadsheet, not a pop up window" request. Built once,
## lazily, then just shown/hidden.
func _on_view_roster_pressed() -> void:
	if _roster_overlay == null:
		_roster_overlay = _build_roster_table()
		_roster_overlay.visible = false   # starts hidden — a fresh node defaults to visible
		add_child(_roster_overlay)
	_roster_overlay.visible = not _roster_overlay.visible


## Column spec for the roster table: label, minimum width, horizontal
## alignment, and the roster-entry key/formatter that fills its cells.
## Table-driven so a column is one more entry here, not a hand-placed
## node — same reasoning character_screen.gd's ATTRIBUTE_ROWS gives for
## its own row list.
const ROSTER_COLUMNS := [
	{"label": "#", "width": 36.0, "align": HORIZONTAL_ALIGNMENT_RIGHT},
	{"label": "NAME", "width": 220.0, "align": HORIZONTAL_ALIGNMENT_LEFT},
	{"label": "POS", "width": 70.0, "align": HORIZONTAL_ALIGNMENT_LEFT},
	{"label": "HEIGHT", "width": 90.0, "align": HORIZONTAL_ALIGNMENT_RIGHT},
	{"label": "WEIGHT", "width": 90.0, "align": HORIZONTAL_ALIGNMENT_RIGHT},
	{"label": "OVERALL", "width": 90.0, "align": HORIZONTAL_ALIGNMENT_RIGHT},
]


func _build_roster_table() -> Control:
	var page := Panel.new()
	page.set_anchors_preset(Control.PRESET_FULL_RECT)
	page.add_theme_stylebox_override(&"panel", CareerTheme.panel_style(CareerTheme.BACKGROUND))
	page.mouse_filter = Control.MOUSE_FILTER_STOP   # a full page under it, not a click-through scrim

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		var value := SCREEN_MARGIN_Y if side in ["top", "bottom"] else SCREEN_MARGIN_X
		margin.add_theme_constant_override(StringName("margin_" + side), int(value))
	page.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", int(BAND_GAP))
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(column)

	var header_row := HBoxContainer.new()
	header_row.add_theme_constant_override(&"separation", 16)
	header_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(header_row)
	header_row.add_child(CareerTheme.label("ROSTER — " + CareerProfile.team_name,
		SoftBrutalist.SIZE_TITLE, CareerTheme.TEXT, SoftBrutalist.WEIGHT_HEAVY))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header_row.add_child(spacer)
	var back_button := _build_action_button("BACK", &"arrow_left", true,
		func() -> void: _roster_overlay.visible = false)
	header_row.add_child(back_button)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	column.add_child(scroll)

	var grid := GridContainer.new()
	grid.columns = ROSTER_COLUMNS.size()
	grid.add_theme_constant_override(&"h_separation", 18)
	grid.add_theme_constant_override(&"v_separation", 8)
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scroll.add_child(grid)

	for col: Dictionary in ROSTER_COLUMNS:
		var heading := CareerTheme.label(col["label"], SoftBrutalist.SIZE_LABEL,
			CareerTheme.TEXT, SoftBrutalist.WEIGHT_BOLD, 1)
		heading.custom_minimum_size.x = col["width"]
		heading.horizontal_alignment = col["align"]
		grid.add_child(heading)

	var sorted_roster := CareerProfile.roster.duplicate()
	sorted_roster.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["number"]) < int(b["number"]))

	for entry: Dictionary in sorted_roster:
		_add_roster_row(grid, entry)

	return page


func _add_roster_row(grid: GridContainer, entry: Dictionary) -> void:
	var role_label: String = ""
	for slot: Dictionary in TeamFormation.SLOTS:
		if slot["role"] == entry["role"]:
			role_label = slot["label"]
			break
	var cells := [
		"%d" % entry["number"],
		String(entry["name"]),
		role_label,
		"%.0f cm" % entry.get("height", Tuning.CHARACTER_HEIGHT_DEFAULT),
		"%.0f kg" % entry.get("weight", 0.5 * (RosterGenerator.WEIGHT_MIN + RosterGenerator.WEIGHT_MAX)),
		"%d" % RosterGenerator.overall(entry),
	]
	for i in ROSTER_COLUMNS.size():
		var col: Dictionary = ROSTER_COLUMNS[i]
		var cell := CareerTheme.label(cells[i], SoftBrutalist.SIZE_BODY, CareerTheme.TEXT)
		cell.custom_minimum_size.x = col["width"]
		cell.horizontal_alignment = col["align"]
		grid.add_child(cell)


## Dims (not a true blur — a semi-transparent scrim, see the plan's own
## "whichever is less code" allowance) the whole dashboard and shows a
## lock glyph with the only action left: MAIN MENU. The scrim's own
## MOUSE_FILTER_STOP already eats every click meant for the content
## underneath, so there's no need to separately disable those buttons.
func _build_locked_overlay() -> void:
	var scrim := Panel.new()
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.add_theme_stylebox_override(&"panel",
		CareerTheme.panel_style(Color(CareerTheme.BACKGROUND, 0.82)))
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(scrim)

	var centre_wrap := CenterContainer.new()
	centre_wrap.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scrim.add_child(centre_wrap)

	var centre := VBoxContainer.new()
	centre.add_theme_constant_override(&"separation", 16)
	centre.alignment = BoxContainer.ALIGNMENT_CENTER
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	centre_wrap.add_child(centre)

	var lock_icon := UIIcon.new()
	lock_icon.icon_name = &"lock"
	lock_icon.custom_minimum_size = Vector2(56.0, 56.0)
	lock_icon.line_colour = CareerTheme.TEXT
	lock_icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	centre.add_child(lock_icon)

	var message := CareerTheme.label("MORE OF THE SEASON IS ON THE WAY",
		SoftBrutalist.SIZE_LABEL, CareerTheme.TEXT, SoftBrutalist.WEIGHT_BOLD, 1)
	message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	centre.add_child(message)

	var menu_button := _build_action_button("MAIN MENU", &"exit", true, _on_main_menu_pressed)
	menu_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	centre.add_child(menu_button)


func _on_main_menu_pressed() -> void:
	SceneWipe.change_scene("res://scenes/ui/main_menu.tscn")


## Pixel-art exclamation mark: a tall stem block over a square dot, both
## solid yellow with a black stroke — drawn rather than imported, same
## "no art pipeline yet" reasoning ui_icon.gd's glyphs already follow.
class ExclamationIcon extends Control:
	const FILL := Color("#F5C518")
	const STROKE := Color.BLACK

	func _init() -> void:
		custom_minimum_size = Vector2(18.0, 18.0)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var stem_w := size.x * 0.34
		var stem := Rect2((size.x - stem_w) * 0.5, size.y * 0.04, stem_w, size.y * 0.58)
		draw_rect(stem, FILL, true)
		draw_rect(stem, STROKE, false, 1.5)
		var dot_size := stem_w
		var dot := Rect2((size.x - dot_size) * 0.5, size.y * 0.78, dot_size, dot_size * 0.85)
		draw_rect(dot, FILL, true)
		draw_rect(dot, STROKE, false, 1.5)
