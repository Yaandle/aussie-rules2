extends Node

## Records the README's feature demos (marking, tackling, ruck, kicking) in
## the animation viewer's studio. Dev-only, and only useful under Godot's
## movie writer. Each demo runs through the real gameplay code: the
## viewer's own MARK DELIVERY and CONTESTS where they exist, and for the
## ruck and the kick a short staging of the same calls a match makes.
## Nothing here decides an outcome; it only presses buttons and moves the
## camera.
##
## One demo per run, picked by the user arg `demo=` (marking, tackling,
## ruck or kicking). Each run writes PNG frames into its own folder, named
## after the demo; tools/make_demo_gifs.py turns those folders into
## docs/media/<demo>.gif:
##
##   Godot_console.exe --path . --write-movie <frames>/tackling/f.png
##       --fixed-fps 30 res://scenes/dev/demo_recorder.tscn -- demo=tackling
##   python tools/make_demo_gifs.py <frames> docs/media
##
## Frames come out at the project's 1600x900 window size; `--resolution`
## doesn't override that. The viewer's menus are hidden and a caption names
## the control instead. The run prints what each ruck and tackle take really
## did, and quits when the demo's timeline ends.
##
## Two things the viewer can't show on its own:
## * Its SEQUENCES buttons (bounce on the run, mark retreat, umpire ball-up)
##   have been stubs since 2026-10-08, so the ruck stages its own ball-up:
##   FullGame._begin_ruck_contest's nomination, throw-up and release.
## * Its contest brains aren't HumanBrains, and a Slide only slings for a
##   human (PlayerController._slide_connect), so the sling uses DemoBrain.

const ViewerScene := preload("res://scenes/dev/animation_viewer.tscn")

## How fast the camera eases to its target, 1/s.
const CAMERA_SMOOTHING := 6.0

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
		return false

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

	func wants_bump_stance() -> bool:
		return false

	func wants_goal_set_shot() -> bool:
		return false


var _viewer: Node
var _camera: Camera3D
var _caption: Label
var _caption_panel: PanelContainer
var _time := 0.0
var _end_time := 0.0
## [time, Callable], in time order.
var _timeline: Array = []
## Called every frame with delta: where the camera should be and look.
## Returns [position, look_at].
var _camera_shot := Callable()
## Tackling: true from a take's launch until the hit lands, when both
## brains stop running — the viewer's contests leave the tackler running
## on through the get-up and out of shot.
var _watch_contact := false


func _ready() -> void:
	_viewer = ViewerScene.instantiate()
	add_child(_viewer)
	_viewer.set_root_layout_visible(false)
	_hide_hint_bars(_viewer)
	_camera = _viewer.get_node("Camera3D")
	_build_caption()

	var demo := "marking"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("demo="):
			demo = arg.trim_prefix("demo=")
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
	if _camera_shot.is_valid():
		var shot: Array = _camera_shot.call()
		var k := 1.0 - exp(-CAMERA_SMOOTHING * delta)
		_camera.position = _camera.position.lerp(shot[0], k)
		_camera.look_at(shot[1])
	if _time >= _end_time:
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
	_camera.look_at(first[1])


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


func _build_caption() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	margin.grow_vertical = Control.GROW_DIRECTION_BEGIN
	margin.add_theme_constant_override(&"margin_left", 24)
	margin.add_theme_constant_override(&"margin_bottom", 24)
	layer.add_child(margin)
	_caption_panel = PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = RetroWindow.PANEL
	box.border_color = RetroWindow.BORDER
	box.set_border_width_all(3)
	box.set_content_margin_all(12)
	box.content_margin_left = 18
	box.content_margin_right = 18
	box.shadow_color = RetroWindow.BORDER
	box.shadow_size = 0
	box.shadow_offset = Vector2(4, 4)
	_caption_panel.add_theme_stylebox_override(&"panel", box)
	margin.add_child(_caption_panel)
	_caption = UIStyle.label("", 30, RetroWindow.BORDER, UIStyle.WEIGHT_HEAVY)
	_caption_panel.add_child(_caption)
	_caption_panel.visible = false


