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
##   (x < -85, z ~ 12) and (x ~ 0, z > 70), plus a layout glb from
##   build_oval1_layout.py: paths, the bush wall (dark oaks, shrubs, bushes,
##   ferns, logs), benches, coach's shelters, a clubroom out west and its
##   own timber scoreboard (2026-10-31).
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
## glTF keeps that sharing). Every distinct mesh becomes one MultiMesh (two
## if some copies are in the far band), so a layout of ~1,000-1,300 benches,
## bushes and trees costs ~30 meshes' worth of draw calls. To move a bench,
## move it in the .blend and re-export. Placement lives there, not here.
@export var layout_scenes: Array[PackedScene] = []

## How the ground's scoreboard shows the score (FieldScoreboard.Style):
## Field 1's park keeps the digital seven-segment face, Field 2's bush oval
## has a hand-worked board with hung number tiles (playtest 2026-10-30), on
## its own timber prop since 2026-10-31.
@export var scoreboard_style: FieldScoreboard.Style = FieldScoreboard.Style.DIGITAL

## ── Shadow budget ───────────────────────────────────────────────────
## A MultiMesh is culled as one box, and a layout layer's box is the whole
## park, so every shadow-casting layer is drawn into every shadow split,
## all its copies. Two kinds of prop skip that:
## - Knee-high props (a mesh under SMALL_PROP_HEIGHT: paths, flower
##   patches, grass tussocks, rocks): their shadow is a smudge nobody sees
##   from 20 m up, and a path's is nothing at all. (Until 2026-10-31 only
##   flat meshes, under 5 cm, were left out.)
## - The far band. A layout object named FAR_PREFIX* (the Blender scripts
##   name the trees they plant 50-60 m and more past the fence that way)
##   goes into its own no-shadow layer. That far out it's past the sun's
##   directional_shadow_max_distance (120 m) from most of the ground anyway.
## Unmeasured: nobody has profiled a 32-player match on these grounds yet.
## If it's slow, raising SMALL_PROP_HEIGHT to ~2 m drops the bushes (the
## most copies by far) out of the shadow pass too.
const SMALL_PROP_HEIGHT := 0.8
const FAR_PREFIX := "Far"

## ── Per-copy tint (2026-10-31) ──────────────────────────────────────
## Every copy of a prop is the same mesh, so a stand of oaks was one green
## stamped out. Plants get a small per-instance tint through the MultiMesh's
## colour channel: a little darker or lighter, a little warmer or cooler,
## hashed from where the copy stands so it's the same every load. Look
## guesses, unchecked under the match cameras.
const TINT_VALUE_MIN := 0.84
const TINT_WARMTH := 0.06
## Meshes whose name contains one of these (any case) are plants and get
## tinted. Benches, the scoreboards, buildings and paths keep their exact
## colours, so don't give a non-plant prop a name with one of these in it.
const TINTED_MESH_WORDS: Array[String] = ["Oak", "Bush", "Fruit", "Gum", "Shrub", "Fern",
	"Tussock", "Agave", "Eucalyptus", "Tree", "FlowerPatch"]
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


## Whether the playing surface keeps the mown stripes baked into the
## Blender grass (Turf_Oval's two materials). Off for both ovals: they're
## parks, and a park isn't mown in bands (playtest 2026-10-30: "no lines, a
## bit of texture"), so at runtime the turf gets park_turf.gdshader,
## coloured from those same two materials. A stadium's environment scene
## turns this on and keeps its pattern.
@export var turf_stripes := false
const TURF_NODE := &"Turf_Oval"
const PARK_TURF_SHADER := preload("res://assets/shaders/park_turf.gdshader")


func _ready() -> void:
	if not Engine.is_editor_hint():
		add_to_group(GROUP)
		# Runtime only: an override set on a node inside an instanced glb
		# would be saved into the .tscn if the scene were saved in the editor.
		if not turf_stripes:
			_unstripe_turf()
	var placements: Array = [eucalyptus, basic_trees, simple_trees_a, simple_trees_b]
	for i in mini(tree_scenes.size(), placements.size()):
		if tree_scenes[i] != null and not (placements[i] as Array).is_empty():
			_build_ring_layer(tree_scenes[i], placements[i], "Trees%d" % i)
	for i in layout_scenes.size():
		if layout_scenes[i] != null:
			_build_layout(layout_scenes[i], "Layout%d" % i)


## See turf_stripes. The darker of the stripe pair is turf_dark, whichever
## surface it is.
func _unstripe_turf() -> void:
	var turf := find_child(String(TURF_NODE), true, false) as MeshInstance3D
	if turf == null or turf.mesh == null:
		return
	var colours: Array[Color] = []
	for i in turf.mesh.get_surface_count():
		var material := turf.mesh.surface_get_material(i) as BaseMaterial3D
		if material != null:
			colours.append(material.albedo_color)
	var shader := ShaderMaterial.new()
	shader.shader = PARK_TURF_SHADER
	if colours.size() >= 2:
		colours.sort_custom(func(a: Color, b: Color) -> bool: return a.get_luminance() < b.get_luminance())
		shader.set_shader_parameter(&"turf_dark", colours[0])
		shader.set_shader_parameter(&"turf_light", colours[colours.size() - 1])
	turf.material_override = shader


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
		var kept_colours: Array[Color] = []
		for i in multimesh.instance_count:
			var t := multimesh.get_instance_transform(i)
			if not _blocks_broadcast(layer.global_transform * t, aabb):
				kept.append(t)
				if multimesh.use_colors:
					kept_colours.append(multimesh.get_instance_color(i))
		if kept.size() == multimesh.instance_count:
			continue
		removed += multimesh.instance_count - kept.size()
		# Resizing wipes the buffer, tints included, so both go back in.
		multimesh.instance_count = kept.size()
		for i in kept.size():
			multimesh.set_instance_transform(i, kept[i])
			if multimesh.use_colors:
				multimesh.set_instance_color(i, kept_colours[i])
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
		# Tinted by the placement, not the part, so a tree's trunk and
		# canopy get the same shift.
		_add_multimesh("%s_%d" % [layer_name, p], mi, instances, transforms)
	source.free()


