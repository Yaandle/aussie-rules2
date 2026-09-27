# scripts/dev/tackle_selftest.gd
extends SceneTree

const Model = preload("res://scripts/dev/tackle_model.gd")
const Exp = preload("res://scripts/dev/tackle_experiment.gd")

func _init() -> void:
	var m := Model.new()  # defaults = worked example
	print("p_break(2,1,1) = %.4f  (expect 0.7858)" % m.p_break(2.0, 1.0, 1.0))

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
	print("fit w=(%.2f, %.2f, %.2f) b=%.2f  (true 0.80, 0.20, 0.50, -1.00)" % [
		f.w_speed, f.w_angle, f.w_stamina, f.bias])