class_name CareerSeason
extends RefCounted

## Career mode's league maths — stateless, same "static helper" shape as
## RosterGenerator (nothing here holds state between calls; CareerProfile
## owns the save and calls in).
##
## * LEAGUES is the pathway, Prototype 1's Hero ladder (hero_levels.py):
##   Juniors first, Country at the top. Each tier's generated players sit
##   in a higher attribute band (league_band()).
## * A league is 12 teams: you plus 11 opponents. build_rounds() is a
##   circle-method round robin — 11 rounds in which every team meets every
##   other once, then round 12 replays round 1 (a rematch) to make the
##   12-game season the original brief asked for.
## * sim_match() scores the five games each round that you're not in, so a
##   ladder exists at all. Seeded and stored at the time (CareerProfile.
##   record_result()), so re-tuning the sim later never rewrites a played
##   round. It is only ever used off-screen — see Tuning's CAREER_SIM_*.
## * ladder() is a pure function of the stored rounds: AFL premiership
##   points (4 a win, 2 a draw), percentage = points for / against × 100.

const LEAGUES := [
	{"name": "JUNIORS U18s", "tagline": "WHERE IT ALL STARTS"},
	{"name": "REPRESENTATIVE", "tagline": "PUT YOUR HAND UP"},
	{"name": "ACADEMY", "tagline": "THE PATHWAY GETS SERIOUS"},
	{"name": "SENIORS", "tagline": "MAN'S FOOTY NOW"},
	{"name": "STATE", "tagline": "PLAYING FOR THE JUMPER"},
	{"name": "COUNTRY", "tagline": "THE HIGHEST HONOUR THERE IS"},
]

const LEAGUE_SIZE := 12
const WIN_POINTS := 4
const DRAW_POINTS := 2


static func league_name(index: int) -> String:
	return String(LEAGUES[clampi(index, 0, LEAGUES.size() - 1)]["name"])


static func league_tagline(index: int) -> String:
	return String(LEAGUES[clampi(index, 0, LEAGUES.size() - 1)]["tagline"])


static func is_top_league(index: int) -> bool:
	return index >= LEAGUES.size() - 1


## Attribute levels a generated player in league `index` is drawn between.
## `shift` moves both ends (Career difficulty on the opposition, see
## CareerProfile.opponent_band()), each clamped to the level range.
static func league_band(index: int, shift := 0) -> Vector2i:
	var top := Tuning.CAREER_ATTRIBUTE_LEVELS
	var low := clampi(index + shift, 0, top)
	return Vector2i(low, clampi(index + Tuning.CAREER_LEAGUE_BAND_WIDTH + shift, low, top))


## `your_opponents` is the order you meet the 11 opponents in rounds 1-11
## (the caller shuffles it per season). The other five games each round
## follow from the circle method: you're fixed at position 0, the others
## rotate one place a round, and position k plays position 11 - k. Placing
## your sequence at position 11 (round r: order[(r + 10) % 11]) is what
## lets a caller choose your fixture order — the version-1 save rebuild
## needs that to keep a round it already played. Rounds past 11 replay the
## first ones with home and away swapped.
static func build_rounds(your_opponents: Array[String], season_length: int) -> Array[Dictionary]:
	var others := your_opponents.size()
	var order: Array[String] = []
	order.resize(others)
	for r in others:
		order[(r + others - 1) % others] = your_opponents[r]

	var base_rounds: Array[Dictionary] = []
	for r in others:
		var positions: Array[String] = [""]
		for k in range(1, others + 1):
			positions.append(order[(k - 1 + r) % others])
		var games: Array[Dictionary] = []
		for k in range(1, floori((others + 1) / 2.0)):
			games.append({"home": positions[k], "away": positions[others - k]})
		base_rounds.append({"opponent": positions[others], "others": games})

	var rounds: Array[Dictionary] = []
	for r in season_length:
		var base: Dictionary = base_rounds[r % others]
		var games: Array[Dictionary] = []
		for game: Dictionary in base["others"]:
			var swap := r >= others
			games.append({"home": game["away"] if swap else game["home"],
				"away": game["home"] if swap else game["away"]})
		rounds.append({"opponent": base["opponent"], "played": false, "others": games})
	return rounds


