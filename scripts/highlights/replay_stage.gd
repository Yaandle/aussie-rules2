class_name ReplayStage
extends Node3D

## Plays a ReplayClip back: the oval, a puppet for every recorded body and
## the ball, posed frame by frame from the recording. No physics, brains or
## AnimationTree on anything here; the puppets are bare HumanoidRigs in the
## recorded model and kit, so a replay can't change what happened, only how
## it's framed.
##
## The camera is the point of replaying rather than capturing video: each
## moment can be shot from a new angle (CAMERA_PRESETS), and the vertical
## 9:16 export reframes the same footage instead of cropping it.

const FIELD_SCENE := preload("res://scenes/field/field.tscn")
const BALL_SCENE := preload("res://scenes/ball/ball.tscn")
const ENVIRONMENT := preload("res://materials/broadcast_environment.tres")

## Broadcast: up in the stand on the wing. Close: down at ground level,
## circling the contest. End: from behind the play, looking back at it (for
## a goal, from behind the posts). Third: the in-game chase camera, behind
## and above the moment's main player (the kicker, marker, tackler...),
## looking the way they're going. All distances in metres, unplaytested
## framing guesses.
## Auto (2026-11-24) is the director: it picks and cuts between shots by the
## moment's type and what the ball is doing (see "The director" below).
const CAMERA_PRESETS := ["auto", "broadcast", "close", "end", "third"]
const PRESET_LABELS := {"auto": "AUTO", "broadcast": "BROADCAST", "close": "CLOSE", "end": "END-ON",
	"third": "THIRD PERSON"}
## Where each type is shot from unless the player picks (HighlightPrefs.camera_for
## reads this as its fallback). Every type is the director since 2026-11-24
## (audit: kicks and marks shot from behind, goals missing the ball at the
## posts, broadcast players ~70 px tall).
const DEFAULT_PRESET := {"goal": "auto", "behind": "auto", "mark": "auto",
	"tackle": "auto", "bump": "auto", "long_kick": "auto", "ruck": "auto", "general": "auto"}
## The defaults before the director, so HighlightPrefs can tell a camera the
## player picked from one it only saved because it was the default.
const OLD_DEFAULT_PRESET := {"goal": "broadcast", "behind": "broadcast", "mark": "broadcast",
	"tackle": "third", "bump": "third", "long_kick": "broadcast", "ruck": "close", "general": "broadcast"}
const BROADCAST_OFFSET := Vector3(0.0, 15.0, 34.0)
const CLOSE_RADIUS := 8.5
const CLOSE_HEIGHT := 2.6
const CLOSE_ORBIT_SPEED := 0.12   ## rad/s
const END_BACK := 30.0
const END_HEIGHT := 8.0
## The end-on and third-person cameras stay within the fence: this far past
## the boundary.
const END_FENCE_MARGIN := 3.0
## Third person is the match's chase camera (Tuning.CAM_DISTANCE, CAM_PITCH_DEFAULT,
## CAM_FOCUS_HEIGHT, the look-ahead, the ball pull and the sprint FOV), minus
## the stick: a replay has no stick, so it turns to the way the player is
## going instead (unplaytested feel guesses below).
## How fast it swings round behind a new heading, 1/s.
const THIRD_HEADING_RATE := 3.0
## Heading is where the player was going over this many frames either side;
## under THIRD_MIN_SPEED (m/s) they're standing, so it uses the way they face.
const THIRD_HEADING_FRAMES := 5
const THIRD_MIN_SPEED := 1.5
## 9:16 gets a wider vertical field of view than the match's 64 degrees, as
## the other presets do, so the narrow frame still holds the contest.
const THIRD_FOV_PORTRAIT := 78.0
## After a goal or behind the camera follows the ball only this far past the
## goal line (and never when it jumps: the ball is reset to the centre for
## the bounce, which used to drag the camera there, and a long ball ran on
## into the trees).
const FOLLOW_PAST_GOAL := 3.0
const BALL_JUMP := 8.0
## Portrait gets a wider vertical field of view and comes in closer, so the
## narrow frame still holds the contest.
const FOV_LANDSCAPE := 40.0
const FOV_PORTRAIT := 62.0
const PORTRAIT_PULL_IN := 0.75
## How fast the camera eases onto its target, 1/s.
const CAMERA_SMOOTHING := 4.0
const TARGET_SMOOTHING := 6.0

var clip: ReplayClip

var _field: Field
var _ball: Node3D
var _puppets: Array[Dictionary] = []
var _decoded := {}
var _focus_point := Vector3.ZERO
var _ball_point := Vector3.ZERO
## The moment's main player (clip focus[0]), for the third-person camera: the
## point on them to frame, which way they're heading and how fast.
var _main_point := Vector3.ZERO
var _main_heading := Vector3.FORWARD
var _main_speed := 0.0
## First frame a goal/behind clip stops following the ball, or -1; and the
## x the followed ball never passes (a goal/behind's goal line plus
## FOLLOW_PAST_GOAL, `_limit_dir` 1 or -1 for which end; 0 for other types).
var _hold_frame := -1
var _limit_x := 0.0
var _limit_dir := 0
## What the cameras treat as the ball (see _followed_ball).
var _follow_ball := Vector3.ZERO
var _cameras := {}
## Overrides for the clip's own meta (`type`, `focus`, `attack_dir`,
## `event_frame`, plus `hold_until`, the last frame a goal's hold search may
## look at): set_context. The full-match recording has none of these, so a
## moment's stretch of it is shot by handing the stage that moment's
## (MatchCameraPlan), and the cameras frame it as the moment's own clip would.
var _context := {}
## The dressing and bodies a camera keeps out of (CameraOccluders), built on
## first use once the Field has dressed itself.
var _occluders: CameraOccluders = null
## The frame being shown (fractional) and its two recorded neighbours.
var _frame_f := 0.0
var _cur_a := {}
var _cur_b := {}
var _cur_w := 0.0
## The director's shot list for the loaded clip and context (_plan_shots).
var _shots: Array[Dictionary] = []


