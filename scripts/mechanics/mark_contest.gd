class_name MarkContest
extends RefCounted

## Who takes a contested mark: the tackle formula's twin (TackleBalance),
## for 6AE ("when several players jump in a contest, the one with the
## highest rated P(mark success) wins the mark").
##
## Each player going for the same ball gets a rating
## σ(w_timing·timing + w_position·position + w_height·height + w_body·body + bias)
## from four reads of the real contest, each normalised 0-1:
##   timing    how close the attempt is to the ball's arrival: the Stage 3
##             jump timing (PlayerController.mark_timing_offset against the
##             tier's ideal / OK windows), 1 inside the ideal window.
##   position  how near the hands are to the ball (front position).
##   height    how high the hands are: stature plus the leap, so the jump
##             attribute (6AD) and a well-timed Y both show up here.
##   body      mass x the run at the ball: the bigger player coming in
##             harder holds their ground in the pack.
## PlayerController compares the ratings on the frame a catch would land
## (_wins_mark_contest): only the highest rated player's hands close.
## Evaluated, never rolled: the same contest always goes the same way
## (RULES_REFERENCE.md §3). The sigmoid changes nothing about who wins (it
## is monotonic); it's there so the number reads as a 0-1 P(mark) for the
## maths display and the ML page, like the tackle model's.
##
## The weights are hand-set feel guesses, unplaytested and untrained. A
## trained set saved to WEIGHTS_PATH is picked up the way TackleBalance's is.

const WEIGHTS_PATH := "res://data/ml/mark_contest_weights.json"

const DEFAULT_WEIGHTS := {"w_timing": 2.5, "w_position": 3.0, "w_height": 3.0,
	"w_body": 1.5, "bias": -4.0}

static var _weights := {}


static func weights() -> Dictionary:
	if _weights.is_empty():
		reload()
	return _weights


static func reload() -> void:
	_weights = DEFAULT_WEIGHTS.duplicate()
	if not FileAccess.file_exists(WEIGHTS_PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(WEIGHTS_PATH))
	if parsed is Dictionary:
		for key: String in DEFAULT_WEIGHTS:
			if parsed.has(key):
				_weights[key] = float(parsed[key])


## 1 inside the ideal window, falling in a straight line to 0 at the edge of
## the OK window. Smoother than the reach multiplier's three steps, so two
## players in the same window are still told apart.
static func timing_score(offset: float, ideal_window: float, ok_window: float) -> float:
	var magnitude := absf(offset)
	if magnitude <= ideal_window:
		return 1.0
	if magnitude >= ok_window:
		return 0.0
	return 1.0 - (magnitude - ideal_window) / (ok_window - ideal_window)


## The four inputs from the real contest. `hands_to_ball` and `hands_height`
## are metres, `closing_speed` is the player's flat speed toward the ball.
static func inputs(timing_offset: float, ideal_window: float, ok_window: float,
		hands_to_ball: float, hands_height: float, mass: float, closing_speed: float) -> Dictionary:
	return {
		"timing": timing_score(timing_offset, ideal_window, ok_window),
		"position": clampf(1.0 - hands_to_ball / Tuning.MARK_CONTEST_REACH, 0.0, 1.0),
		"height": clampf(inverse_lerp(Tuning.MARK_CONTEST_HANDS_LOW, Tuning.MARK_CONTEST_HANDS_HIGH,
			hands_height), 0.0, 1.0),
		"body": clampf(mass * maxf(closing_speed, Tuning.MARK_CONTEST_BODY_MIN_SPEED)
			/ (Tuning.MARK_CONTEST_BODY_REF_MASS * Tuning.SPRINT_SPEED), 0.0, 1.0),
	}


## P(mark) for one contestant, 0-1.
static func rating(read: Dictionary) -> float:
	var w := weights()
	var z := float(w.w_timing) * float(read.timing) + float(w.w_position) * float(read.position) \
		+ float(w.w_height) * float(read.height) + float(w.w_body) * float(read.body) + float(w.bias)
	return 1.0 / (1.0 + exp(-z))
