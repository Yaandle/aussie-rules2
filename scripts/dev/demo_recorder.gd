extends Node

## Records the README's feature demos (marking, tackling, ruck, kicking) on a
## real ground under the match's sun. Dev-only, and only useful under Godot's
## movie writer. Each demo runs through the real gameplay code on real
## players: the animation viewer's own MARK DELIVERY and CONTESTS where they
## exist, and for the ruck, the kick and the set shot a short staging of the
## same calls a match makes. Nothing here decides an outcome; it only presses
## buttons and moves the camera.
##
## One demo per run, picked by the user arg `demo=` (marking, tackling, ruck
## or kicking). `field=bush` or `field=park` picks the ground (default: bush
## for marking and tackling, park for the ruck and the kick). Each run writes
## PNG frames into its own folder, named after the demo, plus a captions.json
## beside them; tools/make_demo_gifs.py turns those folders into
## docs/media/<demo>.gif (captioned) and docs/media/video/<demo>.mp4 (clean):
##
##   Godot_console.exe --path . --write-movie <frames>/tackling/f.png
##       --fixed-fps 30 --scene res://scenes/dev/demo_recorder.tscn
##       -- demo=tackling
##   python tools/make_demo_gifs.py <frames> docs/media
##
## Frames come out at the project's 1600x900 window size; `--resolution`
## doesn't override that. The frame is clean: the viewer's menus are hidden
## and the only HUD is the mark badge and timing ring in the marking demo.
## Captions aren't drawn here. They go to captions.json with their times, and
## the GIF tool draws them, so one recording gives the captioned GIF and the
## clean video. Every take starts at LEAD_IN; the tool drops the frames
## before it, so a video's first frame is the first take's first frame.
##
## The run prints what each take really did (who marked, how each tackle
## resolved, which ruckman connected, where the set shot crossed the line),
## and quits when the demo's timeline ends.
##
## The ground: the viewer's studio (white cove, grid, fill light) is hidden
## and a Field is added under the viewer's players with
## `follow_field_style`, lit by full_game.tscn's Sun and the broadcast
## environment, the same way ReplayStage lights a replay. `Settings.
## field_style` and the mark-timing assist are set in memory only, never
## saved. Contests happen in the centre circle.
##
## Staging the viewer can't do on its own (all of it through the real code):
## * Its SEQUENCES buttons (bounce on the run, mark retreat, umpire ball-up)
##   have been stubs since 2026-10-08, so the ruck stages its own ball-up:
##   FullGame._begin_ruck_contest's nomination, throw-up and release, with
##   the ground's own field umpire. A third player, a HOME runner, waits on
##   the side the first tap is aimed at and runs onto the ball once it's
##   tapped; the recorder steers them at the ball and the real gather picks
##   it up.
## * Its contest brains aren't HumanBrains, and a Slide only steps in and
##   holds on a held button, so the sling uses DemoBrain.
## * The fend-off: the carrier is put on a DemoBrain that taps RB as the
##   tackler closes. The run-in speeds and the bearing are picked so the wrap
##   is one a fend can break (Tuning's "Fend-off"); TackleBalance and
##   fend_impact still decide it, and the run prints b and the result.
## * The contested mark: the opponent at the marker's shoulder is put on a
##   DemoBrain holding the Safe mark, so both players are in the contest and
##   MarkContest picks who takes it.
## * The set shot: a kick is delivered to a player holding the Safe mark 36 m
##   from goal (Ball.launch as a kick disposal, on the velocity the viewer's
##   MARK DELIVERY solves for). The mark, the walk back, the line-up (Y), the
##   run-up and the kick are the real ones.

const ViewerScene := preload("res://scenes/dev/animation_viewer.tscn")
const FieldScene := preload("res://scenes/field/field.tscn")
const PlayerScene := preload("res://scenes/player/player.tscn")
const MatchEnvironment := preload("res://materials/broadcast_environment.tres")

## How fast the camera eases to its target position and look point, 1/s.
const CAMERA_SMOOTHING := 5.0
const LOOK_SMOOTHING := 7.0
## When the first take starts. The frames before it (the ground loading, the
## players being built) are dropped by tools/make_demo_gifs.py: keep its
## SKIP_START at 9 (0.29 s is inside frame 8, so frame 9 is the first clean one).
const LEAD_IN := 0.29

