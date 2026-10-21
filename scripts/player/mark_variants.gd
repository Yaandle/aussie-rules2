class_name MarkVariants
extends RefCounted

## Situational marking variants, generated at load on top of an imported
## character's own Blender-authored mark clips (6thbuild: tools/blender/
## author_6thbuild_clips.py). Madden's catch types are the design language —
## Safe = possession/chest mark, Running = catch in stride on the lead,
## Aggressive = high-point/pack mark — and each variant is the same base clip
## bent toward a situation PlayerAnimation picks from the catch's context
## (_select_mark_state): ball height at contact, the flight's direction
## against the player's facing, gait, and whether an opponent is close.
##
## REST-AWARE, NEVER REST-OVERWRITING: this is the reason the old procedural
## mark clips broke on 6thbuild (they wrote absolute local rotations meant
## for identity rests). Everything here is a delta on the base clip's own
## sampled pose:
## * a torso/head/clavicle offset R is written in the character's frame and
##   applied as local = base_local * G^-1 R G (G = the bone's global rest
##   rotation) — "rotate this segment by R, carried by its parent", the same
##   convention the Blender authoring script uses;
## * hands are re-placed by two-bone IK (an offset from where the base clip
##   had the wrist, or an absolute point), each arm bone swung by the
##   shortest arc from the base pose so twist stays continuous;
## * the legs are re-solved after any hips/torso change so the feet stay on
##   the base clip's own ankle path — a lowered pelvis bends the knees rather
##   than sinking the feet through the turf (PlayerAnimation's ground clamp
##   would otherwise lift the whole rig back up and undo the offset).
##
## Skeleton space (glTF, before HumanoidRig's 180° node turn): +Z forward,
## +Y up, +X the character's left. P(left, fwd, up) builds points in those
## terms.
##
## The tier, reach and timing resolution in PlayerController never reads any
## of this: a variant is chosen after the catch has already been decided
## (Safe/Running) or once the leap is already committed (Aggressive), and
## only changes what the body looks like doing it.
##
## RAGDOLL HAND-OFF CANDIDATES (MECHANICS_AUDIT §B4 stage 2, not built):
## mark_safe_contested at its contact key (braced, both arms committed) and
## mark_aggressive_offbalance_* from contact to ~0.6 s (airborne, balance
## already gone — the moment a hard contested landing would hand the body
## to physics).

const SKELETON := "Skeleton3D"

## Bones a rig needs for any of this to apply — 6thbuild's 18. A rig
## without them (the procedural one, the umpire) just keeps its base clips;
## PlayerAnimation falls back to the base state whenever a variant is
## missing from the library.
const REQUIRED_BONES: Array[String] = ["Hips", "Spine", "Chest", "head",
	"LeftShoulder", "LeftUpperArm", "LeftLowerArm", "LeftHand",
	"RightShoulder", "RightUpperArm", "RightLowerArm", "RightHand",
	"LeftUpperLeg", "LeftLowerLeg", "LeftFoot",
	"RightUpperLeg", "RightLowerLeg", "RightFoot"]

## Baked by scripts/dev/mark_landing_bake.gd from the passive Physics
## Ragdoll: how 6thbuild's trunk and legs actually respond, in the air, to a
## push at the chest from its right. The off-balance landing layers it on
## after contact (mirrored for a push from the left). Optional — without it
## the variant is just its authored stagger.
const RAGDOLL_BAKE_PATH := "res://assets/animations/mark_offbalance_ragdoll.json"

## Built variants, keyed on the base clip instances they were bent from —
## see build().
static var _cache := {}


static func P(left := 0.0, fwd := 0.0, up := 0.0) -> Vector3:
	return Vector3(left, up, fwd)


## Character-frame rotation, degrees: fwd tips an upright segment's top
## forward (+Z), left bends it toward +X, turn yaws it to face left.
static func lean(fwd := 0.0, left := 0.0, turn := 0.0) -> Quaternion:
	return Quaternion(Vector3.UP, deg_to_rad(turn)) \
		* Quaternion(Vector3.RIGHT, deg_to_rad(fwd)) \
		* Quaternion(Vector3.FORWARD, deg_to_rad(left))


