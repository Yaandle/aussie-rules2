extends Node

## The Career mode save — one created player, one generated roster, one
## 12-game season. Separate from CharacterProfile (the quick-play Full
## Game/Kick-to-Kick profile) rather than extending it: Career's player
## carries fields quick-play never needed (name/position/number/foot, a
## roster, a season), and the two should never bleed into each other —
## editing your Career player shouldn't touch the quick-play draft, and
## vice versa.
##
## Persisted to its own ConfigFile, same pattern as character_profile.gd
## (and for the same reason: this autoload has to load before Settings,
## see project.godot's [autoload] order, so it can't lean on Settings for
## its own persistence).

const CONFIG_PATH := "user://career_profile.cfg"
const SECTION := "career"

const FOOT_LEFT := "LEFT"
const FOOT_RIGHT := "RIGHT"

## Fixed roster size — a real AFL team (see Tuning.TEAM_SIZE), not a
## Career-specific number.
const ROSTER_SIZE := Tuning.TEAM_SIZE

const DEFAULT_TEAM_NAME := "YOUR JUNIORS U18s"
const SEASON_LENGTH := 12

var player_name := ""
var position: TeamFormation.Role = TeamFormation.Role.CENTRE
var number := 1
var foot := FOOT_RIGHT

## Own copies of the same five adjustable stats CharacterProfile has, same
## Tuning bounds — see character_profile.gd for why these particular
## fields/units.
var speed := Tuning.CHARACTER_SPEED_DEFAULT
var height := Tuning.CHARACTER_HEIGHT_DEFAULT
var kick_power := Tuning.CHARACTER_KICK_POWER_DEFAULT
var kick_accuracy := Tuning.CHARACTER_KICK_ACCURACY_DEFAULT
var agility := Tuning.CHARACTER_AGILITY_DEFAULT

var model_id := "procedural"
var skin_color := ""
var jersey_color := ""
var shorts_color := ""
var boot_color := ""

var team_name := DEFAULT_TEAM_NAME

## 18 {name: String, role: TeamFormation.Role, number: int} dicts, one per
## TeamFormation.SLOTS entry — index 0 is always the created player's own
## slot's match, set by career_character_screen.gd on confirm. Empty until
## a character has actually been created.
var roster: Array[Dictionary] = []

## 12 generated opponent team names, one per fixture — rosters for them
## aren't generated (or persisted) until that fixture is actually played,
## see RosterGenerator.generate_team().
var fixtures: Array[String] = []
var games_played := 0


func _ready() -> void:
	_load()


func has_player() -> bool:
	return not player_name.is_empty()


func speed_scale() -> float:
	return speed / Tuning.CHARACTER_SPEED_DEFAULT


func height_scale() -> float:
	return height / Tuning.CHARACTER_HEIGHT_DEFAULT


func agility_scale() -> float:
	return agility / Tuning.CHARACTER_AGILITY_DEFAULT


## True once every fixture has been played — nothing past game 1 exists
## yet (see career_dashboard_screen.gd's locked state), but the season
## itself is only 12 games long regardless.
func season_complete() -> bool:
	return games_played >= fixtures.size()


func current_fixture() -> String:
	if games_played >= fixtures.size():
		return ""
	return fixtures[games_played]


## Called once, on character creation. `created_roster` is whatever
## RosterGenerator.generate_team() built with this player's own slot
## already substituted in — see career_character_screen.gd.
func start_season(created_roster: Array[Dictionary], opponent_names: Array[String]) -> void:
	roster = created_roster
	fixtures = opponent_names
	games_played = 0
	save()


## Records a played fixture's result and advances to the next one. Score
## text is whatever MatchState.scoreline() produced for each side — kept
## as display strings rather than re-deriving them later, since nothing
## past the full-time screen needs to recompute a ladder yet.
func record_result() -> void:
	games_played += 1
	save()


func save() -> void:
	var config := ConfigFile.new()
	config.set_value(SECTION, "player_name", player_name)
	config.set_value(SECTION, "position", int(position))
	config.set_value(SECTION, "number", number)
	config.set_value(SECTION, "foot", foot)
	config.set_value(SECTION, "speed", speed)
	config.set_value(SECTION, "height", height)
	config.set_value(SECTION, "kick_power", kick_power)
	config.set_value(SECTION, "kick_accuracy", kick_accuracy)
	config.set_value(SECTION, "agility", agility)
	config.set_value(SECTION, "model_id", model_id)
	config.set_value(SECTION, "skin_color", skin_color)
	config.set_value(SECTION, "jersey_color", jersey_color)
	config.set_value(SECTION, "shorts_color", shorts_color)
	config.set_value(SECTION, "boot_color", boot_color)
	config.set_value(SECTION, "team_name", team_name)
	config.set_value(SECTION, "roster", roster)
	config.set_value(SECTION, "fixtures", fixtures)
	config.set_value(SECTION, "games_played", games_played)
	config.save(CONFIG_PATH)


## Never raises — a missing or corrupt file just means "no Career save
## yet", same as never having created a character (has_player() stays
## false). Numeric fields are re-clamped exactly as CharacterProfile._load()
## does, for the same reason.
func _load() -> void:
	var config := ConfigFile.new()
	if config.load(CONFIG_PATH) != OK:
		return
	player_name = config.get_value(SECTION, "player_name", player_name)
	var loaded_position: int = config.get_value(SECTION, "position", int(position))
	if loaded_position >= 0 and loaded_position < TeamFormation.Role.size():
		position = loaded_position
	number = clampi(config.get_value(SECTION, "number", number), 1, 99)
	var loaded_foot: String = config.get_value(SECTION, "foot", foot)
	foot = loaded_foot if loaded_foot in [FOOT_LEFT, FOOT_RIGHT] else foot
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
	var loaded_model: String = config.get_value(SECTION, "model_id", model_id)
	if loaded_model == "procedural" or HumanoidRig.CHARACTER_MODELS.has(loaded_model):
		model_id = loaded_model
	skin_color = _load_hex(config, "skin_color")
	jersey_color = _load_hex(config, "jersey_color")
	shorts_color = _load_hex(config, "shorts_color")
	boot_color = _load_hex(config, "boot_color")
	team_name = config.get_value(SECTION, "team_name", team_name)
	var loaded_roster: Array = config.get_value(SECTION, "roster", [])
	roster.assign(loaded_roster)
	var loaded_fixtures: Array = config.get_value(SECTION, "fixtures", [])
	fixtures.assign(loaded_fixtures)
	games_played = clampi(config.get_value(SECTION, "games_played", games_played),
		0, fixtures.size())


## Guards against a hand-edited or stale config naming something that
## isn't a "#rrggbb" colour at all — same check character_profile.gd uses.
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
