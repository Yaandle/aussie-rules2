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
## a goal, from behind the posts). All distances in metres, unplaytested
## framing guesses.
const CAMERA_PRESETS := ["broadcast", "close", "end"]
const PRESET_LABELS := {"broadcast": "BROADCAST", "close": "CLOSE", "end": "END-ON"}
const DEFAULT_PRESET := {"goal": "broadcast", "behind": "broadcast", "mark": "broadcast",
	"tackle": "close", "bump": "close", "long_kick": "broadcast", "ruck": "close"}
const BROADCAST_OFFSET := Vector3(0.0, 15.0, 34.0)
const CLOSE_RADIUS := 8.5
const CLOSE_HEIGHT := 2.6
const CLOSE_ORBIT_SPEED := 0.12   ## rad/s
const END_BACK := 30.0
const END_HEIGHT := 8.0
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
		_decoded[index] = clip.decode(index)
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
	_focus_point = _compute_focus(a, b, w)


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
	return _ball_point


func event_time() -> float:
	return float(clip.meta.get("event_frame", 0)) / clip.fps() if clip != null else 0.0


func duration() -> float:
	return clip.duration() if clip != null else 0.0


func default_preset() -> String:
	return String(DEFAULT_PRESET.get(String(clip.meta.get("type", "")), "broadcast")) if clip != null \
		else "broadcast"


## Points `camera` for this frame. `snap` jumps straight there (a new clip, a
## scrub, every export frame's first); otherwise it eases at the
## CAMERA_SMOOTHING rates over `delta`.
func frame_camera(camera: Camera3D, preset: String, portrait: bool, t: float, delta: float, snap := false) -> void:
	var key := camera.get_instance_id()
	var state: Dictionary = _cameras.get(key, {})
	if snap or state.is_empty():
		state = {"target": _focus_point, "pos": Vector3.INF}
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
			want = target + Vector3(direction * END_BACK * pull, END_HEIGHT, 0.0)
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
