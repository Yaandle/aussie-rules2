class_name MLExperimentViewer
extends RefCounted

const STAGES := ["Logistic regression", "Genetic algorithm", "MLP", "Deep Q-learning"]
const ACTIVE_STAGE := 0
const SWEEP_VALUES := [0.0, 0.2, 0.4, 0.6, 0.8]



## Split out of animation_viewer.gd: the ML Experiments side panel
## (tackle-break-probability model + sweep). Self-contained UI + logic;
## talks back to the AnimationViewer only for the three things it can't
## do itself — swap to the single-subject framing, move the camera, and
## toggle the studio floor/root layout visibility while its own swipe
## panel is open.

const EXPERIMENT_SWIPE_TIME := 0.32
const EXPERIMENT_CAMERA_DISTANCE := 4.2
const EXPERIMENT_CAMERA_HEIGHT := 1.1
const EXPERIMENT_CAMERA_SIDESTEP := 0.0

const TackleModelScript := preload("res://scripts/dev/tackle_model.gd")
const TackleExperimentScript := preload("res://scripts/dev/tackle_experiment.gd")
const TackleChartScript := preload("res://scripts/dev/tackle_chart.gd")

## Back-reference to the owning viewer, for the handful of calls this
## panel doesn't own (camera moves, floor/layout visibility swaps).
var _viewer: AnimationViewer

var _experiment_layer: Control
var _experiment_panel: PanelContainer
var _experiment_status: Label
var _experiment_model_label: Label
var _experiment_results: Label
var _experiment_open := false
var _experiment_layer_tween: Tween
var _experiment_w2 := 0.2
var _experiment_attempts := 1000
var _experiment_cube: Node3D
var _experiment_success_label: Label
var _experiment_z_label: Label
var _experiment_s2_label: Label
var _experiment_sf_label: Label
var _chart

func _init(viewer: AnimationViewer) -> void:
	_viewer = viewer


func is_open() -> bool:
	return _experiment_open


