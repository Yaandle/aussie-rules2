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
## CAMERA is the one row that changes what the left-hand preview panel
## shows: selecting it swaps the formation whiteboard out for both camera
## modes live at once (3RD PERSON and FULL-SIDE, each a real
## CameraModePreview render rather than the static screenshots this used
## to show — user ask: "update from the screenshot to a live rendering of
## the field"), the active one bordered — "both options side by side",
## not a one-at-a-time picker, since this panel has no second "open"
## cursor level to toggle between them. A ZOOM row sits above both panels,
## the one setting adjustable directly here rather than through a row on
## the right (see _build_zoom_row()).
##
## YOUR POSITION locks (dimmed, A/D a no-op) whenever PLAYER CONTROL is
## FULL TEAM, same rule full_game_pregame_screen.gd's own _update_your_
## position_lock() enforces — home_human_slot only matters in SINGLE
## PLAYER mode.
##
## START MATCH sets GameState.career_active so full_game.gd knows to pull
## rosters from CareerProfile/the generated opponent instead of the
## generic spawn, and launches the same full_game.tscn Full Game does.

const PLAYER_CONTROL_ROW := 0
const CAMERA_ROW := 1
const YOUR_POSITION_ROW := 5

const SCREEN_MARGIN_X := SoftBrutalist.SPACE_6
const SCREEN_MARGIN_Y := SoftBrutalist.SPACE_4
const BAND_GAP := SoftBrutalist.SPACE_4
const ROW_HEIGHT := 44.0
const ROW_PAD := 16.0
const PREVIEW_SIZE := Vector2(380.0, 460.0)
const CAMERA_PANEL_HEIGHT := 190.0
const CAMERA_FIELD_HEIGHT := 134.0
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
var _camera_panel_third_person: Panel
var _camera_panel_full_side: Panel
var _camera_preview_third_person: CameraModePreview
var _camera_preview_full_side: CameraModePreview
var _zoom_value_label: Label

var _selected := 0
var _busy := false


