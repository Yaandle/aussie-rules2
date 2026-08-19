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
const DISABLED_BORDER := Color("#808780")

const BORDER_WIDTH := 3
const CORNER_RADIUS := 14

# ── Shadow states ────────────────────────────────────────────────────
const SHADOW_REST_SIZE := 10
const SHADOW_REST_OFFSET := Vector2(4, 4)
const SHADOW_HOVER_SIZE := 16
const SHADOW_HOVER_OFFSET := Vector2(-2, -2)
const SHADOW_PRESSED_SIZE := 2
const SHADOW_PRESSED_OFFSET := Vector2(2, 2)
const PRESSED_DARKEN := 0.06   ## bg brightness reduction on press

# ── Type ─────────────────────────────────────────────────────────────
const WEIGHT_HEAVY := 0.45
const WEIGHT_BOLD := 0.2
const WEIGHT_REGULAR := -0.1
const TRACK_TITLE := 4
const TRACK_LABEL := 1

## Numeric HUD readouts only (design brief) — everything else uses the
## rounded/grotesk FontVariation from `font()`.
static var monospace_font: Font = ThemeDB.fallback_font

# ── Tween timing ─────────────────────────────────────────────────────
const TRANSITION_MIN := 0.12
const TRANSITION_MAX := 0.18
const TRANSITION_TRANS := Tween.TRANS_CUBIC
const TRANSITION_EASE := Tween.EASE_OUT


static var _fonts := {}


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


static func label(text: String, size: int, colour: Color = INK, embolden := WEIGHT_REGULAR,
		tracking := 0) -> Label:
	var node := Label.new()
	node.text = text
	node.add_theme_font_override(&"font", font(embolden, tracking))
	node.add_theme_font_size_override(&"font_size", size)
	node.add_theme_color_override(&"font_color", colour)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node


## Numeric readout label — monospace per the design brief, reserved for
## HUD values (scoreboard clock/score, debug HUD figures) rather than UI
## chrome text.
static func numeric_label(text: String, size: int, colour: Color = INK) -> Label:
	var node := Label.new()
	node.text = text
	node.add_theme_font_override(&"font", monospace_font)
	node.add_theme_font_size_override(&"font_size", size)
	node.add_theme_color_override(&"font_color", colour)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node


## The one panel shape used everywhere: 3px ink border, 14px corners, a
## soft blurred drop shadow — never a hard-edged one. `fill` defaults to
## pure white (the token set's "Panel" colour); pass BACKGROUND or a
## custom tint for the rarer inset/backdrop cases.
static func panel_style(fill: Color = PANEL, shadow_size := SHADOW_REST_SIZE,
		shadow_offset := SHADOW_REST_OFFSET, border_colour := INK) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border_colour
	box.set_border_width_all(BORDER_WIDTH)
	box.set_corner_radius_all(CORNER_RADIUS)
	box.shadow_color = Color(INK.r, INK.g, INK.b, 0.22)
	box.shadow_size = shadow_size
	box.shadow_offset = shadow_offset
	box.anti_aliasing_size = 0.6
	return box


## Button-shaped StyleBox for a given interaction state — same shape as
## panel_style(), different fill/shadow per state. Used by hand-built
## button-like controls (ActionButton, menu rows) so they read as the
## same physical object as a real themed Button.
static func button_style(state: StringName) -> StyleBoxFlat:
	match state:
		&"hover":
			return panel_style(ACCENT_SECONDARY, SHADOW_HOVER_SIZE, SHADOW_HOVER_OFFSET)
		&"pressed":
			var darkened := PANEL.darkened(PRESSED_DARKEN) if PANEL != Color.WHITE \
				else ACCENT_SECONDARY.darkened(PRESSED_DARKEN)
			return panel_style(darkened, SHADOW_PRESSED_SIZE, SHADOW_PRESSED_OFFSET)
		&"disabled":
			return panel_style(DISABLED_BG, 0, Vector2.ZERO, DISABLED_BORDER)
		_:
			return panel_style(PANEL, SHADOW_REST_SIZE, SHADOW_REST_OFFSET)


## Tweens `control`'s StyleBoxFlat "panel" override from its current state
## to `to_state` (one of &"normal"/&"hover"/&"pressed"/&"disabled"),
## ease-out cubic over TRANSITION_MIN-MAX seconds — the one shared state
## transition every interactive Soft Brutalist control should use instead
## of snapping instantly.
static func animate_state(control: Control, panel_name: StringName, to_state: StringName,
		duration := TRANSITION_MAX) -> void:
	var target := button_style(to_state)
	var current: StyleBoxFlat = control.get_theme_stylebox(panel_name)
	if current == null or not (current is StyleBoxFlat):
		control.add_theme_stylebox_override(panel_name, target)
		return
	# StyleBoxFlat properties aren't individually tweenable via a shared
	# box (each control needs its own instance to animate independently),
	# so clone the current box and tween its fields, swapping the eased
	# copy in as the override every step.
	var box: StyleBoxFlat = current.duplicate()
	control.add_theme_stylebox_override(panel_name, box)
	var tween := control.create_tween()
	tween.set_trans(TRANSITION_TRANS)
	tween.set_ease(TRANSITION_EASE)
	tween.set_parallel(true)
	tween.tween_property(box, "bg_color", target.bg_color, duration)
	tween.tween_property(box, "border_color", target.border_color, duration)
	tween.tween_property(box, "shadow_size", target.shadow_size, duration)
	tween.tween_property(box, "shadow_offset", target.shadow_offset, duration)
