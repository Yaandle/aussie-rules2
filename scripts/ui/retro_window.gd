class_name RetroWindow
extends RefCounted

## Shared "windowed retro pixel game console" card shell: a warm parchment
## fill, a thick near-black rule, sharp (unrounded) corners, and a solid
## offset drop shadow with no blur — a stamped, hard-edged look rather than
## SoftBrutalist's soft blurred one. Originally local to team_list_screen.gd
## (see its header for the full rationale); pulled out here so
## settings_screen.gd and pause_screen.gd can use the identical shell
## instead of each drifting their own copy.
##
## Text/label styling still goes through SoftBrutalist.label() — only the
## panel shape changes here, not the type system.

const PANEL := Color("#F3E7CE")     ## warm parchment, not plain white
const BORDER := Color("#1C1A17")    ## near-black, not pure ink — warmer
const SHADOW := Color("#2F5F5A")    ## dusty teal, the one recurring accent
const ACCENT := Color("#C2542F")    ## rust/terracotta — title underline, hint chips
const BORDER_WIDTH := 4
const RADIUS := 0                   ## sharp corners — the whole point of this shell
const SHADOW_OFFSET := Vector2(7.0, 7.0)


## Builds the wrapper + hard-offset shadow + bordered front panel common to
## every retro card, and returns the front Panel itself — callers that lay
## children out with raw `.position` (settings_screen.gd, pause_screen.gd)
## should add directly to this. `shell()` and `card()` below both build on
## top of this.
static func _build(parent: Control, minimum: Vector2) -> Panel:
	var wrapper := Control.new()
	wrapper.custom_minimum_size = minimum
	wrapper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(wrapper)

	# Both anchored full-rect to `wrapper` (not sized off the `minimum`
	# snapshot directly) so a caller that stretches the wrapper afterwards
	# carries the shadow and the front panel along with it.
	var shadow := Panel.new()
	shadow.set_anchors_preset(Control.PRESET_FULL_RECT)
	shadow.offset_left = SHADOW_OFFSET.x
	shadow.offset_right = SHADOW_OFFSET.x
	shadow.offset_top = SHADOW_OFFSET.y
	shadow.offset_bottom = SHADOW_OFFSET.y
	shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shadow_style := StyleBoxFlat.new()
	shadow_style.bg_color = SHADOW
	shadow_style.set_corner_radius_all(RADIUS)
	shadow.add_theme_stylebox_override(&"panel", shadow_style)
	wrapper.add_child(shadow)

	var panel := Panel.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override(&"panel", panel_style())
	wrapper.add_child(panel)
	return panel


## A card is a plain Control wrapper (not a Container, so its children's
## positions don't get re-sorted) exactly `minimum` in size. Inside it: a
## solid SHADOW panel offset by SHADOW_OFFSET first, then the real
## parchment-and-border panel at (0,0) on top — intentionally allowed to
## poke past the wrapper's own claimed rect since Control rendering isn't
## clipped to its reported size. Returns a MarginContainer for
## container-laid-out content (VBoxContainer children etc.) — do NOT add
## children with raw `.position` here, a Container re-sorts them every
## layout pass; use shell() instead for that.
static func card(parent: Control, minimum: Vector2, pad: float = 24.0) -> MarginContainer:
	var panel := _build(parent, minimum)
	var inner := MarginContainer.new()
	inner.set_anchors_preset(Control.PRESET_FULL_RECT)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side: String in ["left", "right", "top", "bottom"]:
		inner.add_theme_constant_override(StringName("margin_" + side), int(pad))
	panel.add_child(inner)
	return inner


## Same shell as card(), but returns the bare front Panel with no
## MarginContainer inside it — for callers that position children by hand
## with raw `.position` offsets (settings_screen.gd, pause_screen.gd),
## where a Container would fight every one of those positions.
static func shell(parent: Control, minimum: Vector2) -> Panel:
	return _build(parent, minimum)


static func panel_style(fill: Color = PANEL, border_colour: Color = BORDER) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border_colour
	style.set_border_width_all(BORDER_WIDTH)
	style.set_corner_radius_all(RADIUS)
	style.anti_aliasing_size = 1.0
	return style


## Sharp-cornered interactive row style — a tinted fill when selected,
## transparent (reads as plain text on the card) otherwise. Used for
## list/menu rows across the retro-shelled screens instead of
## SoftBrutalist's rounded+blurred button_style()/soften().
static func row_style(selected: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	if selected:
		style.bg_color = ACCENT.lightened(0.78)
		style.border_color = BORDER
		style.set_border_width_all(2)
	else:
		style.bg_color = Color(PANEL, 0.0)
	style.set_corner_radius_all(RADIUS)
	return style
