extends Node3D

## Dev-only animation audit (not on any menu): numbers for how a player
## model moves, so animation work has a before and after. Headless:
##   godot --headless --path . res://scenes/dev/anim_audit.tscn --fixed-fps 60 --quit-after 9000 -- --model=7thbuild
## Nothing is saved; CharacterProfile.model_id is set in memory only.
##
## Part 1, MOVES: one real player (player.tscn, PlayerController and
## PlayerAnimation, so stride matching, phase lock, lean, bank and the foot
## clamp all run) on a scripted brain through each of MOVES. Sampled after
## the tree mixes and PlayerAnimation's post-pass, per frame:
##   slip     a planted sole's speed over the turf (m/s): mean, 90th
##            percentile, and the share of planted frames over 0.5 m/s.
##            The sole is sampled at heel, ball and toe; planted = its lowest
##            point within PLANT_HEIGHT of the turf, and that point's speed
##            counts. 0 is a locked foot.
##   pop      the biggest one-frame change in any bone's angular velocity,
##            in the body's own frame (rad/s per frame), and when: a fast
##            but smooth swing scores low, a blend snap or seam high.
##   arms     upper-arm swing, fore-aft, degrees peak to peak (in the
##            steady part of the move).
##   counter  chest yaw against pelvis yaw, degrees peak to peak each, and
##            their correlation (-1 is a full counter-rotation, as in a
##            real run; +1 is the torso turning with the hips).
##   head     the head's world yaw and pitch wobble (deg, std dev).
## Part 2, CLIPS: every clip of the model sampled on a bare rig at 120 Hz.
##   peak     the fastest bone turn inside the clip (rad/s) and where;
##   in/out   how far the clip's first/last frame is from the pose it
##            blends from/to (idle), as the summed bone-angle difference
##            (deg): a big "out" with a short blend is a pop.

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const PLANT_HEIGHT := 0.015
const POP_BONES: Array[StringName] = [&"Hips", &"Spine", &"Chest", &"head", &"LeftUpperArm",
	&"RightUpperArm", &"LeftLowerArm", &"RightLowerArm", &"LeftUpperLeg", &"RightUpperLeg",
	&"LeftLowerLeg", &"RightLowerLeg", &"LeftFoot", &"RightFoot"]

## [name, seconds, steady window start (s), fn(t) -> [wish (world), gait]].
## The player starts facing -Z.
var MOVES := [
	["jog", 5.0, 2.0, func(_t): return [Vector3.FORWARD, Tuning.GAIT_JOG]],
	["sprint", 5.0, 2.5, func(_t): return [Vector3.FORWARD, 1.0]],
	["start_stop", 5.0, 0.0, func(t): return [Vector3.FORWARD, 1.0 if t < 2.5 else 0.0]],
	["cut90", 5.0, 2.0, func(t): return [Vector3.FORWARD if t < 2.5 else Vector3.RIGHT, 1.0]],
	["cut180", 5.0, 2.0, func(t): return [Vector3.FORWARD if t < 2.5 else Vector3.BACK, 1.0]],
	["weave", 6.0, 1.5, func(t): return [Vector3(sin(t * 2.4) * 0.8, 0.0, -1.0).normalized(), Tuning.GAIT_JOG]],
	# Standing, a dab of stick the other way every 1.2 s (0.3 s each).
	["turn_spot", 4.8, 0.5, func(t): return [Vector3.FORWARD.rotated(Vector3.UP, PI * floorf(t / 1.2)),
		0.1 if fmod(t, 1.2) < 0.3 else 0.0]],
	["walk", 5.0, 2.0, func(_t): return [Vector3.FORWARD, Tuning.GAIT_WALK]],
]

var model := "7thbuild"
var only: Array = []
## --trace: per-frame planted-foot lines (TRACE ...) in the steady window.
var trace := false


class ScriptBrain extends PlayerBrain:
	var wish := Vector3.ZERO
	var gait_value := 0.0

	func wish_direction(_controller: PlayerController) -> Vector3:
		return wish

	func gait() -> float:
		return gait_value


