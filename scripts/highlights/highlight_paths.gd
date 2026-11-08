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


static func root() -> String:
	var base := ProjectSettings.globalize_path("res://") if OS.has_feature("editor") \
		else OS.get_executable_path().get_base_dir()
	var dir := base.path_join(FOLDER)
	if _writable(dir):
		return dir
	var fallback := ProjectSettings.globalize_path("user://").path_join(FOLDER)
	_writable(fallback)
	return fallback


## A fresh per-match folder under root(): `<date>_<time>_<HOME>-v-<AWAY>`.
static func match_folder(home: String, away: String) -> String:
	var t := Time.get_datetime_dict_from_system()
	var stamp := "%04d-%02d-%02d_%02d%02d%02d" % [t.year, t.month, t.day, t.hour, t.minute, t.second]
	var dir := root().path_join("%s_%s-v-%s" % [stamp, _slug(home), _slug(away)])
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
