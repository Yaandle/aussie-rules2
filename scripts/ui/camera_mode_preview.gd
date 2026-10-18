class_name CameraModePreview
extends SubViewportContainer

## Live render of a BroadcastCamera mode (CHASE "3RD PERSON" / FULL_SIDE)
## for the Full Game / Career pregame screens' CAMERA preview — replaces
## the old static fullside.png/3rdperson.png screenshots those screens
## used to show (user ask: "update from the screenshot to a live
## rendering of the field... I should then be able to adjust values and
## see it update").
##
## The scene it renders is MenuBackdrop's own recipe, reused rather than
## invented fresh: a real Field, one standing-still player (base
## PlayerBrain, never told to move — exactly the frozen subject a settings
## preview needs), and a real BroadcastCamera targeting them. Shared
## between both pregame screens rather than duplicated, the same
## instantiate-and-assign-fields pattern as KickCrosshair/MarkPrompt/
## ControlledPlayerRing — this is a real field+player+camera scene, not a
## few lines worth copying twice the way the screenshot-era private
## _CameraPreviewField class in each screen used to be.

const FIELD_SCENE := preload("res://scenes/field/field.tscn")
const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const CAMERA_SCENE := preload("res://scenes/camera/broadcast_camera.tscn")

## CHASE ("3RD PERSON") or FULL_SIDE — which mode this preview renders.
## Settable at any time; BroadcastCamera.set_mode() re-centres itself.
var mode: BroadcastCamera.Mode = BroadcastCamera.Mode.CHASE:
	set(value):
		mode = value
		if is_instance_valid(_camera_rig):
			_camera_rig.set_mode(value)

## Settings.camera_zoom's own multiplier — see BroadcastCamera.zoom.
var zoom := Tuning.CAM_ZOOM_DEFAULT:
	set(value):
		zoom = value
		if is_instance_valid(_camera_rig):
			_camera_rig.zoom = value

## Renders at 1/this resolution and lets `stretch` upscale the texture back
## up to the container's actual display size — a small decorative preview
## has no business paying full-resolution 3D render cost (user ask:
## "scale the resolution... make it a little smaller").
const RENDER_SHRINK := 2

var _viewport: SubViewport
var _camera_rig: BroadcastCamera
var _dummy: PlayerController


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	stretch = true
	stretch_shrink = RENDER_SHRINK

	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.transparent_bg = false
	_viewport.size = _container_size()
	add_child(_viewport)

	_viewport.add_child(FIELD_SCENE.instantiate())

	_dummy = PLAYER_SCENE.instantiate()
	_dummy.team = Tuning.Team.HOME
	(_dummy.get_node("Rig") as HumanoidRig).away_kit = false
	_dummy.position = Vector3.ZERO
	_viewport.add_child(_dummy)
	_dummy.set_brain(PlayerBrain.new())

	_camera_rig = CAMERA_SCENE.instantiate()
	_camera_rig.target = _dummy
	_camera_rig.mode = mode
	_camera_rig.zoom = zoom
	_viewport.add_child(_camera_rig)
	_camera_rig.recenter()
	_camera_rig.camera().current = true

	resized.connect(_on_resized)


func _on_resized() -> void:
	if is_instance_valid(_viewport):
		_viewport.size = _container_size()


func _container_size() -> Vector2i:
	return Vector2i(maxi(int(size.x) / RENDER_SHRINK, 1), maxi(int(size.y) / RENDER_SHRINK, 1))
