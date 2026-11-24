extends Node

## Dev tool: measures how well each highlight camera films an export's
## moments, so a camera change is judged on numbers and frames rather than
## by eye (2026-11-24 highlights audit).
##
##   Godot_console.exe --headless --path . res://scenes/dev/highlight_camera_audit.tscn -- \
##       --folder=<export folder> [--presets=moment|broadcast,close,end,third,auto] \
##       [--types=goal,mark] [--ranks=1,5] [--limit=N] [--report=<file.json>] [--field=classic|oval1]
##   (windowed, no --headless) ... -- --folder=<dir> --frames=<out dir> [--size=1280x720]
##   --portrait shoots 9:16 (the size is swapped; px are then of 1920 lines)
##
## For every moment's own .replay and each preset asked for it walks the
## clip frame by frame exactly as the exporter does (ReplayStage.apply, then
## frame_camera at 1/30 s) and records, at 1080 lines:
##   subject_px   the main subject's on-screen height (focus[0], else the ball)
##                as median and 10th percentile: a player under ~80 px reads as
##                a dot on a phone
##   ball_vis     fraction of frames with the ball inside the frame
##   inside       frames with the lens inside a tree/prop box or a body
##   blocked      frames with dressing between the lens and the subject
##   goal_seen    goals/behinds: the ball is in frame on the scoring frame
## With --frames it also saves PNGs at the kick, the event -0.5 s, the event
## and the event +1 s, named <NN>_<type>_<preset>_<tag>.png.
## Needs no renderer without --frames.

const SUBJECT_HEIGHT := 1.9
const LINES := 1080.0
## Lens travel in one frame (m) that reads as a jolt rather than a move
## (30 m/s at 30 fps).
const JUMP_M := 1.0

var _stage: ReplayStage
var _view: SubViewport
var _camera: Camera3D
var _portrait := false


func _ready() -> void:
	var args := {}
	for arg: String in OS.get_cmdline_user_args():
		var kv := arg.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var folder := String(args.get("folder", ""))
	var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("moments.json")))
	if not (doc is Dictionary):
		push_error("AUDIT: no moments.json in '%s'" % folder)
		get_tree().quit(2)
		return
	var presets := String(args.get("presets", "moment")).split(",")
	var types := String(args.get("types", "")).split(",", false)
	var ranks := String(args.get("ranks", "")).split(",", false)
	var limit := int(args.get("limit", "999"))
	var frames_dir := String(args.get("frames", ""))
	var size := Vector2i(1920, 1080)
	if args.has("size"):
		var wh := String(args.size).split("x")
		size = Vector2i(int(wh[0]), int(wh[1]))
	_portrait = args.has("portrait")
	if _portrait:
		size = Vector2i(size.y, size.x)
	if frames_dir != "":
		DirAccess.make_dir_recursive_absolute(frames_dir)
	if args.has("field"):
		# Which ground the stage builds (Field reads Settings in its _ready).
		# Not saved: Settings only writes when something calls save.
		Settings.field_style = Settings.FieldStyle.CLASSIC if String(args.field) == "classic" 			else Settings.FieldStyle.OVAL_1
	_stage = ReplayStage.new()
	add_child(_stage)
	_view = SubViewport.new()
	_view.size = size
	_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_view.msaa_3d = Viewport.MSAA_4X
	_camera = Camera3D.new()
	_camera.current = true
	_view.add_child(_camera)
	_stage.add_child(_view)
	await get_tree().process_frame
	await get_tree().process_frame
	if args.has("full"):
		await _audit_full(folder, String(args.get("presets", "broadcast")).split(",")[0])
		get_tree().quit()
		return
	var report: Array = []
	var totals := {}
	var done := 0
	for row: Dictionary in doc.moments:
		if done >= limit:
			break
		if not types.is_empty() and not types.has(String(row.type)):
			continue
		if not ranks.is_empty() and not ranks.has(str(int(row.rank))):
			continue
		var path := folder.path_join(String((row.files as Dictionary).get("replay", "")))
		var clip := ReplayClip.load_file(path)
		if clip == null:
			continue
		done += 1
		_stage.load_clip(clip)
		for preset: String in presets:
			var p := String(row.get("camera", "broadcast")) if preset == "moment" else preset
			var r := await _measure(clip, row, p, frames_dir)
			report.append(r)
			print("AUDIT %02d %-9s %-9s subj_px med %4d p10 %4d  ball_vis %3d%%  inside %3d  blocked %3d%s" % [
				int(row.rank), row.type, p, r.subject_px_median, r.subject_px_p10, roundi(r.ball_vis * 100.0),
				r.inside, r.blocked, ("  goal_seen %s" % r.goal_seen) if r.has("goal_seen") else ""])
			if r.jumps > 0:
				print("      jumps %d (cuts %d)" % [r.jumps, r.cuts])
			var t: Dictionary = totals.get(p, {"n": 0, "px": 0.0, "small": 0, "inside": 0, "blocked": 0, "goals": 0, "goals_seen": 0})
			t.n += 1
			t.px += r.subject_px_median
			t.small += 1 if r.subject_px_median < 80 else 0
			t.inside += r.inside
			t.blocked += r.blocked
			if r.has("goal_seen"):
				t.goals += 1
				t.goals_seen += 1 if r.goal_seen else 0
			totals[p] = t
	for p: String in totals:
		var t: Dictionary = totals[p]
		print("AUDIT TOTAL %-9s moments %d  mean subj_px %d  under-80px %d  inside-frames %d  blocked-frames %d  goals seen %d/%d" % [
			p, t.n, roundi(t.px / maxf(1.0, t.n)), t.small, t.inside, t.blocked, t.goals_seen, t.goals])
	if args.has("report"):
		var f := FileAccess.open(String(args.report), FileAccess.WRITE)
		f.store_string(JSON.stringify({"folder": folder, "totals": totals, "moments": report}, "  "))
		f.close()
	get_tree().quit()


