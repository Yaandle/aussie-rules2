class_name HighlightPaths
extends RefCounted

## Where Highlights exports go: a `highlights/` folder beside the game.
## In a built game that's next to the .exe, wherever it was installed, so
## every user's exports land in their own install. Run from the editor it's
## the project root, which .gitignore leaves out (`/highlights/`) and a
## `.gdignore` keeps Godot from importing the clips.
##
## An install folder can be read-only (Program Files): then it falls back
## to `user://highlights` (%APPDATA%\Godot\app_userdata\Aussie Rules 2\
## highlights on Windows). The Highlights screen always shows the path it
## really used.

const FOLDER := "highlights"
## Where the match being played records its full-match file (one at a time:
## the next match overwrites it). The exporter copies it into the match's
## export folder.
const RECORDING := "_recording"
const MATCH_REPLAY := "match.replay"
const MATCH_JSON := "match.json"


static func root() -> String:
	var base := ProjectSettings.globalize_path("res://") if OS.has_feature("editor") \
		else OS.get_executable_path().get_base_dir()
	var dir := base.path_join(FOLDER)
	if _writable(dir):
		return dir
	var fallback := ProjectSettings.globalize_path("user://").path_join(FOLDER)
	_writable(fallback)
	return fallback


## Where ffmpeg might be when it isn't on PATH: the video tool's own copy on
## the dev machine (F:/dev/video-editor, studio/config.py's tools/ffmpeg/bin).
## The `ffmpeg` key in user://highlights.cfg wins over both.
const FFMPEG_CANDIDATES := ["F:/dev/video-editor/video-editor/tools/ffmpeg/bin/ffmpeg.exe"]

static var _ffmpeg := ""
static var _ffmpeg_checked := false


## The ffmpeg to run, or "" when there's none: the saved path, a known copy,
## then PATH. Checked once per run.
static func ffmpeg() -> String:
	if _ffmpeg_checked:
		return _ffmpeg
	_ffmpeg_checked = true
	var candidates: Array[String] = []
	var saved := HighlightPrefs.ffmpeg_path()
	if saved != "":
		candidates.append(saved)
	for c: String in FFMPEG_CANDIDATES:
		candidates.append(c)
	for c in candidates:
		if FileAccess.file_exists(c):
			_ffmpeg = c
			return _ffmpeg
	var out: Array = []
	if OS.execute("ffmpeg", ["-version"], out) == 0:
		_ffmpeg = "ffmpeg"
	return _ffmpeg


static func recording_dir() -> String:
	var dir := root().path_join(RECORDING)
	DirAccess.make_dir_recursive_absolute(dir)
	return dir


## A fresh per-match folder under root(): `<date>_<time>_<HOME>-v-<AWAY>`.
## `sub` puts it one folder down (the generator's footage goes in `generated/`,
## apart from the player's own matches).
static func match_folder(home: String, away: String, sub := "") -> String:
	var t := Time.get_datetime_dict_from_system()
	var stamp := "%04d-%02d-%02d_%02d%02d%02d" % [t.year, t.month, t.day, t.hour, t.minute, t.second]
	var parent := root() if sub == "" else root().path_join(sub)
	var dir := parent.path_join("%s_%s-v-%s" % [stamp, _slug(home), _slug(away)])
	DirAccess.make_dir_recursive_absolute(dir)
	return dir


static func _writable(dir: String) -> bool:
	if DirAccess.make_dir_recursive_absolute(dir) != OK and not DirAccess.dir_exists_absolute(dir):
		return false
	var marker := dir.path_join(".gdignore")
	if FileAccess.file_exists(marker):
		return true
	var file := FileAccess.open(marker, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string("Highlights exports: not game assets.\n")
	file.close()
	return true


static func _slug(text: String) -> String:
	var out := ""
	for c in text.strip_edges():
		out += c if (c.is_valid_identifier() or c.is_valid_int()) else "_"
	return out if out != "" else "team"
