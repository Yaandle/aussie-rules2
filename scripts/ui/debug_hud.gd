class_name DebugHud
extends CanvasLayer

## Numbers on screen, because "does this feel weighty?" is not a question
## you can answer by eye alone.
##
## Speed in real m/s against the named gaits, the live blend-space
## coordinate, the current animation state and action, the carry distance
## against AFL's 15m bounce rule, the last tackle's numbers off the tackle
## model, and the match and ball state. If the blend position is not
## moving when the player turns hard, the strafe axis is not being fed —
## that is the kind of thing this exists to catch.
##
## F3 / D-pad up steps through three pages: LIVE (the readouts above),
## CONTROLS, and off. Rebuilt 2026-10-30 (playtest: "the dev F3 screen is
## very outdated"). The old CONTROLS table was typed in by hand and had
## drifted from project.godot (Smother on J, Set Shot on X, Tackle as one
## row...). It's now read live off the InputMap every time the page opens,
## so it always shows the real bindings, a player's remaps included, and
## can't go stale again. Only the row labels and grouping are written here.
##
## The always-on Reset Ball chip in the bottom-right is gone (same
## playtest: "hide the button that shows up in the bottom-right"). R / Back
## still resets the ball in practice; it's listed on the CONTROLS page.
## The Set Shot for Goal chip stays: it only shows while one is on.

enum Page { LIVE, CONTROLS, OFF }

const BAR_WIDTH := 14
const COL_ACTION := 24
const COL_KEY := 22
const HEADER_WIDTH := 64

## Rows of the CONTROLS page: [label, action, action...]. Several actions
## on one row are shown joined ("W/A/S/D"). Several rows deliberately share
## one physical button (X: handball, running mark and the lunge; B: bounce
## and tackle) — this project's "ball state + player state decides, not
## just the button" design (see player_controller.gd's Marking header), so
## they're grouped to read that way rather than hidden.
const CONTROL_GROUPS := [
	["MOVE", [
		["Move", &"move_forward", &"move_left", &"move_back", &"move_right"],
		["Sprint / walk", &"sprint", &"walk"],
		["Camera", &"camera_left", &"camera_right", &"camera_up", &"camera_down"],
		["Camera recentre", &"camera_recenter"],
	]],
	["WITH THE BALL", [
		["Kick stance (hold) / kick", &"kick_stance", &"kick_execute"],
		["Handball", &"handball"],
		["Bounce", &"bounce"],
		["Set shot for goal", &"goal_set_shot"],
	]],
	["MARKING", [
		["Safe mark / pick up", &"mark_safe"],
		["Running mark", &"mark_running"],
		["Aggressive mark (leap)", &"mark_aggressive"],
		["Spoil", &"spoil"],
		["Call for the ball", &"call_for_ball"],
	]],
	["CONTEST", [
		["Tackle: slide / sling, bump", &"tackle"],
		["Lunge tackle (wrap)", &"lunge_tackle"],
		["Bump stance (+ flick)", &"bump_stance"],
		["Fend off (with the ball)", &"fend"],
		["Fist away (mark contest)", &"hit_out"],
		["Smother / ruck hit-out", &"smother", &"hit_out"],
	]],
	["MATCH", [
		["Switch player", &"switch_player"],
		["Switch on defence (tap)", &"switch_player_defence"],
		["Command teammate", &"issue_command"],
		["Team menu", &"team_menu"],
		["Show opposition", &"toggle_opposition"],
		["Control scheme", &"toggle_control_scheme"],
		["Talk / confirm / back", &"interact", &"confirm", &"decline"],
		["Pause", &"pause"],
	]],
	["DEV", [
		["Reset ball (practice)", &"debug_reset"],
		["Character menu", &"character_menu"],
		["This HUD (cycle page)", &"debug_hud"],
	]],
]

