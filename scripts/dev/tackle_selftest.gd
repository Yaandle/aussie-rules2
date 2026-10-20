# scripts/dev/tackle_selftest.gd
extends SceneTree

const Model = preload("res://scripts/dev/tackle_model.gd")
const Exp = preload("res://scripts/dev/tackle_experiment.gd")

func _init() -> void:
	var m := Model.new()  # defaults = worked example
	# docs/ML_AI_AUDIT.md §2(a): this used to read "(expect 0.7858)",
	# which is what you get from raw un-normalised weights (0.8, 0.2,
	# 0.5, -1.0) applied directly with no normalisation step at all — a
	# pre-normalisation version of this model, never updated when the
	# weights were rescaled to the current (6, 4, 2, -5.6) configuration.
	print("p_break(2,1,1) = %.4f  (expect 0.9168)" % m.p_break(2.0, 1.0, 1.0))

	var inputs := {"dspeed": 0.0, "angle": 0.5, "stamina": 0.5}
	var rows: Array = Exp.sweep(m, "w_angle", [0.0, 0.2, 0.4, 0.6, 0.8], inputs, 2000)
	for r in rows:
		print("w2=%.1f  success %.1f%% [%.1f-%.1f]  expected %.1f%%" % [
			r.value, r.rate, r.lo, r.hi, r.expected])
	print("two-point 0.2->0.8: %.1f pp/unit" % Exp.sensitivity(rows, 1, 4))
	print("full-range 0.0->0.8: %.1f pp/unit" % Exp.sensitivity(rows, 0, 4))
	print("least-squares slope: %.1f pp/unit" % Exp.slope(rows))

	# Fitter recovery: generate data from the known model, refit, compare.
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var data: Array = []
	for _i in 4000:
		var s := {"dspeed": rng.randf_range(-2.0, 2.0), "angle": rng.randf(), "stamina": rng.randf()}
		s["broke"] = 1 if m.roll_break(rng, s.dspeed, s.angle, s.stamina) else 0
		data.append(s)
	var f = Exp.fit(data)
	# docs/ML_AI_AUDIT.md §2(a): this used to claim "(true 0.80, 0.20,
	# 0.50, -1.00)", but `m` above (the model that actually generated
	# `data`) uses the class's real defaults — 6.0/4.0/2.0/-5.6, not
	# 0.8/0.2/0.5/-1.0. Also see §2(b): Exp.fit() fits on raw,
	# un-normalised feature values while m.p_break() always normalises
	# internally, so even against the correct true weights this recovery
	# is approximate, not exact — expect "close to 6/4/2/-5.6", not a
	# precise match.
	print("fit w=(%.2f, %.2f, %.2f) b=%.2f  (true ~6.0, ~4.0, ~2.0, ~-5.6 — approximate, see comment above)" % [
		f.w_speed, f.w_angle, f.w_stamina, f.bias])
	quit()