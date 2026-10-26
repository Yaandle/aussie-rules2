class_name CareerLadderTable
extends RefCounted

## The league ladder as a CareerTable card, with a green cut line under
## the last promotion place. Shared by the Dashboard and the Season
## Summary. Rows are CareerSeason.ladder() dicts.

## PTS and % last, as on a real AFL ladder. The number columns are as
## narrow as two digits allow: the longest generated name ("Jindivick
## Magpies") needs ~150 px of TEAM.
const COLUMNS := [
	{"label": "", "width": 22.0, "align": HORIZONTAL_ALIGNMENT_RIGHT},
	{"label": "TEAM", "width": 0.0, "align": HORIZONTAL_ALIGNMENT_LEFT},
	{"label": "P", "width": 24.0, "align": HORIZONTAL_ALIGNMENT_RIGHT},
	{"label": "W", "width": 24.0, "align": HORIZONTAL_ALIGNMENT_RIGHT},
	{"label": "L", "width": 24.0, "align": HORIZONTAL_ALIGNMENT_RIGHT},
	{"label": "D", "width": 24.0, "align": HORIZONTAL_ALIGNMENT_RIGHT},
	{"label": "%", "width": 52.0, "align": HORIZONTAL_ALIGNMENT_RIGHT},
	{"label": "PTS", "width": 36.0, "align": HORIZONTAL_ALIGNMENT_RIGHT},
]


## `cut_after` draws the promotion line under that many rows (0 for none).
static func build(ladder: Array[Dictionary], width: float, cut_after: int) -> Control:
	var rows: Array = []
	for i in ladder.size():
		var row := ladder[i]
		rows.append({"you": row["you"], "cells": [
			"%d" % (i + 1),
			String(row["team"]),
			"%d" % row["played"],
			"%d" % row["won"],
			"%d" % row["lost"],
			"%d" % row["drawn"],
			"%.1f" % row["percentage"],
			"%d" % row["points"],
		]})
	return CareerTable.build(COLUMNS, rows, width, cut_after)