func _ready() -> void:
	var environment := WorldEnvironment.new()
	environment.environment = ENVIRONMENT
	add_child(environment)
	var sun := DirectionalLight3D.new()
	# full_game.tscn's Sun, setting for setting, so a replay is lit like the
	# match. A .tscn writes a Transform3D's basis row by row, but Basis()
	# takes columns: hence transposed(). Without it the sun pointed up from
	# under the ground and the replay was lit by ambient alone (playtest
	# 2026-11-10: "looks too dark").
	sun.transform = Transform3D(Basis(Vector3(0.8637, -0.3627, 0.3499), Vector3(0.0, 0.6943, 0.7197),
		Vector3(-0.5039, -0.6216, 0.5998)).transposed(), Vector3(0.0, 40.0, 0.0))
	sun.light_energy = 1.05
	sun.light_angular_distance = 2.2
	sun.shadow_enabled = true
	sun.shadow_opacity = 0.72
	sun.directional_shadow_max_distance = 120.0
	sun.directional_shadow_blend_splits = true
	add_child(sun)
	_field = FIELD_SCENE.instantiate() as Field
	_field.follow_field_style = true
	add_child(_field)
	_ball = _make_ball()
	add_child(_ball)


## A ball that only looks like one: the match ball's mesh and stretch,
## without its RigidBody or script (never added to the tree, so its _ready
## never runs).
func _make_ball() -> Node3D:
	var holder := Node3D.new()
	holder.name = "ReplayBall"
	var source := BALL_SCENE.instantiate()
	var mesh := MeshInstance3D.new()
	mesh.mesh = (source.get_node("MeshInstance3D") as MeshInstance3D).mesh
	mesh.scale = Vector3(1.0, 1.0, Tuning.BALL_SEMI_MAJOR / Tuning.BALL_SEMI_MINOR)
	source.free()
	holder.add_child(mesh)
	return holder


## Builds puppets for `new_clip`'s bodies. Cheap to call again with a clip
## from the same match: the puppets are kept when the body table matches.
func load_clip(new_clip: ReplayClip) -> void:
	var same := clip != null and _puppets.size() == (new_clip.meta.bodies as Array).size()
	clip = new_clip
	_decoded.clear()
	if not same:
		_build_puppets()
	_cameras.clear()
	_context = {}
	_hold_frame = _find_hold_frame()
	_shots = _plan_shots()


## Shoots the loaded clip as if it were the moment `context` describes (see
## `_context`); {} goes back to the clip's own meta. The caller snaps the
## camera after a change: a new stretch is a cut.
func set_context(context: Dictionary) -> void:
	if context == _context:
		return
	_context = context
	_hold_frame = _find_hold_frame()
	_shots = _plan_shots()


func _meta(key: String, default: Variant) -> Variant:
	if _context.has(key):
		return _context[key]
	return clip.meta.get(key, default) if clip != null else default


func _build_puppets() -> void:
	for p in _puppets:
		if p.kind == "player" and is_instance_valid(p.node):
			p.node.queue_free()
	_puppets.clear()
	var officials := _field.get_node_or_null(^"Umpires")
	for body: Dictionary in clip.meta.bodies:
		var entry := {"kind": body.kind, "scale": float(body.get("scale", 1.0)), "node": null, "skeleton": null}
		if body.kind == "player":
			var rig := HumanoidRig.new()
			rig.away_kit = bool(body.get("away_kit", false))
			rig.guernsey_number = int(body.get("number", 0))
			var model := String(body.get("model", "procedural"))
			if model == "procedural":
				rig.allow_imported_character = false
			else:
				rig.character_model_override = model
			var kit: Dictionary = body.get("kit", {})
			if kit.has("jersey"):
				rig.kit_torso = Color(kit.jersey)
				rig.kit_shorts = Color(kit.shorts)
				rig.kit_socks = Color(kit.socks)
				rig.kit_boot = Color(kit.boot)
				rig.kit_skin = Color(kit.skin)
			add_child(rig)
			entry.node = rig
			entry.skeleton = rig.skeleton()
		elif officials != null and int(body.get("slot", -1)) < officials.get_child_count():
			var umpire := officials.get_child(int(body.slot)) as Umpire
			if umpire != null:
				# The recording has the flags and the throw-up in it already.
				umpire.set_process(false)
				for child in umpire.get_children():
					if child is HumanoidRig:
						entry.skeleton = (child as HumanoidRig).skeleton()
				entry.node = umpire
		_puppets.append(entry)


func _frame(index: int) -> Dictionary:
	if not _decoded.has(index):
		if _decoded.size() > 8:
			_decoded.clear()
		var decoded := clip.decode(index)
		decoded["index"] = index
		_decoded[index] = decoded
	return _decoded[index]


