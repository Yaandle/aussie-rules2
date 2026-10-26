class_name CareerFixtureScreen
extends CanvasLayer

## Career mode's VIEW FIXTURE page — the season's 12 rounds as a carousel
## of cards, reached from the Dashboard. Playtest brief: "a simple card
## system and arrows on the right to click to see next game. If I go right
## bring up an arrow on the left", using the main menu's cards and the look
## of the BEAT section (scene 02) of the user's showcase video.
##
## * Cards keep MainMenu's proportions (CARD_MIN_WIDTH x CARD_MIN_HEIGHT),
##   its sharp 3px border and its 1.07 selected pop. The BEAT look is what
##   goes on them: a big "01".."12" in the corner; a played round filled
##   tan over a hard offset shadow with its W/L/D chip and score; a round
##   still to come an outline over a dot grid; the next game crossed by
##   CareerTheme.MARKER's vertical tick. No lime — the Career palette stays.
## * VISIBLE cards show at once; the strip slides one card when the
##   selection walks off either end. It opens on the current round (the
##   last one once the season is over).
## * The right arrow shows whenever there's a later round; the left arrow
##   fades in once there's an earlier one to go back to, so a season opened
##   on round 1 shows only the right arrow until you move. Arrows and
##   ← / → step one card; LB / Home jumps to round 1, RB / End back to the
##   next game. Clicking a card selects it.
## * Above the strip, the selected round as a headline with its result or
##   the opponent's ladder place; below it a caption row (your round, place
##   and record) and a season progress bar, both as in the BEAT frames.

const VISIBLE := 4
const CARD_SIZE := Vector2(MainMenu.CARD_MIN_WIDTH, MainMenu.CARD_MIN_HEIGHT)
const CARD_GAP := 24.0
const CARD_BORDER := float(MainMenu.CARD_BORDER_WIDTH)
const SELECTED_SCALE := MainMenu.CARD_SELECTED_SCALE
## Room inside the strip's clip for the pop, the shadow and the tick's
## overhang above and below the card.
const CLIP_PAD := Vector2(16.0, 26.0)
const SHADOW_OFFSET := Vector2(8.0, 8.0)
const ARROW_SIZE := Vector2(48.0, 48.0)
const SLIDE_DURATION := 0.25
const ARROW_FADE_DURATION := 0.15
const PROGRESS_HEIGHT := 4.0

const SCREEN_MARGIN_X := SoftBrutalist.SPACE_6
const SCREEN_MARGIN_Y := SoftBrutalist.SPACE_4
const DASHBOARD_SCENE := "res://scenes/ui/career_dashboard_screen.tscn"

var _cards: Array[FixtureCard] = []
var _track: Control
var _track_tween: Tween
var _left_arrow: Control
var _right_arrow: Control
var _headline: Label
var _subline: Label
var _index := 0
var _first := 0
var _busy := false


func _ready() -> void:
	_index = _current_index()
	_first = clampi(_index, 0, maxi(_cards_count() - VISIBLE, 0))
	_build()
	_track.position.x = _track_x()
	_refresh(false)


func _cards_count() -> int:
	return CareerProfile.season_length()


## The next game, or the last round once the season is over.
func _current_index() -> int:
	return mini(CareerProfile.games_played, _cards_count() - 1)


func _unhandled_input(event: InputEvent) -> void:
	if _busy:
		return
	if event.is_action_pressed(&"move_left") or event.is_action_pressed(&"ui_left"):
		_select(_index - 1)
	elif event.is_action_pressed(&"move_right") or event.is_action_pressed(&"ui_right"):
		_select(_index + 1)
	elif _is_key(event, KEY_HOME) or _is_pad(event, JOY_BUTTON_LEFT_SHOULDER):
		_select(0)
	elif _is_key(event, KEY_END) or _is_pad(event, JOY_BUTTON_RIGHT_SHOULDER):
		_select(_current_index())
	elif event.is_action_pressed(&"pause") or event.is_action_pressed(&"decline"):
		_busy = true
		SceneWipe.change_scene(DASHBOARD_SCENE)


## Read raw, not through an action: LB/RB are bound to match actions, and
## Home/End to none.
func _is_key(event: InputEvent, key: Key) -> bool:
	return event is InputEventKey and event.pressed and not event.echo \
		and (event as InputEventKey).keycode == key


func _is_pad(event: InputEvent, button: JoyButton) -> bool:
	return event is InputEventJoypadButton and event.pressed \
		and (event as InputEventJoypadButton).button_index == button