## Builds the swipe-in panel and attaches it under `ui_root`. Call once
## from AnimationViewer._build_ui, same place _build_experiment_layer used
## to be called.
func build(ui_root: Control) -> void:
	_experiment_layer = Control.new()
	_experiment_layer.name = "ExperimentLayer"
	_experiment_layer.custom_minimum_size = _viewer.get_window().size
	_experiment_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	_experiment_layer.visible = false
	ui_root.add_child(_experiment_layer)

	_experiment_panel = PanelContainer.new()
	_experiment_panel.position = Vector2(24.0, 24.0)
	_experiment_panel.custom_minimum_size = Vector2(380.0, 600.0)
	_experiment_panel.size = Vector2(380.0, 600.0)
	_experiment_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_experiment_layer.add_child(_experiment_panel)

	var panel_box := StyleBoxFlat.new()
	panel_box.bg_color = Color(RetroWindow.PANEL, 0.97)
	panel_box.border_color = RetroWindow.BORDER
	panel_box.set_border_width_all(2)
	panel_box.set_corner_radius_all(RetroWindow.RADIUS)
	panel_box.content_margin_left = 18.0
	panel_box.content_margin_right = 18.0
	panel_box.content_margin_top = 16.0
	panel_box.content_margin_bottom = 16.0
	_experiment_panel.add_theme_stylebox_override(&"panel", panel_box)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(344.0, 560.0)
	_experiment_panel.add_child(scroll)

	var root := VBoxContainer.new()
	root.add_theme_constant_override(&"separation", 10)
	scroll.add_child(root)

	root.add_child(UIStyle.label(
		"ML Experiments",
		UIStyle.SIZE_TITLE,
		UIStyle.TEXT_PRIMARY,
		UIStyle.WEIGHT_HEAVY
	))
	root.add_child(_muted_caption("Stage %d of %d: %s" % [ACTIVE_STAGE + 1, STAGES.size(), STAGES[ACTIVE_STAGE]]))
	root.add_child(_muted_caption("P(break) = σ(w₁·Δspeed + w₂·angle + w₃·stamina + b)\nTackle success = 1 − P(break)"))
	root.add_child(HSeparator.new())

	var metrics := GridContainer.new()
	metrics.columns = 2
	metrics.add_theme_constant_override(&"h_separation", 12)
	metrics.add_theme_constant_override(&"v_separation", 12)
	root.add_child(metrics)

	var pb_card := _metric_card("P(BREAK)")
	_experiment_model_label = pb_card.value_label
	metrics.add_child(pb_card.node)

	var ts_card := _metric_card("TACKLE SUCCESS")
	_experiment_success_label = ts_card.value_label
	metrics.add_child(ts_card.node)

	_experiment_z_label = _mono_caption("")
	root.add_child(_experiment_z_label)

	root.add_child(_section_heading("Inputs"))

	var dspeed := _slider_row(root, "Δspeed", -2.0, 4.0, 0.1, 2.0)
	var angle := _slider_row(root, "Angle", -2.0, 2.0, 0.1, 1.0)
	var stamina := _slider_row(root, "Stamina", 0.0, 2.0, 0.1, 1.0)

	root.add_child(_section_heading("Weights"))

	var w1 := _slider_row(root, "w₁ speed", -1.0, 2.0, 0.1, 0.8)
	var w2 := _slider_row(root, "w₂ angle", 0.0, 1.0, 0.05, 0.2)
	var w3 := _slider_row(root, "w₃ stamina", 0.0, 1.5, 0.1, 0.5)
	var bias := _slider_row(root, "b bias", -3.0, 1.0, 0.1, -1.0)

	var recompute := func() -> void:
		var z := w1.value * dspeed.value + w2.value * angle.value + w3.value * stamina.value + bias.value
		var p := 1.0 / (1.0 + exp(-z))
		_experiment_model_label.text = "%.1f%%" % (p * 100.0)
		_experiment_success_label.text = "%.1f%%" % ((1.0 - p) * 100.0)
		_experiment_z_label.text = "z = %.2f" % z
		_experiment_w2 = w2.value

	for s in [dspeed, angle, stamina, w1, w2, w3, bias]:
		s.value_changed.connect(func(_v): recompute.call())
	recompute.call()

	root.add_child(_section_heading("Experiment 01: sweep w₂"))

	var run_row := HBoxContainer.new()
	run_row.add_theme_constant_override(&"separation", 10)
	root.add_child(run_row)

	var attempts := OptionButton.new()
	attempts.add_item("100 attempts each", 100)
	attempts.add_item("1,000 attempts each", 1000)
	attempts.add_item("10,000 attempts each", 10000)
	attempts.select(1)
	attempts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	run_row.add_child(attempts)

	var run_sweep := func() -> void:
		_run_tackle_experiment(
			{"dspeed": dspeed.value, "angle": angle.value, "stamina": stamina.value},
			{"w_speed": w1.value, "w_stamina": w3.value, "bias": bias.value},
			attempts.get_selected_id()
		)

	var run := _viewer.make_dev_button("RUN")
	run.pressed.connect(run_sweep)
	run_row.add_child(run)

	var legend := HBoxContainer.new()
	legend.add_theme_constant_override(&"separation", 16)
	root.add_child(legend)
	legend.add_child(_legend_item("Simulated", UIStyle.ACCENT))
	legend.add_child(_legend_item("Illustrative", UIStyle.TEXT_MUTED))

	_chart = TackleChartScript.new()
	root.add_child(_chart)

	_experiment_results = UIStyle.label("RESULTS\n—", UIStyle.SIZE_LABEL, UIStyle.TEXT_PRIMARY)
	root.add_child(_experiment_results)

	var summary := GridContainer.new()
	summary.columns = 2
	summary.add_theme_constant_override(&"h_separation", 12)
	summary.add_theme_constant_override(&"v_separation", 12)
	root.add_child(summary)

	var s2_card := _metric_card("TWO-POINT 0.2 → 0.8")
	_experiment_s2_label = s2_card.value_label
	summary.add_child(s2_card.node)

	var sf_card := _metric_card("FULL RANGE 0.0 → 0.8")
	_experiment_sf_label = sf_card.value_label
	summary.add_child(sf_card.node)

	_experiment_status = _muted_caption("")
	root.add_child(_experiment_status)

	var back_button := _viewer.make_dev_button("← Back")
	back_button.pressed.connect(func() -> void: set_open(false))
	root.add_child(back_button)

	run_sweep.call()  # last, so every label exists


## Toggled callback target — wire the CONTROL group's EXPERIMENTS button
## straight to this from AnimationViewer._build_control_group.
func on_toggled(on: bool) -> void:
	set_open(on)


func set_open(open: bool) -> void:
	_experiment_open = open
	if _experiment_layer_tween != null and _experiment_layer_tween.is_valid():
		_experiment_layer_tween.kill()

	var viewport_width := maxf(0.0, _viewer.get_window().size.x)
	var hidden_x := viewport_width
	var shown_x := 0.0

	if open:
		_viewer.show_single_subject()
		_viewer.move_camera_to(
			_viewer.STAND_ON + Vector3(-EXPERIMENT_CAMERA_SIDESTEP, EXPERIMENT_CAMERA_HEIGHT, EXPERIMENT_CAMERA_DISTANCE)
		)
		_ensure_experiment_cube_built()
		if _experiment_cube != null:
			_experiment_cube.visible = true
		_viewer.set_studio_floor_visible(false)
		_viewer.set_root_layout_visible(false)
		_experiment_layer.visible = true
		_experiment_layer.position.x = hidden_x
	else:
		_viewer.set_studio_floor_visible(true)
		if _experiment_cube != null:
			_experiment_cube.visible = false

	_experiment_layer_tween = _viewer.create_tween()
	_experiment_layer_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_experiment_layer_tween.tween_property(
		_experiment_layer, "position:x", shown_x if open else hidden_x, EXPERIMENT_SWIPE_TIME
	)
	if not open:
		_experiment_layer_tween.finished.connect(func() -> void:
			_experiment_layer.visible = false
			_viewer.set_root_layout_visible(true)
			_viewer.move_camera_to(
				_viewer.STAND_ON + Vector3(-_viewer.CAMERA_SIDESTEP, _viewer.CAMERA_HEIGHT, _viewer.CAMERA_DISTANCE)
			)
		)


