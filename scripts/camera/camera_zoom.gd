class_name CameraZoom
extends RefCounted

## The match camera's zoom steps and named presets, shared by every screen
## that sets Settings.camera_zoom (the Full Game and Career pregame screens
## and the in-match pause menu), so they offer the same values, label them
## the same way and stay in sync: they all read and write the one setting,
## which is saved in user://settings.cfg and applied live
## (Settings.camera_zoom_changed -> BroadcastCamera.zoom).
##
## 2026-11-24 highlights audit: the old range (0.8-1.4 in 0.1 steps) was too
## narrow both ways. Now 0.5 (half the 3rd-person arm's reach out, or twice
## the Full-Side lens's width) to 3.0, in steps that grow with the zoom so
## each click looks about the same size. Presets are the steps with a name;
## the steps between them are the free zoom.
##
## The highlights' replay cameras do NOT use this: a replay is re-shot from
## the recorded poses and never sees the match camera, and a zoom picked to
## play (to see team-mates) is the wrong zoom for a phone video. They have
## their own framing (HighlightPrefs.framing, in the export window). So
## changing this mid-match can't touch a recording or its alignment.

const STEPS := [0.5, 0.6, 0.7, 0.8, 0.9, 1.0, 1.15, 1.3, 1.5, 1.75, 2.0, 2.5, 3.0]
const PRESETS := [
	{"name": "WIDE", "zoom": 0.6},
	{"name": "STANDARD", "zoom": 1.0},
	{"name": "CLOSE", "zoom": 1.5},
	{"name": "TIGHT", "zoom": 2.5},
]


## Index of the step nearest `zoom`.
static func index_of(zoom: float) -> int:
	var best := 0
	for i in STEPS.size():
		if absf(float(STEPS[i]) - zoom) < absf(float(STEPS[best]) - zoom):
			best = i
	return best


## The zoom `step` clicks from `zoom` (clamped at the ends; `wrap` goes
## round from the widest to the tightest and back).
static func stepped(zoom: float, step: int, wrap := false) -> float:
	var i := index_of(zoom) + step
	if wrap:
		i = posmod(i, STEPS.size())
	return float(STEPS[clampi(i, 0, STEPS.size() - 1)])


## The next named preset after `zoom` (wrapping), for one-button cycling.
static func next_preset(zoom: float) -> float:
	for preset: Dictionary in PRESETS:
		if float(preset.zoom) > zoom + 0.001:
			return float(preset.zoom)
	return float(PRESETS[0].zoom)


## "CLOSE 150%" on a preset, "130%" between them.
static func label(zoom: float) -> String:
	for preset: Dictionary in PRESETS:
		if is_equal_approx(float(preset.zoom), zoom):
			return "%s %d%%" % [preset.name, roundi(zoom * 100.0)]
	return "%d%%" % roundi(zoom * 100.0)


## Every step as a label, for a row that cycles options.
static func labels() -> Array[String]:
	var out: Array[String] = []
	for z: float in STEPS:
		out.append(label(z))
	return out
