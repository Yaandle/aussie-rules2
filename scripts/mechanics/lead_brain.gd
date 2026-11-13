class_name LeadBrain
extends PlayerBrain

## A teammate who leads for the ball and takes it: the kicking tutorial's
## target (KickTutorial) and a drill bot's receive (DrillBrain uses the
## same chase). Stands still until `lead_delay` after restart(), runs
## `lead_direction` for `lead_time`, then pulls up. The moment a kick from
## `kicker` is in the air they stop leading and run to where it'll come
## down (Ball.predicted_landing_position at chest height), holding the safe
## mark once it's close — the same marking every player has, so a bad kick
## is genuinely spilled or never reached, not caught by script.

## Chest height, where predicted_landing_position meets the flight.
const CATCH_HEIGHT := 1.4
## Within this of the ball they hold the safe mark.
const MARK_RANGE := 7.0
## Closer than this to the landing spot they only walk.
const SETTLE_DISTANCE := 2.5

var ball: Ball = null
var kicker: PlayerController = null
var lead_direction := Vector3.FORWARD
var lead_delay := 0.0
var lead_time := 0.0
var lead_gait := 0.9

var _clock := 0.0
var _dir := Vector3.ZERO
var _gait := 0.0
var _mark := false


func restart() -> void:
	_clock = 0.0


func update(controller: PlayerController, delta: float) -> void:
	_clock += delta
	_dir = Vector3.ZERO
	_gait = 0.0
	_mark = false
	if controller.is_carrying():
		return
	if is_instance_valid(ball) and ball.is_kick_flight() and ball.last_disposer() == kicker:
		var land := ball.predicted_landing_position(CATCH_HEIGHT)
		var to_land := land - controller.global_position
		to_land.y = 0.0
		if to_land.length() > 0.3:
			_dir = to_land.normalized()
			_gait = 1.0 if to_land.length() > SETTLE_DISTANCE else 0.35
		_mark = controller.global_position.distance_to(ball.global_position) <= MARK_RANGE
		return
	if _clock >= lead_delay and _clock < lead_delay + lead_time:
		_dir = lead_direction
		_gait = lead_gait


func wish_direction(_controller: PlayerController) -> Vector3:
	return _dir


func gait() -> float:
	return _gait


func wants_mark_safe() -> bool:
	return _mark
