class_name PhysicsRagdoll
extends RefCounted

## Stage 1 of docs/MECHANICS_AUDIT.md §B4 ("Physics Ragdoll Lab"): a purely
## PASSIVE ragdoll hung off an existing HumanoidRig's Skeleton3D. No motors,
## no target pose, no animation hand-off — the body is posed (kinematic,
## following the skeleton) until start() switches every bone to rigid, then
## gravity, contacts and the joint limits below decide everything.
##
## Built in code rather than with the editor's Skeleton3D > "Create Physical
## Skeleton" tool because HumanoidRig assembles 6thbuild at runtime (it
## hoists the glb's Skeleton3D into itself — see _try_build_from_import), so
## there is no saved scene for the editor tool to bake bodies into. This is
## that tool's own recipe (one PhysicalBone3D per bone under a
## PhysicalBoneSimulator3D, body_offset placing the shape along the bone,
## joint pivot at the bone's origin) with the parts it leaves as a stub
## filled in: per-bone shape types and sizes, masses, and real joint types
## and limits instead of its default pin joints.
##
## Written against 6thbuild's skeleton specifically (see BODIES): Hips is the
## root (there is no Root bone), "head" is lowercase, there is no Neck or
## Toes, and the clavicles (Left/RightShoulder) and hands get no body of
## their own — each follows its parent's body through its normal local pose,
## which keeps the body count at 14 and avoids tiny, jittery links.
## Every 6thbuild bone's rest +Y already points at its child (Blender bone
## convention), which is what lets "span" below be measured simply along the
## bone. The export (tools/blender/export_6thbuild.py) ships only the 18
## deform bones; the IK helpers (ikpole.*/iktarget.*) and the stray
## pelvis.001 root, whose weights are merged into Hips, never reach Godot.
##
## ── What the lab's headless checks turned up (60 Hz, default Jolt) ───
## * Ball joints are 6DOF, NOT PhysicalBone3D's CONE type. Under Jolt the
##   cone-twist joint blew the whole chain apart (hundreds of m/s, limbs
##   inverted) on any hit above ~250 N·s; the same limits as a 6DOF joint
##   held to ~18 m/s peak on a 700 N·s push. Swapping cones for unlimited
##   pins was also stable, which is what pinned it on the cone itself.
## * A jointed chain lying on the floor never fully comes to rest on its own
##   — the feet/forearms keep a ~0.3-0.7 rad/s contact buzz that stops Jolt
##   ever putting the island to sleep (a lone box the same size as a foot
##   sleeps fine; joint type, limits, self-collision and the simulator's
##   pose write-back were each ruled out). step() ramps damping up once
##   everything is slow (SETTLE_*), then puts it to sleep once nothing is
##   actually going anywhere (SLEEP_*); rounded feet (see BODIES) took the
##   worst of the buzz out in the first place.
## * Hard landings sink a light link (a foot squashed under the leg, a
##   forearm under the torso) 4-9 cm into the floor for a tick or two before
##   contact recovers — up to ~15 cm on the hardest 700 N·s hit; resting
##   penetration is ~1-1.5 cm, inside Jolt's 2 cm penetration slop.
##   A 120 Hz physics tick roughly halves both — a project-wide change, left
##   for whoever decides how this plugs into a match.

enum Joint { NONE, BALL, HINGE }

## glTF faces +Z, and HumanoidRig fixes that up by rotating the Skeleton3D
## NODE 180° (_fix_imported_forward_axis), never the bone data — so in
## skeleton space an imported character still faces +Z. Only used to pick a
## hinge's bend direction below.
const SKELETON_FORWARD := Vector3(0.0, 0.0, 1.0)

## Godot's hinge angle has the opposite sign to a right-hand rotation of the
## child about the hinge axis, so an anatomical "flex 0..140" maps to a
## Godot lower/upper of -140..0. Confirmed in the lab's headless check: a
## limp fall buckles the knees to +110..+140 (measured by joint_report()).
const HINGE_ANGLE_SIGN := -1.0

## Every principal moment of inertia is raised to at least this fraction of
## the body's largest one. A limb capsule's moment about its own long axis
## is tiny (a forearm's is ~1/13 of its end-over-end one), so an off-centre
## contact can spin it up to absurd rates in a tick. Standard ragdoll
## stabiliser; costs a little realism in limb roll. Its measured effect in
## the lab was small either way once the ball joints were 6DOF.
const INERTIA_FLOOR := 0.35

