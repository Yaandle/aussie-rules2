extends Node

## The Career mode save — one created player, one generated roster, one
## 12-round season. Separate from CharacterProfile (the quick-play Full
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
##
## Save version 2 (docs/CAREER_AUDIT.md Phase 0):
## * Attributes are levels, one per stat-bar square (Tuning.CAREER_
##   ATTRIBUTE_LEVELS), not free floats — attribute_value() turns one back
##   into the units PlayerController reads. HEIGHT isn't one of them: it
##   follows position (height_for_role()).
## * Every roster entry carries a stable "id", and player_id names yours.
##   Per-player stats are keyed by it: display names repeat (480 name
##   combinations across 36 players a match) and merged two players' tallies.
## * The roster copy of you is kept in sync with these fields on every
##   save (_sync_player_entry()), so a match, the roster table and OVERALL
##   all read one place instead of a creation-time snapshot.
## * `rounds` replaces the bare fixture-name list, so each played round
##   keeps its result.
## * career_seed salts every generated name/roster, so a new career gets
##   new teammates and opponents (the old fixed seeds gave every career the
##   same 12 opponents in the same order). 0 is the version-1 seeding.
## A version-1 file loads and converts in place (_load()).

const CONFIG_PATH := "user://career_profile.cfg"
const SECTION := "career"
const SAVE_VERSION := 2

const FOOT_LEFT := "LEFT"
const FOOT_RIGHT := "RIGHT"

## Fixed roster size — a real AFL team (see Tuning.TEAM_SIZE), not a
## Career-specific number.
const ROSTER_SIZE := Tuning.TEAM_SIZE

const DEFAULT_TEAM_NAME := "YOUR JUNIORS U18s"
const SEASON_LENGTH := 12

## The four trainable attributes and the Tuning range each level maps
## across — the same ranges the quick-play CHARACTER screen drafts within,
## so a Career player's OVERALL sits on the same scale as everyone else's.
const ATTRIBUTE_RANGES := {
	"speed": [Tuning.CHARACTER_SPEED_MIN, Tuning.CHARACTER_SPEED_MAX],
	"kick_power": [Tuning.CHARACTER_KICK_POWER_MIN, Tuning.CHARACTER_KICK_POWER_MAX],
	"kick_accuracy": [Tuning.CHARACTER_KICK_ACCURACY_MIN, Tuning.CHARACTER_KICK_ACCURACY_MAX],
	"agility": [Tuning.CHARACTER_AGILITY_MIN, Tuning.CHARACTER_AGILITY_MAX],
}
const ATTRIBUTE_DEFAULTS := {
	"speed": Tuning.CHARACTER_SPEED_DEFAULT,
	"kick_power": Tuning.CHARACTER_KICK_POWER_DEFAULT,
	"kick_accuracy": Tuning.CHARACTER_KICK_ACCURACY_DEFAULT,
	"agility": Tuning.CHARACTER_AGILITY_DEFAULT,
}

var player_name := ""
var position: TeamFormation.Role = TeamFormation.Role.CENTRE
var number := 1
var foot := FOOT_RIGHT

## Attribute key -> level, 0..Tuning.CAREER_ATTRIBUTE_LEVELS. Starts at the
## level nearest each Tuning default.
var levels := {}

var model_id := "procedural"
var skin_color := ""
var jersey_color := ""
var shorts_color := ""
var boot_color := ""
var socks_color := ""

var team_name := DEFAULT_TEAM_NAME
var career_seed := 0

## 18 {id, name, role, number, height, weight, speed, kick_power,
## kick_accuracy, agility} dicts in roster-spawn order (index i's role ==
## TeamFormation.roster_slot(i).role). The entry whose id is player_id is
## you. Empty until a career has been started.
var roster: Array[Dictionary] = []
var player_id := 0

## One {opponent, played, home_score, away_score, home_points, away_points}
## per round. Opponent rosters aren't saved — RosterGenerator rebuilds one
## from its name and career_seed right before the match (opponent_roster()).
var rounds: Array[Dictionary] = []

## The number of rounds played so far, which is also the index of the next
## one. Derived from `rounds` so the two can't disagree.
var games_played: int:
	get:
		var count := 0
		for round_entry in rounds:
			if not bool(round_entry.get("played", false)):
				break
			count += 1
		return count

## The most recent full-time result, for the full-time screen and the
## Dashboard's VIEW STATS: {"opponent": String, "home_score": String,
## "away_score": String, "goals": [{name, value}], "disposals": [{name,
## value}]}. Persisted so the result can be reopened after the full-time
## screen is gone (playtest: "still cannot see the stats page"). Empty
## until a Career match has finished.
var last_result: Dictionary = {}


func _ready() -> void:
	_reset_levels()
	_load()


func has_player() -> bool:
	return not player_name.is_empty()


## A career in progress — what the main menu's CAREER card checks to send
## you to the Dashboard instead of character creation.
func has_career() -> bool:
	return has_player() and roster.size() == ROSTER_SIZE and not rounds.is_empty()


# ── Attributes ───────────────────────────────────────────────────────

