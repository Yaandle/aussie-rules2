extends Node3D

## Dev tool: makes highlight footage nobody played. It runs an all-AI Full
## Game with the highlight recorder on, then exports the best goals, marks,
## tackles, bumps and some general play from varied cameras, flagged as
## generated (moments.json: `footage` "generated", `match.mode` "ai_vs_ai",
## every player `human: false`), into `highlights/generated/`. The daily
## video series uses it for B-roll; the video side must not caption it as the
## player's own ("I").
##
## Contests and tackles are the match's own. The Training drills are passing
## drills with bots, with no contest, set shot or tackle in them, and they
## don't run inside a Full Game, so nothing there feeds the recorder. AI play
## alone rarely scores (2026-11-11: no goal in 340 s of game time), so it also
## STAGES set shots: every so often a player is put on the ball at a chosen
## spot 20-42 m out, off a different angle, with nobody told where to kick. The
## AI brain takes the shot like any carrier in range and the kick, the
## flight and any defender are physics and timing (docs/RULES_REFERENCE.md §3),
## so some go through, some miss and some are smothered. Nothing about the
## outcome is scripted. A run that staged anything says `match.mode: "staged"`.
##
## Run WINDOWED (exports need a real renderer) with a fixed frame rate: the
## recorder samples each rendered frame and the replay assumes they're evenly
## spaced, so a variable-rate run would play back sped up and slowed down.
##
##   Godot.exe --path . res://scenes/dev/highlight_generator.tscn --fixed-fps 60 -- --quarters=2
##
## Options (after `--`):
##   --quarters=N       play up to N quarters (default 2; a quarter is 120 s of
##                      game time) and stop sooner once every quota is filled
##   --seed=N           seed the AI's randomness (default random)
##   --staged=N         set shots to stage (default 8; 0 for a pure AI match)
##   --aspect=A         16x9 (default), 9x16 or both
##   --quota=goal:5,mark:5,tackle:5,general:2,behind:1,bump:0,long_kick:0,ruck:0
##                      clips to export per type (the best of each)
##   --max-seconds=S    give up after S seconds of game time (default 1500)
##
## V-sync is switched off so the run goes as fast as the renderer allows.
## Camera numbers and quotas are unplaytested feel guesses (2026-11-11).

const FULL_GAME := "res://scenes/modes/full_game.tscn"

## Staged set shots (unplaytested guesses): distance out from the goal line,
## metres off the centre line, and game seconds between shots.
const STAGE_DISTANCES := [30.0, 42.0, 22.0, 36.0, 26.0, 40.0]
const STAGE_LATERAL := [0.0, 14.0, -18.0, 8.0, -6.0, 20.0]
const STAGE_GAP := 22.0

## Per type, the cameras its clips cycle through, so a batch isn't one angle.
const CAMERA_CYCLE := {
	"goal": ["broadcast", "end", "third", "broadcast", "close"],
	"behind": ["broadcast", "end"],
	"mark": ["third", "broadcast", "close", "third"],
	"tackle": ["third", "close", "broadcast", "third", "end"],
	"bump": ["third", "close"],
	"long_kick": ["broadcast", "third"],
	"ruck": ["close", "broadcast"],
	"general": ["broadcast", "third", "end"],
}

