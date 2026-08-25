class_name SkeletonWireframe
extends MeshInstance3D

## Draws a glowing line skeleton over a Skeleton3D — one segment per bone,
## from the bone's origin to its parent's. Purely a visual "this is a
## real rig" cue for the character screen preview: it makes the humanoid
## rig work legible at a glance instead of only provable by reading code.
##
## Deliberately not attached to on-field players. This project is scaling
## toward 16-a-side (see HumanoidRig's own header), and while the cost
## here is small per instance (one PRIMITIVE_LINES rebuild of ~21 short
## segments a frame, no shading, no collision), "small per instance"
## times dozens of on-field bodies every frame is exactly the kind of
## cost this project has been careful to avoid elsewhere (placeholder_rig/
## HumanoidRig's own mesh budget notes). One preview instance paying it
## is free; every player on a field paying it would not be. Attach this
## only where a human is actually looking closely at one figure.

const LINE_COLOUR := Color("#4E9F5B")   ## SoftBrutalist.ACCENT_PRIMARY
## Widened from 0.012 (design brief: "make the outer body wireframe more
## visible") — the body meshes it overlays are semi-transparent now
## (CharacterBackdrop.BODY_ALPHA), so the wireframe reads through them
## instead of only ever peeking past the silhouette edge, and a thicker
## line reads as a real rig rather than a hairline at that distance.
const LINE_WIDTH := 0.022               ## rendered as a thin quad, not a GL line —
                                         ## GL_LINES ignores width on most backends,
                                         ## a camera-facing quad per bone doesn't.

## Opt-in polish, all defaulting off so existing callers (the character
## screen) render exactly as before. The animation viewer turns them on:
##
## `on_top` draws the whole skeleton over the mesh (no depth test) instead of
## letting the body occlude the half of every bone that faces away — the
## occluded half is what reads as the wireframe "not lining up" with a limb.
## `show_joints` marks each bone origin with a small diamond so the joints
## the segments pivot around are legible. `skip_root` drops the Root->Hips
## segment, which runs from the floor up into the pelvis with no mesh behind
## it — a stray line, not a limb.
var on_top := false
var show_joints := false
var skip_root := false

## Half-size of a joint diamond, metres (only drawn when show_joints).
const JOINT_HALF := 0.018

var _skeleton: Skeleton3D
var _mesh: ImmediateMesh


func _ready() -> void:
	_mesh = ImmediateMesh.new()
	mesh = _mesh
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	material_override = _material()


## Call once after the skeleton exists (e.g. right after HumanoidRig's
## _ready()). Nothing is drawn until this is set.
func track(skeleton: Skeleton3D) -> void:
	_skeleton = skeleton


func _process(_delta: float) -> void:
	if _skeleton == null:
		return
	_rebuild()


## Rebuilds the line set from the skeleton's current global bone poses.
## Simple by design: one dot product's worth of work (a camera-facing
## billboard quad, not real cylinder geometry) per bone, no per-vertex
## skinning, no allocation beyond the two arrays ImmediateMesh needs —
## this is the "keep it cheap enough for a team" half of the brief, even
## though this node itself only ever runs on one instance at a time.
func _rebuild() -> void:
	var cam := get_viewport().get_camera_3d()
	var cam_world := cam.global_position if cam != null else global_position + Vector3.BACK

	# ImmediateMesh vertices are in THIS node's local space, then rendered
	# through its own global_transform. Joint poses below are world space, so
	# they must be pulled back into local space first — otherwise a wireframe
	# parented under a rotated node (the viewer faces the figure 180 deg at
	# the camera) gets that rotation applied a second time and renders
	# mirrored/backwards relative to the mesh, which BoneAttachment3D places
	# correctly on its own. An identity parent transform makes this a plain
	# no-op, so it stays correct however the node is parented.
	var to_local := global_transform.affine_inverse()
	var cam_pos := to_local * cam_world

	_mesh.clear_surfaces()
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	_mesh.surface_set_color(LINE_COLOUR)

	var bone_count := _skeleton.get_bone_count()
	for i in bone_count:
		var parent := _skeleton.get_bone_parent(i)
		if parent < 0:
			continue
		# The Root bone has no parent, so a segment whose parent IS Root runs
		# from the floor into the pelvis with no mesh behind it — skip it when
		# asked rather than drawing a stray line.
		if skip_root and _skeleton.get_bone_parent(parent) < 0:
			continue
		var a := to_local * (_skeleton.global_transform * _skeleton.get_bone_global_pose(parent).origin)
		var b := to_local * (_skeleton.global_transform * _skeleton.get_bone_global_pose(i).origin)
		_add_segment_quad(a, b, cam_pos)
		if show_joints:
			_add_joint_dot(b, cam_pos)

	_mesh.surface_end()


## A short camera-facing quad standing in for a "line" — GL_LINES/width
## is unsupported or ignored on several of Godot's renderers, a billboard
## quad renders identically everywhere at a trivial vertex cost (4
## verts/6 indices per bone, ~120 total).
func _add_segment_quad(a: Vector3, b: Vector3, cam_pos: Vector3) -> void:
	var along := b - a
	var length := along.length()
	if length < 0.001:
		return
	var forward := along / length
	var to_cam := (cam_pos - a).normalized()
	var side := forward.cross(to_cam).normalized()
	if side.length_squared() < 0.001:
		side = forward.cross(Vector3.UP).normalized()
	var half := side * (LINE_WIDTH * 0.5)

	var p0 := a - half
	var p1 := a + half
	var p2 := b + half
	var p3 := b - half

	_mesh.surface_add_vertex(p0)
	_mesh.surface_add_vertex(p1)
	_mesh.surface_add_vertex(p2)
	_mesh.surface_add_vertex(p0)
	_mesh.surface_add_vertex(p2)
	_mesh.surface_add_vertex(p3)


## A small camera-facing diamond at a joint, built from the same two triangles
## a quad uses so it stays in the one PRIMITIVE_TRIANGLES surface. Axes come
## off the direction to the camera so it faces the viewer at any angle.
func _add_joint_dot(p: Vector3, cam_pos: Vector3) -> void:
	var to_cam := (cam_pos - p).normalized()
	var right := to_cam.cross(Vector3.UP)
	if right.length_squared() < 0.001:
		right = to_cam.cross(Vector3.RIGHT)
	right = right.normalized() * JOINT_HALF
	var up := to_cam.cross(right).normalized() * JOINT_HALF

	var top := p + up
	var bottom := p - up
	var left := p - right
	var rightp := p + right

	_mesh.surface_add_vertex(top)
	_mesh.surface_add_vertex(rightp)
	_mesh.surface_add_vertex(bottom)
	_mesh.surface_add_vertex(top)
	_mesh.surface_add_vertex(bottom)
	_mesh.surface_add_vertex(left)


func _material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(LINE_COLOUR, 0.9)
	mat.emission_enabled = true
	mat.emission = LINE_COLOUR
	mat.emission_energy_multiplier = 1.8   ## brighter, same "more visible" ask as LINE_WIDTH above
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = on_top
	return mat
