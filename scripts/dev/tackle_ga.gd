# scripts/dev/tackle_ga.gd
class_name TackleGA
extends RefCounted
## Stage 2 (genetic algorithm, docs/ML_AI_AUDIT.md §5): evolves
## TackleModel's three weights (w_speed, w_angle, w_stamina) toward a
## target overall tackle-success rate while staying meaningfully
## sensitive to each input — "no dominant strategy" per the brief. bias
## is held fixed at the model's own default; only the three weights
## evolve, matching the genome shape both ML planning docs describe
## (`[speed w, angle w, stamina w]`, no bias term in the genome).
##
## Fitness is evaluated against a fixed 5-point scenario ladder spanning
## the model's full input range — not a single fixed input — so a genome
## can't "win" by overfitting one scenario. LOW/BASELINE/HIGH are the
## exact cases docs/ML_AI_AUDIT.md §1 already verified by hand against
## the ML doc's own table; EXTREME_TACKLE/EXTREME_BREAK are the model's
## true input-range corners. Evaluated via the closed-form p_break()
## rather than Monte Carlo rolls — exact and fast, since what's being
## optimised is the probability curve itself, not one stochastic outcome
## (a "10 SEEDS"-style stochastic check is still useful afterward, as a
## sanity readout on the winning genome — see the GA page's VERIFY action).

const ModelScript = preload("res://scripts/dev/tackle_model.gd")

const GENE_KEYS: Array[String] = ["w_speed", "w_angle", "w_stamina"]

## Same ranges as the MODEL page's own w1/w2/w3 sliders (ml_experiment_
## viewer.gd), so a GA result always lands somewhere a human could also
## have dialled in by hand.
const GENE_BOUNDS := {
	"w_speed": Vector2(0.0, 12.0),
	"w_angle": Vector2(0.0, 8.0),
	"w_stamina": Vector2(0.0, 6.0),
}

## dspeed, angle, stamina — raw units, same convention as TackleModel's
## own header comment (all three weights are positive, so raising any
## raw input monotonically raises P(BREAK) — "extreme_tackle" is the
## input space's low corner, "extreme_break" its high corner).
const LADDER := [
	{"name": "extreme_tackle", "dspeed": -2.0, "angle": -2.0, "stamina": 0.0},
	{"name": "low",            "dspeed":  0.0, "angle":  0.0, "stamina": 0.0},
	{"name": "baseline",       "dspeed":  0.7, "angle":  0.7, "stamina": 0.7},
	{"name": "high",           "dspeed":  1.0, "angle":  1.0, "stamina": 1.0},
	{"name": "extreme_break",  "dspeed":  4.0, "angle":  2.0, "stamina": 2.0},
]


static func default_bias() -> float:
	return ModelScript.new().bias


## {population_size, generations, mutation_rate, mutation_strength,
## elite_count, target_success, bias, seed} — every key optional, see
## the fallbacks below.
static func default_params() -> Dictionary:
	return {
		"population_size": 40,
		"generations": 40,
		"mutation_rate": 0.15,
		"mutation_strength": 0.12,
		"elite_count": 2,
		"target_success": 0.55,
		"bias": default_bias(),
		"seed": 1,
	}


static func random_genome(rng: RandomNumberGenerator) -> Dictionary:
	var g := {}
	for k in GENE_KEYS:
		var b: Vector2 = GENE_BOUNDS[k]
		g[k] = rng.randf_range(b.x, b.y)
	return g


static func clamp_genome(g: Dictionary) -> Dictionary:
	var out := {}
	for k in GENE_KEYS:
		var b: Vector2 = GENE_BOUNDS[k]
		out[k] = clampf(g.get(k, 0.0), b.x, b.y)
	return out


static func _model_for(genome: Dictionary, bias: float):
	var m = ModelScript.new()
	m.w_speed = genome["w_speed"]
	m.w_angle = genome["w_angle"]
	m.w_stamina = genome["w_stamina"]
	m.bias = bias
	return m


