extends Node3D

## Dev-only side-by-side of two character builds (not on any menu): the same
## clip at the same time on each, same camera, light and kit, saved as PNGs
## for review. Written for Build 7 against Build 6 (docs/BUILD7_MODEL.md),
## and reusable for any model swap that keeps 6thbuild's skeleton (a scanned
## mesh, say): change LEFT_MODEL / RIGHT_MODEL and OUT_DIR.
##
## Run it WINDOWED (headless has no renderer to read back), e.g.
##   godot --path . res://scenes/dev/build_compare.tscn
## It works through SHOTS, writes OUT_DIR/<prefix>_<shot>.png for each and
## quits. Existing files are never overwritten: a second run adds a
## numeric suffix.
##
## Poses come straight off each rig's imported clips through a plain
## AnimationPlayer, so they show the skin on the clip itself, without
## PlayerAnimation's lean, bank or foot lift on top. The ragdoll shots build
## the real PhysicsRagdoll on each rig (passive, the same push for both) and
## let it fall; "ragdoll_shapes" draws the physics bodies over the skin, to
## judge how well the mesh sits on them.

const LEFT_MODEL := "6thbuild"
const RIGHT_MODEL := "7thbuild"
const OUT_DIR := "res://docs/review/7thbuild/"
const PREFIX := "build6_vs_build7"

## [shot name, clip, time as a fraction of the clip]. "ragdoll*" and
## "kits" are handled specially.
const SHOTS := [
	["idle", "idle", 0.30],
	["run", "run_fwd", 0.25],
	["kick", "kick", 0.55],
	["mark", "mark_aggressive", 0.42],
	["tackle", "tackle_takedown", 0.45],
	["ragdoll", "", 0.0],
	["ragdoll_shapes", "", 0.0],
	["rest_shapes", "", 0.0],
	["kits", "", 0.0],
]

## Same explicit kit on both bodies so only the model differs.
const KIT := {"torso": Color("#e9c95e"), "shorts": Color("#2a2c33"), "socks": Color("#e9c95e"),
	"boot": Color("#22241d"), "skin": Color("#c9925f")}

const SPACING := 0.85
const RAGDOLL_PUSH := Vector3(0.0, 0.0, 2.6)   # away from the camera
const RAGDOLL_SECONDS := 1.8

var _rigs: Array[HumanoidRig] = []
var _players: Array[AnimationPlayer] = []
var _ragdolls: Array[PhysicsRagdoll] = []
var _labels: Array[Label] = []
var _title: Label
var _camera: Camera3D


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_build_stage()
	_run.call_deferred()


func _build_stage() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("#9fb6c9")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("#d8e2ea")
	e.ambient_light_energy = 0.55
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48.0, 150.0, 0.0)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	add_child(sun)

	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	floor_body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40.0, 1.0, 40.0)
	shape.shape = box
	shape.position.y = -0.5
	floor_body.add_child(shape)
	var turf := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40.0, 40.0)
	turf.mesh = plane
	var turf_mat := StandardMaterial3D.new()
	turf_mat.albedo_color = Color("#5d8a45")
	turf_mat.roughness = 1.0
	turf.material_override = turf_mat
	floor_body.add_child(turf)
	add_child(floor_body)

	_camera = Camera3D.new()
	_camera.fov = 38.0
	add_child(_camera)
	_frame_camera(Vector3(0.0, 1.05, 0.0), 4.6)

	var ui := CanvasLayer.new()
	add_child(ui)
	_title = _label(ui, Vector2(0.0, 18.0), 30)
	_title.size = Vector2(1280.0, 40.0)
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
	_camera.position = target + Vector3(-0.9, 0.35, -distance)
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
func _spawn(models: Array, kits: Array, captions: Array) -> void:
	_clear_bodies()
	var n := models.size()
	for i in n:
		var rig := HumanoidRig.new()
		rig.character_model_override = models[i]
		var kit: Dictionary = kits[i]
		if kit.has("away"):
			rig.away_kit = true
		else:
			rig.kit_torso = kit.get("torso", Color(0, 0, 0, 0))
			rig.kit_shorts = kit.get("shorts", Color(0, 0, 0, 0))
			rig.kit_socks = kit.get("socks", Color(0, 0, 0, 0))
			rig.kit_boot = kit.get("boot", Color(0, 0, 0, 0))
			rig.kit_skin = kit.get("skin", Color(0, 0, 0, 0))
		rig.position = Vector3((float(n - 1) * 0.5 - i) * SPACING * (2.0 if n == 2 else 1.0), 0.0, 0.0)
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
		var screen := _camera.unproject_position(rig.position + Vector3(0.0, 2.35, 0.0))
		var cap := _label(_title.get_parent(), screen - Vector2(70.0, 0.0), 24)
		cap.text = captions[i]
		_labels.append(cap)


func _pose(clip: String, fraction: float) -> void:
	for p in _players:
		if not p.has_animation(clip):
			push_error("BuildCompare: no clip %s" % clip)
			continue
		var anim := p.get_animation(clip)
		p.play(clip)
		p.seek(anim.length * fraction, true)
		p.pause()


func _run() -> void:
	for shot: Array in SHOTS:
		var name: String = shot[0]
		_frame_camera(Vector3(0.0, 1.05, 0.0), 4.6)
		if name == "kits":
			await _shoot_kits()
			continue
		_spawn([LEFT_MODEL, RIGHT_MODEL], [KIT, KIT], ["BUILD 6", "BUILD 7"])
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
			_pose(shot[1], shot[2])
		_title.text = "%s  (%s)" % [name.to_upper(), what]
		await _save(name)
	print("BuildCompare: done")
	get_tree().quit()


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
	_camera.position = centre + Vector3(-0.5, 1.9, -2.3)
	_camera.look_at(centre, Vector3.UP)
	for i in mini(_labels.size(), _ragdolls.size()):
		_labels[i].position = _camera.unproject_position(_ragdolls[i].body(&"Hips").global_position + Vector3(0.0, 0.5, 0.0)) - Vector2(55.0, 0.0)


func _shoot_kits() -> void:
	var white := {"torso": Color("#f2f2f2"), "shorts": Color("#102a6b"), "socks": Color("#102a6b"),
		"boot": Color("#f2f2f2"), "skin": Color("#6b4428")}
	_spawn([LEFT_MODEL, LEFT_MODEL, RIGHT_MODEL, RIGHT_MODEL, RIGHT_MODEL],
		[{}, {"away": true}, {}, {"away": true}, white],
		["B6 HOME", "B6 AWAY", "B7 HOME", "B7 AWAY", "B7 CUSTOM"])
	_frame_camera(Vector3(0.0, 1.05, 0.0), 6.2)
	for i in _labels.size():
		_labels[i].position = _camera.unproject_position(_rigs[i].position + Vector3(0.0, 2.35, 0.0)) - Vector2(55.0, 0.0)
		_labels[i].add_theme_font_size_override("font_size", 20)
	_pose("idle", 0.3)
	_title.text = "KITS  (HOME = your CHARACTER kit, AWAY = TeamKit preset, CUSTOM = white / navy)"
	await _save("kits")


func _save(name: String) -> void:
	for _i in 4:
		await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var base := ProjectSettings.globalize_path(OUT_DIR).path_join("%s_%s" % [PREFIX, name])
	var path := base + ".png"
	var k := 2
	while FileAccess.file_exists(path):
		path = "%s_%d.png" % [base, k]
		k += 1
	img.save_png(path)
	print("BuildCompare: wrote ", path)
