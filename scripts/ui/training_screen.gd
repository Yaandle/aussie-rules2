class_name TrainingScreen
extends Node3D

## Training: where the main menu's KICK TO KICK card goes. The open field
## with the coaches (kick_to_kick.tscn) is the first entry; under it, the
## drills (DrillLibrary).
##
## Playtest 2026-10-30: "take the real-life training structure I'll run and
## replicate it in-game ... think of it like the animation viewer but as a
## tutorial page — a menu where we show the player being simulated." So
## it's built like the animation viewer: a list down the left, the thing
## itself running live on the right. Pick a drill and its cones go down on
## the oval and bots run it on loop (DrillRunner), the step being run lit
## up in the list. Enter plays it: you take the PLAY AS role (← / → to
## change it) with the chase camera, and the bots run the rest of it round
## you. Esc stops and goes back to watching.
##
## The chrome is StudioStyle, the same as HUD Style.

const FIELD_SCENE := preload("res://scenes/field/field.tscn")
const BALL_SCENE := preload("res://scenes/ball/ball.tscn")
const CAMERA_SCENE := preload("res://scenes/camera/broadcast_camera.tscn")
const ENVIRONMENT := preload("res://materials/broadcast_environment.tres")
const OPEN_FIELD_SCENE := "res://scenes/modes/kick_to_kick.tscn"
const MENU_SCENE := "res://scenes/ui/main_menu.tscn"

const COLUMN_WIDTH := 380.0
const ENTRY_HEIGHT := 46.0
## The watching camera's slow orbit round the drill.
const ORBIT_RADIUS := 36.0
const ORBIT_HEIGHT := 21.0
const ORBIT_SPEED := 0.06   ## rad/s
## Where on the field the drills are run: off centre, clear of the centre
## square's markings.
const DRILL_ORIGIN := Vector3(0.0, 0.0, 0.0)

const OPEN_FIELD := {
	"name": "Open field",
	"summary": "Free roam on the oval with the three coaches: kicking, marking and tackling, each a step-by-step tutorial. Walk up to one and press Talk.",
}

var _entries: Array[Dictionary] = []
var _index := 0
var _play_roles: Array[int] = []
var _playing := false
var _busy := false

var _field: Field
var _ball: Ball
var _preview_camera: Camera3D
var _chase: BroadcastCamera
var _runner: DrillRunner
var _orbit := 0.0

var _column: Control
var _header: Control
var _entry_panels: Array[Panel] = []
var _entry_labels: Array[Label] = []
var _summary: Label
var _role_row: Control
var _role_label: Label
var _steps_box: VBoxContainer
var _step_labels: Array[Label] = []
var _status_chip: Panel
var _status_label: Label
var _play_card: Panel
var _play_title: Label
var _play_body: Label
var _play_margin: MarginContainer


func _ready() -> void:
	GameState.mode = GameState.Mode.KICK_TO_KICK
	GameState.phase = GameState.Phase.PLAY
	_entries.append(OPEN_FIELD)
	_play_roles.append(-1)
	for drill in DrillLibrary.DRILLS:
		_entries.append(drill)
		_play_roles.append(int(drill.get("play_role", 0)))
	_build_world()
	_build_ui()
	_select(0)


func _exit_tree() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _process(delta: float) -> void:
	if _playing:
		return
	_orbit += ORBIT_SPEED * delta
	var centre := DRILL_ORIGIN + Vector3(8.0, 0.0, 0.0)
	_preview_camera.global_position = centre + Vector3(cos(_orbit) * ORBIT_RADIUS, ORBIT_HEIGHT,
		sin(_orbit) * ORBIT_RADIUS)
	_preview_camera.look_at(centre + Vector3.UP * 1.0)


