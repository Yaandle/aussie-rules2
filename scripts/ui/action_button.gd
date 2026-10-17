class_name ActionButton
extends Panel

## The one confirm control on a screen: [▶] PLAY — OPEN FIELD.
##
## Not a `Button`, because this screen is driven entirely by the row
## cursor (W/S then Enter) the way `main_menu.gd` is — a real Button would
## bring its own focus and hover states that would fight the cursor for
## which thing looks "current". All it does is draw, and expose
## `set_selected()` for the screen to call.
##
## `Panel`, not `PanelContainer`: the shadow under this is a child node
## (see SoftBrutalist.soften) that has to reach *past* the button's rect
## to have anywhere to blur into, and a Container would sort that child
## back inside its own content box every layout pass. Panel draws the
## same stylebox without claiming its children, so the row below is laid
## out against explicit padding offsets instead and the width is measured
## from it once in _ready().

const HEIGHT := 44.0
const PAD_X := 20.0
const ICON_SIZE := 18.0
const ICON_GAP := 14

## Button corner radius — sharp, matching RetroWindow's unrounded shell.
const RADIUS := RetroWindow.RADIUS

var _row: HBoxContainer
var _icon: UIIcon
var _label: Label
var _box_idle: StyleBoxFlat
var _box_selected: StyleBoxFlat
var _shadow: SoftShadow


func _init(text := "") -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size.y = HEIGHT
	size_flags_horizontal = Control.SIZE_SHRINK_BEGIN

	# Hairline box (UIStyle.rounded()), matching the icon boxes' treatment
	# rather than the 2px edge a full card carries. "Selected" swaps in
	# the accent-bordered cut directly rather than tweening through
	# SoftBrutalist.animate_state(); the shadow underneath does ease, so
	# the button still lifts rather than snapping.
	_box_idle = UIStyle.rounded(UIStyle.ICON_BOX_FILL, UIStyle.ICON_BOX_BORDER, 2, RADIUS)
	_box_selected = UIStyle.rounded(UIStyle.ICON_BOX_FILL, UIStyle.ACCENT, 2, RADIUS)
	add_theme_stylebox_override(&"panel", _box_idle)
	_shadow = SoftBrutalist.soften(self, SoftBrutalist.Elevation.LOW, float(RADIUS))

	_row = HBoxContainer.new()
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.add_theme_constant_override(&"separation", ICON_GAP)
	_row.set_anchors_preset(Control.PRESET_FULL_RECT)
	_row.offset_left = PAD_X
	_row.offset_right = -PAD_X
	_row.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(_row)

	_icon = UIIcon.new()
	_icon.icon_name = &"play"
	_icon.line_colour = UIStyle.ACCENT
	_icon.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
	_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_row.add_child(_icon)

	_label = UIStyle.label(text, UIStyle.SIZE_BUTTON, UIStyle.TEXT_PRIMARY,
		UIStyle.WEIGHT_BOLD, UIStyle.TRACK_BUTTON)
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_row.add_child(_label)


## Panel does not grow to fit its children, so the width the container
## would have supplied is measured here instead — once, since the label
## text is fixed at construction.
func _ready() -> void:
	size = Vector2(_row.get_combined_minimum_size().x + PAD_X * 2.0, HEIGHT)


## Swaps the fixed "play" triangle for another glyph — CUSTOMISE/BACK on
## the character screen reuses this same button shape with &"gear".
func set_icon(icon_name: StringName) -> void:
	_icon.icon_name = icon_name


func set_text(text: String) -> void:
	_label.text = text
	size.x = _row.get_combined_minimum_size().x + PAD_X * 2.0


func set_selected(selected: bool) -> void:
	add_theme_stylebox_override(&"panel", _box_selected if selected else _box_idle)
	SoftBrutalist.set_elevation(_shadow,
		SoftBrutalist.Elevation.REST if selected else SoftBrutalist.Elevation.LOW)
