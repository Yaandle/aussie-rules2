class_name MLExperimentViewer
extends RefCounted

## Split out of animation_viewer.gd: the ML Experiments page — stage tabs
## LR (tackle-break-probability model + sweep), GA (evolving that model's
## weights), MLP (marking-cue timing, MarkCueModel) and DQL (queued).
##
## Layout: a narrow control column on the left (pinned metrics + MODEL / SWEEP
## tabs) and a SIM window on the right showing the player inside an X/Y/Z
## wireframe cube. No .tscn needed; everything is built in code and hosted by
## animation_viewer.tscn / animation_viewer.gd.
##
## Talks back to the AnimationViewer only for things it can't do itself:
## single-subject framing, camera moves, and floor/root-layout visibility.

const STAGES := ["Logistic regression", "Genetic algorithm", "MLP", "Deep Q-learning"]
const STAGE_SHORT_NAMES := ["LR", "GA", "MLP", "DQL"]
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
const TackleGAScript := preload("res://scripts/dev/tackle_ga.gd")
const GAFitnessChartScript := preload("res://scripts/dev/ga_fitness_chart.gd")
const MLPLossChartScript := preload("res://scripts/dev/mlp_loss_chart.gd")

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
var _lr_sliders: Dictionary = {}   ## MODEL page's slider set — Stage 2's APPLY TO MODEL writes into this
var _ga_last_result: Dictionary = {}
var _mlp_training := false   ## MLP stage TRAIN in progress (it spans frames)

var _sim_camera: Camera3D
var _sim_yaw := 0.7
var _sim_pitch := 0.35
var _sim_dist := 5.2


func _init(viewer: AnimationViewer) -> void:
	_viewer = viewer


func is_open() -> bool:
	return _experiment_open


## The MODEL page's current dialled-in weights (w1/w2/w3/bias), as a
## fresh TackleModel instance — read by AnimationViewer's CONTESTS
## simulation (_tackle_model_z_for_inputs/_tackle_model_p_for_inputs/
## _compute_tackle_model_prediction) so dialling a weight in, or hitting
## Stage 2's APPLY TO MODEL after a GA run, actually changes what the
## live two-body contest predicts and rolls — previously those always
## built a fresh default-weight TackleModel of their own and silently
## ignored this page entirely, so nothing dialled in here (by hand or by
## the GA) ever reached the simulation it looked like it was feeding.
## Falls back to class defaults if asked before build() has run.
func get_active_model() -> TackleModel:
	var m := TackleModelScript.new()
	if _lr_sliders.is_empty():
		return m
	m.w_speed = _lr_sliders.w1.value
	m.w_angle = _lr_sliders.w2.value
	m.w_stamina = _lr_sliders.w3.value
	m.bias = _lr_sliders.bias.value
	return m


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

	# Stage bookmarks — one per STAGES entry, switches which stage page
	# below is visible. Previously a static "Stage 1/4 · Logistic
	# regression" caption with ACTIVE_STAGE hardcoded to 0; now a real
	# toggle so Stage 2's GA page (and the Stage 3/4 placeholders) are
	# actually reachable, not just named.
	var bookmarks := HBoxContainer.new()
	bookmarks.add_theme_constant_override(&"separation", 4)
	col.add_child(bookmarks)

	var stage_container := VBoxContainer.new()
	stage_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(stage_container)

	var stage_pages: Array[Control] = [
		_build_lr_stage(),
		_build_ga_stage(),
		_build_mlp_stage(),
		_build_placeholder_stage("Deep Q-learning", "team positioning",
			"State: ball, teammates, opponents, possession.\nReward: marks + territory.\nRisk: reward hacking — e.g. farming safe handballs forever instead of\nrisking a scoring chance.\n\nNot built yet — see docs/ML_AI_AUDIT.md §4: ai_brain.gd's\n_think_support/_think_defend still use one global pull scalar plus a\nnearest-teammate spacing nudge, no real zone/role awareness."),
	]
	for i in stage_pages.size():
		stage_container.add_child(stage_pages[i])
		stage_pages[i].visible = (i == 0)

	var stage_group := ButtonGroup.new()
	for i in STAGES.size():
		var bm := _button(STAGE_SHORT_NAMES[i], true)
		bm.button_group = stage_group
		bm.button_pressed = (i == 0)
		bm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bm.tooltip_text = STAGES[i]
		var idx := i
		bm.pressed.connect(func() -> void:
			for j in stage_pages.size():
				stage_pages[j].visible = (j == idx)
		)
		bookmarks.add_child(bm)

	return panel


