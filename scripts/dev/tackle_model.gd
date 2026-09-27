# scripts/dev/tackle_model.gd
class_name TackleModel
extends Resource
## Output is P(break). Tackle success = 1 - P(break).

@export var w_speed := 0.8
@export var w_angle := 0.2
@export var w_stamina := 0.5
@export var bias := -1.0

static func sigmoid(z: float) -> float:
	return 1.0 / (1.0 + exp(-z))

func p_break(dspeed: float, angle: float, stamina: float) -> float:
	return sigmoid(w_speed * dspeed + w_angle * angle + w_stamina * stamina + bias)

func roll_break(rng: RandomNumberGenerator, dspeed: float, angle: float, stamina: float) -> bool:
	return rng.randf() < p_break(dspeed, angle, stamina)