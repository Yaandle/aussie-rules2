class_name CareerStatsScreen
extends CanvasLayer

## Career mode's VIEW STATS page — reached from the Dashboard. One stat at
## a time (← / → or a click on its tab cycles STATS below), as a
## leaderboard of this season's squad: PLAYER | TOTAL | AVG | GP, highest
## total first, your row tinted. The card on the left is your own line for
## that stat, this season and across the whole career (CareerProfile.
## season_stats / career_stats). LAST MATCH (Enter/A) opens the full-time
## card for the most recent match, which comes back here.
##
## Season stats come from real matches only — a dev-simmed round adds no
## games — and every player who played gets the game, since there's no
## interchange bench yet. Left-anchored and in CareerTheme, like the
## Dashboard.

## Tab order. "disposals" is kicks + handballs (CareerProfile.stat_total).
const STATS := [
	{"key": "disposals", "label": "DISPOSALS"},
	{"key": "kicks", "label": "KICKS"},
	{"key": "handballs", "label": "HANDBALLS"},
	{"key": "marks", "label": "MARKS"},
	{"key": "tackles", "label": "TACKLES"},
	{"key": "goals", "label": "GOALS"},
	{"key": "behinds", "label": "BEHINDS"},
	{"key": "hitouts", "label": "HIT-OUTS"},
]

const COLUMNS := [
	{"label": "", "width": 22.0, "align": HORIZONTAL_ALIGNMENT_RIGHT},
	{"label": "PLAYER", "width": 0.0, "align": HORIZONTAL_ALIGNMENT_LEFT},
	{"label": "TOTAL", "width": 64.0, "align": HORIZONTAL_ALIGNMENT_RIGHT},
	{"label": "AVG", "width": 64.0, "align": HORIZONTAL_ALIGNMENT_RIGHT},
	{"label": "GP", "width": 44.0, "align": HORIZONTAL_ALIGNMENT_RIGHT},
]

const SCREEN_MARGIN_X := SoftBrutalist.SPACE_6
const SCREEN_MARGIN_Y := SoftBrutalist.SPACE_4
const BAND_GAP := SoftBrutalist.SPACE_4
const SIDE_WIDTH := 360.0
## 18 rows have to fit the 720 design height under the tabs.
const ROW_HEIGHT := 26.0
const TAB_HEIGHT := 32.0
const BUTTON_HEIGHT := 44.0

const DASHBOARD_SCENE := "res://scenes/ui/career_dashboard_screen.tscn"
const STATS_SCENE := "res://scenes/ui/career_stats_screen.tscn"
const MATCH_END_SCENE := "res://scenes/ui/career_match_end_screen.tscn"

## Remembered across visits so coming back from LAST MATCH lands on the
## same tab.
static var _stat_index := 0

var _tabs: Array[PanelContainer] = []
var _you_holder: Control
var _table_holder: Control
var _busy := false


func _ready() -> void:
	_build()
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if _busy:
		return
	if event.is_action_pressed(&"move_left") or event.is_action_pressed(&"ui_left"):
		_select(_stat_index - 1)
	elif event.is_action_pressed(&"move_right") or event.is_action_pressed(&"ui_right"):
		_select(_stat_index + 1)
	elif event.is_action_pressed(&"ui_accept") or event.is_action_pressed(&"confirm"):
		_open_last_match()
	elif event.is_action_pressed(&"pause") or event.is_action_pressed(&"decline"):
		_leave(DASHBOARD_SCENE)


func _select(index: int) -> void:
	_stat_index = posmod(index, STATS.size())
	_refresh()


func _open_last_match() -> void:
	if CareerProfile.last_result.is_empty():
		return
	CareerMatchEndScreen.return_scene = STATS_SCENE
	_leave(MATCH_END_SCENE)


func _leave(scene: String) -> void:
	if _busy:
		return
	_busy = true
	SceneWipe.change_scene(scene)


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

	var body := HBoxContainer.new()
	body.add_theme_constant_override(&"separation", int(BAND_GAP))
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(body)
	body.add_child(_build_side_column())

	var right := VBoxContainer.new()
	right.add_theme_constant_override(&"separation", 12)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(right)
	right.add_child(_build_tabs())
	_table_holder = MarginContainer.new()
	_table_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right.add_child(_table_holder)


