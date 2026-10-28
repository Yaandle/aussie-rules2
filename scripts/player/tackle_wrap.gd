class_name TackleWrap
extends RefCounted

## A held Lunge's arms round the carrier, for the fall. Playtest 2026-10-27:
## "x tackle does not hug the tackled player enough, the arms should wrap
## around the model and the two bodies fall down/ragdoll together with the
## tackling player holding onto tackled player as they fall down." Both
## players are ragdolls by now (PlayerController._lunge_connect); this puts
## the tackler's arms round the carrier's waist and keeps them there until
## either one starts to get up. Owned and stepped by the tackler's
## PlayerController. Every number is in Tuning's "Tackle wrap".
##
## Three parts, each tick:
## * The reach. Each arm is solved as a two-bone IK chain from its shoulder
##   to a grip point, elbow out to the side, and the tackler's own joint
##   motors swing the upper arm and forearm onto it (PhysicsRagdoll.aim_dirs,
##   at TACKLE_WRAP_ARM_STRENGTH). The motors are sized by each link's own
##   inertia, so they move an arm quickly. A pull at the wrist alone didn't:
##   it treated a 2 kg forearm as free when it's jointed to the whole body,
##   and closed on the carrier at ~1.5 m/s while they went down in 0.4 s.
## * The grip. A pull from the wrist to its grip point, PhysicsRagdoll's
##   motor recipe applied to a point: a velocity servo asking for a closing
##   speed proportional to the gap, closing TACKLE_WRAP_GAIN (< 1) of the
##   shortfall a tick, so it can't overshoot, capped at the grip force. Equal
##   and opposite, so the pair's momentum is only what the hit gave it. Not a
##   Joint3D: one made mid-fall between two separately simulated chains
##   snaps to its anchor on the first tick, the same violent correction that
##   blew CONE joints apart under Jolt (LESSONS.md).
## * The hug. A one-sided pull that only ever draws the two chests together.
##
## Each grip is beside the carrier's waist on that arm's side first, then
## behind it once the wrist is level with the middle. Straight at the back,
## the arm drove into the carrier's stomach and stuck: their bodies collide
## (PhysicsRagdoll's "ragdoll" layer), which is what makes the arms go round
## rather than through. The points are kept in the waist body's own frame,
## so they turn with the carrier as they go down.

enum Phase { WAITING, HOLDING, DONE }

const WAIST := &"Spine"
const CHEST := &"Chest"
## forearm -> its upper arm.
const ARMS := {&"LeftLowerArm": &"LeftUpperArm", &"RightLowerArm": &"RightUpperArm"}

var _tackler: PlayerRagdoll
var _target: PlayerRagdoll
var _phase := Phase.WAITING
var _time := 0.0
var _down_time := 0.0

## Per forearm: {"side", "back" (points), "out" (direction)}, all in the
## waist body's frame.
var _grips := {}
## The tackler -> carrier line at the bind, in the waist body's frame.
var _line_local := Vector3.ZERO

## For headless checks: each wrist's gap to its grip, and the chest gap,
## last tick (m); and how long it's held.
var last_gaps := {}
var held_time := 0.0


func _init(tackler: PlayerRagdoll, target: PlayerRagdoll) -> void:
	_tackler = tackler
	_target = target


func is_done() -> bool:
	return _phase == Phase.DONE


func phase() -> Phase:
	return _phase


## Call every physics tick from the tackler's PlayerController, after its
## ragdoll has stepped.
func step(delta: float) -> void:
	match _phase:
		Phase.WAITING:
			# Either ragdoll may still be building (PlayerRagdoll.PENDING).
			if not _both(PlayerRagdoll.Phase.FALLING):
				if not _tackler.is_active() or not _target.is_active():
					_phase = Phase.DONE
				return
			_bind()
			_phase = Phase.HOLDING
			_hold(delta)
		Phase.HOLDING:
			_time += delta
			held_time = _time
			# Held through the fall, then let go once they're both lying
			# there: the grip kept the pair from settling, which held the
			# get-up off to TACKLE_RAGDOLL_GETUP_MAX_TIME.
			var both_down := _tackler.ragdoll().is_down() and _target.ragdoll().is_down()
			_down_time = _down_time + delta if both_down else 0.0
			if not _both(PlayerRagdoll.Phase.FALLING) or _time > Tuning.TACKLE_WRAP_MAX_TIME \
					or _down_time > Tuning.TACKLE_WRAP_HOLD_DOWN_TIME:
				release()
				return
			_hold(delta)


