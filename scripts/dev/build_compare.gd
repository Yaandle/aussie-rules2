extends Node3D

## Dev-only side-by-side of character builds (not on any menu): the same
## clip at the same time on each, same camera, light and kit, saved as PNGs
## for review. Written for Build 7 against Build 6 (docs/BUILD7_MODEL.md),
## and reusable for any model swap that keeps 6thbuild's skeleton (a scanned
## mesh, say).
##
## Run it WINDOWED (headless has no renderer to read back), e.g.
##   godot --path . res://scenes/dev/build_compare.tscn
##   godot --path . res://scenes/dev/build_compare.tscn -- --models=6thbuild,7thbuild
##       --captions="BUILD 6,BUILD 7" --out=res://docs/review/7thbuild/polish/
##       --prefix=audit --shots=idle,close_front,broadcast
## It works through the shots, writes OUT/<prefix>_<shot>.png for each and
## quits. Existing files are never overwritten: a second run adds a numeric
## suffix. A model can be a CHARACTER_MODELS id or a res:// .glb path (a
## "before" copy of a model, for a three-way before/after shot).
##
## Poses come straight off each rig's imported clips through a plain
## AnimationPlayer, so they show the skin on the clip itself, without
## PlayerAnimation's lean, bank or foot lift on top. The ragdoll shots build
## the real PhysicsRagdoll on each rig (passive, the same push for both) and
## let it fall; "ragdoll_shapes" draws the physics bodies over the skin, to
## judge how well the mesh sits on them.
##
## Lighting is the match's own (broadcast_environment.tres and full_game's
## sun), so a shot reads the way the model will in a game. The two
## match-distance shots use the game's cameras: "chase" is the third-person
## rig (Tuning.CAM_DISTANCE behind CAM_FOCUS_HEIGHT, CAM_PITCH_DEFAULT,
## CAM_FOV_BASE), and "broadcast" is the full-side rig 90 m off and 20 m up
## at a mid zoom. A broadcast body is only ~40 px tall, so that shot saves the
## crop round the bodies blown up with nearest-neighbour pixels: what you see
## is exactly what the screen has, only bigger.

var left_model := "6thbuild"
var right_model := "7thbuild"
var models: Array = ["6thbuild", "7thbuild"]
var captions: Array = ["BUILD 6", "BUILD 7"]
var out_dir := "res://docs/review/7thbuild/"
var prefix := "build6_vs_build7"
var only_shots: Array = []

## [shot name, clip, time as a fraction of the clip, camera]. Camera:
## [target height, yaw, pitch, distance, fov, framing]; see _orbit_camera
## for yaw and pitch. Framing "pair" puts every body in one frame; "each"
## frames each body on its own (the others hidden) and lays the frames side
## by side, for close shots where the bodies would cover each other.
## "ragdoll*", "rest_shapes", "kits", "chase" and "broadcast" are handled
## specially.
const SHOTS := [
	["idle", "idle", 0.30, [1.05, -11.0, 4.4, 4.6, 38.0, "pair"]],
	["run", "run_fwd", 0.25, [1.05, -11.0, 4.4, 4.6, 38.0, "pair"]],
	["run_knee", "run_fwd", 0.46, [1.0, 62.0, 2.0, 2.9, 38.0, "each"]],
	["jog_knee", "jog_fwd", 0.47, [1.0, 62.0, 2.0, 2.9, 38.0, "each"]],
	["kick", "kick", 0.55, [1.05, -11.0, 4.4, 4.6, 38.0, "pair"]],
	["mark", "mark_aggressive", 0.42, [1.25, -11.0, 4.4, 5.0, 38.0, "pair"]],
	["tackle", "tackle_takedown", 0.45, [0.85, -11.0, 4.4, 4.6, 38.0, "pair"]],
	["dive", "smother_dive", 0.62, [0.75, 55.0, 8.0, 3.2, 38.0, "each"]],
	["sit", "tackled", 0.40, [0.65, 55.0, 8.0, 2.9, 38.0, "each"]],
	["close_front", "idle", 0.30, [1.70, -24.0, 2.0, 1.55, 34.0, "each"]],
	["close_back", "idle", 0.30, [1.45, 160.0, 6.0, 2.1, 38.0, "each"]],
	["close_side", "run_fwd", 0.25, [1.45, 90.0, 2.0, 2.4, 38.0, "each"]],
	["profile", "idle", 0.30, [1.07, 90.0, 0.0, 7.5, 24.0, "each"]],
	["chase", "run_fwd", 0.25, []],
	["broadcast", "run_fwd", 0.25, []],
	["ragdoll", "", 0.0, []],
	["ragdoll_shapes", "", 0.0, []],
	["rest_shapes", "", 0.0, []],
	["kits", "", 0.0, []],
]

