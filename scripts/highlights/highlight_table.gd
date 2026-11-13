class_name HighlightTable
extends RefCounted

## Every number the Highlights feature ranks and cuts moments by, in one
## place, so the ranking can be adjusted without reading the detector.
##
## None of this feeds gameplay. The recorder (highlight_recorder.gd) only
## listens to signals the match already emits and reads public state; these
## numbers decide which of those events become a highlight, how they rank,
## and how much lead-in and play-out each clip gets. All of them are
## unplaytested feel guesses (2026-11-08) unless a comment says otherwise.
##
## Score = TYPES[type].base + the bonuses that apply. Moments under
## MIN_SCORE are dropped. Each type has its own memory cap (TYPES[type].cap:
## the best that many are kept) so a run of goals can't push every tackle
## out of memory, and its own default tick count (TYPES[type].keep: the best
## that many start ticked for export when the type's toggle is on). A type's
## toggle, its default camera and the export format live in HighlightPrefs.

## Recording rate for the replay buffer, frames per second. Exports render
## at this rate too (EXPORT_FPS), so a clip's frames map one to one.
const RECORD_FPS := 30
## Seconds of history the rolling buffer holds. Must cover the longest
## lead-in (GOAL_MAX_LEAD) plus a margin.
const BUFFER_SECONDS := 20.0

const MIN_SCORE := 15.0
## Score added when the human's own player is in the moment.
const HUMAN_BONUS := 10.0

## Per type: base score, seconds of lead-in before the event and play-out
## after it, and a display name. `enabled` false drops the type entirely.
## `cap` is how many of the type are held in memory (best first) and `keep`
## how many of them start ticked; `plural` and `default_on` are for the
## Highlights screen's toggles (default_on is only the first-run value: the
## player's choice is saved in HighlightPrefs). Caps and keeps are unplaytested
## feel guesses (2026-11-11): one clip is ~5-10 MB, so the caps hold the lot
## to roughly 250 MB. A behind's base sits just over MIN_SCORE: it has no
## bonuses, so at the old 8 none ever survived and the BEHINDS toggle was
## always empty.
const TYPES := {
	"goal":      {"enabled": true, "base": 60.0, "lead": 4.0, "out": 3.5, "label": "GOAL", "plural": "GOALS",
		"cap": 10, "keep": 6, "default_on": true},
	"behind":    {"enabled": true, "base": 16.0, "lead": 4.0, "out": 2.5, "label": "BEHIND", "plural": "BEHINDS",
		"cap": 4, "keep": 2, "default_on": true},
	"mark":      {"enabled": true, "base": 22.0, "lead": 3.0, "out": 2.0, "label": "MARK", "plural": "MARKS",
		"cap": 10, "keep": 5, "default_on": true},
	"tackle":    {"enabled": true, "base": 25.0, "lead": 3.0, "out": 3.0, "label": "TACKLE", "plural": "TACKLES",
		"cap": 12, "keep": 5, "default_on": true},
	"bump":      {"enabled": true, "base": 18.0, "lead": 2.5, "out": 2.5, "label": "BUMP", "plural": "BUMPS",
		"cap": 8, "keep": 3, "default_on": true},
	"long_kick": {"enabled": true, "base": 14.0, "lead": 2.0, "out": 4.0, "label": "LONG KICK", "plural": "LONG KICKS",
		"cap": 5, "keep": 2, "default_on": false},
	"ruck":      {"enabled": true, "base": 6.0,  "lead": 2.0, "out": 3.0, "label": "RUCK", "plural": "RUCKS",
		"cap": 4, "keep": 2, "default_on": false},
	# A passage with no single headline event: a chain of disposals or a run
	# with bounces. `lead` here is the shortest; the recorder stretches it
	# back to where the passage began (GENERAL_MAX_LEAD).
	"general":   {"enabled": true, "base": 12.0, "lead": 3.0, "out": 3.0, "label": "GENERAL PLAY", "plural": "GENERAL PLAY",
		"cap": 6, "keep": 3, "default_on": false},
}
## The order the toggles are listed in.
const TYPE_ORDER := ["goal", "behind", "mark", "tackle", "bump", "long_kick", "ruck", "general"]

# ── Goals and behinds ────────────────────────────────────────────────
## A goal's lead-in stretches back to the kick that scored it (plus this
## much run-up), up to GOAL_MAX_LEAD seconds before the ball crosses.
const GOAL_KICK_RUNUP := 1.5
const GOAL_MAX_LEAD := 8.0
## Per metre of kick distance past GOAL_DISTANCE_FREE.
const GOAL_DISTANCE_FREE := 25.0
const GOAL_PER_METRE := 0.6
const GOAL_ON_THE_RUN := 10.0      ## not a set shot from a mark or free kick
const GOAL_AFTER_SIREN := 25.0
const GOAL_GO_AHEAD := 15.0        ## takes the lead, or levels it
const GOAL_CLOSE_MARGIN := 6       ## points; a margin this close after the score
const GOAL_CLOSE_BONUS := 8.0
## A passage of play: this many team disposals in a row before the score,
## and so much per disposal past it, up to the cap.
const CHAIN_FREE := 2
const CHAIN_PER_DISPOSAL := 4.0
const CHAIN_CAP := 20.0

# ── Marks ────────────────────────────────────────────────────────────
## An opponent this close to the marker when it sticks makes it contested.
const MARK_CONTEST_RADIUS := 2.0
const MARK_CONTESTED := 20.0
const MARK_AGGRESSIVE_TIER := 12.0  ## the leaping (Aggressive) mark
const MARK_RUNNING_TIER := 4.0
## Ball height at the catch: per metre over MARK_HIGH_FROM.
const MARK_HIGH_FROM := 2.3
const MARK_HIGH_PER_METRE := 16.0
const MARK_INSIDE_50 := 5.0

