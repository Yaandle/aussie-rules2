class_name SettingsScreen
extends CanvasLayer

## Settings screen (design brief).
##
## The first three rows (Master Volume / Control Scheme / Screen Shake)
## remain inert display placeholders — nothing in the project reads
## audio/haptics settings yet, and inventing values for options nothing
## consumes would just be decoration. The two rows below them,
## FULL GAME CAMERA and MOUSE KICK BUTTONS, are real: they read from and
## write to the Settings autoload, which persists them to
## user://settings.cfg and applies each one live the moment it changes
## (see settings.gd) — so, unlike the row above them, these survive
## closing and reopening this screen, and even take effect immediately
## if changed while a match is already running.

const CARD_WIDTH := 560.0
const ROW_HEIGHT := 56.0
const ROW_GAP := 14.0

class Row:
	var title: String
	var options: Array[String]
	var index: int
	## Called with the new index whenever cycle() changes it — the
	## live/persisted rows use this to push into Settings; the
	## placeholder rows above just leave it unset and stay inert exactly
	## as before.
	var on_change: Callable

	func _init(p_title: String, p_options: Array[String], p_index := 0,
			p_on_change := Callable()) -> void:
		title = p_title
		options = p_options
		index = p_index
		on_change = p_on_change

	func value() -> String:
		return options[index]

	func cycle(step: int) -> void:
		index = (index + step + options.size()) % options.size()
		if on_change.is_valid():
			on_change.call(index)


var _rows: Array[Row] = []
var _index := 0
var _busy := false

var _row_panels: Array[Panel] = []
var _title_labels: Array[Label] = []
var _value_labels: Array[Label] = []


func _ready() -> void:
	_rows = [
		Row.new("MASTER VOLUME", ["—", "25%", "50%", "75%", "100%"]),
		Row.new("CONTROL SCHEME", ["—", "KEYBOARD", "GAMEPAD"]),
		Row.new("SCREEN SHAKE", ["—", "OFF", "ON"]),
		Row.new("FULL GAME CAMERA", ["3RD PERSON", "FULL-SIDE"],
			Settings.full_game_camera_mode, _set_camera_mode),
		Row.new("MOUSE KICK BUTTONS", ["RIGHT AIM · LEFT KICK", "LEFT AIM · RIGHT KICK"],
			1 if Settings.mouse_kick_swapped else 0, _set_mouse_kick_swapped),
	]

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	root.add_child(SoftBrutalist.backdrop())

	var card_height := 110.0 + _rows.size() * (ROW_HEIGHT + ROW_GAP) + 40.0
	var card := Panel.new()
	card.add_theme_stylebox_override(&"panel", SoftBrutalist.panel_style())
	SoftBrutalist.soften(card, SoftBrutalist.Elevation.OVERLAY)
	card.size = Vector2(CARD_WIDTH, card_height)
	card.position = Vector2((1280.0 - CARD_WIDTH) / 2.0, (720.0 - card_height) / 2.0)
	root.add_child(card)

	var title := SoftBrutalist.label("SETTINGS", SoftBrutalist.SIZE_TITLE, SoftBrutalist.INK,
		SoftBrutalist.WEIGHT_HEAVY, SoftBrutalist.TRACK_TITLE)
	title.position = Vector2(32.0, 28.0)
	card.add_child(title)

	var subtitle := SoftBrutalist.label("PLACEHOLDER · NOT SAVED", SoftBrutalist.SIZE_CAPTION, SoftBrutalist.MUTED,
		SoftBrutalist.WEIGHT_REGULAR, SoftBrutalist.TRACK_LABEL)
	subtitle.position = Vector2(32.0, 68.0)
	card.add_child(subtitle)

	var top := 110.0
	for i in _rows.size():
		var row := _rows[i]
		var panel := Panel.new()
		panel.add_theme_stylebox_override(&"panel", SoftBrutalist.button_style(&"normal"))
		SoftBrutalist.soften(panel, SoftBrutalist.Elevation.LOW,
			float(SoftBrutalist.RADIUS_SM))
		panel.position = Vector2(32.0, top)
		panel.size = Vector2(CARD_WIDTH - 64.0, ROW_HEIGHT)
		card.add_child(panel)
		_row_panels.append(panel)

		var title_label := SoftBrutalist.label(row.title, SoftBrutalist.SIZE_BODY, SoftBrutalist.INK,
			SoftBrutalist.WEIGHT_BOLD, SoftBrutalist.TRACK_LABEL)
		title_label.position = Vector2(20.0, 16.0)
		panel.add_child(title_label)
		_title_labels.append(title_label)

		var value_label := SoftBrutalist.label(row.value(), SoftBrutalist.SIZE_BODY, SoftBrutalist.MUTED,
			SoftBrutalist.WEIGHT_REGULAR, 0)
		value_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		value_label.position = Vector2(-180.0, 16.0)
		value_label.size = Vector2(160.0, 24.0)
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		panel.add_child(value_label)
		_value_labels.append(value_label)

		top += ROW_HEIGHT + ROW_GAP

	var hint := SoftBrutalist.label("UP/DOWN SELECT · LEFT/RIGHT CHANGE · ESC BACK",
		SoftBrutalist.SIZE_CAPTION,
		SoftBrutalist.MUTED, SoftBrutalist.WEIGHT_REGULAR, SoftBrutalist.TRACK_LABEL)
	hint.position = Vector2(32.0, top + 8.0)
	card.add_child(hint)

	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if _busy:
		return
	if event.is_action_pressed(&"pause") or event.is_action_pressed(&"ui_cancel"):
		_back()
	elif event.is_action_pressed(&"move_forward") or event.is_action_pressed(&"ui_up"):
		_move(-1)
	elif event.is_action_pressed(&"move_back") or event.is_action_pressed(&"ui_down"):
		_move(1)
	elif event.is_action_pressed(&"ui_left"):
		_rows[_index].cycle(-1)
		_refresh()
	elif event.is_action_pressed(&"ui_right"):
		_rows[_index].cycle(1)
		_refresh()


func _move(step: int) -> void:
	_index = (_index + step + _rows.size()) % _rows.size()
	_refresh()


func _back() -> void:
	if _busy:
		return
	_busy = true
	Settings.save()
	SceneWipe.change_scene("res://scenes/ui/main_menu.tscn")


func _set_camera_mode(index: int) -> void:
	Settings.full_game_camera_mode = index as Settings.FullGameCameraMode


func _set_mouse_kick_swapped(index: int) -> void:
	Settings.mouse_kick_swapped = index == 1


func _refresh() -> void:
	for i in _rows.size():
		var selected := i == _index
		SoftBrutalist.animate_state(_row_panels[i], &"panel",
			&"hover" if selected else &"normal")
		_value_labels[i].text = _rows[i].value()
