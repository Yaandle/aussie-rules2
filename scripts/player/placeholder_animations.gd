class_name PlaceholderAnimations
extends RefCounted

## Generates the placeholder AnimationLibrary for PlaceholderRig.
##
## Every clip here is sampled from a parametric gait function — leg swing,
## knee lift, arm counter-swing, hip bob, torso lean and twist, all sine
## functions of one phase. It is not good animation. It is not trying to
## be. It exists so the BlendSpace2D in player_animation.gd has real,
## differently-shaped clips to interpolate between, which is the only way
## to prove the locomotion pipeline before there is any art.
##
## THE SWAP TO MIXAMO: import the .glb, and the whole of this file plus
## placeholder_rig.gd is deleted. player_animation.gd keeps the same
## clip names, blend point layout and state names, and stops calling
## build_library(). Nothing in player_controller.gd is touched.

## Track targets, relative to the AnimationPlayer's root_node (the Rig).
const PATHS := {
	"hips": "Hips",
	"torso": "Hips/Torso",
	"neck": "Hips/Torso/Neck",
	"shoulder_l": "Hips/Torso/ShoulderL",
	"shoulder_r": "Hips/Torso/ShoulderR",
	"elbow_l": "Hips/Torso/ShoulderL/ElbowL",
	"elbow_r": "Hips/Torso/ShoulderR/ElbowR",
	"hip_l": "Hips/HipL",
	"hip_r": "Hips/HipR",
	"knee_l": "Hips/HipL/KneeL",
	"knee_r": "Hips/HipR/KneeR",
	"ankle_l": "Hips/HipL/KneeL/AnkleL",
	"ankle_r": "Hips/HipR/KneeR/AnkleR",
}

const ARM_REST_OUT := 0.10    ## rad, arms held clear of the ribs
const ELBOW_REST := 0.30      ## rad, resting elbow bend
const KNEE_PHASE := 0.5       ## rad, knee bends slightly after toe-off
const GAIT_SAMPLES := 14      ## keys per locomotion cycle

## Locomotion clips, keyed by name. Read alongside the blend point layout
## in player_animation.gd — the two lists have to agree.
const GAITS := {
	"idle": {
		"cycle": 3.2, "stride": 0.02, "knee_lift": 0.03, "arm_swing": 0.02,
		"bob": 0.006, "lean": 0.02, "twist": 0.012,
	},
	"jog_fwd": {
		"cycle": 0.72, "stride": 0.42, "knee_lift": 0.75, "arm_swing": 0.45,
		"bob": 0.035, "lean": 0.08, "twist": 0.06,
	},
	"run_fwd": {
		"cycle": 0.58, "stride": 0.72, "knee_lift": 1.25, "arm_swing": 0.85,
		"bob": 0.055, "lean": 0.20, "twist": 0.11,
	},
	"run_back": {
		"cycle": 0.68, "stride": 0.50, "knee_lift": 0.85, "arm_swing": 0.55,
		"bob": 0.040, "lean": -0.10, "twist": 0.05, "dir": -1.0,
	},
	"strafe_l": {
		"cycle": 0.66, "stride": 0.10, "knee_lift": 0.55, "arm_swing": 0.20,
		"bob": 0.030, "lean": 0.04, "twist": 0.02, "abduct": -0.32, "roll": -0.05,
	},
	"strafe_r": {
		"cycle": 0.66, "stride": 0.10, "knee_lift": 0.55, "arm_swing": 0.20,
		"bob": 0.030, "lean": 0.04, "twist": 0.02, "abduct": 0.32, "roll": 0.05,
	},
	"run_fwd_l": {
		"cycle": 0.60, "stride": 0.62, "knee_lift": 1.10, "arm_swing": 0.75,
		"bob": 0.050, "lean": 0.17, "twist": 0.09, "abduct": -0.14, "yaw_bias": 0.12,
	},
	"run_fwd_r": {
		"cycle": 0.60, "stride": 0.62, "knee_lift": 1.10, "arm_swing": 0.75,
		"bob": 0.050, "lean": 0.17, "twist": 0.09, "abduct": 0.14, "yaw_bias": -0.12,
	},
}