func _select(index: int) -> void:
	index = clampi(index, 0, _cards_count() - 1)
	if index == _index:
		return
	_index = index
	if _index < _first:
		_first = _index
	elif _index > _first + VISIBLE - 1:
		_first = _index - VISIBLE + 1
	if _track_tween != null and _track_tween.is_valid():
		_track_tween.kill()
	_track_tween = create_tween()
	_track_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_track_tween.tween_property(_track, "position:x", _track_x(), SLIDE_DURATION)
	_refresh(true)


func _track_x() -> float:
	return CLIP_PAD.x - _first * (CARD_SIZE.x + CARD_GAP)


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
	column.add_theme_constant_override(&"separation", int(SoftBrutalist.SPACE_3))
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(column)

	var header := VBoxContainer.new()
	header.add_theme_constant_override(&"separation", 4)
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(header)
	header.add_child(CareerTheme.label("FIXTURE · SEASON %d · %s" % [CareerProfile.season_index + 1,
		CareerSeason.league_name(CareerProfile.league_index)], SoftBrutalist.SIZE_LABEL,
		CareerTheme.MARKER, SoftBrutalist.WEIGHT_BOLD, 1))
	_headline = CareerTheme.label("", SoftBrutalist.SIZE_DISPLAY, CareerTheme.TEXT,
		SoftBrutalist.WEIGHT_HEAVY)
	header.add_child(_headline)
	_subline = CareerTheme.label("", SoftBrutalist.SIZE_BODY, CareerTheme.TEXT_MUTED)
	header.add_child(_subline)

	var strip := HBoxContainer.new()
	strip.add_theme_constant_override(&"separation", 8)
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(strip)
	_left_arrow = _build_arrow(&"arrow_left", -1)
	strip.add_child(_left_arrow)
	strip.add_child(_build_clip())
	_right_arrow = _build_arrow(&"arrow_right", 1)
	strip.add_child(_right_arrow)

	var below := VBoxContainer.new()
	below.add_theme_constant_override(&"separation", 10)
	below.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(below)
	below.add_child(CareerTheme.label(_caption_text(), SoftBrutalist.SIZE_LABEL, CareerTheme.TEXT,
		SoftBrutalist.WEIGHT_BOLD, 1))
	below.add_child(_build_progress_bar())

	var hints := DeviceHintBar.new()
	column.add_child(hints)
	hints.set_hint_sets({
		InputManager.Device.KEYBOARD: [
			{"keys": "← / →", "label": "Round"},
			{"keys": "Home", "label": "Round 1"},
			{"keys": "End", "label": "Next game"},
			{"keys": "Esc", "label": "Back"},
		],
		InputManager.Device.GAMEPAD: [
			{"keys": "D-Pad ↔", "label": "Round"},
			{"keys": "LB", "label": "Round 1"},
			{"keys": "RB", "label": "Next game"},
			{"keys": "B", "label": "Back"},
		],
	})


## VISIBLE cards' worth of window onto a track holding all of them; the
## track slides, the window stays put.
func _build_clip() -> Control:
	var clip := Control.new()
	clip.custom_minimum_size = Vector2(VISIBLE * CARD_SIZE.x + (VISIBLE - 1) * CARD_GAP,
		CARD_SIZE.y) + CLIP_PAD * 2.0
	clip.clip_contents = true
	clip.mouse_filter = Control.MOUSE_FILTER_PASS

	_track = Control.new()
	_track.position = Vector2(0.0, CLIP_PAD.y)
	_track.mouse_filter = Control.MOUSE_FILTER_PASS
	clip.add_child(_track)

	var current := CareerProfile.games_played
	for i in _cards_count():
		var round_entry: Dictionary = CareerProfile.rounds[i]
		var card := FixtureCard.new()
		card.position = Vector2(i * (CARD_SIZE.x + CARD_GAP), 0.0)
		if bool(round_entry.get("played", false)):
			card.state = FixtureCard.State.PLAYED
		elif i == current:
			card.state = FixtureCard.State.CURRENT
		else:
			card.state = FixtureCard.State.UPCOMING
		card.fill(i + 1, round_entry)
		card.gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton and event.pressed \
					and event.button_index == MOUSE_BUTTON_LEFT:
				_select(i))
		_track.add_child(card)
		_cards.append(card)
	return clip


