# scripts/dev/tackle_experiment.gd
class_name TackleExperiment
extends RefCounted

const ModelScript = preload("res://scripts/dev/tackle_model.gd")

## Sweep one parameter. inputs = {dspeed, angle, stamina}.
## Same seed per setting, so differences come from the weight, not luck.
static func sweep(base, param: String, values: Array, inputs: Dictionary,
		attempts: int = 1000, rng_seed: int = 1) -> Array:
	var rng := RandomNumberGenerator.new()
	var rows: Array = []
	for v in values:
		var m = base.duplicate()
		m.set(param, v)
		rng.seed = rng_seed
		var ok := 0
		for _i in attempts:
			if not m.roll_break(rng, inputs.dspeed, inputs.angle, inputs.stamina):
				ok += 1
		var ci := wilson(ok, attempts)
		rows.append({
			"value": v, "attempts": attempts, "successes": ok,
			"rate": 100.0 * ok / attempts,
			"lo": 100.0 * ci.x, "hi": 100.0 * ci.y,
			"expected": 100.0 * (1.0 - m.p_break(inputs.dspeed, inputs.angle, inputs.stamina)),
		})
	return rows

static func wilson(k: int, n: int, z: float = 1.96) -> Vector2:
	var p := float(k) / n
	var d := 1.0 + z * z / n
	var c := (p + z * z / (2.0 * n)) / d
	var h := z * sqrt(p * (1.0 - p) / n + z * z / (4.0 * n * n)) / d
	return Vector2(c - h, c + h)

## Two-point sensitivity in percentage points per weight unit.
static func sensitivity(rows: Array, i: int, j: int) -> float:
	return (rows[j].rate - rows[i].rate) / (rows[j].value - rows[i].value)

## Least-squares slope across all rows (pp per weight unit).
static func slope(rows: Array) -> float:
	var n := rows.size()
	var mx := 0.0
	var my := 0.0
	for r in rows:
		mx += r.value
		my += r.rate
	mx /= n
	my /= n
	var sxy := 0.0
	var sxx := 0.0
	for r in rows:
		sxy += (r.value - mx) * (r.rate - my)
		sxx += (r.value - mx) * (r.value - mx)
	return sxy / sxx

## Fit the logistic model to logged samples: [{dspeed, angle, stamina, broke: 0|1}].
## Inputs must vary across samples or the weights can't be separated.
static func fit(samples: Array, lr: float = 1.0, iters: int = 600):
	var m = ModelScript.new()
	m.w_speed = 0.0
	m.w_angle = 0.0
	m.w_stamina = 0.0
	m.bias = 0.0
	var n := float(samples.size())
	for _it in iters:
		var g0 := 0.0
		var g1 := 0.0
		var g2 := 0.0
		var g3 := 0.0
		for s in samples:
			var err: float = m.p_break(s.dspeed, s.angle, s.stamina) - float(s.broke)
			g0 += err * s.dspeed
			g1 += err * s.angle
			g2 += err * s.stamina
			g3 += err
		m.w_speed -= lr * g0 / n
		m.w_angle -= lr * g1 / n
		m.w_stamina -= lr * g2 / n
		m.bias -= lr * g3 / n
	return m

static func to_csv(rows: Array, path: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_line("value,attempts,successes,rate,lo,hi,expected")
	for r in rows:
		f.store_line("%s,%d,%d,%.2f,%.2f,%.2f,%.2f" % [
			r.value, r.attempts, r.successes, r.rate, r.lo, r.hi, r.expected])