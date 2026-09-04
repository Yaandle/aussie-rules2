class_name PlayerRegistry
extends RefCounted

## Flat live list of every PlayerController currently in the scene tree.
##
## Exists so proximity/contest queries don't each call
## get_tree().get_nodes_in_group(&"players"), which allocates and fills a
## fresh Array on every call — and at 18-a-side several of those run per
## physics frame per AI brain (see SpatialQuery, and docs/MECHANICS_AUDIT.md
## A1/A2). PlayerController self-registers in _ready() and drops out in
## _exit_tree(); nothing else maintains this.
##
## Mode-agnostic: it keys off the node lifecycle, so it is correct in
## full_game, kick_to_kick and the scenes/main.tscn sandbox alike —
## unlike ControlMode.roster_for(), which kick_to_kick never populates.
##
## Iterate all() directly and treat it as read-only. The list only ever
## holds in-tree nodes, so callers don't need is_instance_valid() (the old
## group scan didn't either — a freed node leaves its groups the same way
## it leaves this list).

static var _all: Array[PlayerController] = []


static func add(player: PlayerController) -> void:
	if _all.has(player):
		return
	# Cheap prune on the rare (spawn-time) path rather than in every read:
	# guards against a node that was freed without _exit_tree ever firing.
	for i in range(_all.size() - 1, -1, -1):
		if not is_instance_valid(_all[i]):
			_all.remove_at(i)
	_all.append(player)


static func remove(player: PlayerController) -> void:
	_all.erase(player)


static func all() -> Array[PlayerController]:
	return _all
