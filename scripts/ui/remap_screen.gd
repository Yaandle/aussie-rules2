class_name RemapScreen
extends CanvasLayer

## Control-remapping screen (FEATURE_AUDIT.md (archived)'s control-
## remapping item). Every action already supports keyboard+gamepad+mouse
## through the InputMap (project.godot's [input] section); this screen
## lets a player change the keyboard key or the controller button on the
## discrete action buttons.
##
## Two tabs (6AB, playtest 2026-11-11: "keyboard and controller binds
## should be on two tabs"): KEYBOARD and CONTROLLER, switched with LB / RB
## or Tab. Each tab lists only its own device's bindings, so neither has to
## squeeze both into one row.
##
## Still out of scope: the four-way movement/camera axes (WASD/arrows,
## sticks), which need a "define a direction" UI this screen doesn't build,
## and the mouse buttons (Settings.mouse_kick_swapped covers those).
##
## The tabs differ on conflicts. KEYBOARD is "last one wins": a key on two
## actions would fire the older one silently. CONTROLLER allows sharing,
## because a pad has far fewer buttons and one button doing different
## things in different situations is how the default layout works (A marks,
## calls for the ball and confirms).
##
## Persistence and the actual InputMap mutation live in Settings.gd
## (apply_keybind/apply_joybind and their readers); this screen is display
## and input capture only.

enum Tab { KEYBOARD, CONTROLLER }

const KEYBOARD_ACTIONS := [
	{"action": &"sprint", "label": "SPRINT"},
	{"action": &"walk", "label": "WALK"},
	{"action": &"camera_recenter", "label": "CAMERA RECENTRE"},
	{"action": &"kick_stance", "label": "KICK STANCE (AIM)"},
	{"action": &"kick_execute", "label": "KICK EXECUTE"},
	{"action": &"handball", "label": "HANDBALL"},
	{"action": &"bounce", "label": "BOUNCE"},
	{"action": &"tackle", "label": "TACKLE"},
	{"action": &"mark_safe", "label": "MARK — SAFE"},
	{"action": &"mark_running", "label": "MARK — RUNNING"},
	{"action": &"mark_aggressive", "label": "MARK — AGGRESSIVE"},
	{"action": &"spoil", "label": "SPOIL"},
	{"action": &"smother", "label": "SMOTHER"},
	{"action": &"bump_stance", "label": "BUMP STANCE"},
	{"action": &"hit_out", "label": "HIT-OUT"},
	{"action": &"switch_player", "label": "SWITCH PLAYER"},
	{"action": &"pause", "label": "PAUSE"},
	{"action": &"debug_reset", "label": "RESET BALL"},
	{"action": &"fend", "label": "FEND OFF"},
	{"action": &"kick_curve", "label": "SNAP / BANANA"},
]

## PAUSE isn't here: Start is this tab's reserved cancel (the pad's Esc),
## so it can't also be a binding someone moves away and loses.
## `walk` has no pad binding by design (the stick's push is the gait), so
## SWITCH ON DEFENCE takes its slot and the two columns stay even.
const CONTROLLER_ACTIONS := [
	{"action": &"sprint", "label": "SPRINT"},
	{"action": &"camera_recenter", "label": "CAMERA RECENTRE"},
	{"action": &"kick_stance", "label": "KICK STANCE (AIM)"},
	{"action": &"kick_execute", "label": "KICK EXECUTE"},
	{"action": &"handball", "label": "HANDBALL"},
	{"action": &"bounce", "label": "BOUNCE"},
	{"action": &"tackle", "label": "TACKLE"},
	{"action": &"mark_safe", "label": "MARK — SAFE"},
	{"action": &"mark_running", "label": "MARK — RUNNING"},
	{"action": &"mark_aggressive", "label": "MARK — AGGRESSIVE"},
	{"action": &"spoil", "label": "SPOIL"},
	{"action": &"smother", "label": "SMOTHER"},
	{"action": &"bump_stance", "label": "BUMP STANCE"},
	{"action": &"hit_out", "label": "HIT-OUT"},
	{"action": &"switch_player", "label": "SWITCH PLAYER"},
	{"action": &"switch_player_defence", "label": "SWITCH ON DEFENCE"},
	{"action": &"call_for_ball", "label": "CALL FOR BALL"},
	{"action": &"debug_reset", "label": "RESET BALL"},
	{"action": &"fend", "label": "FEND OFF"},
	{"action": &"kick_curve", "label": "SNAP / BANANA"},
]

## A trigger counts as "pressed" for capture past this pull, well clear of
## resting drift.
const TRIGGER_CAPTURE := 0.6

