class_name ScoreboardFace
extends Control

## A suburban-ground scoreboard face in seven-segment digits (playtest
## 2026-10-29: "have 7 seg scoreboard: 00 | 00 | 000 ... goals points total
## for both sides"). One row per team, goals | behinds | total, with the
## quarter and the clock beside them:
##
##          GOALS  BEHINDS  POINTS     QTR 1
##   ▌HOME   0 0  |  0 0  |  0 0 0    12:34
##   ▌AWAY   0 0  |  0 0  |  0 0 0
##
## Drawn with _draw() rather than Labels: segments are polygons, so the
## digits read as a real lit board at any size, with the unlit segments
## showing faintly the way a real one's do. The same face is the HUD
## (Scoreboard) and the board out on the ground (FieldScoreboard, which
## draws it into a SubViewport), so the two always agree. Everything is
## sized off one digit height, worked out to fit whatever rect it's given.
##
## Reads MatchState itself. `changed` fires when what it shows changes (a
## score, the quarter, or the clock's displayed second), which is when
## FieldScoreboard redraws its viewport.

signal changed

## The board. Warm near-black like RetroWindow.BORDER, so it sits with the
## rest of the UI; amber digits like a ground's incandescent board.
const BOARD := Color("#14120F")
const BOARD_EDGE := Color("#3A352D")
const LIT := Color("#FFB627")
const UNLIT := Color("#2C2822")
const TEXT := Color("#EDE6D6")
const TEXT_MUTED := Color("#8F877A")

## Layout, in digit heights (H). The digit's width and its segments'
## thickness, the gap between digits in a group, a " | " separator, the
## team-name column, the clock block's digit size.
const DIGIT_W := 0.56
const SEG_T := 0.15
const DIGIT_GAP := 0.2
const SEP_W := 0.62
const NAME_W := 3.1
const SWATCH_W := 0.16
const CLOCK_GAP := 0.9
const CLOCK_H := 0.72
const HEADER_H := 0.42
const ROW_GAP := 0.32
const PAD := 0.32
## A classic seven-segment face leans forward a little.
const SKEW := 0.09

## Segments a-g as [from, to] in a unit digit (x 0..1 across, y 0..1 down).
const SEGMENTS := {
	&"a": [Vector2(0.0, 0.0), Vector2(1.0, 0.0)],
	&"b": [Vector2(1.0, 0.0), Vector2(1.0, 0.5)],
	&"c": [Vector2(1.0, 0.5), Vector2(1.0, 1.0)],
	&"d": [Vector2(0.0, 1.0), Vector2(1.0, 1.0)],
	&"e": [Vector2(0.0, 0.5), Vector2(0.0, 1.0)],
	&"f": [Vector2(0.0, 0.0), Vector2(0.0, 0.5)],
	&"g": [Vector2(0.0, 0.5), Vector2(1.0, 0.5)],
}
const DIGITS := {
	"0": "abcdef", "1": "bc", "2": "abdeg", "3": "abcdg", "4": "bcfg",
	"5": "acdfg", "6": "acdefg", "7": "abc", "8": "abcdefg", "9": "abcdfg",
	" ": "", "-": "g",
}

## Team names shown on the rows; set from MatchState's teams by default
## (team_label), or by whoever owns the match.
var home_name := ""
var away_name := ""
## The board's rounded edge. FieldScoreboard turns it off: its prop is the
## frame, and the face fills the prop's panel edge to edge.
var draw_frame := true

var _shown := ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if home_name == "":
		home_name = team_label(Tuning.Team.HOME)
	if away_name == "":
		away_name = team_label(Tuning.Team.AWAY)
	MatchState.score_changed.connect(func(_team: Tuning.Team) -> void: _refresh())
	MatchState.clock_changed.connect(func(_seconds: float) -> void: _refresh())
	MatchState.quarter_changed.connect(func(_quarter: int) -> void: _refresh())
	resized.connect(queue_redraw)
	_refresh()


