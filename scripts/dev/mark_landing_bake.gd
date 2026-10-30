extends Node3D

## Offline bake: how 6thbuild's body actually responds, in the air, to being
## hit at the chest — the physical reference for the off-balance landing
## after a contested Aggressive mark (MarkVariants' mark_aggressive_
## offbalance_*). Uses the stage-1 PASSIVE ragdoll as a measuring tool only
## (docs/MECHANICS_AUDIT.md §B4): nothing here runs in gameplay, and nothing
## hands animation to physics — the output is a small JSON of rotations that
## the animation generator layers onto an authored clip.
##
## Run headless (writes the JSON, prints a summary, quits):
##   godot --headless --path . res://scenes/dev/mark_landing_bake.tscn --fixed-fps 60 --quit-after 200
## or open the scene and press F6 to watch the fall.
##
## Why the body starts from its REST pose, not the leap's contact pose: the
## lab's joints are configured around the rest pose (PhysicsRagdoll.build
## reads get_bone_global_rest), and the contact pose has both arms ~170°
## from rest — far past the 75° shoulder swing limit, so the joints would
## snap on the first tick. The arms aren't wanted anyway (they're holding
## the ball — MarkVariants never applies the bake to them); the trunk's
## tumble and the legs' swing are, and those start close enough to rest.
## The body is lifted LIFT m so the push lands in the air, like a bump at
## the top of a leap, and the bake stops before the feet reach the floor.
##
## Output convention (consumed by MarkVariants._bake_at): per sample, per
## bodied bone, a rotation R in skeleton space —
##   Hips:   R = Q_hips(t) * Q_hips(0)^-1          (whole-body tumble)
##   others: R = Q_parent(0) * Q_parent(t)^-1 * Q(t) * Q(0)^-1
## i.e. each bone's own motion relative to its parent, in the character's
## frame — exactly what local = base_local * G^-1 R G re-applies, since the
## bake starts from rest (Q(0) = G).

const MODEL_ID := "6thbuild"
const OUTPUT_PATH := MarkVariants.RAGDOLL_BAKE_PATH

## Height the body starts at — about the leap's apex (MARK_AGGRESSIVE_JUMP_
## SPEED 4.0 m/s -> 0.82 m). Free fall from here takes ~0.40 s, which is why
## BAKE_LENGTH stops there.
const LIFT := 0.80
const BAKE_LENGTH := 0.40
const SAMPLE_STEP := 1.0 / 30.0

## The hit: from the player's right (the lab's IMPACT FROM convention: 0 =
## front, 90 = right), on the chest, as a constant force over the lab's own
## PUSH_DURATION. 200 N·s is a firm shoulder in a marking contest — inside
## the range the lab's headless sweep found stable (150-700). Unplaytested
## feel guess; the generator scales the result by its own weight anyway.
const PUSH_BEARING_DEG := 90.0
const PUSH_IMPULSE := 200.0
const PUSH_DURATION := 0.12
const PUSH_BONE := &"Chest"

const BAKED_BONES: Array[String] = ["Hips", "Spine", "Chest", "head",
	"LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "RightUpperLeg", "RightLowerLeg", "RightFoot"]

var _subject: Node3D
var _rig: HumanoidRig
var _ragdoll: PhysicsRagdoll
var _skeleton: Skeleton3D
var _t := 0.0
var _next_sample := 0.0
var _push_force := Vector3.ZERO
var _push_left := PUSH_DURATION
var _start := {}
var _samples: Array = []
var _peak_speed := 0.0
var _done := false


func _ready() -> void:
	add_child(_build_floor())
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50.0, -30.0, 0.0)
	add_child(light)
	var camera := Camera3D.new()
	camera.position = Vector3(3.5, 1.6, 3.5)
	add_child(camera)
	camera.look_at(Vector3(0.0, 0.9, 0.0))

	_subject = Node3D.new()
	_subject.rotation.y = deg_to_rad(180.0)
	add_child(_subject)
	_rig = HumanoidRig.new()
	_rig.character_model_override = MODEL_ID
	_subject.add_child(_rig)
	if not _rig.is_imported():
		push_error("MarkLandingBake: %s did not import" % MODEL_ID)
		_finish(false)
		return
	_skeleton = _rig.skeleton()
	_skeleton.reset_bone_poses()
	_ragdoll = PhysicsRagdoll.new()
	if not _ragdoll.build(_skeleton):
		_finish(false)
		return
	_subject.position.y = LIFT
	_ragdoll.start()
	for bone in BAKED_BONES:
		_start[bone] = _bone_rotation(bone)
	var a := deg_to_rad(PUSH_BEARING_DEG)
	var source := (_subject.global_basis * Vector3(sin(a), 0.0, -cos(a))).normalized()
	_push_force = -source * PUSH_IMPULSE / PUSH_DURATION
	_take_sample()


