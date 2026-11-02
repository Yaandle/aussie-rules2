class_name DrillLibrary
extends RefCounted

## The training drills (TrainingScreen), as data. Playtest 2026-10-30: "I
## want to take the real-life training structure I'll run and replicate it
## in-game: map out how the drill works, simulate it in the environment,
## and play the drill with bots." So a drill is written down the way a
## coach draws one up: where the cones go, who stands where, then the beats
## in order. DrillRunner plays it on loop with bots, and with you in one of
## the roles when you play it. The first three are starters to show the
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
##     swap      [role, role]: once the beat's done, the two players trade
##               roles (a rotation; you go with your player)
##   A beat that hasn't finished after "timeout" s (default 10; never, for
##   one where you're the one acting) runs again from where it started.

static var DRILLS: Array[Dictionary] = [
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
	## The first of the user's own session drills (2026-11-02), in two
	## versions: D's lead straight back at A, and the progression where D
	## spreads away at 45°. A → B straight, B → C into C's 45° lead, C hands
	## off to A who has followed their kick the whole way, A → D. Then D jogs
	## back to A's cone with the ball and is the next A while A goes up to
	## D's ("swap"), so it runs continuously the way it does on the day.
	## The layout's offset 16 m down the ground so
	## the 56 m circuit sits round the field centre.
	_kicking_circuit("Kicking circuit",
		"A → B straight, B → C on a 45° lead, C hands off to A following their kick, A hits D leading straight at them. Follow your kick, lead into space, kick to their advantage.",
		Vector2(28.0, 1.0), Vector2(20.0, 1.0), "D leads straight back at A; A hits them"),
	_kicking_circuit("Kicking circuit: spread",
		"The progression: the same circuit, but D spreads away from A at 45° and A has to kick into the space D's running to.",
		Vector2(24.0, 1.0), Vector2(30.0, 7.0), "D spreads away at 45°; A kicks into their space"),
]


## The kicking circuit with D's start and lead as given (see above).
static func _kicking_circuit(title: String, summary: String, d_at: Vector2, d_lead: Vector2,
		d_text: String) -> Dictionary:
	return {
		"name": title,
		"summary": summary,
		"cones": [Vector2(-28.0, 0.0), Vector2(-4.0, 0.0), Vector2(-6.0, -12.0), d_at],
		"roles": [
			{"name": "A", "at": Vector2(-28.0, 0.0)},
			{"name": "B", "at": Vector2(-4.0, 0.0)},
			{"name": "C", "at": Vector2(-6.0, -12.0)},
			{"name": "D", "at": d_at},
		],
		"play_role": 0,
		"ball_to": 0,
		"beats": [
			# A's follow-up run is a separate entry after the kick's gone: a
			# bot does one task at a time, and A runs a lane 3 m wide of B so
			# they don't run through each other.
			{"text": "B leads straight at A; A kicks to them and follows the kick",
				"do": [{"role": 1, "run_to": Vector2(-11.0, 0.0), "gait": 0.95},
					{"role": 0, "kick_to": 1, "delay": 1.0},
					{"role": 0, "run_to": Vector2(-16.0, 3.0), "gait": 0.9, "delay": 1.8}],
				"until": "caught", "by": 1},
			{"text": "C pushes off and leads at 45°; B kicks into their space and A keeps running",
				"do": [{"role": 2, "run_to": Vector2(2.0, -4.0), "gait": 0.95},
					{"role": 1, "kick_to": 2, "delay": 0.9},
					{"role": 0, "run_to": Vector2(-10.0, 2.0), "gait": 0.9}],
				"until": "caught", "by": 2},
			# C walks back off the mark (~2 s, toward B) before they can
			# dispose of it, so A holds their run until C's nearly done.
			{"text": "C handballs to A running past",
				"do": [{"role": 0, "run_to": Vector2(14.0, 1.0), "gait": 0.85, "delay": 0.4},
					{"role": 2, "handball_to": 0, "delay": 0.2}],
				"until": "caught", "by": 0},
			{"text": d_text,
				"do": [{"role": 3, "run_to": d_lead, "gait": 0.95},
					{"role": 0, "kick_to": 3, "delay": 0.7}],
				"until": "caught", "by": 3},
			# The rotation: D brings it back and is the next A; A goes up to
			# D's cone, B and C jog back to theirs. D comes back wide of the
			# line first: straight home they met A running up it head-on
			# and stalled the beat.
			{"text": "D takes it back to A's cone and kicks next; A goes up to D's spot",
				"do": [{"role": 3, "run_to": Vector2(-20.0, 8.0), "gait": 0.9},
					{"role": 0, "run_to": d_at, "gait": 0.7},
					{"role": 1, "run_to": Vector2(-4.0, 0.0), "gait": 0.6},
					{"role": 2, "run_to": Vector2(-6.0, -12.0), "gait": 0.6}],
				"until": "arrived", "timeout": 15.0},
			{"text": "D takes it back to A's cone and kicks next; A goes up to D's spot",
				"do": [{"role": 3, "run_to": Vector2(-28.0, 0.0), "gait": 0.6}],
				"until": "arrived", "swap": [0, 3]},
		],
	}
