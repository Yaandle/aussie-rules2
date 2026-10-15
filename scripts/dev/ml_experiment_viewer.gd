class_name MLExperimentViewer
extends RefCounted

## Split out of animation_viewer.gd: the ML Experiments page
## (tackle-break-probability model + sweep).
##
## Layout: a narrow control column on the left (pinned metrics + MODEL / SWEEP
## tabs) and a SIM window on the right showing the player inside an X/Y/Z
## wireframe cube. No .tscn needed; everything is built in code and hosted by
## animation_viewer.tscn / animation_viewer.gd.
##
## Talks back to the AnimationViewer only for things it can't do itself:
## single-subject framing, camera moves, and floor/root-layout visibility.

const STAGES := ["Logistic regression", "Genetic algorithm", "MLP", "Deep Q-learning"]
const ACTIVE_STAGE := 0
const SWEEP_VALUES := [0.0, 0.2, 0.4, 0.6, 0.8]

const SWEEP_WEIGHTS := [
	{"key": "w_angle", "name": "w₂"},
	{"key": "w_speed", "name": "w₁"},
	{"key": "w_stamina", "name": "w₃"},
	{"key": "bias", "name": "b"},
]

const EXPERIMENT_SWIPE_TIME := 0.32
const EXPERIMENT_CAMERA_DISTANCE := 4.2
const EXPERIMENT_CAMERA_HEIGHT := 1.1
const EXPERIMENT_CAMERA_SIDESTEP := 0.0

# --- layout -----------------------------------------------------------------
const OUTER_MARGIN := 18
const COLUMN_GAP := 18
const MENU_WIDTH := 312.0
const HARD_SHADOW := 4.0

# --- sim window / cube ------------------------------------------------------
const CUBE_SIZE := 2.0          # metres; player stands at the floor centre
const CUBE_TICK_STEP := 0.5
const SIM_DIST_MIN := 2.5
const SIM_DIST_MAX := 9.0
const COLOR_EDGE := Color(0.82, 0.82, 0.78, 0.9)
const COLOR_GRID := Color(0.82, 0.82, 0.78, 0.22)
const COLOR_AXIS_X := Color(0.95, 0.30, 0.28)
const COLOR_AXIS_Y := Color(0.40, 0.88, 0.40)
const COLOR_AXIS_Z := Color(0.35, 0.58, 1.00)
const COLOR_SIM_BG := Color(0.07, 0.07, 0.08)

const TackleModelScript := preload("res://scripts/dev/tackle_model.gd")
const TackleExperimentScript := preload("res://scripts/dev/tackle_experiment.gd")
const TackleChartScript := preload("res://scripts/dev/tackle_chart.gd")

## Back-reference to the owning viewer.
var _viewer: AnimationViewer

var _experiment_layer: Control
var _experiment_status: Label
var _experiment_model_label: Label
var _experiment_results: Label
var _experiment_open := false
var _experiment_layer_tween: Tween
var _experiment_w2 := 0.2
var _experiment_attempts := 1000
var _experiment_seed := 1
var _experiment_cube: Node3D
var _experiment_success_label: Label
var _experiment_z_label: Label
var _experiment_s2_label: Label
var _experiment_sf_label: Label
var _chart

var _sim_camera: Camera3D
var _sim_yaw := 0.7
var _sim_pitch := 0.35
var _sim_dist := 5.2


func _init(viewer: AnimationViewer) -> void:
	_viewer = viewer


func is_open() -> bool:
	return _experiment_open


# =============================================================================
# BUILD
# =============================================================================

## Builds the page and attaches it under `ui_root`. Call once from
## AnimationViewer._build_ui.
func build(ui_root: Control) -> void:
	_experiment_layer = Control.new()
	_experiment_layer.name = "ExperimentLayer"
	_experiment_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_experiment_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	_experiment_layer.visible = false
	ui_root.add_child(_experiment_layer)

	# Opaque backdrop so the main 3D view doesn't show through.
	var backdrop := ColorRect.new()
	backdrop.color = Color(RetroWindow.PANEL).darkened(0.25)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_experiment_layer.add_child(backdrop)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, OUTER_MARGIN)
	_experiment_layer.add_child(margin)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override(&"separation", COLUMN_GAP)
	margin.add_child(columns)

	columns.add_child(_build_menu())
	columns.add_child(_build_sim_window())

	_ensure_experiment_cube_built()
	_update_sim_camera()


