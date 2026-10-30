class_name TackleBalance
extends RefCounted

## How much a connected tackle takes a player's balance, and the push that
## goes with it — the bridge between the ML page's tackle model and the
## active ragdoll (docs/MECHANICS_AUDIT.md §B4, Tuning's "Active ragdoll
## tackles"). Used by PlayerController on a live Lunge connect and by the
## Physics Ragdoll Lab's TACKLE mode, so both run the same numbers.
##
## Balance loss b is the logistic tackle model's formula —
## σ(w_speed·speed + w_angle·angle + w_stamina·mass + bias) — with the
## weights trained on the ML page (LR sliders / GA, SAVE TO MATCHES) and
## read from WEIGHTS_PATH, falling back to TackleModel's defaults. The
## sandbox reads its output as P(break); here it's only used as a smooth
## 0-1 measure of how hard the hit was. The inputs are the real contact,
## each normalised 0-1 (see Tuning), not the sandbox's ordinal ranges.
## Every input favours the tackler (faster, squarer, heavier), so the live
## read is the other way round from the sandbox's: b is how much the hit
## wins, and p_break = 1 - b is the carrier's share — a hard square hit
## rarely breaks, a glancing touch usually does. PlayerController compares
## p_break with each tackle type's threshold (Tuning.TACKLE_*_BREAK_P) to
## decide whether a landed tackle holds. Evaluated, never rolled: the same
## hit always gives the same b and the same outcome (RULES_REFERENCE.md §3).

const WEIGHTS_PATH := "res://data/ml/tackle_weights.json"

## TackleModel's own defaults (scripts/dev/tackle_model.gd), for when no
## weights file has been saved yet.
const DEFAULT_WEIGHTS := {"w_speed": 6.0, "w_angle": 4.0, "w_stamina": 2.0, "bias": -5.6}

static var _weights := {}


static func weights() -> Dictionary:
	if _weights.is_empty():
		reload()
	return _weights


## Re-reads WEIGHTS_PATH (the ML page calls this after saving).
static func reload() -> void:
	_weights = DEFAULT_WEIGHTS.duplicate()
	if not FileAccess.file_exists(WEIGHTS_PATH):
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(WEIGHTS_PATH))
	if not parsed is Dictionary:
		push_warning("TackleBalance: %s isn't a JSON object, using defaults" % WEIGHTS_PATH)
		return
	for key: String in DEFAULT_WEIGHTS:
		if (parsed as Dictionary).has(key):
			_weights[key] = float(parsed[key])


static func save_weights(w_speed: float, w_angle: float, w_stamina: float, bias: float,
		source: String) -> Error:
	var file := FileAccess.open(WEIGHTS_PATH, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify({
		"w_speed": w_speed, "w_angle": w_angle, "w_stamina": w_stamina, "bias": bias,
		"inputs": "closing speed / squareness / tackler-to-carrier mass ratio, each 0-1 (TackleBalance)",
		"source": source,
	}, "\t"))
	file.close()
	reload()
	return OK


## The three numbers _resolve_tackle_contact has always judged a tackle on,
## for tackler -> target. closing_speed: relative velocity along the line
## between them, positive = the gap is shrinking. approach_angle (deg):
## between "target -> tackler" and the target's own heading — 0 in their
## path, 180 chasing from behind — 0 when the target is near-stationary.
static func contact_metrics(tackler_pos: Vector3, tackler_vel: Vector3,
		target_pos: Vector3, target_vel: Vector3) -> Dictionary:
	var to_target := target_pos - tackler_pos
	to_target.y = 0.0
	var dir := to_target.normalized() if to_target.length_squared() > 0.0001 else Vector3.ZERO
	var rel := tackler_vel - target_vel
	rel.y = 0.0
	var carrier := Vector3(target_vel.x, 0.0, target_vel.z)
	var carrier_speed := carrier.length()
	var angle := 0.0
	if carrier_speed > Tuning.PIVOT_SPEED_THRESHOLD and dir != Vector3.ZERO:
		angle = rad_to_deg((-dir).angle_to(carrier / carrier_speed))
	return {
		"direction": dir,
		"closing_speed": rel.dot(dir),
		"carrier_speed": carrier_speed,
		"approach_angle": angle,
		"relative_velocity": rel,
	}


## b in 0..1 — see the header.
static func balance_loss(closing_speed: float, approach_angle_deg: float, mass_ratio: float) -> float:
	var w := weights()
	var speed := clampf(closing_speed / Tuning.TACKLE_BALANCE_CLOSING_SPEED_MAX, 0.0, 1.0)
	var square := clampf(1.0 - approach_angle_deg / 180.0, 0.0, 1.0)
	var mass := clampf(mass_ratio * 0.5, 0.0, 1.0)
	var z: float = w.w_speed * speed + w.w_angle * square + w.w_stamina * mass + w.bias
	return 1.0 / (1.0 + exp(-z))


