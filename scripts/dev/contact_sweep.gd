extends Node3D

## Headless sweep of the contacts that keep players on their feet
## (2026-11-09, docs/ANIMATION_RAGDOLL_AUDIT.md "Contact on the motor
## ragdoll"): two players running into each other, a Lunge that breaks, a
## held-up Slide on AI-style clips, a glancing bump, at a spread of
## bearings, paces and stamina for both players. tackle_sweep.tscn is the
## one for falls; this is the one for knocks. Each case is the pair's first
## contact, mid-stride, through the real resolvers. Nothing is saved
## (CharacterProfile.model_id only in memory).
##
##   godot --headless --path . res://scenes/dev/contact_sweep.tscn --fixed-fps 60 --quit-after 400
##   ... -- --model=7thbuild    (default 6thbuild)
##   ... -- --cases=18          (only these CASES indices)
## The mark cases need running one at a time: a match has one ball, and
## PlayerController._live_ball() reads the first in the "ball" group, so
## with several in the scene every marker watches someone else's.
##
## Per case: the outcome (and b, the tackle formula's balance loss), then
## for A (the one coming in) and B:
##   kind   — react (upper body on physics, legs on the animation), FALL
##            (whole-body ragdoll), or "-" (nothing physical)
##   tone   — lowest muscle tone the knock left (1 = none lost)
##   shift  — furthest the rendered chest got from the animated one (m):
##            how much of the knock shows
##   waist  — furthest the spine's root got from the animated hips (m): a
##            tear between the simulated trunk and the animated legs
##   spin   — fastest a simulated body turned (rad/s)
##   pop    — fastest the rendered chest turned beyond the animated chest's
##            own turn (rad/s), worst frame: a snap in or out of physics
##            (the trunk is capped at PhysicsRagdoll.PARTIAL_MAX_SPIN, so
##            anything far past that is the hand-in or hand-back)
##   stam   — stamina after
##   ball   — a carrier's ball, furthest from between their wrists (m)
##   [...]  — mark cases: the action clips each played
## SUMMARY gives the worst of each.

const PlayerScene := preload("res://scenes/player/player.tscn")
const PAIR_SPACING := 30.0
const RUN_IN := 75
const WATCH := 120
const CONTACT_GAP := 0.75
const COLLIDE_LEAD := 0.2   ## s before the capsules meet

## [kind, A's bearing in (deg, 0 = head-on into B's run, 180 = from behind),
##  A pace, B pace (0-1 gait), A stamina, B stamina]
const CASES := [
	[&"collide", 0.0, 1.0, 1.0, 1.0, 1.0],
	[&"collide", 45.0, 1.0, 1.0, 1.0, 1.0],
	[&"collide", 90.0, 1.0, 1.0, 1.0, 1.0],
	[&"collide", 90.0, 0.6, 0.6, 1.0, 1.0],
	[&"collide", 135.0, 1.0, 0.6, 1.0, 1.0],
	[&"collide", 180.0, 1.0, 0.6, 1.0, 1.0],
	[&"collide", 90.0, 1.0, 1.0, 1.0, 0.2],
	[&"collide", 90.0, 1.0, 1.0, 0.2, 1.0],
	[&"break", 180.0, 0.6, 1.0, 1.0, 1.0],
	[&"break", 150.0, 0.6, 1.0, 1.0, 1.0],
	[&"break", 180.0, 0.6, 1.0, 1.0, 0.2],
	[&"hold", 0.0, 1.0, 1.0, 1.0, 1.0],
	[&"hold", 90.0, 1.0, 1.0, 1.0, 1.0],
	[&"hold", 180.0, 1.0, 0.6, 1.0, 1.0],
	[&"hold", 90.0, 1.0, 1.0, 0.2, 0.2],
	[&"hold", 0.0, 0.6, 0.0, 1.0, 1.0],
	[&"glance", 90.0, 1.0, 1.0, 1.0, 1.0],
	[&"glance", 90.0, 1.0, 1.0, 1.0, 0.2],
	# A contested mark: both go for a kick arriving chest high where they
	# meet (MARK_LEAD after the hit), on the AI's Safe path.
	[&"mark", 0.0, 0.6, 0.6, 1.0, 1.0],
	[&"mark", 45.0, 0.6, 0.6, 1.0, 1.0],
	[&"mark", 90.0, 1.0, 0.6, 1.0, 1.0],
	[&"mark", 90.0, 0.6, 0.0, 1.0, 1.0],
	[&"mark", 135.0, 1.0, 0.6, 1.0, 1.0],
	[&"mark", 180.0, 1.0, 0.6, 1.0, 1.0],
	[&"mark", 270.0, 1.0, 1.0, 0.3, 1.0],
]
## A contested mark's ball: kicked from this far out along B's run, to reach
## chest height at the meeting point this long after the hit.
const MARK_KICK_DISTANCE := 20.0
const MARK_LEAD := 0.3
const MARK_HEIGHT := 1.4


