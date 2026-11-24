class_name HighlightExportDialog
extends Control

## The Highlights screen's export window. The page behind is blurred and
## dimmed.
##
## Simplified 2026-11-17 (playtest: "the export is not that simple... just
## showing the types of clips we have selected, not every single individual
## one"). One export makes the match video for the daily series:
##   match_16x9.mp4    the whole match, breaks and dead time cut
##   highlight.mp4     every ticked clip of the ticked types, in match order
##   match_video.json  the timeline (markers, moments, cameras) for the
##                     video tool
## so the window lists only what changes that, top to bottom:
##   a row per clip TYPE, in HighlightTable.TYPE_ORDER: its tick, how many
##     clips it adds and how long they run, and its camera (left / right);
##   one row for the old per-clip files (off by default; the video tool's
##     current reader still uses them);
##   EXPORT and CLOSE.
## Single moments aren't listed: untick one on the Highlights page (Space /
## X) to leave it out. Type ticks and cameras are saved (HighlightPrefs).
##
## Without a full-match recording (full-match recording off, or a match from
## before it existed) there's nothing to cut the videos from, so the export
## falls back to separate clip files and says so.
##
## Pad and keyboard: ↑/↓ move, ←/→ change a camera, A/Enter (or X/Space)
## toggles or presses EXPORT/CLOSE, Y/E exports straight away, B/Esc closes
## (or cancels a running export). Mouse: click a row. The screen forwards
## its input here while the window is open (handle_input).

signal export_requested(moments: Array[Dictionary])
signal cancel_requested
signal closed

const WIDTH := 600.0
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
## One per row, top to bottom: {kind: "type"|"clips"|"export"|"close", type}.
var _entries: Array[Dictionary] = []
var _rows: Array[Panel] = []
var _labels: Array[Label] = []
## Type rows only: the clip count and the camera, each at its own x so the
## columns line up (the body font isn't fixed-width). Null on other rows.
var _amounts: Array = []
var _cameras: Array = []
const AMOUNT_X := 190.0
const CAMERA_X := 370.0
var _list: VBoxContainer
var _actions: HBoxContainer
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

	column.add_child(StudioStyle.text("Export the match", 20, StudioStyle.INK, StudioStyle.display_font()))
	var makes := StudioStyle.text(_makes_text(), 12, StudioStyle.INK, StudioStyle.body_font())
	makes.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	makes.custom_minimum_size.x = WIDTH
	column.add_child(makes)
	_rule(column)

	column.add_child(StudioStyle.text("CLIPS IN THE HIGHLIGHT VIDEO", 11, StudioStyle.INK_SOFT, StudioStyle.mono_font()))
	_list = VBoxContainer.new()
	_list.add_theme_constant_override(&"separation", 4)
	column.add_child(_list)
	_rule(column)

	_count = StudioStyle.text("", 12, StudioStyle.INK, StudioStyle.body_font())
	_count.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_count.custom_minimum_size.x = WIDTH
	column.add_child(_count)
	_actions = HBoxContainer.new()
	_actions.add_theme_constant_override(&"separation", 8)
	column.add_child(_actions)
	_status = StudioStyle.text("A / Enter tick   ·   ← / → camera   ·   Y / E export   ·   B / Esc close", 11,
		StudioStyle.INK_SOFT, StudioStyle.mono_font())
	_status.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	_status.custom_minimum_size.x = WIDTH
	column.add_child(_status)
	var where := StudioStyle.text("To %s" % HighlightPaths.root(), 11, StudioStyle.INK_SOFT, StudioStyle.mono_font())
	where.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	where.custom_minimum_size.x = WIDTH
	column.add_child(where)
	_rebuild()


static func _rule(parent: Control) -> void:
	var rule := ColorRect.new()
	rule.color = StudioStyle.INK
	rule.custom_minimum_size = Vector2(0.0, 2.0)
	parent.add_child(rule)


static func has_full_match() -> bool:
	return not Highlights.full_match.is_empty() and FileAccess.file_exists(String(Highlights.full_match.replay))


func _makes_text() -> String:
	if not has_full_match():
		return "This match wasn't recorded in full, so there's no match video to cut. The export saves each ticked clip as its own 16:9 file instead."
	return "Makes match_16x9.mp4 (the whole match, breaks and dead time cut), highlight.mp4 (the ticked clips below, in match order) and match_video.json (the timeline for the video tool). Both videos use the cameras set here and on the timeline."


## Builds every row. Called again whenever a type is switched.
func _rebuild() -> void:
	for child in _list.get_children():
		child.queue_free()
	for child in _actions.get_children():
		child.queue_free()
	_entries.clear()
	_rows.clear()
	_labels.clear()
	_amounts.clear()
	_cameras.clear()
	for type: String in HighlightTable.TYPE_ORDER:
		_add_entry(_list, {"kind": "type", "type": type})
	_add_entry(_list, {"kind": "framing"})
	if has_full_match():
		_add_entry(_list, {"kind": "clips"})
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
	var amount: Label = null
	var camera: Label = null
	if String(entry.kind) == "type":
		label.size.x = AMOUNT_X - 20.0
		amount = StudioStyle.text("", 13, StudioStyle.INK, StudioStyle.body_font())
		amount.position = Vector2(AMOUNT_X, 7.0)
		panel.add_child(amount)
		camera = StudioStyle.text("", 13, StudioStyle.INK, StudioStyle.body_font())
		camera.position = Vector2(CAMERA_X, 7.0)
		panel.add_child(camera)
	parent.add_child(panel)
	_entries.append(entry)
	_rows.append(panel)
	_labels.append(label)
	_amounts.append(amount)
	_cameras.append(camera)
	return panel


