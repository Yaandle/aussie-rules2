class_name TackleChart
extends Control

const Y_MIN := 0.0
const Y_MAX := 100.0
const X_MIN := 0.0
const X_MAX := 0.8

const ILLUSTRATIVE_POINTS: Array[Vector2] = [
	Vector2(0.0, 42.0),
	Vector2(0.2, 48.0),
	Vector2(0.4, 55.0),
	Vector2(0.6, 63.0),
	Vector2(0.8, 70.0),
]

var simulated_points: Array[Vector2] = []

const MARGIN_LEFT := 36.0
const MARGIN_RIGHT := 10.0
const MARGIN_TOP := 10.0
const MARGIN_BOTTOM := 24.0

func _ready() -> void:
	custom_minimum_size = Vector2(344.0, 220.0)

func set_simulated(points: Array[Vector2]) -> void:
	simulated_points = points
	queue_redraw()

func _plot_area() -> Rect2:
	return Rect2(
		MARGIN_LEFT, MARGIN_TOP,
		size.x - MARGIN_LEFT - MARGIN_RIGHT,
		size.y - MARGIN_TOP - MARGIN_BOTTOM
	)

func _to_screen(p: Vector2, area: Rect2) -> Vector2:
	var tx := (p.x - X_MIN) / (X_MAX - X_MIN)
	var ty := (p.y - Y_MIN) / (Y_MAX - Y_MIN)
	return Vector2(
		area.position.x + tx * area.size.x,
		area.position.y + (1.0 - ty) * area.size.y
	)

func _draw() -> void:
	var area := _plot_area()

	for i in range(5):
		var yv := Y_MIN + (Y_MAX - Y_MIN) * float(i) / 4.0
		var p := _to_screen(Vector2(X_MIN, yv), area)
		draw_line(Vector2(area.position.x, p.y), Vector2(area.end.x, p.y), UIStyle.TEXT_MUTED, 1.0)
		draw_string(ThemeDB.fallback_font, Vector2(2.0, p.y + 4.0), "%d%%" % int(yv),
			HORIZONTAL_ALIGNMENT_LEFT, -1, UIStyle.SIZE_LABEL, UIStyle.TEXT_MUTED)

	for xv in [0.0, 0.2, 0.4, 0.6, 0.8]:
		var p := _to_screen(Vector2(xv, Y_MIN), area)
		draw_string(ThemeDB.fallback_font, Vector2(p.x - 10.0, area.end.y + 16.0), "%.1f" % xv,
			HORIZONTAL_ALIGNMENT_LEFT, -1, UIStyle.SIZE_LABEL, UIStyle.TEXT_MUTED)

	draw_rect(area, UIStyle.TEXT_MUTED, false, 1.0)

	_draw_dashed_polyline(ILLUSTRATIVE_POINTS, area, UIStyle.TEXT_MUTED)

	if simulated_points.size() >= 2:
		var pts := PackedVector2Array()
		for wp in simulated_points:
			pts.append(_to_screen(wp, area))
		draw_polyline(pts, UIStyle.ACCENT, 2.0, true)

func _draw_dashed_polyline(points: Array[Vector2], area: Rect2, color: Color) -> void:
	var dash_len := 5.0
	var gap_len := 4.0
	for i in range(points.size() - 1):
		var a := _to_screen(points[i], area)
		var b := _to_screen(points[i + 1], area)
		var seg := b - a
		var seg_len := seg.length()
		if seg_len <= 0.0:
			continue
		var dir := seg / seg_len
		var t := 0.0
		var draw_dash := true
		while t < seg_len:
			var step: float = dash_len if draw_dash else gap_len
			var t_end: float = min(t + step, seg_len)
			if draw_dash:
				draw_line(a + dir * t, a + dir * t_end, color, 1.5)
			t = t_end
			draw_dash = not draw_dash