## The name a row shows: in a Career match the club's nickname, the last
## word of "Ivanhoe Swans", the way a ground's board shortens it; otherwise
## HOME / AWAY. Upper case, and cut to fit the column.
static func team_label(team: Tuning.Team) -> String:
	var label := "HOME" if team == Tuning.Team.HOME else "AWAY"
	if GameState.career_active:
		var club := CareerProfile.team_name if team == Tuning.Team.HOME \
			else CareerProfile.current_fixture()
		var words := club.strip_edges().split(" ", false)
		if not words.is_empty():
			label = words[-1]
	label = label.to_upper()
	return label if label.length() <= 9 else label.substr(0, 9)


## What the face shows right now, as one string: a change in it is a change
## worth redrawing for (the clock ticks every frame; its seconds don't).
func _snapshot() -> String:
	return "%d.%d|%d.%d|%d|%d" % [MatchState.goals[Tuning.Team.HOME], MatchState.behinds[Tuning.Team.HOME],
		MatchState.goals[Tuning.Team.AWAY], MatchState.behinds[Tuning.Team.AWAY],
		MatchState.quarter, maxi(int(ceil(MatchState.seconds_remaining)), 0)]


func _refresh() -> void:
	var now := _snapshot()
	if now == _shown:
		return
	_shown = now
	queue_redraw()
	changed.emit()


## The face's natural size for digit height `h` — what a container should
## give it.
static func size_for(h: float) -> Vector2:
	return Vector2(_content_width(), HEADER_H + 2.0 + ROW_GAP + 2.0 * PAD) * h


static func _content_width() -> float:
	var two := 2.0 * DIGIT_W + DIGIT_GAP
	var three := 3.0 * DIGIT_W + 2.0 * DIGIT_GAP
	var clock := (4.0 * DIGIT_W + 3.0 * DIGIT_GAP + 0.4) * CLOCK_H
	return 2.0 * PAD + NAME_W + two + SEP_W + two + SEP_W + three + CLOCK_GAP + clock


func _draw() -> void:
	var natural := size_for(1.0)
	var h := minf(size.x / natural.x, size.y / natural.y)
	var origin := (size - natural * h) * 0.5

	if draw_frame:
		var board := StyleBoxFlat.new()
		board.bg_color = BOARD
		board.border_color = BOARD_EDGE
		board.set_border_width_all(maxi(2, int(h * 0.07)))
		board.set_corner_radius_all(int(h * 0.12))
		draw_style_box(board, Rect2(origin, natural * h))
	else:
		draw_rect(Rect2(Vector2.ZERO, size), BOARD)

	var font := SoftBrutalist.font(SoftBrutalist.WEIGHT_HEAVY)
	var small := int(h * 0.27)
	var x0 := origin.x + PAD * h
	var y0 := origin.y + PAD * h
	var two := (2.0 * DIGIT_W + DIGIT_GAP) * h
	var three := (3.0 * DIGIT_W + 2.0 * DIGIT_GAP) * h
	var sep := SEP_W * h
	var goals_x := x0 + NAME_W * h
	var behinds_x := goals_x + two + sep
	var points_x := behinds_x + two + sep

	# Column headings.
	var head_y := y0 + HEADER_H * h * 0.72
	for column: Array in [["GOALS", goals_x, two], ["BEHINDS", behinds_x, two], ["POINTS", points_x, three]]:
		draw_string(font, Vector2(column[1], head_y), column[0], HORIZONTAL_ALIGNMENT_CENTER,
			column[2], small, TEXT_MUTED)

	# The two team rows.
	var row_y := y0 + HEADER_H * h
	for team: Tuning.Team in [Tuning.Team.HOME, Tuning.Team.AWAY]:
		var away := team == Tuning.Team.AWAY
		# The team's jersey colour, outlined so a black or navy kit still
		# shows on the dark board.
		var jersey: Color = TeamKit.colours(away)["jersey"]
		var swatch := Rect2(x0, row_y + h * 0.08, SWATCH_W * h, h * 0.84)
		draw_rect(swatch, jersey)
		draw_rect(swatch, TEXT_MUTED, false, maxf(1.0, h * 0.04))
		var team_text := away_name if away else home_name
		draw_string(font, Vector2(x0 + (SWATCH_W + 0.2) * h, row_y + h * 0.7), team_text,
			HORIZONTAL_ALIGNMENT_LEFT, (NAME_W - SWATCH_W - 0.3) * h, int(h * 0.5), TEXT)
		var goals := clampi(MatchState.goals[team], 0, 99)
		var behinds := clampi(MatchState.behinds[team], 0, 99)
		var total := clampi(MatchState.points(team), 0, 999)
		_draw_number("%02d" % goals, Vector2(goals_x, row_y), h)
		_draw_separator(goals_x + two, row_y, sep, h)
		_draw_number("%02d" % behinds, Vector2(behinds_x, row_y), h)
		_draw_separator(behinds_x + two, row_y, sep, h)
		_draw_number("%03d" % total, Vector2(points_x, row_y), h)
		row_y += h * (1.0 + ROW_GAP)

	# Quarter over clock, right of the rows.
	var clock_x := points_x + three + CLOCK_GAP * h
	var ch := CLOCK_H * h
	var seconds := maxi(int(ceil(MatchState.seconds_remaining)), 0)
	var qtr_y := y0 + HEADER_H * h
	draw_string(font, Vector2(clock_x, qtr_y + ch * 0.75), "QTR", HORIZONTAL_ALIGNMENT_LEFT, -1,
		int(h * 0.36), TEXT_MUTED)
	_draw_number(str(clampi(MatchState.quarter, 0, 9)), Vector2(clock_x + 1.35 * ch, qtr_y), ch)
	var time_y := y0 + HEADER_H * h + h * (1.0 + ROW_GAP)
	var minutes := "%02d" % mini(seconds / 60, 99)
	var secs := "%02d" % (seconds % 60)
	_draw_number(minutes, Vector2(clock_x, time_y), ch)
	var colon_x := clock_x + (2.0 * DIGIT_W + DIGIT_GAP) * ch + 0.2 * ch
	for dot_y in [0.32, 0.72]:
		draw_rect(Rect2(colon_x - SEG_T * ch * 0.5, time_y + dot_y * ch - SEG_T * ch * 0.5,
			SEG_T * ch, SEG_T * ch), LIT)
	_draw_number(secs, Vector2(colon_x + 0.2 * ch + SEG_T * ch, time_y), ch)


