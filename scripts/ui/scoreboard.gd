class_name Scoreboard
extends CanvasLayer

## Always-visible match state: score, clock, quarter.
##
## Distinct from DebugHud, which is a toggleable diagnostic overlay for
## judging feel — this is what a player is actually meant to read while
## playing, so unlike DebugHud it has no visibility toggle.
##
## Built as a small Soft Brutalist card (see soft_brutalist.gd's header
## for why hand-built Control trees are the norm in scenes/ui/): the
## score/clock digits are real Label nodes routed through
## SoftBrutalist.numeric_label() rather than one RichTextLabel string, so
## the monospace digits can sit next to the rounded/grotesk HOME/AWAY tags
## without BBCode juggling fonts mid-string.

## Same colours as PlaceholderRig's home/away guernsey — HOME and AWAY read
## at a glance without needing the word to be parsed, and it ties the
## scoreboard into the same palette as the players on the field.
const COLOUR_HOME := Color("#C99A2E")
const COLOUR_AWAY := Color("#C24A3F")

const TAG_FONT_SIZE := 13
const DIGIT_FONT_SIZE := 20
const CLOCK_FONT_SIZE := 16
const BANNER_FONT_SIZE := 18

@onready var _panel: Panel = $Panel

var _readout: Control
var _home_tag: Label
var _home_score: Label
var _clock_label: Label
var _away_score: Label
var _away_tag: Label
var _banner: Label

## While > 0, a transient message (see flash()) is showing instead of the
## normal readout — used for "GOAL!", "QUARTER TIME", "FULL TIME".
var _banner_timer := 0.0


func _ready() -> void:
	_build_ui()
	MatchState.score_changed.connect(func(_team: Tuning.Team) -> void: _refresh())
	MatchState.clock_changed.connect(func(_seconds: float) -> void: _refresh())
	MatchState.quarter_changed.connect(func(_quarter: int) -> void: _refresh())
	_refresh()


func _process(delta: float) -> void:
	if _banner_timer <= 0.0:
		return
	_banner_timer = maxf(0.0, _banner_timer - delta)
	if _banner_timer <= 0.0:
		_refresh()


## Replaces the readout with `text` for `duration` seconds, then reverts.
func flash(text: String, duration := 2.5) -> void:
	_readout.visible = false
	_banner.text = text
	_banner.visible = true
	_banner_timer = duration


func _refresh() -> void:
	if _banner_timer > 0.0:
		return
	_banner.visible = false
	_readout.visible = true
	_home_score.text = MatchState.scoreline(Tuning.Team.HOME)
	_away_score.text = MatchState.scoreline(Tuning.Team.AWAY)
	var total := maxi(int(ceil(MatchState.seconds_remaining)), 0)
	_clock_label.text = "Q%d   %02d:%02d" % [MatchState.quarter, total / 60, total % 60]


func _build_ui() -> void:
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_theme_stylebox_override(&"panel", SoftBrutalist.panel_style())

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override(&"margin_left", 16)
	margin.add_theme_constant_override(&"margin_right", 16)
	margin.add_theme_constant_override(&"margin_top", 6)
	margin.add_theme_constant_override(&"margin_bottom", 6)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(row)
	_readout = row

	_home_tag = SoftBrutalist.label("HOME", TAG_FONT_SIZE, COLOUR_HOME, SoftBrutalist.WEIGHT_BOLD,
		SoftBrutalist.TRACK_LABEL)
	_home_tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_home_tag)

	_home_score = SoftBrutalist.numeric_label("0.0.0", DIGIT_FONT_SIZE, COLOUR_HOME)
	_home_score.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_home_score)

	_clock_label = SoftBrutalist.numeric_label("Q1   00:00", CLOCK_FONT_SIZE, SoftBrutalist.INK)
	_clock_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_clock_label)

	_away_score = SoftBrutalist.numeric_label("0.0.0", DIGIT_FONT_SIZE, COLOUR_AWAY)
	_away_score.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_away_score)

	_away_tag = SoftBrutalist.label("AWAY", TAG_FONT_SIZE, COLOUR_AWAY, SoftBrutalist.WEIGHT_BOLD,
		SoftBrutalist.TRACK_LABEL)
	_away_tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_away_tag)

	_banner = SoftBrutalist.label("", BANNER_FONT_SIZE, SoftBrutalist.INK, SoftBrutalist.WEIGHT_BOLD)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_banner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_banner.visible = false
	margin.add_child(_banner)