func _build_menu() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = MENU_WIDTH
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override(&"panel", _box(Color(RetroWindow.PANEL), 2, HARD_SHADOW, 12))

	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 8)
	panel.add_child(col)

	# Header: back + title
	var header := HBoxContainer.new()
	header.add_theme_constant_override(&"separation", 10)
	col.add_child(header)

	var back := _button("← BACK")
	back.pressed.connect(func() -> void: set_open(false))
	header.add_child(back)

	var title := UIStyle.label("ML EXPERIMENTS", UIStyle.SIZE_TITLE, UIStyle.TEXT_PRIMARY, UIStyle.WEIGHT_HEAVY)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header.add_child(title)

	col.add_child(_muted_caption("Stage %d/%d · %s" % [ACTIVE_STAGE + 1, STAGES.size(), STAGES[ACTIVE_STAGE]]))

	# Pinned live metrics
	var metrics := HBoxContainer.new()
	metrics.add_theme_constant_override(&"separation", 8)
	col.add_child(metrics)

	var pb_card := _metric_card("P(BREAK)")
	_experiment_model_label = pb_card.value_label
	pb_card.node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	metrics.add_child(pb_card.node)

	var ts_card := _metric_card("SUCCESS")
	_experiment_success_label = ts_card.value_label
	ts_card.node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	metrics.add_child(ts_card.node)

	# Tabs
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override(&"separation", 6)
	col.add_child(tabs)

	var group := ButtonGroup.new()
	var model_tab := _button("MODEL", true)
	model_tab.button_group = group
	model_tab.button_pressed = true
	model_tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.add_child(model_tab)

	var sweep_tab := _button("SWEEP", true)
	sweep_tab.button_group = group
	sweep_tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.add_child(sweep_tab)

	# Scrolling page area
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(scroll)

	var pages := VBoxContainer.new()
	pages.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(pages)

	var model_page := VBoxContainer.new()
	model_page.add_theme_constant_override(&"separation", 6)
	pages.add_child(model_page)

	var sweep_page := VBoxContainer.new()
	sweep_page.add_theme_constant_override(&"separation", 6)
	sweep_page.visible = false
	pages.add_child(sweep_page)

	model_tab.pressed.connect(func() -> void:
		model_page.visible = true
		sweep_page.visible = false
	)
	sweep_tab.pressed.connect(func() -> void:
		model_page.visible = false
		sweep_page.visible = true
	)

	var sliders := _build_model_page(model_page)
	_build_sweep_page(sweep_page, sliders)

	return panel


## Returns the slider set so the sweep page can read them.
func _build_model_page(page: VBoxContainer) -> Dictionary:
	page.add_child(_muted_caption("P(break) = σ(w₁·Δspeed + w₂·angle + w₃·stamina + b)\nSuccess = 1 − P(break)"))

	_experiment_z_label = _muted_caption("")
	page.add_child(_experiment_z_label)

	page.add_child(_section_heading("Inputs"))
	var dspeed := _slider_row(page, "Δspeed", -2.0, 4.0, 0.1, 0.7)
	var angle := _slider_row(page, "Angle", -2.0, 2.0, 0.1, 0.7)
	var stamina := _slider_row(page, "Stamina", 0.0, 2.0, 0.1, 0.7)

	page.add_child(_section_heading("Weights"))
	var w1 := _slider_row(page, "w₁ speed", 0.0, 12.0, 0.5, 6.0)
	var w2 := _slider_row(page, "w₂ angle", 0.0, 8.0, 0.2, 4.0)
	var w3 := _slider_row(page, "w₃ stamina", 0.0, 6.0, 0.2, 2.0)
	var bias := _slider_row(page, "b bias", -10.0, 2.0, 0.2, -5.6)

	var m = TackleModelScript.new()
	var recompute := func() -> void:
		m.w_speed = w1.value
		m.w_angle = w2.value
		m.w_stamina = w3.value
		m.bias = bias.value
		var z: float = m.score(dspeed.value, angle.value, stamina.value)
		var p: float = TackleModelScript.sigmoid(z)
		_experiment_model_label.text = "%.2f%%" % (p * 100.0)
		_experiment_success_label.text = "%.2f%%" % ((1.0 - p) * 100.0)
		_experiment_z_label.text = "z = %.2f" % z
		_experiment_w2 = w2.value

	for s in [dspeed, angle, stamina, w1, w2, w3, bias]:
		s.value_changed.connect(func(_v): recompute.call())
	recompute.call()

	return {"dspeed": dspeed, "angle": angle, "stamina": stamina, "w1": w1, "w2": w2, "w3": w3, "bias": bias}


