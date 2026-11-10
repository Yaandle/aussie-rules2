class_name UIStyle
extends RefCounted

## Role-named aliases over SoftBrutalist, for the character screen.
##
## The character screen is eight repeats of one row plus a button and a
## hint bar, and every widget in it reads its colour and type by *role*
## ("the value column", "a hint chip") rather than by token. That
## indirection is worth keeping — but it used to carry its own numbers,
## and two independent scales for one app is how a 36px title on one
## screen ends up beside a 40px title on another, with 6px of tracking
## against 4px.
##
## So nothing here is a value any more. Every constant below resolves to
## a SoftBrutalist or RetroWindow token, which are the two places sizes,
## weights and colours are actually chosen; this file only records which
## token each role uses. Changing the app's type scale is a change there,
## and this screen follows.
##
## The palette/shape tokens (ACCENT, ICON_BOX_*, CHIP_BORDER, PANEL_FILL,
## TEXT_PRIMARY, and rounded()'s corner radius) now point at RetroWindow
## rather than SoftBrutalist — sharp corners, near-black ink, warm
## parchment fill, rust accent — so this screen's chips read as the same
## "windowed retro console" family as settings/pause/team-list/remap
## rather than the rounded soft-shadow look those screens moved off of.
## The blurred elevation shadow (SoftBrutalist.soften/set_elevation) is
## deliberately left alone: swapping every icon box and the play button
## over to a hard offset shadow the way a full card does would be a much
## bigger structural change for a screen sitting directly on the live 3D
## backdrop, not "some of the retro style".
##
## Fonts are built as FontVariation over the engine's default face
## (`ThemeDB.fallback_font`, Open Sans SemiBold) rather than shipped as
## an asset. The reference look is not really about the typeface, it is
## about weight and tracking: `variation_embolden` supplies the weight
## axis the base face does not have, and `spacing_glyph` supplies the
## letter-spacing. If a licensed display face is ever added, set
## `base_font` in SoftBrutalist.font() and every screen picks it up.

# ── Palette ──────────────────────────────────────────────────────────

const TEXT_PRIMARY := RetroWindow.BORDER      ## Titles, labels, values
const TEXT_MUTED := SoftBrutalist.MUTED       ## Subtitle, "· LOCKED", hint labels
const ICON_LINE := RetroWindow.BORDER
const SEGMENT_FILL := SoftBrutalist.ACCENT_PRIMARY  ## A filled bar square is the green accent
const SEGMENT_EMPTY := SoftBrutalist.LINE_SOFT      ## An empty one is this, outline only
const PANEL_FILL := RetroWindow.PANEL
const CHIP_BORDER := RetroWindow.BORDER

## Rust. The one "this is live/interactive" accent on this screen — the
## play button's border, and the selected row's icon box and marker. Same
## accent the retro-shelled screens (settings/pause/team-list/remap) use
## for their own selected-row highlight.
const ACCENT := RetroWindow.ACCENT

## Icon box fill/border: warm parchment fill, near-black border — the
## retro palette, in place of the plain white/soft-LINE pairing every
## other bordered element in the app still uses.
const ICON_BOX_FILL := RetroWindow.PANEL
const ICON_BOX_BORDER := RetroWindow.BORDER

# ── Type ─────────────────────────────────────────────────────────────
# Sizes are for the project's 1280x720 design resolution; `canvas_items`
# stretch scales them from there (see project.godot [display]).

const SIZE_TITLE := SoftBrutalist.SIZE_TITLE
const SIZE_SUBTITLE := SoftBrutalist.SIZE_LABEL
const SIZE_LABEL := SoftBrutalist.SIZE_BODY
const SIZE_VALUE := SoftBrutalist.SIZE_BODY
const SIZE_BUTTON := SoftBrutalist.SIZE_BODY
const SIZE_HINT := SoftBrutalist.SIZE_CAPTION

const WEIGHT_HEAVY := SoftBrutalist.WEIGHT_HEAVY
const WEIGHT_BOLD := SoftBrutalist.WEIGHT_BOLD
const WEIGHT_REGULAR := SoftBrutalist.WEIGHT_REGULAR

const TRACK_TITLE := SoftBrutalist.TRACK_TITLE
const TRACK_SUBTITLE := SoftBrutalist.TRACK_LABEL
const TRACK_LABEL := SoftBrutalist.TRACK_LABEL
const TRACK_BUTTON := SoftBrutalist.TRACK_TITLE
const TRACK_HINT := SoftBrutalist.TRACK_LABEL


static func font(embolden: float, tracking: int) -> FontVariation:
	return SoftBrutalist.font(embolden, tracking)