var _player: PlayerController
var _brain: ScriptBrain
var _skeleton: Skeleton3D
var _move := 0
var _t := 0.0
var _rows := {}
var _prev := {}
var _prev_w := {}
var _foot_prev := {}
var _started := false


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		var kv := arg.trim_prefix("--").split("=", true, 1)
		if kv.size() == 2 and kv[0] == "model":
			model = kv[1]
		elif kv.size() == 2 and kv[0] == "only":
			only = Array(kv[1].split(","))
		elif arg == "--trace":
			trace = true
	CharacterProfile.model_id = model
	process_priority = 1000   # after the AnimationTree and PlayerAnimation
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400.0, 1.0, 400.0)
	shape.shape = box
	shape.position.y = -0.5
	floor_body.add_child(shape)
	add_child(floor_body)
	# Jolt's same-frame construction race (LESSONS.md): throwaways first.
	for i in 3:
		var throwaway := PLAYER_SCENE.instantiate()
		add_child(throwaway)
		throwaway.queue_free()
	_audit_clips()
	_next_move.call_deferred()


func _next_move() -> void:
	if _player != null:
		_player.queue_free()
		_player = null
	while _move < MOVES.size() and not only.is_empty() and not only.has(MOVES[_move][0]):
		_move += 1
	if _move >= MOVES.size():
		print("ANIM_AUDIT done")
		get_tree().quit()
		return
	await get_tree().physics_frame
	await get_tree().physics_frame
	_player = PLAYER_SCENE.instantiate() as PlayerController
	_player.team = Tuning.Team.HOME
	_player.position = Vector3(0.0, 0.05, 0.0)
	add_child(_player)
	_brain = ScriptBrain.new()
	_player.set_brain(_brain)
	_skeleton = (_player.get_node("Rig") as HumanoidRig).skeleton()
	if _move == 0 or only.size() == 1:
		var anim := _player.get_node("PlayerAnimation") as PlayerAnimation
		await get_tree().physics_frame
		for clip in anim.stride_measurements():
			var m: Dictionary = anim.stride_measurements()[clip]
			print("STRIDE %-8s authored %.2f m/s, %.2f steps/s" % [clip, float(m.speed), float(m.cadence)])
	_t = 0.0
	_prev = {}
	_prev_w = {}
	_foot_prev = {}
	_rows = {"slip": [], "pop": [], "arm_l": [], "arm_r": [], "chest_yaw": [], "hips_yaw": [],
		"head_yaw": [], "head_pitch": [], "pop_at": 0.0, "pop_bone": ""}
	_started = true


func _process(delta: float) -> void:
	if not _started or _player == null or _skeleton == null:
		return
	var move: Array = MOVES[_move]
	var cmd: Array = (move[3] as Callable).call(_t)
	_brain.wish = cmd[0]
	_brain.gait_value = cmd[1]
	if _t > 0.2:
		_sample(delta, _t >= float(move[2]))
	_t += delta
	if _t >= float(move[1]):
		_report(move[0])
		_started = false
		_move += 1
		_next_move.call_deferred()


func _bone_world(bone: StringName) -> Transform3D:
	var idx := _skeleton.find_bone(bone)
	return _skeleton.global_transform * _skeleton.get_bone_global_pose(idx)


