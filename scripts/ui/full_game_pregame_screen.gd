class_name FullGamePregameScreen
extends CanvasLayer

## Full Game pregame settings screen — the step between main_menu.gd's
## FULL GAME card and full_game.tscn itself. main_menu.gd's FULL GAME
## Entry now points its scene_path here, and this screen is what actually
## calls SceneWipe.change_scene() on to the match once START MATCH is
## confirmed.
##
## ── Why a card row and not another settings_screen.gd list ──────────
## settings_screen.gd's plain vertical rows are the right shape for a
## long list of unrelated global options. A pregame screen is a small,
## fixed set of matchday choices you scan once and start, so this borrows
## main_menu.gd's horizontal card row instead: a cursor that runs across
## tiles, one tile visibly lifted, an icon glyph in the tile as the
## cursor, and locked tiles greyed with a padlock (main_menu.gd's own
## SCENARIO/GOAL KICKING treatment). Each tile shows a setting's name and
## its current value rather than a mode name over artwork, so there is no
## photo shader here — the tiles are plain RetroWindow parchment panels,
## matching settings/pause/team-list/remap rather than the menu's photo
## tiles.
##
## ── Two-level cursor ────────────────────────────────────────────────
## The row already spends left/right on moving the cursor, so a card's
## own value picker cannot also live on left/right at the same time —
## hence two modes, which is the whole interaction design of this screen:
##
##   ROW MODE   left/right   move the cursor across the 10 cards and the
##                           trailing START MATCH button (11 stops, wraps)
##              accept       open the focused card's picker (no-op on a
##                           locked card, per main_menu.gd's locked-card
##                           _select(); on START MATCH, accept starts the
##                           match instead)
##              down         jump straight to START MATCH — a spatial
##                           "the button is below the cards" move, not a
##                           value-picker gesture
##              up           jump back from START MATCH to whichever card
##                           was last selected (no-op from a card)
##              cancel / pause  back to the main menu
##
##   CARD OPEN  left/right   cycle THAT card's value, live (see
##                           SettingsScreen.Row.cycle() — the same
##                           instant-apply cycling row this project
##                           already uses everywhere)
##              accept / cancel / up   close back to ROW MODE
##
## Down used to open a card's picker; it now moves the cursor down to
## START MATCH instead, since a controller/keyboard player reads "down"
## as "go to the button underneath the cards", not "start editing this
## card" — accept alone still opens a card. Cancel is deliberately
## swallowed by an open card rather than exiting the screen — you close
## the picker first, then back out, so a stray B press can never drop you
## out of the pregame screen mid-edit.
##
## Mouse: hovering a card or START MATCH moves the row cursor there (no
## picker needed) and a left click on a card cycles its value one step,
## live — the click-to-change path the keyboard/controller two-level
## cursor exists to also support without a mouse. A left click on START
## MATCH starts the match. ActionButton normally ignores the mouse
## entirely (see its own header comment) — this screen overrides that
## deliberately, since it is the one screen an ActionButton needs to be
## clickable on.
##
## The trailing START MATCH stop follows character_screen.gd's PLAY row /
## settings_screen.gd's REMAP CONTROLS row convention ("one extra index
## past the real rows, accept activates instead of cycling"), just on a
## horizontal cursor instead of a vertical one — so it costs no new input
## binding.
##
## ── Locked cards ───────────────────────────────────────────────────
## DIFFICULTY / QUARTER LENGTH / VENUE / WEATHER are inert placeholders,
## the settings_screen.gd SCREEN SHAKE pattern: a fixed value displayed
## with no on_change and no second option to reach. Nothing in the
## project reads any of them and, deliberately, none of them has a
## Settings field — inventing persisted state for a value nothing
## consumes is exactly what settings_screen.gd's own header argues
## against.
##
## ── Camera preview ─────────────────────────────────────────────────
## The CAMERA card borrows settings_screen.gd's camera-preview system
## wholesale rather than reinventing it: the same PREVIEW_* sizing, the
## same RetroWindow.shell() two-panel layout, the same _CameraPreviewField
## draw logic, and the same slide/fade/scale Tween shape as
## SettingsScreen._set_preview_active(). The one structural difference is
## what moves — settings_screen.gd slides its single vertical card,
## this screen slides the whole horizontal card row (see this file's own
## header on why a card row exists at all) left as one unit so the
## preview has room beside it, matching this task's brief that individual
## cards must not move independently. The preview activates whenever the
## cursor sits on the CAMERA card, selected or open, same trigger shape as
## settings_screen.gd's `_index == 2` check, and always reflects
## Settings.full_game_camera_mode live — the same source of truth the
## CAMERA card itself reads and writes.

# ── Layout ───────────────────────────────────────────────────────────
# Design resolution is 1280x720 (project.godot [display], canvas_items
# stretch). Bands are laid out in containers the way main_menu.gd's
# rewrite does — the preview band is the only one that expands, so it
# absorbs whatever the fixed bands leave and nothing can grow into the
# footer.

const DESIGN_HEIGHT := 720.0

const SCREEN_MARGIN_X := SoftBrutalist.SPACE_5      ## 40
const SCREEN_MARGIN_Y := SoftBrutalist.SPACE_3      ## 24
const BAND_GAP := int(SoftBrutalist.SPACE_2)        ## 16
const HEADER_HEIGHT := 66.0
const FOOTER_HEIGHT := 24.0

## Ten cards plus nine gaps has to clear the screen's own side margins:
## 10*90 + 9*18 = 1062, against 1280 - 40*2 = 1200 usable. Card height is
## set by the tallest content a card can hold — a two-line wrapped title
## ("DEFENSIVE PRESSURE"), a two-line wrapped value, and the cursor glyph
## row under it.
const CARD_WIDTH := 90.0
const CARD_HEIGHT := 96.0
const CARD_SEPARATION := 18
const CARD_PAD_X := 7
const CARD_PAD_Y := 8
const CARD_GLYPH_SIZE := 11.0
const CARD_CHEVRON_GAP := 6