## An outlined square with a chevron, clickable; hidden (faded, inert)
## when there's no card that way — see _refresh().
func _build_arrow(icon_name: StringName, step: int) -> Control:
	var panel := Panel.new()
	panel.custom_minimum_size = ARROW_SIZE
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var idle := CareerTheme.panel_style(Color(CareerTheme.PANEL, 0.0), CareerTheme.TEXT, 2)
	var hover := CareerTheme.panel_style(CareerTheme.PANEL, CareerTheme.PANEL, 2)
	panel.add_theme_stylebox_override(&"panel", idle)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var icon := UIIcon.new()
	icon.icon_name = icon_name
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon.offset_left = 12.0
	icon.offset_top = 12.0
	icon.offset_right = -12.0
	icon.offset_bottom = -12.0
	icon.line_colour = CareerTheme.TEXT
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(icon)
	panel.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_select(_index + step))
	panel.mouse_entered.connect(func() -> void:
		panel.add_theme_stylebox_override(&"panel", hover)
		icon.line_colour = CareerTheme.PANEL_TEXT)
	panel.mouse_exited.connect(func() -> void:
		panel.add_theme_stylebox_override(&"panel", idle)
		icon.line_colour = CareerTheme.TEXT)
	return panel


## A thin rule the strip's width, filled in MARKER for the rounds played.
func _build_progress_bar() -> Control:
	var width := VISIBLE * CARD_SIZE.x + (VISIBLE - 1) * CARD_GAP + CLIP_PAD.x * 2.0 \
		+ (ARROW_SIZE.x + 8.0) * 2.0
	var bar := ColorRect.new()
	bar.color = Color(CareerTheme.TEXT, 0.12)
	bar.custom_minimum_size = Vector2(width, PROGRESS_HEIGHT)
	bar.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fill := ColorRect.new()
	fill.color = CareerTheme.MARKER
	var done := float(CareerProfile.games_played) / maxf(1.0, float(_cards_count()))
	fill.size = Vector2(width * done, PROGRESS_HEIGHT)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(fill)
	return bar


func _caption_text() -> String:
	var table := CareerProfile.ladder()
	var me: Dictionary = table[CareerProfile.ladder_position() - 1]
	var round_text := "SEASON COMPLETE" if CareerProfile.season_complete() \
		else "ROUND %d OF %d" % [CareerProfile.games_played + 1, _cards_count()]
	return "%s   ·   %s ON THE LADDER   ·   W%d  L%d  D%d" % [round_text,
		CareerSeason.ordinal(CareerProfile.ladder_position()).to_upper(),
		me["won"], me["lost"], me["drawn"]]


# ── Refresh ──────────────────────────────────────────────────────────

func _refresh(animate: bool) -> void:
	for i in _cards.size():
		_cards[i].set_selected(i == _index, animate)
	_set_arrow(_left_arrow, _index > 0)
	_set_arrow(_right_arrow, _index < _cards_count() - 1)
	var round_entry: Dictionary = CareerProfile.rounds[_index]
	var opponent := String(round_entry["opponent"])
	_headline.text = "Round %d — %s" % [_index + 1, opponent]
	_subline.text = _subline_text(round_entry, opponent)


func _set_arrow(arrow: Control, shown: bool) -> void:
	arrow.mouse_filter = Control.MOUSE_FILTER_STOP if shown else Control.MOUSE_FILTER_IGNORE
	var tween := arrow.create_tween()
	tween.tween_property(arrow, "modulate:a", 1.0 if shown else 0.0, ARROW_FADE_DURATION)


func _subline_text(round_entry: Dictionary, opponent: String) -> String:
	if bool(round_entry.get("played", false)):
		var ours := int(round_entry.get("home_points", 0))
		var theirs := int(round_entry.get("away_points", 0))
		var verb := "Won" if ours > theirs else ("Lost" if ours < theirs else "Drew")
		var text := "%s %s to %s" % [verb, String(round_entry.get("home_score", str(ours))),
			String(round_entry.get("away_score", str(theirs)))]
		return text + ("  ·  simulated" if bool(round_entry.get("simulated", false)) else "")
	var when := "Next game" if _index == CareerProfile.games_played else "Upcoming"
	# Before round 1 every row is 0-0 and the order is alphabetical, so a
	# place would mean nothing.
	if CareerProfile.games_played == 0:
		return when
	var place := ""
	var table := CareerProfile.ladder()
	for i in table.size():
		if String(table[i]["team"]) == opponent:
			place = CareerSeason.ordinal(i + 1)
	return "%s  ·  %s sit %s on the ladder" % [when, opponent, place]