## Share of an apply_impact() that lands on the body actually hit; the rest
## is split by mass across the bodies jointed to it. A real contact covers
## more than one link, and putting it all on one light link is the
## hardest case for the joint solver.
const IMPACT_DIRECT_SHARE := 0.6

## "players" layer (project.godot layer_2). Masks world + players + ball so
## the body lands on the floor, non-adjacent limbs can't pass through each
## other, and a thrown ball hits it.
const COLLISION_LAYER := 1 << 1
const COLLISION_MASK := (1 << 0) | (1 << 1) | (1 << 2)

## Contact feel. Friction high enough that a fallen body stops rather than
## skates; no bounce. A little angular damping stands in for the joint
## friction a real body has. Unplaytested feel guesses.
const FRICTION := 0.9
const BOUNCE := 0.0
const LINEAR_DAMP := 0.1
const ANGULAR_DAMP := 1.2

## Settle assist (see header): once every body has stayed under both speeds
## for SETTLE_DELAY — and the fall is at least SETTLE_MIN_TIME old, so the
## first instant of a limp collapse from standing doesn't count — damping
## ramps to SETTLE_*_DAMP over SETTLE_RAMP. Any body speeding back up (a
## second hit, a slow roll off something) drops it straight back to normal.
## A passive physics tweak, not a motor: it only ever removes energy. The
## speeds tested are smoothed over SETTLE_SMOOTHING seconds — the contact
## buzz throws single-tick spin spikes past SETTLE_SPIN that would
## otherwise keep restarting the clock on a body that isn't going anywhere.
const SETTLE_SMOOTHING := 0.3
const SETTLE_SPEED := 0.4
const SETTLE_SPIN := 2.0
const SETTLE_MIN_TIME := 0.6
const SETTLE_DELAY := 0.3
const SETTLE_RAMP := 0.8
const SETTLE_LINEAR_DAMP := 3.0
const SETTLE_ANGULAR_DAMP := 10.0

## Damping alone doesn't finish the job: the leftover buzz is the solver not
## quite converging joint + contact each tick, not energy, so it survives any
## amount of damping and keeps every body just over Jolt's own 0.03 m/s
## sleep threshold (with the odd spike well past it). It's buzz in place,
## though — so once fully settle-damped, if no body has moved more than
## SLEEP_DRIFT or turned more than SLEEP_TURN across a whole SLEEP_WINDOW,
## the bodies are put to sleep directly: what Jolt would have done itself,
## and woken the same way (any contact or impulse).
const SLEEP_WINDOW := 0.5
const SLEEP_DRIFT := 0.015
const SLEEP_TURN := 4.0

