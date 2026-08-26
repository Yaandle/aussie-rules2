class_name MainMenu
extends CanvasLayer

## Mode-select screen (design doc §7's front door).
##
## One reusable keyboard/gamepad-navigable list, matching Prototype 1's
## menu.py pattern: left/right moves a card index, Enter/accept selects, a
## locked row is shown muted with a LOCKED tag and Enter is a no-op on
## it. P1 kept exactly one such list component and had render.py mirror it
## for drawing; here there is only one place the rows are defined (_entries
## below) and the cards draw directly from it, so there is nothing to keep
## in sync.
##
## Cards are photo tiles (reference: a greyscale/muted tile at rest, full
## colour on the selected one, both clipped to a rounded rect by
## assets/shaders/menu_card_image.gdshader) rather than the flat Soft
## Brutalist text cards the rest of the project uses — see that shader's
## header for why a shader owns the rounding+colour blend instead of a
## StyleBoxFlat. Everything else on the screen (header/footer chrome,
## panel frame behind each card) is still plain SoftBrutalist.
##
## Card artwork lives in assets/textures/images/ (menuscreen_ball.png ->
## FULL GAME, menuscreen_board.png -> SCENARIO, menuscreen_field.png ->
## GOAL KICKING). `_find_card_image()` looks there for `<image_key>.
## <jpg|jpeg|png|webp>` and falls back to a flat tinted placeholder if a
## file is missing, so the screen still renders correctly either way.
## Source images are cover-cropped by the shader rather than stretched,
## so they need no particular aspect ratio.
##
## ── Layout ──────────────────────────────────────────────────────────
## Everything is in containers, and no band knows the screen size. The
## screen is four stacked bands inside one MarginContainer — corner
## chrome, header, cards, footer — with the card band as the only one
## that expands, so it takes exactly the space the other three leave and
## the cards can never grow into the footer.
##
## The previous revision positioned every band from hardcoded 1280x720
## constants, which put the card row's measured bottom (~674px, and ~681
## once the selected card's scale-up is counted) below the footer's top
## at 666 — the cards overlapped the hint text on every frame, and the
## right-hand chrome was placed by subtracting a guessed label width from
## the screen edge, so it never lined up with the left-hand chrome. Both
## classes of bug are unreachable from a container layout, which is the
## actual reason for the rewrite.

class Entry:
	var title: String
	var subtitle: String
	var scene_path: String
	var unlocked: bool
	var image_key: String

	func _init(p_title: String, p_subtitle: String, p_scene_path: String, p_unlocked: bool,
			p_image_key: String) -> void:
		title = p_title
		subtitle = p_subtitle
		scene_path = p_scene_path
		unlocked = p_unlocked
		image_key = p_image_key


var _entries: Array[Entry] = [
	Entry.new("FULL GAME", "4-a-side, real clock, quarters, scoring",
		"res://scenes/ui/full_game_pregame_screen.tscn", true, "menuscreen_field"),
	Entry.new("SCENARIO", "Practice a set situation", "", false, "menuscreen_board"),
	Entry.new("GOAL KICKING", "Shots on goal from the arc", "", false,
		"menuscreen_ball"),
]

var _index := 0

const TITLE_TEXT := "AUSSIE RULES 2"
const SUBTITLE_TEXT := "CHOOSE YOUR GAME MODE"
const LOCKED_SUBTITLE := "Not built yet"
const ESTABLISHED_TEXT := "EST. 2025"
## Placeholder — the project has no build-version source yet; update this
## by hand until one exists.
const VERSION_TEXT := "v0.1.0"

## Control legend, in the same chip form the character screen uses
## (KeyHintBar) rather than this screen's old single run-on sentence —
## one legend treatment across the front end, and four short pairs read
## at a glance where a 78-character line did not.
const HINTS := [
	{"keys": "A / D", "label": "Choose"},
	{"keys": "Enter", "label": "Select"},
	{"keys": "C", "label": "Character"},
	{"keys": "T", "label": "Team"},
]