func _measure(clip: ReplayClip, row: Dictionary, preset: String, frames_dir: String) -> Dictionary:
	var fps := clip.fps()
	var n := clip.frame_count()
	var focus: Array = clip.meta.get("focus", [])
	var subject := int(focus[0]) if not focus.is_empty() else -1
	var scale := float((clip.meta.bodies[subject] as Dictionary).get("scale", 1.0)) if subject >= 0 else 1.0
	var event := int(clip.meta.get("event_frame", 0))
	var kick := int(clip.meta.get("kick_frame", -1)) if clip.meta.get("kick_frame") != null else -1
	var shots := {}
	if frames_dir != "":
		if kick >= 0:
			shots[kick] = "kick"
		shots[maxi(0, event - 15)] = "pre"
		shots[event] = "event"
		shots[mini(n - 1, event + 30)] = "after"
	var px: Array[float] = []
	var ball_in := 0
	var inside := 0
	var blocked := 0
	var goal_seen := false
	var jumps := 0
	var cuts := 0
	var prev_cam := Vector3.INF
	var prev_shot := -1
	var occ := _stage.occluders()
	for i in n:
		var t := float(i) / fps
		_stage.apply(t)
		_stage.frame_camera(_camera, preset, _portrait, t, 1.0 / fps, i == 0)
		var cam := _camera.global_position
		# A jump: the lens moving over JUMP_M in one frame without a cut.
		var shot := int(_stage.current_shot().index) if preset == "auto" else 0
		if prev_cam != Vector3.INF:
			if shot != prev_shot:
				cuts += 1
			elif cam.distance_to(prev_cam) > JUMP_M:
				jumps += 1
				if OS.get_environment("AUDIT_DEBUG") != "":
					print("   jump f%d %s -> %s ball %s" % [i, prev_cam, cam, clip.ball_position(i)])
		prev_cam = cam
		prev_shot = shot
		var ball := clip.ball_position(i)
		var base := clip.body_position(i, subject) if subject >= 0 else ball - Vector3.UP * 0.2
		var top := base + Vector3.UP * SUBJECT_HEIGHT * (scale if subject >= 0 else 0.0) \
			+ (Vector3.UP * 0.4 if subject < 0 else Vector3.ZERO)
		px.append(_screen_height(base, top))
		var ball_ok := _on_screen(ball)
		if ball_ok:
			ball_in += 1
		if i == event and (row.type == "goal" or row.type == "behind"):
			goal_seen = ball_ok
		var mid := (base + top) * 0.5
		var c := occ.check(cam, mid)
		if c.inside:
			inside += 1
		if c.blocked:
			blocked += 1
		if shots.has(i):
			await RenderingServer.frame_post_draw
			var img := _view.get_texture().get_image()
			img.save_png(frames_dir.path_join("%02d_%s_%s_%s.png" % [int(row.rank), row.type, preset, shots[i]]))
	var sorted := px.duplicate()
	sorted.sort()
	var out := {"rank": row.rank, "id": row.id, "type": row.type, "preset": preset, "frames": n,
		"subject_px_median": roundi(sorted[sorted.size() / 2]) if not sorted.is_empty() else 0,
		"subject_px_p10": roundi(sorted[sorted.size() / 10]) if not sorted.is_empty() else 0,
		"ball_vis": float(ball_in) / maxf(1.0, n), "inside": inside, "blocked": blocked, "jumps": jumps, "cuts": cuts}
	if row.type == "goal" or row.type == "behind":
		out["goal_seen"] = goal_seen
	return out


