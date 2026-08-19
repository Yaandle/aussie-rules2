class_name UIStyle
extends RefCounted

## Palette, type scale and stylebox factory for the front-end screens.
##
## The character screen is eight repeats of one row plus a button and a
## hint bar, so every colour and every font weight it uses is named once
## here rather than spelled out per widget. `main_menu.gd`'s older
## `COLOUR_*` string constants predate this and are deliberately left
## alone — that screen is not part of this pass — but this is where a
## future menu pass should pull from.
##
## Fonts are built as FontVariation over the engine's default face
## (`ThemeDB.fallback_font`, Open Sans SemiBold) rather than shipped as
## an asset. The reference look is not really about the typeface, it is
## about weight and tracking: `variation_embolden` supplies the weight
## axis the base face doesn't have, and `spacing_glyph` supplies the
## letter-spacing. If a licensed display face is ever added, set
## `base_face` below and every screen picks it up.

# ── Palette ──────────────────────────────────────────────────────────
# Pulled from SoftBrutalist (scripts/ui/soft_brutalist.gd) rather than
# sampled locally, so this screen reads as the same design language as
# the rest of scenes/ui/ instead of a one-off dark "studio" look. Names
# are kept as-is (every call site below reads by role, not by hex) so
# only this block had to change when the screen moved off its old dark
# palette; the character_backdrop's own dark navy environment is a
# separate 3D lighting concern and is untouched by this.

const TEXT_PRIMARY := SoftBrutalist.INK       ## Titles, labels, values
const TEXT_MUTED := SoftBrutalist.MUTED       ## Subtitle, "· LOCKED", hint labels
const ICON_LINE := SoftBrutalist.INK
const SEGMENT_FILL := SoftBrutalist.ACCENT_PRIMARY  ## A filled bar square is the green accent
const SEGMENT_EMPTY := SoftBrutalist.MUTED          ## An empty one is this, outline only
const PANEL_FILL := SoftBrutalist.PANEL
const CHIP_BORDER := SoftBrutalist.INK

## Green. The one "this is live/interactive" accent on this screen — the
## play button's border, and the selected row's icon box and marker.
const ACCENT := SoftBrutalist.ACCENT_PRIMARY

## Icon box fill/border — sharp hairline boxes (see `rounded()`), not the
## full boxed-element shape. Light-palette values (the panel white and the
## ink line) rather than the old dark-studio hex, so they still sit on the
## Soft Brutalist palette this screen moved to.
const ICON_BOX_FILL := SoftBrutalist.PANEL
const ICON_BOX_BORDER := SoftBrutalist.INK

# ── Type ─────────────────────────────────────────────────────────────
# Sizes are for the project's 1280x720 design resolution; `canvas_items`
# stretch scales them from there (see project.godot [display]).

const SIZE_TITLE := 36
const SIZE_SUBTITLE := 13
const SIZE_LABEL := 15
const SIZE_VALUE := 15
const SIZE_BUTTON := 16
const SIZE_HINT := 12

## variation_embolden. The base face is already SemiBold, so "regular"
## text has to be thinned rather than the other way round.
const WEIGHT_HEAVY := 0.45
const WEIGHT_BOLD := 0.22
const WEIGHT_REGULAR := -0.28

## spacing_glyph, in px at the sizes above — the tracked-out uppercase
## treatment the reference uses everywhere except the numeric values.
const TRACK_TITLE := 6
const TRACK_SUBTITLE := 2
const TRACK_LABEL := 1
const TRACK_BUTTON := 3
const TRACK_HINT := 1


static var _fonts := {}


## Cached, because eight rows x two fonts each would otherwise build a
## new FontVariation per row per rebuild and none of them differ.
static func font(embolden: float, tracking: int) -> FontVariation:
	var key := Vector2(embolden, float(tracking))
	if _fonts.has(key):
		return _fonts[key]
	var variation := FontVariation.new()
	variation.base_font = ThemeDB.fallback_font
	variation.variation_embolden = embolden
	variation.spacing_glyph = tracking
	_fonts[key] = variation
	return variation


static func label(text: String, size: int, colour: Color, embolden := WEIGHT_REGULAR,
		tracking := 0) -> Label:
	var node := Label.new()
	node.text = text
	node.add_theme_font_override(&"font", font(embolden, tracking))
	node.add_theme_font_size_override(&"font_size", size)
	node.add_theme_color_override(&"font_color", colour)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node


## Rounded rect with a hairline border. Used for the icon boxes, the play
## button, and the key hint chips — small, sharp-edged shapes where a
## hairline reads better than SoftBrutalist's full 3px-ink-border boxed
## shape.
static func rounded(fill: Color, border: Color, border_width := 1, radius := 6) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(border_width)
	box.set_corner_radius_all(radius)
	# Tighter than the 1.0 default: at these radii the default feather
	# eats most of a 1px border and the hairline reads as a smudge.
	box.anti_aliasing_size = 0.4
	return box
