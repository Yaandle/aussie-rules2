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
##               beats refer to it. Optional "back_name": its name on the
##               way back (see "leg").
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
##     next      [role per role]: once the beat's done, role i is taken by
##               the player who had role next[i] (you go with your player)
##     leg       0 or 1: once the beat's done, the drill's on the way up (0)
##               or the way back (1), which picks the role names
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
	## The first of the user's own session drills (2026-11-02), as worked out
	## with the user 2026-11-03: six players, lines at the start and the B
	## cone, and you go where you give. Up: A → B straight, B → C on the 45°
	## lead, C hands off to A running through, A → D. Back: D → the B cone
	## (the furthest one), B hands off to C coming off the C cone (who was B
	## going up), C → the start. Moves: up, A to the end line, B to the C
	## cone, C to the B line; back, D to the B line, B to the C cone, C to
	## the start line. Every
	## line keeps its numbers, so it runs for ever, and players work through
	## every spot. Two versions: D's lead straight back at A, and the
	## progression where D spreads away at 45°.
	_kicking_circuit("Kicking circuit",
		"Six players, go where you give. Up: A → B straight, B → C on a 45° lead, C hands off to A running through, A → D. Back: D → B cone, handball to C off the C cone, C → start.",
		Vector2(28.0, 1.0), Vector2(20.0, 1.0), "D leads straight back at A; A hits them"),
	_kicking_circuit("Kicking circuit: spread",
		"The progression: the same circuit, but D spreads away from A at 45° and A has to kick into the space D's running to.",
		Vector2(24.0, 1.0), Vector2(30.0, 7.0), "D spreads away at 45°; A kicks into their space"),
]


