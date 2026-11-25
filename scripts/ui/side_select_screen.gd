class_name SideSelectScreen
extends CanvasLayer

## FULL GAME's first step (6AC, playtest 2026-11-11: "take TEAM off the
## main menu; the FULL game menu gets side select (your team and the
## opposition), then the TEAM page"). Since 2026-11-26 the TEAM page is
## gone ("we don't need the team list screen ... move the team/players
## table into the team select screen, with a simple toggle to show and hide
## it"): its tactics rows and board already live on the pregame screen, and
## its squad table now sits under the club pickers here. Flow:
##   main menu FULL GAME -> here -> FullGamePregameScreen -> the match.
## Back steps one screen at a time the other way.
##
## Two rows, YOUR TEAM and OPPOSITION, each cycling through the quick-play
## clubs (Settings.quick_team_names()). The two can't be the same club:
## cycling skips whichever one the other row holds. The picks are display
## only (scoreboard names, the squad table); see Settings' quick_home_team.
## Career has its own clubs and never comes through here.
##
## ── Squad table ─────────────────────────────────────────────────────
## A SHOW SQUAD / HIDE SQUAD button under the card (a third cursor stop, a
## mouse click, or `team_menu` (T / RB) from anywhere) toggles a
## SquadSheet below it. The sheet shows whichever row the cursor was last
## on — your club with your profile stats, or the opposition's — and is
## rebuilt every time a club changes, so each club shows its own players.
## Shown or hidden is a view toggle, not a setting: it starts hidden.
## With the sheet up, down from the button scrolls the page into it (the
## old TEAM page's pattern); up from its top hands the cursor back.
##
## Same RetroWindow card and row language as remap_screen.gd /
## settings_screen.gd.

const CARD_WIDTH := 560.0
const CARD_MARGIN := 32.0
const HEADER_HEIGHT := 88.0
const ROW_HEIGHT := 56.0
const ROW_GAP := 12.0
const HINT_HEIGHT := 24.0
const SCREEN_MARGIN := 32.0
const BAND_GAP := 16
const ROW_TITLES := ["YOUR TEAM", "OPPOSITION"]

## Cursor stop for the SHOW/HIDE SQUAD button, after the two club rows.
const TOGGLE_STOP := 2
## Squad card width: the old TEAM page's content column, which the sheet's
## nine columns were laid out against.
const SQUAD_WIDTH := 780.0
const SQUAD_PAD := 24.0
## Pixels per up/down press while the cursor is in the squad sheet.
const SQUAD_SCROLL_STEP := SquadSheet.ROW_HEIGHT * 3.0
const SCROLL_TWEEN_DURATION := 0.25

var _index := 0
var _busy := false
var _names: Array[String] = []
## Index into _names for each row: 0 = your team, 1 = the opposition.
var _picks := [0, 1]
## The club row the sheet shows: the last of the two rows the cursor sat on.
var _sheet_row := 0
var _squad_shown := false
## True while up/down scrolls the squad sheet instead of moving the cursor.
var _in_squad := false

var _row_panels: Array[Panel] = []
var _value_labels: Array[Label] = []
var _hints: DeviceHintBar

var _scroll: ScrollContainer
var _scroll_tween: Tween
var _top_spacer: Control
var _picker_height := 0.0
var _toggle_band: Control
var _toggle_button: ActionButton
var _squad_wrapper: Control
var _squad_inner: MarginContainer
var _squad_sheet: SquadSheet


