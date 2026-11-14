extends Node

## Dev tool: renders high-quality 16:9 stills from exported highlight replays,
## with hand-placed "hero" cameras, for social-media covers. Nothing in the
## game uses it.
##
## The highlight exporter shoots from three fixed presets (broadcast, close,
## end) at 1920x1080. For a cover we want the camera low and close on the
## contest, lit from the sun's side, so this places its own camera per shot,
## renders at 3840x2160 with MSAA and a sharper shadow map, and lets the
## caller downsample (supersampling).
##
## Run windowed (a still needs a real renderer, not --headless):
##   Godot_console.exe --path . res://scenes/dev/highlight_stills.tscn -- --shots <shots.json> --out <dir>
##       [--size 2560x1440] [--jpg] [--field classic|oval1]
## A camera move is a run of shots with a shared name prefix, changing "t" and
## "azimuth" a little each step (see the video editor's media/ar2-intro/make_shots.py).
##
## shots.json is a list of:
##   {"name": "mark-ai-low", "replay": "<abs path>.replay", "frame": 87,
##    "target": "ball" | "body:Away #5" | "bodies:Away #5,Home #16",
##    "azimuth": 25,      # degrees around the target; 0 = the sun straight behind the camera
##    "elevation": 8,     # degrees above the target
##    "distance": 7.0, "fov": 40, "aim_up": 1.4,   # metres above the target to look at
##    "toward_frame": 123 # optional: look along (ball at this frame - target) instead of the sun
##    "dof": true}        # optional soft background (default true)
## All camera numbers are framing guesses for covers, not gameplay values.

const SIZE := Vector2i(3840, 2160)

var _out := ""


func _ready() -> void:
	var args := _args()
	if not args.has("shots") or not args.has("out"):
		push_error("usage: -- --shots <shots.json> --out <dir>")
		get_tree().quit(2)
		return
	_out = String(args.out)
	DirAccess.make_dir_recursive_absolute(_out)
	var shots: Array = JSON.parse_string(FileAccess.get_file_as_string(String(args.shots)))
	RenderingServer.directional_shadow_atlas_set_size(8192, true)
	# --field classic|oval1: which ground the stage builds (Field reads Settings in its
	# _ready). Only this run's memory is changed; settings.cfg is not saved.
	if args.has("field"):
		Settings.field_style = Settings.FieldStyle.CLASSIC if String(args.field) == "classic" \
			else Settings.FieldStyle.OVAL_1
	var size := SIZE
	if args.has("size"):
		var wh := String(args.size).split("x")
		size = Vector2i(int(wh[0]), int(wh[1]))
	var jpg := args.has("jpg")
	var stage := ReplayStage.new()
	add_child(stage)
	var vp := SubViewport.new()
	vp.size = size
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.msaa_3d = Viewport.MSAA_8X
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	var cam := Camera3D.new()
	cam.current = true
	cam.near = 0.05
	cam.far = 1500.0
	vp.add_child(cam)
	stage.add_child(vp)
	var sun: DirectionalLight3D = null
	for child in stage.get_children():
		if child is DirectionalLight3D:
			sun = child
	if sun != null:
		# covers are close-ups: spend the shadow map on the first 60 m
		sun.directional_shadow_max_distance = 60.0
	await get_tree().process_frame
	for shot: Dictionary in shots:
		var clip := ReplayClip.load_file(String(shot.replay))
		if clip == null:
			push_error("can't read %s" % shot.replay)
			continue
		stage.load_clip(clip)
		# "t" (seconds, fractional) poses between recorded frames, for slow camera moves
		var t := float(shot.t) if shot.has("t") else float(int(shot.frame)) / clip.fps()
		var f := clampi(int(round(t * clip.fps())), 0, clip.frame_count() - 1)
		stage.apply(t)
		var dec := clip.decode(f)
		var target := _target(String(shot.get("target", "ball")), clip, dec)
		var aim := target + Vector3.UP * float(shot.get("aim_up", 1.0))
		var dir := _look_dir(shot, sun, clip, target)
		var dist := float(shot.get("distance", 8.0))
		var elev := deg_to_rad(float(shot.get("elevation", 10.0)))
		cam.fov = float(shot.get("fov", 40.0))
		cam.global_position = aim - dir * dist * cos(elev) + Vector3.UP * dist * sin(elev)
		cam.global_position.y = maxf(cam.global_position.y, 0.35)
		cam.look_at(aim)
		cam.attributes = _dof(dist) if bool(shot.get("dof", true)) else null
		for i in 4:
			await RenderingServer.frame_post_draw
		var path := _out.path_join(String(shot.name) + (".jpg" if jpg else ".png"))
		if jpg:
			vp.get_texture().get_image().save_jpg(path, 0.95)
		else:
			vp.get_texture().get_image().save_png(path)
		print("still %s" % path)
	get_tree().quit()


## Horizontal direction the camera looks along. By default the sun is behind
## the camera (front-lit players), turned by `azimuth`.
func _look_dir(shot: Dictionary, sun: DirectionalLight3D, clip: ReplayClip, target: Vector3) -> Vector3:
	var d := Vector3.FORWARD
	if shot.has("toward_frame"):
		var other: Vector3 = clip.decode(clampi(int(shot.toward_frame), 0, clip.frame_count() - 1)).ball_pos
		d = Vector3(other.x - target.x, 0.0, other.z - target.z)
	elif sun != null:
		var light := -sun.global_transform.basis.z
		d = Vector3(light.x, 0.0, light.z)
	if d.length() < 0.001:
		d = Vector3.FORWARD
	d = d.normalized()
	return d.rotated(Vector3.UP, deg_to_rad(float(shot.get("azimuth", 0.0))))


func _target(spec: String, clip: ReplayClip, dec: Dictionary) -> Vector3:
	if spec.begins_with("body:") or spec.begins_with("bodies:"):
		var names := spec.split(":", true, 1)[1].split(",")
		var sum := Vector3.ZERO
		var n := 0
		for i in (clip.meta.bodies as Array).size():
			if String(clip.meta.bodies[i].get("name", "")) in names:
				sum += dec.bodies[i].pos as Vector3
				n += 1
		if n > 0:
			return sum / float(n)
		push_warning("no body named %s; aiming at the ball" % spec)
	return dec.ball_pos


func _dof(dist: float) -> CameraAttributesPractical:
	var a := CameraAttributesPractical.new()
	a.dof_blur_far_enabled = true
	a.dof_blur_far_distance = dist + 10.0
	a.dof_blur_far_transition = 25.0
	a.dof_blur_amount = 0.05
	return a


func _args() -> Dictionary:
	var out := {}
	var list := OS.get_cmdline_user_args()
	var i := 0
	while i < list.size():
		if list[i].begins_with("--") and i + 1 < list.size():
			out[list[i].substr(2)] = list[i + 1]
			i += 2
		else:
			i += 1
	return out