## A HumanBrain whose wants are set from here, not from InputManager —
## HumanBrain so the human-only paths (sling, trajectory preview, timing-
## graded marks) are the ones recorded.
class DemoBrain extends HumanBrain:
	var wish_dir := Vector3.ZERO
	var gait_value := 0.0
	var kick_hold := false
	var kick_execute := false
	var kick_charge := -1.0
	var tackle_hold := false
	var hit_out_press := false
	var hit_out_dir := Vector3.ZERO
	var fend_press := false
	var mark_safe_hold := false
	var set_shot_press := false

	func wish_direction(_controller: PlayerController) -> Vector3:
		return wish_dir

	func gait() -> float:
		return gait_value

	func wants_kick() -> bool:
		return kick_hold

	func wants_kick_execute() -> bool:
		var pressed := kick_execute
		kick_execute = false
		return pressed

	func kick_charge_override() -> float:
		return kick_charge

	func wants_handball() -> bool:
		return false

	func wants_bounce() -> bool:
		return false

	func wants_tackle() -> bool:
		return tackle_hold

	func wants_lunge_tackle() -> bool:
		return false

	func lunge_tackle_pending() -> bool:
		return false

	func wants_mark_safe() -> bool:
		return mark_safe_hold

	func wants_mark_running() -> bool:
		return false

	func wants_mark_aggressive() -> bool:
		return false

	func wants_spoil() -> bool:
		return false

	func wants_smother() -> bool:
		return false

	func wants_hit_out() -> bool:
		var pressed := hit_out_press
		hit_out_press = false
		return pressed

	func hit_out_aim(_controller: PlayerController) -> Vector3:
		return hit_out_dir

	func wants_fend() -> bool:
		var pressed := fend_press
		fend_press = false
		return pressed

	func wants_fist() -> bool:
		return false

	func wants_kick_curve() -> bool:
		return false

	func wants_bump_stance() -> bool:
		return false

	func wants_goal_set_shot() -> bool:
		var pressed := set_shot_press
		set_shot_press = false
		return pressed


var _viewer: Node
var _field: Field
var _camera: Camera3D
var _time := 0.0
var _end_time := 0.0
## [time, Callable], in time order.
var _timeline: Array = []
## [time, text] for tools/make_demo_gifs.py; "" clears the caption.
var _captions: Array = []
## Called every frame: where the camera should be and look.
## Returns [position, look_at].
var _camera_shot := Callable()
var _look := Vector3.ZERO
## Tackling: true from a take's launch until the hit lands, when both
## brains stop running — the viewer's contests leave the tackler running
## on through the get-up and out of shot.
var _watch_contact := false
## Tackling, the fend take: the carrier's brain while it still has RB to
## press, and the range (m) it presses at.
var _fend_brain: DemoBrain
var _fend_tackler: DemoBrain
var _fend_pressed := false
const FEND_PRESS_RANGE := Tuning.FEND_TARGET_RANGE
## Ruck: the HOME runner the first tap goes to, and whether they're after
## the ball yet.
var _runner: PlayerController
var _runner_brain: DemoBrain
var _runner_chasing := false
var _runner_run_dir := Vector3.FORWARD
## Kicking, the set shot: the kicker's brain, and whether the ball has been
## reported crossing the goal line yet.
var _set_shot_brain: DemoBrain
var _set_shot_reported := true


func _ready() -> void:
	var demo := "marking"
	var ground := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("demo="):
			demo = arg.trim_prefix("demo=")
		elif arg.begins_with("field="):
			ground = arg.trim_prefix("field=")
	if ground == "":
		ground = "park" if demo in ["ruck", "kicking"] else "bush"
	# In memory only: neither is saved, so the user's settings stay theirs.
	Settings.field_style = Settings.FieldStyle.CLASSIC if ground == "park" else Settings.FieldStyle.OVAL_1
	Settings.set_hud(&"mark_assist", 0)

	_viewer = ViewerScene.instantiate()
	add_child(_viewer)
	_viewer.set_root_layout_visible(false)
	_hide_hint_bars(_viewer)
	_camera = _viewer.get_node("Camera3D")
	_dress_ground()
	print("demo_recorder: %s on the %s" % [demo, "park (Field 1)" if ground == "park" else "bush oval (Field 2)"])

	match demo:
		"marking":
			_stage_marking()
		"tackling":
			_stage_tackling()
		"ruck":
			_stage_ruck()
		"kicking":
			_stage_kicking()
		_:
			push_error("demo_recorder: unknown demo '%s'" % demo)
			get_tree().quit(1)


