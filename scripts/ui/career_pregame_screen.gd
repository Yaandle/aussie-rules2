class_name CareerPregameScreen
extends CanvasLayer

## Career mode's pregame screen — reached from the Dashboard's NEXT GAME
## card. A trimmed, re-skinned relative of full_game_pregame_screen.gd:
## the same match-feel settings (PLAYER CONTROL, CAMERA, FORMATION, BALL
## MOVEMENT, DEFENSIVE PRESSURE) plus YOUR POSITION, reusing the exact
## same Settings fields and SettingsScreen.Row cycling class that screen
## already uses — a Career match is still just a Full Game match
## underneath, so there's no reason to invent a second settings surface
## for the same dials. What's dropped: the four decorative locked
## placeholder cards and the two-level horizontal card cursor — this is a
## season fixture you glance at and start, not a settings screen, so a
## plain vertical list (the same keyboard-driven StatRow-style cursor
## character_screen.gd/career_character_screen.gd already use, just
## styled with CareerTheme instead of RetroWindow) is the simpler fit.
##
## CAMERA and CAMERA ZOOM are the rows that change what the left-hand
## preview panel shows: selecting either swaps the formation whiteboard
## for one live CameraModePreview of the selected mode (a real render, not
## a screenshot), headed with that mode's name, with ZOOM and its % right
## underneath. 2026-10-24 playtest: it used to show both modes at once,
## with a grey ZOOM heading that was hard to read and zoom chevrons that
## could only be reached through Godot focus, which nothing on this screen
## ever grabs, so a controller couldn't change zoom at all. Zoom is now a
## normal row in the list (left/right steps it, clamped, no wrap); the
## chevrons stay for the mouse.
##
## YOUR POSITION starts on the Career player's own slot (the position
## picked at character creation, CareerProfile.position) every time this
## screen opens, and stays changeable in both control modes: in SINGLE
## PLAYER it's who you are, in FULL TEAM it's who you start the match on
## (full_game.gd seeds the controlled player from Settings.home_human_slot
## either way). It used to lock in FULL TEAM and read whatever slot the
## quick-play pregame last saved.
##
## START MATCH sets GameState.career_active so full_game.gd knows to pull
## rosters from CareerProfile/the generated opponent instead of the
## generic spawn, and launches the same full_game.tscn Full Game does.

const PLAYER_CONTROL_ROW := 0
const CAMERA_ROW := 1
const CAMERA_ZOOM_ROW := 2
const YOUR_POSITION_ROW := 6

const SCREEN_MARGIN_X := SoftBrutalist.SPACE_6
const SCREEN_MARGIN_Y := SoftBrutalist.SPACE_4
const BAND_GAP := SoftBrutalist.SPACE_4
const ROW_HEIGHT := 44.0
const ROW_PAD := 16.0
const SUB_ROW_INDENT := 28.0
const PREVIEW_SIZE := Vector2(380.0, 460.0)
const CAMERA_FIELD_HEIGHT := 190.0
## A real camera's own aspect, not this panel's own wide/short rect — see
## the AspectRatioContainer each live preview is wrapped in, in
## _build_camera_panel().
const CAMERA_PREVIEW_ASPECT := 16.0 / 9.0
const SELECTED_BORDER_WIDTH := 3

var _settings: Array[SettingsScreen.Row] = []
var _row_panels: Array[Panel] = []
var _row_title_labels: Array[Label] = []
var _row_value_labels: Array[Label] = []
var _start_panel: Panel
var _start_label: Label
var _whiteboard: FormationWhiteboard
var _camera_container: Control
var _camera_panel: PanelContainer
var _camera_heading: Label
var _camera_preview: CameraModePreview
var _zoom_value_label: Label

var _selected := 0
var _busy := false


