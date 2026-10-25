extends Node

## The single global player profile — the Godot equivalent of Prototype
## 1's character_state.py "APPLY TO ALL PLAYERS" default. P1 also had a
## named-roster/disk-persistence system layered on top of that default;
## this port keeps one always-live profile plus the APPLY TO ALL / one
## specific player toggle, and drops the roster list / naming screen /
## disk-vs-session prompt (see character_screen.gd).
##
## Whatever mode spawns players reads speed_scale()/height_scale()/
## agility_scale()/kick_power/kick_accuracy when building them:
## kick_to_kick.gd for its single player, full_game.gd for HOME (all of
## them when `apply_all`, else just the pregame start-position slot).
##
## Persisted to its own small ConfigFile rather than through Settings —
## Settings loads *after* this autoload (see project.godot [autoload]
## order), so it isn't available at _load() time. Mirrors P1 keeping
## persistence in its own player_data.py.

const CONFIG_PATH := "user://character_profile.cfg"
const SECTION := "profile"

var speed := Tuning.CHARACTER_SPEED_DEFAULT
var height := Tuning.CHARACTER_HEIGHT_DEFAULT

## Already in the units PlayerController wants (a multiplier and a 0..1
## fraction respectively), unlike speed/height above — no _scale()
## getters needed, read these directly.
var kick_power := Tuning.CHARACTER_KICK_POWER_DEFAULT
var kick_accuracy := Tuning.CHARACTER_KICK_ACCURACY_DEFAULT

## Unitless, 1.0 == baseline tuning. agility_scale() below is identity
## while DEFAULT is 1.0, but keeps the getter shape consistent with speed.
var agility := Tuning.CHARACTER_AGILITY_DEFAULT

## true  -> the profile applies to every HOME player in Full Game.
## false -> only the pregame start-position player (Settings.home_human_slot);
##          the rest of HOME (and all of AWAY) stay on baseline tuning.
## Kick-to-Kick ignores this — it only ever has the one player.
var apply_all := true

## "procedural" (the built-in placeholder mesh) or a HumanoidRig.
## CHARACTER_MODELS key — which body every HumanoidRig that doesn't
## override it explicitly (Umpire does) builds. Set from the character
## screen's MODEL row (see HumanoidRig.selected_model()).
var model_id := "procedural"

## Customise colour rows — hex strings ("#rrggbb"), empty means "unset"
## (HumanoidRig falls back to its own constant, same alpha-0 contract
## kit_torso/kit_shorts already have). The character screen owns the fixed
## swatch lists these are chosen from; this autoload just stores whatever
## hex it's handed.
var skin_color := ""
var jersey_color := ""
var shorts_color := ""
var boot_color := ""
var socks_color := ""



func _ready() -> void:
	_load()


func speed_scale() -> float:
	return speed / Tuning.CHARACTER_SPEED_DEFAULT


func height_scale() -> float:
	return height / Tuning.CHARACTER_HEIGHT_DEFAULT


func agility_scale() -> float:
	return agility / Tuning.CHARACTER_AGILITY_DEFAULT


## Called by character_screen.gd when the draft is committed (PLAY or
## backing out). Best-effort — a failed write shouldn't break the menu.
func save() -> void:
	var config := ConfigFile.new()
	config.set_value(SECTION, "speed", speed)
	config.set_value(SECTION, "height", height)
	config.set_value(SECTION, "kick_power", kick_power)
	config.set_value(SECTION, "kick_accuracy", kick_accuracy)
	config.set_value(SECTION, "agility", agility)
	config.set_value(SECTION, "apply_all", apply_all)
	config.set_value(SECTION, "model_id", model_id)
	config.set_value(SECTION, "skin_color", skin_color)
	config.set_value(SECTION, "jersey_color", jersey_color)
	config.set_value(SECTION, "shorts_color", shorts_color)
	config.set_value(SECTION, "boot_color", boot_color)
	config.set_value(SECTION, "socks_color", socks_color)
	config.save(CONFIG_PATH)


## Never raises — a missing or corrupt file just means "fresh install",
## same as never having opened the character screen. Every numeric field
## is re-clamped to its Tuning range so a hand-edited or stale file can't
## push a stat out of bounds.
func _load() -> void:
	var config := ConfigFile.new()
	if config.load(CONFIG_PATH) != OK:
		return
	speed = clampf(config.get_value(SECTION, "speed", speed),
		Tuning.CHARACTER_SPEED_MIN, Tuning.CHARACTER_SPEED_MAX)
	height = clampf(config.get_value(SECTION, "height", height),
		Tuning.CHARACTER_HEIGHT_MIN, Tuning.CHARACTER_HEIGHT_MAX)
	kick_power = clampf(config.get_value(SECTION, "kick_power", kick_power),
		Tuning.CHARACTER_KICK_POWER_MIN, Tuning.CHARACTER_KICK_POWER_MAX)
	kick_accuracy = clampf(config.get_value(SECTION, "kick_accuracy", kick_accuracy),
		Tuning.CHARACTER_KICK_ACCURACY_MIN, Tuning.CHARACTER_KICK_ACCURACY_MAX)
	agility = clampf(config.get_value(SECTION, "agility", agility),
		Tuning.CHARACTER_AGILITY_MIN, Tuning.CHARACTER_AGILITY_MAX)
	apply_all = bool(config.get_value(SECTION, "apply_all", apply_all))
	var loaded_model: String = config.get_value(SECTION, "model_id", model_id)
	# A stale save naming a model that no longer exists (removed asset,
	# renamed id) falls back to the always-valid procedural body rather
	# than HumanoidRig silently failing to resolve it every spawn.
	if loaded_model == "procedural" or HumanoidRig.CHARACTER_MODELS.has(loaded_model):
		model_id = loaded_model
	skin_color = _load_hex(config, "skin_color")
	jersey_color = _load_hex(config, "jersey_color")
	shorts_color = _load_hex(config, "shorts_color")
	boot_color = _load_hex(config, "boot_color")
	socks_color = _load_hex(config, "socks_color")


## Guards against a hand-edited or stale config naming something that
## isn't a "#rrggbb" colour at all — exactly what save() ever writes.
func _load_hex(config: ConfigFile, key: String) -> String:
	var value: String = config.get_value(SECTION, key, "")
	if value.is_empty():
		return ""
	if value.length() != 7 or value[0] != "#":
		return ""
	for i in range(1, 7):
		if not value[i].is_valid_hex_number():
			return ""
	return value
