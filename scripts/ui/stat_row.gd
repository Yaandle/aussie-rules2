class_name StatRow
extends Control

## One attribute line: [icon] LABEL · LOCKED  [■■■■□□□□□]  8.40 m/s
##
## The character screen is eight of these, so nothing about a particular
## stat lives in here. Everything the row draws comes in through
## `configure()` (the parts fixed at build time) and `set_state()` (the
## parts that change as the draft is edited) — adding a ninth attribute is
## a line of data in `character_screen.gd` and no change to this file.
##
## Columns are explicit pixel offsets rather than an HBoxContainer of
## sized children, because the bar has to start at the same x on every row
## regardless of how long the label is ("SPEED" vs "KICKING ACCURACY"),
## and a container would have to be told that via minimum sizes anyway.

# ── Column layout, in design-resolution px (1280x720) ────────────────
const HEIGHT := 40.0
const WIDTH := 560.0
const ICON_BOX := 40.0
const ICON_INSET := 8.0
const ICON_RADIUS := 10
const LABEL_X := 56.0
const LABEL_GAP := 10           ## label to its "· LOCKED" suffix
const BAR_X := 254.0
const VALUE_X := 460.0

## Nine squares regardless of the stat's real range, so every row reads
## the same at a glance — the bar is a rough sense of "how far up", not a
## precise readout. The number beside it is the precise readout.
const SEGMENTS := 9
const SEGMENT_SIZE := 11.0
const SEGMENT_GAP := 10.0

## Cursor tick in the left margin, outside the icon column.
const MARKER_X := -16.0
const MARKER_SIZE := Vector2(3.0, 20.0)

const LOCKED_SUFFIX := "• LOCKED"


## Bar squares: filled solid, empty outlined. Split out only because
## `_draw` needs a canvas of its own to sit in the bar column.
class SegmentBar extends Control:
	var filled := 0:
		set(value):
			filled = value
			queue_redraw()

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(
			SEGMENTS * SEGMENT_SIZE + (SEGMENTS - 1) * SEGMENT_GAP, HEIGHT)

	func _draw() -> void:
		var top := floorf((size.y - SEGMENT_SIZE) * 0.5)
		for i in SEGMENTS:
			var left := i * (SEGMENT_SIZE + SEGMENT_GAP)
			if i < filled:
				draw_rect(Rect2(left, top, SEGMENT_SIZE, SEGMENT_SIZE),
					UIStyle.SEGMENT_FILL, true)
			else:
				# Half-pixel inset so the 1px stroke lands on whole
				# pixels instead of straddling two and going grey.
				draw_rect(Rect2(left + 0.5, top + 0.5,
					SEGMENT_SIZE - 1.0, SEGMENT_SIZE - 1.0),
					UIStyle.SEGMENT_EMPTY, false, 1.0)


var _marker: ColorRect
var _icon_box: Panel
var _icon: UIIcon
var _name: Label
var _lock: Label
var _bar: SegmentBar
var _value: Label
var _locked := false
var _accent := UIStyle.ACCENT
var _box_idle: StyleBoxFlat
var _box_selected: StyleBoxFlat


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(WIDTH, HEIGHT)
	_build()


func _build() -> void:
	_marker = ColorRect.new()
	_marker.position = Vector2(MARKER_X, (HEIGHT - MARKER_SIZE.y) * 0.5)
	_marker.size = MARKER_SIZE
	_marker.visible = false
	add_child(_marker)

	_icon_box = Panel.new()
	_icon_box.position = Vector2.ZERO
	_icon_box.size = Vector2(ICON_BOX, ICON_BOX)
	add_child(_icon_box)

	_icon = UIIcon.new()
	_icon.position = Vector2(ICON_INSET, ICON_INSET)
	_icon.size = Vector2(ICON_BOX - ICON_INSET * 2.0, ICON_BOX - ICON_INSET * 2.0)
	_icon_box.add_child(_icon)

	# The label and its "· LOCKED" suffix are two nodes, not one string,
	# because the suffix is a different weight and colour. An HBox spares
	# the row from measuring the label's rendered width by hand.
	var name_box := HBoxContainer.new()
	name_box.position = Vector2(LABEL_X, 0.0)
	name_box.size = Vector2(BAR_X - LABEL_X - 12.0, HEIGHT)
	name_box.add_theme_constant_override(&"separation", LABEL_GAP)
	name_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(name_box)

	_name = UIStyle.label("", UIStyle.SIZE_LABEL, UIStyle.TEXT_PRIMARY,
		UIStyle.WEIGHT_BOLD, UIStyle.TRACK_LABEL)
	_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_box.add_child(_name)

	_lock = UIStyle.label(LOCKED_SUFFIX, UIStyle.SIZE_LABEL, UIStyle.TEXT_MUTED,
		UIStyle.WEIGHT_REGULAR, UIStyle.TRACK_LABEL)
	_lock.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_lock.visible = false
	name_box.add_child(_lock)

	_bar = SegmentBar.new()
	_bar.position = Vector2(BAR_X, 0.0)
	_bar.size = Vector2(_bar.custom_minimum_size.x, HEIGHT)
	add_child(_bar)

	_value = UIStyle.label("", UIStyle.SIZE_VALUE, UIStyle.TEXT_PRIMARY,
		UIStyle.WEIGHT_REGULAR, 0)
	_value.position = Vector2(VALUE_X, 0.0)
	_value.size = Vector2(WIDTH - VALUE_X, HEIGHT)
	_value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_value)


## Build-time content. `bar` is false for categorical stats (KICKING
## FOOT is a side, not a level) — those get no squares at all rather than
## nine empty ones, which would read as "zero" for something that has no
## zero.
func configure(icon_name: StringName, display_name: String, locked: bool,
		bar := true) -> void:
	_icon.icon_name = icon_name
	_name.text = display_name
	_locked = locked
	_lock.visible = locked
	_bar.visible = bar
	# A locked row can still hold the cursor (W/S walks every row), so it
	# needs a cursor cue — dimmed, to say "you are here, and there is
	# nothing to turn".
	_accent = UIStyle.ACCENT if not locked else Color(UIStyle.ACCENT, 0.45)
	_marker.color = _accent
	_box_idle = UIStyle.rounded(UIStyle.ICON_BOX_FILL, UIStyle.ICON_BOX_BORDER,
		1, ICON_RADIUS)
	_box_selected = UIStyle.rounded(UIStyle.ICON_BOX_FILL, _accent, 1, ICON_RADIUS)


## Per-refresh state. `filled` is honoured whether or not the row is
## locked — locked means "you cannot change this", not "this has no
## value". `value_text` empty hides the numeric column, for stats that
## have no assigned number yet.
func set_state(selected: bool, filled: int, value_text: String) -> void:
	_bar.filled = filled
	_value.text = value_text
	_value.visible = not value_text.is_empty()

	_marker.visible = selected
	_icon_box.add_theme_stylebox_override(&"panel",
		_box_selected if selected else _box_idle)
	_icon.line_colour = _accent if selected else UIStyle.ICON_LINE
