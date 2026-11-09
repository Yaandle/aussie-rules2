extends Node

## Highlights (autoload): keeps the last Full Game's highlight moments
## between the match scene and the Highlights screen.
##
## It attaches a HighlightRecorder to every Full Game scene as it becomes
## ready (watching SceneTree.node_added for the scene's path), so no
## gameplay script needed an edit to host one. Moments arrive as their
## play-outs finish; this ranks them, caps them at
## HighlightTable.MAX_MOMENTS (dropping the lowest score, and its footage,
## from memory) and ticks the best HighlightTable.DEFAULT_KEEP for export.
## Everything lives in memory only until the Highlights screen exports it.

const FULL_GAME_SCENE := "res://scenes/modes/full_game.tscn"

## Moments, best first. Each is HighlightRecorder's dictionary plus `clip`
## (a ReplayClip) and `keep` (ticked for export).
var moments: Array[Dictionary] = []
## Teams, final score, when: filled when the recorder leaves.
var match_info := {}
## Where the Highlights screen's Back goes: the full-time screen that
## opened it (quick play or Career). Set by that screen.
var return_scene := ""

var _recorder: HighlightRecorder


func _ready() -> void:
	get_tree().node_added.connect(_on_node_added)


func has_moments() -> bool:
	return not moments.is_empty()


func kept() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for m in moments:
		if m.keep:
			out.append(m)
	return out


func clear() -> void:
	moments.clear()
	match_info = {}


func _on_node_added(node: Node) -> void:
	if node.scene_file_path == FULL_GAME_SCENE:
		node.ready.connect(_attach.bind(node), CONNECT_ONE_SHOT)


func _attach(game: Node) -> void:
	clear()
	_recorder = HighlightRecorder.new()
	_recorder.name = "HighlightRecorder"
	_recorder.setup(game)
	_recorder.moment_detected.connect(_add)
	_recorder.tree_exiting.connect(_on_match_left.bind(_recorder))
	match_info = {
		"home": _recorder.team_name(Tuning.Team.HOME),
		"away": _recorder.team_name(Tuning.Team.AWAY),
		"career": GameState.career_active,
		"started": Time.get_datetime_string_from_system(),
	}
	game.add_child(_recorder)


func _on_match_left(recorder: HighlightRecorder) -> void:
	# The recorder's own _exit_tree flushes waiting moments after this, and
	# they still reach _add; the final score is what MatchState holds now.
	match_info["final"] = {
		"home": MatchState.scoreline(Tuning.Team.HOME), "away": MatchState.scoreline(Tuning.Team.AWAY),
		"home_points": MatchState.points(Tuning.Team.HOME), "away_points": MatchState.points(Tuning.Team.AWAY),
	}
	match_info["finished"] = MatchState.is_full_time() or GameState.phase == GameState.Phase.FINISHED
	if recorder == _recorder:
		_recorder = null


func _add(moment: Dictionary) -> void:
	moments.append(moment)
	moments.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.highlight_score) > float(b.highlight_score))
	if moments.size() > HighlightTable.MAX_MOMENTS:
		moments.resize(HighlightTable.MAX_MOMENTS)
	for i in moments.size():
		moments[i].keep = i < HighlightTable.DEFAULT_KEEP
