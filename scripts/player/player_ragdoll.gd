class_name PlayerRagdoll
extends RefCounted

## One player's active ragdoll in a live match (docs/MECHANICS_AUDIT.md §B4
## stages 2-5): the hand-off from animation to a PhysicsRagdoll when a
## tackle connects, the fall, and the hand-back to animation through a
## get-up. Owned and stepped by PlayerController (see _begin_ragdoll there);
## every gameplay number is in Tuning's "Active ragdoll tackles".
##
## Kept cheap on purpose:
## * Nothing is built until a player's first tackle — never all 36 up
##   front. The build waits Tuning.TACKLE_RAGDOLL_BUILD_FRAMES physics
##   frames before going rigid (LESSONS.md's same-frame construction race),
##   so the first hit on a player lands that many frames late; every later
##   one is immediate.
## * Between tackles the simulator is parked (PhysicsRagdoll.park): no body
##   follows the skeleton, nothing collides, nothing is simulated.
## * Only the players in the contact simulate — the target, and the tackler
##   too on a big enough hit.
##
## The phases:
##   FALLING    — physics owns the skeleton. The motors pull toward the pose
##                the animation had at contact, at strength 1 - b. The
##                player's CharacterBody3D follows the ragdoll's hips across
##                the ground (hips_ground_position), so gameplay position is
##                wherever the body actually ends up.
##   GETTING_UP — the bodies are put to sleep where they lie, the player is
##                turned and placed so the get-up clip's own lying pose sits
##                on the ragdoll's (yaw from the spine's line along the
##                ground, position from the hips), the clip starts from its
##                lying frame, and the simulator's influence ramps 1 -> 0 over
##                Tuning.TACKLE_RAGDOLL_GETUP_BLEND — physics pose fading into
##                the clip. A ragdoll that never went down (a stagger) does
##                the same into locomotion instead.
##   REACTING   — (2026-11-09) a knock that keeps the player on their feet:
##                only the upper body is simulated (PhysicsRagdoll's
##                "Upper-body reactions"), the legs and the player stay on
##                the animation and the controller, and nothing in gameplay
##                changes. Muscle tone drops by the hit's balance loss and
##                recovers over Tuning.CONTACT_REACT_RECOVER, then physics
##                fades back out over CONTACT_REACT_BLEND_OUT. is_active()
##                is false throughout: the player isn't ragdolled.
## Any teleport (a stoppage repositioning the player) or cancel() drops
## straight back to animation.

enum Phase { OFF, PENDING, FALLING, GETTING_UP, REACTING }

## How far the player's body may sit from the ragdoll's hips before it's
## taken as a teleport (a stoppage moved the player) rather than following.
const TELEPORT_DISTANCE := 3.0

var _player: CharacterBody3D
var _rig: HumanoidRig
var _animation: PlayerAnimation
var _ragdoll: PhysicsRagdoll
var _mass_kg := Tuning.PLAYER_DEFAULT_MASS_KG

var _phase := Phase.OFF
var _pending_frames := 0
var _hit := {}
var _push := Vector3.ZERO
var _push_left := 0.0
var _time := 0.0
var _blend := 0.0
var _getup_state: StringName = &""
## REACTING: the hit being taken (react()'s), how long it has run, and
## whether PENDING is waiting to start one rather than a fall.
var _reaction := {}
var _pending_reaction := false
var _react_time := 0.0
var _react_blend := 0.0
## A reaction being held open (sustain): its tone is capped here, -1 = not.
var _hold_tone := -1.0

## For headless checks and the lab: what the last hit was, and how the
## fall ended.
var last_hit := {}
var last_landing := {}


func _init(player: CharacterBody3D, rig: HumanoidRig, animation: PlayerAnimation) -> void:
	_player = player
	_rig = rig
	_animation = animation


## Whether this player can ragdoll at all: a 6thbuild-skeleton import (the
## procedural rig keeps the canned clips) and the feature switched on.
static func supported(rig: HumanoidRig) -> bool:
	return Tuning.TACKLE_RAGDOLL_ENABLED and rig != null and rig.is_imported() \
		and PhysicsRagdoll.supports(rig.skeleton())


## Whether physics owns the body (a fall or its get-up). A reaction isn't
## that: see is_reacting().
func is_active() -> bool:
	return _phase != Phase.OFF and not is_reacting()