## Mirror across the sagittal plane (x -> -x): axis (x, y, z) -> (x, -y, -z).
static func mirror_q(q: Quaternion) -> Quaternion:
	return Quaternion(q.x, -q.y, -q.z, q.w)


static func mirror_bone(bone: String) -> String:
	if bone.begins_with("Left"):
		return "Right" + bone.substr(4)
	if bone.begins_with("Right"):
		return "Left" + bone.substr(5)
	return bone


static func supports(skeleton: Skeleton3D) -> bool:
	if skeleton == null:
		return false
	for bone in REQUIRED_BONES:
		if skeleton.find_bone(bone) < 0:
			return false
	return true


## variant clip name -> Animation, for every variant whose base clip is in
## `base_clips` (clip name -> Animation). Pass only clips authored for this
## skeleton (HumanoidRig.imported_animations()) — bending a procedural
## fallback would bend a pose that's already wrong on this rig. Empty if the
## skeleton isn't one this knows how to pose.
static func build(skeleton: Skeleton3D, base_clips: Dictionary) -> Dictionary:
	var out := {}
	if not supports(skeleton):
		return out
	# ~55 ms per build, and a full game has 36 players on one model. Every
	# HumanoidRig instantiating the same .glb gets the SAME Animation
	# resources (measured), so the variants built off them are shared too —
	# keyed on those base clip instances, paid once per model.
	var key := ""
	for spec: Dictionary in _specs():
		var base_clip: Animation = base_clips.get(spec["base"])
		if base_clip != null:
			key += "%d," % base_clip.get_instance_id()
	if _cache.has(key):
		return _cache[key]
	var rig := _Rig.new(skeleton)
	var bake := _load_ragdoll_bake()
	for spec: Dictionary in _specs():
		var base_name: String = spec["base"]
		if not base_clips.has(base_name):
			continue
		out[spec["name"]] = _build_variant(rig, base_clips[base_name], spec, bake)
	_cache[key] = out
	return out


## The base clip a variant bends — what PlayerAnimation falls back to when
## the variant isn't in the library.
static func base_of(variant: String) -> String:
	for spec: Dictionary in _specs():
		if spec["name"] == variant:
			return spec["base"]
	return ""


## Every variant PlayerAnimation can select, base clip first. Order is the
## build order only.
static func variant_names() -> Array[String]:
	var names: Array[String] = []
	for spec: Dictionary in _specs():
		names.append(spec["name"])
	return names


# ── Variant specs ──────────────────────────────────────────────────────
# Each: {name, base, keys: [[t, offsets], ...]}. Offsets ease (smoothstep)
# from key to key and hold flat before the first / after the last key, so a
# spec that should only bend part of the clip starts and ends with {}.
#   "pelvis_pos": P offset   "pelvis_rot": lean()
#   "rot": {bone: lean()}    — Spine / Chest / head / clavicles
#   "hand_l"/"hand_r": wrist offset from the base clip's wrist, P()
#   "hand_l_abs"/"hand_r_abs": absolute wrist target, P() in root space
#   "elbow_l"/"elbow_r": elbow pole direction override
#   "foot_l"/"foot_r": ankle offset from the base clip's ankle, P()
#   "ragdoll": 0..1 weight of the baked passive-ragdoll response
# Heights for reference (6thbuild, standing): ankle 0.08, hips 1.14,
# shoulder joint 1.73, head top ~2.1; Safe's base clip takes the ball
# around 1.4-1.5 m.

