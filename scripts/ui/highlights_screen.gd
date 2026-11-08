class_name HighlightsScreen
extends Node3D

## Highlights: the last Full Game's best moments, replayed on the oval.
## Reached from the full-time screens' HIGHLIGHTS row.
##
## Built like TrainingScreen (StudioStyle chrome, the list down the left,
## the thing itself running on the right), so it reads as the same family:
## the moments, best first, with type, quarter and time and their score;
## the selected one replays on the right on a loop. Each can be ticked to
## keep, and the kept ones exported (HighlightExporter) to the folder shown
## in the EXPORT section (HighlightPaths: `highlights/` beside the game).
##
## The replay is a ReplayStage drawn through a SubViewport that fills the
## area right of the column, so the picture is centred in the space you can
## see, and the portrait preview is the same 9:16 framing the export uses.

const MENU_SCENE := "res://scenes/ui/main_menu.tscn"
const COLUMN_WIDTH := 380.0
const ENTRY_HEIGHT := 60.0
const VIEW_SIZE := Vector2(1280.0, 720.0)
const SPEEDS := [1.0, 0.5, 0.25]
## A beat on the last frame before the loop starts again.
const LOOP_HOLD := 1.0
## Trigger travel that counts as a press (LT/RT step the replay).
const TRIGGER_PRESS := 0.6

const SCENE := "res://scenes/ui/highlights_screen.tscn"


## The full-time screens offer Highlights with H / Y: these three are all
## they need, so their own layout didn't change. Nothing is offered when
## the match produced no moments.
static func offer_hints(device: InputManager.Device) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if Highlights.has_moments():
		out.append({"keys": "Y" if device == InputManager.Device.GAMEPAD else "H", "label": "Highlights"})
	return out


static func is_open_request(event: InputEvent) -> bool:
	if not Highlights.has_moments():
		return false
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.physical_keycode == KEY_H:
		return true
	var pad := event as InputEventJoypadButton
	return pad != null and pad.pressed and pad.button_index == JOY_BUTTON_Y


## Opens the Highlights screen; Back returns to `from`. Returns true.
static func open_from(from: String) -> bool:
	Highlights.return_scene = from
	SceneWipe.change_scene(SCENE)
	return true


var _moments: Array[Dictionary] = []
var _index := 0
var _t := 0.0
var _hold := 0.0
var _playing := true
var _speed_index := 0
var _portrait := false
var _busy := false
var _triggers := {}

var _stage: ReplayStage
var _exporter: HighlightExporter
var _view_container: SubViewportContainer
var _view: SubViewport
var _camera: Camera3D

var _entry_panels: Array[Panel] = []
var _entry_titles: Array[Label] = []
var _entry_captions: Array[Label] = []
var _list: VBoxContainer
var _kept_label: Label
var _path_label: Label
var _status_label: Label
var _chip_label: Label
var _card_title: Label
var _card_body: Label
var _bar_fill: ColorRect
var _bar_event: ColorRect
var _bar_back: Panel
var _time_label: Label
var _empty_card: PanelContainer
var _overlay: Control


func _ready() -> void:
	_moments = Highlights.moments
	_stage = ReplayStage.new()
	add_child(_stage)
	_exporter = HighlightExporter.new()
	_exporter.stage = _stage
	add_child(_exporter)
	_exporter.progress.connect(_on_export_progress)
	_build_ui()
	if _moments.is_empty():
		_empty_card.visible = true
		_overlay.visible = false
	else:
		_select(0)
	_refresh()


func _process(delta: float) -> void:
	if _moments.is_empty() or _exporter.busy:
		return
	if _playing:
		if _t >= _stage.duration():
			_hold += delta
			if _hold >= LOOP_HOLD:
				_hold = 0.0
				_t = 0.0
				_show_frame(true)
				return
		else:
			_t = minf(_t + delta * float(SPEEDS[_speed_index]), _stage.duration())
	_show_frame(false, delta * float(SPEEDS[_speed_index]))


func _show_frame(snap: bool, delta := 1.0 / 60.0) -> void:
	_stage.apply(_t)
	_stage.frame_camera(_camera, _preset(), _portrait, _t, maxf(delta, 0.0001), snap)
	var duration := maxf(_stage.duration(), 0.001)
	_bar_fill.size.x = _bar_back.size.x * clampf(_t / duration, 0.0, 1.0)
	_time_label.text = "%4.1f / %4.1f s" % [_t, _stage.duration()]