func _unhandled_input(event: InputEvent) -> void:
	if _busy:
		return
	if _playing:
		if event.is_action_pressed(&"pause") or event.is_action_pressed(&"ui_cancel"):
			_stop_playing()
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"pause") or event.is_action_pressed(&"ui_cancel") \
			or event.is_action_pressed(&"decline"):
		_leave(MENU_SCENE)
	elif event.is_action_pressed(&"ui_up") or event.is_action_pressed(&"move_forward"):
		_select(_index - 1)
	elif event.is_action_pressed(&"ui_down") or event.is_action_pressed(&"move_back"):
		_select(_index + 1)
	elif event.is_action_pressed(&"ui_left") or event.is_action_pressed(&"move_left"):
		_cycle_role(-1)
	elif event.is_action_pressed(&"ui_right") or event.is_action_pressed(&"move_right"):
		_cycle_role(1)
	elif event.is_action_pressed(&"ui_accept") or event.is_action_pressed(&"confirm"):
		if _index == 0:
			_leave(OPEN_FIELD_SCENE)
		else:
			_start_playing()
	else:
		return
	get_viewport().set_input_as_handled()


func _leave(scene: String) -> void:
	_busy = true
	_runner.stop()
	SceneWipe.change_scene(scene)


# ── Watching and playing ────────────────────────────────────────────

func _select(index: int) -> void:
	_index = posmod(index, _entries.size())
	# The step list first: starting the drill lights its first step.
	_refresh()
	_watch()


func _watch() -> void:
	_playing = false
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_preview_camera.make_current()
	if _index == 0:
		_runner.stop()
		_ball.reset_at(DRILL_ORIGIN + Vector3.UP * 0.3)
	else:
		_runner.start(_entries[_index])
	_column.visible = true
	_header.visible = true
	_play_card.visible = false
	_status_label.text = "OPEN FIELD" if _index == 0 else "SIMULATING"
	_status_chip.size = _status_label.get_combined_minimum_size() + Vector2(20.0, 10.0)


func _start_playing() -> void:
	_runner.start(_entries[_index], _play_roles[_index])
	var me := _runner.human()
	if me == null:
		return
	_playing = true
	_chase.target = me
	_chase.ball = _ball
	_chase.recenter()
	_chase.camera().make_current()
	me.camera = _chase.camera()
	me.camera_rig = _chase
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_column.visible = false
	_header.visible = false
	_play_card.visible = true
	var roles: Array = _entries[_index].roles
	_play_title.text = "%s  ·  you're %s" % [_entries[_index].name, roles[_play_roles[_index]].name]
	_status_label.text = "PLAYING"
	_status_chip.size = _status_label.get_combined_minimum_size() + Vector2(20.0, 10.0)


func _stop_playing() -> void:
	_refresh()
	_watch()


func _cycle_role(step: int) -> void:
	if _index == 0:
		return
	var roles: Array = _entries[_index].roles
	_play_roles[_index] = posmod(_play_roles[_index] + step, roles.size())
	_refresh()


func _on_beat_changed(index: int, text: String) -> void:
	for i in _step_labels.size():
		var lit := i == index
		_step_labels[i].add_theme_color_override(&"font_color",
			StudioStyle.INK if lit else StudioStyle.INK_SOFT)
		(_step_labels[i].get_parent() as Panel).add_theme_stylebox_override(&"panel",
			StudioStyle.box(StudioStyle.LIME if lit else StudioStyle.PAPER, 2 if lit else 0, 0))
	if _play_body != null:
		_play_body.text = text
		_play_card.size = _play_margin.get_combined_minimum_size()


# ── Building ─────────────────────────────────────────────────────────