static func level_value(key: String, level: int) -> float:
	var range_pair: Array = ATTRIBUTE_RANGES[key]
	var t := clampf(float(level) / float(Tuning.CAREER_ATTRIBUTE_LEVELS), 0.0, 1.0)
	return lerpf(float(range_pair[0]), float(range_pair[1]), t)


## Nearest level to a raw value — used to convert a version-1 save and to
## seed the defaults.
static func level_for(key: String, value: float) -> int:
	var range_pair: Array = ATTRIBUTE_RANGES[key]
	var span := float(range_pair[1]) - float(range_pair[0])
	if span <= 0.0:
		return 0
	return clampi(roundi((value - float(range_pair[0])) / span * Tuning.CAREER_ATTRIBUTE_LEVELS),
		0, Tuning.CAREER_ATTRIBUTE_LEVELS)


static func height_for_role(role: TeamFormation.Role) -> float:
	if role == TeamFormation.Role.RUCK:
		return Tuning.CAREER_HEIGHT_RUCK
	if role in [TeamFormation.Role.FULL_BACK, TeamFormation.Role.CENTRE_HALF_BACK,
			TeamFormation.Role.CENTRE_HALF_FORWARD, TeamFormation.Role.FULL_FORWARD]:
		return Tuning.CAREER_HEIGHT_KEY
	if role in [TeamFormation.Role.BACK_POCKET_LEFT, TeamFormation.Role.BACK_POCKET_RIGHT,
			TeamFormation.Role.FORWARD_POCKET_LEFT, TeamFormation.Role.FORWARD_POCKET_RIGHT,
			TeamFormation.Role.ROVER]:
		return Tuning.CAREER_HEIGHT_SMALL
	return Tuning.CAREER_HEIGHT_MEDIUM


func level(key: String) -> int:
	return int(levels.get(key, 0))


func set_level(key: String, value: int) -> void:
	levels[key] = clampi(value, 0, Tuning.CAREER_ATTRIBUTE_LEVELS)


## The attribute in the units PlayerController and RosterGenerator use.
func attribute_value(key: String) -> float:
	return level_value(key, level(key))


func player_height() -> float:
	return height_for_role(position)


func _reset_levels() -> void:
	for key: String in ATTRIBUTE_RANGES:
		levels[key] = level_for(key, float(ATTRIBUTE_DEFAULTS[key]))


# ── Roster ───────────────────────────────────────────────────────────

## Your index in `roster` (= your roster-spawn slot), or -1 with no career.
func player_roster_index() -> int:
	for i in roster.size():
		if int(roster[i].get("id", -1)) == player_id:
			return i
	return RosterGenerator.roster_index_for_role(roster, position)


## Moves you to `role`'s slot: your entry and the teammate already there
## swap places, each taking the role of the slot they land in. Without the
## swap a position change put the human on a generated teammate (their
## name, their stats) while your own player ran as AI in the old slot.
func set_position(role: TeamFormation.Role) -> void:
	position = role
	var from := player_roster_index()
	var to := RosterGenerator.roster_index_for_role(roster, role)
	if from >= 0 and to >= 0 and from != to:
		var displaced := roster[to]
		roster[to] = roster[from]
		roster[from] = displaced
		roster[from]["role"] = TeamFormation.roster_slot(from)["role"]
	save()


## Takes `value` as your number; a teammate already wearing it gets your
## old one, so two players never share a jumper.
func set_number(value: int) -> void:
	value = clampi(value, 1, 99)
	var mine := player_roster_index()
	var old_number := number if mine < 0 else int(roster[mine]["number"])
	for i in roster.size():
		if i != mine and int(roster[i]["number"]) == value:
			roster[i]["number"] = old_number
	number = value
	save()


## Writes your current identity and attributes into your roster entry.
func _sync_player_entry() -> void:
	var i := player_roster_index()
	if i < 0:
		return
	var entry := roster[i]
	entry["id"] = player_id
	entry["name"] = player_name
	entry["role"] = position
	entry["number"] = number
	entry["height"] = player_height()
	for key: String in ATTRIBUTE_RANGES:
		entry[key] = attribute_value(key)


func opponent_roster() -> Array[Dictionary]:
	return RosterGenerator.generate_team(current_fixture(), career_seed)


# ── Season ───────────────────────────────────────────────────────────

func season_length() -> int:
	return rounds.size()


## True once every round has been played.
func season_complete() -> bool:
	return games_played >= rounds.size()


func current_fixture() -> String:
	var index := games_played
	if index >= rounds.size():
		return ""
	return String(rounds[index]["opponent"])


## Called once, on character creation, after the identity/attribute fields
## are set: a fresh seed, an 18-player roster with you spliced into your
## position's slot, and a season of fixtures. Overwrites any career in
## progress — the Dashboard's New Career asks before getting here.
func start_career() -> void:
	career_seed = _new_seed()
	team_name = DEFAULT_TEAM_NAME
	roster = RosterGenerator.generate_team(team_name, career_seed)
	for i in roster.size():
		roster[i]["id"] = i + 1
	var slot := RosterGenerator.roster_index_for_role(roster, position)
	player_id = int(roster[slot]["id"])
	# WEIGHT has no draft row (same "flavour only" status it has on the
	# quick-play CHARACTER screen), so you keep the slot's generated weight.
	var wanted_number := number
	number = int(roster[slot]["number"])
	set_number(wanted_number)

	rounds.clear()
	for opponent in RosterGenerator.generate_team_names(SEASON_LENGTH, career_seed):
		rounds.append({"opponent": opponent, "played": false})
	last_result = {}
	save()


