class_name HudStyleScreen
extends CanvasLayer

## HUD Style: the scoreboard, ball trajectory and player ring options
## (Settings.HUD_OPTIONS), reached from Settings' HUD STYLE row.
##
## Laid out after the video editor's Text Studio, its "advanced text
## options" window (playtest 2026-10-30: "I liked that design and it suits a
## customisation screen"): a header bar, the controls in a column on the
## left grouped into sections, and a live preview filling the right, in that
## editor's chrome (StudioStyle). The scoreboard's two styles are that
## window's preset cards; everything else is a cycling row like Settings'.
##
## Every change goes straight to Settings, so the preview, and a match
## running underneath if this is ever opened from one, update live. Saved
## on the way out, like Settings.

const PAPER := StudioStyle.PAPER
const PAPER_DEEP := StudioStyle.PAPER_DEEP
const INK := StudioStyle.INK
const INK_SOFT := StudioStyle.INK_SOFT
const LIME := StudioStyle.LIME
const WHITE := StudioStyle.WHITE
const BORDER := StudioStyle.BORDER
const SHADOW := StudioStyle.SHADOW

const HEADER_HEIGHT := StudioStyle.HEADER_HEIGHT
const CONTROLS_WIDTH := 400.0
const ROW_HEIGHT := 36.0
const PRESET_HEIGHT := 58.0
const PAD := 16.0

const SETTINGS_SCENE := "res://scenes/ui/settings_screen.tscn"

## Section title, then the HUD_OPTIONS keys under it, top to bottom.
const SECTIONS := [
	{"title": "SCOREBOARD", "keys": [&"scoreboard", &"scoreboard_style", &"umpire_banner"]},
	{"title": "BALL TRAJECTORY", "keys": [&"trajectory", &"trajectory_colour",
		&"trajectory_pattern", &"trajectory_thickness"]},
	{"title": "PLAYER RING", "keys": [&"ring", &"ring_colour", &"ring_style", &"ring_size",
		&"ring_thickness"]},
]
## Keys shown as preset cards rather than a cycling row, with each
## option's one-line description.
const PRESETS := {
	&"scoreboard_style": ["Corner card, bottom-left", "Ground board, top-centre"],
}

var _keys: Array[StringName] = []
var _index := 0
var _busy := false
## key -> the row's Panel, its value Label (rows) or its card Panels (presets).
var _row_panels := {}
var _value_labels := {}
var _preset_cards := {}
var _preview: _Preview


func _ready() -> void:
	for section: Dictionary in SECTIONS:
		for key: StringName in section.keys:
			_keys.append(key)

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var paper := ColorRect.new()
	paper.color = PAPER
	paper.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(paper)

	_build_header(root)
	_build_controls(root)
	_build_preview(root)
	Settings.hud_changed.connect(func(_key: StringName) -> void: _refresh())
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if _busy:
		return
	if event.is_action_pressed(&"pause") or event.is_action_pressed(&"ui_cancel") \
			or event.is_action_pressed(&"decline"):
		_back()
	elif event.is_action_pressed(&"move_forward") or event.is_action_pressed(&"ui_up"):
		_move(-1)
	elif event.is_action_pressed(&"move_back") or event.is_action_pressed(&"ui_down"):
		_move(1)
	elif event.is_action_pressed(&"ui_left") or event.is_action_pressed(&"move_left"):
		_cycle(_keys[_index], -1)
	elif event.is_action_pressed(&"ui_right") or event.is_action_pressed(&"move_right") \
			or event.is_action_pressed(&"ui_accept"):
		_cycle(_keys[_index], 1)
	else:
		return
	get_viewport().set_input_as_handled()


func _move(step: int) -> void:
	_index = posmod(_index + step, _keys.size())
	_refresh()


func _cycle(key: StringName, step: int) -> void:
	Settings.set_hud(key, Settings.hud_index(key) + step)


func _back() -> void:
	_busy = true
	Settings.save()
	SceneWipe.change_scene(SETTINGS_SCENE)


func _refresh() -> void:
	for i in _keys.size():
		var key := _keys[i]
		var focused := i == _index
		if _preset_cards.has(key):
			var cards: Array = _preset_cards[key]
			for c in cards.size():
				_style_preset(cards[c], c == Settings.hud_index(key), focused)
			continue
		(_row_panels[key] as Panel).add_theme_stylebox_override(&"panel",
			StudioStyle.box(LIME if focused else WHITE, BORDER, SHADOW if focused else 0))
		(_value_labels[key] as Label).text = "‹  %s  ›" % Settings.hud_choice(key)
	if _preview != null:
		_preview.queue_redraw()
		_preview.sync_scoreboard()


