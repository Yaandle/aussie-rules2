extends Node

## Single source of truth for "which body responds to human input this
## tick" and "how many bodies does the human direct at once" — the
## foundational layer kicking/tackling input rework and camera targeting
## both sit on top of (see docs/HANDOVER.md's control-mode entry).
##
## Before this, full_game.gd owned an ad-hoc `_controlled_index` and built
## HumanBrain/AIBrain instances inline inside `_switch_human_player()` —
## the routing decision and the brain-construction mechanics were the same
## piece of code. That doesn't extend to a second control scheme without
## scattering scheme checks through the mode script (and eventually
## player_controller.gd), which is exactly what this autoload exists to
## avoid: mode scripts register a team's roster and scheme here, then ask
## this singleton who's driving instead of tracking it themselves.
## Brain *construction* stays with the mode script (an AIBrain needs
## mode-specific config — ball ref, home position, attack direction —
## that this autoload has no business knowing), so this is a router, not
## a brain factory.
##
## Scheme is tracked per-team, not once globally — a match can have one
## team human-controlled and the other pure AI (today's only real case),
## and nothing here assumes a human exists on every side or that only one
## scheme exists per match (see TASK's "must coexist" requirement).

enum Scheme {
	SINGLE_PLAYER,  ## human drives exactly one on-field player at a time
	TEAM_COMMAND,   ## human directly drives a selected player and can issue
	                ## a move-here order to one teammate at a time
}

## Emitted whenever the body that should receive raw human input changes,
## for either reason (controlled-player switch in SINGLE_PLAYER, selection
## change in TEAM_COMMAND, or a scheme swap that changes who's focused).
## Camera/HUD/crosshair/mark-prompt all key off this one signal instead of
## each polling focus_player() every frame.
signal focus_changed(team: Tuning.Team, previous: PlayerController, next: PlayerController)

var _scheme: Dictionary = {}       # Tuning.Team -> Scheme
var _controlled: Dictionary = {}   # Tuning.Team -> PlayerController (SINGLE_PLAYER)
var _selected: Dictionary = {}     # Tuning.Team -> PlayerController (TEAM_COMMAND)
var _roster: Dictionary = {}       # Tuning.Team -> Array[PlayerController]


## Called once per match/mode setup (and safe to call again on a rematch)
## to clear any stale state from a previous match — autoloads persist
## across scene changes, so without this a second Full Game in the same
## session would inherit stale PlayerController references.
func reset() -> void:
	_scheme.clear()
	_controlled.clear()
	_selected.clear()
	_roster.clear()


## Registers `team`'s on-field roster and starting scheme. Does not assign
## any brain — the mode script still does that, then calls
## set_controlled_player()/set_selected_player() to tell this router which
## one it picked.
func register_team(team: Tuning.Team, roster: Array[PlayerController],
		scheme: Scheme = Scheme.SINGLE_PLAYER) -> void:
	_roster[team] = roster
	_scheme[team] = scheme


func roster_for(team: Tuning.Team) -> Array[PlayerController]:
	return _roster.get(team, [] as Array[PlayerController])


func scheme_for(team: Tuning.Team) -> Scheme:
	return _scheme.get(team, Scheme.SINGLE_PLAYER)


## Switching scheme does not touch any brain by itself — the caller (mode
## script) must follow this with whatever set_controlled_player()/
## set_selected_player() call restores a coherent single focus body,
## exactly as it would for an in-scheme switch. Kept this way rather than
## this autoload reaching into brains itself, for the same reason
## register_team() doesn't build brains: mode-specific AI config isn't
## this router's business.
func set_scheme(team: Tuning.Team, scheme: Scheme) -> void:
	_scheme[team] = scheme


func controlled_player(team: Tuning.Team) -> PlayerController:
	return _controlled.get(team) as PlayerController


## SINGLE_PLAYER's routing call: `player` is now the one HumanBrain body
## for `team`. Emits focus_changed if this also changes the focus body
## (it always does in SINGLE_PLAYER, since controlled IS focus there).
func set_controlled_player(team: Tuning.Team, player: PlayerController) -> void:
	var previous_focus := focus_player(team)
	_controlled[team] = player
	var next_focus := focus_player(team)
	if previous_focus != next_focus:
		focus_changed.emit(team, previous_focus, next_focus)


## Picks who the human should switch to next — the mode script still swaps
## the brains and calls set_controlled_player(); this only owns the "who's
## next" ordering so it isn't duplicated at each call site.
##
## With `reference` given (a world point — the ball, normally), returns the
## roster member nearest to it that isn't already `current`, so one press
## lands on the player who actually matters (the defender under the ball,
## the next option up the ground) instead of whoever sits next in the spawn
## array. Pressing again while already on the nearest steps to the
## second-nearest, so it still cycles, just anchored on "who matters" rather
## than on array index. Without a reference it falls back to plain
## roster-index round-robin (TEAM_COMMAND's selection cycle, which has no
## single "player who matters" to sort toward).
func next_in_roster(team: Tuning.Team, current: PlayerController,
		reference := Vector3.INF) -> PlayerController:
	var roster := roster_for(team)
	if roster.size() <= 1:
		return current

	if reference == Vector3.INF:
		var idx := roster.find(current)
		return roster[(idx + 1) % roster.size()] if idx >= 0 else roster[0]

	var ordered := roster.duplicate()
	ordered.sort_custom(func(a: PlayerController, b: PlayerController) -> bool:
		return a.global_position.distance_squared_to(reference) \
			< b.global_position.distance_squared_to(reference))
	for player: PlayerController in ordered:
		if player != current:
			return player
	return current


func selected_player(team: Tuning.Team) -> PlayerController:
	return _selected.get(team) as PlayerController


## TEAM_COMMAND's routing call: `player` is now the selected/directly-
## driven body for `team`.
func set_selected_player(team: Tuning.Team, player: PlayerController) -> void:
	var previous_focus := focus_player(team)
	_selected[team] = player
	var next_focus := focus_player(team)
	if previous_focus != next_focus:
		focus_changed.emit(team, previous_focus, next_focus)


## Whichever body should currently receive raw human input, the camera,
## and contest prompts (mark/tackle) — regardless of scheme. Centralizing
## this one getter is what let camera/HUD/crosshair/mark-prompt stop caring
## which scheme is active at all; they just re-bind to this on
## focus_changed.
##
## Design decision (documented per TASK's request not to silently pick
## one): only the focus body ever gets a contest prompt. In SINGLE_PLAYER
## this was already true (there's only one human body). In TEAM_COMMAND it
## stays true rather than prompting the human once per nearby AI-run
## teammate — a multi-prompt system is real UX surface area (whose prompt
## wins when two teammates are both under the ball at once?) that belongs
## to a dedicated design pass, not a side effect of this routing layer.
## Every unfocused teammate resolves marks/tackles through plain AIBrain
## judgement, exactly as full AI-vs-AI already does.
func focus_player(team: Tuning.Team) -> PlayerController:
	return selected_player(team) if scheme_for(team) == Scheme.TEAM_COMMAND \
		else controlled_player(team)