## Poses everything at `t` seconds into the clip, between recorded frames.
func apply(t: float) -> void:
	if clip == null or clip.frame_count() == 0:
		return
	var f := clampf(t * clip.fps(), 0.0, float(clip.frame_count() - 1))
	var ia := int(floor(f))
	var ib := mini(ia + 1, clip.frame_count() - 1)
	var w := f - float(ia)
	var a := _frame(ia)
	var b := _frame(ib)
	_frame_f = f
	_cur_a = a
	_cur_b = b
	_cur_w = w
	_ball.global_transform = Transform3D(Basis((a.ball_rot as Quaternion).slerp(b.ball_rot, w)),
		(a.ball_pos as Vector3).lerp(b.ball_pos, w))
	_ball_point = _ball.global_position
	for i in _puppets.size():
		var puppet := _puppets[i]
		var node: Node3D = puppet.node
		var skeleton: Skeleton3D = puppet.skeleton
		if node == null or skeleton == null:
			continue
		var ba: Dictionary = a.bodies[i]
		var bb: Dictionary = b.bodies[i]
		var rot := (ba.rot as Quaternion).slerp(bb.rot, w)
		var basis := Basis(rot).scaled(Vector3.ONE * float(puppet.scale))
		node.global_transform = Transform3D(basis, (ba.pos as Vector3).lerp(bb.pos, w))
		var bones_a: Array[Quaternion] = ba.bones
		var bones_b: Array[Quaternion] = bb.bones
		var count := mini(bones_a.size(), skeleton.get_bone_count())
		for k in count:
			skeleton.set_bone_pose_rotation(k, bones_a[k].slerp(bones_b[k], w))
		var pos_bones: Array = clip.meta.bodies[i].pos_bones
		var pos_a: Array[Vector3] = ba.bone_pos
		var pos_b: Array[Vector3] = bb.bone_pos
		for k in pos_bones.size():
			if int(pos_bones[k]) < skeleton.get_bone_count():
				skeleton.set_bone_pose_position(int(pos_bones[k]), pos_a[k].lerp(pos_b[k], w))
	if _occluders != null:
		_occluders.bodies.clear()
		for i in _puppets.size():
			if _puppets[i].kind == "player":
				_occluders.bodies.append((a.bodies[i].pos as Vector3).lerp(b.bodies[i].pos, w))
	_follow_ball = _followed_ball(a)
	_focus_point = _compute_focus(a, b, w)
	_update_main(f, a, b, w)


## What the camera follows: the ball, except in a tackle or bump, where it's
## the two bodies in it (the ball's often spilled away from them).
func _compute_focus(a: Dictionary, b: Dictionary, w: float) -> Vector3:
	var type := String(_meta("type", ""))
	var focus: Array = _meta("focus", [])
	if (type == "tackle" or type == "bump") and not focus.is_empty():
		var sum := Vector3.ZERO
		var n := 0
		for i: int in focus:
			if i < 0 or i >= a.bodies.size():
				continue
			sum += (a.bodies[i].pos as Vector3).lerp(b.bodies[i].pos, w)
			n += 1
		if n > 0:
			return sum / float(n) + Vector3.UP * 1.0
	return _follow_ball


## The ball, or for a goal or behind, where it was when the clip stopped
## following it (see _find_hold_frame).
func _followed_ball(a: Dictionary) -> Vector3:
	var p := _ball_point
	if _hold_frame >= 0 and int(a.index) >= _hold_frame:
		p = clip.ball_position(_hold_frame - 1)
	if _limit_dir != 0 and float(_limit_dir) * (p.x - _limit_x) > 0.0:
		p.x = _limit_x
	return p


## Goals and behinds: the first frame after the score where the ball is past
## the goal line by FOLLOW_PAST_GOAL, or has jumped (the reset to the centre).
## Found once per clip, so scrubbing and exporting agree.
func _find_hold_frame() -> int:
	var type := String(_meta("type", ""))
	_limit_dir = 0
	if clip == null:
		return -1
	if (type != "goal" and type != "behind") or _field == null:
		# Any other moment: hold where the ball was if it jumps (a reset for
		# a bounce or a kick-in) after the moment, so the camera never
		# whips across the ground mid-clip (2026-11-24 audit).
		if type == "":
			return -1
		var from := int(_meta("event_frame", 0))
		var to := mini(clip.frame_count(), int(_meta("hold_until", clip.frame_count() - 1)) + 1)
		var prev := clip.ball_position(from)
		for i in range(from + 1, to):
			var q := clip.ball_position(i)
			if q.distance_to(prev) > BALL_JUMP:
				return i
			prev = q
		return -1
	var direction := 1 if float(_meta("attack_dir", 1.0)) >= 0.0 else -1
	var limit := _field.goal_line_x(direction) + float(direction) * FOLLOW_PAST_GOAL
	_limit_dir = direction
	_limit_x = limit
	var start := int(_meta("event_frame", 0))
	var previous := clip.ball_position(start)
	var until := mini(clip.frame_count(), int(_meta("hold_until", clip.frame_count() - 1)) + 1)
	for i in range(start + 1, until):
		var p := clip.ball_position(i)
		if float(direction) * (p.x - limit) > 0.0 or p.distance_to(previous) > BALL_JUMP:
			return i
		previous = p
	return -1


## The main player's point and heading for the third-person camera.
func _update_main(f: float, a: Dictionary, b: Dictionary, w: float) -> void:
	var focus: Array = _meta("focus", [])
	var frame := int(round(f))
	var last := clip.frame_count() - 1
	var from := maxi(0, frame - THIRD_HEADING_FRAMES)
	var to := mini(last, frame + THIRD_HEADING_FRAMES)
	var span := maxf(float(to - from) / clip.fps(), 0.001)
	var p0: Vector3
	var p1: Vector3
	var facing := Vector3.ZERO
	if not focus.is_empty() and int(focus[0]) >= 0 and int(focus[0]) < a.bodies.size():
		var body := int(focus[0])
		_main_point = (a.bodies[body].pos as Vector3).lerp(b.bodies[body].pos, w)
		p0 = clip.body_position(from, body)
		p1 = clip.body_position(to, body)
		facing = clip.body_facing(frame, body)
	else:
		# Nobody to follow (a goal with no kicker): ride the ball.
		_main_point = _follow_ball
		p0 = clip.ball_position(from)
		p1 = clip.ball_position(to)
	var v := Vector3(p1.x - p0.x, 0.0, p1.z - p0.z) / span
	_main_speed = v.length()
	if _main_speed >= THIRD_MIN_SPEED:
		_main_heading = v / _main_speed
	else:
		facing.y = 0.0
		_main_heading = facing.normalized() if facing.length_squared() > 0.0001 else _main_heading