## Stage 1 (logistic regression) — unchanged behaviour from before the
## bookmark rework, just in its own container now instead of living
## directly in _build_menu().
func _build_lr_stage() -> Control:
	var stage := VBoxContainer.new()
	stage.add_theme_constant_override(&"separation", 8)
	# Without this, `stage` sizes to its own minimum inside stage_container
	# — and a ScrollContainer's minimum height is deliberately tiny (that's
	# the whole point of scrolling), so every slider row below it collapses
	# to invisible. stage_container already expands; this is what lets the
	# page actually use that space.
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL

	# Pinned live metrics
	var metrics := HBoxContainer.new()
	metrics.add_theme_constant_override(&"separation", 8)
	stage.add_child(metrics)

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
	stage.add_child(tabs)

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
	stage.add_child(scroll)

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

	_lr_sliders = _build_model_page(model_page)
	_build_sweep_page(sweep_page, _lr_sliders)

	return stage


## Stage 2 (genetic algorithm, docs/ML_AI_AUDIT.md §5) — evolves
## TackleModel's w_speed/w_angle/w_stamina (bias held fixed) against the
## fitness in scripts/dev/tackle_ga.gd: close to a target tackle-success
## rate while staying meaningfully sensitive across the input range ("no
## dominant strategy" per the brief). Fitness is the exact closed-form
## P(BREAK) curve, not a stochastic sim — VERIFY below is the stochastic
## sanity check on the winning genome, same "10 SEEDS" idea the SWEEP
## page already uses.
func _build_ga_stage() -> Control:
	var stage := VBoxContainer.new()
	stage.add_theme_constant_override(&"separation", 8)
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL   # see _build_lr_stage()'s comment

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.add_child(scroll)

	var page := VBoxContainer.new()
	page.add_theme_constant_override(&"separation", 6)
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(page)

	page.add_child(_muted_caption("Genome: w_speed, w_angle, w_stamina (bias fixed). Scored against a fixed 5-point scenario ladder, not one input."))

	page.add_child(_section_heading("Parameters"))
	var pop_box := _spinbox_row(page, "Population", 10, 200, 10, 40)
	var gen_box := _spinbox_row(page, "Generations", 10, 300, 10, 40)
	var mutation_rate := _slider_row(page, "Mut. rate", 0.0, 1.0, 0.01, 0.15)
	var mutation_strength := _slider_row(page, "Mut. size", 0.0, 0.5, 0.01, 0.12)
	var elite_box := _spinbox_row(page, "Elites", 0, 10, 1, 2)
	var target_success := _slider_row(page, "Target %", 0.0, 1.0, 0.01, 0.55)

	var seed := OptionButton.new()
	for n in range(1, 11):
		seed.add_item("Seed %d" % n, n)
	seed.select(0)
	page.add_child(seed)

	var run := _button("RUN GA")
	page.add_child(run)

	var status := _muted_caption("")
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(status)

	var chart = GAFitnessChartScript.new()
	page.add_child(chart)

	page.add_child(_section_heading("Best genome"))
	var genome_label := UIStyle.label("—", UIStyle.SIZE_LABEL, UIStyle.TEXT_PRIMARY)
	page.add_child(genome_label)

	var metrics_row := HBoxContainer.new()
	metrics_row.add_theme_constant_override(&"separation", 8)
	page.add_child(metrics_row)
	var score_card := _metric_card("FITNESS")
	score_card.node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	metrics_row.add_child(score_card.node)
	var success_card := _metric_card("SUCCESS")
	success_card.node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	metrics_row.add_child(success_card.node)

	var ladder_label := UIStyle.label("—", UIStyle.SIZE_LABEL, UIStyle.TEXT_MUTED)
	ladder_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(ladder_label)

	var action_row := HBoxContainer.new()
	action_row.add_theme_constant_override(&"separation", 8)
	page.add_child(action_row)
	var apply_button := _button("APPLY TO MODEL")
	apply_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	apply_button.disabled = true
	action_row.add_child(apply_button)
	var verify_button := _button("VERIFY (1000)")
	verify_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	verify_button.disabled = true
	action_row.add_child(verify_button)

	var verify_label := _muted_caption("")
	verify_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(verify_label)

	run.pressed.connect(func() -> void:
		status.text = "Running..."
		var params := {
			"population_size": int(pop_box.value),
			"generations": int(gen_box.value),
			"mutation_rate": mutation_rate.value,
			"mutation_strength": mutation_strength.value,
			"elite_count": int(elite_box.value),
			"target_success": target_success.value,
			"seed": seed.get_selected_id(),
		}
		var result: Dictionary = TackleGAScript.run(params)
		_ga_last_result = result
		var best: Dictionary = result.best_genome
		var f: Dictionary = result.best_fitness

		genome_label.text = "w_speed=%.2f   w_angle=%.2f   w_stamina=%.2f" % [best.w_speed, best.w_angle, best.w_stamina]
		score_card.value_label.text = "%.3f" % f.score
		success_card.value_label.text = "%.1f%%" % (f.mean_success * 100.0)

		var ladder_text := "LADDER (all 3 inputs move together): "
		for i in TackleGAScript.LADDER.size():
			ladder_text += "%s %.1f%%   " % [TackleGAScript.LADDER[i].name, f.p_breaks[i] * 100.0]
		ladder_text += "\nPER-AXIS swing (other two held at midpoint): dspeed %.2f   angle %.2f   stamina %.2f" % [
			f.axis_spreads.dspeed, f.axis_spreads.angle, f.axis_spreads.stamina]
		ladder_label.text = ladder_text

		status.text = "%d generations · pop %d · target %.0f%% success · balance %.2f · ladder sensitivity %.2f · axis sensitivity %.2f (worst of the 3)" % [
			params.generations, params.population_size, params.target_success * 100.0,
			f.balance_score, f.sensitivity_score, f.axis_sensitivity_score]

		chart.set_history(result.history)
		apply_button.disabled = false
		verify_button.disabled = false
		verify_label.text = ""
	)

	apply_button.pressed.connect(func() -> void:
		if _ga_last_result.is_empty() or _lr_sliders.is_empty():
			return
		var best: Dictionary = _ga_last_result.best_genome
		_lr_sliders.w1.value = best.w_speed
		_lr_sliders.w2.value = best.w_angle
		_lr_sliders.w3.value = best.w_stamina
	)

	verify_button.pressed.connect(func() -> void:
		if _ga_last_result.is_empty():
			return
		var best: Dictionary = _ga_last_result.best_genome
		var m = TackleModelScript.new()
		m.w_speed = best.w_speed
		m.w_angle = best.w_angle
		m.w_stamina = best.w_stamina
		m.bias = TackleGAScript.default_bias()
		var scenario: Dictionary = TackleGAScript.LADDER[2]   # "baseline"
		var rng := RandomNumberGenerator.new()
		rng.seed = 1
		var breaks := 0
		for _i in 1000:
			if m.roll_break(rng, scenario.dspeed, scenario.angle, scenario.stamina):
				breaks += 1
		var predicted := m.p_break(scenario.dspeed, scenario.angle, scenario.stamina) * 100.0
		verify_label.text = "1000 stochastic trials at '%s': %.1f%% broke (formula predicts %.1f%%)" % [
			scenario.name, breaks / 10.0, predicted]
	)

	return stage


