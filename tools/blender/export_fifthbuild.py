"""Export fifthbuild.blend's Armature/Cube to res://assets/characters/fifthbuild.glb,
renaming bones to the names scripts/player/humanoid_rig.gd's HumanoidRig.BONES
expects, with every NLA-stashed action whose name is listed in CLIP_RENAME
included as its own glTF animation under the renamed clip name.

Run from Blender's Scripting workspace (Open this file, Run Script) with
fifthbuild.blend open, or headless:
    blender fifthbuild.blend --background --python tools/blender/export_fifthbuild.py

Never touches the open file's own objects/actions — everything below works
on an in-memory duplicate that gets deleted again after export, so this is
safe to re-run any time you've changed a pose/animation and want Godot to
pick it up.

Bone names:        scripts/player/humanoid_rig.gd HumanoidRig.BONES / the
                    "Import swap" header comment's EXPORT CONTRACT.
Clip names:        scripts/player/humanoid_animations.gd (GAITS keys plus
                    every library.add_animation(&"...", ...) call) and
                    scripts/player/player_animation.gd (BLEND_POINTS /
                    ACTION_STATES) — anything exported under one of those
                    names overrides the matching procedural clip in-game;
                    see player_animation.gd's _build_merged_library().
"""

import bpy

SOURCE_ARMATURE = "Armature"
SOURCE_MESH = "Cube"
EXPORT_PATH = r"F:\dev\aussie-rules2\assets\characters\fifthbuild.glb"

# fifthbuild.blend's own bone name -> the name HumanoidRig.BONES / Godot's
# SkeletonProfileHumanoid-style contract requires. No Root/Neck bone is
# inserted: Root is never looked up by name anywhere in the game code, and
# "head" is left alone (not renamed to "Neck") — the recovered `idle` action
# already keys its head motion against a bone literally named "head", and
# nothing in the game code looks up a "Neck"/"Head" bone by name (only
# HumanoidAnimations' own optional, purely-cosmetic neck-sway track targets
# "Neck", which simply no-ops if the bone isn't there — see
# player_animation.gd's ground-clamp/wireframe code, neither of which
# touches head/neck by name).
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