static func _specs() -> Array[Dictionary]:
	var safe_contact := Tuning.action_contact_time(Tuning.Action.MARK_SAFE)
	var run_contact := Tuning.action_contact_time(Tuning.Action.MARK_RUNNING)
	var leap_contact := Tuning.action_contact_time(Tuning.Action.MARK_AGGRESSIVE)
	var specs: Array[Dictionary] = []

	# Low / knee-height take: sit down into it — knees bend (the legs are
	# re-planted, so it's the knees that give, not the feet), chest folds over
	# the ball, hands go down to meet it, then the body comes back up through
	# the base clip's carry.
	var low := {
		"pelvis_pos": P(0, 0.02, -0.20),
		"rot": {"Spine": lean(14), "Chest": lean(8), "head": lean(12)},
		"hand_l": P(0.0, 0.08, -0.42), "hand_r": P(0.0, 0.08, -0.42),
		"elbow_l": P(0.7, -0.3, -0.6), "elbow_r": P(-0.7, -0.3, -0.6),
	}
	specs.append({"name": "mark_safe_low", "base": "mark_safe", "keys": [
		[0.0, low], [safe_contact, low], [0.30, {}]]})

	# Overhead take: arms up over the head to it, eyes up, then the base
	# clip's pull-down into the chest.
	var high := {
		"pelvis_pos": P(0, 0, 0.02),
		"rot": {"Spine": lean(-4), "Chest": lean(-3), "head": lean(-24),
			"LeftShoulder": _clav_l(16), "RightShoulder": mirror_q(_clav_l(16))},
		"hand_l_abs": P(0.12, 0.24, 2.16), "hand_r_abs": P(-0.12, 0.24, 2.16),
		"elbow_l": P(1.0, 0.0, -0.4), "elbow_r": P(-1.0, 0.0, -0.4),
	}
	specs.append({"name": "mark_safe_overhead", "base": "mark_safe", "keys": [
		[0.0, high], [safe_contact, high], [0.32, {}]]})

	# Contested chest mark: braced for the body that's coming — wider, lower
	# base, chest over the ball, shoulders rolled in, elbows tight, ball
	# pinned. Held a little longer than the plain mark before it relaxes.
	# Ragdoll hand-off candidate at contact (see header).
	var braced := {
		"pelvis_pos": P(0, -0.02, -0.10),
		"rot": {"Spine": lean(8), "Chest": lean(5), "head": lean(8),
			"LeftShoulder": _clav_l(0, 10), "RightShoulder": mirror_q(_clav_l(0, 10))},
		"hand_l": P(-0.03, -0.05, -0.02), "hand_r": P(0.03, -0.05, -0.02),
		"elbow_l": P(0.25, -0.1, -1.0), "elbow_r": P(-0.25, -0.1, -1.0),
		"foot_l": P(0.08, 0.04, 0), "foot_r": P(-0.08, -0.04, 0),
	}
	specs.append({"name": "mark_safe_contested", "base": "mark_safe", "keys": [
		[0.0, braced], [0.30, braced], [0.52, {}]]})

	# Running, low: scooped off the bootlaces in stride.
	var run_low := {
		"pelvis_pos": P(0, 0.02, -0.12),
		"rot": {"Spine": lean(14), "Chest": lean(6), "head": lean(14)},
		"hand_l": P(0.0, 0.06, -0.48), "hand_r": P(0.0, 0.06, -0.48),
		"elbow_l": P(0.7, -0.3, -0.6), "elbow_r": P(-0.7, -0.3, -0.6),
	}
	specs.append({"name": "mark_running_low", "base": "mark_running", "keys": [
		[0.0, run_low], [run_contact, run_low], [0.24, {}]]})

	# Running, high: hands up above the head on the lead.
	var run_high := {
		"rot": {"Chest": lean(-4), "head": lean(-22),
			"LeftShoulder": _clav_l(14), "RightShoulder": mirror_q(_clav_l(14))},
		"hand_l_abs": P(0.13, 0.42, 2.12), "hand_r_abs": P(-0.13, 0.42, 2.12),
		"elbow_l": P(1.0, 0.0, -0.4), "elbow_r": P(-1.0, 0.0, -0.4),
	}
	specs.append({"name": "mark_running_overhead", "base": "mark_running", "keys": [
		[0.0, run_high], [run_contact, run_high], [0.24, {}]]})

	# Over-the-shoulder (Madden's catch running with the flight): the ball
	# comes from behind, over one shoulder. Head turned back to it, chest
	# opened toward it, both hands up beside that shoulder with the far hand
	# reaching across. _r = over the right shoulder; _l mirrors it.
	var shoulder_r := {
		"rot": {"Chest": lean(-2, 0, -16), "head": lean(-14, 0, -55),
			"RightShoulder": mirror_q(_clav_l(18)), "LeftShoulder": _clav_l(10)},
		"hand_r_abs": P(-0.34, 0.18, 1.86), "hand_l_abs": P(-0.10, 0.26, 1.90),
		"elbow_r": P(-1.0, -0.2, -0.3), "elbow_l": P(0.6, -0.4, -0.6),
	}
	specs.append({"name": "mark_running_shoulder_r", "base": "mark_running", "keys": [
		[0.0, shoulder_r], [run_contact, shoulder_r], [0.26, {}]]})
	specs.append({"name": "mark_running_shoulder_l", "base": "mark_running", "keys": [
		[0.0, _mirror_offsets(shoulder_r)], [run_contact, _mirror_offsets(shoulder_r)], [0.26, {}]]})

	# Aggressive, knocked off balance in the air (contested leap): the base
	# clip's take is untouched up to contact; after it the baked ragdoll
	# response to a push at the chest tips the trunk and swings the legs away
	# from the hit, then an authored stagger lands on the far foot and fights
	# back to the base clip's absorb. _r = hit from the right (pushed toward
	# the left); _l mirrors it. Hand-off candidate from contact to ~0.6 s.
	# The bake is a fully LIMP body (hips tumble ~58° by 0.23 s after the
	# push, 95° by 0.4 s — it would land on its side); a player fighting for
	# balance resists most of that, so it goes in at 0.35 (~20° of trunk tip,
	# head and legs whipped with it). Unplaytested feel guess.
	var knocked := {
		"ragdoll": 0.35,
		"pelvis_pos": P(0.10, 0, 0),
		"rot": {"Spine": lean(0, 6), "head": lean(-6, -8)},
		"foot_l": P(0.10, 0.04, 0.10), "foot_r": P(0.0, 0, 0.18),
	}
	var stagger := {
		"ragdoll": 0.15,
		"pelvis_pos": P(0.20, 0.02, -0.08), "pelvis_rot": lean(4, 10),
		"rot": {"Spine": lean(6, 8), "Chest": lean(2, 4), "head": lean(4, -6)},
		"foot_l": P(0.26, 0.06, 0), "foot_r": P(0.0, -0.04, 0.12),
	}
	var recover := {
		"pelvis_pos": P(0.12, 0.02, -0.06), "pelvis_rot": lean(2, 4),
		"rot": {"Spine": lean(4, 2)},
		"foot_l": P(0.22, 0.06, 0), "foot_r": P(0.06, 0, 0),
	}
	var knocked_keys := [[leap_contact, {}], [leap_contact + 0.10, knocked],
		[0.62, knocked], [0.84, stagger], [0.90, recover], [0.958, recover]]
	specs.append({"name": "mark_aggressive_offbalance_r", "base": "mark_aggressive",
		"keys": knocked_keys, "ragdoll_start": leap_contact})
	var mirrored_keys := []
	for key: Array in knocked_keys:
		mirrored_keys.append([key[0], _mirror_offsets(key[1])])
	specs.append({"name": "mark_aggressive_offbalance_l", "base": "mark_aggressive",
		"keys": mirrored_keys, "ragdoll_start": leap_contact, "ragdoll_mirror": true})

	# Aggressive miss: entered at the contact instant (PlayerAnimation plays
	# it from leap_contact on, cross-fading out of the leap — see
	# _build_state_machine) when the leap comes up empty. Hands open and
	# apart past the ball, head turning to watch it go over, arms coming down
	# wide instead of into the chest, a looser landing.
	var whiff := {
		"hand_l": P(0.16, 0.06, 0.06), "hand_r": P(-0.16, 0.06, 0.06),
		"rot": {"head": lean(-16, 0, 10)},
	}
	var empty := {
		"hand_l": P(0.30, -0.12, -0.20), "hand_r": P(-0.30, -0.12, -0.20),
		"elbow_l": P(1.0, 0.2, -0.5), "elbow_r": P(-1.0, 0.2, -0.5),
		"rot": {"head": lean(-10, 0, 14), "Chest": lean(-4)},
	}
	var loose := {
		"hand_l": P(0.30, -0.10, -0.12), "hand_r": P(-0.30, -0.10, -0.12),
		"elbow_l": P(1.0, 0.2, -0.5), "elbow_r": P(-1.0, 0.2, -0.5),
		"pelvis_pos": P(0, 0, -0.03), "rot": {"head": lean(6, 0, 8)},
	}
	specs.append({"name": "mark_aggressive_miss", "base": "mark_aggressive", "keys": [
		[leap_contact, {}], [leap_contact + 0.06, whiff], [0.58, empty], [0.86, loose], [0.958, {}]]})
	return specs


