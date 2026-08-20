extends Node

## Persisted user settings — the first genuinely-saved settings this
## project has had (settings_screen.gd was, until this pass, an inert
## "PLACEHOLDER · NOT SAVED" display per its own header comment). Kept
## deliberately small: only the options this session actually wired
## behaviour to, rather than a speculative options schema for rows
## nothing reads yet.
##
## Saved to user://settings.cfg via ConfigFile — the standard, simplest
## persistence path for a handful of scalar options, no reason to reach
## for anything heavier.

const SAVE_PATH := "user://settings.cfg"
const SECTION := "settings"

## THIRD_PERSON/FULL_SIDE, per the design brief's own naming (this
## project's earlier working titles for these were "Broadcast"/"orthodox"
## respectively — kept as the enum's ordinal order so an existing
## user://settings.cfg int value still resolves to the same mode).
enum FullGameCameraMode { THIRD_PERSON, FULL_SIDE }

## THIRD_PERSON is this project's existing third-person chase rig
## (BroadcastCamera's default behaviour). FULL_SIDE is the elevated,
## outside-the-boundary broadcast rig — see BroadcastCamera.Mode.FULL_SIDE.
## kick_to_kick deliberately never reads this: it is single-player
## practice, not a match, and the brief that asked for this option was
## explicit that kick_to_kick "stays the same."
var full_game_camera_mode: FullGameCameraMode = FullGameCameraMode.THIRD_PERSON:
	set(value):
		if full_game_camera_mode == value:
			return
		full_game_camera_mode = value
		camera_mode_changed.emit(value)

## false (default): right-click holds kick stance/aim (like a gamepad's
## LT), left-click fires the kick (like RT). true: swapped, for players
## who expect the opposite convention (e.g. left-click-to-aim shooter
## muscle memory). Applied by rewriting the InputMap's mouse bindings on
## `kick_stance`/`kick_execute` — see _apply_mouse_kick_binding() — rather
## than branching in HumanBrain, so every existing
## `Input.is_action_pressed(&"kick_stance")`-style read elsewhere in the
## project keeps working unchanged regardless of which physical button is
## currently bound to which action.
var mouse_kick_swapped := false:
	set(value):
		if mouse_kick_swapped == value:
			return
		mouse_kick_swapped = value
		_apply_mouse_kick_binding()
		mouse_kick_binding_changed.emit(value)

signal camera_mode_changed(mode: FullGameCameraMode)
signal mouse_kick_binding_changed(swapped: bool)


func _ready() -> void:
	_load()
	_apply_mouse_kick_binding()


func _load() -> void:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		return   # no save file yet — defaults above stand
	full_game_camera_mode = config.get_value(SECTION, "full_game_camera_mode",
		full_game_camera_mode) as FullGameCameraMode
	mouse_kick_swapped = config.get_value(SECTION, "mouse_kick_swapped",
		mouse_kick_swapped) as bool


func save() -> void:
	var config := ConfigFile.new()
	config.set_value(SECTION, "full_game_camera_mode", full_game_camera_mode)
	config.set_value(SECTION, "mouse_kick_swapped", mouse_kick_swapped)
	config.save(SAVE_PATH)


## Removes whichever mouse button is currently on each action and puts
## the correct one back — the InputMap (not the project.godot defaults
## baked in at build time) is the live source of truth for what a click
## does from here on. Idempotent: safe to call every time either setting
## changes, or once at startup with nothing changed yet.
func _apply_mouse_kick_binding() -> void:
	var stance_button := MOUSE_BUTTON_LEFT if mouse_kick_swapped else MOUSE_BUTTON_RIGHT
	var execute_button := MOUSE_BUTTON_RIGHT if mouse_kick_swapped else MOUSE_BUTTON_LEFT
	_rebind_mouse_button(&"kick_stance", stance_button)
	_rebind_mouse_button(&"kick_execute", execute_button)


func _rebind_mouse_button(action: StringName, button_index: MouseButton) -> void:
	for event in InputMap.action_get_events(action):
		if event is InputEventMouseButton:
			InputMap.action_erase_event(action, event)
	var new_event := InputEventMouseButton.new()
	new_event.button_index = button_index
	InputMap.action_add_event(action, new_event)
