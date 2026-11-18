class_name GoalKickPrompt
extends CanvasLayer

## Quiet corner prompt for a legal-mark set shot. This is intentionally a
## presentation prompt, not a second kick mechanic: accepted shots use the
## regular aim/charge/execute controls and the real Ball physics.
##
## 2026-11-18 (playtest: "the old press Y for goals brown window appears...
## it should be the other minimal text I had"): the 2026-11-14 stash
## recovery brought this in as a brown RetroWindow box over the minimal
## KeyHintBar chip update already had (DebugHud's "Set Shot for Goal"). It
## is that chip now: same KeyHintBar, same bottom-right spot and margin,
## "[Y] Goals" in range, "[LT] Aim  [RT] Kick" once the kick is accepted.
## The keys are read from the live (remappable) bindings. DebugHud hides
## its own chip while this one shows, so there's only ever one.

const EDGE_MARGIN := 16.0

var player: PlayerController = null
var active := false
var _hint: KeyHintBar
var _shown := ""


func _ready() -> void:
	layer = 4
	_hint = KeyHintBar.new()
	_hint.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_hint.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_hint.alignment = BoxContainer.ALIGNMENT_END
	_hint.offset_left = -EDGE_MARGIN
	_hint.offset_right = -EDGE_MARGIN
	_hint.offset_top = -EDGE_MARGIN
	_hint.offset_bottom = -EDGE_MARGIN
	_hint.visible = false
	add_child(_hint)


func _process(_delta: float) -> void:
	var state := ""
	if active:
		state = "kick"
	elif is_instance_valid(player) and player.can_take_goal_kick(Tuning.GOAL_KICK_MAX_RANGE):
		state = "offer"
	_hint.visible = state != ""
	var pad := InputManager.device == InputManager.Device.GAMEPAD
	var key := "%s:%s" % [state, pad]
	if state == "" or key == _shown:
		return
	_shown = key
	if state == "kick":
		_hint.set_hints([{"keys": "LT" if pad else "K", "label": "Aim"}, {"keys": "RT" if pad else "F", "label": "Kick"}])
	else:
		_hint.set_hints([{"keys": _key_for(&"goal_kick", pad), "label": "Goals"}])


## The first binding of `action` for the pad or the keyboard, as a chip label.
static func _key_for(action: StringName, pad: bool) -> String:
	if not InputMap.has_action(action):
		return "Y"
	for event in InputMap.action_get_events(action):
		if pad and event is InputEventJoypadButton:
			match (event as InputEventJoypadButton).button_index:
				JOY_BUTTON_A: return "A"
				JOY_BUTTON_B: return "B"
				JOY_BUTTON_X: return "X"
				JOY_BUTTON_Y: return "Y"
			return "Btn"
		if not pad and event is InputEventKey:
			var k := event as InputEventKey
			var code := k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode
			return OS.get_keycode_string(code)
	return "Y"
