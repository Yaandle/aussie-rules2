class_name CareerDashboardScreen
extends CanvasLayer

## Career mode's home screen — reached after character creation, after
## every full-time screen, and from the main menu's CAREER card whenever a
## career is in progress. Left-anchored, not the centred
## layout main_menu.gd/the rest of the front end uses (the user's own
## note on this: "not everything in our code is centred to avoid ai
## look") — this is the one screen in the whole plan that note actually
## applies to, see career_character_screen.gd's sibling phases for why it
## doesn't apply there too.
##
## The NEXT GAME card walks the season round by round into the Career
## pregame; once the last round is in it becomes SEASON COMPLETE and opens
## the Season Summary (career_season_summary_screen.gd), which starts the
## next season. The league ladder sits on the right (CareerLadderTable),
## with a green line under the promotion places. VIEW ROSTER is an overlay
## reading CareerProfile.roster, VIEW STATS reopens the last full-time
## result (career_match_end_screen.gd, reading CareerProfile.last_result;
## a lock until a match has been played). The lock screen that used to
## follow game 1 is gone.
##
## NEW CAREER is the only way to start over (the main menu's CAREER card
## always continues). It asks first (_build_new_career_confirm()); nothing
## is replaced until CONFIRM on the creation screen, and backing out of
## that screen comes back here.
##
## F8 in a debug build sims the current round (CareerProfile.
## sim_current_round()) — dev-only, for running seasons through quickly.

const SCREEN_MARGIN_X := SoftBrutalist.SPACE_6
const SCREEN_MARGIN_Y := SoftBrutalist.SPACE_4
const BAND_GAP := SoftBrutalist.SPACE_4
const CARD_PAD := 20.0
const BUTTON_HEIGHT := 48.0
const BUTTON_WIDTH := 200.0
const ICON_SIZE := 22.0
## Whatever's left of the 1280 design width beside the left column (the
## three 200 px buttons and their gaps). Phase 3's narrower button row
## frees more.
const LADDER_WIDTH := 470.0

const DASHBOARD_SCENE := "res://scenes/ui/career_dashboard_screen.tscn"
const SUMMARY_SCENE := "res://scenes/ui/career_season_summary_screen.tscn"

var _roster_overlay: Control
var _roster_back_button: Control
var _view_roster_button: Control
var _new_career_button: Control
var _confirm_overlay: Control
var _confirm_cancel_button: Control


func _ready() -> void:
	_build()


func _unhandled_input(event: InputEvent) -> void:
	if _is_dev_sim_press(event):
		CareerProfile.sim_current_round()
		SceneWipe.change_scene(DASHBOARD_SCENE)
		return
	if not (event.is_action_pressed(&"pause") or event.is_action_pressed(&"decline")):
		return
	if is_instance_valid(_confirm_overlay) and _confirm_overlay.visible:
		_close_new_career_confirm()
		return
	# The roster table is its own page with its own BACK control (see
	# _build_roster_table()) — Esc/B closing it straight to the main menu
	# instead of back to the dashboard would contradict the button sitting
	# right there on screen (ui_audit.md finding #3's fix needs this to
	# actually be true, not just claimed in the hint bar).
	if is_instance_valid(_roster_overlay) and _roster_overlay.visible:
		_roster_overlay.visible = false
		if is_instance_valid(_view_roster_button):
			_view_roster_button.grab_focus.call_deferred()
		return
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
	header.add_child(CareerTheme.label("%s · SEASON %d — %s" % [
		CareerSeason.league_name(CareerProfile.league_index), CareerProfile.season_index + 1,
		CareerProfile.player_name], SoftBrutalist.SIZE_BODY, CareerTheme.TEXT_MUTED))

	var body := HBoxContainer.new()
	body.add_theme_constant_override(&"separation", int(BAND_GAP))
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(body)

	var left := VBoxContainer.new()
	left.add_theme_constant_override(&"separation", int(BAND_GAP))
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(left)
	body.add_child(_build_ladder_column())

	var next_game_card := _build_next_game_card()
	left.add_child(next_game_card)

	var button_row := HBoxContainer.new()
	button_row.add_theme_constant_override(&"separation", int(SoftBrutalist.SPACE_4))
	button_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.add_child(button_row)
	var view_roster_button := _build_action_button("VIEW ROSTER", &"gear", true,
		_on_view_roster_pressed)
	_view_roster_button = view_roster_button
	button_row.add_child(view_roster_button)
	button_row.add_child(_build_view_stats_button())
	_new_career_button = _build_new_career_button()
	button_row.add_child(_new_career_button)

	# Hint bar — no control legend existed on this screen at all
	# (ui_audit.md finding #2, missed by the audit's own file list but the
	# same gap every other screen there had).
	var hints := DeviceHintBar.new()
	left.add_child(hints)
	var keyboard_hints: Array = [
		{"keys": "Tab", "label": "Select"},
		{"keys": "Enter", "label": "Confirm"},
		{"keys": "Esc", "label": "Main menu"},
	]
	if OS.is_debug_build():
		keyboard_hints.append({"keys": "F8", "label": "Sim round (dev)"})
	hints.set_hint_sets({
		InputManager.Device.KEYBOARD: keyboard_hints,
		InputManager.Device.GAMEPAD: [
			{"keys": "D-Pad", "label": "Select"},
			{"keys": "A", "label": "Confirm"},
			{"keys": "B", "label": "Main menu"},
		],
	})

	# Explicit default focus (mandatory per the UI brief): the NEXT GAME card,
	# which is live in every state now — the next round, or the season
	# summary once the season is over.
	next_game_card.grab_focus.call_deferred()


