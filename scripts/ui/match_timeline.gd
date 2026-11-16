class_name MatchTimeline
extends Control

## The full match as one bar, for the Highlights screen's MATCH view
## (docs/HIGHLIGHTS_FULLGAME_PLAN.md, phase 3). Its length is the full-match
## VIDEO (FullMatchCut: breaks and dead time already cut), so a point on the
## bar is the same frame the exported match_16x9.mp4 has there, and the
## markers sit where match_video.json puts them.
##
## Drawn by hand (_draw) rather than built from nodes: a match has a hundred-
## odd markers. Rows, top to bottom: the moment bands (kept ones lime, the
## rest paper, the selected one outlined), the event ticks (a goal full
## height, everything else short, coloured by kind), quarter dividers, and
## the playhead. Click or drag anywhere on it to seek.

signal seek_requested(video_frame: int)

## Tick colour per event kind (match.json `events[].kind`). Goals and behinds
## are the loud ones; the rest are quiet so a busy match still reads.
const KIND_COLORS := {
	"goal": StudioStyle.ORANGE,
	"behind": Color("#F2A33A"),
	"mark": Color("#2F6FD6"),
	"tackle": Color("#B0322B"),
	"bump": Color("#7A3FB8"),
	"kick": StudioStyle.INK_SOFT,
	"handball": Color("#8C8778"),
	"bounce": Color("#8C8778"),
	"siren": StudioStyle.INK,
}
## Kinds that get a tall tick.
const TALL := ["goal", "behind", "siren"]
const BAND_HEIGHT := 13.0

var frames := 1
## [{video_from, quarter}] where each quarter starts on the bar.
var quarters: Array = []
## [{frame, kind}] in video frames.
var markers: Array = []
## [{from, to, kept, selected, tag}] in video frames; `tag` is the band's
## camera, a letter drawn on it when there's room.
var moments: Array = []
var playhead := 0

var _dragging := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


func set_playhead(frame: int) -> void:
	if frame != playhead:
		playhead = frame
		queue_redraw()


func _x(frame: float) -> float:
	return size.x * clampf(frame / float(maxi(frames - 1, 1)), 0.0, 1.0)


func _draw() -> void:
	var w := size.x
	var h := size.y
	draw_rect(Rect2(Vector2.ZERO, size), StudioStyle.WHITE)
	# Moment bands along the top.
	for m: Dictionary in moments:
		var x0 := _x(float(m.from))
		var x1 := maxf(_x(float(m.to)), x0 + 2.0)
		var rect := Rect2(x0, 0.0, x1 - x0, BAND_HEIGHT)
		draw_rect(rect, StudioStyle.LIME if m.kept else StudioStyle.PAPER_DEEP)
		if m.selected:
			draw_rect(rect.grow(1.0), StudioStyle.INK, false, 2.0)
		if String(m.get("tag", "")) != "" and x1 - x0 >= 9.0:
			draw_string(StudioStyle.mono_font(), Vector2(x0 + 2.0, BAND_HEIGHT - 2.0), String(m.tag),
				HORIZONTAL_ALIGNMENT_LEFT, x1 - x0 - 2.0, 10, StudioStyle.INK)
	# Event ticks under them.
	var base := h - 4.0
	for e: Dictionary in markers:
		var kind := String(e.kind)
		var x := _x(float(e.frame))
		var top := BAND_HEIGHT + 2.0 if kind in TALL else base - (h - BAND_HEIGHT) * 0.45
		draw_line(Vector2(x, top), Vector2(x, base), KIND_COLORS.get(kind, StudioStyle.INK_SOFT), 2.0 if kind in TALL else 1.0)
	# Quarter dividers and labels.
	var font := StudioStyle.mono_font()
	for q: Dictionary in quarters:
		var x := _x(float(q.video_from))
		draw_line(Vector2(x, 0.0), Vector2(x, h), StudioStyle.INK, 2.0)
		draw_string(font, Vector2(x + 4.0, h - 6.0), "Q%d" % int(q.quarter), HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
			StudioStyle.INK_SOFT)
	draw_rect(Rect2(Vector2.ZERO, size), StudioStyle.INK, false, 2.0)
	# The playhead.
	var px := _x(float(playhead))
	draw_rect(Rect2(px - 1.5, -4.0, 3.0, h + 8.0), StudioStyle.ORANGE)
	draw_line(Vector2(0.0, h), Vector2(w, h), StudioStyle.INK, 2.0)


func _gui_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click != null and click.button_index == MOUSE_BUTTON_LEFT:
		_dragging = click.pressed
		if click.pressed:
			_seek_to(click.position.x)
		accept_event()
		return
	var motion := event as InputEventMouseMotion
	if motion != null and _dragging:
		_seek_to(motion.position.x)
		accept_event()


func _seek_to(x: float) -> void:
	var frame := int(round(clampf(x / maxf(size.x, 1.0), 0.0, 1.0) * float(maxi(frames - 1, 0))))
	seek_requested.emit(frame)
