class_name StudioStyle
extends RefCounted

## The video editor's Text Studio chrome, for the customisation and
## training screens (HudStyleScreen, TrainingScreen): flat paper and ink
## fills, 3 px ink borders, hard offset shadows, lime for focus, and a pick
## shown as an ink tile with lime text. Its own small family on purpose,
## beside Soft Brutalist and RetroWindow (playtest 2026-10-30: "I liked
## that design and it suits a customisation screen"). The tokens are the
## editor's own (video-editor frontend/styles.css :root); the type is this
## project's, through SoftBrutalist, since the editor's fonts aren't here.

const PAPER := Color("#F3EFE4")
const PAPER_DEEP := Color("#E2DCCB")
const INK := Color("#121212")
const INK_SOFT := Color("#4E4B45")
const LIME := Color("#CDF545")
const ORANGE := Color("#FF4F1F")
const WHITE := Color("#FFFFFF")
const BORDER := 3
const SHADOW := 4
const HEADER_HEIGHT := 56.0


## A flat fill with an ink border and, if `shadow` > 0, a hard ink shadow
## offset down-right — StyleBoxFlat's shadow at size 1 is as near hard as
## it draws.
static func box(fill: Color, border := BORDER, shadow := 0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = INK
	style.set_border_width_all(border)
	if shadow > 0:
		style.shadow_color = INK
		style.shadow_size = 1
		style.shadow_offset = Vector2(shadow, shadow)
	return style


## The header (border along the bottom) and a side column (along the
## right), as the editor draws them.
static func bar(fill: Color, right_edge: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = INK
	if right_edge:
		style.border_width_right = BORDER
	else:
		style.border_width_bottom = BORDER
	return style


static func text(content: String, size: int, colour: Color, font: Font) -> Label:
	var label := Label.new()
	label.text = content
	label.add_theme_font_override(&"font", font)
	label.add_theme_font_size_override(&"font_size", size)
	label.add_theme_color_override(&"font_color", colour)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


static func display_font() -> Font:
	return SoftBrutalist.font(SoftBrutalist.WEIGHT_HEAVY)


static func body_font() -> Font:
	return SoftBrutalist.font(SoftBrutalist.WEIGHT_BOLD)


static func mono_font() -> Font:
	return SoftBrutalist.monospace_font()


## The editor's header bar: a title, a mono breadcrumb beside it, and
## `hints` (a DeviceHintBar, already filled) pinned to the right.
static func header(parent: Control, title: String, crumb: String, hints: Control) -> Panel:
	var head := Panel.new()
	head.add_theme_stylebox_override(&"panel", bar(WHITE, false))
	head.set_anchors_preset(Control.PRESET_TOP_WIDE)
	head.offset_bottom = HEADER_HEIGHT
	parent.add_child(head)
	var title_label := text(title, 20, INK, display_font())
	title_label.position = Vector2(24.0, 16.0)
	head.add_child(title_label)
	var crumb_label := text(crumb, 11, INK_SOFT, mono_font())
	crumb_label.position = Vector2(24.0 + title_label.get_combined_minimum_size().x + 16.0, 22.0)
	head.add_child(crumb_label)
	if hints != null:
		hints.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		hints.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		hints.offset_left = -24.0
		hints.offset_right = -24.0
		hints.offset_top = 12.0
		head.add_child(hints)
	return head
