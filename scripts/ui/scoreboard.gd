class_name Scoreboard
extends CanvasLayer

## Always-visible match state: score, clock, quarter.
##
## Distinct from DebugHud, which is a toggleable diagnostic overlay for
## judging feel — this is what a player is actually meant to read while
## playing, so unlike DebugHud it has no visibility toggle.
##
## A small Soft Brutalist card in the bottom-left corner (playtest
## 2026-10-30: back to the card look, but keep the ground board's format,
## and out of the top of the screen):
##
##            G      B     PTS  │  QTR 1
##   HOME    02  |  03  |  015  │  12:34
##   AWAY    01  |  04  |  010  │
##
## Goals | behinds | total per team, as the board out on the oval shows it
## (FieldScoreboard). 1.4.0 put the seven-segment ScoreboardFace here,
## top-centre; the user preferred the card. The digits are real Label
## nodes through SoftBrutalist.numeric_label(), zero-padded and tabular,
## so the card never changes width as the score climbs.
##
## flash()'s messages ("GOAL!", "QUARTER TIME") show in their own card
## top-centre, where the eye already goes for them, so the score that just
## changed stays readable down in the corner.

## Same colours as HumanoidRig's home/away guernsey — HOME and AWAY read
## at a glance without needing the word to be parsed. The full-time screen
## (match_end_screen.gd) uses these too.
const COLOUR_HOME := Color("#C99A2E")
const COLOUR_AWAY := Color("#C24A3F")

const TAG_FONT_SIZE := SoftBrutalist.SIZE_LABEL
const HEAD_FONT_SIZE := SoftBrutalist.SIZE_CAPTION
const DIGIT_FONT_SIZE := SoftBrutalist.SIZE_HEADING
const CLOCK_FONT_SIZE := SoftBrutalist.SIZE_HEADING
const BANNER_FONT_SIZE := SoftBrutalist.SIZE_HEADING

## The card's distance from the screen's left and bottom edges, at the
## 1280x720 base resolution (px). DebugHud's key chips moved to the
## bottom-right to make room.
const EDGE_MARGIN := 16.0
## The banner card's distance from the top edge.
const BANNER_TOP := 14.0
## A floor under the team-name column: HOME and AWAY are short, a Career
## club's nickname can be nine letters, and either way the digits should
## start in the same place every match.
const TAG_COLUMN_WIDTH := 56.0
const CLOCK_COLUMN_WIDTH := 64.0

var _card: Panel
var _card_content: Control
var _home_goals: Label
var _home_behinds: Label
var _home_total: Label
var _away_goals: Label
var _away_behinds: Label
var _away_total: Label
var _quarter_label: Label
var _clock_label: Label

var _banner_panel: Panel
var _banner_content: Control
var _banner: Label

## While > 0, a transient message (see flash()) is showing in the banner
## card — used for "GOAL!", "QUARTER TIME", "FULL TIME".
var _banner_timer := 0.0


func _ready() -> void:
	_build_card()
	_build_banner()
	MatchState.score_changed.connect(func(_team: Tuning.Team) -> void: _refresh())
	MatchState.clock_changed.connect(func(_seconds: float) -> void: _refresh())
	MatchState.quarter_changed.connect(func(_quarter: int) -> void: _refresh())
	_refresh()


func _process(delta: float) -> void:
	if _banner_timer <= 0.0:
		return
	_banner_timer = maxf(0.0, _banner_timer - delta)
	if _banner_timer <= 0.0:
		_banner_panel.visible = false


## Shows `text` in the banner card for `duration` seconds.
func flash(text: String, duration := 2.5) -> void:
	_banner.text = text
	# A Panel doesn't size to its children (LESSONS: a plain Panel collapses),
	# so the card takes its content's size each time the text changes.
	var content_size := _banner_content.get_combined_minimum_size()
	_banner_panel.size = content_size
	_banner_panel.position = Vector2(-content_size.x * 0.5, BANNER_TOP)
	_banner_panel.visible = true
	_banner_timer = duration


func _refresh() -> void:
	for team: Tuning.Team in [Tuning.Team.HOME, Tuning.Team.AWAY]:
		var away := team == Tuning.Team.AWAY
		(_away_goals if away else _home_goals).text = "%02d" % clampi(MatchState.goals[team], 0, 99)
		(_away_behinds if away else _home_behinds).text = "%02d" % clampi(MatchState.behinds[team], 0, 99)
		(_away_total if away else _home_total).text = "%03d" % clampi(MatchState.points(team), 0, 999)
	_quarter_label.text = "QTR %d" % clampi(MatchState.quarter, 0, 9)
	var total := maxi(int(ceil(MatchState.seconds_remaining)), 0)
	_clock_label.text = "%02d:%02d" % [mini(total / 60, 99), total % 60]


