class_name FormationWhiteboard
extends Control

## Top-down whiteboard preview of TeamFormation's 18 slots: a schematic
## oval outline plus one dot per slot, coloured by line, labelled with its
## short role code. Read-only per this pass's scope (see the Team List
## brief) — no drag/select, just a preview of where the data model says a
## full 18-a-side team lines up.
##
## Drawn with plain Control._draw() calls rather than a 3D scene reused
## from Field — Field's geometry generator builds real meshes sized in
## metres for a 3D camera; this only ever needs 2D lines on a flat panel,
## and reusing Field here would mean instancing a 3D subscene just to
## throw away its third dimension.

const MARGIN := 28.0
const DOT_RADIUS := 9.0
const ELLIPSE_SEGMENTS := 72
const LABEL_FONT_SIZE := 11

const LINE_ART_COLOUR := Color("#4a4436")
const LABEL_COLOUR := Color("#2f2b21")
const DOT_BORDER := Color("#2f2b21")

## Muted retro tones, one per TeamFormation.Line — deliberately desaturated
## next to the rest of the game's bright broadcast palette (see
## team_list_screen.gd's header for why this screen owns its own look).
const LINE_COLOURS := {
	TeamFormation.Line.BACK: Color("#a85c4b"),
	TeamFormation.Line.HALF_BACK: Color("#c98a4b"),
	TeamFormation.Line.CENTRE: Color("#b7a03c"),
	TeamFormation.Line.HALF_FORWARD: Color("#5c8a6e"),
	TeamFormation.Line.FORWARD: Color("#4b7a8c"),
	TeamFormation.Line.FOLLOWERS: Color("#7a5c8a"),
}

var _font: Font = ThemeDB.fallback_font


func _draw() -> void:
	var half_length := Tuning.FIELD_HALF_LENGTH
	var half_width := Tuning.FIELD_HALF_WIDTH
	var available := size - Vector2(MARGIN, MARGIN) * 2.0
	if available.x <= 0.0 or available.y <= 0.0:
		return

	var aspect := half_length / half_width
	var w := available.x
	var h := available.y
	if w / h > aspect:
		w = h * aspect
	else:
		h = w / aspect
	var centre := size * 0.5
	var scale := (w * 0.5) / half_length   # uniform: (h*0.5)/half_width is the same value

	_draw_oval(centre, half_length * scale, half_width * scale)
	_draw_centre_markings(centre, scale)

	for slot: Dictionary in TeamFormation.SLOTS:
		var world := TeamFormation.world_position(slot, 1.0)
		var point := centre + Vector2(world.x, world.z) * scale
		var colour: Color = LINE_COLOURS[slot["line"]]
		draw_circle(point, DOT_RADIUS, colour)
		draw_arc(point, DOT_RADIUS, 0.0, TAU, 24, DOT_BORDER, 1.5, true)
		_draw_label(point, String(slot["label"]))

	_draw_label(centre + Vector2(w * 0.5 - 4.0, -h * 0.5 - 10.0), "ATTACK →", true)


func _draw_oval(centre: Vector2, radius_x: float, radius_z: float) -> void:
	var points := PackedVector2Array()
	for i in ELLIPSE_SEGMENTS + 1:
		var t := TAU * float(i) / float(ELLIPSE_SEGMENTS)
		points.append(centre + Vector2(cos(t) * radius_x, sin(t) * radius_z))
	draw_polyline(points, LINE_ART_COLOUR, 2.0, true)


func _draw_centre_markings(centre: Vector2, scale: float) -> void:
	var square_half := Tuning.CENTRE_SQUARE_SIZE * 0.5 * scale
	draw_rect(Rect2(centre - Vector2.ONE * square_half, Vector2.ONE * square_half * 2.0),
		LINE_ART_COLOUR, false, 1.0)
	draw_arc(centre, Tuning.CENTRE_CIRCLE_OUTER * scale, 0.0, TAU, 32, LINE_ART_COLOUR, 1.0, true)


func _draw_label(point: Vector2, text: String, muted := false) -> void:
	var colour := LINE_ART_COLOUR if muted else LABEL_COLOUR
	var text_size := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1.0, LABEL_FONT_SIZE)
	var offset := Vector2(-text_size.x * 0.5, DOT_RADIUS + text_size.y + 1.0) if not muted \
		else Vector2(-text_size.x, text_size.y * 0.5)
	draw_string(_font, point + offset, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0,
		LABEL_FONT_SIZE, colour)
