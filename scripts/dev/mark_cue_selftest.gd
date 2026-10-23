# scripts/dev/mark_cue_selftest.gd
extends Node
## Headless check for MarkCueModel / MarkCueTrainer (the ML page's MLP
## stage). A scene, not a --script SceneTree like tackle_ga_selftest.gd:
## MarkCueModel type-references PlayerController, which needs the
## autoloads a --script run doesn't load. Run with:
##   godot --headless --path . res://scenes/dev/mark_cue_selftest.tscn --fixed-fps 60
##   godot --headless --path . res://scenes/dev/mark_cue_selftest.tscn --fixed-fps 60 -- train
## `train` also writes the trained weights (MarkCueModel.weights_path) —
## the files MarkPrompt / AIBrain / the viewer load when their MLP switch
## is on. The plain run trains and reports without touching them.
##
## Checks, in order:
##  1. backprop matches a numerical gradient (central differences);
##  2. the net can fit a known smooth function of its five inputs;
##  3. the same seed reproduces the same weights bit for bit;
##  4. on the real dataset, per tier: validation and probe-grid cue error
##     and in-band rate, model vs the analytic ring, broken down by region.

var _failures := 0


func _ready() -> void:
	var save := "train" in OS.get_cmdline_user_args()
	var checks := MarkCueTrainer.self_checks()
	for i in checks.lines.size():
		print("%d. %s" % [i + 1, checks.lines[i]])
	_failures += int(checks.failures)
	var trainer := MarkCueTrainer.new()
	if not trainer.load_data():
		_fail("no dataset under %s — run mark_cue_harness.tscn -- dataset first" % MarkCueTrainer.DATA_DIR)
	else:
		print("dataset: %d deliveries, %d attempts (%d aggressive, %d running rule checks), %d caught; probe grid %d deliveries" % [
			trainer.deliveries.size(), trainer.attempt_summary.attempts, trainer.attempt_summary.aggressive,
			trainer.attempt_summary.rule_checks, trainer.attempt_summary.caught, trainer.probe_deliveries.size()])
		for tier in [Tuning.Action.MARK_AGGRESSIVE, Tuning.Action.MARK_RUNNING]:
			_train_and_report(trainer, tier, save)
		_seed_sweep(trainer)
	print("SELFTEST %s (%d failure%s)" % ["PASS" if _failures == 0 else "FAIL", _failures, "" if _failures == 1 else "s"])
	get_tree().quit(1 if _failures > 0 else 0)


func _fail(msg: String) -> void:
	_failures += 1
	print("  FAIL: " + msg)


func _train_and_report(trainer: MarkCueTrainer, tier: Tuning.Action, save: bool) -> void:
	var t0 := Time.get_ticks_msec()
	var params := MarkCueTrainer.default_params()
	params.tier = tier
	var r := trainer.run(params)
	var model: MarkCueModel = r.best_model
	var ev := trainer.evaluate(model, r)
	var name: String = Tuning.Action.keys()[tier]
	print("4. %s: %d train / %d val deliveries, %d / %d rows, best val MSE %.4f at epoch %d of %d (%.1f s)" % [
		name, r.train_ids.size(), r.val_ids.size(), r.train_rows.size(), r.val_rows.size(),
		r.best_val, model.meta.best_epoch, r.epoch, (Time.get_ticks_msec() - t0) / 1000.0])
	var vr: Dictionary = ev.val_rows
	print("   val rows (last 1.0 s of countdown): MAE mlp %.3f s vs analytic %.3f s over %d rows (%d rows with no analytic reading)" % [
		vr.mlp_mae, vr.analytic_mae, vr.rows, vr.no_reading])
	for key in ["train_cues", "val_cues", "probe_cues"]:
		if not ev.has(key):
			continue
		var c: Dictionary = ev[key]
		print("   %-6s cue (mlp / analytic / gated analytic): in band %d / %d / %d of %d | MAE %.3f / %.3f / %.3f s | bias %+.3f / %+.3f / %+.3f | worst %.3f / %.3f / %.3f" % [
			key.trim_suffix("_cues"), c.mlp_in, c.analytic_in, c.gated_in, c.n, c.mlp_mae, c.analytic_mae, c.gated_mae,
			c.mlp_bias, c.analytic_bias, c.gated_bias, c.mlp_worst, c.analytic_worst, c.gated_worst])
	if ev.has("probe_regions"):
		for reg in ev.probe_regions:
			print("     probe %-24s n=%2d  in band %2d / %2d / %2d | MAE %.3f / %.3f / %.3f" % [
				reg.name, reg.n, reg.mlp_in, reg.analytic_in, reg.gated_in, reg.mlp_mae, reg.analytic_mae, reg.gated_mae])
		print("     probe deliveries with no catching press at all: %d" % ev.probe_uncatchable)
	for key in ["val_leads", "probe_leads"]:
		if not ev.has(key):
			continue
		var s := "   %s row MAE by time to best press (mlp / analytic):" % key.trim_suffix("_leads")
		for b in ev[key]:
			s += "  %.2f-%.2f s: %.3f / %.3f (n=%d)" % [b.from, b.to, b.mlp_mae, b.analytic_mae, b.n]
		print(s)
	if ev.has("axes"):
		var s := "   axis swing (s):"
		for a in ev.axes:
			s += "  %s %.2f" % [a.name, a.swing]
		print(s)
	if save:
		var err := model.save()
		print("   saved %s (%s)" % [MarkCueModel.weights_path(tier), error_string(err)])


## 5. ML_AI_AUDIT §7's other lesson: a result from one seed can be seed
## noise. Re-trains Aggressive on seeds 1-5 (each re-draws the validation
## split and the initial weights) and reports the spread of the probe-grid
## cue numbers, which don't depend on the split.
func _seed_sweep(trainer: MarkCueTrainer) -> void:
	var line := "5. AGGRESSIVE seed sweep (probe cue, mlp): "
	var worst_in := 999
	for seed in range(1, 6):
		var params := MarkCueTrainer.default_params()
		params.seed = seed
		var r := trainer.run(params)
		var ev := trainer.evaluate(r.best_model, r)
		if not ev.has("probe_cues"):
			print("5. seed sweep skipped: no probe grid yet (mark_cue_harness.tscn -- probe)")
			return
		var c: Dictionary = ev.probe_cues
		line += " seed %d: in band %d/%d MAE %.3f |" % [seed, c.mlp_in, c.n, c.mlp_mae]
		worst_in = mini(worst_in, c.mlp_in)
	print(line)
	if worst_in < 20:
		_fail("a seed's probe in-band count fell below 20 — the result depends on the seed")
