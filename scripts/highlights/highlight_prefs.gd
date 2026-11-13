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


static func aspect() -> String:
	_ensure()
	return _aspect


static func set_aspect(value: String) -> void:
	_ensure()
	if HighlightTable.ASPECTS.has(value):
		_aspect = value
		_save()
