class_name SoftBrutalist
extends RefCounted

## Code-side companion to res://themes/soft_brutalist.tres.
##
## Most screens in scenes/ui/ build their Control trees entirely in
## _ready() (see character_screen.gd's header for why) rather than laying
## real Button/Panel nodes out in a .tscn, so a Theme resource alone isn't
## enough to reach them — a Theme only styles the built-in look-ups
## (Button/styles/normal etc.) that real Control subclasses ask for. This
## class is the same palette and the same StyleBoxFlat shapes as the
## .tres, exposed as plain constants and factory functions, so hand-built
## screens and the .tres stay visually identical instead of drifting.
##
## Any screen that *does* use real Button/Panel/LineEdit nodes should
## still just assign THEME_PATH to its root and let the engine do the
## lookup — this class is only for screens with bespoke draw calls or
## hand-built Label/Panel trees that a Theme resource can't reach.

const THEME_PATH := "res://themes/soft_brutalist.tres"

# ── Palette ──────────────────────────────────────────────────────────
const BACKGROUND := Color("#F4F1EA")
const PANEL := Color("#FFFFFF")
const INK := Color("#16261F")
const ACCENT_PRIMARY := Color("#4E9F5B")
const ACCENT_SECONDARY := Color("#B8E986")
const MUTED := Color("#808780")
const DISABLED_BG := Color("#E5E2D9")
const DISABLED_BORDER := Color("#A8ADA4")

## Standard Xbox face-button colours, for the contest prompt over a
## receiver's head (MarkPrompt) — A/X/Y already read as green/blue/yellow to
## anyone who has held a pad, so the prompt borrows that convention rather
## than inventing a new one nobody's ever seen. ACCENT_PRIMARY already is
## this same green; the other two are new, this palette's only members.
const BUTTON_A := ACCENT_PRIMARY
const BUTTON_X := Color("#2F6FED")
const BUTTON_Y := Color("#F2C230")

## Panel/card edge. Deliberately not INK: a near-black 3px rule around
## every element is the loudest thing in the old chrome, and the brief
## asks for soft edges and lower contrast rather than heavy outlines.
## This is INK carried most of the way toward the background — still an
## unambiguous edge, at roughly half the visual weight, which together
## with the real shadows below is enough to define a card without the
## border having to do it alone.
const LINE := Color("#3E4A44")
## Hairline rule for dividers and small chrome, lighter again.
const LINE_SOFT := Color("#C8C6BD")

## Screen-background ramp endpoints for backdrop(). A few percent apart —
## the point is depth in the paper, not a gradient anyone should notice.
const BACKGROUND_TOP := Color("#F9F7F2")
const BACKGROUND_BOTTOM := Color("#EDEAE1")

const BORDER_WIDTH := 2

# ── Corner radii ─────────────────────────────────────────────────────
## One scale rather than the ad-hoc 6/14 split the screens had, so a chip
## and a hero card read as the same family at different sizes.
const RADIUS_XS := 7     ## key-hint chips
const RADIUS_SM := 10    ## icon boxes, action buttons, list rows
const RADIUS_MD := 16    ## panels and cards
const RADIUS_LG := 22    ## full-bleed hero cards
## Kept for call sites that just want "the card radius".
const CORNER_RADIUS := RADIUS_MD

# ── Spacing ──────────────────────────────────────────────────────────
## An 8px base step at the 1280x720 design resolution. Screens lay out on
## multiples of this so gaps across unrelated screens agree instead of
## each being hand-picked.
const SPACE_1 := 8.0
const SPACE_2 := 16.0
const SPACE_3 := 24.0
const SPACE_4 := 32.0
const SPACE_5 := 40.0
const SPACE_6 := 56.0
const SPACE_7 := 72.0

# ── Elevation ────────────────────────────────────────────────────────
# Real blurred shadows, drawn by SoftShadow / soft_shadow.gdshader —
# StyleBoxFlat's `shadow_size` cannot blur (see that shader's header), so
# nothing in these tokens goes near it. Each level is two lobes: a wide
# low-opacity `ambient` one for float, a tight `contact` one for anchor.
# Opacities stay under 0.15 on purpose; the depth comes from the blur
# radius, and pushing opacity instead is what makes a card look stuck to
# a grey rectangle.