## An upper-body reaction running (or its first build pending).
func is_reacting() -> bool:
	return _phase == Phase.REACTING or (_phase == Phase.PENDING and _pending_reaction)


func phase() -> Phase:
	return _phase


func ragdoll() -> PhysicsRagdoll:
	return _ragdoll


## Goes physical. `hit`: {"strength" 0-1, "impulse" (N·s, world), "bone",
## "contact_offset" (world, from that body's centre), "body_share" (of the
## push that moves the whole body — PhysicsRagdoll.apply_tackle_push),
## "velocity" (the player's own at contact), "mass_kg"}. Returns false if
## this rig can't ragdoll, so the caller plays its canned clip instead.
func begin(hit: Dictionary) -> bool:
	if not supported(_rig):
		return false
	if _phase == Phase.PENDING:
		# Still inside the first build's wait (a reaction's, or another hit's):
		# the fall takes the rest of it rather than starting a body built a
		# frame ago (LESSONS.md's same-frame construction race).
		_hit = hit
		last_hit = hit
		last_landing = {}
		_pending_reaction = false
		return true
	if _phase != Phase.OFF:
		cancel()
	_hit = hit
	last_hit = hit
	last_landing = {}
	if _ragdoll == null:
		if not _build(hit):
			return false
		_pending_reaction = false
		return true
	_go_rigid()
	return true


## An upper-body reaction (see the header's REACTING). `hit`: "impulse"
## (N·s, world), "bone" and "contact_offset" (as begin()'s), "tone" (0-1:
## muscle tone at the hit, 1 = none lost), "arms" (simulate the arms too —
## false for a ball carrier, whose arms hold the ball), "mass_kg". A
## reaction already running takes the new push on top, at the lower of the
## two tones, and starts its recovery again. Returns false when this rig
## can't, or physics already has the body.
func react(hit: Dictionary) -> bool:
	if not supported(_rig) or is_active():
		return false
	if is_reacting():
		_reaction.impulse = (_reaction.get("impulse", Vector3.ZERO) as Vector3) \
			+ (hit.get("impulse", Vector3.ZERO) as Vector3)
		_reaction.tone = minf(float(_reaction.get("tone", 1.0)), float(hit.get("tone", 1.0)))
		_reaction.bone = hit.get("bone", &"Chest")
		_reaction.contact_offset = hit.get("contact_offset", Vector3.ZERO)
		if _phase == Phase.REACTING:
			_react_time = 0.0
			_react_blend = 0.0
			_ragdoll.simulator.influence = 1.0
			_push = (hit.get("impulse", Vector3.ZERO) as Vector3) / Tuning.CONTACT_REACT_PUSH_DURATION
			_push_left = Tuning.CONTACT_REACT_PUSH_DURATION
		return true
	_reaction = hit.duplicate()
	if _ragdoll == null:
		if not _build(hit):
			return false
		_pending_reaction = true
		return true
	_start_reacting()
	return true


func _build(hit: Dictionary) -> bool:
	_mass_kg = float(hit.get("mass_kg", Tuning.PLAYER_DEFAULT_MASS_KG))
	_ragdoll = PhysicsRagdoll.new()
	if not _ragdoll.build(_rig.skeleton(), _mass_kg / _rest_mass()):
		_ragdoll = null
		return false
	_ragdoll.park()
	_phase = Phase.PENDING
	_pending_frames = Tuning.TACKLE_RAGDOLL_BUILD_FRAMES
	return true


## Drops straight back to animation, wherever the ragdoll is.
func cancel() -> void:
	if _ragdoll != null:
		_ragdoll.park()
	_phase = Phase.OFF
	_hold_tone = -1.0
	_pending_reaction = false
	_push_left = 0.0
	if _animation != null:
		_animation.ragdoll_active = false


## Call every physics frame while is_active(), before the player moves.
func step(delta: float) -> void:
	match _phase:
		Phase.PENDING:
			_pending_frames -= 1
			if _pending_frames <= 0:
				if _pending_reaction:
					_pending_reaction = false
					_start_reacting()
				else:
					_go_rigid()
		Phase.FALLING:
			_step_falling(delta)
		Phase.GETTING_UP:
			_step_getting_up(delta)
		Phase.REACTING:
			_step_reacting(delta)