func _preset() -> String:
	return String(_moments[_index].get("camera", _stage.default_preset()))


# ── Input ───────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if _busy:
		return
	if _exporter.busy:
		if event.is_action_pressed(&"pause") or event.is_action_pressed(&"ui_cancel") \
				or event.is_action_pressed(&"decline"):
			_exporter.cancel()
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"pause") or event.is_action_pressed(&"ui_cancel") \
			or event.is_action_pressed(&"decline"):
		_leave()
	elif _moments.is_empty():
		return
	elif event.is_action_pressed(&"ui_up") or event.is_action_pressed(&"move_forward"):
		_select(_index - 1)
	elif event.is_action_pressed(&"ui_down") or event.is_action_pressed(&"move_back"):
		_select(_index + 1)
	elif event.is_action_pressed(&"ui_left") or event.is_action_pressed(&"move_left") \
			or _pad_button(event, JOY_BUTTON_LEFT_SHOULDER):
		_cycle_camera(-1)
	elif event.is_action_pressed(&"ui_right") or event.is_action_pressed(&"move_right") \
			or _pad_button(event, JOY_BUTTON_RIGHT_SHOULDER):
		_cycle_camera(1)
	elif event.is_action_pressed(&"ui_accept") or event.is_action_pressed(&"confirm"):
		_playing = not _playing
		if _playing and _t >= _stage.duration():
			_t = 0.0
	elif _key(event, KEY_SPACE) or _pad_button(event, JOY_BUTTON_X):
		_moments[_index].keep = not bool(_moments[_index].keep)
	elif _key(event, KEY_E) or _pad_button(event, JOY_BUTTON_Y):
		_export()
	elif _key(event, KEY_V) or _pad_button(event, JOY_BUTTON_RIGHT_STICK):
		_portrait = not _portrait
		_layout_view()
		_show_frame(true)
	elif _key(event, KEY_S) or _pad_button(event, JOY_BUTTON_LEFT_STICK):
		_speed_index = (_speed_index + 1) % SPEEDS.size()
	elif _key(event, KEY_BRACKETLEFT) or _trigger(event, JOY_AXIS_TRIGGER_LEFT):
		_step(-1.0)
	elif _key(event, KEY_BRACKETRIGHT) or _trigger(event, JOY_AXIS_TRIGGER_RIGHT):
		_step(1.0)
	else:
		return
	_refresh()
	get_viewport().set_input_as_handled()


func _key(event: InputEvent, keycode: Key) -> bool:
	var key := event as InputEventKey
	return key != null and key.pressed and not key.echo and key.physical_keycode == keycode


func _pad_button(event: InputEvent, button: JoyButton) -> bool:
	var pad := event as InputEventJoypadButton
	return pad != null and pad.pressed and pad.button_index == button


## A trigger counts once per pull past TRIGGER_PRESS.
func _trigger(event: InputEvent, axis: JoyAxis) -> bool:
	var motion := event as InputEventJoypadMotion
	if motion == null or motion.axis != axis:
		return false
	var was: bool = _triggers.get(axis, false)
	var now := motion.axis_value > TRIGGER_PRESS
	_triggers[axis] = now
	return now and not was


## A second either way while playing, one frame either way while paused.
func _step(direction: float) -> void:
	var amount := 1.0 if _playing else 1.0 / HighlightTable.RECORD_FPS
	_t = clampf(_t + direction * amount, 0.0, _stage.duration())
	_hold = 0.0
	_show_frame(true)


func _select(index: int) -> void:
	_index = posmod(index, _moments.size())
	_stage.load_clip(_moments[_index].clip)
	_t = 0.0
	_hold = 0.0
	_playing = true
	_show_frame(true)
	_scroll_to(_index)


func _cycle_camera(step: int) -> void:
	var presets := ReplayStage.CAMERA_PRESETS
	var i := presets.find(_preset())
	_moments[_index].camera = presets[posmod(i + step, presets.size())]
	_show_frame(true)


func _leave() -> void:
	_busy = true
	SceneWipe.change_scene(Highlights.return_scene if Highlights.return_scene != "" else MENU_SCENE)


