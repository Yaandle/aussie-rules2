class_name GAFitnessChart
extends Control
## Generation → fitness line chart for the ML Experiments page's Genetic
## Algorithm stage. Plots best-of-generation (solid accent) and
## population-average (dashed muted) fitness, Y fixed to TackleGA's own
## 0..1 score range, X auto-scaled to however many generations the last
## run actually used.
##
## A separate control from TackleChart (scripts/dev/tackle_chart.gd)
## rather than a generalisation of it — that one's axes (weight value
## 0..0.8, success % 0..100) and baked-in illustrative reference line are
## specific to the SWEEP page and not a fit for "generation vs fitness".

const MARGIN_LEFT := 36.0
const MARGIN_RIGHT := 10.0
const MARGIN_TOP := 10.0
const MARGIN_BOTTOM := 20.0

var _history: Array = []   ## [{generation, best, avg}, ...]


func _ready() -> void:
	custom_minimum_size = Vector2(344.0, 160.0)


func set_history(history: Array) -> void:
	_history = history
	queue_redraw()


func _plot_area() -> Rect2:
	return Rect2(
		MARGIN_LEFT, MARGIN_TOP,
		size.x - MARGIN_LEFT - MARGIN_RIGHT,
		size.y - MARGIN_TOP - MARGIN_BOTTOM
	)


func _to_screen(gen: float, value: float, area: Rect2, max_gen: float) -> Vector2:
	var tx := 0.0 if max_gen <= 0.0 else gen / max_gen
	var ty := clampf(value, 0.0, 1.0)
	return Vector2(
		area.position.x + tx * area.size.x,
		area.position.y + (1.0 - ty) * area.size.y
	)


func _draw() -> void:
	var area := _plot_area()

	for i in range(5):
		var yv := float(i) / 4.0
		var p := _to_screen(0.0, yv, area, 1.0)
		draw_line(Vector2(area.position.x, p.y), Vector2(area.end.x, p.y), UIStyle.TEXT_MUTED, 1.0)
		draw_string(ThemeDB.fallback_font, Vector2(2.0, p.y + 4.0), "%.2f" % yv,
			HORIZONTAL_ALIGNMENT_LEFT, -1, UIStyle.SIZE_LABEL, UIStyle.TEXT_MUTED)

	draw_rect(area, UIStyle.TEXT_MUTED, false, 1.0)

	if _history.is_empty():
		draw_string(ThemeDB.fallback_font, Vector2(area.position.x + 8.0, area.position.y + area.size.y * 0.5),
			"Run the GA to plot fitness", HORIZONTAL_ALIGNMENT_LEFT, -1, UIStyle.SIZE_LABEL, UIStyle.TEXT_MUTED)
		return

	var max_gen: float = _history[-1].generation
	draw_string(ThemeDB.fallback_font, Vector2(area.position.x, area.end.y + 16.0), "gen 0",
		HORIZONTAL_ALIGNMENT_LEFT, -1, UIStyle.SIZE_LABEL, UIStyle.TEXT_MUTED)
	draw_string(ThemeDB.fallback_font, Vector2(area.end.x - 50.0, area.end.y + 16.0), "gen %d" % int(max_gen),
		HORIZONTAL_ALIGNMENT_LEFT, -1, UIStyle.SIZE_LABEL, UIStyle.TEXT_MUTED)

	var best_pts := PackedVector2Array()
	var avg_pts := PackedVector2Array()
	for row in _history:
		best_pts.append(_to_screen(row.generation, row.best, area, max_gen))
		avg_pts.append(_to_screen(row.generation, row.avg, area, max_gen))

	if avg_pts.size() >= 2:
		draw_polyline(avg_pts, UIStyle.TEXT_MUTED, 1.5, true)
	if best_pts.size() >= 2:
		draw_polyline(best_pts, UIStyle.ACCENT, 2.0, true)