const IMAGE_DIR := "res://assets/textures/images/"
const IMAGE_EXTENSIONS := ["jpg", "jpeg", "png", "webp"]

# ── Layout ───────────────────────────────────────────────────────────
# Sizes on SoftBrutalist's 8px spacing step. Only minimums and gaps are
# fixed; the card band's actual size comes from what the layout leaves.
const SCREEN_MARGIN_X := SoftBrutalist.SPACE_6      ## 56
const SCREEN_MARGIN_Y := SoftBrutalist.SPACE_4      ## 32
const BAND_GAP := int(SoftBrutalist.SPACE_4)        ## 32
const CHROME_HEIGHT := 20.0
const FOOTER_HEIGHT := 28.0
const CARD_SEPARATION := int(SoftBrutalist.SPACE_3) ## 24
## Smaller than a full-bleed hero tile on purpose — these sit centred over
## the live 3D backdrop (menu_backdrop.tscn) with room left on every side,
## so the montage behind them stays visible rather than getting crowded out.
const CARD_MIN_WIDTH := 190.0
const CARD_MIN_HEIGHT := 235.0
const CARD_PAD := SoftBrutalist.SPACE_2             ## 16
## Sharp, matching RetroWindow's unrounded shell — the mode-select cards
## now read as the same "windowed retro console" family as the rest of
## the front end's borders (settings/pause/team-list/remap/character).
## menu_card_image.gdshader's own `radius` uniform is fed this same
## constant (see _build_card()), since its rounded-rect clip has to agree
## with the StyleBoxFlat border sitting on top of it.
const CARD_RADIUS := RetroWindow.RADIUS
## Bolder than SoftBrutalist.BORDER_WIDTH (2) to read as a deliberate
## retro rule against the photo underneath, short of RetroWindow's full
## card-scale 4px — these are small tiles, not a full window shell.
const CARD_BORDER_WIDTH := 3
const ARROW_BADGE_SIZE := 28.0
const TEXT_BLOCK_HEIGHT := 62.0

## Shader saturation / border / shadow-offset tween length — longer than
## SoftBrutalist's button-hover transitions (0.12-0.18s) since this is the
## screen's one deliberately noticeable "small animation", not an instant
## state snap.
const CARD_ANIM_DURATION := 0.22
const CARD_ANIM_TRANS := Tween.TRANS_CUBIC
const CARD_ANIM_EASE := Tween.EASE_OUT

## The scale tween alone runs on a back-out curve (a slight overshoot past
## the target before settling) rather than CARD_ANIM_TRANS/EASE above — a
## plain cubic ease-out gets a card to its target size smoothly but never
## reads as a "pop", since it never goes past where it's headed. TRANS_BACK
## does, which is the whole difference between "resizes" and "pops out".
const CARD_POP_TRANS := Tween.TRANS_BACK
const CARD_POP_EASE := Tween.EASE_OUT
## Bigger than the old 1.025 now that the pop has its own overshoot curve
## to sell it — at the old scale plus TRANS_BACK the overshoot itself was
## barely visible.
const CARD_SELECTED_SCALE := 1.07

## Hard offset "brutalist" shadow (see CARD_SHADOW_COLOR below) — a solid
## black rect sitting behind the card, not SoftBrutalist's blurred one.
## The offset grows on selection, which combined with the scale-up above
## is what sells "this card lifted off the page" rather than just "this
## card got a bit bigger".
const CARD_SHADOW_COLOR := Color(0.0, 0.0, 0.0, 1.0)
const CARD_SHADOW_OFFSET_IDLE := Vector2(5.0, 5.0)
const CARD_SHADOW_OFFSET_SELECTED := Vector2(12.0, 12.0)

## How far an unselected card sits along menu_card_image.gdshader's ramp
## toward its flat muted tint. Locked goes further — flatter and quieter,
## not darker.
const DIM_UNSELECTED := 0.34
const DIM_LOCKED := 0.58

## Opacity of the cream wash over the 3D camera montage (menu_backdrop.tscn)
## — high enough that chrome text stays legible, low enough that the
## montage still reads as a background rather than a hidden layer.
const BACKDROP_OVERLAY_ALPHA := 0.6

