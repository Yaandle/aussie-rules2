extends Node3D

## Dev-only render-cost probe for a player model (not on any menu). Two
## modes, both run WINDOWED (headless doesn't render, so it can't measure
## what a model costs to draw):
##
##   stress: COUNT bodies of one model in a grid, each running its own
##           phase of run_fwd through a plain AnimationPlayer, under the
##           match's sun and environment, all in view of one fixed camera.
##           Isolates the model: skinning, draws and shadow draws.
##   match:  a real quick-play Full Game (full_game.tscn, 36 players) with
##           CharacterProfile.model_id set in memory only (nothing saved),
##           for SECONDS of AI play: the cost in the game as it is.
##
##   godot --path . res://scenes/dev/model_cost.tscn -- --model=7thbuild --mode=stress --count=36
##   godot --path . res://scenes/dev/model_cost.tscn -- --model=6thbuild --mode=match --seconds=20
##
## V-sync is switched off for the run so frames aren't capped. It prints one
## COST line: frame time (ms, mean / median / 95th percentile), the GPU's
## own render time for the viewport (RenderingServer's measured time), draw
## calls, primitives and objects per frame. Compare models on the same
## machine, mode and count; the numbers are this GPU's, not a budget.

const ENVIRONMENT := preload("res://materials/broadcast_environment.tres")
const FULL_GAME := "res://scenes/modes/full_game.tscn"

var model := "7thbuild"
var mode := "stress"
var count := 36
var seconds := 12.0
var warmup := 3.0

var _frames: Array[float] = []
var _gpu: Array[float] = []
var _cpu: Array[float] = []
var _draws: Array[float] = []
var _prims: Array[float] = []
var _objects: Array[float] = []
var _t := 0.0
var _measuring := false


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		var kv := arg.trim_prefix("--").split("=", true, 1)
		if kv.size() != 2:
			continue
		match kv[0]:
			"model": model = kv[1]
			"mode": mode = kv[1]
			"count": count = int(kv[1])
			"seconds": seconds = float(kv[1])
			"warmup": warmup = float(kv[1])
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	if mode == "match":
		_start_match.call_deferred()
	else:
		_build_stress()
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)


## Moves this probe up beside the match so it outlives the scene change,
## then loads the match with the model chosen in memory.
func _start_match() -> void:
	CharacterProfile.model_id = model
	var root := get_tree().root
	get_parent().remove_child(self)
	root.add_child(self)
	get_tree().change_scene_to_file(FULL_GAME)


func _build_stress() -> void:
	CharacterProfile.model_id = model
	var env := WorldEnvironment.new()
	env.environment = ENVIRONMENT
	add_child(env)
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
	var turf := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(200.0, 200.0)
	turf.mesh = plane
	var turf_mat := StandardMaterial3D.new()
	turf_mat.albedo_color = Color("#5d8a45")
	turf.material_override = turf_mat
	add_child(turf)

	var side := ceili(sqrt(float(count)))
	for i in count:
		var rig := HumanoidRig.new()
		rig.character_model_override = model
		rig.away_kit = i % 2 == 1
		rig.position = Vector3((i % side - (side - 1) * 0.5) * 2.4, 0.0, (i / side) * 2.4)
		add_child(rig)
		var player := AnimationPlayer.new()
		add_child(player)
		player.root_node = player.get_path_to(rig)
		var lib := AnimationLibrary.new()
		for clip: String in rig.imported_animations():
			var anim: Animation = rig.imported_animations()[clip].duplicate()
			anim.loop_mode = Animation.LOOP_LINEAR
			lib.add_animation(clip, anim)
		player.add_animation_library(&"", lib)
		if player.has_animation(&"run_fwd"):
			player.play(&"run_fwd")
			player.seek(fmod(i * 0.137, player.get_animation(&"run_fwd").length), true)
	var cam := Camera3D.new()
	cam.fov = Tuning.CAM_FOV_BASE
	cam.far = 400.0
	add_child(cam)
	var depth := (side - 1) * 2.4
	cam.position = Vector3(0.0, 9.0, -14.0)
	cam.look_at(Vector3(0.0, 0.5, depth * 0.45), Vector3.UP)


func _process(delta: float) -> void:
	_t += delta
	if not _measuring:
		if _t >= warmup:
			_measuring = true
			_t = 0.0
		return
	var vp := get_viewport().get_viewport_rid()
	_frames.append(delta * 1000.0)
	_gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(vp))
	_cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(vp))
	_draws.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	_prims.append(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	_objects.append(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
	if _t >= seconds:
		_report()
		get_tree().quit()


func _report() -> void:
	print("COST model=%s mode=%s count=%s frames=%d | frame ms %s | gpu ms %s | render cpu ms %s | draws %s | prims %s | objects %s" % [
		model, mode, str(count) if mode == "stress" else "36 (match)", _frames.size(),
		_stats(_frames), _stats(_gpu), _stats(_cpu), _stats(_draws, true), _stats(_prims, true), _stats(_objects, true)])


func _stats(values: Array[float], whole := false) -> String:
	if values.is_empty():
		return "-"
	var sorted := values.duplicate()
	sorted.sort()
	var mean := 0.0
	for v in sorted:
		mean += v
	mean /= sorted.size()
	var med: float = sorted[sorted.size() / 2]
	var p95: float = sorted[mini(sorted.size() - 1, int(sorted.size() * 0.95))]
	if whole:
		return "%d / %d / %d" % [roundi(mean), roundi(med), roundi(p95)]
	return "%.2f / %.2f / %.2f" % [mean, med, p95]
