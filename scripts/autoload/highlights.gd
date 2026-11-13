extends Node

## Highlights (autoload): keeps the last Full Game's highlight moments
## between the match scene and the Highlights screen.
##
## It attaches a HighlightRecorder to every Full Game scene as it becomes
## ready (watching SceneTree.node_added for the scene's path), so no
## gameplay script needed an edit to host one. Moments arrive as their
## play-outs finish; this ranks them, caps them at
## each type's own cap (HighlightTable.TYPES[type].cap, dropping the lowest
## score of that type, and its footage, from memory) and ticks the best few of
## every type that's switched on (HighlightPrefs) for export. Everything lives
## in memory only until the Highlights screen exports it.

const FULL_GAME_SCENE := "res://scenes/modes/full_game.tscn"

## Moments, best first. Each is HighlightRecorder's dictionary plus `clip`
## (a ReplayClip) and `keep` (ticked for export).
var moments: Array[Dictionary] = []
## Teams, final score, when: filled when the recorder leaves. `mode` says
## who played ("human_vs_ai", "ai_vs_ai" or "staged").
var match_info := {}
## "match" for a game somebody played, "generated" for footage the dev
## generator made (scripts/dev/highlight_generator.gd). moments.json carries it
## so the video side doesn't caption generated play as the player's own.
var footage := "match"
## Where the Highlights screen's Back goes: the full-time screen that
## opened it (quick play or Career). Set by that screen.
var return_scene := ""

var _recorder: HighlightRecorder


func _ready() -> void:
	get_tree().node_added.connect(_on_node_added)


func has_moments() -> bool:
	return not moments.is_empty()


## Moments ticked for export. A switched-off type is never exported, whatever
## its moments' own ticks say.
func kept() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for m in moments:
		if m.keep and HighlightPrefs.type_on(String(m.type)):
			out.append(m)
	return out


## Moments of types that are switched on: what the Highlights screen lists.
func listed() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for m in moments:
		if HighlightPrefs.type_on(String(m.type)):
			out.append(m)
	return out


## How many moments of `type` are held in memory.
func count_of(type: String) -> int:
	var n := 0
	for m in moments:
		if m.type == type:
			n += 1
	return n


## Switches a type on or off (saved), and ticks or unticks its moments: on
## ticks the best HighlightTable.TYPES[type].keep, off unticks them all.
func set_type_on(type: String, on: bool) -> void:
	HighlightPrefs.set_type_on(type, on)
	_retick(type)


func clear() -> void:
	moments.clear()
	match_info = {}
	footage = "match"


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
		# A player drives one HOME body in every normal game. The generator
		# takes the human off before any moment can land, and says so here.
		"mode": "human_vs_ai" if ControlMode.controlled_player(Tuning.Team.HOME) != null else "ai_vs_ai",
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
	var type := String(moment.type)
	# Over this type's cap: the lowest-scoring of the type goes (the list is
	# best first, so the last one of the type).
	var cap := int((HighlightTable.TYPES[type] as Dictionary).cap)
	var held := 0
	for m in moments:
		if m.type == type:
			held += 1
	if held > cap:
		for i in range(moments.size() - 1, -1, -1):
			if moments[i].type == type:
				moments.remove_at(i)
				break
	_retick(type)


## Ticks the best `keep` moments of `type` if it's switched on, else none.
func _retick(type: String) -> void:
	var allowed := HighlightPrefs.type_on(type)
	var keep := int((HighlightTable.TYPES[type] as Dictionary).keep)
	var rank := 0
	for m in moments:
		if m.type != type:
			continue
		m.keep = allowed and rank < keep
		rank += 1