func _on_screen(p: Vector3) -> bool:
	if _camera.is_position_behind(p):
		return false
	var s := _camera.unproject_position(p)
	var r := Vector2(_view.size)
	return s.x >= 0.0 and s.y >= 0.0 and s.x <= r.x and s.y <= r.y


## Projected height of base→top in 1080-line pixels (0 if behind the lens).
func _screen_height(base: Vector3, top: Vector3) -> float:
	if _camera.is_position_behind(base) or _camera.is_position_behind(top):
		return 0.0
	var a := _camera.unproject_position(base)
	var b := _camera.unproject_position(top)
	return a.distance_to(b) * (1920.0 if _portrait else LINES) / float(_view.size.y)


## --full: the whole match.replay on the match camera (no moment context),
## the stretch between moments that the full-match video shows. Reports the
## runs of frames with the lens inside scenery.
func _audit_full(folder: String, preset: String) -> void:
	var clip := ReplayClip.load_file(folder.path_join("match.replay"))
	if clip == null:
		push_error("AUDIT: no match.replay")
		return
	_stage.load_clip(clip)
	var occ := _stage.occluders()
	var n := clip.frame_count()
	var inside := 0
	var blocked := 0
	var run := 0
	var runs: Array = []
	var px: Array[float] = []
	for i in n:
		var t := float(i) / clip.fps()
		_stage.apply(t)
		_stage.frame_camera(_camera, preset, false, t, 1.0 / clip.fps(), i == 0)
		var ball := clip.ball_position(i)
		var c := occ.check(_camera.global_position, ball)
		if c.inside:
			inside += 1
			run += 1
		elif run > 0:
			runs.append([i - run, run])
			run = 0
		if c.blocked:
			blocked += 1
		if i % 10 == 0:
			px.append(_screen_height(ball - Vector3.UP * ball.y, ball - Vector3.UP * ball.y + Vector3.UP * SUBJECT_HEIGHT))
	px.sort()
	runs.sort_custom(func(a: Array, b: Array) -> bool: return a[1] > b[1])
	print("AUDIT FULL %s frames %d  inside %d  blocked %d  player-at-ball px median %d  longest inside runs %s" % [
		preset, n, inside, blocked, roundi(px[px.size() / 2]), str(runs.slice(0, 5))])
