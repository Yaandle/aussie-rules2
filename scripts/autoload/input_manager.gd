extends Node

## Device abstraction and last-used-device tracking (design doc §4).
##
## Nothing outside this file ever branches on device type. Every action is
## a named Input Map action bound to both a keyboard key and a controller
## input, exactly as Prototype 1's controller.py aimed for with its
## synthesized-keyboard-event layer — except Godot's Input Map does the
## unification natively, so there is no synthesis layer at all.
##
## What this autoload adds on top of raw Input:
##   - radial deadzones and per-action response curves (movement and
##     camera-aim want different feel)
##   - a keyboard equivalent of an analog stick's magnitude, so the
##     "keyboard always at full parity" rule survives contact with an
##     analog-first design
##   - last-used-device tracking, so UI glyphs can swap
##   - haptics

signal device_changed(device: Device)

enum Device { KEYBOARD, GAMEPAD }

var device: Device = Device.KEYBOARD:
	set(value):
		if device == value:
			return
		device = value
		device_changed.emit(device)

## Set false while a menu owns the stick/keys. Movement and camera queries
## return zero; button queries still work so menus can read them.
var gameplay_input_enabled := true

var _mouse_look := Vector2.ZERO


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		# Stick drift would otherwise flip the device on every frame.
		if event is InputEventJoypadMotion and absf(event.axis_value) < 0.35:
			return
		device = Device.GAMEPAD
	elif event is InputEventKey or event is InputEventMouseButton:
		device = Device.KEYBOARD
	elif event is InputEventMouseMotion:
		device = Device.KEYBOARD
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			_mouse_look += event.relative * Tuning.CAM_MOUSE_SENSITIVITY


## Movement intent in camera space: x = right, y = forward.
## Deadzoned radially and shaped by MOVE_CURVE. Length is 0..1.
func get_move_vector() -> Vector2:
	if not gameplay_input_enabled:
		return Vector2.ZERO
	var raw := Input.get_vector(
		&"move_left", &"move_right", &"move_back", &"move_forward",
		Tuning.MOVE_DEADZONE)
	return _shape(raw, Tuning.MOVE_CURVE)


## Camera-look intent: x = yaw right, y = pitch up. Length is 0..1.
## Deliberately a different deadzone and a sharper curve than movement.
func get_look_vector() -> Vector2:
	if not gameplay_input_enabled:
		return Vector2.ZERO
	var raw := Input.get_vector(
		&"camera_left", &"camera_right", &"camera_down", &"camera_up",
		Tuning.LOOK_DEADZONE)
	return _shape(raw, Tuning.LOOK_CURVE)


## Accumulated mouse-look since the last call, in degrees. Drained on read
## so it cannot double-apply across frames.
func take_mouse_look() -> Vector2:
	if not gameplay_input_enabled:
		_mouse_look = Vector2.ZERO
		return Vector2.ZERO
	var v := _mouse_look
	_mouse_look = Vector2.ZERO
	return v


## How hard the player wants to run, 0..1, fed to Tuning.speed_for_gait.
##
## On a gamepad this is stick magnitude, capped at JOG_CEILING until the
## sprint trigger is held. On a keyboard the direction is digital, so the
## magnitude has to come from modifiers: Ctrl walks, nothing jogs, Shift
## sprints. Three tiers hitting exactly the same values an analog stick
## reaches — the keyboard is not a downgraded input path here, which is
## the hard requirement carried over from Prototype 1 (§11).
func get_gait() -> float:
	if not gameplay_input_enabled:
		return 0.0
	var magnitude := get_move_vector().length()
	if is_zero_approx(magnitude):
		return 0.0

	var sprinting := Input.is_action_pressed(&"sprint")
	var walking := Input.is_action_pressed(&"walk")

	# Full stick with no sprint trigger tops out at the jog ceiling;
	# holding sprint unlocks the rest. The keyboard's no-modifier case
	# reaches the same value, so neither device is the downgraded one.
	if device == Device.GAMEPAD:
		var ceiling := 1.0 if sprinting else Tuning.GAIT_JOG
		if walking:
			ceiling = minf(ceiling, Tuning.GAIT_WALK)
		return minf(magnitude, ceiling)

	if walking:
		return Tuning.GAIT_WALK
	if sprinting:
		return 1.0
	return Tuning.GAIT_JOG


func rumble(profile: Vector3) -> void:
	if device != Device.GAMEPAD:
		return
	for pad in Input.get_connected_joypads():
		Input.start_joy_vibration(pad, profile.x, profile.y, profile.z)


func device_name() -> String:
	if device == Device.GAMEPAD:
		var pads := Input.get_connected_joypads()
		if not pads.is_empty():
			return Input.get_joy_name(pads[0])
		return "Gamepad"
	return "Keyboard"


## Radial deadzone is already applied by Input.get_vector; this only
## reshapes the magnitude, leaving direction untouched.
func _shape(v: Vector2, curve: float) -> Vector2:
	var magnitude := v.length()
	if is_zero_approx(magnitude):
		return Vector2.ZERO
	return (v / magnitude) * pow(minf(magnitude, 1.0), curve)