## What the four fixed bands leave for the preview. Written as the
## subtraction rather than as a measured constant so moving any band's
## height re-derives this instead of silently overlapping it.
const PREVIEW_HEIGHT := DESIGN_HEIGHT - SCREEN_MARGIN_Y * 2.0 - HEADER_HEIGHT \
	- CARD_HEIGHT - ActionButton.HEIGHT - FOOTER_HEIGHT - float(BAND_GAP) * 4.0

## FormationWhiteboard draws itself to a portrait AFL aspect (Tuning's
## half-width over half-length) fitted to the height it is given, plus its
## own MARGIN inset on every side — so this is the panel width at which
## the board exactly fills the window rather than sitting in a band of
## empty parchment. Same derivation as TeamListScreen.BOARD_PANEL_WIDTH.
const BOARD_ASPECT := 0.818
const PREVIEW_WIDTH := (PREVIEW_HEIGHT - FormationWhiteboard.MARGIN * 2.0) * BOARD_ASPECT \
	+ FormationWhiteboard.MARGIN * 2.0

## The board is centred in the preview window and sized to the height left
## after its own MARGIN, so the bottom MARGIN band of the window is empty
## parchment. The readout strip is overlaid into exactly that band — it
## costs the board no height, which is why the preview can carry a caption
## at all at this size. Four caption rows (FORMATION / CONTROL / CAMERA /
## POSITION) run a little past that band into the board's own inset — a
## harmless overlap of blank margin, not board content.
const READOUT_INSET_X := 14.0
const READOUT_HEIGHT := 66.0
const READOUT_BOTTOM := 6.0
const READOUT_ROW_GAP := 1

## ── Camera preview ───────────────────────────────────────────────────
## The camera preview uses the existing middle preview window rather than
## creating a second window beside the card row. When the CAMERA card is
## selected, the formation whiteboard and its readout are hidden and the
## camera preview occupies the same landscape RetroWindow shell. The card
## row therefore remains completely stationary regardless of the selected
## camera mode.
const CAMERA_PREVIEW_WIDTH := 460.0
const CAMERA_PREVIEW_HEIGHT := 360.0
const CAMERA_BG_COLOUR := Color("#d4b5a0")


const TITLE_TEXT := "FULL GAME"
## Lifted from main_menu.gd's own FULL GAME Entry subtitle, so the card
## you picked and the screen it opens say the same thing.
const SUBTITLE_TEXT := "18-a-side, real clock, quarters, scoring"
const START_TEXT := "START MATCH"

const MATCH_SCENE := "res://scenes/modes/full_game.tscn"
const MENU_SCENE := "res://scenes/ui/main_menu.tscn"

## Selection animation, matching main_menu.gd's card row: a back-out
## overshoot on the scale (a plain ease never reads as a "pop", see that
## file's CARD_POP_TRANS comment) and a cubic ease on the hard offset
## shadow growing underneath.
const CARD_ANIM_DURATION := 0.18
const CARD_POP_TRANS := Tween.TRANS_BACK
const CARD_POP_EASE := Tween.EASE_OUT
const CARD_SHADOW_TRANS := Tween.TRANS_CUBIC
const CARD_SHADOW_EASE := Tween.EASE_OUT
const CARD_SELECTED_SCALE := 1.06
## Smaller than RetroWindow.SHADOW_OFFSET's 7px card-scale slab — these
## are small tiles, and the idle-to-selected growth is what sells the lift.
const CARD_SHADOW_OFFSET_IDLE := Vector2(4.0, 4.0)
const CARD_SHADOW_OFFSET_SELECTED := Vector2(9.0, 9.0)

## Index of the CAMERA card within _cards — fixed by the literal array
## built in _ready(), named here rather than left as a bare "1" everywhere
## the camera preview needs to know which card triggers it.
const CAMERA_CARD_INDEX := 1


## One setting tile. `row` is SettingsScreen.Row — the project's
## established cycling-value shape, reused rather than re-declared
## (team_list_screen.gd already reuses it the same way). `locked` is what
## separates the four inert placeholder cards from the five real ones: a
## locked card has a single-option Row with no on_change (settings_
## screen.gd's SCREEN SHAKE pattern) AND never opens a picker at all.
class Card:
	var row: SettingsScreen.Row
	var locked: bool

	var frame: Control
	var shadow: Panel
	var body: Panel
	var title_label: Label
	var value_label: Label
	var glyph: UIIcon
	var chevron_left: Label
	var chevron_right: Label

	func _init(p_row: SettingsScreen.Row, p_locked := false) -> void:
		row = p_row
		locked = p_locked


## Draws one camera field (3rd-person or full-side) exactly like
## SettingsScreen's private _CameraPreviewField — copied rather than
## shared since that class is private to settings_screen.gd and this file
## must stay self-contained.
class _CameraPreviewField extends Control:
	var full_side := false
	var _texture_rect: TextureRect

	func _ready() -> void:
		# Create a TextureRect to display the camera screenshot
		_texture_rect = TextureRect.new()
		_texture_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		_texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_texture_rect.clip_contents = true
		_texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_texture_rect)
		update_texture()

	func update_texture() -> void:
		if _texture_rect == null:
			return
		var image_path := "res://assets/textures/images/fullside.png" if full_side else "res://assets/textures/images/3rdperson.png"
		_texture_rect.texture = load(image_path)


var _cards: Array[Card] = []

## 0.._cards.size()-1 selects a card; _cards.size() is the trailing START
## MATCH stop (see this file's header).
var _index := 0

## Last card _index pointed at before jumping to the trailing START MATCH
## stop — restored by _leave_start() so "up" from START MATCH is a real
## inverse of "down" into it, not a reset to card 0.
var _last_card_index := 0

## True while one functional card's value picker is open — the second
## level of the cursor. Never true for a locked card or for START MATCH.
var _open := false

