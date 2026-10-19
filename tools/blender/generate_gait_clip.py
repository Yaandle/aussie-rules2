"""Generates a looping locomotion clip on fifthbuild.blend's own Armature by
porting scripts/player/humanoid_animations.gd's _gait_pose()/GAITS math
straight into Blender keyframes on the rig's NATIVE bone names (pelvis,
spine2, shoulder.l, upperleg.l, ...) — not the Godot-renamed ones; that
rename happens only at export (tools/blender/export_fifthbuild.py).

This is a generated STARTING POINT, not hand-authored art: it reuses the
exact same gait parameters the procedural system already uses so the clip
reads as "the same motion, now a real asset" rather than something new, but
it's meant to be posed over/refined in Blender afterward, not kept verbatim.

Run from Blender's Scripting workspace with fifthbuild.blend open, or
headless:
    blender fifthbuild.blend --background --python tools/blender/generate_gait_clip.py

Sign/axis convention was calibrated empirically against this exact rig
before writing this (see conversation) — a positive X-euler rotation swings
a limb bone forward on both sides with no L/R mirroring needed, matching
humanoid_animations.gd's own assumption; this script relies on that holding
for every bone it touches, which hasn't been checked bone-by-bone.
"""

import bpy, math
from mathutils import Euler, Vector

TARGET_CLIP = "jog_fwd"  # change this + GAIT below to generate a different gait

FPS = bpy.context.scene.render.fps

# ── Ported verbatim from scripts/player/humanoid_animations.gd ──────────
STANCE_BIAS = 0.14
KNEE_PHASE = 0.5
KNEE_SOFTEN = 0.12
ARM_REST_OUT = 0.10
ELBOW_REST = 0.30
GAIT_SAMPLES = 14
TAU = math.tau

GAITS = {
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
}

# pose-dict key (humanoid_animations.gd convention) -> this rig's own bone
# name. "hips" doubles as a position track in the original (hip_y, handled
# separately below) as well as a rotation track.
BONE_FOR_KEY = {
	"hips": "pelvis",
	"torso": "spine2",
	"neck": "head",
	"shoulder_l": "shoulder.l",
	"shoulder_r": "shoulder.r",
	"elbow_l": "lowerarm.l",
	"elbow_r": "lowerarm.r",
	"hip_l": "upperleg.l",
	"hip_r": "upperleg.r",
	"knee_l": "lowerleg.l",
	"knee_r": "lowerleg.r",
	"ankle_l": "ankle.l",
	"ankle_r": "ankle.r",
}


def _soft_rectify(x):
	return (x + math.sqrt(x * x + KNEE_SOFTEN * KNEE_SOFTEN)) * 0.5


def _base_pose():
	return {
		"hip_y": 0.0, "hips": (0.0, 0.0, 0.0), "torso": (0.0, 0.0, 0.0),
		"neck": (0.0, 0.0, 0.0),
		"shoulder_l": (0.0, 0.0, -ARM_REST_OUT), "shoulder_r": (0.0, 0.0, ARM_REST_OUT),
		"elbow_l": (ELBOW_REST, 0.0, 0.0), "elbow_r": (ELBOW_REST, 0.0, 0.0),
		"hip_l": (0.0, 0.0, 0.0), "hip_r": (0.0, 0.0, 0.0),
		"knee_l": (0.0, 0.0, 0.0), "knee_r": (0.0, 0.0, 0.0),
		"ankle_l": (0.0, 0.0, 0.0), "ankle_r": (0.0, 0.0, 0.0),
	}


def _gait_pose(phase, g):
	a = TAU * phase + STANCE_BIAS * math.sin(TAU * phase)
	direction = g.get("dir", 1.0)
	stride = g["stride"]
	knee_lift = g["knee_lift"]
	arm = g["arm_swing"]
	bob = g["bob"]
	lean = g["lean"]
	twist = g["twist"]
	abduct = g.get("abduct", 0.0)
	yaw_bias = g.get("yaw_bias", 0.0)
	roll = g.get("roll", 0.0)

	swing_l = math.sin(a) * stride * direction
	swing_r = math.sin(a + math.pi) * stride * direction
	bend_l = -knee_lift * _soft_rectify(math.sin(a + KNEE_PHASE))
	bend_r = -knee_lift * _soft_rectify(math.sin(a + math.pi + KNEE_PHASE))
	ankle_l = max(-0.6, min(0.6, -(swing_l + bend_l) * 0.55))
	ankle_r = max(-0.6, min(0.6, -(swing_r + bend_r) * 0.55))

	pose = _base_pose()
	pose["hip_y"] = -bob * math.cos(2.0 * a)
	pose["hips"] = (0.0, twist * math.sin(a), roll * math.sin(a))
	pose["torso"] = (-lean, yaw_bias - twist * 0.7 * math.sin(a), 0.0)
	pose["neck"] = (lean * 0.6, -yaw_bias * 0.5, 0.0)
	pose["shoulder_l"] = (-swing_l * arm / max(stride, 0.02), 0.0, -ARM_REST_OUT)
	pose["shoulder_r"] = (-swing_r * arm / max(stride, 0.02), 0.0, ARM_REST_OUT)
	pose["elbow_l"] = (ELBOW_REST + arm * 0.6 * max(0.0, math.sin(a + math.pi)), 0.0, 0.0)
	pose["elbow_r"] = (ELBOW_REST + arm * 0.6 * max(0.0, math.sin(a)), 0.0, 0.0)
	pose["hip_l"] = (swing_l, 0.0, 0.0)
	pose["hip_r"] = (swing_r, 0.0, 0.0)
	pose["knee_l"] = (bend_l, 0.0, 0.0)
	pose["knee_r"] = (bend_r, 0.0, 0.0)
	pose["ankle_l"] = (ankle_l, 0.0, 0.0)
	pose["ankle_r"] = (ankle_r, 0.0, 0.0)
	return pose


