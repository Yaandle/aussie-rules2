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

## Reparameterises the master phase before it hits any trig below — a pure
## sinusoidal warp (still starts/ends each cycle at exactly 0/TAU, still
## smooth everywhere) that lingers a touch longer around each footfall and
## sweeps faster through the middle of the swing, instead of the raw
## sin(TAU*phase) metronome reading as a march. Feel-only, small enough to
## stay monotonic (needs > -1) with headroom to spare.
const STANCE_BIAS := 0.14

## maxf(0.0, sin(x)) — used below for knee_lift/ankle — has a hard
## derivative kink at every zero-crossing (0 on one side, ~1 on the other)
## that CUBIC track interpolation can't represent without overshoot; this
## is exactly the mechanism the idle-sway comment on GAITS below diagnoses,
## just invisible at gait amplitude instead of a visible twitch — every
## footfall's knee "snaps" from bent to dead-straight rather than easing.
## Smoothed here by a soft-ReLU (approaches maxf(0,x) as SOFTEN -> 0) so the
## peak amplitude barely moves (< 1% at x=1) but the crossing itself is now
## C-infinity, plus a small residual bend through "stance" instead of a
## perfectly locked knee, which reads as more natural, not less.
const KNEE_SOFTEN := 0.12

static func _soft_rectify(x: float) -> float:
	return (x + sqrt(x * x + KNEE_SOFTEN * KNEE_SOFTEN)) * 0.5