## Latched while a SceneWipe is in flight, same guard every other screen
## in this project uses, so a second Enter during the wipe can't queue a
## second scene change.
var _busy := false

var _whiteboard: FormationWhiteboard
var _readout_values: Array[Label] = []
var _start_button: ActionButton
var _start_band: Control
var _hints: KeyHintBar

var _card_row: HBoxContainer

## The two camera field panels live inside the existing middle preview
## window. They are toggled as a single camera-preview state rather than
## sliding a second window beside the card row.
var _camera_preview_container: Control
var _camera_field_third_person: _CameraPreviewField
var _camera_field_full_side: _CameraPreviewField
var _camera_panel_third_person: Panel
var _camera_panel_full_side: Panel
var _readout_strip: VBoxContainer


func _ready() -> void:
	# A menu, not the match: full_game.tscn sets its own mode/phase when it
	# actually loads.
	GameState.phase = GameState.Phase.MENU

	_cards = [
		Card.new(SettingsScreen.Row.new("PLAYER CONTROL",
			["1 PLAYER", "FULL TEAM"], Settings.player_control_mode,
			_set_player_control)),
		Card.new(SettingsScreen.Row.new("CAMERA",
			["3RD PERSON", "FULL-SIDE"], Settings.full_game_camera_mode,
			_set_camera_mode)),
		Card.new(SettingsScreen.Row.new("FORMATION",
			_formation_options(), Settings.home_formation_index, _set_formation)),
		Card.new(SettingsScreen.Row.new("BALL MOVEMENT",
			["CORRIDOR", "MUTUAL", "BOUNDARY"], Settings.home_ball_movement,
			_set_ball_movement)),
		Card.new(SettingsScreen.Row.new("DEFENSIVE PRESSURE",
			["LOOSE", "BALANCED", "TIGHT"], Settings.home_defensive_pressure,
			_set_defensive_pressure)),
		Card.new(SettingsScreen.Row.new("YOUR POSITION",
			_your_position_options(), Settings.home_human_slot, _set_your_position)),
		# Inert placeholders from here down — see this file's header.
		Card.new(SettingsScreen.Row.new("DIFFICULTY", ["NORMAL"]), true),
		Card.new(SettingsScreen.Row.new("QUARTER LENGTH", ["20 MIN"]), true),
		Card.new(SettingsScreen.Row.new("VENUE", ["HOME GROUND"]), true),
		Card.new(SettingsScreen.Row.new("WEATHER", ["CLEAR"]), true),
	]

	_build()
	# _refresh() drives the preview too, so there is no separate seeding
	# call — one path keeps the cards and the window from ever disagreeing.
	_refresh()


## Read straight off Settings.FORMATION_PRESETS rather than hardcoded, so
## this card can never drift from settings.gd's own preset table if a
## fourth shape is added there.
func _formation_options() -> Array[String]:
	var options: Array[String] = []
	for preset: Dictionary in Settings.FORMATION_PRESETS:
		options.append(String(preset["name"]))
	return options


## One entry per HOME roster slot: "<n> <label>" (1-based roster index +
## the TeamFormation short label), so repeated labels (two BPs, two wings,
## …) still read distinctly and the number doubles as the roster-index
## cue. Static — every slot 0..TEAM_SIZE-1 is a real player at 18-a-side —
## so unlike a formation-preset-derived list it never has to rebuild when
## another card changes. Slot 0 is the AI centre-bounce ruck (full_game.gd
## _bounce_off); it's offered anyway — human-as-ruck is allowed, it just
## can't actively palm a hit-out. Only consumed in SINGLE_PLAYER mode; the
## card always shows (FULL TEAM ignores home_human_slot).
func _your_position_options() -> Array[String]:
	var options: Array[String] = []
	for i in Tuning.TEAM_SIZE:
		options.append("%d %s" % [i + 1, String(TeamFormation.roster_slot(i)["label"])])
	return options


# ── Input ────────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if _busy:
		return

	# Level two: a card is open, so left/right belongs to its value picker
	# rather than to the row cursor, and cancel closes the picker instead
	# of leaving the screen.
	if _open:
		if event.is_action_pressed(&"move_left") or event.is_action_pressed(&"ui_left"):
			_cycle(-1)
		elif event.is_action_pressed(&"move_right") or event.is_action_pressed(&"ui_right"):
			_cycle(1)
		elif event.is_action_pressed(&"ui_accept") or event.is_action_pressed(&"confirm") \
				or event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"decline") \
				or event.is_action_pressed(&"pause") \
				or event.is_action_pressed(&"move_forward") or event.is_action_pressed(&"ui_up"):
			_close_card()
		return

	# Level one: the row cursor. Same left/right pair main_menu.gd's _move()
	# listens on; up/down are spent moving to/from the trailing START MATCH
	# stop instead of main_menu.gd's up/down-as-left/right aliases, since
	# this screen has something real sitting below the row to navigate to.
	if event.is_action_pressed(&"move_left") or event.is_action_pressed(&"ui_left"):
		_move(-1)
	elif event.is_action_pressed(&"move_right") or event.is_action_pressed(&"ui_right"):
		_move(1)
	elif event.is_action_pressed(&"ui_accept") or event.is_action_pressed(&"confirm"):
		_activate()
	elif event.is_action_pressed(&"move_back") or event.is_action_pressed(&"ui_down"):
		_go_to_start()
	elif event.is_action_pressed(&"move_forward") or event.is_action_pressed(&"ui_up"):
		_leave_start()
	elif event.is_action_pressed(&"pause") or event.is_action_pressed(&"ui_cancel") \
			or event.is_action_pressed(&"decline"):
		_back()


## Cards plus the trailing START MATCH stop.
func _stop_count() -> int:
	return _cards.size() + 1


func _move(step: int) -> void:
	_index = (_index + step + _stop_count()) % _stop_count()
	if _index < _cards.size():
		_last_card_index = _index
	_refresh()


