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
## Read-only/no drag-select — this only ever visualises what TeamFormation's
## data says, plus (Team Edit expansion, polish-pass brief) an optional
## `selected_indices` set the owning screen can drive to ring a chosen few
## dots, so a formation *preset* picker (cycling between a few curated
## whole-team choices) has somewhere to show its selection without this
## control growing click-to-assign editing of its own.
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

## Inset from the panel edge. Has to clear the goal-post ticks (which
## poke GOAL_POST_LENGTH past the boundary at each end) *and* the ATTACK
## caption above them, or the caption prints over the posts — which is
## what a 28px inset did.
const MARGIN := 44.0
const DOT_RADIUS := 9.0
const ELLIPSE_SEGMENTS := 96
const LABEL_FONT_SIZE := 11
const DOT_BORDER_WIDTH := 1.5
const ARC_SEGMENTS := 48
const CAPTION_OFFSET := 26.0

## Line weights. The boundary is the only structural line on the board;
## everything inside it is reference marking and is drawn lighter, so the
## oval reads first and the 50m arcs and centre square sit behind it
## rather than all competing at one weight.
const BOUNDARY_WIDTH := 2.0
const MARKING_WIDTH := 1.25

## Schematic goal/behind post sizing — small tick marks poking just
## outside the oval boundary at each goal line, not literal 3D posts.
const GOAL_POST_LENGTH := 10.0
const GOAL_POST_WIDTH := 3.0
const BEHIND_POST_LENGTH := 7.0
const BEHIND_POST_WIDTH := 2.0

## A hint of green rather than the cream the rest of the page uses — the
## board sits on a white card, and at this size an untinted fill reads as
## another panel rather than as a ground.
const PITCH_FILL := Color("#EFF3EC")
const LINE_ART_COLOUR := SoftBrutalist.LINE
const MARKING_COLOUR := Color("#AFB8B0")
const LABEL_COLOUR := SoftBrutalist.INK
const CAPTION_COLOUR := SoftBrutalist.MUTED
const DOT_BORDER := SoftBrutalist.PANEL

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

## Indices into TeamFormation.SLOTS to ring in RETRO_ACCENT-style highlight
## (see _draw_dot) — empty (default) draws every dot plain, unchanged from
## before this field existed.
var selected_indices: PackedInt32Array = PackedInt32Array():
	set(value):
		selected_indices = value
		queue_redraw()

const SELECTED_RING_COLOUR := Color("#C2542F")   ## TeamListScreen's own RETRO_ACCENT
const SELECTED_RING_WIDTH := 2.5
const SELECTED_RING_PAD := 3.0                   ## clear of the dot's own border


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

	_draw_label(centre + Vector2(0.0, -h * 0.5 - CAPTION_OFFSET), "ATTACK ↑", true)


## Maps a world-space position (X = depth/attack axis, Z = lateral) to a
## screen point: world.x -> screen Y (inverted, +depth toward the top),
## world.z -> screen X.
func _to_screen(centre: Vector2, world: Vector3, scale: float) -> Vector2:
	return centre + Vector2(world.z * scale, -world.x * scale)


func _draw_formation(centre: Vector2, scale: float) -> void:
	for i in TeamFormation.SLOTS.size():
		var slot: Dictionary = TeamFormation.SLOTS[i]
		var world := TeamFormation.world_position(slot, 1.0)
		var point := _to_screen(centre, world, scale)
		var colour: Color = LINE_COLOURS[slot["line"]]
		_draw_dot(point, colour)
		if selected_indices.has(i):
			draw_arc(point, DOT_RADIUS + SELECTED_RING_PAD, 0.0, TAU, 24,
				SELECTED_RING_COLOUR, SELECTED_RING_WIDTH, true)
		_draw_label(point, String(slot["label"]))


## White ring, not an ink one: 18 dark-outlined dots over pale line art
## is 18 of the highest-contrast objects on the screen. A light ring
## still separates a dot from the markings underneath it while letting
## the line colour itself carry the position.
func _draw_dot(point: Vector2, colour: Color) -> void:
	draw_circle(point, DOT_RADIUS, colour, true, -1.0, true)
	draw_arc(point, DOT_RADIUS, 0.0, TAU, 32, DOT_BORDER, DOT_BORDER_WIDTH, true)