func _ready() -> void:
	GameState.phase = GameState.Phase.MENU
	var career_slot := RosterGenerator.roster_index_for_role(CareerProfile.roster,
		CareerProfile.position)
	if career_slot >= 0 and Settings.home_human_slot != career_slot:
		Settings.home_human_slot = career_slot
		Settings.save()

	_settings = [
		SettingsScreen.Row.new("PLAYER CONTROL", ["1 PLAYER", "FULL TEAM"],
			Settings.player_control_mode, _set_player_control),
		SettingsScreen.Row.new("CAMERA", ["3RD PERSON", "FULL-SIDE"],
			Settings.full_game_camera_mode, _set_camera_mode),
		SettingsScreen.Row.new("CAMERA ZOOM", _zoom_options(),
			_zoom_index(Settings.camera_zoom), _set_camera_zoom),
		SettingsScreen.Row.new("FORMATION", _formation_options(),
			Settings.home_formation_index, _set_formation),
		SettingsScreen.Row.new("BALL MOVEMENT", ["CORRIDOR", "MUTUAL", "BOUNDARY"],
			Settings.home_ball_movement, _set_ball_movement),
		SettingsScreen.Row.new("DEFENSIVE PRESSURE", ["LOOSE", "BALANCED", "TIGHT"],
			Settings.home_defensive_pressure, _set_defensive_pressure),
		SettingsScreen.Row.new("YOUR POSITION", _your_position_options(),
			Settings.home_human_slot, _set_your_position),
	]

	_build()
	_sync_preview()
	_refresh()


func _formation_options() -> Array[String]:
	var options: Array[String] = []
	for preset: Dictionary in Settings.FORMATION_PRESETS:
		options.append(String(preset["name"]))
	return options


## Same "<n> <label>" form full_game_pregame_screen.gd's own card uses —
## see that file's header comment on why it's a static 18-entry list.
func _your_position_options() -> Array[String]:
	var options: Array[String] = []
	for i in Tuning.TEAM_SIZE:
		options.append("%d %s" % [i + 1, String(TeamFormation.roster_slot(i)["label"])])
	return options


## CAMERA ZOOM's steps, CAM_ZOOM_MIN..CAM_ZOOM_MAX by CAM_ZOOM_STEP, as
## "100%" labels.
func _zoom_options() -> Array[String]:
	var options: Array[String] = []
	var steps := roundi((Tuning.CAM_ZOOM_MAX - Tuning.CAM_ZOOM_MIN) / Tuning.CAM_ZOOM_STEP)
	for i in steps + 1:
		options.append("%d%%" % roundi((Tuning.CAM_ZOOM_MIN + i * Tuning.CAM_ZOOM_STEP) * 100.0))
	return options


func _zoom_index(zoom: float) -> int:
	return clampi(roundi((zoom - Tuning.CAM_ZOOM_MIN) / Tuning.CAM_ZOOM_STEP),
		0, _zoom_options().size() - 1)


## Never locked here any more — see this file's header on YOUR POSITION.
func _your_position_locked() -> bool:
	return false


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
	elif event.is_action_pressed(&"pause") or event.is_action_pressed(&"decline"):
		_exit_to_dashboard()


func _row_count() -> int:
	return _settings.size() + 1   # + START MATCH


func _move(step: int) -> void:
	_selected = (_selected + step + _row_count()) % _row_count()
	_refresh()


func _nudge(direction: int) -> void:
	if _selected >= _settings.size():
		return
	if _selected == YOUR_POSITION_ROW and _your_position_locked():
		return
	if _selected == CAMERA_ZOOM_ROW:
		# Clamped, not wrapped: stepping past 140% shouldn't jump to 80%.
		var row := _settings[CAMERA_ZOOM_ROW]
		if row.index + direction < 0 or row.index + direction >= row.options.size():
			return
	_settings[_selected].cycle(direction)
	if _selected == PLAYER_CONTROL_ROW:
		_refresh()   # PLAYER CONTROL changing may lock/unlock YOUR POSITION
	else:
		_refresh_row(_selected)
	_sync_preview()


func _activate() -> void:
	if _selected == _settings.size():
		_start_match()


func _set_player_control(index: int) -> void:
	Settings.player_control_mode = index as Settings.PlayerControlMode
	Settings.save()


func _set_camera_mode(index: int) -> void:
	Settings.full_game_camera_mode = index as Settings.FullGameCameraMode
	Settings.save()


func _set_camera_zoom(index: int) -> void:
	Settings.camera_zoom = Tuning.CAM_ZOOM_MIN + index * Tuning.CAM_ZOOM_STEP
	Settings.save()


func _set_formation(index: int) -> void:
	Settings.home_formation_index = index
	Settings.save()


func _set_ball_movement(index: int) -> void:
	Settings.home_ball_movement = index as Settings.BallMovementPreference
	Settings.save()


func _set_defensive_pressure(index: int) -> void:
	Settings.home_defensive_pressure = index as Settings.DefensivePressure
	Settings.save()


func _set_your_position(index: int) -> void:
	Settings.home_human_slot = index
	Settings.save()


func _start_match() -> void:
	if _busy:
		return
	_busy = true
	GameState.career_active = true
	SceneWipe.change_scene("res://scenes/modes/full_game.tscn")