## Per-body spec, parents before children.
##   bone   — Skeleton3D bone the body drives
##   tip    — bone whose origin gives the segment direction; "" = the bone's
##            own rest +Y
##   shape  — &"box" | &"capsule" | &"foot" (a capsule lying flat along the
##            ground heel to toe, rather than along the foot bone's own
##            tilted axis — rounded, not a box: a box foot pinned against the
##            ground at its ankle limit chattered between its corner contacts
##            at 2-3 rad/s and kept the whole body from settling)
##   size   — capsule/foot: x = radius. box: x = width, y = depth
##   span   — start/end along the segment from the bone's origin, metres
##            (a capsule's height includes its caps, so a 0..length span
##            ends flush with both joints)
##   mass   — kg; ~86 kg total, rough adult segment proportions
##   joint  — to the nearest ancestor bone that has a body
##   limits — BALL: (swing, twist) in degrees — swing is the per-axis limit
##            on both bend axes, twist about the bone itself. HINGE: (min,
##            max) in degrees, positive = the anatomical bend direction
##   flex   — HINGE only: skeleton-space direction the segment swings toward
##            when the joint bends (elbow forward, knee back, toes up)
const BODIES := [
	{"bone": "Hips", "tip": "Spine", "shape": &"box", "size": Vector2(0.34, 0.22),
		"span": Vector2(-0.13, 0.19), "mass": 12.0, "joint": Joint.NONE},
	{"bone": "Spine", "tip": "Chest", "shape": &"box", "size": Vector2(0.30, 0.20),
		"span": Vector2(0.0, 0.25), "mass": 10.0, "joint": Joint.BALL, "limits": Vector2(25.0, 20.0)},
	{"bone": "Chest", "tip": "head", "shape": &"box", "size": Vector2(0.36, 0.22),
		"span": Vector2(-0.02, 0.19), "mass": 17.0, "joint": Joint.BALL, "limits": Vector2(25.0, 20.0)},
	{"bone": "head", "tip": "", "shape": &"capsule", "size": Vector2(0.11, 0.0),
		"span": Vector2(0.0, 0.37), "mass": 6.0, "joint": Joint.BALL, "limits": Vector2(40.0, 50.0)},

	{"bone": "LeftUpperArm", "tip": "LeftLowerArm", "shape": &"capsule", "size": Vector2(0.06, 0.0),
		"span": Vector2(0.0, 0.374), "mass": 2.6, "joint": Joint.BALL, "limits": Vector2(75.0, 60.0)},
	{"bone": "LeftLowerArm", "tip": "LeftHand", "shape": &"capsule", "size": Vector2(0.05, 0.0),
		"span": Vector2(0.0, 0.445), "mass": 2.0, "joint": Joint.HINGE, "limits": Vector2(0.0, 140.0),
		"flex": SKELETON_FORWARD},
	{"bone": "RightUpperArm", "tip": "RightLowerArm", "shape": &"capsule", "size": Vector2(0.06, 0.0),
		"span": Vector2(0.0, 0.374), "mass": 2.6, "joint": Joint.BALL, "limits": Vector2(75.0, 60.0)},
	{"bone": "RightLowerArm", "tip": "RightHand", "shape": &"capsule", "size": Vector2(0.05, 0.0),
		"span": Vector2(0.0, 0.445), "mass": 2.0, "joint": Joint.HINGE, "limits": Vector2(0.0, 140.0),
		"flex": SKELETON_FORWARD},

	{"bone": "LeftUpperLeg", "tip": "LeftLowerLeg", "shape": &"capsule", "size": Vector2(0.085, 0.0),
		"span": Vector2(0.0, 0.484), "mass": 10.0, "joint": Joint.BALL, "limits": Vector2(60.0, 25.0)},
	{"bone": "LeftLowerLeg", "tip": "LeftFoot", "shape": &"capsule", "size": Vector2(0.065, 0.0),
		"span": Vector2(0.0, 0.521), "mass": 4.5, "joint": Joint.HINGE, "limits": Vector2(0.0, 140.0),
		"flex": -SKELETON_FORWARD},
	{"bone": "LeftFoot", "tip": "", "shape": &"foot", "size": Vector2(0.045, 0.0),
		"span": Vector2(-0.05, 0.34), "mass": 1.3, "joint": Joint.HINGE, "limits": Vector2(-40.0, 25.0),
		"flex": Vector3.UP},
	{"bone": "RightUpperLeg", "tip": "RightLowerLeg", "shape": &"capsule", "size": Vector2(0.085, 0.0),
		"span": Vector2(0.0, 0.484), "mass": 10.0, "joint": Joint.BALL, "limits": Vector2(60.0, 25.0)},
	{"bone": "RightLowerLeg", "tip": "RightFoot", "shape": &"capsule", "size": Vector2(0.065, 0.0),
		"span": Vector2(0.0, 0.521), "mass": 4.5, "joint": Joint.HINGE, "limits": Vector2(0.0, 140.0),
		"flex": -SKELETON_FORWARD},
	{"bone": "RightFoot", "tip": "", "shape": &"foot", "size": Vector2(0.045, 0.0),
		"span": Vector2(-0.05, 0.34), "mass": 1.3, "joint": Joint.HINGE, "limits": Vector2(-40.0, 25.0),
		"flex": Vector3.UP},
]

## Gap left under the sole at rest so the posed body doesn't start the
## simulation already in contact with (or a hair inside) the floor.
const FOOT_CLEARANCE := 0.008

var simulator: PhysicalBoneSimulator3D

## bone name -> PhysicalBone3D
var bodies := {}

var _skeleton: Skeleton3D

