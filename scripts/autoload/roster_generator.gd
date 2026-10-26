class_name RosterGenerator
extends RefCounted

## Procedural rosters for Career mode — stateless, same "static-style
## helper class" shape as TeamFormation/RetroWindow/SoftBrutalist (no
## autoload needed, nothing here holds state between calls).
##
## Every generated team is seeded off a hash of its own name plus a salt
## (RandomNumberGenerator.seed), so calling generate_team("ST KILDA
## HAWKS", salt) twice always produces the same roster without persisting
## every opponent's 18 players up front — only the player's own team
## (CareerProfile.roster) is actually saved; an opponent's roster is
## rebuilt from its fixture name right before that match, see
## CareerProfile.opponent_roster(). The salt is CareerProfile.career_seed,
## so each career gets its own teams; 0 hashes the name alone, which is how
## every career was seeded before salts existed (a version-1 save keeps its
## opponents that way).

const FIRST_NAMES := [
	"Jack", "Noah", "Oliver", "Lachlan", "Ethan", "Cooper", "Mason", "Will",
	"Hunter", "Flynn", "Harrison", "Archer", "Riley", "Charlie", "Tom",
	"Max", "Sam", "Josh", "Ben", "Liam", "Nate", "Toby", "Jasper", "Leo",
]

const LAST_NAMES := [
	"Walsh", "Hogan", "Pickett", "Petracca", "Cripps", "Oliver", "Neale",
	"Daicos", "Ahern", "Sheezel", "Rankine", "Treacy", "Darcy", "Green",
	"Bont", "Serong", "Rowell", "Mills", "English", "Setterfield",
]

## "{Suburb} {Mascot}" word bank for the 12 fixture names — plausible
## juniors-club names, not real AFL club names.
const SUBURBS := [
	"Brookfield", "Carrum", "Dandenong", "Eltham", "Fawkner", "Glenroy",
	"Hartwell", "Ivanhoe", "Jindivick", "Kingsley", "Lilydale", "Morwell",
]

const MASCOTS := [
	"Hawks", "Magpies", "Tigers", "Bombers", "Saints", "Demons", "Blues",
	"Swans", "Eagles", "Lions", "Suns", "Power",
]

## Juniors U18-plausible physical range for a generated teammate — not a
## real tracked gameplay stat anywhere (same "nothing reads it" status
## character_screen.gd's own locked WEIGHT row already has), purely for
## the roster table's HEIGHT/WEIGHT columns. Height reuses CharacterProfile's
## own real range instead of inventing a second one.
const HEIGHT_MIN := Tuning.CHARACTER_HEIGHT_MIN
const HEIGHT_MAX := Tuning.CHARACTER_HEIGHT_MAX
const WEIGHT_MIN := 58.0
const WEIGHT_MAX := 92.0


## 18 {name, role, number, height, weight, speed, kick_power,
## kick_accuracy, agility} dicts in roster-spawn order (index i's role ==
## TeamFormation.roster_slot(i).role — the same order full_game.gd's own
## spawn loop walks), so a caller can read roster[i]["name"] straight
## alongside TeamFormation.roster_slot(i) with no further lookup. The
## four attribute fields are random within the same Tuning ranges the
## Career/quick-play character screens draft from, so a generated
## teammate's OVERALL (see overall()) sits on the same scale a created
## player's does. `band` narrows them to a span of Career attribute levels
## (CareerSeason.league_band() — a Juniors side is weaker than a State
## one); the default is the whole range.
const FULL_BAND := Vector2i(0, Tuning.CAREER_ATTRIBUTE_LEVELS)

static func generate_team(team_name: String, salt := 0, band := FULL_BAND) -> Array[Dictionary]:
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed(team_name, salt)

	var numbers := range(1, TeamFormation.SLOTS.size() + 1)
	_shuffle(rng, numbers)

	var roster: Array[Dictionary] = []
	for i in TeamFormation.SLOTS.size():
		var slot: Dictionary = TeamFormation.roster_slot(i)
		roster.append({
			"name": _generate_name(rng),
			"role": slot["role"],
			"number": numbers[i],
			"height": rng.randf_range(HEIGHT_MIN, HEIGHT_MAX),
			"weight": rng.randf_range(WEIGHT_MIN, WEIGHT_MAX),
			"speed": _banded(rng, Tuning.CHARACTER_SPEED_MIN, Tuning.CHARACTER_SPEED_MAX, band),
			"kick_power": _banded(rng, Tuning.CHARACTER_KICK_POWER_MIN,
				Tuning.CHARACTER_KICK_POWER_MAX, band),
			"kick_accuracy": _banded(rng, Tuning.CHARACTER_KICK_ACCURACY_MIN,
				Tuning.CHARACTER_KICK_ACCURACY_MAX, band),
			"agility": _banded(rng, Tuning.CHARACTER_AGILITY_MIN, Tuning.CHARACTER_AGILITY_MAX, band),
		})
	return roster