func _exit_to_dashboard() -> void:
	if _busy:
		return
	_busy = true
	SceneWipe.change_scene("res://scenes/ui/career_dashboard_screen.tscn")


# ── Build ────────────────────────────────────────────────────────────

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
	var opponent := "SEASON COMPLETE" if CareerProfile.season_complete() \
		else CareerProfile.current_fixture()
	header.add_child(CareerTheme.label(opponent, SoftBrutalist.SIZE_TITLE,
		CareerTheme.TEXT, SoftBrutalist.WEIGHT_HEAVY))
	header.add_child(CareerTheme.label("ROUND %d OF %d — %s" % [
		mini(CareerProfile.games_played + 1, CareerProfile.fixtures.size()),
		CareerProfile.fixtures.size(), CareerProfile.team_name],
		SoftBrutalist.SIZE_BODY, CareerTheme.TEXT_MUTED))
	column.add_child(header)

	var body := HBoxContainer.new()
	body.add_theme_constant_override(&"separation", int(BAND_GAP))
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(body)

	body.add_child(_build_preview_panel())
	body.add_child(_build_settings_column())


func _build_preview_panel() -> Control:
	var panel := Panel.new()
	panel.custom_minimum_size = PREVIEW_SIZE
	panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	panel.add_theme_stylebox_override(&"panel", CareerTheme.panel_style())
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var inner := MarginContainer.new()
	inner.set_anchors_preset(Control.PRESET_FULL_RECT)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		inner.add_theme_constant_override(StringName("margin_" + side), 16)
	panel.add_child(inner)

	_whiteboard = FormationWhiteboard.new()
	_whiteboard.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(_whiteboard)

	# Same full-rect inset as _whiteboard above — MarginContainer gives
	# every child the same inset rect, so the two can share this one
	# container and just toggle `visible` rather than needing a second
	# margin wrapper.
	_camera_container = VBoxContainer.new()
	_camera_container.add_theme_constant_override(&"separation", 12)
	_camera_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_camera_container.visible = false
	inner.add_child(_camera_container)

	_build_camera_panel(_camera_container)

	return panel


## "ZOOM" + "‹  100%  ›" along the bottom of the camera panel, in the tan
## panel's own dark ink (PANEL_TEXT) rather than the grey TEXT_MUTED it
## used to sit in on the page background.
func _build_zoom_row(parent: Control) -> Label:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override(&"separation", 10)
	parent.add_child(row)

	row.add_child(CareerTheme.label("ZOOM", SoftBrutalist.SIZE_LABEL,
		CareerTheme.PANEL_TEXT, SoftBrutalist.WEIGHT_BOLD, 1))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(spacer)

	row.add_child(_build_zoom_arrow("‹", -1))
	var value := CareerTheme.label("", SoftBrutalist.SIZE_BODY, CareerTheme.PANEL_TEXT,
		SoftBrutalist.WEIGHT_BOLD)
	value.custom_minimum_size.x = 56.0
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(value)
	row.add_child(_build_zoom_arrow("›", 1))
	return value


## One clickable chevron, same "a plain Control with gui_input, not a real
## Button" shape every interactive element on this screen already uses
## (_on_next_game_gui_input and friends over in career_dashboard_screen.gd
## follow the identical pattern).
## Mouse only: keyboard and controller step zoom through the CAMERA ZOOM
## row instead (see this file's header).
func _build_zoom_arrow(glyph: String, step: int) -> Control:
	var hit := Control.new()
	hit.custom_minimum_size = Vector2(28.0, 28.0)
	hit.mouse_filter = Control.MOUSE_FILTER_STOP
	hit.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	hit.gui_input.connect(_on_zoom_arrow_input.bind(step))

	var label := CareerTheme.label(glyph, SoftBrutalist.SIZE_BODY, CareerTheme.PANEL_TEXT,
		SoftBrutalist.WEIGHT_BOLD)
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hit.add_child(label)
	return hit


func _on_zoom_arrow_input(event: InputEvent, step: int) -> void:
	if not (event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT):
		return
	var row := _settings[CAMERA_ZOOM_ROW]
	var index := clampi(row.index + step, 0, row.options.size() - 1)
	if index == row.index:
		return
	row.index = index
	_set_camera_zoom(index)
	_refresh_row(CAMERA_ZOOM_ROW)
	_sync_camera_preview()