## Left clavicle rotation, degrees. The left clavicle runs along +X, so a
## lift (tip up toward +Y) is a positive turn about +Z, and a forward roll
## (tip toward +Z) a negative turn about +Y. mirror_q() gives the right.
static func _clav_l(lift := 0.0, fwd := 0.0) -> Quaternion:
	return Quaternion(Vector3.UP, deg_to_rad(-fwd)) * Quaternion(Vector3.BACK, deg_to_rad(lift))


static func _mirror_offsets(o: Dictionary) -> Dictionary:
	var m := {}
	for key: String in o:
		var v = o[key]
		var mk := key
		if key.ends_with("_l"):
			mk = key.substr(0, key.length() - 2) + "_r"
		elif key.ends_with("_r"):
			mk = key.substr(0, key.length() - 2) + "_l"
		elif key.ends_with("_l_abs"):
			mk = key.replace("_l_abs", "_r_abs")
		elif key.ends_with("_r_abs"):
			mk = key.replace("_r_abs", "_l_abs")
		if key == "rot":
			var r := {}
			for bone: String in v:
				r[mirror_bone(bone)] = mirror_q(v[bone])
			m["rot"] = r
		elif v is Vector3:
			m[mk] = Vector3(-v.x, v.y, v.z)
		elif v is Quaternion:
			m[mk] = mirror_q(v)
		else:
			m[mk] = v
	return m


