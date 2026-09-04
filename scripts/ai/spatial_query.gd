class_name SpatialQuery
extends RefCounted

## Proximity queries shared by player_controller.gd, ai_brain.gd and
## ball.gd, over PlayerRegistry.all() rather than a per-call
## get_nodes_in_group(&"players") allocation (docs/MECHANICS_AUDIT.md
## A1/A2). Before this the same "iterate players, filter by team / carrying
## / self, keep the nearest" loop was hand-written ~10 times across three
## files.
##
## All distances are on the XZ plane (y flattened) — this game is played on
## the ground and a jumping mark's extra height should never change who is
## "nearest". Methods that take a bare `point` default it to the subject's
## own position.

## Nearest opponent of `of` within `max_dist` (plane distance), or null.
static func nearest_opponent(of: PlayerController, max_dist := INF) -> PlayerController:
	var best: PlayerController = null
	var best_d := max_dist
	for other in PlayerRegistry.all():
		if other == of or other.team == of.team:
			continue
		var d := _plane_distance(of.global_position, other.global_position)
		if d < best_d:
			best_d = d
			best = other
	return best


## Nearest opponent of `of` that is currently carrying the ball, or null.
static func nearest_opposing_carrier(of: PlayerController) -> PlayerController:
	var best: PlayerController = null
	var best_d := INF
	for other in PlayerRegistry.all():
		if other == of or other.team == of.team or not other.is_carrying():
			continue
		var d := _plane_distance(of.global_position, other.global_position)
		if d < best_d:
			best_d = d
			best = other
	return best


## Nearest same-team player to `point` (default: `of`'s position),
## excluding `of` itself, within `max_dist`, or null.
static func nearest_teammate(of: PlayerController, point := Vector3.INF,
		max_dist := INF) -> PlayerController:
	var from := of.global_position if point == Vector3.INF else point
	var best: PlayerController = null
	var best_d := max_dist
	for other in PlayerRegistry.all():
		if other == of or other.team != of.team:
			continue
		var d := _plane_distance(from, other.global_position)
		if d < best_d:
			best_d = d
			best = other
	return best


## Generic nearest-matching search for the handful of callers with a filter
## that isn't just team/carrying (a kick-aim cone, a tackle-radius gate).
## `exclude` is skipped; `predicate` takes a PlayerController and returns
## whether it's eligible. Pass Callable() to accept any.
static func nearest_where(from: Vector3, exclude: PlayerController,
		max_dist: float, predicate: Callable) -> PlayerController:
	var best: PlayerController = null
	var best_d := max_dist
	var has_pred := predicate.is_valid()
	for other in PlayerRegistry.all():
		if other == exclude:
			continue
		if has_pred and not predicate.call(other):
			continue
		var d := _plane_distance(from, other.global_position)
		if d < best_d:
			best_d = d
			best = other
	return best


## Plane distance from `point` (default: `of`'s position) to `of`'s nearest
## opponent, or INF if there is none. Used to score how open a pass target
## is, and as the "am I being pressured" read.
static func nearest_opponent_distance(of: PlayerController, point := Vector3.INF) -> float:
	var from := of.global_position if point == Vector3.INF else point
	var best := INF
	for other in PlayerRegistry.all():
		if other == of or other.team == of.team:
			continue
		best = minf(best, _plane_distance(from, other.global_position))
	return best


## True if `who` is the closest player on `team` to `point` — used to pick
## the single chaser / presser so a whole side doesn't converge on one spot.
static func is_closest_on_team(who: PlayerController, team: Tuning.Team,
		point: Vector3) -> bool:
	var mine := _plane_distance(who.global_position, point)
	for other in PlayerRegistry.all():
		if other == who or other.team != team:
			continue
		if _plane_distance(point, other.global_position) < mine:
			return false
	return true


## True if any player NOT on `keep_team` is within `radius` of the
## `from`->`to` segment (perpendicular distance, projection between the
## endpoints). A cheap "is the pass lane clogged" test, not a physics ray.
static func lane_blocked(from: Vector3, to: Vector3, radius: float,
		keep_team: Tuning.Team) -> bool:
	var seg := to - from
	seg.y = 0.0
	var seg_len := seg.length()
	if seg_len < 0.01:
		return false
	var dir := seg / seg_len
	for other in PlayerRegistry.all():
		if other.team == keep_team:
			continue
		var rel := other.global_position - from
		rel.y = 0.0
		var along := rel.dot(dir)
		if along <= 0.0 or along >= seg_len:
			continue
		if (rel - dir * along).length() < radius:
			return true
	return false


## Every opponent of `of` within `radius` of `point` (default: `of`'s
## position). Allocates its result — only called on a free-kick / mark
## grant, never per frame.
static func opponents_within(of: PlayerController, radius: float,
		point := Vector3.INF) -> Array[PlayerController]:
	var from := of.global_position if point == Vector3.INF else point
	var found: Array[PlayerController] = []
	for other in PlayerRegistry.all():
		if other == of or other.team == of.team:
			continue
		if _plane_distance(from, other.global_position) <= radius:
			found.append(other)
	return found


## True if any player other than `of` is currently a nominated ruck
## contestant (the "only the two ruckmen may gather" lock).
static func any_other_ruck_contestant(of: PlayerController) -> bool:
	for other in PlayerRegistry.all():
		if other != of and other.is_ruck_contestant():
			return true
	return false


static func _plane_distance(a: Vector3, b: Vector3) -> float:
	var dx := a.x - b.x
	var dz := a.z - b.z
	return sqrt(dx * dx + dz * dz)
