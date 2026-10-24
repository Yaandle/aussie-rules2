class_name MatchEndScreen
extends CanvasLayer

## Read-only full-time scoreline + box-score screen (design brief).
##
## Reads the final score from MatchState.scoreline() — the same call
## full_game.gd's `_finish_match()` uses for the scoreboard flash — and the
## per-team disposal/mark/tackle tallies from MatchState's own stat
## dictionaries (FEATURE_AUDIT.md (archived)'s post-match-stats item), both
## fresh in _ready() rather than passed as scene-change parameters: nothing
## resets MatchState between full_game.gd's _finish_match() and this
## screen loading, so there's nothing to lose crossing the scene swap.
## No replay/rematch wiring; the only action is returning to the main
## menu.
##
## RetroWindow shell + a real selectable/hover RETURN TO MENU row + a
## DeviceHintBar, matching this screen's siblings (settings/pause/remap/
## team-list/career_match_end) — this used to be a bare SoftBrutalist cream
## card with a static button and no legend at all (ui_audit.md findings
## #2/#3/#5, which named this screen specifically as the one place left
## that never got the rest of the project's "windowed retro console" pass).

const CARD_WIDTH := 520.0

const HEADER_TOP := 32.0
const SCORE_HOME_LABEL_TOP := 104.0
const SCORE_HOME_VALUE_TOP := 126.0
const SCORE_AWAY_LABEL_TOP := 178.0
const SCORE_AWAY_VALUE_TOP := 200.0

## Per-team box score — key is the matching MatchState dictionary's own
## property name, read dynamically (MatchState.get(key)) so this table is
## the only place that needs to change if another stat gets tracked later.
const STAT_ROWS := [
	{"label": "Kicks", "key": "kicks"},
	{"label": "Handballs", "key": "handballs"},
	{"label": "Marks", "key": "marks"},
	{"label": "Tackles", "key": "tackles"},
]
const STATS_TOP := 256.0
const STATS_HEADER_HEIGHT := 26.0
const STATS_ROW_HEIGHT := 27.0
const STATS_LABEL_X := 32.0
const STATS_COLUMN_WIDTH := 92.0
const STATS_HOME_X := CARD_WIDTH - 64.0 - STATS_COLUMN_WIDTH * 2.0 - 16.0
const STATS_AWAY_X := CARD_WIDTH - 64.0 - STATS_COLUMN_WIDTH

const BUTTON_HEIGHT := 56.0
const BUTTON_GAP := 28.0
const HINT_GAP := 16.0
const HINT_HEIGHT := 24.0
const CARD_BOTTOM_MARGIN := 32.0

var _busy := false
var _button_panel: Panel
var _button_label: Label


func _ready() -> void:
	var stats_bottom := STATS_TOP + STATS_HEADER_HEIGHT + STAT_ROWS.size() * STATS_ROW_HEIGHT
	var button_top := stats_bottom + BUTTON_GAP
	var hint_top := button_top + BUTTON_HEIGHT + HINT_GAP
	var card_height := hint_top + HINT_HEIGHT + CARD_BOTTOM_MARGIN

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	root.add_child(SoftBrutalist.backdrop())

	# RetroWindow shell — this screen was the one sibling left on a plain
	# SoftBrutalist card instead of the "windowed retro console" shell
	# settings/pause/remap/team-list/character already share (ui_audit.md
	# finding #5).
	var card_wrapper := Control.new()
	card_wrapper.custom_minimum_size = Vector2(CARD_WIDTH, card_height)
	card_wrapper.position = Vector2((1280.0 - CARD_WIDTH) / 2.0, (720.0 - card_height) / 2.0)
	root.add_child(card_wrapper)
	var card := RetroWindow.shell(card_wrapper, Vector2(CARD_WIDTH, card_height))

	var title := SoftBrutalist.label("FULL TIME", SoftBrutalist.SIZE_TITLE, RetroWindow.BORDER,
		SoftBrutalist.WEIGHT_HEAVY, SoftBrutalist.TRACK_TITLE)
	title.position = Vector2(32.0, HEADER_TOP)
	card.add_child(title)

	var home_label := SoftBrutalist.label("HOME", SoftBrutalist.SIZE_LABEL, Scoreboard.COLOUR_HOME,
		SoftBrutalist.WEIGHT_BOLD, SoftBrutalist.TRACK_LABEL)
	home_label.position = Vector2(32.0, SCORE_HOME_LABEL_TOP)
	card.add_child(home_label)

	var home_score := SoftBrutalist.numeric_label(MatchState.scoreline(Tuning.Team.HOME), SoftBrutalist.SIZE_TITLE,
		RetroWindow.ACCENT)
	home_score.position = Vector2(32.0, SCORE_HOME_VALUE_TOP)
	card.add_child(home_score)

	var away_label := SoftBrutalist.label("AWAY", SoftBrutalist.SIZE_LABEL, Scoreboard.COLOUR_AWAY,
		SoftBrutalist.WEIGHT_BOLD, SoftBrutalist.TRACK_LABEL)
	away_label.position = Vector2(32.0, SCORE_AWAY_LABEL_TOP)
	card.add_child(away_label)

	var away_score := SoftBrutalist.numeric_label(MatchState.scoreline(Tuning.Team.AWAY), SoftBrutalist.SIZE_TITLE,
		RetroWindow.ACCENT)
	away_score.position = Vector2(32.0, SCORE_AWAY_VALUE_TOP)
	card.add_child(away_score)

	_build_stats(card)

	# A real selectable row, not a button permanently stuck in its own
	# "hover" StyleBox regardless of actual hover state (the bug this
	# replaces) — shown selected by default since it's the only control on
	# the screen, same "nothing else to lose focus to" reasoning
	# pause_screen.gd's single-row case would also apply if it only had one
	# row. Mouse hover and a click both still work; so does Enter/pause/A
	# globally via _unhandled_input below.
	_button_panel = Panel.new()
	_button_panel.add_theme_stylebox_override(&"panel", RetroWindow.row_style(true))
	_button_panel.position = Vector2(32.0, button_top)
	_button_panel.size = Vector2(CARD_WIDTH - 64.0, BUTTON_HEIGHT)
	_button_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_button_panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_button_panel.gui_input.connect(_on_button_gui_input)
	card.add_child(_button_panel)

	_button_label = SoftBrutalist.label("RETURN TO MENU", SoftBrutalist.SIZE_BODY, RetroWindow.BORDER,
		SoftBrutalist.WEIGHT_BOLD, SoftBrutalist.TRACK_LABEL)
	_button_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_button_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_button_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_button_panel.add_child(_button_label)

	# No control legend existed on this screen at all (ui_audit.md
	# finding #2).
	var hints := DeviceHintBar.new()
	hints.position = Vector2(32.0, hint_top)
	card.add_child(hints)
	hints.set_hint_sets({
		InputManager.Device.KEYBOARD: [{"keys": "Enter / Esc", "label": "Return to menu"}],
		InputManager.Device.GAMEPAD: [{"keys": "A / B", "label": "Return to menu"}],
	})