func _process(delta: float) -> void:
	_time += delta
	while not _timeline.is_empty() and float(_timeline[0][0]) <= _time:
		(_timeline.pop_front()[1] as Callable).call()
	if _watch_contact:
		_stop_runners_on_contact()
	_press_fend_in_range()
	_hide_approach_aim()
	_steer_runner()
	_report_set_shot()
	if _camera_shot.is_valid():
		var shot: Array = _camera_shot.call()
		_camera.position = _camera.position.lerp(shot[0], 1.0 - exp(-CAMERA_SMOOTHING * delta))
		_look = _look.lerp(shot[1], 1.0 - exp(-LOOK_SMOOTHING * delta))
		_camera.look_at(_look)
	if _time >= _end_time:
		_write_captions()
		get_tree().quit()


func _at(time: float, step: Callable) -> void:
	_timeline.append([time, step])
	_timeline.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	_end_time = maxf(_end_time, time)


## Cuts the camera straight to `shot`'s first frame, then lets it ease.
func _cut_to(shot: Callable) -> void:
	_kill_viewer_camera_tween()
	_camera_shot = shot
	var first: Array = shot.call()
	_camera.position = first[0]
	_look = first[1]
	_camera.look_at(_look)


func _kill_viewer_camera_tween() -> void:
	var tween: Tween = _viewer.get("_camera_tween")
	if tween != null and tween.is_valid():
		tween.kill()


## The viewer's "Esc / C back to menu" bars sit outside its root layout.
func _hide_hint_bars(node: Node) -> void:
	for child in node.get_children():
		if child is KeyHintBar:
			(child as CanvasItem).visible = false
		_hide_hint_bars(child)


## The studio out, a ground in: see the header.
func _dress_ground() -> void:
	for studio_part in ["StudioGround", "StudioFloor", "Fill"]:
		var node := _viewer.get_node_or_null(studio_part) as Node3D
		if node != null:
			node.visible = false
	(_viewer.get_node("WorldEnvironment") as WorldEnvironment).environment = MatchEnvironment
	# full_game.tscn's Sun, setting for setting, as ReplayStage builds it (a
	# .tscn writes a basis row by row, Basis() takes columns: transposed()).
	var sun := _viewer.get_node("Sun") as DirectionalLight3D
	sun.transform = Transform3D(Basis(Vector3(0.8637, -0.3627, 0.3499), Vector3(0.0, 0.6943, 0.7197),
		Vector3(-0.5039, -0.6216, 0.5998)).transposed(), Vector3(0.0, 40.0, 0.0))
	sun.light_energy = 1.05
	sun.light_angular_distance = 2.2
	sun.shadow_enabled = true
	sun.shadow_blur = 1.0
	sun.shadow_opacity = 0.72
	sun.directional_shadow_max_distance = 120.0
	sun.directional_shadow_blend_splits = true
	_field = FieldScene.instantiate() as Field
	_field.follow_field_style = true
	_viewer.add_child(_field)
	# The ground's own field umpire is the viewer's: the contests hide him,
	# the ruck has him throw the ball up.
	_viewer.set("_umpire", _field.field_umpire())
	_field.field_umpire().visible = false


## Captions go to a file, not the frame (see the header).
func _say(text: String) -> void:
	_captions.append([snappedf(maxf(_time - LEAD_IN, 0.0), 0.001), text])