func _say(text: String) -> void:
	_caption.text = text
	_caption_panel.visible = text != ""


# ── Marking ──────────────────────────────────────────────────────────

## The viewer's MARK DELIVERY, one take per tier, on the cue the game uses
## (Tuning.MARK_CUE_SOURCE). B's MarkPreviewBrain presses the way a human
## following the ring would.
func _stage_marking() -> void:
	_viewer.set("_mark_cue_source", Tuning.MARK_CUE_SOURCE)
	# caption, MarkPreviewTier (1 SAFE, 2 RUNNING, 3 AGGRESSIVE), B's run
	# speed, ball height at the hands, opponent at B's shoulder, take length.
	# Each take ends soon after the catch, before the walk back off the mark.
	var takes := [
		["SAFE MARK  ·  hold A", 1, 0.0, 1.45, false, 2.5],
		["RUNNING MARK  ·  tap X", 2, 5.5, 1.35, false, 2.4],
		["AGGRESSIVE MARK  ·  tap Y", 3, 0.0, 2.45, true, 2.8],
	]
	var t := 0.2
	for take: Array in takes:
		_at(t, func() -> void:
			_viewer.set("_mark_run_speed", take[2])
			_viewer.set("_mark_height", take[3])
			_viewer.set("_mark_contested", take[4])
			_viewer.call("_launch_mark_preview", take[1])
			_say(take[0])
			_cut_to(_mark_shot))
		t += float(take[5])
	_at(t, func() -> void: pass)


## Beside B, from their left and a little in front, following them in. The
## opponent stands at B's right shoulder, so B is the nearer body.
func _mark_shot() -> Array:
	var b: PlayerController = _viewer.get("_contest_b")
	var focus := Vector3(b.global_position.x, 1.45, b.global_position.z - 0.6)
	return [focus + Vector3(-5.2, 0.5, -1.6), focus]


# ── Tackling ─────────────────────────────────────────────────────────

## Wrap and hit stick through the viewer's CONTESTS (a lunge wraps and a
## clean bump ragdolls for any brain); the sling with A on a DemoBrain.
func _stage_tackling() -> void:
	_viewer.set("_approach_speed", 6.5)
	var t := 0.2
	_at(t, func() -> void:
		_viewer.call("_launch_contest", 1)   # ContestKind.TACKLE_LUNGE
		_hide_approach_aim()
		_watch_contact = true
		_say("WRAP TACKLE  ·  tap X")
		_cut_to(_contest_shot))
	t += 2.9
	_at(t, func() -> void:
		_viewer.call("_launch_contest", 0)   # ContestKind.TACKLE_SLIDE
		_hide_approach_aim()
		var a: PlayerController = _viewer.get("_contest_a")
		var brain := DemoBrain.new()
		brain.wish_dir = _viewer.get("_contest_run_dir")
		brain.gait_value = _viewer.call("_gait_for_speed", 6.5)
		brain.tackle_hold = true
		a.set_brain(brain)
		_watch_contact = true
		_say("SLING TACKLE  ·  hold B")
		_cut_to(_contest_shot))
	t += 2.8
	_at(t, func() -> void:
		var a: PlayerController = _viewer.get("_contest_a")
		a.set_brain(_viewer.get("_brain_a"))
		_viewer.call("_launch_contest", 2)   # ContestKind.BUMP_CLEAN
		_hide_approach_aim()
		_watch_contact = true
		_say("HIT STICK  ·  LB + flick")
		_cut_to(_contest_shot))
	t += 2.9
	_at(t, func() -> void: pass)