## One random draw between `band`'s two levels, as a value in vmin..vmax.
## With FULL_BAND this is the same single draw randf_range(vmin, vmax) was.
static func _banded(rng: RandomNumberGenerator, vmin: float, vmax: float, band: Vector2i) -> float:
	var t := rng.randf_range(float(band.x), float(band.y)) / Tuning.CAREER_ATTRIBUTE_LEVELS
	return lerpf(vmin, vmax, t)


## 0..100 rating from a roster entry's four performance attributes
## (height/weight/number don't factor in — they're physical/identity,
## not skill), each normalised against the same Tuning range the
## character screens draft within, then averaged. Works for both a
## generated teammate's random attributes and the created player's real
## drafted ones, since both are stored in the same shape (see
## generate_team()'s own header note).
static func overall(entry: Dictionary) -> int:
	var total := 0.0
	total += _normalised(entry.get("speed", Tuning.CHARACTER_SPEED_DEFAULT),
		Tuning.CHARACTER_SPEED_MIN, Tuning.CHARACTER_SPEED_MAX)
	total += _normalised(entry.get("kick_power", Tuning.CHARACTER_KICK_POWER_DEFAULT),
		Tuning.CHARACTER_KICK_POWER_MIN, Tuning.CHARACTER_KICK_POWER_MAX)
	total += _normalised(entry.get("kick_accuracy", Tuning.CHARACTER_KICK_ACCURACY_DEFAULT),
		Tuning.CHARACTER_KICK_ACCURACY_MIN, Tuning.CHARACTER_KICK_ACCURACY_MAX)
	total += _normalised(entry.get("agility", Tuning.CHARACTER_AGILITY_DEFAULT),
		Tuning.CHARACTER_AGILITY_MIN, Tuning.CHARACTER_AGILITY_MAX)
	return int(round(total / 4.0))


static func _normalised(value: float, vmin: float, vmax: float) -> float:
	if vmax <= vmin:
		return 50.0
	return clampf((value - vmin) / (vmax - vmin), 0.0, 1.0) * 100.0


## Index into a generate_team() result whose role matches `role` — used to
## splice the Career player's own created character into the generated
## team at the slot their chosen position actually occupies. -1 if
## `role` somehow isn't one of TeamFormation.SLOTS' roles (can't happen
## with a role the character screen's own picker offered).
static func roster_index_for_role(roster: Array[Dictionary], role: TeamFormation.Role) -> int:
	for i in roster.size():
		if roster[i]["role"] == role:
			return i
	return -1


## `count` unique "{Suburb} {Mascot}" fixture names, order shuffled off
## `salt` (see the header) — CareerProfile saves the names it gets.
static func generate_team_names(count: int, salt := 0) -> Array[String]:
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed("career_fixtures", salt)

	var combos: Array[String] = []
	for suburb in SUBURBS:
		for mascot in MASCOTS:
			combos.append("%s %s" % [suburb, mascot])
	_shuffle(rng, combos)
	return combos.slice(0, mini(count, combos.size()))


static func _seed(key: String, salt: int) -> int:
	return hash(key) if salt == 0 else hash("%s#%d" % [key, salt])


static func _generate_name(rng: RandomNumberGenerator) -> String:
	var first: String = FIRST_NAMES[rng.randi() % FIRST_NAMES.size()]
	var last: String = LAST_NAMES[rng.randi() % LAST_NAMES.size()]
	return "%s %s" % [first, last]


## Fisher-Yates — RandomNumberGenerator has no shuffle of its own (that's
## only on the global `randomize()`-seeded RNG), and this needs a seeded,
## reproducible one.
static func _shuffle(rng: RandomNumberGenerator, values: Array) -> void:
	for i in range(values.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = values[i]
		values[i] = values[j]
		values[j] = tmp