def _godot_quat(xyz):
	# Matches Godot's Quaternion.from_euler(Vector3) convention (YXZ order).
	return Euler(xyz, 'YXZ').to_quaternion()


def generate(clip_name=TARGET_CLIP):
	gait = GAITS[clip_name]
	cycle = gait["cycle"]
	arm = bpy.data.objects["Armature"]
	pelvis = arm.pose.bones["pelvis"]

	# World-vertical (Blender Z-up) hip_y offset -> pelvis's own local space,
	# via the inverse of its rest rotation (pelvis's rest, per the live rig,
	# is NOT axis-aligned with world — a plain (0,0,hip_y) local offset would
	# bob in the wrong direction without this).
	rest_rot = pelvis.bone.matrix_local.to_3x3()
	rest_rot_inv = rest_rot.inverted()

	action = bpy.data.actions.get(clip_name)
	if action is None:
		action = bpy.data.actions.new(clip_name)
	else:
		for layer in list(action.layers):
			action.layers.remove(layer)
	action.use_fake_user = True

	if arm.animation_data is None:
		arm.animation_data_create()
	slot = None
	for s in action.slots:
		if s.target_id_type == 'OBJECT':
			slot = s
			break
	if slot is None:
		slot = action.slots.new(id_type='OBJECT', name="OBArmature")
	layer = action.layers.new("Layer")
	strip = layer.strips.new(type='KEYFRAME')
	cb = strip.channelbag(slot, ensure=True)

	def fcurve(data_path, index):
		for fc in cb.fcurves:
			if fc.data_path == data_path and fc.array_index == index:
				return fc
		return cb.fcurves.new(data_path=data_path, index=index)

	for bone_name in set(BONE_FOR_KEY.values()):
		arm.pose.bones[bone_name].rotation_mode = 'QUATERNION'

	samples = list(range(GAIT_SAMPLES)) + [GAIT_SAMPLES]  # + closing key at phase 1.0
	for i in samples:
		phase = float(i) / GAIT_SAMPLES
		frame = phase * cycle * FPS
		pose = _gait_pose(phase if i < GAIT_SAMPLES else 0.0, gait)

		hip_y = pose["hip_y"]
		local_delta = rest_rot_inv @ Vector((0.0, 0.0, hip_y))
		for axis in range(3):
			fc = fcurve('pose.bones["pelvis"].location', axis)
			fc.keyframe_points.insert(frame, local_delta[axis]).interpolation = 'BEZIER'

		for key, bone_name in BONE_FOR_KEY.items():
			quat = _godot_quat(pose[key])
			path = 'pose.bones["%s"].rotation_quaternion' % bone_name
			for axis in range(4):
				fc = fcurve(path, axis)
				fc.keyframe_points.insert(frame, quat[axis]).interpolation = 'BEZIER'

	action.use_cyclic = True
	for fc in cb.fcurves:
		fc.update()

	# stash it (replacing any existing stash entry for this same action,
	# whatever the track happens to be named) so the export script picks it
	# up the same way as every other clip, and a re-run doesn't pile up
	# duplicate tracks.
	for existing_track in list(arm.animation_data.nla_tracks):
		if any(s.action is action for s in existing_track.strips):
			arm.animation_data.nla_tracks.remove(existing_track)
	track = arm.animation_data.nla_tracks.new()
	track.name = "[Action Stash] " + clip_name
	track.strips.new(clip_name, 0, action)

	print("generate_gait_clip: wrote '%s' (%d samples, %.2fs @ %d fps) onto the live rig" %
		(clip_name, GAIT_SAMPLES, cycle, FPS))


if __name__ == "__main__":
	generate()