## One entry per jointed body, for joint_report(): the joint's axis and the
## segment direction in the child body's own frame, plus the same two
## vectors expressed in the parent body's frame at the moment the
## simulation started (the joint's zero).
var _joints: Array[Dictionary] = []

## bone name -> {"shape": Shape3D, "xform": Transform3D (shape in body space)}
var _shapes := {}

var _sim_time := 0.0
var _quiet_time := 0.0
var _settle_blend := 0.0
var _smoothed_speed := 0.0
var _smoothed_spin := 0.0
var _sleep_time := 0.0
var _sleep_snapshot := {}


## Builds every body under a new PhysicalBoneSimulator3D on `skeleton`.
## The skeleton must be at its rest pose. Returns false (and builds
## nothing) if a bone in BODIES is missing — i.e. not a 6thbuild skeleton.
func build(skeleton: Skeleton3D) -> bool:
	_skeleton = skeleton
	var missing: Array[String] = []
	for spec: Dictionary in BODIES:
		if skeleton.find_bone(spec.bone) < 0:
			missing.append(spec.bone)
	if not missing.is_empty():
		push_error("PhysicsRagdoll: skeleton has no bone(s) %s" % [missing])
		return false

	simulator = PhysicalBoneSimulator3D.new()
	simulator.name = "PhysicalBoneSimulator3D"
	skeleton.add_child(simulator)

	for spec: Dictionary in BODIES:
		var bone_rest := skeleton.get_bone_global_rest(skeleton.find_bone(spec.bone))
		var dir := _segment_dir(spec, bone_rest)
		var body_xform := _body_rest_transform(spec, bone_rest, dir)

		var pb := PhysicalBone3D.new()
		pb.name = "Physical_" + String(spec.bone)
		pb.bone_name = spec.bone
		pb.body_offset = bone_rest.affine_inverse() * body_xform
		pb.mass = spec.mass
		pb.friction = FRICTION
		pb.bounce = BOUNCE
		pb.linear_damp = LINEAR_DAMP
		pb.angular_damp = ANGULAR_DAMP
		pb.collision_layer = COLLISION_LAYER
		pb.collision_mask = COLLISION_MASK

		var shape := CollisionShape3D.new()
		shape.name = "CollisionShape3D"
		shape.shape = _make_shape(spec)
		pb.add_child(shape)
		_shapes[spec.bone] = {"shape": shape.shape, "xform": shape.transform}

		_configure_joint(pb, spec, body_xform, bone_rest.origin, dir)
		simulator.add_child(pb)
		bodies[spec.bone] = pb

	# Shapes deliberately overlap where they meet (a thigh's top cap sits
	# inside the pelvis box, a shin's end cap inside the foot box) so there's
	# no gap to snag on — so each body ignores its parent and grandparent
	# outright rather than relying on the joint to do it. A contact fighting
	# a joint every tick never settles.
	for bone: String in bodies:
		var parent := _parent_body(bone)
		if parent == null:
			continue
		(bodies[bone] as PhysicalBone3D).add_collision_exception_with(parent)
		var grandparent := _parent_body(String(parent.bone_name))
		if grandparent != null:
			(bodies[bone] as PhysicalBone3D).add_collision_exception_with(grandparent)
	return true


func is_simulating() -> bool:
	return simulator != null and simulator.is_simulating_physics()


## Goes limp: every body switches from following the skeleton to rigid.
func start() -> void:
	snap_to_pose()
	simulator.physical_bones_start_simulation()
	for bone: String in bodies:
		var pb: PhysicalBone3D = bodies[bone]
		pb.linear_velocity = Vector3.ZERO
		pb.angular_velocity = Vector3.ZERO
		# Not exposed on PhysicalBone3D itself, only on the server.
		PhysicsServer3D.body_set_param(pb.get_rid(), PhysicsServer3D.BODY_PARAM_INERTIA,
			_floored_inertia(bone))
	_sim_time = 0.0
	_quiet_time = 0.0
	_smoothed_speed = 0.0
	_smoothed_spin = 0.0
	_sleep_snapshot.clear()
	_set_settle_blend(0.0, true)
	_capture_joint_zero()


## Back to kinematic, and the skeleton back to its rest pose (the
## simulator's last written pose would otherwise stick).
func stop() -> void:
	simulator.physical_bones_stop_simulation()
	_skeleton.reset_bone_poses()
	_set_settle_blend(0.0, true)
	snap_to_pose()


