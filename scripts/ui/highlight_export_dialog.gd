class_name HighlightExportDialog
extends Control

## The Highlights screen's export window (playtest 2026-11-10: "when I
## click export let me select which clips to export"). The page behind is
## blurred and dimmed; the window lists every moment with a tick box, then
## EXPORT and CANCEL rows. The ticks are the moments' own `keep` flags, so
## what you ticked on the page arrives pre-ticked here and stays in step.
##
## Pad and keyboard: ↑/↓ move, A/Enter (or X/Space) ticks a moment or
## presses EXPORT/CANCEL, Y/E exports straight away, B/Esc closes (or
## cancels a running export). Mouse: click a row. The screen forwards its
## input here while the window is open (handle_input).

signal export_requested(moments: Array[Dictionary])
signal cancel_requested
signal closed

const WIDTH := 560.0
const LIST_HEIGHT := 380.0
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
var _rows: Array[Panel] = []
var _labels: Array[Label] = []
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
	_scroll.custom_minimum_size = Vector2(WIDTH, minf(LIST_HEIGHT, (ROW_HEIGHT + 4.0) * moments.size()))
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(_scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override(&"separation", 4)
	_scroll.add_child(list)
	for i in moments.size():
		list.add_child(_row(i))

	_count = StudioStyle.text("", 12, StudioStyle.INK, StudioStyle.body_font())
	column.add_child(_count)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override(&"separation", 8)
	column.add_child(actions)
	for i in 2:
		var panel := _row(moments.size() + i)
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		actions.add_child(panel)
	_status = StudioStyle.text("A / Enter tick   ·   Y / E export   ·   B / Esc close", 11,
		StudioStyle.INK_SOFT, StudioStyle.mono_font())
	_status.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	_status.custom_minimum_size.x = WIDTH
	column.add_child(_status)
	_refresh()


func _row(index: int) -> Panel:
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
	_rows.append(panel)
	_labels.append(label)
	return panel


func _refresh() -> void:
	var picked := 0
	for m in _moments:
		if m.keep:
			picked += 1
	for i in _rows.size():
		var on := i == _cursor and not _exporting
		_rows[i].add_theme_stylebox_override(&"panel",
			StudioStyle.box(StudioStyle.INK if on else StudioStyle.WHITE, 2, StudioStyle.SHADOW if on else 0))
		_labels[i].add_theme_color_override(&"font_color", StudioStyle.LIME if on else StudioStyle.INK)
		if i < _moments.size():
			var m := _moments[i]
			_labels[i].text = "%s  %s   %s   %s" % ["■" if m.keep else "□", String(m.label),
				HighlightsScreen.clock_text(m), String(m.caption)]
		elif i == _moments.size():
			_labels[i].text = "EXPORT %d CLIP%s" % [picked, "" if picked == 1 else "S"]
		else:
			_labels[i].text = "CLOSE" if _done else "CANCEL"
	_count.text = "%d of %d selected  ·  each exports 16:9 and 9:16" % [picked, _moments.size()]


func selected() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for m in _moments:
		if m.keep:
			out.append(m)
	return out


func set_progress(text: String) -> void:
	_status.text = text


## Export over (or cancelled): show where it went; any confirm closes.
func finish(text: String) -> void:
	_exporting = false
	_done = true
	_cursor = _moments.size() + 1
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
	elif event.is_action_pressed(&"ui_left") or event.is_action_pressed(&"ui_right"):
		if _cursor >= _moments.size():
			_cursor = _moments.size() + (1 - (_cursor - _moments.size()))
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
	if _cursor < _moments.size():
		_scroll.ensure_control_visible(_rows[_cursor])


func _activate(index: int) -> void:
	if index < _moments.size():
		if not _done:
			_moments[index].keep = not bool(_moments[index].keep)
	elif index == _moments.size():
		_start()
	else:
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
	_cursor = index
	_activate(index)
	if is_inside_tree():
		_refresh()


static func _key(event: InputEvent, keycode: Key) -> bool:
	var key := event as InputEventKey
	return key != null and key.pressed and not key.echo and key.physical_keycode == keycode


static func _pad(event: InputEvent, button: JoyButton) -> bool:
	var pad := event as InputEventJoypadButton
	return pad != null and pad.pressed and pad.button_index == button
