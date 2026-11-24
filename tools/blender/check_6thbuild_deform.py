"""check_8thbuild_deform.py on the reworked Build 6 (rework_6thbuild.py):
every clip and the twelve ragdoll-limit poses, looking for skin through
the guernsey or the shorts, the shorts through the guernsey, and a sock
through its boot. Nothing is saved.

    blender "F:/dev/learning-&-development/New Folder/6thbuild.blend" --background --python tools/blender/check_6thbuild_deform.py [-- --only=tackled,rd_fetal] [--verbose]

The checker reads whole meshes and a "slot_id" face attribute. Build 6's
parts are left halves with a Mirror modifier and named materials, so this
applies each part's Mirror in memory first and writes slot_id from the
material names (rework_6thbuild.MATERIAL_SLOTS), then runs the checker
with Build 6's object names. The hair is part of Body here.
"""

import os
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import check_8thbuild_deform as C  # noqa: E402
import rework_6thbuild as R  # noqa: E402  (importing it only sets two head constants)

NAMES = {"B8_Body": "Body", "B8_Guernsey": "Shirt", "B8_Shorts": "Shorts", "B8_Boots": "Shoes"}


def prepare():
	"""Mirror applied and slot_id written, on the open file's objects (the
	file is never saved by this script)."""
	for name in NAMES.values():
		ob = bpy.data.objects[name]
		mod = ob.modifiers.get("Mirror")
		if mod is not None:
			with bpy.context.temp_override(object=ob, active_object=ob):
				bpy.ops.object.modifier_apply(modifier="Mirror")
		me = ob.data
		attr = me.attributes.get("slot_id") or me.attributes.new("slot_id", 'INT', 'FACE')
		for poly in me.polygons:
			mat = me.materials[poly.material_index]
			attr.data[poly.index].value = C.SLOTS[R.slot_for_material(mat.name if mat else "")]


def rename(x):
	return NAMES.get(x, x) if isinstance(x, str) else x


C.MESHES = [n for n in NAMES.values()]
## Build 8's pairs, renamed, except the guernsey over the shorts: Build 6's
## shirt stops at 1.29 m, tucked under the shorts' waist (to 1.36 m).
C.PAIRS = [tuple(rename(x) for x in p) for p in C.PAIRS if p[0] != "B8_Shorts"]
C.PAIRS.append(("Shirt", "Shorts", None, 1.28, 1.37, ()))
C.SAME_SIDE = {tuple(rename(x) for x in p) for p in C.SAME_SIDE}
C.CROSSINGS = [tuple(rename(x) for x in p) for p in C.CROSSINGS]

if __name__ == "__main__":
	prepare()
	only = None
	for arg in sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []:
		if arg.startswith("--only="):
			only = set(arg[len("--only="):].split(","))
	for name, worst in C.check(only).items():
		print("%-20s %s" % (name, worst if worst else "clean"))