# ── Tackles and bumps ────────────────────────────────────────────────
const TACKLE_SLING := 20.0
const TACKLE_TAKEDOWN := 14.0
const TACKLE_RAGDOLL := 10.0        ## the tackled body ragdolled to the turf
const TACKLE_HOLDING_THE_BALL := 15.0
## Tackler's speed at the commit: per m/s over TACKLE_SPEED_FREE.
const TACKLE_SPEED_FREE := 4.0
const TACKLE_PER_MS := 2.5
## How long after the commit the outcome (sling, ragdoll, free kick) is
## looked for before the moment is scored.
const TACKLE_OUTCOME_WINDOW := 0.6
const BUMP_CLEAN := 10.0
const BUMP_RAGDOLL := 10.0

# ── General play ─────────────────────────────────────────────────────
## A passage is one team's unbroken possession: this many kicks and handballs
## in a row, or this many bounces. Scored low (the base above) so it only
## outranks nothing else in its own list; off by default.
const GENERAL_MIN_DISPOSALS := 3
const GENERAL_MIN_BOUNCES := 2
const GENERAL_PER_DISPOSAL := 3.0       ## per disposal from GENERAL_MIN_DISPOSALS on
const GENERAL_PER_BOUNCE := 4.0
const GENERAL_PER_METRE := 0.12         ## ground gained toward goal over the passage
const GENERAL_CAP := 20.0
## The passage ends when the other side gathers it, or after this long
## with no disposal.
const GENERAL_MAX_GAP := 8.0
const GENERAL_MAX_LEAD := 9.0
const GENERAL_RUNUP := 1.5

# ── Kicks and rucks ──────────────────────────────────────────────────
const LONG_KICK_FROM := 55.0        ## metres in the air before it counts
const LONG_KICK_PER_METRE := 0.5
const RUCK_TO_ADVANTAGE := 10.0     ## own side gathers soon after the hit-out
const RUCK_ADVANTAGE_WINDOW := 2.0

# ── Export ───────────────────────────────────────────────────────────
const EXPORT_FPS := RECORD_FPS
const EXPORT_LANDSCAPE := Vector2i(1920, 1080)
const EXPORT_PORTRAIT := Vector2i(1080, 1920)
const EXPORT_JPEG_QUALITY := 0.9
## Which shapes an export renders. "both" draws every frame twice, so 16:9
## or 9:16 alone is half the render.
const ASPECTS := ["both", "16x9", "9x16"]
const ASPECT_LABELS := {"both": "16:9 + 9:16", "16x9": "16:9 only", "9x16": "9:16 only"}


## A one-line caption for a moment, from its type and the facts the
## recorder kept (`moment.facts`). Plain templates: the video agent is
## free to rewrite them.
static func caption(moment: Dictionary) -> String:
	var facts: Dictionary = moment.get("facts", {})
	var who := String(facts.get("player", "A player"))
	var other := String(facts.get("opponent", "an opponent"))
	var dist := int(round(float(facts.get("distance", 0.0))))
	match String(moment.type):
		"goal":
			if facts.get("own_goal", false):
				return "%s's kick goes through his own goal from %d m" % [who, dist]
			if facts.get("no_kick", false):
				return "The ball rolls through for a goal"
			var line := "%s kicks a goal from %d m" % [who, dist]
			if facts.get("after_siren", false):
				return line + " after the siren!"
			if facts.get("go_ahead", false):
				return line + " to hit the front"
			if int(facts.get("chain", 0)) > CHAIN_FREE:
				return line + " to finish a %d-kick chain" % int(facts.chain)
			if facts.get("on_the_run", false):
				return line + " on the run"
			return line
		"behind":
			if facts.get("own_goal", false):
				return "%s's kick goes through his own behind from %d m" % [who, dist]
			return "%s just misses from %d m" % [who, dist]
		"mark":
			if facts.get("contested", false) and facts.get("high", false):
				return "%s flies over %s for a big contested grab" % [who, other]
			if facts.get("contested", false):
				return "%s holds a strong contested mark over %s" % [who, other]
			if facts.get("high", false):
				return "%s takes a towering mark" % who
			return "%s marks it cleanly" % who
		"tackle":
			var how := String(facts.get("kind", "tackle"))
			if how == "sling":
				return "%s slings %s to the turf" % [who, other]
			if how == "takedown":
				return "%s drags %s down" % [who, other]
			if facts.get("holding_the_ball", false):
				return "%s pins %s: holding the ball" % [who, other]
			return "%s wraps up %s" % [who, other]
		"bump":
			return "%s lays a %sbump on %s" % [who, "clean " if facts.get("clean", false) else "", other]
		"long_kick":
			return "%s launches one %d m" % [who, dist]
		"ruck":
			return "%s wins the hit-out%s" % [who,
				" to advantage" if facts.get("to_advantage", false) else ""]
		"general":
			var bits: Array[String] = []
			if int(facts.get("disposals", 0)) > 0:
				bits.append("%d disposals" % int(facts.disposals))
			if int(facts.get("bounces", 0)) > 0:
				bits.append("%d bounce%s" % [int(facts.bounces), "" if int(facts.bounces) == 1 else "s"])
			return "%s move it on: %s, %d m gained" % [String(facts.get("team", "A team")),
				", ".join(bits), int(round(float(facts.get("metres", 0.0))))]
	return "%s" % who
