class_name MatchEndScreen
extends CanvasLayer

## Read-only full-time scoreline screen (design brief).
##
## Reads the final score from MatchState.scoreline() — the same call
## full_game.gd's `_finish_match()` uses for the scoreboard flash — and
## presents it in a themed card. No replay/rematch wiring; the only
## action is returning to the main menu. Built in _ready() from
## SoftBrutalist, same hand-built pattern as the other placeholder
## screens in this pass.

const CARD_WIDTH := 480.0
const CARD_HEIGHT := 320.0

var _busy := false


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	root.add_child(SoftBrutalist.backdrop())

	var card := Panel.new()
	card.add_theme_stylebox_override(&"panel", SoftBrutalist.panel_style())
	SoftBrutalist.soften(card, SoftBrutalist.Elevation.OVERLAY)
	card.size = Vector2(CARD_WIDTH, CARD_HEIGHT)
	card.position = Vector2((1280.0 - CARD_WIDTH) / 2.0, (720.0 - CARD_HEIGHT) / 2.0)
	root.add_child(card)

	var title := SoftBrutalist.label("FULL TIME", SoftBrutalist.SIZE_TITLE, SoftBrutalist.INK,
		SoftBrutalist.WEIGHT_HEAVY, SoftBrutalist.TRACK_TITLE)
	title.position = Vector2(32.0, 32.0)
	card.add_child(title)

	var home_label := SoftBrutalist.label("HOME", SoftBrutalist.SIZE_LABEL, SoftBrutalist.MUTED,
		SoftBrutalist.WEIGHT_BOLD, SoftBrutalist.TRACK_LABEL)
	home_label.position = Vector2(32.0, 104.0)
	card.add_child(home_label)

	var home_score := SoftBrutalist.numeric_label(MatchState.scoreline(Tuning.Team.HOME), SoftBrutalist.SIZE_TITLE,
		SoftBrutalist.ACCENT_PRIMARY)
	home_score.position = Vector2(32.0, 126.0)
	card.add_child(home_score)

	var away_label := SoftBrutalist.label("AWAY", SoftBrutalist.SIZE_LABEL, SoftBrutalist.MUTED,
		SoftBrutalist.WEIGHT_BOLD, SoftBrutalist.TRACK_LABEL)
	away_label.position = Vector2(32.0, 178.0)
	card.add_child(away_label)

	var away_score := SoftBrutalist.numeric_label(MatchState.scoreline(Tuning.Team.AWAY), SoftBrutalist.SIZE_TITLE,
		SoftBrutalist.ACCENT_PRIMARY)
	away_score.position = Vector2(32.0, 200.0)
	card.add_child(away_score)

	var button_panel := Panel.new()
	button_panel.add_theme_stylebox_override(&"panel", SoftBrutalist.button_style(&"hover"))
	SoftBrutalist.soften(button_panel, SoftBrutalist.Elevation.LOW,
		float(SoftBrutalist.RADIUS_SM))
	button_panel.position = Vector2(32.0, CARD_HEIGHT - 80.0)
	button_panel.size = Vector2(CARD_WIDTH - 64.0, 56.0)
	card.add_child(button_panel)

	var button_label := SoftBrutalist.label("RETURN TO MENU", SoftBrutalist.SIZE_BODY, SoftBrutalist.INK,
		SoftBrutalist.WEIGHT_BOLD, SoftBrutalist.TRACK_LABEL)
	button_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	button_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	button_panel.add_child(button_label)


func _unhandled_input(event: InputEvent) -> void:
	if _busy:
		return
	if event.is_action_pressed(&"ui_accept") or event.is_action_pressed(&"pause") \
			or event.is_action_pressed(&"ui_cancel"):
		_return_to_menu()


func _return_to_menu() -> void:
	if _busy:
		return
	_busy = true
	SceneWipe.change_scene("res://scenes/ui/main_menu.tscn")
