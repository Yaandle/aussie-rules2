class_name ControlledPlayerRing
extends Node3D

## A flat ring resting on the turf at the feet of the human-controlled
## player, so you can pick your own body out of the pack in the wide
## FULL_SIDE broadcast view (in CHASE the camera is already right behind
## them, so the mode only switches this on for FULL_SIDE).
##
## Real 3D geometry (a flat annulus mesh), not a screen-space overlay —
## user report: drawing it as a CanvasLayer polyline put it on top of
## *everything* in the viewport with no depth test, so it visibly sat over
## the player's own feet/legs from angles where they should have occluded
## it, and it kept drawing straight through the pause screen too (every
## CanvasLayer draws over the 3D viewport regardless of `layer`, so a
## screen-space ring had no way to lose to paused gameplay underneath). A
## real mesh at ground height gets normal depth testing against both the
## player's own geometry and PauseScreen's CanvasLayer (which, being a
## CanvasLayer, already draws over all 3D content unconditionally) for
## free — same instantiate-and-assign-fields pattern as KickCrosshair /
## MarkPrompt otherwise: FullGame sets `player` in _on_focus_changed and
## toggles `active` in _apply_camera_mode.

## Unchanged from the old screen-space version (user report: "increase the
## circle around the player to be larger in diameter") — big enough to pick
## out at a glance from the FULL_SIDE rig's own elevation/distance.
const RADIUS := 1.1          ## m, outer edge
const THICKNESS := 0.22      ## m, outer minus inner radius
const SEGMENTS := 40
const LIFT := 0.03           ## m off the turf, clear of z-fighting the grass

## Blue rather than the kick-aim overlay's green accent (user report: "a
## blue colour to better contrast on the green field"). SoftBrutalist.
## BUTTON_X is already this project's one blue, reused here rather than
## inventing a second.
var _colour: Color = SoftBrutalist.BUTTON_X.lightened(0.15)

## Set by whichever mode owns the human-controlled player. Null → nothing
## drawn, so this is harmless to instantiate before a player exists.
var player: PlayerController = null

## FullGame flips this with the camera mode (on for FULL_SIDE only).
var active := false

## Seconds left of a call_for_ball flash — see flash()/CALL_FLASH_DURATION.
## Shows the ring even while `active` is false (CHASE): the flash is itself
## the feedback a human player asked for ("make the blue ring under the
## player flash" — user report, placeholder ahead of a real animation), so
## it has to be visible regardless of which camera mode the ring is
## normally reserved for.
var _flash_timer := 0.0

const CALL_FLASH_DURATION := 0.6   ## s
const CALL_FLASH_HZ := 6.0         ## on/off cycles per second while flashing

var _mesh: MeshInstance3D


func _ready() -> void:
	_mesh = MeshInstance3D.new()
	_mesh.mesh = _build_ring_mesh()
	_mesh.visible = false
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = _colour
	_mesh.material_override = material
	add_child(_mesh)


## Placeholder call_for_ball feedback (see this file's header and _flash_
## timer's own comment) — a real animation can replace this later without
## anyone else's call site changing, since FullGame._call_for_ball() just
## calls this the instant the shout happens, win or lose.
func flash() -> void:
	_flash_timer = CALL_FLASH_DURATION


func _process(delta: float) -> void:
	_flash_timer = maxf(0.0, _flash_timer - delta)
	var flashing := _flash_timer > 0.0
	if not (active or flashing) or not is_instance_valid(player):
		_mesh.visible = false
		return
	global_position = player.global_position + Vector3.UP * LIFT
	# Hard on/off blink, not an alpha pulse — "flash" read literally, and
	# distinct at a glance from the ring's own steady FULL_SIDE presence.
	_mesh.visible = not flashing or int(_flash_timer * CALL_FLASH_HZ * 2.0) % 2 == 0


## A flat annulus in the XZ plane (outer RADIUS, inner RADIUS - THICKNESS)
## built once as a real mesh — the hole in the middle is actual missing
## geometry, not a texture trick, so there is nothing to see through to
## the turf except the turf itself. Double-sided via the material's
## CULL_DISABLED above rather than a second ring of back-facing triangles,
## since the ring is always meant to read the same from above or below.
func _build_ring_mesh() -> ArrayMesh:
	var inner := RADIUS - THICKNESS
	var verts := PackedVector3Array()
	var indices := PackedInt32Array()
	for i in SEGMENTS:
		var a := TAU * float(i) / float(SEGMENTS)
		verts.append(Vector3(cos(a) * RADIUS, 0.0, sin(a) * RADIUS))
		verts.append(Vector3(cos(a) * inner, 0.0, sin(a) * inner))
	for i in SEGMENTS:
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
