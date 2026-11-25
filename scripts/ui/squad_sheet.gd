class_name SquadSheet
extends VBoxContainer

## The squad table: a minimal spreadsheet of a club's 18 players grouped by
## position line (BACK → FOLLOWERS, each group under its line colour) in
## the style of Career's VIEW ROSTER table, for RetroWindow's parchment
## card. Lifted out of the old TEAM LIST screen (playtest 2026-11-26: "we
## don't need the team list screen ... move the team/players table into the
## team select screen" with a show/hide toggle), so SideSelectScreen can
## show it under the club pickers and rebuild it whenever a club changes.
##
## show_team(club, home) rebuilds the rows. The stat columns show what a
## quick-play match will actually field, not invented numbers:
##   - HOME: CharacterProfile's stats on every player when apply_all, else
##     on the start slot (Settings.home_human_slot) only and Tuning
##     defaults elsewhere — the exact rule FullGame._apply_character_
##     profile() applies at kickoff. The start slot reads "YOU".
##   - AWAY: Tuning defaults on all 18 — quick play never applies a profile
##     to the opposition.
## Names and numbers are display-only: quick play has no named roster, so
## they come from RosterGenerator seeded off the club name (stable between
## visits, different per club, never persisted). When clubs get real
## squads, _entries() is the one place to read them from.

const ROW_HEIGHT := 30.0
## Fixed column widths; PLAYER (width 0) takes what's left. Short headers on
## purpose: units live in the caption above, so each cell reads as a bare
## number the way a spreadsheet's would.
const COLUMNS := [
	{"label": "POS", "width": 64.0, "align": HORIZONTAL_ALIGNMENT_LEFT},
	{"label": "#", "width": 36.0, "align": HORIZONTAL_ALIGNMENT_RIGHT},
	{"label": "PLAYER", "width": 0.0, "align": HORIZONTAL_ALIGNMENT_LEFT},
	{"label": "HT", "width": 56.0, "align": HORIZONTAL_ALIGNMENT_RIGHT},
	{"label": "SPD", "width": 56.0, "align": HORIZONTAL_ALIGNMENT_RIGHT},
	{"label": "AGI", "width": 56.0, "align": HORIZONTAL_ALIGNMENT_RIGHT},
	{"label": "KICK", "width": 56.0, "align": HORIZONTAL_ALIGNMENT_RIGHT},
	{"label": "ACC", "width": 56.0, "align": HORIZONTAL_ALIGNMENT_RIGHT},
	{"label": "OVR", "width": 48.0, "align": HORIZONTAL_ALIGNMENT_RIGHT},
]
## Faint zebra stripe and the YOU row's tint on the parchment card.
const STRIPE := Color(0.11, 0.10, 0.09, 0.045)
const YOU_TINT := Color(RetroWindow.ACCENT, 0.12)


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override(&"separation", 0)


## Rebuilds the sheet for `club`. `home` picks the stat rule (see header).
func show_team(club: String, home: bool) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	var squad := _entries(club, home)

	var title_row := HBoxContainer.new()
	title_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(title_row)
	title_row.add_child(SoftBrutalist.label("%s  ·  SQUAD" % club.to_upper(),
		SoftBrutalist.SIZE_HEADING, RetroWindow.BORDER, SoftBrutalist.WEIGHT_HEAVY,
		SoftBrutalist.TRACK_TITLE))
	var title_spacer := Control.new()
	title_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_row.add_child(title_spacer)
	var summary := SoftBrutalist.label(_summary(squad), SoftBrutalist.SIZE_LABEL,
		SoftBrutalist.MUTED, SoftBrutalist.WEIGHT_BOLD, SoftBrutalist.TRACK_LABEL)
	summary.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	summary.size_flags_vertical = Control.SIZE_FILL
	title_row.add_child(summary)

	add_child(SoftBrutalist.label(
		"HT cm  ·  SPD m/s  ·  AGI / KICK multiplier  ·  ACC %  ·  " + _scope_text(home),
		SoftBrutalist.SIZE_CAPTION, SoftBrutalist.MUTED, SoftBrutalist.WEIGHT_REGULAR,
		SoftBrutalist.TRACK_LABEL))

	var gap := Control.new()
	gap.custom_minimum_size.y = SoftBrutalist.SPACE_2
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(gap)

	var headings: Array[String] = []
	for col: Dictionary in COLUMNS:
		headings.append(String(col["label"]))
	add_child(_row(headings, Color(0, 0, 0, 0), RetroWindow.BORDER, true))
	add_child(_rule(RetroWindow.BORDER, 2.0))

	for line: int in TeamFormation.LINE_NAMES.size():
		add_child(_line_divider(line))
		var stripe := false
		for entry: Dictionary in squad:
			if int(entry["line"]) != line:
				continue
			var fill := YOU_TINT if entry["you"] else (STRIPE if stripe else Color(0, 0, 0, 0))
			add_child(_row(_cells(entry), fill, SoftBrutalist.INK, entry["you"]))
			stripe = not stripe


