class_name FieldScoreboard
extends Node3D

## The live score on the oval's own scoreboard (playtest 2026-10-29:
## "update in the environment if possible"). Both ovals' layouts place
## Prop_Scoreboard north of centre (assets/blender/scripts/
## build_park_props.py), whose face only had painted "HOME 88 / AWAY 88"
## digits. OvalEnvironment puts one of these on it, at the prop's own
## transform from the layout glb.
##
## The face is the HUD's ScoreboardFace drawn into a SubViewport, on a quad
## just in front of the painted panel, so the board on the ground and the
## one on screen always read the same. The viewport only redraws when the
## face changes (a score, the quarter, the clock's second), not every
## frame. Unshaded, like a lit board: it reads the same in sun or shade.

## Prop_Scoreboard's face panel: 8.0 x 3.3 m, centred 5.25 m up, its front
## 0.19 m forward of the prop's origin (Blender -Y, glTF +Z). The painted
## block digits stand out to 0.245 m, so the quad sits just past them.
const FACE_SIZE := Vector2(8.0, 3.3)
const FACE_CENTRE := Vector3(0.0, 5.25, 0.27)
## Texture resolution: ~110 px a metre is sharp from the grandstand side
## of the ground and still a small texture (880 x 363).
const PIXELS_PER_METRE := 110.0

var _viewport: SubViewport


func _ready() -> void:
	_viewport = SubViewport.new()
	_viewport.size = Vector2i((FACE_SIZE * PIXELS_PER_METRE).round())
	_viewport.disable_3d = true
	_viewport.transparent_bg = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(_viewport)

	var face := ScoreboardFace.new()
	face.draw_frame = false
	face.size = Vector2(_viewport.size)
	_viewport.add_child(face)
	face.changed.connect(_redraw)

	var mesh := QuadMesh.new()
	mesh.size = FACE_SIZE
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_texture = _viewport.get_texture()
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	var quad := MeshInstance3D.new()
	quad.name = "Face"
	quad.mesh = mesh
	quad.material_override = material
	quad.position = FACE_CENTRE
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(quad)


func _redraw() -> void:
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
