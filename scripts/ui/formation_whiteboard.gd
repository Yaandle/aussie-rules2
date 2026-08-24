class_name FormationWhiteboard
extends Control

## Top-down tactics board: a schematic oval plus one marker per HOME
## player — all 18 AFL slots from TeamFormation.SLOTS, always drawn, each
## displaced by the three Team Edit tactics dials. A full position chart
## that also breathes with the tactics dials, rather than either extreme
## on its own: the previous design only drew whichever 4 slots a formation
## preset actually fielded (a FIFA/NBA 2K-style coaching board), and before
## that the retired design drew all 18 but static (see HANDOVER.md) — this
## keeps the animation, not the fielded-subset filtering.
##
## Drawn vertically — attack direction points toward the top of the panel
## — with world.x (the length/attack axis) mapped to screen Y (inverted)
## and world.z (width) mapped to screen X, so the oval reads as a real
## portrait-oriented AFL ground rather than the landscape 3D-world layout.
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
##
## ── Public surface (driven by TeamListScreen) ──────────────────────────
## `formation_index`/`ball_movement`/`defensive_pressure` mirror Settings'
## own three tactics dials; setting any of them retargets the board (see
## _retarget()/_retarget_engagement()) and animates there via Tween rather
## than snapping. `show_opposition` toggles a static, unanimated mirrored
## 18-marker "generic balanced" reference side — no tactics logic of its
## own, just a shape to gauge your own spacing against.

## Widened from 44 — with all 18 slots always drawn (not just 4), the
## forward-pocket/back-pocket markers sit near the oval's own poles where
## the boundary curves sharply, and their DOT_RADIUS + caption pushed past
## the panel edge at the old margin. More margin shrinks the whole board
## uniformly (see _draw()'s available-size calc), pulling every marker and
## the "ATTACK ↑" caption safely inside the card instead of clipping it.
const MARGIN := 64.0
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

# ── Tactics inputs ───────────────────────────────────────────────────

var formation_index := 0:
	set(value):
		formation_index = value
		_retarget()

var ball_movement: Settings.BallMovementPreference = Settings.BallMovementPreference.MUTUAL:
	set(value):
		ball_movement = value
		_retarget()

var defensive_pressure: Settings.DefensivePressure = Settings.DefensivePressure.BALANCED:
	set(value):
		defensive_pressure = value
		_retarget_engagement()
		queue_redraw()

## Static mirrored 18-marker reference side — see header comment. Doesn't
## animate (nothing about it ever moves), so this can queue_redraw() flat.
var show_opposition := false:
	set(value):
		show_opposition = value
		queue_redraw()

# ── Depth (Matchday Formation) / width (Ball Movement) offset tables ───
# Small [preset]x[line] lookup tables (design brief), not per-player: any
# new position later only ever needs a Line to fall under, never its own
# tuning entry.
#
# DEPTH: a whole-team "push" toward one end (positive = toward the
# attacking end, TeamFormation's own +depth convention), split across
# lines by weight rather than every line moving the same amount — a real
# attacking/defensive mentality surges the front line hardest and only
# edges the back line up/back, it doesn't march the whole XI forward in
# lockstep (which is what a flat per-line shift would look like, and
# exactly what "apply as a per-line multiplier" in the brief is guarding
# against). FOLLOWERS (ruck/rovers) barely move — they live at the
# centre-square hinge regardless of mentality.
const FORMATION_DEPTH_PUSH := {
	0: 0.0,    # BALANCED — Settings.FORMATION_PRESETS index order
	1: 0.16,   # ATTACKING
	2: -0.16,  # DEFENSIVE
}

const LINE_DEPTH_WEIGHT := {
	TeamFormation.Line.BACK: 0.30,
	TeamFormation.Line.HALF_BACK: 0.80,
	TeamFormation.Line.CENTRE: 0.20,
	TeamFormation.Line.HALF_FORWARD: 0.80,
	TeamFormation.Line.FORWARD: 1.0,
	TeamFormation.Line.FOLLOWERS: 0.12,
}