## The ground dressing as camera keep-out boxes (see CameraOccluders).
func occluders() -> CameraOccluders:
	if _occluders == null:
		_occluders = CameraOccluders.build(_field)
	return _occluders


## The point the broadcast, close and end-on cameras are following.
func focus_point() -> Vector3:
	return _focus_point


func event_time() -> float:
	return float(_meta("event_frame", 0)) / clip.fps() if clip != null else 0.0


func duration() -> float:
	return clip.duration() if clip != null else 0.0


func default_preset() -> String:
	return HighlightPrefs.camera_for(String(_meta("type", ""))) if clip != null else "broadcast"


## Points `camera` for this frame. `snap` jumps straight there (a new clip, a
## scrub, every export frame's first); otherwise it eases at the
## CAMERA_SMOOTHING rates over `delta`.
func frame_camera(camera: Camera3D, preset: String, portrait: bool, t: float, delta: float, snap := false) -> void:
	var key := camera.get_instance_id()
	var state: Dictionary = _cameras.get(key, {})
	if snap or state.is_empty():
		state = {"target": _focus_point, "pos": Vector3.INF}
	if preset == "auto":
		_frame_auto(camera, state, portrait, delta, snap)
		_cameras[key] = state
		return
	if preset == "broadcast":
		_frame_shot(camera, state, {"kind": "follow"}, portrait, delta, snap)
		_cameras[key] = state
		return
	if preset == "third":
		_frame_third(camera, state, portrait, delta, snap)
		_cameras[key] = state
		return
	var k_target := 1.0 - exp(-TARGET_SMOOTHING * delta)
	state.target = (state.target as Vector3).lerp(_focus_point, k_target) if not snap else _focus_point
	var target: Vector3 = state.target
	var direction := float(_meta("attack_dir", 1.0)) if clip != null else 1.0
	var pull := PORTRAIT_PULL_IN if portrait else 1.0
	var want := target
	match preset:
		"close":
			var angle := t * CLOSE_ORBIT_SPEED + PI * 0.5
			want = target + Vector3(cos(angle) * CLOSE_RADIUS * pull, CLOSE_HEIGHT, sin(angle) * CLOSE_RADIUS * pull)
		_:
			# End-on: as far back as END_BACK, but no further than the
			# framing's size rule allows (the 2026-11-24 audit measured
			# players ~90 px tall from 30 m).
			var fov := FOV_PORTRAIT if portrait else FOV_LANDSCAPE
			var back := minf(END_BACK * pull, size_distance(fov, framing_fraction()) * END_BACK
				/ Vector2(END_BACK, END_HEIGHT).length())
			var up := END_HEIGHT * back / END_BACK
			want = _inside_fence(target + Vector3(direction * back, up, 0.0), END_FENCE_MARGIN)
	want.y = maxf(want.y, 1.2)
	if state.pos == Vector3.INF:
		state.pos = want
	else:
		state.pos = (state.pos as Vector3).lerp(want, 1.0 - exp(-CAMERA_SMOOTHING * delta))
	var look := target + Vector3.UP * 0.5
	state.pos = _clear_view(state, look, state.pos, delta, snap)
	_cameras[key] = state
	camera.fov = FOV_PORTRAIT if portrait else FOV_LANDSCAPE
	camera.global_position = state.pos
	if camera.global_position.distance_squared_to(look) > 0.01:
		camera.look_at(look)


## The match's chase rig, replayed: the camera sits CAM_DISTANCE behind the
## player at CAM_PITCH_DEFAULT, looking at a point on their chest led by their
## velocity and pulled a little toward the ball while it's in the air.
func _frame_third(camera: Camera3D, state: Dictionary, portrait: bool, delta: float, snap: bool) -> void:
	var desired_yaw := atan2(-_main_heading.x, -_main_heading.z)
	if snap or not state.has("yaw"):
		state["yaw"] = desired_yaw
		state["ball_weight"] = 0.0
	else:
		state["yaw"] = lerp_angle(float(state.yaw), desired_yaw, 1.0 - exp(-THIRD_HEADING_RATE * delta))
	var lead := _main_heading * minf(_main_speed * Tuning.CAM_LOOKAHEAD_TIME, Tuning.CAM_LOOKAHEAD_MAX)
	var point := _main_point + Vector3.UP * Tuning.CAM_FOCUS_HEIGHT + lead
	var weight_goal := 0.0
	if _follow_ball.y > Tuning.CAM_BALL_FOCUS_MIN_HEIGHT:
		weight_goal = Tuning.CAM_BALL_FOCUS_MAX \
			* clampf(_follow_ball.distance_to(_main_point) / Tuning.CAM_MAX_FRAMING_DISTANCE, 0.0, 1.0)
	if snap:
		state["ball_weight"] = weight_goal
	else:
		state["ball_weight"] = lerpf(float(state.ball_weight), weight_goal,
			1.0 - exp(-Tuning.CAM_BALL_FOCUS_RATE * delta))
	point = point.lerp(_follow_ball, float(state.ball_weight))
	if snap or not state.has("focus"):
		state["focus"] = point
	else:
		state["focus"] = (state.focus as Vector3).lerp(point, 1.0 - exp(-Tuning.CAM_FOLLOW_RATE * delta))
	var focus: Vector3 = state.focus
	var pitch := -deg_to_rad(Tuning.CAM_PITCH_DEFAULT)
	var arm := Tuning.CAM_DISTANCE / Tuning.CAM_ZOOM_DEFAULT
	var behind := Basis(Vector3.UP, float(state.yaw)) * Vector3(0.0, arm * sin(pitch), arm * cos(pitch))
	var position := _inside_fence(focus + behind, END_FENCE_MARGIN)
	position.y = maxf(position.y, BroadcastCamera.MIN_CAMERA_HEIGHT)
	# The chase rig's spring arm, replayed: pull in (or lift) rather than sit
	# in a tree or another player.
	position = _clear_view(state, focus, position, delta, snap)
	camera.global_position = position
	camera.fov = THIRD_FOV_PORTRAIT if portrait else Tuning.CAM_FOV_BASE \
		+ Tuning.CAM_FOV_SPRINT_GAIN * clampf(_main_speed / Tuning.SPRINT_SPEED, 0.0, 1.0)
	if position.distance_squared_to(focus) > 0.01:
		camera.look_at(focus)