# ── Rig + pose math ────────────────────────────────────────────────────

class _Rig:
	var bones: Array[String] = []          # index order — parents first
	var parent := {}                       # bone -> parent bone or ""
	var rest := {}                         # bone -> local rest Transform3D
	var grest := {}                        # bone -> global rest rotation

	func _init(skeleton: Skeleton3D) -> void:
		for i in skeleton.get_bone_count():
			var name := skeleton.get_bone_name(i)
			bones.append(name)
			var p := skeleton.get_bone_parent(i)
			parent[name] = skeleton.get_bone_name(p) if p >= 0 else ""
			rest[name] = skeleton.get_bone_rest(i)
			grest[name] = skeleton.get_bone_global_rest(i).basis.get_rotation_quaternion()

	## pose: bone -> {"q": Quaternion, "p": Vector3} (local). Returns bone ->
	## global Transform3D in skeleton space.
	func fk(pose: Dictionary) -> Dictionary:
		var g := {}
		for name in bones:
			var local := Transform3D(Basis(pose[name].q), pose[name].p)
			var p: String = parent[name]
			g[name] = (g[p] as Transform3D) * local if p != "" else local
		return g

	func rel(name: String, r: Quaternion) -> Quaternion:
		var G: Quaternion = grest[name]
		return G.inverse() * r * G


static func _sample(rig: _Rig, anim: Animation, t: float) -> Dictionary:
	var pose := {}
	for name in rig.bones:
		var r: Transform3D = rig.rest[name]
		pose[name] = {"q": r.basis.get_rotation_quaternion(), "p": r.origin}
	for i in anim.get_track_count():
		var bone := String(anim.track_get_path(i).get_concatenated_subnames())
		if not pose.has(bone):
			continue
		match anim.track_get_type(i):
			Animation.TYPE_ROTATION_3D:
				pose[bone].q = anim.rotation_track_interpolate(i, t)
			Animation.TYPE_POSITION_3D:
				pose[bone].p = anim.position_track_interpolate(i, t)
	return pose


