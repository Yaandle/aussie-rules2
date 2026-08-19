class_name FormationWhiteboard
extends Control

## Top-down whiteboard preview of a team's starting layout: a schematic
## oval outline plus one dot per player, drawn from TeamFormation.SLOTS
## (all 18, back line first).
##
## Drawn vertically — attack direction points toward the top of the panel
## — with world.x (the length/attack axis) mapped to screen Y (inverted)
## and world.z (width) mapped to screen X, so the oval reads as a real
## portrait-oriented AFL ground rather than the landscape 3D-world layout.
##
## Read-only/no drag-select (see the Team Edit brief) — this only ever
## visualises what TeamFormation's data says.
##
## Drawn with plain Control._draw() calls rather than a 3D scene reused
## from Field — Field's geometry generator builds real meshes sized in
## metres for a 3D camera; this only ever needs 2D lines on a flat panel,
## and reusing Field here would mean instancing a 3D subscene just to
## throw away its third dimension.
##
## Palette lives on the Soft Brutalist system (see soft_brutalist.gd)
## rather than owning its own retro tones the way this screen used to —
## ink line art over a cream pitch fill, with a green-family gradient
## (accent primary/secondary at the ends) distinguishing the six position
## lines: a simple, slightly blocky "indie pixel screen" read rather than
## a photoreal field.

const MARGIN := 28.0
const DOT_RADIUS := 9.0
const ELLIPSE_SEGMENTS := 72
const LABEL_FONT_SIZE := 11
const DOT_BORDER_WIDTH := 2.0
const ARC_SEGMENTS := 32

## Schematic goal/behind post sizing — small tick marks poking just
## outside the oval boundary at each goal line, not literal 3D posts.
const GOAL_POST_LENGTH := 10.0
const GOAL_POST_WIDTH := 3.0
const BEHIND_POST_LENGTH := 7.0
const BEHIND_POST_WIDTH := 2.0

const PITCH_FILL := SoftBrutalist.BACKGROUND
const LINE_ART_COLOUR := SoftBrutalist.INK
const LABEL_COLOUR := SoftBrutalist.INK
const DOT_BORDER := SoftBrutalist.INK

## One tint per TeamFormation.Line, back-to-forward, blended between the
## Soft Brutalist accent green's darker and lighter ends so the legend
## still reads as a gradient rather than an arbitrary rainbow.
const LINE_COLOURS := {
	TeamFormation.Line.BACK: Color("#2E5E37"),
	TeamFormation.Line.HALF_BACK: Color("#3D7A47"),
	TeamFormation.Line.CENTRE: Color("#4E9F5B"),
	TeamFormation.Line.HALF_FORWARD: Color("#7CC46B"),
	TeamFormation.Line.FORWARD: Color("#B8E986"),
	TeamFormation.Line.FOLLOWERS: Color("#8FCB6E"),
}

var _font: Font = ThemeDB.fallback_font


func _draw() -> void:
	var half_length := Tuning.FIELD_HALF_LENGTH
	var half_width := Tuning.FIELD_HALF_WIDTH
	var available := size - Vector2(MARGIN, MARGIN) * 2.0
	if available.x <= 0.0 or available.y <= 0.0:
		return

	# Portrait orientation: available height fits the field's length
	# (attack axis), available width fits the field's width.
	var aspect := half_width / half_length
	var w := available.x
	var h := available.y
	if w / h > aspect:
		w = h * aspect
	else:
		h = w / aspect
	var centre := size * 0.5
	var scale := (h * 0.5) / half_length   # uniform: (w*0.5)/half_width is the same value

	_draw_oval(centre, half_width * scale, half_length * scale)
	_draw_centre_markings(centre, scale)
	_draw_scoring_arcs(centre, scale)
	_draw_goal_squares(centre, scale)
	_draw_goal_posts(centre, scale)
	_draw_formation(centre, scale)

	_draw_label(centre + Vector2(4.0, -h * 0.5 - 18.0), "ATTACK ↑", true)


## Maps a world-space position (X = depth/attack axis, Z = lateral) to a
## screen point: world.x -> screen Y (inverted, +depth toward the top),
## world.z -> screen X.
func _to_screen(centre: Vector2, world: Vector3, scale: float) -> Vector2:
	return centre + Vector2(world.z * scale, -world.x * scale)


func _draw_formation(centre: Vector2, scale: float) -> void:
	for slot: Dictionary in TeamFormation.SLOTS:
		var world := TeamFormation.world_position(slot, 1.0)
		var point := _to_screen(centre, world, scale)
		var colour: Color = LINE_COLOURS[slot["line"]]
		_draw_dot(point, colour)
		_draw_label(point, String(slot["label"]))


func _draw_dot(point: Vector2, colour: Color) -> void:
	draw_circle(point, DOT_RADIUS, colour)
	draw_arc(point, DOT_RADIUS, 0.0, TAU, 24, DOT_BORDER, DOT_BORDER_WIDTH, true)


func _draw_oval(centre: Vector2, radius_x: float, radius_z: float) -> void:
	var points := PackedVector2Array()
	for i in ELLIPSE_SEGMENTS + 1:
		var t := TAU * float(i) / float(ELLIPSE_SEGMENTS)
		points.append(centre + Vector2(cos(t) * radius_x, sin(t) * radius_z))
	draw_colored_polygon(points, PITCH_FILL)
	draw_polyline(points, LINE_ART_COLOUR, 2.0, true)