## Same explicit kit on both bodies so only the model differs.
const KIT := {"torso": Color("#e9c95e"), "shorts": Color("#2a2c33"), "socks": Color("#e9c95e"),
	"boot": Color("#22241d"), "skin": Color("#c9925f")}

const SPACING := 0.85
const RAGDOLL_PUSH := Vector3(0.0, 0.0, 2.6)   # away from the camera
const RAGDOLL_SECONDS := 1.8

## The full-side camera's mount (Tuning.CAM_FULL_SIDE_*) at a mid zoom:
## 90 m off, 20 m up, a 32° field of view.
const BROADCAST_OFF := 90.0
const BROADCAST_UP := 20.0
const BROADCAST_FOV := 32.0
const BROADCAST_SPACING := 2.4

const ENVIRONMENT := preload("res://materials/broadcast_environment.tres")

var _rigs: Array[HumanoidRig] = []
var _players: Array[AnimationPlayer] = []
var _ragdolls: Array[PhysicsRagdoll] = []
var _labels: Array[Label] = []
var _title: Label
var _camera: Camera3D


func _ready() -> void:
	_read_args()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	_build_stage()
	_run.call_deferred()


func _read_args() -> void:
	for arg: String in OS.get_cmdline_user_args():
		var kv := arg.trim_prefix("--").split("=", true, 1)
		if kv.size() != 2:
			continue
		match kv[0]:
			"models":
				models = Array(kv[1].split(","))
			"captions":
				captions = Array(kv[1].split(","))
			"out":
				out_dir = kv[1] if kv[1].ends_with("/") else kv[1] + "/"
			"prefix":
				prefix = kv[1]
			"shots":
				only_shots = Array(kv[1].split(","))
	while captions.size() < models.size():
		captions.append(str(models[captions.size()]).get_file().get_basename().to_upper())
	left_model = models[0]
	right_model = models[-1]


func _build_stage() -> void:
	var env := WorldEnvironment.new()
	env.environment = ENVIRONMENT
	add_child(env)

	# full_game.tscn's sun, as it is there.
	var sun := DirectionalLight3D.new()
	sun.transform = Transform3D(Basis(Vector3(0.8637, 0.0, -0.5039), Vector3(-0.3627, 0.6943, -0.6216),
		Vector3(0.3499, 0.7197, 0.5998)), Vector3(0.0, 40.0, 0.0))
	sun.light_energy = 1.05
	sun.light_angular_distance = 2.2
	sun.shadow_opacity = 0.72
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 120.0
	sun.directional_shadow_blend_splits = true
	add_child(sun)

	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	floor_body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400.0, 1.0, 400.0)
	shape.shape = box
	shape.position.y = -0.5
	floor_body.add_child(shape)
	var turf := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(400.0, 400.0)
	turf.mesh = plane
	var turf_mat := StandardMaterial3D.new()
	turf_mat.albedo_color = Color("#5d8a45")
	turf_mat.roughness = 1.0
	turf.material_override = turf_mat
	floor_body.add_child(turf)
	add_child(floor_body)

	_camera = Camera3D.new()
	_camera.fov = 38.0
	_camera.far = 600.0
	add_child(_camera)
	_frame_camera(Vector3(0.0, 1.05, 0.0), 4.6)

	var ui := CanvasLayer.new()
	add_child(ui)
	_title = _label(ui, Vector2(0.0, 18.0), 30)
	_title.size = Vector2(1600.0, 40.0)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func _label(parent: Node, pos: Vector2, size: int) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color.WHITE)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 6)
	parent.add_child(l)
	return l


## The camera sits in front of the bodies (they face -Z), a little to one
## side, looking at `target`.
func _frame_camera(target: Vector3, distance: float) -> void:
	_camera.fov = 38.0
	_camera.position = target + Vector3(-0.9, 0.35, -distance)
	_camera.look_at(target, Vector3.UP)