## Down, from anywhere in the row (a card or already at START MATCH):
## jump straight to the trailing stop. Idempotent so mashing down never
## does anything surprising once you're there.
func _go_to_start() -> void:
	_index = _cards.size()
	_refresh()


## Up, from START MATCH only: back to whichever card sent you there. A
## no-op from inside the card row — there's nothing above it to go to.
func _leave_start() -> void:
	if _index != _cards.size():
		return
	_index = _last_card_index
	_refresh()


func _activate() -> void:
	if _index == _cards.size():
		_start_match()
		return
	# Locked card: a deliberate no-op, exactly like main_menu.gd's
	# _select() on a locked mode entry.
	_open_card()


func _open_card() -> void:
	if _index >= _cards.size():
		return
	if _cards[_index].locked:
		return
	_open = true
	_refresh()


func _close_card() -> void:
	_open = false
	_refresh()


## Instant-apply, like every other cycling row in this project:
## Row.cycle() calls the on_change below, which writes straight into
## Settings and persists, and _refresh() then redraws the card and the
## preview from the value that is already live.
func _cycle(step: int) -> void:
	if _index >= _cards.size():
		return
	_cards[_index].row.cycle(step)
	_refresh()


## Hovering a card moves the row cursor to it, same as arrowing over —
## closes any open picker first, since the mouse never opens one (a click
## changes the value directly instead, see _on_card_input()).
func _on_card_hovered(index: int) -> void:
	_index = index
	_last_card_index = index
	_open = false
	_refresh()


## A click is the mouse's whole interaction with a card: no open/close
## step, just "this click changed the value by one", locked cards
## excepted (selecting one is still fine, changing it is not).
func _on_card_input(event: InputEvent, index: int) -> void:
	if not (event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT):
		return
	_index = index
	_last_card_index = index
	_open = false
	if not _cards[index].locked:
		_cards[index].row.cycle(1)
	_refresh()


func _start_match() -> void:
	if _busy:
		return
	_busy = true
	Settings.save()
	SceneWipe.change_scene(MATCH_SCENE)


func _back() -> void:
	if _busy:
		return
	_busy = true
	Settings.save()
	SceneWipe.change_scene(MENU_SCENE)


# ── Setting writes ───────────────────────────────────────────────────
# Each writes its Settings field and saves immediately, so a value is
# persisted the moment it is chosen rather than only on the way out —
# this screen has two exits (START MATCH and back) and one of them hands
# straight over to a match that reads these same fields.

func _set_player_control(index: int) -> void:
	Settings.player_control_mode = index as Settings.PlayerControlMode
	Settings.save()


func _set_camera_mode(index: int) -> void:
	Settings.full_game_camera_mode = index as Settings.FullGameCameraMode
	Settings.save()


func _set_formation(index: int) -> void:
	Settings.home_formation_index = index
	Settings.save()


func _set_your_position(index: int) -> void:
	Settings.home_human_slot = index
	Settings.save()


func _set_ball_movement(index: int) -> void:
	Settings.home_ball_movement = index as Settings.BallMovementPreference
	Settings.save()


func _set_defensive_pressure(index: int) -> void:
	Settings.home_defensive_pressure = index as Settings.DefensivePressure
	Settings.save()


# ── Build ────────────────────────────────────────────────────────────

func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	root.add_child(SoftBrutalist.backdrop())

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

	_build_header(bands)
	_build_preview(bands)
	_build_card_row(bands)
	_build_start_band(bands)
	_build_footer(bands)



func _build_header(parent: Control) -> void:
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.custom_minimum_size.y = HEADER_HEIGHT
	column.alignment = BoxContainer.ALIGNMENT_BEGIN
	column.add_theme_constant_override(&"separation", int(SoftBrutalist.SPACE_1))
	parent.add_child(column)

	# Top-left, not centred like main_menu.gd's own header: this screen
	# already has a centred object (the preview window), and a centred
	# title stacked directly over it reads as one column of centred things
	# with the card row hanging off the bottom.
	column.add_child(SoftBrutalist.label(TITLE_TEXT, SoftBrutalist.SIZE_DISPLAY,
		RetroWindow.BORDER, SoftBrutalist.WEIGHT_HEAVY, SoftBrutalist.TRACK_DISPLAY))
	column.add_child(SoftBrutalist.label(SUBTITLE_TEXT, SoftBrutalist.SIZE_LABEL,
		SoftBrutalist.MUTED, SoftBrutalist.WEIGHT_REGULAR, SoftBrutalist.TRACK_LABEL))


