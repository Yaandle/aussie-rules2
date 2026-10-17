class_name RosterGenerator
extends RefCounted

## Procedural rosters for Career mode — stateless, same "static-style
## helper class" shape as TeamFormation/RetroWindow/SoftBrutalist (no
## autoload needed, nothing here holds state between calls).
##
## Every generated team is seeded off a hash of its own name
## (RandomNumberGenerator.seed), so calling generate_team("ST KILDA
## HAWKS") twice always produces the same roster without persisting every
## opponent's 18 players up front — only the player's own team (Career
## Profile.roster) is actually saved; an opponent's roster is rebuilt from
## its fixture name right before that match, see career_pregame_screen.gd.

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


## 18 {name: String, role: TeamFormation.Role, number: int} dicts in
## roster-spawn order (index i's role == TeamFormation.roster_slot(i).role
## — the same order full_game.gd's own spawn loop walks), so a caller can
## read roster[i]["name"] straight alongside TeamFormation.roster_slot(i)
## with no further lookup.
static func generate_team(team_name: String) -> Array[Dictionary]:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(team_name)

	var numbers := range(1, TeamFormation.SLOTS.size() + 1)
	_shuffle(rng, numbers)

	var roster: Array[Dictionary] = []
	for i in TeamFormation.SLOTS.size():
		var slot: Dictionary = TeamFormation.roster_slot(i)
		roster.append({
			"name": _generate_name(rng),
			"role": slot["role"],
			"number": numbers[i],
		})
	return roster


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


## `count` unique "{Suburb} {Mascot}" fixture names, order shuffled off a
## fixed seed so the season's opponent list is stable across loads
## without persisting anything beyond the names themselves (see
## CareerProfile.fixtures).
static func generate_team_names(count: int) -> Array[String]:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("career_fixtures")

	var combos: Array[String] = []
	for suburb in SUBURBS:
		for mascot in MASCOTS:
			combos.append("%s %s" % [suburb, mascot])
	_shuffle(rng, combos)
	return combos.slice(0, mini(count, combos.size()))


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
