class_name RemapScreen
extends CanvasLayer

## Keyboard control-remapping screen (docs/FEATURE_AUDIT.md's control-
## remapping item). Every action already supports keyboard+gamepad+mouse
## through the InputMap (project.godot's [input] section) — this is the
## first screen that actually lets a player change one of those bindings
## rather than only reading it.
##
## Deliberately scoped to the keyboard binding on the discrete action
## buttons — not the four-way movement/camera axes (WASD/arrows), which
## need a genuinely different "press two keys to define a direction" UI
## this pass doesn't build, and not the mouse buttons
## (Settings.mouse_kick_swapped already covers those), and not gamepad
## bindings (no axis/button capture flow here yet). A bounded first
## version, same "build the piece that has a clean shape" discipline this
## project applies everywhere else, not a promise this is the whole of
## remapping.
##
## Persistence and the actual InputMap mutation live in Settings.gd
## (apply_keybind/clear_keyboard_binding/keyboard_keycode) — this screen
## is display and input-capture only, same split every other live setting
## in this project already has between its screen and Settings.

const REMAPPABLE_ACTIONS := [
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
]

const CARD_WIDTH := 680.0
const HEADER_HEIGHT := 88.0
const ROW_HEIGHT := 40.0
const ROW_GAP := 8.0
const ROWS_PER_COLUMN := 9   ## REMAPPABLE_ACTIONS.size() / 2 — two even columns
const COLUMN_WIDTH := 288.0
const COLUMN_GAP := 24.0
const HINT_HEIGHT := 32.0
const CARD_MARGIN := 32.0

var _index := 0
var _listening := false
var _busy := false

var _row_panels: Array[Panel] = []
var _key_labels: Array[Label] = []
var _hint_label: Label


func _ready() -> void:
	_build()
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if _busy:
		return
	if _listening:
		_handle_listen_input(event)
		return
	if event.is_action_pressed(&"pause") or event.is_action_pressed(&"ui_cancel"):
		_back()
	elif event.is_action_pressed(&"move_forward") or event.is_action_pressed(&"ui_up"):
		_move(-1)
	elif event.is_action_pressed(&"move_back") or event.is_action_pressed(&"ui_down"):
		_move(1)
	# Left/right step by a whole column (ROWS_PER_COLUMN) rather than one
	# row — the two columns read as parallel lists, so "next column, same
	# rough height" is the more useful jump than "one row further down".
	elif event.is_action_pressed(&"ui_left"):
		_move(-ROWS_PER_COLUMN)
	elif event.is_action_pressed(&"ui_right"):
		_move(ROWS_PER_COLUMN)
	elif event.is_action_pressed(&"ui_accept"):
		_start_listening()


func _move(step: int) -> void:
	_index = (_index + step + REMAPPABLE_ACTIONS.size()) % REMAPPABLE_ACTIONS.size()
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


## Any key ends listening — Escape always cancels without changing
## anything (the universal cancel key stays reserved; no remappable action
## can steal it), any other physical key becomes the new binding.
func _handle_listen_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	get_viewport().set_input_as_handled()
	var keycode := key_event.physical_keycode
	_listening = false
	if keycode == KEY_ESCAPE:
		_refresh()
		return
	_rebind(REMAPPABLE_ACTIONS[_index]["action"], keycode)
	_refresh()


