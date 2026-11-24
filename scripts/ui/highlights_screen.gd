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
## A TYPES grid above the list has a toggle per moment type with a count
## (keys 1-8, or click). A type that's off isn't listed and isn't exported;
## switching it on lists it and ticks its best few (Highlights.set_type_on).
## The choices are saved (HighlightPrefs). The pad reaches them, the export
## format and each type's default camera in the export window (Y).
##
## The replay is a ReplayStage drawn through a SubViewport that fills the
## area right of the column, so the picture is centred in the space you can
## see, and the portrait preview is the same 9:16 framing the export uses.
##
## MATCH view (T / View; docs/HIGHLIGHTS_FULLGAME_PLAN.md phase 3): when the
## whole match was recorded, the stage plays the full recording instead,
## timed as the full-match video (FullMatchCut: breaks and dead time cut),
## with a MatchTimeline under it: every moment as a band, every event as a
## tick, quarters marked. Click or drag it to seek; up / down jump between
## moments (and select them in the list). It shows exactly what
## export_full_match will render, frame for frame, cameras included.
##
## Cameras (MatchCameraPlan): inside a moment's band left / right change that
## moment's camera (the same choice its clip export uses); outside every band
## they change the match camera (saved). Each band carries its camera's
## letter. A change of stretch is a cut, as in the render.

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
var _index := -1
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
var _type_panels: Array[Panel] = []
var _type_labels: Array[Label] = []
var _moments_head: Label
var _empty_text: Label
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
var _ui_root: Control
var _dialog: HighlightExportDialog

# MATCH view (see the header). The full recording is loaded on first use
# (~100 MB) and kept while the screen is open.
var _match_mode := false
var _full: ReplayClip
var _cut: FullMatchCut
var _match_t := 0.0                 ## seconds into the full-match video
var _plan: MatchCameraPlan
var _match_range := -1              ## keep range last shown: the camera snaps on a cut
var _match_stretch := -2            ## plan stretch last shown (-1 the match camera)
var _moment_video := {}             ## moment index -> {from, to, frame}, video frames
var _timeline: MatchTimeline
var _match_hint: Label


func _ready() -> void:
	_moments = Highlights.moments
	_stage = ReplayStage.new()
	add_child(_stage)
	_exporter = HighlightExporter.new()
	_exporter.stage = _stage
	add_child(_exporter)
	_exporter.progress.connect(_on_export_progress)
	_build_ui()
	_apply_filter()


func _process(delta: float) -> void:
	if _exporter.busy:
		return
	if _match_mode:
		if _playing:
			_match_t = minf(_match_t + delta * float(SPEEDS[_speed_index]), _match_duration())
			if _match_t >= _match_duration():
				_playing = false
				_refresh()
		_show_match(false, delta * float(SPEEDS[_speed_index]))
		return
	if not _any_shown():
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
	if _match_mode:
		return _plan.preset(_match_stretch) if _plan != null else HighlightPrefs.match_camera()
	return String(_moments[_index].get("camera", _stage.default_preset()))


# ── MATCH view ──────────────────────────────────────────────────────

func _has_full_match() -> bool:
	return not Highlights.full_match.is_empty() and FileAccess.file_exists(String(Highlights.full_match.replay))


func _match_duration() -> float:
	return float(maxi(_cut.video_frames - 1, 0)) / _cut.fps if _cut != null else 0.0


## T / View: in and out of the MATCH view. Loads the recording the first time.
func _toggle_match() -> void:
	if _match_mode:
		_match_mode = false
		_timeline.visible = false
		_set_bar_visible(true)
		_apply_filter()
		if _index >= 0 and _index < _moments.size() and _shown(_index):
			_stage.load_clip(_moments[_index].clip)
			_show_frame(true)
		return
	if not _has_full_match():
		_status_label.text = "No full-match recording for this match (it's made while you play, when full-match recording is on)."
		return
	if _full == null:
		_status_label.text = "Loading the full match..."
		_busy = true
		await get_tree().process_frame
		await get_tree().process_frame
		var ok := _load_full()
		_busy = false
		if not ok:
			_status_label.text = "The full-match recording couldn't be read."
			return
		_status_label.text = ""
	_match_mode = true
	_stage.load_clip(_full)
	_match_range = -1
	_rebuild_plan()
	_overlay.visible = true
	_view_container.visible = true
	_empty_card.visible = false
	_timeline.visible = true
	_set_bar_visible(false)
	if _moment_video.has(_index):
		_match_t = float(_moment_video[_index].from) / _cut.fps
	_show_match(true)
	_refresh()


