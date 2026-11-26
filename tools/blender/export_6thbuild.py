"""Export 6thbuild.blend's Armature + Body/Shirt/Shorts/Shoes to
res://assets/characters/6thbuild.glb, renaming bones to the names
scripts/player/humanoid_rig.gd's HumanoidRig.BONES expects — same bone
names/rest pose as fifthbuild.blend (its Armature was copied in directly),
so this plugs into the exact same Godot HumanoidRig/animation pipeline.

2026-11-24 (rework_6thbuild.py, docs/BUILD6_REWORK.md): on the duplicate,
each part's Mirror is applied, its named materials become the kit shader's
slots (a "Slot" UV, U = slot + 0.5, V = the sash's distance), the back's
faces in the number box become "number" faces with the box in "UVMap",
and the four parts join under one "Kit_Mat". So Build 6 gets Build 7/8's
player_kit.gdshader: per-team colours, the sash, the red sock band (the
accent), the player's number and hair colour, in one surface and one draw.
The .blend keeps its friendly named materials and half-body Mirror.

Run from Blender's Scripting workspace (Open this file, Run Script) with
6thbuild.blend open, or headless:
    blender 6thbuild.blend --background --python tools/blender/export_6thbuild.py

Never touches the open file's own objects/actions — everything below works
on an in-memory duplicate that gets deleted again after export, so this is
safe to re-run any time you've changed the meshes/rig/animation and want
Godot to pick it up.

Bone names: scripts/player/humanoid_rig.gd HumanoidRig.BONES / the
            "Import swap" header comment's EXPORT CONTRACT.
Clip names: scripts/player/humanoid_animations.gd (GAITS keys plus every
            library.add_animation(&"...", ...) call) — anything exported
            under one of those names overrides the matching procedural
            clip in-game; see player_animation.gd's _build_merged_library().
"""

import os
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_8thbuild_mesh as K  # noqa: E402  (SLOTS, sash_v, number_uv, the number box)
import rework_6thbuild as R  # noqa: E402  (slot_for_material)

KIT_MATERIAL = "Kit_Mat"
SASH_SLOTS = ("jersey", "number")

SOURCE_ARMATURE = "Armature"
SOURCE_MESHES = ["Body", "Shirt", "Shorts", "Shoes"]
EXPORT_PATH = r"F:\dev\aussie-rules2\assets\characters\6thbuild.glb"

# Same map as export_fifthbuild.py's BONE_RENAME — 6thbuild's Armature is a
# direct copy of fifthbuild's. NOTE: this rig has no separate ankle/toe
# split yet (just one "foot.l"/"foot.r" bone each, no "ankle.l"/"ankle.r"),
# unlike the fuller chain export_fifthbuild.py's version assumes — so
# foot.l/foot.r map straight to LeftFoot/RightFoot here, and LeftToes/
# RightToes are left unmapped (HumanoidRig tolerates a missing Toes bone;
# it just won't get toe articulation until this rig grows one).
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
	"foot.l": "LeftFoot",
	"upperleg.r": "RightUpperLeg",
	"lowerleg.r": "RightLowerLeg",
	"foot.r": "RightFoot",
}

# Vertex groups skinned to a bone outside the deform chain -> the chain bone
# that should carry that weight instead. pelvis.001 is a parentless, zero-
# length leftover sitting at the pelvis; no clip moves it, so anything
# skinned to it stays at standing height while Hips moves away and stretches
# into a sliver (tackled/tackle_takedown). Merged on the duplicate only.
STRAY_WEIGHT_MERGE = {
	"pelvis.001": "pelvis",
}