static func build_library(hip_height: float) -> AnimationLibrary:
	var library := AnimationLibrary.new()
	for clip_name: String in GAITS:
		library.add_animation(clip_name, _build_gait(GAITS[clip_name], hip_height))
	library.add_animation(&"kick", _build_kick(hip_height))
	library.add_animation(&"handball", _build_handball(hip_height))
	library.add_animation(&"bounce", _build_bounce(hip_height))
	return library


# ── Locomotion ───────────────────────────────────────────────────────

static func _build_gait(g: Dictionary, hip_height: float) -> Animation:
	var cycle: float = g["cycle"]
	var keys: Array = []
	for i in GAIT_SAMPLES:
		var phase := float(i) / float(GAIT_SAMPLES)
		keys.append([phase * cycle, _gait_pose(phase, g)])
	return _assemble(cycle, true, keys, hip_height)


static func _gait_pose(phase: float, g: Dictionary) -> Dictionary:
	var a := TAU * phase
	var dir: float = g.get("dir", 1.0)
	var stride: float = g["stride"]
	var knee_lift: float = g["knee_lift"]
	var arm: float = g["arm_swing"]
	var bob: float = g["bob"]
	var lean: float = g["lean"]
	var twist: float = g["twist"]
	var abduct: float = g.get("abduct", 0.0)
	var yaw_bias: float = g.get("yaw_bias", 0.0)
	var roll: float = g.get("roll", 0.0)

	# A limb hangs along -Y, so a positive rotation about X swings its far
	# end toward -Z, which is forward. The torso runs along +Y, so its
	# lean is the same rotation with the opposite sign.
	var swing_l := sin(a) * stride * dir
	var swing_r := sin(a + PI) * stride * dir
	var bend_l := -knee_lift * maxf(0.0, sin(a + KNEE_PHASE))
	var bend_r := -knee_lift * maxf(0.0, sin(a + PI + KNEE_PHASE))
	# Keep the sole roughly parallel to the turf through the stride.
	var ankle_l := clampf(-(swing_l + bend_l) * 0.55, -0.6, 0.6)
	var ankle_r := clampf(-(swing_r + bend_r) * 0.55, -0.6, 0.6)
	# Both hips lean toward the direction of travel for a side-step, the
	# trailing one harder — a shuffle, not a march.
	var abduct_l := abduct * (0.55 + 0.45 * sin(a))
	var abduct_r := abduct * (0.55 - 0.45 * sin(a))

	var pose := _base_pose()
	pose["hip_y"] = -bob * cos(2.0 * a)
	pose["hips"] = Vector3(0.0, twist * sin(a), roll * sin(a))
	pose["torso"] = Vector3(-lean, yaw_bias - twist * 0.7 * sin(a), 0.0)
	pose["neck"] = Vector3(lean * 0.6, -yaw_bias * 0.5, 0.0)
	pose["shoulder_l"] = Vector3(-swing_l * arm / maxf(stride, 0.02),
		0.0, -ARM_REST_OUT - absf(abduct) * 0.5)
	pose["shoulder_r"] = Vector3(-swing_r * arm / maxf(stride, 0.02),
		0.0, ARM_REST_OUT + absf(abduct) * 0.5)
	pose["elbow_l"] = Vector3(-(ELBOW_REST + arm * 0.6 * maxf(0.0, sin(a + PI))), 0.0, 0.0)
	pose["elbow_r"] = Vector3(-(ELBOW_REST + arm * 0.6 * maxf(0.0, sin(a))), 0.0, 0.0)
	pose["hip_l"] = Vector3(swing_l, 0.0, abduct_l)
	pose["hip_r"] = Vector3(swing_r, 0.0, abduct_r)
	pose["knee_l"] = Vector3(bend_l, 0.0, 0.0)
	pose["knee_r"] = Vector3(bend_r, 0.0, 0.0)
	pose["ankle_l"] = Vector3(ankle_l, 0.0, 0.0)
	pose["ankle_r"] = Vector3(ankle_r, 0.0, 0.0)
	return pose


# ── Discrete actions ─────────────────────────────────────────────────
# Timings come from Tuning.ACTION_DURATION / ACTION_CONTACT so the moment
# the boot meets the ball in player_controller.gd is the same moment the
# leg is through the ball here.

