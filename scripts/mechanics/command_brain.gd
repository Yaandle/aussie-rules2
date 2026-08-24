class_name CommandBrain
extends AIBrain

## The TEAM_COMMAND scheme's brain for every teammate that isn't the
## currently selected/human-driven player (ControlMode.Scheme.TEAM_COMMAND).
##
## Extends AIBrain rather than wrapping it: a commanded player should still
## gather a loose ball at its feet, still contest a mark it's already
## running under, still get tackled sensibly — none of that should be
## thrown away just because the human once told this player to lead into a
## channel. So the default (no order queued) is exactly AIBrain's own
## judgement, and a queued order is a *override* consulted first, not a
## separate decision loop bolted on the side.
##
## The only new state is `commanded_target` — a world point set externally
## by whoever issues the order (full_game.gd's command-issuing input
## handling), consumed here as "run there", and cleared once reached so
## the player falls back to normal AI think rather than idling on the spot
## forever.

const ARRIVAL_RADIUS := 1.5   ## m — same order of magnitude as AIBrain's own dead zones

var commanded_target: Vector3 = Vector3.ZERO
var _has_command := false


func issue_command(target: Vector3) -> void:
	commanded_target = target
	_has_command = true


func clear_command() -> void:
	_has_command = false


func update(controller: PlayerController, delta: float) -> void:
	if _has_command and not controller.is_carrying():
		var pos := controller.global_position
		if pos.distance_to(commanded_target) <= ARRIVAL_RADIUS:
			_has_command = false
		else:
			_move_toward(commanded_target, pos, 1.0)
			return
	super.update(controller, delta)