const JOY_BUTTON_NAMES := {
	JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
	JOY_BUTTON_BACK: "VIEW", JOY_BUTTON_GUIDE: "GUIDE", JOY_BUTTON_START: "START",
	JOY_BUTTON_LEFT_STICK: "L3", JOY_BUTTON_RIGHT_STICK: "R3",
	JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB",
	JOY_BUTTON_DPAD_UP: "D-PAD ↑", JOY_BUTTON_DPAD_DOWN: "D-PAD ↓",
	JOY_BUTTON_DPAD_LEFT: "D-PAD ←", JOY_BUTTON_DPAD_RIGHT: "D-PAD →",
	JOY_BUTTON_MISC1: "SHARE",
}

const CARD_WIDTH := 680.0
const HEADER_HEIGHT := 88.0
const ROW_HEIGHT := 40.0
const ROW_GAP := 8.0
const ROWS_PER_COLUMN := 10   ## each tab's list is 20 long: two even columns
const COLUMN_WIDTH := 288.0
const COLUMN_GAP := 24.0
const HINT_HEIGHT := 32.0
const CARD_MARGIN := 32.0

var _tab := Tab.KEYBOARD
var _index := 0
var _listening := false
var _busy := false

## Per tab: the row panels and the binding labels, built once; switching
## tabs only toggles which set is visible.
var _tab_roots: Array[Control] = []
var _row_panels: Array = [[], []]
var _key_labels: Array = [[], []]
var _tab_labels: Array[Label] = []
var _hints: DeviceHintBar


func _ready() -> void:
	# Open on whichever device the player is using right now.
	if InputManager.device == InputManager.Device.GAMEPAD:
		_tab = Tab.CONTROLLER
	_build()
	_refresh()


func _actions() -> Array:
	return KEYBOARD_ACTIONS if _tab == Tab.KEYBOARD else CONTROLLER_ACTIONS


func _unhandled_input(event: InputEvent) -> void:
	if _busy:
		return
	if _listening:
		get_viewport().set_input_as_handled()
		if _tab == Tab.KEYBOARD:
			_handle_key_listen(event)
		else:
			_handle_pad_listen(event)
		return
	if _is_tab_switch(event):
		_switch_tab()
	elif event.is_action_pressed(&"pause") or event.is_action_pressed(&"ui_cancel") \
			or event.is_action_pressed(&"decline"):
		_back()
	elif event.is_action_pressed(&"move_forward") or event.is_action_pressed(&"ui_up"):
		_move(-1)
	elif event.is_action_pressed(&"move_back") or event.is_action_pressed(&"ui_down"):
		_move(1)
	# Left/right step by a whole column (ROWS_PER_COLUMN) rather than one
	# row: the two columns read as parallel lists, so "next column, same
	# rough height" is the more useful jump than "one row further down".
	elif event.is_action_pressed(&"ui_left"):
		_move(-ROWS_PER_COLUMN)
	elif event.is_action_pressed(&"ui_right"):
		_move(ROWS_PER_COLUMN)
	# `confirm` too (6AB): ui_accept alone doesn't fire for a pad's (A).
	elif event.is_action_pressed(&"ui_accept") or event.is_action_pressed(&"confirm"):
		_start_listening()


## LB / RB on a pad, Tab on a keyboard. Raw events, not actions: LB and RB
## are gameplay bindings a player may have moved, and the tab switch
## shouldn't move with them.
func _is_tab_switch(event: InputEvent) -> bool:
	if event is InputEventJoypadButton and event.is_pressed():
		var button := (event as InputEventJoypadButton).button_index
		return button == JOY_BUTTON_LEFT_SHOULDER or button == JOY_BUTTON_RIGHT_SHOULDER
	if event is InputEventKey and event.is_pressed() and not event.is_echo():
		return (event as InputEventKey).physical_keycode == KEY_TAB
	return false


func _switch_tab() -> void:
	_tab = Tab.CONTROLLER if _tab == Tab.KEYBOARD else Tab.KEYBOARD
	_index = mini(_index, _actions().size() - 1)
	_refresh()


func _move(step: int) -> void:
	var count := _actions().size()
	_index = (_index + step + count) % count
	_refresh()


func _back() -> void:
	if _busy:
		return
	_busy = true
	Settings.save()
	SceneWipe.change_scene("res://scenes/ui/settings_screen.tscn")


func _start_listening() -> void:
	_listening = true
	_refresh()


## KEYBOARD tab. Escape cancels without changing anything (the universal
## cancel key stays reserved; no remappable action can steal it), any other
## physical key becomes the new binding. Any pad button also cancels, so a
## controller player who opened listening here isn't stuck in it.
func _handle_key_listen(event: InputEvent) -> void:
	if event is InputEventJoypadButton and (event as InputEventJoypadButton).pressed:
		_listening = false
		_refresh()
		return
	if not (event is InputEventKey):
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	var keycode := key_event.physical_keycode
	_listening = false
	if keycode != KEY_ESCAPE:
		_rebind_key(_actions()[_index]["action"], keycode)
	_refresh()