func _build_sweep_page(page: VBoxContainer, s: Dictionary) -> void:
	page.add_child(_section_heading("Experiment 01 · sweep weight"))

	var weight_pick := OptionButton.new()
	weight_pick.add_item("Sweep w₂ (angle)")
	weight_pick.add_item("Sweep w₁ (speed)")
	weight_pick.add_item("Sweep w₃ (stamina)")
	weight_pick.add_item("Sweep b (bias)")
	page.add_child(weight_pick)

	var run_row := HBoxContainer.new()
	run_row.add_theme_constant_override(&"separation", 8)
	page.add_child(run_row)

	var attempts := OptionButton.new()
	attempts.add_item("100 each", 100)
	attempts.add_item("1,000 each", 1000)
	attempts.add_item("10,000 each", 10000)
	attempts.select(1)
	attempts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	run_row.add_child(attempts)

	var seed := OptionButton.new()
	for n in range(1, 11):
		seed.add_item("Seed %d" % n, n)
	seed.select(0)
	seed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	run_row.add_child(seed)

	var run_sweep := func() -> void:
		_experiment_seed = seed.get_selected_id()
		var pick: Dictionary = SWEEP_WEIGHTS[weight_pick.selected]
		_run_tackle_experiment(
			{"dspeed": s.dspeed.value, "angle": s.angle.value, "stamina": s.stamina.value},
			{"w_speed": s.w1.value, "w_angle": s.w2.value, "w_stamina": s.w3.value, "bias": s.bias.value},
			attempts.get_selected_id(),
			pick.key,
			pick.name
		)

	weight_pick.item_selected.connect(func(_i: int) -> void: run_sweep.call())
	seed.item_selected.connect(func(_i: int) -> void: run_sweep.call())

	var run := _button("RUN")
	run.pressed.connect(run_sweep)
	
	var ten := _button("10 SEEDS")
	ten.pressed.connect(func() -> void:
		var m = TackleModelScript.new()
		m.w_speed = s.w1.value
		m.w_angle = s.w2.value
		m.w_stamina = s.w3.value
		m.bias = s.bias.value
		var counts := []
		for sd in range(1, 11):
			var rng := RandomNumberGenerator.new()
			rng.seed = sd
			var n := 0
			for i in 1000:
				if m.roll_break(rng, s.dspeed.value, s.angle.value, s.stamina.value):
					n += 1
			counts.append(n)
		var total := 0.0
		for c in counts:
			total += c
		var mean: float = total / counts.size()
		var ss := 0.0
		for c in counts:
			ss += (c - mean) * (c - mean)
		var sd_val := sqrt(ss / (counts.size() - 1))
		_experiment_results.text = "10 SEEDS · 1,000 trials each\ncounts: %s\nmean %.1f   SD %.1f" % [str(counts), mean, sd_val]
	)
	var action_row := HBoxContainer.new()
	action_row.add_theme_constant_override(&"separation", 8)
	page.add_child(action_row)
	run.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ten.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	action_row.add_child(run)
	action_row.add_child(ten)

	

	var legend := HBoxContainer.new()
	legend.add_theme_constant_override(&"separation", 14)
	page.add_child(legend)
	legend.add_child(_legend_item("Simulated", UIStyle.ACCENT))
	legend.add_child(_legend_item("Illustrative", UIStyle.TEXT_MUTED))

	_chart = TackleChartScript.new()
	if _chart.custom_minimum_size.y < 120.0:
		_chart.custom_minimum_size.y = 120.0
	page.add_child(_chart)

	_experiment_results = UIStyle.label("RESULTS\n—", UIStyle.SIZE_LABEL, UIStyle.TEXT_PRIMARY)
	page.add_child(_experiment_results)

	var summary := HBoxContainer.new()
	summary.add_theme_constant_override(&"separation", 8)
	page.add_child(summary)

	var s2_card := _metric_card("0.2 → 0.8")
	_experiment_s2_label = s2_card.value_label
	s2_card.node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	summary.add_child(s2_card.node)

	var sf_card := _metric_card("0.0 → 0.8")
	_experiment_sf_label = sf_card.value_label
	sf_card.node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	summary.add_child(sf_card.node)

	_experiment_status = _muted_caption("")
	_experiment_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(_experiment_status)

	run_sweep.call()  # last, so every label exists