func _load_full() -> bool:
	var info: Dictionary = Highlights.full_match
	var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(String(info.json)))
	_full = ReplayClip.load_file(String(info.replay))
	if not (doc is Dictionary) or _full == null or _full.frame_count() == 0:
		_full = null
		return false
	# The same protected stretches the export uses, so the timeline and
	# the exported video agree frame for frame.
	_cut = FullMatchCut.build(_full, doc,
		FullMatchCut.protect_moments(Highlights.kept(), float(doc.get("fps", HighlightTable.RECORD_FPS))))
	var quarters: Array = []
	var seen := {}
	for r in _cut.keep:
		if not seen.has(int(r.quarter)):
			seen[int(r.quarter)] = true
			quarters.append({"video_from": int(r.video_from), "quarter": int(r.quarter)})
	var markers: Array = []
	for ev: Dictionary in doc.get("events", []):
		markers.append({"frame": int(_cut.video_frame(int(ev.frame)).frame), "kind": String(ev.kind)})
	_moment_video.clear()
	for i in _moments.size():
		var m := _moments[i]
		if m.has("match_from"):
			_moment_video[i] = {"from": int(_cut.video_frame(int(m.match_from)).frame),
				"to": int(_cut.video_frame(int(m.match_to)).frame),
				"frame": int(_cut.video_frame(int(m.match_frame)).frame)}
	_timeline.frames = _cut.video_frames
	_timeline.quarters = quarters
	_timeline.markers = markers
	return true


func _show_match(snap: bool, delta := 1.0 / 60.0) -> void:
	if _cut == null or _cut.keep.is_empty():
		return
	var video_f := _match_t * _cut.fps
	var r := _cut.range_at(int(video_f))
	var range_: Dictionary = _cut.keep[r]
	if r != _match_range:
		snap = true    # a cut: jump, don't ease across it
		_match_range = r
	var source := _cut.source_frame(range_, clampf(video_f - float(range_.video_from), 0.0, float(range_.video_frames) - 1.0))
	var stretch := _plan.at(int(round(source)))
	if stretch != _match_stretch:
		_stage.set_context(_plan.context(stretch))
		_match_stretch = stretch
		snap = true    # a new stretch is a new camera: a cut
		_refresh_match_card()
	_stage.apply(source / _full.fps())
	_stage.frame_camera(_camera, _plan.preset(stretch), _portrait, _match_t, maxf(delta, 0.0001), snap)
	_timeline.set_playhead(int(video_f))
	var head := _full.frames[int(source)]
	var clock := head.decode_float(0)
	var elapsed := maxf(0.0, Tuning.QUARTER_LENGTH - clock)
	_time_label.text = "Q%d %d:%02d   %d:%02d / %d:%02d" % [head.decode_u8(4), int(elapsed) / 60, int(elapsed) % 60,
		int(_match_t) / 60, int(_match_t) % 60, int(_match_duration()) / 60, int(_match_duration()) % 60]


func _seek_match(video_frame: int) -> void:
	_match_t = clampf(float(video_frame) / _cut.fps, 0.0, _match_duration())
	_show_match(true)


## The listed moment whose band starts next after (or last before) the
## playhead, going `step`; -1 when there's none that way.
func _next_moment_on_timeline(step: int) -> int:
	var here := int(_match_t * _cut.fps)
	var best := -1
	var best_from := -1
	for i: int in _moment_video:
		if not _shown(i):
			continue
		var from := int(_moment_video[i].from)
		if step > 0 and from > here + 1 and (best < 0 or from < best_from):
			best = i
			best_from = from
		elif step < 0 and from < here - 1 and (best < 0 or from > best_from):
			best = i
			best_from = from
	return best


