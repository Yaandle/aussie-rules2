"""Authors Build 7's standing idle: arms hanging relaxed at the sides
instead of held out in the rest A-pose, with a slow breath through the
chest. Writes the "idle" action on assets/blender/7thbuild.blend's
Armature. Build 6's clips (and its .blend) are never touched.

    blender assets/blender/7thbuild.blend --background --python tools/blender/author_7thbuild_idle.py [-- --no-save]

WHY: the idle both builds inherited is 6thbuild's original, and it holds
the arms where the rest pose has them, ~53° out from the sides (an
A-pose). A player standing at a stoppage, and the character screen's
preview, stood like a mannequin waiting to be rigged (playtest 2026-11-09:
"the player default idle animation is not the t pose but the hands sitting
naturally pointing down").

THE ORIGINAL IS KEPT as "idle_base": every clip script builds its poses as
offsets from frame 1 of the base idle (author_6thbuild_clips.BASE_ACTION;
author_7thbuild_gaits.py samples it too), and those clips were authored
against the A-pose arms. Both scripts read "idle_base" when the file has
it, so re-running them gives the same clips as before. idle_base isn't in
export_7thbuild.CLIP_RENAME, so it never reaches the .glb.

THE POSE: each wrist hangs a hand's width outside the thigh, a little in
front of the shoulder, close enough to it that the elbow keeps a soft bend
(about 15°); elbows point back, bent about the ragdoll's elbow hinge
(solve_arm's hinge mode, as the Build 7 gaits do). The clavicles drop a
couple of degrees. The legs and feet are the base idle's. Every joint is
well inside PhysicsRagdoll.BODIES' limits (the upper arm turns ~50° of its
75° swing to hang), since a tackle can land on a standing player and the
ragdoll starts from the animated pose.

THE MOTION: one breath per CYCLE seconds. The chest lifts and opens a
little on the in-breath (spine2 back, clavicles up), the hips settle a few
millimetres, the head stays level, and the hands drift a centimetre with
the shoulders. Slow and small: it should read as alive at match distance
and calm up close. Unplaytested feel numbers.
"""

import math
import os
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import author_6thbuild_clips as A  # noqa: E402  (the rig helpers: IK, keying, frames)

NAME = "idle"
BASE = "idle_base"
CYCLE = 3.0            # s per breath; the procedural rig's idle sways over 4.5
## Wrist target from its own shoulder joint (m): out, forward, down. The
## arm is 0.648 m shoulder to wrist; 0.61 of reach leaves the elbow ~15°
## of bend. Out far enough that the hand clears the shorts' hip (0.23 m
## from the midline) with the arm hanging.
HAND = (0.05, 0.035, 0.605)
## Elbow pole direction: back and a little out, so the elbow points behind.
ELBOW = (0.35, -1.0, -0.2)
CLAV_DROP = 2.5        # deg the clavicles sit below their base pose
## Breath amplitudes.
CHEST_LIFT = 1.2       # deg spine2 tips back at the top of the breath
CLAV_LIFT = 1.5        # deg the clavicles rise with it
HIPS_SETTLE = 0.004    # m the pelvis dips on the out-breath
HAND_DRIFT = 0.010     # m the hands move forward-back with the shoulders


def stash_base():
	"""Keeps the inherited idle as BASE (once). Its NLA track goes: the
	exporter only exports CLIP_RENAME's names anyway, and a stray track
	would make the file's NLA list lie about what's live."""
	arm_obj = bpy.data.objects[A.ARMATURE]
	if BASE in bpy.data.actions:
		return bpy.data.actions[BASE]
	old = bpy.data.actions[NAME]
	for track in list(arm_obj.animation_data.nla_tracks):
		if any(s.action is old for s in track.strips):
			arm_obj.animation_data.nla_tracks.remove(track)
	old.name = BASE
	old.use_fake_user = True
	return old


