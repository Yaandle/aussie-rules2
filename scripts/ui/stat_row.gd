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
const LABEL_X := 56.0
const LABEL_GAP := 10           ## label to its "· LOCKED" suffix
const BAR_X := 254.0
const VALUE_X := 460.0

## "You can change this" cue flanking the value column, shown only while
## the row is selected (and adjustable — a locked row never shows them,
## nothing to change) — the orange marker on the left says "you are
## here", these say "and here's what moves". Sized and placed to sit
## clear of the value text itself (VALUE_X's own column) rather than
## bracketing it exactly, since value strings vary a lot in width
## (short counts/percentages vs a swatch name like "CRIMSON").
const ARROW_SIZE := 13.0
const ARROW_GAP := 8.0
const ARROW_LEFT_X := VALUE_X - ARROW_GAP - ARROW_SIZE
const ARROW_RIGHT_X := WIDTH + ARROW_GAP

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

## Icon box corner radius — sharp, matching RetroWindow's unrounded shell.
const ICON_RADIUS := RetroWindow.RADIUS


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
				# Half-pixel inset so the stroke lands on whole pixels
				# instead of straddling two and going grey. A full
				# SoftBrutalist.BORDER_WIDTH stroke would all but erase an
				# 11px square, so this stays a 1.5px hairline in the soft
				# rule colour — an empty segment is a placeholder, and
				# drawing it at the same weight as a filled one makes the
				# bar read as full.
				draw_rect(Rect2(left + 0.5, top + 0.5,
					SEGMENT_SIZE - 1.0, SEGMENT_SIZE - 1.0),
					UIStyle.SEGMENT_EMPTY, false, 1.5)


var _marker: ColorRect
var _icon_box: Panel
var _box_idle: StyleBoxFlat
var _box_selected: StyleBoxFlat
var _icon: UIIcon
var _name: Label
var _lock: Label
var _bar: SegmentBar
var _value: Label
var _arrow_left: UIIcon
var _arrow_right: UIIcon
var _locked := false
## Separate from `_locked` — a row can be fully enabled but still edited
## some other way than A/D (career_character_screen.gd's NAME row opens
## a text field on Enter instead), in which case the arrow cue would be
## actively misleading even though the row isn't "locked" in the
## dimmed/LOCKED-badge sense at all.
var _adjustable := true
var _accent := UIStyle.ACCENT
var _shadow: SoftShadow


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
	# Hairline box (UIStyle.rounded()), not the 2px edge a full card
	# carries — at 40px square a card border would be most of the shape.
	_box_idle = UIStyle.rounded(UIStyle.ICON_BOX_FILL, UIStyle.ICON_BOX_BORDER, 2, ICON_RADIUS)
	_box_selected = UIStyle.rounded(UIStyle.ICON_BOX_FILL, UIStyle.ACCENT, 2, ICON_RADIUS)

	_icon_box.add_theme_stylebox_override(&"panel", _box_idle)
	add_child(_icon_box)
	# LOW, not REST: the card-height blur is wider than this box is, and
	# a shadow bigger than the thing casting it reads as a smudge rather
	# than as height.
	_shadow = SoftBrutalist.soften(_icon_box, SoftBrutalist.Elevation.LOW, float(ICON_RADIUS))

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

	_arrow_left = UIIcon.new()
	_arrow_left.icon_name = &"arrow_left"
	_arrow_left.position = Vector2(ARROW_LEFT_X, (HEIGHT - ARROW_SIZE) * 0.5)
	_arrow_left.size = Vector2(ARROW_SIZE, ARROW_SIZE)
	_arrow_left.modulate.a = 0.0
	add_child(_arrow_left)

	_arrow_right = UIIcon.new()
	_arrow_right.icon_name = &"arrow_right"
	_arrow_right.position = Vector2(ARROW_RIGHT_X, (HEIGHT - ARROW_SIZE) * 0.5)
	_arrow_right.size = Vector2(ARROW_SIZE, ARROW_SIZE)
	_arrow_right.modulate.a = 0.0
	add_child(_arrow_right)


## Build-time content. `bar` is false for categorical stats (KICKING
## FOOT is a side, not a level) — those get no squares at all rather than
## nine empty ones, which would read as "zero" for something that has no
## zero.
func configure(icon_name: StringName, display_name: String, locked: bool,
		bar := true, adjustable := true) -> void:
	_icon.icon_name = icon_name
	_name.text = display_name
	_locked = locked
	_adjustable = adjustable
	_lock.visible = locked
	_bar.visible = bar
	# A locked row can still hold the cursor (W/S walks every row), so it
	# needs a cursor cue — dimmed, to say "you are here, and there is
	# nothing to turn".
	_accent = UIStyle.ACCENT if not locked else Color(UIStyle.ACCENT, 0.45)
	_marker.color = _accent


## Per-refresh state. `filled` is honoured whether or not the row is
## locked — locked means "you cannot change this", not "this has no
## value". `value_text` empty hides the numeric column, for stats that
## have no assigned number yet.
func set_state(selected: bool, filled: int, value_text: String) -> void:
	_bar.filled = filled
	_value.text = value_text
	_value.visible = not value_text.is_empty()

	_marker.visible = selected
	_icon_box.add_theme_stylebox_override(&"panel", _box_selected if selected else _box_idle)
	_icon.line_colour = _accent if selected else UIStyle.ICON_LINE
	# The selected row lifts as well as changing colour, so the cursor
	# reads at a glance from across the column rather than only up close.
	SoftBrutalist.set_elevation(_shadow,
		SoftBrutalist.Elevation.REST if selected else SoftBrutalist.Elevation.LOW)

	# "You can adjust this" cue — only while selected, and never on a
	# locked row (nothing to adjust). Full opacity rather than UIStyle.
	# ACCENT's own alpha, so the cue reads as clearly as the orange
	# marker it's paired with.
	var show_arrows := selected and not _locked and _adjustable
	_arrow_left.line_colour = UIStyle.ACCENT
	_arrow_right.line_colour = UIStyle.ACCENT
	_arrow_left.modulate.a = 1.0 if show_arrows else 0.0
	_arrow_right.modulate.a = 1.0 if show_arrows else 0.0
