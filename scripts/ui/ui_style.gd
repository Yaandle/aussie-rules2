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
# Sampled off the design reference. Nothing here is a gameplay colour;
# the two accents that *are* shared with the world (the guernsey gold in
# main_menu.gd, the line off-white in field.gd) stay defined there.

const TEXT_PRIMARY := Color("#eaedef")   ## Titles, labels, values
const TEXT_MUTED := Color("#7c8a9a")     ## Subtitle, "· LOCKED", hint labels
const ICON_LINE := Color("#c2cfdb")
const ICON_BOX_FILL := Color("#22303f")
const ICON_BOX_BORDER := Color("#3a4a5c")
const SEGMENT_FILL := Color("#ffffff")   ## A filled bar square is pure white
const SEGMENT_EMPTY := Color("#8b98a6")  ## An empty one is this, outline only
const PANEL_FILL := Color("#0f1620")
const CHIP_BORDER := Color("#46586a")

## Cyan/teal. The one "this is live/interactive" accent on this screen —
## the play button's border, and the selected row's icon box and marker.
const ACCENT := Color("#4fd1c5")

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


## Rounded rect with a hairline border — the icon boxes, the play button
## and the key chips are all this shape at different sizes.
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