## Orbit framing: yaw 0 is in front of the bodies (at -Z) and a positive
## yaw swings round toward +X, which is their right side once an import is
## turned to face -Z, so 90 is a right profile and 180 is from behind. Pitch
## is how far the camera looks down.
func _orbit_camera(cam: Array, around := Vector3.ZERO) -> void:
	var target := around + Vector3(0.0, cam[0], 0.0)
	var yaw := deg_to_rad(cam[1])
	var pitch := deg_to_rad(cam[2])
	var dist: float = cam[3]
	var dir := Vector3(sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))
	_camera.fov = cam[4]
	_camera.position = target + dir * dist
	_camera.look_at(target, Vector3.UP)


func _clear_bodies() -> void:
	for r in _rigs:
		r.queue_free()
	for p in _players:
		p.queue_free()
	for l in _labels:
		l.queue_free()
	_rigs.clear()
	_players.clear()
	_ragdolls.clear()
	_labels.clear()


## Bodies left to right on screen. From a camera at -Z, screen-left is +X.
func _spawn(spawn_models: Array, kits: Array, spawn_captions: Array, spacing := -1.0) -> void:
	_clear_bodies()
	var n := spawn_models.size()
	if spacing < 0.0:
		spacing = SPACING * (2.0 if n == 2 else 1.25)
	for i in n:
		var rig := HumanoidRig.new()
		rig.character_model_override = spawn_models[i]
		var kit: Dictionary = kits[i]
		if kit.has("away"):
			rig.away_kit = true
		else:
			rig.kit_torso = kit.get("torso", Color(0, 0, 0, 0))
			rig.kit_shorts = kit.get("shorts", Color(0, 0, 0, 0))
			rig.kit_socks = kit.get("socks", Color(0, 0, 0, 0))
			rig.kit_boot = kit.get("boot", Color(0, 0, 0, 0))
			rig.kit_skin = kit.get("skin", Color(0, 0, 0, 0))
		if kit.has("number") and "guernsey_number" in rig:
			rig.set("guernsey_number", kit["number"])
		rig.position = Vector3((float(n - 1) * 0.5 - i) * spacing, 0.0, 0.0)
		add_child(rig)
		_rigs.append(rig)
		var player := AnimationPlayer.new()
		add_child(player)
		player.root_node = player.get_path_to(rig)
		var lib := AnimationLibrary.new()
		for clip: String in rig.imported_animations():
			lib.add_animation(clip, rig.imported_animations()[clip])
		player.add_animation_library(&"", lib)
		_players.append(player)
		var cap := _label(_title.get_parent(), Vector2.ZERO, 24)
		cap.text = spawn_captions[i]
		_labels.append(cap)
	_place_labels(2.35)


## Captions over each body's head, as the camera now sees it; hidden when
## the body is behind the camera.
func _place_labels(height: float) -> void:
	for i in mini(_labels.size(), _rigs.size()):
		var p := _rigs[i].global_position + Vector3(0.0, height, 0.0)
		_labels[i].visible = not _camera.is_position_behind(p)
		_labels[i].position = _camera.unproject_position(p) - Vector2(_labels[i].get_minimum_size().x * 0.5, 0.0)
		_labels[i].position.y = maxf(_labels[i].position.y, 64.0)   # clear of the title


func _pose(clip: String, fraction: float) -> void:
	for p in _players:
		if not p.has_animation(clip):
			push_error("BuildCompare: no clip %s" % clip)
			continue
		var anim := p.get_animation(clip)
		p.play(clip)
		p.seek(anim.length * fraction, true)
		p.pause()


func _kits_for(n: int) -> Array:
	var out := []
	for i in n:
		out.append(KIT)
	return out


func _run() -> void:
	for shot: Array in SHOTS:
		var name: String = shot[0]
		if not only_shots.is_empty() and not only_shots.has(name):
			continue
		_frame_camera(Vector3(0.0, 1.05, 0.0), 4.6)
		match name:
			"kits":
				await _shoot_kits()
				continue
			"chase":
				await _shoot_chase()
				continue
			"broadcast":
				await _shoot_broadcast()
				continue
		_spawn(models, _kits_for(models.size()), captions)
		await get_tree().process_frame
		var what: String = shot[1]
		if name.begins_with("ragdoll"):
			await _drop(name == "ragdoll_shapes")
			what = "passive ragdoll, same push" + (", physics bodies drawn over" if name == "ragdoll_shapes" else "")
		elif name == "rest_shapes":
			# The pose every ragdoll is built in, with its bodies drawn over
			# the skin: how well each mesh sits on the physics.
			for rig in _rigs:
				var r := PhysicsRagdoll.new()
				if r.build(rig.skeleton()):
					r.build_debug_meshes()
					_ragdolls.append(r)
			what = "rest pose, ragdoll bodies drawn over"
		else:
			var cam: Array = shot[3]
			_pose(shot[1], shot[2])
			what = "%s @ %d%%" % [shot[1], roundi(shot[2] * 100.0)]
			if cam[5] == "each":
				await _shoot_each(name, what, cam)
				continue
			_orbit_camera(cam)
			_place_labels(2.35)
		_title.text = "%s  (%s)" % [name.to_upper(), what]
		await _save(name)
	print("BuildCompare: done")
	get_tree().quit()