## The preview window: a RetroWindow shell holding a live
## FormationWhiteboard (the project's existing tactics board — the same
## component team_list_screen.gd stages, driven by the same three
## Settings dials) plus an overlaid readout strip.
##
## The board alone can only reflect three of the five real settings —
## it moves its 18 markers for FORMATION and BALL MOVEMENT and swings its
## dashed engagement line for DEFENSIVE PRESSURE, but it has no concept of
## who is holding the controller or where the camera is. Rather than
## teach it two settings that have nothing to do with formation geometry
## (it is shared with TeamListScreen, which must not change), the two
## remaining settings are shown in the readout strip below the board, and
## FORMATION is echoed there as well so its change is unambiguous rather
## than "some dots moved a bit".
## The preview band is a full-width landscape RetroWindow card (the landscape
## panel IS the card, not a border over a portrait one). The formation
## whiteboard sits portrait-sized and centred inside it. The readout strip
## overlays the bottom of the portrait area within the wider card.
##
## This band is the formation whiteboard preview and is untouched by the
## camera preview added below — the camera preview is a separate window
## that slides in beside the card row instead.
func _build_preview(parent: Control) -> void:
	var band := HBoxContainer.new()
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.size_flags_vertical = Control.SIZE_EXPAND_FILL
	band.alignment = BoxContainer.ALIGNMENT_CENTER
	parent.add_child(band)

	# Landscape card — fixed width, centred; slightly inset from the screen edges.
	var wrapper := Control.new()
	wrapper.custom_minimum_size = Vector2(900.0, PREVIEW_HEIGHT)
	wrapper.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	wrapper.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	wrapper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.add_child(wrapper)

	var shadow := Panel.new()
	shadow.set_anchors_preset(Control.PRESET_FULL_RECT)
	shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shadow_style := StyleBoxFlat.new()
	shadow_style.bg_color = RetroWindow.SHADOW
	shadow_style.set_corner_radius_all(RetroWindow.RADIUS)
	shadow.add_theme_stylebox_override(&"panel", shadow_style)
	shadow.offset_left = 6; shadow.offset_right = 6
	shadow.offset_top  = 6; shadow.offset_bottom = 6
	wrapper.add_child(shadow)

	var body := Panel.new()
	body.set_anchors_preset(Control.PRESET_FULL_RECT)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_theme_stylebox_override(&"panel", RetroWindow.panel_style())
	wrapper.add_child(body)

	# Portrait-sized holder, centred in the landscape card. The whiteboard
	# fills it; the readout strip overlays its bottom edge (same as before).
	var board_holder := Control.new()
	board_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board_holder.set_anchors_preset(Control.PRESET_CENTER)
	board_holder.offset_left   = -PREVIEW_WIDTH * 0.5
	board_holder.offset_right  =  PREVIEW_WIDTH * 0.5
	board_holder.offset_top    = -PREVIEW_HEIGHT * 0.5
	board_holder.offset_bottom =  PREVIEW_HEIGHT * 0.5
	body.add_child(board_holder)

	_whiteboard = FormationWhiteboard.new()
	_whiteboard.set_anchors_preset(Control.PRESET_FULL_RECT)
	_whiteboard.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board_holder.add_child(_whiteboard)

	_build_readout(board_holder)
	_build_camera_preview_content(body)

func _build_camera_preview_content(parent: Control) -> void:
	_camera_preview_container = Control.new()
	_camera_preview_container.set_anchors_preset(Control.PRESET_CENTER)
	_camera_preview_container.offset_left = -CAMERA_PREVIEW_WIDTH * 0.5
	_camera_preview_container.offset_right = CAMERA_PREVIEW_WIDTH * 0.5
	_camera_preview_container.offset_top = -CAMERA_PREVIEW_HEIGHT * 0.5
	_camera_preview_container.offset_bottom = CAMERA_PREVIEW_HEIGHT * 0.5
	_camera_preview_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_camera_preview_container.visible = false
	parent.add_child(_camera_preview_container)

	var title := SoftBrutalist.label(
		"CAMERA PREVIEW",
		SoftBrutalist.SIZE_LABEL,
		RetroWindow.BORDER,
		SoftBrutalist.WEIGHT_HEAVY,
		SoftBrutalist.TRACK_TITLE
	)
	title.position = Vector2(20.0, 18.0)
	_camera_preview_container.add_child(title)

	var divider := ColorRect.new()
	divider.color = RetroWindow.BORDER
	divider.position = Vector2(20.0, 48.0)
	divider.size = Vector2(CAMERA_PREVIEW_WIDTH - 40.0, 1.0)
	_camera_preview_container.add_child(divider)

	var cam_panel_size := Vector2(CAMERA_PREVIEW_WIDTH - 32.0, 192.0)
	var cam_panel_pos := Vector2(16.0, 52.0)

	_camera_panel_third_person = _build_camera_panel(
		_camera_preview_container, cam_panel_pos, cam_panel_size, "3RD PERSON", false)

	_camera_panel_full_side = _build_camera_panel(
		_camera_preview_container, cam_panel_pos, cam_panel_size, "FULL-SIDE", true)
## Three label/value rows overlaid on the empty parchment band below the
## board (see READOUT_HEIGHT's comment). Parented to the window's front
## Panel rather than to the MarginContainer the board fills, so it draws
## over the board and is positioned by anchors instead of being sorted
## into the container's layout.
func _build_readout(panel: Control) -> void:
	var strip := VBoxContainer.new()
	_readout_strip = strip
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	strip.grow_vertical = Control.GROW_DIRECTION_BEGIN
	strip.offset_left = READOUT_INSET_X
	strip.offset_right = -READOUT_INSET_X
	strip.offset_top = -(READOUT_HEIGHT + READOUT_BOTTOM)
	strip.offset_bottom = -READOUT_BOTTOM
	strip.add_theme_constant_override(&"separation", READOUT_ROW_GAP)
	panel.add_child(strip)

	for title: String in ["FORMATION", "CONTROL", "CAMERA", "POSITION"]:
		_readout_values.append(_build_readout_row(strip, title))


func _build_readout_row(parent: Control, title: String) -> Label:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(row)

	var title_label := SoftBrutalist.label(title, SoftBrutalist.SIZE_CAPTION,
		SoftBrutalist.MUTED, SoftBrutalist.WEIGHT_BOLD, SoftBrutalist.TRACK_LABEL)
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(title_label)

	var spacer := Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	var value_label := SoftBrutalist.label("", SoftBrutalist.SIZE_CAPTION,
		RetroWindow.ACCENT, SoftBrutalist.WEIGHT_BOLD, SoftBrutalist.TRACK_NONE)
	value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(value_label)
	return value_label


func _build_card_row(parent: Control) -> void:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.custom_minimum_size.y = CARD_HEIGHT
	# Cards are shrink-sized, so without this they bunch against the row's
	# left edge instead of sitting centred under the preview window.
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override(&"separation", CARD_SEPARATION)
	parent.add_child(row)
	# Kept so the camera preview can slide this exact container left as a
	# unit (see this file's header) — individual cards never move for the
	# camera preview, only for their own selection pop in _animate_card().
	_card_row = row

	for i in _cards.size():
		_build_card(_cards[i], i)
		row.add_child(_cards[i].frame)



