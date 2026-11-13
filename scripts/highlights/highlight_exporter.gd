class_name HighlightExporter
extends Node

## Renders the kept highlight moments to video files and writes
## moments.json beside them, into a per-match folder under HighlightPaths.
##
## Each clip is replayed on the ReplayStage and drawn into off-screen
## SubViewports, landscape 1920x1080 and/or portrait 1080x1920 (the
## `aspect` option: both, 16:9 only or 9:16 only; one shape is half the
## render), one recorded frame per rendered frame, so the export is
## frame-exact whatever the machine's frame rate (it just takes longer on a
## slow one). Frames go to MjpegAviWriter; if ffmpeg is on PATH each .avi is
## also converted to an H.264 .mp4 afterwards.
##
## Output, per moment NN (its rank, best first):
##   NN_<type>_16x9.avi, NN_<type>_9x16.avi   MJPEG, 30 fps (the shapes asked for)
##   NN_<type>_16x9.mp4, NN_<type>_9x16.mp4   only when ffmpeg is found
##   NN_<type>.replay                          the raw pose data (ReplayClip)
## plus moments.json describing them all (docs/HIGHLIGHTS.md has the schema).
##
## A cancelled export keeps the clip it was part-way through, and its row says
## so: "complete": false with `frames` the frames actually written (the
## .replay is always whole, `replay_frames`).

signal progress(text: String, fraction: float)
signal finished(folder: String, ok: bool)

const FORMAT := "aussie-rules-2-highlights"
## 2: adds match.mode, footage and, per moment, event_frame, frames,
## replay_frames, complete, events and (goals/behinds) kick_frame, kicker and
## kick_distance. Every v1 field is as it was.
const VERSION := 2

var stage: ReplayStage
var busy := false
var _cancel := false


func cancel() -> void:
	_cancel = true


## Exports `moments` (Highlights' dictionaries, best first) to a fresh
## folder. `options`: `aspect` ("both", "16x9" or "9x16", default the saved
## choice), `footage` ("match" or "generated", default Highlights') and
## `subfolder` (under the highlights folder, default none). Awaitable; emits
## progress as it goes and finished at the end.
func export_moments(moments: Array[Dictionary], match_info: Dictionary, options := {}) -> String:
	busy = true
	_cancel = false
	var aspect := String(options.get("aspect", HighlightPrefs.aspect()))
	var footage := String(options.get("footage", Highlights.footage))
	var want_land := aspect != "9x16"
	var want_port := aspect != "16x9"
	var folder := HighlightPaths.match_folder(String(match_info.get("home", "Home")),
		String(match_info.get("away", "Away")), String(options.get("subfolder", "")))
	var land := _viewport(HighlightTable.EXPORT_LANDSCAPE) if want_land else {}
	var port := _viewport(HighlightTable.EXPORT_PORTRAIT) if want_port else {}
	var rows: Array = []
	var fps := HighlightTable.EXPORT_FPS
	for n in moments.size():
		if _cancel:
			break
		var moment := moments[n]
		var clip: ReplayClip = moment.clip
		var base := "%02d_%s" % [n + 1, String(moment.type)]
		var files := {"replay": base + ".replay"}
		if want_land:
			files["landscape"] = base + "_16x9.avi"
		if want_port:
			files["portrait"] = base + "_9x16.avi"
		clip.save(folder.path_join(files.replay))
		stage.load_clip(clip)
		var preset := String(moment.get("camera", stage.default_preset()))
		var writer_l: MjpegAviWriter = null
		var writer_p: MjpegAviWriter = null
		if want_land:
			writer_l = MjpegAviWriter.new()
			writer_l.open(folder.path_join(files.landscape), HighlightTable.EXPORT_LANDSCAPE, fps)
		if want_port:
			writer_p = MjpegAviWriter.new()
			writer_p.open(folder.path_join(files.portrait), HighlightTable.EXPORT_PORTRAIT, fps)
		var total := clip.frame_count()
		var written := 0
		for i in total:
			if _cancel:
				break
			var t := float(i) / float(fps)
			stage.apply(t)
			if want_land:
				stage.frame_camera(land.camera, preset, false, t, 1.0 / fps, i == 0)
			if want_port:
				stage.frame_camera(port.camera, preset, true, t, 1.0 / fps, i == 0)
			await RenderingServer.frame_post_draw
			if want_land:
				writer_l.add_image(land.viewport.get_texture().get_image(), HighlightTable.EXPORT_JPEG_QUALITY)
			if want_port:
				writer_p.add_image(port.viewport.get_texture().get_image(), HighlightTable.EXPORT_JPEG_QUALITY)
			written += 1
			progress.emit("Rendering %d of %d: %s" % [n + 1, moments.size(), String(moment.label)],
				(float(n) + float(i) / float(total)) / float(moments.size()))
		if writer_l != null:
			writer_l.close()
		if writer_p != null:
			writer_p.close()
		if written == 0:
			# Cancelled before a single frame: nothing to describe.
			for key: String in files:
				DirAccess.remove_absolute(folder.path_join(String(files[key])))
			continue
		rows.append(_row(moment, n + 1, files, preset, written))

	if want_land:
		land.viewport.queue_free()
	if want_port:
		port.viewport.queue_free()

	var mp4 := not _cancel and _has_ffmpeg()
	if mp4:
		for n in rows.size():
			var files: Dictionary = rows[n].files
			for key: String in ["landscape", "portrait"]:
				if not files.has(key):
					continue
				var avi: String = files[key]
				var out := avi.get_basename() + ".mp4"
				progress.emit("Converting to mp4: %s" % out, float(n) / float(rows.size()))
				if await _ffmpeg(folder.path_join(avi), folder.path_join(out)):
					files[key + "_mp4"] = out

	var shapes: Array[String] = []
	if want_land:
		shapes.append("landscape %dx%d (16:9)" % [HighlightTable.EXPORT_LANDSCAPE.x, HighlightTable.EXPORT_LANDSCAPE.y])
	if want_port:
		shapes.append("portrait %dx%d (9:16)" % [HighlightTable.EXPORT_PORTRAIT.x, HighlightTable.EXPORT_PORTRAIT.y])
	var match_doc := match_info.duplicate(true)
	if not match_doc.has("mode"):
		match_doc["mode"] = "human_vs_ai"
	var doc := {
		"format": FORMAT, "version": VERSION,
		"footage": footage,
		"match": match_doc,
		"exported_at": Time.get_datetime_string_from_system(),
		"output": {
			"folder": folder,
			"video": "MJPEG AVI, %d fps, %s" % [fps, " and ".join(shapes)],
			"aspect": aspect,
			"mp4": mp4,
			"complete": not _cancel,
		},
		"moments": rows,
	}
	var json := FileAccess.open(folder.path_join("moments.json"), FileAccess.WRITE)
	if json != null:
		json.store_string(JSON.stringify(doc, "  ", false))
		json.close()
	busy = false
	finished.emit(folder, not _cancel)
	return folder