# Blender action name (exactly as it appears in the NLA stash / Action
# Editor) -> the Godot clip name it should override. Name new actions
# directly after their target clip (e.g. "run_fwd") and this map doesn't
# need a new entry; it only exists for names that don't already match.
# "_TPose" is deliberately left out — it's a reference pose, not a
# gameplay clip, and HumanoidAnimations has no "_TPose" slot to override.
CLIP_RENAME = {
	"idle": "idle",
	"jog_fwd": "jog_fwd",
	"run_fwd": "run_fwd",
	"Walk": "jog_fwd",
	"walk": "jog_fwd",
	"Run": "run_fwd",
	"run": "run_fwd",
}


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
	source actions map to the same clip name (e.g. a stray duplicate),
	keep whichever has the longer frame range and report the other as
	skipped, rather than letting the exporter pick one arbitrarily."""
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


def export_fifthbuild():
	src_arm_obj = bpy.data.objects[SOURCE_ARMATURE]
	src_mesh_obj = bpy.data.objects[SOURCE_MESH]

	actions = _gather_actions(src_arm_obj)
	by_clip, skipped = _pick_wanted_clips(actions)
	empty_clips = [name for name, action in by_clip.items()
		if action.frame_range[1] - action.frame_range[0] < 1]
	by_clip = {name: action for name, action in by_clip.items() if name not in empty_clips}

	if not by_clip:
		print("export_fifthbuild: nothing to export — no action matched CLIP_RENAME "
			"with real keyframe data.")
		if empty_clips:
			print("  (empty stub, skipped):", empty_clips)
		return

	# ---- duplicate the armature + mesh; the original file is never touched ----
	dup_arm_data = src_arm_obj.data.copy()
	dup_arm_obj = src_arm_obj.copy()
	dup_arm_obj.animation_data_clear()
	dup_arm_obj.data = dup_arm_data
	dup_arm_obj.name = "Armature_EXPORT_TMP"

	dup_mesh_data = src_mesh_obj.data.copy()
	dup_mesh_obj = src_mesh_obj.copy()
	dup_mesh_obj.data = dup_mesh_data
	dup_mesh_obj.name = "Cube_EXPORT_TMP"
	dup_mesh_obj.parent = dup_arm_obj
	for mod in dup_mesh_obj.modifiers:
		if mod.type == 'ARMATURE':
			mod.object = dup_arm_obj

	scene_coll = bpy.context.scene.collection
	scene_coll.objects.link(dup_arm_obj)
	scene_coll.objects.link(dup_mesh_obj)

	# Independent copies of only the wanted actions, stashed onto the
	# duplicate under their final clip names — this is what the bone
	# rename below fixes up, and it's what the exporter will see.
	dup_arm_obj.animation_data_create()
	action_copies = {}
	for clip_name, action in by_clip.items():
		copy = action.copy()
		copy.name = clip_name
		copy.use_fake_user = True
		track = dup_arm_obj.animation_data.nla_tracks.new()
		track.name = clip_name  # NLA_TRACKS export mode names the glTF animation after this
		track.strips.new(clip_name, 0, copy)
		action_copies[clip_name] = copy

	# ---- rename bones + vertex groups on the duplicate only ----
	bpy.context.view_layer.objects.active = dup_arm_obj
	bpy.ops.object.mode_set(mode='EDIT')
	renamed = []
	for old, new in BONE_RENAME.items():
		eb = dup_arm_data.edit_bones.get(old)
		if eb is not None:
			eb.name = new
			renamed.append(new)
	bpy.ops.object.mode_set(mode='OBJECT')

	for old, new in BONE_RENAME.items():
		vg = dup_mesh_obj.vertex_groups.get(old)
		if vg is not None:
			vg.name = new

	missing_bones = [old for old, new in BONE_RENAME.items() if new not in renamed]

	# ---- export ----
	bpy.ops.object.select_all(action='DESELECT')
	dup_arm_obj.select_set(True)
	dup_mesh_obj.select_set(True)
	bpy.context.view_layer.objects.active = dup_arm_obj

	# NLA_TRACKS (not ACTIONS): ACTIONS mode sweeps up every action in the
	# whole .blend compatible with an Armature-driven object, regardless of
	# which object actually uses it (confirmed by testing — it pulled in
	# the live file's own idle/_TPose actions even though they were never
	# assigned to this duplicate). NLA_TRACKS scopes strictly to this
	# object's own stashed tracks, one glTF animation per track, named
	# after the track — exactly the one-clip-per-stash-entry mapping
	# action_copies above already sets up.
	bpy.ops.export_scene.gltf(
		filepath=EXPORT_PATH,
		export_format='GLB',
		use_selection=True,
		export_animations=True,
		export_animation_mode='NLA_TRACKS',
		export_bake_animation=True,
		export_force_sampling=True,
		export_skins=True,
		export_apply=False,
	)

	# ---- cleanup: remove every trace of the duplicate ----
	bpy.data.objects.remove(dup_mesh_obj, do_unlink=True)
	bpy.data.objects.remove(dup_arm_obj, do_unlink=True)
	bpy.data.meshes.remove(dup_mesh_data, do_unlink=True)
	bpy.data.armatures.remove(dup_arm_data, do_unlink=True)
	for copy in action_copies.values():
		bpy.data.actions.remove(copy, do_unlink=True)

	print("export_fifthbuild: wrote", EXPORT_PATH)
	print("  clips exported:", sorted(action_copies.keys()))
	if skipped:
		print("  skipped (no CLIP_RENAME entry, or shadowed duplicate):", skipped)
	if empty_clips:
		print("  skipped (matched a clip name but has no keyframes yet):", empty_clips)
	if missing_bones:
		print("  WARNING: bones not found on the source armature, left unrenamed:", missing_bones)


if __name__ == "__main__":
	export_fifthbuild()
