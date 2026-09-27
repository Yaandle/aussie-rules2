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

const PREVIEW_WIDTH := 320.0
const PREVIEW_HEIGHT := 270.0
const PREVIEW_OFFSET := 80.0
const PREVIEW_GAP := -10.0
const PREVIEW_DURATION := 0.28

class Row:
	var title: String
	var options: Array[String]
	var index: int

	var on_change: Callable

	func _init(
		p_title: String,
		p_options: Array[String],
		p_index := 0,
		p_on_change := Callable()
	) -> void:
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

var _settings_content: Control
var _card_wrapper: Control
var _preview_wrapper: Control

var _preview_window: Control
var _preview_active := false
var _preview_tween: Tween

var _camera_panel_third_person: Panel
var _camera_panel_full_side: Panel


func _ready() -> void:
	_rows = [
		Row.new(
			"MASTER VOLUME",
			["MUTE", "25%", "50%", "75%", "100%"],
			_volume_index(Settings.master_volume),
			_set_master_volume
		),
		Row.new(
			"SCREEN SHAKE",
			["—", "OFF", "ON"]
		),
		Row.new(
			"FULL GAME CAMERA",
			["3RD PERSON", "FULL-SIDE"],
			Settings.full_game_camera_mode,
			_set_camera_mode
		),
		Row.new(
			"MOUSE KICK BUTTONS",
			["RIGHT AIM · LEFT KICK", "LEFT AIM · RIGHT KICK"],
			1 if Settings.mouse_kick_swapped else 0,
			_set_mouse_kick_swapped
		),
	]

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	root.add_child(SoftBrutalist.backdrop())

	var card_height := 110.0 + _row_count() * (ROW_HEIGHT + ROW_GAP) + 40.0
	var card_size := Vector2(CARD_WIDTH, card_height)

	_card_wrapper = Control.new()
	_card_wrapper.custom_minimum_size = card_size
	_card_wrapper.position = Vector2(
		(1280.0 - CARD_WIDTH) / 2.0,
		(720.0 - card_height) / 2.0
	)
	_card_wrapper.size = card_size
	root.add_child(_card_wrapper)

	var card := RetroWindow.shell(_card_wrapper, card_size)

	# Keep the content stationary inside the card.
	# The card wrapper itself is animated so the entire window, including
	# its border and shadow, moves together.
	_settings_content = Control.new()
	_settings_content.set_anchors_preset(Control.PRESET_FULL_RECT)
	_settings_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(_settings_content)

	var title := SoftBrutalist.label(
		"SETTINGS",
		SoftBrutalist.SIZE_TITLE,
		RetroWindow.BORDER,
		SoftBrutalist.WEIGHT_HEAVY,
		SoftBrutalist.TRACK_TITLE
	)
	title.position = Vector2(32.0, 28.0)
	_settings_content.add_child(title)

	var subtitle := SoftBrutalist.label(
		"SCREEN SHAKE NOT YET WIRED ",
		SoftBrutalist.SIZE_CAPTION,
		SoftBrutalist.MUTED,
		SoftBrutalist.WEIGHT_REGULAR,
		SoftBrutalist.TRACK_LABEL
	)
	subtitle.position = Vector2(32.0, 74.0)
	_settings_content.add_child(subtitle)

	var top := 112.0

	for i in _rows.size():
		var row := _rows[i]

		var panel := Panel.new()
		panel.add_theme_stylebox_override(
			&"panel",
			RetroWindow.row_style(false)
		)
		panel.position = Vector2(32.0, top)
		panel.size = Vector2(CARD_WIDTH - 64.0, ROW_HEIGHT)
		_settings_content.add_child(panel)
		_row_panels.append(panel)

		var title_label := SoftBrutalist.label(
			row.title,
			SoftBrutalist.SIZE_BODY,
			RetroWindow.BORDER,
			SoftBrutalist.WEIGHT_BOLD,
			SoftBrutalist.TRACK_LABEL
		)
		title_label.position = Vector2(20.0, 16.0)
		panel.add_child(title_label)
		_title_labels.append(title_label)

		var value_label := SoftBrutalist.label(
			row.value(),
			SoftBrutalist.SIZE_BODY,
			RetroWindow.ACCENT,
			SoftBrutalist.WEIGHT_BOLD,
			0
		)
		value_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		value_label.position = Vector2(-180.0, 16.0)
		value_label.size = Vector2(160.0, 24.0)
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		panel.add_child(value_label)
		_value_labels.append(value_label)

		top += ROW_HEIGHT + ROW_GAP

	var remap_panel := Panel.new()
	remap_panel.add_theme_stylebox_override(
		&"panel",
		RetroWindow.row_style(false)
	)
	remap_panel.position = Vector2(32.0, top)
	remap_panel.size = Vector2(CARD_WIDTH - 64.0, ROW_HEIGHT)
	_settings_content.add_child(remap_panel)
	_row_panels.append(remap_panel)

	var remap_label := SoftBrutalist.label(
		"REMAP CONTROLS",
		SoftBrutalist.SIZE_BODY,
		RetroWindow.BORDER,
		SoftBrutalist.WEIGHT_BOLD,
		SoftBrutalist.TRACK_LABEL
	)
	remap_label.position = Vector2(20.0, 16.0)
	remap_panel.add_child(remap_label)

	var remap_arrow := SoftBrutalist.label(
		"ENTER >",
		SoftBrutalist.SIZE_BODY,
		RetroWindow.ACCENT,
		SoftBrutalist.WEIGHT_BOLD,
		0
	)
	remap_arrow.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	remap_arrow.position = Vector2(-100.0, 18.0)
	remap_arrow.size = Vector2(80.0, 24.0)
	remap_arrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	remap_panel.add_child(remap_arrow)

	top += ROW_HEIGHT + ROW_GAP

	var hint := SoftBrutalist.label(
		"UP/DOWN SELECT · LEFT/RIGHT CHANGE · ENTER ACTIVATE · ESC BACK",
		SoftBrutalist.SIZE_CAPTION,
		SoftBrutalist.MUTED,
		SoftBrutalist.WEIGHT_REGULAR,
		SoftBrutalist.TRACK_LABEL
	)
	hint.position = Vector2(32.0, top + 8.0)
	_settings_content.add_child(hint)

	_create_camera_preview(root, _card_wrapper, card_height)

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


