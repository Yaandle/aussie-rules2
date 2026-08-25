class_name HumanoidRig
extends Node3D

## A blocked-out 1.85m humanoid, built in code around a real Skeleton3D.
##
## Replaces PlaceholderRig. The old version hung primitive meshes off a
## tree of bare Node3D "joints" and animated those nodes directly — which
## worked for BlendSpace2D locomotion, but a Node3D hierarchy is not a
## retarget target. This version builds an actual Skeleton3D whose bone
## names and parent chain match Godot 4's built-in SkeletonProfileHumanoid
## (Root, Hips, Spine, Chest, Neck, Head, Left/RightShoulder,
## Left/RightUpperArm, Left/RightLowerArm, Left/RightHand,
## Left/RightUpperLeg, Left/RightLowerLeg, Left/RightFoot,
## Left/RightToes — the required core chain; finger/eye/jaw bones are
## optional in the profile and are skipped here as placeholder-scope) —
## so mocap glTF exports or a Mixamo-style rig, once retargeted through
## Godot's own BoneMap tooling, land on this skeleton with no renaming.
##
## The primitive meshes are unchanged in spirit from PlaceholderRig (boxes/
## capsules/spheres, same silhouette tricks — yoke, side panels, sock
## trim) but now hang off BoneAttachment3D nodes instead of driving their
## own transforms, so a single mesh set follows whatever pose the skeleton
## is in — procedural today, real mocap later — for free.
##
## HumanoidAnimations (formerly PlaceholderAnimations) writes bone tracks
## against this skeleton via the "Skeleton3D:BoneName" track-path
## convention; nothing else in this file drives animation.

const HIP_HEIGHT := 0.99
const THIGH_LENGTH := 0.44
const SHIN_LENGTH := 0.42
const UPPER_ARM_LENGTH := 0.30
const FOREARM_LENGTH := 0.27
const SHOULDER_HEIGHT := 0.40    # above Chest bone origin
const SHOULDER_WIDTH := 0.24
const HIP_WIDTH := 0.10
const NECK_HEIGHT := 0.44        # above Chest bone origin, split across Neck/Head
const SPINE_HEIGHT := 0.06       # Hips -> Spine
const CHEST_HEIGHT := 0.22       # Spine -> Chest

const COLOUR_GUERNSEY := Color("#e9c95e")
const COLOUR_GUERNSEY_AWAY := Color("#c95f55")
const COLOUR_SKIN := Color("#ecc9a0")
const COLOUR_SHORTS := Color("#2a2c33")
const COLOUR_HAIR := Color("#2c241d")
const COLOUR_BOOT := Color("#22241d")
const COLOUR_TRIM := Color("#f0ece0")
const COLOUR_TREAD := Color("#141513")

@export var away_kit := false

## Viewer-only high-fidelity switch (scripts/dev/animation_viewer.gd sets it
## before _ready). A dev screen renders one to three bodies, not 16-a-side,
## so it can afford much rounder primitives and slightly richer materials
## than the on-field budget allows. Only vertex counts and material params
## change — no extra MeshInstance3D/draw calls, the one cost the header says
## must not scale with the roster — so the on-field default stays untouched.
@export var high_detail := false

## Segment multiplier applied to every curved primitive when high_detail is
## on. Smoother silhouettes on capsules/spheres/cylinders; boxes are flat
## either way so they're left alone.
const DETAIL_SCALE := 2.4