func _ready() -> void:
	_names = Settings.quick_team_names()
	_picks[0] = maxi(0, _names.find(Settings.quick_home_name()))
	_picks[1] = maxi(0, _names.find(Settings.quick_away_name()))
	_build()
	_rebuild_sheet()
	_apply_squad_shown()
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if _busy:
		return
	if event.is_action_pressed(&"pause") or event.is_action_pressed(&"ui_cancel") \
			or event.is_action_pressed(&"decline"):
		_leave("res://scenes/ui/main_menu.tscn")
	elif event.is_action_pressed(&"team_menu"):
		_toggle_squad()
	elif event.is_action_pressed(&"move_forward") or event.is_action_pressed(&"ui_up"):
		if _in_squad:
			_scroll_squad(-1)
		else:
			_move(-1)
	elif event.is_action_pressed(&"move_back") or event.is_action_pressed(&"ui_down"):
		if _in_squad:
			_scroll_squad(1)
		elif _index == TOGGLE_STOP and _squad_shown:
			_enter_squad()
		else:
			_move(1)
	elif event.is_action_pressed(&"ui_accept") or event.is_action_pressed(&"confirm"):
		if _index == TOGGLE_STOP and not _in_squad:
			_toggle_squad()
		else:
			_leave("res://scenes/ui/full_game_pregame_screen.tscn")
	elif _in_squad or _index == TOGGLE_STOP:
		return
	elif event.is_action_pressed(&"ui_left") or event.is_action_pressed(&"move_left"):
		_cycle(-1)
	elif event.is_action_pressed(&"ui_right") or event.is_action_pressed(&"move_right"):
		_cycle(1)


## Clamped, not wrapping like it used to: there are three stops now and
## down off the last one scrolls into the sheet, so wrapping would make
## "down" mean two different things.
func _move(step: int) -> void:
	_index = clampi(_index + step, 0, TOGGLE_STOP)
	if _index != TOGGLE_STOP and _index != _sheet_row:
		_sheet_row = _index
		_rebuild_sheet()
	_refresh()


## Steps this row's club, skipping the one the other row holds.
func _cycle(step: int) -> void:
	var other: int = _picks[1 - _index]
	var next: int = _picks[_index]
	for i in _names.size():
		next = (next + step + _names.size()) % _names.size()
		if next != other:
			break
	_picks[_index] = next
	Settings.quick_home_team = _names[_picks[0]]
	Settings.quick_away_team = _names[_picks[1]]
	_rebuild_sheet()
	_refresh()


func _leave(scene: String) -> void:
	_busy = true
	Settings.quick_home_team = _names[_picks[0]]
	Settings.quick_away_team = _names[_picks[1]]
	Settings.save()
	SceneWipe.change_scene(scene)


# ── Squad sheet ──────────────────────────────────────────────────────

func _toggle_squad() -> void:
	_squad_shown = not _squad_shown
	_apply_squad_shown()
	_refresh()


## Shows/hides the sheet. Hidden, the picker card and button sit centred
## in the view like the old single card did; shown, the spacer above them
## collapses so the sheet starts on the first screenful.
func _apply_squad_shown() -> void:
	if not _squad_shown:
		_in_squad = false
	_squad_wrapper.visible = _squad_shown
	_toggle_button.set_text("HIDE SQUAD" if _squad_shown else "SHOW SQUAD")
	var view := 720.0 - SCREEN_MARGIN * 2.0 - HINT_HEIGHT - float(BAND_GAP)
	var content := _picker_height + float(BAND_GAP) + ActionButton.HEIGHT
	_top_spacer.custom_minimum_size.y = 0.0 if _squad_shown \
		else maxf(0.0, (view - content) * 0.5 - float(BAND_GAP))
	_scroll_to(0.0)


func _rebuild_sheet() -> void:
	_squad_sheet.show_team(_names[_picks[_sheet_row]], _sheet_row == 0)
	# RetroWindow's wrapper is a plain Control sized only by its minimum,
	# so it has to be told the sheet's height or the scroll range is ~0.
	_squad_wrapper.custom_minimum_size.y = _squad_inner.get_combined_minimum_size().y


func _enter_squad() -> void:
	_in_squad = true
	_refresh()
	_scroll_to(_squad_top())


func _leave_squad() -> void:
	_in_squad = false
	_refresh()
	_scroll_to(0.0)


## Steps through the sheet; up from its top edge hands the cursor back to
## the SHOW/HIDE button (and the page back to the top).
func _scroll_squad(direction: int) -> void:
	var current := float(_scroll.scroll_vertical)
	if direction < 0 and current <= _squad_top() + 1.0:
		_leave_squad()
		return
	_scroll_to(clampf(current + direction * SQUAD_SCROLL_STEP, _squad_top(), _max_scroll()))


