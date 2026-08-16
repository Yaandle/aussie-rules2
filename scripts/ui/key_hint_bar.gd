class_name KeyHintBar
extends HBoxContainer

## Bottom-of-screen control legend: a row of [chip] label pairs, e.g.
## `[W / S] Select   [A / D] Adjust   [Enter] Play   [Esc / C] Back`.
##
## Deliberately knows nothing about which device or which bindings it is
## describing — `set_hints()` takes plain strings, so a controller legend
## is the same call with different data. That matters because the Xbox
## bindings are being settled elsewhere; see `character_screen.gd`'s
## `_hint_sets`, which is the single place a gamepad set gets added, and
## which is already wired to `InputManager.device_changed`.

const CHIP_PAD_X := 9
const CHIP_PAD_Y := 4
const CHIP_RADIUS := 5
const CHIP_GAP := 8       ## chip to its own label
const PAIR_GAP := 26      ## one hint pair to the next


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override(&"separation", PAIR_GAP)
	alignment = BoxContainer.ALIGNMENT_BEGIN


## `hints` is an Array of {"keys": String, "label": String}.
func set_hints(hints: Array) -> void:
	for child in get_children():
		child.queue_free()
		remove_child(child)
	for hint: Dictionary in hints:
		add_child(_pair(String(hint.get("keys", "")), String(hint.get("label", ""))))


func _pair(keys: String, text: String) -> HBoxContainer:
	var pair := HBoxContainer.new()
	pair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pair.add_theme_constant_override(&"separation", CHIP_GAP)

	var chip := PanelContainer.new()
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var box := UIStyle.rounded(Color(UIStyle.PANEL_FILL, 0.55), UIStyle.CHIP_BORDER,
		1, CHIP_RADIUS)
	box.content_margin_left = CHIP_PAD_X
	box.content_margin_right = CHIP_PAD_X
	box.content_margin_top = CHIP_PAD_Y
	box.content_margin_bottom = CHIP_PAD_Y
	chip.add_theme_stylebox_override(&"panel", box)
	chip.add_child(UIStyle.label(keys, UIStyle.SIZE_HINT, UIStyle.TEXT_PRIMARY,
		UIStyle.WEIGHT_REGULAR, UIStyle.TRACK_HINT))
	pair.add_child(chip)

	var label := UIStyle.label(text, UIStyle.SIZE_HINT, UIStyle.TEXT_MUTED,
		UIStyle.WEIGHT_REGULAR, UIStyle.TRACK_HINT)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pair.add_child(label)
	return pair