## Call every physics tick while simulating — drives the settle assist.
func step(delta: float) -> void:
	if not is_simulating():
		return
	_sim_time += delta
	# A sleeping body keeps reporting its last velocity — nothing to read.
	if is_asleep():
		return
	# Smoothed on the way down only: a real hit (a ball arriving at a
	# sleeping, settle-damped body) has to drop the damping at once.
	var k := 1.0 - exp(-delta / SETTLE_SMOOTHING)
	var speed := peak_speed()
	var spin := peak_angular_speed()
	_smoothed_speed = speed if speed > SETTLE_SPEED * 2.0 else lerpf(_smoothed_speed, speed, k)
	_smoothed_spin = spin if spin > SETTLE_SPIN * 2.0 else lerpf(_smoothed_spin, spin, k)
	if _smoothed_speed < SETTLE_SPEED and _smoothed_spin < SETTLE_SPIN and _sim_time > SETTLE_MIN_TIME:
		_quiet_time += delta
	else:
		_quiet_time = 0.0
	_set_settle_blend(clampf((_quiet_time - SETTLE_DELAY) / SETTLE_RAMP, 0.0, 1.0))
	if _settle_blend < 1.0:
		_sleep_snapshot.clear()
		return
	if _sleep_snapshot.is_empty():
		_take_sleep_snapshot()
		return
	_sleep_time += delta
	if _sleep_time < SLEEP_WINDOW:
		return
	var still := true
	for bone: String in bodies:
		var now := (bodies[bone] as PhysicalBone3D).global_transform
		var then: Transform3D = _sleep_snapshot[bone]
		if now.origin.distance_to(then.origin) > SLEEP_DRIFT 				or rad_to_deg(now.basis.get_rotation_quaternion().angle_to(
					then.basis.get_rotation_quaternion())) > SLEEP_TURN:
			still = false
			break
	if still:
		for pb: PhysicalBone3D in bodies.values():
			PhysicsServer3D.body_set_state(pb.get_rid(), PhysicsServer3D.BODY_STATE_SLEEPING, true)
	_take_sleep_snapshot()


func _take_sleep_snapshot() -> void:
	_sleep_time = 0.0
	for bone: String in bodies:
		_sleep_snapshot[bone] = (bodies[bone] as PhysicalBone3D).global_transform


## True once every body is asleep (Jolt's or step()'s doing).
func is_asleep() -> bool:
	for pb: PhysicalBone3D in bodies.values():
		if not PhysicsServer3D.body_get_state(pb.get_rid(), PhysicsServer3D.BODY_STATE_SLEEPING):
			return false
	return true


## 0 = normal damping, 1 = fully settle-damped. For the lab's readout.
func settle_blend() -> float:
	return _settle_blend


## Puts every body exactly on its bone's current pose right now. The
## simulator does this itself for posed bodies, but only on its next
## modification pass — a start() in the same frame as a stop() would
## otherwise go rigid wherever the last fall left the bodies.
func snap_to_pose() -> void:
	var skeleton_xform := _skeleton.global_transform
	for bone: String in bodies:
		var pb: PhysicalBone3D = bodies[bone]
		pb.global_transform = skeleton_xform * _skeleton.get_bone_global_pose(
			_skeleton.find_bone(bone)) * pb.body_offset


## Impulse (N·s, world space) into `bone`, spread over its jointed
## neighbours per IMPACT_DIRECT_SHARE. Call once per physics tick for a
## contact that lasts longer than one.
func apply_impact(bone: StringName, impulse: Vector3) -> void:
	_quiet_time = 0.0
	_sleep_snapshot.clear()
	_set_settle_blend(0.0)
	var hit := body(bone)
	var neighbours: Array[PhysicalBone3D] = []
	var neighbour_mass := 0.0
	for other: String in bodies:
		var pb: PhysicalBone3D = bodies[other]
		if pb == hit:
			continue
		if _parent_body(other) == hit or _parent_body(String(bone)) == pb:
			neighbours.append(pb)
			neighbour_mass += pb.mass
	if neighbours.is_empty():
		hit.apply_central_impulse(impulse)
		return
	hit.apply_central_impulse(impulse * IMPACT_DIRECT_SHARE)
	for pb in neighbours:
		pb.apply_central_impulse(impulse * (1.0 - IMPACT_DIRECT_SHARE) * pb.mass / neighbour_mass)