func _create_camera_preview(
	root: Control,
	card_wrapper: Control,
	card_height: float
) -> void:
	_preview_wrapper = Control.new()
	_preview_wrapper.custom_minimum_size = Vector2(
		PREVIEW_WIDTH,
		PREVIEW_HEIGHT
	)

	var card_x := card_wrapper.position.x
	var card_y := card_wrapper.position.y

	# Move the preview left enough that its complete border and shadow
	# remain comfortably inside the 1280px-wide viewport.
	_preview_wrapper.position = Vector2(
		card_x + CARD_WIDTH + PREVIEW_GAP,
		card_y + (card_height - PREVIEW_HEIGHT) / 2.0
	)

	_preview_wrapper.size = Vector2(
		PREVIEW_WIDTH,
		PREVIEW_HEIGHT
	)
	_preview_wrapper.modulate.a = 0.0
	_preview_wrapper.scale = Vector2(0.96, 0.96)
	_preview_wrapper.pivot_offset = Vector2(
		PREVIEW_WIDTH / 2.0,
		PREVIEW_HEIGHT / 2.0
	)
	_preview_wrapper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview_wrapper.visible = false
	root.add_child(_preview_wrapper)

	_preview_window = RetroWindow.shell(
		_preview_wrapper,
		Vector2(PREVIEW_WIDTH, PREVIEW_HEIGHT)
	)

	var title := SoftBrutalist.label(
		"CAMERA PREVIEW",
		SoftBrutalist.SIZE_LABEL,
		RetroWindow.BORDER,
		SoftBrutalist.WEIGHT_HEAVY,
		SoftBrutalist.TRACK_TITLE
	)
	title.position = Vector2(20.0, 18.0)
	_preview_window.add_child(title)

	var divider := ColorRect.new()
	divider.color = RetroWindow.BORDER
	divider.position = Vector2(20.0, 48.0)
	divider.size = Vector2(PREVIEW_WIDTH - 40.0, 1.0)
	_preview_window.add_child(divider)

	_create_camera_panel(
		Vector2(16.0, 62.0),
		Vector2(140.0, 184.0),
		"3RD PERSON",
		false
	)

	_create_camera_panel(
		Vector2(164.0, 62.0),
		Vector2(140.0, 184.0),
		"FULL-SIDE",
		true
	)