func _physics_process(delta: float) -> void:
	if _done or _ragdoll == null:
		return
	if _push_left > 0.0:
		var dt := minf(delta, _push_left)
		_ragdoll.apply_impact(PUSH_BONE, _push_force * dt)
		_push_left -= dt
	_ragdoll.step(delta)
	_t += delta
	_peak_speed = maxf(_peak_speed, _ragdoll.peak_speed())
	if _t + 0.0001 >= _next_sample:
		_take_sample()
	if _t >= BAKE_LENGTH:
		_finish(true)


## Skeleton-space rotation of `bone`, read off its physical body (the
## simulator's write-back to the skeleton lags a tick).
func _bone_rotation(bone: String) -> Quaternion:
	var pb := _ragdoll.body(bone)
	var g := _skeleton.global_transform.affine_inverse() * pb.global_transform * pb.body_offset.affine_inverse()
	return g.basis.get_rotation_quaternion()


func _take_sample() -> void:
	var now := {}
	for bone in BAKED_BONES:
		now[bone] = _bone_rotation(bone)
	var rot := {}
	for bone in BAKED_BONES:
		var r: Quaternion
		if bone == "Hips":
			r = now[bone] * (_start[bone] as Quaternion).inverse()
		else:
			var parent := _skeleton.get_bone_name(_skeleton.get_bone_parent(_skeleton.find_bone(bone)))
			r = (_start[parent] as Quaternion) * (now[parent] as Quaternion).inverse() \
				* (now[bone] as Quaternion) * (_start[bone] as Quaternion).inverse()
		r = r.normalized()
		rot[bone] = [snappedf(r.x, 0.00001), snappedf(r.y, 0.00001), snappedf(r.z, 0.00001), snappedf(r.w, 0.00001)]
	_samples.append({"t": snappedf(_t, 0.0001), "rot": rot})
	_next_sample += SAMPLE_STEP


func _finish(ok: bool) -> void:
	_done = true
	if ok:
		var data := {
			"source": "scripts/dev/mark_landing_bake.gd",
			"model": MODEL_ID,
			"push_bearing_deg": PUSH_BEARING_DEG,
			"push_impulse": PUSH_IMPULSE,
			"push_duration": PUSH_DURATION,
			"push_bone": String(PUSH_BONE),
			"lift": LIFT,
			"peak_body_speed": snappedf(_peak_speed, 0.01),
			"samples": _samples,
		}
		var file := FileAccess.open(OUTPUT_PATH, FileAccess.WRITE)
		file.store_string(JSON.stringify(data, "\t"))
		file.close()
		var last: Dictionary = _samples[_samples.size() - 1]
		var hips := MarkVariants._q(last.rot["Hips"])
		print("MarkLandingBake: wrote %s — %d samples over %.2fs, peak body speed %.2f m/s, hips tumble %.1f° by the end" % [
			OUTPUT_PATH, _samples.size(), _t, _peak_speed, rad_to_deg(hips.get_angle())])
		for s: Dictionary in _samples:
			var line := "  t=%.3f" % s.t
			for bone in ["Hips", "Spine", "Chest", "head", "LeftUpperLeg", "RightUpperLeg"]:
				line += "  %s %.1f°" % [bone, rad_to_deg(MarkVariants._q(s.rot[bone]).get_angle())]
			print(line)
	if DisplayServer.get_name() == "headless":
		get_tree().quit()


func _build_floor() -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20.0, 2.0, 20.0)
	shape.shape = box
	shape.position = Vector3(0.0, -1.0, 0.0)
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(20.0, 20.0)
	mesh.mesh = plane
	body.add_child(mesh)
	return body
