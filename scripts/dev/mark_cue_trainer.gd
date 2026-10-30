# scripts/dev/mark_cue_trainer.gd
class_name MarkCueTrainer
extends RefCounted
## Stage 3 (MLP, docs/ML_AI_AUDIT.md §9): turns the harness's CSVs into
## training rows for MarkCueModel, trains it, and scores it against the
## analytic cue on held-out deliveries and on the probe grid.
##
## Rows: every airborne frame of a delivery's no-press trace, up to a few
## frames past its best press, with target = seconds from that frame to the
## best press: the catching press whose contact frame finds the ball
## nearest the hands. For Aggressive that's the harness's verified target
## (mark_cue_harness.gd _aggressive_label: a quadratic through the real
## attempts' contact distances, checked by one more real press — bands can
## have holes), always a frame a real attempt caught on. For Running it's
## the trace's closest approach, inside the trace band — a rule the
## harness's real taps check. A delivery with no verified catching press has no best
## press, so it contributes no rows — the model only answers "when", never
## "whether".
##
## Split is by DELIVERY, not by row: rows within one delivery are a smooth
## countdown, so a row-level split would put near-copies of every
## validation row in the training set and the validation loss would mean
## nothing.
##
## Scoring is at the cue, not just on rows. Row MAE says how good the
## countdown is on average; what the player (or the clip) actually gets is
## the one frame the cue fires on — first frame the prediction reaches the
## press instant — and whether that frame is inside the real band. Both
## are reported, for the model and the analytic ring side by side.

## The harness's CSVs (mark_cue_harness.gd DATA_DIR). The folder has a
## .gdignore so Godot doesn't import the CSVs as translations; FileAccess
## still reads it in the editor and headless runs, which is all a dev page
## needs.
const DATA_DIR := "res://data/ml/mark_cue/"
const ROW_TAIL := 0.3   ## s past the best press still included as rows (negative targets)
const NEAR_WIDTH := 0.15   ## s, see rows_for
## The three cues every result compares: the model, the analytic ring as
## shipped (MarkPrompt today), and the analytic ring with the model's
## press_registers() gate — see MarkCueModel.analytic_cue_frame.
const CUE_SOURCES: Array[String] = ["mlp", "analytic", "gated"]

var deliveries := {}   ## id -> Dictionary (deliveries.csv row)
var traces := {}       ## id -> Array[PackedFloat64Array]
var probe_deliveries := {}
var probe_traces := {}
var attempt_summary := {}


static func _read_csv(path: String) -> Array:
	var out := []
	if not FileAccess.file_exists(path):
		return out
	var file := FileAccess.open(path, FileAccess.READ)
	var header := file.get_csv_line()
	while not file.eof_reached():
		var line := file.get_csv_line()
		if line.size() < header.size():
			continue
		var row := {}
		for i in header.size():
			row[header[i]] = line[i]
		out.append(row)
	return out


func load_data() -> bool:
	deliveries = _load_deliveries(DATA_DIR + "deliveries.csv")
	traces = _load_traces(DATA_DIR + "trace.csv")
	probe_deliveries = _load_deliveries(DATA_DIR + "probe_deliveries.csv")
	probe_traces = _load_traces(DATA_DIR + "probe_trace.csv")
	attempt_summary = {"attempts": 0, "aggressive": 0, "running": 0, "caught": 0, "rule_checks": 0}
	for row in _read_csv(DATA_DIR + "attempts.csv"):
		attempt_summary.attempts += 1
		attempt_summary[String(row.tier).substr(5).to_lower()] += 1
		if row.outcome == "caught":
			attempt_summary.caught += 1
		if row.note == "rule_check":
			attempt_summary.rule_checks += 1
	return not deliveries.is_empty() and not traces.is_empty()


static func _load_deliveries(path: String) -> Dictionary:
	var out := {}
	for row in _read_csv(path):
		var d := {}
		for k in row:
			d[k] = float(row[k])
		d["id"] = int(row.delivery)
		out[d.id] = d
	return out