## The six-player kicking circuit (see above), with D's cone and lead as
## given. Six roles, by spot: the same spot has a different job each way,
## hence the back names. At the end of each leg "next" hands the players
## round to the spot they've gone to:
##
##   role  up          back
##   0     A (start)   D (end, kicks back)
##   1     B           C (C cone)
##   2     C           B (B cone)
##   3     D (end)     A (start)
##   4     start line  end line
##   5     B line      B line
static func _kicking_circuit(title: String, summary: String, d_at: Vector2, d_lead: Vector2,
		d_text: String) -> Dictionary:
	var start := Vector2(-28.0, 0.0)
	var start_line := Vector2(-31.0, -4.0)
	# The B cone is off the line A runs and C walks back off their mark
	# along, and its line waits beside it, clear of both.
	var b_cone := Vector2(-4.0, 6.0)
	var b_line := Vector2(0.0, 7.0)
	var c_cone := Vector2(-6.0, -12.0)
	# Wide of D, on the C cone's side: A runs out to it while D kicks back
	# toward the B cone, and through the middle A took D's kick.
	var end_line := d_at + Vector2(3.0, -8.0)
	return {
		"name": title,
		"summary": summary,
		"cones": [start, b_cone, c_cone, d_at],
		"roles": [
			{"name": "A", "back_name": "D", "at": start},
			{"name": "B", "back_name": "C", "at": b_cone},
			{"name": "C", "back_name": "B", "at": c_cone},
			{"name": "D", "back_name": "A", "at": d_at},
			{"name": "start line", "back_name": "end line", "at": start_line},
			{"name": "B line", "at": b_line},
		],
		"play_role": 0,
		"ball_to": 0,
		"beats": [
			{"text": "Lines set: A at the start, B and C on their cones, D at the end",
				"do": [{"role": 0, "run_to": start, "gait": 0.4},
					{"role": 1, "run_to": b_cone, "gait": 0.7},
					{"role": 2, "run_to": c_cone, "gait": 0.8},
					{"role": 3, "run_to": d_at, "gait": 0.7},
					{"role": 4, "run_to": start_line, "gait": 0.7},
					{"role": 5, "run_to": b_line, "gait": 0.7}],
				"until": "arrived", "timeout": 15.0},
			# ── The way up ──
			# A's follow-up run is a separate entry after the kick's gone: a
			# bot does one task at a time. The B line steps up to the cone as
			# soon as B's gone.
			{"text": "Up: B leads straight at A; A kicks to them and follows the kick",
				"do": [{"role": 1, "run_to": Vector2(-11.0, 5.0), "gait": 0.95},
					{"role": 0, "kick_to": 1, "delay": 1.0},
					{"role": 0, "run_to": Vector2(-16.0, 2.0), "gait": 0.9, "delay": 1.8},
					{"role": 5, "run_to": b_cone, "gait": 0.5, "delay": 0.5}],
				"until": "caught", "by": 1},
			{"text": "Up: C leads at 45°; B kicks into their space and goes to the C cone",
				"do": [{"role": 2, "run_to": Vector2(2.0, -4.0), "gait": 0.95},
					{"role": 1, "kick_to": 2, "delay": 0.9},
					{"role": 1, "run_to": c_cone, "gait": 0.7, "delay": 1.7},
					{"role": 0, "run_to": Vector2(-10.0, 1.0), "gait": 0.9},
					{"role": 5, "run_to": b_cone, "gait": 0.5}],
				"until": "caught", "by": 2},
			# C walks back off the mark (~2 s, toward B) before they can
			# dispose of it, so A holds their run until C's nearly done. C's
			# own run waits for the next beat: a run would cancel the
			# handball. Every beat tells the movers again, since a new beat
			# stands everyone not in it down.
			{"text": "Up: C handballs to A running past",
				"do": [{"role": 0, "run_to": Vector2(14.0, 1.0), "gait": 0.85, "delay": 0.4},
					{"role": 2, "handball_to": 0, "delay": 0.2},
					{"role": 1, "run_to": c_cone, "gait": 0.7}],
				"until": "caught", "by": 0},
			{"text": "Up: " + d_text + "; A goes to the end line, C to the B line",
				"do": [{"role": 3, "run_to": d_lead, "gait": 0.95},
					{"role": 0, "kick_to": 3, "delay": 0.7},
					{"role": 0, "run_to": end_line, "gait": 0.7, "delay": 1.5},
					{"role": 1, "run_to": c_cone, "gait": 0.7},
					{"role": 2, "run_to": b_line, "gait": 0.6, "delay": 0.3}],
				"until": "caught", "by": 3, "next": [3, 1, 5, 4, 0, 2], "leg": 1},
			# ── The way back ── (roles by their back names from here: D has it
			# at the end, B on the B cone, C (who was B going up) on the C cone,
			# A at the start.) Runs that would cancel a disposal, or cut across
			# a player walking back off their mark, wait for the next beat.
			{"text": "Back: B leads; D kicks to the B cone, the furthest one",
				"do": [{"role": 2, "run_to": Vector2(2.0, 5.0), "gait": 0.95},
					{"role": 0, "kick_to": 2, "delay": 1.4},
					{"role": 3, "run_to": start, "gait": 0.5},
					{"role": 4, "run_to": end_line, "gait": 0.7}],
				"until": "caught", "by": 2},
			{"text": "Back: B handballs to C running onto it off the C cone",
				"do": [{"role": 1, "run_to": Vector2(5.0, 0.0), "gait": 0.85, "delay": 0.8},
					{"role": 2, "handball_to": 1, "delay": 0.2},
					{"role": 3, "run_to": start, "gait": 0.5},
					{"role": 4, "run_to": end_line, "gait": 0.7}],
				"until": "caught", "by": 1},
			{"text": "Back: C kicks to A at the start; B to the C cone, D to the B line",
				"do": [{"role": 3, "run_to": Vector2(-22.0, 0.0), "gait": 0.9},
					{"role": 1, "kick_to": 3, "delay": 0.6},
					{"role": 1, "run_to": start_line, "gait": 0.7, "delay": 1.4},
					{"role": 2, "run_to": c_cone, "gait": 0.7},
					{"role": 0, "run_to": b_line, "gait": 0.7, "delay": 0.8},
					{"role": 5, "run_to": b_cone, "gait": 0.5}],
				"until": "caught", "by": 3, "next": [3, 5, 2, 4, 1, 0], "leg": 0},
		],
	}