## Groups every MeshInstance3D in the layout by the mesh it draws, then
## builds one MultiMesh per group. Godot's glTF importer gives nodes that
## share a glTF mesh the same ArrayMesh, which is what the grouping keys on.
func _build_layout(scene: PackedScene, layer_name: String) -> void:
	var source := scene.instantiate()
	var parts: Array = []
	for child in source.get_children():
		_collect_meshes(child, Transform3D.IDENTITY, parts)
	# [mesh, far?] -> [MeshInstance3D, Array[Transform3D], far?]; see
	# "Shadow budget" for the far band.
	var groups := {}
	for part: Array in parts:
		var mi: MeshInstance3D = part[0]
		# The ground's scoreboard gets the live score on its face (in a
		# running game; the editor shows the prop as built).
		if mi.name == SCOREBOARD_NODE and not Engine.is_editor_hint():
			var board := FieldScoreboard.new()
			board.name = "FieldScoreboard"
			board.style = scoreboard_style
			board.transform = part[1]
			add_child(board)
		var far := String(mi.name).begins_with(FAR_PREFIX)
		var key := [mi.mesh, far]
		if not groups.has(key):
			var fresh: Array[Transform3D] = []
			groups[key] = [mi, fresh, far]
		var transforms: Array[Transform3D] = groups[key][1]
		transforms.append(part[1])
	for key: Array in groups:
		var mesh: Mesh = key[0]
		var mi: MeshInstance3D = groups[key][0]
		var transforms: Array[Transform3D] = groups[key][1]
		var far: bool = groups[key][2]
		var layer := _add_multimesh("%s_%s%s" % [layer_name, "Far_" if far else "", mesh.resource_name],
			mi, transforms, transforms)
		var height := mesh.get_aabb().size.y
		if far or height < SMALL_PROP_HEIGHT:
			layer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	source.free()


## `placements` (one per transform) are what the tint is hashed from; a
## plant mesh gets tinted, anything else ignores them.
func _add_multimesh(layer_name: String, mi: MeshInstance3D, transforms: Array[Transform3D],
		placements: Array[Transform3D]) -> MultiMeshInstance3D:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	var tinted := not Engine.is_editor_hint() and _is_plant(mi.mesh)
	# use_colors before instance_count: it sizes the buffer.
	multimesh.use_colors = tinted
	multimesh.mesh = _tintable_copy(mi.mesh) if tinted else mi.mesh
	multimesh.instance_count = transforms.size()
	for t in transforms.size():
		multimesh.set_instance_transform(t, transforms[t])
		if tinted:
			multimesh.set_instance_color(t, _tint(placements[t].origin))
	var layer := MultiMeshInstance3D.new()
	layer.name = layer_name
	layer.multimesh = multimesh
	layer.material_override = mi.material_override
	layer.cast_shadow = mi.cast_shadow
	add_child(layer)
	return layer


func _is_plant(mesh: Mesh) -> bool:
	var mesh_name := mesh.resource_name
	for word in TINTED_MESH_WORDS:
		if mesh_name.containsn(word):
			return true
	return false


## The instance colour only reaches a StandardMaterial3D's albedo when it
## uses vertex colour as albedo (the meshes have no colour array, so COLOR
## is white times the instance's tint). The imported materials are shared
## with the cached glb, so the flag goes on copies, on a copy of the mesh.
func _tintable_copy(mesh: Mesh) -> Mesh:
	var copy := mesh.duplicate() as Mesh
	for s in copy.get_surface_count():
		var material := copy.surface_get_material(s) as BaseMaterial3D
		if material == null:
			continue
		material = material.duplicate() as BaseMaterial3D
		material.vertex_color_use_as_albedo = true
		copy.surface_set_material(s, material)
	return copy


## See "Per-copy tint". Two cheap hashes of the ground position: one for
## light/dark, one for warm/cool. Darkening only, so nothing glows.
func _tint(at: Vector3) -> Color:
	var a := fposmod(sin(at.x * 12.9898 + at.z * 78.233) * 43758.5453, 1.0)
	var b := fposmod(sin(at.x * 39.3468 + at.z * 11.135) * 24634.6345, 1.0)
	var value := lerpf(TINT_VALUE_MIN, 1.0, a)
	var warmth := (b * 2.0 - 1.0) * TINT_WARMTH
	# Warm: less blue, so yellower. Cool: less red, so bluer.
	return Color(value * (1.0 - maxf(0.0, -warmth) * 2.0), value,
		value * (1.0 - maxf(0.0, warmth) * 2.0))


func _collect_meshes(node: Node, parent_xform: Transform3D, out: Array) -> void:
	var xform := parent_xform
	if node is Node3D:
		xform = parent_xform * (node as Node3D).transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		out.append([node, xform])
	for child in node.get_children():
		_collect_meshes(child, xform, out)
