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
## Any teleport (a stoppage repositioning the player) or cancel() drops
## straight back to animation.

enum Phase { OFF, PENDING, FALLING, GETTING_UP }

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


func is_active() -> bool:
	return _phase != Phase.OFF


func phase() -> Phase:
	return _phase


func ragdoll() -> PhysicsRagdoll:
	return _ragdoll


## Goes physical. `hit`: {"strength" 0-1, "impulse" (N·s, world), "bone",
## "contact_offset" (world, from that body's centre), "velocity" (the
## player's own at contact), "mass_kg"}. Returns false if this rig can't
## ragdoll, so the caller plays its canned clip instead.
func begin(hit: Dictionary) -> bool:
	if not supported(_rig):
		return false
	if _phase != Phase.OFF:
		cancel()
	_hit = hit
	last_hit = hit
	last_landing = {}
	if _ragdoll == null:
		_mass_kg = float(hit.get("mass_kg", Tuning.PLAYER_DEFAULT_MASS_KG))
		_ragdoll = PhysicsRagdoll.new()
		if not _ragdoll.build(_rig.skeleton(), _mass_kg / _rest_mass()):
			_ragdoll = null
			return false
		_ragdoll.park()
		_phase = Phase.PENDING
		_pending_frames = Tuning.TACKLE_RAGDOLL_BUILD_FRAMES
		return true
	_go_rigid()
	return true


## Drops straight back to animation, wherever the ragdoll is.
func cancel() -> void:
	if _ragdoll != null:
		_ragdoll.park()
	_phase = Phase.OFF
	_push_left = 0.0
	if _animation != null:
		_animation.ragdoll_active = false


## Call every physics frame while is_active(), before the player moves.
func step(delta: float) -> void:
	match _phase:
		Phase.PENDING:
			_pending_frames -= 1
			if _pending_frames <= 0:
				_go_rigid()
		Phase.FALLING:
			_step_falling(delta)
		Phase.GETTING_UP:
			_step_getting_up(delta)


## Where the player's body should be while FALLING: the hips, on the ground.
func hips_ground_position() -> Vector3:
	var hips := _ragdoll.body(&"Hips").global_position
	return Vector3(hips.x, _player.global_position.y, hips.z)


## Whether the player's body should follow the hips this frame (FALLING
## only — GETTING_UP has already placed it).
func is_falling() -> bool:
	return _phase == Phase.FALLING


func _go_rigid() -> void:
	_ragdoll.capture_target_pose()
	_ragdoll.strength = clampf(float(_hit.get("strength", 0.0)), 0.0, 1.0)
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
		_ragdoll.apply_impact_at(bone, _push * dt, point)
		_push_left -= dt
	_ragdoll.step(delta)
	_time += delta
	var settled := _ragdoll.is_asleep() or _ragdoll.peak_speed() < Tuning.TACKLE_RAGDOLL_GETUP_SETTLED_SPEED
	if (_time >= Tuning.TACKLE_RAGDOLL_GETUP_MIN_TIME and settled) \
			or _time >= Tuning.TACKLE_RAGDOLL_GETUP_MAX_TIME:
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


func _step_getting_up(delta: float) -> void:
	_blend += delta
	var t := clampf(_blend / Tuning.TACKLE_RAGDOLL_GETUP_BLEND, 0.0, 1.0)
	_ragdoll.simulator.influence = 1.0 - t
	if t >= 1.0:
		cancel()


func _rest_mass() -> float:
	var m := 0.0
	for spec: Dictionary in PhysicsRagdoll.BODIES:
		m += float(spec.mass)
	return m


func _rest_hips() -> Vector3:
	var skeleton := _rig.skeleton()
	return skeleton.get_bone_global_rest(skeleton.find_bone(&"Hips")).origin
