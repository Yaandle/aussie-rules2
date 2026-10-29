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
## The layout object FieldScoreboard goes on (build_oval1_layout.py and
## build_park_oval.py both name it this).
const SCOREBOARD_NODE := &"Scoreboard"

## ── Broadcast side ──────────────────────────────────────────────────
## Playtest 2026-10-29: "I can't see past some of the trees when the ball is
## in either 50m arc". The FULL_SIDE camera rides a rail CAM_FULL_SIDE_
## SIDE_OFFSET (90 m) up the +Z wing, 20 m high. Level with the middle the
## tree band is behind it, but out at the arcs the fence curves in and the
## band lies between the lens and the play. A ground's broadcast side is
## its open stand, so when that camera comes on (BroadcastCamera.set_mode
## calls clear_broadcast_side) every prop standing taller than
## BROADCAST_CLEAR_MIN_TOP between the fence and the rail on that wing is
## dropped from its MultiMesh. Bushes, benches and the rest of the ring
## stay; a Chase-camera match keeps every tree. One way: the trees don't
## pop back for a set shot's brief Chase cut.
const GROUP := &"oval_environment"
## The fence ellipse, semi-axes along X and Z (assets/blender/scripts/
## field_kit.py FENCE_A / FENCE_B, the same for both ovals).
const FENCE_AXES := Vector2(91.5, 76.5)
## Lower than this (m, the top of the instance) doesn't block a lens 20 m up.
const BROADCAST_CLEAR_MIN_TOP := 3.0
## The corridor: from the fence out to this far past the rail (the camera
## sits 6 m behind it on its arm), on the rail's half of the ground
## (z > MIN_Z), not past the ends' pockets (|x| < MAX_X).
const BROADCAST_CLEAR_PAST_RAIL := 8.0
const BROADCAST_CLEAR_MIN_Z := 30.0
const BROADCAST_CLEAR_MAX_X := 105.0

var _broadcast_cleared := false


func _ready() -> void:
	if not Engine.is_editor_hint():
		add_to_group(GROUP)
	var placements: Array = [eucalyptus, basic_trees, simple_trees_a, simple_trees_b]
	for i in mini(tree_scenes.size(), placements.size()):
		if tree_scenes[i] != null and not (placements[i] as Array).is_empty():
			_build_ring_layer(tree_scenes[i], placements[i], "Trees%d" % i)
	for i in layout_scenes.size():
		if layout_scenes[i] != null:
			_build_layout(layout_scenes[i], "Layout%d" % i)


## See "Broadcast side". Rebuilds each MultiMesh without the instances in
## the corridor, so nothing is left drawing at zero scale.
func clear_broadcast_side() -> void:
	if _broadcast_cleared:
		return
	_broadcast_cleared = true
	var removed := 0
	for child in get_children():
		var layer := child as MultiMeshInstance3D
		if layer == null or layer.multimesh == null or layer.multimesh.mesh == null:
			continue
		var multimesh := layer.multimesh
		var aabb := multimesh.mesh.get_aabb()
		var kept: Array[Transform3D] = []
		for i in multimesh.instance_count:
			var t := multimesh.get_instance_transform(i)
			if not _blocks_broadcast(layer.global_transform * t, aabb):
				kept.append(t)
		if kept.size() == multimesh.instance_count:
			continue
		removed += multimesh.instance_count - kept.size()
		multimesh.instance_count = kept.size()
		for i in kept.size():
			multimesh.set_instance_transform(i, kept[i])
	print_verbose("OvalEnvironment: cleared %d props off the broadcast side" % removed)


func _blocks_broadcast(world: Transform3D, aabb: AABB) -> bool:
	var top := (world * aabb).end.y
	if top < BROADCAST_CLEAR_MIN_TOP:
		return false
	var p := world.origin
	if p.z < BROADCAST_CLEAR_MIN_Z or absf(p.x) > BROADCAST_CLEAR_MAX_X \
			or p.z > Tuning.CAM_FULL_SIDE_SIDE_OFFSET + BROADCAST_CLEAR_PAST_RAIL:
		return false
	var across := clampf(p.x / FENCE_AXES.x, -1.0, 1.0)
	return p.z > FENCE_AXES.y * sqrt(1.0 - across * across)


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
		# The ground's scoreboard gets the live score on its face (in a
		# running game; the editor shows the prop as built).
		if mi.name == SCOREBOARD_NODE and not Engine.is_editor_hint():
			var board := FieldScoreboard.new()
			board.name = "FieldScoreboard"
			board.transform = part[1]
			add_child(board)
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
