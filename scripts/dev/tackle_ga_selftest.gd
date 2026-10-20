# scripts/dev/tackle_ga_selftest.gd
extends SceneTree
## Headless CLI check for TackleGA. Run with:
##   godot --headless --path . --script res://scripts/dev/tackle_ga_selftest.gd
##
## Always calls quit() at the end — tackle_selftest.gd originally didn't,
## which leaves a --script run hanging forever since nothing else ends
## the main loop; fixed there too, noted here so it isn't reintroduced.

const GA = preload("res://scripts/dev/tackle_ga.gd")

func _init() -> void:
	var target := 0.55

	# A deliberately bad starting point: zero weights means every ladder
	# scenario gets the exact same P(BREAK) = sigmoid(bias) regardless of
	# input — zero spread, a textbook "dominant strategy" genome.
	var flat_genome := {"w_speed": 0.0, "w_angle": 0.0, "w_stamina": 0.0}
	var flat_fitness := GA.evaluate(flat_genome, GA.default_bias(), target)
	print("flat genome   score=%.3f  success=%.1f%%  spread=%.3f  (expect spread ≈ 0)" % [
		flat_fitness.score, flat_fitness.mean_success * 100.0, flat_fitness.spread])

	var result := GA.run({"seed": 7})
	var best: Dictionary = result.best_genome
	var f: Dictionary = result.best_fitness
	print("best genome   w_speed=%.2f  w_angle=%.2f  w_stamina=%.2f" % [
		best.w_speed, best.w_angle, best.w_stamina])
	print("best fitness  score=%.3f  success=%.1f%% (target %.0f%%)  ladder spread=%.3f  balance=%.3f  ladder sensitivity=%.3f  axis sensitivity=%.3f" % [
		f.score, f.mean_success * 100.0, target * 100.0, f.spread, f.balance_score, f.sensitivity_score, f.axis_sensitivity_score])
	print("per-axis spread (holding the other two at their midpoint): dspeed=%.3f  angle=%.3f  stamina=%.3f" % [
		f.axis_spreads.dspeed, f.axis_spreads.angle, f.axis_spreads.stamina])

	var line := ""
	for i in GA.LADDER.size():
		line += "%s=%.1f%%  " % [GA.LADDER[i].name, f.p_breaks[i] * 100.0]
	print(line)

	var improved: bool = f.score > flat_fitness.score
	var balanced: bool = absf(f.mean_success - target) < 0.10
	var sensitive: bool = f.spread > 0.3
	var every_axis_used: bool = f.axis_sensitivity_score > 0.2
	print("PASS improved over flat genome: %s" % improved)
	print("PASS within 10pp of target success: %s" % balanced)
	print("PASS ladder spread > 0.3 (not a dominant strategy): %s" % sensitive)
	print("PASS every axis spread > 0.2 (no neglected input): %s" % every_axis_used)

	print("generations run: %d  final avg fitness: %.3f" % [
		result.history.size(), result.history[-1].avg])

	quit()