## Locomotion clips, keyed by name. Read alongside the blend point layout
## in player_animation.gd — the two lists have to agree.
const GAITS := {
	# Revisited per the old comment's own suggestion (kept below for the
	# diagnosis): stride/knee_lift stay at exactly zero — those are what
	# fed _gait_pose()'s maxf(0.0, sin(...)) rectifier, now _soft_rectify()
	# above, but idle has no reason to touch that path at all when a plain
	# sway reads as breathing on its own. bob/lean/twist below only ever
	# ran through raw sin/cos, never the rectifier, so they were never
	# actually the twitch's cause — zeroing them alongside it was the
	# original fix being blunter than it needed to be. Small, slow
	# (~13/min, real resting-breath order of magnitude) vertical
	# chest/torso sway; no stride/arm motion, so the legs/arms stay dead
	# still exactly as before.
	#
	# Original diagnosis, unchanged: two rounds of shrinking the rectified
	# terms toward zero (0.02-ish, then ~0.006-0.01) still read as a twitch
	# rather than a sway, most visible on the character screen's tight
	# preview camera — maxf(0.0, sin(...)) has a hard kink at every
	# zero-crossing that CUBIC track interpolation, sampled at only
	# GAIT_SAMPLES (14) points over the cycle, cannot represent without
	# overshoot, and an overshoot's absolute size doesn't necessarily
	# shrink just because the signal feeding it does.
	"idle": {
		"cycle": 4.5, "stride": 0.0, "knee_lift": 0.0, "arm_swing": 0.0,
		"bob": 0.008, "lean": 0.015, "twist": 0.010,
	},
	# `roll` on the forward gaits below is new: a small pelvic hip-drop onto
	# the stance leg (real weight transfer — the swing-leg hip rises a
	# little relative to the planted one) rather than the pelvis staying
	# level through the whole stride. Smaller than strafe_l/r's own 0.05
	# (a sideways shuffle leans harder into it than a straight run does).
	"jog_fwd": {
		"cycle": 0.72, "stride": 0.42, "knee_lift": 0.75, "arm_swing": 0.45,
		"bob": 0.035, "lean": 0.08, "twist": 0.06, "roll": 0.025,
	},
	"run_fwd": {
		"cycle": 0.58, "stride": 0.72, "knee_lift": 1.25, "arm_swing": 0.85,
		"bob": 0.055, "lean": 0.20, "twist": 0.11, "roll": 0.035,
	},
	"run_back": {
		"cycle": 0.68, "stride": 0.50, "knee_lift": 0.85, "arm_swing": 0.55,
		"bob": 0.040, "lean": -0.10, "twist": 0.05, "dir": -1.0, "roll": 0.025,
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
	library.add_animation(&"mark_safe_miss", _build_mark_safe_miss(hip_height))
	library.add_animation(&"mark_running_miss", _build_mark_running_miss(hip_height))
	library.add_animation(&"hit_out", _build_hit_out(hip_height))
	library.add_animation(&"tackled", _build_tackled(hip_height))
	library.add_animation(&"tackle_grab", _build_tackle_grab(hip_height))
	library.add_animation(&"tackle_held", _build_tackle_held(hip_height))
	library.add_animation(&"tackle_takedown", _build_tackle_takedown(hip_height))
	library.add_animation(&"knocked_back", _build_knocked_back(hip_height))
	library.add_animation(&"smothered", _build_smothered(hip_height))
	library.add_animation(&"smother_dive", _build_smother_dive(hip_height))
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
	var a := TAU * phase + STANCE_BIAS * sin(TAU * phase)
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
	var bend_l := -knee_lift * _soft_rectify(sin(a + KNEE_PHASE))
	var bend_r := -knee_lift * _soft_rectify(sin(a + PI + KNEE_PHASE))
	# Keep the sole roughly parallel to the turf through the stride.
	var ankle_l := clampf(-(swing_l + bend_l) * 0.55, -0.6, 0.6)
	var ankle_r := clampf(-(swing_r + bend_r) * 0.55, -0.6, 0.6)
	# Sideways shuffle without the legs crossing: abduction opens each leg
	# AWAY from the centreline — a limb hangs along -Y, so a +Z rotation
	# swings the left foot outward (+X) and a -Z rotation swings the right
	# foot outward (-X), so the two hips never rotate toward one another.
	# `abduct`'s sign only picks which leg leads the step (that one opens a
	# little further on its push half of the cycle); its magnitude is the
	# stance width. The previous version applied one signed value to BOTH
	# hips, which by that same convention drove one leg inward across the
	# other — the shins/knees visibly clipping through each other on a hard
	# strafe. Splaying both outward instead removes the intersection while
	# still reading as a weighted side-step.
	var spread := absf(abduct)
	var lead := signf(abduct)
	var abduct_l := spread * (0.65 + 0.45 * maxf(0.0, lead * sin(a)))
	var abduct_r := -spread * (0.65 + 0.45 * maxf(0.0, -lead * sin(a)))

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
	# User brief: a bounce on the run should read as reaching the ball down
	# and back up in one motion — not the carrier ducking into a deep crouch
	# and popping back up. The dip is now shallow (hip_y bottoms at -0.03,
	# was -0.07; torso folds -0.22, was -0.40) and the recovery keyframe
	# sits at 0.35 of the post-contact time rather than 0.5, so the figure
	# is back upright and running quickly instead of unfolding slowly.
	return _assemble(length, false, [
		[0.0, _base_pose()],
		[contact * 0.55, _pose({
			"hip_y": -0.02, "torso": Vector3(-0.16, 0.0, 0.0), "neck": Vector3(0.12, 0.0, 0.0),
			"shoulder_l": Vector3(0.70, 0.0, -0.20), "shoulder_r": Vector3(0.70, 0.0, 0.20),
			"elbow_l": Vector3(-0.45, 0.0, 0.0), "elbow_r": Vector3(-0.45, 0.0, 0.0),
			"knee_l": Vector3(-0.18, 0.0, 0.0), "knee_r": Vector3(-0.18, 0.0, 0.0),
		})],
		[contact, _pose({
			"hip_y": -0.03, "torso": Vector3(-0.22, 0.0, 0.0), "neck": Vector3(0.16, 0.0, 0.0),
			"shoulder_l": Vector3(0.95, 0.0, -0.18), "shoulder_r": Vector3(0.95, 0.0, 0.18),
			"elbow_l": Vector3(-0.18, 0.0, 0.0), "elbow_r": Vector3(-0.18, 0.0, 0.0),
			"knee_l": Vector3(-0.24, 0.0, 0.0), "knee_r": Vector3(-0.24, 0.0, 0.0),
		})],
		[lerpf(contact, length, 0.35), _pose({
			"hip_y": -0.005, "torso": Vector3(-0.06, 0.0, 0.0), "neck": Vector3(0.04, 0.0, 0.0),
			"shoulder_l": Vector3(0.32, 0.0, -0.12), "shoulder_r": Vector3(0.32, 0.0, 0.12),
			"knee_l": Vector3(-0.08, 0.0, 0.0), "knee_r": Vector3(-0.08, 0.0, 0.0),
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
		# Shoulder rotation.x: 0 = arm hanging at rest, PI = straight overhead
		# (see the swing-convention comment on _gait_pose). This clip starts
		# after the catch already happened (see the doc comment above), so
		# t=0 should already read as "hands genuinely up", not the ~66 deg
		# arm-half-raised pose this used to peak at.
		[0.0, _pose({
			"hip_y": -0.04, "torso": Vector3(-0.08, 0.0, 0.0), "neck": Vector3(0.10, 0.0, 0.0),
			"shoulder_l": Vector3(2.05, 0.0, -0.35), "elbow_l": Vector3(-0.35, 0.0, 0.0),
			"shoulder_r": Vector3(2.05, 0.0, 0.35), "elbow_r": Vector3(-0.35, 0.0, 0.0),
			"hip_l": Vector3(0.05, 0.0, 0.0), "hip_r": Vector3(-0.05, 0.0, 0.0),
			"knee_l": Vector3(-0.22, 0.0, 0.0), "knee_r": Vector3(-0.18, 0.0, 0.0),
		})],
		[contact, _pose({
			"hip_y": -0.05, "torso": Vector3(-0.04, 0.0, 0.0), "neck": Vector3(0.06, 0.0, 0.0),
			"shoulder_l": Vector3(1.85, 0.0, -0.22), "elbow_l": Vector3(-0.75, 0.0, 0.0),
			"shoulder_r": Vector3(1.85, 0.0, 0.22), "elbow_r": Vector3(-0.75, 0.0, 0.0),
			"knee_l": Vector3(-0.16, 0.0, 0.0), "knee_r": Vector3(-0.14, 0.0, 0.0),
		})],
		[lerpf(contact, length, 0.55), _pose({
			"hip_y": -0.01, "torso": Vector3(0.05, 0.0, 0.0),
			"shoulder_l": Vector3(1.00, 0.0, -0.20), "elbow_l": Vector3(-0.95, 0.0, 0.0),
			"shoulder_r": Vector3(0.80, 0.0, 0.30), "elbow_r": Vector3(-0.55, 0.0, 0.0),
		})],
		[length, _base_pose()],
	], hip_height)


## Miss reaction (user brief: raise animation quality on whatever's already
## being touched, and make sure a drop reads as clearly as a catch). Shares
## _build_mark_safe's own reach-out setup pose verbatim through `contact` —
## same commitment, same plant — then diverges: hands stay open and reach
## past rather than closing into the catch clip's -0.75 elbow bend, and the
## recovery is a shorter, more deflated drop than the catch's own settle.
static func _build_mark_safe_miss(hip_height: float) -> Animation:
	var length := Tuning.action_duration(Tuning.Action.MARK_SAFE_MISS)
	var contact := Tuning.action_contact_time(Tuning.Action.MARK_SAFE_MISS)
	return _assemble(length, false, [
		# t=0 matches _build_mark_safe's own t=0 verbatim (see doc comment
		# above) — same overhead-reach fix applies here for the same reason.
		[0.0, _pose({
			"hip_y": -0.04, "torso": Vector3(-0.08, 0.0, 0.0), "neck": Vector3(0.10, 0.0, 0.0),
			"shoulder_l": Vector3(2.05, 0.0, -0.35), "elbow_l": Vector3(-0.35, 0.0, 0.0),
			"shoulder_r": Vector3(2.05, 0.0, 0.35), "elbow_r": Vector3(-0.35, 0.0, 0.0),
			"hip_l": Vector3(0.05, 0.0, 0.0), "hip_r": Vector3(-0.05, 0.0, 0.0),
			"knee_l": Vector3(-0.22, 0.0, 0.0), "knee_r": Vector3(-0.18, 0.0, 0.0),
		})],
		[contact, _pose({
			"hip_y": -0.06, "torso": Vector3(0.02, 0.0, 0.0), "neck": Vector3(0.02, 0.0, 0.0),
			"shoulder_l": Vector3(2.20, 0.0, -0.42), "elbow_l": Vector3(-0.10, 0.0, 0.0),
			"shoulder_r": Vector3(2.20, 0.0, 0.42), "elbow_r": Vector3(-0.10, 0.0, 0.0),
			"knee_l": Vector3(-0.28, 0.0, 0.0), "knee_r": Vector3(-0.24, 0.0, 0.0),
		})],
		[lerpf(contact, length, 0.6), _pose({
			"hip_y": -0.02, "torso": Vector3(-0.10, 0.0, 0.0), "neck": Vector3(0.12, 0.0, 0.0),
			"shoulder_l": Vector3(0.30, 0.0, -0.20), "elbow_l": Vector3(-0.30, 0.0, 0.0),
			"shoulder_r": Vector3(0.30, 0.0, 0.20), "elbow_r": Vector3(-0.30, 0.0, 0.0),
		})],
		[length, _base_pose()],
	], hip_height)


## Running/RAC mark: a snap grab that barely interrupts the stride — legs
## keep a running pose throughout rather than planting, unlike the safe
## mark above. Three release stages rather than two (added alongside the
## timing mechanic while already touching this clip) — the grab was
## cutting straight from the tight snap-grab pose to base in one large
## cubic jump; an intermediate half-relaxed stage reads as arms folding the
## ball into a carry rather than snapping back to neutral.
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
		[lerpf(contact, length, 0.5), _pose({
			"torso": Vector3(0.06, 0.02, 0.0),
			"shoulder_l": Vector3(0.25, 0.0, -0.14), "elbow_l": Vector3(-0.55, 0.0, 0.0),
			"shoulder_r": Vector3(0.20, 0.0, 0.24), "elbow_r": Vector3(-0.40, 0.0, 0.0),
			"hip_l": Vector3(0.18, 0.0, 0.0), "knee_l": Vector3(-0.35, 0.0, 0.0),
			"hip_r": Vector3(-0.12, 0.0, 0.0), "knee_r": Vector3(-0.12, 0.0, 0.0),
		})],
		[length, _base_pose()],
	], hip_height)


## Miss reaction (user brief: raise animation quality on whatever's already
## being touched, and make sure a drop reads as clearly as a catch). Shares
## _build_mark_running's own reach-out setup pose verbatim — visually
## you're genuinely going for it right up to `contact`, same commitment as
## the catch — and diverges only there: elbows stay extended (grasping past
## the ball) rather than snapping into the catch clip's tight -0.85/-0.70
## bend, then a quicker recovery than the catch's own release since there's
## no ball to fold into a carry.
static func _build_mark_running_miss(hip_height: float) -> Animation:
	var length := Tuning.action_duration(Tuning.Action.MARK_RUNNING_MISS)
	var contact := Tuning.action_contact_time(Tuning.Action.MARK_RUNNING_MISS)
	return _assemble(length, false, [
		[0.0, _pose({
			"torso": Vector3(0.10, 0.08, 0.0),
			"shoulder_l": Vector3(0.75, 0.0, -0.18), "elbow_l": Vector3(-0.55, 0.0, 0.0),
			"shoulder_r": Vector3(0.60, 0.0, 0.28), "elbow_r": Vector3(-0.45, 0.0, 0.0),
			"hip_l": Vector3(0.30, 0.0, 0.0), "knee_l": Vector3(-0.55, 0.0, 0.0),
			"hip_r": Vector3(-0.20, 0.0, 0.0), "knee_r": Vector3(-0.25, 0.0, 0.0),
		})],
		[contact, _pose({
			"torso": Vector3(0.18, 0.10, 0.0),
			"shoulder_l": Vector3(0.85, 0.0, -0.30), "elbow_l": Vector3(-0.20, 0.0, 0.0),
			"shoulder_r": Vector3(0.70, 0.0, 0.35), "elbow_r": Vector3(-0.15, 0.0, 0.0),
			"hip_l": Vector3(0.38, 0.0, 0.0), "knee_l": Vector3(-0.62, 0.0, 0.0),
			"hip_r": Vector3(-0.28, 0.0, 0.0), "knee_r": Vector3(-0.18, 0.0, 0.0),
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
		# Shoulder rotation.x: 0 = arm hanging at rest, PI = straight overhead
		# (see the swing-convention comment on _gait_pose). This ramp used to
		# peak at 1.55 rad (~89 deg, arm-straight-forward) right when the
		# jump crests — the one moment overhead reach actually matters for a
		# spectacular mark. Raised to ~2.75 rad (~158 deg) at `contact`, with
		# the two lead-in keys raised to match so the arms sweep smoothly up
		# to it rather than jumping the last stretch in one key.
		[contact * 0.6, _pose({
			"hip_y": 0.05, "torso": Vector3(0.06, 0.0, 0.0), "neck": Vector3(0.08, 0.0, 0.0),
			"shoulder_l": Vector3(2.05, 0.0, -0.40), "shoulder_r": Vector3(2.05, 0.0, 0.40),
			"elbow_l": Vector3(-0.20, 0.0, 0.0), "elbow_r": Vector3(-0.20, 0.0, 0.0),
			"hip_l": Vector3(-0.55, 0.0, 0.0), "knee_l": Vector3(-0.40, 0.0, 0.0),
			"hip_r": Vector3(0.35, 0.0, 0.0), "knee_r": Vector3(-0.15, 0.0, 0.0),
		})],
		[contact, _pose({
			"hip_y": 0.08, "torso": Vector3(0.10, 0.0, 0.0), "neck": Vector3(0.10, 0.0, 0.0),
			"shoulder_l": Vector3(2.75, 0.0, -0.30), "shoulder_r": Vector3(2.75, 0.0, 0.30),
			"elbow_l": Vector3(-0.35, 0.0, 0.0), "elbow_r": Vector3(-0.35, 0.0, 0.0),
			"hip_l": Vector3(-0.40, 0.0, 0.0), "knee_l": Vector3(-0.25, 0.0, 0.0),
			"hip_r": Vector3(0.45, 0.0, 0.0), "knee_r": Vector3(-0.10, 0.0, 0.0),
		})],
		[lerpf(contact, length, 0.55), _pose({
			"hip_y": -0.02, "torso": Vector3(0.02, 0.0, 0.0),
			"shoulder_l": Vector3(0.95, 0.0, -0.20), "elbow_l": Vector3(-0.95, 0.0, 0.0),
			"shoulder_r": Vector3(0.80, 0.0, 0.28), "elbow_r": Vector3(-0.70, 0.0, 0.0),
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


## Ruck Hit-Out: the same leap MARK_AGGRESSIVE uses (identical timing — see
## Tuning.ACTION_DURATION/ACTION_CONTACT's own comment on why HIT_OUT copies
## that row verbatim) but resolved as a one-armed palm rather than a
## two-handed catch — the dominant (right) arm drives up and across to tap
## the ball away, the left trails low for balance instead of mirroring it,
## and the recovery is a plain landing rather than mark_aggressive's own
## fold-into-a-carry tail, since there's nothing being caught.
static func _build_hit_out(hip_height: float) -> Animation:
	var length := Tuning.action_duration(Tuning.Action.HIT_OUT)
	var contact := Tuning.action_contact_time(Tuning.Action.HIT_OUT)
	return _assemble(length, false, [
		[0.0, _pose({
			"hip_y": -0.10, "torso": Vector3(-0.05, 0.0, 0.0),
			"shoulder_l": Vector3(0.45, 0.0, -0.24), "shoulder_r": Vector3(0.55, 0.0, 0.30),
			"elbow_l": Vector3(-0.25, 0.0, 0.0), "elbow_r": Vector3(-0.30, 0.0, 0.0),
			"hip_l": Vector3(-0.35, 0.0, 0.0), "knee_l": Vector3(-0.70, 0.0, 0.0),
			"hip_r": Vector3(0.20, 0.0, 0.0), "knee_r": Vector3(-0.30, 0.0, 0.0),
		})],
		[contact * 0.6, _pose({
			"hip_y": 0.05, "torso": Vector3(0.04, 0.0, -0.05), "neck": Vector3(0.08, 0.0, 0.0),
			"shoulder_l": Vector3(0.70, 0.0, -0.20), "shoulder_r": Vector3(2.00, 0.0, 0.20),
			"elbow_l": Vector3(-0.20, 0.0, 0.0), "elbow_r": Vector3(-0.15, 0.0, 0.0),
			"hip_l": Vector3(-0.55, 0.0, 0.0), "knee_l": Vector3(-0.40, 0.0, 0.0),
			"hip_r": Vector3(0.35, 0.0, 0.0), "knee_r": Vector3(-0.15, 0.0, 0.0),
		})],
		[contact, _pose({
			"hip_y": 0.08, "torso": Vector3(0.06, 0.0, -0.10), "neck": Vector3(0.10, 0.0, 0.0),
			"shoulder_l": Vector3(0.55, 0.0, -0.16), "shoulder_r": Vector3(2.80, 0.0, 0.10),
			"elbow_l": Vector3(-0.20, 0.0, 0.0), "elbow_r": Vector3(-0.10, 0.0, 0.0),
			"hip_l": Vector3(-0.40, 0.0, 0.0), "knee_l": Vector3(-0.25, 0.0, 0.0),
			"hip_r": Vector3(0.45, 0.0, 0.0), "knee_r": Vector3(-0.10, 0.0, 0.0),
		})],
		[lerpf(contact, length, 0.5), _pose({
			"hip_y": -0.04, "torso": Vector3(0.0, 0.0, -0.03),
			"shoulder_l": Vector3(0.30, 0.0, -0.18), "shoulder_r": Vector3(1.10, 0.0, 0.20),
			"elbow_l": Vector3(0.10, 0.0, 0.0), "elbow_r": Vector3(-0.30, 0.0, 0.0),
			"hip_l": Vector3(0.15, 0.0, 0.0), "knee_l": Vector3(-0.55, 0.0, 0.0),
			"hip_r": Vector3(0.10, 0.0, 0.0), "knee_r": Vector3(-0.50, 0.0, 0.0),
		})],
		[length, _base_pose()],
	], hip_height)


## A successfully tackled player going down, facing away from the hit —
## PlayerController._get_tackled() (and, since the hit-stick bump rework,
## _knockdown() generally) already snaps body-facing to that direction
## before this ever starts (_fall_toward()), so the clip itself only ever
## has to know how to topple straight ahead in local space, never which way
## world-space "away from the tackler" actually points.
##
## Bug found and fixed here, not just a sign flip: the original version of
## this clip never actually wrote a "hips" key at all (every pose dict
## below went straight from hip_y to torso), despite its own doc comment
## already saying the design should be "hips" (the root bone every other
## bone hangs off) carrying the big pitch and "torso"/"neck" only adding a
## small relative hunch on top. With "hips" silently staying at its
## Vector3.ZERO default the whole clip, all ~1.1-1.5 rad (63-86 deg) of
## pitch that should have been the whole body toppling as a unit landed on
## "torso" alone instead — the chest whipping back and forth relative to a
## pelvis that stayed bolt upright the entire time, which is exactly the
## "weird glitch, not a fall" report: a body snapping in half at the waist,
## not a person going to ground. Fixed by moving that big pitch onto
## "hips" where the design always said it belonged, and cutting "torso"/
## "neck" down to a genuinely small hunch (max ~0.24 rad) riding on top of
## it — legs/arms untouched, they were already using the established
## kick-derived swing convention correctly (positive = forward/up).
##
## Sign, while already in here: "hips" runs along +Y like "torso" already
## does in _gait_pose's own convention ("the torso runs along +Y, so its
## lean is the same rotation with the opposite sign" as a limb) — negative
## X pitches it toward -Z, i.e. toward wherever local "forward" currently
## points. _fall_toward() has already rotated the whole body so local
## forward IS the real fall direction by the time this clip starts, so a
## negative "hips" pitch means the body goes down face-first in the
## direction it's travelling — the read this clip has always wanted.
## Least-confident part of this fix, same as before: if it now reads as
## falling backward or into the tackler, every "hips"/"torso"/"neck" angle
## below needs the same sign flip and nothing else changes — check in the
## Animation Viewer's Tackle Sandbox.
static func _build_tackled(hip_height: float) -> Animation:
	var length := Tuning.action_duration(Tuning.Action.TACKLED)
	var contact := Tuning.action_contact_time(Tuning.Action.TACKLED)
	return _assemble(length, false, [
		# Impact: thrown off balance, arms flung wide, legs starting to buckle.
		[0.0, _pose({
			"hip_y": -0.05, "hips": Vector3(-0.30, 0.0, 0.05), "torso": Vector3(-0.10, 0.0, 0.02),
			"neck": Vector3(-0.05, 0.0, 0.0),
			"shoulder_l": Vector3(0.90, 0.0, -0.95), "elbow_l": Vector3(-0.30, 0.0, 0.0),
			"shoulder_r": Vector3(0.70, 0.0, 0.85), "elbow_r": Vector3(-0.25, 0.0, 0.0),
			"hip_l": Vector3(0.35, 0.0, 0.0), "knee_l": Vector3(-0.60, 0.0, 0.0),
			"hip_r": Vector3(0.20, 0.0, 0.0), "knee_r": Vector3(-0.75, 0.0, 0.0),
		})],
		# Mid-fall at `contact` — hips dropping hard, pitching toward the
		# ground, arms bracing forward for the landing.
		[contact, _pose({
			"hip_y": -0.45, "hips": Vector3(-0.95, 0.0, 0.08), "torso": Vector3(-0.20, 0.0, 0.03),
			"neck": Vector3(-0.10, 0.0, 0.0),
			"shoulder_l": Vector3(1.60, 0.0, -0.55), "elbow_l": Vector3(-0.20, 0.0, 0.0),
			"shoulder_r": Vector3(1.50, 0.0, 0.50), "elbow_r": Vector3(-0.20, 0.0, 0.0),
			"hip_l": Vector3(0.15, 0.0, 0.0), "knee_l": Vector3(-1.00, 0.0, 0.0),
			"hip_r": Vector3(0.05, 0.0, 0.0), "knee_r": Vector3(-1.10, 0.0, 0.0),
		})],
		# Hits the ground — near-flat, limbs sprawled.
		[lerpf(contact, length, 0.35), _pose({
			"hip_y": -0.80, "hips": Vector3(-1.30, 0.0, 0.10), "torso": Vector3(-0.24, 0.0, 0.04),
			"neck": Vector3(-0.12, 0.0, 0.05),
			"shoulder_l": Vector3(1.30, 0.0, -1.10), "elbow_l": Vector3(-0.45, 0.0, 0.0),
			"shoulder_r": Vector3(1.20, 0.0, 1.05), "elbow_r": Vector3(-0.40, 0.0, 0.0),
			"hip_l": Vector3(0.05, 0.0, 0.0), "knee_l": Vector3(-0.85, 0.0, 0.0),
			"hip_r": Vector3(-0.05, 0.0, 0.0), "knee_r": Vector3(-0.95, 0.0, 0.0),
		})],
		# Down and settled — a brief stunned beat rather than an identical
		# hold, so it reads as landing rather than freezing.
		[lerpf(contact, length, 0.62), _pose({
			"hip_y": -0.78, "hips": Vector3(-1.28, 0.0, 0.10), "torso": Vector3(-0.22, 0.0, 0.04),
			"neck": Vector3(-0.10, 0.0, 0.04),
			"shoulder_l": Vector3(1.15, 0.0, -1.00), "elbow_l": Vector3(-0.50, 0.0, 0.0),
			"shoulder_r": Vector3(1.05, 0.0, 0.95), "elbow_r": Vector3(-0.45, 0.0, 0.0),
			"hip_l": Vector3(0.08, 0.0, 0.0), "knee_l": Vector3(-0.80, 0.0, 0.0),
			"hip_r": Vector3(-0.02, 0.0, 0.0), "knee_r": Vector3(-0.90, 0.0, 0.0),
		})],
		# Push-up recovery begins, asymmetric (one arm driving off the
		# ground) rather than a symmetric rise — reads as getting up, not
		# the fall playing in reverse.
		[lerpf(contact, length, 0.88), _pose({
			"hip_y": -0.30, "hips": Vector3(-0.50, 0.0, 0.0), "torso": Vector3(-0.08, 0.0, 0.0),
			"neck": Vector3(0.05, 0.0, 0.0),
			"shoulder_l": Vector3(0.60, 0.0, -0.40), "elbow_l": Vector3(-1.20, 0.0, 0.0),
			"shoulder_r": Vector3(0.30, 0.0, 0.25), "elbow_r": Vector3(-0.35, 0.0, 0.0),
			"hip_l": Vector3(0.25, 0.0, 0.0), "knee_l": Vector3(-0.70, 0.0, 0.0),
			"hip_r": Vector3(-0.15, 0.0, 0.0), "knee_r": Vector3(-0.30, 0.0, 0.0),
		})],
		[length, _base_pose()],
	], hip_height)


## Tackler's hug beat (PlayerController._try_tackle, Slide connects only —
## see Tuning.Action's own doc comment on why Lunge doesn't get one instead
## it gets TACKLE_TAKEDOWN below): reach in and wrap both arms AROUND the
## target rather than driving down onto them — playtest feedback wanted
## Slide to read as a wrap-up hold (both bodies stay standing, synced with
## the target's own TACKLE_HELD), not a knockdown, so this clip was
## softened from an earlier "drive down" version to match: shoulders pull
## in close to near-zero spread and elbows bend deep, the shape of arms
## closing around someone rather than reaching past them. Not aimed at the
## target's actual position (no root motion yet — see player_animation.gd's
## own "NOT YET WIRED" note) — a generic committed reach-and-wrap reads
## fine since the tackler is already facing the target at the moment of
## contact.
static func _build_tackle_grab(hip_height: float) -> Animation:
	var length := Tuning.action_duration(Tuning.Action.TACKLE_GRAB)
	var contact := Tuning.action_contact_time(Tuning.Action.TACKLE_GRAB)
	return _assemble(length, false, [
		[0.0, _base_pose()],
		# Arms come up and out to gather the target in — shoulders already
		# near horizontal (PI/2 is straight out in front) with the elbows
		# opening, the shape of reaching around someone rather than at them.
		[contact * 0.55, _pose({
			"hip_y": -0.08, "torso": Vector3(-0.20, 0.0, 0.0),
			"neck": Vector3(-0.10, 0.0, 0.0),
			"shoulder_l": Vector3(1.10, 0.0, -0.18), "elbow_l": Vector3(-0.30, 0.0, 0.0),
			"shoulder_r": Vector3(1.06, 0.0, 0.16), "elbow_r": Vector3(-0.26, 0.0, 0.0),
			"hip_l": Vector3(0.24, 0.0, 0.0), "knee_l": Vector3(-0.34, 0.0, 0.0),
			"hip_r": Vector3(0.10, 0.0, 0.0), "knee_r": Vector3(-0.22, 0.0, 0.0),
		})],
		# The clamp. Shoulders sit just under horizontal and swing past
		# each other (the Z sign flips relative to _base_pose's own
		# outward rest spread), so both arms come around the front of the
		# body being held and meet on its far side.
		#
		# The elbows are only lightly bent on purpose. An earlier version
		# folded them ~1.95 rad, which reads as the forearms pointing back
		# *behind* the tackler — the upper arms were forward but the hands
		# ended up back at his own chest. Playtest report: "the arms point
		# the opposite direction, behind the player." A shallow bend keeps
		# the forearms continuing forward around the target, which is what
		# a wrap actually looks like.
		[contact, _pose({
			"hip_y": -0.16, "torso": Vector3(-0.34, 0.0, 0.0),
			"neck": Vector3(-0.16, 0.0, 0.0),
			"shoulder_l": Vector3(1.30, 0.0, 0.34), "elbow_l": Vector3(-0.70, 0.0, 0.0),
			"shoulder_r": Vector3(1.26, 0.0, -0.32), "elbow_r": Vector3(-0.66, 0.0, 0.0),
			"hip_l": Vector3(0.34, 0.0, 0.0), "knee_l": Vector3(-0.52, 0.0, 0.0),
			"hip_r": Vector3(0.18, 0.0, 0.0), "knee_r": Vector3(-0.40, 0.0, 0.0),
		})],
		# Held, with a wrestle in it: the clamp stays shut the whole time
		# (this is a 1.0s hold, not a beat to pass through) and only the
		# torso twists, so the pair looks like it is straining rather than
		# frozen mid-pose.
		[lerpf(contact, length, 0.35), _pose({
			"hip_y": -0.15, "torso": Vector3(-0.32, 0.0, 0.09),
			"neck": Vector3(-0.14, 0.0, 0.05),
			"shoulder_l": Vector3(1.32, 0.0, 0.36), "elbow_l": Vector3(-0.74, 0.0, 0.0),
			"shoulder_r": Vector3(1.24, 0.0, -0.30), "elbow_r": Vector3(-0.62, 0.0, 0.0),
			"hip_l": Vector3(0.34, 0.0, 0.0), "knee_l": Vector3(-0.50, 0.0, 0.0),
			"hip_r": Vector3(0.18, 0.0, 0.0), "knee_r": Vector3(-0.42, 0.0, 0.0),
		})],
		[lerpf(contact, length, 0.72), _pose({
			"hip_y": -0.15, "torso": Vector3(-0.30, 0.0, -0.07),
			"neck": Vector3(-0.14, 0.0, -0.04),
			"shoulder_l": Vector3(1.26, 0.0, 0.30), "elbow_l": Vector3(-0.64, 0.0, 0.0),
			"shoulder_r": Vector3(1.30, 0.0, -0.34), "elbow_r": Vector3(-0.72, 0.0, 0.0),
			"hip_l": Vector3(0.32, 0.0, 0.0), "knee_l": Vector3(-0.48, 0.0, 0.0),
			"hip_r": Vector3(0.20, 0.0, 0.0), "knee_r": Vector3(-0.44, 0.0, 0.0),
		})],
		# Let go and stand up. Only the last fraction of the clip, so the
		# release reads as a release rather than the hold quietly fading.
		[lerpf(contact, length, 0.90), _pose({
			"hip_y": -0.08, "torso": Vector3(-0.16, 0.0, 0.0),
			"shoulder_l": Vector3(0.70, 0.0, -0.10), "elbow_l": Vector3(-0.80, 0.0, 0.0),
			"shoulder_r": Vector3(0.66, 0.0, 0.10), "elbow_r": Vector3(-0.76, 0.0, 0.0),
			"hip_l": Vector3(0.14, 0.0, 0.0), "knee_l": Vector3(-0.20, 0.0, 0.0),
		})],
		[length, _base_pose()],
	], hip_height)


## Target's reaction to a Slide connect — wrapped up and held, standing,
## the whole point of TACKLE_HELD's existence (playtest feedback: Slide
## should hold them up rather than knock them down, distinct from Lunge's
## own TACKLED fall — see Tuning.Action.TACKLE_HELD's own comment). Synced
## with the tackler's own TACKLE_GRAB just above: a small backward stagger
## on impact (torso arches back slightly, the "same rotation, opposite
## sign" convention _gait_pose() establishes for a limb vs. the torso —
## positive here, unlike TACKLED's own forward crumple, since this is a
## much smaller stagger, not a topple), arms pinned close against the body
## (reduced shoulder spread, deep elbow bend — can't swing them, held
## still), a brief struggle wobble, then released back to base as the ball
## goes. No fall, so PlayerController._get_tackled() never calls
## _fall_toward() for a Slide connect — but the target does now turn to
## face the tackler for the length of the hold (_begin_tackle_hold pins
## the pair together at Tuning.TACKLE_HOLD_DISTANCE and points both at
## each other), which is what makes this read as being wrapped up by
## someone rather than staggering on the spot.
static func _build_tackle_held(hip_height: float) -> Animation:
	var length := Tuning.action_duration(Tuning.Action.TACKLE_HELD)
	var contact := Tuning.action_contact_time(Tuning.Action.TACKLE_HELD)
	return _assemble(length, false, [
		[0.0, _base_pose()],
		# Caught: arched back, arms clamped in against the ribs and folded
		# shut — held, not swinging. Deeper than the first version of this
		# clip, which barely moved and read as a shrug next to the
		# tackler's own wrap.
		[contact, _pose({
			"hip_y": -0.09, "torso": Vector3(0.26, 0.0, 0.0), "neck": Vector3(-0.10, 0.0, 0.0),
			"shoulder_l": Vector3(0.34, 0.0, 0.06), "elbow_l": Vector3(-1.15, 0.0, 0.0),
			"shoulder_r": Vector3(0.32, 0.0, -0.06), "elbow_r": Vector3(-1.12, 0.0, 0.0),
			"hip_l": Vector3(-0.20, 0.0, 0.0), "knee_l": Vector3(-0.30, 0.0, 0.0),
			"hip_r": Vector3(-0.16, 0.0, 0.0), "knee_r": Vector3(-0.26, 0.0, 0.0),
		})],
		# Two struggle beats against the hold, opposite ways, mirroring the
		# tackler's own wrestle so the pair strains together rather than
		# each drifting on its own schedule.
		[lerpf(contact, length, 0.35), _pose({
			"hip_y": -0.08, "torso": Vector3(0.22, 0.0, -0.13), "neck": Vector3(-0.09, 0.0, -0.06),
			"shoulder_l": Vector3(0.38, 0.0, 0.08), "elbow_l": Vector3(-1.20, 0.0, 0.0),
			"shoulder_r": Vector3(0.28, 0.0, -0.04), "elbow_r": Vector3(-1.05, 0.0, 0.0),
			"hip_l": Vector3(-0.22, 0.0, 0.0), "knee_l": Vector3(-0.32, 0.0, 0.0),
			"hip_r": Vector3(-0.14, 0.0, 0.0), "knee_r": Vector3(-0.24, 0.0, 0.0),
		})],
		[lerpf(contact, length, 0.72), _pose({
			"hip_y": -0.08, "torso": Vector3(0.20, 0.0, 0.11), "neck": Vector3(-0.08, 0.0, 0.05),
			"shoulder_l": Vector3(0.30, 0.0, 0.04), "elbow_l": Vector3(-1.06, 0.0, 0.0),
			"shoulder_r": Vector3(0.36, 0.0, -0.08), "elbow_r": Vector3(-1.18, 0.0, 0.0),
			"hip_l": Vector3(-0.16, 0.0, 0.0), "knee_l": Vector3(-0.26, 0.0, 0.0),
			"hip_r": Vector3(-0.20, 0.0, 0.0), "knee_r": Vector3(-0.30, 0.0, 0.0),
		})],
		# Released on the same beat the tackler lets go.
		[lerpf(contact, length, 0.90), _pose({
			"hip_y": -0.04, "torso": Vector3(0.10, 0.0, 0.0),
			"shoulder_l": Vector3(0.16, 0.0, 0.0), "elbow_l": Vector3(-0.90, 0.0, 0.0),
			"shoulder_r": Vector3(0.15, 0.0, 0.0), "elbow_r": Vector3(-0.88, 0.0, 0.0),
		})],
		[length, _base_pose()],
	], hip_height)


## Tackler's own beat on a Lunge connect (PlayerController._try_lunge_
## tackle) — playtest feedback: "the lunge tackle can take both players to
## the ground," synced with the target's own TACKLED fall (same 1.3s
## length/0.30 contact). Drives forward and down into a low, deep crouch —
## ending kneeling near the felled target, not standing over them untouched
## — then rises back up. Torso-only pitch is enough at these more modest
## crouch angles (max ~0.55 rad, an everyday forward lean, not the ~1.3 rad
## topple TACKLED/KNOCKED_BACK need the root "hips" bone for — see that
## clip's own doc comment on why the distinction matters at the extreme end
## but not here). The tackler themselves never actually falls or gets
## stunned (PlayerController._try_lunge_tackle's own doc comment) — this is
## a cosmetic crouch layered on the same "stays on feet" physical outcome
## Lunge has always had, not a second real knockdown.
static func _build_tackle_takedown(hip_height: float) -> Animation:
	var length := Tuning.action_duration(Tuning.Action.TACKLE_TAKEDOWN)
	var contact := Tuning.action_contact_time(Tuning.Action.TACKLE_TAKEDOWN)
	return _assemble(length, false, [
		[0.0, _base_pose()],
		[contact * 0.5, _pose({
			"hip_y": -0.12, "torso": Vector3(-0.35, 0.0, 0.0), "neck": Vector3(0.12, 0.0, 0.0),
			"shoulder_l": Vector3(0.75, 0.0, -0.30), "elbow_l": Vector3(-0.55, 0.0, 0.0),
			"shoulder_r": Vector3(0.70, 0.0, 0.28), "elbow_r": Vector3(-0.50, 0.0, 0.0),
			"hip_l": Vector3(0.40, 0.0, 0.0), "knee_l": Vector3(-0.55, 0.0, 0.0),
			"hip_r": Vector3(-0.15, 0.0, 0.0), "knee_r": Vector3(-0.20, 0.0, 0.0),
		})],
		[contact, _pose({
			"hip_y": -0.35, "torso": Vector3(-0.55, 0.0, 0.0), "neck": Vector3(0.18, 0.0, 0.0),
			"shoulder_l": Vector3(0.95, 0.0, -0.20), "elbow_l": Vector3(-0.75, 0.0, 0.0),
			"shoulder_r": Vector3(0.90, 0.0, 0.18), "elbow_r": Vector3(-0.70, 0.0, 0.0),
			"hip_l": Vector3(0.55, 0.0, 0.0), "knee_l": Vector3(-0.85, 0.0, 0.0),
			"hip_r": Vector3(-0.30, 0.0, 0.0), "knee_r": Vector3(-0.30, 0.0, 0.0),
		})],
		[lerpf(contact, length, 0.55), _pose({
			"hip_y": -0.55, "torso": Vector3(-0.45, 0.0, 0.0), "neck": Vector3(0.10, 0.0, 0.0),
			"shoulder_l": Vector3(0.70, 0.0, -0.15), "elbow_l": Vector3(-0.90, 0.0, 0.0),
			"shoulder_r": Vector3(0.65, 0.0, 0.14), "elbow_r": Vector3(-0.85, 0.0, 0.0),
			"hip_l": Vector3(0.65, 0.0, 0.0), "knee_l": Vector3(-1.10, 0.0, 0.0),
			"hip_r": Vector3(-0.20, 0.0, 0.0), "knee_r": Vector3(-0.40, 0.0, 0.0),
		})],
		[lerpf(contact, length, 0.85), _pose({
			"hip_y": -0.25, "torso": Vector3(-0.20, 0.0, 0.0), "neck": Vector3(0.05, 0.0, 0.0),
			"shoulder_l": Vector3(0.40, 0.0, -0.10), "elbow_l": Vector3(-0.60, 0.0, 0.0),
			"shoulder_r": Vector3(0.35, 0.0, 0.10), "elbow_r": Vector3(-0.55, 0.0, 0.0),
			"hip_l": Vector3(0.30, 0.0, 0.0), "knee_l": Vector3(-0.55, 0.0, 0.0),
			"hip_r": Vector3(-0.10, 0.0, 0.0), "knee_r": Vector3(-0.15, 0.0, 0.0),
		})],
		[length, _base_pose()],
	], hip_height)


## A clean Bump connect's own fall — mirrors _build_tackled() exactly
## (identical hip_y/shoulder/elbow/leg keys at every corresponding time)
## except "hips"/"torso"/"neck" are sign-flipped positive instead of
## negative. TACKLED's own convention pitches the body forward along
## whatever direction _fall_toward() just snapped facing to — right for a
## tackle (driven down in the direction of momentum), wrong for a clean
## hit from the front, which playtest feedback confirmed was spinning the
## target 180° to face away before falling. PlayerController._resolve_
## bump_contact() skips the facing snap entirely for this Action
## (_knockdown()'s own `snap_facing = false`), so the body falls straight
## backward relative to whichever way it was already facing — the "torso
## runs along +Y, same rotation, opposite sign as a limb" rule _gait_pose()
## already establishes, just applied to "hips" (the root bone) the same
## way the TACKLED fix did, with the sign that means "backward" instead of
## "forward." Arms/legs are physically direction-agnostic (someone losing
## their balance flails and buckles the same way whichever way they're
## about to land) so those keys are untouched from TACKLED's own values.
static func _build_knocked_back(hip_height: float) -> Animation:
	var length := Tuning.action_duration(Tuning.Action.KNOCKED_BACK)
	var contact := Tuning.action_contact_time(Tuning.Action.KNOCKED_BACK)
	return _assemble(length, false, [
		[0.0, _pose({
			"hip_y": -0.05, "hips": Vector3(0.30, 0.0, 0.05), "torso": Vector3(0.10, 0.0, 0.02),
			"neck": Vector3(0.05, 0.0, 0.0),
			"shoulder_l": Vector3(0.90, 0.0, -0.95), "elbow_l": Vector3(-0.30, 0.0, 0.0),
			"shoulder_r": Vector3(0.70, 0.0, 0.85), "elbow_r": Vector3(-0.25, 0.0, 0.0),
			"hip_l": Vector3(0.35, 0.0, 0.0), "knee_l": Vector3(-0.60, 0.0, 0.0),
			"hip_r": Vector3(0.20, 0.0, 0.0), "knee_r": Vector3(-0.75, 0.0, 0.0),
		})],
		[contact, _pose({
			"hip_y": -0.45, "hips": Vector3(0.95, 0.0, 0.08), "torso": Vector3(0.20, 0.0, 0.03),
			"neck": Vector3(0.10, 0.0, 0.0),
			"shoulder_l": Vector3(1.60, 0.0, -0.55), "elbow_l": Vector3(-0.20, 0.0, 0.0),
			"shoulder_r": Vector3(1.50, 0.0, 0.50), "elbow_r": Vector3(-0.20, 0.0, 0.0),
			"hip_l": Vector3(0.15, 0.0, 0.0), "knee_l": Vector3(-1.00, 0.0, 0.0),
			"hip_r": Vector3(0.05, 0.0, 0.0), "knee_r": Vector3(-1.10, 0.0, 0.0),
		})],
		[lerpf(contact, length, 0.35), _pose({
			"hip_y": -0.80, "hips": Vector3(1.30, 0.0, 0.10), "torso": Vector3(0.24, 0.0, 0.04),
			"neck": Vector3(0.12, 0.0, 0.05),
			"shoulder_l": Vector3(1.30, 0.0, -1.10), "elbow_l": Vector3(-0.45, 0.0, 0.0),
			"shoulder_r": Vector3(1.20, 0.0, 1.05), "elbow_r": Vector3(-0.40, 0.0, 0.0),
			"hip_l": Vector3(0.05, 0.0, 0.0), "knee_l": Vector3(-0.85, 0.0, 0.0),
			"hip_r": Vector3(-0.05, 0.0, 0.0), "knee_r": Vector3(-0.95, 0.0, 0.0),
		})],
		[lerpf(contact, length, 0.62), _pose({
			"hip_y": -0.78, "hips": Vector3(1.28, 0.0, 0.10), "torso": Vector3(0.22, 0.0, 0.04),
			"neck": Vector3(0.10, 0.0, 0.04),
			"shoulder_l": Vector3(1.15, 0.0, -1.00), "elbow_l": Vector3(-0.50, 0.0, 0.0),
			"shoulder_r": Vector3(1.05, 0.0, 0.95), "elbow_r": Vector3(-0.45, 0.0, 0.0),
			"hip_l": Vector3(0.08, 0.0, 0.0), "knee_l": Vector3(-0.80, 0.0, 0.0),
			"hip_r": Vector3(-0.02, 0.0, 0.0), "knee_r": Vector3(-0.90, 0.0, 0.0),
		})],
		[lerpf(contact, length, 0.88), _pose({
			"hip_y": -0.30, "hips": Vector3(0.50, 0.0, 0.0), "torso": Vector3(0.08, 0.0, 0.0),
			"neck": Vector3(-0.05, 0.0, 0.0),
			"shoulder_l": Vector3(0.60, 0.0, -0.40), "elbow_l": Vector3(-1.20, 0.0, 0.0),
			"shoulder_r": Vector3(0.30, 0.0, 0.25), "elbow_r": Vector3(-0.35, 0.0, 0.0),
			"hip_l": Vector3(0.25, 0.0, 0.0), "knee_l": Vector3(-0.70, 0.0, 0.0),
			"hip_r": Vector3(-0.15, 0.0, 0.0), "knee_r": Vector3(-0.30, 0.0, 0.0),
		})],
		[length, _base_pose()],
	], hip_height)


## Smother's reaction: the kick blocked at the boot, hands recoiling off
## the impact and a half-step stumble backward — a recoil, not a knockdown,
## so it never reaches TACKLED's near-flat sprawl (PlayerController.
## _get_smothered plays this directly, no fall direction to compute; the
## body doesn't turn, it just flinches).
static func _build_smothered(hip_height: float) -> Animation:
	var length := Tuning.action_duration(Tuning.Action.SMOTHERED)
	var contact := Tuning.action_contact_time(Tuning.Action.SMOTHERED)
	return _assemble(length, false, [
		[0.0, _base_pose()],
		[contact, _pose({
			"hip_y": -0.04, "torso": Vector3(0.22, 0.0, 0.0), "neck": Vector3(-0.10, 0.0, 0.0),
			"shoulder_l": Vector3(0.55, 0.0, -0.50), "elbow_l": Vector3(-0.65, 0.0, 0.0),
			"shoulder_r": Vector3(0.50, 0.0, 0.48), "elbow_r": Vector3(-0.60, 0.0, 0.0),
			"hip_l": Vector3(-0.20, 0.0, 0.0), "knee_l": Vector3(-0.15, 0.0, 0.0),
			"hip_r": Vector3(-0.15, 0.0, 0.0), "knee_r": Vector3(-0.15, 0.0, 0.0),
		})],
		[lerpf(contact, length, 0.55), _pose({
			"hip_y": -0.02, "torso": Vector3(0.10, 0.0, 0.0), "neck": Vector3(-0.04, 0.0, 0.0),
			"shoulder_l": Vector3(0.25, 0.0, -0.28), "elbow_l": Vector3(-0.35, 0.0, 0.0),
			"shoulder_r": Vector3(0.22, 0.0, 0.26), "elbow_r": Vector3(-0.32, 0.0, 0.0),
			"hip_l": Vector3(-0.08, 0.0, 0.0), "hip_r": Vector3(-0.06, 0.0, 0.0),
		})],
		[length, _base_pose()],
	], hip_height)


## Smother's dive — the beat on the SMOTHERER, not the smothered player
## (see Action.SMOTHERED just above for that side). Reworked into a real
## ground dive after playtest feedback the first version never actually
## went down ("doesn't make the player dive at the ground towards
## oppositions player feet") — a low, forward-driving lunge into a full
## horizontal stretch along the ground, both arms reaching far forward and
## low at boot height (design intent: blocking the ball off the boot, not
## catching it out of the air the way a mark's overhead reach does), one
## leg driving off then both trailing extended behind as the body goes
## flat, before snapping back to standing at the very end. Uses the same
## "hips" root-bone technique _build_tackled()'s own fix established — the
## big forward pitch belongs on "hips" (it's the root every other bone
## hangs off), "torso" only adds a small hunch on top, or the pelvis stays
## unnaturally upright while the chest folds double, the exact bug that fix
## was for. Plays out to its full length regardless of whether the dive
## actually reaches SMOTHER_RADIUS in time (see PlayerController._try_
## smother_contact) — the dive itself is the animation, the block is a
## separate game effect layered on top only if it connects. No facing
## snap needed here (unlike a knockdown) — PlayerController._update_
## smother() already keeps _smother_dive_direction, and therefore facing,
## aimed at the live target for as long as the dive is active.
static func _build_smother_dive(hip_height: float) -> Animation:
	var length := Tuning.action_duration(Tuning.Action.SMOTHER_DIVE)
	var contact := Tuning.action_contact_time(Tuning.Action.SMOTHER_DIVE)
	return _assemble(length, false, [
		[0.0, _base_pose()],
		# Push-off: still upright-ish, driving leg loading up.
		[contact * 0.35, _pose({
			"hip_y": -0.10, "hips": Vector3(-0.25, 0.0, 0.0), "torso": Vector3(-0.15, 0.0, 0.0),
			"neck": Vector3(0.10, 0.0, 0.0),
			"shoulder_l": Vector3(0.55, 0.0, -0.25), "elbow_l": Vector3(-0.20, 0.0, 0.0),
			"shoulder_r": Vector3(0.50, 0.0, 0.22), "elbow_r": Vector3(-0.20, 0.0, 0.0),
			"hip_l": Vector3(0.55, 0.0, 0.0), "knee_l": Vector3(-0.70, 0.0, 0.0),
			"hip_r": Vector3(-0.25, 0.0, 0.0), "knee_r": Vector3(-0.15, 0.0, 0.0),
		})],
		# Airborne, stretching out toward horizontal.
		[contact * 0.7, _pose({
			"hip_y": -0.35, "hips": Vector3(-0.75, 0.0, 0.0), "torso": Vector3(-0.22, 0.0, 0.0),
			"neck": Vector3(0.15, 0.0, 0.0),
			"shoulder_l": Vector3(0.80, 0.0, -0.15), "elbow_l": Vector3(-0.10, 0.0, 0.0),
			"shoulder_r": Vector3(0.75, 0.0, 0.14), "elbow_r": Vector3(-0.10, 0.0, 0.0),
			"hip_l": Vector3(0.30, 0.0, 0.0), "knee_l": Vector3(-0.30, 0.0, 0.0),
			"hip_r": Vector3(-0.55, 0.0, 0.0), "knee_r": Vector3(-0.10, 0.0, 0.0),
		})],
		# Ground contact — full horizontal stretch, arms reaching flat at
		# boot height, legs trailing extended behind.
		[contact, _pose({
			"hip_y": -0.65, "hips": Vector3(-1.15, 0.0, 0.0), "torso": Vector3(-0.20, 0.0, 0.0),
			"neck": Vector3(0.18, 0.0, 0.05),
			"shoulder_l": Vector3(0.95, 0.0, -0.10), "elbow_l": Vector3(-0.08, 0.0, 0.0),
			"shoulder_r": Vector3(0.90, 0.0, 0.10), "elbow_r": Vector3(-0.08, 0.0, 0.0),
			"hip_l": Vector3(0.10, 0.0, 0.0), "knee_l": Vector3(-0.15, 0.0, 0.0),
			"hip_r": Vector3(-0.65, 0.0, 0.0), "knee_r": Vector3(-0.08, 0.0, 0.0),
		})],
		# Held flat on the ground for a beat — the block itself lands
		# somewhere in this window.
		[lerpf(contact, length, 0.75), _pose({
			"hip_y": -0.60, "hips": Vector3(-1.10, 0.0, 0.0), "torso": Vector3(-0.18, 0.0, 0.0),
			"neck": Vector3(0.15, 0.0, 0.05),
			"shoulder_l": Vector3(0.85, 0.0, -0.12), "elbow_l": Vector3(-0.20, 0.0, 0.0),
			"shoulder_r": Vector3(0.80, 0.0, 0.12), "elbow_r": Vector3(-0.20, 0.0, 0.0),
			"hip_l": Vector3(0.15, 0.0, 0.0), "knee_l": Vector3(-0.20, 0.0, 0.0),
			"hip_r": Vector3(-0.55, 0.0, 0.0), "knee_r": Vector3(-0.12, 0.0, 0.0),
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