## Runs one way at one pace. An AIBrain stand-in (not a HumanBrain) so a
## held Slide stays on the hold-up clips, the AI's path.
class ScriptedBrain extends PlayerBrain:
	var direction := Vector3.ZERO
	var pace := 0.0

	func wish_direction(_controller: PlayerController) -> Vector3:
		return direction

	func gait() -> float:
		return pace

	var marking := false

	func wants_mark_safe() -> bool:
		return marking


var _pairs: Array[Dictionary] = []
var _frame := 0


func _ready() -> void:
	var model := "6thbuild"
	var only: Array[int] = []
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--model="):
			model = arg.trim_prefix("--model=")
		elif arg.begins_with("--cases="):
			for index in arg.trim_prefix("--cases=").split(","):
				only.append(int(index))
	CharacterProfile.model_id = model
	print("contact_sweep: model %s" % model)
	add_child(_build_floor())
	for i in 3:
		var throwaway := PlayerScene.instantiate()
		add_child(throwaway)
		throwaway.queue_free()
	for i in CASES.size():
		if only.is_empty() or only.has(i):
			_pairs.append(_spawn_pair(CASES[i], Vector3((i - CASES.size() * 0.5) * PAIR_SPACING, 0.0, 0.0)))
	# After the players' own physics (and their ragdoll steps) each tick.
	process_physics_priority = 100
	process_priority = 100


func _build_floor() -> StaticBody3D:
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(PAIR_SPACING * (CASES.size() + 2), 1.0, 300.0)
	shape.shape = box
	shape.position = Vector3(0.0, -0.5, 0.0)
	floor_body.add_child(shape)
	return floor_body


func _spawn_pair(spec: Array, base: Vector3) -> Dictionary:
	var run := Vector3.FORWARD
	# A comes in from `bearing` relative to B's run: 0 = from in front.
	var from := run.rotated(Vector3.UP, -deg_to_rad(spec[1]))
	var a: PlayerController = PlayerScene.instantiate()
	a.team = Tuning.Team.AWAY
	var b: PlayerController = PlayerScene.instantiate()
	b.team = Tuning.Team.HOME
	add_child(a)
	add_child(b)
	var brain_a := ScriptedBrain.new()
	brain_a.direction = -from
	brain_a.pace = spec[2]
	var brain_b := ScriptedBrain.new()
	brain_b.direction = run if spec[3] > 0.0 else Vector3.ZERO
	brain_b.pace = spec[3]
	a.set_brain(brain_a)
	b.set_brain(brain_b)
	a.global_position = base + Vector3(10.0, 0.0, 80.0)
	b.global_position = base + Vector3(0.0, 0.0, 80.0)
	_face(a, -from)
	_face(b, run)
	return {"spec": spec, &"a": a, &"b": b, "from": from, "contact": base, "rows": {}, "outcome": "-"}