## `p` pulled in onto the oval (the boundary plus `margin`) if it's outside:
## the fence, with the trees behind it.
static func _inside_fence(p: Vector3, margin: float) -> Vector3:
	var hx := Tuning.FIELD_HALF_LENGTH + margin
	var hz := Tuning.FIELD_HALF_WIDTH + margin
	var k := (p.x * p.x) / (hx * hx) + (p.z * p.z) / (hz * hz)
	if k <= 1.0:
		return p
	var scale := 1.0 / sqrt(k)
	return Vector3(p.x * scale, p.y, p.z * scale)



# ── The director (2026-11-24) ────────────────────────────────────────
# "auto" shoots each moment as a sequence of shots chosen from its type and
# what the ball does, cutting (a snap) between them and easing within one:
#   goal / behind  the kick side-on from a little behind the kicker, the
#                  ball's flight from the wing, then a cut to behind the posts
#                  before the ball gets there, so the ball always crosses the
#                  line in frame (audit: the third-person camera missed it in
#                  3 of 8 goals)
#   mark           low and side-on to the ball's flight, the marker and the
#                  nearest opponent framed together
#   tackle / bump  side-on to the line between the two bodies, close
#   ruck           side-on to the two ruckmen
#   long kick      the kick side-on, then the flight, framed to hold the
#                  kicker and the ball while it's up
#   general / the match camera   the follow shot (smart broadcast)
# Every shot obeys the framing's size rule (HighlightTable.FRAMING_FRACTION:
# the main subject is never shorter than that share of the frame) and keeps
# out of the scenery (_clear_view). All numbers are unplaytested framing
# guesses.

## A player this tall (m) is what the size rule measures.
const SUBJECT_HEIGHT := 1.9
## Side-on shots use a longer lens than the follow shot (a compressed,
## TV-like background) and frame a little tighter than the size rule asks.
const SIDE_FOV_LANDSCAPE := 34.0
const SIDE_FOV_PORTRAIT := 56.0
const SIDE_TIGHTER := 1.6
const SIDE_MIN_DIST := 5.5
const SIDE_FIT_STRETCH := 1.5
## Elevation of each side-on shot above its look point, degrees.
const SIDE_ELEVATION := {"kick": 10.0, "mark": 7.0, "tackle": 12.0, "ruck": 11.0}
## How far round behind the kicker the kick shot sits, degrees off side-on:
## enough to see where the ball is going, not so much it's the back of a head.
const KICK_BEHIND := 35.0
## The kick shot holds this many frames past the boot.
const KICK_HOLD_FRAMES := 10
## Follow shot: the broadcast direction (BROADCAST_OFFSET), no nearer than
## FOLLOW_MIN_DIST; while the ball is well up (FLIGHT_HEIGHT) and away from the
## main player it widens to hold both, up to FLIGHT_MAX_DIST.
const FOLLOW_MIN_DIST := 9.0
const FLIGHT_HEIGHT := 3.0
const FLIGHT_MAX_DIST := 48.0
## Frame-fit slack: a framed point sits at most 1/FIT_MARGIN of the way to
## the frame's edge.
const FIT_MARGIN := 1.3
## A mark's flight shot hands over to the contest this many frames before
## the catch.
const MARK_CUT_FRAMES := 27
## The ball counts as part of a side-on shot within this many metres.
const FIT_BALL_RADIUS := 8.0
## Behind the posts: this far back from the goal line (inside the fence, which
## is Field.FENCE_OFFSET out), this high, this lens; the cut comes when the ball
## is POSTS_CUT_DIST from the line, and at least POSTS_LEAD_FRAMES before the
## score.
const POSTS_BACK := 8.0
const POSTS_HEIGHT := 6.0
const POSTS_FOV_LANDSCAPE := 60.0
const POSTS_FOV_PORTRAIT := 80.0
const POSTS_CUT_DIST := 30.0
## Highest the posts shot looks, m, and frames after the score it starts
## settling back onto the goal square.
const POSTS_LOOK_MAX_Y := 7.0
const POSTS_SETTLE_FRAMES := 8
const POSTS_LEAD_FRAMES := 24
## Easing inside a shot, 1/s.
const SHOT_LOOK_RATE := 5.0
const SHOT_DIST_RATE := 2.5
const FOLLOW_POS_RATE := 1.6
const SIDE_POS_RATE := 4.0
const RIG_MAX_SPEED := 14.0   ## m/s
## Scenery avoidance: lifts tried, metres; how fast the lift rises and falls.
const LIFT_STEPS := [1.5, 3.0, 5.0, 8.0, 12.0, 17.0]
const LIFT_UP_RATE := 9.0
const LIFT_DOWN_RATE := 1.2
## The nearest a pulled-in camera comes to what it's looking at, m.
const PULL_IN_MIN := 2.0


## The framing's minimum subject height, as a fraction of the frame.
static func framing_fraction() -> float:
	return float(HighlightTable.FRAMING_FRACTION.get(HighlightPrefs.framing(), 0.16))