## The hit has landed once the carrier has lost the ball or either body is
## down: from then on nobody runs, so the pair stays in shot.
func _stop_runners_on_contact() -> void:
	var a: PlayerController = _viewer.get("_contest_a")
	var b: PlayerController = _viewer.get("_contest_b")
	if b.is_carrying() and not a.is_ragdolled() and not b.is_ragdolled():
		return
	_watch_contact = false
	# What landed, as the real resolver saw it. Cleared after, so the bump
	# take (no tackle) doesn't report the sling's.
	var tackle := a.last_tackle
	var landed := "bump" if tackle.is_empty() else "tackle b %.2f held %s knocked down %s" % [
		float(tackle.get("b", 0.0)), tackle.get("held", false), tackle.get("knocked_down", false)]
	print("demo_recorder: %s at %.2f s, carrier ragdolled %s, tackler ragdolled %s" % [
		landed, _time, b.is_ragdolled(), a.is_ragdolled()])
	a.last_tackle = {}
	for brain in [a.brain(), _viewer.get("_brain_b")]:
		brain.set("wish_dir", Vector3.ZERO)
		brain.set("gait_value", 0.0)
	if a.brain() is DemoBrain:
		(a.brain() as DemoBrain).tackle_hold = false


func _hide_approach_aim() -> void:
	var aim: Node3D = _viewer.get("_approach_aim")
	if aim != null:
		aim.visible = false


## Side-on to the run, framed on the pair as they meet and fall.
func _contest_shot() -> Array:
	var a: PlayerController = _viewer.get("_contest_a")
	var b: PlayerController = _viewer.get("_contest_b")
	var mid := (a.global_position + b.global_position) * 0.5
	mid.y = 0.0
	var focus := mid + Vector3(0.0, 0.8, 0.0)
	return [focus + Vector3(4.6, 0.9, 1.2), focus]


# ── Ruck ─────────────────────────────────────────────────────────────

## Two ball-ups, staged the way FullGame._begin_ruck_contest and
## _release_ruck_contest run one: both ruckmen nominated, the umpire's
## throw-up with the ball in his hands, the toss at the release. One ruckman
## presses RB early, during the throw-up, so the latch fires it near the
## toss's peak and taps it where their right stick points; the other
## presses late and misses. HOME wins the first, AWAY the second.
func _stage_ruck() -> void:
	var spot := Vector3(0.0, 0.0, 0.5)
	_ruck_take(0.05, spot, true, Vector3(-0.55, 0.0, -0.85), "HIT-OUT  ·  RB")
	_ruck_take(3.25, spot, false, Vector3(0.55, 0.0, -0.85), "TAP TO A RUNNER  ·  aim with the right stick")
	_at(6.45, func() -> void: pass)


func _ruck_take(t: float, spot: Vector3, home_early: bool, aim: Vector3, caption: String) -> void:
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
		_viewer.call("_ensure_contest_built")
		_viewer.call("_show_contest")
		_viewer.call("_reset_contest_state")
		_hide_approach_aim()
		var a: PlayerController = _viewer.get("_contest_a")
		var b: PlayerController = _viewer.get("_contest_b")
		a.set_ruck_contestant(false)
		b.set_ruck_contestant(false)
		a.set_brain(home)
		b.set_brain(away)
		_viewer.call("_place_contest_body", a, spot + Vector3(-offset, 0.0, 0.0), Vector3.RIGHT, 0.0)
		_viewer.call("_place_contest_body", b, spot + Vector3(offset, 0.0, 0.0), Vector3.LEFT, 0.0)
		_viewer.call("_ensure_umpire")
		var umpire: Umpire = _viewer.get("_umpire")
		umpire.visible = true
		umpire.stand_at(spot + Vector3.FORWARD * 2.4, spot)   # Field.UMPIRE_CENTRE_OFFSET
		var ball: Ball = _viewer.get("_contest_ball")
		ball.visible = true
		ball.lock_to(umpire.ball_hold_point())
		for player: PlayerController in [a, b]:
			if not player.hit_out_resolved.is_connected(_on_hit_out_resolved):
				player.hit_out_resolved.connect(_on_hit_out_resolved)
		_say(caption)
		_cut_to(_ruck_shot.bind(spot)))
	_at(throw_at, func() -> void:
		var umpire: Umpire = _viewer.get("_umpire")
		umpire.throw_up(Tuning.BALL_UP_THROW_DURATION)
		for player: PlayerController in [_viewer.get("_contest_a"), _viewer.get("_contest_b")]:
			player.set_ruck_contestant(true, release + Tuning.RUCK_CONTEST_WINDOW))
	_at(throw_at + 0.5, func() -> void: early.hit_out_press = true)
	_at(throw_at + release, func() -> void:
		var ball: Ball = _viewer.get("_contest_ball")
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
		"connected" if connected else "missed", _time])