## WIDTH: a multiplicative scale on each slot's own `lateral` fraction —
## naturally proportional to how far off-centre a slot already sits (a
## slot sitting dead on the centre line, lateral 0.0, stays at 0.0 under
## any scale), so a single per-line weight is enough; no separate "how far
## from centre" term needed the way depth's additive push needed one.
##
## Table shifted from its original {-0.35, 0.0, 0.35}: the old MUTUAL
## (default, scale 1.0) put FORWARD/BACK-line pockets (depth 0.80, lateral
## 0.55) right at the oval boundary (normalized radius 0.9425 of 1.0) with
## zero room to spare, and old BOUNDARY (scale 1.35) pushed them past it
## (1.091) — genuinely outside the white oval, not just close to it.
## MUTUAL moved to -0.35 (the old CORRIDOR view) so the default sits
## comfortably inside (0.876), and BOUNDARY moved to 0.0 (the old MUTUAL
## scale, 0.9425 — inside) so even the widest setting never crosses the
## boundary. CORRIDOR itself only moved a little further in from the new
## MUTUAL (-0.50, a -0.15 step) rather than mirroring BOUNDARY's full
## +0.35 step — the initial equal-and-opposite shift squeezed CORRIDOR
## too tight relative to how far BOUNDARY had to move to clear the oval.
const WIDTH_PUSH := {
	Settings.BallMovementPreference.CORRIDOR: -0.50,
	Settings.BallMovementPreference.MUTUAL: -0.35,
	Settings.BallMovementPreference.BOUNDARY: 0.0,
}

const LINE_WIDTH_WEIGHT := {
	TeamFormation.Line.BACK: 1.0,
	TeamFormation.Line.HALF_BACK: 1.0,
	TeamFormation.Line.CENTRE: 1.0,
	TeamFormation.Line.HALF_FORWARD: 1.0,
	TeamFormation.Line.FORWARD: 1.0,
	TeamFormation.Line.FOLLOWERS: 0.4,   ## already hug the centre; move less
}

## Clamp headroom so an aggressive push/scale can never place a marker on
## or past the boundary line itself.
const OFFSET_CLAMP := 0.95

## Pocket nudge: pulls the four pocket slots (FP/FP, BP/BP) a little
## closer to their line's centre marker (FF, FB) than TeamFormation.SLOTS'
## raw depth/lateral give them. Without this the pocket pair sits at
## exactly the same depth as the full-forward/full-back marker beside it,
## so the forward and back lines each draw as a flat edge and the whole
## fielded 6 reads as a rectangle rather than a fanned-out line. Applied
## on top of TeamFormation.SLOTS rather than by editing SLOTS itself —
## SLOTS also drives FullGame's real kickoff spawn positions, and this is
## a board-legibility tweak, not a formation redesign.
const POCKET_ROLES := [
	TeamFormation.Role.FORWARD_POCKET_LEFT, TeamFormation.Role.FORWARD_POCKET_RIGHT,
	TeamFormation.Role.BACK_POCKET_LEFT, TeamFormation.Role.BACK_POCKET_RIGHT,
]
const POCKET_DEPTH_INSET := 0.08     ## pulls FP/BP in, depth-wise, toward FF/FB
const POCKET_LATERAL_SCALE := 0.82   ## pulls FP/BP in, laterally, toward FF/FB