## How far away a SUBJECT_HEIGHT player fills `fraction` of a frame whose
## vertical field of view is `fov_deg`.
static func size_distance(fov_deg: float, fraction: float) -> float:
	return SUBJECT_HEIGHT / (2.0 * maxf(fraction, 0.01) * tan(deg_to_rad(fov_deg) * 0.5))


## The shots the director uses for the loaded clip and context, in frame
## order: {from, kind ("side", "follow", "posts"), index, ...}. Frames are the
## loaded clip's (match frames for a full-match stretch).
func _plan_shots() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if clip == null or clip.frame_count() == 0:
		return out
	var type := String(_meta("type", ""))
	var bodies: Array[int] = []
	for i: Variant in _meta("focus", []):
		if int(i) >= 0 and int(i) < (clip.meta.bodies as Array).size():
			bodies.append(int(i))
	var last := clip.frame_count() - 1
	var event := clampi(int(_meta("event_frame", 0)), 0, last)
	var kick_meta: Variant = _meta("kick_frame", null)
	var kick := clampi(int(kick_meta), 0, last) if kick_meta != null else -1
	match type:
		"goal", "behind":
			var cut := _posts_cut_frame(kick, event)
			if kick >= 0 and not bodies.is_empty():
				out.append(_side_shot(0, "kick", [bodies[0]], _kick_axis(kick, event), kick))
				if kick + KICK_HOLD_FRAMES < cut:
					out.append({"from": kick + KICK_HOLD_FRAMES, "kind": "follow"})
			else:
				out.append({"from": 0, "kind": "follow"})
			out.append({"from": cut, "kind": "posts", "cross_z": clip.ball_position(event).z})
		"mark":
			if bodies.is_empty():
				out.append({"from": 0, "kind": "follow"})
			else:
				var axis := clip.ball_position(event) - clip.ball_position(maxi(0, event - 20))
				# A ball still well up MARK_CUT_FRAMES out is a kick on its way:
				# follow its flight, then cut to the contest as it drops in
				# (the side-on shot alone showed the ball in ~46% of frames).
				var cut := maxi(0, event - MARK_CUT_FRAMES)
				if cut > 0 and clip.ball_position(cut).y > FLIGHT_HEIGHT:
					out.append({"from": 0, "kind": "follow"})
				else:
					cut = 0
				out.append(_side_shot(cut, "mark", bodies, axis, event))
		"tackle", "bump", "ruck":
			if bodies.is_empty():
				out.append({"from": 0, "kind": "follow"})
			else:
				var axis := Vector3.RIGHT
				if bodies.size() > 1:
					axis = clip.body_position(event, bodies[1]) - clip.body_position(event, bodies[0])
				else:
					axis = clip.body_facing(event, bodies[0])
				out.append(_side_shot(0, "ruck" if type == "ruck" else "tackle", bodies, axis, event))
		"long_kick":
			if bodies.is_empty():
				out.append({"from": 0, "kind": "follow"})
			else:
				var land := mini(last, event + 60)
				out.append(_side_shot(0, "kick", [bodies[0]], _kick_axis(event, land), event))
				out.append({"from": event + KICK_HOLD_FRAMES, "kind": "follow"})
		_:
			out.append({"from": 0, "kind": "follow"})
	for i in out.size():
		out[i]["index"] = i
	return out


## Which way a kick went, kick frame to `to` (the ball's flight, flat).
func _kick_axis(kick: int, to: int) -> Vector3:
	var a := clip.ball_position(kick)
	var b := clip.ball_position(maxi(to, kick + 1))
	return Vector3(b.x - a.x, 0.0, b.z - a.z)


## A side-on shot of `bodies`, square to `axis` at frame `at`, from whichever
## side puts the camera nearer the middle of the ground (further from the
## fence and the trees); the kick shot turns KICK_BEHIND toward behind the
## kicker.
func _side_shot(from: int, kind: String, bodies: Array[int], axis: Vector3, at: int) -> Dictionary:
	axis.y = 0.0
	axis = axis.normalized() if axis.length_squared() > 0.0001 else Vector3.RIGHT
	var centre := Vector3.ZERO
	for i in bodies:
		centre += clip.body_position(at, i)
	centre /= float(bodies.size())
	var side := Vector3(-axis.z, 0.0, axis.x)
	# The side with fewer other bodies between the lens and the contest
	# (bystanders in the foreground hid a tackle, 2026-11-24 frames); on a
	# tie, the side nearer the middle of the ground.
	var block_a := _bodies_between(centre, centre + side * 12.0, bodies, at)
	var block_b := _bodies_between(centre, centre - side * 12.0, bodies, at)
	if block_b < block_a or (block_b == block_a
			and (centre + side * 10.0).length() > (centre - side * 10.0).length()):
		side = -side
	if kind == "kick":
		var a := deg_to_rad(KICK_BEHIND)
		side = (side * cos(a) - axis * sin(a)).normalized()
	return {"from": from, "kind": "side", "look": kind, "bodies": bodies, "dir": side}


## How many bodies (other than `skip`) stand within 1.2 m of the ground line
## a..b at frame `at`.
func _bodies_between(a: Vector3, b: Vector3, skip: Array[int], at: int) -> int:
	var n := 0
	var a2 := Vector2(a.x, a.z)
	var b2 := Vector2(b.x, b.z)
	for i in (clip.meta.bodies as Array).size():
		if skip.has(i) or String(clip.meta.bodies[i].kind) != "player":
			continue
		var p := clip.body_position(at, i)
		var q := Geometry2D.get_closest_point_to_segment(Vector2(p.x, p.z), a2, b2)
		if q.distance_to(Vector2(p.x, p.z)) < 1.2 and q.distance_to(a2) > 1.0:
			n += 1
	return n