## The moments.json entry for one moment. Plain data only. `written` is the
## number of video frames actually rendered: under the clip's own count when
## the export was cancelled part-way.
static func _row(moment: Dictionary, rank: int, files: Dictionary, camera: String, written: int) -> Dictionary:
	var clip: ReplayClip = moment.clip
	var elapsed := float(moment.quarter_elapsed_s)
	var row := {
		"id": moment.id, "rank": rank, "type": moment.type, "label": moment.label,
		"caption": moment.caption,
		"quarter": moment.quarter,
		"game_clock": "Q%d %d:%02d" % [int(moment.quarter), int(elapsed) / 60, int(elapsed) % 60],
		"quarter_elapsed_s": elapsed,
		"match_time_s": moment.match_time_s,
		"duration_s": snappedf(clip.duration(), 0.01),
		"event_offset_s": snappedf(float(clip.meta.get("event_frame", 0)) / clip.fps(), 0.01),
		"highlight_score": moment.highlight_score,
		"human_involved": moment.human,
		"players": moment.players,
		"score_before": moment.score_before,
		"score_after": moment.score_after,
		"facts": moment.facts,
		"camera": camera,
		"files": files,
		# v2
		"event_frame": int(clip.meta.get("event_frame", 0)),
		"frames": written,
		"replay_frames": clip.frame_count(),
		"complete": written >= clip.frame_count(),
		"events": moment.get("events", []),
	}
	if moment.type == "goal" or moment.type == "behind":
		row["kick_frame"] = moment.get("kick_frame")
		row["kicker"] = moment.get("kicker")
		row["kick_distance"] = moment.get("kick_distance")
	return row


func _viewport(size: Vector2i) -> Dictionary:
	var viewport := SubViewport.new()
	viewport.size = size
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.msaa_3d = Viewport.MSAA_4X
	var camera := Camera3D.new()
	camera.current = true
	viewport.add_child(camera)
	stage.add_child(viewport)
	return {"viewport": viewport, "camera": camera}


static func _has_ffmpeg() -> bool:
	var out: Array = []
	return OS.execute("ffmpeg", ["-version"], out) == 0


## Runs ffmpeg in its own process and waits for it without blocking the
## frame (the screen keeps drawing its progress).
func _ffmpeg(input: String, output: String) -> bool:
	var pid := OS.create_process("ffmpeg", ["-y", "-loglevel", "error", "-i", input,
		"-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "20", "-movflags", "+faststart", output])
	if pid <= 0:
		return false
	while OS.is_process_running(pid):
		await get_tree().create_timer(0.2).timeout
	return FileAccess.file_exists(output)