## Where the player's body should be while FALLING: the hips, on the ground.
func hips_ground_position() -> Vector3:
	var hips := _ragdoll.body(&"Hips").global_position
	return Vector3(hips.x, _player.global_position.y, hips.z)


## Whether the player's body should follow the hips this frame (FALLING
## only — GETTING_UP has already placed it).
func is_falling() -> bool:
	return _phase == Phase.FALLING


func _go_rigid() -> void:
	_ragdoll.track_pose = bool(_hit.get("track", false))
	_ragdoll.capture_target_pose()
	_ragdoll.strength = clampf(float(_hit.get("strength", 0.0)), 0.0, 1.0)
	_ragdoll.support_share = float(_hit.get("support", PhysicsRagdoll.SUPPORT_SHARE))
	_ragdoll.tilt_from_feet = bool(_hit.get("tilt_from_feet", false))
	_ragdoll.start(_hit.get("velocity", Vector3.ZERO))
	_push = _hit.get("impulse", Vector3.ZERO) / Tuning.TACKLE_RAGDOLL_PUSH_DURATION
	_push_left = Tuning.TACKLE_RAGDOLL_PUSH_DURATION if _push != Vector3.ZERO else 0.0
	_time = 0.0
	_phase = Phase.FALLING
	if _animation != null:
		_animation.ragdoll_active = true


func _step_falling(delta: float) -> void:
	if _player.global_position.distance_to(hips_ground_position()) > TELEPORT_DISTANCE:
		cancel()
		return
	if _push_left > 0.0:
		var dt := minf(delta, _push_left)
		var bone: StringName = _hit.get("bone", &"Chest")
		var point := _ragdoll.body(bone).global_position + (_hit.get("contact_offset", Vector3.ZERO) as Vector3)
		_ragdoll.apply_tackle_push(bone, _push * dt, point, float(_hit.get("body_share", 0.0)))
		_push_left -= dt
	_ragdoll.step(delta)
	_time += delta
	var settled := _ragdoll.is_asleep() or _ragdoll.peak_speed() < Tuning.TACKLE_RAGDOLL_GETUP_SETTLED_SPEED
	# A hit can ask for a shorter fall ("max_time"): a stumble hands back to
	# animation while the body is still up, rather than waiting to settle.
	var max_time := float(_hit.get("max_time", Tuning.TACKLE_RAGDOLL_GETUP_MAX_TIME))
	if (_time >= minf(Tuning.TACKLE_RAGDOLL_GETUP_MIN_TIME, max_time) and settled) \
			or _time >= max_time:
		_begin_getup()


## See the header's GETTING_UP. Sets last_landing.
func _begin_getup() -> void:
	var hips := _ragdoll.body(&"Hips").global_position
	var chest := _ragdoll.body(&"Chest").global_position
	var down := _ragdoll.is_down()
	var face_down := (_ragdoll.front_of("Hips") + _ragdoll.front_of("Chest")).y < 0.0
	for pb: PhysicalBone3D in _ragdoll.bodies.values():
		PhysicsServer3D.body_set_state(pb.get_rid(), PhysicsServer3D.BODY_STATE_SLEEPING, true)

	var state: StringName = &"getup_face_down" if face_down else &"getup_face_up"
	var info := _animation.getup_info(state) if _animation != null and down else {}
	# Skeleton -> player-local: the rig node (height scale) and the
	# skeleton's own 180° import fix-up.
	var skel_to_player := _rig.transform * _rig.skeleton().transform
	var local_hips: Vector3
	var local_line: Vector3
	var world_line: Vector3
	if info.is_empty():
		# Standing (or no clip): face where the chest faces, hips where
		# they are.
		local_hips = skel_to_player * (_rest_hips())
		local_line = skel_to_player.basis * PhysicsRagdoll.SKELETON_FORWARD
		world_line = _ragdoll.front_of("Chest")
		state = &""
	else:
		local_hips = skel_to_player * (info.hips_position as Vector3)
		local_line = skel_to_player.basis * (info.hips_up as Vector3)
		world_line = chest - hips
	local_line.y = 0.0
	world_line.y = 0.0
	# The yaw that turns the clip's line (player-local) onto the ragdoll's.
	var yaw := _player.rotation.y
	if local_line.length_squared() > 1e-6 and world_line.length_squared() > 1e-6:
		yaw = local_line.normalized().signed_angle_to(world_line.normalized(), Vector3.UP)
	var basis := Basis(Vector3.UP, yaw)
	var offset := basis * local_hips
	var origin := Vector3(hips.x - offset.x, _player.global_position.y, hips.z - offset.z)

	_getup_state = state
	last_landing = {
		"hips": hips,
		"down": down,
		"face_down": face_down,
		"state": state,
		"origin": origin,
		"yaw": yaw,
		"time": _time,
		# The clip starts now and the blend rides its first moments, so the
		# player is back when the clip ends.
		"stun": maxf(float(info.get("remaining", 0.0)), Tuning.TACKLE_RAGDOLL_GETUP_BLEND),
	}
	# Duck-typed so the lab can drive one of these without a PlayerController.
	if _player.has_method(&"on_ragdoll_getup"):
		_player.call(&"on_ragdoll_getup", origin, yaw, float(last_landing.stun))
	if state != &"":
		_animation.play_getup(state)
	elif _animation != null:
		_animation.play_locomotion()
	_blend = 0.0
	_phase = Phase.GETTING_UP


