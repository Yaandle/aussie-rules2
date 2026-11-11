class_name ArmIK
extends RefCounted

## Two-bone arm IK on a live Skeleton3D (2026-11-11, fable_pass_1 Phase 2
## step 4): puts one wrist on a target point, the elbow bent toward a pole,
## with the same elbow fit as tools/blender/author_6thbuild_clips.py's
## solve_arm(hinge=True). The elbow is swivelled about the shoulder-to-wrist
## line and the upper arm rolled, searched not solved, so the forearm bends
## about PhysicsRagdoll's elbow hinge (rest forearm x SKELETON_FORWARD,
## fixed in the upper arm). A forearm bent about any other axis is snapped
## onto the hinge in one tick when physics takes the arm (LESSONS:
## "Animated poses must stay inside the ragdoll's joint limits").
##
## It's a solver with a target point and nothing else: PlayerAnimation aims
## it at the other body's chest during a knock, and the partial ragdoll's
## arm motors follow the animated pose, so that is their target too. A
## "hands on a wall" reach is the same call with a raycast's hit point.
## Visual only: gameplay never reads the pose.

const SWIVEL_MAX := 20.0      ## deg, as HINGE_SWIVEL_MAX
const ROLL_TWIST_MAX := 58.0  ## deg, as HINGE_ROLL_TWIST_MAX
const SWIVEL_COST := 0.15     ## as HINGE_SWIVEL_COST


## Turns `upper` and its child `lower` (bone indices; `hand` is the wrist
## bone) so the wrist reaches `target` (skeleton space), elbow toward
## `pole` (a skeleton-space direction from the shoulder), blended in by
## `weight` (0-1) from the pose they have. Returns the reached wrist.
static func solve(skeleton: Skeleton3D, upper: int, lower: int, hand: int,
		target: Vector3, pole: Vector3, weight := 1.0) -> Vector3:
	var ua := skeleton.get_bone_global_pose(upper)
	var la := skeleton.get_bone_global_pose(lower)
	var hd := skeleton.get_bone_global_pose(hand)
	var s := ua.origin
	var l1 := la.origin.distance_to(s)
	var l2 := hd.origin.distance_to(la.origin)
	var to_t := target - s
	if l1 < 1e-4 or l2 < 1e-4 or to_t.length_squared() < 1e-6:
		return hd.origin
	var d := clampf(to_t.length(), absf(l1 - l2) + 0.02, l1 + l2 - 0.004)
	var u := to_t.normalized()
	var v := pole - u * pole.dot(u)
	if v.length_squared() < 1e-8:
		v = u.cross(Vector3.UP if absf(u.y) < 0.9 else Vector3.RIGHT)
	v = v.normalized()
	var a := (l1 * l1 - l2 * l2 + d * d) / (2.0 * d)
	var h := sqrt(maxf(l1 * l1 - a * a, 0.0))
	var t := s + u * d

	# The hinge, fixed in the upper arm's frame (from the rest pose).
	var ua_rest := skeleton.get_bone_global_rest(upper).basis.get_rotation_quaternion()
	var rest_dir := (skeleton.get_bone_global_rest(hand).origin
		- skeleton.get_bone_global_rest(lower).origin).normalized()
	var axis_local := ua_rest.inverse() * rest_dir.cross(PhysicsRagdoll.SKELETON_FORWARD).normalized()
	var rest_la := ua_rest.inverse() * rest_dir
	var q0 := ua.basis.get_rotation_quaternion()
	var y0 := (la.origin - s).normalized()

	var best := [INF, 0.0, 0.0]
	for pass_i in 2:
		var sw0: float = best[1]
		var ro0: float = best[2]
		var sw_range := range(-int(SWIVEL_MAX), int(SWIVEL_MAX) + 1, 5) if pass_i == 0 else range(-5, 6)
		for sw_i in sw_range:
			var swivel: float = float(sw_i) if pass_i == 0 else sw0 + sw_i * 0.5
			var e := s + u * a + (Quaternion(u, deg_to_rad(swivel)) * v) * h
			var qd := Quaternion(y0, (e - s).normalized()) * q0
			var w := (e - s).normalized()
			var dd := (t - e).normalized()
			var roll_range := range(-60, 61, 4) if pass_i == 0 else range(-8, 9)
			for ro_i in roll_range:
				var roll: float = float(ro_i) if pass_i == 0 else ro0 + ro_i * 0.5
				var q := Quaternion(w, deg_to_rad(roll)) * qd
				var axis := q * axis_local
				var cost := absf(90.0 - rad_to_deg(axis.angle_to(dd)))
				if (q * rest_la).cross(dd).dot(axis) < -0.05:
					cost += 30.0
				cost += maxf(0.0, absf(roll) - ROLL_TWIST_MAX) + SWIVEL_COST * absf(swivel)
				if cost < best[0]:
					best = [cost, swivel, roll]
	var elbow := s + u * a + (Quaternion(u, deg_to_rad(best[1])) * v) * h
	var w_dir := (elbow - s).normalized()
	var ua_new := Quaternion(w_dir, deg_to_rad(best[2])) * Quaternion(y0, w_dir) * q0
	ua_new = q0.slerp(ua_new, weight)
	# The forearm as the new upper arm carries it, then turned onto the wrist.
	var carry := ua_new * q0.inverse()
	var la_rot := carry * la.basis.get_rotation_quaternion()
	var elbow_now := s + carry * (la.origin - s)
	var fore_now := carry * (hd.origin - la.origin).normalized()
	var la_target := Quaternion(fore_now, (t - elbow_now).normalized()) * la_rot
	la_rot = la_rot.slerp(la_target, weight)
	_set_global_rotation(skeleton, upper, ua_new)
	_set_global_rotation(skeleton, lower, la_rot)
	return elbow_now + la_rot * (la.basis.get_rotation_quaternion().inverse() * (hd.origin - la.origin))


static func _set_global_rotation(skeleton: Skeleton3D, bone: int, rot: Quaternion) -> void:
	var parent := skeleton.get_bone_parent(bone)
	var parent_rot := skeleton.get_bone_global_pose(parent).basis.get_rotation_quaternion() \
		if parent >= 0 else Quaternion.IDENTITY
	skeleton.set_bone_pose_rotation(bone, (parent_rot.inverse() * rot).normalized())
