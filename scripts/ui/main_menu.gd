class_name MainMenu
extends CanvasLayer

## Mode-select screen (design doc §7's front door).
##
## One reusable keyboard/gamepad-navigable list, matching Prototype 1's
## menu.py pattern: up/down moves a row index, Enter/accept selects, a
## locked row is shown muted with a " · LOCKED" tag and Enter is a no-op on
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
## Source images aren't cropped to CARD_WIDTH x CARD_HEIGHT's aspect
## (372x486) — the shader samples UV 0..1 directly rather than reflowing
## to fit, so a mismatched aspect will stretch; see _find_card_image()'s
## call site if that needs a cover-crop pass later.

class Entry:
	var title: String
	var subtitle: String
	var scene_path: String
	var unlocked: bool
	var icon_name: StringName
	var image_key: String

	func _init(p_title: String, p_subtitle: String, p_scene_path: String, p_unlocked: bool,
			p_icon_name: StringName, p_image_key: String) -> void:
		title = p_title
		subtitle = p_subtitle
		scene_path = p_scene_path
		unlocked = p_unlocked
		icon_name = p_icon_name
		image_key = p_image_key


var _entries: Array[Entry] = [
	Entry.new("FULL GAME", "4-a-side, real clock, quarters, scoring",
		"res://scenes/modes/full_game.tscn", true, &"football", "menuscreen_ball"),
	Entry.new("SCENARIO", "Practice a set situation", "", false, &"cone", "menuscreen_board"),
	Entry.new("GOAL KICKING", "Shots on goal from the arc", "", false, &"goalpost",
		"menuscreen_field"),
]

var _index := 0

const TITLE_TEXT := "AUSSIE RULES 2"
const SUBTITLE_TEXT := "CHOOSE YOUR GAME MODE"
const HINT_TEXT := "W/S or arrows to choose   Enter to select   C for character   T for team list"
const LOCKED_SUBTITLE := "Not built yet"
const ESTABLISHED_TEXT := "EST. 2025"
## Placeholder — the project has no build-version source yet; update this
## by hand until one exists.
const VERSION_TEXT := "v0.1.0"

const IMAGE_DIR := "res://assets/textures/images/"
const IMAGE_EXTENSIONS := ["jpg", "jpeg", "png", "webp"]

# ── Layout geometry, in design-resolution px (1280x720) ────────────────
const TITLE_FONT_SIZE := 40
const SUBTITLE_FONT_SIZE := 15
const CARD_WIDTH := 372.0
const CARD_HEIGHT := 486.0
const CARD_TITLE_SIZE := 20
const CARD_SUBTITLE_SIZE := 13
const CARD_PAD := 20.0
const CARD_SEPARATION := 28
const BADGE_SIZE := 46.0
const ARROW_BADGE_SIZE := 34.0
const TITLE_TO_CARDS_GAP := 34
const HINT_FONT_SIZE := 14
const CORNER_MARGIN := 40.0
const FOOTER_HEIGHT := 30.0

## Shader saturation / scale-pop tween length — longer than SoftBrutalist's
## button-hover transitions (0.12-0.18s) since this is the screen's one
## deliberately noticeable "small animation", not an instant state snap.
const CARD_ANIM_DURATION := 0.22
const CARD_ANIM_TRANS := Tween.TRANS_CUBIC
const CARD_ANIM_EASE := Tween.EASE_OUT
const CARD_SELECTED_SCALE := 1.03

const DIM_UNSELECTED := 0.28
const DIM_LOCKED := 0.5

## Opacity of the cream wash over the 3D camera montage (menu_backdrop.tscn)
## — high enough that chrome text stays legible, low enough that the
## montage still reads as a background rather than a hidden layer.
const BACKDROP_OVERLAY_ALPHA := 0.80