## Lets go: the tackler's arms go back to their own motors and reflexes.
func release() -> void:
	if _phase == Phase.HOLDING and _tackler.ragdoll() != null:
		_tackler.ragdoll().aim_dirs.clear()
	_phase = Phase.DONE


func _both(p: PlayerRagdoll.Phase) -> bool:
	return _tackler.phase() == p and _target.phase() == p


func _bind() -> void:
	var tackler := _tackler.ragdoll()
	var target := _target.ragdoll()
	var waist := target.body(WAIST)
	var to_waist := waist.global_transform.affine_inverse()
	var line := waist.global_position - tackler.body(CHEST).global_position
	line.y = 0.0
	line = line.normalized() if line.length_squared() > 0.0001 else -tackler.front_of("Chest")
	var left := Vector3.UP.cross(line).normalized()
	var scale := target.rig_scale()
	var radius := Tuning.TACKLE_WRAP_TORSO_RADIUS * scale
	var centre := waist.global_position
	# Whichever arm's shoulder is further to the tackler's left takes the
	# left side, so it doesn't hang on which way the rig names its arms.
	var forearms: Array = ARMS.keys()
	var a := tackler.segment_root(ARMS[forearms[0]])
	var b := tackler.segment_root(ARMS[forearms[1]])
	var a_left := (a - b).dot(left) >= 0.0
	for i in forearms.size():
		var on_left := a_left if i == 0 else not a_left
		var out := left if on_left else -left
		_grips[forearms[i]] = {
			"side": to_waist * (centre + out * (radius + Tuning.TACKLE_WRAP_SIDE_MARGIN * scale)),
			"back": to_waist * (centre + line * radius + out * Tuning.TACKLE_WRAP_BACK_SPREAD * scale),
			"out": (to_waist.basis * out).normalized(),
		}
	_line_local = (to_waist.basis * line).normalized()
	tackler.aim_strength = Tuning.TACKLE_WRAP_ARM_STRENGTH


