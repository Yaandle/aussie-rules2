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
const LINE_WIDTH := 0.012               ## rendered as a thin quad, not a GL line —
                                         ## GL_LINES ignores width on most backends,
                                         ## a camera-facing quad per bone doesn't.

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
	var cam_pos := cam.global_position if cam != null else global_position + Vector3.BACK

	_mesh.clear_surfaces()
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	_mesh.surface_set_color(LINE_COLOUR)

	var bone_count := _skeleton.get_bone_count()
	for i in bone_count:
		var parent := _skeleton.get_bone_parent(i)
		if parent < 0:
			continue
		var a := _skeleton.global_transform * _skeleton.get_bone_global_pose(parent).origin
		var b := _skeleton.global_transform * _skeleton.get_bone_global_pose(i).origin
		_add_segment_quad(a, b, cam_pos)

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


func _material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(LINE_COLOUR, 0.9)
	mat.emission_enabled = true
	mat.emission = LINE_COLOUR
	mat.emission_energy_multiplier = 1.4
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = false
	return mat
