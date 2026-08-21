class_name TeamListScreen
extends CanvasLayer

## Team List screen: a top-down whiteboard preview of a team's starting
## layout (FormationWhiteboard, driven by TeamFormation's fixed 18
## slots). Reached from the main menu via the "team_menu" action (T),
## same as character_menu (C) reaches CharacterScreen — see main_menu.gd.
##
## Deliberately its own visual identity again — a chunky neomorphism x
## brutalist retro-'90s treatment (thick near-black borders, hard offset
## drop shadows instead of SoftBrutalist's blurred ones, a warm parchment
## card fill) rather than the rest of the game's Soft Brutalist system.
## Only the card shell changes: layout, the legend/roster content, and
## FormationWhiteboard itself are untouched — see _retro_card() below,
## which is a drop-in replacement for what used to be a plain _card()
## built on SoftBrutalist.panel_style()/soften().
##
## Roster editing (which named real player fills which of the 18 slots) is
## still out of scope — the project has no multi-player roster/persistence
## system yet (see character_screen.gd's own header). What IS now editable
## (Team Edit expansion, polish-pass brief): which of Settings.
## FORMATION_PRESETS' curated 4-a-side shapes Full Game actually spawns the
## HOME side into — Ui-left/right cycles it in the MATCHDAY FORMATION card
## below, persisted via Settings.save() same as settings_screen.gd's own
## rows, and highlighted live on the whiteboard. FullGame._kickoff_slot()
## reads the same Settings.home_formation_slots() this screen writes, so a
## choice made here changes where the human side actually lines up.
##
## ── Layout ──────────────────────────────────────────────────────────
## One centred content column, not a full-width spread. The board is a
## portrait oval and it sizes itself to the available *height*, so when
## its panel was given every pixel of width left over after the legend
## column, the drawing ended up about 410px wide inside a 960px panel —
## two thirds of the screen's largest card was empty. Sizing that panel
## to the board it holds and centring the pair instead turns that dead
## area into margin, which reads as deliberate space rather than as a
## card someone forgot to fill.

const SCREEN_MARGIN := SoftBrutalist.SPACE_4        ## 32
const BAND_GAP := int(SoftBrutalist.SPACE_2)        ## 16
const PANEL_GAP := int(SoftBrutalist.SPACE_3)       ## 24
## Tall enough for a 30px title over a 13px subtitle *plus* the card's own
## padding. At 84 the two lines measured 61px against 36px of usable box
## and the subtitle printed through the bottom border.
const HEADER_HEIGHT := 104.0
const HINT_HEIGHT := 24.0
const COLUMN_WIDTH := 320.0
const CARD_PAD := SoftBrutalist.SPACE_3             ## 24

## Board panel width. The board draws itself to a portrait AFL aspect
## (Tuning's half-width over half-length) fitted to whatever height it is
## given, so this is that aspect applied to the tallest band this screen
## can offer, plus the board's own inset — i.e. the width at which the
## panel is exactly full rather than padded with empty cream.
const BOARD_ASPECT := 0.818
const BOARD_BAND_HEIGHT := 720.0 - SCREEN_MARGIN * 2.0 - HEADER_HEIGHT - HINT_HEIGHT \
	- float(BAND_GAP) * 2.0
const BOARD_PANEL_WIDTH := (BOARD_BAND_HEIGHT - FormationWhiteboard.MARGIN * 2.0) \
	* BOARD_ASPECT + FormationWhiteboard.MARGIN * 2.0
const CONTENT_WIDTH := COLUMN_WIDTH + float(PANEL_GAP) + BOARD_PANEL_WIDTH