## "LADDER" over the league table, your row tinted and the promotion places
## (or, in the top league, first place) above a green line.
func _build_ladder_column() -> Control:
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 10)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(CareerTheme.label("LADDER — %s" % CareerSeason.league_name(CareerProfile.league_index),
		SoftBrutalist.SIZE_LABEL, CareerTheme.TEXT, SoftBrutalist.WEIGHT_BOLD, 1))
	var cut := 1 if CareerSeason.is_top_league(CareerProfile.league_index) \
		else Tuning.CAREER_PROMOTION_PLACES
	column.add_child(CareerLadderTable.build(CareerProfile.ladder(), LADDER_WIDTH, cut))
	return column


func _is_dev_sim_press(event: InputEvent) -> bool:
	return OS.is_debug_build() and event is InputEventKey and event.pressed \
		and not event.echo and (event as InputEventKey).keycode == KEY_F8


## The "NEXT GAME" card: a yellow/black pixel-art exclamation mark beside
## the heading (see ExclamationIcon below), the round and the upcoming
## fixture's generated opponent name, and a click-through to the Career
## pregame screen — a plain Panel with gui_input wired directly, same
## mechanism character_screen.gd's PLAY/CUSTOMISE buttons already proved
## works. After the last round it reads SEASON COMPLETE with your finish
## and what it means, and clicks through to the Season Summary instead.
func _build_next_game_card() -> Control:
	var panel := Panel.new()
	panel.custom_minimum_size = Vector2(520.0, 132.0)
	panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	# Scale grows from the card's own centre, not its top-left corner — see
	# _set_next_game_hover().
	panel.pivot_offset = panel.custom_minimum_size * 0.5
	panel.add_theme_stylebox_override(&"panel", CareerTheme.panel_style())
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

	# Icon to the right of the "NEXT GAME" label, not the left — label added
	# to the row first so the icon trails it.
	var heading_row := HBoxContainer.new()
	heading_row.add_theme_constant_override(&"separation", 8)
	heading_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_child(heading_row)
	var season_over := CareerProfile.season_complete()
	var heading := "SEASON COMPLETE" if season_over else "NEXT GAME · ROUND %d OF %d" % [
		CareerProfile.games_played + 1, CareerProfile.season_length()]
	heading_row.add_child(CareerTheme.label(heading, SoftBrutalist.SIZE_LABEL, CareerTheme.PANEL_TEXT,
		SoftBrutalist.WEIGHT_BOLD, 1))
	var icon := ExclamationIcon.new()
	heading_row.add_child(icon)

	var title := "Finished %s" % CareerSeason.ordinal(CareerProfile.ladder_position()) if season_over \
		else CareerProfile.current_fixture()
	rows.add_child(CareerTheme.label(title, SoftBrutalist.SIZE_TITLE, CareerTheme.PANEL_TEXT,
		SoftBrutalist.WEIGHT_HEAVY))
	var hint_text := "%s — click for the season summary" % CareerProfile.season_outcome_text() \
		if season_over \
		else "Click to set up the match"
	rows.add_child(CareerTheme.label(hint_text, SoftBrutalist.SIZE_BODY, CareerTheme.PANEL_TEXT.lightened(0.3)))

	return panel


