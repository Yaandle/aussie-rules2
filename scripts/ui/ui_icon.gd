@tool
class_name UIIcon
extends Control

## Single-colour line icons, drawn rather than imported.
##
## The project has no icon assets and no art pipeline yet (design doc §9,
## same reason `turf.gdshader` computes the ground analytically and
## `humanoid_rig.gd` builds a figure out of boxes). Eight glyphs at one
## size did not justify starting one: these are stroked from a shape table
## in `_draw()`, so they cost no import step, stay sharp at any UI scale,
## and recolour by setting `line_colour` instead of shipping a second set.
##
## Swap for real assets by replacing this node with a TextureRect — the
## only thing anything outside here uses is `icon_name` and `line_colour`.

## Every shape below is authored on this square, then scaled to `size`.
## Keeping one grid means the glyphs share an optical weight without each
## one needing its own hand-tuned scale factor.
const GRID := 24.0

## op, then that op's arguments, in GRID units:
##   ["poly", x, y, x, y, ...]           open polyline
##   ["loop", x, y, x, y, ...]           closed polyline
##   ["arc", cx, cy, radius, deg0, deg1] stroked arc, 0 deg = +X, CW
##   ["ring", cx, cy, radius]            stroked full circle
##   ["dot", cx, cy, radius]             filled disc
##   ["fill", x, y, x, y, ...]           filled polygon
const SHAPES := {
	# Speedometer: dial arc plus a needle swung to the upper right.
	&"speed": [
		["arc", 12.0, 15.5, 8.0, 195.0, 345.0],
		["poly", 12.0, 15.5, 16.8, 10.2],
		["dot", 12.0, 15.5, 1.1],
	],
	# Two stacked chevrons over a baseline — "up", without reusing the
	# HEIGHT row's arrow.
	&"jump": [
		["poly", 4.5, 11.0, 12.0, 3.5, 19.5, 11.0],
		["poly", 4.5, 18.0, 12.0, 10.5, 19.5, 18.0],
	],
	# Kicking leg: hip, knee, shin swung through, toe pointed.
	&"kick": [
		["poly", 6.5, 3.5, 8.5, 10.5, 15.0, 12.5, 12.5, 19.5],
		["poly", 12.5, 19.5, 19.0, 17.5],
	],
	# Crosshair.
	&"accuracy": [
		["ring", 12.0, 12.0, 6.2],
		["dot", 12.0, 12.0, 1.5],
		["poly", 12.0, 2.2, 12.0, 5.2],
		["poly", 12.0, 18.8, 12.0, 21.8],
		["poly", 2.2, 12.0, 5.2, 12.0],
		["poly", 18.8, 12.0, 21.8, 12.0],
	],
	# Dumbbell, seen side on: bar, inner plates, outer plates. No end caps
	# — at 24px they close up against the outer plates and the whole thing
	# reads as one blob.
	&"strength": [
		["poly", 8.0, 12.0, 16.0, 12.0],
		["poly", 8.0, 7.0, 8.0, 17.0],
		["poly", 16.0, 7.0, 16.0, 17.0],
		["poly", 4.5, 9.5, 4.5, 14.5],
		["poly", 19.5, 9.5, 19.5, 14.5],
	],
	# Double-headed vertical arrow. The measuring rules top and bottom
	# went the same way as the dumbbell's end caps.
	&"height": [
		["poly", 12.0, 3.5, 12.0, 20.5],
		["poly", 7.8, 7.7, 12.0, 3.5, 16.2, 7.7],
		["poly", 7.8, 16.3, 12.0, 20.5, 16.2, 16.3],
	],
	# Balance scale: post on a base, beam, two hanging pans.
	&"weight": [
		["poly", 12.0, 6.5, 12.0, 19.5],
		["poly", 8.0, 20.0, 16.0, 20.0],
		["poly", 3.0, 7.5, 21.0, 7.5],
		["poly", 0.8, 13.5, 3.0, 7.5, 5.2, 13.5],
		["poly", 0.8, 13.5, 5.2, 13.5],
		["poly", 18.8, 13.5, 21.0, 7.5, 23.2, 13.5],
		["poly", 18.8, 13.5, 23.2, 13.5],
	],
	# Football boot, side on, toe to the right.
	&"foot": [
		["loop", 5.5, 4.0, 10.0, 4.0, 10.8, 11.5, 17.0, 14.0, 20.5, 16.5,
			20.5, 19.5, 5.5, 19.5],
		["poly", 12.5, 12.2, 13.6, 9.8],
		["poly", 15.6, 13.2, 16.7, 11.2],
	],
	# Solid play triangle — the one filled glyph, on the action button.
	&"play": [
		["fill", 7.5, 4.0, 19.0, 12.0, 7.5, 20.0],
	],
	# AFL ball, stood on its end: a pointed oval with a seam and four
	# laces across it — main_menu.gd's FULL GAME card badge.
	#
	# Upright and pointed, not the wide flat ellipse this was. Lying on
	# its side with a single horizontal line through the middle, the glyph
	# read as an eye at badge size — the long axis and the seam ran the
	# same way, which is the shape of an iris, not of a football.
	&"football": [
		["loop", 12.0, 2.8, 15.3, 5.4, 17.2, 8.8, 17.6, 12.0, 17.2, 15.2,
			15.3, 18.6, 12.0, 21.2, 8.7, 18.6, 6.8, 15.2, 6.4, 12.0,
			6.8, 8.8, 8.7, 5.4],
		["poly", 12.0, 6.6, 12.0, 17.4],
		["poly", 9.9, 8.8, 14.1, 8.8],
		["poly", 9.7, 11.2, 14.3, 11.2],
		["poly", 9.7, 13.6, 14.3, 13.6],
		["poly", 9.9, 16.0, 14.1, 16.0],
	],
	# Witches-hat training cone — main_menu.gd's SCENARIO card badge.
	&"cone": [
		["loop", 12.0, 3.0, 8.0, 19.0, 16.0, 19.0],
		["poly", 6.0, 20.0, 18.0, 20.0],
		["poly", 9.0, 13.0, 15.0, 13.0],
	],
	# AFL goalposts: two tall goal posts flanked by two shorter behind
	# posts on a baseline — main_menu.gd's GOAL KICKING card badge.
	&"goalpost": [
		["poly", 4.0, 10.0, 4.0, 21.0],
		["poly", 9.0, 3.0, 9.0, 21.0],
		["poly", 15.0, 3.0, 15.0, 21.0],
		["poly", 20.0, 10.0, 20.0, 21.0],
		["poly", 2.0, 21.0, 22.0, 21.0],
	],
	# Simple right-pointing chevron-arrow — the "open this" glyph in the
	# corner of a main_menu.gd card.
	&"arrow_right": [
		["poly", 5.0, 12.0, 19.0, 12.0],
		["poly", 13.5, 6.0, 19.0, 12.0, 13.5, 18.0],
	],
	# Three sliders, not a cogwheel. A cog is a ring plus eight teeth, and
	# at the 18px this is drawn at, teeth land at about two pixels each
	# and mush into a fuzzy circle; sliders keep three clean horizontal
	# strokes at any size.
	&"gear": [
		["poly", 4.0, 6.5, 20.0, 6.5],
		["poly", 4.0, 12.0, 20.0, 12.0],
		["poly", 4.0, 17.5, 20.0, 17.5],
		["dot", 15.0, 6.5, 2.1],
		["dot", 8.5, 12.0, 2.1],
		["dot", 16.5, 17.5, 2.1],
	],
	# Door bracket, open on the side the arrow leaves through.
	&"exit": [
		["poly", 13.5, 4.0, 5.0, 4.0, 5.0, 20.0, 13.5, 20.0],
		["poly", 10.5, 12.0, 20.0, 12.0],
		["poly", 17.0, 8.8, 20.2, 12.0, 17.0, 15.2],
	],
	# Padlock — the "· LOCKED" tag glyph.
	&"lock": [
		["arc", 12.0, 9.0, 4.0, 200.0, 340.0],
		["loop", 6.5, 9.0, 17.5, 9.0, 17.5, 20.0, 6.5, 20.0],
		["dot", 12.0, 14.0, 1.3],
	],
}

