extends Node3D

## Dev-only (not on any menu): renders one character model the way the Build
## 8 reference image (docs/review/8thbuild/reference.webp) shows its player,
## so the two can be compared frame for frame. Same kit (a black guernsey
## with a red sash, black shorts, black socks with a red band, black boots),
## a light tan skin, dark hair, a warm low sun from the camera's left, and a
## front-on full-body camera at chest height. Also a close-up, a profile, a
## three-quarter and a back view.
##
## Run it WINDOWED (headless has no renderer to read back):
##   godot --path . res://scenes/dev/reference_match.tscn
##   godot --path . res://scenes/dev/reference_match.tscn -- --model=8thbuild
##       --out=res://docs/review/8thbuild/ --prefix=ref --clip=idle --at=0.3
## Writes OUT/<prefix>_<shot>.png, overwriting, and quits.

var model := "8thbuild"
var out_dir := "res://docs/review/8thbuild/"
var prefix := "ref"
var clip := "idle"
var at := 0.3

## The reference's kit, read off the image.
const KIT_JERSEY := Color("#131417")
const KIT_ACCENT := Color("#b8191f")
const KIT_SKIN := Color("#a8714c")
const KIT_HAIR := Color("#221813")

## [name, camera position, look-at target, fov]. The body stands at the
## origin facing -Z.
const SHOTS := [
	["front", Vector3(0.0, 1.30, -5.2), Vector3(0.0, 1.06, 0.0), 30.0],
	["close", Vector3(0.0, 1.62, -2.0), Vector3(0.0, 1.62, 0.0), 30.0],
	["face", Vector3(0.0, 1.98, -1.0), Vector3(0.0, 1.98, 0.0), 26.0],
	["three_quarter", Vector3(-3.4, 1.30, -3.9), Vector3(0.0, 1.06, 0.0), 30.0],
	["side", Vector3(-5.2, 1.30, 0.0), Vector3(0.0, 1.06, 0.0), 30.0],
	["back", Vector3(0.0, 1.30, 5.2), Vector3(0.0, 1.06, 0.0), 30.0],
	["head_back", Vector3(0.6, 2.05, 1.0), Vector3(0.0, 2.0, 0.0), 30.0],
]

var _camera: Camera3D
var _player: AnimationPlayer


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		var kv := arg.trim_prefix("--").split("=", true, 1)
		if kv.size() != 2:
			continue
		match kv[0]:
			"model": model = kv[1]
			"out": out_dir = kv[1] if kv[1].ends_with("/") else kv[1] + "/"
			"prefix": prefix = kv[1]
			"clip": clip = kv[1]
			"at": at = float(kv[1])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	_build_stage()
	_run.call_deferred()


func _build_stage() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("#6f9fcf")
	sky_mat.sky_horizon_color = Color("#d9e2e6")
	sky_mat.ground_horizon_color = Color("#9fae84")
	sky_mat.ground_bottom_color = Color("#3c5a2c")
	sky.sky_material = sky_mat
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.9
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	add_child(env)

	# Late-afternoon sun, low and warm, from in front and to the camera's
	# left, as in the reference.
	var sun := DirectionalLight3D.new()
	sun.light_color = Color("#ffe0b8")
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	add_child(sun)
	sun.look_at_from_position(Vector3(-3.0, 2.2, -4.0), Vector3.ZERO, Vector3.UP)

	var turf := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(200.0, 200.0)
	turf.mesh = plane
	var turf_mat := StandardMaterial3D.new()
	turf_mat.albedo_color = Color("#4f7a37")
	turf_mat.roughness = 1.0
	turf.material_override = turf_mat
	add_child(turf)

	var rig := HumanoidRig.new()
	rig.character_model_override = model
	rig.kit_torso = KIT_JERSEY
	rig.kit_shorts = KIT_JERSEY
	rig.kit_socks = KIT_JERSEY
	rig.kit_boot = KIT_JERSEY
	rig.kit_skin = KIT_SKIN
	if "kit_accent" in rig:
		rig.set("kit_accent", KIT_ACCENT)
	if "kit_hair" in rig:
		rig.set("kit_hair", KIT_HAIR)
	add_child(rig)
	_player = AnimationPlayer.new()
	add_child(_player)
	_player.root_node = _player.get_path_to(rig)
	var lib := AnimationLibrary.new()
	for c: String in rig.imported_animations():
		lib.add_animation(c, rig.imported_animations()[c])
	_player.add_animation_library(&"", lib)

	_camera = Camera3D.new()
	add_child(_camera)


func _run() -> void:
	if _player.has_animation(clip):
		_player.play(clip)
		_player.seek(_player.get_animation(clip).length * at, true)
		_player.pause()
	else:
		push_error("ReferenceMatch: no clip %s" % clip)
	for shot: Array in SHOTS:
		_camera.fov = shot[3]
		_camera.look_at_from_position(shot[1], shot[2], Vector3.UP)
		for _i in 4:
			await RenderingServer.frame_post_draw
		var path := ProjectSettings.globalize_path(out_dir).path_join("%s_%s.png" % [prefix, shot[0]])
		get_viewport().get_texture().get_image().save_png(path)
		print("ReferenceMatch: wrote ", path)
	get_tree().quit()