func _draw_oval(centre: Vector2, radius_x: float, radius_z: float) -> void:
	var points := PackedVector2Array()
	for i in ELLIPSE_SEGMENTS + 1:
		var t := TAU * float(i) / float(ELLIPSE_SEGMENTS)
		points.append(centre + Vector2(cos(t) * radius_x, sin(t) * radius_z))
	draw_colored_polygon(points, PITCH_FILL)
	draw_polyline(points, LINE_ART_COLOUR, BOUNDARY_WIDTH, true)


func _draw_centre_markings(centre: Vector2, scale: float) -> void:
	var square_half := Tuning.CENTRE_SQUARE_SIZE * 0.5 * scale
	_draw_box(Rect2(centre - Vector2.ONE * square_half, Vector2.ONE * square_half * 2.0))
	draw_arc(centre, Tuning.CENTRE_CIRCLE_OUTER * scale, 0.0, TAU, ARC_SEGMENTS,
		MARKING_COLOUR, MARKING_WIDTH, true)


## Antialiased rectangle outline. draw_rect()'s unfilled mode has no
## antialiasing, so a 1px marking box came out as stair-stepped grey
## against the pitch fill while every arc beside it was smooth.
func _draw_box(rect: Rect2) -> void:
	draw_polyline(PackedVector2Array([
		rect.position,
		rect.position + Vector2(rect.size.x, 0.0),
		rect.end,
		rect.position + Vector2(0.0, rect.size.y),
		rect.position,
	]), MARKING_COLOUR, MARKING_WIDTH, true)


## The 50m arcs, one per end, centred on each goal-line midpoint and
## drawn as a half-circle bulging back toward the centre of the ground.
##
## Clipped to the boundary, the way Field._arc_inside_oval() clips the
## 3D one: a 50m circle struck from the goal line is wider than the
## ground at that end, so the untrimmed half-circle sweeps outside the
## oval and hangs in the margin either side of each goal square. Ink-dark
## that read as a mistake; at the lighter marking weight it reads as one
## too.
func _draw_scoring_arcs(centre: Vector2, scale: float) -> void:
	var radius := Tuning.SCORING_ARC_RADIUS * scale
	var radius_x := Tuning.FIELD_HALF_WIDTH * scale
	var radius_y := Tuning.FIELD_HALF_LENGTH * scale
	for direction: float in [1.0, -1.0]:
		var goal := _to_screen(centre,
			Vector3(direction * Tuning.FIELD_HALF_LENGTH, 0.0, 0.0), scale)
		# Screen angles: 0 = +X (right), increasing clockwise (+Y is down).
		# From the attacking (top) goal the arc bulges into the bottom half
		# of its circle; from the defensive (bottom) goal, the top half.
		var start := 0.0 if direction > 0.0 else PI
		_draw_clipped_arc(goal, radius, start, centre, radius_x, radius_y)


## Walks the arc and emits it as runs of consecutive points that fall
## inside the oval, breaking the polyline wherever it leaves — a single
## polyline over the filtered points would draw a chord straight across
## the gap.
func _draw_clipped_arc(origin: Vector2, radius: float, start_angle: float,
		centre: Vector2, radius_x: float, radius_y: float) -> void:
	var run := PackedVector2Array()
	for i in ARC_SEGMENTS + 1:
		var t := start_angle + PI * float(i) / float(ARC_SEGMENTS)
		var point := origin + Vector2(cos(t), sin(t)) * radius
		var normalised := (point - centre) / Vector2(radius_x, radius_y)
		if normalised.length_squared() <= 1.0:
			run.append(point)
			continue
		if run.size() >= 2:
			draw_polyline(run, MARKING_COLOUR, MARKING_WIDTH, true)
		run = PackedVector2Array()
	if run.size() >= 2:
		draw_polyline(run, MARKING_COLOUR, MARKING_WIDTH, true)


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
		_draw_box(Rect2(a, b - a).abs())


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
	draw_rect(Rect2(top_left, rect_size).abs(), LINE_ART_COLOUR, true, -1.0, true)


func _draw_label(point: Vector2, text: String, muted := false) -> void:
	var colour := CAPTION_COLOUR if muted else LABEL_COLOUR
	var text_size := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1.0, LABEL_FONT_SIZE)
	var offset := Vector2(-text_size.x * 0.5, DOT_RADIUS + text_size.y + 1.0) if not muted \
		else Vector2(-text_size.x * 0.5, text_size.y * 0.5)
	draw_string(_font, point + offset, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0,
		LABEL_FONT_SIZE, colour)
