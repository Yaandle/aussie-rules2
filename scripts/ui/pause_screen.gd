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
const CARD_HEIGHT := 280.0
const ROW_HEIGHT := 64.0
const ROW_GAP := 16.0

class Row:
	var title: String
	var action: Callable

	func _init(p_title: String, p_action: Callable) -> void:
		title = p_title
		action = p_action


var _rows: Array[Row] = []
var _index := 0
var _busy := false

var _row_panels: Array[Panel] = []
var _row_labels: Array[Label] = []


func _ready() -> void:
	_rows = [
		Row.new("RESUME", resume),
		Row.new("QUIT TO MENU", _quit_to_menu),
	]

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	root.add_child(SoftBrutalist.backdrop())

	# Retro windowed-console shell (see retro_window.gd) — same sharp,
	# unrounded card language as settings_screen.gd / team_list_screen.gd.
	var card_size := Vector2(CARD_WIDTH, CARD_HEIGHT)
	var card_wrapper := Control.new()
	card_wrapper.custom_minimum_size = card_size
	card_wrapper.position = Vector2((1280.0 - CARD_WIDTH) / 2.0, (720.0 - CARD_HEIGHT) / 2.0)
	root.add_child(card_wrapper)
	var card := RetroWindow.shell(card_wrapper, card_size)

	var title := SoftBrutalist.label("PAUSED", SoftBrutalist.SIZE_TITLE, RetroWindow.BORDER,
		SoftBrutalist.WEIGHT_HEAVY, SoftBrutalist.TRACK_TITLE)
	title.position = Vector2(32.0, 32.0)
	card.add_child(title)

	var top := 100.0
	for i in _rows.size():
		var row := _rows[i]
		var panel := Panel.new()
		panel.add_theme_stylebox_override(&"panel", RetroWindow.row_style(false))
		panel.position = Vector2(32.0, top)
		panel.size = Vector2(CARD_WIDTH - 64.0, ROW_HEIGHT)
		card.add_child(panel)
		panel.mouse_filter = Control.MOUSE_FILTER_STOP
		panel.gui_input.connect(_on_row_gui_input.bind(i))
		panel.mouse_entered.connect(_on_row_hover.bind(i))
		_row_panels.append(panel)

		var label := SoftBrutalist.label(row.title, SoftBrutalist.SIZE_BODY, RetroWindow.BORDER,
			SoftBrutalist.WEIGHT_BOLD, SoftBrutalist.TRACK_LABEL)
		label.set_anchors_preset(Control.PRESET_FULL_RECT)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		panel.add_child(label)
		_row_labels.append(label)

		top += ROW_HEIGHT + ROW_GAP

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
	elif event.is_action_pressed(&"ui_accept") or event.is_action_pressed(&"confirm"):
		_select()


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
	SceneWipe.change_scene("res://scenes/ui/main_menu.tscn")


func _quit_to_menu() -> void:
	if _busy:
		return
	_busy = true
	get_tree().paused = false
	SceneWipe.change_scene("res://scenes/ui/main_menu.tscn")


func _refresh() -> void:
	for i in _rows.size():
		var selected := i == _index
		_row_panels[i].add_theme_stylebox_override(&"panel", RetroWindow.row_style(selected))
		_row_labels[i].add_theme_color_override(&"font_color", RetroWindow.BORDER)