class CardWidgets:
	var frame: Control
	var image: TextureRect
	var material: ShaderMaterial
	var border: Panel
	var shadow: Panel
	var arrow_icon: UIIcon
	var arrow_badge: Panel

var _cards: Array[CardWidgets] = []
var _placeholder_tints := [SoftBrutalist.ACCENT_SECONDARY, SoftBrutalist.MUTED,
	SoftBrutalist.ACCENT_PRIMARY]


func _ready() -> void:
	GameState.mode = GameState.Mode.SANDBOX
	GameState.phase = GameState.Phase.MENU
	_build()
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"character_menu"):
		SceneWipe.change_scene("res://scenes/ui/character_screen.tscn")
	elif event.is_action_pressed(&"team_menu"):
		SceneWipe.change_scene("res://scenes/ui/team_list_screen.tscn")
	elif event.is_action_pressed(&"move_left") or event.is_action_pressed(&"ui_left") \
			or event.is_action_pressed(&"move_forward") or event.is_action_pressed(&"ui_up"):
		_move(-1)
	elif event.is_action_pressed(&"move_right") or event.is_action_pressed(&"ui_right") \
			or event.is_action_pressed(&"move_back") or event.is_action_pressed(&"ui_down"):
		_move(1)
	elif event.is_action_pressed(&"ui_accept") or _is_gamepad_a_press(event):
		_select()


## ui_accept's built-in default binding already includes joypad button 0,
## but every other action a player's thumb rests on this screen
## (character_menu/team_menu, plus mark_safe/confirm elsewhere in the
## project) is bound explicitly in project.godot rather than left to an
## engine default — this checks the physical A/Cross press directly too,
## so selecting the highlighted card doesn't depend on ui_accept's
## default surviving whatever InputMap state this screen is reached in.
func _is_gamepad_a_press(event: InputEvent) -> bool:
	return event is InputEventJoypadButton and event.is_pressed() \
		and (event as InputEventJoypadButton).button_index == JOY_BUTTON_A


func _move(step: int) -> void:
	_index = (_index + step + _entries.size()) % _entries.size()
	_refresh()


func _select() -> void:
	var entry := _entries[_index]
	if not entry.unlocked:
		return
	SceneWipe.change_scene(entry.scene_path)


# ── Build ────────────────────────────────────────────────────────────

func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# Translucent, not opaque: menu_backdrop.tscn's camera montage renders
	# behind this in the SubViewportContainer laid out in main_menu.tscn,
	# and this wash just needs to knock the footage back enough that ink
	# text and the card frames stay legible over it.
	root.add_child(SoftBrutalist.backdrop(BACKDROP_OVERLAY_ALPHA))

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override(&"margin_left", int(SCREEN_MARGIN_X))
	margin.add_theme_constant_override(&"margin_right", int(SCREEN_MARGIN_X))
	margin.add_theme_constant_override(&"margin_top", int(SCREEN_MARGIN_Y))
	margin.add_theme_constant_override(&"margin_bottom", int(SCREEN_MARGIN_Y))
	root.add_child(margin)

	var bands := VBoxContainer.new()
	bands.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bands.add_theme_constant_override(&"separation", BAND_GAP)
	margin.add_child(bands)

	_build_corner_chrome(bands)
	_build_header(bands)
	_build_card_row(bands)
	_build_footer(bands)


## EST. 2025 on the left, version on the right, both on the screen's own
## margin. An HBox with a spacer between them, rather than the old pair of
## anchored labels offset by a guessed text width — a guess that put the
## version tag 35px short of where the left-hand tag started from its own
## edge, which is exactly the kind of near-miss the brief flags.
func _build_corner_chrome(parent: Control) -> void:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.custom_minimum_size.y = CHROME_HEIGHT
	parent.add_child(row)

	row.add_child(SoftBrutalist.label(ESTABLISHED_TEXT, SoftBrutalist.SIZE_LABEL,
		SoftBrutalist.MUTED, SoftBrutalist.WEIGHT_BOLD, SoftBrutalist.TRACK_LABEL))

	var spacer := Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	row.add_child(SoftBrutalist.label(VERSION_TEXT, SoftBrutalist.SIZE_LABEL,
		SoftBrutalist.MUTED, SoftBrutalist.WEIGHT_BOLD, SoftBrutalist.TRACK_LABEL))