## Levels are heights, not states: LOW is both "a small element at rest"
## (a 40px icon box under a 26px blur would be swallowed by its own
## shadow) and "a card being pressed", because those are the same
## distance off the page.
enum Elevation { FLAT, LOW, REST, RAISED, OVERLAY }

const ELEVATIONS := {
	Elevation.FLAT: {
		"ambient_blur": 0.0, "ambient_offset": Vector2.ZERO, "ambient_opacity": 0.0,
		"contact_blur": 0.0, "contact_offset": Vector2.ZERO, "contact_opacity": 0.0,
	},
	Elevation.LOW: {
		"ambient_blur": 10.0, "ambient_offset": Vector2(0.0, 3.0), "ambient_opacity": 0.09,
		"contact_blur": 4.0, "contact_offset": Vector2(0.0, 1.0), "contact_opacity": 0.05,
	},
	Elevation.REST: {
		"ambient_blur": 26.0, "ambient_offset": Vector2(0.0, 10.0), "ambient_opacity": 0.12,
		"contact_blur": 7.0, "contact_offset": Vector2(0.0, 2.0), "contact_opacity": 0.06,
	},
	Elevation.RAISED: {
		"ambient_blur": 36.0, "ambient_offset": Vector2(0.0, 18.0), "ambient_opacity": 0.16,
		"contact_blur": 11.0, "contact_offset": Vector2(0.0, 4.0), "contact_opacity": 0.06,
	},
	Elevation.OVERLAY: {
		"ambient_blur": 48.0, "ambient_offset": Vector2(0.0, 24.0), "ambient_opacity": 0.14,
		"contact_blur": 14.0, "contact_offset": Vector2(0.0, 6.0), "contact_opacity": 0.06,
	},
}

# ── Type scale ───────────────────────────────────────────────────────
# One scale for the whole front end. UIStyle's names alias into these
# (see ui_style.gd) so the character screen and the menu cannot drift to
# different sizes for the same job the way they had.

const SIZE_DISPLAY := 40   ## the one screen title
const SIZE_TITLE := 30     ## section / card headings
const SIZE_HEADING := 20
const SIZE_BODY := 15
const SIZE_LABEL := 13
const SIZE_CAPTION := 11

## variation_embolden. The engine's fallback face is already SemiBold, so
## the lighter end of the scale is reached by thinning rather than the
## other way round — the brief's "lightweight, premium" body text is
## WEIGHT_REGULAR, not the base weight.
const WEIGHT_HEAVY := 0.45
const WEIGHT_BOLD := 0.2
const WEIGHT_REGULAR := -0.22
const WEIGHT_LIGHT := -0.38

## spacing_glyph, in px. Tracking scales *down* as size goes up — the
## usual optical correction, and the reason one number could not serve
## both a 40px title and an 11px caption.
const TRACK_DISPLAY := 5
const TRACK_TITLE := 3
const TRACK_LABEL := 1
const TRACK_NONE := 0

# ── Tween timing ─────────────────────────────────────────────────────
const TRANSITION_MIN := 0.12
const TRANSITION_MAX := 0.18
const TRANSITION_TRANS := Tween.TRANS_CUBIC
const TRANSITION_EASE := Tween.EASE_OUT


static var _fonts := {}
static var _numeric_fonts := {}
static var _monospace_font: Font = null


static func font(embolden: float = WEIGHT_REGULAR, tracking: int = 0) -> FontVariation:
	var key := Vector2(embolden, float(tracking))
	if _fonts.has(key):
		return _fonts[key]
	var variation := FontVariation.new()
	variation.base_font = ThemeDB.fallback_font
	variation.variation_embolden = embolden
	variation.spacing_glyph = tracking
	_fonts[key] = variation
	return variation