## Eased, not linear: a straight ramp starts and stops the hand-over at full
## rate, so the body visibly jerks into motion at the start of the get-up and
## lands on the clip with a kink at the end.
func _step_getting_up(delta: float) -> void:
	_blend += delta
	var t := clampf(_blend / Tuning.TACKLE_RAGDOLL_GETUP_BLEND, 0.0, 1.0)
	_ragdoll.simulator.influence = 1.0 - smoothstep(0.0, 1.0, t)
	if t >= 1.0:
		cancel()


func _start_reacting() -> void:
	_ragdoll.track_pose = true
	_ragdoll.capture_target_pose()
	# The trunk starts at the velocity the body had before the contact
	# ("velocity"), not the capsule's after it: when the legs are stopped or
	# turned by the collision, the trunk carries on by its own momentum and
	# lurches over them until the follow brings it back. That's the inertial
	# half of the knock, and it's free; the push is only the other body's
	# contact on the chest.
	_ragdoll.carry_velocity = _reaction.get("velocity", _player.velocity)
	_apply_reaction_tone(0.0)
	_set_arms_loose(bool(_reaction.get("arms", true)))
	_ragdoll.start_partial(PhysicsRagdoll.UPPER_BODY)
	_push = (_reaction.get("impulse", Vector3.ZERO) as Vector3) / Tuning.CONTACT_REACT_PUSH_DURATION
	_push_left = Tuning.CONTACT_REACT_PUSH_DURATION if _push != Vector3.ZERO else 0.0
	_react_time = 0.0
	_react_blend = 0.0
	_phase = Phase.REACTING


## A carrier's arms hold the ball on full-strength motors, following the
## carry pose on the chest (see PhysicsRagdoll.TRUNK for why they're
## simulated at all); anyone else's hang on the floor motors.
func _set_arms_loose(loose: bool) -> void:
	_ragdoll.arm_motor_floor = PhysicsRagdoll.ARM_MOTOR_FLOOR if loose else 1.0
	_ragdoll.arm_follow = PhysicsRagdoll.ARM_FOLLOW if loose else Tuning.CONTACT_REACT_FOLLOW * 2.0


## Tone climbs from the hit's back to full over CONTACT_REACT_RECOVER,
## eased, and sets both the follow and the joint motors.
func _apply_reaction_tone(t: float) -> void:
	var hit_tone := clampf(float(_reaction.get("tone", 1.0)), 0.0, 1.0)
	var tone := lerpf(hit_tone, 1.0, smoothstep(0.0, Tuning.CONTACT_REACT_RECOVER, t))
	if _hold_tone >= 0.0:
		tone = minf(tone, _hold_tone)
	_ragdoll.follow = Tuning.CONTACT_REACT_FOLLOW * tone
	_ragdoll.strength = Tuning.CONTACT_REACT_MOTOR * tone


