class_name DrillLibrary
extends RefCounted

## The training drills (TrainingScreen), as data. Playtest 2026-10-30: "I
## want to take the real-life training structure I'll run and replicate it
## in-game: map out how the drill works, simulate it in the environment,
## and play the drill with bots." So a drill is written down the way a
## coach draws one up: where the cones go, who stands where, then the beats
## in order. DrillRunner plays it on loop with bots, and with you in one of
## the roles when you play it. The three below are starters to show the
## format; a real session's drills go in alongside them.
##
## Positions are drill-local metres, Vector2(x, z): +x is up the ground
## (toward the attacking goal), +z to the right of that. The drill's centre
## is placed at the field centre.
##
##   name        list title
##   summary     a line or two under it: what the drill trains
##   cones       Array[Vector2] of cone spots
##   roles       [{"name", "at": Vector2}], in order. A role's index is how
##               beats refer to it.
##   play_role   the role you take when you play it
##   ball_to     the role holding the ball at the start
##   beats       in order, looping. Each:
##     text      the step, as the coach would call it
##     do        [{"role", and one of:
##                  "run_to": Vector2   (+ "gait" 0..1, default 0.8)
##                  "kick_to": role     (kicks to where they're leading)
##                  "handball_to": role
##                "delay": s after the beat starts, default 0}]
##     until     "caught" (role "by" has the ball), "arrived" (everyone
##               told to run_to is there) or "time" (after "time" s)
##     reset     true: everyone back to their start, ball to ball_to
##   A beat that hasn't finished after "timeout" s (default 10; never, for
##   one where you're the one acting) runs again from where it started.

const DRILLS: Array[Dictionary] = [
	{
		"name": "Kick to kick",
		"summary": "Two lines 30 m apart kick to each other. Hit your partner on the chest, every time.",
		"cones": [Vector2(-15.0, -3.0), Vector2(-15.0, 3.0), Vector2(15.0, -3.0), Vector2(15.0, 3.0)],
		"roles": [
			{"name": "Line A", "at": Vector2(-15.0, 0.0)},
			{"name": "Line B", "at": Vector2(15.0, 0.0)},
		],
		"play_role": 0,
		"ball_to": 0,
		"beats": [
			{"text": "A kicks to B", "do": [{"role": 0, "kick_to": 1, "delay": 0.6}], "until": "caught", "by": 1},
			{"text": "B kicks back to A", "do": [{"role": 1, "kick_to": 0, "delay": 0.6}], "until": "caught", "by": 0},
		],
	},
	{
		"name": "Lead and hit",
		"summary": "The leader breaks from the cone at 45° toward the kicker, who hits them on the lead. They turn and find the target up the ground.",
		"cones": [Vector2(-20.0, 0.0), Vector2(12.0, -8.0), Vector2(0.0, 2.0), Vector2(32.0, 0.0)],
		"roles": [
			{"name": "Kicker", "at": Vector2(-20.0, 0.0)},
			{"name": "Leader", "at": Vector2(12.0, -8.0)},
			{"name": "Target", "at": Vector2(32.0, 0.0)},
		],
		"play_role": 0,
		"ball_to": 0,
		"beats": [
			{"text": "Leader breaks at 45° back toward the kicker",
				"do": [{"role": 1, "run_to": Vector2(0.0, 2.0), "gait": 0.95},
					{"role": 0, "kick_to": 1, "delay": 1.1}],
				"until": "caught", "by": 1},
			{"text": "Leader turns and kicks to the target",
				"do": [{"role": 1, "kick_to": 2, "delay": 0.5}], "until": "caught", "by": 2},
			{"text": "Everyone back to their start", "reset": true, "until": "time", "time": 1.0},
		],
	},
	{
		"name": "Handball triangle",
		"summary": "Three players, 8 m apart. Hands to hands round the triangle, quick and clean.",
		"cones": [Vector2(0.0, 0.0), Vector2(7.0, 4.0), Vector2(7.0, -4.0)],
		"roles": [
			{"name": "Point", "at": Vector2(0.0, 0.0)},
			{"name": "Left", "at": Vector2(7.0, -4.0)},
			{"name": "Right", "at": Vector2(7.0, 4.0)},
		],
		"play_role": 0,
		"ball_to": 0,
		"beats": [
			{"text": "Point handballs to Left", "do": [{"role": 0, "handball_to": 1, "delay": 0.4}], "until": "caught", "by": 1},
			{"text": "Left handballs to Right", "do": [{"role": 1, "handball_to": 2, "delay": 0.4}], "until": "caught", "by": 2},
			{"text": "Right handballs to Point", "do": [{"role": 2, "handball_to": 0, "delay": 0.4}], "until": "caught", "by": 0},
		],
	},
]