func _export() -> void:
	var kept := Highlights.kept()
	if kept.is_empty():
		_status_label.text = "Nothing ticked to keep. X / Space ticks a moment."
		return
	_status_label.text = "Starting export..."
	var folder := await _exporter.export_moments(kept, Highlights.match_info)
	_status_label.text = "Exported %d moment%s to\n%s" % [kept.size(), "" if kept.size() == 1 else "s", folder]
	# The stage was driven by the exporter: back to the selected moment.
	_select(_index)
	_refresh()


func _on_export_progress(text: String, fraction: float) -> void:
	_status_label.text = "%s  %d%%\nEsc / B cancels" % [text, int(fraction * 100.0)]


# ── UI ──────────────────────────────────────────────────────────────

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)

	# The replay, right of the column.
	_view_container = SubViewportContainer.new()
	_view_container.stretch = true
	_view_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_view_container)
	_view = SubViewport.new()
	_view.msaa_3d = Viewport.MSAA_4X
	_view_container.add_child(_view)
	_camera = Camera3D.new()
	_camera.current = true
	_view.add_child(_camera)
	_layout_view()

	var hints := DeviceHintBar.new()
	hints.alignment = BoxContainer.ALIGNMENT_END
	var info: Dictionary = Highlights.match_info
	var final: Dictionary = info.get("final", {})
	var crumb := "Full time" if final.is_empty() else "%s %s  v  %s %s" % [
		String(info.get("home", "Home")), String(final.get("home", "")),
		String(info.get("away", "Away")), String(final.get("away", ""))]
	StudioStyle.header(root, "Highlights", crumb, hints)
	hints.set_hint_sets({
		InputManager.Device.KEYBOARD: [
			{"keys": "↑ / ↓", "label": "Select"},
			{"keys": "Enter", "label": "Play / pause"},
			{"keys": "Space", "label": "Keep"},
			{"keys": "← / →", "label": "Camera"},
			{"keys": "E", "label": "Export"},
			{"keys": "Esc", "label": "Back"},
		],
		InputManager.Device.GAMEPAD: [
			{"keys": "D-Pad ↕", "label": "Select"},
			{"keys": "A", "label": "Play / pause"},
			{"keys": "X", "label": "Keep"},
			{"keys": "LB / RB", "label": "Camera"},
			{"keys": "Y", "label": "Export"},
			{"keys": "B", "label": "Back"},
		],
	})

	var column := Panel.new()
	column.add_theme_stylebox_override(&"panel", StudioStyle.bar(StudioStyle.PAPER, true))
	column.position = Vector2(0.0, StudioStyle.HEADER_HEIGHT)
	column.size = Vector2(COLUMN_WIDTH, VIEW_SIZE.y - StudioStyle.HEADER_HEIGHT)
	root.add_child(column)

	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.offset_right = -StudioStyle.BORDER
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in [&"margin_left", &"margin_right", &"margin_top", &"margin_bottom"]:
		margin.add_theme_constant_override(side, 16)
	scroll.add_child(margin)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override(&"separation", 8)
	margin.add_child(_list)

	_section(_list, "MOMENTS  (%d)" % _moments.size())
	for i in _moments.size():
		var moment := _moments[i]
		var panel := Panel.new()
		panel.custom_minimum_size = Vector2(0.0, ENTRY_HEIGHT)
		panel.mouse_filter = Control.MOUSE_FILTER_STOP
		panel.gui_input.connect(_on_entry_input.bind(i))
		var title := StudioStyle.text("", 14, StudioStyle.INK, StudioStyle.body_font())
		title.position = Vector2(12.0, 8.0)
		panel.add_child(title)
		var caption := StudioStyle.text(String(moment.caption), 11, StudioStyle.INK_SOFT, StudioStyle.body_font())
		caption.position = Vector2(12.0, 32.0)
		caption.size = Vector2(COLUMN_WIDTH - 60.0, 18.0)
		caption.clip_text = true
		caption.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		panel.add_child(caption)
		_list.add_child(panel)
		_entry_panels.append(panel)
		_entry_titles.append(title)
		_entry_captions.append(caption)

	_section(_list, "EXPORT")
	_kept_label = StudioStyle.text("", 12, StudioStyle.INK, StudioStyle.body_font())
	_list.add_child(_kept_label)
	_path_label = StudioStyle.text("", 11, StudioStyle.INK_SOFT, StudioStyle.mono_font())
	_path_label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	_path_label.custom_minimum_size.x = COLUMN_WIDTH - 56.0
	_path_label.text = "Folder: %s\nPer moment: 16:9 1920x1080 and 9:16 1080x1920 MJPEG .avi at %d fps (.mp4 too if ffmpeg is installed), a .replay, and moments.json." % [
		HighlightPaths.root(), HighlightTable.EXPORT_FPS]
	_list.add_child(_path_label)
	_status_label = StudioStyle.text("", 12, StudioStyle.INK, StudioStyle.body_font())
	_status_label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	_status_label.custom_minimum_size.x = COLUMN_WIDTH - 56.0
	_list.add_child(_status_label)

	# Over the replay, top-left: the lime chip (type, camera, speed) and the
	# moment's card. Bottom: the scrub bar.
	_overlay = Control.new()
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.position = Vector2(COLUMN_WIDTH + 20.0, StudioStyle.HEADER_HEIGHT + 20.0)
	_overlay.size = Vector2(VIEW_SIZE.x - COLUMN_WIDTH - 40.0, VIEW_SIZE.y - StudioStyle.HEADER_HEIGHT - 40.0)
	root.add_child(_overlay)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override(&"separation", 10)
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(stack)
	var chip_row := HBoxContainer.new()
	stack.add_child(chip_row)
	var chip := _padded(StudioStyle.box(StudioStyle.LIME, 2, StudioStyle.SHADOW), 10, 5)
	chip_row.add_child(chip)
	_chip_label = StudioStyle.text("", 11, StudioStyle.INK, StudioStyle.mono_font())
	chip.get_child(0).add_child(_chip_label)
	var card := _padded(StudioStyle.box(StudioStyle.WHITE, StudioStyle.BORDER, StudioStyle.SHADOW), 12, 10)
	card.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	stack.add_child(card)
	var card_column := VBoxContainer.new()
	card.get_child(0).add_child(card_column)
	_card_title = StudioStyle.text("", 16, StudioStyle.INK, StudioStyle.display_font())
	card_column.add_child(_card_title)
	_card_body = StudioStyle.text("", 12, StudioStyle.INK, StudioStyle.body_font())
	_card_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_card_body.custom_minimum_size.x = 340.0
	card_column.add_child(_card_body)

	var bar_y := _overlay.size.y - 26.0
	_bar_back = Panel.new()
	_bar_back.add_theme_stylebox_override(&"panel", StudioStyle.box(StudioStyle.WHITE, 2, StudioStyle.SHADOW))
	_bar_back.position = Vector2(0.0, bar_y)
	_bar_back.size = Vector2(_overlay.size.x - 130.0, 14.0)
	_bar_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(_bar_back)
	_bar_fill = ColorRect.new()
	_bar_fill.color = StudioStyle.INK
	_bar_fill.size = Vector2(0.0, 14.0)
	_bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar_back.add_child(_bar_fill)
	_bar_event = ColorRect.new()
	_bar_event.color = StudioStyle.ORANGE
	_bar_event.size = Vector2(4.0, 22.0)
	_bar_event.position.y = -4.0
	_bar_event.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar_back.add_child(_bar_event)
	var time_chip := _padded(StudioStyle.box(StudioStyle.WHITE, 2, StudioStyle.SHADOW), 8, 2)
	time_chip.position = Vector2(_overlay.size.x - 118.0, bar_y - 4.0)
	_overlay.add_child(time_chip)
	_time_label = StudioStyle.text("", 11, StudioStyle.INK, StudioStyle.mono_font())
	time_chip.get_child(0).add_child(_time_label)

	_empty_card = _padded(StudioStyle.box(StudioStyle.WHITE, StudioStyle.BORDER, StudioStyle.SHADOW), 16, 14)
	_empty_card.position = Vector2(COLUMN_WIDTH + 40.0, StudioStyle.HEADER_HEIGHT + 40.0)
	_empty_card.visible = false
	root.add_child(_empty_card)
	var empty_text := StudioStyle.text(
		"No highlights from this match yet.\nPlay a Full Game: goals, big marks, tackles and long kicks are picked out as it goes.",
		13, StudioStyle.INK, StudioStyle.body_font())
	empty_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	empty_text.custom_minimum_size.x = 420.0
	_empty_card.get_child(0).add_child(empty_text)


