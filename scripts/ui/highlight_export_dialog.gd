class_name HighlightExportDialog
extends Control

## The Highlights screen's export window (playtest 2026-11-10: "when I
## click export let me select which clips to export"). The page behind is
## blurred and dimmed; the window lists, top to bottom:
##   a row per moment TYPE: its toggle, how many are held and ticked, and the
##     type's default camera (left / right changes it);
##   the FORMAT row: 16:9 + 9:16, 16:9 only or 9:16 only (half the render);
##   a row per listed moment with its tick box and camera (left / right
##     changes that moment's own camera);
##   then EXPORT and CANCEL.
## The type toggles, cameras and format are saved (HighlightPrefs). The
## moment ticks are the moments' own `keep` flags, so what you ticked on the
## page arrives pre-ticked here and stays in step. A type that's off isn't
## listed and isn't rendered.
##
## Pad and keyboard: ↑/↓ move, ←/→ change a camera or the format, A/Enter
## (or X/Space) toggles or presses EXPORT/CANCEL, Y/E exports straight away,
## B/Esc closes (or cancels a running export). Mouse: click a row. The screen
## forwards its input here while the window is open (handle_input).

signal export_requested(moments: Array[Dictionary])
signal cancel_requested
signal closed

const WIDTH := 600.0
const LIST_HEIGHT := 400.0
const ROW_HEIGHT := 34.0

## A mipmap blur of whatever is drawn under it (the 3D replay and the
## page), so the window reads as on top without hiding the page entirely.
const BLUR_SHADER := """
shader_type canvas_item;
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform float lod = 3.0;
uniform vec4 tint : source_color = vec4(0.07, 0.07, 0.07, 0.45);
void fragment() {
	vec3 c = textureLod(screen_texture, SCREEN_UV, lod).rgb;
	COLOR = vec4(mix(c, tint.rgb, tint.a), 1.0);
}
"""

var _moments: Array[Dictionary] = []
var _cursor := 0
var _exporting := false
var _done := false
## One per row, top to bottom: {kind: "type"|"format"|"moment"|"export"|"close",
## type (for "type"), moment (for "moment")}.
var _entries: Array[Dictionary] = []
var _rows: Array[Panel] = []
var _labels: Array[Label] = []
var _list: VBoxContainer
var _actions: HBoxContainer
var _scroll: ScrollContainer
var _status: Label
var _count: Label


func _init(moments: Array[Dictionary]) -> void:
	_moments = moments
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var blur := ColorRect.new()
	blur.set_anchors_preset(Control.PRESET_FULL_RECT)
	blur.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := Shader.new()
	shader.code = BLUR_SHADER
	var material := ShaderMaterial.new()
	material.shader = shader
	blur.material = material
	add_child(blur)

	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre)
	var window := PanelContainer.new()
	window.add_theme_stylebox_override(&"panel", StudioStyle.box(StudioStyle.PAPER, StudioStyle.BORDER, StudioStyle.SHADOW))
	centre.add_child(window)
	var margin := MarginContainer.new()
	for side in [&"margin_left", &"margin_right", &"margin_top", &"margin_bottom"]:
		margin.add_theme_constant_override(side, 18)
	window.add_child(margin)
	var column := VBoxContainer.new()
	column.custom_minimum_size.x = WIDTH
	column.add_theme_constant_override(&"separation", 8)
	margin.add_child(column)

	column.add_child(StudioStyle.text("Export highlights", 20, StudioStyle.INK, StudioStyle.display_font()))
	var where := StudioStyle.text("To %s" % HighlightPaths.root(), 11, StudioStyle.INK_SOFT, StudioStyle.mono_font())
	where.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	where.custom_minimum_size.x = WIDTH
	column.add_child(where)
	var rule := ColorRect.new()
	rule.color = StudioStyle.INK
	rule.custom_minimum_size = Vector2(0.0, 2.0)
	column.add_child(rule)

	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size = Vector2(WIDTH, LIST_HEIGHT)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override(&"separation", 4)
	_scroll.add_child(_list)

	_count = StudioStyle.text("", 12, StudioStyle.INK, StudioStyle.body_font())
	_count.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_count.custom_minimum_size.x = WIDTH
	column.add_child(_count)
	_actions = HBoxContainer.new()
	_actions.add_theme_constant_override(&"separation", 8)
	column.add_child(_actions)
	_status = StudioStyle.text("A / Enter toggle   ·   ← / → camera, format   ·   Y / E export   ·   B / Esc close", 11,
		StudioStyle.INK_SOFT, StudioStyle.mono_font())
	_status.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	_status.custom_minimum_size.x = WIDTH
	column.add_child(_status)
	_rebuild()


