class_name CommandBrain
extends AIBrain

## The TEAM_COMMAND scheme's brain for every teammate that isn't the
## currently selected/human-driven player (ControlMode.Scheme.TEAM_COMMAND).
##
## Extends AIBrain rather than wrapping it: a commanded player should still
## gather a loose ball at its feet, still contest a mark it's already
## running under, still get tackled sensibly — none of that should be
## thrown away just because the human once told this player to lead into a
## channel. So update() always runs AIBrain's own think first, and the
## order then overrides only where that think was idle drift
## (AIBrain._decision_committed is false) — a live contest always wins.
## The order colours off-ball positioning; it is not a separate decision
## loop bolted on the side.
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
	# Always run AIBrain's own think first, so the reflexes the class doc
	# promises actually fire: it sets _mark_safe_wanted for a kick dropping
	# on this player, marks itself committed when it's the closest chaser or
	# the presser, and so on. (A ball at the player's literal feet is
	# gathered by PlayerController._try_gather regardless of movement, and a
	# tackle lands regardless of the brain — those need nothing here.)
	super.update(controller, delta)

	if not _has_command or controller.is_carrying():
		return
	var pos := controller.global_position
	if pos.distance_to(commanded_target) <= ARRIVAL_RADIUS:
		_has_command = false
		return
	# A "lead here" order sets where an OFF-BALL player runs — it does not
	# blind a reflex. If the think above committed to a live job (chasing a
	# loose ball it's closest to, pressing the carrier, contesting a mark),
	# that outranks the order and we leave its decision untouched.
	if _decision_committed:
		return
	_move_toward(commanded_target, pos, 1.0)
