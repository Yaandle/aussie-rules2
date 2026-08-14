extends Node

## Session-only character attributes — the Godot equivalent of Prototype
## 1's character_state.py "APPLY TO ALL PLAYERS" default. P1 also had a
## named-roster/disk-persistence system layered on top of that default;
## this port stops at the single always-live profile, since nothing here
## yet has more than one controllable player to apply a roster entry to.
## Whatever mode spawns the human-controlled player (currently just
## kick_to_kick.gd) reads speed_scale()/height_scale() when building it.

var speed := Tuning.CHARACTER_SPEED_DEFAULT
var height := Tuning.CHARACTER_HEIGHT_DEFAULT


func speed_scale() -> float:
	return speed / Tuning.CHARACTER_SPEED_DEFAULT


func height_scale() -> float:
	return height / Tuning.CHARACTER_HEIGHT_DEFAULT
