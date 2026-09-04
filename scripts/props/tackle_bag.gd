class_name TackleBag
extends Node3D

## A padded, player-sized tackle bag — training-ground dressing beside the
## kick-to-kick tackling coach. Built entirely in code like everything else
## in this project (there is no imported art); mirrors field.gd's goal-post
## idiom: a flat-topped CylinderMesh body, a dark foot collar, and a
## StaticBody3D collider so the player bumps into it rather than walking
## through.
##
## Scenery only. It carries no PlayerController, no brain and sits on the
## "world" collision layer, not "players" — so every PlayerController
## proximity query (tackle, gather, mark, bump) is blind to it. It can be
## run into, nothing more.
##
## `lying` tips the whole bag onto its side so it rests along the ground
## (a couple of spares dumped next to the standing one); `lie_yaw` spins a
## lying bag about vertical so a scatter of them doesn't all point the same
## way.

const RADIAL_SEGMENTS := 16
const BASE_HEIGHT := 0.16          ## m — the black foot collar in the reference photo
const BODY_COLLAR_OVERLAP := 0.02  ## m the collider sinks below y=0 so there is no lip to catch on

## Set by the spawner (kick_to_kick.gd) before add_child(); read in _ready().
var lying := false
var lie_yaw := 0.0


func _ready() -> void:
	var height := Tuning.TACKLE_BAG_HEIGHT
	var radius := Tuning.TACKLE_BAG_RADIUS

	var body_material := StandardMaterial3D.new()
	body_material.albedo_color = Tuning.TACKLE_BAG_COLOUR
	body_material.roughness = 0.85
	body_material.metallic = 0.0

	var base_material := StandardMaterial3D.new()
	base_material.albedo_color = Tuning.TACKLE_BAG_BASE_COLOUR
	base_material.roughness = 0.7

	# Main cylinder — flat top, origin at the feet (y = 0), so .position
	# places an upright bag on the ground with no float (same convention
	# _spawn_coach documents).
	var body := CylinderMesh.new()
	body.top_radius = radius
	body.bottom_radius = radius
	body.height = height
	body.radial_segments = RADIAL_SEGMENTS
	var body_node := MeshInstance3D.new()
	body_node.mesh = body
	body_node.material_override = body_material
	body_node.position = Vector3(0.0, height * 0.5, 0.0)
	add_child(body_node)

	# Dark foot collar.
	var base := CylinderMesh.new()
	base.top_radius = radius * 1.08
	base.bottom_radius = radius * 1.14
	base.height = BASE_HEIGHT
	base.radial_segments = RADIAL_SEGMENTS
	var base_node := MeshInstance3D.new()
	base_node.mesh = base
	base_node.material_override = base_material
	base_node.position = Vector3(0.0, BASE_HEIGHT * 0.5, 0.0)
	add_child(base_node)

	# Solid, on the "world" layer only (project.godot [layer_names]: layer_1).
	var collider := StaticBody3D.new()
	collider.collision_layer = 1
	collider.collision_mask = 0
	add_child(collider)
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height + BODY_COLLAR_OVERLAP
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position = Vector3(0.0, (height + BODY_COLLAR_OVERLAP) * 0.5 - BODY_COLLAR_OVERLAP, 0.0)
	collider.add_child(collision)

	if lying:
		# Tip the whole assembly onto its side: the body axis (local +Y) goes
		# horizontal, and the bag now rests on its curved surface, so its
		# lowest point sits one radius below the node origin — lift by that.
		rotation = Vector3(PI * 0.5, lie_yaw, 0.0)
		position.y = radius
