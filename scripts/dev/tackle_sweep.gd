extends Node3D

## Headless regression sweep for ragdoll tackles: real held-Lunge (X),
## Sling (B) and clean-bump connects between pairs of 6thbuild players who
## are already running, and how every body falls. Each pair's hit is its
## FIRST, so each ragdoll builds on the spot, mid-animation — the path a
## match takes. Nothing here runs in gameplay and nothing is saved
## (CharacterProfile.model_id is only set in memory).
##
## Run it, read the table, change a Tuning number or PhysicsRagdoll.BODIES,
## run it again:
##   godot --headless --path . res://scenes/dev/tackle_sweep.tscn --fixed-fps 60 --quit-after 700
##
## Per case and per body (c = carrier, t = tackler):
##   DOWN/up      — hips on the turf when the get-up started (PlayerRagdoll)
##   along/across — where the hips landed from the contact point, metres,
##                  along the hit line and to its left
##   fd/fu        — face down / face up at the get-up; t = seconds to it
##   start        — fastest any body spun in the first 0.1 s of the fall
##                  (rad/s): a snap at the hand-off, not the fall itself
##   peak         — fastest linear / angular body speed in the whole fall
##   hip_back     — furthest a thigh swung behind the pelvis (deg): the
##                  hand-built anatomy check, independent of the joints'
##                  own frames, so it compares across versions
##   joint        — PhysicsRagdoll.joint_report's worst overshoot past a
##                  limit, measured from the rest pose the joints are built
##                  in, and where
## The SUMMARY line totals the falls and the worst of each.
##
## Baseline 2026-10-28 (docs/ANIMATION_RAGDOLL_AUDIT.md), after the wrap's
## grip was sized on the wrist's real mass: every carrier and tackler down;
## hip_back worst 60° (c) / 54° (t); start worst 27 / 23; peak spin worst
## 74 / 52 rad/s; joint overshoots of 10-40° for a frame or two at ground
## impact, mostly Spine/Chest/feet as the body lands. Before that grip fix
## the tacklers' worst joint was an elbow in 8 of 12 Lunges (up to +47°)
## and a forearm whipped to 335 rad/s. The code before the audit, on the
## same cases: hip_back ~100°, knees folding to ~180°, start up to 62 (t).

const PlayerScene := preload("res://scenes/player/player.tscn")
const MODEL_ID := "6thbuild"

## [kind, carrier's run bearing (deg, 0 = -Z), carrier gait (0 = standing),
## where the tackler comes from relative to the carrier's run (0 = head-on,
## 90 = their right, 180 = behind), tackler gait]
const CASES := [
	[&"lunge", 0.0, 1.0, 0.0, 1.0],
	[&"lunge", 0.0, 1.0, 45.0, 1.0],
	[&"lunge", 0.0, 1.0, 90.0, 1.0],
	[&"lunge", 0.0, 1.0, 135.0, 1.0],
	[&"lunge", 0.0, 1.0, 180.0, 1.0],
	[&"lunge", 0.0, 1.0, 225.0, 1.0],
	[&"lunge", 0.0, 1.0, 270.0, 1.0],
	[&"lunge", 0.0, 1.0, 315.0, 1.0],
	[&"lunge", 0.0, 0.0, 0.0, 1.0],
	[&"lunge", 0.0, 0.0, 90.0, 1.0],
	[&"lunge", 0.0, 0.0, 180.0, 1.0],
	[&"lunge", 30.0, 0.6, 90.0, 0.7],
	[&"sling", 0.0, 1.0, 0.0, 1.0],
	[&"sling", 0.0, 1.0, 90.0, 1.0],
	[&"bump", 0.0, 1.0, 0.0, 0.7],
	[&"bump", 0.0, 1.0, 90.0, 0.7],
]
## Physics frames of running before the hit (long enough to be mid-stride at
## pace), then frames watched after it (past the longest get-up).
const RUN_IN := 75
const WATCH := 300
const START_FRAMES := 6
const PAIR_SPACING := 40.0
## Where the tackler stands off the carrier at the hit (inside TACKLE_RADIUS).
const CONTACT_GAP := 0.8


