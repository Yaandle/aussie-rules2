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
## shows the next round (or SEASON COMPLETE) and the updated ladder.
##
## 2026-10-24 playtest ("still cannot see the stats page at end of career
## or game"): the screen worked, but it closed on the first A/Enter/B with
## no delay, so a button already being pressed at the siren skipped it,
## and nothing could reopen it. Now:
## * it reads CareerProfile.last_result, the persisted snapshot full_game.gd
##   records at full time, so the Dashboard's VIEW STATS opens this same
##   screen later;
## * input is ignored for INPUT_GRACE seconds after it appears;
## * layout per the playtest: your team left, the opposition right, each
##   score underneath, a rule, top 3 goalkickers, a rule, top 3 disposals.

const LEADERBOARD_SIZE := 3
const CARD_WIDTH := 520.0
## Seconds after the screen appears before a key/button press can leave it.
## Covers a press still in flight from the last seconds of play plus the
## scene wipe (Tuning.CHARACTER_TRANSITION_TIME).
const INPUT_GRACE := 1.0

var _busy := false
var _elapsed := 0.0
var _result: Dictionary = {}


func _ready() -> void:
	_result = CareerProfile.last_result
	var bg := ColorRect.new()
	bg.color = CareerTheme.BACKGROUND
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre)

	# PanelContainer, not Panel: a plain Panel doesn't grow to fit its
	# children, so inside the CenterContainer the card got zero height, its
	# tan backing never drew, and the dark PANEL_TEXT sat invisible on the
	# dark page with the button pushed off-screen. That blank screen is
	# what the playtest reported as "cannot see the stats page".
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(CARD_WIDTH, 0.0)
	card.add_theme_stylebox_override(&"panel", CareerTheme.panel_style())
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	centre.add_child(card)

	var inner := MarginContainer.new()
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
	column.add_child(_build_rule())
	column.add_child(_build_leaderboard("TOP GOALKICKERS", _entries("goals")))
	column.add_child(_build_rule())
	column.add_child(_build_leaderboard("TOP DISPOSALS", _entries("disposals")))
	column.add_child(_build_return_button())

	# No control legend existed on this screen at all (ui_audit.md
	# finding #2).
	var hints := DeviceHintBar.new()
	column.add_child(hints)
	hints.set_hint_sets({
		InputManager.Device.KEYBOARD: [{"keys": "Enter / Esc", "label": "Return to menu"}],
		InputManager.Device.GAMEPAD: [{"keys": "A / B", "label": "Return to menu"}],
	})


func _build_scoreline() -> Control:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	row.add_child(_build_side(CareerProfile.team_name,
		String(_result.get("home_score", "-")), HORIZONTAL_ALIGNMENT_LEFT))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(spacer)
	row.add_child(_build_side(String(_result.get("opponent", "OPPONENT")),
		String(_result.get("away_score", "-")), HORIZONTAL_ALIGNMENT_RIGHT))
	return row


## One team's name over its score, aligned to its own edge of the card.
func _build_side(team: String, score: String, align: HorizontalAlignment) -> Control:
	var side := VBoxContainer.new()
	side.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var name_label := CareerTheme.label(team, SoftBrutalist.SIZE_LABEL,
		CareerTheme.PANEL_TEXT, SoftBrutalist.WEIGHT_BOLD, 1)
	name_label.horizontal_alignment = align
	side.add_child(name_label)
	var score_label := SoftBrutalist.numeric_label(score, SoftBrutalist.SIZE_TITLE,
		CareerTheme.PANEL_TEXT)
	score_label.horizontal_alignment = align
	side.add_child(score_label)
	return side


## The line break between sections: a thin rule in the card's text ink.
func _build_rule() -> Control:
	var rule := ColorRect.new()
	rule.color = Color(CareerTheme.PANEL_TEXT, 0.35)
	rule.custom_minimum_size = Vector2(0.0, 2.0)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rule


func _entries(key: String) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var raw: Variant = _result.get(key, [])
	if raw is Array:
		for entry: Variant in raw:
			if entry is Dictionary:
				entries.append(entry)
	return entries


## `entries` is the saved MatchState.top_goalkickers()/top_disposals()
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
	panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	panel.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT \
				and _input_ready():
			_return_to_dashboard())
	# Hover feedback — this was a static Panel with no state change at all
	# before (ui_audit.md finding #3), only reachable via the global
	# ui_accept/pause fallback with nothing on screen showing it was the
	# control that would respond.
	panel.mouse_entered.connect(func() -> void:
		panel.add_theme_stylebox_override(&"panel",
			CareerTheme.panel_style(CareerTheme.POSITIVE.lightened(0.15), Color.BLACK, 2)))
	panel.mouse_exited.connect(func() -> void:
		panel.add_theme_stylebox_override(&"panel", CareerTheme.panel_style(CareerTheme.POSITIVE)))

	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(centre)
	centre.add_child(CareerTheme.label("RETURN TO MENU", SoftBrutalist.SIZE_BODY,
		CareerTheme.TEXT, SoftBrutalist.WEIGHT_BOLD, 1))

	return panel


func _process(delta: float) -> void:
	_elapsed += delta


func _input_ready() -> bool:
	return _elapsed >= INPUT_GRACE


func _unhandled_input(event: InputEvent) -> void:
	if _busy or not _input_ready():
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