func _max_scroll() -> float:
	return maxf(0.0, _scroll.get_v_scroll_bar().max_value - _scroll.size.y)


func _squad_top() -> float:
	return minf(_squad_wrapper.position.y, _max_scroll())


func _scroll_to(target: float) -> void:
	if _scroll_tween != null and _scroll_tween.is_valid():
		_scroll_tween.kill()
	_scroll_tween = create_tween()
	_scroll_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_scroll_tween.tween_property(_scroll, "scroll_vertical", int(target),
		SCROLL_TWEEN_DURATION)


func _on_toggle_hovered() -> void:
	if _in_squad:
		return
	_index = TOGGLE_STOP
	_refresh()


func _on_toggle_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		_index = TOGGLE_STOP
		_in_squad = false
		_toggle_squad()


func _centre_toggle_button() -> void:
	if not is_instance_valid(_toggle_button) or not is_instance_valid(_toggle_band):
		return
	_toggle_button.position = Vector2(
		maxf((_toggle_band.size.x - _toggle_button.size.x) * 0.5, 0.0), 0.0)


# ── Build ────────────────────────────────────────────────────────────

func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	root.add_child(SoftBrutalist.backdrop())

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override(StringName("margin_" + side), int(SCREEN_MARGIN))
	root.add_child(margin)

	var bands := VBoxContainer.new()
	bands.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bands.add_theme_constant_override(&"separation", BAND_GAP)
	margin.add_child(bands)

	# Card, button and sheet scroll together; the hint bar stays put below.
	# The scrollbar is hidden (a default-theme bar is the one grey widget on
	# the page) but the wheel still works.
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	bands.add_child(_scroll)

	var page := VBoxContainer.new()
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_theme_constant_override(&"separation", BAND_GAP)
	_scroll.add_child(page)

	_top_spacer = Control.new()
	_top_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(_top_spacer)

	_build_picker(page)
	_build_toggle(page)
	_build_squad(page)
	_build_hints(bands)


func _build_picker(parent: Control) -> void:
	_picker_height = CARD_MARGIN * 2.0 + HEADER_HEIGHT \
		+ ROW_TITLES.size() * (ROW_HEIGHT + ROW_GAP) - ROW_GAP
	var card := RetroWindow.shell(parent, Vector2(CARD_WIDTH, _picker_height))
	(card.get_parent() as Control).size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	var title := SoftBrutalist.label("FULL GAME", SoftBrutalist.SIZE_TITLE, RetroWindow.BORDER,
		SoftBrutalist.WEIGHT_HEAVY, SoftBrutalist.TRACK_TITLE)
	title.position = Vector2(CARD_MARGIN, CARD_MARGIN)
	card.add_child(title)
	var subtitle := SoftBrutalist.label("PICK YOUR SIDES", SoftBrutalist.SIZE_CAPTION,
		SoftBrutalist.MUTED, SoftBrutalist.WEIGHT_REGULAR, SoftBrutalist.TRACK_LABEL)
	subtitle.position = Vector2(CARD_MARGIN, CARD_MARGIN + 36.0)
	card.add_child(subtitle)

	for i in ROW_TITLES.size():
		var panel := Panel.new()
		panel.position = Vector2(CARD_MARGIN, CARD_MARGIN + HEADER_HEIGHT + i * (ROW_HEIGHT + ROW_GAP))
		panel.size = Vector2(CARD_WIDTH - CARD_MARGIN * 2.0, ROW_HEIGHT)
		card.add_child(panel)
		_row_panels.append(panel)

		var row_title := SoftBrutalist.label(ROW_TITLES[i], SoftBrutalist.SIZE_LABEL,
			RetroWindow.BORDER, SoftBrutalist.WEIGHT_BOLD, SoftBrutalist.TRACK_LABEL)
		row_title.position = Vector2(16.0, (ROW_HEIGHT - 20.0) / 2.0)
		panel.add_child(row_title)

		var value := SoftBrutalist.label("", SoftBrutalist.SIZE_HEADING,
			RetroWindow.BORDER, SoftBrutalist.WEIGHT_HEAVY, SoftBrutalist.TRACK_LABEL)
		value.position = Vector2(150.0, (ROW_HEIGHT - 28.0) / 2.0)
		value.size = Vector2(panel.size.x - 166.0, 28.0)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		panel.add_child(value)
		_value_labels.append(value)