func _on_button_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		_return_to_menu()


## HOME/AWAY column headers over four right-aligned value rows — the same
## fixed-column-width idea Scoreboard.gd already uses for its own score
## digits, so a stat growing a digit (single- to double-figure disposals)
## can't shove anything else in the row sideways.
func _build_stats(card: Panel) -> void:
	var header_home := SoftBrutalist.label("HOME", SoftBrutalist.SIZE_CAPTION, Scoreboard.COLOUR_HOME,
		SoftBrutalist.WEIGHT_BOLD, SoftBrutalist.TRACK_LABEL)
	header_home.position = Vector2(STATS_HOME_X, STATS_TOP)
	header_home.size = Vector2(STATS_COLUMN_WIDTH, STATS_HEADER_HEIGHT)
	header_home.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	card.add_child(header_home)

	var header_away := SoftBrutalist.label("AWAY", SoftBrutalist.SIZE_CAPTION, Scoreboard.COLOUR_AWAY,
		SoftBrutalist.WEIGHT_BOLD, SoftBrutalist.TRACK_LABEL)
	header_away.position = Vector2(STATS_AWAY_X, STATS_TOP)
	header_away.size = Vector2(STATS_COLUMN_WIDTH, STATS_HEADER_HEIGHT)
	header_away.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	card.add_child(header_away)

	for i in STAT_ROWS.size():
		var row: Dictionary = STAT_ROWS[i]
		var top := STATS_TOP + STATS_HEADER_HEIGHT + float(i) * STATS_ROW_HEIGHT
		var home_value: int = (MatchState.get(row["key"]) as Dictionary)[Tuning.Team.HOME]
		var away_value: int = (MatchState.get(row["key"]) as Dictionary)[Tuning.Team.AWAY]

		var label := SoftBrutalist.label(row["label"], SoftBrutalist.SIZE_BODY, SoftBrutalist.MUTED,
			SoftBrutalist.WEIGHT_REGULAR, SoftBrutalist.TRACK_NONE)
		label.position = Vector2(STATS_LABEL_X, top)
		card.add_child(label)

		var home_number := SoftBrutalist.numeric_label(str(home_value), SoftBrutalist.SIZE_BODY, SoftBrutalist.INK)
		home_number.position = Vector2(STATS_HOME_X, top)
		home_number.size = Vector2(STATS_COLUMN_WIDTH, STATS_ROW_HEIGHT)
		home_number.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		card.add_child(home_number)

		var away_number := SoftBrutalist.numeric_label(str(away_value), SoftBrutalist.SIZE_BODY, SoftBrutalist.INK)
		away_number.position = Vector2(STATS_AWAY_X, top)
		away_number.size = Vector2(STATS_COLUMN_WIDTH, STATS_ROW_HEIGHT)
		away_number.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		card.add_child(away_number)


func _unhandled_input(event: InputEvent) -> void:
	if _busy:
		return
	if event.is_action_pressed(&"ui_accept") or event.is_action_pressed(&"pause") \
			or event.is_action_pressed(&"ui_cancel"):
		_return_to_menu()


func _return_to_menu() -> void:
	if _busy:
		return
	_busy = true
	SceneWipe.change_scene("res://scenes/ui/main_menu.tscn")