func _ready() -> void:
	GameState.phase = GameState.Phase.MENU

	_settings = [
		SettingsScreen.Row.new("PLAYER CONTROL", ["1 PLAYER", "FULL TEAM"],
			Settings.player_control_mode, _set_player_control),
		SettingsScreen.Row.new("CAMERA", ["3RD PERSON", "FULL-SIDE"],
			Settings.full_game_camera_mode, _set_camera_mode),
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


func _your_position_locked() -> bool:
	return Settings.player_control_mode != Settings.PlayerControlMode.SINGLE_PLAYER


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

	# ZOOM, top-left of this window above the two live panels — same
	# "heading + options to change" language the row list to the right
	# already uses (user ask: "have it look similar to the other options
	# where I have the heading and options to change in the top left of
	# the main large window"). The one setting adjustable directly here
	# rather than through a row on the right.
	_zoom_value_label = _build_zoom_row(_camera_container)

	_camera_panel_third_person = _build_camera_panel(_camera_container, "3RD PERSON", false)
	_camera_panel_full_side = _build_camera_panel(_camera_container, "FULL-SIDE", true)

	return panel


## "ZOOM" heading + "‹  100%  ›" value row, CareerTheme-styled (this
## screen's own palette, not RetroWindow/SoftBrutalist's — see this
## file's header on why Career reads as its own visual family).
func _build_zoom_row(parent: Control) -> Label:
	parent.add_child(CareerTheme.label("ZOOM", SoftBrutalist.SIZE_LABEL,
		CareerTheme.TEXT_MUTED, SoftBrutalist.WEIGHT_BOLD, 1))

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override(&"separation", 10)
	parent.add_child(row)

	row.add_child(_build_zoom_arrow("‹", -1))
	var value := CareerTheme.label("", SoftBrutalist.SIZE_BODY, CareerTheme.POSITIVE,
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
## Real Control focus (FOCUS_ALL), not mouse-only — user ask: "improve
## the accessibility of the options for both mouse and keyboard... and
## controller navigating and changing them". The row cursor this screen's
## own settings rows already use doesn't reach into this preview panel,
## so Godot's own focus traversal is what makes Tab/D-pad land on these at
## all. Default focus stylebox suppressed — the hover-tint _on_zoom_row_
## hover() already gives the row is the only visible state change wanted.
func _build_zoom_arrow(glyph: String, step: int) -> Control:
	var hit := Control.new()
	hit.custom_minimum_size = Vector2(28.0, 28.0)
	hit.mouse_filter = Control.MOUSE_FILTER_STOP
	hit.focus_mode = Control.FOCUS_ALL
	hit.add_theme_stylebox_override(&"focus", StyleBoxEmpty.new())
	hit.gui_input.connect(_on_zoom_arrow_input.bind(step))

	var label := CareerTheme.label(glyph, SoftBrutalist.SIZE_BODY, CareerTheme.TEXT,
		SoftBrutalist.WEIGHT_BOLD)
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hit.add_child(label)
	return hit


func _on_zoom_arrow_input(event: InputEvent, step: int) -> void:
	var clicked: bool = event is InputEventMouseButton and event.pressed \
		and event.button_index == MOUSE_BUTTON_LEFT
	# Control.gui_input also receives key/joypad input once the control has
	# focus — same "confirm activates a focused control" shape career_
	# dashboard_screen.gd's _on_next_game_gui_input() already established.
	if not (clicked or event.is_action_pressed(&"confirm")):
		return
	Settings.camera_zoom += step * Tuning.CAM_ZOOM_STEP
	Settings.save()
	_sync_camera_preview()


func _build_camera_panel(parent: Control, label_text: String, full_side: bool) -> Panel:
	var panel := Panel.new()
	panel.custom_minimum_size = Vector2(0.0, CAMERA_PANEL_HEIGHT)
	panel.add_theme_stylebox_override(&"panel", CareerTheme.panel_style())
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(panel)

	var inner := MarginContainer.new()
	inner.set_anchors_preset(Control.PRESET_FULL_RECT)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		inner.add_theme_constant_override(StringName("margin_" + side), 10)
	panel.add_child(inner)

	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 6)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(col)
	col.add_child(CareerTheme.label(label_text, SoftBrutalist.SIZE_LABEL,
		CareerTheme.PANEL_TEXT, SoftBrutalist.WEIGHT_BOLD, 1))

	# Live render (CameraModePreview) rather than a static screenshot — see
	# that class's own header, and this file's header on why both panels
	# stay simultaneously live ("both options side by side"). Wrapped in an
	# AspectRatioContainer rather than stretched to fill the panel's own
	# wide/short rect (user report: "scale the resolution but maintain
	# aspect ratio, make it a little smaller").
	var aspect := AspectRatioContainer.new()
	aspect.custom_minimum_size = Vector2(0.0, CAMERA_FIELD_HEIGHT)
	aspect.ratio = CAMERA_PREVIEW_ASPECT
	aspect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(aspect)

	var preview := CameraModePreview.new()
	preview.mode = BroadcastCamera.Mode.FULL_SIDE if full_side else BroadcastCamera.Mode.CHASE
	preview.zoom = Settings.camera_zoom
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	aspect.add_child(preview)

	if full_side:
		_camera_preview_full_side = preview
	else:
		_camera_preview_third_person = preview

	return panel


func _build_settings_column() -> Control:
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 10)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.custom_minimum_size = Vector2(380.0, 0.0)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE

	for row in _settings:
		column.add_child(_build_setting_row(row))

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(spacer)

	column.add_child(_build_start_row())
	column.add_child(CareerTheme.label("W / S select · A / D adjust · Enter confirm · Esc back",
		SoftBrutalist.SIZE_LABEL, CareerTheme.TEXT_MUTED))

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
		_whiteboard.highlighted_slot = TeamFormation.ROSTER_ORDER[Settings.home_human_slot] \
			if Settings.player_control_mode == Settings.PlayerControlMode.SINGLE_PLAYER else -1
	_sync_camera_preview()


## Both camera panels stay visible (see this file's header on why) —
## only the border on whichever matches Settings.full_game_camera_mode
## right now changes, so cycling CAMERA always shows which one is live.
func _sync_camera_preview() -> void:
	if not is_instance_valid(_camera_panel_third_person) or not is_instance_valid(_camera_panel_full_side):
		return
	var full_side := Settings.full_game_camera_mode == Settings.FullGameCameraMode.FULL_SIDE
	var active_panel := _camera_panel_full_side if full_side else _camera_panel_third_person
	var inactive_panel := _camera_panel_third_person if full_side else _camera_panel_full_side
	active_panel.add_theme_stylebox_override(&"panel",
		CareerTheme.panel_style(CareerTheme.PANEL, CareerTheme.POSITIVE, SELECTED_BORDER_WIDTH))
	inactive_panel.add_theme_stylebox_override(&"panel", CareerTheme.panel_style())
	if is_instance_valid(_camera_preview_third_person):
		_camera_preview_third_person.zoom = Settings.camera_zoom
	if is_instance_valid(_camera_preview_full_side):
		_camera_preview_full_side.zoom = Settings.camera_zoom
	if is_instance_valid(_zoom_value_label):
		_zoom_value_label.text = "%d%%" % roundi(Settings.camera_zoom * 100.0)


## Swaps the left-hand panel to the two camera screenshots while CAMERA
## holds the cursor, and back to the formation whiteboard otherwise —
## full_game_pregame_screen.gd's own _set_camera_preview_active() does
## the same swap, just between a single preview and the whiteboard+
## readout pair instead of two always-both-visible camera panels.
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
	_set_camera_preview_active(_selected == CAMERA_ROW)


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
