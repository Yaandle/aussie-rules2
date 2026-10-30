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

##
## Playtest 2026-10-29: "the camera preview settings still look bad". It
## rendered its own world with no sun and no WorldEnvironment (those live in
## full_game.tscn, not field.tscn), so the grass came out near-black and the
## full-side view was unreadable, and it showed field.gd's generated ground
## rather than the oval the match will use. Now it carries the match's own
## sun and broadcast_environment, follows Settings.field_style, and stands a
## few players and the ball round the centre so FULL_SIDE has something to
## frame.

const FIELD_SCENE := preload("res://scenes/field/field.tscn")
const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const BALL_SCENE := preload("res://scenes/ball/ball.tscn")
const CAMERA_SCENE := preload("res://scenes/camera/broadcast_camera.tscn")
const ENVIRONMENT := preload("res://materials/broadcast_environment.tres")
## full_game.tscn's Sun, copied (transform, energy, softness, shadow).
const SUN_TRANSFORM := Transform3D(Basis(Vector3(0.8637, 0.0, -0.5039), Vector3(-0.3627, 0.6943, -0.6216),
	Vector3(0.3499, 0.7197, 0.5998)), Vector3(0.0, 40.0, 0.0))
const SUN_ENERGY := 1.05
const SUN_ANGULAR_DISTANCE := 2.2
const SUN_SHADOW_OPACITY := 0.72
## Shorter than the match's 120 m: the preview's subject is at the centre.
const SUN_SHADOW_DISTANCE := 60.0
## The rest of the centre-bounce picture: [team, position, facing yaw deg].
const EXTRAS := [
	[Tuning.Team.AWAY, Vector3(3.0, 0.0, 0.5), -90.0],
	[Tuning.Team.HOME, Vector3(-9.0, 0.0, 6.0), 70.0],
	[Tuning.Team.AWAY, Vector3(10.0, 0.0, -5.0), -110.0],
	[Tuning.Team.HOME, Vector3(-4.0, 0.0, -14.0), 20.0],
	[Tuning.Team.AWAY, Vector3(6.0, 0.0, 15.0), -150.0],
]

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
##
## With `stretch` enabled, SubViewportContainer resizes its child
## SubViewport itself on every layout pass (container size / stretch_shrink)
## — this script must never also set `_viewport.size`. It used to, in both
## _ready() and a `resized` handler, which raced the engine's own resize
## and produced "Can't change the size of a SubViewport with a
## SubViewportContainer parent that has stretch enabled" plus a viewport
## that rendered at a stale size while the container around it had already
## grown — the washed-out/empty strip down one side of the preview that
## looked like a blank window was that mismatch, not a styling bug.
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
	add_child(_viewport)

	var world_environment := WorldEnvironment.new()
	world_environment.environment = ENVIRONMENT
	_viewport.add_child(world_environment)
	var sun := DirectionalLight3D.new()
	sun.transform = SUN_TRANSFORM
	sun.light_energy = SUN_ENERGY
	sun.light_angular_distance = SUN_ANGULAR_DISTANCE
	sun.shadow_enabled = true
	sun.shadow_opacity = SUN_SHADOW_OPACITY
	sun.directional_shadow_max_distance = SUN_SHADOW_DISTANCE
	sun.directional_shadow_blend_splits = true
	_viewport.add_child(sun)

	var field := FIELD_SCENE.instantiate() as Field
	field.follow_field_style = true
	_viewport.add_child(field)

	_dummy = _spawn(Tuning.Team.HOME, Vector3.ZERO, 0.0)
	for extra: Array in EXTRAS:
		_spawn(extra[0], extra[1], extra[2])
	var ball := BALL_SCENE.instantiate() as Ball
	_viewport.add_child(ball)
	ball.reset_at(Vector3(1.0, 0.2, -0.8))

	_camera_rig = CAMERA_SCENE.instantiate()
	_camera_rig.target = _dummy
	_camera_rig.mode = mode
	_camera_rig.zoom = zoom
	_viewport.add_child(_camera_rig)
	_camera_rig.recenter()
	_camera_rig.camera().current = true


## A standing player that never moves (base PlayerBrain), in its team's kit.
func _spawn(team: Tuning.Team, at: Vector3, yaw_deg: float) -> PlayerController:
	var player := PLAYER_SCENE.instantiate() as PlayerController
	player.team = team
	(player.get_node("Rig") as HumanoidRig).away_kit = team == Tuning.Team.AWAY
	player.position = at
	player.rotation.y = deg_to_rad(yaw_deg)
	_viewport.add_child(player)
	player.set_brain(PlayerBrain.new())
	return player
