class_name PlayerBrain
extends RefCounted

## What decides a player's movement and actions each frame — human input
## or AI — behind one interface (design doc §7's Full Game needs both on
## the same PlayerController).
##
## Before this, PlayerController called InputManager/Input directly, so
## only one player could ever be controlled. Every query it made moves
## here unchanged; only where the answer comes from changes.
##
## update() does one think per physics frame for brains that need it
## (AIBrain caches a decision here rather than re-deriving it on every
## getter call); the base implementation is a no-op because HumanBrain
## reads live input on each call and has nothing to precompute.

func update(_controller: PlayerController, _delta: float) -> void:
	pass


## World-space movement intent, length 0..1. PlayerController camera-
## relativises nothing itself any more — a human brain does that against
## the controller's assigned camera; an AI brain already thinks in world
## space, so there is nothing to convert.
func wish_direction(_controller: PlayerController) -> Vector3:
	return Vector3.ZERO


## 0..1, fed to Tuning.speed_for_gait — see InputManager.get_gait.
func gait() -> float:
	return 0.0


## Held-down semantics: true for as long as kick stance/charge should be
## held (LT on a pad) — see PlayerController._update_charge.
func wants_kick() -> bool:
	return false


## Edge-triggered: true for the one frame the kick should actually fire
## (RT tap on a pad), while wants_kick() is still held. Only consulted
## while stance is active; ignored otherwise.
func wants_kick_execute() -> bool:
	return false


## Direct 0..1 override for kick power — "where the end of the trajectory
## line currently reaches to" — or a negative sentinel to mean "no
## override, ramp over hold duration instead" (see
## PlayerController._update_charge). Only a human on a gamepad has stick
## position to read this way; keyboard and AI always fall through to the
## ramp.
func kick_charge_override() -> float:
	return -1.0


## Edge-triggered: true for the one frame the action should fire.
func wants_handball() -> bool:
	return false


func wants_bounce() -> bool:
	return false


func wants_tackle() -> bool:
	return false


## Edge-triggered: true for the one frame a Lunge tackle should be attempted
## (Q/X tap, not carrying) — see PlayerController._try_lunge_tackle. Shares
## its physical binding with wants_handball()/wants_mark_running()/
## wants_smother() — target state, not the input layer, decides which of
## those actually fires on any given press. AI never attempts this — only
## AIBrain's existing wants_tackle() standing/Slide-tackle behavior is in
## AI's scope (design doc: AI never attempts Running/Aggressive marks,
## spoil, smother, bump, Hit-Out, or Lunge) — AIBrain and CommandBrain both
## inherit this base false with no override, same as wants_mark_running()/
## wants_smother() today.
func wants_lunge_tackle() -> bool:
	return false


## Held-down semantics, exactly like wants_kick(): true for as long as a
## Safe Mark should stay readied (A on a pad) — see
## PlayerController._update_aerial_contest. The same query, unchanged, is
## also what drives the A-as-ground-pickup case once the ball isn't
## airborne (PlayerController._update_ground_pickup) — one input, two
## meanings, decided by ball state rather than by the brain.
func wants_mark_safe() -> bool:
	return false


## Edge-triggered: true for the one frame a Running/RAC mark should be
## attempted (X tap).
func wants_mark_running() -> bool:
	return false


## Edge-triggered: true for the one frame an Aggressive/Spectacular mark
## should be attempted (Y tap) — commits to a jump immediately, whether or
## not it will connect.
func wants_mark_aggressive() -> bool:
	return false


## Edge-triggered: true for the one frame a Punch/Spoil should be
## attempted (LT tap, not carrying) — see PlayerController._try_spoil.
func wants_spoil() -> bool:
	return false


## Edge-triggered: true for the one frame a Smother should be attempted
## (X tap, not carrying) — see PlayerController._try_smother.
func wants_smother() -> bool:
	return false


## Edge-triggered: true for the one frame a ruck contestant should attempt
## a Hit-Out (RB tap) — see PlayerController._update_ruck_contest. Only
## read while the controller has been nominated into a live contest
## (set_ruck_contestant); meaningless otherwise, same as every other
## wants_* here being read only in the context that gives it meaning.
func wants_hit_out() -> bool:
	return false


## Held-down semantics, exactly like wants_kick()/wants_mark_safe(): true
## for as long as bump stance should be held (LB on a pad) — see
## PlayerController._update_bump. The flick that actually commits a bump
## comes from InputManager.flick_vector() directly, not through a brain
## method, since it's a raw device gesture rather than a per-player intent.
func wants_bump_stance() -> bool:
	return false