## The camera plan from the listed moments and the match camera; again after
## any camera or type change. The next frame snaps to whatever it now says.
func _rebuild_plan() -> void:
	_plan = MatchCameraPlan.from_moments(Highlights.kept(), HighlightPrefs.match_camera())
	_match_stretch = -2


func _set_bar_visible(on: bool) -> void:
	_bar_back.visible = on
	_match_hint.visible = not on


func _refresh_timeline() -> void:
	var bands: Array = []
	for i: int in _moment_video:
		if _shown(i):
			var camera := String(_moments[i].get("camera", HighlightPrefs.camera_for(String(_moments[i].type))))
			bands.append({"from": _moment_video[i].from, "to": _moment_video[i].to,
				"kept": bool(_moments[i].keep), "selected": i == _index, "tag": camera.substr(0, 1).to_upper()})
	_timeline.moments = bands
	_timeline.queue_redraw()


## Whether moment `i` is listed: its type is switched on.
func _shown(i: int) -> bool:
	return HighlightPrefs.type_on(String(_moments[i].type))


func _any_shown() -> bool:
	for i in _moments.size():
		if _shown(i):
			return true
	return false


## The next listed moment from `from` going `step` (+1 / -1), wrapping, or -1.
func _next_shown(from: int, step: int) -> int:
	for k in range(1, _moments.size() + 1):
		var i := posmod(from + step * k, _moments.size())
		if _shown(i):
			return i
	return -1


## Switches a moment type on or off (saved), ticking or unticking its moments,
## and brings the list into line.
func _toggle_type(slot: int) -> void:
	if slot < 0 or slot >= HighlightTable.TYPE_ORDER.size():
		return
	var type: String = HighlightTable.TYPE_ORDER[slot]
	Highlights.set_type_on(type, not HighlightPrefs.type_on(type))
	_apply_filter()


## After a type changes (or the export window closes): hides the entries of
## types that are off, moves the selection onto a listed one, and shows or
## hides the replay and the empty card.
func _apply_filter() -> void:
	for i in _entry_panels.size():
		_entry_panels[i].visible = _shown(i)
	var any := _any_shown()
	if _match_mode:
		_rebuild_plan()
	_overlay.visible = any or _match_mode
	_view_container.visible = any or _match_mode
	_empty_card.visible = not any and not _match_mode
	if not any:
		_empty_text.text = "No highlights from this match yet.\nPlay a Full Game: goals, big marks, tackles and long kicks are picked out as it goes." \
			if _moments.is_empty() else "Every moment type is switched off.\nTurn some back on above (keys 1-8)."
		_playing = false
	elif _index < 0 or _index >= _moments.size() or not _shown(_index):
		_select(_next_shown(maxi(_index, 0) - 1, 1))
	_refresh()


# ── Input ───────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if _busy:
		return
	if is_instance_valid(_dialog):
		if _dialog.handle_input(event):
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"pause") or event.is_action_pressed(&"ui_cancel") \
			or event.is_action_pressed(&"decline"):
		if _match_mode:
			_toggle_match()
		else:
			_leave()
	elif _key(event, KEY_T) or _pad_button(event, JOY_BUTTON_BACK):
		_toggle_match()
	elif _type_key(event) >= 0:
		_toggle_type(_type_key(event))
	elif _match_mode and (event.is_action_pressed(&"ui_up") or event.is_action_pressed(&"move_forward")):
		_select(_next_moment_on_timeline(-1))
	elif _match_mode and (event.is_action_pressed(&"ui_down") or event.is_action_pressed(&"move_back")):
		_select(_next_moment_on_timeline(1))
	elif _match_mode and (event.is_action_pressed(&"ui_accept") or event.is_action_pressed(&"confirm")):
		_playing = not _playing
		if _playing and _match_t >= _match_duration():
			_match_t = 0.0
	elif not _any_shown() and not _match_mode:
		return
	elif event.is_action_pressed(&"ui_up") or event.is_action_pressed(&"move_forward"):
		_select(_next_shown(_index, -1))
	elif event.is_action_pressed(&"ui_down") or event.is_action_pressed(&"move_back"):
		_select(_next_shown(_index, 1))
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
	elif (_key(event, KEY_SPACE) or _pad_button(event, JOY_BUTTON_X)) and _index >= 0:
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


