class_name TeamListScreen
extends CanvasLayer

## Team List screen: a top-down whiteboard preview of a team's starting
## layout (FormationWhiteboard, driven by TeamFormation's fixed 18
## slots). Reached from the main menu via the "team_menu" action (T),
## same as character_menu (C) reaches CharacterScreen — see main_menu.gd.
##
## Built on the Soft Brutalist system (see soft_brutalist.gd) like the
## rest of the game's UI, rather than owning its own separate visual
## identity the way this screen used to (neo-morphism over a muted retro
## palette, see the old NeoPanel-based revision).
##
## Read-only: roster editing (which real players fill which slot) and
## picking between multiple named formations are out of scope for this
## pass, and the previous team_size / start-positions controls have been
## removed now that the roster is fixed at the full 18-a-side (4 on the
## interchange bench, informational only) — this screen just previews
## TeamFormation.SLOTS's one data-driven layout.

const MARGIN := 36.0
const HEADER_HEIGHT := 78.0
const LEGEND_WIDTH := 224.0
const LEGEND_HEIGHT := 248.0
const PANEL_GAP := 18.0
const HINT_HEIGHT := 30.0
const INFO_HEIGHT := 72.0

var _busy := false
var _whiteboard: FormationWhiteboard


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var background := ColorRect.new()
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.color = SoftBrutalist.BACKGROUND
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(background)

	_build_header(root)
	_build_legend(root)
	_build_info_panel(root)
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
	var panel := Panel.new()
	panel.add_theme_stylebox_override(&"panel", SoftBrutalist.panel_style())
	panel.position = Vector2(MARGIN, MARGIN)
	panel.size = Vector2(1280.0 - MARGIN * 2.0, HEADER_HEIGHT)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(panel)

	var column := VBoxContainer.new()
	column.position = Vector2(24.0, 12.0)
	column.add_theme_constant_override(&"separation", 2)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(column)
	column.add_child(SoftBrutalist.label("TEAM LIST", 26, SoftBrutalist.INK,
		SoftBrutalist.WEIGHT_HEAVY, SoftBrutalist.TRACK_TITLE))
	column.add_child(SoftBrutalist.label("STARTING FORMATION PREVIEW", 12,
		SoftBrutalist.MUTED, SoftBrutalist.WEIGHT_REGULAR, SoftBrutalist.TRACK_LABEL))


func _build_legend(root: Control) -> void:
	var top := MARGIN + HEADER_HEIGHT + PANEL_GAP
	var panel := Panel.new()
	panel.add_theme_stylebox_override(&"panel", SoftBrutalist.panel_style())
	panel.position = Vector2(MARGIN, top)
	panel.size = Vector2(LEGEND_WIDTH, LEGEND_HEIGHT)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(panel)

	var column := VBoxContainer.new()
	column.position = Vector2(20.0, 18.0)
	column.add_theme_constant_override(&"separation", 14)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(column)
	column.add_child(SoftBrutalist.label("POSITION LINES", 13, SoftBrutalist.INK,
		SoftBrutalist.WEIGHT_BOLD, SoftBrutalist.TRACK_LABEL))

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
		row.add_child(SoftBrutalist.label(TeamFormation.LINE_NAMES[line], 13,
			SoftBrutalist.INK, SoftBrutalist.WEIGHT_REGULAR, 0))


## Small static info card filling the slot the old editable "TEAM SIZE" /
## "START POSITIONS" panel used to occupy — the roster is fixed now, so
## this is read-only context rather than a control.
func _build_info_panel(root: Control) -> void:
	var top := MARGIN + HEADER_HEIGHT + PANEL_GAP * 2.0 + LEGEND_HEIGHT
	var panel := Panel.new()
	panel.add_theme_stylebox_override(&"panel", SoftBrutalist.panel_style())
	panel.position = Vector2(MARGIN, top)
	panel.size = Vector2(LEGEND_WIDTH, INFO_HEIGHT)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(panel)

	var column := VBoxContainer.new()
	column.position = Vector2(20.0, 16.0)
	column.add_theme_constant_override(&"separation", 4)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(column)
	column.add_child(SoftBrutalist.label("ROSTER", 11, SoftBrutalist.MUTED,
		SoftBrutalist.WEIGHT_REGULAR, SoftBrutalist.TRACK_LABEL))
	column.add_child(SoftBrutalist.label("18 A-SIDE · 4 ON INTERCHANGE", 15,
		SoftBrutalist.INK, SoftBrutalist.WEIGHT_BOLD, 0))


func _build_whiteboard(root: Control) -> void:
	var top := MARGIN + HEADER_HEIGHT + PANEL_GAP
	var left := MARGIN + LEGEND_WIDTH + PANEL_GAP
	var panel := Panel.new()
	panel.add_theme_stylebox_override(&"panel", SoftBrutalist.panel_style())
	panel.position = Vector2(left, top)
	panel.size = Vector2(1280.0 - left - MARGIN, 720.0 - top - MARGIN - HINT_HEIGHT - PANEL_GAP)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(panel)

	_whiteboard = FormationWhiteboard.new()
	_whiteboard.set_anchors_preset(Control.PRESET_FULL_RECT)
	_whiteboard.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(_whiteboard)


func _build_hint(root: Control) -> void:
	var label := SoftBrutalist.label("T / ESC — BACK TO MENU", 12,
		SoftBrutalist.MUTED, SoftBrutalist.WEIGHT_REGULAR, SoftBrutalist.TRACK_LABEL)
	label.position = Vector2(MARGIN, 720.0 - MARGIN - HINT_HEIGHT + 8.0)
	root.add_child(label)