# ── Pressure (Defensive Pressure) — an engagement line, not a player move
# Per the design brief, pressure never touches a player marker's own
# position; it only moves this dashed line and (with the opposition
# overlay on) restyles the marking-distance connector lines below.
const PRESSURE_ENGAGEMENT_DEPTH := {
	Settings.DefensivePressure.LOOSE: -0.55,     ## deep, near defensive 50
	Settings.DefensivePressure.BALANCED: 0.0,    ## ground midpoint
	Settings.DefensivePressure.TIGHT: 0.45,      ## pushed up, high engagement
}
const ENGAGEMENT_LINE_COLOUR := SoftBrutalist.ACCENT_PRIMARY
const ENGAGEMENT_LINE_WIDTH := 1.6
const ENGAGEMENT_DASH := 9.0
const ENGAGEMENT_GAP := 6.0

## Marking-distance connector style per pressure (opposition overlay only)
## — dash <= 0 draws solid. Tight marking reads as a short, unbroken line;
## loose coverage as a long, sparse dash.
const PRESSURE_LINK_DASH := {
	Settings.DefensivePressure.TIGHT: {"dash": -1.0, "gap": 0.0},
	Settings.DefensivePressure.BALANCED: {"dash": 7.0, "gap": 5.0},
	Settings.DefensivePressure.LOOSE: {"dash": 11.0, "gap": 9.0},
}
const MARKING_LINE_COLOUR := SoftBrutalist.LINE
const MARKING_LINE_ALPHA := 0.5
const MARKING_LINE_WIDTH := 1.2

const OPPOSITION_COLOUR := SoftBrutalist.MUTED
const OPPOSITION_LINE_WIDTH := 1.4
const OPPOSITION_DOT_SCALE := 0.75

const TWEEN_DURATION := 0.35
const TWEEN_TRANS := Tween.TRANS_CUBIC
const TWEEN_EASE := Tween.EASE_IN_OUT

## Per-fielded-slot animation state, keyed by TeamFormation.SLOTS index.
## An index enters this dict fading in from alpha 0 the first time it's
## fielded, and is dropped once it finishes fading out after a formation
## change stops fielding it — see _retarget()/_on_tween_finished().
## Shape: {start_pos, target_pos, start_alpha, target_alpha, display_pos,
## display_alpha}, all in TeamFormation's depth/lateral-fraction Vector3
## (world_position() shape), not screen pixels — screen mapping happens
## once, at draw time, so a resize doesn't require replaying the tween.
var _anim: Dictionary = {}
var _tween: Tween

var _engagement_current := 0.0
var _engagement_tween: Tween


func _ready() -> void:
	_retarget()
	_retarget_engagement()


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
	_draw_engagement_line(centre, scale)
	_draw_opposition(centre, scale)
	_draw_marking_lines(centre, scale)
	_draw_formation(centre, scale)

	_draw_label(centre + Vector2(0.0, -h * 0.5 - CAPTION_OFFSET), "ATTACK ↑", true)


## Maps a world-space position (X = depth/attack axis, Z = lateral) to a
## screen point: world.x -> screen Y (inverted, +depth toward the top),
## world.z -> screen X.
func _to_screen(centre: Vector2, world: Vector3, scale: float) -> Vector2:
	return centre + Vector2(world.z * scale, -world.x * scale)


# ── Tactics: retarget + animate ─────────────────────────────────────

func _depth_offset(line: int) -> float:
	return float(FORMATION_DEPTH_PUSH.get(formation_index, 0.0)) * float(LINE_DEPTH_WEIGHT[line])


func _width_scale(line: int) -> float:
	return _width_scale_for(line, ball_movement)


func _width_scale_for(line: int, movement: int) -> float:
	return 1.0 + float(WIDTH_PUSH[movement]) * float(LINE_WIDTH_WEIGHT[line])


## Depth-frame sign for a pocket's inset — FORWARD_POCKET sits at positive
## depth (toward attack) and pulls back toward FF (negative delta);
## BACK_POCKET sits at negative depth and pulls forward toward FB
## (positive delta). Both read as "toward the line's own centre marker".
func _pocket_depth_inset(role: int) -> float:
	if role == TeamFormation.Role.FORWARD_POCKET_LEFT or role == TeamFormation.Role.FORWARD_POCKET_RIGHT:
		return -POCKET_DEPTH_INSET
	if role == TeamFormation.Role.BACK_POCKET_LEFT or role == TeamFormation.Role.BACK_POCKET_RIGHT:
		return POCKET_DEPTH_INSET
	return 0.0