## Which type slot a number key 1-8 asks for, or -1.
func _type_key(event: InputEvent) -> int:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return -1
	var slot := int(key.physical_keycode) - int(KEY_1)
	return slot if slot >= 0 and slot < HighlightTable.TYPE_ORDER.size() else -1


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
	if _match_mode:
		_match_t = clampf(_match_t + direction * amount * (5.0 if _playing else 1.0), 0.0, _match_duration())
		_show_match(true)
		return
	_t = clampf(_t + direction * amount, 0.0, _stage.duration())
	_hold = 0.0
	_show_frame(true)


func _select(index: int) -> void:
	if index < 0 or index >= _moments.size():
		return
	if _match_mode:
		# In the MATCH view a moment is a place on the timeline.
		_index = index
		if _moment_video.has(index):
			_seek_match(int(_moment_video[index].from))
		_scroll_to(_index)
		return
	_index = index
	_stage.load_clip(_moments[_index].clip)
	_t = 0.0
	_hold = 0.0
	_playing = true
	_show_frame(true)
	_scroll_to(_index)


func _cycle_camera(step: int) -> void:
	var presets := ReplayStage.CAMERA_PRESETS
	var i := presets.find(_preset())
	if _match_mode:
		var next: String = presets[posmod(i + step, presets.size())]
		if _match_stretch >= 0:
			# Inside a moment's band: that moment's camera.
			var id: Variant = _plan.stretches[_match_stretch].id
			for m in _moments:
				if m.get("id") == id:
					m["camera"] = next
		else:
			HighlightPrefs.set_match_camera(next)
		_rebuild_plan()
		_show_match(true)
		return
	_moments[_index].camera = presets[posmod(i + step, presets.size())]
	_show_frame(true)


func _leave() -> void:
	_busy = true
	SceneWipe.change_scene(Highlights.return_scene if Highlights.return_scene != "" else MENU_SCENE)


## Opens the export window over a blurred page: pick the clips there, and
## its EXPORT renders them into the highlights folder.
func _export() -> void:
	if is_instance_valid(_dialog):
		return
	_playing = false
	_dialog = HighlightExportDialog.new(_moments)
	_dialog.export_requested.connect(_run_export)
	_dialog.cancel_requested.connect(_exporter.cancel)
	_dialog.closed.connect(_apply_filter)
	_ui_root.add_child(_dialog)


func _run_export(picked: Array[Dictionary]) -> void:
	var folder := await _exporter.export_moments(picked, Highlights.match_info, {"footage": Highlights.footage})
	var made: Array[String] = []
	for file: String in ["match_16x9.mp4", "highlight.mp4"]:
		if FileAccess.file_exists(folder.path_join(file)):
			made.append(file)
	var text := "Exported %s to\n%s" % [" and ".join(made) if not made.is_empty() else "%d clip%s" % [picked.size(),
		"" if picked.size() == 1 else "s"], folder]
	_status_label.text = text
	if is_instance_valid(_dialog):
		_dialog.finish(text + "\nA / Enter or B / Esc closes.")
	# The stage was driven by the exporter: back to the selected moment (or
	# the full match, in the MATCH view).
	if _match_mode:
		_stage.load_clip(_full)
		_match_range = -1
		_show_match(true)
	else:
		_select(_index)
	_playing = false
	_refresh()


func _on_export_progress(text: String, fraction: float) -> void:
	if is_instance_valid(_dialog):
		_dialog.set_progress("%s  %d%%   ·   Esc / B cancels" % [text, int(fraction * 100.0)])