func _build_card(card: Card, index: int) -> void:
	var frame := Control.new()
	frame.custom_minimum_size = Vector2(CARD_WIDTH, CARD_HEIGHT)
	frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# STOP, not IGNORE: this card has to be the one thing under the mouse
	# that actually receives the click (see _on_card_input()) — every
	# descendant built below stays IGNORE, so none of them steal the
	# event, and it falls through to frame the way main_menu.gd's own
	# mouse-only footer actions rely on the same fall-through.
	frame.mouse_filter = Control.MOUSE_FILTER_STOP
	frame.mouse_entered.connect(_on_card_hovered.bind(index))
	frame.gui_input.connect(_on_card_input.bind(index))
	card.frame = frame

	# Hard offset shadow, added first so everything after it draws on top.
	# RetroWindow's dusty teal rather than main_menu.gd's black — these
	# tiles sit on the paper backdrop with the retro shell family, not over
	# a photo montage.
	var shadow := Panel.new()
	shadow.set_anchors_preset(Control.PRESET_FULL_RECT)
	shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shadow_style := StyleBoxFlat.new()
	shadow_style.bg_color = RetroWindow.SHADOW
	shadow_style.set_corner_radius_all(RetroWindow.RADIUS)
	shadow.add_theme_stylebox_override(&"panel", shadow_style)
	_set_shadow_offset(shadow, CARD_SHADOW_OFFSET_IDLE)
	frame.add_child(shadow)
	card.shadow = shadow

	var body := Panel.new()
	body.set_anchors_preset(Control.PRESET_FULL_RECT)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(body)
	card.body = body

	var inset := MarginContainer.new()
	inset.set_anchors_preset(Control.PRESET_FULL_RECT)
	inset.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inset.add_theme_constant_override(&"margin_left", CARD_PAD_X)
	inset.add_theme_constant_override(&"margin_right", CARD_PAD_X)
	inset.add_theme_constant_override(&"margin_top", CARD_PAD_Y)
	inset.add_theme_constant_override(&"margin_bottom", CARD_PAD_Y)
	body.add_child(inset)

	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override(&"separation", 2)
	inset.add_child(column)

	# Titles wrap rather than clip — "DEFENSIVE PRESSURE" does not fit a
	# 118px tile on one line at any readable size, and a card row where one
	# label is silently truncated is worse than one where it takes two
	# lines.
	card.title_label = SoftBrutalist.label(card.row.title, SoftBrutalist.SIZE_CAPTION,
		RetroWindow.BORDER, SoftBrutalist.WEIGHT_BOLD, SoftBrutalist.TRACK_LABEL)
	card.title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card.title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(card.title_label)

	var spacer := Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(spacer)

	card.value_label = SoftBrutalist.label(card.row.value(), SoftBrutalist.SIZE_LABEL,
		RetroWindow.ACCENT, SoftBrutalist.WEIGHT_BOLD, SoftBrutalist.TRACK_NONE)
	card.value_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card.value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(card.value_label)

	# Cursor/lock glyph, flanked by the two picker chevrons. The chevrons
	# are always in the layout and only change alpha (see _refresh()), so
	# opening a card never nudges the glyph sideways — a marker that shifts
	# as you press a button reads as a glitch, same reason main_menu.gd
	# moved its cursor off a text prefix and onto a badge.
	var glyph_row := HBoxContainer.new()
	glyph_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glyph_row.alignment = BoxContainer.ALIGNMENT_CENTER
	glyph_row.add_theme_constant_override(&"separation", CARD_CHEVRON_GAP)
	column.add_child(glyph_row)

	card.chevron_left = SoftBrutalist.label("‹", SoftBrutalist.SIZE_BODY,
		RetroWindow.ACCENT, SoftBrutalist.WEIGHT_HEAVY, SoftBrutalist.TRACK_NONE)
	card.chevron_left.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	glyph_row.add_child(card.chevron_left)

	card.glyph = UIIcon.new()
	# Padlock on the four inert cards, matching main_menu.gd's locked mode
	# tiles; the "open this" chevron-arrow otherwise, its own glyph too.
	card.glyph.icon_name = &"lock" if card.locked else &"arrow_right"
	card.glyph.custom_minimum_size = Vector2(CARD_GLYPH_SIZE, CARD_GLYPH_SIZE)
	card.glyph.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	glyph_row.add_child(card.glyph)

	card.chevron_right = SoftBrutalist.label("›", SoftBrutalist.SIZE_BODY,
		RetroWindow.ACCENT, SoftBrutalist.WEIGHT_HEAVY, SoftBrutalist.TRACK_NONE)
	card.chevron_right.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	glyph_row.add_child(card.chevron_right)

	# The card's pixel size comes from the layout, and the selection pop
	# has to scale about the card's middle rather than its top-left corner.
	frame.resized.connect(func() -> void:
		frame.pivot_offset = frame.size * 0.5)


## ActionButton measures its own width in _ready() and is positioned by
## hand (character_screen.gd stages it the same way) rather than sized by
## a container, so the band holding it is a plain Control — a Container
## would re-sort the button back to its own content box every layout pass
## — and the button is re-centred whenever either rect changes.
func _build_start_band(parent: Control) -> void:
	_start_band = Control.new()
	_start_band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_start_band.custom_minimum_size.y = ActionButton.HEIGHT
	parent.add_child(_start_band)

	_start_button = ActionButton.new(START_TEXT)
	# ActionButton ignores the mouse by design (see its own header) since
	# every other screen that uses it drives it purely from the row
	# cursor — this is the one screen where START MATCH also has to be a
	# real click target, so that default is overridden here rather than
	# in the shared component.
	_start_button.mouse_filter = Control.MOUSE_FILTER_STOP
	_start_button.mouse_entered.connect(_on_start_hovered)
	_start_button.gui_input.connect(_on_start_input)
	_start_band.add_child(_start_button)

	_start_band.resized.connect(_centre_start_button)
	_start_button.resized.connect(_centre_start_button)
	_centre_start_button()


func _on_start_hovered() -> void:
	_go_to_start()


func _on_start_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		_start_match()