func _build_header(parent: Control) -> void:
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override(&"separation", int(SoftBrutalist.SPACE_1))
	parent.add_child(column)

	var title := SoftBrutalist.label(TITLE_TEXT, SoftBrutalist.SIZE_DISPLAY, SoftBrutalist.INK,
		SoftBrutalist.WEIGHT_HEAVY, SoftBrutalist.TRACK_DISPLAY)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)

	var subtitle := SoftBrutalist.label(SUBTITLE_TEXT, SoftBrutalist.SIZE_LABEL,
		SoftBrutalist.MUTED, SoftBrutalist.WEIGHT_BOLD, SoftBrutalist.TRACK_TITLE)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(subtitle)


func _build_card_row(parent: Control) -> void:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# The one band that expands: it absorbs whatever height the chrome,
	# header and footer do not use, so the cards are sized by the layout
	# rather than by a constant that has to be kept in step with it.
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# Cards are shrink-sized (see _build_card), so without this they would
	# bunch against the row's left edge instead of sitting in the middle of
	# the space the band leaves for them.
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override(&"separation", CARD_SEPARATION)
	parent.add_child(row)

	for i in _entries.size():
		var widgets := _build_card(_entries[i], i)
		row.add_child(widgets.frame)
		_cards.append(widgets)


## SETTINGS on the left margin, the control legend centred, EXIT GAME on
## the right margin — the expanding legend in the middle is what pins the
## two actions to the screen's own margins instead of to a hardcoded
## offset.
func _build_footer(parent: Control) -> void:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.custom_minimum_size.y = FOOTER_HEIGHT
	row.add_theme_constant_override(&"separation", int(SoftBrutalist.SPACE_3))
	parent.add_child(row)

	row.add_child(_build_footer_action(&"gear", "SETTINGS",
		func() -> void: SceneWipe.change_scene("res://scenes/ui/settings_screen.tscn")))

	var hints := KeyHintBar.new()
	hints.alignment = BoxContainer.ALIGNMENT_CENTER
	hints.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hints.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(hints)
	hints.set_hints(HINTS)

	row.add_child(_build_footer_action(&"exit", "EXIT GAME",
		func() -> void: get_tree().quit()))


## Mouse-only footer action (SETTINGS / EXIT GAME): the screen's real
## navigation model is keyboard-only (left/right over the three cards, per
## the rest of the project's screens), and these two rows are not part of
## that card cursor — no new input actions were added for them, so a
## keyboard/gamepad user simply cannot reach them yet. Click-only until
## there is a reason to spend a new action binding on them.
func _build_footer_action(icon_name: StringName, text: String, on_click: Callable) -> Control:
	# HBoxContainer sized to its own content rather than a Control with a
	# guessed 140px width — the old fixed width left the label floating
	# short of the margin it was meant to sit on.
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", int(SoftBrutalist.SPACE_1))
	row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	var icon := UIIcon.new()
	icon.icon_name = icon_name
	icon.line_colour = SoftBrutalist.MUTED
	icon.custom_minimum_size = Vector2(18.0, 18.0)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)

	var label := SoftBrutalist.label(text, SoftBrutalist.SIZE_LABEL, SoftBrutalist.MUTED,
		SoftBrutalist.WEIGHT_BOLD, SoftBrutalist.TRACK_LABEL)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)

	row.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed \
				and event.button_index == MOUSE_BUTTON_LEFT:
			on_click.call())
	row.mouse_entered.connect(func() -> void:
		icon.line_colour = SoftBrutalist.INK
		label.add_theme_color_override(&"font_color", SoftBrutalist.INK))
	row.mouse_exited.connect(func() -> void:
		icon.line_colour = SoftBrutalist.MUTED
		label.add_theme_color_override(&"font_color", SoftBrutalist.MUTED))
	return row