func _build_world() -> void:
	var environment := WorldEnvironment.new()
	environment.environment = ENVIRONMENT
	add_child(environment)
	var sun := DirectionalLight3D.new()
	# kick_to_kick.tscn's Sun, so the two light the oval the same.
	sun.transform = Transform3D(Basis(Vector3(0.8637, -0.3627, 0.3499), Vector3(0.0, 0.6943, 0.7197),
		Vector3(-0.5039, -0.6216, 0.5998)), Vector3(0.0, 40.0, 0.0))
	sun.light_energy = 1.05
	sun.shadow_enabled = true
	sun.shadow_opacity = 0.72
	sun.directional_shadow_max_distance = 120.0
	add_child(sun)

	_field = FIELD_SCENE.instantiate() as Field
	_field.follow_field_style = true
	add_child(_field)
	_ball = BALL_SCENE.instantiate() as Ball
	add_child(_ball)

	_preview_camera = Camera3D.new()
	_preview_camera.fov = 50.0
	add_child(_preview_camera)
	_chase = CAMERA_SCENE.instantiate() as BroadcastCamera
	add_child(_chase)

	_runner = DrillRunner.new()
	_runner.ball = _ball
	_runner.origin = DRILL_ORIGIN
	_runner.human_camera = _chase.camera()
	_runner.human_camera_rig = _chase
	add_child(_runner)
	_runner.beat_changed.connect(_on_beat_changed)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)

	var hints := DeviceHintBar.new()
	hints.alignment = BoxContainer.ALIGNMENT_END
	_header = StudioStyle.header(root, "Training", "Kick to kick", hints)
	hints.set_hint_sets({
		InputManager.Device.KEYBOARD: [
			{"keys": "↑ / ↓", "label": "Select"},
			{"keys": "← / →", "label": "Role"},
			{"keys": "Enter", "label": "Play"},
			{"keys": "Esc", "label": "Back"},
		],
		InputManager.Device.GAMEPAD: [
			{"keys": "D-Pad ↕", "label": "Select"},
			{"keys": "D-Pad ↔", "label": "Role"},
			{"keys": "A", "label": "Play"},
			{"keys": "B", "label": "Back"},
		],
	})

	var column := Panel.new()
	column.add_theme_stylebox_override(&"panel", StudioStyle.bar(StudioStyle.PAPER, true))
	column.position = Vector2(0.0, StudioStyle.HEADER_HEIGHT)
	column.size = Vector2(COLUMN_WIDTH, 720.0 - StudioStyle.HEADER_HEIGHT)
	root.add_child(column)
	_column = column

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.offset_right = -StudioStyle.BORDER
	for side in [&"margin_left", &"margin_right", &"margin_top", &"margin_bottom"]:
		margin.add_theme_constant_override(side, 16)
	column.add_child(margin)
	var list := VBoxContainer.new()
	list.add_theme_constant_override(&"separation", 8)
	margin.add_child(list)

	_section(list, "SESSIONS")
	for i in _entries.size():
		var panel := Panel.new()
		panel.custom_minimum_size = Vector2(0.0, ENTRY_HEIGHT)
		panel.mouse_filter = Control.MOUSE_FILTER_STOP
		panel.gui_input.connect(_on_entry_input.bind(i))
		var label := StudioStyle.text(String(_entries[i].name), 14, StudioStyle.INK, StudioStyle.body_font())
		label.position = Vector2(12.0, 12.0)
		panel.add_child(label)
		list.add_child(panel)
		_entry_panels.append(panel)
		_entry_labels.append(label)

	_section(list, "ABOUT")
	_summary = StudioStyle.text("", 12, StudioStyle.INK, StudioStyle.body_font())
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_summary.custom_minimum_size.x = COLUMN_WIDTH - 40.0
	list.add_child(_summary)

	_role_row = VBoxContainer.new()
	list.add_child(_role_row)
	_section(_role_row, "PLAY AS")
	_role_label = StudioStyle.text("", 13, StudioStyle.INK, StudioStyle.mono_font())
	_role_row.add_child(_role_label)

	_steps_box = VBoxContainer.new()
	_steps_box.add_theme_constant_override(&"separation", 4)
	list.add_child(_steps_box)

	# The 3D view's status chip, top-left of the field.
	_status_chip = Panel.new()
	_status_chip.add_theme_stylebox_override(&"panel", StudioStyle.box(StudioStyle.LIME, 2, StudioStyle.SHADOW))
	_status_chip.position = Vector2(COLUMN_WIDTH + 20.0, StudioStyle.HEADER_HEIGHT + 18.0)
	root.add_child(_status_chip)
	_status_label = StudioStyle.text("SIMULATING", 11, StudioStyle.INK, StudioStyle.mono_font())
	_status_label.position = Vector2(10.0, 5.0)
	_status_chip.add_child(_status_label)

	# Playing: the drill and the step being run, top-left over the game.
	_play_card = Panel.new()
	_play_card.add_theme_stylebox_override(&"panel", StudioStyle.box(StudioStyle.WHITE, StudioStyle.BORDER, StudioStyle.SHADOW))
	_play_card.position = Vector2(16.0, 16.0)
	_play_card.visible = false
	root.add_child(_play_card)
	var play_margin := MarginContainer.new()
	_play_margin = play_margin
	for side in [&"margin_left", &"margin_right", &"margin_top", &"margin_bottom"]:
		play_margin.add_theme_constant_override(side, 12)
	_play_card.add_child(play_margin)
	var play_column := VBoxContainer.new()
	play_margin.add_child(play_column)
	_play_title = StudioStyle.text("", 14, StudioStyle.INK, StudioStyle.display_font())
	play_column.add_child(_play_title)
	_play_body = StudioStyle.text("", 13, StudioStyle.INK, StudioStyle.body_font())
	_play_body.custom_minimum_size.x = 380.0
	_play_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	play_column.add_child(_play_body)
	play_column.add_child(StudioStyle.text("Esc / Menu  stop", 11, StudioStyle.INK_SOFT, StudioStyle.mono_font()))
	_play_card.size = play_margin.get_combined_minimum_size()