## One frame per body, each framed the same way round its own position with
## the others hidden, cut to a strip and laid side by side. The camera's
## vertical field of view is unchanged, so every body is the same size it
## would be in a single frame.
func _shoot_each(name: String, what: String, cam: Array) -> void:
	var strips: Array[Image] = []
	_title.add_theme_font_size_override("font_size", 22 if _rigs.size() > 2 else 26)
	for i in _rigs.size():
		for j in _rigs.size():
			_rigs[j].visible = j == i
		_orbit_camera(cam, _rigs[i].global_position)
		for l in _labels:
			l.visible = false
		_title.text = "%s  %s  (%s)" % [captions[i], name.to_upper(), what]
		for _k in 4:
			await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var w := img.get_width() / _rigs.size()
		strips.append(img.get_region(Rect2i((img.get_width() - w) / 2, 0, w, img.get_height())))
	for r in _rigs:
		r.visible = true
	_title.add_theme_font_size_override("font_size", 30)
	var sheet := Image.create(strips[0].get_width() * strips.size(), strips[0].get_height(), false, strips[0].get_format())
	for i in strips.size():
		sheet.blit_rect(strips[i], Rect2i(Vector2i.ZERO, strips[i].get_size()), Vector2i(strips[0].get_width() * i, 0))
		# A thin divider between strips.
		if i > 0:
			sheet.fill_rect(Rect2i(strips[0].get_width() * i, 0, 2, sheet.get_height()), Color(1, 1, 1, 0.8))
	_write(sheet, name)


## Passive ragdoll on each body, built at rest the way a match builds it,
## the same push for both, then left to fall and settle.
func _drop(show_shapes: bool) -> void:
	for rig in _rigs:
		var r := PhysicsRagdoll.new()
		if not r.build(rig.skeleton()):
			push_error("BuildCompare: ragdoll build failed on %s" % rig.character_model_override)
			continue
		if show_shapes:
			r.build_debug_meshes()
		_ragdolls.append(r)
	for _i in 3:
		await get_tree().physics_frame
	for r in _ragdolls:
		r.start(RAGDOLL_PUSH)
	var t := 0.0
	while t < RAGDOLL_SECONDS:
		await get_tree().physics_frame
		var dt := 1.0 / float(Engine.physics_ticks_per_second)
		for r in _ragdolls:
			r.step(dt)
		t += dt
	# Look down on where they landed, close enough to read the limbs.
	var centre := Vector3.ZERO
	for r in _ragdolls:
		centre += r.body(&"Hips").global_position
	centre /= maxf(_ragdolls.size(), 1)
	_camera.position = centre + Vector3(-0.5, 1.9, -2.3) * (1.0 + 0.25 * maxf(_ragdolls.size() - 2, 0))
	_camera.look_at(centre, Vector3.UP)
	for i in mini(_labels.size(), _ragdolls.size()):
		_labels[i].position = _camera.unproject_position(_ragdolls[i].body(&"Hips").global_position + Vector3(0.0, 0.5, 0.0)) - Vector2(55.0, 0.0)


## The in-game third-person camera behind a pair running away from it.
func _shoot_chase() -> void:
	_spawn(models, _kits_for(models.size()), captions, 1.3)
	await get_tree().process_frame
	_pose("run_fwd", 0.25)
	# Behind the bodies (they face -Z, so behind is +Z), CAM_DISTANCE back
	# from the focus point at CAM_FOCUS_HEIGHT, looking down CAM_PITCH_DEFAULT.
	_orbit_camera([Tuning.CAM_FOCUS_HEIGHT, 180.0, -Tuning.CAM_PITCH_DEFAULT, Tuning.CAM_DISTANCE, Tuning.CAM_FOV_BASE])
	_place_labels(2.35)
	_title.text = "CHASE  (in-game 3rd-person camera: %.1f m back, %d° down, fov %d)" % [
		Tuning.CAM_DISTANCE, roundi(-Tuning.CAM_PITCH_DEFAULT), roundi(Tuning.CAM_FOV_BASE)]
	await _save("chase")


