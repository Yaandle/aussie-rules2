class_name MatchCameraPlan
extends RefCounted

## Which camera films each stretch of the full match
## (docs/HIGHLIGHTS_FULLGAME_PLAN.md step 4; the user chose to set cameras on
## the Highlights screen's timeline, 2026-11-16).
##
## Every listed moment's stretch (its clip window, `match_from`..`match_to`
## in recording frames) is filmed from that moment's own camera, the same
## `camera` the clip export and the export window use, with the moment's
## framing context (type, focus player, attack direction, the goal's hold),
## so the full video shows a moment exactly as its clip does. Everywhere else
## is the match camera (HighlightPrefs.match_camera()). Where two moments'
## stretches overlap, the better-ranked one wins (moments are kept best
## first). A change of stretch is a cut: the camera snaps.

var default_preset := HighlightTable.FULL_MATCH_CAMERA
## Best first: {id, label, from, to, preset, context}.
var stretches: Array[Dictionary] = []


## `moments`: Highlights' dictionaries (best first) that have `match_from`.
static func from_moments(moments: Array[Dictionary], default_preset: String) -> MatchCameraPlan:
	var plan := MatchCameraPlan.new()
	plan.default_preset = default_preset
	for m in moments:
		if not m.has("match_from"):
			continue
		var clip: ReplayClip = m.get("clip")
		var meta: Dictionary = clip.meta if clip != null else {}
		var type := String(m.type)
		# The director needs the scoring kick, in match frames like the rest.
		var kick: Variant = null
		if m.get("kick_frame") != null:
			kick = int(m.match_from) + int(m.kick_frame)
		plan.stretches.append({
			"id": m.get("id"), "label": String(m.get("label", type)),
			"from": int(m.match_from), "to": int(m.match_to),
			"preset": String(m.get("camera", HighlightPrefs.camera_for(type))),
			"context": {"type": type, "focus": meta.get("focus", []),
				"attack_dir": meta.get("attack_dir", 1.0), "event_frame": int(m.match_frame),
				"hold_until": int(m.match_to), "kick_frame": kick},
		})
	return plan


## The stretch filming recording frame `frame`: an index into `stretches`,
## or -1 for the match camera.
func at(frame: int) -> int:
	for i in stretches.size():
		if frame >= int(stretches[i].from) and frame <= int(stretches[i].to):
			return i
	return -1


func preset(index: int) -> String:
	return String(stretches[index].preset) if index >= 0 else default_preset


## The stage context for stretch `index` ({} for the match camera).
func context(index: int) -> Dictionary:
	return stretches[index].context if index >= 0 else {}


## The plan in video frames, for match_video.json: one entry per run of the
## video filmed by the same camera, {video_from, video_to, preset, moment}
## (`moment` the moment id, or null for the match camera).
func video_runs(cut: FullMatchCut) -> Array:
	var out: Array = []
	var current := -2
	for r in cut.keep:
		for j in int(r.video_frames):
			var v := int(r.video_from) + j
			var s := at(int(round(cut.source_frame(r, float(j)))))
			if s != current or out.is_empty():
				out.append({"video_from": v, "video_to": v, "preset": preset(s),
					"moment": stretches[s].id if s >= 0 else null})
				current = s
			else:
				out[-1].video_to = v
	return out