func _hold(delta: float) -> void:
	var tackler := _tackler.ragdoll()
	var target := _target.ragdoll()
	var waist := target.body(WAIST)
	var xf := waist.global_transform
	var line := (xf.basis * _line_local).normalized()
	# The grip comes on over TACKLE_WRAP_GRIP_RAMP. At the bind the wrist is
	# still moving with the tackler's run and arm swing, up to the whole
	# closing speed off the carrier's waist, and a full-strength servo
	# cancelled that in one tick at the wrist: the arms whipped round at
	# 45-105 rad/s for a frame (measured) before the reach even began.
	var cap := Tuning.TACKLE_WRAP_MAX_FORCE * delta \
		* smoothstep(0.0, Tuning.TACKLE_WRAP_GRIP_RAMP, _time)
	var margin := Tuning.TACKLE_WRAP_SIDE_MARGIN * target.rig_scale()
	for forearm: StringName in _grips:
		var upper: StringName = ARMS[forearm]
		var grip: Dictionary = _grips[forearm]
		var wrist := tackler.segment_tip(forearm)
		# Once round, it stays round: flicking back to the side point when a
		# wrist slipped had the arm thrashing between the two at 14 m/s.
		if not grip.get("round", false) and (wrist - xf.origin).dot(line) > -margin:
			grip["round"] = true
		var goal: Vector3 = xf * (grip.back if grip.get("round", false) else grip.side)
		last_gaps[forearm] = wrist.distance_to(goal)
		# On the ground the reach is done and the grip just holds: the
		# point behind the carrier is under them by then, in the turf, and
		# the motors driving at it thrashed the arm against the ground.
		if tackler.is_down():
			tackler.aim_dirs.erase(String(upper))
			tackler.aim_dirs.erase(String(forearm))
		else:
			_aim_arm(tackler, upper, forearm, goal, (xf.basis * (grip.out as Vector3)).normalized())
		var fore := tackler.body(forearm)
		# Down, the grip only holds what it has. A wrist pinned between the
		# bodies and the turf can't close the last few centimetres, and a
		# full-strength pull at it buzzed the forearm at 8-12 m/s.
		var down := tackler.is_down()
		var slack := Tuning.TACKLE_WRAP_DOWN_DEADZONE * target.rig_scale() if down else 0.0
		var j := _servo(wrist, goal, tackler.point_velocity(forearm, wrist), target.point_velocity(WAIST, goal),
			1.0 / (1.0 / (fore.mass + tackler.body(upper).mass) + 1.0 / waist.mass),
			cap * (Tuning.TACKLE_WRAP_DOWN_GRIP if down else 1.0), slack)
		fore.apply_impulse(j, wrist - fore.global_position)
		waist.apply_impulse(-j, goal - waist.global_position)
	# The hug: only ever draws the chests together, never shoves them apart.
	var chest_t := tackler.body(CHEST)
	var chest_c := target.body(CHEST)
	var gap := chest_c.global_position - chest_t.global_position
	last_gaps[&"chest"] = gap.length()
	var reach := Tuning.TACKLE_WRAP_HUG_DISTANCE * target.rig_scale()
	if gap.length() > reach:
		var goal := chest_t.global_position + gap.normalized() * (gap.length() - reach)
		var j := _servo(chest_t.global_position, goal, chest_t.linear_velocity, chest_c.linear_velocity,
			1.0 / (1.0 / chest_t.mass + 1.0 / chest_c.mass), cap)
		chest_t.apply_central_impulse(j)
		chest_c.apply_central_impulse(-j)


## Two-bone IK from the shoulder to `goal`, elbow toward `out` and a little
## down; hands the two segment directions to the arm motors.
static func _aim_arm(rd: PhysicsRagdoll, upper: StringName, fore: StringName, goal: Vector3,
		out: Vector3) -> void:
	var shoulder := rd.segment_root(upper)
	var l1 := rd.segment_length(upper)
	var l2 := rd.segment_length(fore)
	var to := goal - shoulder
	if to.length_squared() < 1e-6:
		return
	var u := to.normalized()
	var d := clampf(to.length(), absf(l1 - l2) + 0.02, l1 + l2 - 0.01)
	var pole := out + Vector3.DOWN * 0.5
	var v := pole - u * pole.dot(u)
	v = v.normalized() if v.length_squared() > 1e-6 else u.cross(Vector3.UP).normalized()
	var a := (l1 * l1 - l2 * l2 + d * d) / (2.0 * d)
	var h := sqrt(maxf(l1 * l1 - a * a, 0.0))
	var elbow := shoulder + u * a + v * h
	rd.aim_dirs[String(upper)] = (elbow - shoulder).normalized()
	rd.aim_dirs[String(fore)] = (shoulder + u * d - elbow).normalized()


## The impulse on the moving point (the other gets minus it) that closes
## TACKLE_WRAP_GAIN of the gap between the closing speed asked for and the
## one it has — see the header. Inside `slack` of the goal it asks for no
## closing at all and only damps the two points' relative motion.
static func _servo(point: Vector3, goal: Vector3, point_vel: Vector3, goal_vel: Vector3,
		reduced_mass: float, cap: float, slack := 0.0) -> Vector3:
	var gap := goal - point
	var want := gap * Tuning.TACKLE_WRAP_RATE if gap.length() > slack else Vector3.ZERO
	if want.length() > Tuning.TACKLE_WRAP_MAX_SPEED:
		want = want.normalized() * Tuning.TACKLE_WRAP_MAX_SPEED
	var j := (want - (point_vel - goal_vel)) * Tuning.TACKLE_WRAP_GAIN * reduced_mass
	return j.limit_length(cap)