## Builds every row from the saved choices and the moments held. Called again
## whenever a type is switched, since that changes which moments are listed.
func _rebuild() -> void:
	for child in _list.get_children():
		child.queue_free()
	for child in _actions.get_children():
		child.queue_free()
	_entries.clear()
	_rows.clear()
	_labels.clear()
	for type: String in HighlightTable.TYPE_ORDER:
		_add_entry(_list, {"kind": "type", "type": type})
	_add_entry(_list, {"kind": "format"})
	for m in _moments:
		if HighlightPrefs.type_on(String(m.type)):
			_add_entry(_list, {"kind": "moment", "moment": m})
	for kind in ["export", "close"]:
		var panel := _add_entry(_actions, {"kind": kind})
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cursor = clampi(_cursor, 0, _entries.size() - 1)
	_refresh()


func _add_entry(parent: Control, entry: Dictionary) -> Panel:
	var index := _entries.size()
	var panel := Panel.new()
	panel.custom_minimum_size = Vector2(0.0, ROW_HEIGHT)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.gui_input.connect(_on_row_input.bind(index))
	var label := StudioStyle.text("", 13, StudioStyle.INK, StudioStyle.body_font())
	label.position = Vector2(10.0, 7.0)
	label.size = Vector2(WIDTH - 20.0, 20.0)
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	panel.add_child(label)
	parent.add_child(panel)
	_entries.append(entry)
	_rows.append(panel)
	_labels.append(label)
	return panel


func _camera_label(preset: String) -> String:
	return String(ReplayStage.PRESET_LABELS.get(preset, preset))


## How many clips the export would make, and the frames they'd render.
func _plan() -> Dictionary:
	var picked := selected()
	var frames := 0
	for m in picked:
		frames += (m.clip as ReplayClip).frame_count()
	var shapes := 2 if HighlightPrefs.aspect() == "both" else 1
	return {"clips": picked.size(), "frames": frames * shapes}


func _refresh() -> void:
	var plan := _plan()
	for i in _rows.size():
		var on := i == _cursor and not _exporting
		_rows[i].add_theme_stylebox_override(&"panel",
			StudioStyle.box(StudioStyle.INK if on else StudioStyle.WHITE, 2, StudioStyle.SHADOW if on else 0))
		_labels[i].add_theme_color_override(&"font_color", StudioStyle.LIME if on else StudioStyle.INK)
		var entry := _entries[i]
		match String(entry.kind):
			"type":
				var type: String = entry.type
				var spec: Dictionary = HighlightTable.TYPES[type]
				var held := Highlights.count_of(type)
				var ticked := 0
				for m in _moments:
					if m.type == type and m.keep:
						ticked += 1
				_labels[i].text = "%s  %s   %d held, %d ticked   ·   camera ◂ %s ▸" % [
					"■" if HighlightPrefs.type_on(type) else "□", String(spec.plural), held,
					ticked if HighlightPrefs.type_on(type) else 0, _camera_label(HighlightPrefs.camera_for(type))]
			"format":
				_labels[i].text = "FORMAT   ◂ %s ▸      (16:9 alone is half the render)" % String(
					HighlightTable.ASPECT_LABELS[HighlightPrefs.aspect()])
			"moment":
				var m: Dictionary = entry.moment
				var camera := String(m.get("camera", HighlightPrefs.camera_for(String(m.type))))
				_labels[i].text = "%s  %s   %s   ◂ %s ▸   %s" % ["■" if m.keep else "□", String(m.label),
					HighlightsScreen.clock_text(m), _camera_label(camera), String(m.caption)]
			"export":
				_labels[i].text = "EXPORT %d CLIP%s" % [plan.clips, "" if plan.clips == 1 else "S"]
			_:
				_labels[i].text = "CLOSE" if _done else "CANCEL"
	_count.text = "%d clip%s ticked  ·  %d frames to render (%.0f s of video, %s)" % [plan.clips,
		"" if plan.clips == 1 else "s", plan.frames, float(plan.frames) / HighlightTable.EXPORT_FPS,
		String(HighlightTable.ASPECT_LABELS[HighlightPrefs.aspect()])]