func _physics_process(_delta: float) -> void:
	_frame += 1
	if _frame == RUN_IN:
		for pair in _pairs:
			_hit(pair)
	elif _frame > RUN_IN and _frame <= RUN_IN + WATCH:
		pass
	elif _frame > RUN_IN + WATCH:
		_report()
		get_tree().quit()


## Sampled on the render frame, after PlayerAnimation has synced a knock's
## bodies (sync_reaction_pose) — what's drawn.
func _process(_delta: float) -> void:
	if _frame <= RUN_IN or _frame > RUN_IN + WATCH:
		return
	for pair in _pairs:
		_watch(pair, &"a")
		_watch(pair, &"b")


func _hit(pair: Dictionary) -> void:
	var spec: Array = pair.spec
	var a: PlayerController = pair[&"a"]
	var b: PlayerController = pair[&"b"]
	var from: Vector3 = pair.from
	b.global_position = pair.contact
	a.global_position = (pair.contact as Vector3) + from * CONTACT_GAP
	# Both at the pace asked for, along their lines, whatever the run-in left
	# them at (a body turning onto its line from a standstill isn't up to
	# speed in 75 frames).
	_face(a, -from, Tuning.speed_for_gait(spec[2]))
	_face(b, Vector3.FORWARD, Tuning.speed_for_gait(spec[3]))
	a.stamina = spec[4]
	b.stamina = spec[5]
	match spec[0]:
		&"collide":
			# Nothing to resolve: both converge on the contact point over
			# COLLIDE_LEAD, so the capsules meet mid-move (placed already
			# touching, Godot settles them apart as overlap and reports no
			# collision) and _react_to_body_contact does the rest.
			a.global_position = (pair.contact as Vector3) + from * (0.7 + Tuning.speed_for_gait(spec[2]) * COLLIDE_LEAD)
			b.global_position = (pair.contact as Vector3) - Vector3.FORWARD * Tuning.speed_for_gait(spec[3]) * COLLIDE_LEAD
			pair.outcome = "contact"
		&"break", &"hold":
			b.give_possession(_ball_for(b))
			var slide: bool = spec[0] == &"hold"
			var velocity := a._tackle_velocity(b, Tuning.TACKLE_SLIDE_STEP_SPEED if slide
				else Tuning.TACKLE_LUNGE_SPEED)
			var impact := TackleBalance.resolve(a.global_position, velocity, a.body_mass,
				b.global_position, b.velocity, b.body_mass,
				0.0 if slide else Tuning.TACKLE_RAGDOLL_MIN_BALANCE_LOSS, -b.global_transform.basis.z)
			var threshold := Tuning.TACKLE_SLIDE_BREAK_P if slide else Tuning.TACKLE_LUNGE_BREAK_P
			var held := float(impact.p_break) < threshold
			a.last_tackle = impact.merged({"slide": slide, "held": held})
			pair.b_loss = float(impact.b)
			if not held:
				pair.outcome = "broke (p %.2f)" % float(impact.p_break)
				b._break_tackle(a, impact)
			elif slide:
				a._slide_connect(b, impact, false)
				pair.outcome = String(a.last_tackle.get("outcome", "held"))
			else:
				a._lunge_connect(b, impact, false)
				pair.outcome = String(a.last_tackle.get("outcome", "held"))
		&"mark":
			a.global_position = (pair.contact as Vector3) + from * (0.7 + Tuning.speed_for_gait(spec[2]) * COLLIDE_LEAD)
			b.global_position = (pair.contact as Vector3) - Vector3.FORWARD * Tuning.speed_for_gait(spec[3]) * COLLIDE_LEAD
			(a.brain() as ScriptedBrain).marking = true
			(b.brain() as ScriptedBrain).marking = true
			var ball := _ball_for(b)
			var meet := (pair.contact as Vector3) + Vector3.FORWARD * Tuning.speed_for_gait(spec[3]) * MARK_LEAD
			var at := meet + Vector3.UP * MARK_HEIGHT
			var from_point := meet + Vector3.FORWARD * MARK_KICK_DISTANCE + Vector3.UP * 1.0
			var v := _launch_velocity(from_point, at, MARK_LEAD + COLLIDE_LEAD)
			ball.global_position = from_point
			ball.launch(v.normalized(), v.length(), Vector3.ZERO, null, true)
			pair.ball = ball
			for tag: StringName in [&"a", &"b"]:
				var who: StringName = tag
				(pair[tag] as PlayerController).mark_caught.connect(func(_tier: Tuning.Action, _legal: bool) -> void:
					pair.outcome = "%s marks" % who)
			pair.outcome = "spilled"
		&"glance":
			var dir := -from
			b.receive_bump(dir * Tuning.BUMP_KNOCKBACK_SPEED * Tuning.BUMP_MISTIMED_SCALE,
				Tuning.BUMP_STUN_DURATION * Tuning.BUMP_MISTIMED_SCALE, a)
			pair.outcome = "glancing bump"