## One sheet row: fixed-width cells per COLUMNS over a flat fill.
func _row(cells: Array, fill: Color, colour: Color, bold: bool) -> Control:
	var panel := Panel.new()
	panel.custom_minimum_size.y = ROW_HEIGHT
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	panel.add_theme_stylebox_override(&"panel", style)

	var line := HBoxContainer.new()
	line.set_anchors_preset(Control.PRESET_FULL_RECT)
	line.offset_left = 8.0
	line.offset_right = -8.0
	line.add_theme_constant_override(&"separation", 8)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(line)

	var heading := bold and colour == RetroWindow.BORDER
	for i in COLUMNS.size():
		var col: Dictionary = COLUMNS[i]
		var cell := SoftBrutalist.label(String(cells[i]),
			SoftBrutalist.SIZE_LABEL if heading else SoftBrutalist.SIZE_BODY,
			colour, SoftBrutalist.WEIGHT_BOLD if bold else SoftBrutalist.WEIGHT_REGULAR,
			SoftBrutalist.TRACK_LABEL if colour == RetroWindow.BORDER else SoftBrutalist.TRACK_NONE)
		cell.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		cell.size_flags_vertical = Control.SIZE_FILL
		cell.horizontal_alignment = col["align"]
		cell.clip_text = true
		if float(col["width"]) > 0.0:
			cell.custom_minimum_size.x = col["width"]
		else:
			cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(cell)
	return panel


## Position-line group header: the board legend's swatch colour as a short
## bar beside the line name, so the sheet and the pregame board read as one
## key.
func _line_divider(line: int) -> Control:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = ROW_HEIGHT + 4.0
	row.add_theme_constant_override(&"separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var bar := Panel.new()
	bar.custom_minimum_size = Vector2(4.0, 14.0)
	bar.size_flags_vertical = Control.SIZE_SHRINK_END
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = FormationWhiteboard.LINE_COLOURS[line]
	bar.add_theme_stylebox_override(&"panel", style)
	row.add_child(bar)

	var name_label := SoftBrutalist.label(TeamFormation.LINE_NAMES[line],
		SoftBrutalist.SIZE_CAPTION, SoftBrutalist.MUTED, SoftBrutalist.WEIGHT_BOLD,
		SoftBrutalist.TRACK_TITLE)
	name_label.size_flags_vertical = Control.SIZE_SHRINK_END
	row.add_child(name_label)
	return row


func _rule(colour: Color, thickness: float) -> Control:
	var rule := ColorRect.new()
	rule.color = colour
	rule.custom_minimum_size.y = thickness
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rule


## The 18 players as {pos, number, name, line, you, height, speed, agility,
## kick_power, kick_accuracy, overall}, in TeamFormation.SLOTS order (which
## already runs back line → followers, left → right).
func _entries(club: String, home: bool) -> Array[Dictionary]:
	var generated := RosterGenerator.generate_team(club)
	var start_idx := clampi(Settings.home_human_slot, 0, generated.size() - 1) if home else -1
	var entries: Array[Dictionary] = []
	for slot_index in TeamFormation.SLOTS.size():
		var slot: Dictionary = TeamFormation.SLOTS[slot_index]
		var roster_idx := TeamFormation.ROSTER_ORDER.find(slot_index)
		var base: Dictionary = generated[roster_idx]
		var you := roster_idx == start_idx
		var profiled := home and (CharacterProfile.apply_all or you)
		var entry := {
			"pos": TeamFormation.position_label(slot),
			"number": int(base["number"]),
			"name": "YOU" if you else String(base["name"]),
			"line": int(slot["line"]),
			"you": you,
			"height": CharacterProfile.height if profiled else Tuning.CHARACTER_HEIGHT_DEFAULT,
			"speed": CharacterProfile.speed if profiled else Tuning.CHARACTER_SPEED_DEFAULT,
			"agility": CharacterProfile.agility if profiled else Tuning.CHARACTER_AGILITY_DEFAULT,
			"kick_power": CharacterProfile.kick_power if profiled \
				else Tuning.CHARACTER_KICK_POWER_DEFAULT,
			"kick_accuracy": CharacterProfile.kick_accuracy if profiled \
				else Tuning.CHARACTER_KICK_ACCURACY_DEFAULT,
		}
		entry["overall"] = RosterGenerator.overall(entry)
		entries.append(entry)
	return entries


func _cells(entry: Dictionary) -> Array:
	return [
		entry["pos"],
		"%d" % entry["number"],
		entry["name"],
		"%.0f" % entry["height"],
		"%.1f" % entry["speed"],
		"%.2f" % entry["agility"],
		"%.2f" % entry["kick_power"],
		"%.0f" % (float(entry["kick_accuracy"]) * 100.0),
		"%d" % entry["overall"],
	]


func _summary(squad: Array[Dictionary]) -> String:
	var overall := 0.0
	var height := 0.0
	for entry in squad:
		overall += float(entry["overall"])
		height += float(entry["height"])
	var count := maxf(1.0, float(squad.size()))
	return "%d PLAYERS   ·   AVG OVR %d   ·   AVG HT %.0f cm" % [squad.size(),
		roundi(overall / count), height / count]


func _scope_text(home: bool) -> String:
	if not home:
		return "DEFAULT STATS"
	return "PROFILE STATS ON ALL 18" if CharacterProfile.apply_all \
		else "PROFILE STATS ON YOU, DEFAULTS ELSEWHERE"