static func _arc(a: Vector3, b: Vector3) -> Quaternion:
	a = a.normalized()
	b = b.normalized()
	var d := clampf(a.dot(b), -1.0, 1.0)
	if d > 0.999999:
		return Quaternion.IDENTITY
	if d < -0.999999:
		var perp := a.cross(Vector3.RIGHT if absf(a.x) < 0.9 else Vector3.UP).normalized()
		return Quaternion(perp, PI)
	return Quaternion(a.cross(b).normalized(), acos(d))


## Swing `bone` so its +Y (which runs along every 6thbuild bone) points
## along `dir`, by the shortest arc from where it points now.
static func _aim(rig: _Rig, pose: Dictionary, bone: String, dir: Vector3) -> void:
	var g := rig.fk(pose)
	var cur: Quaternion = (g[bone] as Transform3D).basis.get_rotation_quaternion()
	var want := _arc(cur * Vector3.UP, dir) * cur
	var p: String = rig.parent[bone]
	var pg: Quaternion = (g[p] as Transform3D).basis.get_rotation_quaternion() if p != "" else Quaternion.IDENTITY
	pose[bone].q = (pg.inverse() * want).normalized()


## Two-bone IK: upper -> lower -> end lands `end`'s origin on `target`
## (clamped to reach), bending toward `pole` (a direction from the upper
## joint). End bone keeps its local rotation (follows the lower bone).
static func _two_bone(rig: _Rig, pose: Dictionary, upper: String, lower: String, end: String,
		target: Vector3, pole: Vector3) -> void:
	var g := rig.fk(pose)
	var s: Vector3 = (g[upper] as Transform3D).origin
	var l1: float = (rig.rest[lower] as Transform3D).origin.length()
	var l2: float = (rig.rest[end] as Transform3D).origin.length()
	var to_t := target - s
	var d := clampf(to_t.length(), absf(l1 - l2) + 0.02, l1 + l2 - 0.004)
	var u := to_t.normalized() if to_t.length() > 0.0001 else Vector3.DOWN
	var v := pole - u * pole.dot(u)
	if v.length() < 0.0001:
		v = u.cross(Vector3.RIGHT)
	v = v.normalized()
	var a := (l1 * l1 - l2 * l2 + d * d) / (2.0 * d)
	var h := sqrt(maxf(l1 * l1 - a * a, 0.0))
	var e := s + u * a + v * h
	_aim(rig, pose, upper, e - s)
	_aim(rig, pose, lower, s + u * d - e)


static func _smooth(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)


## Offsets at time t: eased between the two keys either side, flat outside.
## Returns [offsets_a, offsets_b, weight_b].
static func _bracket(keys: Array, t: float) -> Array:
	if t <= float(keys[0][0]):
		return [keys[0][1], keys[0][1], 0.0]
	for i in range(keys.size() - 1):
		var t0: float = keys[i][0]
		var t1: float = keys[i + 1][0]
		if t <= t1:
			return [keys[i][1], keys[i + 1][1], _smooth((t - t0) / maxf(t1 - t0, 0.0001))]
	var last: Dictionary = keys[keys.size() - 1][1]
	return [last, last, 0.0]


static func _mix_v(a: Dictionary, b: Dictionary, key: String, w: float, a_default := Vector3.ZERO,
		b_default := Vector3.ZERO) -> Vector3:
	var va: Vector3 = a.get(key, a_default)
	var vb: Vector3 = b.get(key, b_default)
	return va.lerp(vb, w)


static func _mix_q(qa: Quaternion, qb: Quaternion, w: float) -> Quaternion:
	return qa.slerp(qb, w)


static func _mix_f(a: Dictionary, b: Dictionary, key: String, w: float) -> float:
	return lerpf(float(a.get(key, 0.0)), float(b.get(key, 0.0)), w)


