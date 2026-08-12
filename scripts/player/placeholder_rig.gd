class_name PlaceholderRig
extends Node3D

## A blocked-out 1.85m humanoid, built in code.
##
## Design doc §9 says start on placeholder/stock humanoids and Mixamo
## animation and prove the physical/animation system before buying art.
## There is no art yet, so this is the placeholder: a joint hierarchy
## with box and capsule meshes hung off it, at real human proportions.
##
## The point is not the meshes. The point is that the joint hierarchy and
## the AnimationTree wired to it (player_animation.gd) are the real
## thing — a genuine BlendSpace2D driven by genuine velocity, which is
## what milestone 1 is asking to be proved. Dropping in a Mixamo
## character replaces this node and the generated clips; the blend space,
## the state machine, the parameter names and everything in
## player_controller.gd stay exactly as they are.
##
## Proportions for 1.85m — Prototype 1's CHARACTER_HEIGHT_BASELINE_CM
## was 185, so the default body is the same one.

const HIP_HEIGHT := 0.99
const THIGH_LENGTH := 0.44
const SHIN_LENGTH := 0.42
const UPPER_ARM_LENGTH := 0.30
const FOREARM_LENGTH := 0.27
const SHOULDER_HEIGHT := 0.40    # above Torso origin
const SHOULDER_WIDTH := 0.21
const HIP_WIDTH := 0.10
const NECK_HEIGHT := 0.44        # above Torso origin

## Prototype 1's palette, carried over for the player only — the guernsey
## gold and the charcoal shorts are its identity. Everything else in this
## project moves to realistic-leaning colour (§1).
const COLOUR_GUERNSEY := Color("#e9c95e")
const COLOUR_GUERNSEY_AWAY := Color("#c95f55")
const COLOUR_SKIN := Color("#ecc9a0")
const COLOUR_SHORTS := Color("#2a2c33")
const COLOUR_HAIR := Color("#2c241d")
const COLOUR_BOOT := Color("#22241d")

@export var away_kit := false

var _materials := {}


func _ready() -> void:
	_build()


func _build() -> void:
	var guernsey := COLOUR_GUERNSEY_AWAY if away_kit else COLOUR_GUERNSEY

	var hips := _joint(self, "Hips", Vector3(0.0, HIP_HEIGHT, 0.0))
	_box(hips, "Pelvis", Vector3(0.30, 0.18, 0.20), Vector3.ZERO, COLOUR_SHORTS)

	var torso := _joint(hips, "Torso", Vector3(0.0, 0.06, 0.0))
	_box(torso, "Chest", Vector3(0.36, 0.44, 0.23), Vector3(0.0, 0.22, 0.0), guernsey)

	var neck := _joint(torso, "Neck", Vector3(0.0, NECK_HEIGHT, 0.0))
	_sphere(neck, "Head", 0.115, Vector3(0.0, 0.20, 0.0), COLOUR_SKIN)
	var hair := _sphere(neck, "Hair", 0.125, Vector3(0.0, 0.235, -0.012), COLOUR_HAIR)
	hair.scale = Vector3(1.0, 0.85, 1.0)

	for side: int in [-1, 1]:
		var suffix := "L" if side < 0 else "R"
		var shoulder := _joint(torso, "Shoulder" + suffix,
			Vector3(SHOULDER_WIDTH * side, SHOULDER_HEIGHT, 0.0))
		_capsule(shoulder, "UpperArm" + suffix, 0.055, UPPER_ARM_LENGTH,
			Vector3(0.0, -UPPER_ARM_LENGTH * 0.5, 0.0), COLOUR_SKIN)
		var elbow := _joint(shoulder, "Elbow" + suffix,
			Vector3(0.0, -UPPER_ARM_LENGTH, 0.0))
		_capsule(elbow, "Forearm" + suffix, 0.048, FOREARM_LENGTH,
			Vector3(0.0, -FOREARM_LENGTH * 0.5, 0.0), COLOUR_SKIN)

		var hip := _joint(hips, "Hip" + suffix,
			Vector3(HIP_WIDTH * side, -0.05, 0.0))
		_capsule(hip, "Thigh" + suffix, 0.085, THIGH_LENGTH,
			Vector3(0.0, -THIGH_LENGTH * 0.5, 0.0), COLOUR_SKIN)
		var knee := _joint(hip, "Knee" + suffix, Vector3(0.0, -THIGH_LENGTH, 0.0))
		_capsule(knee, "Shin" + suffix, 0.062, SHIN_LENGTH,
			Vector3(0.0, -SHIN_LENGTH * 0.5, 0.0), COLOUR_SKIN)
		var ankle := _joint(knee, "Ankle" + suffix, Vector3(0.0, -SHIN_LENGTH, 0.0))
		_box(ankle, "Boot" + suffix, Vector3(0.10, 0.07, 0.26),
			Vector3(0.0, -0.035, -0.06), COLOUR_BOOT)


# ── Construction helpers ─────────────────────────────────────────────

func _joint(parent: Node3D, joint_name: String, offset: Vector3) -> Node3D:
	var node := Node3D.new()
	node.name = joint_name
	node.position = offset
	parent.add_child(node)
	return node


func _mesh_node(parent: Node3D, part_name: String, mesh: Mesh, offset: Vector3,
		colour: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = part_name
	node.mesh = mesh
	node.position = offset
	node.material_override = _material(colour)
	parent.add_child(node)
	return node


func _box(parent: Node3D, part_name: String, size: Vector3, offset: Vector3,
		colour: Color) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _mesh_node(parent, part_name, mesh, offset, colour)


func _capsule(parent: Node3D, part_name: String, radius: float, length: float,
		offset: Vector3, colour: Color) -> MeshInstance3D:
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = maxf(length, radius * 2.0 + 0.001)
	mesh.radial_segments = 10
	mesh.rings = 3
	return _mesh_node(parent, part_name, mesh, offset, colour)


func _sphere(parent: Node3D, part_name: String, radius: float, offset: Vector3,
		colour: Color) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 14
	mesh.rings = 8
	return _mesh_node(parent, part_name, mesh, offset, colour)


func _material(colour: Color) -> StandardMaterial3D:
	if _materials.has(colour):
		return _materials[colour]
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.roughness = 0.78
	_materials[colour] = material
	return material
