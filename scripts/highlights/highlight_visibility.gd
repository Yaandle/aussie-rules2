class_name HighlightVisibility
extends Node

## How well a moment is filmed, from the camera it will be exported with:
## the ranking pass the 2026-11-24 audit asked for (docs/HIGHLIGHTS_AUDIT.md,
## plan item 1). Close, clear footage of the key moment ranks up; distant,
## blocked or out-of-frame footage ranks down; the Highlights page shows the
## numbers and the reasons, so a moment's place in the list can be read.
##
## It walks the moment's clip exactly as the export would (same director,
## same framing, same smoothing) on a `light` ReplayStage: positions only, no
## puppets, nothing drawn (its own SubViewport, own world, never updated), so
## a 150-frame clip measures in a few milliseconds and the page stays live.
## The projection is done by hand from the camera's transform and lens, so
## it needs no renderer either: it also runs headless and in the exporter.
##
## Per moment, `camera_quality`:
##   score       0-100 (SIZE_POINTS + BALL_POINTS + CLEAR_POINTS + KEY_POINTS)
##   subject_px  median on-screen height of the main player(s), at 1080 lines,
##               over the frames a player is the subject (a goal's posts shot
##               is about the ball, so those frames don't count here)
##   ball_vis    share of frames with the ball in frame
##   blocked     share of frames with scenery or another player between the
##               lens and the subject
##   key_seen    the key thing (the ball for a score or long kick, the marker
##               for a mark, the pair for a tackle) in frame on the event frame
##   reasons     short plain-English lines for the page
## and `rank_score` = highlight_score × (RANK_FLOOR + (1 - RANK_FLOOR) × score / 100).
## The moment's own `highlight_score` (how good the play was) is untouched.
## Contrast and colour can't be judged without rendering pixels, so they
## aren't part of the score. Every number here is an unplaytested guess.

## A player this tall on screen (1080 lines) is full marks for size; under
## SIZE_FLOOR px scores nothing.
const SIZE_FULL := 220.0
const SIZE_FLOOR := 40.0
const SIZE_POINTS := 40.0
const BALL_POINTS := 20.0
const CLEAR_POINTS := 25.0
const KEY_POINTS := 15.0
## A good moment filmed badly keeps this share of its score.
const RANK_FLOOR := 0.6
## A body counts as in the way within this distance of the sight line, m.
const BLOCK_RADIUS := 0.45
## The key thing must sit this far inside the frame's edge (fraction of the
## half-frame) to count as seen.
const KEY_INSET := 0.9
const SUBJECT_HEIGHT := 1.9
const LINES := 1080.0

var _view: SubViewport
var _stage: ReplayStage
var _camera: Camera3D
var _queue: Array[Dictionary] = []
## The moment being measured and how far it has got.
var _job := {}


## `field`: the Field of a stage that's already built (the page's or the
## exporter's): this one borrows its goal lines and scenery.
func setup(field: Field) -> void:
	_view = SubViewport.new()
	_view.own_world_3d = true
	_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_view.size = Vector2i(16, 16)
	add_child(_view)
	_stage = ReplayStage.new()
	_stage.light = true
	_stage.shared_field = field
	_view.add_child(_stage)
	_camera = Camera3D.new()
	_view.add_child(_camera)


## Queues `moments` (Highlights' dictionaries) for step().
func start(moments: Array[Dictionary]) -> void:
	_queue = moments.duplicate()
	_job = {}


func pending() -> int:
	return _queue.size() + (0 if _job.is_empty() else 1)


## Measures queued moments for at most `budget_usec`; true when none are
## left. Each finished moment gets camera_quality and rank_score.
func step(budget_usec: int) -> bool:
	var until := Time.get_ticks_usec() + budget_usec
	while Time.get_ticks_usec() < until:
		if _job.is_empty():
			if _queue.is_empty():
				return true
			_job = _begin(_queue.pop_front())
			if _job.is_empty():
				continue
		if _advance(_job, until):
			_finish(_job)
			_job = {}
	return _queue.is_empty() and _job.is_empty()


## Measures one moment straight through (a camera change, the exporter).
func measure_now(moment: Dictionary) -> void:
	var job := _begin(moment)
	if job.is_empty():
		return
	_advance(job, Time.get_ticks_usec() + 60_000_000)
	_finish(job)


func _begin(moment: Dictionary) -> Dictionary:
	var clip: ReplayClip = moment.get("clip")
	if clip == null or clip.frame_count() == 0:
		return {}
	_stage.load_clip(clip)
	var meta := clip.meta
	var focus: Array[int] = []
	for i: Variant in meta.get("focus", []):
		if int(i) >= 0 and int(i) < (meta.bodies as Array).size():
			focus.append(int(i))
	var kick: Variant = meta.get("kick_frame")
	return {"moment": moment, "clip": clip, "frame": 0, "focus": focus,
		"type": String(moment.type), "event": int(meta.get("event_frame", 0)),
		"kick": int(kick) if kick != null else -1,
		"preset": String(moment.get("camera", HighlightPrefs.camera_for(String(moment.type)))),
		"px": [], "ball_in": 0, "blocked": 0, "key_seen": false}