def pose_spec(phase):
	"""phase 0..1 round one breath; 0 = the bottom of the out-breath."""
	breath = 0.5 - 0.5 * math.cos(2.0 * math.pi * phase)   # 0 out .. 1 in
	ox, fwd, down = HAND
	drift = HAND_DRIFT * (breath - 0.5)
	spec = {
		"pelvis": {"pos": A.P(0.0, 0.0, -HIPS_SETTLE * (1.0 - breath))},
		"spine1": A.lean(fwd=-CHEST_LIFT * 0.3 * breath),
		"spine2": A.lean(fwd=-CHEST_LIFT * 0.7 * breath),
		"head": A.lean(fwd=CHEST_LIFT * breath),
		"clav_l": A.clav(lift=-CLAV_DROP + CLAV_LIFT * breath),
		"clav_r": A.mirror_q(A.clav(lift=-CLAV_DROP + CLAV_LIFT * breath)),
		"hands_in": "chest",
		"elbow_hinge": True,
		"hand_l": A.P(ox, fwd + drift, -down),
		"hand_r": A.P(-ox, fwd + drift, -down),
		"elbow_l": A.P(ELBOW[0], ELBOW[1], ELBOW[2]),
		"elbow_r": A.P(-ELBOW[0], ELBOW[1], ELBOW[2]),
	}
	return spec


def author(rig, base, fps):
	arm_obj = rig.obj
	old = bpy.data.actions.get(NAME)
	if old is not None:
		for track in list(arm_obj.animation_data.nla_tracks):
			if any(s.action is old for s in track.strips):
				arm_obj.animation_data.nla_tracks.remove(track)
		bpy.data.actions.remove(old)
	action = bpy.data.actions.new(NAME)
	action.use_fake_user = True
	keyer = A.Keyer(rig, action, fps)
	frames = round(CYCLE * fps)
	# Eight keys a breath; the Bezier keys in between keep it smooth.
	steps = 8
	for k in range(steps + 1):
		phase = k / steps
		basis, _ = A.build_basis(rig, base, pose_spec(phase % 1.0))
		frame = 1 + frames * phase
		for bone in A.FK_BONES + A.LEG_CONTROL_BONES:
			loc, q = basis[bone]
			keyer.key(frame, bone, loc=loc if bone == "pelvis" or bone.startswith("ik") else None, q=q)
	keyer.finish()
	track = arm_obj.animation_data.nla_tracks.new()
	track.name = NAME
	track.strips.new(NAME, 1, action)
	track.mute = True
	print("author_7thbuild_idle: %s, %d frames (%.2f s a breath)" % (NAME, frames, CYCLE))
	return action


def main():
	argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
	save = "--no-save" not in argv
	arm_obj = bpy.data.objects[A.ARMATURE]
	fps = bpy.context.scene.render.fps
	ad = arm_obj.animation_data
	saved_action = ad.action
	base_action = stash_base()
	saved_mutes = {t.name: t.mute for t in ad.nla_tracks}
	ad.action = None
	for t in ad.nla_tracks:
		t.mute = True
	for name in A.FK_BONES + A.LEG_CONTROL_BONES:
		pb = arm_obj.pose.bones[name]
		pb.location = (0, 0, 0)
		pb.rotation_quaternion = (1, 0, 0, 0)
		pb.rotation_euler = (0, 0, 0)
	A.calibrate_foot_pitch(arm_obj)
	foot = arm_obj.data.bones["foot.r"]
	along = foot.tail_local - foot.head_local
	A.FOOT_REST_BELOW = math.degrees(math.atan2(-along.z, -along.y))
	rig = A.Rig(arm_obj)
	base = A.sample_action(rig, base_action, base_action.frame_range[0])
	author(rig, base, fps)
	ad.action = saved_action if saved_action is None or saved_action.name != NAME else None
	for t in ad.nla_tracks:
		t.mute = saved_mutes.get(t.name, True)
	if save:
		bpy.ops.wm.save_mainfile()
		print("author_7thbuild_idle: saved", bpy.data.filepath)


if __name__ == "__main__":
	main()