## Points `player` along `dir`, moving at `speed` — the controller's own
## facing and heading too, or _update_facing turns it back.
static func _face(player: PlayerController, dir: Vector3, speed := 0.0) -> void:
	var yaw := atan2(-dir.x, -dir.z)
	player.rotation.y = yaw
	player._facing_yaw = yaw
	player._heading = dir
	player.velocity = dir * speed
	player._speed = speed


## Gravity-only aim, refined against the Ball's drag (as MarkCueHarness).
static func _launch_velocity(from: Vector3, to: Vector3, t: float) -> Vector3:
	var v := (to - from) / t + Vector3.UP * 0.5 * Tuning.GRAVITY * t
	for i in 8:
		var p := from
		var w := v
		var elapsed := 0.0
		while elapsed < t:
			var dt := minf(1.0 / 120.0, t - elapsed)
			w += (-w * w.length() * Tuning.BALL_DRAG_COEFF / Tuning.BALL_MASS + Vector3.DOWN * Tuning.GRAVITY) * dt
			p += w * dt
			elapsed += dt
		v += (to - p) / t
	return v


func _ball_for(player: PlayerController) -> Ball:
	var ball := preload("res://scenes/ball/ball.tscn").instantiate() as Ball
	add_child(ball)
	ball.global_position = player.global_position + Vector3.UP
	return ball


