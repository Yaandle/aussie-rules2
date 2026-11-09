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
## MIN_SCORE are dropped; the best MAX_MOMENTS are kept in memory; the best
## DEFAULT_KEEP start ticked for export on the Highlights screen.

## Recording rate for the replay buffer, frames per second. Exports render
## at this rate too (EXPORT_FPS), so a clip's frames map one to one.
const RECORD_FPS := 30
## Seconds of history the rolling buffer holds. Must cover the longest
## lead-in (GOAL_MAX_LEAD) plus a margin.
const BUFFER_SECONDS := 20.0

const MIN_SCORE := 15.0
const MAX_MOMENTS := 24
const DEFAULT_KEEP := 8
## Score added when the human's own player is in the moment.
const HUMAN_BONUS := 10.0

## Per type: base score, seconds of lead-in before the event and play-out
## after it, and a display name. `enabled` false drops the type entirely.
const TYPES := {
	"goal":      {"enabled": true, "base": 60.0, "lead": 4.0, "out": 3.5, "label": "GOAL"},
	"behind":    {"enabled": true, "base": 8.0,  "lead": 4.0, "out": 2.5, "label": "BEHIND"},
	"mark":      {"enabled": true, "base": 22.0, "lead": 3.0, "out": 2.0, "label": "MARK"},
	"tackle":    {"enabled": true, "base": 25.0, "lead": 3.0, "out": 3.0, "label": "TACKLE"},
	"bump":      {"enabled": true, "base": 18.0, "lead": 2.5, "out": 2.5, "label": "BUMP"},
	"long_kick": {"enabled": true, "base": 14.0, "lead": 2.0, "out": 4.0, "label": "LONG KICK"},
	"ruck":      {"enabled": true, "base": 6.0,  "lead": 2.0, "out": 3.0, "label": "RUCK"},
}

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
	return "%s" % who
