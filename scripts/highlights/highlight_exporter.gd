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
##   match.replay, match.json                  the whole match, when recorded
##   match_16x9.mp4, match_video.json          that match rendered, dead time
##                                             cut (export_full_match)
##   highlight.mp4                             the exported moments cut from it,
##                                             in match order, same cameras
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
## folder: each moment's .replay and moments.json row, the full match
## (match.replay, match.json, then export_full_match: match_16x9.mp4,
## highlight.mp4 of these moments, match_video.json), and, only when asked,
## each moment as its own video file (the old format).
##
## `options`: `clips` (render each moment's own video file; default the saved
## choice, and always when there's no full-match recording to cut from),
## `aspect` for those files ("both", "16x9" or "9x16", default 16x9),
## `full_video` (default true), `footage` ("match" or "generated", default
## Highlights') and `subfolder` (under the highlights folder, default none).
## Awaitable; emits progress as it goes and finished at the end.
func export_moments(moments: Array[Dictionary], match_info: Dictionary, options := {}) -> String:
	busy = true
	_cancel = false
	var full: Dictionary = options.get("full_match", Highlights.full_match)
	var have_full := not full.is_empty() and FileAccess.file_exists(String(full.replay))
	var clips := bool(options.get("clips", HighlightPrefs.clip_files())) or not have_full
	var aspect := String(options.get("aspect", "16x9"))
	var footage := String(options.get("footage", Highlights.footage))
	var want_land := clips and aspect != "9x16"
	var want_port := clips and aspect != "16x9"
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
		if not clips:
			# No video of its own: it's in highlight.mp4. The row still says
			# where it is (match_from..) and keeps its .replay.
			var row := _row(moment, n + 1, files, preset, 0)
			row["frames"] = 0
			row["complete"] = true
			rows.append(row)
			continue
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
			"video": "MJPEG AVI, %d fps, %s" % [fps, " and ".join(shapes)] if clips else "no separate clips (in highlight.mp4)",
			"clips": clips,
			"aspect": aspect,
			"mp4": mp4,
			"complete": not _cancel,
		},
		"moments": rows,
	}
	if have_full and not _cancel:
		progress.emit("Copying the full-match recording", 1.0)
		await get_tree().process_frame
		var ok := DirAccess.copy_absolute(String(full.replay), folder.path_join(HighlightPaths.MATCH_REPLAY)) == OK \
			and DirAccess.copy_absolute(String(full.json), folder.path_join(HighlightPaths.MATCH_JSON)) == OK
		if ok:
			doc["full_match"] = {"replay": HighlightPaths.MATCH_REPLAY, "json": HighlightPaths.MATCH_JSON,
				"frames": int(full.frames), "fps": int(full.fps)}
	var json := FileAccess.open(folder.path_join("moments.json"), FileAccess.WRITE)
	if json != null:
		json.store_string(JSON.stringify(doc, "  ", false))
		json.close()
	if doc.has("full_match") and not _cancel and bool(options.get("full_video", true)):
		# The exported moments set the cameras and make highlight.mp4.
		await export_full_match(folder, MatchCameraPlan.from_moments(moments, HighlightPrefs.match_camera()))
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
	if moment.has("match_from"):
		# Where the clip sits in match.replay (full-match frames).
		row["match_from"] = moment.match_from
		row["match_to"] = moment.match_to
		row["match_frame"] = moment.match_frame
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
	return HighlightPaths.ffmpeg() != ""


