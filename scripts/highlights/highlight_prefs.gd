class_name HighlightPrefs
extends RefCounted

## The player's Highlights choices, remembered between runs: which moment
## types are switched on (listed and ticked for export), each type's default
## camera, and the export format (both shapes, 16:9 only or 9:16 only).
##
## Its own file (user://highlights.cfg) rather than settings.cfg: the
## Settings autoload is busy with controls and HUD work, and nothing here is
## read by gameplay. Static, loaded on first use. `transient` stops writes
## (the generator sets types and cameras for itself and must not overwrite
## what the player chose).

const PATH := "user://highlights.cfg"
const SECTION := "highlights"

static var transient := false

static var _loaded := false
static var _types := {}
static var _cameras := {}
static var _aspect := "both"
## Record the whole match to disk as well as the moments (~130 MB a match).
static var _full_match := true
## Render the full match to video when exporting (16:9, dead time cut).
static var _full_video := true
## An ffmpeg.exe to use (HighlightPaths.ffmpeg); "" looks for one. Not
## shown anywhere: set it in the .cfg.
static var _ffmpeg := ""
## The camera for the full match outside every moment's stretch
## (MatchCameraPlan): set on the Highlights screen's MATCH view.
static var _match_camera := ""


static func _ensure() -> void:
	if _loaded:
		return
	_loaded = true
	var config := ConfigFile.new()
	if config.load(PATH) != OK:
		return
	for type: String in HighlightTable.TYPE_ORDER:
		if config.has_section_key(SECTION, "on_" + type):
			_types[type] = bool(config.get_value(SECTION, "on_" + type))
		if config.has_section_key(SECTION, "camera_" + type):
			var preset := String(config.get_value(SECTION, "camera_" + type))
			if ReplayStage.CAMERA_PRESETS.has(preset):
				_cameras[type] = preset
	_full_video = bool(config.get_value(SECTION, "full_video", true))
	_ffmpeg = String(config.get_value(SECTION, "ffmpeg", ""))
	_match_camera = String(config.get_value(SECTION, "match_camera", ""))
	if not ReplayStage.CAMERA_PRESETS.has(_match_camera):
		_match_camera = ""
	if config.has_section_key(SECTION, "full_match"):
		_full_match = bool(config.get_value(SECTION, "full_match"))
	if config.has_section_key(SECTION, "aspect"):
		var aspect := String(config.get_value(SECTION, "aspect"))
		if HighlightTable.ASPECTS.has(aspect):
			_aspect = aspect


static func _save() -> void:
	if transient:
		return
	var config := ConfigFile.new()
	for type: String in HighlightTable.TYPE_ORDER:
		config.set_value(SECTION, "on_" + type, type_on(type))
		config.set_value(SECTION, "camera_" + type, camera_for(type))
	config.set_value(SECTION, "aspect", _aspect)
	config.set_value(SECTION, "full_match", _full_match)
	config.set_value(SECTION, "full_video", _full_video)
	config.set_value(SECTION, "ffmpeg", _ffmpeg)
	config.set_value(SECTION, "match_camera", match_camera())
	config.save(PATH)


static func type_on(type: String) -> bool:
	_ensure()
	if _types.has(type):
		return bool(_types[type])
	return bool((HighlightTable.TYPES.get(type, {}) as Dictionary).get("default_on", false))


static func set_type_on(type: String, on: bool) -> void:
	_ensure()
	_types[type] = on
	_save()


## The camera a type's moments are shot from unless a moment picked its own.
static func camera_for(type: String) -> String:
	_ensure()
	return String(_cameras.get(type, ReplayStage.DEFAULT_PRESET.get(type, "broadcast")))


static func set_camera(type: String, preset: String) -> void:
	_ensure()
	_cameras[type] = preset
	_save()


static func full_match() -> bool:
	_ensure()
	return _full_match


static func set_full_match(on: bool) -> void:
	_ensure()
	_full_match = on
	_save()


static func full_video() -> bool:
	_ensure()
	return _full_video


static func set_full_video(on: bool) -> void:
	_ensure()
	_full_video = on
	_save()


static func match_camera() -> String:
	_ensure()
	return _match_camera if _match_camera != "" else HighlightTable.FULL_MATCH_CAMERA


static func set_match_camera(preset: String) -> void:
	_ensure()
	_match_camera = preset
	_save()


static func ffmpeg_path() -> String:
	_ensure()
	return _ffmpeg


static func aspect() -> String:
	_ensure()
	return _aspect


static func set_aspect(value: String) -> void:
	_ensure()
	if HighlightTable.ASPECTS.has(value):
		_aspect = value
		_save()
