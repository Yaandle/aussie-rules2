class_name UIStyle
extends RefCounted

## Role-named aliases over SoftBrutalist, for the character screen.
##
## The character screen is eight repeats of one row plus a button and a
## hint bar, and every widget in it reads its colour and type by *role*
## ("the value column", "a hint chip") rather than by token. That
## indirection is worth keeping — but it used to carry its own numbers,
## and two independent scales for one app is how a 36px title on one
## screen ends up beside a 40px title on another, with 6px of tracking
## against 4px.
##
## So nothing here is a value any more. Every constant below resolves to
## a SoftBrutalist token (scripts/ui/soft_brutalist.gd), which is the one
## place sizes, weights and colours are chosen; this file only records
## which token each role uses. Changing the app's type scale is a change
## there, and this screen follows.
##
## Fonts are built as FontVariation over the engine's default face
## (`ThemeDB.fallback_font`, Open Sans SemiBold) rather than shipped as
## an asset. The reference look is not really about the typeface, it is
## about weight and tracking: `variation_embolden` supplies the weight
## axis the base face does not have, and `spacing_glyph` supplies the
## letter-spacing. If a licensed display face is ever added, set
## `base_font` in SoftBrutalist.font() and every screen picks it up.

# ── Palette ──────────────────────────────────────────────────────────

const TEXT_PRIMARY := SoftBrutalist.INK       ## Titles, labels, values
const TEXT_MUTED := SoftBrutalist.MUTED       ## Subtitle, "· LOCKED", hint labels
const ICON_LINE := SoftBrutalist.INK
const SEGMENT_FILL := SoftBrutalist.ACCENT_PRIMARY  ## A filled bar square is the green accent
const SEGMENT_EMPTY := SoftBrutalist.LINE_SOFT      ## An empty one is this, outline only
const PANEL_FILL := SoftBrutalist.PANEL
const CHIP_BORDER := SoftBrutalist.LINE

## Green. The one "this is live/interactive" accent on this screen — the
## play button's border, and the selected row's icon box and marker.
const ACCENT := SoftBrutalist.ACCENT_PRIMARY

## Icon box fill/border. The soft LINE edge rather than full-strength
## ink, matching every other bordered element in the app.
const ICON_BOX_FILL := SoftBrutalist.PANEL
const ICON_BOX_BORDER := SoftBrutalist.LINE

# ── Type ─────────────────────────────────────────────────────────────
# Sizes are for the project's 1280x720 design resolution; `canvas_items`
# stretch scales them from there (see project.godot [display]).

const SIZE_TITLE := SoftBrutalist.SIZE_TITLE
const SIZE_SUBTITLE := SoftBrutalist.SIZE_LABEL
const SIZE_LABEL := SoftBrutalist.SIZE_BODY
const SIZE_VALUE := SoftBrutalist.SIZE_BODY
const SIZE_BUTTON := SoftBrutalist.SIZE_BODY
const SIZE_HINT := SoftBrutalist.SIZE_CAPTION

const WEIGHT_HEAVY := SoftBrutalist.WEIGHT_HEAVY
const WEIGHT_BOLD := SoftBrutalist.WEIGHT_BOLD
const WEIGHT_REGULAR := SoftBrutalist.WEIGHT_REGULAR

const TRACK_TITLE := SoftBrutalist.TRACK_TITLE
const TRACK_SUBTITLE := SoftBrutalist.TRACK_LABEL
const TRACK_LABEL := SoftBrutalist.TRACK_LABEL
const TRACK_BUTTON := SoftBrutalist.TRACK_TITLE
const TRACK_HINT := SoftBrutalist.TRACK_LABEL


static func font(embolden: float, tracking: int) -> FontVariation:
	return SoftBrutalist.font(embolden, tracking)


static func label(text: String, size: int, colour: Color, embolden := WEIGHT_REGULAR,
		tracking := 0) -> Label:
	return SoftBrutalist.label(text, size, colour, embolden, tracking)


## Rounded rect with a hairline border. Used for the icon boxes, the play
## button, and the key hint chips — small shapes where a hairline reads
## better than the 2px edge a full-size card carries. Depth, where a
## shape wants any, comes from SoftBrutalist.soften() rather than from a
## StyleBoxFlat shadow.
static func rounded(fill: Color, border: Color, border_width := 1,
		radius := SoftBrutalist.RADIUS_SM) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(border_width)
	box.set_corner_radius_all(radius)
	# Tighter than the 1.0 a full card uses: at a 1px border the default
	# feather eats most of the stroke and the hairline reads as a smudge.
	box.anti_aliasing_size = 0.5
	return box