## One round's card. Drawn rather than built from styleboxes because the
## BEAT look needs things a StyleBoxFlat can't do: the dot grid, a hard
## shadow offset outside the card, and the marker tick running past its
## top and bottom edges. Text is still Labels, for the shared fonts.
class FixtureCard extends Control:
	enum State { PLAYED, CURRENT, UPCOMING }

	const DOT_STEP := 18.0
	const DOT_RADIUS := 1.4
	const TICK_WIDTH := 3.0
	const TICK_OVERHANG := 14.0
	const CHIP_COLOURS := {"W": CareerTheme.POSITIVE, "L": CareerTheme.NEGATIVE, "D": CareerTheme.TEXT_MUTED}

	var state := State.UPCOMING
	var _selected := false

	func _init() -> void:
		size = CareerFixtureScreen.CARD_SIZE
		custom_minimum_size = size
		pivot_offset = size * 0.5
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	## Number, round, opponent and (once played) the result chip and score.
	func fill(number: int, round_entry: Dictionary) -> void:
		var played := state == State.PLAYED
		var ink := CareerTheme.PANEL_TEXT if played else CareerTheme.TEXT
		var soft := CareerTheme.PANEL_TEXT.lightened(0.3) if played else CareerTheme.TEXT_MUTED

		var inner := MarginContainer.new()
		inner.set_anchors_preset(Control.PRESET_FULL_RECT)
		inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for side in ["left", "right", "top", "bottom"]:
			inner.add_theme_constant_override(StringName("margin_" + side), 16)
		add_child(inner)
		var rows := VBoxContainer.new()
		rows.add_theme_constant_override(&"separation", 4)
		rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inner.add_child(rows)

		rows.add_child(SoftBrutalist.numeric_label("%02d" % number, SoftBrutalist.SIZE_TITLE, ink))
		var spacer := Control.new()
		spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
		spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rows.add_child(spacer)
		var tag := "NEXT GAME" if state == State.CURRENT else "ROUND %d" % number
		rows.add_child(CareerTheme.label(tag, SoftBrutalist.SIZE_CAPTION,
			CareerTheme.MARKER if state == State.CURRENT else soft, SoftBrutalist.WEIGHT_BOLD, 1))
		var name_label := CareerTheme.label(String(round_entry["opponent"]), SoftBrutalist.SIZE_HEADING,
			ink, SoftBrutalist.WEIGHT_BOLD)
		name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		name_label.custom_minimum_size.x = size.x - 32.0
		rows.add_child(name_label)
		if played:
			rows.add_child(_result_row(round_entry, ink))

	func _result_row(round_entry: Dictionary, ink: Color) -> Control:
		var ours := int(round_entry.get("home_points", 0))
		var theirs := int(round_entry.get("away_points", 0))
		var result := "W" if ours > theirs else ("L" if ours < theirs else "D")
		var row := HBoxContainer.new()
		row.add_theme_constant_override(&"separation", 10)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var chip := PanelContainer.new()
		chip.add_theme_stylebox_override(&"panel", CareerTheme.panel_style(CHIP_COLOURS[result]))
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var chip_inner := MarginContainer.new()
		chip_inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for side in ["left", "right"]:
			chip_inner.add_theme_constant_override(StringName("margin_" + side), 8)
		chip.add_child(chip_inner)
		chip_inner.add_child(CareerTheme.label(result, SoftBrutalist.SIZE_LABEL, CareerTheme.TEXT,
			SoftBrutalist.WEIGHT_BOLD))
		row.add_child(chip)
		row.add_child(SoftBrutalist.numeric_label("%d – %d" % [ours, theirs], SoftBrutalist.SIZE_BODY, ink))
		return row

	func set_selected(selected: bool, animate: bool) -> void:
		_selected = selected
		var target := Vector2.ONE * (CareerFixtureScreen.SELECTED_SCALE if selected else 1.0)
		if animate:
			create_tween().tween_property(self, "scale", target, 0.15)
		else:
			scale = target
		queue_redraw()

	func _draw() -> void:
		var rect := Rect2(Vector2.ZERO, size)
		var border := CareerTheme.POSITIVE if _selected else (CareerTheme.BACKGROUND \
			if state == State.PLAYED else CareerTheme.TEXT)
		if state == State.PLAYED:
			draw_rect(Rect2(CareerFixtureScreen.SHADOW_OFFSET, size), Color(CareerTheme.TEXT, 0.9))
			draw_rect(rect, CareerTheme.PANEL)
		else:
			var dot := Color(CareerTheme.TEXT, 0.18)
			var y := DOT_STEP
			while y < size.y - 4.0:
				var x := DOT_STEP
				while x < size.x - 4.0:
					draw_circle(Vector2(x, y), DOT_RADIUS, dot)
					x += DOT_STEP
				y += DOT_STEP
		var half := CareerFixtureScreen.CARD_BORDER * 0.5
		draw_rect(rect.grow(-half), border, false, CareerFixtureScreen.CARD_BORDER)
		# Down the card's left edge, like a playhead, rather than across its
		# middle as in the BEAT frames: those cards had no text to cross.
		if state == State.CURRENT:
			draw_rect(Rect2(-TICK_WIDTH * 0.5, -TICK_OVERHANG, TICK_WIDTH, size.y + TICK_OVERHANG * 2.0),
				CareerTheme.MARKER)