func _sample(delta: float, steady: bool) -> void:
	var body := _player.global_basis.orthonormalized()
	var to_body := body.inverse()
	# Planted-sole slip, in the world: heel, ball and toe along the foot
	# bone (+Y runs ankle to toe), each with its own height above the sole.
	for foot: StringName in [&"LeftFoot", &"RightFoot"]:
		var xf := _bone_world(foot)
		var points := [xf * Vector3(0.0, -0.02, 0.0), xf * Vector3(0.0, 0.22, 0.0), xf * Vector3(0.0, 0.30, 0.0)]
		var lift := [PlayerAnimation.BOOT_GROUND_CLEARANCE, 0.035, 0.028]
		var low := 0
		for k in 3:
			if points[k].y - lift[k] < points[low].y - lift[low]:
				low = k
		if _foot_prev.has(foot) and points[low].y - lift[low] <= PLANT_HEIGHT:
			var v: Vector3 = (points[low] - _foot_prev[foot][low]) / delta
			_rows.slip.append(Vector2(v.x, v.z).length())
			if trace and steady:
				print("TRACE %.3f %s pt%d h %.3f slip %.2f" % [_t, foot, low, points[low].y - lift[low], Vector2(v.x, v.z).length()])
		_foot_prev[foot] = points
	# Pops: each bone's turn in the body's frame since last frame.
	for bone: StringName in POP_BONES:
		if _skeleton.find_bone(bone) < 0:
			continue
		var q := (to_body * _bone_world(bone).basis.orthonormalized()).get_rotation_quaternion()
		if _prev.has(bone):
			var dq: Quaternion = q * (_prev[bone] as Quaternion).inverse()
			if dq.w < 0.0:
				dq = -dq   # the short way round (q and -q are one rotation)
			var w := dq.get_axis() * dq.get_angle() / delta if dq.get_angle() > 1e-6 else Vector3.ZERO
			if _prev_w.has(bone):
				var jerk: float = (w - _prev_w[bone]).length()
				_rows.pop.append(jerk)
				if jerk >= (_rows.pop as Array).max():
					_rows.pop_at = _t
					_rows.pop_bone = String(bone)
			_prev_w[bone] = w
		_prev[bone] = q
	if not steady:
		return
	# Arm swing: the upper arm's direction pitched fore-aft in the body frame.
	for side: Array in [[&"LeftUpperArm", "arm_l"], [&"RightUpperArm", "arm_r"]]:
		var a := _bone_world(side[0])
		var tip := to_body * (_bone_world(&"LeftLowerArm" if side[1] == "arm_l" else &"RightLowerArm").origin - a.origin)
		_rows[side[1]].append(rad_to_deg(atan2(-tip.z, -tip.y)))
	for pair: Array in [[&"Chest", "chest_yaw"], [&"Hips", "hips_yaw"]]:
		var fwd := to_body * (_bone_world(pair[0]).basis * Vector3(0.0, 0.0, 1.0))
		_rows[pair[1]].append(rad_to_deg(atan2(fwd.x, fwd.z)))
	var head := _bone_world(&"head").basis.orthonormalized()
	var look := head * Vector3(0.0, 0.0, 1.0)
	_rows.head_yaw.append(rad_to_deg(atan2(look.x, look.z)))
	_rows.head_pitch.append(rad_to_deg(asin(clampf(look.y, -1.0, 1.0))))


static func _pct(values: Array, q: float) -> float:
	if values.is_empty():
		return 0.0
	var s := values.duplicate()
	s.sort()
	return s[mini(s.size() - 1, int(s.size() * q))]


static func _mean(values: Array) -> float:
	var m := 0.0
	for v in values:
		m += v
	return m / maxf(values.size(), 1)


static func _span(values: Array) -> float:
	return 0.0 if values.is_empty() else float(values.max()) - float(values.min())


static func _std(values: Array) -> float:
	var m := _mean(values)
	var s := 0.0
	for v in values:
		s += (v - m) * (v - m)
	return sqrt(s / maxf(values.size(), 1))


## Unwraps yaw readings into a continuous series and takes out the mean.
static func _centred(values: Array) -> Array:
	var out := []
	var prev := 0.0
	var acc := 0.0
	for i in values.size():
		var v: float = values[i]
		if i > 0:
			acc += wrapf(v - prev, -180.0, 180.0)
		prev = v
		out.append(acc)
	var m := _mean(out)
	return out.map(func(x): return x - m)


static func _corr(a: Array, b: Array) -> float:
	var n := mini(a.size(), b.size())
	if n < 3:
		return 0.0
	var ma := _mean(a.slice(0, n))
	var mb := _mean(b.slice(0, n))
	var sab := 0.0
	var saa := 0.0
	var sbb := 0.0
	for i in n:
		sab += (a[i] - ma) * (b[i] - mb)
		saa += (a[i] - ma) * (a[i] - ma)
		sbb += (b[i] - mb) * (b[i] - mb)
	return sab / sqrt(maxf(saa * sbb, 1e-9))


