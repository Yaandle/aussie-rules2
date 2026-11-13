extends Node

## Dev tool: checks a highlights export folder against its own replays, so
## a re-export proves the 2026-11-11 fixes instead of asserting them.
##
##   Godot.exe --headless --path . res://scenes/dev/highlight_check.tscn -- --folder=<export folder> [--cameras]
##
## Per moment (v2 rows only; v1 rows are listed and skipped):
##   - the .replay's frame count is `replay_frames`; the 16:9 and 9:16 .avi
##     headers hold `frames`; `complete` is true exactly when they match;
##   - every event's frame is inside the clip and its kind is a known one;
##   - a goal or behind's `kick_distance` and `facts.distance` are within
##     DISTANCE_TOLERANCE of the ball's horizontal travel from `kick_frame` to
##     `event_frame`, and the kicker is at the ball on `kick_frame` (a kickless
##     score has no kick to check);
##   - generated footage has no human player.
## With --cameras it also replays each clip on a ReplayStage and reports how
## far each camera preset strays: the goal/behind follow point past the goal
## line (bug 2), and the end-on and third-person cameras outside the fence.
## Exits 1 if anything fails. Needs no renderer (--headless is fine).

const DISTANCE_TOLERANCE := 3.0
## How far the kicker may be from the ball on the frame it's kicked.
const KICKER_REACH := 2.5
const KINDS := ["kick", "handball", "mark", "tackle", "bump", "bounce", "goal", "behind", "siren"]

var _failures := 0


func _ready() -> void:
	var folder := ""
	var cameras := false
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--folder="):
			folder = arg.trim_prefix("--folder=")
		elif arg == "--cameras":
			cameras = true
	var text := FileAccess.get_file_as_string(folder.path_join("moments.json"))
	if text == "":
		push_error("CHECK: no moments.json in '%s'" % folder)
		get_tree().quit(2)
		return
	var doc: Dictionary = JSON.parse_string(text)
	print("CHECK: %s  version %s  footage %s  mode %s  aspect %s" % [folder.get_file(), doc.get("version"),
		doc.get("footage", "-"), (doc.match as Dictionary).get("mode", "-"), (doc.output as Dictionary).get("aspect", "both")])
	var stage: ReplayStage = null
	if cameras:
		stage = ReplayStage.new()
		add_child(stage)
		await get_tree().process_frame
	for row: Dictionary in doc.moments:
		await _check_row(folder, doc, row, stage)
	print("CHECK: %s" % ("all good" if _failures == 0 else "%d FAILED" % _failures))
	get_tree().quit(1 if _failures > 0 else 0)


func _fail(row: Dictionary, what: String) -> void:
	_failures += 1
	print("  FAIL %02d %s: %s" % [int(row.rank), row.type, what])