func _camera_label(preset: String) -> String:
	return String(ReplayStage.PRESET_LABELS.get(preset, preset))


## The clips of `type` that would go in, and how long they run together
## (seconds; overlapping clips counted once by the video, so this is an
## upper bound).
func _type_plan(type: String) -> Dictionary:
	var clips := 0
	var seconds := 0.0
	for m in _moments:
		if m.type == type and m.keep:
			clips += 1
			seconds += float(m.get("duration_s", 0.0))
	return {"clips": clips, "seconds": seconds}


static func _mmss(seconds: float) -> String:
	return "%d:%02d" % [int(seconds) / 60, int(seconds) % 60]


func _refresh() -> void:
	var total_clips := 0
	var total_seconds := 0.0
	for i in _rows.size():
		var on := i == _cursor and not _exporting
		_rows[i].add_theme_stylebox_override(&"panel",
			StudioStyle.box(StudioStyle.INK if on else StudioStyle.WHITE, 2, StudioStyle.SHADOW if on else 0))
		for label in [_labels[i], _amounts[i], _cameras[i]]:
			if label != null:
				(label as Label).add_theme_color_override(&"font_color", StudioStyle.LIME if on else StudioStyle.INK)
		var entry := _entries[i]
		match String(entry.kind):
			"type":
				var type: String = entry.type
				var spec: Dictionary = HighlightTable.TYPES[type]
				var ticked := HighlightPrefs.type_on(type)
				var plan := _type_plan(type)
				var held := Highlights.count_of(type)
				var amount := "none this match" if held == 0 else "%d clip%s  ·  %s" % [plan.clips,
					"" if plan.clips == 1 else "s", _mmss(plan.seconds)]
				if ticked:
					total_clips += int(plan.clips)
					total_seconds += float(plan.seconds)
				_labels[i].text = "%s  %s" % ["■" if ticked else "□", String(spec.plural)]
				(_amounts[i] as Label).text = amount if ticked else ("%d held" % held if held > 0 else "none this match")
				(_cameras[i] as Label).text = "camera  ◂ %s ▸" % _camera_label(HighlightPrefs.camera_for(type))
			"framing":
				# The highlight cameras' own zoom (HighlightTable.FRAMINGS):
				# how tall a player is at least, on every camera.
				var framing := HighlightPrefs.framing()
				_labels[i].text = "CAMERA FRAMING  ◂ %s ▸   players at least %d%% of the frame's height" % [
					String(HighlightTable.FRAMING_LABELS[framing]),
					roundi(float(HighlightTable.FRAMING_FRACTION[framing]) * 100.0)]
			"clips":
				_labels[i].text = "%s  Also save each clip as its own file (old format, for the current video tool)" % [
					"■" if HighlightPrefs.clip_files() else "□"]
			"export":
				_labels[i].text = "EXPORT"
			_:
				_labels[i].text = "CLOSE" if _done else "CANCEL" if _exporting else "CLOSE"
	if has_full_match():
		var recorded := float(Highlights.full_match.get("frames", 0)) / float(HighlightTable.RECORD_FPS)
		_count.text = "Highlight video: %d clip%s, up to %s   ·   Full match: %s recorded, less once the dead time is cut" % [
			total_clips, "" if total_clips == 1 else "s", _mmss(total_seconds), _mmss(recorded)]
	else:
		_count.text = "%d clip%s to save (%s)" % [total_clips, "" if total_clips == 1 else "s", _mmss(total_seconds)]


## The moments that will be exported: ticked, of a ticked type.
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
		_cursor = clampi(_cursor - 1, 0, _rows.size() - 1)
	elif event.is_action_pressed(&"ui_down") or event.is_action_pressed(&"move_back"):
		_cursor = clampi(_cursor + 1, 0, _rows.size() - 1)
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
	if is_inside_tree() and not is_queued_for_deletion():
		_refresh()
	return true


## Left / right: a type row's camera; on the action row, swap EXPORT and
## CLOSE.
func _sideways(step: int) -> void:
	var entry := _entries[_cursor]
	match String(entry.kind):
		"type":
			var type: String = entry.type
			HighlightPrefs.set_camera(type, _cycled(ReplayStage.CAMERA_PRESETS, HighlightPrefs.camera_for(type), step))
			# A moment's own camera (set on the page) gives way to the type's
			# new one: the window shows types, so the type's camera is the one
			# the export should use.
			for m in _moments:
				if m.type == type:
					m.erase("camera")
		"framing":
			HighlightPrefs.set_framing(_cycled(HighlightTable.FRAMINGS, HighlightPrefs.framing(), step))
		"clips":
			pass
		_:
			var first := _entries.size() - 2
			_cursor = first + (1 - (_cursor - first))


static func _cycled(options: Array, current: String, step: int) -> String:
	return String(options[posmod(options.find(current) + step, options.size())])


func _activate(index: int) -> void:
	var entry := _entries[index]
	match String(entry.kind):
		"type":
			if not _done:
				var type: String = entry.type
				Highlights.set_type_on(type, not HighlightPrefs.type_on(type))
				_rebuild()
		"clips":
			HighlightPrefs.set_clip_files(not HighlightPrefs.clip_files())
		"framing":
			HighlightPrefs.set_framing(_cycled(HighlightTable.FRAMINGS, HighlightPrefs.framing(), 1))
		"export":
			_start()
		_:
			_close()


func _start() -> void:
	if _done:
		_close()
		return
	var picked := selected()
	if picked.is_empty() and not has_full_match():
		_status.text = "Tick at least one type with clips to export."
		return
	_exporting = true
	_done = false
	_status.text = "Starting export..."
	_refresh()
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