## name, parent, rest offset from parent bone (bone-local, i.e. before the
## parent's own rotation is applied — matches Skeleton3D.set_bone_rest's
## own convention of a Transform3D relative to the parent bone). Order
## matters: parents must be added before children.
const BONES := [
	["Root", "", Vector3(0.0, 0.0, 0.0)],
	["Hips", "Root", Vector3(0.0, HIP_HEIGHT, 0.0)],
	["Spine", "Hips", Vector3(0.0, SPINE_HEIGHT, 0.0)],
	["Chest", "Spine", Vector3(0.0, CHEST_HEIGHT, 0.0)],
	["Neck", "Chest", Vector3(0.0, NECK_HEIGHT - CHEST_HEIGHT, 0.0)],
	["Head", "Neck", Vector3(0.0, 0.20, 0.0)],

	["LeftShoulder", "Chest", Vector3(0.03, SHOULDER_HEIGHT - CHEST_HEIGHT, 0.0)],
	["LeftUpperArm", "LeftShoulder", Vector3(SHOULDER_WIDTH - 0.03, 0.0, 0.0)],
	["LeftLowerArm", "LeftUpperArm", Vector3(0.0, -UPPER_ARM_LENGTH, 0.0)],
	["LeftHand", "LeftLowerArm", Vector3(0.0, -FOREARM_LENGTH, 0.0)],

	["RightShoulder", "Chest", Vector3(-0.03, SHOULDER_HEIGHT - CHEST_HEIGHT, 0.0)],
	["RightUpperArm", "RightShoulder", Vector3(-(SHOULDER_WIDTH - 0.03), 0.0, 0.0)],
	["RightLowerArm", "RightUpperArm", Vector3(0.0, -UPPER_ARM_LENGTH, 0.0)],
	["RightHand", "RightLowerArm", Vector3(0.0, -FOREARM_LENGTH, 0.0)],

	["LeftUpperLeg", "Hips", Vector3(HIP_WIDTH, -0.05, 0.0)],
	["LeftLowerLeg", "LeftUpperLeg", Vector3(0.0, -THIGH_LENGTH, 0.0)],
	["LeftFoot", "LeftLowerLeg", Vector3(0.0, -SHIN_LENGTH, 0.0)],
	["LeftToes", "LeftFoot", Vector3(0.0, -0.05, 0.12)],

	["RightUpperLeg", "Hips", Vector3(-HIP_WIDTH, -0.05, 0.0)],
	["RightLowerLeg", "RightUpperLeg", Vector3(0.0, -THIGH_LENGTH, 0.0)],
	["RightFoot", "RightLowerLeg", Vector3(0.0, -SHIN_LENGTH, 0.0)],
	["RightToes", "RightFoot", Vector3(0.0, -0.05, 0.12)],
]

var _materials := {}
var _skeleton: Skeleton3D


func _ready() -> void:
	_build()


func skeleton() -> Skeleton3D:
	return _skeleton