func _centre_start_button() -> void:
	if not is_instance_valid(_start_button) or not is_instance_valid(_start_band):
		return
	_start_button.position = Vector2(
		maxf((_start_band.size.x - _start_button.size.x) * 0.5, 0.0), 0.0)


func _build_footer(parent: Control) -> void:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.custom_minimum_size.y = FOOTER_HEIGHT
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	parent.add_child(row)

	_hints = KeyHintBar.new()
	_hints.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_hints)


func _build_camera_preview(body: Control) -> void:
	_camera_preview_container = Control.new()
	_camera_preview_container.custom_minimum_size = Vector2(
		CAMERA_PREVIEW_WIDTH, CAMERA_PREVIEW_HEIGHT)
	_camera_preview_container.size = Vector2(
		CAMERA_PREVIEW_WIDTH, CAMERA_PREVIEW_HEIGHT)
	_camera_preview_container.set_anchors_preset(Control.PRESET_CENTER)
	_camera_preview_container.position = Vector2(
		-CAMERA_PREVIEW_WIDTH * 0.5,
		-CAMERA_PREVIEW_HEIGHT * 0.5)
	_camera_preview_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_camera_preview_container.visible = false
	body.add_child(_camera_preview_container)

	var title := SoftBrutalist.label(
		"CAMERA PREVIEW",
		SoftBrutalist.SIZE_LABEL,
		RetroWindow.BORDER,
		SoftBrutalist.WEIGHT_HEAVY,
		SoftBrutalist.TRACK_TITLE
	)
	title.position = Vector2(0.0, 0.0)
	_camera_preview_container.add_child(title)

	var divider := ColorRect.new()
	divider.color = RetroWindow.BORDER
	divider.position = Vector2(0.0, 30.0)
	divider.size = Vector2(CAMERA_PREVIEW_WIDTH, 1.0)
	_camera_preview_container.add_child(divider)

	_camera_panel_third_person = _build_camera_panel(
		_camera_preview_container,
		Vector2(0.0, 44.0),
		Vector2(140.0, 184.0),
		"3RD PERSON",
		false
	)

	_camera_panel_full_side = _build_camera_panel(
		_camera_preview_container,
		Vector2(148.0, 44.0),
		Vector2(140.0, 184.0),
		"FULL-SIDE",
		true
	)

## Builds one of the two field panels inside the camera preview and
## returns it so _refresh() can highlight whichever one is currently
## selected — settings_screen.gd's own _create_camera_panel() has no
## selection concept since neither of its panels ever needs highlighting,
## but this screen already asks the same question its CAMERA card does
## ("which mode is live right now") for the readout strip, so the
## returned Panel lets the preview answer it the same way.
func _build_camera_panel(
	parent: Control,
	panel_position: Vector2,
	panel_size: Vector2,
	label_text: String,
	full_side: bool
) -> Panel:
	var panel := Panel.new()
	panel.position = panel_position
	panel.size = panel_size
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cam_style := StyleBoxFlat.new()
	cam_style.bg_color = CAMERA_BG_COLOUR
	cam_style.set_corner_radius_all(RetroWindow.RADIUS)
	panel.add_theme_stylebox_override(&"panel", cam_style)
	parent.add_child(panel)

	var title := SoftBrutalist.label(
		label_text,
		SoftBrutalist.TRACK_LABEL
	)
	title.position = Vector2(10.0, 8.0)
	panel.add_child(title)

	var field := _CameraPreviewField.new()
	field.full_side = full_side
	field.position = Vector2(10.0, 38.0)
	field.size = Vector2(panel_size.x - 20.0, panel_size.y - 50.0)
	field.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(field)

	if full_side:
		_camera_field_full_side = field
	else:
		_camera_field_third_person = field

	return panel


## The legend reflects the mode the cursor is actually in — an open card,
## a locked card, a functional card, or the START MATCH stop all offer
## genuinely different things, and one combined run-on legend would be
## telling the player about three states they are not in.
func _hints_for_state() -> Array:
	if _open:
		return [
			{"keys": "← / →", "label": "Change"},
			{"keys": "Enter / A / B / Esc", "label": "Close"},
		]
	if _index == _cards.size():
		return [
			{"keys": "← / →", "label": "Choose"},
			{"keys": "Enter / A", "label": "Start match"},
			{"keys": "↑", "label": "Back to cards"},
			{"keys": "B / Esc", "label": "Back to menu"},
		]
	if _cards[_index].locked:
		return [
			{"keys": "← / →", "label": "Choose"},
			{"keys": "—", "label": "Not built yet"},
			{"keys": "↓", "label": "Start match"},
			{"keys": "B / Esc", "label": "Back to menu"},
		]
	return [
		{"keys": "← / →", "label": "Choose"},
		{"keys": "Enter / A", "label": "Open"},
		{"keys": "↓", "label": "Start match"},
		{"keys": "B / Esc", "label": "Back to menu"},
	]


# ── Refresh ──────────────────────────────────────────────────────────

func _refresh() -> void:
	for i in _cards.size():
		var card := _cards[i]
		var selected := i == _index
		var open := selected and _open

		card.value_label.text = card.row.value()

		card.body.add_theme_stylebox_override(&"panel", _card_style(card, selected, open))
		card.title_label.add_theme_color_override(&"font_color",
			SoftBrutalist.MUTED if card.locked else RetroWindow.BORDER)
		card.value_label.add_theme_color_override(&"font_color",
			SoftBrutalist.MUTED if card.locked else RetroWindow.ACCENT)
		card.glyph.line_colour = _glyph_colour(card, selected)

		# Alpha rather than `visible`, so the glyph row's layout never
		# reflows — see _build_card().
		var chevron_alpha := 1.0 if open else 0.0
		card.chevron_left.modulate.a = chevron_alpha
		card.chevron_right.modulate.a = chevron_alpha

		# The cursor "lifts" a locked card too (shadow and scale follow the
		# cursor, not unlocked-ness) — same split main_menu.gd draws between
		# its `selected` and `live` flags, so a locked tile still shows you
		# where you are without pretending to be actionable.
		var lifted := selected or open
		_animate_card(card, lifted)

	_start_button.set_selected(_index == _cards.size())
	_hints.set_hints(_hints_for_state())
	_sync_preview()

		# The middle preview switches between the formation board and the
	# camera preview when the CAMERA card owns the cursor.
	_set_camera_preview_active(_index == CAMERA_CARD_INDEX)
	_sync_camera_preview()


