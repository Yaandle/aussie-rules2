class_name MarkCueModel
extends RefCounted

## Stage 3 of the ML Experiments page (docs/ML_AI_AUDIT.md §9): a small
## 5 → 8 → 8 → 1 MLP that predicts WHEN to press a mark — never whether the
## mark succeeds. Plain arrays, a hand-written forward pass and backprop with
## a fixed seed, the same shape of code as TackleModel / TackleGA.
##
## Output: seconds from now until the best press for this model's tier,
## negative once that instant has passed. "Best" means the catching press
## whose contact frame puts the ball nearest the hands — the brief's "the
## clip's contact frame meets the ball". It's measured from real attempts
## (scripts/dev/mark_cue_harness.gd _aggressive_label), and it's always a
## press a real attempt caught on.
##
## The band's centre was this label's first version, and it was the wrong
## target. It caught as often, but the contact minimum sits early in the
## band, so it left the ball about twice as far from the hands at contact.
##
## Two instances are trained, one per tier whose press is a timing
## decision. MARK_AGGRESSIVE: the leap commits ACTION_CONTACT ahead of
## contact, so its cue is a forward prediction. MARK_RUNNING: a tap that
## resolves on the frame it's read. Safe is a held button that catches on
## reach entry anywhere inside a 0.55 s window, so there is no press
## instant for a model to improve on.
##
## Only the Aggressive model is used by default (see CueSource). The
## Running one is trained and scored, but it didn't beat the analytic cue
## on the probe grid. Inside Running's reach the time-to-arrival input is
## pinned at 0, and nothing else in the five inputs says how deep into the
## band the ball is. docs/ML_AI_AUDIT.md §9 has the numbers.
##
## Hard rule (RULES_REFERENCE.md §3, brief Part 2.4): this is a policy
## input only. Nothing in contest resolution reads it — the catch is still
## decided by _ball_in_catch_reach + _timing_reach_mult at the real press.
##
## Inputs (all read from live state, no lookahead sim):
##   1. ball height — m above ground
##   2. ball distance — m, ball to the player's catch point
##   3. player speed — m/s, horizontal
##   4. time to arrival — -mark_timing_offset(ball, tier), the analytic
##      estimate itself, capped at TTA_CAP; the not-closing sentinel reads
##      as 0 (arrived / past). Giving the net the estimate it's correcting
##      means it learns a correction, not ballistics from scratch.
##   5. approach cos — cos of the bearing the flight comes FROM relative to
##      the player's facing (APPROACH FROM's convention: 1 = from in front,
##      0 = from the side, -1 = from behind). Chosen as the fifth because
##      it's the one thing the other four can't see: the same distance,
##      height, speed and ETA mean different things when the player runs
##      INTO the flight (closing speeds add, the band is short) versus
##      WITH it (the ball overtakes from behind, closing is slow and the
##      ETA's constant-acceleration model is at its worst). cos rather than
##      degrees: left/right are mirror images (the reach test is a sphere),
##      and it's smooth through 0°/360°.

const RAW_NAMES: Array[String] = ["ball_height", "ball_dist", "player_speed", "cos_bearing",
	"offset_running", "offset_aggressive", "airborne", "flight_dist"]
const RAW_HEIGHT := 0
const RAW_DIST := 1
const RAW_SPEED := 2
const RAW_COS_BEARING := 3
const RAW_OFFSET_RUN := 4
const RAW_OFFSET_AGGR := 5
const RAW_AIRBORNE := 6
const RAW_FLIGHT := 7
const RAW_COUNT := 8

const INPUT_NAMES: Array[String] = ["ball height", "ball distance", "player speed",
	"time to arrival", "approach cos"]
const INPUT_COUNT := 5
const HIDDEN := 8
## Fixed normalisation (centre, half-range), not fitted statistics, so the
## weights file is all a runtime caller needs and the numbers are readable.
const INPUT_CENTRE: Array[float] = [2.0, 12.0, 4.2, 1.25, 0.0]
const INPUT_SCALE: Array[float] = [2.0, 12.0, 4.2, 1.25, 1.0]
const TTA_CAP := 2.5

## Not the dataset folder: that one has a .gdignore (Godot would otherwise
## import every CSV in it as a translation table), and a .gdignore'd folder
## isn't packed into an export — the weights must be, for the cue to work
## outside the editor.
const WEIGHTS_DIR := "res://data/ml/mark_cue_weights/"

