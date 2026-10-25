@tool
class_name Oval1Environment
extends Node3D

## The "Oval 1" ground dressing (task board 4B "stadium/field options"):
## the Blender grass and fence plus a ring of 160 trees 15–70 m outside the
## boundary, with gaps left for the paths at (x < -85, z ~ 12) and
## (x ~ 0, z > 70). Field instances this when Settings.field_style is
## OVAL_1 and hides its own generated turf/fence/trees (see Field._ready);
## the lines, goal posts and ground collision stay Field's, unchanged.
##
## Lifted out of kick_to_kick.tscn, which used to hard-code all of this as
## 160 separate glb instances, so Full Game and Career get the same look.
## The trees are now one MultiMeshInstance3D per mesh in each tree glb
## rather than a node tree per tree: ~6 draw calls for the whole ring
## instead of ~160+, which matters on top of a 32-player match.
##
## @tool so opening this scene in the editor shows the ring. The generated
## MultiMesh nodes get no owner, so they're never saved back into the .tscn
## — the transform arrays below are the source of truth. Edit them (or
## regenerate them) to move trees; each array lines up with tree_scenes by
## index.

@export var tree_scenes: Array[PackedScene] = []
@export var eucalyptus: Array[Transform3D] = []
@export var basic_trees: Array[Transform3D] = []
@export var simple_trees_a: Array[Transform3D] = []
@export var simple_trees_b: Array[Transform3D] = []


func _ready() -> void:
	var placements: Array = [eucalyptus, basic_trees, simple_trees_a, simple_trees_b]
	for i in mini(tree_scenes.size(), placements.size()):
		if tree_scenes[i] != null and not (placements[i] as Array).is_empty():
			_build_ring_layer(tree_scenes[i], placements[i], "Trees%d" % i)


## One MultiMeshInstance3D per MeshInstance3D in the tree glb (a trunk and a
## canopy, say), each instance placed at placement * that mesh's own
## transform inside the glb so multi-part trees stay assembled. Materials
## ride on the mesh surfaces; a node-level material_override is carried
## across too. Per-surface overrides on the glb's MeshInstance3D aren't —
## Godot's glTF importer doesn't produce them.
func _build_ring_layer(scene: PackedScene, transforms: Array[Transform3D], layer_name: String) -> void:
	var source := scene.instantiate()
	var parts: Array = []
	# From the root's children: in the old per-tree instances the placement
	# transform replaced the glb root's own, so the root's is skipped here too.
	if source is MeshInstance3D and (source as MeshInstance3D).mesh != null:
		parts.append([source, Transform3D.IDENTITY])
	for child in source.get_children():
		_collect_meshes(child, Transform3D.IDENTITY, parts)
	for p in parts.size():
		var mi: MeshInstance3D = parts[p][0]
		var local: Transform3D = parts[p][1]
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = mi.mesh
		multimesh.instance_count = transforms.size()
		for t in transforms.size():
			multimesh.set_instance_transform(t, transforms[t] * local)
		var layer := MultiMeshInstance3D.new()
		layer.name = "%s_%d" % [layer_name, p]
		layer.multimesh = multimesh
		layer.material_override = mi.material_override
		layer.cast_shadow = mi.cast_shadow
		add_child(layer)
	source.free()


func _collect_meshes(node: Node, parent_xform: Transform3D, out: Array) -> void:
	var xform := parent_xform
	if node is Node3D:
		xform = parent_xform * (node as Node3D).transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		out.append([node, xform])
	for child in node.get_children():
		_collect_meshes(child, xform, out)