static func _build_variant(rig: _Rig, base: Animation, spec: Dictionary, bake: Dictionary) -> Animation:
	var out := Animation.new()
	out.length = base.length
	out.loop_mode = base.loop_mode
	var tracks := {}
	for name in rig.bones:
		var tr := out.add_track(Animation.TYPE_ROTATION_3D)
		out.track_set_path(tr, NodePath(SKELETON + ":" + name))
		tracks[name] = tr
	var hips_pos := out.add_track(Animation.TYPE_POSITION_3D)
	out.track_set_path(hips_pos, NodePath(SKELETON + ":Hips"))

	var keys: Array = spec["keys"]
	var mirror_bake: bool = spec.get("ragdoll_mirror", false)
	var bake_start: float = spec.get("ragdoll_start", 0.0)
	# Same sample times as the base clip (imports are baked every frame), so
	# a variant is exactly as smooth as what it bends.
	var times := _key_times(base)
	for t in times:
		var pose := _sample(rig, base, t)
		var g0 := rig.fk(pose)
		var br := _bracket(keys, t)
		var a: Dictionary = br[0]
		var b: Dictionary = br[1]
		var w: float = br[2]

		# Hips: armature-space offset + rotation about the hips joint.
		var off := _mix_v(a, b, "pelvis_pos", w)
		var prot := _mix_q(a.get("pelvis_rot", Quaternion.IDENTITY), b.get("pelvis_rot", Quaternion.IDENTITY), w)
		pose["Hips"].p += off
		pose["Hips"].q = (prot * pose["Hips"].q).normalized()

		# Passive-ragdoll response (baked), weighted.
		var rw := _mix_f(a, b, "ragdoll", w)
		if rw > 0.0 and not bake.is_empty():
			var deltas := _bake_at(bake, t - bake_start, mirror_bake)
			for bone: String in deltas:
				if not pose.has(bone):
					continue
				var r: Quaternion = Quaternion.IDENTITY.slerp(deltas[bone], rw)
				if bone == "Hips":
					pose[bone].q = (r * pose[bone].q).normalized()
				elif not bone.ends_with("Arm") and not bone.ends_with("Hand") \
						and not bone.ends_with("Shoulder"):
					# Arms stay the player's — they're holding the ball.
					pose[bone].q = (pose[bone].q * rig.rel(bone, r)).normalized()

		# Torso / head / clavicles.
		var ra: Dictionary = a.get("rot", {})
		var rb: Dictionary = b.get("rot", {})
		for bone: String in _union(ra, rb):
			var r := _mix_q(ra.get(bone, Quaternion.IDENTITY), rb.get(bone, Quaternion.IDENTITY), w)
			pose[bone].q = (pose[bone].q * rig.rel(bone, r)).normalized()

		# Hands: offset from the base wrist, or an absolute point (turned into
		# an offset against the base wrist *now*, so both blend the same way).
		for side in ["l", "r"]:
			var prefix := "Left" if side == "l" else "Right"
			var wrist: Vector3 = (g0[prefix + "Hand"] as Transform3D).origin
			var oa := _hand_offset(a, side, wrist)
			var ob := _hand_offset(b, side, wrist)
			var hand_off := oa.lerp(ob, w)
			var has_pole := a.has("elbow_" + side) or b.has("elbow_" + side)
			if hand_off.length() < 0.0005 and not has_pole:
				continue   # no hand spec: the arm just rides along with the torso
			var shoulder: Vector3 = (g0[prefix + "UpperArm"] as Transform3D).origin
			var elbow: Vector3 = (g0[prefix + "LowerArm"] as Transform3D).origin
			var base_pole := elbow - shoulder
			var pole := _mix_v(a, b, "elbow_" + side, w, a.get("elbow_" + side, base_pole), b.get("elbow_" + side, base_pole))
			_two_bone(rig, pose, prefix + "UpperArm", prefix + "LowerArm", prefix + "Hand",
				wrist + hand_off, pole)

		# Legs back onto the base clip's ankle path (plus any foot offset),
		# keeping each foot's base orientation.
		for side in ["l", "r"]:
			var prefix := "Left" if side == "l" else "Right"
			var ankle: Vector3 = (g0[prefix + "Foot"] as Transform3D).origin
			var knee: Vector3 = (g0[prefix + "LowerLeg"] as Transform3D).origin
			var hip: Vector3 = (g0[prefix + "UpperLeg"] as Transform3D).origin
			var foot_q: Quaternion = (g0[prefix + "Foot"] as Transform3D).basis.get_rotation_quaternion()
			var foot_off := _mix_v(a, b, "foot_" + side, w)
			_two_bone(rig, pose, prefix + "UpperLeg", prefix + "LowerLeg", prefix + "Foot",
				ankle + foot_off, knee - hip)
			var g1 := rig.fk(pose)
			var shin_q: Quaternion = (g1[prefix + "LowerLeg"] as Transform3D).basis.get_rotation_quaternion()
			pose[prefix + "Foot"].q = (shin_q.inverse() * foot_q).normalized()

		for name in rig.bones:
			out.rotation_track_insert_key(tracks[name], t, pose[name].q)
		out.position_track_insert_key(hips_pos, t, pose["Hips"].p)
	return out