static func label(text: String, size: int, colour: Color, embolden := WEIGHT_REGULAR,
		tracking := 0) -> Label:
	return SoftBrutalist.label(text, size, colour, embolden, tracking)


## Sharp-cornered rect with a hairline border — despite the name, this now
## draws RetroWindow's unrounded corner (radius 0) by default, kept as
## "rounded" only because every call site already reads `UIStyle.rounded()`
## and the shape's role (small bordered chip) hasn't changed, only its
## corner. Used for the icon boxes, the play button, and the key hint
## chips. Depth, where a shape wants any, comes from SoftBrutalist.soften()
## rather than from a StyleBoxFlat shadow.
static func rounded(fill: Color, border: Color, border_width := 1,
		radius := RetroWindow.RADIUS) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(border_width)
	box.set_corner_radius_all(radius)
	# Tighter than the 1.0 a full card uses: at a 1px border the default
	# feather eats most of the stroke and the hairline reads as a smudge.
	box.anti_aliasing_size = 0.5
	return box


# ── Dev tool shell ───────────────────────────────────────────────────
# The animation viewer, the ML page and the ragdoll lab are one family:
# parchment panels with a hard offset shadow, square buttons, sunken
# metric cards. Each used to carry its own copy of these builders, and
# the copies had drifted (26 and 30 px buttons, 20 and 30 px card values,
# three slider rows with three label widths). They live here now, so a
# change to the dev look is one edit.

const DEV_EDGE := 8.0            ## panel inset from the window edge
const DEV_PAD := 12.0            ## inside a panel
const DEV_GAP := 8               ## between sections
const DEV_ROW_GAP := 4           ## between rows of one section
const DEV_SHADOW := 4.0
const DEV_BUTTON_HEIGHT := 28.0
const DEV_LABEL_WIDTH := 72.0    ## a slider row's caption column
const DEV_VALUE_WIDTH := 64.0    ## a slider row's readout column ("135° B-R", "6.0 m/s")
## Room left under a docked panel for the key-hint bar.
const DEV_HINT_CLEARANCE := 48.0

## Captions on parchment. TEXT_MUTED is 2.9:1 there and 2:1 on a metric
## card; this is 6.8:1 and 4.6:1.
const TEXT_CAPTION := Color("#4A4E48")