func _watch(pair: Dictionary, tag: StringName) -> void:
	var player: PlayerController = pair[tag]
	var controller := player.ragdoll_controller()
	var rows: Dictionary = pair.rows
	var key := String(tag) + "."
	rows[key + "stamina"] = player.stamina
	if pair.spec[0] == &"mark":
		var state := String(player._animation.current_state())
		if state != "locomotion" and not String(rows.get(key + "clips", "")).contains(state):
			rows[key + "clips"] = String(rows.get(key + "clips", "")) + state + " "
	if controller == null or controller.ragdoll() == null:
		return
	var ragdoll := controller.ragdoll()
	if controller.phase() == PlayerRagdoll.Phase.FALLING:
		rows[key + "kind"] = "FALL"
		_keep_max(rows, key + "spin", ragdoll.peak_angular_speed())
		return
	if controller.phase() != PlayerRagdoll.Phase.REACTING:
		rows.erase(key + "last_chest")
		return
	rows[key + "kind"] = "react"
	if player.is_carrying():
		var ball := player.carried_ball()
		var hands := (ragdoll.segment_tip(&"LeftLowerArm") + ragdoll.segment_tip(&"RightLowerArm")) * 0.5
		_keep_max(rows, key + "ball", ball.global_position.distance_to(hands))
	_keep_min(rows, key + "tone", controller.reaction_tone())
	var chest := ragdoll.body(&"Chest")
	var animated := ragdoll.animated_transform(&"Chest")
	var influence := ragdoll.simulator.influence
	_keep_max(rows, key + "shift", chest.global_position.distance_to(animated.origin) * influence)
	var spine_root := ragdoll.segment_root(&"Spine")
	var skeleton := (player.get_node("Rig") as HumanoidRig).skeleton()
	var spine_anim := (skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone(&"Spine"))).origin
	_keep_max(rows, key + "waist", spine_root.distance_to(spine_anim) * influence)
	for bone: StringName in ragdoll.partial_bones():
		var spin := ragdoll.body(bone).angular_velocity.length()
		if spin > float(rows.get(key + "spin", 0.0)):
			rows[key + "spin"] = spin
			rows[key + "spin_bone"] = String(bone)
	# What's drawn: the animated chest turned toward the body by influence.
	var a_rot := animated.basis.get_rotation_quaternion()
	var drawn := a_rot.slerp(chest.global_basis.get_rotation_quaternion(), influence)
	var dt := get_process_delta_time()
	if rows.has(key + "last_chest"):
		# How fast the knock's offset from the clip changes: the turn physics
		# adds on top of the animation (comparing the two turns' sizes read
		# a clip turning one way and the trunk lagging the other as a snap).
		var offset := drawn * a_rot.inverse()
		var last_offset := (rows[key + "last_chest"] as Quaternion) * (rows[key + "last_anim"] as Quaternion).inverse()
		var pop := offset.angle_to(last_offset) / maxf(dt, 0.0001)
		if pop > float(rows.get(key + "pop", 0.0)):
			rows[key + "pop"] = pop
			rows[key + "pop_at"] = "%.2fs@%.2f" % [float(_frame - RUN_IN) / 60.0, influence]
	rows[key + "last_chest"] = drawn
	rows[key + "last_anim"] = a_rot


static func _keep_max(rows: Dictionary, key: String, value: float) -> void:
	rows[key] = maxf(float(rows.get(key, -INF)), value)


static func _keep_min(rows: Dictionary, key: String, value: float) -> void:
	rows[key] = minf(float(rows.get(key, INF)), value)


func _report() -> void:
	var worst := {}
	for pair in _pairs:
		var spec: Array = pair.spec
		var line := "%-7s from %3.0f° pace %.1f/%.1f stam %.1f/%.1f -> %-14s b %.2f" % [spec[0], spec[1],
			spec[2], spec[3], spec[4], spec[5], pair.outcome, float(pair.get("b_loss", NAN))]
		for tag: StringName in [&"a", &"b"]:
			var rows: Dictionary = pair.rows
			var key := String(tag) + "."
			line += " | %s %-5s tone %.2f shift %.2f waist %.3f spin %4.1f %-13s pop %4.1f %-10s stam %.2f" % [tag,
				rows.get(key + "kind", "-"), float(rows.get(key + "tone", 1.0)),
				float(rows.get(key + "shift", 0.0)), float(rows.get(key + "waist", 0.0)),
				float(rows.get(key + "spin", 0.0)), rows.get(key + "spin_bone", ""), float(rows.get(key + "pop", 0.0)),
				rows.get(key + "pop_at", ""), float(rows.get(key + "stamina", 0.0))]
			if rows.has(key + "clips"):
				line += " [%s]" % String(rows[key + "clips"]).strip_edges()
			if rows.has(key + "ball"):
				line += " ball %.2f" % float(rows[key + "ball"])
			if rows.get(key + "kind", "-") == "react":
				worst.reacts = int(worst.get("reacts", 0)) + 1
				for stat in ["shift", "waist", "spin", "pop"]:
					worst[stat] = snappedf(maxf(float(worst.get(stat, 0.0)), float(rows.get(key + stat, 0.0))), 0.001)
		print(line)
	print("SUMMARY %s" % worst)