## Runs ffmpeg in its own process and waits for it without blocking the
## frame (the screen keeps drawing its progress).
func _ffmpeg(input: String, output: String) -> bool:
	return await _run_ffmpeg(["-y", "-loglevel", "error", "-i", input,
		"-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "20", "-movflags", "+faststart", output], output)


func _run_ffmpeg(args: PackedStringArray, output: String) -> bool:
	var pid := OS.create_process(HighlightPaths.ffmpeg(), args)
	if pid <= 0:
		return false
	while OS.is_process_running(pid):
		await get_tree().create_timer(0.2).timeout
	return FileAccess.file_exists(output)


# ── Full match (docs/HIGHLIGHTS_FULLGAME_PLAN.md, phase 2) ─────────────

const MATCH_VIDEO := "match_16x9.mp4"
const MATCH_VIDEO_JSON := "match_video.json"
const HIGHLIGHT_VIDEO := "highlight.mp4"


## Renders `folder`'s match.replay to one 16:9 video with the dead time cut
## (FullMatchCut), and writes match_video.json: the kept ranges, every event
## of match.json as a marker on its video frame, and where each moment of
## moments.json is in the video. Cameras come from `plan` (MatchCameraPlan:
## each listed moment's stretch from its own camera, the rest from the match
## camera; default built from Highlights.listed()), snapped at each cut and
## each change of stretch so both are clean jumps. Then highlight.mp4: the
## exported moments' stretches cut out of the joined video, in match order,
## overlaps merged (needs ffmpeg).
##
## A part left from an earlier run is reused as is, even if the cameras have
## changed since: delete the part to re-render it.
##
## A quarter at a time, each to its own part file, then joined. A part that
## finished is kept when the render is cancelled and skipped when it's run
## again, so a long render can be resumed. With ffmpeg (HighlightPaths.ffmpeg)
## frames are piped straight into an H.264 encoder: no 2.8 GB of MJPEG on
## disk. Without it each quarter is its own MJPEG .avi and there's no single
## match file (`video` null, `parts` lists them).
func export_full_match(folder: String, plan: MatchCameraPlan = null) -> bool:
	var was_busy := busy
	busy = true
	var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(folder.path_join(HighlightPaths.MATCH_JSON)))
	var clip := ReplayClip.load_file(folder.path_join(HighlightPaths.MATCH_REPLAY))
	if not (doc is Dictionary) or clip == null or clip.frame_count() == 0:
		busy = was_busy
		return false
	progress.emit("Full match: finding the dead time", 0.0)
	await get_tree().process_frame
	var cut := FullMatchCut.build(clip, doc)
	var ffmpeg := HighlightPaths.ffmpeg()
	var size := HighlightTable.EXPORT_LANDSCAPE
	var fps := HighlightTable.EXPORT_FPS
	if plan == null:
		plan = MatchCameraPlan.from_moments(Highlights.listed(), HighlightPrefs.match_camera())
	stage.load_clip(clip)
	var view := _viewport(size)

	var quarters: Array[int] = []
	for r in cut.keep:
		if not quarters.has(int(r.quarter)):
			quarters.append(int(r.quarter))
	var parts: Array = []
	var done := 0
	for q in quarters:
		if _cancel:
			break
		var ranges: Array[Dictionary] = []
		var frames := 0
		for r in cut.keep:
			if int(r.quarter) == q:
				ranges.append(r)
				frames += int(r.video_frames)
		var file := "match_q%d_16x9.%s" % [q, "mp4" if ffmpeg != "" else "avi"]
		var path := folder.path_join(file)
		var part := {"quarter": q, "file": file, "video_from": int(ranges[0].video_from), "frames": frames}
		if FileAccess.file_exists(path):
			# Finished on an earlier run (unfinished parts are written under
			# a .partial name and only renamed once complete).
			parts.append(part)
			done += frames
			continue
		var partial := path + ".partial" + ("" if ffmpeg == "" else ".mp4")
		var sink := _open_sink(ffmpeg, partial, size, fps)
		if sink.is_empty():
			push_warning("HighlightExporter: couldn't start the full-match encoder")
			break
		var written := 0
		var stretch := -2
		for r in ranges:
			for j in int(r.video_frames):
				if _cancel:
					break
				var source := cut.source_frame(r, j)
				var s := plan.at(int(round(source)))
				var snap := j == 0 or s != stretch
				if s != stretch:
					stage.set_context(plan.context(s))
					stretch = s
				stage.apply(source / clip.fps())
				stage.frame_camera(view.camera, plan.preset(s), false, float(written) / fps, 1.0 / fps, snap)
				await RenderingServer.frame_post_draw
				_sink_add(sink, view.viewport.get_texture().get_image())
				written += 1
				if written % 15 == 0:
					progress.emit("Full match: quarter %d, %d of %d frames" % [q, done + written, cut.video_frames],
						float(done + written) / float(cut.video_frames))
		await _close_sink(sink)
		if _cancel or written < frames or not FileAccess.file_exists(partial):
			DirAccess.remove_absolute(partial)
			break
		DirAccess.rename_absolute(partial, path)
		parts.append(part)
		done += frames
	view.viewport.queue_free()

	var complete := parts.size() == quarters.size()
	var video: Variant = null
	if complete and ffmpeg != "":
		progress.emit("Full match: joining the quarters", 1.0)
		var list_path := folder.path_join("match_parts.txt")
		var list := FileAccess.open(list_path, FileAccess.WRITE)
		for p: Dictionary in parts:
			list.store_line("file '%s'" % String(p.file))
		list.close()
		var out := folder.path_join(MATCH_VIDEO)
		if await _run_ffmpeg(["-y", "-loglevel", "error", "-f", "concat", "-safe", "0", "-i", list_path,
				"-c", "copy", "-movflags", "+faststart", out], out):
			video = MATCH_VIDEO
			# The joined file has every frame: the parts would only double
			# the disk use.
			for p: Dictionary in parts:
				DirAccess.remove_absolute(folder.path_join(String(p.file)))
				p["file"] = null
		DirAccess.remove_absolute(list_path)
	var highlight := {}
	if video != null and not _cancel:
		highlight = await _cut_highlight(folder, cut)
	stage.set_context({})
	_write_match_video(folder, doc, cut, parts, video, complete, plan, highlight)
	busy = was_busy
	return complete


## highlight.mp4: the exported moments (moments.json rows) cut out of the
## full-match video by frame number, in match order, overlapping stretches
## merged so nothing plays twice. Re-encoded (a frame-exact cut can't be a
## stream copy). {} when there's nothing to cut or ffmpeg failed.
func _cut_highlight(folder: String, cut: FullMatchCut) -> Dictionary:
	var moments_doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("moments.json")))
	if not (moments_doc is Dictionary):
		return {}
	var spans: Array = []
	for row: Dictionary in moments_doc.get("moments", []):
		if row.has("match_from"):
			spans.append({"from": int(cut.video_frame(int(row.match_from)).frame),
				"to": int(cut.video_frame(int(row.match_to)).frame), "ids": [row.id]})
	if spans.is_empty():
		return {}
	spans.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.from) < int(b.from))
	var merged: Array = [spans[0]]
	for k in range(1, spans.size()):
		var last: Dictionary = merged[-1]
		if int(spans[k].from) <= int(last.to) + 1:
			last.to = maxi(int(last.to), int(spans[k].to))
			(last.ids as Array).append_array(spans[k].ids)
		else:
			merged.append(spans[k])
	var terms: Array[String] = []
	var at := 0
	var segments: Array = []
	for span: Dictionary in merged:
		terms.append("between(n,%d,%d)" % [int(span.from), int(span.to)])
		segments.append({"video_from": span.from, "video_to": span.to, "highlight_from": at, "moments": span.ids})
		at += int(span.to) - int(span.from) + 1
	progress.emit("Cutting highlight.mp4 (%d stretches)" % merged.size(), 1.0)
	var out := folder.path_join(HIGHLIGHT_VIDEO)
	var ok: bool = await _run_ffmpeg(["-y", "-loglevel", "error", "-i", folder.path_join(MATCH_VIDEO),
		"-vf", "select='%s',setpts=N/(%d*TB)" % ["+".join(terms), HighlightTable.EXPORT_FPS], "-an",
		"-r", str(HighlightTable.EXPORT_FPS), "-fps_mode", "cfr",
		"-c:v", "libx264", "-preset", HighlightTable.FULL_MATCH_PRESET, "-crf", str(HighlightTable.FULL_MATCH_CRF),
		"-pix_fmt", "yuv420p", "-movflags", "+faststart", out], out)
	if not ok:
		return {}
	return {"file": HIGHLIGHT_VIDEO, "frames": at, "segments": segments}