## ── Retro neomorphism x brutalist card shell ───────────────────────────
## A warm parchment fill, a thick near-black rule (brutalist), and a
## solid offset shadow with no blur (the neomorphic-brutalist hybrid's
## signature — a real embossed shape, but hard-edged like a stamped card
## rather than airbrushed) instead of SoftBrutalist's soft blur. Local to
## this screen only; see the header comment for why.
const RETRO_PANEL := Color("#F3E7CE")     ## warm parchment, not plain white
const RETRO_BORDER := Color("#1C1A17")    ## near-black, not pure ink — warmer
const RETRO_SHADOW := Color("#2F5F5A")    ## dusty teal, the one recurring accent
const RETRO_ACCENT := Color("#C2542F")    ## rust/terracotta — title underline, hint chips
const RETRO_BORDER_WIDTH := 4
const RETRO_RADIUS := 6                   ## chunky, not the rest of the app's 16px soft round
const RETRO_SHADOW_OFFSET := Vector2(7.0, 7.0)

const FORMATION_CARD_HEIGHT := 88.0   ## was ROSTER_HEIGHT — this card is the formation picker now, not roster info
## Six legend rows plus their heading and the card padding. Fixed rather
## than expanding: a legend stretched to the full height of the board
## beside it is mostly empty card, and the slack reads better as space
## between two compact cards.
const LEGEND_HEIGHT := 296.0

var _busy := false
var _whiteboard: FormationWhiteboard
var _formation_name_label: Label


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	root.add_child(SoftBrutalist.backdrop())

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override(StringName("margin_" + side), int(SCREEN_MARGIN))
	root.add_child(margin)

	var bands := VBoxContainer.new()
	bands.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bands.add_theme_constant_override(&"separation", BAND_GAP)
	margin.add_child(bands)

	_build_header(bands)
	_build_body(bands)
	_build_hint(bands)
	_refresh_formation_display()


func _unhandled_input(event: InputEvent) -> void:
	if _busy:
		return
	if event.is_action_pressed(&"pause") or event.is_action_pressed(&"team_menu"):
		_exit_to_menu()
	elif event.is_action_pressed(&"ui_left"):
		_cycle_formation(-1)
	elif event.is_action_pressed(&"ui_right"):
		_cycle_formation(1)


func _exit_to_menu() -> void:
	if _busy:
		return
	_busy = true
	Settings.save()
	SceneWipe.change_scene("res://scenes/ui/main_menu.tscn")


func _cycle_formation(step: int) -> void:
	# Wraps rather than clamps — same convention settings_screen.gd's own
	# Row.cycle() uses for every other left/right picker in the project.
	var count := Settings.FORMATION_PRESETS.size()
	Settings.home_formation_index = (Settings.home_formation_index + step + count) % count
	_refresh_formation_display()


func _refresh_formation_display() -> void:
	if is_instance_valid(_whiteboard):
		_whiteboard.selected_indices = PackedInt32Array(Settings.home_formation_slots())
	if is_instance_valid(_formation_name_label):
		_formation_name_label.text = Settings.home_formation_name()


# ── Build ────────────────────────────────────────────────────────────