## Average OVERALL of a roster — what sim_match() weighs two sides by.
static func team_ovr(roster: Array[Dictionary]) -> float:
	if roster.is_empty():
		return 0.0
	var total := 0.0
	for entry in roster:
		total += RosterGenerator.overall(entry)
	return total / roster.size()


static func scoreline(goals: int, behinds: int) -> String:
	return "%d.%d (%d)" % [goals, behinds, goals * 6 + behinds]


## Both sides' scores for one off-screen game, from a seed that names the
## game (season, round and teams) so it comes out the same every time.
static func sim_match(seed_key: String, home_ovr: float, away_ovr: float) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed_key)
	var home := _sim_side(rng, home_ovr - away_ovr)
	var away := _sim_side(rng, away_ovr - home_ovr)
	return {
		"home_score": scoreline(home.x, home.y), "home_points": home.x * 6 + home.y,
		"away_score": scoreline(away.x, away.y), "away_points": away.x * 6 + away.y,
	}


static func _sim_side(rng: RandomNumberGenerator, ovr_advantage: float) -> Vector2i:
	var goals := rng.randfn(Tuning.CAREER_SIM_GOALS + Tuning.CAREER_SIM_GOALS_PER_OVR * ovr_advantage,
		Tuning.CAREER_SIM_GOALS_SD)
	var behinds := rng.randfn(Tuning.CAREER_SIM_BEHINDS, Tuning.CAREER_SIM_BEHINDS_SD)
	return Vector2i(maxi(roundi(goals), 0), maxi(roundi(behinds), 0))


## One row per team, best first: {team, you, played, won, lost, drawn,
## points_for, points_against, percentage, points}. Ties on points go to
## percentage, then name, so the order never wobbles.
static func ladder(your_team: String, opponents: Array[String], rounds: Array[Dictionary]) -> Array[Dictionary]:
	var rows := {}
	for team: String in [your_team] + opponents:
		rows[team] = {"team": team, "you": team == your_team, "played": 0, "won": 0, "lost": 0,
			"drawn": 0, "points_for": 0, "points_against": 0, "percentage": 0.0, "points": 0}
	for round_entry in rounds:
		if not bool(round_entry.get("played", false)):
			continue
		_add_game(rows, your_team, String(round_entry["opponent"]),
			int(round_entry.get("home_points", 0)), int(round_entry.get("away_points", 0)))
		for game: Dictionary in round_entry.get("others", []):
			if game.has("home_points"):
				_add_game(rows, String(game["home"]), String(game["away"]),
					int(game["home_points"]), int(game["away_points"]))

	var table: Array[Dictionary] = []
	for row: Dictionary in rows.values():
		var against := int(row["points_against"])
		row["percentage"] = float(row["points_for"]) / against * 100.0 if against > 0 \
			else (100.0 if int(row["points_for"]) == 0 else 999.9)
		table.append(row)
	table.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["points"] != b["points"]:
			return a["points"] > b["points"]
		if not is_equal_approx(a["percentage"], b["percentage"]):
			return a["percentage"] > b["percentage"]
		return String(a["team"]) < String(b["team"]))
	return table


static func _add_game(rows: Dictionary, home: String, away: String, home_points: int,
		away_points: int) -> void:
	for side: Array in [[home, home_points, away_points], [away, away_points, home_points]]:
		if not rows.has(side[0]):
			continue
		var row: Dictionary = rows[side[0]]
		var scored: int = side[1]
		var conceded: int = side[2]
		row["played"] += 1
		row["points_for"] += scored
		row["points_against"] += conceded
		if scored > conceded:
			row["won"] += 1
			row["points"] += WIN_POINTS
		elif scored < conceded:
			row["lost"] += 1
		else:
			row["drawn"] += 1
			row["points"] += DRAW_POINTS


## "1st", "2nd", "3rd", "4th" ... "11th", "12th".
static func ordinal(n: int) -> String:
	var suffix := "th"
	if n % 100 < 11 or n % 100 > 13:
		match n % 10:
			1: suffix = "st"
			2: suffix = "nd"
			3: suffix = "rd"
	return "%d%s" % [n, suffix]
