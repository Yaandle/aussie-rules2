"""Export 6thbuild.blend's Armature + Body/Shirt/Shorts/Shoes to
res://assets/characters/6thbuild.glb, renaming bones to the names
scripts/player/humanoid_rig.gd's HumanoidRig.BONES expects — same bone
names/rest pose as fifthbuild.blend (its Armature was copied in directly),
so this plugs into the exact same Godot HumanoidRig/animation pipeline.

Run from Blender's Scripting workspace (Open this file, Run Script) with
6thbuild.blend open, or headless:
    blender 6thbuild.blend --background --python tools/blender/export_6thbuild.py

Never touches the open file's own objects — everything below works on an
in-memory duplicate that gets deleted again after export, so this is safe
to re-run any time you've changed the meshes/rig and want Godot to pick it
up.

No animations yet (6thbuild has no actions/NLA stashed) — this exports a
static skinned mesh in its rest pose. humanoid_animations.gd's procedural
clips will still drive it in-game once bone names match, exactly as they
do for fifthbuild; see export_fifthbuild.py for the animation-export shape
once 6thbuild gets its own poses/clips.

Bone names: scripts/player/humanoid_rig.gd HumanoidRig.BONES / the
            "Import swap" header comment's EXPORT CONTRACT.
"""

import bpy

SOURCE_ARMATURE = "Armature"
SOURCE_MESHES = ["Body", "Shirt", "Shorts", "Shoes"]
EXPORT_PATH = r"F:\dev\aussie-rules2\assets\characters\6thbuild.glb"

# Same map as export_fifthbuild.py's BONE_RENAME — 6thbuild's Armature is a
# direct copy of fifthbuild's, so the source bone names are identical.
BONE_RENAME = {
	"pelvis": "Hips",
	"spine1": "Spine",
	"spine2": "Chest",
	"shoulder.l": "LeftShoulder",
	"upperarm.l": "LeftUpperArm",
	"lowerarm.l": "LeftLowerArm",
	"hand.l": "LeftHand",
	"shoulder.r": "RightShoulder",
	"upperarm.r": "RightUpperArm",
	"lowerarm.r": "RightLowerArm",
	"hand.r": "RightHand",
	"upperleg.l": "LeftUpperLeg",
	"lowerleg.l": "LeftLowerLeg",
	"ankle.l": "LeftFoot",
	"foot.l": "LeftToes",
	"upperleg.r": "RightUpperLeg",
	"lowerleg.r": "RightLowerLeg",
	"ankle.r": "RightFoot",
	"foot.r": "RightToes",
}


def _find_view3d_override():
	"""The addon's MCP code-exec path runs with no active area (context.area
	is None even though a window/VIEW_3D area exists) — object.mode_set's
	poll needs one. Hand back a context dict the caller can temp_override
	with; harmless to reuse when running as a normal in-Blender script,
	where context.area is already set and this is never needed."""
	for window in bpy.context.window_manager.windows:
		for area in window.screen.areas:
			if area.type == 'VIEW_3D':
				for region in area.regions:
					if region.type == 'WINDOW':
						return {"window": window, "area": area, "region": region}
	return {}


def export_6thbuild():
	src_arm_obj = bpy.data.objects[SOURCE_ARMATURE]
	src_mesh_objs = [bpy.data.objects[n] for n in SOURCE_MESHES if n in bpy.data.objects]
	missing_src_meshes = [n for n in SOURCE_MESHES if n not in bpy.data.objects]

	# ---- duplicate the armature + meshes; the original file is never touched ----
	dup_arm_data = src_arm_obj.data.copy()
	dup_arm_obj = src_arm_obj.copy()
	dup_arm_obj.animation_data_clear()
	dup_arm_obj.data = dup_arm_data
	dup_arm_obj.name = "Armature_EXPORT_TMP"

	scene_coll = bpy.context.scene.collection
	scene_coll.objects.link(dup_arm_obj)

	dup_mesh_objs = []
	dup_mesh_datas = []
	for src in src_mesh_objs:
		dup_data = src.data.copy()
		dup_obj = src.copy()
		dup_obj.data = dup_data
		dup_obj.name = src.name + "_EXPORT_TMP"
		dup_obj.parent = dup_arm_obj
		for mod in dup_obj.modifiers:
			if mod.type == 'ARMATURE':
				mod.object = dup_arm_obj
		scene_coll.objects.link(dup_obj)
		dup_mesh_objs.append(dup_obj)
		dup_mesh_datas.append(dup_data)

	# ---- rename bones + vertex groups on the duplicate only ----
	override = _find_view3d_override()
	bpy.context.view_layer.objects.active = dup_arm_obj
	with bpy.context.temp_override(**override):
		bpy.ops.object.mode_set(mode='EDIT')
		renamed = []
		for old, new in BONE_RENAME.items():
			eb = dup_arm_data.edit_bones.get(old)
			if eb is not None:
				eb.name = new
				renamed.append(new)
		bpy.ops.object.mode_set(mode='OBJECT')

	for dup_obj in dup_mesh_objs:
		for old, new in BONE_RENAME.items():
			vg = dup_obj.vertex_groups.get(old)
			if vg is not None:
				vg.name = new

	missing_bones = [old for old, new in BONE_RENAME.items() if new not in renamed]

	# ---- export ----
	with bpy.context.temp_override(**override):
		bpy.ops.object.select_all(action='DESELECT')
	dup_arm_obj.select_set(True)
	for dup_obj in dup_mesh_objs:
		dup_obj.select_set(True)
	bpy.context.view_layer.objects.active = dup_arm_obj

	bpy.ops.export_scene.gltf(
		filepath=EXPORT_PATH,
		export_format='GLB',
		use_selection=True,
		export_animations=False,
		export_skins=True,
		export_apply=False,
	)

	# ---- cleanup: remove every trace of the duplicate ----
	for dup_obj in dup_mesh_objs:
		bpy.data.objects.remove(dup_obj, do_unlink=True)
	bpy.data.objects.remove(dup_arm_obj, do_unlink=True)
	for dup_data in dup_mesh_datas:
		bpy.data.meshes.remove(dup_data, do_unlink=True)
	bpy.data.armatures.remove(dup_arm_data, do_unlink=True)

	print("export_6thbuild: wrote", EXPORT_PATH)
	print("  meshes exported:", [o.name for o in src_mesh_objs])
	if missing_src_meshes:
		print("  WARNING: expected mesh objects not found, skipped:", missing_src_meshes)
	if missing_bones:
		print("  WARNING: bones not found on the source armature, left unrenamed:", missing_bones)


if __name__ == "__main__":
	export_6thbuild()