func _build_side_column() -> Control:
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 14)
	column.custom_minimum_size.x = SIDE_WIDTH
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE

	column.add_child(CareerTheme.label("SEASON %d · %s" % [CareerProfile.season_index + 1,
		CareerSeason.league_name(CareerProfile.league_index)], SoftBrutalist.SIZE_LABEL,
		CareerTheme.TEXT_MUTED, SoftBrutalist.WEIGHT_BOLD, 1))
	column.add_child(CareerTheme.label("Season Stats", SoftBrutalist.SIZE_TITLE, CareerTheme.TEXT,
		SoftBrutalist.WEIGHT_HEAVY))
	column.add_child(CareerTheme.label(CareerProfile.team_name, SoftBrutalist.SIZE_BODY,
		CareerTheme.TEXT_MUTED))

	_you_holder = MarginContainer.new()
	_you_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_you_holder)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override(&"separation", 12)
	actions.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(actions)
	actions.add_child(_build_button("LAST MATCH", not CareerProfile.last_result.is_empty(),
		_open_last_match))
	actions.add_child(_build_button("BACK", true, _leave.bind(DASHBOARD_SCENE)))

	var hints := DeviceHintBar.new()
	column.add_child(hints)
	hints.set_hint_sets({
		InputManager.Device.KEYBOARD: [
			{"keys": "← / →", "label": "Stat"},
			{"keys": "Enter", "label": "Last match"},
			{"keys": "Esc", "label": "Back"},
		],
		InputManager.Device.GAMEPAD: [
			{"keys": "D-Pad ↔", "label": "Stat"},
			{"keys": "A", "label": "Last match"},
			{"keys": "B", "label": "Back"},
		],
	})
	return column


## One clickable tab per STATS entry; _refresh() styles the selected one.
func _build_tabs() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in STATS.size():
		var tab := PanelContainer.new()
		tab.custom_minimum_size.y = TAB_HEIGHT
		tab.mouse_filter = Control.MOUSE_FILTER_STOP
		tab.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		tab.gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton and event.pressed \
					and event.button_index == MOUSE_BUTTON_LEFT:
				_select(i))
		var inner := MarginContainer.new()
		inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for side in ["left", "right"]:
			inner.add_theme_constant_override(StringName("margin_" + side), 10)
		tab.add_child(inner)
		var label := CareerTheme.label(String(STATS[i]["label"]), SoftBrutalist.SIZE_CAPTION,
			CareerTheme.TEXT, SoftBrutalist.WEIGHT_BOLD, 1)
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		inner.add_child(label)
		row.add_child(tab)
		_tabs.append(tab)
	return row


## A tan tile with a centred label, mouse-clickable when `enabled` — the
## same shape as the Dashboard's action buttons, sized for this column.
func _build_button(text: String, enabled: bool, on_pressed: Callable) -> Control:
	var panel := Panel.new()
	panel.custom_minimum_size = Vector2((SIDE_WIDTH - 12.0) * 0.5, BUTTON_HEIGHT)
	var fill := CareerTheme.PANEL if enabled else CareerTheme.PANEL.darkened(0.35)
	var idle := CareerTheme.panel_style(fill)
	panel.add_theme_stylebox_override(&"panel", idle)
	if enabled:
		var hover := CareerTheme.panel_style(fill.lightened(0.12), CareerTheme.POSITIVE, 2)
		panel.mouse_filter = Control.MOUSE_FILTER_STOP
		panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		panel.gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton and event.pressed \
					and event.button_index == MOUSE_BUTTON_LEFT:
				on_pressed.call())
		panel.mouse_entered.connect(func() -> void: panel.add_theme_stylebox_override(&"panel", hover))
		panel.mouse_exited.connect(func() -> void: panel.add_theme_stylebox_override(&"panel", idle))
	else:
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(centre)
	centre.add_child(CareerTheme.label(text, SoftBrutalist.SIZE_LABEL,
		CareerTheme.PANEL_TEXT if enabled else Color(CareerTheme.PANEL_TEXT, 0.5),
		SoftBrutalist.WEIGHT_BOLD, 1))
	return panel


# ── Refresh ──────────────────────────────────────────────────────────