## The replay fills the space right of the column; the portrait preview is
## a 9:16 window centred in it.
func _layout_view() -> void:
	var area := Rect2(Vector2(COLUMN_WIDTH, StudioStyle.HEADER_HEIGHT),
		Vector2(VIEW_SIZE.x - COLUMN_WIDTH, VIEW_SIZE.y - StudioStyle.HEADER_HEIGHT))
	var rect := area
	if _portrait:
		var width := area.size.y * 9.0 / 16.0
		rect = Rect2(Vector2(area.position.x + (area.size.x - width) * 0.5, area.position.y),
			Vector2(width, area.size.y))
	_view_container.position = rect.position
	_view_container.size = rect.size


func _padded(style: StyleBox, across: int, down: int) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override(&"panel", style)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var margin := MarginContainer.new()
	margin.add_theme_constant_override(&"margin_left", across)
	margin.add_theme_constant_override(&"margin_right", across)
	margin.add_theme_constant_override(&"margin_top", down)
	margin.add_theme_constant_override(&"margin_bottom", down)
	panel.add_child(margin)
	return panel


func _section(parent: Control, title: String) -> void:
	var head := StudioStyle.text(title, 11, StudioStyle.INK_SOFT, StudioStyle.mono_font())
	head.custom_minimum_size.y = 22.0
	head.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	parent.add_child(head)
	var rule := ColorRect.new()
	rule.color = StudioStyle.INK
	rule.custom_minimum_size = Vector2(0.0, 2.0)
	parent.add_child(rule)