## Face for numeric readouts. The project ships no monospace asset, so
## this asks the fallback face for tabular figures instead — "tnum" makes
## every digit advance the same width, which is the only property a clock
## or a scoreline actually needs from a monospace font. Without it the
## scoreboard clock shuffles its neighbours every second as the digit
## widths change. A face with no tnum table simply ignores the feature,
## so this is safe on whatever ThemeDB hands back.
static func numeric_font(embolden: float = WEIGHT_BOLD) -> FontVariation:
	if _numeric_fonts.has(embolden):
		return _numeric_fonts[embolden]
	var variation := FontVariation.new()
	variation.base_font = ThemeDB.fallback_font
	variation.variation_embolden = embolden
	variation.opentype_features = {"tnum": 1, "lnum": 1}
	_numeric_fonts[embolden] = variation
	return variation


## True fixed-pitch face, for the one place that needs character cells
## rather than just even digits: the debug HUD, which draws ASCII bars and
## printf-padded columns that only line up in a monospace. Asked of the
## OS by generic family name (Consolas/DejaVu Sans Mono/Menlo depending on
## the platform) rather than shipped as an asset — the project has no font
## pipeline, and a diagnostic overlay is not worth starting one. If the
## platform hands back nothing, Godot falls through to its own fallback,
## which is what this used to be unconditionally.
static func monospace_font() -> Font:
	if _monospace_font != null:
		return _monospace_font
	var system := SystemFont.new()
	system.font_names = PackedStringArray(["monospace"])
	_monospace_font = system
	return _monospace_font


static func label(text: String, size: int, colour: Color = INK, embolden := WEIGHT_REGULAR,
		tracking := 0) -> Label:
	var node := Label.new()
	node.text = text
	node.add_theme_font_override(&"font", font(embolden, tracking))
	node.add_theme_font_size_override(&"font_size", size)
	node.add_theme_color_override(&"font_color", colour)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node


## Numeric readout label — tabular figures per numeric_font(), reserved
## for HUD values (scoreboard clock/score, debug HUD figures) rather than
## UI chrome text.
static func numeric_label(text: String, size: int, colour: Color = INK) -> Label:
	var node := Label.new()
	node.text = text
	node.add_theme_font_override(&"font", numeric_font())
	node.add_theme_font_size_override(&"font_size", size)
	node.add_theme_color_override(&"font_color", colour)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node


## The one panel shape used everywhere: a soft LINE border, rounded
## corners, flat fill. It carries no shadow of its own — depth comes from
## soften() below, which is a real blur rather than the hard offset slab
## StyleBoxFlat draws.
static func panel_style(fill: Color = PANEL, radius: int = RADIUS_MD,
		border_colour: Color = LINE) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border_colour
	box.set_border_width_all(BORDER_WIDTH)
	box.set_corner_radius_all(radius)
	# Just over a pixel of feather. StyleBoxFlat's corners are geometry,
	# not an SDF, so below ~1.0 the rounded arcs step visibly at the 16px
	# radius this scale uses.
	box.anti_aliasing_size = 1.0
	return box


## Attaches (or re-configures) the blurred shadow layer under `target`.
## Safe to call twice on the same control — the second call re-uses the
## existing layer rather than stacking a second one.
##
## `target` must not be a Container. The shadow is a child that anchors
## itself *outside* its parent rect so the blur has room to fade, and a
## Container sorts every Control child back inside its own content box
## every layout pass, which would clip the blur to the card edge and put
## the harsh cut-off look straight back. Use Panel over PanelContainer
## for anything that needs depth (see action_button.gd).
static func soften(target: Control, level: Elevation = Elevation.REST,
		radius: float = float(RADIUS_MD), colour: Color = INK) -> SoftShadow:
	if target is Container:
		push_warning("SoftBrutalist.soften(): %s is a Container; its layout pass will clip the shadow."
			% target.get_class())
	var shadow: SoftShadow = null
	for child in target.get_children():
		if child is SoftShadow:
			shadow = child
			break
	if shadow == null:
		shadow = SoftShadow.new()
		target.add_child(shadow)
		target.move_child(shadow, 0)
	shadow.configure(ELEVATIONS[level], radius, colour)
	return shadow


