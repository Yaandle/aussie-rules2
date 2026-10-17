class_name CareerMatchEndScreen
extends CanvasLayer

## Career mode's full-time screen — full_game.gd's _show_match_end_screen()
## routes here instead of the generic match_end_screen.gd whenever
## GameState.career_active is true. Same data source for the scoreline
## (MatchState.scoreline(), fresh — nothing resets MatchState between
## full_game.gd's _finish_match() and this screen loading, see match_end_
## screen.gd's own header note) plus the two leaderboards MatchState.
## top_goalkickers()/top_disposals() now track per Career match (see
## match_state.gd and full_game.gd's _on_player_disposed/_on_scored).
##
## RETURN TO MENU clears GameState.career_active — the one place that
## actually happens (see GameState.gd's own header note on why it isn't
## cleared any earlier) — then goes back to the Dashboard, which by now
## sees CareerProfile.games_played >= 1 and renders its locked state.

const LEADERBOARD_SIZE := 3
const CARD_WIDTH := 440.0

var _busy := false


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = CareerTheme.BACKGROUND
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre)

	var card := Panel.new()
	card.custom_minimum_size = Vector2(CARD_WIDTH, 0.0)
	card.add_theme_stylebox_override(&"panel", CareerTheme.panel_style())
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	centre.add_child(card)

	var inner := MarginContainer.new()
	inner.set_anchors_preset(Control.PRESET_FULL_RECT)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		inner.add_theme_constant_override(StringName("margin_" + side), 28)
	card.add_child(inner)

	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 18)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(column)

	column.add_child(CareerTheme.label("FULL TIME", SoftBrutalist.SIZE_TITLE,
		CareerTheme.PANEL_TEXT, SoftBrutalist.WEIGHT_HEAVY, 1))
	column.add_child(_build_scoreline())
	column.add_child(_build_leaderboard("TOP GOALKICKERS", MatchState.top_goalkickers(LEADERBOARD_SIZE)))
	column.add_child(_build_leaderboard("TOP DISPOSALS", MatchState.top_disposals(LEADERBOARD_SIZE)))
	column.add_child(_build_return_button())


func _build_scoreline() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 24)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var home := VBoxContainer.new()
	home.mouse_filter = Control.MOUSE_FILTER_IGNORE
	home.add_child(CareerTheme.label(CareerProfile.team_name, SoftBrutalist.SIZE_CAPTION,
		CareerTheme.PANEL_TEXT.lightened(0.2), SoftBrutalist.WEIGHT_BOLD, 1))
	home.add_child(SoftBrutalist.numeric_label(MatchState.scoreline(Tuning.Team.HOME),
		SoftBrutalist.SIZE_TITLE, CareerTheme.PANEL_TEXT))
	row.add_child(home)

	var away := VBoxContainer.new()
	away.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var opponent_name := CareerProfile.fixtures[CareerProfile.games_played - 1] \
		if CareerProfile.games_played - 1 < CareerProfile.fixtures.size() else "OPPONENT"
	away.add_child(CareerTheme.label(opponent_name, SoftBrutalist.SIZE_CAPTION,
		CareerTheme.PANEL_TEXT.lightened(0.2), SoftBrutalist.WEIGHT_BOLD, 1))
	away.add_child(SoftBrutalist.numeric_label(MatchState.scoreline(Tuning.Team.AWAY),
		SoftBrutalist.SIZE_TITLE, CareerTheme.PANEL_TEXT))
	row.add_child(away)

	return row


## `entries` is MatchState.top_goalkickers()/top_disposals()'s own
## {name, value} list — empty for a goalless/disposal-less tally (a
## short headless match, or a side that genuinely never scored), shown
## as a single muted placeholder line rather than an empty-looking gap.
func _build_leaderboard(title: String, entries: Array[Dictionary]) -> Control:
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 4)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE

	column.add_child(CareerTheme.label(title, SoftBrutalist.SIZE_LABEL,
		CareerTheme.PANEL_TEXT, SoftBrutalist.WEIGHT_BOLD, 1))

	if entries.is_empty():
		column.add_child(CareerTheme.label("—", SoftBrutalist.SIZE_BODY,
			CareerTheme.PANEL_TEXT.lightened(0.3)))
	for i in entries.size():
		var entry: Dictionary = entries[i]
		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var name_label := CareerTheme.label("%d. %s" % [i + 1, entry["name"]],
			SoftBrutalist.SIZE_BODY, CareerTheme.PANEL_TEXT)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)
		row.add_child(CareerTheme.label(str(entry["value"]), SoftBrutalist.SIZE_BODY,
			CareerTheme.PANEL_TEXT, SoftBrutalist.WEIGHT_BOLD))
		column.add_child(row)

	return column


func _build_return_button() -> Control:
	var panel := Panel.new()
	panel.custom_minimum_size = Vector2(0.0, 48.0)
	panel.add_theme_stylebox_override(&"panel", CareerTheme.panel_style(CareerTheme.POSITIVE))
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_return_to_dashboard())

	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(centre)
	centre.add_child(CareerTheme.label("RETURN TO MENU", SoftBrutalist.SIZE_BODY,
		CareerTheme.TEXT, SoftBrutalist.WEIGHT_BOLD, 1))

	return panel


func _unhandled_input(event: InputEvent) -> void:
	if _busy:
		return
	if event.is_action_pressed(&"ui_accept") or event.is_action_pressed(&"pause") \
			or event.is_action_pressed(&"decline"):
		_return_to_dashboard()


func _return_to_dashboard() -> void:
	if _busy:
		return
	_busy = true
	GameState.career_active = false
	SceneWipe.change_scene("res://scenes/ui/career_dashboard_screen.tscn")