func body(bone: StringName) -> PhysicalBone3D:
	return bodies.get(String(bone))


func total_mass() -> float:
	var m := 0.0
	for pb: PhysicalBone3D in bodies.values():
		m += pb.mass
	return m


## Mass-weighted centre of the whole body, world space.
func centre_of_mass() -> Vector3:
	var sum := Vector3.ZERO
	for pb: PhysicalBone3D in bodies.values():
		sum += pb.global_position * pb.mass
	return sum / total_mass()


func peak_speed() -> float:
	var peak := 0.0
	for pb: PhysicalBone3D in bodies.values():
		peak = maxf(peak, pb.linear_velocity.length())
	return peak


func peak_angular_speed() -> float:
	var peak := 0.0
	for pb: PhysicalBone3D in bodies.values():
		peak = maxf(peak, pb.angular_velocity.length())
	return peak


## Lowest point of any collision shape, world y. Negative means a shape is
## inside a y=0 floor by that much — Jolt keeps up to 2 cm of resting
## penetration (its penetration slop), anything well past that is a link
## being squashed through.
func lowest_point() -> float:
	var lowest := INF
	for bone: String in bodies:
		lowest = minf(lowest, lowest_point_of(bone))
	return lowest


func lowest_point_of(bone: String) -> float:
	var pb: PhysicalBone3D = bodies[bone]
	var info: Dictionary = _shapes[bone]
	var xf: Transform3D = pb.global_transform * (info.xform as Transform3D)
	var shape: Shape3D = info.shape
	if shape is CapsuleShape3D:
		var cap := shape as CapsuleShape3D
		var half := cap.height * 0.5 - cap.radius
		return minf((xf * Vector3(0.0, half, 0.0)).y, (xf * Vector3(0.0, -half, 0.0)).y) - cap.radius
	var lowest := INF
	var h := (shape as BoxShape3D).size * 0.5
	for corner in 8:
		var c := Vector3(h.x if corner & 1 else -h.x, h.y if corner & 2 else -h.y,
			h.z if corner & 4 else -h.z)
		lowest = minf(lowest, (xf * c).y)
	return lowest


## Worst joint-limit overshoot right now, in degrees, plus which joint and
## its current angle — {"bone", "over", "angle"}. BALL angle is the swing
## off the start direction, checked against the diagonal of the 6DOF
## limits' swing pyramid (two axes each at `swing` reach further than
## `swing` together); HINGE angle is the signed bend (positive = the spec's
## `flex` direction), so a knee reading -30 is bending backwards. Twist
## isn't measured. Only meaningful while simulating.
func joint_report() -> Dictionary:
	var worst := {"bone": "", "over": 0.0, "angle": 0.0}
	for j: Dictionary in _joints:
		var reading := _joint_reading(j)
		if reading.over > worst.over or worst.bone == "":
			worst = reading
	return worst


func joint_readings() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for j: Dictionary in _joints:
		out.append(_joint_reading(j))
	return out


## Translucent copies of every collision shape, parented to each body so they
## ride along. Returned so the caller can toggle them; built once.
func build_debug_meshes() -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.95, 0.35, 0.2, 0.45)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = true
	for bone: String in bodies:
		var info: Dictionary = _shapes[bone]
		var mesh: Mesh
		if info.shape is CapsuleShape3D:
			var capsule := CapsuleMesh.new()
			capsule.radius = (info.shape as CapsuleShape3D).radius
			capsule.height = (info.shape as CapsuleShape3D).height
			capsule.radial_segments = 12
			capsule.rings = 4
			mesh = capsule
		else:
			var box := BoxMesh.new()
			box.size = (info.shape as BoxShape3D).size
			mesh = box
		var instance := MeshInstance3D.new()
		instance.name = "DebugShape"
		instance.mesh = mesh
		instance.material_override = material
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		instance.transform = info.xform
		(bodies[bone] as PhysicalBone3D).add_child(instance)
		out.append(instance)
	return out


# ── Construction ─────────────────────────────────────────────────────