## Conflict handling: any OTHER remappable action currently holding this
## exact key loses its keyboard binding — standard "last one wins" remap
## UX, since leaving both bound would fire the older assignment silently
## alongside the new one. Only scanned against REMAPPABLE_ACTIONS, not
## every action in the project (movement/camera/mouse are out of scope
## here — see this file's header) — a player can still bind a remappable
## action onto a movement/camera key, which is a known, accepted
## limitation, not a guarded one.
func _rebind(action: StringName, physical_keycode: int) -> void:
	for entry in REMAPPABLE_ACTIONS:
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

	var card := Panel.new()
	card.add_theme_stylebox_override(&"panel", SoftBrutalist.panel_style())
	SoftBrutalist.soften(card, SoftBrutalist.Elevation.OVERLAY)
	card.size = Vector2(CARD_WIDTH, card_height)
	card.position = Vector2((1280.0 - CARD_WIDTH) / 2.0, (720.0 - card_height) / 2.0)
	root.add_child(card)

	var title := SoftBrutalist.label("REMAP CONTROLS", SoftBrutalist.SIZE_TITLE, SoftBrutalist.INK,
		SoftBrutalist.WEIGHT_HEAVY, SoftBrutalist.TRACK_TITLE)
	title.position = Vector2(CARD_MARGIN, CARD_MARGIN)
	card.add_child(title)

	var subtitle := SoftBrutalist.label("KEYBOARD ONLY · GAMEPAD/MOUSE UNCHANGED", SoftBrutalist.SIZE_CAPTION,
		SoftBrutalist.MUTED, SoftBrutalist.WEIGHT_REGULAR, SoftBrutalist.TRACK_LABEL)
	subtitle.position = Vector2(CARD_MARGIN, CARD_MARGIN + 36.0)
	card.add_child(subtitle)

	var rows_top := CARD_MARGIN + HEADER_HEIGHT
	for i in REMAPPABLE_ACTIONS.size():
		var column := i / ROWS_PER_COLUMN
		var row_in_column := i % ROWS_PER_COLUMN
		var x := CARD_MARGIN + float(column) * (COLUMN_WIDTH + COLUMN_GAP)
		var y := rows_top + float(row_in_column) * (ROW_HEIGHT + ROW_GAP)
		_build_row(card, i, Vector2(x, y))

	_hint_label = SoftBrutalist.label("", SoftBrutalist.SIZE_CAPTION, SoftBrutalist.MUTED,
		SoftBrutalist.WEIGHT_REGULAR, SoftBrutalist.TRACK_LABEL)
	_hint_label.position = Vector2(CARD_MARGIN, card_height - CARD_MARGIN - HINT_HEIGHT + 4.0)
	card.add_child(_hint_label)


func _build_row(card: Panel, index: int, pos: Vector2) -> void:
	var panel := Panel.new()
	panel.position = pos
	panel.size = Vector2(COLUMN_WIDTH, ROW_HEIGHT)
	panel.add_theme_stylebox_override(&"panel", SoftBrutalist.button_style(&"normal"))
	SoftBrutalist.soften(panel, SoftBrutalist.Elevation.LOW, float(SoftBrutalist.RADIUS_XS))
	card.add_child(panel)
	_row_panels.append(panel)

	var label := SoftBrutalist.label(REMAPPABLE_ACTIONS[index]["label"], SoftBrutalist.SIZE_LABEL,
		SoftBrutalist.INK, SoftBrutalist.WEIGHT_BOLD, SoftBrutalist.TRACK_LABEL)
	label.position = Vector2(14.0, 11.0)
	label.size = Vector2(COLUMN_WIDTH - 100.0, 20.0)
	label.clip_text = true
	panel.add_child(label)

	var key_label := SoftBrutalist.numeric_label("", SoftBrutalist.SIZE_LABEL, SoftBrutalist.ACCENT_PRIMARY)
	key_label.position = Vector2(COLUMN_WIDTH - 84.0, 11.0)
	key_label.size = Vector2(74.0, 20.0)
	key_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	panel.add_child(key_label)
	_key_labels.append(key_label)


# ── Refresh ──────────────────────────────────────────────────────────

func _refresh() -> void:
	for i in REMAPPABLE_ACTIONS.size():
		var action: StringName = REMAPPABLE_ACTIONS[i]["action"]
		var selected := i == _index
		var listening_here := selected and _listening
		SoftBrutalist.animate_state(_row_panels[i], &"panel",
			&"hover" if (selected and not listening_here) else &"normal", 0.12,
			SoftBrutalist.RADIUS_XS)
		if listening_here:
			_key_labels[i].text = "PRESS A KEY…"
			_key_labels[i].add_theme_color_override(&"font_color", SoftBrutalist.ACCENT_PRIMARY)
		else:
			_key_labels[i].text = _key_display_name(action)
			_key_labels[i].add_theme_color_override(&"font_color", SoftBrutalist.INK)

	_hint_label.text = "ESC CANCEL · SELECTED KEY REPLACES ANY OTHER ACTION USING IT" if _listening \
		else "↑/↓ SELECT · ←/→ SWITCH COLUMN · ENTER REBIND · ESC BACK"


func _key_display_name(action: StringName) -> String:
	var keycode := Settings.keyboard_keycode(action)
	if keycode == KEY_NONE:
		return "—"
	return OS.get_keycode_string(keycode).to_upper()