class CardWidgets:
	var frame: Control
	var image: TextureRect
	var material: ShaderMaterial
	var border: Panel
	var title_label: Label
	var lock_row: Control

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
	elif event.is_action_pressed(&"ui_accept"):
		_select()


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
	var background := ColorRect.new()
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.color = Color(SoftBrutalist.BACKGROUND, BACKDROP_OVERLAY_ALPHA)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(background)

	_build_corner_chrome(root)

	var content := VBoxContainer.new()
	content.set_anchors_preset(Control.PRESET_CENTER)
	content.grow_horizontal = Control.GROW_DIRECTION_BOTH
	content.grow_vertical = Control.GROW_DIRECTION_BOTH
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_theme_constant_override(&"separation", TITLE_TO_CARDS_GAP)
	root.add_child(content)

	var title := SoftBrutalist.label(TITLE_TEXT, TITLE_FONT_SIZE, SoftBrutalist.INK,
		SoftBrutalist.WEIGHT_HEAVY, SoftBrutalist.TRACK_TITLE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	content.add_child(title)

	var subtitle := SoftBrutalist.label(SUBTITLE_TEXT, SUBTITLE_FONT_SIZE, SoftBrutalist.MUTED,
		SoftBrutalist.WEIGHT_BOLD, SoftBrutalist.TRACK_TITLE)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	content.add_child(subtitle)

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	row.add_theme_constant_override(&"separation", CARD_SEPARATION)
	content.add_child(row)

	for i in _entries.size():
		var widgets := _build_card(_entries[i], i)
		row.add_child(widgets.frame)
		_cards.append(widgets)

	_build_footer(root)


func _build_corner_chrome(root: Control) -> void:
	var established := SoftBrutalist.label(ESTABLISHED_TEXT, HINT_FONT_SIZE, SoftBrutalist.MUTED,
		SoftBrutalist.WEIGHT_BOLD, SoftBrutalist.TRACK_LABEL)
	established.position = Vector2(CORNER_MARGIN, CORNER_MARGIN * 0.6)
	root.add_child(established)

	var version := SoftBrutalist.label(VERSION_TEXT, HINT_FONT_SIZE, SoftBrutalist.MUTED,
		SoftBrutalist.WEIGHT_BOLD, SoftBrutalist.TRACK_LABEL)
	version.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	version.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	version.position = Vector2(-CORNER_MARGIN - 80.0, CORNER_MARGIN * 0.6)
	root.add_child(version)


func _build_footer(root: Control) -> void:
	var settings := _build_footer_action("gear", "SETTINGS",
		func() -> void: SceneWipe.change_scene("res://scenes/ui/settings_screen.tscn"))
	settings.position = Vector2(CORNER_MARGIN, 720.0 - CORNER_MARGIN * 0.6 - FOOTER_HEIGHT)
	root.add_child(settings)

	var hint := SoftBrutalist.label(HINT_TEXT, HINT_FONT_SIZE, SoftBrutalist.MUTED,
		SoftBrutalist.WEIGHT_REGULAR, SoftBrutalist.TRACK_LABEL)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hint.position.y = -(CORNER_MARGIN * 0.6 + FOOTER_HEIGHT * 0.5 + HINT_FONT_SIZE * 0.5)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hint)

	var exit_row := _build_footer_action("exit", "EXIT GAME", func() -> void: get_tree().quit())
	exit_row.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	exit_row.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	exit_row.position = Vector2(-CORNER_MARGIN - 140.0, 720.0 - CORNER_MARGIN * 0.6 - FOOTER_HEIGHT)
	root.add_child(exit_row)


## Mouse-only footer action (SETTINGS / EXIT GAME): the screen's real
## navigation model is keyboard-only (up/down over the three cards, per
## the rest of the project's screens), and these two rows aren't part of
## that row-cursor — no new input actions were added for them, so a
## keyboard/gamepad user simply can't reach them yet. Click-only until
## there's a reason to spend a new action binding on them.
func _build_footer_action(icon_name: StringName, text: String, on_click: Callable) -> Control:
	var wrap := Control.new()
	wrap.custom_minimum_size = Vector2(140.0, FOOTER_HEIGHT)
	wrap.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override(&"separation", 8)
	wrap.add_child(row)

	var icon := UIIcon.new()
	icon.icon_name = icon_name
	icon.line_colour = SoftBrutalist.MUTED
	icon.custom_minimum_size = Vector2(18.0, 18.0)
	row.add_child(icon)

	var label := SoftBrutalist.label(text, HINT_FONT_SIZE, SoftBrutalist.MUTED,
		SoftBrutalist.WEIGHT_BOLD, SoftBrutalist.TRACK_LABEL)
	row.add_child(label)

	wrap.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed \
				and event.button_index == MOUSE_BUTTON_LEFT:
			on_click.call())
	wrap.mouse_entered.connect(func() -> void:
		icon.line_colour = SoftBrutalist.INK
		label.add_theme_color_override(&"font_color", SoftBrutalist.INK))
	wrap.mouse_exited.connect(func() -> void:
		icon.line_colour = SoftBrutalist.MUTED
		label.add_theme_color_override(&"font_color", SoftBrutalist.MUTED))
	return wrap