static func _load_traces(path: String) -> Dictionary:
	var out := {}
	if not FileAccess.file_exists(path):
		return out
	var file := FileAccess.open(path, FileAccess.READ)
	file.get_csv_line()
	while not file.eof_reached():
		var line := file.get_csv_line()
		if line.size() < 2 + MarkCueModel.RAW_COUNT:
			continue
		var id := int(line[0])
		var raw := PackedFloat64Array()
		raw.resize(MarkCueModel.RAW_COUNT)
		for i in MarkCueModel.RAW_COUNT:
			raw[i] = float(line[2 + i])
		if not out.has(id):
			out[id] = [] as Array[PackedFloat64Array]
		(out[id] as Array[PackedFloat64Array]).append(raw)
	return out


## The stretch of catching press frames [lo, hi] the label sits in for
## `tier`, or (-1, -1) if there is no label. For Aggressive that's the
## harness's run_lo/run_hi — the outer band, or the half of it the
## verified target is in when the band has holes (see mark_cue_harness.gd
## _aggressive_label); for Running, the trace band.
static func band(d: Dictionary, tier: Tuning.Action) -> Vector2i:
	if tier == Tuning.Action.MARK_AGGRESSIVE:
		return Vector2i(int(d.aggr_run_lo), int(d.aggr_run_hi)) if int(d.aggr_target) >= 0 else Vector2i(-1, -1)
	return Vector2i(int(d.run_lo), int(d.run_hi))


## The press frame the model learns: Aggressive's verified target (the
## catching press whose contact frame found the ball nearest the hands — a
## frame a real attempt caught on), Running's closest-approach frame (its
## tap is its contact).
static func best_frame(d: Dictionary, tier: Tuning.Action) -> float:
	if tier == Tuning.Action.MARK_AGGRESSIVE:
		return float(d.aggr_target)
	return float(d.run_target)