static func _build_kick(hip_height: float) -> Animation:
	var length := Tuning.action_duration(Tuning.Action.KICK)
	var contact := Tuning.action_contact_time(Tuning.Action.KICK)
	return _assemble(length, false, [
		[0.0, _base_pose()],
		[contact * 0.33, _pose({
			"hip_y": -0.03, "torso": Vector3(-0.10, 0.0, 0.0),
			"hip_r": Vector3(-0.55, 0.0, 0.0), "knee_r": Vector3(-0.95, 0.0, 0.0),
			"hip_l": Vector3(0.12, 0.0, 0.0), "knee_l": Vector3(-0.18, 0.0, 0.0),
			"shoulder_l": Vector3(0.50, 0.0, -0.30), "shoulder_r": Vector3(-0.50, 0.0, 0.30),
		})],
		[contact * 0.72, _pose({
			"hip_y": -0.02, "torso": Vector3(0.02, 0.0, 0.0),
			"hip_r": Vector3(-0.15, 0.0, 0.0), "knee_r": Vector3(-1.15, 0.0, 0.0),
			"hip_l": Vector3(0.10, 0.0, 0.0), "knee_l": Vector3(-0.22, 0.0, 0.0),
			"shoulder_l": Vector3(0.72, 0.0, -0.34), "shoulder_r": Vector3(-0.62, 0.0, 0.30),
		})],
		[contact, _pose({
			"hip_y": 0.02, "torso": Vector3(0.20, 0.0, 0.0), "neck": Vector3(-0.12, 0.0, 0.0),
			"hip_r": Vector3(0.85, 0.0, 0.0), "knee_r": Vector3(-0.10, 0.0, 0.0),
			"ankle_r": Vector3(-0.25, 0.0, 0.0),
			"hip_l": Vector3(0.05, 0.0, 0.0), "knee_l": Vector3(-0.10, 0.0, 0.0),
			"shoulder_l": Vector3(0.90, 0.0, -0.42), "shoulder_r": Vector3(-0.70, 0.0, 0.36),
		})],
		[lerpf(contact, length, 0.45), _pose({
			"hip_y": 0.03, "torso": Vector3(0.26, 0.0, 0.0), "neck": Vector3(-0.16, 0.0, 0.0),
			"hip_r": Vector3(1.20, 0.0, 0.0), "knee_r": Vector3(-0.05, 0.0, 0.0),
			"ankle_r": Vector3(-0.30, 0.0, 0.0),
			"shoulder_l": Vector3(0.70, 0.0, -0.40), "shoulder_r": Vector3(-0.55, 0.0, 0.34),
		})],
		[length, _base_pose()],
	], hip_height)


static func _build_handball(hip_height: float) -> Animation:
	var length := Tuning.action_duration(Tuning.Action.HANDBALL)
	var contact := Tuning.action_contact_time(Tuning.Action.HANDBALL)
	return _assemble(length, false, [
		[0.0, _base_pose()],
		[contact * 0.5, _pose({
			"hip_y": -0.02, "torso": Vector3(-0.12, 0.14, 0.0),
			"shoulder_l": Vector3(0.90, 0.0, -0.26), "elbow_l": Vector3(-0.85, 0.0, 0.0),
			"shoulder_r": Vector3(-0.55, 0.0, 0.34), "elbow_r": Vector3(-1.30, 0.0, 0.0),
			"knee_l": Vector3(-0.16, 0.0, 0.0), "knee_r": Vector3(-0.16, 0.0, 0.0),
		})],
		[contact, _pose({
			"torso": Vector3(-0.06, -0.10, 0.0),
			"shoulder_l": Vector3(0.70, 0.0, -0.22), "elbow_l": Vector3(-0.60, 0.0, 0.0),
			"shoulder_r": Vector3(0.75, 0.0, 0.20), "elbow_r": Vector3(-0.25, 0.0, 0.0),
			"knee_l": Vector3(-0.10, 0.0, 0.0), "knee_r": Vector3(-0.10, 0.0, 0.0),
		})],
		[lerpf(contact, length, 0.5), _pose({
			"torso": Vector3(-0.02, -0.14, 0.0),
			"shoulder_l": Vector3(0.40, 0.0, -0.18), "elbow_l": Vector3(-0.45, 0.0, 0.0),
			"shoulder_r": Vector3(0.95, 0.0, 0.18), "elbow_r": Vector3(-0.15, 0.0, 0.0),
		})],
		[length, _base_pose()],
	], hip_height)