func _build_card(entry: Entry, index: int) -> CardWidgets:
	var widgets := CardWidgets.new()

	var frame := Control.new()
	frame.custom_minimum_size = Vector2(CARD_WIDTH, CARD_HEIGHT)
	frame.pivot_offset = Vector2(CARD_WIDTH, CARD_HEIGHT) * 0.5
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	widgets.frame = frame

	# Drop shadow behind the photo — same panel shape the rest of the
	# project's cards use, just filled with a placeholder tint that only
	# ever peeks out at the rounded corners/shadow, since the image (or
	# its own placeholder fill) covers the rest.
	var shadow := Panel.new()
	shadow.set_anchors_preset(Control.PRESET_FULL_RECT)
	shadow.add_theme_stylebox_override(&"panel", SoftBrutalist.panel_style(SoftBrutalist.PANEL))
	frame.add_child(shadow)

	var image := TextureRect.new()
	image.set_anchors_preset(Control.PRESET_FULL_RECT)
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var texture := _find_card_image(entry.image_key)
	if texture == null:
		texture = _placeholder_texture(_placeholder_tints[index % _placeholder_tints.size()])
	image.texture = texture

	var material := ShaderMaterial.new()
	material.shader = load("res://assets/shaders/menu_card_image.gdshader")
	material.set_shader_parameter(&"rect_size", Vector2(CARD_WIDTH, CARD_HEIGHT))
	material.set_shader_parameter(&"radius", float(SoftBrutalist.CORNER_RADIUS))
	material.set_shader_parameter(&"saturation", 0.0)
	material.set_shader_parameter(&"dim", DIM_LOCKED if not entry.unlocked else DIM_UNSELECTED)
	material.set_shader_parameter(&"image", texture)
	material.set_shader_parameter(&"image_size", Vector2(texture.get_size()))
	image.material = material
	frame.add_child(image)
	widgets.image = image
	widgets.material = material

	var scrim := TextureRect.new()
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scrim.stretch_mode = TextureRect.STRETCH_SCALE
	scrim.texture = _bottom_scrim_texture()
	frame.add_child(scrim)

	var badge := _build_icon_badge(entry.icon_name, BADGE_SIZE)
	badge.position = Vector2(CARD_PAD, CARD_PAD)
	frame.add_child(badge)

	var text_column := VBoxContainer.new()
	text_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_column.add_theme_constant_override(&"separation", 4)
	text_column.position = Vector2(CARD_PAD, CARD_HEIGHT - CARD_PAD - 70.0)
	text_column.size = Vector2(CARD_WIDTH - CARD_PAD * 2.0 - ARROW_BADGE_SIZE - 10.0, 70.0)
	frame.add_child(text_column)

	var title_label := SoftBrutalist.label(entry.title, CARD_TITLE_SIZE, Color.WHITE,
		SoftBrutalist.WEIGHT_HEAVY, SoftBrutalist.TRACK_LABEL)
	text_column.add_child(title_label)
	widgets.title_label = title_label

	if entry.unlocked:
		var subtitle_label := SoftBrutalist.label(entry.subtitle, CARD_SUBTITLE_SIZE,
			Color(1.0, 1.0, 1.0, 0.78), SoftBrutalist.WEIGHT_REGULAR, SoftBrutalist.TRACK_LABEL)
		subtitle_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text_column.add_child(subtitle_label)
	else:
		var lock_row := HBoxContainer.new()
		lock_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lock_row.add_theme_constant_override(&"separation", 6)
		text_column.add_child(lock_row)
		var lock_icon := UIIcon.new()
		lock_icon.icon_name = &"lock"
		lock_icon.line_colour = Color(1.0, 1.0, 1.0, 0.85)
		lock_icon.custom_minimum_size = Vector2(14.0, 14.0)
		lock_row.add_child(lock_icon)
		lock_row.add_child(SoftBrutalist.label("LOCKED", CARD_SUBTITLE_SIZE,
			Color(1.0, 1.0, 1.0, 0.85), SoftBrutalist.WEIGHT_BOLD, SoftBrutalist.TRACK_LABEL))
		text_column.add_child(SoftBrutalist.label(LOCKED_SUBTITLE, CARD_SUBTITLE_SIZE,
			Color(1.0, 1.0, 1.0, 0.6), SoftBrutalist.WEIGHT_REGULAR, SoftBrutalist.TRACK_LABEL))
		widgets.lock_row = lock_row

	var arrow_badge := _build_icon_badge(&"arrow_right", ARROW_BADGE_SIZE)
	arrow_badge.position = Vector2(CARD_WIDTH - CARD_PAD - ARROW_BADGE_SIZE,
		CARD_HEIGHT - CARD_PAD - ARROW_BADGE_SIZE)
	frame.add_child(arrow_badge)

	# Border drawn last, on top of everything: a transparent-fill StyleBox
	# with just the 3px ink edge + rounded corners, so the frame reads as
	# crisp and unbroken regardless of what the photo underneath is doing.
	var border := Panel.new()
	border.set_anchors_preset(Control.PRESET_FULL_RECT)
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	border.add_theme_stylebox_override(&"panel", _border_style(SoftBrutalist.INK, 0, Vector2.ZERO))
	frame.add_child(border)
	widgets.border = border

	return widgets