func _create_camera_panel(
	panel_position: Vector2,
	panel_size: Vector2,
	label_text: String,
	full_side: bool
) -> Panel:
	var panel := Panel.new()
	panel.position = panel_position
	panel.size = panel_size
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override(
		&"panel",
		RetroWindow.row_style(false)
	)
	_preview_window.add_child(panel)

	var label := SoftBrutalist.label(
		label_text,
		SoftBrutalist.SIZE_CAPTION,
		RetroWindow.ACCENT,
		SoftBrutalist.WEIGHT_BOLD,
		SoftBrutalist.TRACK_LABEL
	)
	label.position = Vector2(10.0, 8.0)
	label.size = Vector2(panel_size.x - 20.0, 20.0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(label)

	var field := _CameraPreviewField.new()
	field.full_side = full_side
	field.position = Vector2(10.0, 38.0)
	field.size = Vector2(panel_size.x - 20.0, panel_size.y - 50.0)
	field.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(field)
	
	# Store panel references for visibility toggling
	if full_side:
		_camera_panel_full_side = panel
	else:
		_camera_panel_third_person = panel
	
	return panel


func _set_preview_active(active: bool) -> void:
	if _preview_wrapper == null or _card_wrapper == null:
		return

	if _preview_active == active:
		return

	_preview_active = active

	if _preview_tween != null:
		_preview_tween.kill()

	_preview_tween = create_tween()
	_preview_tween.set_parallel(true)
	_preview_tween.set_trans(Tween.TRANS_QUAD)
	_preview_tween.set_ease(Tween.EASE_OUT)

	var card_base_x := (1280.0 - CARD_WIDTH) / 2.0
	var card_target_x := card_base_x - PREVIEW_OFFSET

	var preview_base_x := (
		card_base_x +
		CARD_WIDTH +
		PREVIEW_GAP
	)

	if active:
		# Move the complete settings card, not just its content.
		_preview_tween.tween_property(
			_card_wrapper,
			"position:x",
			card_target_x,
			PREVIEW_DURATION
		)

		_preview_wrapper.visible = true
		_preview_wrapper.position.x = preview_base_x + 20.0
		_preview_wrapper.modulate.a = 0.0
		_preview_wrapper.scale = Vector2(0.96, 0.96)

		_preview_tween.tween_property(
			_preview_wrapper,
			"position:x",
			preview_base_x,
			PREVIEW_DURATION
		)

		_preview_tween.tween_property(
			_preview_wrapper,
			"modulate:a",
			1.0,
			PREVIEW_DURATION
		)

		_preview_tween.tween_property(
			_preview_wrapper,
			"scale",
			Vector2.ONE,
			PREVIEW_DURATION
		)
	else:
		_preview_tween.tween_property(
			_card_wrapper,
			"position:x",
			card_base_x,
			PREVIEW_DURATION
		)

		_preview_tween.tween_property(
			_preview_wrapper,
			"position:x",
			preview_base_x + 20.0,
			PREVIEW_DURATION
		)

		_preview_tween.tween_property(
			_preview_wrapper,
			"modulate:a",
			0.0,
			PREVIEW_DURATION
		)

		_preview_tween.tween_property(
			_preview_wrapper,
			"scale",
			Vector2(0.96, 0.96),
			PREVIEW_DURATION
		)

		_preview_tween.chain().tween_callback(_hide_preview)


func _hide_preview() -> void:
	if not _preview_active and _preview_wrapper != null:
		_preview_wrapper.visible = false

		# Explicitly restore the absolute base position so repeated
		# enter/exit cycles can never accumulate offsets.
		_preview_wrapper.position.x = (
			(1280.0 - CARD_WIDTH) / 2.0 +
			CARD_WIDTH +
			PREVIEW_GAP
		)


func _refresh() -> void:
	for i in _row_panels.size():
		var selected := i == _index

		_row_panels[i].add_theme_stylebox_override(
			&"panel",
			RetroWindow.row_style(selected)
		)

		if i < _rows.size():
			_value_labels[i].text = _rows[i].value()

	_set_preview_active(_index == 2)
	_sync_camera_preview()


func _sync_camera_preview() -> void:
	if not is_instance_valid(_camera_panel_third_person) \
			or not is_instance_valid(_camera_panel_full_side):
		return
	
	var full_side := Settings.full_game_camera_mode == Settings.FullGameCameraMode.FULL_SIDE
	
	# Only show the panel matching the current camera mode
	_camera_panel_third_person.visible = not full_side
	_camera_panel_full_side.visible = full_side


class _CameraPreviewField extends Control:
	var full_side := false
	var _texture_rect: TextureRect

	func _ready() -> void:
		# Create a TextureRect to display the camera screenshot
		_texture_rect = TextureRect.new()
		_texture_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		_texture_rect.expand_mode = TextureRect.EXPAND_FIT_HEIGHT
		_texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_texture_rect)
		update_texture()

	func update_texture() -> void:
		if _texture_rect == null:
			return
		var image_path := "res://assets/textures/images/fullside.png" if full_side else "res://assets/textures/images/3rdperson.png"
		_texture_rect.texture = load(image_path)