## See the header's REACTING.
func _step_reacting(delta: float) -> void:
	# A stoppage moved the player: the posed hips went with them, and the
	# trunk mustn't be dragged after them through the joint.
	if _ragdoll.body(&"Chest").global_position.distance_to(
			_ragdoll.animated_transform(&"Chest").origin) > TELEPORT_DISTANCE * 0.25:
		cancel()
		return
	_react_time += delta
	# Stepped after the player's move (PlayerController), so the animated
	# pose is already where it'll be when physics steps: nothing to lead by.
	_ragdoll.carry_velocity = Vector3.ZERO
	_apply_reaction_tone(_react_time)
	# The ball can change hands mid-knock (a contested mark spills off one
	# body into the other's arms). Duck-typed, as on_ragdoll_getup is.
	if _player.has_method(&"is_carrying"):
		_set_arms_loose(not bool(_player.call(&"is_carrying")))
	if _push_left > 0.0:
		var dt := minf(delta, _push_left)
		var bone: StringName = _reaction.get("bone", &"Chest")
		var pb := _ragdoll.body(bone)
		if pb != null:
			_ragdoll.apply_impact_at(bone, _push * dt,
				pb.global_position + (_reaction.get("contact_offset", Vector3.ZERO) as Vector3))
		_push_left -= dt
	_ragdoll.step(delta)
	if _react_time < Tuning.CONTACT_REACT_TIME:
		return
	if _react_blend == 0.0:
		_hand_back_lean()
	_react_blend += delta
	var t := clampf(_react_blend / Tuning.CONTACT_REACT_BLEND_OUT, 0.0, 1.0)
	_ragdoll.simulator.influence = 1.0 - smoothstep(0.0, 1.0, t)
	if t >= 1.0:
		cancel()


## Holds a running reaction open at no more than `tone` for as long as it's
## called every tick (a held-up wrestle): the trunk stays on physics past
## CONTACT_REACT_TIME. release() lets it recover and hand back as usual.
func sustain(tone: float) -> void:
	if _phase != Phase.REACTING:
		return
	_hold_tone = clampf(tone, 0.0, 1.0)
	_react_time = minf(_react_time, Tuning.CONTACT_REACT_RECOVER)
	_react_blend = 0.0
	_ragdoll.simulator.influence = 1.0


## Ends sustain(): tone climbs from where it was held, then the usual
## hand-back.
func release() -> void:
	if _hold_tone < 0.0:
		return
	if _phase == Phase.REACTING:
		_reaction.tone = minf(_hold_tone, reaction_tone())
		_react_time = 0.0
	_hold_tone = -1.0


## A steady contact on a reacting trunk, this tick's worth (N·s, world), on
## the chest `offset` from its centre: the force between two wrestling
## bodies, which a one-off knock's push can't carry.
func press(impulse: Vector3, offset: Vector3) -> void:
	if _phase != Phase.REACTING or impulse.length_squared() < 1e-8:
		return
	_ragdoll.apply_impact_at(&"Chest", impulse, _ragdoll.body(&"Chest").global_position + offset)


## The hand-back starts from the body's own lean, not upright: whatever tilt
## the trunk still has off the animation becomes the animation's own sway
## (PlayerAnimation.adopt_lean), which settles it from there, so physics
## fades into a pose that's already where the body is.
func _hand_back_lean() -> void:
	if _animation == null:
		return
	var up := _ragdoll.pose_offset(&"Chest").basis.orthonormalized() * Vector3.UP
	var basis := _player.global_basis.orthonormalized()
	_animation.adopt_lean(Vector2(rad_to_deg(asin(clampf(up.dot(basis.x), -1.0, 1.0))),
		rad_to_deg(asin(clampf(up.dot(-basis.z), -1.0, 1.0)))))


## For checks: the reaction's tone right now (1 = none lost), or -1 when
## none is running.
func reaction_tone() -> float:
	if _phase != Phase.REACTING:
		return -1.0
	return _ragdoll.follow / maxf(Tuning.CONTACT_REACT_FOLLOW, 0.0001)


func _rest_mass() -> float:
	var m := 0.0
	for spec: Dictionary in PhysicsRagdoll.BODIES:
		m += float(spec.mass)
	return m


func _rest_hips() -> Vector3:
	var skeleton := _rig.skeleton()
	return skeleton.get_bone_global_rest(skeleton.find_bone(&"Hips")).origin