## Runs frames until the clip ends (true) or the clock passes `until`.
func _advance(job: Dictionary, until: int) -> bool:
	var clip: ReplayClip = job.clip
	var n := clip.frame_count()
	var fps := clip.fps()
	var occ := _stage.occluders()
	while int(job.frame) < n:
		var i := int(job.frame)
		var t := float(i) / fps
		_stage.apply(t)
		_stage.frame_camera(_camera, String(job.preset), false, t, 1.0 / fps, i == 0)
		var cam := _camera.global_transform
		var ball := clip.ball_position(i)
		if _in_frame(cam, ball, 1.0):
			job.ball_in = int(job.ball_in) + 1
		# The subject this frame: the focus players, except a score or long
		# kick once the ball is away (then the ball is the subject).
		var type := String(job.type)
		var ball_is_subject := (job.focus as Array).is_empty() \
			or ((type == "goal" or type == "behind" or type == "long_kick")
				and int(job.kick) >= 0 and i > int(job.kick) + 10) \
			or ((type == "goal" or type == "behind") and int(job.kick) < 0)
		var target := ball
		if not ball_is_subject:
			var best := 0.0
			var mid := Vector3.ZERO
			for b: int in job.focus:
				var base := clip.body_position(i, b)
				var scale := float((clip.meta.bodies[b] as Dictionary).get("scale", 1.0))
				best = maxf(best, _screen_height(cam, base, base + Vector3.UP * SUBJECT_HEIGHT * scale))
				mid += base
			mid /= float((job.focus as Array).size())
			target = mid + Vector3.UP * 1.0
			(job.px as Array).append(best)
		if occ.check(cam.origin, target).blocked or _player_in_way(clip, i, cam.origin, target, job.focus):
			job.blocked = int(job.blocked) + 1
		if i == int(job.event):
			var key := ball if (type == "goal" or type == "behind" or type == "long_kick" or ball_is_subject) else target
			job.key_seen = _in_frame(cam, key, KEY_INSET)
		job.frame = i + 1
		if Time.get_ticks_usec() >= until:
			return int(job.frame) >= n
	return true


func _finish(job: Dictionary) -> void:
	var clip: ReplayClip = job.clip
	var n := float(maxi(1, clip.frame_count()))
	var px: Array = job.px
	var sorted := px.duplicate()
	sorted.sort()
	var median := float(sorted[sorted.size() / 2]) if not sorted.is_empty() else -1.0
	var ball_vis := float(job.ball_in) / n
	var blocked := float(job.blocked) / n
	var size_part := ball_vis if median < 0.0 else clampf((median - SIZE_FLOOR) / (SIZE_FULL - SIZE_FLOOR), 0.0, 1.0)
	var score := SIZE_POINTS * size_part + BALL_POINTS * ball_vis + CLEAR_POINTS * (1.0 - blocked) \
		+ (KEY_POINTS if job.key_seen else 0.0)
	var reasons: Array[String] = []
	if median >= 0.0:
		var word := "close" if median >= 180.0 else "mid" if median >= 90.0 else "distant"
		reasons.append("players %d px tall (%s)" % [roundi(median), word])
	reasons.append("ball in frame %d%%" % roundi(ball_vis * 100.0))
	reasons.append("view clear" if blocked < 0.05 else "something in the way %d%% of the time" % roundi(blocked * 100.0))
	var key_name: String = {"goal": "the ball at the posts", "behind": "the ball at the posts", "mark": "the catch",
		"tackle": "the tackle", "bump": "the bump", "long_kick": "the ball", "ruck": "the hit-out"}.get(
		String(job.type), "the moment")
	reasons.append(("%s in frame" if job.key_seen else "%s out of frame") % key_name)
	var moment: Dictionary = job.moment
	moment["camera_quality"] = {"score": roundi(score), "subject_px": roundi(median) if median >= 0.0 else null,
		"ball_vis": snappedf(ball_vis, 0.01), "blocked": snappedf(blocked, 0.01), "key_seen": bool(job.key_seen),
		"camera": String(job.preset), "framing": HighlightPrefs.framing(), "reasons": reasons}
	moment["rank_score"] = snappedf(rank_score(float(moment.highlight_score), score), 0.1)


static func rank_score(highlight_score: float, quality: float) -> float:
	return highlight_score * (RANK_FLOOR + (1.0 - RANK_FLOOR) * clampf(quality, 0.0, 100.0) / 100.0)


## `p` in the camera's frame, inside `inset` of the way to each edge (16:9,
## the export's landscape shape).
func _in_frame(cam: Transform3D, p: Vector3, inset: float) -> bool:
	var local := cam.affine_inverse() * p
	if local.z >= -0.05:
		return false
	var tan_v := tan(deg_to_rad(_camera.fov) * 0.5)
	var tan_h := tan_v * 16.0 / 9.0
	return absf(local.y / -local.z) <= tan_v * inset and absf(local.x / -local.z) <= tan_h * inset


func _screen_height(cam: Transform3D, base: Vector3, top: Vector3) -> float:
	var a := cam.affine_inverse() * base
	var b := cam.affine_inverse() * top
	if a.z >= -0.05 or b.z >= -0.05:
		return 0.0
	var tan_v := tan(deg_to_rad(_camera.fov) * 0.5)
	return absf(a.y / -a.z - b.y / -b.z) / (2.0 * tan_v) * LINES


## Another player standing on the sight line from the lens to the subject
## (not within a metre of either end).
static func _player_in_way(clip: ReplayClip, frame: int, from: Vector3, to: Vector3, skip: Array) -> bool:
	var span := to - from
	var length := span.length()
	if length < 2.5:
		return false
	for i in (clip.meta.bodies as Array).size():
		if skip.has(i) or String(clip.meta.bodies[i].kind) != "player":
			continue
		var p := clip.body_position(frame, i)
		var along := clampf((p + Vector3.UP * 1.0 - from).dot(span) / (length * length), 0.0, 1.0)
		if along * length < 1.0 or (1.0 - along) * length < 1.0:
			continue
		var on_line := from + span * along
		if on_line.y < p.y - 0.1 or on_line.y > p.y + 2.0:
			continue
		if Vector2(on_line.x - p.x, on_line.z - p.z).length() < BLOCK_RADIUS:
			return true
	return false
