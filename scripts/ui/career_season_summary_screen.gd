class_name CareerSeasonSummaryScreen
extends CanvasLayer

## End of a Career season — reached from the Dashboard's SEASON COMPLETE
## card. Left-anchored like the Dashboard: where you finished, what it
## means (promoted, champions, or another season), your record, the final
## ladder, and the seasons before this one. START SEASON N calls
## CareerProfile.start_next_season() — which files this season, moves you
## up a league to a new club if you were promoted, and draws the next
## fixture — then returns to the Dashboard. Esc/B goes back without
## starting it, so the summary can be read again.

const SCREEN_MARGIN_X := SoftBrutalist.SPACE_6
const SCREEN_MARGIN_Y := SoftBrutalist.SPACE_4
const BAND_GAP := SoftBrutalist.SPACE_4
const LADDER_WIDTH := 560.0
const SIDE_WIDTH := 400.0
const BUTTON_HEIGHT := 52.0
const DASHBOARD_SCENE := "res://scenes/ui/career_dashboard_screen.tscn"

var _start_button: Panel
var _busy := false


func _ready() -> void:
	if not CareerProfile.season_complete():
		# Nothing to summarise (reached by hand mid-season) — go home.
		SceneWipe.change_scene.call_deferred(DASHBOARD_SCENE)
		return
	_build()


func _unhandled_input(event: InputEvent) -> void:
	if _busy:
		return
	if event.is_action_pressed(&"pause") or event.is_action_pressed(&"decline"):
		_leave(false)
	elif event.is_action_pressed(&"ui_accept") or event.is_action_pressed(&"confirm"):
		_leave(true)


func _leave(start_next: bool) -> void:
	if _busy:
		return
	_busy = true
	if start_next:
		CareerProfile.start_next_season()
	SceneWipe.change_scene(DASHBOARD_SCENE)


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
	column.add_theme_constant_override(&"separation", int(BAND_GAP))
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(column)

	column.add_child(_build_header())

	var body := HBoxContainer.new()
	body.add_theme_constant_override(&"separation", int(BAND_GAP))
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(body)

	var cut := 1 if CareerSeason.is_top_league(CareerProfile.league_index) \
		else Tuning.CAREER_PROMOTION_PLACES
	var ladder := CareerLadderTable.build(CareerProfile.ladder(), LADDER_WIDTH, cut)
	ladder.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	body.add_child(ladder)
	body.add_child(_build_side_column())


## "SEASON 1 · JUNIORS U18s" over "Finished 2nd", the outcome chip, and
## your record — W/L/D and percentage, from your own ladder row.
func _build_header() -> Control:
	var header := VBoxContainer.new()
	header.add_theme_constant_override(&"separation", 8)
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE

	header.add_child(CareerTheme.label("SEASON %d · %s · %s" % [CareerProfile.season_index + 1,
		CareerSeason.league_name(CareerProfile.league_index), CareerProfile.team_name],
		SoftBrutalist.SIZE_LABEL, CareerTheme.TEXT_MUTED, SoftBrutalist.WEIGHT_BOLD, 1))

	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override(&"separation", int(SoftBrutalist.SPACE_3))
	title_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(title_row)
	title_row.add_child(CareerTheme.label("Finished %s" % CareerSeason.ordinal(CareerProfile.ladder_position()),
		SoftBrutalist.SIZE_TITLE, CareerTheme.TEXT, SoftBrutalist.WEIGHT_HEAVY))
	var chip := _build_outcome_chip()
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	title_row.add_child(chip)

	var row: Dictionary = CareerProfile.ladder()[CareerProfile.ladder_position() - 1]
	header.add_child(CareerTheme.label("W%d  ·  L%d  ·  D%d  ·  %.1f%%  ·  %d points" % [
		row["won"], row["lost"], row["drawn"], row["percentage"], row["points"]],
		SoftBrutalist.SIZE_BODY, CareerTheme.TEXT_MUTED))
	return header


## Green for promoted/champions, tan for another season.
func _build_outcome_chip() -> Control:
	var good := CareerProfile.season_outcome() != CareerProfile.OUTCOME_STAY
	var chip := PanelContainer.new()
	chip.add_theme_stylebox_override(&"panel",
		CareerTheme.panel_style(CareerTheme.POSITIVE if good else CareerTheme.PANEL))
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var inner := MarginContainer.new()
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right"]:
		inner.add_theme_constant_override(StringName("margin_" + side), 12)
	for side in ["top", "bottom"]:
		inner.add_theme_constant_override(StringName("margin_" + side), 6)
	chip.add_child(inner)
	inner.add_child(CareerTheme.label(CareerProfile.season_outcome_text().to_upper(),
		SoftBrutalist.SIZE_LABEL, CareerTheme.TEXT if good else CareerTheme.PANEL_TEXT,
		SoftBrutalist.WEIGHT_BOLD, 1))
	return chip