## Xbox names for Godot's joypad buttons (SDL order) and axes.
const PAD_BUTTONS := {
	JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
	JOY_BUTTON_BACK: "View", JOY_BUTTON_GUIDE: "Guide", JOY_BUTTON_START: "Menu",
	JOY_BUTTON_LEFT_STICK: "L3", JOY_BUTTON_RIGHT_STICK: "R3",
	JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB",
	JOY_BUTTON_DPAD_UP: "D-Up", JOY_BUTTON_DPAD_DOWN: "D-Down",
	JOY_BUTTON_DPAD_LEFT: "D-Left", JOY_BUTTON_DPAD_RIGHT: "D-Right",
}
const PAD_AXES := {
	JOY_AXIS_LEFT_X: "LS", JOY_AXIS_LEFT_Y: "LS", JOY_AXIS_RIGHT_X: "RS", JOY_AXIS_RIGHT_Y: "RS",
	JOY_AXIS_TRIGGER_LEFT: "LT", JOY_AXIS_TRIGGER_RIGHT: "RT",
}

## Where the Set Shot chip sits — bottom-right, clear of _panel's top-left
## box, of the centred crosshair/mark-prompt overlays and of the
## Scoreboard card in the bottom-left. Its right edge is pinned this far in
## from the screen's right and bottom edges (px at the 1280x720 base), and
## it grows leftward, so a longer label never runs off the screen. Only
## visible while PlayerController.can_take_goal_set_shot() is true for the
## controlled player and they aren't already mid-kick.
const HINT_EDGE_MARGIN := 16.0
const PANEL_PAD := Vector2(8.0, 8.0)

var player: PlayerController
var ball: Ball

var _page := Page.LIVE
var _controls_text := ""
var _goal_shot_hint_sets := {}
var _goal_shot_hint: KeyHintBar

@onready var _panel: Panel = $Panel
@onready var _label: Label = $Label


func _ready() -> void:
	## Single card panel behind the text block (see soft_brutalist.gd) —
	## this is a debug overlay, not a screen. Translucent and faint (0.14)
	## so it reads as an overlay over a bright field, not a card on it.
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := SoftBrutalist.panel_style(Color(SoftBrutalist.PANEL, 0.14),
		SoftBrutalist.RADIUS_MD, Color(SoftBrutalist.LINE, 0.45))
	_panel.add_theme_stylebox_override(&"panel", style)
	# Genuinely fixed-pitch, not just tabular figures: every line below is
	# printf-padded into columns and some draw ASCII bars.
	_label.add_theme_font_override(&"font", SoftBrutalist.monospace_font())
	_label.add_theme_font_size_override(&"font_size", 13)
	_label.add_theme_color_override(&"font_color", SoftBrutalist.INK)
	# A light outline keeps the dark text legible over grass/sky/players
	# through the faint panel.
	_label.add_theme_color_override(&"font_outline_color", Color(SoftBrutalist.PANEL, 0.9))
	_label.add_theme_constant_override(&"outline_size", 3)

	_goal_shot_hint_sets = {
		InputManager.Device.KEYBOARD: [{"keys": _keys_for(&"goal_set_shot", false), "label": "Set Shot for Goal"}],
		InputManager.Device.GAMEPAD: [{"keys": _keys_for(&"goal_set_shot", true), "label": "Set Shot for Goal"}],
	}
	_goal_shot_hint = KeyHintBar.new()
	_goal_shot_hint.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_goal_shot_hint.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_goal_shot_hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_goal_shot_hint.alignment = BoxContainer.ALIGNMENT_END
	_goal_shot_hint.offset_left = -HINT_EDGE_MARGIN
	_goal_shot_hint.offset_right = -HINT_EDGE_MARGIN
	_goal_shot_hint.offset_top = -HINT_EDGE_MARGIN
	_goal_shot_hint.offset_bottom = -HINT_EDGE_MARGIN
	_goal_shot_hint.visible = false
	add_child(_goal_shot_hint)
	_apply_goal_shot_hint()
	InputManager.device_changed.connect(func(_device: int) -> void: _apply_goal_shot_hint())
	_show_page()


func _process(_delta: float) -> void:
	_goal_shot_hint.visible = is_instance_valid(player) and player.is_carrying() \
		and not player.is_kick_aiming() and player.can_take_goal_set_shot()
	if Input.is_action_just_pressed(&"debug_hud"):
		_page = ((_page + 1) % Page.size()) as Page
		_show_page()
	if _page == Page.LIVE:
		_set_text(_compose_live())


func _show_page() -> void:
	_panel.visible = _page != Page.OFF
	_label.visible = _page != Page.OFF
	if _page == Page.CONTROLS:
		# Read now, not cached at _ready: a remap made since shows up.
		_controls_text = "\n".join(_controls_lines())
		_set_text(_controls_text)


