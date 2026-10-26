@tool
class_name OvalEnvironment
extends Node3D

## Ground dressing for one of the Settings.field_style ovals (task board 4B
## "stadium/field options"). Field instances the style's scene and hides its
## own generated turf/fence/trees (see Field._apply_environment); the lines,
## goal posts and ground collision stay Field's, unchanged.
##
## Two scenes use this:
## - Field 1, park_environment.tscn: the park oval (first reference image).
##   Everything comes from Blender: assets/blender/scripts/build_park_oval.py.
## - Field 2, oval1_environment.tscn: the bush oval (second reference image),
##   "Oval 1" in the code. Its Blender grass and fence, a ring of 160 trees
##   15–70 m outside the boundary with gaps left for the paths at
##   (x < -85, z ~ 12) and (x ~ 0, z > 70), plus a layout glb (paths, bushes,
##   benches, scoreboard) from build_oval1_layout.py.
##
## Either way the scene's own glb children (grass, fence) instance as normal,
## and the many-copies parts are batched. The tree ring was lifted out of
## kick_to_kick.tscn, which used to hard-code it as 160 separate glb
## instances. The trees are now one MultiMeshInstance3D per mesh in each
## tree glb rather than a node tree per tree: ~6 draw calls for the whole
## ring instead of ~160+, which matters on top of a 32-player match.
##
## @tool so opening either scene in the editor shows it all. The generated
## MultiMesh nodes get no owner, so they're never saved back into the .tscn.
## For the tree ring the transform arrays below are the source of truth.
## Edit them (or regenerate them) to move trees; each array lines up with
## tree_scenes by index.

@export var tree_scenes: Array[PackedScene] = []
@export var eucalyptus: Array[Transform3D] = []
@export var basic_trees: Array[Transform3D] = []
@export var simple_trees_a: Array[Transform3D] = []
@export var simple_trees_b: Array[Transform3D] = []

## Blender layout glbs: scenes of placed copies of a few prop meshes (the
## Blender side links each copy to one mesh in park_props.blend, and the
## glTF keeps that sharing). Every distinct mesh becomes one MultiMesh, so a
## layout of 350 benches, bushes and trees costs ~14 meshes' worth of draw
## calls. To move a bench, move it in the .blend and re-export. Placement
## lives there, not here.
@export var layout_scenes: Array[PackedScene] = []

## Meshes flatter than this (paths, painted decals) don't cast shadows. A
## shadow from something lying on the grass is invisible and costs atlas.
const FLAT_MESH_HEIGHT := 0.05


func _ready() -> void:
	var placements: Array = [eucalyptus, basic_trees, simple_trees_a, simple_trees_b]
	for i in mini(tree_scenes.size(), placements.size()):
		if tree_scenes[i] != null and not (placements[i] as Array).is_empty():
			_build_ring_layer(tree_scenes[i], placements[i], "Trees%d" % i)
	for i in layout_scenes.size():
		if layout_scenes[i] != null:
			_build_layout(layout_scenes[i], "Layout%d" % i)


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
		var instances: Array[Transform3D] = []
		for t in transforms:
			instances.append(t * local)
		_add_multimesh("%s_%d" % [layer_name, p], mi, instances)
	source.free()


## Groups every MeshInstance3D in the layout by the mesh it draws, then
## builds one MultiMesh per group. Godot's glTF importer gives nodes that
## share a glTF mesh the same ArrayMesh, which is what the grouping keys on.
func _build_layout(scene: PackedScene, layer_name: String) -> void:
	var source := scene.instantiate()
	var parts: Array = []
	for child in source.get_children():
		_collect_meshes(child, Transform3D.IDENTITY, parts)
	var groups := {}   # Mesh -> [MeshInstance3D, Array[Transform3D]]
	for part: Array in parts:
		var mi: MeshInstance3D = part[0]
		if not groups.has(mi.mesh):
			var fresh: Array[Transform3D] = []
			groups[mi.mesh] = [mi, fresh]
		var transforms: Array[Transform3D] = groups[mi.mesh][1]
		transforms.append(part[1])
	for mesh: Mesh in groups:
		var mi: MeshInstance3D = groups[mesh][0]
		var transforms: Array[Transform3D] = groups[mesh][1]
		var layer := _add_multimesh("%s_%s" % [layer_name, mesh.resource_name], mi, transforms)
		if mesh.get_aabb().size.y < FLAT_MESH_HEIGHT:
			layer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	source.free()


func _add_multimesh(layer_name: String, mi: MeshInstance3D,
		transforms: Array[Transform3D]) -> MultiMeshInstance3D:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mi.mesh
	multimesh.instance_count = transforms.size()
	for t in transforms.size():
		multimesh.set_instance_transform(t, transforms[t])
	var layer := MultiMeshInstance3D.new()
	layer.name = layer_name
	layer.multimesh = multimesh
	layer.material_override = mi.material_override
	layer.cast_shadow = mi.cast_shadow
	add_child(layer)
	return layer


func _collect_meshes(node: Node, parent_xform: Transform3D, out: Array) -> void:
	var xform := parent_xform
	if node is Node3D:
		xform = parent_xform * (node as Node3D).transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		out.append([node, xform])
	for child in node.get_children():
		_collect_meshes(child, xform, out)