func _build_card(entry: Entry, index: int) -> CardWidgets:
	var widgets := CardWidgets.new()

	var frame := Control.new()
	frame.custom_minimum_size = Vector2(CARD_MIN_WIDTH, CARD_MIN_HEIGHT)
	# Shrink to that minimum rather than filling the row/band — the whole
	# point of a smaller card is that the live backdrop shows around it, not
	# just that its own artwork is smaller while still stretching to fill.
	frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	widgets.frame = frame

	# Hard offset "brutalist" shadow — a solid black Panel added as the
	# frame's first child (so everything built after it draws on top),
	# anchored full-rect and then pushed down-right by CARD_SHADOW_OFFSET_
	# IDLE via offset_left/top/right/bottom (all shifted the same amount,
	# so the rect moves rather than resizes — same technique as
	# RetroWindow._build()'s shadow). _refresh() tweens that offset out
	# further on selection instead of a blurred SoftBrutalist shadow.
	var shadow := Panel.new()
	shadow.set_anchors_preset(Control.PRESET_FULL_RECT)
	shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shadow_style := StyleBoxFlat.new()
	shadow_style.bg_color = CARD_SHADOW_COLOR
	shadow_style.set_corner_radius_all(int(CARD_RADIUS))
	shadow.add_theme_stylebox_override(&"panel", shadow_style)
	_set_card_shadow_offset(shadow, CARD_SHADOW_OFFSET_IDLE)
	frame.add_child(shadow)
	widgets.shadow = shadow

	var image := TextureRect.new()
	image.set_anchors_preset(Control.PRESET_FULL_RECT)
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# EXPAND_IGNORE_SIZE, and this is not optional. TextureRect defaults
	# to EXPAND_KEEP_SIZE, which reports the *source texture* as the
	# node's minimum size — and Control.size clamps up to the minimum, so
	# the anchors asking for the card rect were silently overruled by the
	# artwork's own 575x887. That is the "images extend outside their
	# containers" the brief opens with: all three photos were drawing ~250px
	# past the bottom of their cards, straight over the footer.
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	var texture := _find_card_image(entry.image_key)
	if texture == null:
		texture = _placeholder_texture(_placeholder_tints[index % _placeholder_tints.size()])
	image.texture = texture

	var material := ShaderMaterial.new()
	material.shader = load("res://assets/shaders/menu_card_image.gdshader")
	material.set_shader_parameter(&"radius", float(CARD_RADIUS))
	# Seeded from the minimum so the first drawn frame is already clipped
	# correctly; the resized handler below takes over from the layout.
	material.set_shader_parameter(&"rect_size", Vector2(CARD_MIN_WIDTH, CARD_MIN_HEIGHT))
	material.set_shader_parameter(&"saturation", 0.0)
	material.set_shader_parameter(&"dim", DIM_LOCKED if not entry.unlocked else DIM_UNSELECTED)
	material.set_shader_parameter(&"image", texture)
	material.set_shader_parameter(&"image_size", Vector2(texture.get_size()))
	image.material = material
	frame.add_child(image)
	widgets.image = image
	widgets.material = material

	# Anchored to the card's bottom edge with a gap kept clear on the
	# right for the arrow badge, so the text block reflows with the card
	# instead of being placed at a fixed offset from a fixed card size.
	var text_column := VBoxContainer.new()
	text_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_column.add_theme_constant_override(&"separation", 4)
	text_column.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	text_column.grow_vertical = Control.GROW_DIRECTION_BEGIN
	text_column.offset_left = CARD_PAD
	text_column.offset_right = -(CARD_PAD + ARROW_BADGE_SIZE + SoftBrutalist.SPACE_2)
	text_column.offset_top = -(TEXT_BLOCK_HEIGHT + CARD_PAD)
	text_column.offset_bottom = -CARD_PAD
	text_column.alignment = BoxContainer.ALIGNMENT_END
	frame.add_child(text_column)

	var title_label := SoftBrutalist.label(entry.title, SoftBrutalist.SIZE_HEADING, Color.WHITE,
		SoftBrutalist.WEIGHT_HEAVY, SoftBrutalist.TRACK_LABEL)
	text_column.add_child(title_label)

	if entry.unlocked:
		var subtitle_label := SoftBrutalist.label(entry.subtitle, SoftBrutalist.SIZE_LABEL,
			Color(1.0, 1.0, 1.0, 0.78), SoftBrutalist.WEIGHT_REGULAR, SoftBrutalist.TRACK_LABEL)
		subtitle_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text_column.add_child(subtitle_label)
	else:
		# One line, not the three the locked cards used to carry (a lock
		# row, the word LOCKED, and a separate "Not built yet"). Three
		# stacked lines of chrome on a card with nothing behind it is the
		# noisiest thing on the screen and says one thing.
		var lock_row := HBoxContainer.new()
		lock_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lock_row.add_theme_constant_override(&"separation", 6)
		text_column.add_child(lock_row)

		var lock_icon := UIIcon.new()
		lock_icon.icon_name = &"lock"
		lock_icon.line_colour = Color(1.0, 1.0, 1.0, 0.8)
		lock_icon.custom_minimum_size = Vector2(13.0, 13.0)
		lock_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		lock_row.add_child(lock_icon)

		var lock_label := SoftBrutalist.label(LOCKED_SUBTITLE, SoftBrutalist.SIZE_LABEL,
			Color(1.0, 1.0, 1.0, 0.8), SoftBrutalist.WEIGHT_REGULAR, SoftBrutalist.TRACK_LABEL)
		lock_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lock_row.add_child(lock_label)

	widgets.arrow_badge = _build_icon_badge(&"arrow_right", ARROW_BADGE_SIZE)
	widgets.arrow_badge.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	widgets.arrow_badge.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	widgets.arrow_badge.grow_vertical = Control.GROW_DIRECTION_BEGIN
	widgets.arrow_badge.position = Vector2(-(CARD_PAD + ARROW_BADGE_SIZE),
		-(CARD_PAD + ARROW_BADGE_SIZE))
	widgets.arrow_icon = widgets.arrow_badge.get_child(0) as UIIcon
	frame.add_child(widgets.arrow_badge)

	# Border drawn last, on top of everything: a transparent-fill StyleBox
	# with just the edge + rounded corners, so the frame reads as crisp
	# and unbroken regardless of what the photo underneath is doing.
	var border := Panel.new()
	border.set_anchors_preset(Control.PRESET_FULL_RECT)
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	border.add_theme_stylebox_override(&"panel", _border_style(RetroWindow.BORDER))
	frame.add_child(border)
	widgets.border = border

	# The card's pixel size is decided by the layout, and the image shader
	# needs it to do its rounded clip and cover-crop. Pivot for the
	# selection scale-up has to follow it too, or the card would grow from
	# its top-left corner.
	frame.resized.connect(func() -> void:
		material.set_shader_parameter(&"rect_size", frame.size)
		frame.pivot_offset = frame.size * 0.5)

	return widgets