func _check_row(folder: String, doc: Dictionary, row: Dictionary, stage: ReplayStage) -> void:
	var files: Dictionary = row.files
	var clip := ReplayClip.load_file(folder.path_join(String(files.replay)))
	if clip == null:
		_fail(row, "replay missing")
		return
	if not row.has("events"):
		print("  %02d %s (v1 row: fields not checked)" % [int(row.rank), row.type])
		if stage != null:
			_check_cameras(row, clip, stage)
		return
	var summary := "%02d %-9s %-9s frames %d/%d" % [int(row.rank), row.type, row.camera, int(row.frames), int(row.replay_frames)]
	if clip.frame_count() != int(row.replay_frames):
		_fail(row, "replay has %d frames, row says %d" % [clip.frame_count(), int(row.replay_frames)])
	var complete := true
	for key: String in ["landscape", "portrait"]:
		if not files.has(key):
			continue
		var avi := _avi_frames(folder.path_join(String(files[key])))
		if avi != int(row.frames):
			_fail(row, "%s has %d frames, row says %d" % [key, avi, int(row.frames)])
		complete = complete and avi == clip.frame_count()
	if complete != bool(row.complete):
		_fail(row, "complete is %s but the video %s the replay" % [row.complete, "matches" if complete else "is shorter than"])
	for ev: Dictionary in row.events:
		if int(ev.frame) < 0 or int(ev.frame) >= clip.frame_count() or not KINDS.has(String(ev.kind)):
			_fail(row, "bad event %s" % ev)
	if String(doc.get("footage", "")) == "generated":
		for p: Dictionary in row.players:
			if bool(p.human):
				_fail(row, "generated footage has a human player (%s)" % p.name)
	if row.type == "goal" or row.type == "behind":
		if row.get("kick_frame") == null:
			summary += "  (no kick)"
		else:
			var from := clip.ball_position(int(row.kick_frame))
			var to := clip.ball_position(int(row.event_frame))
			var travel := Vector2(to.x - from.x, to.z - from.z).length()
			summary += "  kick %s %.1f m, travel %.1f m, facts %.1f m" % [row.kicker, float(row.kick_distance), travel,
				float((row.facts as Dictionary).distance)]
			# The kicker has to be at the ball when it leaves the boot.
			var at_ball := INF
			for b in (clip.meta.bodies as Array).size():
				var body: Dictionary = clip.meta.bodies[b]
				if body.kind == "player" and String(body.name) == String(row.kicker):
					var q := clip.body_position(int(row.kick_frame), b)
					at_ball = Vector2(q.x - from.x, q.z - from.z).length()
			if at_ball > KICKER_REACH:
				_fail(row, "%s is %.1f m from the ball on its kick frame" % [row.kicker, at_ball])
			for pair: Array in [["kick_distance", float(row.kick_distance)], ["facts.distance", float((row.facts as Dictionary).distance)]]:
				if absf(float(pair[1]) - travel) > DISTANCE_TOLERANCE:
					_fail(row, "%s %.1f vs the ball's travel %.1f" % [pair[0], float(pair[1]), travel])
	print("  " + summary)
	if stage != null:
		_check_cameras(row, clip, stage)


## Reads dwTotalFrames out of an AVI's main header.
func _avi_frames(path: String) -> int:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return -1
	file.seek(48)
	var n := file.get_32()
	file.close()
	return int(n)


func _check_cameras(row: Dictionary, clip: ReplayClip, stage: ReplayStage) -> void:
	stage.load_clip(clip)
	var direction := 1.0 if float(clip.meta.get("attack_dir", 1.0)) >= 0.0 else -1.0
	var line := stage._field.goal_line_x(int(direction))
	var camera := Camera3D.new()
	stage.add_child(camera)
	var report := "      cameras:"
	for preset: String in ReplayStage.CAMERA_PRESETS:
		var worst_out := 0.0
		var worst_focus := -INF
		var ball_past := -INF
		for i in clip.frame_count():
			var t := float(i) / clip.fps()
			stage.apply(t)
			stage.frame_camera(camera, preset, false, t, 1.0 / clip.fps(), i == 0)
			var p := camera.global_position
			var k := sqrt(p.x * p.x / pow(Tuning.FIELD_HALF_LENGTH + ReplayStage.END_FENCE_MARGIN, 2.0)
				+ p.z * p.z / pow(Tuning.FIELD_HALF_WIDTH + ReplayStage.END_FENCE_MARGIN, 2.0))
			worst_out = maxf(worst_out, k)
			worst_focus = maxf(worst_focus, direction * (stage.focus_point().x - line))
			ball_past = maxf(ball_past, direction * (clip.ball_position(i).x - line))
		report += "  %s fence %.2f focus %+.1f m past the line (ball %+.1f);" % [preset, worst_out, worst_focus, ball_past]
		if row.type == "goal" or row.type == "behind":
			if worst_focus > ReplayStage.FOLLOW_PAST_GOAL + 1.0:
				_fail(row, "%s camera follows %.1f m past the goal line" % [preset, worst_focus])
		if (preset == "end" or preset == "third") and worst_out > 1.01:
			_fail(row, "%s camera leaves the fence (%.2f of the oval)" % [preset, worst_out])
	camera.queue_free()
	print(report)
