class_name Scoreboard
extends CanvasLayer

## Always-visible match state: score, clock, quarter.
##
## Distinct from DebugHud, which is a toggleable diagnostic overlay for
## judging feel — this is what a player is actually meant to read while
## playing, so unlike DebugHud it has no visibility toggle.
##
## Since 2026-10-29 it's a seven-segment ground scoreboard (ScoreboardFace:
## goals | behinds | total per team, quarter and clock), the same face the
## board out on the oval shows (FieldScoreboard). It used to be a small
## Soft Brutalist card with "0.0.0" scorelines. flash()'s messages ("GOAL!",
## "QUARTER TIME") now show in a card under the board instead of in place
## of the score, so the score that just changed stays readable.

## Same colours as HumanoidRig's home/away guernsey — HOME and AWAY read
## at a glance without needing the word to be parsed. The full-time screen
## (match_end_screen.gd) still uses these; the board itself shows the real
## kits (TeamKit).
const COLOUR_HOME := Color("#C99A2E")
const COLOUR_AWAY := Color("#C24A3F")

## The board's digit height at the 1280x720 base resolution (px). The face
## sizes everything else off it (ScoreboardFace.size_for).
const DIGIT_HEIGHT := 27.0
const TOP_MARGIN := 10.0
const BANNER_GAP := 8.0
const BANNER_FONT_SIZE := SoftBrutalist.SIZE_HEADING

var _face: ScoreboardFace
var _banner_panel: PanelContainer
var _banner: Label

## While > 0, a transient message (see flash()) is showing under the board —
## used for "GOAL!", "QUARTER TIME", "FULL TIME".
var _banner_timer := 0.0


func _ready() -> void:
	_build_ui()


func _process(delta: float) -> void:
	if _banner_timer <= 0.0:
		return
	_banner_timer = maxf(0.0, _banner_timer - delta)
	if _banner_timer <= 0.0:
		_banner_panel.visible = false


## Shows `text` under the board for `duration` seconds.
func flash(text: String, duration := 2.5) -> void:
	_banner.text = text
	_banner_panel.visible = true
	_banner_timer = duration


func _build_ui() -> void:
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override(&"separation", int(BANNER_GAP))
	column.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	column.grow_horizontal = Control.GROW_DIRECTION_BOTH
	column.offset_top = TOP_MARGIN
	add_child(column)

	_face = ScoreboardFace.new()
	_face.custom_minimum_size = ScoreboardFace.size_for(DIGIT_HEIGHT)
	_face.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(_face)

	_banner_panel = PanelContainer.new()
	_banner_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_banner_panel.add_theme_stylebox_override(&"panel", SoftBrutalist.panel_style())
	SoftBrutalist.soften(_banner_panel, SoftBrutalist.Elevation.REST)
	column.add_child(_banner_panel)
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in [&"margin_left", &"margin_right"]:
		margin.add_theme_constant_override(side, 18)
	for side in [&"margin_top", &"margin_bottom"]:
		margin.add_theme_constant_override(side, 6)
	_banner_panel.add_child(margin)
	_banner = SoftBrutalist.label("", BANNER_FONT_SIZE, SoftBrutalist.INK,
		SoftBrutalist.WEIGHT_HEAVY, SoftBrutalist.TRACK_LABEL)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	margin.add_child(_banner)
	_banner_panel.visible = false
