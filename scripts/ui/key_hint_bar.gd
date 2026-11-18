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
const CHIP_RADIUS := RetroWindow.RADIUS
const CHIP_GAP := 8       ## chip to its own label
const PAIR_GAP := 26      ## one hint pair to the next
const KEY_GAP := 4        ## between the chips of one multi-key hint

## Over live footage (the main menu's oval montage) rather than a cream
## panel: light keycap chips with dark letters and light labels, as in the
## menu reference image. Off everywhere else, so no other screen changes.
var on_dark := false
const DARK_CHIP_FILL := Color(0.86, 0.86, 0.84, 0.92)
const DARK_CHIP_TEXT := Color(0.12, 0.12, 0.12)
const DARK_LABEL := Color(0.97, 0.96, 0.93, 0.9)


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override(&"separation", PAIR_GAP)
	alignment = BoxContainer.ALIGNMENT_BEGIN


## `hints` is an Array of {"keys": String, "label": String}. "keys" may
## also be an Array of Strings, drawn as one chip per key ("W A S D").
func set_hints(hints: Array) -> void:
	for child in get_children():
		child.queue_free()
		remove_child(child)
	for hint: Dictionary in hints:
		var keys: Variant = hint.get("keys", "")
		var key_list: Array = keys if keys is Array else [String(keys)]
		add_child(_pair(key_list, String(hint.get("label", ""))))


func _pair(keys: Array, text: String) -> HBoxContainer:
	var pair := HBoxContainer.new()
	pair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pair.add_theme_constant_override(&"separation", CHIP_GAP)

	var chips := HBoxContainer.new()
	chips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chips.add_theme_constant_override(&"separation", KEY_GAP)
	for key: Variant in keys:
		chips.add_child(_chip(String(key)))
	pair.add_child(chips)

	var label := UIStyle.label(text, UIStyle.SIZE_HINT,
		DARK_LABEL if on_dark else Color(0.35, 0.35, 0.35),
		UIStyle.WEIGHT_REGULAR, UIStyle.TRACK_HINT)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pair.add_child(label)
	return pair


func _chip(key: String) -> PanelContainer:
	var chip := PanelContainer.new()
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# Deliberately shadowless: a legend chip is the quietest thing on the
	# screen, and eight of them each casting their own shadow along the
	# bottom edge is exactly the busy chrome the brief asks to avoid.
	var box: StyleBoxFlat
	if on_dark:
		box = UIStyle.rounded(DARK_CHIP_FILL, DARK_CHIP_FILL, 0, 2)
	else:
		box = UIStyle.rounded(Color(UIStyle.PANEL_FILL, 0.7), UIStyle.CHIP_BORDER,
			1, CHIP_RADIUS)
	box.content_margin_left = CHIP_PAD_X if key.length() > 1 else 7
	box.content_margin_right = CHIP_PAD_X if key.length() > 1 else 7
	box.content_margin_top = CHIP_PAD_Y
	box.content_margin_bottom = CHIP_PAD_Y
	chip.add_theme_stylebox_override(&"panel", box)
	chip.add_child(UIStyle.label(key, UIStyle.SIZE_HINT,
		DARK_CHIP_TEXT if on_dark else UIStyle.TEXT_PRIMARY,
		UIStyle.WEIGHT_BOLD if on_dark else UIStyle.WEIGHT_REGULAR, UIStyle.TRACK_HINT))
	return chip
