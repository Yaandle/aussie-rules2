class_name SideSelectScreen
extends CanvasLayer

## FULL GAME's first step (6AC, playtest 2026-11-11: "take TEAM off the
## main menu; the FULL game menu gets side select (your team and the
## opposition), then the TEAM page"). Flow:
##   main menu FULL GAME -> here -> TeamListScreen -> FullGamePregameScreen
##   -> the match. Back steps one screen at a time the other way.
##
## Two rows, YOUR TEAM and OPPOSITION, each cycling through the quick-play
## clubs (Settings.quick_team_names()). The two can't be the same club:
## cycling skips whichever one the other row holds. The picks are display
## only (scoreboard names, the TEAM page's squad); see Settings'
## quick_home_team. Career has its own clubs and never comes through here.
##
## Same RetroWindow card and row language as remap_screen.gd /
## settings_screen.gd.

const CARD_WIDTH := 560.0
const CARD_MARGIN := 32.0
const HEADER_HEIGHT := 88.0
const ROW_HEIGHT := 56.0
const ROW_GAP := 12.0
const HINT_HEIGHT := 32.0
const ROW_TITLES := ["YOUR TEAM", "OPPOSITION"]

var _index := 0
var _busy := false
var _names: Array[String] = []
## Index into _names for each row: 0 = your team, 1 = the opposition.
var _picks := [0, 1]

var _row_panels: Array[Panel] = []
var _value_labels: Array[Label] = []
var _hints: DeviceHintBar


func _ready() -> void:
	_names = Settings.quick_team_names()
	_picks[0] = maxi(0, _names.find(Settings.quick_home_name()))
	_picks[1] = maxi(0, _names.find(Settings.quick_away_name()))
	_build()
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if _busy:
		return
	if event.is_action_pressed(&"pause") or event.is_action_pressed(&"ui_cancel") \
			or event.is_action_pressed(&"decline"):
		_leave("res://scenes/ui/main_menu.tscn")
	elif event.is_action_pressed(&"move_forward") or event.is_action_pressed(&"ui_up") \
			or event.is_action_pressed(&"move_back") or event.is_action_pressed(&"ui_down"):
		_index = 1 - _index
		_refresh()
	elif event.is_action_pressed(&"ui_left") or event.is_action_pressed(&"move_left"):
		_cycle(-1)
	elif event.is_action_pressed(&"ui_right") or event.is_action_pressed(&"move_right"):
		_cycle(1)
	elif event.is_action_pressed(&"ui_accept") or event.is_action_pressed(&"confirm"):
		_leave("res://scenes/ui/team_list_screen.tscn")


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
	_refresh()


func _leave(scene: String) -> void:
	_busy = true
	Settings.quick_home_team = _names[_picks[0]]
	Settings.quick_away_team = _names[_picks[1]]
	Settings.save()
	SceneWipe.change_scene(scene)


# ── Build ────────────────────────────────────────────────────────────

func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	root.add_child(SoftBrutalist.backdrop())

	var card_height := CARD_MARGIN * 2.0 + HEADER_HEIGHT \
		+ ROW_TITLES.size() * (ROW_HEIGHT + ROW_GAP) - ROW_GAP + HINT_HEIGHT + 24.0
	var card_size := Vector2(CARD_WIDTH, card_height)
	var card_wrapper := Control.new()
	card_wrapper.custom_minimum_size = card_size
	card_wrapper.position = Vector2((1280.0 - CARD_WIDTH) / 2.0, (720.0 - card_height) / 2.0)
	root.add_child(card_wrapper)
	var card := RetroWindow.shell(card_wrapper, card_size)

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

	_hints = DeviceHintBar.new()
	_hints.position = Vector2(CARD_MARGIN, card_height - CARD_MARGIN - HINT_HEIGHT + 4.0)
	card.add_child(_hints)
	_hints.set_hint_sets({
		InputManager.Device.KEYBOARD: [
			{"keys": "↑ / ↓", "label": "Select"},
			{"keys": "← / →", "label": "Change club"},
			{"keys": "Enter", "label": "Team"},
			{"keys": "Esc", "label": "Back"},
		],
		InputManager.Device.GAMEPAD: [
			{"keys": "D-Pad ↕", "label": "Select"},
			{"keys": "D-Pad ↔", "label": "Change club"},
			{"keys": "A", "label": "Team"},
			{"keys": "B", "label": "Back"},
		],
	})


func _refresh() -> void:
	for i in _row_panels.size():
		_row_panels[i].add_theme_stylebox_override(&"panel", RetroWindow.row_style(i == _index))
		var club := _names[_picks[i]].to_upper()
		_value_labels[i].text = "‹  %s  ›" % club if i == _index else club