## The moments that will render: ticked, and of a type that's switched on.
func selected() -> Array[Dictionary]:
	return Highlights.kept()


func set_progress(text: String) -> void:
	_status.text = text


## Export over (or cancelled): show where it went; any confirm closes.
func finish(text: String) -> void:
	_exporting = false
	_done = true
	_cursor = _entries.size() - 1
	_status.text = text
	_refresh()


## Returns true if the event was used.
func handle_input(event: InputEvent) -> bool:
	var back := event.is_action_pressed(&"pause") or event.is_action_pressed(&"ui_cancel") \
		or event.is_action_pressed(&"decline")
	if _exporting:
		if back:
			cancel_requested.emit()
		return true
	if back:
		_close()
	elif event.is_action_pressed(&"ui_up") or event.is_action_pressed(&"move_forward"):
		_move(-1)
	elif event.is_action_pressed(&"ui_down") or event.is_action_pressed(&"move_back"):
		_move(1)
	elif event.is_action_pressed(&"ui_left") or event.is_action_pressed(&"move_left"):
		_sideways(-1)
	elif event.is_action_pressed(&"ui_right") or event.is_action_pressed(&"move_right"):
		_sideways(1)
	elif event.is_action_pressed(&"ui_accept") or event.is_action_pressed(&"confirm") \
			or _key(event, KEY_SPACE) or _pad(event, JOY_BUTTON_X):
		_activate(_cursor)
	elif _key(event, KEY_E) or _pad(event, JOY_BUTTON_Y):
		_start()
	else:
		return false
	_refresh()
	return true


func _move(step: int) -> void:
	_cursor = clampi(_cursor + step, 0, _rows.size() - 1)
	if String(_entries[_cursor].kind) in ["type", "format", "moment"]:
		_scroll.ensure_control_visible(_rows[_cursor])


## Left / right: change the row's camera or the format; on the action row,
## swap between EXPORT and CANCEL.
func _sideways(step: int) -> void:
	var entry := _entries[_cursor]
	match String(entry.kind):
		"type":
			var type: String = entry.type
			HighlightPrefs.set_camera(type, _cycled(ReplayStage.CAMERA_PRESETS, HighlightPrefs.camera_for(type), step))
		"format":
			HighlightPrefs.set_aspect(_cycled(HighlightTable.ASPECTS, HighlightPrefs.aspect(), step))
		"moment":
			var m: Dictionary = entry.moment
			m["camera"] = _cycled(ReplayStage.CAMERA_PRESETS,
				String(m.get("camera", HighlightPrefs.camera_for(String(m.type)))), step)
		_:
			var first := _entries.size() - 2
			_cursor = first + (1 - (_cursor - first))


static func _cycled(options: Array, current: String, step: int) -> String:
	return String(options[posmod(options.find(current) + step, options.size())])


func _activate(index: int) -> void:
	var entry := _entries[index]
	match String(entry.kind):
		"type":
			var type: String = entry.type
			Highlights.set_type_on(type, not HighlightPrefs.type_on(type))
			_rebuild()
		"format":
			HighlightPrefs.set_aspect(_cycled(HighlightTable.ASPECTS, HighlightPrefs.aspect(), 1))
		"moment":
			if not _done:
				var m: Dictionary = entry.moment
				m["keep"] = not bool(m.keep)
		"export":
			_start()
		_:
			_close()


func _start() -> void:
	var picked := selected()
	if picked.is_empty():
		_status.text = "Tick at least one clip to export."
		return
	_exporting = true
	_done = false
	_status.text = "Starting export..."
	export_requested.emit(picked)


func _close() -> void:
	closed.emit()
	queue_free()


func _on_row_input(event: InputEvent, index: int) -> void:
	var click := event as InputEventMouseButton
	if _exporting or click == null or not click.pressed or click.button_index != MOUSE_BUTTON_LEFT:
		return
	if index >= _entries.size():
		return
	_cursor = index
	_activate(index)
	if is_inside_tree() and not is_queued_for_deletion():
		_refresh()


static func _key(event: InputEvent, keycode: Key) -> bool:
	var key := event as InputEventKey
	return key != null and key.pressed and not key.echo and key.physical_keycode == keycode


static func _pad(event: InputEvent, button: JoyButton) -> bool:
	var pad := event as InputEventJoypadButton
	return pad != null and pad.pressed and pad.button_index == button