static func _hand_offset(o: Dictionary, side: String, wrist: Vector3) -> Vector3:
	if o.has("hand_%s_abs" % side):
		return (o["hand_%s_abs" % side] as Vector3) - wrist
	return o.get("hand_" + side, Vector3.ZERO)


static func _union(a: Dictionary, b: Dictionary) -> Array:
	var keys := a.keys()
	for k in b.keys():
		if not keys.has(k):
			keys.append(k)
	return keys


static func _key_times(anim: Animation) -> PackedFloat64Array:
	var times := PackedFloat64Array()
	var track := -1
	for i in anim.get_track_count():
		if anim.track_get_type(i) == Animation.TYPE_ROTATION_3D:
			if track < 0 or anim.track_get_key_count(i) > anim.track_get_key_count(track):
				track = i
	if track < 0 or anim.track_get_key_count(track) < 2:
		var steps := maxi(2, ceili(anim.length * 30.0) + 1)
		for i in steps:
			times.append(anim.length * float(i) / float(steps - 1))
		return times
	for k in anim.track_get_key_count(track):
		times.append(anim.track_get_key_time(track, k))
	return times


# ── Ragdoll bake ───────────────────────────────────────────────────────

static func _load_ragdoll_bake() -> Dictionary:
	if not FileAccess.file_exists(RAGDOLL_BAKE_PATH):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(RAGDOLL_BAKE_PATH))
	if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("samples"):
		return {}
	return parsed


## Baked per-bone deltas at `t` seconds after the push (clamped to the bake's
## range, linear between samples), optionally mirrored to a push from the
## other side.
static func _bake_at(bake: Dictionary, t: float, mirror: bool) -> Dictionary:
	var samples: Array = bake.samples
	if samples.is_empty():
		return {}
	t = clampf(t, float(samples[0].t), float(samples[samples.size() - 1].t))
	var i := 0
	while i < samples.size() - 2 and float(samples[i + 1].t) < t:
		i += 1
	var s0: Dictionary = samples[i]
	var s1: Dictionary = samples[mini(i + 1, samples.size() - 1)]
	var span := float(s1.t) - float(s0.t)
	var w := (t - float(s0.t)) / span if span > 0.0 else 0.0
	var out := {}
	for bone: String in s0.rot:
		var qa := _q(s0.rot[bone])
		var qb := _q(s1.rot.get(bone, s0.rot[bone]))
		var q := qa.slerp(qb, clampf(w, 0.0, 1.0))
		if mirror:
			out[mirror_bone(bone)] = mirror_q(q)
		else:
			out[bone] = q
	return out


static func _q(a: Array) -> Quaternion:
	return Quaternion(float(a[0]), float(a[1]), float(a[2]), float(a[3])).normalized()