# ── Building ─────────────────────────────────────────────────────────

func _build_header(root: Control) -> void:
	var hints := DeviceHintBar.new()
	hints.alignment = BoxContainer.ALIGNMENT_END
	StudioStyle.header(root, "HUD Style", "Settings  /  HUD", hints)
	hints.set_hint_sets({
		InputManager.Device.KEYBOARD: [
			{"keys": "↑ / ↓", "label": "Select"},
			{"keys": "← / →", "label": "Change"},
			{"keys": "Esc", "label": "Back"},
		],
		InputManager.Device.GAMEPAD: [
			{"keys": "D-Pad ↕", "label": "Select"},
			{"keys": "D-Pad ↔", "label": "Change"},
			{"keys": "B", "label": "Back"},
		],
	})


func _build_controls(root: Control) -> void:
	var column := Panel.new()
	column.add_theme_stylebox_override(&"panel", StudioStyle.bar(PAPER, true))
	column.position = Vector2(0.0, HEADER_HEIGHT)
	column.size = Vector2(CONTROLS_WIDTH, 720.0 - HEADER_HEIGHT)
	root.add_child(column)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.offset_right = -BORDER
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)

	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in [&"margin_left", &"margin_right", &"margin_top", &"margin_bottom"]:
		margin.add_theme_constant_override(side, int(PAD))
	scroll.add_child(margin)

	var list := VBoxContainer.new()
	list.add_theme_constant_override(&"separation", 8)
	margin.add_child(list)

	var flat_index := 0
	for section: Dictionary in SECTIONS:
		var head := StudioStyle.text(String(section.title), 11, INK_SOFT, StudioStyle.mono_font())
		head.custom_minimum_size.y = 24.0
		head.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		list.add_child(head)
		var rule := ColorRect.new()
		rule.color = INK
		rule.custom_minimum_size = Vector2(0.0, 2.0)
		list.add_child(rule)
		for key: StringName in section.keys:
			if PRESETS.has(key):
				list.add_child(_build_presets(key, flat_index))
			else:
				list.add_child(_build_row(key, flat_index))
			flat_index += 1
		var gap := Control.new()
		gap.custom_minimum_size.y = 6.0
		list.add_child(gap)


func _build_row(key: StringName, flat_index: int) -> Control:
	var panel := Panel.new()
	panel.custom_minimum_size = Vector2(0.0, ROW_HEIGHT)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.gui_input.connect(_on_row_input.bind(key, flat_index))
	var label := StudioStyle.text(String(Settings.HUD_OPTIONS[key].label), 13, INK,
		StudioStyle.body_font())
	label.position = Vector2(12.0, 8.0)
	panel.add_child(label)
	var value := StudioStyle.text("", 12, INK, StudioStyle.mono_font())
	value.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	value.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.offset_left = -220.0
	value.offset_right = -12.0
	value.offset_top = 10.0
	panel.add_child(value)
	_row_panels[key] = panel
	_value_labels[key] = value
	return panel


func _build_presets(key: StringName, flat_index: int) -> Control:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override(&"h_separation", 10)
	grid.add_theme_constant_override(&"v_separation", 10)
	var cards: Array[Panel] = []
	var options: Array = Settings.HUD_OPTIONS[key].options
	for i in options.size():
		var card := Panel.new()
		card.custom_minimum_size = Vector2(0.0, PRESET_HEIGHT)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.mouse_filter = Control.MOUSE_FILTER_STOP
		card.gui_input.connect(_on_preset_input.bind(key, i, flat_index))
		var name_label := StudioStyle.text(String(options[i]), 12, INK, StudioStyle.body_font())
		name_label.name = &"Name"
		name_label.position = Vector2(10.0, 9.0)
		card.add_child(name_label)
		var note := StudioStyle.text(String(PRESETS[key][i]), 10, INK_SOFT, StudioStyle.mono_font())
		note.name = &"Note"
		note.position = Vector2(10.0, 30.0)
		card.add_child(note)
		grid.add_child(card)
		cards.append(card)
	_preset_cards[key] = cards
	return grid


func _style_preset(card: Panel, picked: bool, focused: bool) -> void:
	var fill := INK if picked else (LIME if focused else WHITE)
	card.add_theme_stylebox_override(&"panel", StudioStyle.box(fill, BORDER, SHADOW))
	(card.get_node(^"Name") as Label).add_theme_color_override(&"font_color", LIME if picked else INK)
	(card.get_node(^"Note") as Label).add_theme_color_override(&"font_color", PAPER if picked else INK_SOFT)