## Every weight and bias in one flat packed array — W1 (row-major,
## HIDDEN x INPUT_COUNT), b1, W2 (HIDDEN x HIDDEN), b2, w3, b3 — so the
## forward/backward passes index packed floats rather than nested Variant
## Arrays (the nested version took minutes to train in GDScript; this takes
## seconds). to_dict() still writes the readable nested layout.
const OFF_W1 := 0
const OFF_B1 := OFF_W1 + HIDDEN * INPUT_COUNT
const OFF_W2 := OFF_B1 + HIDDEN
const OFF_B2 := OFF_W2 + HIDDEN * HIDDEN
const OFF_W3 := OFF_B2 + HIDDEN
const OFF_B3 := OFF_W3 + HIDDEN
const PARAM_COUNT := OFF_B3 + 1

var tier := Tuning.Action.MARK_AGGRESSIVE
var params := PackedFloat64Array()
var meta: Dictionary = {}   ## training run summary, saved alongside the weights

# Adam moments, same layout as params.
var _m := PackedFloat64Array()
var _v := PackedFloat64Array()
var _step := 0

static var _cache := {}


# ── Features ─────────────────────────────────────────────────────────

## Everything the harness records per frame, and everything inputs() needs.
## One function for both, so the dataset and the live cue can't drift.
static func raw_state(player: PlayerController, ball: Ball) -> PackedFloat64Array:
	var raw := PackedFloat64Array()
	raw.resize(RAW_COUNT)
	var catch_point := player.catch_point_position()
	raw[RAW_HEIGHT] = ball.global_position.y
	raw[RAW_DIST] = ball.global_position.distance_to(catch_point)
	raw[RAW_SPEED] = Vector2(player.velocity.x, player.velocity.z).length()
	var facing := -player.global_basis.z
	facing.y = 0.0
	var from_dir := -ball.linear_velocity
	from_dir.y = 0.0
	raw[RAW_COS_BEARING] = facing.normalized().dot(from_dir.normalized()) \
		if facing.length_squared() > 0.0001 and from_dir.length_squared() > 0.0001 else 1.0
	raw[RAW_OFFSET_RUN] = player.mark_timing_offset(ball, Tuning.Action.MARK_RUNNING)
	raw[RAW_OFFSET_AGGR] = player.mark_timing_offset(ball, Tuning.Action.MARK_AGGRESSIVE)
	raw[RAW_AIRBORNE] = 1.0 if ball.is_airborne() else 0.0
	raw[RAW_FLIGHT] = ball.distance_since_launch()
	return raw


static func time_to_arrival(offset: float) -> float:
	if offset >= Tuning.MARK_TIMING_PAST_PEAK_OFFSET:
		return 0.0
	return clampf(-offset, 0.0, TTA_CAP)


## The mark_timing_offset() value the analytic ring completes at: Aggressive
## commits ACTION_CONTACT ahead of contact, Safe/Running resolve on the
## press itself. (MarkPrompt._press_target_offset delegates here.)
static func press_target(for_tier: Tuning.Action) -> float:
	if for_tier == Tuning.Action.MARK_AGGRESSIVE:
		return -Tuning.action_contact_time(for_tier)
	return 0.0


## The analytic cue's own answer to the same question the net answers:
## seconds until MarkPrompt's ring completes (offset reaching the tier's
## press target). NAN while mark_timing_offset() reports not-closing — the
## ring has nothing to count down then either.
static func analytic_time_to_press(raw: PackedFloat64Array, for_tier: Tuning.Action) -> float:
	var offset: float = raw[RAW_OFFSET_AGGR] if for_tier == Tuning.Action.MARK_AGGRESSIVE else raw[RAW_OFFSET_RUN]
	if offset >= Tuning.MARK_TIMING_PAST_PEAK_OFFSET:
		return NAN
	var target := press_target(for_tier)
	return target - offset


func inputs(raw: PackedFloat64Array) -> PackedFloat64Array:
	var offset: float = raw[RAW_OFFSET_AGGR] if tier == Tuning.Action.MARK_AGGRESSIVE else raw[RAW_OFFSET_RUN]
	var x := PackedFloat64Array([raw[RAW_HEIGHT], raw[RAW_DIST], raw[RAW_SPEED],
		time_to_arrival(offset), raw[RAW_COS_BEARING]])
	for i in INPUT_COUNT:
		x[i] = (x[i] - INPUT_CENTRE[i]) / INPUT_SCALE[i]
	return x


## Which cue MarkPrompt's ring, MARK DELIVERY's scripted presser and (behind
## its own flag) AIBrain follow — see Tuning.MARK_CUE_SOURCE for which one
## real matches use. ANALYTIC is the ring as it shipped. GATED is the same
## analytic countdown, but it won't complete while a press couldn't register
## (press_registers). MLP is this model's countdown, plus the same gate.
## Only Aggressive differs between the three. Running stays analytic under
## every source, because the trained Running model didn't beat it on the
## probe grid (docs/ML_AI_AUDIT.md §9). Safe has no press instant to learn.
enum CueSource { ANALYTIC, GATED, MLP }