## Full-side broadcast distance, home and away of each model, cropped round
## the bodies and scaled up with whole pixels.
func _shoot_broadcast() -> void:
	var spawn_models := []
	var kits := []
	var caps := []
	for i in models.size():
		spawn_models.append_array([models[i], models[i]])
		kits.append_array([{}, {"away": true}])
		caps.append_array([str(captions[i]) + " H", str(captions[i]) + " A"])
	_spawn(spawn_models, kits, caps, BROADCAST_SPACING)
	await get_tree().process_frame
	_pose("run_fwd", 0.25)
	for l in _labels:
		l.visible = false
	# Seen from the side, the way a full-side camera mostly sees a pack
	# running along the ground: each body turned to run across the screen.
	for rig in _rigs:
		rig.rotation.y = PI * 0.5
	_camera.fov = BROADCAST_FOV
	_camera.position = Vector3(-BROADCAST_OFF * 0.2, BROADCAST_UP, -BROADCAST_OFF)
	_camera.look_at(Vector3(0.0, 1.0, 0.0), Vector3.UP)
	_title.visible = false
	for _i in 4:
		await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	_title.visible = true
	# unproject_position answers in the canvas's units (the project's
	# 1280x720 base size); the image is the window's real pixels.
	var to_px := Vector2(img.get_size()) / get_viewport().get_visible_rect().size
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for rig in _rigs:
		for y: float in [0.0, 2.2]:
			var s := _camera.unproject_position(rig.global_position + Vector3(0.0, y, 0.0)) * to_px
			lo = lo.min(s)
			hi = hi.max(s)
	var pad := Vector2(28.0, 18.0)
	var rect := Rect2i(Vector2i((lo - pad).floor()), Vector2i((hi - lo + pad * 2.0).ceil()))
	rect = rect.intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	var crop := img.get_region(rect)
	var k := maxi(1, mini(1560 / maxi(rect.size.x, 1), 800 / maxi(rect.size.y, 1)))
	crop.resize(rect.size.x * k, rect.size.y * k, Image.INTERPOLATE_NEAREST)
	var body_px := 0.0
	for rig in _rigs:
		body_px = maxf(body_px, ((_camera.unproject_position(rig.global_position) -
			_camera.unproject_position(rig.global_position + Vector3(0.0, 2.15, 0.0))) * to_px).length())
	print("BuildCompare: broadcast bodies are %.0f px tall on a %dx%d frame, crop x%d, left to right %s" % [
		body_px, img.get_width(), img.get_height(), k, ", ".join(caps)])
	_write(crop, "broadcast")
	_write(img, "broadcast_full")


func _shoot_kits() -> void:
	var white := {"torso": Color("#f2f2f2"), "shorts": Color("#102a6b"), "socks": Color("#102a6b"),
		"boot": Color("#f2f2f2"), "skin": Color("#6b4428"), "number": 4}
	_spawn([left_model, left_model, right_model, right_model, right_model],
		[{}, {"away": true}, {"number": 17}, {"away": true, "number": 9}, white],
		["%s HOME" % captions[0], "%s AWAY" % captions[0], "%s HOME" % captions[-1],
			"%s AWAY" % captions[-1], "%s CUSTOM" % captions[-1]], 1.15)
	_frame_camera(Vector3(0.0, 1.05, 0.0), 6.6)
	_pose("idle", 0.3)
	_place_labels(2.35)
	for l in _labels:
		l.add_theme_font_size_override("font_size", 20)
	_title.text = "KITS  (HOME = your CHARACTER kit, AWAY = TeamKit preset, CUSTOM = white / navy)"
	await _save("kits")
	# The same five from behind, for the number and the trim.
	_camera.position = Vector3(0.9, 1.6, 6.6)
	_camera.look_at(Vector3(0.0, 1.25, 0.0), Vector3.UP)
	_place_labels(2.35)
	_title.text = "KITS FROM BEHIND  (number and trim on each kit)"
	await _save("kits_back")


func _save(name: String) -> void:
	for _i in 4:
		await RenderingServer.frame_post_draw
	_write(get_viewport().get_texture().get_image(), name)


func _write(img: Image, name: String) -> void:
	var base := ProjectSettings.globalize_path(out_dir).path_join("%s_%s" % [prefix, name])
	var path := base + ".png"
	var k := 2
	while FileAccess.file_exists(path):
		path = "%s_%d.png" % [base, k]
		k += 1
	img.save_png(path)
	print("BuildCompare: wrote ", path)