func _section(parent: Control, title: String) -> void:
	var head := StudioStyle.text(title, 11, StudioStyle.INK_SOFT, StudioStyle.mono_font())
	head.custom_minimum_size.y = 22.0
	head.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	parent.add_child(head)
	var rule := ColorRect.new()
	rule.color = StudioStyle.INK
	rule.custom_minimum_size = Vector2(0.0, 2.0)
	parent.add_child(rule)


func _refresh() -> void:
	for i in _entry_panels.size():
		var picked := i == _index
		_entry_panels[i].add_theme_stylebox_override(&"panel",
			StudioStyle.box(StudioStyle.INK if picked else StudioStyle.WHITE, StudioStyle.BORDER,
				StudioStyle.SHADOW if picked else 0))
		_entry_labels[i].add_theme_color_override(&"font_color", StudioStyle.LIME if picked else StudioStyle.INK)
	var entry := _entries[_index]
	_summary.text = String(entry.summary)
	_role_row.visible = _index != 0
	for child in _steps_box.get_children():
		child.queue_free()
	_step_labels.clear()
	if _index == 0:
		return
	var roles: Array = entry.roles
	_role_label.text = "‹  %s  ›" % roles[_play_roles[_index]].name
	_section(_steps_box, "STEPS")
	var beats: Array = entry.beats
	for i in beats.size():
		var row := Panel.new()
		row.custom_minimum_size = Vector2(0.0, 30.0)
		var label := StudioStyle.text("%d  %s" % [i + 1, beats[i].text], 12, StudioStyle.INK_SOFT,
			StudioStyle.body_font())
		label.position = Vector2(8.0, 6.0)
		label.clip_text = true
		label.size = Vector2(COLUMN_WIDTH - 56.0, 20.0)
		row.add_child(label)
		row.add_theme_stylebox_override(&"panel", StudioStyle.box(StudioStyle.PAPER, 0, 0))
		_steps_box.add_child(row)
		_step_labels.append(label)


func _on_entry_input(event: InputEvent, index: int) -> void:
	var click := event as InputEventMouseButton
	if click == null or not click.pressed or click.button_index != MOUSE_BUTTON_LEFT:
		return
	if click.double_click:
		if index == 0:
			_leave(OPEN_FIELD_SCENE)
		else:
			_index = index
			_start_playing()
		return
	_select(index)
