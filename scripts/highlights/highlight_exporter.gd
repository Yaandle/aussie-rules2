class_name HighlightExporter
extends Node

## Renders the kept highlight moments to video files and writes
## moments.json beside them, into a per-match folder under HighlightPaths.
##
## Each clip is replayed on the ReplayStage and drawn into two off-screen
## SubViewports at once, landscape 1920x1080 and portrait 1080x1920, one
## recorded frame per rendered frame, so the export is frame-exact whatever
## the machine's frame rate (it just takes longer on a slow one). Frames go
## to MjpegAviWriter; if ffmpeg is on PATH each .avi is also converted to an
## H.264 .mp4 afterwards.
##
## Output, per moment NN (its rank, best first):
##   NN_<type>_16x9.avi, NN_<type>_9x16.avi   MJPEG, 30 fps
##   NN_<type>_16x9.mp4, NN_<type>_9x16.mp4   only when ffmpeg is found
##   NN_<type>.replay                          the raw pose data (ReplayClip)
## plus moments.json describing them all (docs/HIGHLIGHTS.md has the schema).

signal progress(text: String, fraction: float)
signal finished(folder: String, ok: bool)

const FORMAT := "aussie-rules-2-highlights"
const VERSION := 1

var stage: ReplayStage
var busy := false
var _cancel := false


func cancel() -> void:
	_cancel = true


## Exports `moments` (Highlights' dictionaries, best first) to a fresh
## folder. Awaitable; emits progress as it goes and finished at the end.
func export_moments(moments: Array[Dictionary], match_info: Dictionary) -> String:
	busy = true
	_cancel = false
	var folder := HighlightPaths.match_folder(String(match_info.get("home", "Home")),
		String(match_info.get("away", "Away")))
	var land := _viewport(HighlightTable.EXPORT_LANDSCAPE)
	var port := _viewport(HighlightTable.EXPORT_PORTRAIT)
	var rows: Array = []
	var fps := HighlightTable.EXPORT_FPS
	for n in moments.size():
		if _cancel:
			break
		var moment := moments[n]
		var clip: ReplayClip = moment.clip
		var base := "%02d_%s" % [n + 1, String(moment.type)]
		var files := {
			"landscape": base + "_16x9.avi", "portrait": base + "_9x16.avi", "replay": base + ".replay",
		}
		clip.save(folder.path_join(files.replay))
		stage.load_clip(clip)
		var preset := String(moment.get("camera", stage.default_preset()))
		var writer_l := MjpegAviWriter.new()
		var writer_p := MjpegAviWriter.new()
		writer_l.open(folder.path_join(files.landscape), HighlightTable.EXPORT_LANDSCAPE, fps)
		writer_p.open(folder.path_join(files.portrait), HighlightTable.EXPORT_PORTRAIT, fps)
		var total := clip.frame_count()
		for i in total:
			if _cancel:
				break
			var t := float(i) / float(fps)
			stage.apply(t)
			stage.frame_camera(land.camera, preset, false, t, 1.0 / fps, i == 0)
			stage.frame_camera(port.camera, preset, true, t, 1.0 / fps, i == 0)
			await RenderingServer.frame_post_draw
			writer_l.add_image(land.viewport.get_texture().get_image(), HighlightTable.EXPORT_JPEG_QUALITY)
			writer_p.add_image(port.viewport.get_texture().get_image(), HighlightTable.EXPORT_JPEG_QUALITY)
			progress.emit("Rendering %d of %d: %s" % [n + 1, moments.size(), String(moment.label)],
				(float(n) + float(i) / float(total)) / float(moments.size()))
		writer_l.close()
		writer_p.close()
		rows.append(_row(moment, n + 1, files, preset))

	land.viewport.queue_free()
	port.viewport.queue_free()

	var mp4 := not _cancel and _has_ffmpeg()
	if mp4:
		for n in rows.size():
			var files: Dictionary = rows[n].files
			for key: String in ["landscape", "portrait"]:
				var avi: String = files[key]
				var out := avi.get_basename() + ".mp4"
				progress.emit("Converting to mp4: %s" % out, float(n) / float(rows.size()))
				if await _ffmpeg(folder.path_join(avi), folder.path_join(out)):
					files[key + "_mp4"] = out

	var doc := {
		"format": FORMAT, "version": VERSION,
		"match": match_info.duplicate(true),
		"exported_at": Time.get_datetime_string_from_system(),
		"output": {
			"folder": folder,
			"video": "MJPEG AVI, %d fps, landscape %dx%d (16:9) and portrait %dx%d (9:16)" % [fps,
				HighlightTable.EXPORT_LANDSCAPE.x, HighlightTable.EXPORT_LANDSCAPE.y,
				HighlightTable.EXPORT_PORTRAIT.x, HighlightTable.EXPORT_PORTRAIT.y],
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


## The moments.json entry for one moment. Plain data only.
static func _row(moment: Dictionary, rank: int, files: Dictionary, camera: String) -> Dictionary:
	var clip: ReplayClip = moment.clip
	var elapsed := float(moment.quarter_elapsed_s)
	return {
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
	}


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