## The frame the goal shot cuts behind the posts: when the ball first comes
## within POSTS_CUT_DIST of the line after the kick shot, and no later than
## POSTS_LEAD_FRAMES before the score.
func _posts_cut_frame(kick: int, event: int) -> int:
	var start := kick + KICK_HOLD_FRAMES if kick >= 0 else 0
	var direction := 1 if float(_meta("attack_dir", 1.0)) >= 0.0 else -1
	var line := _field.goal_line_x(direction) if _field != null else float(direction) * Tuning.FIELD_HALF_LENGTH
	var cut := event - POSTS_LEAD_FRAMES
	for i in range(maxi(start, 0), event):
		if absf(line - clip.ball_position(i).x) < POSTS_CUT_DIST:
			cut = mini(cut, i)
			break
	if kick >= 0:
		cut = maxi(cut, kick + 6)
	return clampi(cut, 0, event)


func _shot_at(frame: float) -> Dictionary:
	if _shots.is_empty():
		return {"from": 0, "kind": "follow", "index": 0}
	var pick: Dictionary = _shots[0]
	for shot in _shots:
		if float(shot.from) <= frame + 0.001:
			pick = shot
	return pick


## The director's shot for the current frame, as {kind, index}, for the
## Highlights screen and match_video.json.
func current_shot() -> Dictionary:
	var shot := _shot_at(_frame_f)
	return {"kind": String(shot.get("look", shot.kind)), "index": int(shot.get("index", 0))}


func _frame_auto(camera: Camera3D, state: Dictionary, portrait: bool, delta: float, snap: bool) -> void:
	var shot := _shot_at(_frame_f)
	if int(state.get("shot", -1)) != int(shot.get("index", 0)):
		snap = true   # a new shot is a cut
		state["shot"] = int(shot.get("index", 0))
	_frame_shot(camera, state, shot, portrait, delta, snap)


## Points `camera` for one director shot (also the "broadcast" preset: a
## follow shot on its own).
func _frame_shot(camera: Camera3D, state: Dictionary, shot: Dictionary, portrait: bool, delta: float,
		snap: bool) -> void:
	var kind := String(shot.kind)
	var fov := FOV_PORTRAIT if portrait else FOV_LANDSCAPE
	var look := _focus_point + Vector3.UP * 0.5
	var dir := BROADCAST_OFFSET.normalized()
	var dist := 0.0
	var aspect := 9.0 / 16.0 if portrait else 16.0 / 9.0
	match kind:
		"posts":
			fov = POSTS_FOV_PORTRAIT if portrait else POSTS_FOV_LANDSCAPE
			var direction := 1 if float(_meta("attack_dir", 1.0)) >= 0.0 else -1
			var line := _field.goal_line_x(direction) if _field != null else float(direction) * Tuning.FIELD_HALF_LENGTH
			var pos := Vector3(line + float(direction) * POSTS_BACK, POSTS_HEIGHT,
				clampf(float(shot.get("cross_z", 0.0)) * 0.5, -6.0, 6.0))
			# Not swung all the way to a ball that's still far out: aimed
			# between it and the goal mouth until it's close.
			var mouth := Vector3(line, 2.5, 0.0)
			var near := clampf(1.0 - (absf(_follow_ball.x - line) - 10.0) / 40.0, 0.0, 1.0)
			look = mouth.lerp(_follow_ball, lerpf(0.55, 1.0, near))
			# Never tilted up into empty sky after a high kick (first frames:
			# a dot on blue): the posts and the ground stay in the bottom of
			# the frame, the ball drops into it.
			look.y = minf(look.y, POSTS_LOOK_MAX_Y)
			# ...but tilted up as far as it takes to keep the ball inside
			# the top quarter-margin of the frame.
			var flat := Vector2(look.x - pos.x, look.z - pos.z).length()
			var ball_flat := maxf(Vector2(_follow_ball.x - pos.x, _follow_ball.z - pos.z).length(), 0.5)
			var tilt := maxf(atan2(look.y - pos.y, flat),
				atan2(_follow_ball.y - pos.y, ball_flat) - deg_to_rad(fov) * 0.5 * 0.6)
			look.y = pos.y + tan(tilt) * flat
			# After the score, settle on the goal square and whoever's in
			# it, not on where the ball was left.
			var after := _frame_f - float(_meta("event_frame", 0)) - POSTS_SETTLE_FRAMES
			if after > 0.0:
				var square := Vector3(line - float(direction) * 7.0, 1.2, look.z * 0.5)
				look = look.lerp(square, clampf(after / 20.0, 0.0, 1.0))
			if snap or not state.has("look"):
				state["look"] = look
			else:
				state["look"] = (state.look as Vector3).lerp(look, 1.0 - exp(-SHOT_LOOK_RATE * 1.6 * delta))
			state["pos"] = _clear_view(state, state.look, pos, delta, snap)
			_place(camera, state.pos, state.look, fov)
			return
		"side":
			fov = SIDE_FOV_PORTRAIT if portrait else SIDE_FOV_LANDSCAPE
			var bodies: Array = shot.bodies
			var centre := Vector3.ZERO
			var points: Array[Vector3] = []
			for i: int in bodies:
				var p := _body_now(i)
				centre += p
				points.append(p)
				points.append(p + Vector3.UP * SUBJECT_HEIGHT)
			centre /= float(bodies.size())
			look = centre + Vector3.UP * 1.1
			if _ball_point.distance_to(look) < FIT_BALL_RADIUS:
				look = look.lerp(_ball_point, 0.3)
				points.append(_ball_point)
			var el := deg_to_rad(float(SIDE_ELEVATION.get(String(shot.look), 10.0)))
			dir = ((shot.dir as Vector3) * cos(el) + Vector3.UP * sin(el)).normalized()
			var size := size_distance(fov, framing_fraction() * SIDE_TIGHTER)
			# The size rule sets the distance; fitting both bodies and the ball
			# may bring it in a little, or take it out to SIDE_FIT_STRETCH times
			# it (the narrow 9:16 frame cut a two-shot's players at the edges),
			# never further: never tiny.
			dist = maxf(clampf(_fit_distance(points, look, dir, fov, aspect), size * 0.85, size * SIDE_FIT_STRETCH),
				SIDE_MIN_DIST)
		_:
			# Follow: the old broadcast angle, as close as the size rule says;
			# with the ball well up and away, wide enough for it and the main
			# player both.
			var size := size_distance(fov, framing_fraction())
			dist = clampf(size, FOLLOW_MIN_DIST, BROADCAST_OFFSET.length())
			if _follow_ball.y > FLIGHT_HEIGHT and _follow_ball.distance_to(_main_point) > 6.0:
				var points: Array[Vector3] = [_follow_ball, _main_point, _main_point + Vector3.UP * SUBJECT_HEIGHT]
				var mid := (_follow_ball + _main_point) * 0.5
				look = look.lerp(mid, 0.5)
				dist = clampf(maxf(dist, _fit_distance(points, look, dir, fov, aspect)), dist, FLIGHT_MAX_DIST)
	if snap or not state.has("look"):
		state["look"] = look
		state["dist"] = dist
	else:
		state["look"] = (state.look as Vector3).lerp(look, 1.0 - exp(-SHOT_LOOK_RATE * delta))
		state["dist"] = lerpf(float(state.dist), dist, 1.0 - exp(-SHOT_DIST_RATE * delta))
	var want: Vector3 = (state.look as Vector3) + dir * float(state.dist)
	want.y = maxf(want.y, 1.2)
	if kind == "side":
		want = _inside_fence(want, END_FENCE_MARGIN)
	# The lens body drifts after where it wants to be (the follow shot at
	# FOLLOW_POS_RATE, so it pans like a camera on a tower rather than flying
	# after a 30 m/s kick) and never faster than RIG_MAX_SPEED, while the aim
	# keeps up: the audit counted lens moves over 1 m a frame with the old rig
	# and while the flight shot widened.
	if snap or not state.has("rig"):
		state["rig"] = want
	else:
		var rig: Vector3 = state.rig
		var next := rig.lerp(want, 1.0 - exp(-(FOLLOW_POS_RATE if kind != "side" else SIDE_POS_RATE) * delta))
		var step := next - rig
		var most := RIG_MAX_SPEED * delta
		state["rig"] = rig + (step.normalized() * most if step.length() > most else step)
	want = state.rig
	state["pos"] = _clear_view(state, state.look, want, delta, snap)
	_place(camera, state.pos, state.look, fov)