func _build_sim_window() -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override(&"panel", _box(Color(RetroWindow.PANEL), 2, HARD_SHADOW, 8))

	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 6)
	panel.add_child(col)

	var bar := HBoxContainer.new()
	col.add_child(bar)
	var title := UIStyle.label("SIM · X Y Z FIELD", UIStyle.SIZE_LABEL, UIStyle.TEXT_PRIMARY, UIStyle.WEIGHT_BOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(title)
	bar.add_child(_muted_caption("DRAG: ORBIT · WHEEL: ZOOM"))

	# The SubViewport shares the main World3D (own_world_3d stays false), so the
	# player already in the scene shows up here, seen by a separate camera.
	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	svc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	svc.mouse_filter = Control.MOUSE_FILTER_STOP
	svc.gui_input.connect(_on_sim_input)
	col.add_child(svc)

	var frame := StyleBoxFlat.new()  # inset border around the viewport
	frame.bg_color = Color(0, 0, 0, 0)
	frame.border_color = RetroWindow.BORDER
	frame.set_border_width_all(2)

	var sub := SubViewport.new()
	sub.name = "SimViewport"
	sub.handle_input_locally = false
	sub.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	svc.add_child(sub)

	_sim_camera = Camera3D.new()
	_sim_camera.name = "SimCamera"
	_sim_camera.fov = 45.0
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = COLOR_SIM_BG
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.85, 0.85, 0.9)
	env.ambient_light_energy = 0.7
	_sim_camera.environment = env
	sub.add_child(_sim_camera)
	_sim_camera.current = true

	# Border drawn on top of the viewport
	var border := Panel.new()
	border.set_anchors_preset(Control.PRESET_FULL_RECT)
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	border.add_theme_stylebox_override(&"panel", frame)
	svc.add_child(border)

	return panel


# =============================================================================
# SIM CAMERA / CUBE
# =============================================================================

func _sim_target() -> Vector3:
	return _viewer.STAND_ON + Vector3(0.0, CUBE_SIZE * 0.5, 0.0)


func _update_sim_camera() -> void:
	if _sim_camera == null or not _sim_camera.is_inside_tree():
		return
	var offset := Vector3(
		cos(_sim_pitch) * sin(_sim_yaw),
		sin(_sim_pitch),
		cos(_sim_pitch) * cos(_sim_yaw)
	) * _sim_dist
	_sim_camera.look_at_from_position(_sim_target() + offset, _sim_target(), Vector3.UP)


func _on_sim_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		_sim_yaw -= event.relative.x * 0.01
		_sim_pitch = clampf(_sim_pitch + event.relative.y * 0.01, -0.2, 1.4)
		_update_sim_camera()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_sim_dist = clampf(_sim_dist - 0.3, SIM_DIST_MIN, SIM_DIST_MAX)
			_update_sim_camera()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_sim_dist = clampf(_sim_dist + 0.3, SIM_DIST_MIN, SIM_DIST_MAX)
			_update_sim_camera()