## The one camera panel: the selected mode's name, its live render, and
## ZOOM underneath. A PanelContainer so it sizes to its contents (a plain
## Panel in a container collapses to zero height; see career_match_end_
## screen.gd's card).
func _build_camera_panel(parent: Control) -> void:
	_camera_panel = PanelContainer.new()
	_camera_panel.add_theme_stylebox_override(&"panel", CareerTheme.panel_style())
	_camera_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(_camera_panel)

	var inner := MarginContainer.new()
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		inner.add_theme_constant_override(StringName("margin_" + side), 12)
	_camera_panel.add_child(inner)

	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 10)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(col)
	_camera_heading = CareerTheme.label("", SoftBrutalist.SIZE_LABEL,
		CareerTheme.PANEL_TEXT, SoftBrutalist.WEIGHT_BOLD, 1)
	col.add_child(_camera_heading)

	# Wrapped in an AspectRatioContainer rather than stretched to fill the
	# panel's own rect (user report: "scale the resolution but maintain
	# aspect ratio").
	var aspect := AspectRatioContainer.new()
	aspect.custom_minimum_size = Vector2(0.0, CAMERA_FIELD_HEIGHT)
	aspect.ratio = CAMERA_PREVIEW_ASPECT
	aspect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(aspect)

	_camera_preview = CameraModePreview.new()
	_camera_preview.zoom = Settings.camera_zoom
	_camera_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	aspect.add_child(_camera_preview)

	_zoom_value_label = _build_zoom_row(col)


func _build_settings_column() -> Control:
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 10)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.custom_minimum_size = Vector2(380.0, 0.0)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE

	for i in _settings.size():
		var row_panel := _build_setting_row(_settings[i])
		if i == CAMERA_ZOOM_ROW:
			column.add_child(_indent_sub_row(row_panel, i))
		else:
			column.add_child(row_panel)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(spacer)

	column.add_child(_build_start_row())

	# DeviceHintBar, not a static caption (ui_audit.md finding #1/#2 — this
	# line never changed with the last-used device, and used a KEY/A-style
	# label — "A / D" — which means two different things on the two devices
	# the project otherwise treats as equivalent: the A/D *keys*, not the
	# gamepad's A *button*).
	var hints := DeviceHintBar.new()
	column.add_child(hints)
	hints.set_hint_sets({
		InputManager.Device.KEYBOARD: [
			{"keys": "W / S", "label": "Select"},
			{"keys": "A / D", "label": "Adjust"},
			{"keys": "Enter", "label": "Confirm"},
			{"keys": "Esc", "label": "Back"},
		],
		InputManager.Device.GAMEPAD: [
			{"keys": "D-Pad ↕", "label": "Select"},
			{"keys": "D-Pad ↔", "label": "Adjust"},
			{"keys": "A", "label": "Confirm"},
			{"keys": "B", "label": "Back"},
		],
	})

	return column


func _build_setting_row(row: SettingsScreen.Row) -> Panel:
	var panel := Panel.new()
	panel.custom_minimum_size = Vector2(0.0, ROW_HEIGHT)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override(&"panel", CareerTheme.panel_style())

	var inner := MarginContainer.new()
	inner.set_anchors_preset(Control.PRESET_FULL_RECT)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right"]:
		inner.add_theme_constant_override(StringName("margin_" + side), int(ROW_PAD))
	panel.add_child(inner)

	var hb := HBoxContainer.new()
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(hb)

	var title_label := CareerTheme.label(row.title, SoftBrutalist.SIZE_LABEL,
		CareerTheme.PANEL_TEXT, SoftBrutalist.WEIGHT_BOLD, 1)
	hb.add_child(title_label)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(spacer)

	var value_label := CareerTheme.label(row.value(), SoftBrutalist.SIZE_LABEL,
		CareerTheme.PANEL_TEXT, SoftBrutalist.WEIGHT_BOLD)
	hb.add_child(value_label)

	_row_panels.append(panel)
	_row_title_labels.append(title_label)
	_row_value_labels.append(value_label)
	return panel


## ZOOM reads as a sub-option of CAMERA (playtest: "an indented smaller
## option under camera, like a smaller sub header... as large as the other
## buttons"): same row height, inset by SUB_ROW_INDENT, with a smaller
## title. Navigation is unchanged — it's still an ordinary row index.
func _indent_sub_row(row_panel: Panel, index: int) -> Control:
	var title := _row_title_labels[index]
	title.text = "ZOOM"
	title.add_theme_font_size_override(&"font_size", SoftBrutalist.SIZE_CAPTION)
	var indent := MarginContainer.new()
	indent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	indent.add_theme_constant_override(&"margin_left", int(SUB_ROW_INDENT))
	indent.add_child(row_panel)
	return indent