func _segment_dir(spec: Dictionary, bone_rest: Transform3D) -> Vector3:
	if spec.shape == &"foot":
		# Heel-to-toe along the ground: the foot bone's own axis, flattened.
		var flat := bone_rest.basis.y
		flat.y = 0.0
		return flat.normalized()
	if String(spec.tip) != "":
		var tip_rest := _skeleton.get_bone_global_rest(_skeleton.find_bone(spec.tip))
		return (tip_rest.origin - bone_rest.origin).normalized()
	return bone_rest.basis.y.normalized()


## Skeleton-space rest transform of the body itself: +Y along the segment
## (so a CapsuleShape3D, whose axis is Y, needs no rotation of its own),
## origin at the middle of `span`.
func _body_rest_transform(spec: Dictionary, bone_rest: Transform3D, dir: Vector3) -> Transform3D:
	var span: Vector2 = spec.span
	if spec.shape == &"foot":
		# Y = heel->toe (the capsule's own axis), Z = up.
		var basis := Basis(dir.cross(Vector3.UP).normalized(), dir, Vector3.UP)
		var radius: float = (spec.size as Vector2).x
		var origin := bone_rest.origin + dir * (span.x + span.y) * 0.5
		origin.y = FOOT_CLEARANCE + radius
		return Transform3D(basis.orthonormalized(), origin)
	# Keep the bone's own rest Z as the reference so a box's depth axis
	# stays front-to-back.
	var z := bone_rest.basis.z
	z = (z - dir * z.dot(dir)).normalized()
	var x := dir.cross(z).normalized()
	return Transform3D(Basis(x, dir, z), bone_rest.origin + dir * (span.x + span.y) * 0.5)


func _make_shape(spec: Dictionary) -> Shape3D:
	var span: Vector2 = spec.span
	var length := span.y - span.x
	var size: Vector2 = spec.size
	if spec.shape == &"capsule":
		var capsule := CapsuleShape3D.new()
		capsule.radius = size.x
		capsule.height = maxf(length, size.x * 2.0)
		return capsule
	if spec.shape == &"foot":
		var foot := CapsuleShape3D.new()
		foot.radius = size.x
		foot.height = length
		return foot
	var box := BoxShape3D.new()
	box.size = Vector3(size.x, length, size.y)
	return box


## The joint's pivot is the bone's origin; its frame lives in this body's
## own space (PhysicalBone3D.joint_offset). The 6DOF joint's X axis is the
## twist axis (along the bone), Y/Z the two bend axes; a hinge turns about Z.
func _configure_joint(pb: PhysicalBone3D, spec: Dictionary, body_xform: Transform3D,
		pivot: Vector3, dir: Vector3) -> void:
	var to_body := body_xform.affine_inverse()
	var origin := to_body * pivot
	var dir_body := (to_body.basis * dir).normalized()
	match spec.joint:
		Joint.BALL:
			var limits: Vector2 = spec.limits
			pb.joint_type = PhysicalBone3D.JOINT_TYPE_6DOF
			pb.joint_offset = Transform3D(_basis_with_x(dir_body), origin)
			# Linear limits default to enabled at 0 (locked) — only angular
			# needs setting.
			for axis: String in ["x", "y", "z"]:
				var span := limits.y if axis == "x" else limits.x
				pb.set("joint_constraints/%s/angular_limit_enabled" % axis, true)
				pb.set("joint_constraints/%s/angular_limit_upper" % axis, span)
				pb.set("joint_constraints/%s/angular_limit_lower" % axis, -span)
			_joints.append({"bone": spec.bone, "kind": Joint.BALL, "limits": limits,
				"axis_c": dir_body, "dir_c": dir_body})
		Joint.HINGE:
			var limits: Vector2 = spec.limits
			var flex: Vector3 = spec.flex
			# Right-hand rotation about dir x flex swings dir toward flex.
			var axis := dir.cross(flex).normalized()
			var z := (to_body.basis * axis).normalized()
			var x := (dir_body - z * dir_body.dot(z)).normalized()
			pb.joint_type = PhysicalBone3D.JOINT_TYPE_HINGE
			pb.joint_offset = Transform3D(Basis(x, z.cross(x), z), origin)
			var a := limits.x * HINGE_ANGLE_SIGN
			var b := limits.y * HINGE_ANGLE_SIGN
			pb.set(&"joint_constraints/angular_limit_enabled", true)
			pb.set(&"joint_constraints/angular_limit_lower", minf(a, b))
			pb.set(&"joint_constraints/angular_limit_upper", maxf(a, b))
			_joints.append({"bone": spec.bone, "kind": Joint.HINGE, "limits": limits,
				"axis_c": z, "dir_c": dir_body})
		_:
			pb.joint_type = PhysicalBone3D.JOINT_TYPE_NONE