func _pocket_lateral_scale(role: int) -> float:
	return POCKET_LATERAL_SCALE if role in POCKET_ROLES else 1.0


## Depth/lateral-fraction target for slot `idx`, tactics offsets applied —
## reuses TeamFormation.world_position() itself (a temp adjusted slot dict)
## rather than re-deriving its depth/lateral -> world-metres formula here.
func _target_position(idx: int) -> Vector3:
	var slot: Dictionary = TeamFormation.SLOTS[idx]
	var line: int = slot["line"]
	var role: int = slot["role"]
	var depth := float(slot["depth"]) + _pocket_depth_inset(role)
	var lateral := float(slot["lateral"]) * _pocket_lateral_scale(role)
	var adjusted := {
		"depth": clampf(depth + _depth_offset(line), -OFFSET_CLAMP, OFFSET_CLAMP),
		"lateral": clampf(lateral * _width_scale(line), -OFFSET_CLAMP, OFFSET_CLAMP),
	}
	return TeamFormation.world_position(adjusted, 1.0)


## Static mirrored position for the opposition overlay (see
## _draw_opposition()) — same pocket inset as the fielded side, and the
## same MUTUAL width scale as the current default so both sides read at
## one consistent scale, but deliberately no depth push and no reaction to
## the ball-movement dial: the opposition is a fixed reference shape, not
## a simulated opposing gameplan (see this file's own header).
func _opposition_position(idx: int) -> Vector3:
	var slot: Dictionary = TeamFormation.SLOTS[idx]
	var line: int = slot["line"]
	var role: int = slot["role"]
	var depth := float(slot["depth"]) + _pocket_depth_inset(role)
	var lateral := float(slot["lateral"]) * _pocket_lateral_scale(role)
	var adjusted := {
		"depth": clampf(depth, -OFFSET_CLAMP, OFFSET_CLAMP),
		"lateral": clampf(lateral * _width_scale_for(line, Settings.BallMovementPreference.MUTUAL),
			-OFFSET_CLAMP, OFFSET_CLAMP),
	}
	return TeamFormation.world_position(adjusted, -1.0)


## Recomputes every slot's target and starts one Tween animating the whole
## board there. All 18 TeamFormation.SLOTS are always fielded — the fade
## in/out machinery below only ever fires on first build now, but is kept
## rather than stripped: a future roster feature (fielding fewer than 18)
## has somewhere to plug back into. Called for both a formation and a
## ball-movement change — either can move a slot's target position.
func _retarget() -> void:
	var fielded := range(TeamFormation.SLOTS.size())
	var fielded_set := {}
	for idx in fielded:
		fielded_set[idx] = true

	for idx in fielded:
		var target := _target_position(idx)
		if _anim.has(idx):
			var e: Dictionary = _anim[idx]
			e["start_pos"] = e["display_pos"]
			e["start_alpha"] = e["display_alpha"]
			e["target_pos"] = target
			e["target_alpha"] = 1.0
		else:
			_anim[idx] = {
				"start_pos": target, "target_pos": target,
				"start_alpha": 0.0, "target_alpha": 1.0,
				"display_pos": target, "display_alpha": 0.0,
			}

	for idx in _anim.keys():
		if fielded_set.has(idx):
			continue
		var e: Dictionary = _anim[idx]
		e["start_pos"] = e["display_pos"]
		e["target_pos"] = e["display_pos"]   ## hold in place, fade only
		e["start_alpha"] = e["display_alpha"]
		e["target_alpha"] = 0.0

	_start_tween()