var _quarters := 2
var _max_seconds := 1500.0
var _aspect := "16x9"
var _quota := {"goal": 5, "behind": 1, "mark": 5, "tackle": 5, "general": 2}
var _game: Node
var _sim := 0.0
var _next_report := 30.0
var _checked := 0.0
var _finishing := false
var _fps_warned := false
## Set shots still to stage, game seconds until the next, and how many were.
var _staged_left := 8
var _stage_in := 12.0
var _staged := 0


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("highlight_generator needs a real renderer: run it windowed, not --headless")
		get_tree().quit(2)
		return
	for arg: String in OS.get_cmdline_user_args():
		var kv := arg.trim_prefix("--").split("=", true, 1)
		if kv.size() != 2:
			continue
		match kv[0]:
			"quarters": _quarters = clampi(int(kv[1]), 1, Tuning.QUARTERS_PER_MATCH)
			"seed": seed(int(kv[1]))
			"staged": _staged_left = maxi(0, int(kv[1]))
			"aspect": _aspect = kv[1]
			"max-seconds": _max_seconds = float(kv[1])
			"quota": _quota = _parse_quota(kv[1])
	if not HighlightTable.ASPECTS.has(_aspect):
		_aspect = "16x9"
	# The player's saved Highlights choices are theirs: nothing here writes them.
	HighlightPrefs.transient = true
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	_start_match()


func _parse_quota(text: String) -> Dictionary:
	var out := {}
	for pair in text.split(","):
		var kv := pair.split(":")
		if kv.size() == 2 and HighlightTable.TYPES.has(kv[0]):
			out[kv[0]] = maxi(0, int(kv[1]))
	return out


## An ordinary Full Game with nobody driving: the one human body gets an AI
## brain like its team-mates' and ControlMode has no controlled player, so
## the recorder marks every player `human: false`.
func _start_match() -> void:
	# Quick play's setup, in memory only (nothing here saves Settings). FULL_TEAM
	# would hand a HumanBrain to whichever HOME player gains the ball, and
	# nobody is there to drive it.
	GameState.career_active = false
	Settings.player_control_mode = Settings.PlayerControlMode.SINGLE_PLAYER
	_game = (load(FULL_GAME) as PackedScene).instantiate()
	add_child(_game)
	var human := ControlMode.controlled_player(Tuning.Team.HOME)
	if human != null:
		var slot: int = (_game.get("_home_players") as Array).find(human)
		human.set_brain(_game.call("_configure_ai_brain", AIBrain.new(), Tuning.Team.HOME, 1.0,
			_game.call("_kickoff_slot", slot, 1.0, Tuning.Team.HOME)))
		ControlMode.set_controlled_player(Tuning.Team.HOME, null)
	# A view of the match while it runs: the wide camera on the ball.
	var camera := _game.get("_camera") as BroadcastCamera
	if camera != null:
		camera.target = _game.get("_ball")
		camera.set_mode(BroadcastCamera.Mode.FULL_SIDE)
	Highlights.footage = "generated"
	Highlights.match_info["mode"] = "ai_vs_ai"
	print("GENERATOR: AI v AI, up to %d quarter(s), quotas %s" % [_quarters, _quota])


func _process(delta: float) -> void:
	if _game == null or _finishing:
		return
	if not _fps_warned and absf(delta - 1.0 / 60.0) > 0.003 and _sim > 2.0:
		_fps_warned = true
		push_warning("GENERATOR: frame time is %.1f ms, not a steady 16.7 ms. Run with --fixed-fps 60 or the clips' timing will be off." % (delta * 1000.0))
	_sim += delta
	_stage_in -= delta
	if _staged_left > 0 and _stage_in <= 0.0:
		_stage_set_shot()
	if _sim >= _next_report:
		_next_report += 30.0
		print("GENERATOR: %.0f s, Q%d %.0f s left, holding %s" % [_sim, MatchState.quarter,
			MatchState.seconds_remaining, _held()])
	_checked += delta
	if _checked < 1.0:
		return
	_checked = 0.0
	var played := MatchState.quarter > _quarters \
		or (MatchState.quarter == _quarters and MatchState.seconds_remaining <= 0.0)
	if played or _sim >= _max_seconds or _quota_filled():
		_finishing = true
		_finish.call_deferred()