func _ensure_experiment_cube_built() -> void:
	if _experiment_cube != null:
		return

	var s := CUBE_SIZE
	var h := s * 0.5
	var verts := PackedVector3Array()
	var colors := PackedColorArray()

	var add_line := func(a: Vector3, b: Vector3, c: Color) -> void:
		verts.append(a)
		verts.append(b)
		colors.append(c)
		colors.append(c)

	var corner := func(i: int) -> Vector3:
		return Vector3(
			h if (i & 1) != 0 else -h,
			s if (i & 2) != 0 else 0.0,
			h if (i & 4) != 0 else -h
		)

	# 12 cube edges
	for i in 8:
		for bit in [1, 2, 4]:
			if (i & bit) == 0:
				add_line.call(corner.call(i), corner.call(i | bit), COLOR_EDGE)

	# Floor grid
	var steps := int(round(s / CUBE_TICK_STEP))
	for k in range(1, steps):
		var t := -h + k * CUBE_TICK_STEP
		add_line.call(Vector3(t, 0, -h), Vector3(t, 0, h), COLOR_GRID)
		add_line.call(Vector3(-h, 0, t), Vector3(h, 0, t), COLOR_GRID)

	# Axes from the min corner, poking slightly past the cube, with ticks
	var o := Vector3(-h, 0.0, -h)
	var ext := 0.4
	add_line.call(o, o + Vector3(s + ext, 0, 0), COLOR_AXIS_X)
	add_line.call(o, o + Vector3(0, s + ext, 0), COLOR_AXIS_Y)
	add_line.call(o, o + Vector3(0, 0, s + ext), COLOR_AXIS_Z)
	for k in range(1, steps + 1):
		var d := k * CUBE_TICK_STEP
		add_line.call(o + Vector3(d, 0, 0), o + Vector3(d, 0.07, 0), COLOR_AXIS_X)
		add_line.call(o + Vector3(0, d, 0), o + Vector3(0.07, d, 0), COLOR_AXIS_Y)
		add_line.call(o + Vector3(0, 0, d), o + Vector3(0.07, 0, d), COLOR_AXIS_Z)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat

	_experiment_cube = Node3D.new()
	_experiment_cube.name = "ExperimentCube"
	_experiment_cube.visible = false
	_experiment_cube.add_child(mi)
	_experiment_cube.add_child(_axis_label("X", o + Vector3(s + ext + 0.12, 0, 0), COLOR_AXIS_X))
	_experiment_cube.add_child(_axis_label("Y", o + Vector3(0, s + ext + 0.12, 0), COLOR_AXIS_Y))
	_experiment_cube.add_child(_axis_label("Z", o + Vector3(0, 0, s + ext + 0.12), COLOR_AXIS_Z))

	_viewer.add_child(_experiment_cube)
	_experiment_cube.global_position = _viewer.STAND_ON


func _axis_label(text: String, pos: Vector3, color: Color) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.position = pos
	l.modulate = color
	l.font_size = 64
	l.pixel_size = 0.005
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.shaded = false
	return l


# =============================================================================
# OPEN / CLOSE
# =============================================================================

## Toggled callback target — wire the CONTROL group's EXPERIMENTS button
## straight to this from AnimationViewer._build_control_group.
func on_toggled(on: bool) -> void:
	set_open(on)


func set_open(open: bool) -> void:
	_experiment_open = open
	if _experiment_layer_tween != null and _experiment_layer_tween.is_valid():
		_experiment_layer_tween.kill()

	var hidden_x := maxf(0.0, _viewer.get_viewport().get_visible_rect().size.x)
	var shown_x := 0.0

	if open:
		_viewer.show_single_subject()
		_viewer.move_camera_to(
			_viewer.STAND_ON + Vector3(-EXPERIMENT_CAMERA_SIDESTEP, EXPERIMENT_CAMERA_HEIGHT, EXPERIMENT_CAMERA_DISTANCE)
		)
		_ensure_experiment_cube_built()
		_experiment_cube.visible = true
		_update_sim_camera()
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


# =============================================================================
# EXPERIMENT LOGIC
# =============================================================================

func _run_tackle_experiment(inputs: Dictionary, weights: Dictionary, attempts: int, sweep_key: String, sweep_name: String) -> void:
	var model = TackleModelScript.new()
	for key in weights:
		model.set(key, weights[key])

	var rows: Array = TackleExperimentScript.sweep(model, sweep_key, SWEEP_VALUES, inputs, attempts, _experiment_seed)

	var text := "RESULTS · sweep %s\n" % sweep_name
	var plot_points: Array[Vector2] = []
	for row in rows:
		text += "%s %.1f  %.1f%%  [%d/%d]\n" % [sweep_name, row.value, row.rate, row.successes, row.attempts]
		plot_points.append(Vector2(row.value, row.rate))
	_experiment_results.text = text

	_experiment_s2_label.text = "%.1f pp/u" % _slope_between(rows, 0.2, 0.8)
	_experiment_sf_label.text = "%.1f pp/u" % _slope_between(rows, 0.0, 0.8)

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


# =============================================================================
# STYLE HELPERS
# =============================================================================