## {score, mean_success, mean_break, spread, balance_score,
## sensitivity_score, p_breaks: Array[float] in LADDER order}.
##
## score = 0.6 * balance_score + 0.4 * sensitivity_score:
##  - balance_score: how close the ladder's average tackle-success rate
##    sits to `target_success` (kanban: "success near 55%"). 0.5 (50
##    points) of error or more floors this at 0.
##  - sensitivity_score: rewards a wide, correctly-ordered spread from
##    the tackler-favoured corner to the breaker-favoured one ("no
##    dominant strategy" — a genome that's near-0% or near-100% break
##    regardless of input scores 0 here even if its average happens to
##    hit the target). `monotonic_penalty` punishes any step in the
##    ladder that runs backwards.
static func evaluate(genome: Dictionary, bias: float, target_success: float) -> Dictionary:
	var m = _model_for(genome, bias)
	var p_breaks: Array[float] = []
	for scenario in LADDER:
		p_breaks.append(m.p_break(scenario.dspeed, scenario.angle, scenario.stamina))

	var mean_break := 0.0
	for p in p_breaks:
		mean_break += p
	mean_break /= p_breaks.size()
	var mean_success := 1.0 - mean_break

	var balance_score := clampf(1.0 - absf(mean_success - target_success) / 0.5, 0.0, 1.0)

	var spread: float = p_breaks[p_breaks.size() - 1] - p_breaks[0]
	var monotonic_penalty := 0.0
	for i in range(p_breaks.size() - 1):
		if p_breaks[i + 1] < p_breaks[i]:
			monotonic_penalty += p_breaks[i] - p_breaks[i + 1]
	var sensitivity_score := clampf(spread - monotonic_penalty, 0.0, 1.0)

	return {
		"score": 0.6 * balance_score + 0.4 * sensitivity_score,
		"mean_success": mean_success,
		"mean_break": mean_break,
		"spread": spread,
		"balance_score": balance_score,
		"sensitivity_score": sensitivity_score,
		"p_breaks": p_breaks,
	}


## Uniform crossover: each gene independently taken from one parent or
## the other.
static func crossover(a: Dictionary, b: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var child := {}
	for k in GENE_KEYS:
		child[k] = a[k] if rng.randf() < 0.5 else b[k]
	return child


## mutation_rate is the one dial the brief calls out ("one variable to
## tune"): the per-gene probability a mutation happens at all.
## mutation_strength scales how big that mutation is (as a fraction of
## the gene's own range) once it does.
static func mutate(genome: Dictionary, rng: RandomNumberGenerator,
		mutation_rate: float, mutation_strength: float) -> Dictionary:
	var out := genome.duplicate()
	for k in GENE_KEYS:
		if rng.randf() < mutation_rate:
			var b: Vector2 = GENE_BOUNDS[k]
			var span: float = b.y - b.x
			out[k] += rng.randfn(0.0, mutation_strength * span)
	return clamp_genome(out)


## Tournament selection: draw `k` random genomes, return the fittest.
static func _select(population: Array, fitnesses: Array, rng: RandomNumberGenerator, k: int) -> Dictionary:
	var best_i := rng.randi_range(0, population.size() - 1)
	for _i in range(k - 1):
		var i := rng.randi_range(0, population.size() - 1)
		if fitnesses[i].score > fitnesses[best_i].score:
			best_i = i
	return population[best_i]


## Runs the full evolution synchronously (pure arithmetic over a 5-point
## ladder — population_size * generations * 5 sigmoid calls, trivial even
## at the UI's upper slider bounds). Returns {best_genome, best_fitness,
## history: [{generation, best, avg}, ...]}.
static func run(params: Dictionary = {}) -> Dictionary:
	var p := default_params()
	for k in params:
		p[k] = params[k]

	var rng := RandomNumberGenerator.new()
	rng.seed = p.seed

	var pop_size: int = p.population_size
	var population: Array = []
	for _i in pop_size:
		population.append(random_genome(rng))

	var history: Array = []
	var best_genome: Dictionary = (population[0] as Dictionary).duplicate()
	var best_fitness: Dictionary = evaluate(best_genome, p.bias, p.target_success)

	for gen in p.generations:
		var fitnesses: Array = []
		var total_score := 0.0
		for genome in population:
			var f := evaluate(genome, p.bias, p.target_success)
			fitnesses.append(f)
			total_score += f.score
			if f.score > best_fitness.score:
				best_fitness = f
				best_genome = genome.duplicate()

		history.append({
			"generation": gen,
			"best": best_fitness.score,
			"avg": total_score / pop_size,
		})

		var indices: Array = range(pop_size)
		indices.sort_custom(func(i, j): return fitnesses[i].score > fitnesses[j].score)

		var next_population: Array = []
		for i in range(mini(p.elite_count, pop_size)):
			next_population.append(population[indices[i]].duplicate())

		while next_population.size() < pop_size:
			var parent_a := _select(population, fitnesses, rng, 3)
			var parent_b := _select(population, fitnesses, rng, 3)
			var child := crossover(parent_a, parent_b, rng)
			child = mutate(child, rng, p.mutation_rate, p.mutation_strength)
			next_population.append(child)

		population = next_population

	return {
		"best_genome": best_genome,
		"best_fitness": best_fitness,
		"history": history,
	}