func _build_icon_badge(icon_name: StringName, badge_size: float) -> Panel:
	var badge := Panel.new()
	badge.custom_minimum_size = Vector2(badge_size, badge_size)
	badge.size = Vector2(badge_size, badge_size)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1.0, 1.0, 1.0, 0.92)
	style.set_corner_radius_all(int(badge_size * 0.5))
	style.anti_aliasing_size = 0.6
	badge.add_theme_stylebox_override(&"panel", style)

	var icon := UIIcon.new()
	icon.icon_name = icon_name
	icon.line_colour = SoftBrutalist.INK
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	var inset := badge_size * 0.24
	icon.offset_left = inset
	icon.offset_top = inset
	icon.offset_right = -inset
	icon.offset_bottom = -inset
	badge.add_child(icon)
	return badge


## Transparent-fill variant of SoftBrutalist.panel_style() — the shared
## helper always fills solid, which would hide the photo/placeholder it's
## layered over here.
func _border_style(border_colour: Color, shadow_size: int, shadow_offset: Vector2) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0, 0, 0, 0)
	box.border_color = border_colour
	box.set_border_width_all(SoftBrutalist.BORDER_WIDTH)
	box.set_corner_radius_all(SoftBrutalist.CORNER_RADIUS)
	box.shadow_color = Color(SoftBrutalist.INK.r, SoftBrutalist.INK.g, SoftBrutalist.INK.b, 0.22)
	box.shadow_size = shadow_size
	box.shadow_offset = shadow_offset
	box.anti_aliasing_size = 0.6
	return box


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


## A generated (not imported) top-transparent/bottom-dark vertical
## gradient, so the white title/subtitle text on every card stays legible
## over whatever the photo is doing underneath, same job a broadcast
## lower-third scrim does.
func _bottom_scrim_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([Color(0, 0, 0, 0), Color(0, 0, 0, 0.7)])
	gradient.offsets = PackedFloat32Array([0.35, 1.0])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_LINEAR
	texture.fill_from = Vector2(0.0, 0.0)
	texture.fill_to = Vector2(0.0, 1.0)
	texture.width = 4
	texture.height = 64
	return texture


# ── Refresh ──────────────────────────────────────────────────────────

func _refresh() -> void:
	for i in _entries.size():
		var entry := _entries[i]
		var selected := i == _index
		var widgets := _cards[i]

		var cursor := "› " if selected else ""
		widgets.title_label.text = cursor + entry.title

		var target_saturation := 1.0 if (selected and entry.unlocked) else 0.0
		var target_scale := CARD_SELECTED_SCALE if (selected and entry.unlocked) else 1.0
		var target_border := SoftBrutalist.ACCENT_PRIMARY if (selected and entry.unlocked) \
			else SoftBrutalist.INK
		var target_shadow_size := SoftBrutalist.SHADOW_HOVER_SIZE if selected \
			else SoftBrutalist.SHADOW_REST_SIZE
		var target_shadow_offset := SoftBrutalist.SHADOW_HOVER_OFFSET if selected \
			else SoftBrutalist.SHADOW_REST_OFFSET

		var tween := widgets.frame.create_tween()
		tween.set_trans(CARD_ANIM_TRANS)
		tween.set_ease(CARD_ANIM_EASE)
		tween.set_parallel(true)
		tween.tween_property(widgets.material, "shader_parameter/saturation",
			target_saturation, CARD_ANIM_DURATION)
		tween.tween_property(widgets.frame, "scale", Vector2.ONE * target_scale,
			CARD_ANIM_DURATION)

		var border_style: StyleBoxFlat = widgets.border.get_theme_stylebox(&"panel")
		var next_border := border_style.duplicate()
		widgets.border.add_theme_stylebox_override(&"panel", next_border)
		tween.tween_property(next_border, "border_color", target_border, CARD_ANIM_DURATION)
		tween.tween_property(next_border, "shadow_size", target_shadow_size, CARD_ANIM_DURATION)
		tween.tween_property(next_border, "shadow_offset", target_shadow_offset,
			CARD_ANIM_DURATION)