## Everything a connected tackle hands the ragdoll, tackler -> target:
## b (and raw_b / p_break before the floor), the push (impulse N·s, world),
## which body it lands on and where and how much of it moves the whole body
## (PhysicsRagdoll.apply_tackle_push), and the tackler's own share
## (tackler_b 0 = stays on their feet). `min_b` floors b
## (Tuning.TACKLE_RAGDOLL_MIN_BALANCE_LOSS on a live Lunge connect).
## `target_facing` (flat, world) stands in for the target's heading when
## they're near-stationary: the tackle gate treats any hit on a standing
## player as square (approach angle 0), which is right for whether it
## holds, but a standing player blindsided from behind is still hit from
## behind as far as their balance goes.
static func resolve(tackler_pos: Vector3, tackler_vel: Vector3, tackler_mass: float,
		target_pos: Vector3, target_vel: Vector3, target_mass: float, min_b := 0.0,
		target_facing := Vector3.ZERO) -> Dictionary:
	var m := contact_metrics(tackler_pos, tackler_vel, target_pos, target_vel)
	var angle: float = m.approach_angle
	target_facing.y = 0.0
	if m.carrier_speed <= Tuning.PIVOT_SPEED_THRESHOLD and target_facing.length_squared() > 0.0001 \
			and (m.direction as Vector3) != Vector3.ZERO:
		angle = rad_to_deg((-(m.direction as Vector3)).angle_to(target_facing.normalized()))
	var ratio := tackler_mass / maxf(target_mass, 1.0)
	var raw_b := balance_loss(maxf(m.closing_speed, 0.0), angle, ratio)
	# Whether it holds is read off the gate's own angle, not the facing one:
	# a standing player has no run to carry them out of a tackle, so one hit
	# from behind is no easier to break than one from in front — but it
	# does still knock them over the way it came (raw_b, the fall).
	var hold_b := balance_loss(maxf(m.closing_speed, 0.0), m.approach_angle, ratio)
	var b := maxf(raw_b, min_b)
	# Along the hit vector — the line from the tackler into the carrier —
	# which is the only way an impulse through the contact can push, and
	# the direction the closing speed below is measured along. It used to
	# be the relative velocity, which on a carrier running across a tackler
	# points mostly back down the carrier's own path: a hit from the side
	# knocked them backwards. Their own run isn't lost — PlayerRagdoll starts
	# every body at the carrier's velocity — the hit only adds to it.
	var flat: Vector3 = m.direction
	if flat == Vector3.ZERO:
		flat = Vector3(m.relative_velocity.x, 0.0, m.relative_velocity.z)
		flat = flat.normalized() if flat.length_squared() > 0.0001 else Vector3.FORWARD
	var push_dir := (flat + Vector3.DOWN * Tuning.TACKLE_RAGDOLL_DRAG_DOWN).normalized()
	# A wrap-up is an inelastic collision: the momentum it can change is the
	# pair's reduced mass times the closing speed, not the tackler's whole
	# momentum (which flung a light carrier 5 m in the lab).
	var reduced_mass := tackler_mass * target_mass / maxf(tackler_mass + target_mass, 1.0)
	var size := minf(reduced_mass * maxf(m.closing_speed, 0.0) * b * Tuning.TACKLE_RAGDOLL_IMPULSE_SCALE,
		Tuning.TACKLE_RAGDOLL_IMPULSE_MAX)
	var tackler_b := 0.0
	if b >= Tuning.TACKLE_RAGDOLL_TACKLER_MIN_B:
		tackler_b = b * Tuning.TACKLE_RAGDOLL_TACKLER_SHARE
	# The tackler goes down the way they were running — driving on through
	# the tackle — or into the carrier if they'd stopped: tackler_impulse is
	# that drive down into the turf, at the chest so it topples them rather
	# than shoving them along. Their bodies start at tackler_velocity, their
	# own less what the collision itself took out of them (the push without
	# SCALE's leg drive, which comes off the ground, not out of their
	# momentum). Started at their full run they ploughed into the carrier's
	# falling body, stopped dead at the chest while their legs ran on, and
	# sat down backwards — or swept the carrier's legs out from under them,
	# so the carrier fell back onto them.
	var travel := Vector3(tackler_vel.x, 0.0, tackler_vel.z)
	var tackler_dir := travel.normalized() if travel.length() > Tuning.PIVOT_SPEED_THRESHOLD else flat
	var collision := size / Tuning.TACKLE_RAGDOLL_IMPULSE_SCALE
	return {
		"b": b,
		"raw_b": raw_b,
		"p_break": 1.0 - hold_b,
		"closing_speed": m.closing_speed,
		"approach_angle": angle,
		"mass_ratio": ratio,
		"direction": flat,
		"impulse": push_dir * size,
		# Above the centre of mass, from whichever side: a push there tips
		# the body the way it's pushed. A low wrap from behind used to go on
		# the hips, which slid the pelvis forward under the torso and sat the
		# carrier down backwards onto the tackler.
		"bone": &"Chest",
		# World offset from the hit body's centre toward the tackler.
		"contact_offset": -flat * Tuning.TACKLE_RAGDOLL_CONTACT_SIDE_OFFSET,
		"body_share": Tuning.TACKLE_RAGDOLL_BODY_SHARE,
		"tackler_b": tackler_b,
		"tackler_direction": tackler_dir,
		"tackler_velocity": tackler_vel - flat * collision / maxf(tackler_mass, 1.0),
		"tackler_impulse": (tackler_dir + Vector3.DOWN * Tuning.TACKLE_RAGDOLL_DRAG_DOWN).normalized()
			* size * Tuning.TACKLE_RAGDOLL_TACKLER_DRIVE,
	}