## CONTROLLER tab. Start (or Esc) cancels; any other button, or a trigger
## pulled past TRIGGER_CAPTURE, becomes the binding. Stick motion is
## ignored so a resting thumb can't bind anything.
func _handle_pad_listen(event: InputEvent) -> void:
	if event is InputEventKey and event.is_pressed() \
			and (event as InputEventKey).physical_keycode == KEY_ESCAPE:
		_listening = false
		_refresh()
		return
	var code := -1
	if event is InputEventJoypadButton and (event as InputEventJoypadButton).pressed:
		var button := (event as InputEventJoypadButton).button_index
		if button == JOY_BUTTON_START:
			_listening = false
			_refresh()
			return
		code = int(button)
	elif event is InputEventJoypadMotion:
		var motion := event as InputEventJoypadMotion
		if (motion.axis == JOY_AXIS_TRIGGER_LEFT or motion.axis == JOY_AXIS_TRIGGER_RIGHT) \
				and motion.axis_value >= TRIGGER_CAPTURE:
			code = Settings.JOY_AXIS_CODE_BASE + int(motion.axis)
	if code < 0:
		return
	_listening = false
	Settings.apply_joybind(_actions()[_index]["action"], code)
	_refresh()


## Conflict handling (KEYBOARD only): any OTHER remappable action holding
## this exact key loses its keyboard binding, "last one wins", since leaving
## both bound would fire the older assignment silently alongside the new
## one. Only scanned against KEYBOARD_ACTIONS: a player can still bind one
## onto a movement/camera key, a known, accepted limitation.
func _rebind_key(action: StringName, physical_keycode: int) -> void:
	for entry in KEYBOARD_ACTIONS:
		var other: StringName = entry["action"]
		if other != action and Settings.keyboard_keycode(other) == physical_keycode:
			Settings.clear_keyboard_binding(other)
	Settings.apply_keybind(action, physical_keycode)


# ── Build ────────────────────────────────────────────────────────────

func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	root.add_child(SoftBrutalist.backdrop())

	var content_height := HEADER_HEIGHT + ROWS_PER_COLUMN * (ROW_HEIGHT + ROW_GAP) - ROW_GAP + HINT_HEIGHT
	var card_height := content_height + CARD_MARGIN * 2.0

	# Retro windowed-console shell (see retro_window.gd), same sharp,
	# unrounded card language as settings_screen.gd / pause_screen.gd /
	# team_list_screen.gd.
	var card_size := Vector2(CARD_WIDTH, card_height)
	var card_wrapper := Control.new()
	card_wrapper.custom_minimum_size = card_size
	card_wrapper.position = Vector2((1280.0 - CARD_WIDTH) / 2.0, (720.0 - card_height) / 2.0)
	root.add_child(card_wrapper)
	var card := RetroWindow.shell(card_wrapper, card_size)

	var title := SoftBrutalist.label("REMAP CONTROLS", SoftBrutalist.SIZE_TITLE, RetroWindow.BORDER,
		SoftBrutalist.WEIGHT_HEAVY, SoftBrutalist.TRACK_TITLE)
	title.position = Vector2(CARD_MARGIN, CARD_MARGIN)
	card.add_child(title)

	# The two tab names sit where the old "KEYBOARD ONLY" subtitle was; the
	# active one is in the accent colour (see _refresh).
	var tab_x := CARD_MARGIN
	for tab_name in ["KEYBOARD", "CONTROLLER"]:
		var tab_label := SoftBrutalist.label(tab_name, SoftBrutalist.SIZE_LABEL,
			SoftBrutalist.MUTED, SoftBrutalist.WEIGHT_BOLD, SoftBrutalist.TRACK_LABEL)
		tab_label.position = Vector2(tab_x, CARD_MARGIN + 36.0)
		card.add_child(tab_label)
		_tab_labels.append(tab_label)
		tab_x += 150.0

	var rows_top := CARD_MARGIN + HEADER_HEIGHT
	for tab in [Tab.KEYBOARD, Tab.CONTROLLER]:
		var tab_root := Control.new()
		tab_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(tab_root)
		_tab_roots.append(tab_root)
		var actions: Array = KEYBOARD_ACTIONS if tab == Tab.KEYBOARD else CONTROLLER_ACTIONS
		for i in actions.size():
			var column := i / ROWS_PER_COLUMN
			var row_in_column := i % ROWS_PER_COLUMN
			var x := CARD_MARGIN + float(column) * (COLUMN_WIDTH + COLUMN_GAP)
			var y := rows_top + float(row_in_column) * (ROW_HEIGHT + ROW_GAP)
			_build_row(tab_root, tab, actions[i]["label"], Vector2(x, y))

	_hints = DeviceHintBar.new()
	_hints.position = Vector2(CARD_MARGIN, card_height - CARD_MARGIN - HINT_HEIGHT + 4.0)
	card.add_child(_hints)


