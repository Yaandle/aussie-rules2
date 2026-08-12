extends Node

## Mode and phase singleton — the role Prototype 1's GameState played,
## minus everything that belongs in the scene tree.
##
## P1's game_state.py grew to 16k because it owned the phase machine AND
## input AND the update loop AND possession AND rendering hand-off. The
## split it eventually took (formations / menu / outcomes / gameplay) is
## the lesson; this autoload keeps only the part that genuinely has to be
## global — which mode is running and which phase it is in. Everything
## else lives on nodes.
##
## Milestone 1 only ever sits in Mode.SANDBOX / Phase.PLAY. The rest is
## declared because the shape is known from P1, not because it is wired.

signal mode_changed(mode: Mode)
signal phase_changed(phase: Phase)

enum Mode {
	SANDBOX,      ## the milestone-1 harness: one player, one ball, one oval
	FULL_GAME,    ## §7 priority 1
	SCENARIO,     ## §7 priority 2
	GOAL_KICKING, ## §7 priority 4
}

enum Phase {
	MENU,
	CENTRE_BOUNCE,
	PLAY,
	SET_SHOT,     ## a mark or free kick being taken
	STOPPAGE,     ## ball-up / boundary throw-in
	SCORE,
	FINISHED,
}

var mode: Mode = Mode.SANDBOX:
	set(value):
		if mode == value:
			return
		mode = value
		mode_changed.emit(mode)

var phase: Phase = Phase.PLAY:
	set(value):
		if phase == value:
			return
		phase = value
		phase_changed.emit(phase)


func is_live() -> bool:
	return phase == Phase.PLAY or phase == Phase.CENTRE_BOUNCE


func mode_name() -> String:
	return Mode.keys()[mode]


func phase_name() -> String:
	return Phase.keys()[phase]