func _on_next_game_gui_input(event: InputEvent) -> void:
	var clicked: bool = event is InputEventMouseButton and event.pressed \
		and event.button_index == MOUSE_BUTTON_LEFT
	# Control.gui_input also receives key/joypad input once the control has
	# focus (not just mouse events inside its rect) — see the focus_mode
	# this card now sets in _build_next_game_card() — so "confirm" (A on a
	# pad) activates it the same way a click does, for the gamepad
	# navigation that focus_mode exists for in the first place.
	if clicked or event.is_action_pressed(&"confirm"):
		SceneWipe.change_scene(SUMMARY_SCENE if CareerProfile.season_complete()
			else "res://scenes/ui/career_pregame_screen.tscn")


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
## `enabled` (VIEW STATS is a dimmed, inert lock glyph until a match has
## been played — see the header note). Built with a fixed width rather than ActionButton's
## own measure-after-layout trick (character_screen.gd's PLAY button):
## these are short, known labels, and a fixed width keeps the row's
## spacing predictable.
##
## Real Control focus (FOCUS_ALL) when enabled, same treatment
## _build_next_game_card() already gives its own card — before this, VIEW
## ROSTER, the roster table's BACK, and the old lock screen's MAIN MENU were
## all mouse-only with no way for a keyboard/gamepad player to reach them
## at all (ui_audit.md finding #3).
func _build_action_button(text: String, icon_name: StringName, enabled: bool,
		on_pressed: Callable) -> Control:
	var panel := Panel.new()
	panel.custom_minimum_size = Vector2(BUTTON_WIDTH, BUTTON_HEIGHT)
	panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var fill := CareerTheme.PANEL if enabled else CareerTheme.PANEL.darkened(0.35)
	panel.add_theme_stylebox_override(&"panel", CareerTheme.panel_style(fill))
	if enabled:
		panel.mouse_filter = Control.MOUSE_FILTER_STOP
		panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		panel.gui_input.connect(func(event: InputEvent) -> void:
			if (event is InputEventMouseButton and event.pressed \
					and event.button_index == MOUSE_BUTTON_LEFT) \
					or event.is_action_pressed(&"confirm"):
				on_pressed.call())
		panel.focus_mode = Control.FOCUS_ALL
		panel.add_theme_stylebox_override(&"focus", StyleBoxEmpty.new())
		# Same green stroke as the NEXT GAME card's hover (_set_next_game_
		# hover), so every live control on this screen highlights alike
		# (playtest: VIEW ROSTER's black stroke didn't match).
		var hover_style := CareerTheme.panel_style(fill.lightened(0.12), CareerTheme.POSITIVE, 2)
		var idle_style := CareerTheme.panel_style(fill)
		panel.mouse_entered.connect(func() -> void:
			panel.add_theme_stylebox_override(&"panel", hover_style))
		panel.mouse_exited.connect(func() -> void:
			if not panel.has_focus():
				panel.add_theme_stylebox_override(&"panel", idle_style))
		panel.focus_entered.connect(func() -> void:
			panel.add_theme_stylebox_override(&"panel", hover_style))
		panel.focus_exited.connect(func() -> void:
			panel.add_theme_stylebox_override(&"panel", idle_style))
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
	# Explicit focus on whichever page is now showing (mandatory per the UI
	# brief) — a keyboard/gamepad player who just opened or closed the
	# roster table otherwise has nothing focused at all to pick up from.
	if _roster_overlay.visible and is_instance_valid(_roster_back_button):
		_roster_back_button.grab_focus.call_deferred()
	elif not _roster_overlay.visible and is_instance_valid(_view_roster_button):
		_view_roster_button.grab_focus.call_deferred()


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
		func() -> void:
			_roster_overlay.visible = false
			if is_instance_valid(_view_roster_button):
				_view_roster_button.grab_focus.call_deferred())
	_roster_back_button = back_button
	header_row.add_child(back_button)

	var hints := DeviceHintBar.new()
	column.add_child(hints)
	hints.set_hint_sets({
		InputManager.Device.KEYBOARD: [{"keys": "Esc", "label": "Back"}],
		InputManager.Device.GAMEPAD: [{"keys": "B", "label": "Back"}],
	})

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


