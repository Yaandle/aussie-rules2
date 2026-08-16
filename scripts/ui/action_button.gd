class_name ActionButton
extends PanelContainer

## The one confirm control on a screen: [▶] PLAY — OPEN FIELD.
##
## Not a `Button`, because this screen is driven entirely by the row
## cursor (W/S then Enter) the way `main_menu.gd` is — a real Button would
## bring its own focus and hover states that would fight the cursor for
## which thing looks "current". All it does is draw, and expose
## `set_selected()` for the screen to call.

const HEIGHT := 44.0
const PAD_X := 20
const ICON_SIZE := 18.0
const ICON_GAP := 14
const RADIUS := 8

var _icon: UIIcon
var _label: Label
var _box_idle: StyleBoxFlat
var _box_selected: StyleBoxFlat


func _init(text := "") -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size.y = HEIGHT
	size_flags_horizontal = Control.SIZE_SHRINK_BEGIN

	# Idle already shows the accent border — the reference's resting
	# state is a visible teal outline, not a grey one that lights up. The
	# selected state doubles the border and warms the fill instead.
	_box_idle = _panel(Color(UIStyle.PANEL_FILL, 0.82), Color(UIStyle.ACCENT, 0.55), 1)
	_box_selected = _panel(UIStyle.PANEL_FILL.lerp(UIStyle.ACCENT, 0.07),
		UIStyle.ACCENT, 2)
	add_theme_stylebox_override(&"panel", _box_idle)

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override(&"separation", ICON_GAP)
	add_child(row)

	_icon = UIIcon.new()
	_icon.icon_name = &"play"
	_icon.line_colour = UIStyle.ACCENT
	_icon.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
	_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_icon)

	_label = UIStyle.label(text, UIStyle.SIZE_BUTTON, UIStyle.TEXT_PRIMARY,
		UIStyle.WEIGHT_BOLD, UIStyle.TRACK_BUTTON)
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_label)


func set_selected(selected: bool) -> void:
	add_theme_stylebox_override(&"panel", _box_selected if selected else _box_idle)


func _panel(fill: Color, border: Color, width: int) -> StyleBoxFlat:
	var box := UIStyle.rounded(fill, border, width, RADIUS)
	box.content_margin_left = PAD_X
	box.content_margin_right = PAD_X + 4
	box.content_margin_top = 0
	box.content_margin_bottom = 0
	return box
