class_name PauseScreen
extends CanvasLayer

## Soft Brutalist pause overlay (design brief's pause overlay).
##
## Pushed as a paused in-place overlay by full_game.gd/kick_to_kick.gd's
## own `pause` handlers: instantiate, set process_mode = PROCESS_MODE_ALWAYS
## (so this node — and only this node — keeps receiving input while the
## tree is paused), add as a child of the match scene, then
## get_tree().paused = true. RESUME/`resume()` below already handles that
## exact shape. Built entirely in _ready() from SoftBrutalist, following the
## same hand-built-Control pattern as team_list_screen.gd / main_menu.gd
## rather than a .tscn-authored tree.

## Emitted right before this frees itself via the RESUME path (not the QUIT
## path, which changes scene instead) — for whoever pushed the overlay to
## restore anything it suspended going in (kick_to_kick.gd re-captures the
## mouse cursor this way, for example).
signal resumed

const CARD_WIDTH := 420.0
## Wider with the CAMERA ZOOM row: its "← / → Zoom" hint makes the bar
## under the rows longer than 420 holds.
const CARD_WIDTH_WITH_ZOOM := 520.0
const ROW_HEIGHT := 64.0
const ROW_GAP := 16.0
const HINT_HEIGHT := 28.0
const CARD_TOP_MARGIN := 100.0
const CARD_BOTTOM_MARGIN := 32.0
class Row:
	var title: String
	var action: Callable
	## Optional: left/right on the row calls this with -1 / +1, and `value`
	## gives the text shown after the title (the CAMERA ZOOM row).
	var adjust: Callable
	var value: Callable

	func _init(p_title: String, p_action: Callable, p_adjust := Callable(),
			p_value := Callable()) -> void:
		title = p_title
		action = p_action
		adjust = p_adjust
		value = p_value

	func text() -> String:
		return title if not value.is_valid() else "%s   ‹ %s ›" % [title, value.call()]


## Full Game sets this before adding the overlay: a CAMERA ZOOM row
## (playtest 2026-10-29, "ensure the zoom settings updates in game if I
## adjust it"). The match camera already follows Settings.camera_zoom live,
## but the only place to change it was the pregame screen. Kick-to-Kick
## doesn't read the zoom, so it doesn't get the row.
var show_camera_zoom := false

var _rows: Array[Row] = []
var _index := 0
var _busy := false

var _row_panels: Array[Panel] = []
var _row_labels: Array[Label] = []
var _hints: DeviceHintBar


func _ready() -> void:
	# Topmost of every CanvasLayer this project draws (DebugHud/MarkPrompt/
	# KickCrosshair/ControlledPlayerRing's own key-hint chips etc. all sit
	# at single-digit layers) — a pause overlay that something else could
	# still draw over would be a worse bug than the ring-through-pause
	# report this is also half of the fix for (ControlledPlayerRing's own
	# move to real 3D geometry is the other half).
	layer = 100
	_rows = [Row.new("RESUME", resume)]
	if show_camera_zoom:
		# Enter / a click steps it up, wrapping, for a mouse or one button.
		_rows.append(Row.new("CAMERA ZOOM", _step_zoom.bind(1, true), _step_zoom.bind(false),
			func() -> String: return "%d%%" % roundi(Settings.camera_zoom * 100.0)))
	_rows.append(Row.new("QUIT TO MENU", _quit_to_menu))
	# Derived from content (rows + the hint bar under them) rather than a
	# fixed constant, same reason settings_screen.gd/remap_screen.gd compute
	# their own card_height — a hand-picked number drifts the moment a row
	# is added or removed.
	var card_height := CARD_TOP_MARGIN + _rows.size() * (ROW_HEIGHT + ROW_GAP) + HINT_HEIGHT \
		+ CARD_BOTTOM_MARGIN

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	root.add_child(SoftBrutalist.backdrop())

	# Retro windowed-console shell (see retro_window.gd) — same sharp,
	# unrounded card language as settings_screen.gd / team_list_screen.gd.
	var card_width := CARD_WIDTH_WITH_ZOOM if show_camera_zoom else CARD_WIDTH
	var card_size := Vector2(card_width, card_height)
	var card_wrapper := Control.new()
	card_wrapper.custom_minimum_size = card_size
	card_wrapper.position = Vector2((1280.0 - card_width) / 2.0, (720.0 - card_height) / 2.0)
	root.add_child(card_wrapper)
	var card := RetroWindow.shell(card_wrapper, card_size)

	var title := SoftBrutalist.label("PAUSED", SoftBrutalist.SIZE_TITLE, RetroWindow.BORDER,
		SoftBrutalist.WEIGHT_HEAVY, SoftBrutalist.TRACK_TITLE)
	title.position = Vector2(32.0, 32.0)
	card.add_child(title)

	var top := CARD_TOP_MARGIN
	for i in _rows.size():
		var row := _rows[i]
		var panel := Panel.new()
		panel.add_theme_stylebox_override(&"panel", RetroWindow.row_style(false))
		panel.position = Vector2(32.0, top)
		panel.size = Vector2(card_width - 64.0, ROW_HEIGHT)
		card.add_child(panel)
		panel.mouse_filter = Control.MOUSE_FILTER_STOP
		panel.gui_input.connect(_on_row_gui_input.bind(i))
		panel.mouse_entered.connect(_on_row_hover.bind(i))
		_row_panels.append(panel)

		var label := SoftBrutalist.label(row.text(), SoftBrutalist.SIZE_BODY, RetroWindow.BORDER,
			SoftBrutalist.WEIGHT_BOLD, SoftBrutalist.TRACK_LABEL)
		label.set_anchors_preset(Control.PRESET_FULL_RECT)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		panel.add_child(label)
		_row_labels.append(label)

		top += ROW_HEIGHT + ROW_GAP

	# No control legend existed on this screen at all (ui_audit.md
	# finding #2) — RESUME/QUIT already had full keyboard/gamepad/mouse
	# support via the row cursor above, nothing on screen just said so.
	_hints = DeviceHintBar.new()
	_hints.position = Vector2(32.0, top + 8.0)
	card.add_child(_hints)
	_hints.set_hint_sets({
		InputManager.Device.KEYBOARD: [
			{"keys": "↑ / ↓", "label": "Select"},
		] + ([{"keys": "← / →", "label": "Zoom"}] if show_camera_zoom else []) + [
			{"keys": "Enter", "label": "Confirm"},
			{"keys": "Esc", "label": "Resume"},
		],
		InputManager.Device.GAMEPAD: [
			{"keys": "D-Pad ↕", "label": "Select"},
		] + ([{"keys": "D-Pad ↔", "label": "Zoom"}] if show_camera_zoom else []) + [
			{"keys": "A", "label": "Confirm"},
			{"keys": "Start", "label": "Resume"},
		],
	})

	_refresh()