static func _build_bounce(hip_height: float) -> Animation:
	var length := Tuning.action_duration(Tuning.Action.BOUNCE)
	var contact := Tuning.action_contact_time(Tuning.Action.BOUNCE)
	return _assemble(length, false, [
		[0.0, _base_pose()],
		[contact * 0.55, _pose({
			"hip_y": -0.05, "torso": Vector3(-0.30, 0.0, 0.0), "neck": Vector3(0.18, 0.0, 0.0),
			"shoulder_l": Vector3(0.75, 0.0, -0.22), "shoulder_r": Vector3(0.75, 0.0, 0.22),
			"elbow_l": Vector3(-0.50, 0.0, 0.0), "elbow_r": Vector3(-0.50, 0.0, 0.0),
			"knee_l": Vector3(-0.35, 0.0, 0.0), "knee_r": Vector3(-0.35, 0.0, 0.0),
		})],
		[contact, _pose({
			"hip_y": -0.07, "torso": Vector3(-0.40, 0.0, 0.0), "neck": Vector3(0.24, 0.0, 0.0),
			"shoulder_l": Vector3(1.00, 0.0, -0.20), "shoulder_r": Vector3(1.00, 0.0, 0.20),
			"elbow_l": Vector3(-0.15, 0.0, 0.0), "elbow_r": Vector3(-0.15, 0.0, 0.0),
			"knee_l": Vector3(-0.42, 0.0, 0.0), "knee_r": Vector3(-0.42, 0.0, 0.0),
		})],
		[lerpf(contact, length, 0.5), _pose({
			"hip_y": -0.02, "torso": Vector3(-0.18, 0.0, 0.0), "neck": Vector3(0.10, 0.0, 0.0),
			"shoulder_l": Vector3(0.50, 0.0, -0.16), "shoulder_r": Vector3(0.50, 0.0, 0.16),
			"knee_l": Vector3(-0.20, 0.0, 0.0), "knee_r": Vector3(-0.20, 0.0, 0.0),
		})],
		[length, _base_pose()],
	], hip_height)


# ── Assembly ─────────────────────────────────────────────────────────

static func _base_pose() -> Dictionary:
	return {
		"hip_y": 0.0,
		"hips": Vector3.ZERO,
		"torso": Vector3.ZERO,
		"neck": Vector3.ZERO,
		"shoulder_l": Vector3(0.0, 0.0, -ARM_REST_OUT),
		"shoulder_r": Vector3(0.0, 0.0, ARM_REST_OUT),
		"elbow_l": Vector3(-ELBOW_REST, 0.0, 0.0),
		"elbow_r": Vector3(-ELBOW_REST, 0.0, 0.0),
		"hip_l": Vector3.ZERO,
		"hip_r": Vector3.ZERO,
		"knee_l": Vector3.ZERO,
		"knee_r": Vector3.ZERO,
		"ankle_l": Vector3.ZERO,
		"ankle_r": Vector3.ZERO,
	}


static func _pose(overrides: Dictionary) -> Dictionary:
	var pose := _base_pose()
	pose.merge(overrides, true)
	return pose


## Every clip writes the identical track set — that is a hard requirement
## for clean AnimationTree blending, and the reason all of them go
## through here.
static func _assemble(length: float, looping: bool, keys: Array,
		hip_height: float) -> Animation:
	var anim := Animation.new()
	anim.length = length
	anim.loop_mode = Animation.LOOP_LINEAR if looping else Animation.LOOP_NONE

	var hip_position_track := anim.add_track(Animation.TYPE_POSITION_3D)
	anim.track_set_path(hip_position_track, NodePath(PATHS["hips"]))
	anim.track_set_interpolation_type(hip_position_track, Animation.INTERPOLATION_CUBIC)

	var rotation_tracks := {}
	for key: String in PATHS:
		var track := anim.add_track(Animation.TYPE_ROTATION_3D)
		anim.track_set_path(track, NodePath(PATHS[key] as String))
		anim.track_set_interpolation_type(track, Animation.INTERPOLATION_CUBIC)
		rotation_tracks[key] = track

	for entry: Array in keys:
		var time: float = entry[0]
		var pose: Dictionary = entry[1]
		anim.position_track_insert_key(hip_position_track, time,
			Vector3(0.0, hip_height + float(pose["hip_y"]), 0.0))
		for key: String in rotation_tracks:
			anim.rotation_track_insert_key(rotation_tracks[key], time,
				Quaternion.from_euler(pose[key] as Vector3))
	return anim