## Puts a player on the ball at a spot 20-42 m out from the goal they attack,
## protected as after a mark, and lets the AI do what it does. Waits for
## live play (no stoppage, siren or score under way) and for the goal quota
## to still be open. Spots rotate through distance and angle, alternating
## the two ends.
func _stage_set_shot() -> void:
	if GameState.phase != GameState.Phase.PLAY or MatchState.seconds_remaining < 20.0 			or _game.call("_after_siren_active"):
		_stage_in = 2.0
		return
	if Highlights.count_of("goal") + Highlights.count_of("behind") >= int(_quota.get("goal", 0)) 			+ int(_quota.get("behind", 0)):
		_staged_left = 0
		return
	var n := _staged
	_staged += 1
	_staged_left -= 1
	_stage_in = STAGE_GAP
	var team := Tuning.Team.HOME if n % 2 == 0 else Tuning.Team.AWAY
	var direction := 1.0 if team == Tuning.Team.HOME else -1.0
	var distance: float = STAGE_DISTANCES[n % STAGE_DISTANCES.size()]
	var lateral: float = STAGE_LATERAL[(n / 2) % STAGE_LATERAL.size()]
	var line: float = (_game.get("_field") as Field).goal_line_x(int(direction))
	var spot := Vector3(line - direction * distance, 0.0, lateral)
	var squad: Array = _game.get("_home_players") if team == Tuning.Team.HOME else _game.get("_away_players")
	var shooter: PlayerController = _game.call("_nearest_player", squad, spot)
	shooter.global_position = spot
	shooter.velocity = Vector3.ZERO
	# Faced the goal, as a player lining one up would be.
	shooter.face_toward(Vector3(line, 0.0, 0.0))
	_game.call("_award_possession_at", spot, shooter, false)
	print("GENERATOR: staged shot %d: %s from %.0f m, %.0f m off centre (game %.0f s)" % [n + 1,
		Highlights.match_info.get("home" if team == Tuning.Team.HOME else "away", "?"), distance, lateral, _sim])


func _held() -> Dictionary:
	var out := {}
	for type: String in HighlightTable.TYPE_ORDER:
		var n := Highlights.count_of(type)
		if n > 0:
			out[type] = n
	return out


func _quota_filled() -> bool:
	for type: String in _quota:
		if Highlights.count_of(type) < int(_quota[type]):
			return false
	return true


## Ends the match (its recorder flushes what's waiting as it leaves), picks
## the clips and renders them.
func _finish() -> void:
	print("GENERATOR: stopping at %.0f s of game time, holding %s" % [_sim, _held()])
	_game.queue_free()
	_game = null
	await get_tree().process_frame
	await get_tree().process_frame
	var picked := _pick()
	if picked.is_empty():
		push_error("GENERATOR: no moments to export")
		get_tree().quit(1)
		return
	var stage := ReplayStage.new()
	add_child(stage)
	var exporter := HighlightExporter.new()
	exporter.stage = stage
	add_child(exporter)
	var last_text := [""]
	exporter.progress.connect(func(text: String, _fraction: float) -> void:
		if text != last_text[0]:
			last_text[0] = text
			print("GENERATOR: %s" % text))
	if _staged > 0:
		Highlights.match_info["mode"] = "staged"
		Highlights.match_info["staged_shots"] = _staged
	var folder := await exporter.export_moments(picked, Highlights.match_info,
		{"aspect": _aspect, "footage": "generated", "subfolder": "generated"})
	print("GENERATOR: exported %d clips to %s" % [picked.size(), folder])
	get_tree().quit()


## The best `quota` moments of each type, each given a camera from its type's
## cycle. Best first overall, as the exporter ranks them.
func _pick() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var taken := {}
	for m in Highlights.moments:
		var type := String(m.type)
		var n := int(taken.get(type, 0))
		if n >= int(_quota.get(type, 0)):
			continue
		taken[type] = n + 1
		var cycle: Array = CAMERA_CYCLE.get(type, ["broadcast"])
		m["camera"] = cycle[n % cycle.size()]
		m["keep"] = true
		out.append(m)
	return out