func _on_row_gui_input(event: InputEvent, i: int) -> void:
	if _busy:
		return
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		_index = i
		_refresh()
		_select()


func _on_row_hover(i: int) -> void:
	if _busy:
		return
	_index = i
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if _busy:
		return
	if event.is_action_pressed(&"pause"):
		resume()
	elif event.is_action_pressed(&"move_forward") or event.is_action_pressed(&"ui_up"):
		_move(-1)
	elif event.is_action_pressed(&"move_back") or event.is_action_pressed(&"ui_down"):
		_move(1)
	elif event.is_action_pressed(&"move_left") or event.is_action_pressed(&"ui_left"):
		_adjust(-1)
	elif event.is_action_pressed(&"move_right") or event.is_action_pressed(&"ui_right"):
		_adjust(1)
	elif event.is_action_pressed(&"ui_accept") or event.is_action_pressed(&"confirm"):
		_select()


func _adjust(step: int) -> void:
	var row := _rows[_index]
	if row.adjust.is_valid():
		row.adjust.call(step)


## One CAM_ZOOM_STEP. `wrap` (Enter, a click) goes back to the minimum past
## the maximum; the arrows stop at either end. Saved straight away, as the
## pregame screens' zoom arrows do, so the next match starts on it too.
func _step_zoom(step: int, wrap: bool) -> void:
	var zoom := Settings.camera_zoom + step * Tuning.CAM_ZOOM_STEP
	if wrap and zoom > Tuning.CAM_ZOOM_MAX + 0.001:
		zoom = Tuning.CAM_ZOOM_MIN
	Settings.camera_zoom = zoom
	Settings.save()
	_refresh()


func _move(step: int) -> void:
	_index = (_index + step + _rows.size()) % _rows.size()
	_refresh()


func _select() -> void:
	var row := _rows[_index]
	row.action.call()


## The normal case: pushed as a paused overlay (see this file's header) —
## unpause, tell whoever pushed us, and free ourselves, handing control
## straight back to the match scene underneath exactly where it left off.
## Falls back to a menu return if this is somehow shown unpaused (e.g. a
## future non-match caller), rather than freeing into a broken state.
func resume() -> void:
	if _busy:
		return
	_busy = true
	if get_tree().paused:
		get_tree().paused = false
		resumed.emit()
		queue_free()
		return
	SceneWipe.change_scene(_quit_destination())


func _quit_to_menu() -> void:
	if _busy:
		return
	_busy = true
	get_tree().paused = false
	SceneWipe.change_scene(_quit_destination())


## QUIT TO MENU from a Career match goes back to the Dashboard, not the
## main menu — the fixture's still there to replay (quitting doesn't
## count as a loss or advance the season, see CareerProfile.record_
## result()'s own call sites). Clears GameState.career_active either
## way: we're leaving the match context regardless of destination, same
## as career_match_end_screen.gd's RETURN TO MENU already does on the
## full-time path.
func _quit_destination() -> String:
	var destination := "res://scenes/ui/career_dashboard_screen.tscn" if GameState.career_active \
		else "res://scenes/ui/main_menu.tscn"
	GameState.career_active = false
	return destination


func _refresh() -> void:
	for i in _rows.size():
		var selected := i == _index
		_row_panels[i].add_theme_stylebox_override(&"panel", RetroWindow.row_style(selected))
		_row_labels[i].add_theme_color_override(&"font_color", RetroWindow.BORDER)
		_row_labels[i].text = _rows[i].text()