const ARC_POINTS := 28

@export var icon_name: StringName = &"speed":
	set(value):
		icon_name = value
		queue_redraw()

@export var line_colour := UIStyle.ICON_LINE:
	set(value):
		line_colour = value
		queue_redraw()

## Stroke weight in GRID units, so it scales with the glyph.
@export var line_width := 1.6:
	set(value):
		line_width = value
		queue_redraw()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var shapes: Array = SHAPES.get(icon_name, [])
	if shapes.is_empty():
		return
	# Uniform scale off the shorter side, centred, so a non-square box
	# doesn't stretch the glyph.
	var scale := minf(size.x, size.y) / GRID
	var origin := (size - Vector2(GRID, GRID) * scale) * 0.5
	var width := maxf(line_width * scale, 1.0)
	for shape: Array in shapes:
		_draw_shape(shape, origin, scale, width)


func _draw_shape(shape: Array, origin: Vector2, scale: float, width: float) -> void:
	match shape[0]:
		"poly", "loop", "fill":
			var points := PackedVector2Array()
			for i in range(1, shape.size(), 2):
				points.append(origin + Vector2(shape[i], shape[i + 1]) * scale)
			if shape[0] == "fill":
				draw_colored_polygon(points, line_colour)
			else:
				if shape[0] == "loop":
					points.append(points[0])
				draw_polyline(points, line_colour, width, true)
		"arc":
			draw_arc(origin + Vector2(shape[1], shape[2]) * scale, shape[3] * scale,
				deg_to_rad(shape[4]), deg_to_rad(shape[5]), ARC_POINTS,
				line_colour, width, true)
		"ring":
			draw_arc(origin + Vector2(shape[1], shape[2]) * scale, shape[3] * scale,
				0.0, TAU, ARC_POINTS * 2, line_colour, width, true)
		"dot":
			draw_circle(origin + Vector2(shape[1], shape[2]) * scale, shape[3] * scale,
				line_colour)