## Records the current round's result and advances to the next one. Score
## text is whatever MatchState.scoreline() produced for each side, kept as
## display strings; the points are kept as numbers for the ladder.
func record_result(result: Dictionary = {}) -> void:
	var index := games_played
	if index >= rounds.size():
		return
	var round_entry := rounds[index]
	round_entry["played"] = true
	for key in ["home_score", "away_score", "home_points", "away_points"]:
		if result.has(key):
			round_entry[key] = result[key]
	if not result.is_empty():
		last_result = result
	save()


## Never 0 — 0 means "seeded the version-1 way" (see the header).
func _new_seed() -> int:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return rng.randi_range(1, 0x7FFFFFFF)


# ── Persistence ──────────────────────────────────────────────────────

func save() -> void:
	_sync_player_entry()
	var config := ConfigFile.new()
	config.set_value(SECTION, "save_version", SAVE_VERSION)
	config.set_value(SECTION, "player_name", player_name)
	config.set_value(SECTION, "position", int(position))
	config.set_value(SECTION, "number", number)
	config.set_value(SECTION, "foot", foot)
	config.set_value(SECTION, "levels", levels)
	config.set_value(SECTION, "model_id", model_id)
	config.set_value(SECTION, "skin_color", skin_color)
	config.set_value(SECTION, "jersey_color", jersey_color)
	config.set_value(SECTION, "shorts_color", shorts_color)
	config.set_value(SECTION, "boot_color", boot_color)
	config.set_value(SECTION, "socks_color", socks_color)
	config.set_value(SECTION, "team_name", team_name)
	config.set_value(SECTION, "career_seed", career_seed)
	config.set_value(SECTION, "roster", roster)
	config.set_value(SECTION, "player_id", player_id)
	config.set_value(SECTION, "rounds", rounds)
	config.set_value(SECTION, "last_result", last_result)
	config.save(CONFIG_PATH)


## Never raises — a missing or corrupt file just means "no Career save
## yet", same as never having created a character (has_player() stays
## false). A version-1 file (no "save_version") is converted: attribute
## floats to levels, the fixture list + games_played to rounds, ids onto
## the roster. Nothing is written back until the next save().
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

	var loaded_levels: Variant = config.get_value(SECTION, "levels", {})
	for key: String in ATTRIBUTE_RANGES:
		if loaded_levels is Dictionary and (loaded_levels as Dictionary).has(key):
			set_level(key, int(loaded_levels[key]))
		elif config.has_section_key(SECTION, key):
			set_level(key, level_for(key, float(config.get_value(SECTION, key))))

	var loaded_model: String = config.get_value(SECTION, "model_id", model_id)
	if loaded_model == "procedural" or HumanoidRig.CHARACTER_MODELS.has(loaded_model):
		model_id = loaded_model
	skin_color = _load_hex(config, "skin_color")
	jersey_color = _load_hex(config, "jersey_color")
	shorts_color = _load_hex(config, "shorts_color")
	boot_color = _load_hex(config, "boot_color")
	socks_color = _load_hex(config, "socks_color")
	team_name = config.get_value(SECTION, "team_name", team_name)
	career_seed = int(config.get_value(SECTION, "career_seed", 0))

	var loaded_roster: Array = config.get_value(SECTION, "roster", [])
	roster.assign(loaded_roster)
	for i in roster.size():
		if not roster[i].has("id"):
			roster[i]["id"] = i + 1
	if config.has_section_key(SECTION, "player_id"):
		player_id = int(config.get_value(SECTION, "player_id"))
	else:
		var slot := RosterGenerator.roster_index_for_role(roster, position)
		player_id = int(roster[slot]["id"]) if slot >= 0 else 0

	var loaded_result: Variant = config.get_value(SECTION, "last_result", {})
	last_result = loaded_result if loaded_result is Dictionary else {}

	if config.has_section_key(SECTION, "rounds"):
		rounds.assign(config.get_value(SECTION, "rounds"))
	else:
		_rounds_from_version_1(config)
	_sync_player_entry()


## Version 1 kept only the opponent names and a played count; the only
## result it kept was the last one, which lands on the last played round.
func _rounds_from_version_1(config: ConfigFile) -> void:
	rounds.clear()
	var fixtures: Array = config.get_value(SECTION, "fixtures", [])
	var played := clampi(int(config.get_value(SECTION, "games_played", 0)), 0, fixtures.size())
	for i in fixtures.size():
		rounds.append({"opponent": String(fixtures[i]), "played": i < played})
	if played > 0 and not last_result.is_empty():
		var last := rounds[played - 1]
		last["home_score"] = last_result.get("home_score", "-")
		last["away_score"] = last_result.get("away_score", "-")


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
