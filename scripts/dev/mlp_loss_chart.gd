class_name MLPLossChart
extends Control
## Epoch → loss line chart for the ML Experiments page's MLP stage: training
## loss (solid accent) and validation loss (muted), on a log10 Y axis
## auto-ranged to the run, with a marker at the epoch whose weights were
## kept (best validation loss — MarkCueTrainer keeps those rather than the
## last epoch's).
##
## Same drawing approach as GAFitnessChart (ga_fitness_chart.gd) rather
## than a generalisation of it: that one's Y is fixed to TackleGA's 0..1
## score, and a loss curve spans orders of magnitude, so it needs a log axis
## that one doesn't.

const MARGIN_LEFT := 44.0
const MARGIN_RIGHT := 10.0
const MARGIN_TOP := 10.0
const MARGIN_BOTTOM := 20.0

var _history: Array = []   ## [{epoch, train, val}, ...]
var _best_epoch := -1


func _ready() -> void:
	custom_minimum_size = Vector2(344.0, 170.0)


func set_history(history: Array, best_epoch: int = -1) -> void:
	_history = history
	_best_epoch = best_epoch
	queue_redraw()


func _plot_area() -> Rect2:
	return Rect2(MARGIN_LEFT, MARGIN_TOP, size.x - MARGIN_LEFT - MARGIN_RIGHT,
		size.y - MARGIN_TOP - MARGIN_BOTTOM)


func _draw() -> void:
	var area := _plot_area()
	draw_rect(area, UIStyle.TEXT_MUTED, false, 1.0)
	if _history.is_empty():
		draw_string(ThemeDB.fallback_font, Vector2(area.position.x + 8.0, area.position.y + area.size.y * 0.5),
			"TRAIN to plot loss", HORIZONTAL_ALIGNMENT_LEFT, -1, UIStyle.SIZE_LABEL, UIStyle.TEXT_MUTED)
		return

	var lo := INF
	var hi := -INF
	for row in _history:
		for v in [row.train, row.val]:
			if v > 0.0:
				lo = minf(lo, log(v) / log(10.0))
				hi = maxf(hi, log(v) / log(10.0))
	lo = floorf(lo)
	hi = ceilf(hi)
	if hi <= lo:
		hi = lo + 1.0
	var max_epoch: float = maxf(1.0, _history[-1].epoch)
	var to_screen := func(epoch: float, value: float) -> Vector2:
		var ly := log(maxf(value, 1e-12)) / log(10.0)
		return Vector2(area.position.x + epoch / max_epoch * area.size.x,
			area.position.y + (1.0 - (ly - lo) / (hi - lo)) * area.size.y)

	for decade in range(int(lo), int(hi) + 1):
		var y: float = to_screen.call(0.0, pow(10.0, decade)).y
		draw_line(Vector2(area.position.x, y), Vector2(area.end.x, y), Color(UIStyle.TEXT_MUTED, 0.35), 1.0)
		draw_string(ThemeDB.fallback_font, Vector2(2.0, y + 4.0), "1e%d" % decade,
			HORIZONTAL_ALIGNMENT_LEFT, -1, UIStyle.SIZE_LABEL, UIStyle.TEXT_MUTED)
	draw_string(ThemeDB.fallback_font, Vector2(area.position.x, area.end.y + 16.0), "epoch 0",
		HORIZONTAL_ALIGNMENT_LEFT, -1, UIStyle.SIZE_LABEL, UIStyle.TEXT_MUTED)
	draw_string(ThemeDB.fallback_font, Vector2(area.end.x - 64.0, area.end.y + 16.0), "epoch %d" % int(max_epoch),
		HORIZONTAL_ALIGNMENT_LEFT, -1, UIStyle.SIZE_LABEL, UIStyle.TEXT_MUTED)

	if _best_epoch > 0:
		var x: float = to_screen.call(float(_best_epoch), pow(10.0, lo)).x
		draw_line(Vector2(x, area.position.y), Vector2(x, area.end.y), UIStyle.TEXT_PRIMARY, 1.0)

	var train_pts := PackedVector2Array()
	var val_pts := PackedVector2Array()
	for row in _history:
		train_pts.append(to_screen.call(float(row.epoch), row.train))
		val_pts.append(to_screen.call(float(row.epoch), row.val))
	if val_pts.size() >= 2:
		draw_polyline(val_pts, UIStyle.TEXT_MUTED, 1.5, true)
	if train_pts.size() >= 2:
		draw_polyline(train_pts, UIStyle.ACCENT, 2.0, true)
