class_name RigExport
extends Node3D

## One-off dev tool: builds a bare HumanoidRig + its full HumanoidAnimations
## clip set, then bakes the whole thing to a .glb via Godot's own glTF2
## exporter (GLTFDocument) for Blender to import.
##
## WHY THIS EXISTS: there is no animation/mesh ASSET anywhere in this repo to
## export — HumanoidRig builds its Skeleton3D + primitive meshes from code in
## _ready() (humanoid_rig.gd) and HumanoidAnimations writes its clips as bone
## tracks straight into an AnimationLibrary at the same moment
## (humanoid_animations.gd). Godot's glTF exporter walks a real scene tree
## (Skeleton3D + its BoneAttachment3D/MeshInstance3D children + an
## AnimationPlayer's animation libraries), not a blend-tree graph, so this
## script assembles exactly that tree once, in memory, then hands it to
## GLTFDocument — no asset file ever existed to begin with; this generates
## one.
##
## Deliberately bypasses AnimationTree/PlayerAnimation entirely: the
## AnimationNodeStateMachine/BlendSpace2D graph has no glTF equivalent (glTF
## only knows flat, named animation clips), so the clips are attached to a
## plain AnimationPlayer here instead, library flattened onto "" so each
## clip name (idle, jog_fwd, run_fwd, kick, handball, ...) becomes its own
## top-level glTF animation — exactly what both Blender's NLA editor and a
## future Godot re-import want to see.
##
## Run via scenes/dev/rig_export.tscn, either F6 in the editor (watch the
## Output panel) or headless:
##   Godot --headless --path <project> res://scenes/dev/rig_export.tscn
## Writes res://export/humanoid_rig.glb (res://export/ is created if
## missing) and quits automatically when running headless.

const ExportPath := "res://export/humanoid_rig.glb"


func _ready() -> void:
	var rig := HumanoidRig.new()
	rig.name = "Rig"
	rig.high_detail = true
	add_child(rig)

	var player := AnimationPlayer.new()
	player.name = "AnimationPlayer"
	add_child(player)
	# Track paths in the generated library are authored relative to the rig
	# root (see player_animation.gd's own root_node wiring) — same convention
	# here so "Skeleton3D:BoneName" tracks resolve.
	player.root_node = player.get_path_to(rig)
	player.add_animation_library(&"", HumanoidAnimations.build_library(HumanoidRig.HIP_HEIGHT))

	await get_tree().process_frame  # let _ready()-built meshes/skeleton settle before baking

	# WITHOUT this: HumanoidRig's meshes hang off BoneAttachment3D nodes with
	# no per-vertex bone weights at all (rigid "follow this bone" parenting,
	# not skinning — see humanoid_rig.gd's own header, "Stubbed" note in
	# docs/HANDOVER.md). GLTFDocument only emits a glTF `skin` for an actual
	# skinned MeshInstance3D (ARRAY_BONES/ARRAY_WEIGHTS + .skeleton + .skin
	# set); with none anywhere in the tree, append_from_scene() exports
	# the Skeleton3D as a plain hierarchy of empty transform nodes instead of
	# a joint hierarchy, and Blender's glTF importer only builds an Armature
	# from nodes a skin actually references — zero skins in means zero
	# Armature out, just nested Empties. This converts every primitive mesh
	# to a trivial single-bone skin (100% weight to whichever bone it already
	# rides) so the exported file carries a real skin and imports into
	# Blender as one Armature with one Mesh object per primitive, ready to
	# use as a weight-paint/retarget reference or to delete once a real mesh
	# is skinned onto the same bones.
	_convert_to_skinned_meshes(rig.skeleton())

	var result := _export()
	if result == OK:
		print("RigExport: wrote ", ProjectSettings.globalize_path(ExportPath))
	else:
		push_error("RigExport: glTF export failed with error code %d" % result)

	if DisplayServer.get_name() == "headless":
		get_tree().quit()


## Rebinds every BoneAttachment3D's primitive meshes as real single-bone
## skins against `skeleton`, so GLTFDocument has something to hang a glTF
## `skin` off. All of HumanoidRig's bone rests use Basis.IDENTITY (see its
## BONES table — every entry is `Transform3D(Basis.IDENTITY, offset)`), so
## each bone's global rest transform is a pure translation and converting a
## mesh's vertices from "offset within its BoneAttachment3D" to "skeleton-
## local, at that bone's rest position" is just an addition, no rotation
## math to get wrong.
func _convert_to_skinned_meshes(skeleton: Skeleton3D) -> void:
	var skin := skeleton.create_skin_from_rest_transforms()
	var attachments: Array[BoneAttachment3D] = []
	for child in skeleton.get_children():
		if child is BoneAttachment3D:
			attachments.append(child)

	for attachment: BoneAttachment3D in attachments:
		var bone_idx := skeleton.find_bone(attachment.bone_name)
		var bone_rest := skeleton.get_bone_global_rest(bone_idx)
		var mesh_instances: Array[MeshInstance3D] = []
		for child in attachment.get_children():
			if child is MeshInstance3D:
				mesh_instances.append(child)

		for mesh_instance: MeshInstance3D in mesh_instances:
			var local_transform := bone_rest * mesh_instance.transform
			var arrays := mesh_instance.mesh.surface_get_arrays(0)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var vertex_count := vertices.size()
			for i in vertex_count:
				vertices[i] = local_transform * vertices[i]
				normals[i] = (local_transform.basis * normals[i]).normalized()
			arrays[Mesh.ARRAY_VERTEX] = vertices
			arrays[Mesh.ARRAY_NORMAL] = normals

			var bones := PackedInt32Array()
			var weights := PackedFloat32Array()
			bones.resize(vertex_count * 4)
			weights.resize(vertex_count * 4)
			for i in vertex_count:
				bones[i * 4] = bone_idx
				weights[i * 4] = 1.0
				# bones[i*4+1..3] / weights[i*4+1..3] stay 0 — single-bone skin.
			arrays[Mesh.ARRAY_BONES] = bones
			arrays[Mesh.ARRAY_WEIGHTS] = weights

			var skinned := ArrayMesh.new()
			skinned.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			skinned.surface_set_material(0, mesh_instance.material_override)

			attachment.remove_child(mesh_instance)
			skeleton.add_child(mesh_instance)
			mesh_instance.transform = Transform3D.IDENTITY
			mesh_instance.mesh = skinned
			mesh_instance.material_override = null  # baked into the surface above
			mesh_instance.skeleton = mesh_instance.get_path_to(skeleton)
			mesh_instance.skin = skin

		attachment.queue_free()


func _export() -> int:
	var dir := DirAccess.open("res://")
	if not dir.dir_exists("export"):
		dir.make_dir("export")

	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var err := document.append_from_scene(self, state)
	if err != OK:
		return err
	return document.write_to_filesystem(state, ExportPath)