## Moves an already-attached shadow to another elevation, easing the blur
## and offset rather than cutting between them — a card that grows its
## shadow instantly reads as a texture swap, not as lifting.
static func set_elevation(shadow: SoftShadow, level: Elevation, animate := true,
		duration := TRANSITION_MAX) -> void:
	if shadow == null or not is_instance_valid(shadow):
		return
	var tokens: Dictionary = ELEVATIONS[level]
	# Pad for the target state first, so a widening blur has somewhere to
	# go before it starts growing rather than being clipped mid-tween.
	shadow.reserve_for(tokens)
	var shader_material := shadow.shader_material()
	if not animate:
		for key: String in tokens:
			shader_material.set_shader_parameter(StringName(key), tokens[key])
		return
	var tween := shadow.create_tween()
	tween.set_trans(TRANSITION_TRANS)
	tween.set_ease(TRANSITION_EASE)
	tween.set_parallel(true)
	for key: String in tokens:
		tween.tween_property(shader_material, "shader_parameter/%s" % key, tokens[key], duration)


## Full-screen background wash (soft_backdrop.gdshader) — the front-end
## screens' replacement for a flat BACKGROUND ColorRect. `alpha` below 1
## is for screens layered over a live 3D backdrop, where this doubles as
## the legibility wash.
static func backdrop(alpha := 1.0) -> ColorRect:
	var node := ColorRect.new()
	node.set_anchors_preset(Control.PRESET_FULL_RECT)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.color = Color.WHITE
	var shader_material := ShaderMaterial.new()
	shader_material.shader = load("res://assets/shaders/soft_backdrop.gdshader")
	shader_material.set_shader_parameter(&"top_colour", BACKGROUND_TOP)
	shader_material.set_shader_parameter(&"bottom_colour", BACKGROUND_BOTTOM)
	shader_material.set_shader_parameter(&"alpha", alpha)
	node.material = shader_material
	return node


## Button-shaped StyleBox for a given interaction state — same shape as
## panel_style(), different fill per state. Used by hand-built
## button-like controls (ActionButton, menu rows) so they read as the
## same physical object as a real themed Button. Depth is soften()'s job,
## so only the fill and the border change here.
static func button_style(state: StringName, radius: int = RADIUS_SM) -> StyleBoxFlat:
	match state:
		&"hover":
			return panel_style(ACCENT_SECONDARY, radius, ACCENT_PRIMARY)
		&"pressed":
			return panel_style(ACCENT_SECONDARY.darkened(0.06), radius, ACCENT_PRIMARY)
		&"disabled":
			return panel_style(DISABLED_BG, radius, DISABLED_BORDER)
		_:
			return panel_style(PANEL, radius, LINE)


## Eases `control`'s "panel" StyleBoxFlat between button states, and its
## attached shadow with it — the one shared state transition every
## interactive Soft Brutalist control should use instead of snapping.
static func animate_state(control: Control, panel_name: StringName, to_state: StringName,
		duration := TRANSITION_MAX, radius: int = RADIUS_SM) -> void:
	var target := button_style(to_state, radius)
	var current: StyleBoxFlat = control.get_theme_stylebox(panel_name)
	if current == null or not (current is StyleBoxFlat):
		control.add_theme_stylebox_override(panel_name, target)
	else:
		# StyleBoxFlat properties are not individually tweenable via a
		# shared box (each control needs its own instance to animate
		# independently), so clone the current box and tween its fields,
		# swapping the eased copy in as the override every step.
		var box: StyleBoxFlat = current.duplicate()
		control.add_theme_stylebox_override(panel_name, box)
		var tween := control.create_tween()
		tween.set_trans(TRANSITION_TRANS)
		tween.set_ease(TRANSITION_EASE)
		tween.set_parallel(true)
		tween.tween_property(box, "bg_color", target.bg_color, duration)
		tween.tween_property(box, "border_color", target.border_color, duration)

	for child in control.get_children():
		if child is SoftShadow:
			set_elevation(child, _state_elevation(to_state), true, duration)
			break


static func _state_elevation(state: StringName) -> Elevation:
	match state:
		&"hover":
			return Elevation.RAISED
		&"pressed":
			return Elevation.LOW
		&"disabled":
			return Elevation.FLAT
		_:
			return Elevation.REST