## A card is a plain Control wrapper (not a Container, so its children's
## positions don't get re-sorted) exactly `minimum` in size — the same
## external footprint the old SoftBrutalist-based card claimed, so none of
## this screen's hand-tuned pixel geometry (CONTENT_WIDTH, BOARD_PANEL_
## WIDTH etc.) shifts. Inside it: a solid RETRO_SHADOW panel offset by
## RETRO_SHADOW_OFFSET first, then the real parchment-and-border panel at
## (0,0) on top — a hard-edged stamped shadow instead of a blurred one,
## intentionally allowed to poke past the wrapper's own claimed rect
## since Control rendering isn't clipped to its reported size.
func _card(parent: Control, minimum: Vector2) -> MarginContainer:
	var wrapper := Control.new()
	wrapper.custom_minimum_size = minimum
	wrapper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(wrapper)

	# Both anchored full-rect to `wrapper` (not sized off the `minimum`
	# snapshot directly) so a caller that stretches the wrapper afterwards
	# (SIZE_EXPAND_FILL on the whiteboard panel, sizing it to the row's
	# actual height) carries the shadow and the front panel along with it.
	var shadow := Panel.new()
	shadow.set_anchors_preset(Control.PRESET_FULL_RECT)
	shadow.offset_left = RETRO_SHADOW_OFFSET.x
	shadow.offset_right = RETRO_SHADOW_OFFSET.x
	shadow.offset_top = RETRO_SHADOW_OFFSET.y
	shadow.offset_bottom = RETRO_SHADOW_OFFSET.y
	shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shadow_style := StyleBoxFlat.new()
	shadow_style.bg_color = RETRO_SHADOW
	shadow_style.set_corner_radius_all(RETRO_RADIUS)
	shadow_style.anti_aliasing_size = 1.0
	shadow.add_theme_stylebox_override(&"panel", shadow_style)
	wrapper.add_child(shadow)

	var panel := Panel.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = RETRO_PANEL
	panel_style.border_color = RETRO_BORDER
	panel_style.set_border_width_all(RETRO_BORDER_WIDTH)
	panel_style.set_corner_radius_all(RETRO_RADIUS)
	panel_style.anti_aliasing_size = 1.0
	panel.add_theme_stylebox_override(&"panel", panel_style)
	wrapper.add_child(panel)

	var inner := MarginContainer.new()
	inner.set_anchors_preset(Control.PRESET_FULL_RECT)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side: String in ["left", "right", "top", "bottom"]:
		inner.add_theme_constant_override(StringName("margin_" + side), int(CARD_PAD))
	panel.add_child(inner)
	return inner


func _build_header(parent: Control) -> void:
	var inner := _card(parent, Vector2(CONTENT_WIDTH, HEADER_HEIGHT))
	# Two levels up: inner -> panel -> wrapper. Size flags have to land on
	# the wrapper, since that's the node actually parented into `parent`'s
	# layout — panel and shadow are just anchored full-rect inside it now.
	(inner.get_parent().get_parent() as Control).size_flags_horizontal = \
		Control.SIZE_SHRINK_CENTER

	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override(&"separation", 2)
	inner.add_child(column)
	column.add_child(SoftBrutalist.label("TEAM LIST", SoftBrutalist.SIZE_TITLE,
		RETRO_BORDER, SoftBrutalist.WEIGHT_HEAVY, SoftBrutalist.TRACK_TITLE))

	# The one "printed card" flourish: a short rust-coloured rule under the
	# title, the retro touch a plain type-only header didn't have.
	var underline := Panel.new()
	underline.custom_minimum_size = Vector2(56.0, 4.0)
	underline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var underline_style := StyleBoxFlat.new()
	underline_style.bg_color = RETRO_ACCENT
	underline.add_theme_stylebox_override(&"panel", underline_style)
	column.add_child(underline)
	column.add_child(SoftBrutalist.label("STARTING FORMATION PREVIEW",
		SoftBrutalist.SIZE_LABEL, SoftBrutalist.MUTED, SoftBrutalist.WEIGHT_REGULAR,
		SoftBrutalist.TRACK_LABEL))


func _build_body(parent: Control) -> void:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Neither child expands, so ALIGNMENT_CENTER centres the pair as a
	# group and the leftover width becomes even margin on both sides.
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override(&"separation", PANEL_GAP)
	parent.add_child(row)

	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.custom_minimum_size.x = COLUMN_WIDTH
	column.add_theme_constant_override(&"separation", PANEL_GAP)
	row.add_child(column)

	_build_legend(column)

	# Pushes the roster card down to sit level with the board panel's
	# bottom edge, so the left column reads as two anchored cards rather
	# than two floating ones.
	var spacer := Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(spacer)

	_build_info_panel(column)
	_build_whiteboard(row)


