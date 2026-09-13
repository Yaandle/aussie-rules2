class_name SettingsScreen
extends CanvasLayer

## Settings screen (design brief).
##
## MASTER VOLUME is now real — AudioManager reads Settings.master_volume
## directly on every playback, so this row is live the instant it moves,
## same as every other cycling row below it. SCREEN SHAKE stays an inert
## placeholder: nothing in the project reads a screen-shake setting yet,
## and inventing a value nothing consumes would just be decoration.
## FULL GAME CAMERA and MOUSE KICK BUTTONS are real for the same reason
## MASTER VOLUME now is: they read from and write to the Settings
## autoload, which persists them to user://settings.cfg and applies each
## one live the moment it changes (see settings.gd) — so, unlike the row
## above them, these survive closing and reopening this screen, and even
## take effect immediately if changed while a match is already running.
## CONTROL SCHEME was the last inert row of its kind — it's gone, replaced
## by a real REMAP CONTROLS action row (not a cycling value, see
## _row_count()/_activate() below) that opens RemapScreen.

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
		Row.new("MASTER VOLUME", ["MUTE", "25%", "50%", "75%", "100%"],
			_volume_index(Settings.master_volume), _set_master_volume),
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

	# Retro windowed-console shell (see retro_window.gd) — same sharp,
	# unrounded card language as team_list_screen.gd / pause_screen.gd,
	# in place of SoftBrutalist's rounded, softly-blurred panel.
	var card_height := 110.0 + _row_count() * (ROW_HEIGHT + ROW_GAP) + 40.0
	var card_size := Vector2(CARD_WIDTH, card_height)
	var card_wrapper := Control.new()
	card_wrapper.custom_minimum_size = card_size
	card_wrapper.position = Vector2((1280.0 - CARD_WIDTH) / 2.0, (720.0 - card_height) / 2.0)
	root.add_child(card_wrapper)
	var card := RetroWindow.shell(card_wrapper, card_size)

	var title := SoftBrutalist.label("SETTINGS", SoftBrutalist.SIZE_TITLE, RetroWindow.BORDER,
	SoftBrutalist.WEIGHT_HEAVY, SoftBrutalist.TRACK_TITLE)
	title.position = Vector2(32.0, 28.0)
	card.add_child(title)

	var subtitle := SoftBrutalist.label("SCREEN SHAKE NOT YET WIRED ",
		SoftBrutalist.SIZE_CAPTION, SoftBrutalist.MUTED,
		SoftBrutalist.WEIGHT_REGULAR, SoftBrutalist.TRACK_LABEL)
	subtitle.position = Vector2(32.0, 74.0)
	card.add_child(subtitle)

	var top := 112.0
	for i in _rows.size():
		var row := _rows[i]
		var panel := Panel.new()
		panel.add_theme_stylebox_override(&"panel", RetroWindow.row_style(false))
		panel.position = Vector2(32.0, top)
		panel.size = Vector2(CARD_WIDTH - 64.0, ROW_HEIGHT)
		card.add_child(panel)
		_row_panels.append(panel)

		var title_label := SoftBrutalist.label(row.title, SoftBrutalist.SIZE_BODY, RetroWindow.BORDER,
			SoftBrutalist.WEIGHT_BOLD, SoftBrutalist.TRACK_LABEL)
		title_label.position = Vector2(20.0, 16.0)
		panel.add_child(title_label)
		_title_labels.append(title_label)

		var value_label := SoftBrutalist.label(row.value(), SoftBrutalist.SIZE_BODY, RetroWindow.ACCENT,
			SoftBrutalist.WEIGHT_BOLD, 0)
		value_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		value_label.position = Vector2(-180.0, 16.0)
		value_label.size = Vector2(160.0, 24.0)
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		panel.add_child(value_label)
		_value_labels.append(value_label)

		top += ROW_HEIGHT + ROW_GAP

	# Trailing action row (character_screen.gd's PLAY row uses the same
	# "one extra index past the real rows, ui_accept activates instead of
	# cycling" shape) — not a Row instance, since there's no value to
	# cycle, just a destination.
	var remap_panel := Panel.new()
	remap_panel.add_theme_stylebox_override(&"panel", RetroWindow.row_style(false))
	remap_panel.position = Vector2(32.0, top)
	remap_panel.size = Vector2(CARD_WIDTH - 64.0, ROW_HEIGHT)
	card.add_child(remap_panel)
	_row_panels.append(remap_panel)

	var remap_label := SoftBrutalist.label("REMAP CONTROLS", SoftBrutalist.SIZE_BODY, RetroWindow.BORDER,
		SoftBrutalist.WEIGHT_BOLD, SoftBrutalist.TRACK_LABEL)
	remap_label.position = Vector2(20.0, 16.0)
	remap_panel.add_child(remap_label)

	var remap_arrow := SoftBrutalist.label("ENTER >", SoftBrutalist.SIZE_LABEL, RetroWindow.ACCENT,
		SoftBrutalist.WEIGHT_REGULAR, 0)
	remap_arrow.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	remap_arrow.position = Vector2(-100.0, 18.0)
	remap_arrow.size = Vector2(80.0, 24.0)
	remap_arrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	remap_panel.add_child(remap_arrow)

	top += ROW_HEIGHT + ROW_GAP

	var hint := SoftBrutalist.label("UP/DOWN SELECT · LEFT/RIGHT CHANGE · ENTER ACTIVATE · ESC BACK",
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
	elif event.is_action_pressed(&"ui_accept") and _index == _rows.size():
		_activate()
	elif event.is_action_pressed(&"ui_left") and _index < _rows.size():
		_rows[_index].cycle(-1)
		_refresh()
	elif event.is_action_pressed(&"ui_right") and _index < _rows.size():
		_rows[_index].cycle(1)
		_refresh()


## Real cycling rows plus the one trailing REMAP CONTROLS action row.
func _row_count() -> int:
	return _rows.size() + 1


func _move(step: int) -> void:
	_index = (_index + step + _row_count()) % _row_count()
	_refresh()


func _activate() -> void:
	if _busy:
		return
	_busy = true
	Settings.save()
	SceneWipe.change_scene("res://scenes/ui/remap_screen.tscn")


func _back() -> void:
	if _busy:
		return
	_busy = true
	Settings.save()
	SceneWipe.change_scene("res://scenes/ui/main_menu.tscn")


const VOLUME_STEPS := [0.0, 0.25, 0.5, 0.75, 1.0]


func _volume_index(volume: float) -> int:
	var best := 0
	var best_diff := INF
	for i in VOLUME_STEPS.size():
		var diff := absf(VOLUME_STEPS[i] - volume)
		if diff < best_diff:
			best_diff = diff
			best = i
	return best


func _set_master_volume(index: int) -> void:
	Settings.master_volume = VOLUME_STEPS[index]


func _set_camera_mode(index: int) -> void:
	Settings.full_game_camera_mode = index as Settings.FullGameCameraMode


func _set_mouse_kick_swapped(index: int) -> void:
	Settings.mouse_kick_swapped = index == 1


func _refresh() -> void:
	for i in _row_panels.size():
		var selected := i == _index
		_row_panels[i].add_theme_stylebox_override(&"panel", RetroWindow.row_style(selected))
		if i < _rows.size():
			_value_labels[i].text = _rows[i].value()