func _ruck_shot(spot: Vector3) -> Array:
	var focus := spot + Vector3(0.0, 1.75, -0.7)
	return [focus + Vector3(0.4, 0.15, 4.9), focus]


# ── Kicking ──────────────────────────────────────────────────────────

## A jogs in carrying and holds the stance, seen from behind and to one
## side, so the trajectory preview's arc opens out to its landing ring. On the kick it cuts side-on and close for the drop punt (ball
## drop, straight leg, pointed foot), then eases back as the ball goes.
## The preview's pale green is made for turf; on the white studio floor
## it's drawn in the full accent green instead.
func _stage_kicking() -> void:
	var brain := DemoBrain.new()
	var start := Vector3(0.0, 0.0, 6.0)

	_at(0.05, func() -> void:
		_viewer.call("_ensure_contest_built")
		_viewer.call("_show_contest")
		_viewer.call("_reset_contest_state")
		_hide_approach_aim()
		var a: PlayerController = _viewer.get("_contest_a")
		var b: PlayerController = _viewer.get("_contest_b")
		b.visible = false
		_viewer.call("_place_contest_body", b, Vector3(30.0, 0.0, 30.0), Vector3.FORWARD, 0.0)
		a.set_brain(brain)
		_viewer.call("_place_contest_body", a, start, Vector3.FORWARD, Tuning.JOG_SPEED * 0.5)
		a.give_possession(_viewer.get("_contest_ball"))
		var trajectory := a.get_node("KickTrajectory")
		var colour := SoftBrutalist.ACCENT_PRIMARY.darkened(0.1)
		trajectory.set("_colour", colour)
		(trajectory.get("_dot_material") as StandardMaterial3D).albedo_color = colour
		brain.wish_dir = Vector3.FORWARD
		brain.gait_value = Tuning.GAIT_JOG * 0.5
		_say("KICK  ·  hold LT to aim")
		_cut_to(_kick_behind_shot))
	_at(0.5, func() -> void:
		brain.kick_charge = 0.55
		brain.kick_hold = true)
	_at(2.2, func() -> void:
		_say("KICK  ·  RT to kick")
		_cut_to(_kick_side_shot))
	_at(2.3, func() -> void: brain.kick_execute = true)
	_at(2.9, func() -> void:
		brain.kick_hold = false
		brain.wish_dir = Vector3.ZERO
		brain.gait_value = 0.0
		var a: PlayerController = _viewer.get("_contest_a")
		_camera_shot = _kick_away_shot.bind(a.global_position))
	_at(3.9, func() -> void: pass)


func _kick_behind_shot() -> Array:
	var a: PlayerController = _viewer.get("_contest_a")
	return [a.global_position + Vector3(5.0, 2.0, 4.6), a.global_position + Vector3(0.0, 1.9, -7.5)]


func _kick_side_shot() -> Array:
	var a: PlayerController = _viewer.get("_contest_a")
	var focus := a.global_position + Vector3(0.0, 0.85, -0.5)
	return [focus + Vector3(4.0, 0.15, 0.4), focus]


## Eased back and up from where the kick was taken, so the kicker's follow-
## through and the ball climbing away share the frame.
func _kick_away_shot(kicked_from: Vector3) -> Array:
	var focus := kicked_from + Vector3(0.0, 2.2, -3.5)
	return [focus + Vector3(8.5, -0.6, 0.8), focus]
