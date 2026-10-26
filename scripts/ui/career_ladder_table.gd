class_name CareerLadderTable
extends RefCounted

## The league ladder as a tan Career card: a header row over a 2px rule,
## one row per team on a faint zebra stripe, your row tinted green, and a
## green cut line under the last promotion place — the same minimal
## spreadsheet language team_list_screen.gd's squad sheet uses, in
## CareerTheme's colours. Built in code like every Career screen; shared
## by the Dashboard and the Season Summary so the two can't drift.
##
## Rows are CareerSeason.ladder() dicts. Not interactive.

## PTS and % last, as on a real AFL ladder. TEAM (width 0) takes the slack.
## The number columns are as narrow as two digits allow: the longest
## generated name ("Jindivick Magpies") needs ~150 px of TEAM.
const COLUMNS := [
	{"label": "", "width": 22.0, "align": HORIZONTAL_ALIGNMENT_RIGHT},
	{"label": "TEAM", "width": 0.0, "align": HORIZONTAL_ALIGNMENT_LEFT},
	{"label": "P", "width": 24.0, "align": HORIZONTAL_ALIGNMENT_RIGHT},
	{"label": "W", "width": 24.0, "align": HORIZONTAL_ALIGNMENT_RIGHT},
	{"label": "L", "width": 24.0, "align": HORIZONTAL_ALIGNMENT_RIGHT},
	{"label": "D", "width": 24.0, "align": HORIZONTAL_ALIGNMENT_RIGHT},
	{"label": "%", "width": 52.0, "align": HORIZONTAL_ALIGNMENT_RIGHT},
	{"label": "PTS", "width": 36.0, "align": HORIZONTAL_ALIGNMENT_RIGHT},
]
const ROW_HEIGHT := 28.0
const CARD_PAD := 16
const STRIPE := Color(CareerTheme.PANEL_TEXT, 0.06)
const YOU_TINT := Color(CareerTheme.POSITIVE, 0.32)


## `cut_after` draws the promotion line under that many rows (0 for none).
static func build(rows: Array[Dictionary], width: float, cut_after: int) -> Control:
	var card := PanelContainer.new()
	card.custom_minimum_size.x = width
	card.add_theme_stylebox_override(&"panel", CareerTheme.panel_style())
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var inner := MarginContainer.new()
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		inner.add_theme_constant_override(StringName("margin_" + side), CARD_PAD)
	card.add_child(inner)

	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 0)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(column)

	var headings: Array = []
	for col: Dictionary in COLUMNS:
		headings.append(col["label"])
	column.add_child(_row(headings, Color(0, 0, 0, 0), true))
	column.add_child(_rule(CareerTheme.PANEL_TEXT, 2.0))

	for i in rows.size():
		var row := rows[i]
		var fill := YOU_TINT if row["you"] else (STRIPE if i % 2 == 1 else Color(0, 0, 0, 0))
		column.add_child(_row(_cells(i + 1, row), fill, row["you"]))
		if i + 1 == cut_after and i + 1 < rows.size():
			column.add_child(_rule(CareerTheme.POSITIVE, 2.0))
	return card


static func _cells(place: int, row: Dictionary) -> Array:
	return [
		"%d" % place,
		String(row["team"]),
		"%d" % row["played"],
		"%d" % row["won"],
		"%d" % row["lost"],
		"%d" % row["drawn"],
		"%.1f" % row["percentage"],
		"%d" % row["points"],
	]


static func _row(cells: Array, fill: Color, bold: bool) -> Control:
	var panel := Panel.new()
	panel.custom_minimum_size.y = ROW_HEIGHT
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	panel.add_theme_stylebox_override(&"panel", style)

	var line := HBoxContainer.new()
	line.set_anchors_preset(Control.PRESET_FULL_RECT)
	line.offset_left = 6.0
	line.offset_right = -6.0
	line.add_theme_constant_override(&"separation", 6)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(line)

	for i in COLUMNS.size():
		var col: Dictionary = COLUMNS[i]
		var cell := CareerTheme.label(String(cells[i]), SoftBrutalist.SIZE_BODY, CareerTheme.PANEL_TEXT,
			SoftBrutalist.WEIGHT_BOLD if bold else SoftBrutalist.WEIGHT_REGULAR)
		cell.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		cell.size_flags_vertical = Control.SIZE_FILL
		cell.horizontal_alignment = col["align"]
		cell.clip_text = true
		if float(col["width"]) > 0.0:
			cell.custom_minimum_size.x = col["width"]
		else:
			cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(cell)
	return panel


static func _rule(colour: Color, thickness: float) -> Control:
	var rule := ColorRect.new()
	rule.color = colour
	rule.custom_minimum_size.y = thickness
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rule