## Seeded 1-in-5 validation split by delivery.
static func split(ids: Array, seed: int) -> Dictionary:
	var sorted := ids.duplicate()
	sorted.sort()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	for i in range(sorted.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = sorted[i]
		sorted[i] = sorted[j]
		sorted[j] = tmp
	var n_val := maxi(1, roundi(sorted.size() * 0.2))
	return {"val": sorted.slice(0, n_val), "train": sorted.slice(n_val)}


func catchable_ids(tier: Tuning.Action, from: Dictionary = deliveries) -> Array:
	var out := []
	for id in from:
		if band(from[id], tier).x >= 0:
			out.append(id)
	out.sort()
	return out


## [inputs, target, raw, weight] rows for `ids`, every `stride`-th frame.
## `near_weight` up-weights rows close to the best press (a Gaussian of
## NEAR_WIDTH s around target 0): the cue fires on the one frame the
## prediction crosses zero, so accuracy there is worth more than accuracy
## a second out, where the ring is only a slow sweep anyway.
func rows_for(model: MarkCueModel, ids: Array, stride: int = 1,
		from_deliveries: Dictionary = deliveries, from_traces: Dictionary = traces,
		near_weight: float = 0.0) -> Array:
	var rows := []
	for id in ids:
		var d: Dictionary = from_deliveries[id]
		var best := best_frame(d, model.tier)
		var trace: Array = from_traces.get(id, [])
		for f in range(0, trace.size(), stride):
			var raw: PackedFloat64Array = trace[f]
			if raw[MarkCueModel.RAW_AIRBORNE] < 0.5:
				continue
			var target := (best - f) / 60.0
			if target < -ROW_TAIL:
				break
			var weight := 1.0 + near_weight * exp(-pow(target / NEAR_WIDTH, 2.0))
			rows.append([model.inputs(raw), target, raw, weight])
	return rows


# ── Evaluation ───────────────────────────────────────────────────────

## The same comparison split by how far out the countdown is — the analytic
## ETA's error is not one number: it grows with time-to-go (its constant-
## acceleration model is exact only at the end), which is where "off by
## several tenths" lives, while at the press instant itself it's much
## smaller. LEAD_BINS in seconds-to-best-press.
const LEAD_BINS: Array[float] = [0.0, 0.25, 0.5, 1.0, 1.5]

static func row_errors_by_lead(model: MarkCueModel, rows: Array) -> Array:
	var out := []
	for b in LEAD_BINS.size() - 1:
		var subset := rows.filter(func(r): return r[1] >= LEAD_BINS[b] and r[1] < LEAD_BINS[b + 1])
		var mlp := 0.0
		var ana := 0.0
		var n := 0
		for r in subset:
			var a := MarkCueModel.analytic_time_to_press(r[2], model.tier)
			if is_nan(a):
				continue
			mlp += absf(model.forward(r[0]) - r[1])
			ana += absf(a - r[1])
			n += 1
		out.append({"from": LEAD_BINS[b], "to": LEAD_BINS[b + 1], "n": n,
			"mlp_mae": mlp / maxf(1.0, n), "analytic_mae": ana / maxf(1.0, n)})
	return out


## Row-level error on the final `window` seconds of countdown (where the
## cue actually lives), model vs analytic, only on rows where the analytic
## ring has a reading at all; plus how many rows it had none on.
static func row_errors(model: MarkCueModel, rows: Array, window: float = 1.0) -> Dictionary:
	var mlp := 0.0
	var ana := 0.0
	var n := 0
	var no_reading := 0
	for row in rows:
		var target: float = row[1]
		if target > window or target < -ROW_TAIL:
			continue
		var a := MarkCueModel.analytic_time_to_press(row[2], model.tier)
		if is_nan(a):
			no_reading += 1
			continue
		mlp += absf(model.forward(row[0]) - target)
		ana += absf(a - target)
		n += 1
	return {"mlp_mae": mlp / maxf(1.0, n), "analytic_mae": ana / maxf(1.0, n), "rows": n, "no_reading": no_reading}


## Per delivery: the frame each cue fires on, its error from the best press
## (s, + = late), and whether it's inside the real band.
func cue_results(model: MarkCueModel, ids: Array, from_deliveries: Dictionary = deliveries,
		from_traces: Dictionary = traces) -> Array:
	var out := []
	for id in ids:
		var d: Dictionary = from_deliveries[id]
		var b := band(d, model.tier)
		var best := best_frame(d, model.tier)
		var trace: Array[PackedFloat64Array] = from_traces[id]
		var mlp := model.cue_frame(trace)
		var r := {"id": id, "d": d, "band": b, "best": best}
		var cues := {"mlp": mlp, "analytic": MarkCueModel.analytic_cue_frame(trace, model.tier),
			"gated": MarkCueModel.analytic_cue_frame(trace, model.tier, true)}
		for src in cues:
			var c: int = cues[src]
			r[src] = c
			r[src + "_err"] = (c - best) / 60.0 if c >= 0 else NAN
			r[src + "_in"] = c >= b.x and c <= b.y
		out.append(r)
	return out


static func summarise_cues(results: Array) -> Dictionary:
	var s := {"n": results.size()}
	for src in CUE_SOURCES:
		s[src + "_in"] = 0
		s[src + "_mae"] = 0.0
		s[src + "_bias"] = 0.0
		s[src + "_worst"] = 0.0
	for r in results:
		for src in CUE_SOURCES:
			if r[src + "_in"]:
				s[src + "_in"] += 1
			var e: float = r[src + "_err"]
			if is_nan(e):
				e = 1.0   # never cued — count as a full second off
			s[src + "_mae"] += absf(e)
			s[src + "_bias"] += e
			s[src + "_worst"] = maxf(s[src + "_worst"], absf(e))
	for src in CUE_SOURCES:
		s[src + "_mae"] /= maxf(1.0, s.n)
		s[src + "_bias"] /= maxf(1.0, s.n)
	return s


## The §7 lesson applied: the same cue results broken down along each
## delivery axis separately, so a model that only works for one corner of
## the space (say, balls from in front) can't hide behind a good average.
static func by_region(results: Array) -> Array:
	var regions := [
		["from front (cos > 0.5)", func(d): return cos(deg_to_rad(d.from_deg)) > 0.5],
		["from side", func(d): return absf(cos(deg_to_rad(d.from_deg))) <= 0.5],
		["from behind (cos < -0.5)", func(d): return cos(deg_to_rad(d.from_deg)) < -0.5],
		["standing (< 1.8 m/s)", func(d): return d.run_speed < Tuning.WALK_SPEED],
		["jog", func(d): return d.run_speed >= Tuning.WALK_SPEED and d.run_speed < 6.5],
		["sprint (> 6.5 m/s)", func(d): return d.run_speed >= 6.5],
		["low (< 1.3 m)", func(d): return d.height < 1.3],
		["chest (1.3-2.3 m)", func(d): return d.height >= 1.3 and d.height <= 2.3],
		["high (> 2.3 m)", func(d): return d.height > 2.3],
	]
	var out := []
	for region in regions:
		var subset := results.filter(func(r): return region[1].call(r.d))
		if subset.is_empty():
			continue
		var s := summarise_cues(subset)
		s["name"] = region[0]
		out.append(s)
	return out


## Per-axis response: sweeps one input across its whole range with the
## rest held at a reference row, reporting the prediction's swing — same
## idea as TackleGA's axis_spreads. A near-zero swing on an input means the
## model ignores it; a swing far larger than any target in the data means
## it's extrapolating wildly there.
static func axis_sweep(model: MarkCueModel, reference: PackedFloat64Array) -> Array:
	var lo := [0.3, 1.0, 0.0, 0.0, -1.0]
	var hi := [4.0, 25.0, Tuning.SPRINT_SPEED, 2.0, 1.0]
	var out := []
	for i in MarkCueModel.INPUT_COUNT:
		var preds := []
		for k in 9:
			var x := reference.duplicate()
			var raw_v: float = lerpf(lo[i], hi[i], k / 8.0)
			x[i] = (raw_v - MarkCueModel.INPUT_CENTRE[i]) / MarkCueModel.INPUT_SCALE[i]
			preds.append(model.forward(x))
		out.append({"name": MarkCueModel.INPUT_NAMES[i], "min": preds.min(), "max": preds.max(),
			"swing": preds.max() - preds.min(), "first": preds[0], "last": preds[-1]})
	return out


# ── Training ─────────────────────────────────────────────────────────

static func default_params() -> Dictionary:
	return {"tier": Tuning.Action.MARK_AGGRESSIVE, "epochs": 150, "learning_rate": 0.01,
		"batch_size": 32, "seed": 1, "stride": 2, "near_weight": 0.0}


## Builds a fresh model and its row sets for `params`; train it with
## step_training() one epoch at a time (the ML page does that across frames
## so the loss chart animates and the UI never freezes), or run() for all
## of it at once.
func begin(params: Dictionary) -> Dictionary:
	var model := MarkCueModel.new()
	model.tier = params.tier
	model.init_weights(int(params.seed))
	var parts := split(catchable_ids(model.tier), int(params.seed))
	var rng := RandomNumberGenerator.new()
	rng.seed = int(params.seed) * 7919
	return {"params": params, "model": model, "rng": rng, "epoch": 0,
		"train_ids": parts.train, "val_ids": parts.val,
		"train_rows": rows_for(model, parts.train, int(params.stride), deliveries, traces, float(params.near_weight)),
		"val_rows": rows_for(model, parts.val, 1, deliveries, traces, float(params.near_weight)),
		"history": [], "best_val": INF, "best_weights": {}}


## One epoch; keeps the weights with the best validation loss so far (the
## data is small enough that a fixed epoch count can overfit — early
## stopping by keeping the best, not by cutting the run short, so the
## chart still shows the whole curve).
func step_training(run: Dictionary) -> void:
	var model: MarkCueModel = run.model
	var p: Dictionary = run.params
	var train_loss := model.train_epoch(run.train_rows, run.rng, float(p.learning_rate), int(p.batch_size))
	var val_loss := model.mean_loss(run.val_rows)
	run.epoch += 1
	run.history.append({"epoch": run.epoch, "train": train_loss, "val": val_loss})
	if val_loss < run.best_val:
		run.best_val = val_loss
		run.best_epoch = run.epoch
		run.best_weights = model.to_dict().duplicate(true)


func finish(run: Dictionary) -> MarkCueModel:
	var best: MarkCueModel = MarkCueModel.from_dict(run.best_weights) if not run.best_weights.is_empty() else run.model
	best.meta = {"seed": run.params.seed, "epochs": run.epoch, "best_epoch": run.get("best_epoch", run.epoch),
		"learning_rate": run.params.learning_rate, "batch_size": run.params.batch_size,
		"stride": run.params.stride, "train_deliveries": run.train_ids, "val_deliveries": run.val_ids,
		"train_rows": run.train_rows.size(), "val_rows": run.val_rows.size(), "best_val_mse": run.best_val}
	return best


func run(params: Dictionary) -> Dictionary:
	var r := begin(params)
	for i in int(params.epochs):
		step_training(r)
	r["best_model"] = finish(r)
	return r


## Everything the page and the self-test report for a trained model.
func evaluate(model: MarkCueModel, run_info: Dictionary) -> Dictionary:
	var out := {}
	out["val_rows"] = row_errors(model, run_info.val_rows)
	out["val_leads"] = row_errors_by_lead(model, run_info.val_rows)
	out["val_cues"] = summarise_cues(cue_results(model, run_info.val_ids))
	out["train_cues"] = summarise_cues(cue_results(model, run_info.train_ids))
	var probe_ids := catchable_ids(model.tier, probe_deliveries)
	if not probe_ids.is_empty() and not probe_traces.is_empty():
		var probe_results := cue_results(model, probe_ids, probe_deliveries, probe_traces)
		out["probe_cues"] = summarise_cues(probe_results)
		out["probe_regions"] = by_region(probe_results)
		var probe_rows := rows_for(model, probe_ids, 1, probe_deliveries, probe_traces)
		out["probe_rows"] = row_errors(model, probe_rows)
		out["probe_leads"] = row_errors_by_lead(model, probe_rows)
		out["probe_uncatchable"] = probe_deliveries.size() - probe_ids.size()
	if not run_info.val_rows.is_empty():
		out["axes"] = axis_sweep(model, run_info.val_rows[run_info.val_rows.size() / 2][0])
	return out


# ── Self-checks ──────────────────────────────────────────────────────

## The checks that don't need the dataset, shared by the ML page's SELF-TEST
## button and scenes/dev/mark_cue_selftest.tscn: backprop against a
## central-difference numerical gradient over every parameter; a fit to a
## known smooth function of all five inputs; same seed, same weights.
## {lines: Array[String], failures: int}.
static func self_checks() -> Dictionary:
	var lines: Array[String] = []
	var failures := 0

	var m := MarkCueModel.new()
	m.init_weights(3)
	var x := PackedFloat64Array([0.3, -0.7, 0.2, 0.9, -0.4])
	var target := 0.37
	var g := PackedFloat64Array()
	g.resize(MarkCueModel.PARAM_COUNT)
	g.fill(0.0)
	var h1 := PackedFloat64Array()
	h1.resize(MarkCueModel.HIDDEN)
	var h2 := h1.duplicate()
	m.accumulate(x, target, g, h1, h2)
	var worst := 0.0
	var eps := 1e-5
	for i in MarkCueModel.PARAM_COUNT:
		var saved := m.params[i]
		m.params[i] = saved + eps
		var up := pow(m.forward(x) - target, 2.0)
		m.params[i] = saved - eps
		var down := pow(m.forward(x) - target, 2.0)
		m.params[i] = saved
		var numeric := (up - down) / (2.0 * eps)
		worst = maxf(worst, absf(numeric - g[i]) / maxf(1e-6, absf(numeric) + absf(g[i])))
	var grad_ok := worst < 1e-4
	lines.append("%s gradient check over all %d parameters: worst relative error %s (need < 1e-4)" % [
		"PASS" if grad_ok else "FAIL", MarkCueModel.PARAM_COUNT, String.num_scientific(worst)])
	failures += 0 if grad_ok else 1

	var toy := MarkCueModel.new()
	toy.init_weights(5)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var rows := []
	for i in 400:
		var xi := PackedFloat64Array()
		for k in MarkCueModel.INPUT_COUNT:
			xi.append(rng.randf_range(-1.0, 1.0))
		rows.append([xi, 0.8 * xi[3] - 0.3 * xi[1] * xi[4] + 0.2 * sin(2.0 * xi[0])])
	var before := toy.mean_loss(rows)
	for e in 200:
		toy.train_epoch(rows, rng, 0.01, 32)
	var after := toy.mean_loss(rows)
	var fit_ok := after < 0.005
	lines.append("%s toy fit (known function of all 5 inputs): MSE %.4f -> %.4f (need < 0.005)" % [
		"PASS" if fit_ok else "FAIL", before, after])
	failures += 0 if fit_ok else 1

	var a := MarkCueModel.new()
	var b := MarkCueModel.new()
	a.init_weights(9)
	b.init_weights(9)
	var tiny := [[PackedFloat64Array([0.1, 0.2, 0.3, 0.4, 0.5]), 0.5], [PackedFloat64Array([-0.5, 0.1, 0.0, -0.2, 0.9]), -0.1]]
	var ra := RandomNumberGenerator.new()
	ra.seed = 4
	var rb := RandomNumberGenerator.new()
	rb.seed = 4
	for e in 20:
		a.train_epoch(tiny, ra, 0.01, 1)
		b.train_epoch(tiny, rb, 0.01, 1)
	var same := a.params == b.params
	lines.append("%s reproducible: same seed -> identical weights" % ("PASS" if same else "FAIL"))
	failures += 0 if same else 1
	return {"lines": lines, "failures": failures}


## The probe run's closed-loop results (probe_cues.csv — one REAL press per
## delivery per cue, labelled by mark_caught / mark_missed): per tier and
## source, {n, caught, no_attempt, contact}. contact is the mean ball-to-
## hands distance on the contact frame over the presses that resolved.
## Written by the harness's `probe` mode with whatever weights were saved
## at the time — the page says so rather than implying it's this session's
## model.
static func closed_loop_summary() -> Dictionary:
	var out := {}
	for row in _read_csv(DATA_DIR + "probe_cues.csv"):
		var key := "%s %s" % [row.tier, row.source]
		if not out.has(key):
			out[key] = {"n": 0, "caught": 0, "no_attempt": 0, "contact": 0.0, "resolved": 0}
		var s: Dictionary = out[key]
		s.n += 1
		if row.outcome == "caught":
			s.caught += 1
		elif row.outcome == "no_attempt" or row.outcome == "no_cue":
			s.no_attempt += 1
		# Only presses that resolved have a contact distance (the CSV's "nan"
		# would parse as 0 here and drag the mean down).
		if row.outcome == "caught" or row.outcome == "missed":
			s.contact += float(row.contact_dist)
			s.resolved += 1
	for key in out:
		out[key].contact /= maxf(1.0, out[key].resolved)
	return out
