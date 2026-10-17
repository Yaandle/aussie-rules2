class_name ControlledPlayerRing
extends CanvasLayer

## A flat ring drawn on the turf at the feet of the human-controlled
## player, so you can pick your own body out of the pack in the wide
## FULL_SIDE broadcast view (in CHASE the camera is already right behind
## them, so the mode only switches this on for FULL_SIDE).
##
## Same instantiate-and-assign-fields overlay pattern as KickCrosshair /
## MarkPrompt: FullGame sets `player` in _on_focus_changed and toggles
## `active` in _apply_camera_mode; this component only projects a world-
## space circle at that player's feet to screen space and draws it. Each
## ring vertex is unprojected individually (same as MarkPrompt's single
## badge point), so it foreshortens into a proper ground ellipse rather
## than a flat screen circle.

## Widened from 0.62 (user report: "increase the circle around the player
## to be larger in diameter") — big enough to pick out at a glance from the
## FULL_SIDE broadcast rig's own elevation/distance, not just a capsule's
## own footprint.
const RADIUS := 1.1          ## m
const SEGMENTS := 40
const THICKNESS := 3.5
const LIFT := 0.03          ## m off the turf, clear of z-fighting the grass

## Blue rather than the kick-aim overlay's green accent (user report: "a
## blue colour to better contrast on the green field" — green-on-green was
## the same low-contrast problem KickTrajectory's own colour comment
## already flags, just worse here since this ring sits flat on the turf
## itself rather than floating above it). SoftBrutalist.BUTTON_X is already
## this project's one blue, reused here rather than inventing a second.
var _colour: Color = SoftBrutalist.BUTTON_X.lightened(0.15)

## Set by whichever mode owns the human-controlled player. Null → nothing
## drawn, so this is harmless to instantiate before a player exists.
var player: PlayerController = null

## FullGame flips this with the camera mode (on for FULL_SIDE only).
var active := false

var _ring: Control


func _ready() -> void:
	# Below MarkPrompt / KickCrosshair (layer 4): a badge over the head
	# should still win over a ring on the ground if they ever overlap.
	layer = 3
	var ring := Control.new()
	ring.name = "Ring"
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ring.set_anchors_preset(Control.PRESET_FULL_RECT)
	ring.draw.connect(_draw_ring.bind(ring))
	add_child(ring)
	_ring = ring


func _process(_delta: float) -> void:
	_ring.queue_redraw()


func _draw_ring(ring: Control) -> void:
	if not active or not is_instance_valid(player):
		return
	var camera := player.camera as Camera3D
	if not is_instance_valid(camera):
		return

	var centre := player.global_position + Vector3.UP * LIFT
	var points := PackedVector2Array()
	for i in SEGMENTS + 1:
		var a := TAU * float(i) / float(SEGMENTS)
		var world := centre + Vector3(cos(a) * RADIUS, 0.0, sin(a) * RADIUS)
		if camera.is_position_behind(world):
			return   # part of the ring is behind the camera — skip it this frame
		points.append(camera.unproject_position(world))
	ring.draw_polyline(points, _colour, THICKNESS, true)