func _start_tween() -> void:
	if is_instance_valid(_tween):
		_tween.kill()
	if not is_inside_tree():
		# Nothing to animate from/to yet (first property set can land
		# before this control has entered the tree) — resolve immediately
		# so the first real _draw() already shows the correct state.
		for idx in _anim.keys():
			var e: Dictionary = _anim[idx]
			e["display_pos"] = e["target_pos"]
			e["display_alpha"] = e["target_alpha"]
		return
	_tween = create_tween()
	_tween.set_trans(TWEEN_TRANS).set_ease(TWEEN_EASE)
	_tween.tween_method(_on_tween_step, 0.0, 1.0, TWEEN_DURATION)
	_tween.finished.connect(_on_tween_finished)


func _on_tween_step(t: float) -> void:
	for idx in _anim.keys():
		var e: Dictionary = _anim[idx]
		e["display_pos"] = (e["start_pos"] as Vector3).lerp(e["target_pos"], t)
		e["display_alpha"] = lerpf(e["start_alpha"], e["target_alpha"], t)
	queue_redraw()


func _on_tween_finished() -> void:
	for idx in _anim.keys().duplicate():
		if float(_anim[idx]["target_alpha"]) <= 0.0:
			_anim.erase(idx)
	queue_redraw()


func _retarget_engagement() -> void:
	var target: float = PRESSURE_ENGAGEMENT_DEPTH[defensive_pressure]
	if is_instance_valid(_engagement_tween):
		_engagement_tween.kill()
	if not is_inside_tree():
		_engagement_current = target
		return
	var start := _engagement_current
	_engagement_tween = create_tween()
	_engagement_tween.set_trans(TWEEN_TRANS).set_ease(TWEEN_EASE)
	_engagement_tween.tween_method(func(t: float) -> void:
		_engagement_current = lerpf(start, target, t)
		queue_redraw(), 0.0, 1.0, TWEEN_DURATION)


# ── Drawing ──────────────────────────────────────────────────────────

func _draw_formation(centre: Vector2, scale: float) -> void:
	for idx in _anim.keys():
		var e: Dictionary = _anim[idx]
		var alpha: float = e["display_alpha"]
		if alpha <= 0.01:
			continue
		var slot: Dictionary = TeamFormation.SLOTS[idx]
		var point := _to_screen(centre, e["display_pos"], scale)
		var colour: Color = LINE_COLOURS[slot["line"]]
		_draw_dot(point, Color(colour, alpha))
		_draw_label(point, String(slot["label"]), false, Color(LABEL_COLOUR, alpha))


## White ring, not an ink one: a dark-outlined dot over pale line art
## reads as high-contrast at a glance. A light ring still separates a dot
## from the markings underneath it while letting the line colour itself
## carry the position. Border alpha follows the fill's, so a fading-out
## marker fades as one shape rather than leaving its ring behind.
func _draw_dot(point: Vector2, colour: Color, radius: float = DOT_RADIUS) -> void:
	draw_circle(point, radius, colour, true, -1.0, true)
	draw_arc(point, radius, 0.0, TAU, 32, Color(DOT_BORDER, colour.a), DOT_BORDER_WIDTH, true)


## Opposition side (toggle_opposition): all 18 TeamFormation slots,
## mirrored (attack_direction -1.0) so they sit at the far end facing your
## own, undisplaced by any tactics dial — "a fixed generic balanced
## layout" per the design brief, not a simulated opposing gameplan.
## Outlined only, no fill, no labels: context, not a focus.
func _draw_opposition(centre: Vector2, scale: float) -> void:
	if not show_opposition:
		return
	for idx in TeamFormation.SLOTS.size():
		var point := _to_screen(centre, _opposition_position(idx), scale)
		draw_arc(point, DOT_RADIUS * OPPOSITION_DOT_SCALE, 0.0, TAU, 24,
			OPPOSITION_COLOUR, OPPOSITION_LINE_WIDTH, true)