func _refresh() -> void:
	for i in _tabs.size():
		var selected := i == _stat_index
		_tabs[i].add_theme_stylebox_override(&"panel", CareerTheme.panel_style(
			CareerTheme.PANEL if selected else Color(CareerTheme.PANEL, 0.0), CareerTheme.PANEL, 2))
		var label := _tabs[i].get_child(0).get_child(0) as Label
		label.add_theme_color_override(&"font_color",
			CareerTheme.PANEL_TEXT if selected else CareerTheme.TEXT_MUTED)
	_replace(_you_holder, _build_you_card())
	_replace(_table_holder, CareerTable.build(COLUMNS, _table_rows(), 0.0, 0, ROW_HEIGHT))


func _replace(holder: Control, content: Control) -> void:
	for child in holder.get_children():
		child.queue_free()
	holder.add_child(content)


func _stat_key() -> String:
	return String(STATS[_stat_index]["key"])


## Your line for the selected stat: this season and the whole career, each
## as total / average / games.
func _build_you_card() -> Control:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override(&"panel", CareerTheme.panel_style())
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var inner := MarginContainer.new()
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		inner.add_theme_constant_override(StringName("margin_" + side), 18)
	card.add_child(inner)
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 12)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(column)

	column.add_child(CareerTheme.label("%s — %s" % [CareerProfile.player_name,
		String(STATS[_stat_index]["label"])], SoftBrutalist.SIZE_LABEL, CareerTheme.PANEL_TEXT,
		SoftBrutalist.WEIGHT_BOLD, 1))
	column.add_child(_line_row("THIS SEASON", CareerProfile.season_line(CareerProfile.player_id)))
	column.add_child(CareerTable.rule(Color(CareerTheme.PANEL_TEXT, 0.25), 1.0))
	column.add_child(_line_row("CAREER", CareerProfile.career_stats))
	return card


## "THIS SEASON" over three big figures: total, average and games.
func _line_row(title: String, line: Dictionary) -> Control:
	var block := VBoxContainer.new()
	block.add_theme_constant_override(&"separation", 2)
	block.mouse_filter = Control.MOUSE_FILTER_IGNORE
	block.add_child(CareerTheme.label(title, SoftBrutalist.SIZE_CAPTION,
		CareerTheme.PANEL_TEXT.lightened(0.3), SoftBrutalist.WEIGHT_BOLD, 1))
	var figures := HBoxContainer.new()
	figures.add_theme_constant_override(&"separation", 24)
	figures.mouse_filter = Control.MOUSE_FILTER_IGNORE
	block.add_child(figures)
	var games := CareerProfile.stat_total(line, "games")
	var total := CareerProfile.stat_total(line, _stat_key())
	for pair: Array in [["TOTAL", "%d" % total], ["AVG", _average(total, games)], ["GP", "%d" % games]]:
		var cell := VBoxContainer.new()
		cell.add_theme_constant_override(&"separation", 0)
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(SoftBrutalist.numeric_label(pair[1], SoftBrutalist.SIZE_TITLE,
			CareerTheme.PANEL_TEXT))
		cell.add_child(CareerTheme.label(pair[0], SoftBrutalist.SIZE_CAPTION,
			CareerTheme.PANEL_TEXT.lightened(0.3), SoftBrutalist.WEIGHT_BOLD, 1))
		figures.add_child(cell)
	return block


## Your squad this season for the selected stat, highest total first (ties
## on average, then name). Everyone is listed, games or not.
func _table_rows() -> Array:
	var entries: Array = []
	for entry: Dictionary in CareerProfile.roster:
		var id := int(entry.get("id", 0))
		var line := CareerProfile.season_line(id)
		var games := CareerProfile.stat_total(line, "games")
		var total := CareerProfile.stat_total(line, _stat_key())
		entries.append({"name": String(entry["name"]), "you": id == CareerProfile.player_id,
			"total": total, "games": games,
			"avg": float(total) / games if games > 0 else -1.0})
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["total"] != b["total"]:
			return a["total"] > b["total"]
		if not is_equal_approx(a["avg"], b["avg"]):
			return a["avg"] > b["avg"]
		return String(a["name"]) < String(b["name"]))
	var rows: Array = []
	for i in entries.size():
		var e: Dictionary = entries[i]
		rows.append({"you": e["you"], "cells": ["%d" % (i + 1), e["name"], "%d" % e["total"],
			_average(e["total"], e["games"]), "%d" % e["games"]]})
	return rows


static func _average(total: int, games: int) -> String:
	return "%.1f" % (float(total) / games) if games > 0 else "—"