func _build_start_row() -> Panel:
	_start_panel = Panel.new()
	_start_panel.custom_minimum_size = Vector2(0.0, ROW_HEIGHT + 8.0)
	_start_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_start_panel.add_theme_stylebox_override(&"panel", CareerTheme.panel_style(CareerTheme.POSITIVE))

	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_start_panel.add_child(centre)

	_start_label = CareerTheme.label("START MATCH", SoftBrutalist.SIZE_LABEL,
		CareerTheme.TEXT, SoftBrutalist.WEIGHT_BOLD, 1)
	centre.add_child(_start_label)

	return _start_panel


# ── Refresh ──────────────────────────────────────────────────────────

func _sync_preview() -> void:
	if is_instance_valid(_whiteboard):
		_whiteboard.formation_index = Settings.home_formation_index
		_whiteboard.ball_movement = Settings.home_ball_movement
		_whiteboard.defensive_pressure = Settings.home_defensive_pressure
		# See full_game_pregame_screen.gd's own _sync_preview() comment — YOUR
		# POSITION's index is a ROSTER index, FormationWhiteboard.highlighted_
		# slot wants a raw TeamFormation.SLOTS index, resolved through
		# ROSTER_ORDER exactly the same way.
		_whiteboard.highlighted_slot = TeamFormation.ROSTER_ORDER[Settings.home_human_slot]
	_sync_camera_preview()


## The camera panel follows Settings: heading and render for the selected
## mode, zoom on both the render and the % readout. The panel takes the
## selected-row stroke while CAMERA or CAMERA ZOOM has the cursor.
func _sync_camera_preview() -> void:
	if not is_instance_valid(_camera_panel):
		return
	var full_side := Settings.full_game_camera_mode == Settings.FullGameCameraMode.FULL_SIDE
	_camera_heading.text = "FULL-SIDE" if full_side else "3RD PERSON"
	_camera_preview.mode = BroadcastCamera.Mode.FULL_SIDE if full_side else BroadcastCamera.Mode.CHASE
	_camera_preview.zoom = Settings.camera_zoom
	_zoom_value_label.text = "%d%%" % roundi(Settings.camera_zoom * 100.0)
	var zoom_selected := _selected == CAMERA_ZOOM_ROW
	_zoom_value_label.add_theme_color_override(&"font_color",
		CareerTheme.POSITIVE if zoom_selected else CareerTheme.PANEL_TEXT)
	_camera_panel.add_theme_stylebox_override(&"panel",
		CareerTheme.panel_style(CareerTheme.PANEL, CareerTheme.POSITIVE, SELECTED_BORDER_WIDTH))


## Swaps the left-hand panel to the camera panel while CAMERA or CAMERA
## ZOOM holds the cursor, and back to the formation whiteboard otherwise
## — same swap full_game_pregame_screen.gd's own _set_camera_preview_
## active() does.
func _set_camera_preview_active(active: bool) -> void:
	if is_instance_valid(_whiteboard):
		_whiteboard.visible = not active
	if is_instance_valid(_camera_container):
		_camera_container.visible = active


func _refresh() -> void:
	for i in _settings.size():
		_refresh_row(i)
	var start_selected := _selected == _settings.size()
	_start_panel.add_theme_stylebox_override(&"panel",
		CareerTheme.panel_style(CareerTheme.POSITIVE, Color.BLACK,
			SELECTED_BORDER_WIDTH if start_selected else 0))
	_set_camera_preview_active(_selected == CAMERA_ROW or _selected == CAMERA_ZOOM_ROW)
	_sync_camera_preview()


func _refresh_row(i: int) -> void:
	var row := _settings[i]
	var locked := i == YOUR_POSITION_ROW and _your_position_locked()
	var selected := i == _selected
	var fill := CareerTheme.PANEL.darkened(0.3) if locked else CareerTheme.PANEL
	_row_panels[i].add_theme_stylebox_override(&"panel",
		CareerTheme.panel_style(fill, CareerTheme.POSITIVE, SELECTED_BORDER_WIDTH if selected else 0))
	var text_colour := Color(CareerTheme.PANEL_TEXT, 0.5 if locked else 1.0)
	_row_title_labels[i].modulate = text_colour
	_row_value_labels[i].text = row.value() + ("  •  LOCKED" if locked else "")
	_row_value_labels[i].modulate = text_colour
