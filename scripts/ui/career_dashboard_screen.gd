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
	panel.add_theme_stylebox_override(&"panel", CareerTheme.panel_style())
	if not _locked and not CareerProfile.season_complete():
		panel.mouse_filter = Control.MOUSE_FILTER_STOP
		panel.gui_input.connect(_on_next_game_gui_input)
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
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		SceneWipe.change_scene("res://scenes/ui/career_pregame_screen.tscn")


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


## Toggles a roster overlay reading CareerProfile.roster, grouped by
## TeamFormation line (same grouping team_list_screen.gd's own legend
## uses) — built once, lazily, then just shown/hidden.
func _on_view_roster_pressed() -> void:
	if _roster_overlay == null:
		_roster_overlay = _build_roster_overlay()
		_roster_overlay.visible = false   # starts hidden — a fresh node defaults to visible
		add_child(_roster_overlay)
	_roster_overlay.visible = not _roster_overlay.visible


func _build_roster_overlay() -> Control:
	var scrim := Panel.new()
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.add_theme_stylebox_override(&"panel", CareerTheme.panel_style(Color(0.0, 0.0, 0.0, 0.72)))
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	scrim.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			scrim.visible = false)

	var card := Panel.new()
	card.anchor_left = 0.5
	card.anchor_right = 0.5
	card.anchor_top = 0.5
	card.anchor_bottom = 0.5
	card.offset_left = -220.0
	card.offset_right = 220.0
	card.offset_top = -280.0
	card.offset_bottom = 280.0
	card.add_theme_stylebox_override(&"panel", CareerTheme.panel_style())
	# STOP, not IGNORE — otherwise a click anywhere inside the card still
	# bubbles up to the scrim's own gui_input and closes the overlay.
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	scrim.add_child(card)

	var inner := MarginContainer.new()
	inner.set_anchors_preset(Control.PRESET_FULL_RECT)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		inner.add_theme_constant_override(StringName("margin_" + side), 20)
	card.add_child(inner)

	var scroll := ScrollContainer.new()
	scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	inner.add_child(scroll)

	var list := VBoxContainer.new()
	list.add_theme_constant_override(&"separation", 6)
	list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	list.add_child(CareerTheme.label("ROSTER — " + CareerProfile.team_name,
		SoftBrutalist.SIZE_LABEL, CareerTheme.PANEL_TEXT, SoftBrutalist.WEIGHT_BOLD))

	var role_label := {}
	var role_line := {}
	for slot: Dictionary in TeamFormation.SLOTS:
		role_label[slot["role"]] = slot["label"]
		role_line[slot["role"]] = slot["line"]

	for line_index in TeamFormation.LINE_NAMES.size():
		var any_in_line := false
		for entry: Dictionary in CareerProfile.roster:
			if role_line.get(entry["role"], -1) != line_index:
				continue
			if not any_in_line:
				list.add_child(CareerTheme.label(TeamFormation.LINE_NAMES[line_index],
					SoftBrutalist.SIZE_LABEL, CareerTheme.PANEL_TEXT, SoftBrutalist.WEIGHT_BOLD))
				any_in_line = true
			var row_text := "%s   %s   #%d" % [
				role_label.get(entry["role"], ""), entry["name"], entry["number"]]
			list.add_child(CareerTheme.label(row_text, SoftBrutalist.SIZE_BODY, CareerTheme.PANEL_TEXT))

	return scrim


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
