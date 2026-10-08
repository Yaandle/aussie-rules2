# scripts/dev/tackle_model.gd
class_name TackleModel
extends Resource
## Output is P(break). Tackle success = 1 - P(break).
##
## Inputs are normalized, per-event values in the tackle model:
## - dspeed: delta speed in m/s, typically from -2.0 to +4.0. Positive means the
##   tackler is coming in faster than the ball carrier; larger values increase break chance.
## - angle: body-entry angle in radians or an equivalent signed angle term, generally
##   from -2.0 to +2.0. Positive values represent a more direct/forward approach; the
##   model treats this as a directional advantage for the breaker.
## - stamina: relative contest stamina 0.0 to 2.0. Higher numbers mean the tackler is
##   fresher / stronger in the contact, which raises the odds of a successful break.
## This is intentionally a simplified feature space; the exact units are not world-physics
## units, just ordinal inputs used by the logistic score.

const NORM_MIN := {
	"dspeed": -2.0,
	"angle": -2.0,
	"stamina": 0.0,
}

const NORM_MAX := {
	"dspeed": 4.0,
	"angle": 2.0,
	"stamina": 2.0,
}

@export var w_speed := 6.0
@export var w_angle := 4.0
@export var w_stamina := 2.0
@export var bias := -5.6

static func sigmoid(z: float) -> float:
	return 1.0 / (1.0 + exp(-z))

static func normalise(value: float, minimum: float, maximum: float) -> float:
	if is_equal_approx(maximum, minimum):
		return 0.0
	return clampf((value - minimum) / (maximum - minimum), 0.0, 1.0)

func p_break(dspeed: float, angle: float, stamina: float) -> float:
	var nd := normalise(dspeed, NORM_MIN["dspeed"], NORM_MAX["dspeed"])
	var na := normalise(angle, NORM_MIN["angle"], NORM_MAX["angle"])
	var ns := normalise(stamina, NORM_MIN["stamina"], NORM_MAX["stamina"])
	return sigmoid(w_speed * nd + w_angle * na + w_stamina * ns + bias)

func roll_break(rng: RandomNumberGenerator, dspeed: float, angle: float, stamina: float) -> bool:
	return rng.randf() < p_break(dspeed, angle, stamina)