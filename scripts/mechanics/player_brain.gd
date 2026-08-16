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


## Edge-triggered: true for the one frame the action should fire.
func wants_handball() -> bool:
	return false


func wants_bounce() -> bool:
	return false


func wants_tackle() -> bool:
	return false