func _build_icon_badge(icon_name: StringName, badge_size: float) -> Panel:
	var badge := Panel.new()
	badge.custom_minimum_size = Vector2(badge_size, badge_size)
	badge.size = Vector2(badge_size, badge_size)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1.0, 1.0, 1.0, 0.94)
	style.set_corner_radius_all(int(badge_size * 0.5))
	style.anti_aliasing_size = 1.0
	badge.add_theme_stylebox_override(&"panel", style)

	var icon := UIIcon.new()
	icon.icon_name = icon_name
	icon.line_colour = SoftBrutalist.INK
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	var inset := badge_size * 0.26
	icon.offset_left = inset
	icon.offset_top = inset
	icon.offset_right = -inset
	icon.offset_bottom = -inset
	badge.add_child(icon)
	return badge


## Transparent-fill variant of SoftBrutalist.panel_style() — the shared
## helper always fills solid, which would hide the photo it is layered
## over here. Carries no shadow either: the card's depth comes from the
## SoftShadow attached to its frame.
func _border_style(border_colour: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0, 0, 0, 0)
	box.border_color = border_colour
	box.set_border_width_all(CARD_BORDER_WIDTH)
	box.set_corner_radius_all(CARD_RADIUS)
	box.anti_aliasing_size = 1.0
	return box


