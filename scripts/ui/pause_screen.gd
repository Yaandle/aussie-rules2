class_name PauseScreen
extends CanvasLayer

## Minimal Soft Brutalist pause placeholder (design brief's pause overlay).
##
## Not yet wired into any live match scene — see the comment on `resume()`
## below. Built entirely in _ready() from SoftBrutalist, following the
## same hand-built-Control pattern as team_list_screen.gd / main_menu.gd
## rather than a .tscn-authored tree.

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

	var background := ColorRect.new()
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.color = SoftBrutalist.BACKGROUND
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(background)

	var card := Panel.new()
	card.add_theme_stylebox_override(&"panel", SoftBrutalist.panel_style())
	card.size = Vector2(CARD_WIDTH, CARD_HEIGHT)
	card.position = Vector2((1280.0 - CARD_WIDTH) / 2.0, (720.0 - CARD_HEIGHT) / 2.0)
	root.add_child(card)

	var title := SoftBrutalist.label("PAUSED", 30, SoftBrutalist.INK,
		SoftBrutalist.WEIGHT_HEAVY, SoftBrutalist.TRACK_TITLE)
	title.position = Vector2(32.0, 32.0)
	card.add_child(title)

	var top := 100.0
	for i in _rows.size():
		var row := _rows[i]
		var panel := Panel.new()
		panel.add_theme_stylebox_override(&"panel", SoftBrutalist.button_style(&"normal"))
		panel.position = Vector2(32.0, top)
		panel.size = Vector2(CARD_WIDTH - 64.0, ROW_HEIGHT)
		card.add_child(panel)
		_row_panels.append(panel)

		var label := SoftBrutalist.label(row.title, 18, SoftBrutalist.INK,
			SoftBrutalist.WEIGHT_BOLD, SoftBrutalist.TRACK_LABEL)
		label.set_anchors_preset(Control.PRESET_FULL_RECT)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		panel.add_child(label)
		_row_labels.append(label)

		top += ROW_HEIGHT + ROW_GAP

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
	elif event.is_action_pressed(&"ui_accept"):
		_select()


func _move(step: int) -> void:
	_index = (_index + step + _rows.size()) % _rows.size()
	_refresh()


func _select() -> void:
	var row := _rows[_index]
	row.action.call()


## Placeholder resume: this screen is not currently pushed as an overlay
## from any live match scene (see full_game.gd's `pause` action, which
## just swaps straight to the main menu today), so there is no "previous
## scene" to hand control back to generically. Until pause is wired as an
## in-place overlay (add_child this as a CanvasLayer child of the match
## scene, set get_tree().paused = true and this node's process_mode to
## PROCESS_MODE_ALWAYS, then have RESUME just free/hide it and unpause),
## RESUME behaves the same as QUIT and returns to the main menu.
func resume() -> void:
	if _busy:
		return
	_busy = true
	if get_tree().paused:
		get_tree().paused = false
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
		_row_panels[i].add_theme_stylebox_override(&"panel",
			SoftBrutalist.button_style(&"hover" if selected else &"normal"))
		_row_labels[i].add_theme_color_override(&"font_color", SoftBrutalist.INK)