## ActionButton is a Panel sized in its own _ready(), not by a container,
## so it sits in a plain band and is centred by hand — the same way the
## pregame screen places START MATCH.
func _build_toggle(parent: Control) -> void:
	_toggle_band = Control.new()
	_toggle_band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toggle_band.custom_minimum_size.y = ActionButton.HEIGHT
	parent.add_child(_toggle_band)

	_toggle_button = ActionButton.new("SHOW SQUAD")
	_toggle_button.set_icon(&"figure")
	# ActionButton ignores the mouse by default (see its header); this one
	# is a click target too.
	_toggle_button.mouse_filter = Control.MOUSE_FILTER_STOP
	_toggle_button.mouse_entered.connect(_on_toggle_hovered)
	_toggle_button.gui_input.connect(_on_toggle_input)
	_toggle_band.add_child(_toggle_button)

	_toggle_band.resized.connect(_centre_toggle_button)
	_toggle_button.resized.connect(_centre_toggle_button)
	_centre_toggle_button()


func _build_squad(parent: Control) -> void:
	_squad_inner = RetroWindow.card(parent, Vector2(SQUAD_WIDTH, 0.0), SQUAD_PAD)
	_squad_wrapper = _squad_inner.get_parent().get_parent() as Control
	_squad_wrapper.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_squad_sheet = SquadSheet.new()
	_squad_inner.add_child(_squad_sheet)

	# Room under the card for its hard shadow at the very end of the scroll.
	var tail := Control.new()
	tail.custom_minimum_size.y = RetroWindow.SHADOW_OFFSET.y + 2.0
	tail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(tail)


func _build_hints(parent: Control) -> void:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.custom_minimum_size.y = HINT_HEIGHT
	parent.add_child(row)

	_hints = DeviceHintBar.new()
	_hints.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_hints)


func _refresh() -> void:
	for i in _row_panels.size():
		var selected := i == _index and not _in_squad
		_row_panels[i].add_theme_stylebox_override(&"panel", RetroWindow.row_style(selected))
		var club := _names[_picks[i]].to_upper()
		_value_labels[i].text = "‹  %s  ›" % club if selected else club
	_toggle_button.set_selected(_index == TOGGLE_STOP and not _in_squad)
	_refresh_hints()


func _refresh_hints() -> void:
	var squad_label := "Hide squad" if _squad_shown else "Show squad"
	if _in_squad:
		_hints.set_hint_sets({
			InputManager.Device.KEYBOARD: [
				{"keys": "↑ / ↓", "label": "Scroll"},
				{"keys": "T", "label": squad_label},
				{"keys": "Enter", "label": "Match setup"},
				{"keys": "Esc", "label": "Back"},
			],
			InputManager.Device.GAMEPAD: [
				{"keys": "D-Pad ↕", "label": "Scroll"},
				{"keys": "RB", "label": squad_label},
				{"keys": "A", "label": "Match setup"},
				{"keys": "B", "label": "Back"},
			],
		})
		return
	var on_toggle := _index == TOGGLE_STOP
	_hints.set_hint_sets({
		InputManager.Device.KEYBOARD: [
			{"keys": "↑ / ↓", "label": "Select"},
			{"keys": "← / →", "label": "Change club"},
			{"keys": "T", "label": squad_label},
			{"keys": "Enter", "label": squad_label if on_toggle else "Match setup"},
			{"keys": "Esc", "label": "Back"},
		],
		InputManager.Device.GAMEPAD: [
			{"keys": "D-Pad ↕", "label": "Select"},
			{"keys": "D-Pad ↔", "label": "Change club"},
			{"keys": "RB", "label": squad_label},
			{"keys": "A", "label": squad_label if on_toggle else "Match setup"},
			{"keys": "B", "label": "Back"},
		],
	})