# ── UI ──────────────────────────────────────────────────────────────

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)
	_ui_root = root

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
			{"keys": "1-8", "label": "Types"},
			{"keys": "← / →", "label": "Camera"},
			{"keys": "T", "label": "Match"},
			{"keys": "E", "label": "Export"},
			{"keys": "Esc", "label": "Back"},
		],
		InputManager.Device.GAMEPAD: [
			{"keys": "D-Pad ↕", "label": "Select"},
			{"keys": "A", "label": "Play / pause"},
			{"keys": "X", "label": "Keep"},
			{"keys": "LB / RB", "label": "Camera"},
			{"keys": "View", "label": "Match"},
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

	_section(_list, "TYPES  (keys 1-8)")
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override(&"h_separation", 8)
	grid.add_theme_constant_override(&"v_separation", 6)
	_list.add_child(grid)
	for slot in HighlightTable.TYPE_ORDER.size():
		var chip := Panel.new()
		chip.custom_minimum_size = Vector2((COLUMN_WIDTH - 32.0 - 8.0) * 0.5, 30.0)
		chip.mouse_filter = Control.MOUSE_FILTER_STOP
		chip.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		chip.gui_input.connect(_on_type_input.bind(slot))
		var chip_text := StudioStyle.text("", 12, StudioStyle.INK, StudioStyle.body_font())
		chip_text.position = Vector2(8.0, 6.0)
		chip.add_child(chip_text)
		grid.add_child(chip)
		_type_panels.append(chip)
		_type_labels.append(chip_text)

	_moments_head = _section(_list, "MOMENTS")
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
	# Clickable as well as E / Y: opens the export window.
	var export_button := Panel.new()
	export_button.custom_minimum_size = Vector2(0.0, 38.0)
	export_button.add_theme_stylebox_override(&"panel", StudioStyle.box(StudioStyle.LIME, StudioStyle.BORDER, StudioStyle.SHADOW))
	export_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	export_button.gui_input.connect(func(event: InputEvent) -> void:
		var click := event as InputEventMouseButton
		if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT and not _moments.is_empty():
			_export())
	var export_label := StudioStyle.text("EXPORT THE MATCH...   E / Y", 14, StudioStyle.INK, StudioStyle.body_font())
	export_label.position = Vector2(12.0, 9.0)
	export_button.add_child(export_label)
	_list.add_child(export_button)
	_path_label = StudioStyle.text("", 11, StudioStyle.INK_SOFT, StudioStyle.mono_font())
	_path_label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	_path_label.custom_minimum_size.x = COLUMN_WIDTH - 56.0
	_path_label.text = "Folder: %s\nThe whole match with the dead time cut (match_16x9.mp4), a highlight video of the ticked types (highlight.mp4) and the timeline for the video tool (match_video.json). Space / X leaves one moment out." % [
		HighlightPaths.root()]
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
	_timeline = MatchTimeline.new()
	_timeline.position = Vector2(0.0, bar_y - 30.0)
	_timeline.size = Vector2(_overlay.size.x - 170.0, 44.0)
	_timeline.visible = false
	_timeline.seek_requested.connect(func(frame: int) -> void:
		_seek_match(frame)
		_refresh())
	_overlay.add_child(_timeline)
	_match_hint = StudioStyle.text("↑ / ↓ moments   ← / → camera here   [ / ] step   click the bar to seek   T back to clips", 11,
		StudioStyle.INK, StudioStyle.mono_font())
	_match_hint.position = Vector2(0.0, bar_y - 52.0)
	_match_hint.visible = false
	_overlay.add_child(_match_hint)
	var time_chip := _padded(StudioStyle.box(StudioStyle.WHITE, 2, StudioStyle.SHADOW), 8, 2)
	time_chip.position = Vector2(_overlay.size.x - 158.0, bar_y - 4.0)
	_overlay.add_child(time_chip)
	_time_label = StudioStyle.text("", 11, StudioStyle.INK, StudioStyle.mono_font())
	time_chip.get_child(0).add_child(_time_label)

	_empty_card = _padded(StudioStyle.box(StudioStyle.WHITE, StudioStyle.BORDER, StudioStyle.SHADOW), 16, 14)
	_empty_card.position = Vector2(COLUMN_WIDTH + 40.0, StudioStyle.HEADER_HEIGHT + 40.0)
	_empty_card.visible = false
	root.add_child(_empty_card)
	_empty_text = StudioStyle.text("", 13, StudioStyle.INK, StudioStyle.body_font())
	_empty_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_empty_text.custom_minimum_size.x = 420.0
	_empty_card.get_child(0).add_child(_empty_text)


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


func _section(parent: Control, title: String) -> Label:
	var head := StudioStyle.text(title, 11, StudioStyle.INK_SOFT, StudioStyle.mono_font())
	head.custom_minimum_size.y = 22.0
	head.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	parent.add_child(head)
	var rule := ColorRect.new()
	rule.color = StudioStyle.INK
	rule.custom_minimum_size = Vector2(0.0, 2.0)
	parent.add_child(rule)
	return head


func _on_type_input(event: InputEvent, slot: int) -> void:
	var click := event as InputEventMouseButton
	if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		_toggle_type(slot)


static func clock_text(moment: Dictionary) -> String:
	var elapsed := float(moment.quarter_elapsed_s)
	return "Q%d %d:%02d" % [int(moment.quarter), int(elapsed) / 60, int(elapsed) % 60]


func _refresh() -> void:
	for slot in _type_panels.size():
		var type: String = HighlightTable.TYPE_ORDER[slot]
		var on := HighlightPrefs.type_on(type)
		_type_panels[slot].add_theme_stylebox_override(&"panel",
			StudioStyle.box(StudioStyle.LIME if on else StudioStyle.WHITE, 2, StudioStyle.SHADOW if on else 0))
		_type_labels[slot].text = "%s %s  %d   [%d]" % ["■" if on else "□",
			String((HighlightTable.TYPES[type] as Dictionary).plural), Highlights.count_of(type), slot + 1]
		_type_labels[slot].add_theme_color_override(&"font_color", StudioStyle.INK if on else StudioStyle.INK_SOFT)
	var shown := 0
	var kept := 0
	for i in _entry_panels.size():
		var moment := _moments[i]
		if not _shown(i):
			continue
		shown += 1
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
	_moments_head.text = "MOMENTS  (%d of %d)" % [shown, _moments.size()]
	_kept_label.text = "Kept for export: %d of %d" % [kept, shown]
	if _match_mode:
		_refresh_match_card()
		return
	if not _any_shown() or _index < 0:
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


func _refresh_match_card() -> void:
	_refresh_timeline()
	var preset := _preset()
	var whose := "match camera" if _match_stretch < 0 else "%s's camera" % String(_plan.stretches[_match_stretch].label)
	_chip_label.text = "MATCH  ·  %s  ·  %s (%s)  ·  %s×%s" % [
		"PLAYING" if _playing else "PAUSED",
		String(ReplayStage.PRESET_LABELS.get(preset, preset)), whose,
		str(SPEEDS[_speed_index]), "  ·  9:16" if _portrait else ""]
	var info := Highlights.match_info
	var final: Dictionary = info.get("final", {})
	_card_title.text = "Full match  ·  %s v %s" % [info.get("home", "Home"), info.get("away", "Away")]
	var summary := _cut.summary()
	var text := "%d:%02d of video from %d:%02d recorded: breaks and dead time cut." % [
		int(summary.video_s) / 60, int(summary.video_s) % 60, int(summary.recorded_s) / 60, int(summary.recorded_s) % 60]
	if not final.is_empty():
		text += "\nFinal %s  v  %s" % [final.get("home", ""), final.get("away", "")]
	if _index >= 0 and _index < _moments.size() and _moment_video.has(_index):
		text += "\nSelected: %s  ·  %s" % [String(_moments[_index].label), clock_text(_moments[_index])]
	_card_body.text = text


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
	if index != _index or _match_mode:
		_select(index)
	elif click.double_click:
		_playing = not _playing
	_refresh()