func _card_style(card: Card, selected: bool, open: bool) -> StyleBoxFlat:
	if card.locked:
		# Constant regardless of the cursor: flatter and quieter, the
		# disabled pairing from the shared palette.
		return RetroWindow.panel_style(SoftBrutalist.DISABLED_BG, SoftBrutalist.DISABLED_BORDER)
	if open:
		# The same accent wash RetroWindow.row_style() gives a selected
		# list row — "this control has the input right now", one step past
		# merely being under the cursor.
		return RetroWindow.panel_style(RetroWindow.ACCENT.lightened(0.78), RetroWindow.ACCENT)
	if selected:
		return RetroWindow.panel_style(RetroWindow.PANEL, RetroWindow.ACCENT)
	return RetroWindow.panel_style()


func _glyph_colour(card: Card, selected: bool) -> Color:
	if card.locked:
		return SoftBrutalist.DISABLED_BORDER
	return RetroWindow.ACCENT if selected else SoftBrutalist.MUTED


func _animate_card(card: Card, lifted: bool) -> void:
	var target_scale := CARD_SELECTED_SCALE if lifted else 1.0
	var target_offset := CARD_SHADOW_OFFSET_SELECTED if lifted else CARD_SHADOW_OFFSET_IDLE
	if is_equal_approx(card.frame.scale.x, target_scale) \
			and is_equal_approx(card.shadow.offset_left, target_offset.x):
		return

	var tween := card.frame.create_tween()
	tween.set_parallel(true)
	tween.tween_property(card.frame, "scale", Vector2.ONE * target_scale,
		CARD_ANIM_DURATION).set_trans(CARD_POP_TRANS).set_ease(CARD_POP_EASE)
	for property: String in ["offset_left", "offset_right"]:
		tween.tween_property(card.shadow, property, target_offset.x,
			CARD_ANIM_DURATION).set_trans(CARD_SHADOW_TRANS).set_ease(CARD_SHADOW_EASE)
	for property: String in ["offset_top", "offset_bottom"]:
		tween.tween_property(card.shadow, property, target_offset.y,
			CARD_ANIM_DURATION).set_trans(CARD_SHADOW_TRANS).set_ease(CARD_SHADOW_EASE)


## Shifts a full-rect-anchored shadow down-right without resizing it —
## offset_right/offset_bottom add rather than negate, so all four edges
## move by the same amount (RetroWindow._build() moves its own shadow the
## same way).
func _set_shadow_offset(shadow: Panel, offset: Vector2) -> void:
	shadow.offset_left = offset.x
	shadow.offset_right = offset.x
	shadow.offset_top = offset.y
	shadow.offset_bottom = offset.y

func _set_camera_preview_active(active: bool) -> void:
	if not is_instance_valid(_camera_preview_container):
		return

	if _camera_preview_container.visible == active:
		return

	_camera_preview_container.visible = active

	if is_instance_valid(_whiteboard):
		_whiteboard.visible = not active

	if is_instance_valid(_readout_strip):
		_readout_strip.visible = not active


## Highlights whichever field panel matches Settings.full_game_camera_mode
## right now, so the preview reflects the live value the instant CAMERA's
## own cycle() writes it — no separate signal needed since _refresh()
## already runs on every cycle.
func _sync_camera_preview() -> void:
	if not is_instance_valid(_camera_panel_third_person) \
			or not is_instance_valid(_camera_panel_full_side):
		return

	var full_side := Settings.full_game_camera_mode == Settings.FullGameCameraMode.FULL_SIDE
	
	# Only show the panel matching the current camera mode
	_camera_panel_third_person.visible = not full_side
	_camera_panel_full_side.visible = full_side
	
	# Update the displayed images in both camera preview fields
	if is_instance_valid(_camera_field_third_person):
		_camera_field_third_person.update_texture()
	if is_instance_valid(_camera_field_full_side):
		_camera_field_full_side.update_texture()


## Pushes the live settings into the preview window. All three board dials
## are set every time even when only one changed — cheap (see
## FormationWhiteboard._retarget()) and it keeps every caller from having
## to know which of them the board actually reacts to, same as
## team_list_screen.gd's own _sync_whiteboard().
func _sync_preview() -> void:
	if is_instance_valid(_whiteboard):
		_whiteboard.formation_index = Settings.home_formation_index
		_whiteboard.ball_movement = Settings.home_ball_movement
		_whiteboard.defensive_pressure = Settings.home_defensive_pressure

	if _readout_values.size() < 4:
		return
	_readout_values[0].text = String(
		Settings.FORMATION_PRESETS[Settings.home_formation_index]["name"])
	# Phrased as what the player is holding rather than repeating the
	# card's own "SINGLE PLAYER"/"FULL TEAM" wording verbatim — the card
	# says which mode is set, the preview says what that means on the park.
	_readout_values[1].text = "ONE PLAYER" \
		if Settings.player_control_mode == Settings.PlayerControlMode.SINGLE_PLAYER \
		else "WHOLE TEAM"
	_readout_values[2].text = "3RD PERSON" \
		if Settings.full_game_camera_mode == Settings.FullGameCameraMode.THIRD_PERSON \
		else "FULL-SIDE"
	# Same "<n> <label>" form the YOUR POSITION card uses. Only bites in
	# ONE PLAYER mode, but shown regardless — the card is too.
	_readout_values[3].text = "%d %s" % [Settings.home_human_slot + 1,
		String(TeamFormation.roster_slot(Settings.home_human_slot)["label"])]