func _build_card() -> void:
	# A Panel, not a PanelContainer: soften()'s shadow is a child that
	# reaches outside its parent, and a Container would clip it.
	_card = Panel.new()
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_theme_stylebox_override(&"panel", SoftBrutalist.panel_style())
	SoftBrutalist.soften(_card, SoftBrutalist.Elevation.REST)
	add_child(_card)

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in [&"margin_left", &"margin_right"]:
		margin.add_theme_constant_override(side, 16)
	for side in [&"margin_top", &"margin_bottom"]:
		margin.add_theme_constant_override(side, 8)
	_card.add_child(margin)
	_card_content = margin

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override(&"separation", 14)
	margin.add_child(row)

	var grid := GridContainer.new()
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grid.columns = 6
	grid.add_theme_constant_override(&"h_separation", 8)
	grid.add_theme_constant_override(&"v_separation", 0)
	row.add_child(grid)

	# Column heads: what each number is, quiet enough not to be read first.
	for head in ["", "G", "", "B", "", "PTS"]:
		var node := SoftBrutalist.label(head, HEAD_FONT_SIZE, SoftBrutalist.MUTED,
			SoftBrutalist.WEIGHT_BOLD, SoftBrutalist.TRACK_LABEL)
		node.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		grid.add_child(node)

	var home := _team_row(grid, Tuning.Team.HOME, COLOUR_HOME)
	_home_goals = home[0]
	_home_behinds = home[1]
	_home_total = home[2]
	var away := _team_row(grid, Tuning.Team.AWAY, COLOUR_AWAY)
	_away_goals = away[0]
	_away_behinds = away[1]
	_away_total = away[2]

	var divider := ColorRect.new()
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	divider.color = SoftBrutalist.LINE_SOFT
	divider.custom_minimum_size = Vector2(2.0, 0.0)
	row.add_child(divider)

	# Quarter over clock, centred against the two team rows.
	var clock_column := VBoxContainer.new()
	clock_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clock_column.alignment = BoxContainer.ALIGNMENT_CENTER
	clock_column.add_theme_constant_override(&"separation", 0)
	clock_column.custom_minimum_size.x = CLOCK_COLUMN_WIDTH
	row.add_child(clock_column)
	_quarter_label = SoftBrutalist.label("QTR 1", TAG_FONT_SIZE, SoftBrutalist.MUTED,
		SoftBrutalist.WEIGHT_BOLD, SoftBrutalist.TRACK_LABEL)
	_quarter_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	clock_column.add_child(_quarter_label)
	_clock_label = SoftBrutalist.numeric_label("00:00", CLOCK_FONT_SIZE, SoftBrutalist.INK)
	_clock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	clock_column.add_child(_clock_label)

	# The digits are zero-padded and tabular, so this size holds all match.
	_refresh_placeholders()
	var content_size := margin.get_combined_minimum_size()
	_card.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_card.offset_left = EDGE_MARGIN
	_card.offset_right = EDGE_MARGIN + content_size.x
	_card.offset_bottom = -EDGE_MARGIN
	_card.offset_top = -EDGE_MARGIN - content_size.y
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## One team's row: name tag, goals | behinds | total. Returns the three
## number labels.
func _team_row(grid: GridContainer, team: Tuning.Team, colour: Color) -> Array[Label]:
	var tag := SoftBrutalist.label(ScoreboardFace.team_label(team), TAG_FONT_SIZE, colour,
		SoftBrutalist.WEIGHT_BOLD, SoftBrutalist.TRACK_LABEL)
	tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tag.custom_minimum_size.x = TAG_COLUMN_WIDTH
	grid.add_child(tag)
	var numbers: Array[Label] = []
	for i in 3:
		if i > 0:
			var bar := SoftBrutalist.label("|", DIGIT_FONT_SIZE, SoftBrutalist.LINE_SOFT,
				SoftBrutalist.WEIGHT_REGULAR)
			bar.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			grid.add_child(bar)
		var number := SoftBrutalist.numeric_label("000" if i == 2 else "00", DIGIT_FONT_SIZE, colour)
		number.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		grid.add_child(number)
		numbers.append(number)
	return numbers


## Widest text each label will ever hold, for sizing the card once.
func _refresh_placeholders() -> void:
	for number in [_home_goals, _home_behinds, _away_goals, _away_behinds]:
		(number as Label).text = "00"
	for number in [_home_total, _away_total]:
		(number as Label).text = "000"
	_quarter_label.text = "QTR 4"
	_clock_label.text = "00:00"


func _build_banner() -> void:
	var anchor := Control.new()
	anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	add_child(anchor)

	_banner_panel = Panel.new()
	_banner_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner_panel.add_theme_stylebox_override(&"panel", SoftBrutalist.panel_style())
	SoftBrutalist.soften(_banner_panel, SoftBrutalist.Elevation.REST)
	anchor.add_child(_banner_panel)

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in [&"margin_left", &"margin_right"]:
		margin.add_theme_constant_override(side, 18)
	for side in [&"margin_top", &"margin_bottom"]:
		margin.add_theme_constant_override(side, 6)
	_banner_panel.add_child(margin)
	_banner_content = margin
	_banner = SoftBrutalist.label("", BANNER_FONT_SIZE, SoftBrutalist.INK,
		SoftBrutalist.WEIGHT_HEAVY, SoftBrutalist.TRACK_LABEL)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	margin.add_child(_banner)
	_banner_panel.visible = false