func _build_legend(parent: Control) -> void:
	var inner := _card(parent, Vector2(COLUMN_WIDTH, LEGEND_HEIGHT))

	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override(&"separation", int(SoftBrutalist.SPACE_2))
	inner.add_child(column)
	column.add_child(SoftBrutalist.label("POSITION LINES", SoftBrutalist.SIZE_LABEL,
		SoftBrutalist.MUTED, SoftBrutalist.WEIGHT_BOLD, SoftBrutalist.TRACK_LABEL))

	for line: int in TeamFormation.LINE_NAMES.size():
		var line_row := HBoxContainer.new()
		line_row.add_theme_constant_override(&"separation", int(SoftBrutalist.SPACE_2))
		line_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_child(line_row)

		# Rounded, not a bare square: a hard-cornered swatch beside a set
		# of 16px-radius cards is the one element on the screen that does
		# not belong to the shape language.
		var swatch := Panel.new()
		var swatch_style := SoftBrutalist.panel_style(FormationWhiteboard.LINE_COLOURS[line],
			SoftBrutalist.RADIUS_XS, FormationWhiteboard.LINE_COLOURS[line].darkened(0.25))
		swatch.add_theme_stylebox_override(&"panel", swatch_style)
		swatch.custom_minimum_size = Vector2(16.0, 16.0)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line_row.add_child(swatch)

		var name_label := SoftBrutalist.label(TeamFormation.LINE_NAMES[line],
			SoftBrutalist.SIZE_BODY, SoftBrutalist.INK, SoftBrutalist.WEIGHT_REGULAR,
			SoftBrutalist.TRACK_NONE)
		name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		line_row.add_child(name_label)


## Replaces the old static "18 A-SIDE" info card with the one real control
## this screen now has (Team Edit expansion, polish-pass brief): Ui-left/
## right cycles Settings.home_formation_index through FORMATION_PRESETS,
## same left/right-cycle convention settings_screen.gd's own Row rows use.
## The 4 chosen slots ring themselves on the whiteboard via
## _refresh_formation_display() — this card only owns the name readout and
## the ‹ › affordance, not the highlight itself.
func _build_info_panel(parent: Control) -> void:
	var inner := _card(parent, Vector2(COLUMN_WIDTH, FORMATION_CARD_HEIGHT))

	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override(&"separation", 4)
	inner.add_child(column)
	column.add_child(SoftBrutalist.label("MATCHDAY FORMATION", SoftBrutalist.SIZE_CAPTION,
		SoftBrutalist.MUTED, SoftBrutalist.WEIGHT_REGULAR, SoftBrutalist.TRACK_LABEL))

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override(&"separation", int(SoftBrutalist.SPACE_2))
	column.add_child(row)

	row.add_child(SoftBrutalist.label("‹", SoftBrutalist.SIZE_HEADING, RETRO_ACCENT,
		SoftBrutalist.WEIGHT_BOLD))

	var value := SoftBrutalist.label(Settings.home_formation_name(), SoftBrutalist.SIZE_BODY,
		SoftBrutalist.INK, SoftBrutalist.WEIGHT_BOLD, SoftBrutalist.TRACK_NONE)
	value.custom_minimum_size.x = 150.0
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(value)
	_formation_name_label = value

	row.add_child(SoftBrutalist.label("›", SoftBrutalist.SIZE_HEADING, RETRO_ACCENT,
		SoftBrutalist.WEIGHT_BOLD))


func _build_whiteboard(parent: Control) -> void:
	var inner := _card(parent, Vector2(BOARD_PANEL_WIDTH, 0.0))
	# See _build_header()'s comment — the flag has to land on the wrapper,
	# two levels up from `inner`, for the row to actually stretch it.
	var wrapper := inner.get_parent().get_parent() as Control
	wrapper.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# The board draws its own inset (FormationWhiteboard.MARGIN), so the
	# card's text padding would double it.
	for side: String in ["left", "right", "top", "bottom"]:
		inner.add_theme_constant_override(StringName("margin_" + side), 0)

	_whiteboard = FormationWhiteboard.new()
	_whiteboard.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(_whiteboard)


func _build_hint(parent: Control) -> void:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.custom_minimum_size.y = HINT_HEIGHT
	parent.add_child(row)

	var hints := KeyHintBar.new()
	hints.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(hints)
	hints.set_hints([
		{"keys": "← / →", "label": "Change formation"},
		{"keys": "T / Esc", "label": "Back to menu"},
	])
