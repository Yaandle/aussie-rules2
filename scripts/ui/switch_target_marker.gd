class_name SwitchTargetMarker
extends Node3D

## A small ring on the turf under the HOME player a press of the switch
## button would hand control to (pre-Day-5 W3, FIFA's "next player"
## marker). FullGame sets `player` every physics tick from
## FullGame._switch_preview(); null hides it. Built like ControlledPlayerRing
## (a real mesh with depth testing, not a CanvasLayer overlay, for the same
## reasons that file's header gives), but smaller, thinner and dashed, in
## white at part alpha, so it never reads as the controlled player's own ring.

const RADIUS := 0.7          ## m, outer edge
const THICKNESS := 0.09      ## m
const SEGMENTS := 32
const DASH_ON := 2
const DASH_GAP := 2
const LIFT := 0.035          ## m, just above ControlledPlayerRing's LIFT
const COLOUR := Color(1.0, 1.0, 1.0, 0.7)

var player: PlayerController = null

var _mesh: MeshInstance3D


func _ready() -> void:
	_mesh = MeshInstance3D.new()
	_mesh.mesh = _build_mesh()
	_mesh.visible = false
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = COLOUR
	_mesh.material_override = material
	add_child(_mesh)


func _process(_delta: float) -> void:
	if not is_instance_valid(player):
		_mesh.visible = false
		return
	_mesh.visible = true
	global_position = player.global_position + Vector3.UP * LIFT


func _build_mesh() -> ArrayMesh:
	var inner := RADIUS - THICKNESS
	var verts := PackedVector3Array()
	var indices := PackedInt32Array()
	for i in SEGMENTS:
		var a := TAU * float(i) / float(SEGMENTS)
		verts.append(Vector3(cos(a) * RADIUS, 0.0, sin(a) * RADIUS))
		verts.append(Vector3(cos(a) * inner, 0.0, sin(a) * inner))
	for i in SEGMENTS:
		if i % (DASH_ON + DASH_GAP) >= DASH_ON:
			continue
		var o0 := i * 2
		var i0 := i * 2 + 1
		var o1 := ((i + 1) % SEGMENTS) * 2
		var i1 := ((i + 1) % SEGMENTS) * 2 + 1
		indices.append_array([o0, o1, i0, i0, o1, i1])
	var surface := Array()
	surface.resize(Mesh.ARRAY_MAX)
	surface[Mesh.ARRAY_VERTEX] = verts
	surface[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surface)
	return mesh
