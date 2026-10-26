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
##
## Seasons (docs/CAREER_AUDIT.md Phase 1): you play in a 12-team league
## (league_teams + you) on CareerSeason's round-robin fixture. Recording
## your result also scores that round's other five games, so the ladder
## is always complete. After round 12, start_next_season() files the
## season in season_history and either promotes you — top
## Tuning.CAREER_PROMOTION_PLACES, to a new club in the next league of
## CareerSeason.LEAGUES, with new teammates and opponents — or starts
## another season in the same league with the same club. Your player (and
## player_id) carries over either way. A save from before leagues existed
## gets its season rebuilt into one (_rebuild_legacy_season()).

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

## CAREER SETTINGS on the Create screen, fixed for the career once it
## starts. Sets where attributes start (start_level()); later phases of
## docs/CAREER_AUDIT.md hang upgrades and opponent strength off it too.
const DIFFICULTY_EASY := 0
const DIFFICULTY_HARD := 1
const DIFFICULTY_NAMES := ["EASY", "HARD"]

## season_outcome() values.
const OUTCOME_PROMOTED := "promoted"
const OUTCOME_CHAMPIONS := "champions"
const OUTCOME_STAY := "stay"

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
var difficulty := DIFFICULTY_EASY
var position: TeamFormation.Role = TeamFormation.Role.CENTRE
var number := 1
var foot := FOOT_RIGHT

## Attribute key -> level, 0..Tuning.CAREER_ATTRIBUTE_LEVELS. Starts at the
## level nearest each Tuning default.
var levels := {}

## Squares earned and not yet spent (Edit Player) — upgrades_per_game() for
## every real match recorded, banked without limit; spending is capped per
## attribute by attribute_cap().
var upgrades_available := 0

var model_id := "procedural"
var skin_color := ""
var jersey_color := ""
var shorts_color := ""
var boot_color := ""
var socks_color := ""

var team_name := DEFAULT_TEAM_NAME
var career_seed := 0

## Tier in CareerSeason.LEAGUES, and seasons played before this one.
var league_index := 0
var season_index := 0
## The 11 other teams in this season's league.
var league_teams: Array[String] = []
## Finished seasons, oldest first: {season, league, team, position, played,
## won, lost, drawn, outcome, player} — `player` is your season_stats line.
var season_history: Array[Dictionary] = []

## This season's box score for your club, roster id -> {games, kicks,
## handballs, marks, tackles, goals, behinds, hitouts} (MatchState.
## PLAYER_STATS). Every played match adds a game to all 18 — no interchange
## yet — and a dev-simmed round adds nothing, so averages are over real
## matches only. Cleared each season; career_stats keeps your totals
## across all of them.
var season_stats := {}
var career_stats := {}

## Team name -> average OVERALL for the sim, rebuilt on demand (generating
## a roster is cheap, but the sim asks for 10 of them a round).
var _ovr_cache := {}

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


func upgrades_per_game() -> int:
	return Tuning.CAREER_UPGRADES_PER_GAME_HARD if difficulty == DIFFICULTY_HARD \
		else Tuning.CAREER_UPGRADES_PER_GAME_EASY


## The highest level an upgrade can take an attribute to in this league.
func attribute_cap() -> int:
	return mini(Tuning.CAREER_ATTRIBUTE_CAP_START + league_index, Tuning.CAREER_ATTRIBUTE_LEVELS)


## Where every trainable attribute starts for `for_difficulty`.
static func start_level(for_difficulty: int) -> int:
	return Tuning.CAREER_START_LEVEL_HARD if for_difficulty == DIFFICULTY_HARD \
		else Tuning.CAREER_START_LEVEL_EASY


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
	_take_number(value)
	save()


func _take_number(value: int) -> void:
	value = clampi(value, 1, 99)
	var mine := player_roster_index()
	var old_number := number if mine < 0 else int(roster[mine]["number"])
	for i in roster.size():
		if i != mine and int(roster[i]["number"]) == value:
			roster[i]["number"] = old_number
	number = value


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
	return _league_roster(current_fixture())