## What next season is, the start button, past seasons and the hint bar.
func _build_side_column() -> Control:
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 14)
	column.custom_minimum_size.x = SIDE_WIDTH
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE

	column.add_child(CareerTheme.label("YOUR SEASON", SoftBrutalist.SIZE_LABEL, CareerTheme.TEXT,
		SoftBrutalist.WEIGHT_BOLD, 1))
	var mine := CareerTheme.label(_your_season_text(), SoftBrutalist.SIZE_BODY, CareerTheme.TEXT_MUTED)
	mine.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mine.custom_minimum_size.x = SIDE_WIDTH
	column.add_child(mine)

	column.add_child(CareerTheme.label("NEXT SEASON", SoftBrutalist.SIZE_LABEL, CareerTheme.TEXT,
		SoftBrutalist.WEIGHT_BOLD, 1))
	var next := CareerTheme.label(_next_season_text(), SoftBrutalist.SIZE_BODY, CareerTheme.TEXT_MUTED)
	next.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	next.custom_minimum_size.x = SIDE_WIDTH
	column.add_child(next)

	_start_button = _build_start_button()
	column.add_child(_start_button)

	if not CareerProfile.season_history.is_empty():
		var gap := Control.new()
		gap.custom_minimum_size.y = 8.0
		gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_child(gap)
		column.add_child(CareerTheme.label("CAREER SO FAR", SoftBrutalist.SIZE_LABEL, CareerTheme.TEXT,
			SoftBrutalist.WEIGHT_BOLD, 1))
		for entry: Dictionary in CareerProfile.season_history:
			column.add_child(CareerTheme.label("Season %d  ·  %s  ·  %s  ·  W%d L%d" % [
				entry["season"], entry["league"], CareerSeason.ordinal(int(entry["position"])),
				entry["won"], entry["lost"]], SoftBrutalist.SIZE_BODY, CareerTheme.TEXT_MUTED))

	var hints := DeviceHintBar.new()
	column.add_child(hints)
	hints.set_hint_sets({
		InputManager.Device.KEYBOARD: [
			{"keys": "Enter", "label": "Start next season"},
			{"keys": "Esc", "label": "Back"},
		],
		InputManager.Device.GAMEPAD: [
			{"keys": "A", "label": "Start next season"},
			{"keys": "B", "label": "Back"},
		],
	})
	return column


## Games, disposals (and a game), goals and tackles from your season_stats
## line — real matches only, so a fully dev-simmed season reads 0 games.
func _your_season_text() -> String:
	var line := CareerProfile.season_line(CareerProfile.player_id)
	var games := CareerProfile.stat_total(line, "games")
	if games == 0:
		return "No matches played — every round was simulated."
	var disposals := CareerProfile.stat_total(line, "disposals")
	return "%s  ·  %s (%.1f a game)  ·  %s  ·  %s" % [_count(games, "game"),
		_count(disposals, "disposal"), float(disposals) / games,
		_count(CareerProfile.stat_total(line, "goals"), "goal"),
		_count(CareerProfile.stat_total(line, "tackles"), "tackle")]


static func _count(n: int, word: String) -> String:
	return "%d %s%s" % [n, word, "" if n == 1 else "s"]


func _next_season_text() -> String:
	var league := CareerProfile.league_index
	match CareerProfile.season_outcome():
		CareerProfile.OUTCOME_PROMOTED:
			return "You move up to %s with a new club: new teammates, and a league a level stronger." \
				% CareerSeason.league_name(league + 1)
		CareerProfile.OUTCOME_CHAMPIONS:
			return "Top of the pathway. Same club, same league — defend it."
	return "Same club, same league, a fresh draw. Finish top %d to go up." % Tuning.CAREER_PROMOTION_PLACES \
		if not CareerSeason.is_top_league(league) else "Same club, same league, a fresh draw. Finish 1st."


## Green, like START MATCH on the pregame screen; the screen's one control,
## so it carries the selected stroke from the start.
func _build_start_button() -> Panel:
	var panel := Panel.new()
	panel.custom_minimum_size = Vector2(SIDE_WIDTH, BUTTON_HEIGHT)
	panel.add_theme_stylebox_override(&"panel",
		CareerTheme.panel_style(CareerTheme.POSITIVE, Color.BLACK, 3))
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	panel.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_leave(true))

	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(centre)
	centre.add_child(CareerTheme.label("START SEASON %d" % (CareerProfile.season_index + 2),
		SoftBrutalist.SIZE_LABEL, CareerTheme.TEXT, SoftBrutalist.WEIGHT_BOLD, 1))
	return panel