func _build() -> void:
	var guernsey := COLOUR_GUERNSEY_AWAY if away_kit else COLOUR_GUERNSEY

	_skeleton = Skeleton3D.new()
	_skeleton.name = "Skeleton3D"
	add_child(_skeleton)

	for entry: Array in BONES:
		var bone_name: String = entry[0]
		var parent_name: String = entry[1]
		var offset: Vector3 = entry[2]
		var idx := _skeleton.add_bone(bone_name)
		if parent_name != "":
			_skeleton.set_bone_parent(idx, _skeleton.find_bone(parent_name))
		_skeleton.set_bone_rest(idx, Transform3D(Basis.IDENTITY, offset))
		_skeleton.set_bone_pose_position(idx, offset)

	# Offsets below are relative to each bone's own rest position, which
	# for Hips/Chest/Head already lands exactly where the equivalent
	# placeholder-era joint used to sit (see the BONES table comment) — so
	# a mesh that used to be centred on its joint is centred on its bone
	# (Vector3.ZERO), and one that used to hang some distance off its
	# joint only needs that same distance minus however far the bone
	# itself moved from the old joint to get there.
	_box_on("Hips", "Pelvis", Vector3(0.23, 0.18, 0.20), Vector3.ZERO, COLOUR_SHORTS)
	_box_on("Chest", "Chest_Mesh", Vector3(0.32, 0.44, 0.22), Vector3.ZERO, guernsey)
	_box_on("Chest", "Yoke", Vector3(0.42, 0.09, 0.235), Vector3(0.0, 0.165, 0.0), COLOUR_TRIM, 0.55)
	for panel_side: int in [-1, 1]:
		_box_on("Chest", "SidePanel" + ("L" if panel_side < 0 else "R"),
			Vector3(0.045, 0.34, 0.20), Vector3(0.17 * panel_side, -0.07, 0.0), COLOUR_TRIM, 0.55)

	_sphere_on("Head", "Head_Mesh", 0.115, Vector3.ZERO, COLOUR_SKIN, 16, 10)
	var hair := _sphere_on("Head", "Hair", 0.125, Vector3(0.0, 0.035, -0.012), COLOUR_HAIR, 16, 10)
	hair.scale = Vector3(1.0, 0.85, 1.0)

	# Collar: shares the Chest attachment Chest_Mesh/Yoke/SidePanels already
	# use (see _attach()'s per-bone cache) rather than adding a whole new
	# BoneAttachment3D just for one more small mesh. Sits a touch above the
	# Yoke, at the base of the neck.
	_cylinder_on("Chest", "Collar", 0.075, 0.075, 0.035, Vector3(0.0, 0.20, 0.0), COLOUR_TRIM, 0.55)

	for side: int in [-1, 1]:
		var suffix := "L" if side < 0 else "R"
		_capsule_on("UpperArm" + suffix, "UpperArm" + suffix, 0.055, UPPER_ARM_LENGTH,
			Vector3(0.0, -UPPER_ARM_LENGTH * 0.5, 0.0), COLOUR_SKIN)
		_capsule_on("LowerArm" + suffix, "Forearm" + suffix, 0.048, FOREARM_LENGTH,
			Vector3(0.0, -FOREARM_LENGTH * 0.5, 0.0), COLOUR_SKIN)
		# A small capped end at the wrist — cheap (one more low-poly
		# sphere per arm) but the forearm capsule used to just stop dead
		# in empty air past the elbow, which read as an amputee at any
		# distance closer than broadcast.
		_sphere_on("LowerArm" + suffix, "Hand" + suffix, 0.045,
			Vector3(0.0, -FOREARM_LENGTH - 0.02, 0.0), COLOUR_SKIN)
		# A pair of bunched-finger blocks past the hand sphere, same
		# reasoning as the wrist cap above (an open palm past the wrist
		# with nothing beyond it reads as a mitt at close range) — two
		# blocks rather than five separate fingers to keep this cheap.
		# Shares the Hand sphere's own LowerArm attachment.
		for finger_x in [-0.014, 0.014]:
			_box_on("LowerArm" + suffix, "Fingers" + suffix + ("A" if finger_x < 0 else "B"),
				Vector3(0.024, 0.05, 0.03),
				Vector3(finger_x, -FOREARM_LENGTH - 0.075, 0.006), COLOUR_SKIN)

		_capsule_on("UpperLeg" + suffix, "Thigh" + suffix, 0.085, THIGH_LENGTH,
			Vector3(0.0, -THIGH_LENGTH * 0.5, 0.0), COLOUR_SKIN)
		_capsule_on("LowerLeg" + suffix, "Shin" + suffix, 0.062, SHIN_LENGTH,
			Vector3(0.0, -SHIN_LENGTH * 0.5, 0.0), COLOUR_TRIM)
		_box_on("Foot" + suffix, "Boot" + suffix, Vector3(0.10, 0.07, 0.26),
			Vector3(0.0, -0.035, -0.06), COLOUR_BOOT)
		# Tread: a wider, flush-with-the-sole slab (bottom edge lines up
		# exactly with the Boot box's own -0.07 bottom, not below it —
		# player_animation.gd's ground-clamp IK reads that exact number as
		# BOOT_GROUND_CLEARANCE, so this must not extend past it). Shares
		# the Boot's own Foot attachment.
		_box_on("Foot" + suffix, "Tread" + suffix, Vector3(0.105, 0.02, 0.27),
			Vector3(0.0, -0.06, -0.06), COLOUR_TREAD, 0.9)


# ── Construction helpers ─────────────────────────────────────────────

## Bones are named without the Left/Right prefix split for arms/legs in
## the mesh helper calls above (e.g. "UpperArm" + suffix) because the
## actual bone names carry the prefix the other way round
## (LeftUpperArm/RightUpperArm) — resolved here once so callers can stay
## terse.
func _bone_name(short: String) -> String:
	if short.ends_with("L"):
		return "Left" + short.substr(0, short.length() - 1)
	if short.ends_with("R"):
		return "Right" + short.substr(0, short.length() - 1)
	return short