## The "marking distance" visual: a thin line from each fielded marker to
## its nearest opposition marker, styled by Defensive Pressure (short/
## solid for tight, long-dashed for loose) — style only, since pressure
## never moves either side's markers, so the real on-screen distance
## between them never actually changes with this dial.
func _draw_marking_lines(centre: Vector2, scale: float) -> void:
	if not show_opposition:
		return
	var opponents: Array[Vector2] = []
	for idx in TeamFormation.SLOTS.size():
		opponents.append(_to_screen(centre, _opposition_position(idx), scale))
	if opponents.is_empty():
		return

	var style: Dictionary = PRESSURE_LINK_DASH[defensive_pressure]
	for idx in _anim.keys():
		var e: Dictionary = _anim[idx]
		var alpha: float = e["display_alpha"]
		if alpha <= 0.01:
			continue
		var point := _to_screen(centre, e["display_pos"], scale)
		var nearest := _nearest_point(point, opponents)
		_draw_dashed_line(point, nearest, Color(MARKING_LINE_COLOUR, MARKING_LINE_ALPHA * alpha),
			MARKING_LINE_WIDTH, float(style["dash"]), float(style["gap"]))


func _nearest_point(from: Vector2, points: Array[Vector2]) -> Vector2:
	var best := points[0]
	var best_dist := INF
	for point in points:
		var dist := from.distance_squared_to(point)
		if dist < best_dist:
			best_dist = dist
			best = point
	return best


## Dashed horizontal engagement line, positioned by Defensive Pressure —
## the one Team Edit dial the design brief keeps away from player markers
## entirely (see _retarget_engagement()).
func _draw_engagement_line(centre: Vector2, scale: float) -> void:
	var y := _to_screen(centre, Vector3(_engagement_current * Tuning.FIELD_HALF_LENGTH, 0.0, 0.0),
		scale).y
	var half_width := Tuning.FIELD_HALF_WIDTH * scale
	_draw_dashed_line(Vector2(centre.x - half_width, y), Vector2(centre.x + half_width, y),
		ENGAGEMENT_LINE_COLOUR, ENGAGEMENT_LINE_WIDTH, ENGAGEMENT_DASH, ENGAGEMENT_GAP)


## `dash_len <= 0` draws a plain solid line. draw_line() has no native
## dash mode, so a dashed one is walked and emitted as separate segments.
func _draw_dashed_line(a: Vector2, b: Vector2, colour: Color, width: float,
		dash_len: float, gap_len: float) -> void:
	if dash_len <= 0.0:
		draw_line(a, b, colour, width, true)
		return
	var diff := b - a
	var length := diff.length()
	if length < 0.01:
		return
	var dir := diff / length
	var travelled := 0.0
	var drawing := true
	while travelled < length:
		var seg_len := dash_len if drawing else gap_len
		var seg_end := minf(travelled + seg_len, length)
		if drawing:
			draw_line(a + dir * travelled, a + dir * seg_end, colour, width, true)
		travelled = seg_end
		drawing = not drawing


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


## `label_colour` overrides the muted/normal default without changing the
## position rule below (only the caption's own `muted` case centres the
## text on `point` instead of sitting it under a dot) — used to fade a
## marker's label in step with its dot.
func _draw_label(point: Vector2, text: String, muted := false,
		label_colour := Color(0.0, 0.0, 0.0, 0.0)) -> void:
	var colour := CAPTION_COLOUR if muted else LABEL_COLOUR
	if label_colour.a > 0.0:
		colour = label_colour
	var text_size := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1.0, LABEL_FONT_SIZE)
	var offset := Vector2(-text_size.x * 0.5, DOT_RADIUS + text_size.y + 1.0) if not muted \
		else Vector2(-text_size.x * 0.5, text_size.y * 0.5)
	draw_string(_font, point + offset, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0,
		LABEL_FONT_SIZE, colour)