## How long a gated cue reads as "nearly there" while it waits for the
## press to be able to register — short of a full lap, so no completion
## pulse fires early.
const GATE_HOLD := 0.02


## Seconds until `source`'s press-now instant for `for_tier` (<= 0 means
## press now), or NAN while there's nothing to count down — exactly the
## number MarkPrompt sweeps its ring on. Under ANALYTIC this is the shipped
## ring's own arithmetic, unchanged: target - mark_timing_offset(), NAN on
## the not-closing sentinel.
static func cue_time_to_press(player: PlayerController, ball: Ball, for_tier: Tuning.Action,
		source: CueSource) -> float:
	if for_tier != Tuning.Action.MARK_AGGRESSIVE or source == CueSource.ANALYTIC:
		var offset := player.mark_timing_offset(ball, for_tier)
		if offset >= Tuning.MARK_TIMING_PAST_PEAK_OFFSET:
			return NAN
		var target := press_target(for_tier)
		return target - offset
	var raw := raw_state(player, ball)
	var t := analytic_time_to_press(raw, for_tier)
	if source == CueSource.MLP:
		var model := load_for_tier(for_tier)
		if model != null and raw[RAW_AIRBORNE] > 0.5:
			# Half a frame early so "<= 0" is the same instant is_press_now()
			# and cue_frame() fire on.
			t = model.predict_raw(raw) - 0.5 / 60.0
	if not is_nan(t) and t <= 0.0 and not press_registers(raw, for_tier):
		return GATE_HOLD
	return t


static func cue_press_now(player: PlayerController, ball: Ball, for_tier: Tuning.Action,
		source: CueSource) -> bool:
	var t := cue_time_to_press(player, ball, for_tier, source)
	return not is_nan(t) and t <= 0.0


## Live: seconds until the best press for this tier, from the real state.
func predict(player: PlayerController, ball: Ball) -> float:
	return forward(inputs(raw_state(player, ball)))


func predict_raw(raw: PackedFloat64Array) -> float:
	return forward(inputs(raw))


## Would a press of `for_tier` on this frame register at all? The same
## gates PlayerController applies before it even reads the button —
## _update_aerial_contest's MARK_CONTEST_RANGE + MARK_AGGRESSIVE_MIN_
## FLIGHT_DISTANCE for Aggressive, _attempt_running_mark's MARK_CONTEST_
## RANGE for Running (outside it a tap is silently no attempt). Copied as a
## test, not re-tuned: a cue that fires while this is false tells the
## player to press a button the controller will ignore — which the probe
## grid caught the analytic ring doing on fast run-ins from in front (the
## buffered press expired before the ball reached range).
static func press_registers(raw: PackedFloat64Array, for_tier: Tuning.Action) -> bool:
	if raw[RAW_AIRBORNE] < 0.5 or raw[RAW_DIST] > Tuning.MARK_CONTEST_RANGE:
		return false
	return for_tier != Tuning.Action.MARK_AGGRESSIVE \
		or raw[RAW_FLIGHT] >= Tuning.MARK_AGGRESSIVE_MIN_FLIGHT_DISTANCE


## Live press-now test for this model's tier: the prediction has reached
## the press instant (within half a physics frame) AND a press would
## register. Shared by cue_frame() below, MarkPrompt and AIBrain, so the
## dev page's numbers are the in-game cue's numbers.
func is_press_now(raw: PackedFloat64Array) -> bool:
	return press_registers(raw, tier) and predict_raw(raw) <= 0.5 / 60.0


## First frame of a recorded no-press trace this model would cue on.
func cue_frame(trace: Array[PackedFloat64Array]) -> int:
	for f in trace.size():
		if is_press_now(trace[f]):
			return f
	return -1


## The analytic ring's cue on the same trace: the first frame
## MarkPrompt's sweep completes (offset reaching the tier's press target,
## skipping the not-closing sentinel). `gated` adds press_registers() — the
## same fix applied to the analytic ring alone, so the page can show how
## much of the model's gain is the gate and how much is the model.
static func analytic_cue_frame(trace: Array[PackedFloat64Array], for_tier: Tuning.Action, gated := false) -> int:
	for f in trace.size():
		var to_press := analytic_time_to_press(trace[f], for_tier)
		if is_nan(to_press) or to_press > 0.0:
			continue
		if gated and not press_registers(trace[f], for_tier):
			continue
		return f
	return -1