func _ensure_experiment_cube_built() -> void:
	if _experiment_cube != null:
		return
	# TODO: Build experiment visualization cube if desired


func _run_tackle_experiment(inputs: Dictionary, weights: Dictionary, attempts: int) -> void:
	var model = TackleModelScript.new()
	for key in weights:
		model.set(key, weights[key])

	var rows: Array = TackleExperimentScript.sweep(model, "w_angle", SWEEP_VALUES, inputs, attempts, 1)

	var text := "RESULTS\n"
	var plot_points: Array[Vector2] = []
	for row in rows:
		text += "w₂ %.1f  %.1f%%  [%d/%d]\n" % [row.value, row.rate, row.successes, row.attempts]
		plot_points.append(Vector2(row.value, row.rate))
	_experiment_results.text = text

	_experiment_s2_label.text = "%.1f pp/unit" % _slope_between(rows, 0.2, 0.8)
	_experiment_sf_label.text = "%.1f pp/unit" % _slope_between(rows, 0.0, 0.8)

	var noise := sqrt(0.25 / attempts) * 100.0
	_experiment_status.text = "%d attempts per setting, noise about ±%.1f pp (1 SE, worst case). Slopes are experimental over the tested range." % [attempts, noise]

	if _chart != null:
		_chart.set_simulated(plot_points)


func _slope_between(rows: Array, from_w: float, to_w: float) -> float:
	var lo = null
	var hi = null
	for row in rows:
		if is_equal_approx(row.value, from_w):
			lo = row
		if is_equal_approx(row.value, to_w):
			hi = row
	if lo == null or hi == null:
		return NAN
	return (hi.rate - lo.rate) / (to_w - from_w)


func _metric_card(caption: String) -> Dictionary:
	var box := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(RetroWindow.PANEL, 0.6)
	style.set_corner_radius_all(RetroWindow.RADIUS)
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 12.0
	style.content_margin_bottom = 12.0
	box.add_theme_stylebox_override(&"panel", style)

	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 2)
	box.add_child(col)

	col.add_child(UIStyle.label(caption, UIStyle.SIZE_LABEL, UIStyle.TEXT_MUTED))
	var value := UIStyle.label("—", UIStyle.SIZE_TITLE, UIStyle.TEXT_PRIMARY, UIStyle.WEIGHT_BOLD)
	col.add_child(value)

	return {"node": box, "value_label": value}


func _section_heading(text: String) -> Label:
	return UIStyle.label(text.to_upper(), UIStyle.SIZE_LABEL, UIStyle.TEXT_MUTED, UIStyle.WEIGHT_BOLD)


func _muted_caption(text: String) -> Label:
	return UIStyle.label(text, UIStyle.SIZE_LABEL, UIStyle.TEXT_MUTED)


func _mono_caption(text: String) -> Label:
	return UIStyle.label(text, UIStyle.SIZE_LABEL, UIStyle.TEXT_MUTED)


func _legend_item(text: String, color: Color) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 4)
	var swatch := ColorRect.new()
	swatch.custom_minimum_size = Vector2(10.0, 10.0)
	swatch.color = color
	row.add_child(swatch)
	row.add_child(UIStyle.label(text, UIStyle.SIZE_LABEL, UIStyle.TEXT_MUTED))
	return row


func _slider_row(parent: VBoxContainer, label_text: String, min_v: float, max_v: float, step: float, default: float) -> HSlider:
	var row := GridContainer.new()
	row.columns = 3
	row.add_theme_constant_override(&"h_separation", 10)
	parent.add_child(row)

	var label := UIStyle.label(label_text, UIStyle.SIZE_LABEL, UIStyle.TEXT_MUTED)
	label.custom_minimum_size.x = 76.0
	row.add_child(label)

	var slider := HSlider.new()
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step = step
	slider.value = default
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(slider)

	var out := UIStyle.label("%.2f" % default, UIStyle.SIZE_LABEL, UIStyle.TEXT_PRIMARY)
	out.custom_minimum_size.x = 44.0
	out.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(out)

	slider.value_changed.connect(func(v: float) -> void:
		out.text = "%.2f" % v
	)

	return slider