static func clock_text(moment: Dictionary) -> String:
	var elapsed := float(moment.quarter_elapsed_s)
	return "Q%d %d:%02d" % [int(moment.quarter), int(elapsed) / 60, int(elapsed) % 60]


func _refresh() -> void:
	var kept := 0
	for i in _entry_panels.size():
		var moment := _moments[i]
		var picked := i == _index
		if moment.keep:
			kept += 1
		_entry_panels[i].add_theme_stylebox_override(&"panel",
			StudioStyle.box(StudioStyle.INK if picked else StudioStyle.WHITE, StudioStyle.BORDER,
				StudioStyle.SHADOW if picked else 0))
		_entry_titles[i].text = "%s  %s   %s   %d" % ["■" if moment.keep else "□", String(moment.label),
			clock_text(moment), int(round(float(moment.highlight_score)))]
		_entry_titles[i].add_theme_color_override(&"font_color", StudioStyle.LIME if picked else StudioStyle.INK)
		_entry_captions[i].add_theme_color_override(&"font_color",
			StudioStyle.PAPER if picked else StudioStyle.INK_SOFT)
	_kept_label.text = "Kept for export: %d of %d" % [kept, _moments.size()]
	if _moments.is_empty():
		return
	var moment := _moments[_index]
	_chip_label.text = "%s  ·  %s  ·  %s×%s" % [
		"PLAYING" if _playing else "PAUSED",
		String(ReplayStage.PRESET_LABELS.get(_preset(), _preset())),
		str(SPEEDS[_speed_index]), "  ·  9:16" if _portrait else ""]
	_card_title.text = "%s  ·  %s" % [String(moment.label), clock_text(moment)]
	var before: Dictionary = moment.score_before
	var after: Dictionary = moment.score_after
	var info := Highlights.match_info
	var score_line := "%s %s  v  %s %s" % [info.get("home", "Home"), before.home,
		info.get("away", "Away"), before.away]
	if before.home != after.home or before.away != after.away:
		score_line += "  →  %s v %s" % [after.home, after.away]
	_card_body.text = "%s\n%s\nScore %d  ·  %s" % [String(moment.caption), score_line,
		int(round(float(moment.highlight_score))), "kept" if moment.keep else "not kept"]
	var duration := maxf(_stage.duration(), 0.001)
	_bar_event.position.x = _bar_back.size.x * clampf(_stage.event_time() / duration, 0.0, 1.0) - 2.0


func _scroll_to(index: int) -> void:
	if index < 0 or index >= _entry_panels.size():
		return
	var scroll := _list.get_parent().get_parent() as ScrollContainer
	if scroll != null:
		scroll.ensure_control_visible.call_deferred(_entry_panels[index])


func _on_entry_input(event: InputEvent, index: int) -> void:
	var click := event as InputEventMouseButton
	if click == null or not click.pressed or click.button_index != MOUSE_BUTTON_LEFT:
		return
	if index != _index:
		_select(index)
	elif click.double_click:
		_playing = not _playing
	_refresh()
