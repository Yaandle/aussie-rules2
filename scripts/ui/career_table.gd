class_name CareerTable
extends RefCounted

## A tan Career card holding a minimal spreadsheet: a header row over a
## 2px rule, one row per entry on a faint zebra stripe, your row tinted
## green, and an optional green cut line under the first N rows — the same
## language team_list_screen.gd's squad sheet uses, in CareerTheme's
## colours. Shared by the ladder (CareerLadderTable), the season stats
## page and, from Phase 4, the roster, so they can't drift apart.
##
## `columns`: [{label, width, align}] — width 0 takes whatever's left
## (one column should). `rows`: [{cells: Array of String, you: bool}].
## Not interactive.

const ROW_HEIGHT := 28.0
const CARD_PAD := 16
const STRIPE := Color(CareerTheme.PANEL_TEXT, 0.06)
const YOU_TINT := Color(CareerTheme.POSITIVE, 0.32)


static func build(columns: Array, rows: Array, width: float, cut_after := 0,
		row_height := ROW_HEIGHT) -> Control:
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
	for col: Dictionary in columns:
		headings.append(col["label"])
	column.add_child(_row(columns, headings, Color(0, 0, 0, 0), true, row_height))
	column.add_child(rule(CareerTheme.PANEL_TEXT, 2.0))

	for i in rows.size():
		var row: Dictionary = rows[i]
		var you := bool(row.get("you", false))
		var fill := YOU_TINT if you else (STRIPE if i % 2 == 1 else Color(0, 0, 0, 0))
		column.add_child(_row(columns, row["cells"], fill, you, row_height))
		if i + 1 == cut_after and i + 1 < rows.size():
			column.add_child(rule(CareerTheme.POSITIVE, 2.0))
	return card


static func _row(columns: Array, cells: Array, fill: Color, bold: bool, height: float) -> Control:
	var panel := Panel.new()
	panel.custom_minimum_size.y = height
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

	for i in columns.size():
		var col: Dictionary = columns[i]
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


static func rule(colour: Color, thickness: float) -> Control:
	var line := ColorRect.new()
	line.color = colour
	line.custom_minimum_size.y = thickness
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return line
