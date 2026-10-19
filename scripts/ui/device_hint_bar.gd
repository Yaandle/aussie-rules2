class_name DeviceHintBar
extends KeyHintBar

## KeyHintBar that remembers one hint list per InputManager.Device and
## re-shows the matching one whenever the last-used device changes.
##
## Pulled out of character_screen.gd's `_hint_sets`/`_apply_hints`/
## `_on_device_changed` (the only screen that had it) so every screen with a
## control legend gets the same device-aware behaviour instead of printing
## one combined "Enter / A" string that never actually swaps (ui_audit.md
## finding #1). Call set_hint_sets() instead of the base class's set_hints()
## directly — set_hints() still works for a one-off legend that genuinely
## is the same on every device (there is no such screen left after this
## pass, but nothing stops a future one).

var _hint_sets: Dictionary = {}


func _ready() -> void:
	InputManager.device_changed.connect(_on_device_changed)


func _exit_tree() -> void:
	if InputManager.device_changed.is_connected(_on_device_changed):
		InputManager.device_changed.disconnect(_on_device_changed)


## `hint_sets` is {InputManager.Device.KEYBOARD: [...], InputManager.Device.GAMEPAD: [...]},
## each an Array of {"keys": String, "label": String} same as KeyHintBar.set_hints().
## Keyboard is the fallback for a device with no entry of its own, same
## behaviour character_screen.gd's _apply_hints() already had.
func set_hint_sets(hint_sets: Dictionary) -> void:
	_hint_sets = hint_sets
	_apply()


func _on_device_changed(_device: int) -> void:
	_apply()


func _apply() -> void:
	var keyboard: Array = _hint_sets.get(InputManager.Device.KEYBOARD, [])
	set_hints(_hint_sets.get(InputManager.device, keyboard))
