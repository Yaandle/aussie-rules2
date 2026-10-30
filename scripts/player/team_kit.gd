class_name TeamKit
extends RefCounted

## Resolves the kit (jersey/shorts/socks/shoes) a HumanoidRig wears when no
## explicit kit_* override is set — the task-board 4B "Customisation" pass.
## HumanoidRig used to fall back to fixed constants here, and AWAY differed
## from HOME only on the procedural body's jersey (an imported model kept its
## Blender materials, so the opposition looked identical to you in-match).
##
## HOME wears the player's own CHARACTER-screen kit (CharacterProfile; in a
## Career match a non-empty CareerProfile colour wins, slot by slot), falling
## back to the rig's original constants for any slot left unset. AWAY never
## has its own picker: it takes the first AWAY_PRESETS entry whose jersey
## reads as different enough from HOME's (contrast() >= Tuning.
## AWAY_KIT_MIN_CONTRAST), or the most contrasting one if none clears the bar.
## So the opposition is always readable whatever colour you choose, and with
## the default gold HOME kit it stays the red it always was.
##
## Static only, read at rig build time — called 32 times per full-game spawn,
## so it stays cheap (a handful of Color comparisons, no allocation beyond
## the returned Dictionary).

const SLOTS := ["jersey", "shorts", "socks", "boot"]

## The rig's pre-4B look, slot by slot. HumanoidRig's own constants are the
## source of truth; duplicated as one table so resolution stays a loop.
static func default_home() -> Dictionary:
	return {
		"jersey": HumanoidRig.COLOUR_GUERNSEY,
		"shorts": HumanoidRig.COLOUR_SHORTS,
		"socks": HumanoidRig.COLOUR_TRIM,
		"boot": HumanoidRig.COLOUR_BOOT,
	}


## Ordered by preference. The first is the original away guernsey (red),
## given white shorts so it still separates from HOME's dark shorts at
## broadcast distance; the rest are fallbacks for a HOME kit too close to it.
const AWAY_PRESETS := [
	{"jersey": Color("#c95f55"), "shorts": Color("#f0ece0"), "socks": Color("#c95f55"), "boot": Color("#22241d")},
	{"jersey": Color("#1f3f7a"), "shorts": Color("#f0ece0"), "socks": Color("#1f3f7a"), "boot": Color("#22241d")},
	{"jersey": Color("#f0ece0"), "shorts": Color("#1f2d4a"), "socks": Color("#f0ece0"), "boot": Color("#22241d")},
	{"jersey": Color("#2e7d4f"), "shorts": Color("#f0ece0"), "socks": Color("#2e7d4f"), "boot": Color("#22241d")},
]


## slot -> Color, for the given team. Anything not HOME (AWAY, NONE) gets
## the away kit — NONE never builds a player body, so that's moot.
static func colours(away: bool) -> Dictionary:
	var home := home_kit()
	return away_kit_against(home) if away else home


static func home_kit() -> Dictionary:
	var kit := default_home()
	var hexes := {
		"jersey": CharacterProfile.jersey_color,
		"shorts": CharacterProfile.shorts_color,
		"socks": CharacterProfile.socks_color,
		"boot": CharacterProfile.boot_color,
	}
	if GameState.career_active:
		for slot: String in SLOTS:
			var career_hex: String = CareerProfile.get(slot + "_color")
			if not career_hex.is_empty():
				hexes[slot] = career_hex
	for slot: String in SLOTS:
		var hex: String = hexes[slot]
		if not hex.is_empty():
			kit[slot] = Color(hex)
	return kit


static func away_kit_against(home: Dictionary) -> Dictionary:
	var best: Dictionary = AWAY_PRESETS[0]
	var best_score := -1.0
	for preset: Dictionary in AWAY_PRESETS:
		var score := contrast(preset["jersey"], home["jersey"])
		if score >= Tuning.AWAY_KIT_MIN_CONTRAST:
			return preset.duplicate()
		if score > best_score:
			best_score = score
			best = preset
	return best.duplicate()


## Rough "do these read as different teams" score: straight RGB distance
## plus the luminance gap, since two colours of similar brightness (gold vs
## orange) blur together on a small figure far more than hue alone suggests.
static func contrast(a: Color, b: Color) -> float:
	var rgb := Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()
	return rgb + absf(a.get_luminance() - b.get_luminance())