## Flat fill, hard border, square corners, optional hard offset shadow.
func _box(fill: Color, border_w: int, shadow: float, margin: float) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fill
	s.border_color = RetroWindow.BORDER
	s.set_border_width_all(border_w)
	s.set_corner_radius_all(0)
	s.content_margin_left = margin
	s.content_margin_right = margin
	s.content_margin_top = margin
	s.content_margin_bottom = margin
	if shadow > 0.0:
		s.shadow_color = Color(0, 0, 0, 0.55)
		s.shadow_size = 1
		s.shadow_offset = Vector2(shadow, shadow)
	return s


func _button(text: String, toggle := false) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = toggle
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size.y = 30.0

	var base := Color(RetroWindow.PANEL)
	b.add_theme_stylebox_override(&"normal", _box(base.lightened(0.08), 2, 3.0, 8.0))
	b.add_theme_stylebox_override(&"hover", _box(base.lightened(0.18), 2, 3.0, 8.0))
	b.add_theme_stylebox_override(&"pressed", _box(Color(UIStyle.ACCENT), 2, 0.0, 8.0))
	b.add_theme_stylebox_override(&"hover_pressed", _box(Color(UIStyle.ACCENT), 2, 0.0, 8.0))
	b.add_theme_stylebox_override(&"focus", StyleBoxEmpty.new())
	b.add_theme_font_size_override(&"font_size", UIStyle.SIZE_LABEL)
	b.add_theme_color_override(&"font_color", UIStyle.TEXT_PRIMARY)
	b.add_theme_color_override(&"font_hover_color", UIStyle.TEXT_PRIMARY)
	b.add_theme_color_override(&"font_pressed_color", Color.BLACK)
	b.add_theme_color_override(&"font_hover_pressed_color", Color.BLACK)
	return b


func _metric_card(caption: String) -> Dictionary:
	var box := PanelContainer.new()
	# Sunken look: darker fill, thin border, no shadow.
	box.add_theme_stylebox_override(&"panel", _box(Color(RetroWindow.PANEL).darkened(0.18), 2, 0.0, 8.0))

	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 0)
	box.add_child(col)

	col.add_child(UIStyle.label(caption, UIStyle.SIZE_LABEL, UIStyle.TEXT_MUTED))
	var value := UIStyle.label("—", UIStyle.SIZE_TITLE, UIStyle.TEXT_PRIMARY, UIStyle.WEIGHT_BOLD)
	col.add_child(value)

	return {"node": box, "value_label": value}


func _section_heading(text: String) -> Label:
	return UIStyle.label(text.to_upper(), UIStyle.SIZE_LABEL, UIStyle.TEXT_MUTED, UIStyle.WEIGHT_BOLD)


func _muted_caption(text: String) -> Label:
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


func _slider_row(parent: Control, label_text: String, min_v: float, max_v: float, step: float, default: float) -> HSlider:
	var row := GridContainer.new()
	row.columns = 3
	row.add_theme_constant_override(&"h_separation", 8)
	parent.add_child(row)

	var label := UIStyle.label(label_text, UIStyle.SIZE_LABEL, UIStyle.TEXT_MUTED)
	label.custom_minimum_size.x = 70.0
	row.add_child(label)

	var slider := HSlider.new()
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step = step
	slider.value = default
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(slider)

	var out := UIStyle.label("%.2f" % default, UIStyle.SIZE_LABEL, UIStyle.TEXT_PRIMARY)
	out.custom_minimum_size.x = 40.0
	out.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(out)

	slider.value_changed.connect(func(v: float) -> void:
		out.text = "%.2f" % v
	)

	return slider


func _spinbox_row(parent: Control, label_text: String, min_v: int, max_v: int, step: int, default: int) -> SpinBox:
	var row := GridContainer.new()
	row.columns = 3
	row.add_theme_constant_override(&"h_separation", 8)
	parent.add_child(row)

	var label := UIStyle.label(label_text, UIStyle.SIZE_LABEL, UIStyle.TEXT_MUTED)
	label.custom_minimum_size.x = 70.0
	row.add_child(label)

	var box := SpinBox.new()
	box.min_value = float(min_v)
	box.max_value = float(max_v)
	box.step = float(step)
	box.value = float(default)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(box)

	var out := UIStyle.label("%d" % default, UIStyle.SIZE_LABEL, UIStyle.TEXT_PRIMARY)
	out.custom_minimum_size.x = 40.0
	out.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(out)

	box.value_changed.connect(func(v: float) -> void:
		out.text = "%d" % int(v)
	)

	return box
