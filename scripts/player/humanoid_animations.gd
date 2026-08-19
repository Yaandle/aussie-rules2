class_name HumanoidAnimations
extends RefCounted

## Generates the placeholder AnimationLibrary for HumanoidRig's Skeleton3D.
##
## Replaces PlaceholderAnimations. The pose math (parametric sine-based
## gait, per-action keyframe poses) is untouched — only the track target
## changed, from Node3D property tracks on bare "joint" nodes to bone
## tracks on a real Skeleton3D, via Godot's "NodePath:BoneName" track-path
## convention. That is what makes this something a future retarget/mocap
## pipeline can eventually replace wholesale: import real clips authored
## against SkeletonProfileHumanoid's bone names, drop them in this
## library's place, and nothing in player_animation.gd or
## player_controller.gd has to change, same promise the placeholder always
## made — just against bone tracks now instead of node tracks.
##
## Track targets are bone names on the Skeleton3D, which player_animation.gd
## locates as "Skeleton3D" (a direct child of the Rig, HumanoidRig's own
## root_node target).

const SKELETON := "Skeleton3D"

## Old joint key -> bone name. Keys are kept from the placeholder version
## so _gait_pose()/the per-action pose dictionaries below didn't need
## touching — only this map and _assemble()'s track-path construction did.
const BONES := {
	"hips": "Hips",
	"torso": "Chest",
	"neck": "Neck",
	"shoulder_l": "LeftUpperArm",
	"shoulder_r": "RightUpperArm",
	"elbow_l": "LeftLowerArm",
	"elbow_r": "RightLowerArm",
	"hip_l": "LeftUpperLeg",
	"hip_r": "RightUpperLeg",
	"knee_l": "LeftLowerLeg",
	"knee_r": "RightLowerLeg",
	"ankle_l": "LeftFoot",
	"ankle_r": "RightFoot",
}

const ARM_REST_OUT := 0.10    ## rad, arms held clear of the ribs
const ELBOW_REST := 0.30      ## rad, resting elbow bend
const KNEE_PHASE := 0.5       ## rad, knee bends slightly after toe-off
const GAIT_SAMPLES := 14      ## keys per locomotion cycle