func _build_preview(root: Control) -> void:
	var area := ColorRect.new()
	area.color = PAPER_DEEP
	area.position = Vector2(CONTROLS_WIDTH, HEADER_HEIGHT)
	area.size = Vector2(1280.0 - CONTROLS_WIDTH, 720.0 - HEADER_HEIGHT)
	root.add_child(area)

	var caption := StudioStyle.text("PREVIEW", 11, INK_SOFT, StudioStyle.mono_font())
	caption.position = Vector2(28.0, 18.0)
	area.add_child(caption)

	var stage := Panel.new()
	stage.add_theme_stylebox_override(&"panel", StudioStyle.box(INK, BORDER, SHADOW + 2))
	stage.position = Vector2(28.0, 44.0)
	stage.size = area.size - Vector2(56.0, 72.0)
	area.add_child(stage)

	_preview = _Preview.new()
	_preview.position = Vector2(BORDER, BORDER)
	_preview.size = stage.size - Vector2(BORDER * 2, BORDER * 2)
	_preview.clip_contents = true
	stage.add_child(_preview)
	_preview.build()


func _on_row_input(event: InputEvent, key: StringName, flat_index: int) -> void:
	var click := event as InputEventMouseButton
	if click == null or not click.pressed:
		return
	_index = flat_index
	if click.button_index == MOUSE_BUTTON_LEFT:
		_cycle(key, 1)
	elif click.button_index == MOUSE_BUTTON_RIGHT:
		_cycle(key, -1)
	_refresh()


func _on_preset_input(event: InputEvent, key: StringName, option: int, flat_index: int) -> void:
	var click := event as InputEventMouseButton
	if click == null or not click.pressed or click.button_index != MOUSE_BUTTON_LEFT:
		return
	_index = flat_index
	Settings.set_hud(key, option)
	_refresh()