## Any team in the current league, as RosterGenerator rebuilds it.
func _league_roster(team: String) -> Array[Dictionary]:
	return RosterGenerator.generate_team(team, _league_salt(), CareerSeason.league_band(league_index))


## Salt for this league's generated names and squads. League 0 uses
## career_seed itself, so a version-1 save (seed 0) keeps its names.
func _league_salt() -> int:
	return career_seed if league_index == 0 else hash("%d#league%d" % [career_seed, league_index])


## Joins `club` in the current league: its generated squad with you
## spliced into your position's slot. Ids carry on from the last club's,
## so a player id never repeats within a career; you keep player_id (or
## take your slot's id on a brand-new career), your number (swapping with
## whoever had it) and your weight.
func _join_club(club: String) -> void:
	var first_id := 1
	var carried_weight := -1.0
	var mine := player_roster_index()
	if mine >= 0:
		carried_weight = float(roster[mine].get("weight", -1.0))
	for entry in roster:
		first_id = maxi(first_id, int(entry.get("id", 0)) + 1)

	team_name = club
	roster = _league_roster(club)
	for i in roster.size():
		roster[i]["id"] = first_id + i
	var slot := RosterGenerator.roster_index_for_role(roster, position)
	if player_id <= 0:
		player_id = int(roster[slot]["id"])
	roster[slot]["id"] = player_id
	if carried_weight > 0.0:
		roster[slot]["weight"] = carried_weight
	var wanted_number := number
	number = int(roster[slot]["number"])
	_take_number(wanted_number)


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


## Called once, on character creation, after the identity fields and
## `difficulty` are set: every attribute on difficulty's start_level(), a
## fresh seed, a club and league in the first tier, an
## 18-player roster with you spliced into your position's slot, and the
## season's fixture. Overwrites any career in progress — the Dashboard's
## New Career asks before getting here. WEIGHT has no draft row (same
## "flavour only" status it has on the quick-play CHARACTER screen), so
## you keep your slot's generated weight.
func start_career() -> void:
	for key: String in ATTRIBUTE_RANGES:
		set_level(key, start_level(difficulty))
	upgrades_available = 0
	career_seed = _new_seed()
	league_index = 0
	season_index = 0
	season_history.clear()
	season_stats.clear()
	career_stats.clear()
	roster.clear()
	player_id = 0
	_ovr_cache.clear()
	_enter_league()
	_start_season()
	last_result = {}
	save()


## A club and 11 opponents for the current league, all drawn from that
## league's own name list so they never repeat within it.
func _enter_league() -> void:
	var names := RosterGenerator.generate_team_names(CareerSeason.LEAGUE_SIZE, _league_salt())
	league_teams.assign(names.slice(1))
	_join_club(names[0])