## Locomotion clips, keyed by name. Read alongside the blend point layout
## in player_animation.gd — the two lists have to agree.
const GAITS := {
	# Zero, not just small: two rounds of shrinking these toward zero
	# (0.02-ish, then ~0.006-0.01) still read as a twitch rather than a
	# sway, most visible on the character screen's tight preview camera.
	# The likely cause isn't amplitude — several of these feed a
	# maxf(0.0, sin(...)) rectifier in _gait_pose() (knee_lift, the ankle
	# terms derived from it), which has a hard kink at every zero-crossing
	# that CUBIC track interpolation, sampled at only GAIT_SAMPLES (14)
	# points over the cycle, cannot represent without overshoot — and an
	# overshoot's absolute size doesn't necessarily shrink just because
	# the signal feeding it does. A menu preview doesn't need a believable
	# idle breathing sway badly enough to chase that; zero sidesteps the
	# whole mechanism instead of tuning around it. Revisit with a smooth
	# (kink-free) idle formula or a higher sample rate if idle sway is
	# wanted again later.
	"idle": {
		"cycle": 4.5, "stride": 0.0, "knee_lift": 0.0, "arm_swing": 0.0,
		"bob": 0.0, "lean": 0.0, "twist": 0.0,
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
	library.add_animation(&"mark_safe", _build_mark_safe(hip_height))
	library.add_animation(&"mark_running", _build_mark_running(hip_height))
	library.add_animation(&"mark_aggressive", _build_mark_aggressive(hip_height))
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
	# Positive X, not negative: per this function's swing convention above,
	# a limb hanging along -Y with a positive X rotation swings its far end
	# toward -Z (forward) — an elbow needs the same sign to bend the
	# forearm forward under the upper arm rather than back behind the body.
	pose["elbow_l"] = Vector3(ELBOW_REST + arm * 0.6 * maxf(0.0, sin(a + PI)), 0.0, 0.0)
	pose["elbow_r"] = Vector3(ELBOW_REST + arm * 0.6 * maxf(0.0, sin(a)), 0.0, 0.0)
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


## Safe mark: by the time this plays the catch has already happened
## (PlayerController._complete_mark gathers the ball before calling
## _begin) — this is the follow-through, not the reach. Both hands come up
## and close around the ball, then it's pulled straight into a carry.
static func _build_mark_safe(hip_height: float) -> Animation:
	var length := Tuning.action_duration(Tuning.Action.MARK_SAFE)
	var contact := Tuning.action_contact_time(Tuning.Action.MARK_SAFE)
	return _assemble(length, false, [
		[0.0, _pose({
			"hip_y": -0.04, "torso": Vector3(-0.08, 0.0, 0.0), "neck": Vector3(0.10, 0.0, 0.0),
			"shoulder_l": Vector3(1.15, 0.0, -0.35), "elbow_l": Vector3(-0.35, 0.0, 0.0),
			"shoulder_r": Vector3(1.15, 0.0, 0.35), "elbow_r": Vector3(-0.35, 0.0, 0.0),
			"hip_l": Vector3(0.05, 0.0, 0.0), "hip_r": Vector3(-0.05, 0.0, 0.0),
			"knee_l": Vector3(-0.22, 0.0, 0.0), "knee_r": Vector3(-0.18, 0.0, 0.0),
		})],
		[contact, _pose({
			"hip_y": -0.05, "torso": Vector3(-0.04, 0.0, 0.0), "neck": Vector3(0.06, 0.0, 0.0),
			"shoulder_l": Vector3(1.05, 0.0, -0.22), "elbow_l": Vector3(-0.75, 0.0, 0.0),
			"shoulder_r": Vector3(1.05, 0.0, 0.22), "elbow_r": Vector3(-0.75, 0.0, 0.0),
			"knee_l": Vector3(-0.16, 0.0, 0.0), "knee_r": Vector3(-0.14, 0.0, 0.0),
		})],
		[lerpf(contact, length, 0.55), _pose({
			"hip_y": -0.01, "torso": Vector3(0.05, 0.0, 0.0),
			"shoulder_l": Vector3(0.55, 0.0, -0.20), "elbow_l": Vector3(-0.95, 0.0, 0.0),
			"shoulder_r": Vector3(0.35, 0.0, 0.30), "elbow_r": Vector3(-0.55, 0.0, 0.0),
		})],
		[length, _base_pose()],
	], hip_height)


## Running/RAC mark: a snap grab that barely interrupts the stride — legs
## keep a running pose throughout rather than planting, unlike the safe
## mark above.
static func _build_mark_running(hip_height: float) -> Animation:
	var length := Tuning.action_duration(Tuning.Action.MARK_RUNNING)
	var contact := Tuning.action_contact_time(Tuning.Action.MARK_RUNNING)
	return _assemble(length, false, [
		[0.0, _pose({
			"torso": Vector3(0.10, 0.08, 0.0),
			"shoulder_l": Vector3(0.75, 0.0, -0.18), "elbow_l": Vector3(-0.55, 0.0, 0.0),
			"shoulder_r": Vector3(0.60, 0.0, 0.28), "elbow_r": Vector3(-0.45, 0.0, 0.0),
			"hip_l": Vector3(0.30, 0.0, 0.0), "knee_l": Vector3(-0.55, 0.0, 0.0),
			"hip_r": Vector3(-0.20, 0.0, 0.0), "knee_r": Vector3(-0.25, 0.0, 0.0),
		})],
		[contact, _pose({
			"torso": Vector3(0.14, 0.05, 0.0),
			"shoulder_l": Vector3(0.50, 0.0, -0.10), "elbow_l": Vector3(-0.85, 0.0, 0.0),
			"shoulder_r": Vector3(0.40, 0.0, 0.20), "elbow_r": Vector3(-0.70, 0.0, 0.0),
			"hip_l": Vector3(0.35, 0.0, 0.0), "knee_l": Vector3(-0.60, 0.0, 0.0),
			"hip_r": Vector3(-0.25, 0.0, 0.0), "knee_r": Vector3(-0.20, 0.0, 0.0),
		})],
		[length, _base_pose()],
	], hip_height)


## Aggressive/spectacular mark: the one clip that's a real lead-in rather
## than pure follow-through, since PlayerController fires the jump impulse
## and this animation together at t=0 (see _begin_aggressive_mark) — crouch
## and push off, rise with both arms sweeping up to full stretch around
## `contact` (timed to the jump's physical peak), pull the ball in, land
## and absorb. The extra hip_y lift/dip on top of the physical jump arc
## itself is deliberate: it reads as the body actively stretching for the
## ball rather than just riding the CharacterBody3D's own trajectory inert.
static func _build_mark_aggressive(hip_height: float) -> Animation:
	var length := Tuning.action_duration(Tuning.Action.MARK_AGGRESSIVE)
	var contact := Tuning.action_contact_time(Tuning.Action.MARK_AGGRESSIVE)
	return _assemble(length, false, [
		[0.0, _pose({
			"hip_y": -0.10, "torso": Vector3(-0.05, 0.0, 0.0),
			"shoulder_l": Vector3(0.55, 0.0, -0.30), "shoulder_r": Vector3(0.55, 0.0, 0.30),
			"elbow_l": Vector3(-0.30, 0.0, 0.0), "elbow_r": Vector3(-0.30, 0.0, 0.0),
			"hip_l": Vector3(-0.35, 0.0, 0.0), "knee_l": Vector3(-0.70, 0.0, 0.0),
			"hip_r": Vector3(0.20, 0.0, 0.0), "knee_r": Vector3(-0.30, 0.0, 0.0),
		})],
		[contact * 0.6, _pose({
			"hip_y": 0.05, "torso": Vector3(0.06, 0.0, 0.0), "neck": Vector3(0.08, 0.0, 0.0),
			"shoulder_l": Vector3(1.35, 0.0, -0.40), "shoulder_r": Vector3(1.35, 0.0, 0.40),
			"elbow_l": Vector3(-0.20, 0.0, 0.0), "elbow_r": Vector3(-0.20, 0.0, 0.0),
			"hip_l": Vector3(-0.55, 0.0, 0.0), "knee_l": Vector3(-0.40, 0.0, 0.0),
			"hip_r": Vector3(0.35, 0.0, 0.0), "knee_r": Vector3(-0.15, 0.0, 0.0),
		})],
		[contact, _pose({
			"hip_y": 0.08, "torso": Vector3(0.10, 0.0, 0.0), "neck": Vector3(0.10, 0.0, 0.0),
			"shoulder_l": Vector3(1.55, 0.0, -0.30), "shoulder_r": Vector3(1.55, 0.0, 0.30),
			"elbow_l": Vector3(-0.55, 0.0, 0.0), "elbow_r": Vector3(-0.55, 0.0, 0.0),
			"hip_l": Vector3(-0.40, 0.0, 0.0), "knee_l": Vector3(-0.25, 0.0, 0.0),
			"hip_r": Vector3(0.45, 0.0, 0.0), "knee_r": Vector3(-0.10, 0.0, 0.0),
		})],
		[lerpf(contact, length, 0.55), _pose({
			"hip_y": -0.02, "torso": Vector3(0.02, 0.0, 0.0),
			"shoulder_l": Vector3(0.70, 0.0, -0.20), "elbow_l": Vector3(-0.95, 0.0, 0.0),
			"shoulder_r": Vector3(0.55, 0.0, 0.28), "elbow_r": Vector3(-0.70, 0.0, 0.0),
			"hip_l": Vector3(0.10, 0.0, 0.0), "knee_l": Vector3(-0.45, 0.0, 0.0),
			"hip_r": Vector3(-0.10, 0.0, 0.0), "knee_r": Vector3(-0.40, 0.0, 0.0),
		})],
		[lerpf(contact, length, 0.85), _pose({
			"hip_y": -0.10, "torso": Vector3(-0.10, 0.0, 0.0),
			"shoulder_l": Vector3(0.50, 0.0, -0.18), "elbow_l": Vector3(-0.75, 0.0, 0.0),
			"shoulder_r": Vector3(0.40, 0.0, 0.24), "elbow_r": Vector3(-0.55, 0.0, 0.0),
			"hip_l": Vector3(0.20, 0.0, 0.0), "knee_l": Vector3(-0.60, 0.0, 0.0),
			"hip_r": Vector3(0.15, 0.0, 0.0), "knee_r": Vector3(-0.55, 0.0, 0.0),
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
		"elbow_l": Vector3(ELBOW_REST, 0.0, 0.0),
		"elbow_r": Vector3(ELBOW_REST, 0.0, 0.0),
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
## through here. Bone tracks use Godot's "NodePath:BoneName" convention —
## the node part ("Skeleton3D") resolves relative to the AnimationPlayer's
## root_node (the Rig), same as every plain node track already did.
static func _assemble(length: float, looping: bool, keys: Array,
		hip_height: float) -> Animation:
	var anim := Animation.new()
	anim.length = length
	anim.loop_mode = Animation.LOOP_LINEAR if looping else Animation.LOOP_NONE

	var hip_position_track := anim.add_track(Animation.TYPE_POSITION_3D)
	anim.track_set_path(hip_position_track, NodePath(SKELETON + ":" + BONES["hips"]))
	anim.track_set_interpolation_type(hip_position_track, Animation.INTERPOLATION_CUBIC)

	var rotation_tracks := {}
	for key: String in BONES:
		var track := anim.add_track(Animation.TYPE_ROTATION_3D)
		anim.track_set_path(track, NodePath(SKELETON + ":" + (BONES[key] as String)))
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