## Flat fill, hard border, square corners, optional hard offset shadow.
static func dev_box(fill: Color, border_w := 2, shadow := 0.0, margin := 8.0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fill
	s.border_color = RetroWindow.BORDER
	s.set_border_width_all(border_w)
	s.set_corner_radius_all(0)
	s.set_content_margin_all(margin)
	if shadow > 0.0:
		s.shadow_color = Color(0, 0, 0, 0.55)
		s.shadow_size = 1
		s.shadow_offset = Vector2(shadow, shadow)
	return s


## The rust outline a focused dev control wears.
static func dev_focus_box(expand := 3.0) -> StyleBoxFlat:
	var focus := dev_box(Color(0, 0, 0, 0), 2, 0.0, 0.0)
	focus.border_color = ACCENT
	focus.set_expand_margin_all(expand)
	focus.draw_center = false
	return focus


## The parchment shell every dev panel sits in. Carries dev_theme(), so
## sliders, spin boxes and dropdowns inside it match the buttons.
static func dev_panel(pad := DEV_PAD) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override(&"panel", dev_box(Color(RetroWindow.PANEL), 2, DEV_SHADOW, pad))
	panel.theme = dev_theme()
	return panel


static var _dev_theme: Theme = null

## Stock controls in the dev look: the engine's default dark-grey slider
## track, dropdown and spin box read as a different app on parchment.
static func dev_theme() -> Theme:
	if _dev_theme != null:
		return _dev_theme
	var t := Theme.new()
	var base := Color(RetroWindow.PANEL)

	var track := StyleBoxFlat.new()
	track.bg_color = Color(RetroWindow.BORDER, 0.35)
	track.set_content_margin_all(3.0)
	var filled := StyleBoxFlat.new()
	filled.bg_color = ACCENT
	filled.set_content_margin_all(3.0)
	t.set_stylebox(&"slider", &"HSlider", track)
	t.set_stylebox(&"grabber_area", &"HSlider", filled)
	t.set_stylebox(&"grabber_area_highlight", &"HSlider", filled)
	t.set_stylebox(&"focus", &"HSlider", dev_focus_box(2.0))

	for type: StringName in [&"OptionButton", &"LineEdit"]:
		t.set_font_size(&"font_size", type, SIZE_SUBTITLE)
		t.set_color(&"font_color", type, TEXT_PRIMARY)
		t.set_stylebox(&"focus", type, dev_focus_box(2.0))
	t.set_stylebox(&"normal", &"OptionButton", dev_box(base.lightened(0.08), 2, 0.0, 6.0))
	t.set_stylebox(&"hover", &"OptionButton", dev_box(base.lightened(0.18), 2, 0.0, 6.0))
	t.set_stylebox(&"pressed", &"OptionButton", dev_box(base.darkened(0.1), 2, 0.0, 6.0))
	t.set_color(&"font_hover_color", &"OptionButton", TEXT_PRIMARY)
	t.set_color(&"font_pressed_color", &"OptionButton", TEXT_PRIMARY)
	t.set_color(&"font_focus_color", &"OptionButton", TEXT_PRIMARY)
	t.set_color(&"font_hover_pressed_color", &"OptionButton", TEXT_PRIMARY)
	t.set_stylebox(&"normal", &"LineEdit", dev_box(base.darkened(0.1), 2, 0.0, 4.0))
	t.set_color(&"caret_color", &"LineEdit", TEXT_PRIMARY)
	t.set_font(&"font", &"LineEdit", SoftBrutalist.numeric_font(WEIGHT_REGULAR))
	_dev_theme = t
	return t


## Square dev button. Tab and the d-pad walk these in build order and the
## focused one shows a rust outline; a mouse click doesn't keep the focus,
## so a screen's own key shortcuts (the lab's Space = push) still reach it
## after a click.
static func dev_button(text: String, toggle := false) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = toggle
	b.custom_minimum_size.y = DEV_BUTTON_HEIGHT
	var base := Color(RetroWindow.PANEL)
	b.add_theme_stylebox_override(&"normal", dev_box(base.lightened(0.08), 2, 3.0, 6.0))
	b.add_theme_stylebox_override(&"hover", dev_box(base.lightened(0.18), 2, 3.0, 6.0))
	b.add_theme_stylebox_override(&"pressed", dev_box(Color(ACCENT), 2, 0.0, 6.0))
	b.add_theme_stylebox_override(&"hover_pressed", dev_box(Color(ACCENT), 2, 0.0, 6.0))
	b.add_theme_stylebox_override(&"disabled", dev_box(base.darkened(0.06), 1, 0.0, 6.0))
	b.add_theme_stylebox_override(&"focus", dev_focus_box())
	b.add_theme_font_size_override(&"font_size", SIZE_SUBTITLE)
	b.add_theme_color_override(&"font_color", TEXT_PRIMARY)
	b.add_theme_color_override(&"font_hover_color", TEXT_PRIMARY)
	b.add_theme_color_override(&"font_focus_color", TEXT_PRIMARY)
	b.add_theme_color_override(&"font_pressed_color", Color.BLACK)
	b.add_theme_color_override(&"font_hover_pressed_color", Color.BLACK)
	b.add_theme_color_override(&"font_disabled_color", Color(TEXT_CAPTION, 0.7))
	dev_drop_mouse_focus(b)
	return b


## Lets go of the focus a mouse click gave `control` (see dev_button).
static func dev_drop_mouse_focus(control: Control) -> void:
	control.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and not event.pressed:
			control.release_focus.call_deferred())


## A row of equal-width buttons: [[text, callable], ...]. With `group`
## they are a radio set and `selected` is the one pressed at the start.
static func dev_button_row(entries: Array, group: ButtonGroup = null, selected := -1) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 6)
	for i in entries.size():
		var b := dev_button(entries[i][0], group != null)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if group != null:
			b.button_group = group
			b.button_pressed = i == selected
		b.pressed.connect(entries[i][1])
		row.add_child(b)
	return row


## Sunken card: a caption over one live value in tabular figures, which
## trims rather than widening its panel. Returns {node, value_label}.
static func dev_metric_card(caption: String) -> Dictionary:
	var box := PanelContainer.new()
	box.add_theme_stylebox_override(&"panel", dev_box(Color(RetroWindow.PANEL).darkened(0.18), 2, 0.0, 6.0))
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 0)
	box.add_child(col)
	col.add_child(label(caption, SIZE_HINT, TEXT_CAPTION, WEIGHT_BOLD, TRACK_LABEL))
	var value := label("—", SoftBrutalist.SIZE_HEADING, TEXT_PRIMARY)
	value.add_theme_font_override(&"font", SoftBrutalist.numeric_font(WEIGHT_BOLD))
	value.clip_text = true
	value.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	col.add_child(value)
	return {"node": box, "value_label": value}