## This season's fixture: the league's teams in a per-season order, so a
## repeat season in the same league isn't the same draw again.
func _start_season() -> void:
	var order: Array[String] = league_teams.duplicate()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%d#season%d#%d" % [career_seed, league_index, season_index])
	for i in range(order.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := order[i]
		order[i] = order[j]
		order[j] = tmp
	rounds = CareerSeason.build_rounds(order, SEASON_LENGTH)


## Records the current round's result and advances to the next one. Score
## text is whatever MatchState.scoreline() produced for each side, kept as
## display strings; the points are kept as numbers for the ladder. The
## round's other games are scored here too (_sim_other_games()).
func record_result(result: Dictionary = {}) -> void:
	var index := games_played
	if index >= rounds.size():
		return
	var round_entry := rounds[index]
	round_entry["played"] = true
	for key in ["home_score", "away_score", "home_points", "away_points", "simulated"]:
		if result.has(key):
			round_entry[key] = result[key]
	_sim_other_games(index)
	# A real match (it carries the box score; a dev-simmed round doesn't)
	# earns upgrades. The count rides on the result for the full-time card.
	if result.get("player_stats") is Dictionary:
		_add_player_stats(result["player_stats"])
		upgrades_available += upgrades_per_game()
		result["upgrades"] = upgrades_per_game()
	if not result.is_empty():
		last_result = result
		last_result.erase("player_stats")   # folded in above; the card doesn't need it
	save()


## `stats` is FullGame's {roster id: {stat: n}} for every HOME player.
func _add_player_stats(stats: Dictionary) -> void:
	for id in stats:
		var key := int(id)
		var row: Dictionary = season_stats.get(key, {})
		season_stats[key] = row
		_add_line(row, stats[id])
		if key == player_id:
			_add_line(career_stats, stats[id])


func _add_line(into: Dictionary, match_line: Dictionary) -> void:
	into["games"] = int(into.get("games", 0)) + 1
	for stat: String in MatchState.PLAYER_STATS:
		into[stat] = int(into.get(stat, 0)) + int(match_line.get(stat, 0))


## A season_stats/career_stats line's count of `stat` — a PLAYER_STATS
## entry, "games", or "disposals" (kicks + handballs).
static func stat_total(line: Dictionary, stat: String) -> int:
	if stat == "disposals":
		return int(line.get("kicks", 0)) + int(line.get("handballs", 0))
	return int(line.get(stat, 0))


## This season's line for roster id `id` (empty before their first game).
func season_line(id: int) -> Dictionary:
	return season_stats.get(id, {})


## Dev-only (the Dashboard's debug key): scores your own game with the
## same off-screen sim as everyone else's and records it, so seasons can be
## run through without playing them. Marked "simulated" on the round.
func sim_current_round() -> void:
	if season_complete():
		return
	var opponent := current_fixture()
	var result := CareerSeason.sim_match(_game_key(games_played, team_name, opponent),
		CareerSeason.team_ovr(roster), _team_ovr(opponent))
	result["opponent"] = opponent
	result["simulated"] = true
	record_result(result)


func _sim_other_games(index: int) -> void:
	for game: Dictionary in rounds[index].get("others", []):
		var home := String(game["home"])
		var away := String(game["away"])
		game.merge(CareerSeason.sim_match(_game_key(index, home, away),
			_team_ovr(home), _team_ovr(away)), true)


func _game_key(index: int, home: String, away: String) -> String:
	return "%d|%d|%d|%d|%s|%s" % [career_seed, league_index, season_index, index, home, away]


func _team_ovr(team: String) -> float:
	var key := "%d|%d|%s" % [career_seed, league_index, team]
	if not _ovr_cache.has(key):
		_ovr_cache[key] = CareerSeason.team_ovr(_league_roster(team))
	return _ovr_cache[key]


func ladder() -> Array[Dictionary]:
	return CareerSeason.ladder(team_name, league_teams, rounds)


## Your place on the ladder, 1-based.
func ladder_position() -> int:
	var table := ladder()
	for i in table.size():
		if table[i]["you"]:
			return i + 1
	return table.size()


## What finishing where you are now means, once the season is over.
func season_outcome() -> String:
	var place := ladder_position()
	if CareerSeason.is_top_league(league_index):
		return OUTCOME_CHAMPIONS if place == 1 else OUTCOME_STAY
	return OUTCOME_PROMOTED if place <= Tuning.CAREER_PROMOTION_PLACES else OUTCOME_STAY


## season_outcome() in words, for the Dashboard and the Season Summary.
func season_outcome_text() -> String:
	match season_outcome():
		OUTCOME_PROMOTED:
			return "Promoted to %s" % CareerSeason.league_name(league_index + 1)
		OUTCOME_CHAMPIONS:
			return "Champions of %s" % CareerSeason.league_name(league_index)
	return "Another season in %s" % CareerSeason.league_name(league_index)


## Files the finished season and starts the next one: up a league with a
## new club if promoted, else the same league and club again.
func start_next_season() -> void:
	if not season_complete():
		return
	var outcome := season_outcome()
	var row: Dictionary = ladder()[ladder_position() - 1]
	season_history.append({
		"season": season_index + 1, "league": CareerSeason.league_name(league_index),
		"team": team_name, "position": ladder_position(), "played": row["played"],
		"won": row["won"], "lost": row["lost"], "drawn": row["drawn"], "outcome": outcome,
		"player": season_line(player_id).duplicate(),
	})
	season_stats.clear()
	season_index += 1
	if outcome == OUTCOME_PROMOTED:
		league_index += 1
		_enter_league()
	_start_season()
	last_result = {}
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
	config.set_value(SECTION, "difficulty", difficulty)
	config.set_value(SECTION, "position", int(position))
	config.set_value(SECTION, "number", number)
	config.set_value(SECTION, "foot", foot)
	config.set_value(SECTION, "levels", levels)
	config.set_value(SECTION, "upgrades_available", upgrades_available)
	config.set_value(SECTION, "model_id", model_id)
	config.set_value(SECTION, "skin_color", skin_color)
	config.set_value(SECTION, "jersey_color", jersey_color)
	config.set_value(SECTION, "shorts_color", shorts_color)
	config.set_value(SECTION, "boot_color", boot_color)
	config.set_value(SECTION, "socks_color", socks_color)
	config.set_value(SECTION, "team_name", team_name)
	config.set_value(SECTION, "career_seed", career_seed)
	config.set_value(SECTION, "league_index", league_index)
	config.set_value(SECTION, "season_index", season_index)
	config.set_value(SECTION, "league_teams", league_teams)
	config.set_value(SECTION, "season_history", season_history)
	config.set_value(SECTION, "season_stats", season_stats)
	config.set_value(SECTION, "career_stats", career_stats)
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
	difficulty = clampi(int(config.get_value(SECTION, "difficulty", DIFFICULTY_EASY)),
		DIFFICULTY_EASY, DIFFICULTY_HARD)
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

	upgrades_available = maxi(int(config.get_value(SECTION, "upgrades_available", 0)), 0)

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
	league_index = clampi(int(config.get_value(SECTION, "league_index", 0)),
		0, CareerSeason.LEAGUES.size() - 1)
	season_index = maxi(int(config.get_value(SECTION, "season_index", 0)), 0)
	league_teams.assign(config.get_value(SECTION, "league_teams", []))
	season_history.assign(config.get_value(SECTION, "season_history", []))
	var loaded_season_stats: Variant = config.get_value(SECTION, "season_stats", {})
	season_stats = loaded_season_stats if loaded_season_stats is Dictionary else {}
	var loaded_career_stats: Variant = config.get_value(SECTION, "career_stats", {})
	career_stats = loaded_career_stats if loaded_career_stats is Dictionary else {}

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
	if league_teams.is_empty() and not rounds.is_empty():
		_rebuild_legacy_season()
	_sync_player_entry()


## A save from before leagues (version 1, or version 2 before Phase 1) has
## 12 rounds against 12 different opponents and no other games, so there's
## no ladder to build. It becomes a 12-team league of the first 11
## opponents, rounds already played kept in order at the front of your
## fixture (with their results), and those rounds' other games scored.
## Those saves could only ever have played round 1 (the Dashboard locked
## after it), so nothing past that needs keeping.
func _rebuild_legacy_season() -> void:
	var played: Array[Dictionary] = []
	for round_entry in rounds:
		if not bool(round_entry.get("played", false)):
			break
		played.append(round_entry)
	var sequence: Array[String] = []
	for round_entry in played + rounds:
		var opponent := String(round_entry["opponent"])
		if not opponent in sequence and sequence.size() < CareerSeason.LEAGUE_SIZE - 1:
			sequence.append(opponent)
	league_teams.assign(sequence)
	rounds = CareerSeason.build_rounds(sequence, SEASON_LENGTH)
	for i in mini(played.size(), sequence.size()):
		rounds[i]["played"] = true
		for key in ["home_score", "away_score", "home_points", "away_points"]:
			if played[i].has(key):
				rounds[i][key] = played[i][key]
		# Version 1 kept only the "G.B (P)" text.
		for side in ["home", "away"]:
			if not rounds[i].has(side + "_points"):
				rounds[i][side + "_points"] = _points_in(String(rounds[i].get(side + "_score", "")))
		_sim_other_games(i)


## The P out of a "G.B (P)" scoreline, 0 if there isn't one.
static func _points_in(scoreline: String) -> int:
	var open := scoreline.find("(")
	var close := scoreline.find(")", open)
	if open < 0 or close < 0:
		return 0
	return scoreline.substr(open + 1, close - open - 1).to_int()


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