func _basis_with_x(x: Vector3) -> Basis:
	var ref := Vector3.UP if absf(x.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
	var z := x.cross(ref).normalized()
	return Basis(x, z.cross(x), z)


## Principal moments in the body's own frame (shape axes = body axes),
## each raised to INERTIA_FLOOR of the largest.
func _floored_inertia(bone: String) -> Vector3:
	var pb: PhysicalBone3D = bodies[bone]
	var shape: Shape3D = _shapes[bone].shape
	var m := pb.mass
	var inertia: Vector3
	if shape is CapsuleShape3D:
		var r := (shape as CapsuleShape3D).radius
		var h := (shape as CapsuleShape3D).height
		var side := m * (3.0 * r * r + h * h) / 12.0
		inertia = Vector3(side, 0.5 * m * r * r, side)
	else:
		var e := (shape as BoxShape3D).size
		inertia = Vector3(e.y * e.y + e.z * e.z, e.x * e.x + e.z * e.z, e.x * e.x + e.y * e.y) * m / 12.0
	var floor_value := maxf(inertia.x, maxf(inertia.y, inertia.z)) * INERTIA_FLOOR
	return Vector3(maxf(inertia.x, floor_value), maxf(inertia.y, floor_value), maxf(inertia.z, floor_value))


func _set_settle_blend(blend: float, force := false) -> void:
	if is_equal_approx(blend, _settle_blend) and not force:
		return
	_settle_blend = blend
	var linear := lerpf(LINEAR_DAMP, SETTLE_LINEAR_DAMP, blend)
	var angular := lerpf(ANGULAR_DAMP, SETTLE_ANGULAR_DAMP, blend)
	for pb: PhysicalBone3D in bodies.values():
		pb.linear_damp = linear
		pb.angular_damp = angular


# ── Joint measurement ────────────────────────────────────────────────

func _parent_body(bone: String) -> PhysicalBone3D:
	var idx := _skeleton.get_bone_parent(_skeleton.find_bone(bone))
	while idx >= 0:
		var name := _skeleton.get_bone_name(idx)
		if bodies.has(name):
			return bodies[name]
		idx = _skeleton.get_bone_parent(idx)
	return null


func _capture_joint_zero() -> void:
	for j: Dictionary in _joints:
		var child: PhysicalBone3D = bodies[j.bone]
		var parent := _parent_body(j.bone)
		j.parent = parent
		var rel := parent.global_basis.orthonormalized().inverse() * child.global_basis.orthonormalized()
		j.axis_p = rel * (j.axis_c as Vector3)
		j.dir_p = rel * (j.dir_c as Vector3)


func _joint_reading(j: Dictionary) -> Dictionary:
	var child: PhysicalBone3D = bodies[j.bone]
	var parent: PhysicalBone3D = j.get("parent")
	if parent == null:
		return {"bone": j.bone, "over": 0.0, "angle": 0.0}
	var rel := parent.global_basis.orthonormalized().inverse() * child.global_basis.orthonormalized()
	var limits: Vector2 = j.limits
	var dir_now := rel * (j.dir_c as Vector3)
	var dir_zero: Vector3 = j.dir_p
	if j.kind == Joint.BALL:
		var swing := rad_to_deg(dir_zero.angle_to(dir_now))
		var c := cos(deg_to_rad(limits.x))
		var bound := rad_to_deg(acos(c * c))
		return {"bone": j.bone, "over": maxf(swing - bound, 0.0), "angle": swing}
	var axis: Vector3 = j.axis_p
	var flat := (dir_now - axis * dir_now.dot(axis)).normalized()
	var bend := rad_to_deg(dir_zero.signed_angle_to(flat, axis))
	return {"bone": j.bone, "over": maxf(maxf(limits.x - bend, bend - limits.y), 0.0), "angle": bend}
