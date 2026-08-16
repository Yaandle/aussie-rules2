class_name TeamListScreen
extends CanvasLayer

## Read-only Team List / Edit Team preview (design brief's Team List
## screen, starting scope): a top-down whiteboard of the field outline
## with a dot for each of TeamFormation's 18 slots, plus a legend of the
## six position lines. Reached from the main menu via the "team_menu"
## action (T), the same way character_menu (C) reaches CharacterScreen —
## see main_menu.gd.
##
## Deliberately its own visual identity: neo-morphism/soft-UI (see
## neo_panel.gd) over a muted retro palette, not the bright broadcast look
## the rest of the game uses — the same reasoning CharacterScreen's dark
## teal "studio" look was kept apart from match-day styling (see that
## script's header). ui_style.gd's palette is not reused here for that
## reason, though its component *pattern* (FontVariation type scale,
## rounded() StyleBox factory) is: `_font()` below is the same
## FontVariation idea with this screen's own weights, and NeoPanel's
## StyleBoxFlat.draw() calls are UIStyle.rounded()'s technique extended to
## three layered boxes instead of one.
##
## Wiring formations into a live kickoff, editing rosters, or picking
## which formation a team uses are explicitly out of scope for this pass
## (see the brief) — this screen only ever shows the one data-driven
## layout TeamFormation.SLOTS describes.

const BG_COLOUR := Color("#ded6c3")
const PANEL_FILL := Color("#e2dbc9")
const SHADOW_DARK := Color("#b9ae95")
const SHADOW_LIGHT := Color("#fbf7ea")
const TEXT_PRIMARY := Color("#4a4436")
const TEXT_MUTED := Color("#8c826c")
const ACCENT := Color("#b5652f")

const MARGIN := 36.0
const HEADER_HEIGHT := 78.0
const LEGEND_WIDTH := 224.0
const PANEL_GAP := 18.0
const HINT_HEIGHT := 30.0

var _busy := false


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var background := ColorRect.new()
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.color = BG_COLOUR
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(background)

	_build_header(root)
	_build_legend(root)
	_build_whiteboard(root)
	_build_hint(root)


func _unhandled_input(event: InputEvent) -> void:
	if _busy:
		return
	if event.is_action_pressed(&"pause") or event.is_action_pressed(&"team_menu"):
		_exit_to_menu()


func _exit_to_menu() -> void:
	if _busy:
		return
	_busy = true
	SceneWipe.change_scene("res://scenes/ui/main_menu.tscn")


# ── Build ────────────────────────────────────────────────────────────

func _build_header(root: Control) -> void:
	var panel := NeoPanel.new()
	panel.base_fill = PANEL_FILL
	panel.shadow_dark = SHADOW_DARK
	panel.shadow_light = SHADOW_LIGHT
	panel.radius = 20
	panel.position = Vector2(MARGIN, MARGIN)
	panel.size = Vector2(1280.0 - MARGIN * 2.0, HEADER_HEIGHT)
	root.add_child(panel)

	var column := VBoxContainer.new()
	column.position = Vector2(24.0, 12.0)
	column.add_theme_constant_override(&"separation", 2)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(column)
	column.add_child(_label("TEAM LIST", 26, TEXT_PRIMARY, 0.35, 4))
	column.add_child(_label("18-A-SIDE FORMATION PREVIEW · READ ONLY", 12, TEXT_MUTED, -0.2, 1))


func _build_legend(root: Control) -> void:
	var top := MARGIN + HEADER_HEIGHT + PANEL_GAP
	var panel := NeoPanel.new()
	panel.base_fill = PANEL_FILL
	panel.shadow_dark = SHADOW_DARK
	panel.shadow_light = SHADOW_LIGHT
	panel.radius = 20
	panel.position = Vector2(MARGIN, top)
	panel.size = Vector2(LEGEND_WIDTH, 720.0 - top - MARGIN - HINT_HEIGHT - PANEL_GAP)
	root.add_child(panel)

	var column := VBoxContainer.new()
	column.position = Vector2(20.0, 18.0)
	column.add_theme_constant_override(&"separation", 14)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(column)
	column.add_child(_label("POSITION LINES", 13, TEXT_PRIMARY, 0.2, 2))

	for line: int in TeamFormation.LINE_NAMES.size():
		var row := HBoxContainer.new()
		row.add_theme_constant_override(&"separation", 10)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_child(row)

		var swatch := ColorRect.new()
		swatch.custom_minimum_size = Vector2(14.0, 14.0)
		swatch.color = FormationWhiteboard.LINE_COLOURS[line]
		swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(swatch)
		row.add_child(_label(TeamFormation.LINE_NAMES[line], 13, TEXT_PRIMARY, -0.1, 1))


func _build_whiteboard(root: Control) -> void:
	var top := MARGIN + HEADER_HEIGHT + PANEL_GAP
	var left := MARGIN + LEGEND_WIDTH + PANEL_GAP
	var panel := NeoPanel.new()
	panel.base_fill = PANEL_FILL
	panel.shadow_dark = SHADOW_DARK
	panel.shadow_light = SHADOW_LIGHT
	panel.radius = 20
	panel.position = Vector2(left, top)
	panel.size = Vector2(1280.0 - left - MARGIN, 720.0 - top - MARGIN - HINT_HEIGHT - PANEL_GAP)
	root.add_child(panel)

	var whiteboard := FormationWhiteboard.new()
	whiteboard.set_anchors_preset(Control.PRESET_FULL_RECT)
	whiteboard.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(whiteboard)


func _build_hint(root: Control) -> void:
	var label := _label("T / ESC — BACK TO MENU", 12, TEXT_MUTED, -0.1, 1)
	label.position = Vector2(MARGIN, 720.0 - MARGIN - HINT_HEIGHT + 8.0)
	root.add_child(label)


func _label(text: String, size: int, colour: Color, embolden: float, tracking: int) -> Label:
	var node := Label.new()
	node.text = text
	var variation := FontVariation.new()
	variation.base_font = ThemeDB.fallback_font
	variation.variation_embolden = embolden
	variation.spacing_glyph = tracking
	node.add_theme_font_override(&"font", variation)
	node.add_theme_font_size_override(&"font_size", size)
	node.add_theme_color_override(&"font_color", colour)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node
