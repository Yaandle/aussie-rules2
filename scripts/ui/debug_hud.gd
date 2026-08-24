class_name DebugHud
extends CanvasLayer

## Numbers on screen, because "does this feel weighty?" is not a question
## you can answer by eye alone.
##
## Speed in real m/s against the named gaits, the live blend-space
## coordinate, the current animation state, and the carry distance
## against AFL's 15m bounce rule. If the blend position is not moving
## when the player turns hard, the strafe axis is not being fed — that is
## the kind of thing this exists to catch. F3 / D-pad up toggles it.

const BAR_WIDTH := 14

## Controls reference table — one row per action, [action label, keyboard,
## gamepad]. Static (matches project.godot's actual input map, verified
## against it directly rather than guessed), so it's built once into
## _controls_text in _ready() instead of re-formatted every frame like the
## live state below it. Several actions deliberately share one physical
## button (Q/X: handball, running mark, smother; LT: kick stance, spoil;
## B: bounce, tackle) — that's this project's own "ball state + player
## state decides, not just the button" design (see player_controller.gd's
## Marking section header comment), not a conflict, so rows are grouped to
## read that way rather than hidden.
const COL_ACTION := 26
const COL_KEY := 20
const CONTROLS := [
	["Move", "WASD", "Left Stick"],
	["Walk / Sprint", "Ctrl / Shift", "light push / L3"],
	["Camera", "Arrows, Mouse", "Right Stick"],
	["Camera recentre", "C", "R3"],
	["Kick stance / fire", "K (hold) / F", "LT (hold) / RT"],
	["Handball", "Q", "X"],
	["Bounce", "Space", "B"],
	["Tackle", "E", "B"],
	["Safe mark / pickup", "G (hold)", "A (hold)"],
	["Running mark", "Q", "X"],
	["Aggressive mark (jump)", "H", "Y"],
	["Spoil", "P", "LT"],
	["Smother", "Q", "X"],
	["Bump stance", "L (hold)", "LB (hold)"],
	["Hit-out (ruck only)", "J", "RB"],
	["Reset ball", "R", "Back / View"],
	["Toggle this HUD", "F3", "D-Pad Up"],
]

var player: PlayerController
var ball: Ball

var _controls_text := ""

@onready var _panel: Panel = $Panel
@onready var _label: Label = $Label


func _ready() -> void:
	## Single card panel behind the existing text block (see soft_brutalist.gd)
	## — this is a debug overlay, not a screen, so it doesn't warrant themed
	## per-row layout, just legibility over any field background. Kept
	## translucent (not the opaque panel_style() fill) so it reads as an
	## overlay rather than a solid card blocking the 3D view behind it —
	## and deliberately faint (0.14, down from an earlier 0.35) so it stays
	## an overlay even over a bright field, not a card sitting on top of one.
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := SoftBrutalist.panel_style(Color(SoftBrutalist.PANEL, 0.14),
		SoftBrutalist.RADIUS_MD, Color(SoftBrutalist.LINE, 0.45))
	_panel.add_theme_stylebox_override(&"panel", style)
	# No soften() call: a blurred drop shadow under a translucent panel
	# would darken the field behind it, fighting the point of making this
	# see-through in the first place.
	# Genuinely fixed-pitch, not just tabular figures: every line below is
	# printf-padded into columns and two of them draw ASCII bars, none of
	# which line up in a proportional face.
	_label.add_theme_font_override(&"font", SoftBrutalist.monospace_font())
	_label.add_theme_color_override(&"font_color", SoftBrutalist.INK)
	# A light outline on the dark ink text is what keeps it legible now
	# that the panel behind it is faint enough to show grass/sky/players
	# through — the panel alone no longer guarantees enough contrast on
	# its own the way the old, denser fill did.
	_label.add_theme_color_override(&"font_outline_color", Color(SoftBrutalist.PANEL, 0.9))
	_label.add_theme_constant_override(&"outline_size", 3)

	_controls_text = "\n".join(_controls_lines())


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed(&"debug_hud"):
		visible = not visible
	if not visible:
		return
	_label.text = _compose()


func _compose() -> String:
	var lines: Array[String] = []
	lines.append(_header("STATUS"))
	lines.append("%3d fps      input: %s" % [
		Engine.get_frames_per_second(), InputManager.device_name()])
	lines.append("last gamepad   button %-4s axis %s" % [
		InputManager.last_joy_button_debug(), InputManager.last_joy_axis_debug()])
	lines.append("mode %s / %s" % [GameState.mode_name(), GameState.phase_name()])

	if is_instance_valid(player):
		lines.append("")
		lines.append(_header("PLAYER"))
		var speed := player.speed()
		var tag := "  BACKPEDAL" if player.is_backpedaling() else ""
		lines.append("speed    %5.2f m/s  %s  %s%s" % [
			speed, _gait_label(speed), _bar(speed / Tuning.SPRINT_SPEED), tag])
		var blend := player.locomotion_blend()
		lines.append("blend    strafe %+0.2f   forward %+0.2f" % [blend.x, blend.y])
		lines.append("anim     %s" % player.animation_state())
		lines.append("charge   %s %0.2f" % [_bar(player.kick_charge()), player.kick_charge()])
		var mark_bits: Array[String] = []
		if player.is_mark_readying():
			mark_bits.append("READYING")
		if player.is_protected():
			mark_bits.append("PROTECTED %0.1fs" % player.protected_seconds())
		if player.is_standing_the_mark():
			mark_bits.append("STANDING THE MARK")
		lines.append("mark     %s" % (" / ".join(mark_bits) if not mark_bits.is_empty() else "-"))
		if player.is_ruck_contestant():
			lines.append("ruck     CONTESTING — RB to hit out")
		if player.is_carrying():
			var overdue := "  BOUNCE NOW" if player.bounce_overdue() else ""
			lines.append("carry    %5.1f m / %0.0f m%s" % [
				player.carry_distance(), Tuning.BOUNCE_INTERVAL, overdue])
		else:
			lines.append("carry    -")

	if is_instance_valid(ball):
		lines.append("")
		lines.append(_header("BALL"))
		var state := "held" if ball.is_held else ("airborne" if ball.is_airborne() else "loose")
		var distance := 0.0
		if is_instance_valid(player):
			distance = ball.global_position.distance_to(player.global_position)
		lines.append("%-8s %5.1f m/s   height %4.1f m   %5.1f m away" % [
			state, ball.linear_velocity.length(), ball.global_position.y, distance])

	lines.append("")
	lines.append(_header("CONTROLS"))
	lines.append(_controls_text)
	return "\n".join(lines)


func _header(title: String) -> String:
	return ("-- %s " % title).rpad(56, "-")


func _controls_lines() -> Array[String]:
	var out: Array[String] = []
	out.append("%s%s%s" % [
		"ACTION".rpad(COL_ACTION), "KEYBOARD".rpad(COL_KEY), "GAMEPAD"])
	for row in CONTROLS:
		out.append("%s%s%s" % [
			(row[0] as String).rpad(COL_ACTION),
			(row[1] as String).rpad(COL_KEY),
			row[2] as String])
	return out


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