## The encoder for one part: ffmpeg reading raw RGB on stdin, or an MJPEG
## writer. {} if neither could start.
func _open_sink(ffmpeg: String, path: String, size: Vector2i, fps: int) -> Dictionary:
	if ffmpeg == "":
		var writer := MjpegAviWriter.new()
		if writer.open(path, size, fps) != OK:
			return {}
		return {"avi": writer}
	var pipe := OS.execute_with_pipe(ffmpeg, ["-y", "-loglevel", "error", "-nostats",
		"-f", "rawvideo", "-pix_fmt", "rgb24", "-s", "%dx%d" % [size.x, size.y], "-r", str(fps), "-i", "pipe:0",
		"-c:v", "libx264", "-preset", HighlightTable.FULL_MATCH_PRESET, "-crf", str(HighlightTable.FULL_MATCH_CRF),
		"-pix_fmt", "yuv420p", "-movflags", "+faststart", path])
	if pipe.is_empty():
		return {}
	return {"pipe": pipe}


func _sink_add(sink: Dictionary, image: Image) -> void:
	if sink.has("avi"):
		(sink.avi as MjpegAviWriter).add_image(image, HighlightTable.EXPORT_JPEG_QUALITY)
		return
	if image.get_format() != Image.FORMAT_RGB8:
		image.convert(Image.FORMAT_RGB8)
	(sink.pipe.stdio as FileAccess).store_buffer(image.get_data())