## Stage 3 (MLP, docs/ML_AI_AUDIT.md §9) — MarkCueModel, a 5 → 8 → 8 → 1
## net that predicts seconds until the best press of a mark (when, never
## whether), trained on real attempts recorded by scenes/dev/
## mark_cue_harness.tscn. TRAIN runs across frames so the loss chart fills
## in live, and keeps the best-validation epoch's weights. The cards and
## lines below compare the model against the analytic ring (as shipped) and
## the analytic ring plus the press gate, on held-out deliveries and on the
## 27-delivery probe grid that walks the whole input space. The probe
## grid's closed-loop line is real presses and real signals from the
## harness's last `probe` run. APPLY makes this run the cue MARK DELIVERY's
## CUE MLP uses for the session. SAVE writes it to the weights file. Real
## matches stay on Tuning.MARK_CUE_SOURCE either way.
func _build_mlp_stage() -> Control:
	var stage := VBoxContainer.new()
	stage.add_theme_constant_override(&"separation", 8)
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL   # see _build_lr_stage()'s comment

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.add_child(scroll)

	var page := VBoxContainer.new()
	page.add_theme_constant_override(&"separation", 6)
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(page)

	page.add_child(_wrapped_caption("Marking-cue timing. Output: seconds to the best press, the catching press whose contact frame finds the ball nearest the hands. It decides WHEN to press, never whether a mark succeeds. Inputs: ball height, ball distance, player speed, analytic time to arrival, approach cos (APPROACH FROM)."))

	var trainer := MarkCueTrainer.new()
	var have_data := trainer.load_data()
	var data_label := _wrapped_caption("")
	page.add_child(data_label)
	if have_data:
		var labelled := trainer.catchable_ids(Tuning.Action.MARK_AGGRESSIVE).size()
		data_label.text = "DATA: %d deliveries, %d real attempts (%d caught). Aggressive labelled on %d; Running on %d. Probe grid: %d deliveries. Re-record: mark_cue_harness.tscn -- dataset / -- probe." % [
			trainer.deliveries.size(), trainer.attempt_summary.attempts, trainer.attempt_summary.caught,
			labelled, trainer.catchable_ids(Tuning.Action.MARK_RUNNING).size(), trainer.probe_deliveries.size()]
	else:
		data_label.text = "No dataset under %s. Run scenes/dev/mark_cue_harness.tscn -- dataset first." % MarkCueTrainer.DATA_DIR

	page.add_child(_section_heading("Parameters"))
	var tier_pick := OptionButton.new()
	tier_pick.add_item("AGGRESSIVE (leap)", Tuning.Action.MARK_AGGRESSIVE)
	tier_pick.add_item("RUNNING (tap)", Tuning.Action.MARK_RUNNING)
	page.add_child(tier_pick)
	var defaults := MarkCueTrainer.default_params()
	var epochs_box := _spinbox_row(page, "Epochs", 10, 400, 10, int(defaults.epochs))
	var lr_slider := _slider_row(page, "Learn rate", 0.001, 0.05, 0.001, float(defaults.learning_rate))
	var batch_box := _spinbox_row(page, "Batch", 8, 128, 8, int(defaults.batch_size))
	var near_slider := _slider_row(page, "Near wt", 0.0, 8.0, 0.5, float(defaults.near_weight))
	var seed_pick := OptionButton.new()
	for n in range(1, 11):
		seed_pick.add_item("Seed %d" % n, n)
	page.add_child(seed_pick)

	var action_row := HBoxContainer.new()
	action_row.add_theme_constant_override(&"separation", 8)
	page.add_child(action_row)
	var train_button := _button("TRAIN")
	train_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	train_button.disabled = not have_data
	action_row.add_child(train_button)
	var selftest_button := _button("SELF-TEST")
	selftest_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	action_row.add_child(selftest_button)

	var status := _wrapped_caption("")
	page.add_child(status)
	var chart = MLPLossChartScript.new()
	page.add_child(chart)
	page.add_child(_legend_item("train loss", UIStyle.ACCENT))
	page.add_child(_legend_item("validation loss (bar = kept epoch)", UIStyle.TEXT_MUTED))

	page.add_child(_section_heading("Held-out cue vs analytic"))
	var cards := HBoxContainer.new()
	cards.add_theme_constant_override(&"separation", 8)
	page.add_child(cards)
	var mlp_card := _metric_card("MLP CUE ERR")
	mlp_card.node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cards.add_child(mlp_card.node)
	var ana_card := _metric_card("ANALYTIC")
	ana_card.node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cards.add_child(ana_card.node)
	var results := _wrapped_caption("")
	page.add_child(results)

	page.add_child(_section_heading("Probe grid (whole input space)"))
	var probe_label := _wrapped_caption("")
	page.add_child(probe_label)
	var closed_loop := _wrapped_caption("")
	page.add_child(closed_loop)

	var apply_row := HBoxContainer.new()
	apply_row.add_theme_constant_override(&"separation", 8)
	page.add_child(apply_row)
	var apply_button := _button("APPLY TO PREVIEW")
	apply_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	apply_button.disabled = true
	apply_row.add_child(apply_button)
	var save_button := _button("SAVE WEIGHTS")
	save_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_button.disabled = true
	apply_row.add_child(save_button)
	page.add_child(_wrapped_caption("Real matches use Tuning.MARK_CUE_SOURCE = %d (0 = shipped ring). AI tier choice: Tuning.AI_MARK_USE_CUE_MODEL = %s. Neither changes without the user's say-so." % [
		Tuning.MARK_CUE_SOURCE, Tuning.AI_MARK_USE_CUE_MODEL]))

	var show_closed_loop := func(tier: Tuning.Action) -> void:
		var summary := MarkCueTrainer.closed_loop_summary()
		var key_tier: String = Tuning.Action.keys()[tier]
		var text := "CLOSED LOOP (last harness probe run, saved weights, 1 real press per delivery per cue):"
		for src in [["analytic", "shipped"], ["analytic_gated", "gated"], ["mlp", "mlp"]]:
			var s: Dictionary = summary.get(key_tier + " " + src[0], {})
			if s.is_empty():
				continue
			text += "\n  %-8s caught %d/%d, ball %.2f m from the hands at contact (mean of the %d that resolved)" % [
				src[1], s.caught, s.n, s.contact, s.resolved]
		closed_loop.text = text if not summary.is_empty() else "CLOSED LOOP: no probe_cues.csv yet (mark_cue_harness.tscn -- probe)."
	show_closed_loop.call(Tuning.Action.MARK_AGGRESSIVE)
	tier_pick.item_selected.connect(func(_i: int) -> void:
		show_closed_loop.call(tier_pick.get_selected_id()))

	var last := {}
	train_button.pressed.connect(func() -> void:
		if _mlp_training:
			return
		_mlp_training = true
		train_button.disabled = true
		apply_button.disabled = true
		save_button.disabled = true
		var params := {
			"tier": tier_pick.get_selected_id(),
			"epochs": int(epochs_box.value),
			"learning_rate": lr_slider.value,
			"batch_size": int(batch_box.value),
			"near_weight": near_slider.value,
			"seed": seed_pick.get_selected_id(),
			"stride": int(defaults.stride),
		}
		var run := trainer.begin(params)
		var t0 := Time.get_ticks_msec()
		for e in int(params.epochs):
			trainer.step_training(run)
			if e % 3 == 2 or e == int(params.epochs) - 1:
				chart.set_history(run.history, run.get("best_epoch", -1))
				status.text = "Training %s: epoch %d/%d, %d train / %d val deliveries, val MSE %.4f" % [
					Tuning.Action.keys()[params.tier], run.epoch, params.epochs, run.train_ids.size(),
					run.val_ids.size(), run.history[-1].val]
				await _viewer.get_tree().process_frame
		var model := trainer.finish(run)
		var ev := trainer.evaluate(model, run)
		last.model = model
		var vc: Dictionary = ev.val_cues
		mlp_card.value_label.text = "%.3f s" % vc.mlp_mae
		ana_card.value_label.text = "%.3f s" % vc.analytic_mae
		var text := "Kept epoch %d (best val MSE %.4f), %.1f s. Validation cue, %d deliveries: in band mlp %d / shipped %d / gated %d. Error %.3f / %.3f / %.3f s, bias %+.3f / %+.3f / %+.3f." % [
			model.meta.best_epoch, run.best_val, (Time.get_ticks_msec() - t0) / 1000.0, vc.n,
			vc.mlp_in, vc.analytic_in, vc.gated_in, vc.mlp_mae, vc.analytic_mae, vc.gated_mae,
			vc.mlp_bias, vc.analytic_bias, vc.gated_bias]
		text += "\nCountdown error by time to press (mlp / analytic):"
		for b in ev.val_leads:
			text += "  %.2f–%.2f s %.3f / %.3f" % [b.from, b.to, b.mlp_mae, b.analytic_mae]
		text += "\nAxis swing (s):"
		for a in ev.axes:
			text += "  %s %.2f" % [a.name, a.swing]
		results.text = text
		if ev.has("probe_cues"):
			var pc: Dictionary = ev.probe_cues
			var ptext := "THIS MODEL on the probe traces: in band %d / %d / %d of %d (mlp / shipped / gated), error %.3f / %.3f / %.3f s." % [
				pc.mlp_in, pc.analytic_in, pc.gated_in, pc.n, pc.mlp_mae, pc.analytic_mae, pc.gated_mae]
			for reg in ev.probe_regions:
				ptext += "\n  %s: %d / %d / %d of %d" % [reg.name, reg.mlp_in, reg.analytic_in, reg.gated_in, reg.n]
			probe_label.text = ptext
		else:
			probe_label.text = "No probe grid yet (mark_cue_harness.tscn -- probe)."
		show_closed_loop.call(params.tier)
		status.text = "Done: %s, %d epochs." % [Tuning.Action.keys()[params.tier], run.epoch]
		train_button.disabled = false
		apply_button.disabled = false
		save_button.disabled = false
		_mlp_training = false
	)

	apply_button.pressed.connect(func() -> void:
		if last.has("model"):
			MarkCueModel.set_active(last.model)
			status.text = "Applied: MARK DELIVERY's CUE MLP now uses this run (until restart or SAVE)."
	)
	save_button.pressed.connect(func() -> void:
		if last.has("model"):
			var err: Error = last.model.save()
			status.text = "Saved %s (%s)." % [MarkCueModel.weights_path(last.model.tier), error_string(err)]
	)
	selftest_button.pressed.connect(func() -> void:
		var checks := MarkCueTrainer.self_checks()
		status.text = "SELF-TEST %s\n%s" % ["PASS" if checks.failures == 0 else "FAIL", "\n".join(checks.lines)]
	)
	return stage


func _wrapped_caption(text: String) -> Label:
	var label := _muted_caption(text)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


## Stub page for a not-yet-built stage (MLP / Deep Q-learning) —
## scaffolding only, per the brief ("add in the rest of the ML stages
## infrastructure and setup"): a reachable bookmark and a description of
## what will go here, not a working experiment yet.
func _build_placeholder_stage(stage_name: String, fixes: String, body: String) -> Control:
	var stage := VBoxContainer.new()
	stage.add_theme_constant_override(&"separation", 8)
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL   # see _build_lr_stage()'s comment

	stage.add_child(_muted_caption("QUEUED"))
	stage.add_child(_section_heading(stage_name))
	stage.add_child(_muted_caption("Fixes: " + fixes))

	var body_label := UIStyle.label(body, UIStyle.SIZE_LABEL, UIStyle.TEXT_MUTED)
	body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stage.add_child(body_label)

	return stage


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