## The panel takes the text's size, so a long page never spills past it.
func _set_text(text: String) -> void:
	_label.text = text
	_label.size = _label.get_combined_minimum_size()
	_panel.size = _label.size + PANEL_PAD * 2.0


func _apply_goal_shot_hint() -> void:
	var keyboard: Array = _goal_shot_hint_sets[InputManager.Device.KEYBOARD]
	_goal_shot_hint.set_hints(_goal_shot_hint_sets.get(InputManager.device, keyboard))


# ── LIVE page ────────────────────────────────────────────────────────

func _compose_live() -> String:
	var lines: Array[String] = []
	lines.append(_header("STATUS"))
	lines.append("%3d fps   input %s   pad btn %-4s axis %s" % [
		Engine.get_frames_per_second(), InputManager.device_name(),
		InputManager.last_joy_button_debug(), InputManager.last_joy_axis_debug()])
	lines.append("mode %s / %s   camera %s   field %s" % [
		GameState.mode_name(), GameState.phase_name(),
		Settings.FullGameCameraMode.keys()[Settings.full_game_camera_mode],
		Settings.FieldStyle.keys()[Settings.field_style]])
	if GameState.mode == GameState.Mode.FULL_GAME:
		var clock := maxi(int(ceil(MatchState.seconds_remaining)), 0)
		lines.append("Q%d %02d:%02d   HOME %d.%d.%d  v  AWAY %d.%d.%d" % [
			MatchState.quarter, clock / 60, clock % 60,
			MatchState.goals[Tuning.Team.HOME], MatchState.behinds[Tuning.Team.HOME],
			MatchState.points(Tuning.Team.HOME),
			MatchState.goals[Tuning.Team.AWAY], MatchState.behinds[Tuning.Team.AWAY],
			MatchState.points(Tuning.Team.AWAY)])

	if is_instance_valid(player):
		lines.append("")
		lines.append(_header("PLAYER"))
		var speed := player.speed()
		var tag := "  BACKPEDAL" if player.is_backpedaling() else ""
		lines.append("speed   %5.2f m/s  %s  %s%s" % [
			speed, _gait_label(speed), _bar(speed / Tuning.SPRINT_SPEED), tag])
		var blend := player.locomotion_blend()
		lines.append("blend   strafe %+0.2f   forward %+0.2f" % [blend.x, blend.y])
		lines.append("anim    %s   action %s%s" % [player.animation_state(),
			Tuning.Action.keys()[player.current_action()],
			"   RAGDOLL" if player.is_ragdolled() else ""])
		lines.append("charge  %s %0.2f" % [_bar(player.kick_charge()), player.kick_charge()])
		var mark_bits: Array[String] = []
		if player.is_mark_readying():
			mark_bits.append("READYING")
		if player.is_protected():
			mark_bits.append("PROTECTED %0.1fs" % player.protected_seconds())
		if player.is_standing_the_mark():
			mark_bits.append("STANDING THE MARK")
		if player.is_ruck_contestant():
			mark_bits.append("RUCK CONTEST")
		lines.append("mark    %s" % (" / ".join(mark_bits) if not mark_bits.is_empty() else "-"))
		if player.is_carrying():
			var overdue := "  BOUNCE NOW" if player.bounce_overdue() else ""
			lines.append("carry   %5.1f m / %0.0f m%s" % [
				player.carry_distance(), Tuning.BOUNCE_INTERVAL, overdue])
		else:
			lines.append("carry   -")
		lines.append("tackle  %s" % _tackle_summary(player.last_tackle))

	if is_instance_valid(ball):
		lines.append("")
		lines.append(_header("BALL"))
		var state := "held" if ball.is_held else ("airborne" if ball.is_airborne() else "loose")
		if ball.is_kick_flight():
			state = "kick"
		elif ball.is_handball_flight():
			state = "handball"
		var distance := 0.0
		if is_instance_valid(player):
			distance = ball.global_position.distance_to(player.global_position)
		lines.append("%-8s %5.1f m/s   height %4.1f m   %5.1f m away" % [
			state, ball.linear_velocity.length(), ball.global_position.y, distance])
	lines.append("")
	lines.append("F3 / D-Up: next page (controls, off)")
	return "\n".join(lines)