func _close_sink(sink: Dictionary) -> void:
	if sink.has("avi"):
		(sink.avi as MjpegAviWriter).close()
		return
	(sink.pipe.stdio as FileAccess).close()
	var pid := int(sink.pipe.pid)
	while OS.is_process_running(pid):
		await get_tree().create_timer(0.2).timeout


func _write_match_video(folder: String, doc: Dictionary, cut: FullMatchCut, parts: Array, video: Variant,
		complete: bool, plan: MatchCameraPlan, highlight: Dictionary) -> void:
	var keep: Array = []
	for r in cut.keep:
		keep.append({"from": int(r.from), "to": int(r.to), "quarter": int(r.quarter),
			"video_from": int(r.video_from), "video_frames": int(r.video_frames)})
	var markers: Array = []
	for ev: Dictionary in doc.get("events", []):
		var at := cut.video_frame(int(ev.frame))
		var marker := ev.duplicate()
		marker["video_frame"] = at.frame
		marker["cut"] = at.cut
		markers.append(marker)
	var moments: Array = []
	var moments_doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("moments.json")))
	if moments_doc is Dictionary:
		for row: Dictionary in moments_doc.get("moments", []):
			if not row.has("match_from"):
				continue
			moments.append({"id": row.id, "rank": row.rank, "type": row.type, "label": row.label,
				"video_from": cut.video_frame(int(row.match_from)).frame,
				"video_to": cut.video_frame(int(row.match_to)).frame,
				"video_frame": cut.video_frame(int(row.match_frame)).frame,
				"event_cut": cut.video_frame(int(row.match_frame)).cut})
	var summary := cut.summary()
	var out := {
		"format": "aussie-rules-2-match-video", "version": 1,
		"fps": HighlightTable.EXPORT_FPS,
		"size": [HighlightTable.EXPORT_LANDSCAPE.x, HighlightTable.EXPORT_LANDSCAPE.y],
		"camera": plan.default_preset,
		"cameras": plan.video_runs(cut),
		"highlight": highlight if not highlight.is_empty() else null,
		"video": video,
		"parts": parts,
		"frames": cut.video_frames,
		"complete": complete,
		"recorded_s": snappedf(float(summary.recorded_s), 0.01),
		"video_s": snappedf(float(summary.video_s), 0.01),
		"trim": {"dead_min": HighlightTable.DEAD_MIN, "keep_after": HighlightTable.DEAD_KEEP_AFTER,
			"keep_before": HighlightTable.DEAD_KEEP_BEFORE},
		"keep": keep,
		"markers": markers,
		"moments": moments,
	}
	var file := FileAccess.open(folder.path_join(MATCH_VIDEO_JSON), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(out, "  ", false))
		file.close()