## Runs one way at one gait and does nothing else. A HumanBrain because the
## Sling knockdown is a human's only (PlayerController._slide_connect);
## headless, there's no input for the rest of it to read.
class ScriptedBrain extends HumanBrain:
	var direction := Vector3.ZERO
	var pace := 0.0

	func wish_direction(_controller: PlayerController) -> Vector3:
		return direction

	func gait() -> float:
		return pace


var _pairs: Array[Dictionary] = []
var _frame := 0


func _ready() -> void:
	CharacterProfile.model_id = MODEL_ID
	add_child(_build_floor())
	# LESSONS.md's same-frame construction race.
	for i in 3:
		var throwaway := PlayerScene.instantiate()
		add_child(throwaway)
		throwaway.queue_free()
	for i in CASES.size():
		_pairs.append(_spawn_pair(CASES[i], Vector3((i - CASES.size() * 0.5) * PAIR_SPACING, 0.0, 0.0)))


func _physics_process(_delta: float) -> void:
	_frame += 1
	if _frame == RUN_IN:
		for pair in _pairs:
			_hit(pair)
	elif _frame > RUN_IN and _frame <= RUN_IN + WATCH:
		for pair in _pairs:
			_watch(pair, &"c")
			_watch(pair, &"t")
	elif _frame > RUN_IN + WATCH:
		_report()
		get_tree().quit()


func _build_floor() -> StaticBody3D:
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	# Wide enough that nothing lands off the edge (LESSONS.md: judge a fall
	# on a floor that's really under it).
	box.size = Vector3(PAIR_SPACING * (CASES.size() + 2), 1.0, 200.0)
	shape.shape = box
	shape.position = Vector3(0.0, -0.5, 0.0)
	floor_body.add_child(shape)
	return floor_body


func _spawn_pair(spec: Array, base: Vector3) -> Dictionary:
	var run := Vector3.FORWARD.rotated(Vector3.UP, deg_to_rad(spec[1]))
	var from := run.rotated(Vector3.UP, -deg_to_rad(spec[3]))
	var carrier: PlayerController = PlayerScene.instantiate()
	carrier.team = Tuning.Team.HOME
	var tackler: PlayerController = PlayerScene.instantiate()
	tackler.team = Tuning.Team.AWAY
	add_child(carrier)
	add_child(tackler)
	var carrier_brain := ScriptedBrain.new()
	carrier_brain.direction = run if spec[2] > 0.0 else Vector3.ZERO
	carrier_brain.pace = spec[2]
	var tackler_brain := ScriptedBrain.new()
	tackler_brain.direction = -from
	tackler_brain.pace = spec[4]
	carrier.set_brain(carrier_brain)
	tackler.set_brain(tackler_brain)
	# Apart while they run in; _hit() puts them together.
	carrier.global_position = base + Vector3(0.0, 0.0, 60.0)
	tackler.global_position = base + Vector3(15.0, 0.0, 60.0)
	if spec[2] <= 0.0:
		carrier.rotation.y = atan2(-run.x, -run.z)
	return {"spec": spec, &"c": carrier, &"t": tackler, "from": from, "contact": base,
		"direction": Vector3.ZERO, "rows": {}}


## Both players where they meet, still at the pace and stride they ran in at,
## then the real connect, before either moves this frame (this node's
## physics runs before its children's).
func _hit(pair: Dictionary) -> void:
	var carrier: PlayerController = pair[&"c"]
	var tackler: PlayerController = pair[&"t"]
	var from: Vector3 = pair.from
	carrier.global_position = pair.contact
	tackler.global_position = (pair.contact as Vector3) + from * CONTACT_GAP
	match pair.spec[0]:
		&"lunge":
			var impact := TackleBalance.resolve(tackler.global_position,
				tackler._tackle_velocity(carrier, Tuning.TACKLE_LUNGE_SPEED), tackler.body_mass,
				carrier.global_position, carrier.velocity, carrier.body_mass,
				Tuning.TACKLE_RAGDOLL_MIN_BALANCE_LOSS, -carrier.global_transform.basis.z)
			pair.direction = impact.direction
			tackler._lunge_connect(carrier, impact, false)
		&"sling":
			var impact := TackleBalance.resolve(tackler.global_position,
				tackler._tackle_velocity(carrier, Tuning.TACKLE_SLIDE_STEP_SPEED), tackler.body_mass,
				carrier.global_position, carrier.velocity, carrier.body_mass, 0.0,
				-carrier.global_transform.basis.z)
			# Always the knockdown, whatever this hit's b would have been.
			impact.b = maxf(float(impact.b), Tuning.TACKLE_SLIDE_KNOCKDOWN_B)
			pair.direction = impact.direction
			tackler._slide_connect(carrier, impact, false)
		&"bump":
			tackler._bump_dash_direction = -from
			pair.direction = -from
			tackler._resolve_bump_contact(carrier, true)
	(carrier.brain() as ScriptedBrain).direction = Vector3.ZERO
	(tackler.brain() as ScriptedBrain).direction = Vector3.ZERO