func _write_captions() -> void:
	print("demo_recorder: captions %s" % JSON.stringify(_captions))
	var movie := Engine.get_write_movie_path()
	if movie == "":
		return
	var file := FileAccess.open(movie.get_base_dir().path_join("captions.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(_captions))


func _player_a() -> PlayerController:
	return _viewer.get("_contest_a")


func _player_b() -> PlayerController:
	return _viewer.get("_contest_b")


func _ball() -> Ball:
	return _viewer.get("_contest_ball")


# ── Marking ──────────────────────────────────────────────────────────

## The viewer's MARK DELIVERY, one take per tier, on the cue the game uses
## (Tuning.MARK_CUE_SOURCE). B's MarkPreviewBrain presses the way a human
## following the ring would. In the third take the opponent goes for the
## ball too (holding the Safe mark), so MarkContest decides who takes it.
func _stage_marking() -> void:
	_viewer.set("_mark_cue_source", Tuning.MARK_CUE_SOURCE)
	# caption, MarkPreviewTier (1 SAFE, 2 RUNNING, 3 AGGRESSIVE), B's run
	# speed, ball height at the hands, opponent at B's shoulder, take length.
	var takes := [
		["SAFE MARK  ·  hold A", 1, 0.0, 1.45, false, 3.0],
		["RUNNING MARK  ·  tap X", 2, 5.5, 1.35, false, 3.0],
		["CONTESTED MARK  ·  tap Y to leap", 3, 0.0, 2.45, true, 3.6],
	]
	var t := LEAD_IN
	for take: Array in takes:
		_at(t, func() -> void:
			_viewer.set("_mark_run_speed", take[2])
			_viewer.set("_mark_height", take[3])
			_viewer.set("_mark_contested", take[4])
			_viewer.call("_launch_mark_preview", take[1])
			if take[4]:
				var rival := DemoBrain.new()
				rival.mark_safe_hold = true
				_player_a().set_brain(rival)
			for player: PlayerController in [_player_a(), _player_b()]:
				if not player.mark_caught.is_connected(_on_mark_caught):
					player.mark_caught.connect(_on_mark_caught.bind(player))
			_say(take[0])
			_cut_to(_mark_shot))
		t += float(take[5])
	_at(t, func() -> void: pass)


func _on_mark_caught(tier: Tuning.Action, legal: bool, player: PlayerController) -> void:
	print("demo_recorder: %s marked it (%s, legal %s) at %.2f s" % [
		"the marker" if player == _player_b() else "the opponent",
		Tuning.Action.keys()[tier], legal, _time - LEAD_IN])


## Beside B, from their left and a little in front, following them in. The
## opponent stands at B's right shoulder, so B is the nearer body.
func _mark_shot() -> Array:
	var b := _player_b()
	var focus := Vector3(b.global_position.x, 1.5, b.global_position.z - 0.6)
	return [focus + Vector3(-5.6, 0.4, -2.2), focus]


# ── Tackling ─────────────────────────────────────────────────────────

## Wrap through the viewer's CONTESTS (a lunge wraps for any brain), the
## sling with A on a DemoBrain, then the fend-off. In all three the carrier
## runs on at CARRIER_SPEED and the tackler starts RUN_IN_EXTRA further out
## than the viewer puts them, so there's a run-in to watch.
const CARRIER_SPEED := 4.0
const RUN_IN_EXTRA := 5.0

func _stage_tackling() -> void:
	var t := LEAD_IN
	_at(t, func() -> void:
		_viewer.set("_approach_speed", 6.5)
		_viewer.set("_b_speed", CARRIER_SPEED)
		_viewer.call("_launch_contest", 1)   # ContestKind.TACKLE_LUNGE
		_back_up_tackler()
		_watch_contact = true
		_say("WRAP TACKLE  ·  tap X")
		_cut_to(_contest_shot))
	t += 3.6
	_at(t, func() -> void:
		_viewer.call("_launch_contest", 0)   # ContestKind.TACKLE_SLIDE
		_back_up_tackler()
		var brain := DemoBrain.new()
		brain.wish_dir = _viewer.get("_contest_run_dir")
		brain.gait_value = _viewer.call("_gait_for_speed", 6.5)
		brain.tackle_hold = true
		_player_a().set_brain(brain)
		_watch_contact = true
		_say("SLING TACKLE  ·  hold B")
		_cut_to(_contest_shot))
	t += 3.6
	# The fend-off. A fend cuts the tackle's balance loss b by FEND_B_CUT and
	# a fended Slide breaks past TACKLE_LUNGE_BREAK_P, so the tackle staged
	# is one that can break: a Slide stepped in from 60 degrees off the
	# carrier's line at a jog, not a lunge (a lunge closes at 7 m/s or more
	# and holds through a fend). The tackler holds B from arm's length, the
	# carrier taps RB as they come inside FEND_TARGET_RANGE.
	_at(t, func() -> void:
		_viewer.set("_approach_speed", 2.5)
		_viewer.set("_approach_angle_deg", 60.0)
		_viewer.set("_b_speed", 3.0)
		_viewer.call("_launch_contest", 0)   # ContestKind.TACKLE_SLIDE
		_back_up_tackler(2.0)
		_fend_tackler = DemoBrain.new()
		_fend_tackler.wish_dir = _viewer.get("_contest_run_dir")
		_fend_tackler.gait_value = _viewer.call("_gait_for_speed", 2.5)
		_player_a().set_brain(_fend_tackler)
		_fend_brain = DemoBrain.new()
		_fend_brain.wish_dir = Vector3.FORWARD
		_fend_brain.gait_value = _viewer.call("_gait_for_speed", 3.0)
		_player_b().set_brain(_fend_brain)
		_player_a().last_tackle = {}
		_say("FEND OFF  ·  tap RB with the ball")
		_cut_to(_fend_shot))
	t += 3.8
	_at(t, func() -> void:
		var tackle := _player_a().last_tackle
		print("demo_recorder: fend take, tackle %s" % [tackle if not tackle.is_empty() else "never landed"])
		print("demo_recorder: carrier still has the ball %s, ragdolled %s" % [
			_player_b().is_carrying(), _player_b().is_ragdolled()]))


## Moves the tackler further back along their run line after the viewer has
## placed them.
func _back_up_tackler(extra := RUN_IN_EXTRA) -> void:
	var run_dir: Vector3 = _viewer.get("_contest_run_dir")
	_player_a().global_position -= run_dir * extra


## The hit has landed once the carrier has lost the ball or either body is
## down: from then on nobody runs, so the pair stays in shot.
func _stop_runners_on_contact() -> void:
	var a := _player_a()
	var b := _player_b()
	if b.is_carrying() and not a.is_ragdolled() and not b.is_ragdolled():
		return
	_watch_contact = false
	var tackle := a.last_tackle
	print("demo_recorder: tackle b %.2f held %s outcome %s at %.2f s, carrier ragdolled %s, tackler ragdolled %s" % [
		float(tackle.get("b", 0.0)), tackle.get("held", false), tackle.get("outcome", "?"),
		_time - LEAD_IN, b.is_ragdolled(), a.is_ragdolled()])
	a.last_tackle = {}
	for brain in [a.brain(), _viewer.get("_brain_b")]:
		brain.set("wish_dir", Vector3.ZERO)
		brain.set("gait_value", 0.0)
	if a.brain() is DemoBrain:
		(a.brain() as DemoBrain).tackle_hold = false


## The fend take's presses: the carrier's RB as the tackler comes inside
## FEND_PRESS_RANGE, the way a player sees the tackle coming and palms it
## off, and the tackler's B from arm's length (a step in, not a dive).
func _press_fend_in_range() -> void:
	if _fend_brain == null:
		return
	var gap := _player_a().global_position.distance_to(_player_b().global_position)
	if gap <= Tuning.TACKLE_RADIUS:
		_fend_tackler.tackle_hold = true
	if gap <= FEND_PRESS_RANGE and not _fend_pressed:
		_fend_pressed = true
		_fend_brain.fend_press = true
		print("demo_recorder: fend pressed at %.2f s" % (_time - LEAD_IN))
	if not _player_a().last_tackle.is_empty():
		_fend_tackler.tackle_hold = false
		_fend_tackler.wish_dir = Vector3.ZERO
		_fend_tackler.gait_value = 0.0
		_fend_brain = null


func _hide_approach_aim() -> void:
	var aim: Node3D = _viewer.get("_approach_aim")
	if aim != null:
		# The viewer shows it again on its own frame, so take it off every
		# render layer as well.
		aim.visible = false
		(aim as VisualInstance3D).layers = 0


## Side-on to the run, framed on the pair as they meet and fall.
func _contest_shot() -> Array:
	var mid := (_player_a().global_position + _player_b().global_position) * 0.5
	mid.y = 0.0
	var focus := mid + Vector3(0.0, 0.8, 0.0)
	return [focus + Vector3(4.8, 1.0, 1.2), focus]


## The same side-on shot, held on the carrier: a broken tackle leaves the
## tackler behind.
func _fend_shot() -> Array:
	var b := _player_b().global_position
	var focus := Vector3(b.x, 0.95, b.z - 0.4)
	return [focus + Vector3(5.0, 0.9, -1.4), focus]


# ── Ruck ─────────────────────────────────────────────────────────────

## Two ball-ups in the centre circle, staged the way FullGame.
## _begin_ruck_contest and _release_ruck_contest run one: both ruckmen
## nominated, the umpire's throw-up with the ball in his hands, the toss at
## the release. One ruckman presses RB early, during the throw-up, so the
## latch fires it near the toss's peak and taps it where their right stick
## points; the other presses late and misses. HOME wins the first and taps
## to a runner; AWAY wins the second.
func _stage_ruck() -> void:
	var spot := Vector3.ZERO
	_viewer.call("_ensure_contest_built")
	_runner = PlayerScene.instantiate()
	_runner.team = Tuning.Team.HOME
	(_runner.get_node("Rig") as HumanoidRig).guernsey_number = 7
	_viewer.add_child(_runner)
	_runner_brain = DemoBrain.new()
	_runner.set_brain(_runner_brain)
	_runner.global_position = Vector3(20.0, 0.0, -20.0)
	_ruck_take(LEAD_IN, spot, true, Vector3(-0.5, 0.0, -0.87), "CENTRE BOUNCE  ·  RB to hit out, right stick to aim", true)
	_at(LEAD_IN + 5.6, func() -> void: _runner_chasing = false)
	_ruck_take(LEAD_IN + 5.6, spot, false, Vector3(0.55, 0.0, -0.85), "A PALM, NOT A CATCH  ·  early press, tapped at the peak", false)
	_at(LEAD_IN + 9.2, func() -> void: pass)


func _ruck_take(t: float, spot: Vector3, home_early: bool, aim: Vector3, caption: String,
		with_runner: bool) -> void:
	var home := DemoBrain.new()
	var away := DemoBrain.new()
	var early := home if home_early else away
	var late := away if home_early else home
	early.hit_out_dir = aim.normalized()
	late.hit_out_dir = -aim.normalized()
	var release := Tuning.BALL_UP_THROW_DURATION * Umpire.THROW_RELEASE_END
	var offset := 1.3   # FullGame.RUCK_CONTEST_OFFSET
	var throw_at := t + 0.35

	_at(t, func() -> void:
		_viewer.call("_show_contest")
		_viewer.call("_reset_contest_state")
		_hide_approach_aim()
		var a := _player_a()
		var b := _player_b()
		a.set_ruck_contestant(false)
		b.set_ruck_contestant(false)
		a.set_brain(home)
		b.set_brain(away)
		_viewer.call("_place_contest_body", a, spot + Vector3(-offset, 0.0, 0.0), Vector3.RIGHT, 0.0)
		_viewer.call("_place_contest_body", b, spot + Vector3(offset, 0.0, 0.0), Vector3.LEFT, 0.0)
		var umpire := _field.field_umpire()
		umpire.visible = true
		umpire.stand_at(spot + Vector3.FORWARD * Field.UMPIRE_CENTRE_OFFSET, spot)
		var ball := _ball()
		ball.visible = true
		ball.lock_to(umpire.ball_hold_point())
		for player: PlayerController in [a, b]:
			if not player.hit_out_resolved.is_connected(_on_hit_out_resolved):
				player.hit_out_resolved.connect(_on_hit_out_resolved)
		# The runner holds their spot outside the contest until the tap.
		_runner.drop_ball()
		_runner_brain.wish_dir = Vector3.ZERO
		_runner_brain.gait_value = 0.0
		_runner.visible = with_runner
		_runner_run_dir = aim.normalized()
		var wait_at := spot + aim.normalized() * 9.0 if with_runner else Vector3(30.0, 0.0, -30.0)
		_viewer.call("_place_contest_body", _runner, wait_at, -aim.normalized(), 0.0)
		_say(caption)
		_cut_to(_ruck_shot.bind(spot)))
	_at(throw_at, func() -> void:
		_field.field_umpire().throw_up(Tuning.BALL_UP_THROW_DURATION)
		for player: PlayerController in [_player_a(), _player_b()]:
			player.set_ruck_contestant(true, release + Tuning.RUCK_CONTEST_WINDOW))
	_at(throw_at + 0.5, func() -> void: early.hit_out_press = true)
	_at(throw_at + release, func() -> void:
		var ball := _ball()
		var from := ball.global_position
		var target := spot + Vector3.UP * 0.4
		var rise := Tuning.BALL_UP_TOSS_SPEED
		var drop := maxf(from.y - target.y, 0.0)
		var flight := (rise + sqrt(rise * rise + 2.0 * Tuning.GRAVITY * drop)) / Tuning.GRAVITY
		var across := Vector3(target.x - from.x, 0.0, target.z - from.z) / maxf(flight, 0.05)
		var toss := across + Vector3.UP * rise
		ball.reset_at(from)
		ball.launch(toss.normalized(), toss.length(), Vector3.ZERO, null))
	_at(throw_at + release + 0.62, func() -> void: late.hit_out_press = true)


func _on_hit_out_resolved(player: PlayerController, connected: bool) -> void:
	print("demo_recorder: %s hit-out %s at %.2f s" % [Tuning.Team.keys()[player.team],
		"connected" if connected else "missed", _time - LEAD_IN])
	if connected and player.team == Tuning.Team.HOME and _runner.visible:
		_runner_chasing = true


## The runner's stick: at the ball until they have it, then on along the
## line of the tap. The gather is the real one (_try_gather).
func _steer_runner() -> void:
	if not _runner_chasing:
		return
	var heading := _runner_run_dir
	if not _runner.is_carrying():
		heading = _ball().global_position - _runner.global_position
		heading.y = 0.0
		heading = heading.normalized() if heading.length_squared() > 0.01 else _runner_run_dir
	elif _runner_brain.gait_value < 1.0:
		print("demo_recorder: the runner gathered the tap at %.2f s" % (_time - LEAD_IN))
		_runner_brain.gait_value = 1.0
	_runner_brain.wish_dir = heading
	_runner_brain.gait_value = maxf(_runner_brain.gait_value, Tuning.GAIT_JOG)


## Low and close on the two ruckmen from outside the circle. Once a runner
## is after the tap it pulls back and across to hold the ruckmen, the ball
## and the runner.
func _ruck_shot(spot: Vector3) -> Array:
	if _runner_chasing:
		var runner := _runner.global_position
		var focus := (spot + runner) * 0.5 + Vector3(0.0, 1.2, 0.0)
		return [focus + Vector3(5.5, 1.6, 7.5), focus]
	var focus := spot + Vector3(0.0, 1.9, -0.4)
	return [focus + Vector3(0.6, -0.1, 5.6), focus]


# ── Kicking ──────────────────────────────────────────────────────────

## Two takes. First A jogs in carrying and holds the stance, seen from
## behind and to one side, so the trajectory preview's arc opens out to its
## landing ring; on the kick it cuts side-on and close for the drop punt
## (ball drop, straight leg, pointed foot), then eases back as the ball goes.
## Then the set shot: a mark 36 m out, the walk back, the line-up, the
## run-up and the kick at goal, from behind the kicker.
func _stage_kicking() -> void:
	var brain := DemoBrain.new()
	var start := Vector3(0.0, 0.0, 8.0)

	_at(LEAD_IN, func() -> void:
		_viewer.call("_ensure_contest_built")
		_viewer.call("_show_contest")
		_viewer.call("_reset_contest_state")
		_hide_approach_aim()
		var a := _player_a()
		var b := _player_b()
		b.visible = false
		_viewer.call("_place_contest_body", b, Vector3(30.0, 0.0, 40.0), Vector3.FORWARD, 0.0)
		a.set_brain(brain)
		_viewer.call("_place_contest_body", a, start, Vector3.FORWARD, Tuning.JOG_SPEED * 0.5)
		a.give_possession(_ball())
		brain.wish_dir = Vector3.FORWARD
		brain.gait_value = Tuning.GAIT_JOG * 0.5
		_say("KICK  ·  hold LT to aim and set the power")
		_cut_to(_kick_behind_shot))
	_at(LEAD_IN + 0.5, func() -> void:
		brain.kick_charge = 0.55
		brain.kick_hold = true)
	_at(LEAD_IN + 1.6, func() -> void: brain.kick_charge = 0.8)
	_at(LEAD_IN + 2.9, func() -> void:
		_say("DROP PUNT  ·  RT to kick")
		_cut_to(_kick_side_shot))
	_at(LEAD_IN + 3.0, func() -> void: brain.kick_execute = true)
	_at(LEAD_IN + 3.6, func() -> void:
		brain.kick_hold = false
		brain.wish_dir = Vector3.ZERO
		brain.gait_value = 0.0
		_camera_shot = _kick_away_shot.bind(_player_a().global_position))
	_set_shot_take(LEAD_IN + 5.4)


func _kick_behind_shot() -> Array:
	var a := _player_a().global_position
	return [a + Vector3(4.6, 2.1, 4.8), a + Vector3(0.0, 1.9, -8.0)]


func _kick_side_shot() -> Array:
	var focus := _player_a().global_position + Vector3(0.0, 0.85, -0.5)
	return [focus + Vector3(4.0, 0.15, 0.4), focus]


## Eased back and up from where the kick was taken, so the kicker's follow-
## through and the ball climbing away share the frame.
func _kick_away_shot(kicked_from: Vector3) -> Array:
	var focus := kicked_from + Vector3(0.0, 2.2, -3.5)
	return [focus + Vector3(8.5, -0.6, 0.8), focus]


## HOME kicks to +X. The mark is taken facing back up the ground, 36 m from
## the goal line and a little off the centre line.
func _set_shot_take(t: float) -> void:
	var mark_spot := Vector3(Tuning.FIELD_HALF_LENGTH - 36.0, 0.0, 3.0)
	_set_shot_brain = DemoBrain.new()
	var brain := _set_shot_brain
	_at(t, func() -> void:
		_viewer.call("_reset_contest_state")
		var a := _player_a()
		a.set_brain(brain)
		_viewer.call("_place_contest_body", a, mark_spot, Vector3.LEFT, 0.0)
		brain.mark_safe_hold = true
		# The kick in: a real kick flight (markable), 22 m, solved the way
		# the viewer's MARK DELIVERY solves its own.
		var from := mark_spot + Vector3.LEFT * 22.0 + Vector3.UP * 1.4
		var to := mark_spot + Vector3.UP * 1.45 + Vector3.LEFT * 0.25
		var v: Vector3 = _viewer.call("_mark_launch_velocity", from, to, 1.45)
		var ball := _ball()
		ball.global_transform = Transform3D(Basis.looking_at(-v.normalized(), Vector3.UP), from)
		ball.launch(v.normalized(), v.length(), Vector3.ZERO, null, true)
		if not a.mark_caught.is_connected(_on_set_shot_mark):
			a.mark_caught.connect(_on_set_shot_mark)
		_say("SET SHOT  ·  mark inside 55 m")
		_cut_to(_set_shot_mark_shot.bind(mark_spot)))
	# In case the mark is dropped: the timeline still ends.
	_at(t + 9.0, func() -> void: pass)


## The rest of the take runs off the mark itself: line up (Y) a second into
## the walk back, kick (RT) once the run-up is paced out. The RT press sits
## in the brain until the stance reads it, like a buffered press.
func _on_set_shot_mark(tier: Tuning.Action, legal: bool) -> void:
	print("demo_recorder: set-shot mark (%s, legal %s) at %.2f s" % [
		Tuning.Action.keys()[tier], legal, _time - LEAD_IN])
	var brain := _set_shot_brain
	brain.mark_safe_hold = false
	var now := _time
	_at(now + 0.9, func() -> void:
		brain.kick_charge = 0.9
		brain.set_shot_press = true
		_say("SET SHOT  ·  Y to line up, RT to run in and kick")
		_camera_shot = _set_shot_behind_shot)
	_at(now + 2.6, func() -> void:
		brain.kick_execute = true
		_set_shot_reported = false)


## From the goal side as the kick comes in, the marker facing the camera's
## left.
func _set_shot_mark_shot(mark_spot: Vector3) -> Array:
	var focus := mark_spot + Vector3(-1.0, 1.4, 0.0)
	return [focus + Vector3(3.0, 0.5, 6.0), focus]


## Behind the kicker, the goals over their shoulder. Once the ball is on its
## way the look follows it as far as the goal line.
func _set_shot_behind_shot() -> Array:
	var a := _player_a().global_position
	var goal := Vector3(Tuning.FIELD_HALF_LENGTH, 3.0, 0.0)
	var look := a.lerp(goal, 0.45) + Vector3(0.0, 2.0, 0.0)
	var ball := _ball()
	if not _set_shot_reported and not _player_a().is_carrying():
		look = ball.global_position
		look.x = minf(look.x, goal.x)
	var back := (a - goal)
	back.y = 0.0
	back = back.normalized()
	return [a + back * 6.5 + Vector3(0.0, 2.3, 0.0) + back.cross(Vector3.UP) * 1.6, look]


## Where the set shot crossed the goal line, once.
func _report_set_shot() -> void:
	if _set_shot_reported:
		return
	var ball := _ball()
	if _player_a().is_carrying():
		return
	var p := ball.global_position
	if p.x >= Tuning.FIELD_HALF_LENGTH:
		_set_shot_reported = true
		print("demo_recorder: set shot crossed the goal line at z %.2f m, height %.2f m, at %.2f s (goal posts at z ±%.2f)" % [
			p.z, p.y, _time - LEAD_IN, Tuning.GOAL_POST_SEPARATION * 0.5])
	elif ball.linear_velocity.length() < 0.5 and p.y < 0.5:
		_set_shot_reported = true
		print("demo_recorder: set shot stopped short at x %.2f m, %.2f m from the line" % [
			p.x, Tuning.FIELD_HALF_LENGTH - p.x])