# ── Network ──────────────────────────────────────────────────────────

func init_weights(seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	params = PackedFloat64Array()
	params.resize(PARAM_COUNT)
	params.fill(0.0)
	# Xavier/Glorot uniform for the tanh layers; biases start at zero.
	_fill_uniform(rng, OFF_W1, HIDDEN * INPUT_COUNT, sqrt(6.0 / float(HIDDEN + INPUT_COUNT)))
	_fill_uniform(rng, OFF_W2, HIDDEN * HIDDEN, sqrt(6.0 / float(HIDDEN + HIDDEN)))
	_fill_uniform(rng, OFF_W3, HIDDEN, sqrt(6.0 / float(HIDDEN + 1)))
	_reset_optimiser()


func _fill_uniform(rng: RandomNumberGenerator, offset: int, count: int, limit: float) -> void:
	for i in count:
		params[offset + i] = rng.randf_range(-limit, limit)


func _reset_optimiser() -> void:
	_m = PackedFloat64Array()
	_m.resize(PARAM_COUNT)
	_m.fill(0.0)
	_v = _m.duplicate()
	_step = 0


## Hidden activations for `x` into h1/h2 (pre-sized HIDDEN), returning the
## output. Shared by forward() and backprop so they can't disagree.
func _run(x: PackedFloat64Array, h1: PackedFloat64Array, h2: PackedFloat64Array) -> float:
	var p := params
	for r in HIDDEN:
		var z := p[OFF_B1 + r]
		var row := OFF_W1 + r * INPUT_COUNT
		for c in INPUT_COUNT:
			z += p[row + c] * x[c]
		h1[r] = tanh(z)
	for r in HIDDEN:
		var z := p[OFF_B2 + r]
		var row := OFF_W2 + r * HIDDEN
		for c in HIDDEN:
			z += p[row + c] * h1[c]
		h2[r] = tanh(z)
	var y := p[OFF_B3]
	for i in HIDDEN:
		y += p[OFF_W3 + i] * h2[i]
	return y


func forward(x: PackedFloat64Array) -> float:
	var h1 := PackedFloat64Array()
	h1.resize(HIDDEN)
	var h2 := PackedFloat64Array()
	h2.resize(HIDDEN)
	return _run(x, h1, h2)


## One epoch of mini-batch Adam on weighted mean squared error. `rows` is
## an Array of [PackedFloat64Array inputs, float target, raw, optional
## weight]; shuffled with `rng` so a fixed seed reproduces the run exactly.
## Returns the epoch's weighted mean loss.
func train_epoch(rows: Array, rng: RandomNumberGenerator, learning_rate: float, batch_size: int) -> float:
	var order := PackedInt32Array()
	order.resize(rows.size())
	for i in rows.size():
		order[i] = i
	for i in range(order.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := order[i]
		order[i] = order[j]
		order[j] = tmp
	var g := PackedFloat64Array()
	g.resize(PARAM_COUNT)
	var h1 := PackedFloat64Array()
	h1.resize(HIDDEN)
	var h2 := PackedFloat64Array()
	h2.resize(HIDDEN)
	var total := 0.0
	var weights := 0.0
	var start := 0
	while start < order.size():
		var end := mini(start + batch_size, order.size())
		g.fill(0.0)
		for k in range(start, end):
			var row: Array = rows[order[k]]
			var w: float = row[3] if row.size() > 3 else 1.0
			total += accumulate(row[0], row[1], g, h1, h2, w)
			weights += w
		_adam_update(g, float(end - start), learning_rate)
		start = end
	return total / maxf(1.0, weights)


## Weighted mean squared error, same weighting train_epoch optimises.
func mean_loss(rows: Array) -> float:
	var total := 0.0
	var weights := 0.0
	for row in rows:
		var w: float = row[3] if row.size() > 3 else 1.0
		var e: float = forward(row[0]) - float(row[1])
		total += w * e * e
		weights += w
	return total / maxf(1.0, weights)


## Backprop for one sample, adding d(weight * squared error)/d(param) into
## `g`; returns the weighted squared error. h1/h2 are scratch buffers.
func accumulate(x: PackedFloat64Array, target: float, g: PackedFloat64Array,
		h1: PackedFloat64Array, h2: PackedFloat64Array, weight: float = 1.0) -> float:
	var p := params
	var e := _run(x, h1, h2) - target
	var dy := 2.0 * e * weight
	g[OFF_B3] += dy
	var d2 := PackedFloat64Array()
	d2.resize(HIDDEN)
	for i in HIDDEN:
		g[OFF_W3 + i] += dy * h2[i]
		d2[i] = dy * p[OFF_W3 + i] * (1.0 - h2[i] * h2[i])
	var d1 := PackedFloat64Array()
	d1.resize(HIDDEN)
	d1.fill(0.0)
	for r in HIDDEN:
		g[OFF_B2 + r] += d2[r]
		var row := OFF_W2 + r * HIDDEN
		for c in HIDDEN:
			g[row + c] += d2[r] * h1[c]
			d1[c] += d2[r] * p[row + c]
	for r in HIDDEN:
		var dz := d1[r] * (1.0 - h1[r] * h1[r])
		g[OFF_B1 + r] += dz
		var row := OFF_W1 + r * INPUT_COUNT
		for c in INPUT_COUNT:
			g[row + c] += dz * x[c]
	return weight * e * e


const ADAM_B1 := 0.9
const ADAM_B2 := 0.999
const ADAM_EPS := 1e-8

func _adam_update(g: PackedFloat64Array, n: float, lr: float) -> void:
	if _m.size() != PARAM_COUNT:
		_reset_optimiser()
	_step += 1
	var c1 := 1.0 - pow(ADAM_B1, _step)
	var c2 := 1.0 - pow(ADAM_B2, _step)
	for i in PARAM_COUNT:
		var grad := g[i] / n
		_m[i] = _m[i] * ADAM_B1 + (1.0 - ADAM_B1) * grad
		_v[i] = _v[i] * ADAM_B2 + (1.0 - ADAM_B2) * grad * grad
		params[i] -= lr * (_m[i] / c1) / (sqrt(_v[i] / c2) + ADAM_EPS)


# ── Persistence ──────────────────────────────────────────────────────

static func weights_path(for_tier: Tuning.Action) -> String:
	return WEIGHTS_DIR + "weights_%s.json" % String(Tuning.Action.keys()[for_tier]).to_lower()


## Nested, human-readable layout (w1 as HIDDEN rows of INPUT_COUNT, ...).
func to_dict() -> Dictionary:
	var w1 := []
	var w2 := []
	for r in HIDDEN:
		w1.append(Array(params.slice(OFF_W1 + r * INPUT_COUNT, OFF_W1 + (r + 1) * INPUT_COUNT)))
		w2.append(Array(params.slice(OFF_W2 + r * HIDDEN, OFF_W2 + (r + 1) * HIDDEN)))
	return {"tier": Tuning.Action.keys()[tier], "w1": w1, "b1": Array(params.slice(OFF_B1, OFF_B1 + HIDDEN)),
		"w2": w2, "b2": Array(params.slice(OFF_B2, OFF_B2 + HIDDEN)),
		"w3": Array(params.slice(OFF_W3, OFF_W3 + HIDDEN)), "b3": params[OFF_B3],
		"inputs": INPUT_NAMES, "input_centre": INPUT_CENTRE, "input_scale": INPUT_SCALE, "meta": meta}


static func from_dict(d: Dictionary) -> MarkCueModel:
	var m := MarkCueModel.new()
	m.tier = Tuning.Action.get(String(d.get("tier", "MARK_AGGRESSIVE")), Tuning.Action.MARK_AGGRESSIVE)
	var p := PackedFloat64Array()
	for row in d.w1:
		p.append_array(PackedFloat64Array(row))
	p.append_array(PackedFloat64Array(d.b1))
	for row in d.w2:
		p.append_array(PackedFloat64Array(row))
	p.append_array(PackedFloat64Array(d.b2))
	p.append_array(PackedFloat64Array(d.w3))
	p.append(float(d.b3))
	if p.size() != PARAM_COUNT:
		push_error("MarkCueModel: weights have %d parameters, expected %d" % [p.size(), PARAM_COUNT])
		return null
	m.params = p
	m.meta = d.get("meta", {})
	return m


func save() -> Error:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(WEIGHTS_DIR))
	var file := FileAccess.open(weights_path(tier), FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(to_dict(), "\t"))
	file.close()
	_cache[tier] = self
	return OK


## The saved model for `for_tier`, loaded once and cached; null if none has
## been trained yet (every caller then falls back to the analytic cue).
static func load_for_tier(for_tier: Tuning.Action) -> MarkCueModel:
	if _cache.has(for_tier):
		return _cache[for_tier]
	var model: MarkCueModel = null
	var path := weights_path(for_tier)
	if FileAccess.file_exists(path):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary:
			model = from_dict(parsed)
	_cache[for_tier] = model
	return model


## Swaps in a freshly trained model without a save — the ML page's APPLY.
static func set_active(model: MarkCueModel) -> void:
	_cache[model.tier] = model