func _watch(pair: Dictionary, tag: StringName) -> void:
	var player: PlayerController = pair[tag]
	var controller := player.ragdoll_controller()
	if controller == null or controller.ragdoll() == null:
		return
	var ragdoll := controller.ragdoll()
	var rows: Dictionary = pair.rows
	var key := String(tag) + "."
	if controller.phase() == PlayerRagdoll.Phase.FALLING:
		var frames := int(rows.get(key + "frames", 0)) + 1
		rows[key + "frames"] = frames
		var spin := ragdoll.peak_angular_speed()
		if frames <= START_FRAMES:
			_keep_max(rows, key + "start", spin)
		_keep_max(rows, key + "speed", ragdoll.peak_speed())
		_keep_max(rows, key + "spin", spin)
		var front := ragdoll.front_of("Hips")
		var up := ragdoll.up_of("Hips")
		for side in ["Left", "Right"]:
			var thigh := ragdoll.body(side + "UpperLeg").global_basis.y.normalized()
			_keep_max(rows, key + "hip_back", -rad_to_deg(atan2(thigh.dot(front), thigh.dot(-up))))
		var joint := ragdoll.joint_report()
		if float(joint.over) > float(rows.get(key + "joint_over", 0.0)):
			rows[key + "joint_over"] = float(joint.over)
			rows[key + "joint"] = "%s %.0f°" % [joint.bone, float(joint.angle)]
	elif controller.phase() == PlayerRagdoll.Phase.GETTING_UP and not rows.has(key + "landing"):
		rows[key + "landing"] = controller.last_landing.duplicate()


static func _keep_max(rows: Dictionary, key: String, value: float) -> void:
	rows[key] = maxf(float(rows.get(key, -INF)), value)


func _report() -> void:
	var totals := {}
	for pair in _pairs:
		var spec: Array = pair.spec
		var line := "%-5s %s from %3.0f°" % [spec[0], "running " if spec[2] > 0.0 else "standing", spec[3]]
		for tag: StringName in [&"c", &"t"]:
			line += " | " + _describe(pair, tag, totals)
		print(line)
	print("SUMMARY %s" % totals)


func _describe(pair: Dictionary, tag: StringName, totals: Dictionary) -> String:
	var rows: Dictionary = pair.rows
	var key := String(tag) + "."
	if not rows.has(key + "frames"):
		return "%s: no ragdoll" % tag
	var landing: Dictionary = rows.get(key + "landing", {})
	var moved := Vector3.ZERO
	if landing.has("hips"):
		moved = (landing.hips as Vector3) - (pair.contact as Vector3)
		moved.y = 0.0
	var line: Vector3 = pair.direction
	var down: bool = landing.get("down", false)
	totals[key + "down"] = int(totals.get(key + "down", 0)) + (1 if down else 0)
	totals[key + "falls"] = int(totals.get(key + "falls", 0)) + 1
	for stat in ["start", "spin", "hip_back", "joint_over"]:
		totals[key + stat + "_worst"] = snappedf(maxf(float(totals.get(key + stat + "_worst", 0.0)),
			float(rows.get(key + stat, 0.0))), 0.1)
	return "%s: %s along %.1f across %.1f %s t %.2f start %.0f peak %.1f/%.0f hip_back %.0f joint %s +%.0f" % [
		tag, "DOWN" if down else "up  ", moved.dot(line), moved.dot(Vector3.UP.cross(line)),
		"fd" if landing.get("face_down", false) else "fu", float(landing.get("time", -1.0)),
		float(rows.get(key + "start", 0.0)), float(rows.get(key + "speed", 0.0)),
		float(rows.get(key + "spin", 0.0)), float(rows.get(key + "hip_back", 0.0)),
		rows.get(key + "joint", "-"), float(rows.get(key + "joint_over", 0.0))]