## Cached per bone: several parts now deliberately share one attachment
## (Chest_Mesh/Yoke/SidePanels/Collar all sit on "Chest"; Boot/Tread on
## "Foot"+suffix; Hand/Fingers on "LowerArm"+suffix) rather than each
## getting its own BoneAttachment3D — the geometry pass below adds several
## new parts per player, and 16-a-side means that cost is paid 32 times
## over, so co-located parts reusing one attachment is what keeps node
## count from scaling with mesh count.
var _attachments := {}

func _attach(bone_short: String) -> BoneAttachment3D:
	if _attachments.has(bone_short):
		return _attachments[bone_short]
	var bone_name := _bone_name(bone_short)
	var attachment := BoneAttachment3D.new()
	attachment.name = "Attach_" + bone_name
	attachment.bone_name = bone_name
	_skeleton.add_child(attachment)
	_attachments[bone_short] = attachment
	return attachment


func _box_on(bone_short: String, part_name: String, size: Vector3, offset: Vector3,
		colour: Color, roughness := 0.78) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _mesh_on(bone_short, part_name, mesh, offset, colour, roughness)


## radial_segments/rings bumped from 10/3 — cheap per the header's own
## "primitive geometry is fine, don't multiply node/draw-call count" brief:
## more triangles on an existing mesh costs nothing extra in draw calls,
## unlike adding more MeshInstance3D nodes would.
func _capsule_on(bone_short: String, part_name: String, radius: float, length: float,
		offset: Vector3, colour: Color, roughness := 0.78) -> MeshInstance3D:
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = maxf(length, radius * 2.0 + 0.001)
	mesh.radial_segments = _segments(12)
	mesh.rings = _segments(5)
	return _mesh_on(bone_short, part_name, mesh, offset, colour, roughness)


func _sphere_on(bone_short: String, part_name: String, radius: float, offset: Vector3,
		colour: Color, radial_segments := 14, rings := 8) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = _segments(radial_segments)
	mesh.rings = _segments(rings)
	return _mesh_on(bone_short, part_name, mesh, offset, colour)


func _cylinder_on(bone_short: String, part_name: String, top_radius: float, bottom_radius: float,
		height: float, offset: Vector3, colour: Color, roughness := 0.78) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top_radius
	mesh.bottom_radius = bottom_radius
	mesh.height = height
	mesh.radial_segments = _segments(14)
	return _mesh_on(bone_short, part_name, mesh, offset, colour, roughness)


func _mesh_on(bone_short: String, part_name: String, mesh: Mesh, offset: Vector3,
		colour: Color, roughness := 0.78) -> MeshInstance3D:
	var attachment := _attach(bone_short)
	var node := MeshInstance3D.new()
	node.name = part_name
	node.mesh = mesh
	node.position = offset
	node.material_override = _material(colour, roughness)
	attachment.add_child(node)
	return node


## Curved-primitive tessellation, scaled up only when high_detail is set —
## rounded to the nearest whole segment and floored at the on-field value so
## the low-detail path is bit-for-bit unchanged.
func _segments(base: int) -> int:
	if not high_detail:
		return base
	return maxi(base, int(round(base * DETAIL_SCALE)))


func _material(colour: Color, roughness := 0.78) -> StandardMaterial3D:
	var key := "%s|%.2f|%s" % [colour, roughness, high_detail]
	if _materials.has(key):
		return _materials[key]
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.roughness = roughness
	# High detail gives the figure a little more form under the studio key
	# light: a touch less roughness for a soft sheen on skin/cloth, and a
	# faint rim so the silhouette separates from the flat-white backdrop the
	# viewer sits on. On-field bodies keep the plain matte look.
	if high_detail:
		material.roughness = clampf(roughness - 0.14, 0.2, 1.0)
		material.rim_enabled = true
		material.rim = 0.35
		material.rim_tint = 0.2
	_materials[key] = material
	return material