func _draw_centre_markings(centre: Vector2, scale: float) -> void:
	var square_half := Tuning.CENTRE_SQUARE_SIZE * 0.5 * scale
	draw_rect(Rect2(centre - Vector2.ONE * square_half, Vector2.ONE * square_half * 2.0),
		LINE_ART_COLOUR, false, 1.0)
	draw_arc(centre, Tuning.CENTRE_CIRCLE_OUTER * scale, 0.0, TAU, 32, LINE_ART_COLOUR, 1.0, true)


## The 50m arcs, one per end, centred on each goal-line midpoint and
## drawn as a half-circle bulging back toward the centre of the ground —
## the portion of the real AFL arc that actually falls inside the field.
func _draw_scoring_arcs(centre: Vector2, scale: float) -> void:
	var radius := Tuning.SCORING_ARC_RADIUS * scale
	var attack_goal := _to_screen(centre, Vector3(Tuning.FIELD_HALF_LENGTH, 0.0, 0.0), scale)
	var defence_goal := _to_screen(centre, Vector3(-Tuning.FIELD_HALF_LENGTH, 0.0, 0.0), scale)
	# Screen angles: 0 = +X (right), increasing clockwise (since +Y is down).
	# Facing the centre from the attacking (top) goal means the arc spans
	# the bottom half of that circle (angles 0..PI, i.e. right-down-left).
	draw_arc(attack_goal, radius, 0.0, PI, ARC_SEGMENTS, LINE_ART_COLOUR, 1.0, true)
	# Facing the centre from the defensive (bottom) goal means the arc
	# spans the top half of that circle (angles PI..TAU).
	draw_arc(defence_goal, radius, PI, TAU, ARC_SEGMENTS, LINE_ART_COLOUR, 1.0, true)


## A goal square at each end: GOAL_SQUARE_DEPTH deep (running from the
## goal line inward) and GOAL_POST_SEPARATION wide, centred laterally.
func _draw_goal_squares(centre: Vector2, scale: float) -> void:
	var half_post := Tuning.GOAL_POST_SEPARATION * 0.5
	var depth := Tuning.GOAL_SQUARE_DEPTH
	for sign_dir: float in [1.0, -1.0]:
		var goal_line_x := sign_dir * Tuning.FIELD_HALF_LENGTH
		var inward_x := goal_line_x - sign_dir * depth
		var a := _to_screen(centre, Vector3(goal_line_x, 0.0, -half_post), scale)
		var b := _to_screen(centre, Vector3(inward_x, 0.0, half_post), scale)
		var rect := Rect2(a, b - a).abs()
		draw_rect(rect, LINE_ART_COLOUR, false, 1.0)


## 4 goal posts (inner pair, taller/thicker) and 2 behind posts per side
## (outer pair) at each end's goal line — short schematic tick marks
## poking just outside the oval boundary.
func _draw_goal_posts(centre: Vector2, scale: float) -> void:
	var goal_half := Tuning.GOAL_POST_SEPARATION * 0.5
	var behind_offset := goal_half + Tuning.BEHIND_POST_OFFSET
	for sign_dir: float in [1.0, -1.0]:
		var goal_line_x := sign_dir * Tuning.FIELD_HALF_LENGTH
		_draw_post(centre, scale, goal_line_x, -goal_half, GOAL_POST_LENGTH, GOAL_POST_WIDTH)
		_draw_post(centre, scale, goal_line_x, goal_half, GOAL_POST_LENGTH, GOAL_POST_WIDTH)
		_draw_post(centre, scale, goal_line_x, -behind_offset, BEHIND_POST_LENGTH, BEHIND_POST_WIDTH)
		_draw_post(centre, scale, goal_line_x, behind_offset, BEHIND_POST_LENGTH, BEHIND_POST_WIDTH)


## Draws one post as a small filled rectangle straddling the goal line,
## poking outward (away from the ground centre) by `length` screen pixels.
func _draw_post(centre: Vector2, scale: float, world_x: float, world_z: float,
		length: float, width: float) -> void:
	var base := _to_screen(centre, Vector3(world_x, 0.0, world_z), scale)
	# Screen Y runs opposite world X (attack is toward the top), so poking
	# outward (past the goal line, away from ground centre) means moving
	# to a smaller screen Y at the attack end and a larger one at the
	# defence end — the negated sign of world_x.
	var outward := -signf(world_x)
	var top_left := base + Vector2(-width * 0.5, 0.0)
	var rect_size := Vector2(width, outward * length)
	draw_rect(Rect2(top_left, rect_size).abs(), LINE_ART_COLOUR, true)


func _draw_label(point: Vector2, text: String, muted := false) -> void:
	var colour := LINE_ART_COLOUR if muted else LABEL_COLOUR
	var text_size := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1.0, LABEL_FONT_SIZE)
	var offset := Vector2(-text_size.x * 0.5, DOT_RADIUS + text_size.y + 1.0) if not muted \
		else Vector2(-text_size.x * 0.5, text_size.y * 0.5)
	draw_string(_font, point + offset, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0,
		LABEL_FONT_SIZE, colour)