## The preview: a patch of turf seen from the broadcast angle, with the
## kick line from a player to a landing ring, the ring at the player's
## feet, and the scoreboard and a banner where a match puts them — each
## drawn in whatever the options say right now. The 7-seg board is the
## real ScoreboardFace; the card is a stand-in with the real card's layout.
class _Preview extends Control:
	const TURF := Color("#4F7A45")
	const TURF_LIGHT := Color("#5C8850")
	## Where the kick starts and lands, as fractions of the preview.
	const KICK_FROM := Vector2(0.24, 0.78)
	const KICK_TO := Vector2(0.78, 0.6)
	const KICK_PEAK := 0.22
	const SAMPLES := 22

	var _face: ScoreboardFace
	var _card: Panel
	var _banner: Panel

	func build() -> void:
		_face = ScoreboardFace.new()
		_face.custom_minimum_size = ScoreboardFace.size_for(17.0)
		_face.size = _face.custom_minimum_size
		_face.position = Vector2((size.x - _face.size.x) * 0.5, 10.0)
		add_child(_face)

		_card = Panel.new()
		_card.add_theme_stylebox_override(&"panel", SoftBrutalist.panel_style())
		var card_text := SoftBrutalist.numeric_label("HOME  02 | 03 | 015    QTR 1\nAWAY  01 | 04 | 010    12:34",
			SoftBrutalist.SIZE_LABEL, SoftBrutalist.INK)
		card_text.position = Vector2(12.0, 6.0)
		_card.add_child(card_text)
		_card.size = card_text.get_combined_minimum_size() + Vector2(24.0, 12.0)
		_card.position = Vector2(12.0, size.y - _card.size.y - 12.0)
		add_child(_card)

		_banner = Panel.new()
		_banner.add_theme_stylebox_override(&"panel", SoftBrutalist.panel_style())
		var banner_text := SoftBrutalist.label("BALL UP", SoftBrutalist.SIZE_LABEL, SoftBrutalist.INK,
			SoftBrutalist.WEIGHT_HEAVY, SoftBrutalist.TRACK_LABEL)
		banner_text.position = Vector2(14.0, 4.0)
		_banner.add_child(banner_text)
		_banner.size = banner_text.get_combined_minimum_size() + Vector2(28.0, 8.0)
		add_child(_banner)
		sync_scoreboard()

	func sync_scoreboard() -> void:
		if _face == null:
			return
		var shown := Settings.hud_on(&"scoreboard")
		var seven_seg := Settings.hud_index(&"scoreboard_style") == 1
		_face.visible = shown and seven_seg
		_card.visible = shown and not seven_seg
		_banner.visible = Settings.hud_on(&"umpire_banner")
		var top := 10.0 + (_face.size.y + 8.0 if _face.visible else 4.0)
		_banner.position = Vector2((size.x - _banner.size.x) * 0.5, top)

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), TURF)
		# A few soft lighter patches, so the line and ring are judged on
		# grass that isn't one flat colour.
		for patch: Vector3 in [Vector3(0.2, 0.35, 0.22), Vector3(0.65, 0.3, 0.3), Vector3(0.5, 0.85, 0.25)]:
			draw_circle(Vector2(patch.x, patch.y) * size, patch.z * size.x * 0.5,
				Color(TURF_LIGHT, 0.45))
		var from := KICK_FROM * size
		_draw_ring(from)
		_draw_player(from)
		if Settings.hud_on(&"trajectory"):
			_draw_trajectory(from, KICK_TO * size)

	func _arc_point(from: Vector2, to: Vector2, t: float) -> Vector2:
		var p := from.lerp(to, t)
		p.y -= 4.0 * t * (1.0 - t) * KICK_PEAK * size.y
		return p

	func _draw_trajectory(from: Vector2, to: Vector2) -> void:
		var colour := Settings.hud_colour(&"trajectory_colour")
		var thickness: float = KickTrajectory.THICKNESS_SCALES[Settings.hud_index(&"trajectory_thickness")]
		var pattern := Settings.hud_choice(&"trajectory_pattern")
		var points: Array[Vector2] = []
		for i in SAMPLES:
			points.append(_arc_point(from + Vector2(0.0, -34.0), to, float(i) / float(SAMPLES - 1)))
		for i in points.size():
			var t := float(i) / float(points.size() - 1)
			var c := Color(colour, lerpf(0.35, 1.0, t))
			var r := lerpf(2.2, 5.0, t) * thickness
			match pattern:
				"DOTTED":
					draw_circle(points[i], r, c)
				"DASHED":
					if i < points.size() - 1:
						var mid := (points[i] + points[i + 1]) * 0.5
						var half := (points[i + 1] - points[i]) * 0.25
						draw_line(mid - half, mid + half, c, r * 1.6)
				_:
					if i < points.size() - 1:
						draw_line(points[i], points[i + 1], c, r * 1.6)
		# Landing ring, flattened like the ground it lies on.
		draw_set_transform(to, 0.0, Vector2(1.0, 0.38))
		draw_arc(Vector2.ZERO, 26.0, 0.0, TAU, 40, Color(colour, 0.35), 9.0)
		draw_arc(Vector2.ZERO, 24.0, 0.0, TAU, 40, colour, 3.0)
		draw_set_transform(Vector2.ZERO)

	func _draw_ring(at: Vector2) -> void:
		if Settings.hud_index(&"ring") == 0:
			return
		var colour := Settings.hud_colour(&"ring_colour")
		var radius: float = ControlledPlayerRing.SIZE_RADII[Settings.hud_index(&"ring_size")] * 30.0
		var width: float = ControlledPlayerRing.THICKNESS_WIDTHS[Settings.hud_index(&"ring_thickness")] * 30.0
		draw_set_transform(at, 0.0, Vector2(1.0, 0.38))
		if Settings.hud_choice(&"ring_style") == "DASHED":
			var runs := ControlledPlayerRing.SEGMENTS / (ControlledPlayerRing.DASH_ON + ControlledPlayerRing.DASH_GAP)
			var step := TAU / float(runs)
			var on := step * float(ControlledPlayerRing.DASH_ON) \
				/ float(ControlledPlayerRing.DASH_ON + ControlledPlayerRing.DASH_GAP)
			for i in runs:
				draw_arc(Vector2.ZERO, radius - width * 0.5, i * step, i * step + on, 6, colour, width)
		else:
			draw_arc(Vector2.ZERO, radius - width * 0.5, 0.0, TAU, 48, colour, width)
		draw_set_transform(Vector2.ZERO)

	## A plain figure: enough to read as a player standing in the ring.
	func _draw_player(feet: Vector2) -> void:
		var body := Color("#C99A2E")
		draw_line(feet + Vector2(-6.0, 0.0), feet + Vector2(-4.0, -26.0), Color("#1B1C20"), 6.0)
		draw_line(feet + Vector2(6.0, 0.0), feet + Vector2(4.0, -26.0), Color("#1B1C20"), 6.0)
		draw_rect(Rect2(feet + Vector2(-10.0, -56.0), Vector2(20.0, 32.0)), body)
		draw_circle(feet + Vector2(0.0, -64.0), 8.0, Color("#D9A37E"))