func _report(name: String) -> void:
	var slip: Array = _rows.slip
	var fast := slip.filter(func(v): return v > 0.5).size()
	var chest := _centred(_rows.chest_yaw)
	var hips := _centred(_rows.hips_yaw)
	print("MOVE %-10s slip mean %.2f p90 %.2f >0.5 %3d%% | pop max %5.1f rad/s (%s @%.2fs) p99 %4.1f | arms %3d/%3d deg | counter chest %4.1f hips %4.1f corr %+.2f | head yaw sd %.1f pitch sd %.1f | speed %.1f" % [
		name, _mean(slip), _pct(slip, 0.9), roundi(100.0 * fast / maxf(slip.size(), 1)),
		float(_rows.pop.max()) if not _rows.pop.is_empty() else 0.0, _rows.pop_bone, _rows.pop_at, _pct(_rows.pop, 0.99),
		roundi(_span(_rows.arm_l)), roundi(_span(_rows.arm_r)), _span(chest), _span(hips), _corr(chest, hips),
		_std(_centred(_rows.head_yaw)), _std(_rows.head_pitch), Vector2(_player.velocity.x, _player.velocity.z).length()])


## Part 2: every clip on a bare rig.
func _audit_clips() -> void:
	var rig := HumanoidRig.new()
	rig.character_model_override = model
	add_child(rig)
	var skeleton := rig.skeleton()
	if skeleton == null:
		push_error("AnimAudit: no skeleton for %s" % model)
		return
	var clips := rig.imported_animations()
	var idle := _pose_at(skeleton, clips.get("idle"), 0.0)
	var names := clips.keys()
	names.sort()
	for clip_name: String in names:
		var anim: Animation = clips[clip_name]
		var step := 1.0 / 120.0
		var prev := {}
		var peak := 0.0
		var peak_at := 0.0
		var peak_bone := ""
		var t := 0.0
		while t <= anim.length + 1e-6:
			var pose := _pose_at(skeleton, anim, minf(t, anim.length))
			for bone: StringName in pose:
				if prev.has(bone):
					var w: float = (prev[bone] as Quaternion).angle_to(pose[bone]) / step
					if w > peak:
						peak = w
						peak_at = t
						peak_bone = String(bone)
			prev = pose
			t += step
		var first := _pose_at(skeleton, anim, 0.0)
		var last := _pose_at(skeleton, anim, anim.length)
		print("CLIP %-18s %.2fs %s peak %5.1f rad/s (%s @%.2fs) | in %4d deg | out %4d deg" % [
			clip_name, anim.length, "loop" if anim.loop_mode != Animation.LOOP_NONE else "once",
			peak, peak_bone, peak_at, roundi(_pose_distance(idle, first)), roundi(_pose_distance(idle, last))])
	rig.queue_free()


## Each POP_BONE's rotation in the skeleton's (Hips-relative where it moves
## the whole body) frame at time t of anim.
func _pose_at(skeleton: Skeleton3D, anim: Animation, t: float) -> Dictionary:
	skeleton.reset_bone_poses()
	if anim != null:
		for i in anim.get_track_count():
			var bone := skeleton.find_bone(String(anim.track_get_path(i).get_concatenated_subnames()))
			if bone < 0:
				continue
			match anim.track_get_type(i):
				Animation.TYPE_ROTATION_3D:
					skeleton.set_bone_pose_rotation(bone, anim.rotation_track_interpolate(i, t))
				Animation.TYPE_POSITION_3D:
					skeleton.set_bone_pose_position(bone, anim.position_track_interpolate(i, t))
	var out := {}
	for bone: StringName in POP_BONES:
		var idx := skeleton.find_bone(bone)
		if idx >= 0:
			out[bone] = skeleton.get_bone_global_pose(idx).basis.orthonormalized().get_rotation_quaternion()
	return out


static func _pose_distance(a: Dictionary, b: Dictionary) -> float:
	var d := 0.0
	for bone in a:
		if b.has(bone):
			d += rad_to_deg((a[bone] as Quaternion).angle_to(b[bone]))
	return d
