"""Authors Build 6's standing idle: arms hanging straight down, relaxed,
with a slow breath. Writes "idle" on 6thbuild.blend's Armature and keeps
the original A-pose idle as "idle_base" (once), which every clip script
builds its poses from, so re-running author_6thbuild_clips.py gives the
same clips as before.

    blender "F:/dev/learning-&-development/New Folder/6thbuild.blend" --background --python tools/blender/author_6thbuild_idle.py [-- --no-save]

author_7thbuild_idle.py with a straighter arm: that script works on
whatever file is open (Build 7's .blend is a copy of this one, same
Armature and helpers), so this only changes its pose numbers and runs it.

WHY STRAIGHTER THAN BUILD 7'S: 2026-11-24 request, "the arms more naturally
resting straight down". Build 7's wrist target (0.605 m from the shoulder
on a 0.648 m arm) left the elbow bent about 43°, which reads as holding
the arms up a little. Here the wrist sits 0.643 m below and just in front
of the shoulder joint: an elbow bend of about 15°, the soft bend a hanging
arm really has, and the hand hangs beside the thigh, palm in. Its back
clears the shorts' hip by ~2 cm (the wrist is 0.30 m from the midline).
The upper arm still turns well inside PhysicsRagdoll.BODIES' 75° swing.
Unplaytested feel numbers.
"""

import os
import sys

import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import author_7thbuild_idle as I  # noqa: E402
import author_6thbuild_clips as A  # noqa: E402

## Wrist from its own shoulder joint (m): out, forward, down.
I.HAND = (0.042, 0.022, 0.641)
## Elbow pole: straight back, so the small bend points behind.
I.ELBOW = (0.15, -1.0, -0.1)
## The clavicles sit a little lower, as hanging arms pull them.
I.CLAV_DROP = 3.5
## Standing tall: the inherited idle drops the hips 2.9 cm below the rest
## pose, which with the feet planted bends the knees forward (from the side
## it read as a crouch with the seat pushed back; the reference stands
## straight). The new idle holds the hips HIPS_ABOVE_REST above the rest
## pose instead: the feet stay where they are (the leg IK keeps them), so
## the knees open to ~6 degrees of bend. Past ~5 mm the legs reach full
## stretch and the IK snaps, so keep it small.
HIPS_ABOVE_REST = 0.004
## The breath's settle, smaller than Build 7's 4 mm: on near-straight legs
## the knees take all of it.
I.HIPS_SETTLE = 0.002

_base_drop = None


def _base_pelvis_world():
	"""The base idle's own pelvis offset at its first frame, in armature
	axes (its location keys are in the pelvis bone's frame, whose Y runs up
	the spine)."""
	act = bpy.data.actions[I.BASE]
	cb = act.layers[0].strips[0].channelbag(act.slots[0])
	loc = Vector()
	for fc in cb.fcurves:
		if fc.data_path == 'pose.bones["pelvis"].location':
			loc[fc.array_index] = fc.evaluate(act.frame_range[0])
	G = bpy.data.objects[A.ARMATURE].data.bones["pelvis"].matrix_local.to_3x3()
	return G @ loc


_inherited_pose_spec = I.pose_spec


def pose_spec(phase):
	global _base_drop
	if _base_drop is None:
		_base_drop = _base_pelvis_world()
	spec = _inherited_pose_spec(phase)
	lift = HIPS_ABOVE_REST - _base_drop.z
	spec["pelvis"]["pos"] = spec["pelvis"]["pos"] + A.P(0.0, 0.0, lift)
	return spec


I.pose_spec = pose_spec

if __name__ == "__main__":
	I.main()