func _draw_separator(x: float, y: float, width: float, h: float) -> void:
	draw_rect(Rect2(x + width * 0.5 - h * 0.035, y + h * 0.06, h * 0.07, h * 0.88), BOARD_EDGE)


## `digits` left to right from `at` (the top-left of the first digit), each
## `h` tall.
func _draw_number(digits: String, at: Vector2, h: float) -> void:
	var x := at.x
	for ch in digits:
		_draw_digit(DIGITS.get(ch, ""), Vector2(x, at.y), h)
		x += (DIGIT_W + DIGIT_GAP) * h


func _draw_digit(lit: String, at: Vector2, h: float) -> void:
	var w := DIGIT_W * h
	var t := SEG_T * h
	for segment: StringName in SEGMENTS:
		var ends: Array = SEGMENTS[segment]
		var colour := LIT if String(segment) in lit else UNLIT
		draw_colored_polygon(_segment_polygon(ends[0], ends[1], at, w, h, t), colour)


## A bevelled bar from `a` to `b` (unit digit space), pulled in at each end
## so neighbouring segments don't touch, leaned by SKEW.
func _segment_polygon(a: Vector2, b: Vector2, at: Vector2, w: float, h: float, t: float) -> PackedVector2Array:
	var inset := t * 0.5
	var p0 := Vector2(inset + a.x * (w - 2.0 * inset), inset + a.y * (h - 2.0 * inset))
	var p1 := Vector2(inset + b.x * (w - 2.0 * inset), inset + b.y * (h - 2.0 * inset))
	var along := (p1 - p0).normalized()
	var across := Vector2(-along.y, along.x)
	var gap := t * 0.12
	p0 += along * gap
	p1 -= along * gap
	var half := t * 0.5
	var points := PackedVector2Array([
		p0,
		p0 + along * half + across * half,
		p1 - along * half + across * half,
		p1,
		p1 - along * half - across * half,
		p0 + along * half - across * half,
	])
	for i in points.size():
		var p := points[i]
		points[i] = at + Vector2(p.x + (h - p.y) * SKEW, p.y)
	return points
