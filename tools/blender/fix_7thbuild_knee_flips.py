"""Keeps each knee bending one way through a clip: re-keys the leg IK poles
(ikpole.l/.r) of the named actions in assets/blender/7thbuild.blend so the
knee's bend direction never jumps between frames.

    blender assets/blender/7thbuild.blend --background --python tools/blender/fix_7thbuild_knee_flips.py -- tackled smother_dive

WHY: the rig's legs are IK with a pole target in front of each knee. When a
foot passes its pole, the IK flips the knee to the other side in one frame.
`tackled` did it twice for both legs, bent ~90 deg: at 0.40 s in the fall
and back at 0.96 s in the get-up (124-128 deg in 1/48 s), and the ragdoll
get-up plays that same stretch. The smother dive's push-up did it too.
scenes/dev/anim_audit.tscn saw it as a 50 rad/s spike.

HOW: every frame, the knee's bend direction (the knee off the hip-ankle
line) is compared with the previous frame's. The first frame is trusted
(a standing player). While the clip's own direction stays within FLIP_DEG
of the carried one it's kept; when it jumps, the carried direction is
turned the least it can to stay square to the new hip-ankle line and used
instead, until the clip's own comes back to it. Then every frame's pole is
keyed one bone-length out along the chosen direction. Frames that didn't
flip key the pole where the knee already pointed, so they look the same.
Build 6's .blend is never opened. Re-run after re-authoring a clip.
"""

import math
import sys

import bpy
from mathutils import Vector

FLIP_DEG = 45.0


def bend_dir(pb, side):
	H, K, A = pb["upperleg." + side].head, pb["lowerleg." + side].head, pb["foot." + side].head
	line = (A - H).normalized()
	n = (K - H) - line * (K - H).dot(line)
	return (n.normalized() if n.length > 1e-5 else None), K, line


def fix(arm, name):
	act = bpy.data.actions[name]
	ad = arm.animation_data
	ad.action = act
	ad.action_slot = act.slots[0]
	f0, f1 = (int(x) for x in act.frame_range)
	rest = {s: arm.data.bones["ikpole." + s] for s in ("l", "r")}
	poles = {"l": {}, "r": {}}
	carried = {}
	changed = {"l": 0, "r": 0}
	for f in range(f0, f1 + 1):
		bpy.context.scene.frame_set(f)
		pb = arm.pose.bones
		for s in ("l", "r"):
			n, K, line = bend_dir(pb, s)
			c = carried.get(s)
			if n is None:
				n = c
			elif c is not None and math.degrees(c.angle(n)) > FLIP_DEG:
				# The clip flipped: carry the old direction, kept square to
				# the new hip-ankle line.
				n = (c - line * c.dot(line)).normalized()
				changed[s] += 1
			carried[s] = n
			if n is not None:
				poles[s][f] = K + n * 0.8
	# Key the poles (armature axes into each pole's rest frame).
	for s in ("l", "r"):
		bone = rest[s]
		pbn = arm.pose.bones["ikpole." + s]
		for f, P in poles[s].items():
			loc = bone.matrix_local.to_quaternion().inverted() @ (P - bone.head_local)
			pbn.location = loc
			pbn.keyframe_insert("location", frame=f)
	print("fix_7thbuild_knee_flips: %-14s frames re-poled against a flip: left %d, right %d" % (
		name, changed["l"], changed["r"]))


def main():
	argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
	names = [a for a in argv if a in bpy.data.actions]
	arm = bpy.data.objects["Armature"]
	ad = arm.animation_data
	saved, saved_nla = ad.action, ad.use_nla
	ad.use_nla = False
	for name in names:
		fix(arm, name)
	ad.action, ad.use_nla = saved, saved_nla
	if "--no-save" not in argv:
		bpy.ops.wm.save_mainfile()


if __name__ == "__main__":
	main()