static func dev_heading(text: String) -> Label:
	return label(text.to_upper(), SIZE_SUBTITLE, TEXT_CAPTION, WEIGHT_BOLD, TRACK_LABEL)


static func dev_caption(text: String, wrap := false) -> Label:
	var l := label(text, SIZE_SUBTITLE, TEXT_CAPTION)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


## A block of live numbers: fixed-pitch, so "%-8s %6.2f" columns line up
## and nothing shuffles sideways as a value changes.
static func dev_readout(text := "") -> Label:
	var l := label(text, SIZE_SUBTITLE, TEXT_PRIMARY)
	l.add_theme_font_override(&"font", dev_mono_font())
	return l


static var _dev_mono: Font = null

## Fixed-pitch face for dev readouts, asked of the OS by name. Named faces
## first: the generic "monospace" family alone resolves to Courier New on
## Windows, which is too thin to read at 13 px on parchment.
static func dev_mono_font() -> Font:
	if _dev_mono == null:
		var system := SystemFont.new()
		system.font_names = PackedStringArray(["Consolas", "Cascadia Mono", "DejaVu Sans Mono", "Menlo", "monospace"])
		_dev_mono = system
	return _dev_mono


## The decimals a slider's readout needs to show one step.
static func dev_step_format(step: float) -> String:
	if step >= 1.0:
		return "%.0f"
	if step >= 0.1:
		return "%.1f"
	return "%.2f" if step >= 0.01 else "%.3f"


## Caption / slider / readout. `on_change` gets the new value; `format`
## turns a value into the readout's text (default: the step's decimals).
## Returns {node, slider, value_label}.
static func dev_slider_row(caption: String, min_value: float, max_value: float, step: float,
		value: float, on_change := Callable(), format := Callable(),
		value_width := DEV_VALUE_WIDTH) -> Dictionary:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 8)

	var caption_label := label(caption.to_upper(), SIZE_SUBTITLE, TEXT_CAPTION)
	caption_label.custom_minimum_size.x = DEV_LABEL_WIDTH
	caption_label.clip_text = true
	row.add_child(caption_label)

	var slider := HSlider.new()
	slider.min_value = min_value
	slider.max_value = max_value
	slider.step = step
	slider.value = value
	slider.custom_minimum_size.x = 60.0
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.tooltip_text = caption
	dev_drop_mouse_focus(slider)
	row.add_child(slider)

	var pattern := dev_step_format(step)
	var text_for := func(v: float) -> String:
		return String(format.call(v)) if format.is_valid() else pattern % v
	var value_label := label(text_for.call(value), SIZE_SUBTITLE, TEXT_PRIMARY)
	value_label.add_theme_font_override(&"font", SoftBrutalist.numeric_font(WEIGHT_REGULAR))
	value_label.custom_minimum_size.x = value_width
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value_label)

	slider.value_changed.connect(func(v: float) -> void:
		value_label.text = text_for.call(v)
		if on_change.is_valid():
			on_change.call(v))
	return {"node": row, "slider": slider, "value_label": value_label}


## "135° B-R": the bearing convention the viewer's APPROACH FROM and the
## lab's IMPACT FROM share (0 = from in front, 90 = from the right).
static func dev_bearing(deg: float) -> String:
	const NAMES := ["FRONT", "F-R", "RIGHT", "B-R", "BACK", "B-L", "LEFT", "F-L"]
	return "%d° %s" % [roundi(deg), NAMES[roundi(deg / 45.0) % 8]]


## Sizes a docked panel to its content, capping the scroll area inside it
## at the room above the key-hint bar; past that it scrolls. Call it again
## when the window resizes or the scrolled content changes.
static func dev_fit_scroll(panel: Control, scroll: ScrollContainer, content: Control) -> void:
	scroll.custom_minimum_size.y = 0.0
	var fixed := panel.get_combined_minimum_size().y
	var available := panel.get_viewport_rect().size.y - panel.position.y - DEV_HINT_CLEARANCE - fixed
	if scroll.is_visible_in_tree():
		scroll.custom_minimum_size.y = minf(content.get_combined_minimum_size().y, maxf(available, 120.0))
	panel.reset_size()


## Keyboard / controller way in: with nothing focused, Tab or a d-pad
## up/down lands on `first`. Returns true if it took the event.
static func dev_focus_entry(viewport: Viewport, event: InputEvent, first: Control) -> bool:
	if first == null or viewport.gui_get_focus_owner() != null or not first.is_visible_in_tree():
		return false
	for action: StringName in [&"ui_focus_next", &"ui_down", &"ui_up"]:
		if event.is_action_pressed(action):
			first.grab_focus()
			viewport.set_input_as_handled()
			return true
	return false