func _build_row(parent: Control, tab: int, text: String, pos: Vector2) -> void:
	var panel := Panel.new()
	panel.position = pos
	panel.size = Vector2(COLUMN_WIDTH, ROW_HEIGHT)
	panel.add_theme_stylebox_override(&"panel", RetroWindow.row_style(false))
	parent.add_child(panel)
	(_row_panels[tab] as Array).append(panel)

	var label := SoftBrutalist.label(text, SoftBrutalist.SIZE_LABEL,
		RetroWindow.BORDER, SoftBrutalist.WEIGHT_BOLD, SoftBrutalist.TRACK_LABEL)
	label.position = Vector2(14.0, 11.0)
	label.size = Vector2(COLUMN_WIDTH - 110.0, 20.0)
	label.clip_text = true
	panel.add_child(label)

	var key_label := SoftBrutalist.numeric_label("", SoftBrutalist.SIZE_LABEL, RetroWindow.ACCENT)
	key_label.position = Vector2(COLUMN_WIDTH - 104.0, 11.0)
	key_label.size = Vector2(94.0, 20.0)
	key_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	panel.add_child(key_label)
	(_key_labels[tab] as Array).append(key_label)


# ── Refresh ──────────────────────────────────────────────────────────

func _refresh() -> void:
	for tab in [Tab.KEYBOARD, Tab.CONTROLLER]:
		_tab_roots[tab].visible = tab == _tab
		_tab_labels[tab].add_theme_color_override(&"font_color",
			RetroWindow.ACCENT if tab == _tab else SoftBrutalist.MUTED)

	var actions := _actions()
	var panels: Array = _row_panels[_tab]
	var labels: Array = _key_labels[_tab]
	for i in actions.size():
		var action: StringName = actions[i]["action"]
		var selected := i == _index
		var listening_here := selected and _listening
		(panels[i] as Panel).add_theme_stylebox_override(&"panel",
			RetroWindow.row_style(selected and not listening_here))
		var key_label := labels[i] as Label
		if listening_here:
			key_label.text = "PRESS A KEY…" if _tab == Tab.KEYBOARD else "PRESS…"
			key_label.add_theme_color_override(&"font_color", RetroWindow.ACCENT)
		else:
			key_label.text = _key_display_name(action) if _tab == Tab.KEYBOARD \
				else _pad_display_name(action)
			key_label.add_theme_color_override(&"font_color", RetroWindow.BORDER)

	if _listening and _tab == Tab.KEYBOARD:
		_hints.set_hint_sets({
			InputManager.Device.KEYBOARD: [
				{"keys": "Any key", "label": "Set binding"},
				{"keys": "Esc", "label": "Cancel"},
			],
			InputManager.Device.GAMEPAD: [
				{"keys": "—", "label": "Needs a keyboard to set a key"},
				{"keys": "Any button", "label": "Cancel"},
			],
		})
	elif _listening:
		_hints.set_hint_sets({
			InputManager.Device.KEYBOARD: [
				{"keys": "—", "label": "Press a controller button or trigger"},
				{"keys": "Esc", "label": "Cancel"},
			],
			InputManager.Device.GAMEPAD: [
				{"keys": "Any button / trigger", "label": "Set binding"},
				{"keys": "Start", "label": "Cancel"},
			],
		})
	else:
		_hints.set_hint_sets({
			InputManager.Device.KEYBOARD: [
				{"keys": "Tab", "label": "Keyboard / Controller"},
				{"keys": "↑ / ↓", "label": "Select"},
				{"keys": "Enter", "label": "Rebind"},
				{"keys": "Esc", "label": "Back"},
			],
			InputManager.Device.GAMEPAD: [
				{"keys": "LB / RB", "label": "Keyboard / Controller"},
				{"keys": "D-Pad", "label": "Select"},
				{"keys": "A", "label": "Rebind"},
				{"keys": "B", "label": "Back"},
			],
		})


func _key_display_name(action: StringName) -> String:
	var keycode := Settings.keyboard_keycode(action)
	if keycode == KEY_NONE:
		return "—"
	return OS.get_keycode_string(keycode).to_upper()


func _pad_display_name(action: StringName) -> String:
	var code := Settings.joypad_code(action)
	if code < 0:
		return "—"
	if code >= Settings.JOY_AXIS_CODE_BASE:
		return "LT" if code - Settings.JOY_AXIS_CODE_BASE == JOY_AXIS_TRIGGER_LEFT else "RT"
	return JOY_BUTTON_NAMES.get(code, "BTN %d" % code)
