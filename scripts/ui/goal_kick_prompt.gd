class_name GoalKickPrompt
extends CanvasLayer

## Quiet corner prompt for a legal-mark set shot. This is intentionally a
## presentation prompt, not a second kick mechanic: accepted shots use the
## regular aim/charge/execute controls and the real Ball physics.

var player: PlayerController = null
var active := false
var _label: Label


func _ready() -> void:
	layer = 4
	_label = UIStyle.label("", UIStyle.SIZE_LABEL, UIStyle.TEXT_PRIMARY,
		UIStyle.WEIGHT_HEAVY, UIStyle.TRACK_HINT)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_label.position = Vector2(-196.0, -112.0)
	_label.size = Vector2(172.0, 38.0)
	var box := UIStyle.rounded(UIStyle.PANEL_FILL, UIStyle.CHIP_BORDER, 2, RetroWindow.RADIUS)
	_label.add_theme_stylebox_override(&"normal", box)
	add_child(_label)


func _process(_delta: float) -> void:
	if active:
		_label.text = "LT AIM  ·  RT KICK" if InputManager.device == InputManager.Device.GAMEPAD \
			else "K AIM  ·  F KICK"
		_label.visible = true
		return
	_label.visible = is_instance_valid(player) \
		and player.can_take_goal_kick(Tuning.GOAL_KICK_MAX_RANGE)
	if _label.visible:
		_label.text = "Y  ·  GOALS"