# Blender action name -> the Godot clip name it should override. Name new
# actions directly after their target clip and this map doesn't need a new
# entry. The full locomotion set (PlayerAnimation.BLEND_POINTS) exists on
# 6thbuild so far — add entries here as action clips get animated.
CLIP_RENAME = {
	"idle": "idle",
	"jog_fwd": "jog_fwd",
	"run_fwd": "run_fwd",
	"run_back": "run_back",
	"strafe_l": "strafe_l",
	"strafe_r": "strafe_r",
	"run_fwd_l": "run_fwd_l",
	"run_fwd_r": "run_fwd_r",
	"tackle_grab": "tackle_grab",
	"tackle_held": "tackle_held",
	"tackle_takedown": "tackle_takedown",
	"tackled": "tackled",
	# Marking set, authored by author_6thbuild_clips.py (rest-relative poses
	# on this rig; the procedural fallbacks overwrite its rests).
	"mark_safe": "mark_safe",
	"mark_running": "mark_running",
	"mark_aggressive": "mark_aggressive",
	"mark_safe_miss": "mark_safe_miss",
	"mark_running_miss": "mark_running_miss",
	# Disposals and contest reactions, same script.
	"kick": "kick",
	"handball": "handball",
	"bounce": "bounce",
	"hit_out": "hit_out",
	"knocked_back": "knocked_back",
	"smothered": "smothered",
	"smother_dive": "smother_dive",
	"tackle_sling": "tackle_sling",
	# The two-hand ball carry PlayerAnimation lays over the arms.
	"carry": "carry",
	# Ragdoll get-ups (2026-11-26, author_6thbuild_clips.py): hands down,
	# push up, stand. PlayerAnimation plays them when they exist.
	"getup_face_down": "getup_face_down",
	"getup_face_up": "getup_face_up",
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


def _gather_actions(armature_obj):
	"""name -> Action for every action reachable off the armature (the
	active one plus every NLA-stashed/stored strip), de-duplicated by the
	underlying datablock, skipping strips whose action has been lost."""
	found = {}
	ad = armature_obj.animation_data
	if ad is None:
		return found
	if ad.action is not None:
		found[ad.action.name] = ad.action
	for track in ad.nla_tracks:
		for strip in track.strips:
			if strip.action is not None:
				found[strip.action.name] = strip.action
	return found


def _pick_wanted_clips(actions):
	"""Resolve CLIP_RENAME against what's actually in the file. When two
	source actions map to the same clip name, keep whichever has the longer
	frame range and report the other as skipped, rather than letting the
	exporter pick one arbitrarily."""
	by_clip = {}
	skipped = []
	for action_name, action in actions.items():
		clip_name = CLIP_RENAME.get(action_name)
		if clip_name is None:
			skipped.append(action_name)
			continue
		existing = by_clip.get(clip_name)
		if existing is None or (action.frame_range[1] - action.frame_range[0]) > \
				(existing.frame_range[1] - existing.frame_range[0]):
			if existing is not None:
				skipped.append(existing.name)
			by_clip[clip_name] = action
		else:
			skipped.append(action_name)
	return by_clip, skipped


def _merge_stray_weights(mesh_obj):
	"""Fold each STRAY_WEIGHT_MERGE group's weights into its target group
	(adding, so each vertex's total weight is unchanged) and drop the stray
	group. Returns {stray group: vertices moved}."""
	moved = {}
	for stray_name, target_name in STRAY_WEIGHT_MERGE.items():
		stray = mesh_obj.vertex_groups.get(stray_name)
		if stray is None:
			continue
		target = mesh_obj.vertex_groups.get(target_name)
		if target is None:
			target = mesh_obj.vertex_groups.new(name=target_name)
		count = 0
		for v in mesh_obj.data.vertices:
			for g in v.groups:
				if g.group == stray.index and g.weight > 0.0:
					target.add([v.index], g.weight, 'ADD')
					count += 1
					break
		mesh_obj.vertex_groups.remove(stray)
		moved[stray_name] = count
	return moved


def _weights_off_deform_chain(mesh_obj, armature_data):
	"""Vertex groups that still carry weight but name a bone the export
	drops (non-deform) — should always come back empty."""
	deform = {b.name for b in armature_data.bones if b.use_deform}
	bones = {b.name for b in armature_data.bones}
	bad = {}
	idx = {vg.index: vg.name for vg in mesh_obj.vertex_groups}
	for v in mesh_obj.data.vertices:
		for g in v.groups:
			name = idx[g.group]
			if g.weight > 0.0 and name in bones and name not in deform:
				bad[name] = bad.get(name, 0) + 1
	return bad


def _kitify(dup_obj):
	"""Mirror applied, materials to kit slots, one Kit_Mat (see header).
	Positions are read in the rest pose, world space, as the generator's
	sash and number tables are."""
	if dup_obj.modifiers.get("Mirror") is not None:
		with bpy.context.temp_override(object=dup_obj, active_object=dup_obj):
			bpy.ops.object.modifier_apply(modifier="Mirror")
	me = dup_obj.data
	mw = dup_obj.matrix_world
	(cx, cz), (w, h) = K.NUMBER_CENTRE, K.NUMBER_SIZE
	while len(me.uv_layers) < 1:
		me.uv_layers.new(name="UVMap")
	uv_num = me.uv_layers[0]
	uv_slot = me.uv_layers.get("Slot") or me.uv_layers.new(name="Slot")
	world = [mw @ v.co for v in me.vertices]
	for poly in me.polygons:
		mat = me.materials[poly.material_index] if me.materials else None
		slot = R.slot_for_material(mat.name if mat else "")
		if slot == "jersey":
			c = sum((world[i] for i in poly.vertices), world[0] * 0.0) / len(poly.vertices)
			n = (mw.to_3x3() @ poly.normal).normalized()
			if n.y > 0.25 and abs(c.x - cx) < w * 0.5 + 0.03 and abs(c.z - cz) < h * 0.5 + 0.05:
				slot = "number"
		sid = K.SLOTS[slot]
		for li in poly.loop_indices:
			p = world[me.loops[li].vertex_index]
			uv_slot.data[li].uv = (sid + 0.5, K.sash_v(p) if slot in SASH_SLOTS else 0.5)
			uv_num.data[li].uv = K.number_uv(p) if slot == "number" else (0.0, 0.0)
	kit = bpy.data.materials.get(KIT_MATERIAL) or bpy.data.materials.new(KIT_MATERIAL)
	me.materials.clear()
	me.materials.append(kit)
	for poly in me.polygons:
		poly.material_index = 0
	uv_num.active_render = True
	return kit


def export_6thbuild():
	src_arm_obj = bpy.data.objects[SOURCE_ARMATURE]
	src_mesh_objs = [bpy.data.objects[n] for n in SOURCE_MESHES if n in bpy.data.objects]
	missing_src_meshes = [n for n in SOURCE_MESHES if n not in bpy.data.objects]

	actions = _gather_actions(src_arm_obj)
	by_clip, skipped = _pick_wanted_clips(actions)
	empty_clips = [name for name, action in by_clip.items()
		if action.frame_range[1] - action.frame_range[0] < 1]
	by_clip = {name: action for name, action in by_clip.items() if name not in empty_clips}

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

	kit_mats = {_kitify(dup_obj) for dup_obj in dup_mesh_objs}

	# One mesh: the parts share Kit_Mat, so Godot gets one surface (as
	# export_8thbuild.py does).
	if len(dup_mesh_objs) > 1:
		override_join = _find_view3d_override()
		for o in bpy.context.view_layer.objects:
			o.select_set(False)
		for dup_obj in dup_mesh_objs:
			dup_obj.select_set(True)
		bpy.context.view_layer.objects.active = dup_mesh_objs[0]
		with bpy.context.temp_override(active_object=dup_mesh_objs[0],
				selected_editable_objects=dup_mesh_objs, **override_join):
			bpy.ops.object.join()
		joined = dup_mesh_objs[0]
		joined.name = "B6_Player_EXPORT_TMP"
		keep = joined.data
		dup_mesh_objs = [joined]
		for data in dup_mesh_datas:
			if data is not keep and data.users == 0:
				bpy.data.meshes.remove(data)
		dup_mesh_datas = [keep]

	# Contract step 3 (humanoid_rig.gd): only the deform skeleton exports.
	# Stray weights move onto their chain bone, the stray bones stop being
	# deform bones, and export_def_bones below leaves them — and the
	# ikpole/iktarget control bones, already non-deform — out of the glb.
	# The IK constraints still evaluate on the duplicate, so the baked clips
	# are unchanged.
	merged = {dup_obj.name: _merge_stray_weights(dup_obj) for dup_obj in dup_mesh_objs}
	for stray_name in STRAY_WEIGHT_MERGE:
		bone = dup_arm_data.bones.get(stray_name)
		if bone is not None:
			bone.use_deform = False
	off_chain = {dup_obj.name: _weights_off_deform_chain(dup_obj, dup_arm_data)
		for dup_obj in dup_mesh_objs}
	off_chain = {name: bad for name, bad in off_chain.items() if bad}

	# Independent copies of only the wanted actions, stashed onto the
	# duplicate under their final clip names — same shape as
	# export_fifthbuild.py's approach, so this exports one glTF animation
	# per NLA track regardless of what the live file's own action is doing.
	dup_arm_obj.animation_data_create()
	action_copies = {}
	for clip_name, action in by_clip.items():
		copy = action.copy()
		copy.name = clip_name
		copy.use_fake_user = True
		track = dup_arm_obj.animation_data.nla_tracks.new()
		track.name = clip_name
		track.strips.new(clip_name, 0, copy)
		action_copies[clip_name] = copy

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
		export_animations=bool(action_copies),
		export_animation_mode='NLA_TRACKS',
		export_bake_animation=True,
		export_force_sampling=True,
		export_skins=True,
		export_def_bones=True,
		# True: without this the Mirror modifier is never baked into the
		# exported mesh (the exporter falls back to the un-mirrored base
		# mesh data), so only the modelled half of the body ever reaches
		# Godot. The Armature modifier/skin data is unaffected either way —
		# glTF always reads joints/weights straight off the mesh's vertex
		# groups, never off a modifier's evaluated result.
		export_apply=True,
	)

	# ---- cleanup: remove every trace of the duplicate ----
	for dup_obj in dup_mesh_objs:
		bpy.data.objects.remove(dup_obj, do_unlink=True)
	bpy.data.objects.remove(dup_arm_obj, do_unlink=True)
	for dup_data in dup_mesh_datas:
		bpy.data.meshes.remove(dup_data, do_unlink=True)
	bpy.data.armatures.remove(dup_arm_data, do_unlink=True)
	for copy in action_copies.values():
		bpy.data.actions.remove(copy, do_unlink=True)
	for kit in kit_mats:
		if kit.users == 0:
			bpy.data.materials.remove(kit)

	print("export_6thbuild: wrote", EXPORT_PATH)
	print("  meshes exported:", [o.name for o in src_mesh_objs])
	print("  clips exported:", sorted(action_copies.keys()))
	print("  stray weights merged (vertices per group):", merged)
	if off_chain:
		print("  WARNING: vertices still weighted to non-deform bones (dropped from the skin):", off_chain)
	if missing_src_meshes:
		print("  WARNING: expected mesh objects not found, skipped:", missing_src_meshes)
	if skipped:
		print("  skipped (no CLIP_RENAME entry, or shadowed duplicate):", skipped)
	if empty_clips:
		print("  skipped (matched a clip name but has no keyframes yet):", empty_clips)
	if missing_bones:
		print("  WARNING: bones not found on the source armature, left unrenamed:", missing_bones)


if __name__ == "__main__":
	export_6thbuild()