## The last tackle off PlayerController.last_tackle: how it came out, then
## the model's numbers (b = balance loss, p(break) = 1 - b, drive along the
## hit line) when it landed.
func _tackle_summary(t: Dictionary) -> String:
	if t.is_empty():
		return "-"
	var bits: Array[String] = []
	if t.get("foul", false):
		bits.append("FOUL" + (" (50)" if t.get("fifty", false) else ""))
	elif t.get("missed", false):
		bits.append("missed")
	else:
		bits.append("slide" if t.get("slide", false) else "lunge")
		bits.append("held" if t.get("held", false) else "broke")
	if t.has("outcome"):
		bits.append(String(t.outcome))
	if t.has("b"):
		bits.append("b %0.2f" % float(t.b))
	if t.has("p_break"):
		bits.append("p(break) %0.2f" % float(t.p_break))
	if t.has("drive"):
		bits.append("drive %+0.1f" % float(t.drive))
	return "  ".join(bits)


# ── CONTROLS page ────────────────────────────────────────────────────

func _controls_lines() -> Array[String]:
	var out: Array[String] = []
	out.append(_header("CONTROLS (live from the input map)"))
	out.append("%s%s%s" % ["".rpad(COL_ACTION), "KEYBOARD".rpad(COL_KEY), "GAMEPAD"])
	for group: Array in CONTROL_GROUPS:
		out.append(String(group[0]))
		for row: Array in group[1]:
			var actions := row.slice(1)
			out.append("  %s%s%s" % [String(row[0]).rpad(COL_ACTION - 2),
				_join_keys(actions, false).rpad(COL_KEY), _join_keys(actions, true)])
	out.append("")
	out.append("F3 / D-Up: next page (off)")
	return out


func _join_keys(actions: Array, pad: bool) -> String:
	var names: Array[String] = []
	for action: StringName in actions:
		var name := _keys_for(action, pad)
		if name != "" and not names.has(name):
			names.append(name)
	return "/".join(names) if not names.is_empty() else "-"


## The first binding of `action` on one device: a key or mouse button for
## the keyboard, a pad button or axis for the gamepad. "" if none.
func _keys_for(action: StringName, pad: bool) -> String:
	if not InputMap.has_action(action):
		return ""
	for event in InputMap.action_get_events(action):
		if pad:
			if event is InputEventJoypadButton:
				return PAD_BUTTONS.get((event as InputEventJoypadButton).button_index, "Btn")
			if event is InputEventJoypadMotion:
				var motion := event as InputEventJoypadMotion
				var axis: String = PAD_AXES.get(motion.axis, "Axis")
				if motion.axis == JOY_AXIS_TRIGGER_LEFT or motion.axis == JOY_AXIS_TRIGGER_RIGHT:
					return axis
				var dir := ""
				if motion.axis == JOY_AXIS_LEFT_X or motion.axis == JOY_AXIS_RIGHT_X:
					dir = "→" if motion.axis_value > 0.0 else "←"
				else:
					dir = "↓" if motion.axis_value > 0.0 else "↑"
				return axis + dir
		else:
			if event is InputEventKey:
				var key := event as InputEventKey
				var code := key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
				return OS.get_keycode_string(code)
			if event is InputEventMouseButton:
				match (event as InputEventMouseButton).button_index:
					MOUSE_BUTTON_LEFT:
						return "Mouse L"
					MOUSE_BUTTON_RIGHT:
						return "Mouse R"
					MOUSE_BUTTON_MIDDLE:
						return "Mouse M"
				return "Mouse"
	return ""


# ── Helpers ──────────────────────────────────────────────────────────

func _header(title: String) -> String:
	return ("-- %s " % title).rpad(HEADER_WIDTH, "-")


func _gait_label(speed: float) -> String:
	if speed < 0.2:
		return "stood "
	if speed <= Tuning.WALK_SPEED + 0.3:
		return "walk  "
	if speed <= Tuning.JOG_SPEED + 0.5:
		return "jog   "
	return "sprint"


func _bar(fraction: float) -> String:
	var filled := int(round(clampf(fraction, 0.0, 1.0) * BAR_WIDTH))
	return "[%s%s]" % ["#".repeat(filled), ".".repeat(BAR_WIDTH - filled)]