## Shifts `shadow` (anchored full-rect) down-right by `offset` without
## resizing it — offset_right/offset_bottom add directly rather than being
## negated, so all four edges move by the same amount. Shared by the
## build-time idle pose and _refresh()'s tween target.
func _set_card_shadow_offset(shadow: Panel, offset: Vector2) -> void:
	shadow.offset_left = offset.x
	shadow.offset_right = offset.x
	shadow.offset_top = offset.y
	shadow.offset_bottom = offset.y


func _find_card_image(image_key: String) -> Texture2D:
	for ext in IMAGE_EXTENSIONS:
		var path := "%s%s.%s" % [IMAGE_DIR, image_key, ext]
		if ResourceLoader.exists(path):
			return load(path)
	return null


func _placeholder_texture(tint: Color) -> ImageTexture:
	var image := Image.create(8, 8, false, Image.FORMAT_RGB8)
	image.fill(tint)
	return ImageTexture.create_from_image(image)


# ── Refresh ──────────────────────────────────────────────────────────

func _refresh() -> void:
	for i in _entries.size():
		var entry := _entries[i]
		var selected := i == _index
		var widgets := _cards[i]
		var live := selected and entry.unlocked

		var target_saturation := 1.0 if live else 0.0
		var target_scale := CARD_SELECTED_SCALE if live else 1.0
		var target_border := RetroWindow.ACCENT if live else RetroWindow.BORDER

		# The arrow badge is the cursor. The title used to carry a "› "
		# prefix instead, which re-flowed the whole title line every time
		# the selection moved — text that shifts sideways as you scroll a
		# menu reads as a glitch, not as a cursor.
		widgets.arrow_icon.line_colour = RetroWindow.ACCENT if live \
			else SoftBrutalist.MUTED

		# Shadow offset follows `selected` (cursor is here), independent of
		# `live` (also unlocked) — a locked card still gets the "lifted"
		# shadow when the cursor sits on it, same as the old blurred-shadow
		# elevation used to, it just never saturates/scales/borders.
		var target_shadow_offset := CARD_SHADOW_OFFSET_SELECTED if selected \
			else CARD_SHADOW_OFFSET_IDLE

		var tween := widgets.frame.create_tween()
		tween.set_trans(CARD_ANIM_TRANS)
		tween.set_ease(CARD_ANIM_EASE)
		tween.set_parallel(true)
		tween.tween_property(widgets.material, "shader_parameter/saturation",
			target_saturation, CARD_ANIM_DURATION)
		# The pop: its own back-out curve, overshooting target_scale before
		# settling — see CARD_POP_TRANS's own comment.
		tween.tween_property(widgets.frame, "scale", Vector2.ONE * target_scale,
			CARD_ANIM_DURATION).set_trans(CARD_POP_TRANS).set_ease(CARD_POP_EASE)
		tween.tween_property(widgets.shadow, "offset_left", target_shadow_offset.x,
			CARD_ANIM_DURATION)
		tween.tween_property(widgets.shadow, "offset_right", target_shadow_offset.x,
			CARD_ANIM_DURATION)
		tween.tween_property(widgets.shadow, "offset_top", target_shadow_offset.y,
			CARD_ANIM_DURATION)
		tween.tween_property(widgets.shadow, "offset_bottom", target_shadow_offset.y,
			CARD_ANIM_DURATION)

		var border_style: StyleBoxFlat = widgets.border.get_theme_stylebox(&"panel")
		var next_border := border_style.duplicate()
		widgets.border.add_theme_stylebox_override(&"panel", next_border)
		tween.tween_property(next_border, "border_color", target_border, CARD_ANIM_DURATION)
