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

var player: PlayerController
var ball: Ball

@onready var _panel: Panel = $Panel
@onready var _label: Label = $Label


func _ready() -> void:
	## Single card panel behind the existing text block (see soft_brutalist.gd)
	## — this is a debug overlay, not a screen, so it doesn't warrant themed
	## per-row layout, just legibility over any field background. Kept
	## translucent (not the opaque panel_style() fill) so it reads as an
	## overlay rather than a solid card blocking the 3D view behind it.
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := SoftBrutalist.panel_style(Color(SoftBrutalist.PANEL, 0.35),
		SoftBrutalist.RADIUS_MD, Color(SoftBrutalist.LINE, 0.6))
	_panel.add_theme_stylebox_override(&"panel", style)
	# No soften() call: a blurred drop shadow under a translucent panel
	# would darken the field behind it, fighting the point of making this
	# see-through in the first place.
	# Genuinely fixed-pitch, not just tabular figures: every line below is
	# printf-padded into columns and two of them draw ASCII bars, none of
	# which line up in a proportional face.
	_label.add_theme_font_override(&"font", SoftBrutalist.monospace_font())
	_label.add_theme_color_override(&"font_color", SoftBrutalist.INK)


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed(&"debug_hud"):
		visible = not visible
	if not visible:
		return
	_label.text = _compose()


func _compose() -> String:
	var lines: Array[String] = []
	lines.append("%3d fps      input: %s" % [
		Engine.get_frames_per_second(), InputManager.device_name()])
	lines.append("last gamepad   button %-4s axis %s" % [
		InputManager.last_joy_button_debug(), InputManager.last_joy_axis_debug()])
	lines.append("mode %s / %s" % [GameState.mode_name(), GameState.phase_name()])
	lines.append("")

	if is_instance_valid(player):
		var speed := player.speed()
		lines.append("speed    %5.2f m/s  %s  %s" % [
			speed, _gait_label(speed), _bar(speed / Tuning.SPRINT_SPEED)])
		var blend := player.locomotion_blend()
		lines.append("blend    strafe %+0.2f   forward %+0.2f" % [blend.x, blend.y])
		lines.append("anim     %s" % player.animation_state())
		lines.append("charge   %s %0.2f" % [_bar(player.kick_charge()), player.kick_charge()])
		var mark_bits: Array[String] = []
		if player.is_mark_readying():
			mark_bits.append("READYING")
		if player.is_protected():
			mark_bits.append("PROTECTED %0.1fs" % player.protected_seconds())
		lines.append("mark     %s" % (" / ".join(mark_bits) if not mark_bits.is_empty() else "-"))
		if player.is_carrying():
			var overdue := "  BOUNCE NOW" if player.bounce_overdue() else ""
			lines.append("carry    %5.1f m / %0.0f m%s" % [
				player.carry_distance(), Tuning.BOUNCE_INTERVAL, overdue])
		else:
			lines.append("carry    -")

	if is_instance_valid(ball):
		var state := "held" if ball.is_held else ("airborne" if ball.is_airborne() else "loose")
		var distance := 0.0
		if is_instance_valid(player):
			distance = ball.global_position.distance_to(player.global_position)
		lines.append("ball     %-8s %5.1f m/s   height %4.1f m   %5.1f m away" % [
			state, ball.linear_velocity.length(), ball.global_position.y, distance])

	lines.append("")
	lines.append("WASD move   Ctrl walk   Shift sprint   arrows/mouse camera   C recentre")
	lines.append("K hold+release kick   Q handball   Space bounce   E tackle   R reset ball   F3 hud")
	lines.append("G hold safe mark/pickup   Q running mark   H aggressive mark (jump)")
	return "\n".join(lines)


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