func _place(camera: Camera3D, pos: Vector3, look: Vector3, fov: float) -> void:
	camera.fov = fov
	camera.global_position = pos
	if pos.distance_squared_to(look) > 0.01:
		camera.look_at(look)


## Body `i`'s root now (between the two recorded frames apply() posed).
func _body_now(i: int) -> Vector3:
	if _cur_a.is_empty() or i < 0 or i >= (_cur_a.bodies as Array).size():
		return _ball_point
	return (_cur_a.bodies[i].pos as Vector3).lerp(_cur_b.bodies[i].pos, _cur_w)


## How far back along `dir` from `look` every point fits in the frame with
## FIT_MARGIN to spare.
static func _fit_distance(points: Array[Vector3], look: Vector3, dir: Vector3, fov_v: float, aspect: float) -> float:
	var tan_v := tan(deg_to_rad(fov_v) * 0.5)
	var tan_h := tan_v * aspect
	var forward := -dir
	var right := forward.cross(Vector3.UP).normalized()
	var up := right.cross(forward).normalized()
	var need := 0.0
	for p in points:
		var o := p - look
		var depth := o.dot(forward)   # nearer the lens than look: negative
		var h := absf(o.dot(right)) * FIT_MARGIN
		var v := absf(o.dot(up)) * FIT_MARGIN
		need = maxf(need, maxf(h / tan_h, v / tan_v) - depth)
	return need


## `pos` moved clear of the scenery and the bodies, looking at `look`: lifted
## (eased up fast, down slowly, so the move reads as a crane, not a jump) when
## a tree, stand or prop is in the way or the lens is inside one, and pulled in
## along the sight line as a last resort, so no frame is ever shot from
## inside something. Bodies: never closer than CameraOccluders.PAD to one
## below head height (rises over them instead).
func _clear_view(state: Dictionary, look: Vector3, pos: Vector3, delta: float, snap: bool) -> Vector3:
	var occ := occluders()
	var want_lift := 0.0
	if occ.first_hit(look, pos) < 0.999 or occ.inside(pos):
		want_lift = float(LIFT_STEPS[-1])
		for lift: float in LIFT_STEPS:
			var q := pos + Vector3.UP * lift
			if occ.first_hit(look, q) >= 0.999 and not occ.inside(q):
				want_lift = lift
				break
	var lift := float(state.get("lift", 0.0))
	if snap:
		lift = want_lift
	else:
		var rate := LIFT_UP_RATE if want_lift > lift else LIFT_DOWN_RATE
		lift = lerpf(lift, want_lift, 1.0 - exp(-rate * delta))
	state["lift"] = lift
	var out := pos + Vector3.UP * lift
	var hit := occ.first_hit(look, out)
	if hit < 0.999 or occ.inside(out):
		# Still blocked (the lift is easing up, or nothing cleared it): come
		# in along the sight line to just short of the obstruction.
		var span := out - look
		var keep := maxf(span.length() * hit - CameraOccluders.PAD - 0.3, PULL_IN_MIN)
		out = look + span.normalized() * minf(keep, span.length())
	if occ.near_body(out):
		out.y = CameraOccluders.BODY_HEIGHT + CameraOccluders.PAD + 0.2
	return out