## Live once a Career match has finished (CareerProfile.last_result), a
## lock glyph before that.
func _build_view_stats_button() -> Control:
	var has_result := not CareerProfile.last_result.is_empty()
	return _build_action_button("VIEW STATS", &"goalpost" if has_result else &"lock",
		has_result, _on_view_stats_pressed)


func _build_new_career_button() -> Control:
	return _build_action_button("NEW CAREER", &"figure", true, _open_new_career_confirm)


func _open_new_career_confirm() -> void:
	if _confirm_overlay == null:
		_confirm_overlay = _build_new_career_confirm()
		add_child(_confirm_overlay)
	# Re-added last so it draws over the roster page as well.
	move_child(_confirm_overlay, get_child_count() - 1)
	_confirm_overlay.visible = true
	_confirm_cancel_button.grab_focus.call_deferred()


func _close_new_career_confirm() -> void:
	_confirm_overlay.visible = false
	if is_instance_valid(_new_career_button):
		_new_career_button.grab_focus.call_deferred()


## "Start a new career?" over a near-opaque scrim, CANCEL focused by
## default so a stray A press can't throw a season away. Focus neighbours
## are pinned to the two buttons: Control focus traversal ignores the
## scrim's mouse filter, so a D-pad press would otherwise walk off onto the
## dashboard underneath.
func _build_new_career_confirm() -> Control:
	var scrim := Panel.new()
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.add_theme_stylebox_override(&"panel",
		CareerTheme.panel_style(Color(CareerTheme.BACKGROUND, 0.92)))
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP

	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scrim.add_child(centre)

	var card := PanelContainer.new()
	card.add_theme_stylebox_override(&"panel",
		CareerTheme.panel_style(CareerTheme.BACKGROUND, CareerTheme.PANEL, 2))
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	centre.add_child(card)

	var inner := MarginContainer.new()
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		inner.add_theme_constant_override(StringName("margin_" + side), int(CARD_PAD + 8.0))
	card.add_child(inner)

	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 16)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(column)

	column.add_child(CareerTheme.label("START A NEW CAREER?", SoftBrutalist.SIZE_LABEL,
		CareerTheme.TEXT, SoftBrutalist.WEIGHT_BOLD, 1))
	var body := CareerTheme.label(
		"This replaces %s's career: the roster, the fixture and every result so far." \
			% CareerProfile.player_name,
		SoftBrutalist.SIZE_BODY, CareerTheme.TEXT_MUTED)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size.x = BUTTON_WIDTH * 2.0 + SoftBrutalist.SPACE_4
	column.add_child(body)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override(&"separation", int(SoftBrutalist.SPACE_4))
	actions.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(actions)
	_confirm_cancel_button = _build_action_button("CANCEL", &"arrow_left", true,
		_close_new_career_confirm)
	actions.add_child(_confirm_cancel_button)
	var start_button := _build_action_button("START NEW", &"figure", true, _on_start_new_career)
	actions.add_child(start_button)

	for pair: Array in [[_confirm_cancel_button, start_button], [start_button, _confirm_cancel_button]]:
		var button: Control = pair[0]
		var other: NodePath = button.get_path_to(pair[1])
		var own: NodePath = button.get_path_to(button)
		button.focus_neighbor_left = other
		button.focus_neighbor_right = other
		button.focus_neighbor_top = own
		button.focus_neighbor_bottom = own
		button.focus_next = other
		button.focus_previous = other
	return scrim


func _on_start_new_career() -> void:
	SceneWipe.change_scene("res://scenes/ui/career_character_screen.tscn")


func _on_view_stats_pressed() -> void:
	SceneWipe.change_scene("res://scenes/ui/career_match_end_screen.tscn")


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
