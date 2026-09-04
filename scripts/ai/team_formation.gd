class_name TeamFormation
extends Resource

## Pure-geometry AFL formation data: 18 fixed slots grouped into the six
## real position lines, each at a position expressed as a fraction of
## Tuning.FIELD_HALF_LENGTH/FIELD_HALF_WIDTH rather than a fixed
## coordinate — so the layout stays correct if the ground size ever
## changes. Modelled on Prototype 1's formations.py (E:\aussie-rules_game):
## a flat, static layout with no coupling to player objects or game state.
## Unlike P1, role is kept on each slot rather than discarded after layout
## build, since the Team List screen and testing mode both need to label
## slots by role.
##
## `depth` is in an "attacking frame": -1 sits on your own goal line, 0 is
## the centre of the ground, +1 sits on the goal you're attacking. Actual
## world X folds in `attack_direction` (see world_position) the same way
## ai_brain.gd already does for its own home_position. `lateral` is
## -1..1 across the width, wing-to-wing, and does not flip between teams —
## the ground is symmetric across the centre line, so both teams' left
## flank sits at the same sign.
##
## Depths and laterals here are a plausible AFL-shaped starting-position
## layout, not a scouted real-world formation — good enough for a preview
## screen and a formation-start spawn; a tactics system would vary these
## live, which is explicitly out of scope for this pass.

enum Role {
	FULL_BACK, BACK_POCKET_LEFT, BACK_POCKET_RIGHT,
	CENTRE_HALF_BACK, HALF_BACK_FLANK_LEFT, HALF_BACK_FLANK_RIGHT,
	WING_LEFT, CENTRE, WING_RIGHT,
	CENTRE_HALF_FORWARD, HALF_FORWARD_FLANK_LEFT, HALF_FORWARD_FLANK_RIGHT,
	FULL_FORWARD, FORWARD_POCKET_LEFT, FORWARD_POCKET_RIGHT,
	RUCK, RUCK_ROVER, ROVER,
}

## Index into LINE_NAMES; also the natural back-to-forward draw order.
enum Line { BACK, HALF_BACK, CENTRE, HALF_FORWARD, FORWARD, FOLLOWERS }

const LINE_NAMES := ["BACK", "HALF BACK", "CENTRE", "HALF FORWARD", "FORWARD", "FOLLOWERS"]

## 18 slots, the full AFL team. Each: role, short label (for the Team List
## dots), the line it belongs to, and its depth/lateral fraction.
const SLOTS := [
	{"role": Role.FULL_BACK, "label": "FB", "line": Line.BACK, "depth": -0.80, "lateral": 0.0},
	{"role": Role.BACK_POCKET_LEFT, "label": "BP", "line": Line.BACK, "depth": -0.80, "lateral": -0.55},
	{"role": Role.BACK_POCKET_RIGHT, "label": "BP", "line": Line.BACK, "depth": -0.80, "lateral": 0.55},

	{"role": Role.CENTRE_HALF_BACK, "label": "CHB", "line": Line.HALF_BACK, "depth": -0.42, "lateral": 0.0},
	{"role": Role.HALF_BACK_FLANK_LEFT, "label": "HBF", "line": Line.HALF_BACK, "depth": -0.42, "lateral": -0.55},
	{"role": Role.HALF_BACK_FLANK_RIGHT, "label": "HBF", "line": Line.HALF_BACK, "depth": -0.42, "lateral": 0.55},

	{"role": Role.WING_LEFT, "label": "W", "line": Line.CENTRE, "depth": 0.0, "lateral": -0.85},
	{"role": Role.CENTRE, "label": "C", "line": Line.CENTRE, "depth": 0.0, "lateral": 0.0},
	{"role": Role.WING_RIGHT, "label": "W", "line": Line.CENTRE, "depth": 0.0, "lateral": 0.85},

	{"role": Role.CENTRE_HALF_FORWARD, "label": "CHF", "line": Line.HALF_FORWARD, "depth": 0.42, "lateral": 0.0},
	{"role": Role.HALF_FORWARD_FLANK_LEFT, "label": "HFF", "line": Line.HALF_FORWARD, "depth": 0.42, "lateral": -0.55},
	{"role": Role.HALF_FORWARD_FLANK_RIGHT, "label": "HFF", "line": Line.HALF_FORWARD, "depth": 0.42, "lateral": 0.55},

	{"role": Role.FULL_FORWARD, "label": "FF", "line": Line.FORWARD, "depth": 0.80, "lateral": 0.0},
	{"role": Role.FORWARD_POCKET_LEFT, "label": "FP", "line": Line.FORWARD, "depth": 0.80, "lateral": -0.55},
	{"role": Role.FORWARD_POCKET_RIGHT, "label": "FP", "line": Line.FORWARD, "depth": 0.80, "lateral": 0.55},

	{"role": Role.RUCK, "label": "RK", "line": Line.FOLLOWERS, "depth": -0.03, "lateral": 0.12},
	{"role": Role.RUCK_ROVER, "label": "RR", "line": Line.FOLLOWERS, "depth": 0.05, "lateral": -0.18},
	{"role": Role.ROVER, "label": "ROV", "line": Line.FOLLOWERS, "depth": 0.05, "lateral": 0.30},
]


## Roster spawn order as indices into SLOTS: the four players the AFL
## centre-square law lets start inside the square at a centre bounce — the
## ruck, the centre and the two rovers — are pulled to the front, so a
## mode that rings roster indices 0-3 at a bounce and nominates index 0 as
## its ruck (FullGame._centre_bounce_slot / _bounce_off) lines up with
## real positions and no other slot ever lands inside the square. The
## remaining 14 follow in SLOTS order (back line first). A roster shorter
## than 18 stays a strict prefix — shrinking it never reshuffles who
## remains.
const ROSTER_ORDER: Array[int] = [15, 7, 16, 17, 0, 1, 2, 3, 4, 5, 6, 8, 9, 10, 11, 12, 13, 14]

## The SLOTS entry for the player at roster index `i` (0-based), resolved
## through ROSTER_ORDER. Wraps above 18 (which doubles up — TEAM_SIZE
## above 18 is unsupported, see Tuning.TEAM_SIZE).
static func roster_slot(i: int) -> Dictionary:
	return SLOTS[ROSTER_ORDER[i % SLOTS.size()]]


## World position (Y=0, ground plane) for `slot` (a SLOTS entry, or the
## first `count` of them — see world_positions) given a team's
## attack_direction (+1 attacks +X, -1 attacks -X — same convention as
## ai_brain.gd's attack_direction).
static func world_position(slot: Dictionary, attack_direction: float) -> Vector3:
	var x := attack_direction * float(slot["depth"]) * Tuning.FIELD_HALF_LENGTH
	var z := float(slot["lateral"]) * Tuning.FIELD_HALF_WIDTH
	return Vector3(x, 0.0, z)


## The first `count` slots' world positions, in SLOTS order (back line
## first). Used by a testing mode spawning fewer than 18 a side — taking a
## prefix rather than resampling keeps every team-size a strict subset of
## the full 18, so shrinking the roster never reshuffles who's left.
static func world_positions(count: int, attack_direction: float) -> Array[Vector3]:
	var positions: Array[Vector3] = []
	for i in mini(count, SLOTS.size()):
		positions.append(world_position(SLOTS[i], attack_direction))
	return positions
