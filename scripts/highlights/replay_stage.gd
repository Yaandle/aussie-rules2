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
const CAMERA_PRESETS := ["broadcast", "close", "end", "third"]
const PRESET_LABELS := {"broadcast": "BROADCAST", "close": "CLOSE", "end": "END-ON", "third": "THIRD PERSON"}
## Where each type is shot from unless the player picks (HighlightPrefs.camera_for
## reads this as its fallback). Tackles and bumps are the player's-eye view
## (2026-11-11 brief); the rest keep their old looks.
const DEFAULT_PRESET := {"goal": "broadcast", "behind": "broadcast", "mark": "broadcast",
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
	_hold_frame = _find_hold_frame()


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
	_follow_ball = _followed_ball(a)
	_focus_point = _compute_focus(a, b, w)
	_update_main(f, a, b, w)


## What the camera follows: the ball, except in a tackle or bump, where it's
## the two bodies in it (the ball's often spilled away from them).
func _compute_focus(a: Dictionary, b: Dictionary, w: float) -> Vector3:
	var type := String(clip.meta.get("type", ""))
	var focus: Array = clip.meta.get("focus", [])
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
	var type := String(clip.meta.get("type", ""))
	_limit_dir = 0
	if (type != "goal" and type != "behind") or _field == null:
		return -1
	var direction := 1 if float(clip.meta.get("attack_dir", 1.0)) >= 0.0 else -1
	var limit := _field.goal_line_x(direction) + float(direction) * FOLLOW_PAST_GOAL
	_limit_dir = direction
	_limit_x = limit
	var start := int(clip.meta.get("event_frame", 0))
	var previous := clip.ball_position(start)
	for i in range(start + 1, clip.frame_count()):
		var p := clip.ball_position(i)
		if float(direction) * (p.x - limit) > 0.0 or p.distance_to(previous) > BALL_JUMP:
			return i
		previous = p
	return -1


## The main player's point and heading for the third-person camera.
func _update_main(f: float, a: Dictionary, b: Dictionary, w: float) -> void:
	var focus: Array = clip.meta.get("focus", [])
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


## The point the broadcast, close and end-on cameras are following.
func focus_point() -> Vector3:
	return _focus_point


func event_time() -> float:
	return float(clip.meta.get("event_frame", 0)) / clip.fps() if clip != null else 0.0


func duration() -> float:
	return clip.duration() if clip != null else 0.0


func default_preset() -> String:
	return HighlightPrefs.camera_for(String(clip.meta.get("type", ""))) if clip != null else "broadcast"


## Points `camera` for this frame. `snap` jumps straight there (a new clip, a
## scrub, every export frame's first); otherwise it eases at the
## CAMERA_SMOOTHING rates over `delta`.
func frame_camera(camera: Camera3D, preset: String, portrait: bool, t: float, delta: float, snap := false) -> void:
	var key := camera.get_instance_id()
	var state: Dictionary = _cameras.get(key, {})
	if snap or state.is_empty():
		state = {"target": _focus_point, "pos": Vector3.INF}
	if preset == "third":
		_frame_third(camera, state, portrait, delta, snap)
		_cameras[key] = state
		return
	var k_target := 1.0 - exp(-TARGET_SMOOTHING * delta)
	state.target = (state.target as Vector3).lerp(_focus_point, k_target) if not snap else _focus_point
	var target: Vector3 = state.target
	var direction := float(clip.meta.get("attack_dir", 1.0)) if clip != null else 1.0
	var pull := PORTRAIT_PULL_IN if portrait else 1.0
	var want := target
	match preset:
		"close":
			var angle := t * CLOSE_ORBIT_SPEED + PI * 0.5
			want = target + Vector3(cos(angle) * CLOSE_RADIUS * pull, CLOSE_HEIGHT, sin(angle) * CLOSE_RADIUS * pull)
		"end":
			want = _inside_fence(target + Vector3(direction * END_BACK * pull, END_HEIGHT, 0.0), END_FENCE_MARGIN)
		_:
			want = target + BROADCAST_OFFSET * pull
	want.y = maxf(want.y, 1.2)
	if state.pos == Vector3.INF:
		state.pos = want
	else:
		state.pos = (state.pos as Vector3).lerp(want, 1.0 - exp(-CAMERA_SMOOTHING * delta))
	_cameras[key] = state
	camera.fov = FOV_PORTRAIT if portrait else FOV_LANDSCAPE
	camera.global_position = state.pos
	var look := target + Vector3.UP * 0.5
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
