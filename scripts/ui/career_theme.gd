class_name CareerTheme
extends RefCounted

## Palette for the Career mode screens (Dashboard, trimmed pregame,
## full-time) — a visually distinct family from RetroWindow's parchment
## "windowed retro console" look and SoftBrutalist's cream/green quick-
## play look, since Career reads as its own mode within the game. Same
## "plain constants + factory functions, no Theme resource" shape as
## RetroWindow/SoftBrutalist, for the same reason: these screens are
## built in code from _ready(), not laid out in a .tscn (see
## character_screen.gd's header for why that pattern is used throughout
## this project's hand-built UI).
##
## Spacing/radius reuse SoftBrutalist's own scale rather than duplicating
## it — only the colours actually differ here.

const BACKGROUND := Color("#2A2A2A")
const PANEL := Color("#D4B5A0")
const TEXT := Color("#FEFEFE")
const TEXT_MUTED := Color("#B9ADA3")   ## PANEL, darkened — muted text on BACKGROUND

## Text colour for anything sitting on a PANEL tile — TEXT (near-white) has
## no contrast against PANEL's light tan, so every tan card uses this
## instead. Same value as BACKGROUND, not a coincidence: a dark card on a
## dark page and dark text on a light card are the same ink.
const PANEL_TEXT := BACKGROUND

## Rounds out the three the brief named: a muted forest green for a win/
## "next game ready" accent, a dusty brick red for a loss or (Phase 9) a
## locked state.
const POSITIVE := Color("#5B7A5E")
const NEGATIVE := Color("#A3503F")

const RADIUS := SoftBrutalist.RADIUS_SM


static func panel_style(fill: Color = PANEL, border_colour: Color = Color(0.0, 0.0, 0.0, 0.0),
		border_width: int = 0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.set_corner_radius_all(RADIUS)
	if border_width > 0:
		style.border_color = border_colour
		style.set_border_width_all(border_width)
	return style


static func label(text: String, size: int, colour: Color = TEXT,
		embolden := SoftBrutalist.WEIGHT_REGULAR, tracking := 0) -> Label:
	return SoftBrutalist.label(text, size, colour, embolden, tracking)
