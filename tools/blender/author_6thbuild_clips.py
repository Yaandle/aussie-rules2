"""Authors 6thbuild's action clips (marking first) as real Blender actions on
6thbuild.blend's own Armature, keyed on the rig's NATIVE bone names (pelvis,
spine2, upperarm.l, iktarget.l, ...), so export_6thbuild.py ships them in the
.glb exactly like idle / run_* / tackle_* — and PlayerAnimation's
_build_merged_library() stops falling back to the procedural clip for them.

WHY THIS EXISTS (and why generate_gait_clip.py's approach wasn't reused
as-is): HumanoidAnimations' poses are absolute local rotations written for
the procedural rig's identity rests. 6thbuild's rests are not identity (every
bone's +Y runs along the bone, Blender convention, and the legs/clavicles sit
~90-180 deg off identity), so a verbatim port overwrites the rest and the
pose falls apart — measured in Godot before this script existed: every
procedural mark clip put both feet ~1.9 m up, above the head. This script
keeps the procedural clips' TIMING and INTENT (same keys at the same
fractions of Tuning.ACTION_DURATION / ACTION_CONTACT) but poses the rig
rest-relative:

* Torso / head / clavicles: a rotation R written in armature axes, applied
  as basis = G^-1 R G (G = the bone's rest rotation in armature space). That
  makes R mean "rotate this segment by R in the character's own frame, as
  carried by its parent" — the convention the procedural poses were written
  in, without overwriting the rest.
* Arms: analytic two-bone IK to a wrist target in armature space, with an
  elbow pole direction — so "the hands meet the ball at contact" is a
  position you can read off the clip spec, not a guessed joint angle. Each
  bone is swung onto its solved direction by the shortest arc from where its
  parent left it, so twist stays continuous from the rest A-pose.
* Legs: the rig's own leg IK (lowerleg IK -> iktarget, pole ikpole; foot
  COPY_ROTATION from iktarget) — feet are placed by keying iktarget
  location/rotation, exactly as the hand-authored tackle_* clips do, and the
  exporter's baked sampling resolves the IK.

Armature space: +X = character's left, -Y = forward, +Z = up (Blender front
view). P(left, fwd, up) below builds points/directions in those terms.

Run headless (from the repo root, or anywhere — paths are absolute):
    blender "F:\\dev\\learning-&-development\\New Folder\\6thbuild.blend" \\
        --background --python tools/blender/author_6thbuild_clips.py -- [clip ...]
No clip names = every clip in CLIPS. Re-runnable: an existing action of the
same name (and its NLA stash track) is replaced, never duplicated. Saves the
.blend unless --no-save is passed. Back the .blend up first — it isn't
version-controlled.

Then export (export_6thbuild.py, whose CLIP_RENAME lists these names) and
reimport in Godot — see tools/blender/README.md.

TIMING: the scene runs at 24 fps and an exported clip is sampled on whole
frames, so each clip's last key sits on the whole frame nearest
Tuning.ACTION_DURATION * fps (e.g. MARK_SAFE 0.55 s -> 13 frames = 0.542 s).
Contact keys sit on their exact (fractional) time. ACTION_TIMING below is a
copy of scripts/tuning.gd's ACTION_DURATION / ACTION_CONTACT — keep the two
in sync; gameplay reads Tuning, never the clip length.
"""

import bpy, math, sys
from mathutils import Matrix, Quaternion, Vector

ARMATURE = "Armature"
BASE_ACTION = "idle"         # frame 1 of this is the neutral pose clips settle back to
RUN_ACTION = "run_fwd"       # leg/pelvis source for the in-stride clips

# Copied from scripts/tuning.gd (ACTION_DURATION, ACTION_CONTACT), seconds.
ACTION_TIMING = {
	"mark_safe": (0.55, 0.08),
	"mark_running": (0.40, 0.06),
	"mark_aggressive": (0.95, 0.40),
	"mark_safe_miss": (0.35, 0.10),
	"mark_running_miss": (0.30, 0.10),
	"kick": (0.78, 0.42),
	"handball": (0.45, 0.20),
	"bounce": (0.50, 0.22),
	"hit_out": (0.95, 0.40),
	"knocked_back": (1.3, 0.30),
	"smothered": (0.45, 0.12),
	"smother_dive": (0.55, 0.38),
}

FK_BONES = ["pelvis", "spine1", "spine2", "head", "shoulder.l", "shoulder.r",
	"upperarm.l", "upperarm.r", "lowerarm.l", "lowerarm.r", "hand.l", "hand.r",
	"upperleg.l", "upperleg.r", "lowerleg.l", "lowerleg.r", "foot.l", "foot.r"]
LEG_CONTROL_BONES = ["iktarget.l", "iktarget.r", "ikpole.l", "ikpole.r"]


# ── Semantic helpers (armature space) ──────────────────────────────────

def P(left=0.0, fwd=0.0, up=0.0):
	"""Point/direction from character terms: +left, +forward, +up."""
	return Vector((left, -fwd, up))


def rot(axis, deg):
	return Quaternion(Vector(axis).normalized(), math.radians(deg))


def lean(fwd=0.0, left=0.0, turn=0.0):
	"""Segment rotation in character terms, degrees. fwd tips an upright
	segment's top forward (a hunch / nod down); left bends it toward the
	character's left; turn yaws it to face left. Rx(+a) tips +Z toward -Y
	(forward), Ry(+a) tips +Z toward +X (left), Rz(+a) turns -Y toward +X."""
	return rot((0, 0, 1), turn) @ rot((1, 0, 0), fwd) @ rot((0, 1, 0), left)


def mirror_q(q):
	"""Mirror a rotation across the character's sagittal plane (x -> -x):
	axis (x, y, z) -> (x, -y, -z), same angle. Used to derive right-side
	rotations from left-side ones."""
	axis, angle = q.to_axis_angle()
	return Quaternion(Vector((axis.x, -axis.y, -axis.z)), angle)


def mirror_v(v):
	return Vector((-v.x, v.y, v.z))


def clav(lift=0.0, fwd=0.0):
	"""Left clavicle rotation: lift raises the shoulder tip, fwd rolls it
	forward (protraction). The left clavicle runs along +X, so a lift is a
	negative turn about +Y and a forward roll a negative turn about +Z;
	mirror_q() gives the right side."""
	return rot((0, 0, 1), -fwd) @ rot((0, 1, 0), -lift)


# ── Rig access ─────────────────────────────────────────────────────────

class Rig:
	def __init__(self, arm_obj):
		self.obj = arm_obj
		self.bones = arm_obj.data.bones
		self.rest = {b.name: b.matrix_local.copy() for b in self.bones}
		self.rest_rot = {n: m.to_quaternion() for n, m in self.rest.items()}
		self.parent = {b.name: (b.parent.name if b.parent else None) for b in self.bones}
		self.length = {b.name: b.length for b in self.bones}
		# Arm segment lengths are joint-to-joint (head to child head), which
		# is what the IK needs — bone.length is the same thing here since
		# every arm bone's tail sits on its child's head.
		self.order = []
		def walk(b):
			self.order.append(b.name)
			for c in b.children:
				walk(c)
		for b in self.bones:
			if b.parent is None:
				walk(b)

	def fk(self, basis):
		"""basis: bone -> (loc Vector, rot Quaternion). Returns bone -> 4x4
		armature-space pose matrix, same composition Blender itself uses
		(pose = parent_pose @ parent_rest^-1 @ rest @ basis)."""
		pose = {}
		for name in self.order:
			loc, q = basis.get(name, (Vector(), Quaternion()))
			b = Matrix.Translation(loc) @ q.to_matrix().to_4x4()
			p = self.parent[name]
			if p is None:
				pose[name] = self.rest[name] @ b
			else:
				pose[name] = pose[p] @ self.rest[p].inverted() @ self.rest[name] @ b
		return pose

	def zero_basis_rot(self, name, pose):
		"""Armature-space rotation `name` would have with an identity basis,
		given its parent's current pose."""
		p = self.parent[name]
		if p is None:
			return self.rest_rot[name]
		return pose[p].to_quaternion() @ self.rest_rot[p].inverted() @ self.rest_rot[name]

	def rel_basis(self, name, R):
		"""basis = G^-1 R G: R in armature axes, carried by the parent."""
		G = self.rest_rot[name]
		return G.inverted() @ R @ G


def _arc(a, b):
	"""Shortest-arc rotation taking unit vector a onto unit vector b."""
	a = a.normalized()
	b = b.normalized()
	d = max(-1.0, min(1.0, a.dot(b)))
	if d > 0.999999:
		return Quaternion()
	if d < -0.999999:
		perp = a.orthogonal().normalized()
		return Quaternion(perp, math.pi)
	axis = a.cross(b).normalized()
	return Quaternion(axis, math.acos(d))


def solve_arm(rig, basis, side, target, pole):
	"""Two-bone IK for one arm: writes upperarm/lowerarm basis so the wrist
	(hand bone head) lands on `target` (clamped to reach) with the elbow bent
	toward `pole` (a direction from the shoulder). Returns the reached wrist
	position."""
	ua, la, hd = "upperarm." + side, "lowerarm." + side, "hand." + side
	pose = rig.fk(basis)
	S = pose[ua].translation
	L1 = (rig.rest[la].translation - rig.rest[ua].translation).length
	L2 = (rig.rest[hd].translation - rig.rest[la].translation).length
	to_t = target - S
	d = max(abs(L1 - L2) + 0.02, min(L1 + L2 - 0.004, to_t.length))
	u = to_t.normalized()
	v = pole - u * pole.dot(u)
	if v.length < 1e-4:
		v = u.orthogonal()
	v.normalize()
	a = (L1 * L1 - L2 * L2 + d * d) / (2.0 * d)
	h = math.sqrt(max(L1 * L1 - a * a, 0.0))
	E = S + u * a + v * h
	T = S + u * d

	q0 = rig.zero_basis_rot(ua, pose)
	y0 = q0 @ Vector((0, 1, 0))
	qd = _arc(y0, E - S) @ q0
	basis[ua] = (Vector(), q0.inverted() @ qd)

	pose = rig.fk(basis)
	q0 = rig.zero_basis_rot(la, pose)
	y0 = q0 @ Vector((0, 1, 0))
	qd = _arc(y0, T - E) @ q0
	basis[la] = (Vector(), q0.inverted() @ qd)
	return T


# ── Base pose ──────────────────────────────────────────────────────────

def _action_fcurves(action):
	out = {}
	for layer in action.layers:
		for strip in layer.strips:
			for cb in strip.channelbags:
				for fc in cb.fcurves:
					out[(fc.data_path, fc.array_index)] = fc
	return out


def sample_action(rig, action, frame):
	"""bone -> {"loc": Vector, "rot": Quaternion} for every bone the action
	keys, evaluated at `frame` (euler channels converted with the bone's own
	rotation mode)."""
	fcs = _action_fcurves(action)
	out = {}
	for name in rig.order:
		pb = rig.obj.pose.bones[name]
		def ch(prop, n, default):
			vals = []
			found = False
			for i in range(n):
				fc = fcs.get(('pose.bones["%s"].%s' % (name, prop), i))
				if fc is not None:
					found = True
					vals.append(fc.evaluate(frame))
				else:
					vals.append(default[i])
			return vals, found
		loc, _ = ch("location", 3, (0.0, 0.0, 0.0))
		if pb.rotation_mode == 'QUATERNION':
			q, _ = ch("rotation_quaternion", 4, (1.0, 0.0, 0.0, 0.0))
			q = Quaternion(q).normalized()
		else:
			from mathutils import Euler
			e, _ = ch("rotation_euler", 3, (0.0, 0.0, 0.0))
			q = Euler(e, pb.rotation_mode).to_quaternion()
		out[name] = {"loc": Vector(loc), "rot": q}
	return out


# ── Pose building ──────────────────────────────────────────────────────

class Clip:
	"""One authored clip: a list of (time_s, pose_spec) keys plus an optional
	leg/pelvis source action (in-stride clips keep the run cycle's legs).

	pose_spec keys (all optional; anything left out uses the base pose):
	  "pelvis": {"pos": P offset of the hips, "rot": lean(...)}
	  "spine1", "spine2", "head": lean(...) rotations, parent-carried
	  "clav_l", "clav_r": clav(...)  ("clav" = both, right side mirrored)
	  "hand_l", "hand_r": wrist target point (armature space, P(...))
	  "elbow_l", "elbow_r": elbow pole direction (default out-down-back)
	  "hands_in": "chest" -> hand targets are offsets from that arm's
	              shoulder joint, and poles directions, both in the chest's
	              own carried frame — for falls/dives, where a target fixed
	              in armature space would leave the arms behind the torso
	  "wrist_l", "wrist_r": lean(...) on the hand bone
	  "foot_l", "foot_r": {"pos": P offset from the rest ankle, "pitch": deg
	                       toe-down (negative = toe up), "turn": deg}
	"""

	def __init__(self, name, keys, legs_from=None, legs_offset=0.0):
		self.name = name
		self.keys = keys
		self.legs_from = legs_from
		self.legs_offset = legs_offset


DEFAULT_ELBOW_L = P(0.6, -0.4, -1.0)


def build_basis(rig, base, spec):
	basis = {}
	for name in FK_BONES + LEG_CONTROL_BONES:
		b = base.get(name)
		basis[name] = (b["loc"].copy(), b["rot"].copy()) if b else (Vector(), Quaternion())

	pel = spec.get("pelvis")
	if pel is not None:
		G = rig.rest_rot["pelvis"]
		base_loc = base["pelvis"]["loc"]
		offset = pel.get("pos", Vector())
		# Offset is in armature axes; basis location is in the pelvis's own
		# rest frame (pose head = rest head + G @ loc).
		loc = base_loc + G.inverted() @ offset
		basis["pelvis"] = (loc, rig.rel_basis("pelvis", pel.get("rot", Quaternion())))
	for name in ("spine1", "spine2", "head"):
		if name in spec:
			basis[name] = (Vector(), rig.rel_basis(name, spec[name]))
	clav_l = spec.get("clav_l", spec.get("clav"))
	clav_r = spec.get("clav_r", mirror_q(spec["clav"]) if "clav" in spec else None)
	if clav_l is not None:
		basis["shoulder.l"] = (Vector(), base["shoulder.l"]["rot"] @ rig.rel_basis("shoulder.l", clav_l))
	if clav_r is not None:
		basis["shoulder.r"] = (Vector(), base["shoulder.r"]["rot"] @ rig.rel_basis("shoulder.r", clav_r))

	reached = {}
	chest_frame = spec.get("hands_in") == "chest"
	for side in ("l", "r"):
		tgt = spec.get("hand_" + side)
		if tgt is None:
			continue
		pole = spec.get("elbow_" + side, DEFAULT_ELBOW_L if side == "l" else mirror_v(DEFAULT_ELBOW_L))
		if chest_frame:
			pose = rig.fk(basis)
			delta = pose["spine2"].to_quaternion() @ rig.rest_rot["spine2"].inverted()
			tgt = pose["upperarm." + side].translation + delta @ tgt
			pole = delta @ pole
		reached[side] = solve_arm(rig, basis, side, tgt, pole)
		w = spec.get("wrist_" + side)
		if w is not None:
			basis["hand." + side] = (Vector(), rig.rel_basis("hand." + side, w))

	for side in ("l", "r"):
		f = spec.get("foot_" + side)
		if f is None:
			continue
		loc = f.get("pos", Vector())
		q = rot((1, 0, 0), f.get("pitch", 0.0) * FOOT_PITCH_SIGN) @ rot((0, 0, 1), f.get("turn", 0.0))
		basis["iktarget." + side] = (loc.copy(), q)
	return basis, reached


# iktarget rotation -> foot: the foot COPY_ROTATIONs iktarget in local space
# with X/Y inverted, which makes the sign of "toe down" non-obvious — so it
# is measured in calibrate_foot_pitch() at startup (on this rig: +1, a
# positive iktarget turn about X drops the toe) rather than assumed here.
FOOT_PITCH_SIGN = 1.0


def calibrate_foot_pitch(rig_obj):
	global FOOT_PITCH_SIGN
	pt = rig_obj.pose.bones["iktarget.l"]
	foot = rig_obj.pose.bones["foot.l"]
	saved_mode, saved_q = pt.rotation_mode, pt.rotation_quaternion.copy()
	pt.rotation_mode = 'QUATERNION'
	pt.rotation_quaternion = rot((1, 0, 0), 20.0)
	bpy.context.view_layer.update()
	toe_drop = foot.head.z - foot.tail.z
	pt.rotation_quaternion = rot((1, 0, 0), -20.0)
	bpy.context.view_layer.update()
	toe_drop_neg = foot.head.z - foot.tail.z
	pt.rotation_quaternion = saved_q
	pt.rotation_mode = saved_mode
	bpy.context.view_layer.update()
	FOOT_PITCH_SIGN = 1.0 if toe_drop > toe_drop_neg else -1.0
	print("author_6thbuild_clips: foot pitch sign", FOOT_PITCH_SIGN,
		"(toe drop +20deg: %.3f, -20deg: %.3f)" % (toe_drop, toe_drop_neg))


# ── Keying ─────────────────────────────────────────────────────────────

class Keyer:
	def __init__(self, rig, action, fps):
		self.rig = rig
		self.fps = fps
		self.action = action
		slot = None
		for s in action.slots:
			if s.target_id_type == 'OBJECT':
				slot = s
				break
		if slot is None:
			slot = action.slots.new(id_type='OBJECT', name="OBArmature")
		self.slot = slot
		layer = action.layers.new("Layer")
		strip = layer.strips.new(type='KEYFRAME')
		self.cb = strip.channelbag(slot, ensure=True)
		self.prev_euler = {}
		self.prev_quat = {}

	def _fc(self, path, index, group):
		for fc in self.cb.fcurves:
			if fc.data_path == path and fc.array_index == index:
				return fc
		fc = self.cb.fcurves.new(data_path=path, index=index)
		return fc

	def key(self, frame, name, loc=None, q=None):
		pb = self.rig.obj.pose.bones[name]
		if loc is not None:
			for i in range(3):
				self._fc('pose.bones["%s"].location' % name, i, name) \
					.keyframe_points.insert(frame, loc[i], options={'FAST'})
		if q is not None:
			if pb.rotation_mode == 'QUATERNION':
				prev = self.prev_quat.get(name)
				if prev is not None and prev.dot(q) < 0.0:
					q = -q
				self.prev_quat[name] = q.copy()
				for i in range(4):
					self._fc('pose.bones["%s"].rotation_quaternion' % name, i, name) \
						.keyframe_points.insert(frame, q[i], options={'FAST'})
			else:
				prev = self.prev_euler.get(name)
				e = q.to_euler(pb.rotation_mode, prev) if prev is not None else q.to_euler(pb.rotation_mode)
				self.prev_euler[name] = e.copy()
				for i in range(3):
					self._fc('pose.bones["%s"].rotation_euler' % name, i, name) \
						.keyframe_points.insert(frame, e[i], options={'FAST'})

	def finish(self):
		for fc in self.cb.fcurves:
			for kp in fc.keyframe_points:
				kp.interpolation = 'BEZIER'
				kp.handle_left_type = 'AUTO_CLAMPED'
				kp.handle_right_type = 'AUTO_CLAMPED'
			fc.update()


def author_clip(rig, clip, base, fps):
	length, contact = ACTION_TIMING[clip.name]
	end_frame = 1 + round(length * fps)
	arm_obj = rig.obj

	old = bpy.data.actions.get(clip.name)
	if old is not None:
		for track in list(arm_obj.animation_data.nla_tracks):
			if any(s.action is old for s in track.strips):
				arm_obj.animation_data.nla_tracks.remove(track)
		bpy.data.actions.remove(old)
	action = bpy.data.actions.new(clip.name)
	action.use_fake_user = True
	keyer = Keyer(rig, action, fps)

	legs_src = bpy.data.actions.get(clip.legs_from) if clip.legs_from else None
	leg_bones = {"pelvis", "iktarget.l", "iktarget.r", "ikpole.l", "ikpole.r"}
	cycle_frames = (legs_src.frame_range[1] - legs_src.frame_range[0]) if legs_src else 0.0

	def legs_sample(t):
		f = (t + clip.legs_offset) * fps
		if cycle_frames > 0:
			f = math.fmod(f, cycle_frames)
		return sample_action(rig, legs_src, legs_src.frame_range[0] + f)

	report = []
	for t, spec in clip.keys:
		t = min(t, length)
		frame = 1 + (end_frame - 1 if t >= length - 1e-6 else t * fps)
		key_base = base
		if legs_src is not None:
			key_base = dict(base)
			key_base.update({n: v for n, v in legs_sample(t).items() if n in leg_bones})
		basis, reached = build_basis(rig, key_base, spec)
		for name in FK_BONES + LEG_CONTROL_BONES:
			if legs_src is not None and name in leg_bones:
				continue
			loc, q = basis[name]
			keyer.key(frame, name, loc=loc if name == "pelvis" or name.startswith("ik") else None, q=q)
		report.append((round(t, 3), {s: tuple(round(x, 2) for x in p) for s, p in reached.items()}))

	if legs_src is not None:
		# Dense leg/pelvis keys straight off the run cycle, so the stride
		# never breaks under the catch.
		for i in range(end_frame):
			t = min(i / fps, length)
			s = legs_sample(t)
			for name in leg_bones:
				keyer.key(1 + i, name, loc=s[name]["loc"], q=s[name]["rot"])

	keyer.finish()
	track = arm_obj.animation_data.nla_tracks.new()
	track.name = clip.name
	track.strips.new(clip.name, 1, action)
	track.mute = True
	print("author_6thbuild_clips: %-18s %d frames (%.3fs, Tuning %.2fs), contact key %.3fs; wrist reach %s" %
		(clip.name, end_frame - 1, (end_frame - 1) / fps, length, contact, report))
	return action


# ── Clip specs ─────────────────────────────────────────────────────────
# Madden's catch types mapped to AFL (see NEXT_AGENT_MARKING_BRIEF.md (archived)):
#   Safe       = possession / chest mark: square up, gather into the chest.
#   Running    = catch in stride: hands mark on the lead, legs keep running.
#   Aggressive = high-point / pack mark: leap, lead knee up, take it overhead.
#
# Reference heights on 6thbuild (armature space, standing): ankle 0.08,
# hips 1.14, shoulder joint 1.735, head base 1.79, head top ~2.10. Arm
# reach shoulder->wrist 0.65 m. Godot's CarryPoint (where a held ball
# rides) is P(-0.14, 0.10, 1.05) in these terms — the right hip.
#
# RAGDOLL HAND-OFF CANDIDATES (MECHANICS_AUDIT §B4 stage 2, not built):
# the poses marked "hand-off" below are balanced, both-arms-committed poses
# a future animation->ragdoll switch can take over from cleanly on a hard
# contested hit — mark_safe's contact brace, mark_aggressive's contact
# (peak) and pre-landing keys.

def _safe_receive():
	return {
		"pelvis": {"pos": P(0, 0, -0.04)},
		"spine1": lean(fwd=4), "spine2": lean(fwd=3), "head": lean(fwd=4),
		"clav": clav(lift=4, fwd=6),
		"hand_l": P(0.16, 0.44, 1.50), "hand_r": P(-0.16, 0.44, 1.50),
		"elbow_l": P(0.7, -0.3, -1.0), "elbow_r": P(-0.7, -0.3, -1.0),
		"foot_l": {"pos": P(0, 0.06, 0)}, "foot_r": {"pos": P(0, -0.04, 0)},
	}


def clip_mark_safe():
	length, contact = ACTION_TIMING["mark_safe"]
	return Clip("mark_safe", [
		# t=0: the catch has already resolved (PlayerController._complete_mark
		# gathers before _begin), so the clip opens with hands out in front,
		# ball arriving.
		(0.0, _safe_receive()),
		# contact — hand-off: hands close on the ball against the chest,
		# elbows tucked under it, knees give, torso hunches over it.
		(contact, {
			"pelvis": {"pos": P(0, 0, -0.07)},
			"spine1": lean(fwd=8), "spine2": lean(fwd=6), "head": lean(fwd=10),
			"clav": clav(lift=2, fwd=10),
			"hand_l": P(0.15, 0.27, 1.42), "hand_r": P(-0.15, 0.27, 1.42),
			"elbow_l": P(0.35, -0.1, -1.0), "elbow_r": P(-0.35, -0.1, -1.0),
			"foot_l": {"pos": P(0, 0.06, 0)}, "foot_r": {"pos": P(0, -0.04, 0)},
		}),
		# secure: ball hugged in, settling.
		(contact + (length - contact) * 0.35, {
			"pelvis": {"pos": P(0, 0, -0.05)},
			"spine1": lean(fwd=6), "spine2": lean(fwd=4), "head": lean(fwd=8),
			"clav": clav(fwd=8),
			"hand_l": P(0.15, 0.24, 1.32), "hand_r": P(-0.13, 0.25, 1.30),
			"elbow_l": P(0.4, -0.1, -1.0), "elbow_r": P(-0.4, -0.1, -1.0),
			"foot_l": {"pos": P(0, 0.06, 0)}, "foot_r": {"pos": P(0, -0.04, 0)},
		}),
		# into the carry: right hand takes it down to the hip, left lets go.
		(contact + (length - contact) * 0.72, {
			"pelvis": {"pos": P(0, 0, -0.02)},
			"spine1": lean(fwd=3), "spine2": lean(fwd=2), "head": lean(fwd=3),
			"hand_l": P(0.32, 0.10, 1.22), "hand_r": P(-0.18, 0.14, 1.12),
			"elbow_l": P(1.0, 0.3, -0.6), "elbow_r": P(-0.6, 0.3, -1.0),
			"foot_l": {"pos": P(0, 0.03, 0)}, "foot_r": {"pos": P(0, -0.02, 0)},
		}),
		(length, {}),
	])


def clip_mark_safe_miss():
	length, contact = ACTION_TIMING["mark_safe_miss"]
	return Clip("mark_safe_miss", [
		# Same setup as the catch (_safe_receive), so the commitment reads
		# identically right up to contact.
		(0.0, _safe_receive()),
		# contact: it goes through — arms carried on past, hands apart and
		# open, head chasing the ball down.
		(contact, {
			"pelvis": {"pos": P(0, 0.02, -0.08)},
			"spine1": lean(fwd=10), "spine2": lean(fwd=8), "head": lean(fwd=22),
			"clav": clav(lift=0, fwd=12),
			"hand_l": P(0.24, 0.52, 1.26), "hand_r": P(-0.24, 0.52, 1.26),
			"elbow_l": P(0.8, -0.2, -1.0), "elbow_r": P(-0.8, -0.2, -1.0),
			"foot_l": {"pos": P(0, 0.08, 0)}, "foot_r": {"pos": P(0, -0.04, 0)},
		}),
		# deflate: arms drop, shoulders slump, still looking at the ball.
		(contact + (length - contact) * 0.55, {
			"pelvis": {"pos": P(0, 0.01, -0.06)},
			"spine1": lean(fwd=12), "spine2": lean(fwd=8), "head": lean(fwd=26),
			"clav": clav(lift=-4, fwd=6),
			"hand_l": P(0.30, 0.26, 1.04), "hand_r": P(-0.30, 0.26, 1.04),
			"elbow_l": P(1.0, 0.2, -0.5), "elbow_r": P(-1.0, 0.2, -0.5),
			"foot_l": {"pos": P(0, 0.06, 0)}, "foot_r": {"pos": P(0, -0.03, 0)},
		}),
		(length, {}),
	])


def _running_receive():
	return {
		"spine1": lean(fwd=7), "spine2": lean(fwd=4), "head": lean(fwd=2),
		"clav": clav(lift=6, fwd=8),
		"hand_l": P(0.17, 0.58, 1.56), "hand_r": P(-0.17, 0.58, 1.56),
		"elbow_l": P(0.7, -0.4, -1.0), "elbow_r": P(-0.7, -0.4, -1.0),
	}


def clip_mark_running():
	length, contact = ACTION_TIMING["mark_running"]
	return Clip("mark_running", [
		# Hands out on the lead, arms long, the run never breaks (legs come
		# from run_fwd below).
		(0.0, _running_receive()),
		# contact: hands close on it well out in front.
		(contact, {
			"spine1": lean(fwd=8), "spine2": lean(fwd=4), "head": lean(fwd=4),
			"clav": clav(lift=5, fwd=10),
			"hand_l": P(0.14, 0.54, 1.50), "hand_r": P(-0.14, 0.54, 1.50),
			"elbow_l": P(0.7, -0.4, -1.0), "elbow_r": P(-0.7, -0.4, -1.0),
		}),
		# pull it into the body without slowing.
		(contact + (length - contact) * 0.40, {
			"spine1": lean(fwd=8), "spine2": lean(fwd=3), "head": lean(fwd=4),
			"clav": clav(fwd=6),
			"hand_l": P(0.15, 0.32, 1.40), "hand_r": P(-0.13, 0.32, 1.40),
			"elbow_l": P(0.5, 0.0, -1.0), "elbow_r": P(-0.5, 0.0, -1.0),
		}),
		# tucked on the right hip, left arm back to a running swing.
		(contact + (length - contact) * 0.75, {
			"spine1": lean(fwd=7), "spine2": lean(fwd=2), "head": lean(fwd=2),
			"hand_l": P(0.30, 0.18, 1.26), "hand_r": P(-0.18, 0.15, 1.14),
			"elbow_l": P(0.8, 0.6, -0.6), "elbow_r": P(-0.6, 0.4, -1.0),
		}),
		(length, {}),
	], legs_from=RUN_ACTION)


def clip_mark_running_miss():
	length, contact = ACTION_TIMING["mark_running_miss"]
	return Clip("mark_running_miss", [
		(0.0, _running_receive()),
		# contact: grasping past it — arms fully out, hands apart.
		(contact, {
			"spine1": lean(fwd=12), "spine2": lean(fwd=6), "head": lean(fwd=14),
			"clav": clav(lift=2, fwd=12),
			"hand_l": P(0.20, 0.64, 1.38), "hand_r": P(-0.20, 0.64, 1.36),
			"elbow_l": P(0.8, -0.3, -1.0), "elbow_r": P(-0.8, -0.3, -1.0),
		}),
		# arms come back to the run.
		(contact + (length - contact) * 0.55, {
			"spine1": lean(fwd=9), "spine2": lean(fwd=3), "head": lean(fwd=10),
			"hand_l": P(0.30, 0.24, 1.24), "hand_r": P(-0.30, 0.24, 1.24),
			"elbow_l": P(1.0, 0.4, -0.6), "elbow_r": P(-1.0, 0.4, -0.6),
		}),
		(length, {}),
	], legs_from=RUN_ACTION)


def clip_mark_aggressive():
	length, contact = ACTION_TIMING["mark_aggressive"]
	# The real jump is CharacterBody3D physics launched on the press
	# (Tuning.MARK_AGGRESSIVE_JUMP_SPEED 4.0 m/s -> apex at ~0.41 s, back
	# down at ~0.82 s), so this clip only shapes the body around that arc:
	# contact (0.40 s) is the apex, the absorb lands just after 0.82 s.
	return Clip("mark_aggressive", [
		# load: a quick dip and arms swung back (mostly hidden under the
		# 0.10 s blend-in — the body is already rising).
		(0.0, {
			"pelvis": {"pos": P(0, 0.02, -0.09)},
			"spine1": lean(fwd=10), "spine2": lean(fwd=4), "head": lean(fwd=-12),
			"hand_l": P(0.30, -0.22, 1.08), "hand_r": P(-0.30, -0.22, 1.08),
			"elbow_l": P(0.6, 0.6, -0.4), "elbow_r": P(-0.6, 0.6, -0.4),
			"foot_l": {"pos": P(0, 0.04, 0)}, "foot_r": {"pos": P(0, -0.04, 0)},
		}),
		# take-off: legs drive straight, arms swing up through the face.
		(0.10, {
			"pelvis": {"pos": P(0, 0, 0.01)},
			"spine1": lean(fwd=2), "head": lean(fwd=-22),
			"clav": clav(lift=8),
			"hand_l": P(0.20, 0.36, 1.86), "hand_r": P(-0.20, 0.36, 1.86),
			"elbow_l": P(0.8, 0.2, -1.0), "elbow_r": P(-0.8, 0.2, -1.0),
			"foot_l": {"pos": P(0, 0.06, 0.06), "pitch": 20}, "foot_r": {"pos": P(0, -0.04, 0.10), "pitch": 35},
		}),
		# climbing: lead (left) knee driven up — the pack-mark knee — trail
		# leg long and toes pointed, arms going up past the head.
		(0.24, {
			"pelvis": {"pos": P(0, 0, 0.02), "rot": lean(fwd=-3)},
			"spine1": lean(fwd=-3), "spine2": lean(fwd=-1), "head": lean(fwd=-20),
			"clav": clav(lift=16),
			"hand_l": P(0.14, 0.20, 2.30), "hand_r": P(-0.14, 0.20, 2.30),
			"elbow_l": P(1.0, 0.3, -0.4), "elbow_r": P(-1.0, 0.3, -0.4),
			"foot_l": {"pos": P(0.02, 0.32, 0.50), "pitch": 25}, "foot_r": {"pos": P(0, -0.14, 0.16), "pitch": 45},
		}),
		# contact — hand-off: apex, full stretch, hands together on the ball
		# above and just in front of the head.
		(contact, {
			"pelvis": {"pos": P(0, 0, 0.02), "rot": lean(fwd=-4)},
			"spine1": lean(fwd=-3), "spine2": lean(fwd=-2), "head": lean(fwd=-18),
			"clav": clav(lift=22),
			"hand_l": P(0.07, 0.16, 2.48), "hand_r": P(-0.07, 0.16, 2.48),
			"elbow_l": P(1.0, 0.2, -0.3), "elbow_r": P(-1.0, 0.2, -0.3),
			"foot_l": {"pos": P(0.02, 0.30, 0.46), "pitch": 25}, "foot_r": {"pos": P(0, -0.16, 0.18), "pitch": 45},
		}),
		# pull it down in front of the face — keeps the hands on the ball's
		# line instead of letting the joint-space blend swing them out wide.
		(0.48, {
			"pelvis": {"pos": P(0, 0, 0.02)},
			"spine1": lean(fwd=0), "spine2": lean(fwd=0), "head": lean(fwd=-12),
			"clav": clav(lift=14, fwd=4),
			"hand_l": P(0.09, 0.26, 2.06), "hand_r": P(-0.09, 0.26, 2.06),
			"elbow_l": P(1.0, 0.0, -0.5), "elbow_r": P(-1.0, 0.0, -0.5),
			"foot_l": {"pos": P(0.02, 0.24, 0.32), "pitch": 20}, "foot_r": {"pos": P(0, -0.08, 0.16), "pitch": 35},
		}),
		# bring it down to the chest; legs come down under the body.
		(0.58, {
			"pelvis": {"pos": P(0, 0, 0.0)},
			"spine1": lean(fwd=4), "spine2": lean(fwd=2), "head": lean(fwd=-6),
			"clav": clav(lift=4, fwd=6),
			"hand_l": P(0.08, 0.30, 1.72), "hand_r": P(-0.08, 0.30, 1.72),
			"elbow_l": P(0.5, 0.0, -1.0), "elbow_r": P(-0.5, 0.0, -1.0),
			"foot_l": {"pos": P(0, 0.14, 0.12), "pitch": 15}, "foot_r": {"pos": P(0, 0.02, 0.06), "pitch": 20},
		}),
		# pre-landing — hand-off: ball on the chest, legs reaching for the
		# ground, knees soft.
		(0.80, {
			"pelvis": {"pos": P(0, 0, -0.02)},
			"spine1": lean(fwd=6), "spine2": lean(fwd=3), "head": lean(fwd=4),
			"clav": clav(fwd=8),
			"hand_l": P(0.09, 0.27, 1.40), "hand_r": P(-0.09, 0.27, 1.40),
			"elbow_l": P(0.4, -0.1, -1.0), "elbow_r": P(-0.4, -0.1, -1.0),
			"foot_l": {"pos": P(0, 0.08, 0.02), "pitch": 5}, "foot_r": {"pos": P(0, -0.05, 0.02), "pitch": 5},
		}),
		# absorb the landing.
		(0.88, {
			"pelvis": {"pos": P(0, 0.02, -0.15)},
			"spine1": lean(fwd=12), "spine2": lean(fwd=5), "head": lean(fwd=6),
			"clav": clav(fwd=8),
			"hand_l": P(0.10, 0.28, 1.28), "hand_r": P(-0.10, 0.28, 1.28),
			"elbow_l": P(0.4, -0.1, -1.0), "elbow_r": P(-0.4, -0.1, -1.0),
			"foot_l": {"pos": P(0, 0.08, 0)}, "foot_r": {"pos": P(0, -0.06, 0)},
		}),
		(length, {}),
	])


# ── Disposals and contest reactions ────────────────────────────────────
# Same procedural timing as humanoid_animations.gd's _build_kick/_handball/
# _bounce/_hit_out/_knocked_back/_smothered/_smother_dive. Sides follow the
# gameplay markers rather than the procedural rig's naming: the procedural
# rig has "Left" bones on the anatomical right, but BootPoint and CarryPoint
# both sit on the player's right, so the kick is the right foot and the ball
# rides in the right hand.

def clip_kick():
	length, contact = ACTION_TIMING["kick"]
	# Right-foot drop punt: plant on the left, ball out in front in both
	# hands, drop it, the right leg swings through on BootPoint's line
	# (~0.5 m ahead, ~0.3 m up), follow through high with the body leaning
	# back against it.
	return Clip("kick", [
		(0.0, {}),
		# wind-up: right leg back and up, ball held out over the kicking foot.
		(contact * 0.33, {
			"pelvis": {"pos": P(0, 0.02, -0.04), "rot": lean(turn=-4)},
			"spine1": lean(fwd=5), "spine2": lean(fwd=3), "head": lean(fwd=12),
			"hand_l": P(0.04, 0.36, 1.18), "hand_r": P(-0.16, 0.36, 1.16),
			"elbow_l": P(0.6, -0.2, -1.0), "elbow_r": P(-0.6, -0.2, -1.0),
			"foot_l": {"pos": P(0, 0.14, 0)},
			"foot_r": {"pos": P(0, -0.42, 0.24), "pitch": 35},
		}),
		# drop: hands let go and part for balance, kicking leg coming through
		# knee-first.
		(contact * 0.72, {
			"pelvis": {"pos": P(0, 0.04, -0.03)},
			"spine1": lean(fwd=2), "spine2": lean(fwd=0), "head": lean(fwd=16),
			"hand_l": P(0.42, 0.26, 1.28), "hand_r": P(-0.40, -0.10, 1.16),
			"elbow_l": P(1.0, 0.0, -0.6), "elbow_r": P(-1.0, 0.3, -0.6),
			"foot_l": {"pos": P(0, 0.14, 0)},
			"foot_r": {"pos": P(0, -0.20, 0.34), "pitch": 40},
		}),
		# contact: instep through the ball on BootPoint's line, leg long,
		# torso leaning back over the plant foot, eyes on the ball.
		(contact, {
			"pelvis": {"pos": P(0, 0.06, 0.0), "rot": lean(fwd=-6, turn=4)},
			"spine1": lean(fwd=-5), "spine2": lean(fwd=-2), "head": lean(fwd=18),
			"hand_l": P(0.46, 0.30, 1.40), "hand_r": P(-0.36, -0.22, 1.20),
			"elbow_l": P(1.0, -0.2, -0.6), "elbow_r": P(-1.0, 0.4, -0.5),
			"foot_l": {"pos": P(0, 0.14, 0), "pitch": 5},
			"foot_r": {"pos": P(0.02, 0.50, 0.28), "pitch": 45},
		}),
		# follow-through: boot finishes high, left heel lifting.
		(contact + (length - contact) * 0.45, {
			"pelvis": {"pos": P(0, 0.08, 0.02), "rot": lean(fwd=-10, turn=6)},
			"spine1": lean(fwd=-6), "spine2": lean(fwd=-2), "head": lean(fwd=8),
			"hand_l": P(0.40, 0.34, 1.52), "hand_r": P(-0.36, -0.18, 1.26),
			"elbow_l": P(1.0, -0.2, -0.5), "elbow_r": P(-1.0, 0.4, -0.5),
			"foot_l": {"pos": P(0, 0.14, 0.07), "pitch": 15},
			"foot_r": {"pos": P(0.02, 0.66, 0.88), "pitch": 30},
		}),
		(length, {}),
	])


def clip_handball():
	length, contact = ACTION_TIMING["handball"]
	# Left hand is the platform holding the ball at the waist, right fist
	# punches through it — the torso winds right then drives through.
	return Clip("handball", [
		(0.0, {}),
		(contact * 0.5, {
			"pelvis": {"pos": P(0, 0, -0.03), "rot": lean(turn=-6)},
			"spine1": lean(fwd=6, turn=-6), "spine2": lean(fwd=3, turn=-4), "head": lean(fwd=10, turn=8),
			"hand_l": P(0.08, 0.34, 1.24), "hand_r": P(-0.26, 0.02, 1.22),
			"elbow_l": P(0.6, -0.2, -1.0), "elbow_r": P(-0.6, 0.8, -0.4),
			"foot_l": {"pos": P(0, 0.12, 0)}, "foot_r": {"pos": P(0, -0.06, 0)},
		}),
		# contact: fist meets the ball on the platform.
		(contact, {
			"pelvis": {"pos": P(0, 0.01, -0.03), "rot": lean(turn=4)},
			"spine1": lean(fwd=6, turn=5), "spine2": lean(fwd=3, turn=4), "head": lean(fwd=10, turn=-4),
			"hand_l": P(0.06, 0.36, 1.22), "hand_r": P(-0.02, 0.40, 1.28),
			"elbow_l": P(0.6, -0.2, -1.0), "elbow_r": P(-0.8, 0.0, -0.6),
			"foot_l": {"pos": P(0, 0.12, 0)}, "foot_r": {"pos": P(0, -0.06, 0)},
		}),
		# punch carries through and up; platform hand drops away.
		(contact + (length - contact) * 0.5, {
			"pelvis": {"pos": P(0, 0.02, -0.02), "rot": lean(turn=8)},
			"spine1": lean(fwd=4, turn=8), "spine2": lean(fwd=2, turn=5), "head": lean(fwd=4, turn=-8),
			"hand_l": P(0.26, 0.20, 1.14), "hand_r": P(-0.04, 0.58, 1.46),
			"elbow_l": P(1.0, 0.2, -0.6), "elbow_r": P(-0.8, -0.2, -0.6),
			"foot_l": {"pos": P(0, 0.12, 0)}, "foot_r": {"pos": P(0, -0.04, 0.02), "pitch": 10},
		}),
		(length, {}),
	])


def clip_bounce():
	length, contact = ACTION_TIMING["bounce"]
	# Bounce on the run: legs keep the run cycle, the ball goes from the
	# hands down into the turf in front and is taken back up — a shallow
	# reach, not a crouch (see _build_bounce's own note).
	return Clip("bounce", [
		(0.0, {
			"spine1": lean(fwd=6), "spine2": lean(fwd=3),
			"hand_l": P(0.10, 0.32, 1.30), "hand_r": P(-0.10, 0.32, 1.30),
		}),
		(contact * 0.55, {
			"spine1": lean(fwd=10), "spine2": lean(fwd=6), "head": lean(fwd=14),
			"clav": clav(fwd=8),
			"hand_l": P(0.10, 0.48, 1.12), "hand_r": P(-0.10, 0.48, 1.12),
			"elbow_l": P(0.6, -0.1, -1.0), "elbow_r": P(-0.6, -0.1, -1.0),
		}),
		# release: driven down out of the right hand, left arm out.
		(contact, {
			"spine1": lean(fwd=13), "spine2": lean(fwd=8), "head": lean(fwd=18),
			"clav": clav(fwd=10),
			"hand_l": P(0.24, 0.42, 1.04), "hand_r": P(-0.08, 0.56, 0.92),
			"elbow_l": P(0.8, 0.0, -0.8), "elbow_r": P(-0.5, -0.1, -1.0),
		}),
		# back up and running, hands taking it again.
		(contact + (length - contact) * 0.35, {
			"spine1": lean(fwd=7), "spine2": lean(fwd=3), "head": lean(fwd=4),
			"hand_l": P(0.12, 0.34, 1.26), "hand_r": P(-0.12, 0.34, 1.24),
		}),
		(length, {}),
	], legs_from=RUN_ACTION)


def clip_hit_out():
	length, contact = ACTION_TIMING["hit_out"]
	# The ruck tap: mark_aggressive's identical leap (Tuning copies its
	# timing row) palmed with the right hand; the left arm stays low with
	# the elbow out for body-work on the opposing ruck, and the landing has
	# nothing to gather.
	return Clip("hit_out", [
		(0.0, {
			"pelvis": {"pos": P(0, 0.02, -0.09)},
			"spine1": lean(fwd=10), "spine2": lean(fwd=4), "head": lean(fwd=-12),
			"hand_l": P(0.32, -0.16, 1.10), "hand_r": P(-0.30, -0.22, 1.08),
			"elbow_l": P(0.6, 0.6, -0.4), "elbow_r": P(-0.6, 0.6, -0.4),
			"foot_l": {"pos": P(0, 0.04, 0)}, "foot_r": {"pos": P(0, -0.04, 0)},
		}),
		(contact * 0.6, {
			"pelvis": {"pos": P(0, 0, 0.02), "rot": lean(left=3)},
			"spine1": lean(left=3), "head": lean(fwd=-24),
			"clav_l": clav(lift=6, fwd=6), "clav_r": mirror_q(clav(lift=18)),
			"hand_l": P(0.36, 0.22, 1.62), "hand_r": P(-0.14, 0.16, 2.24),
			"elbow_l": P(1.0, 0.0, -0.4), "elbow_r": P(-1.0, 0.3, -0.4),
			"foot_l": {"pos": P(0.02, 0.30, 0.46), "pitch": 25}, "foot_r": {"pos": P(0, -0.12, 0.16), "pitch": 45},
		}),
		# contact: right palm at full stretch above the head.
		(contact, {
			"pelvis": {"pos": P(0, 0, 0.02), "rot": lean(fwd=-3, left=5)},
			"spine1": lean(fwd=-2, left=5), "spine2": lean(left=3), "head": lean(fwd=-20, turn=-6),
			"clav_l": clav(lift=6, fwd=8), "clav_r": mirror_q(clav(lift=24)),
			"hand_l": P(0.38, 0.24, 1.66), "hand_r": P(-0.10, 0.18, 2.50),
			"elbow_l": P(1.0, 0.0, -0.4), "elbow_r": P(-1.0, 0.2, -0.3),
			"wrist_r": lean(fwd=-25),
			"foot_l": {"pos": P(0.02, 0.30, 0.46), "pitch": 25}, "foot_r": {"pos": P(0, -0.16, 0.18), "pitch": 45},
		}),
		(contact + (length - contact) * 0.5, {
			"pelvis": {"pos": P(0, 0, -0.04)},
			"spine1": lean(fwd=5), "spine2": lean(fwd=2), "head": lean(fwd=2),
			"hand_l": P(0.40, 0.10, 1.24), "hand_r": P(-0.36, 0.16, 1.40),
			"elbow_l": P(1.0, 0.2, -0.6), "elbow_r": P(-1.0, 0.2, -0.6),
			"foot_l": {"pos": P(0, 0.08, 0.03), "pitch": 5}, "foot_r": {"pos": P(0, -0.05, 0.03), "pitch": 5},
		}),
		# absorb the landing.
		(0.88, {
			"pelvis": {"pos": P(0, 0.02, -0.13)},
			"spine1": lean(fwd=10), "spine2": lean(fwd=4), "head": lean(fwd=4),
			"hand_l": P(0.40, 0.14, 1.12), "hand_r": P(-0.40, 0.14, 1.12),
			"elbow_l": P(1.0, 0.2, -0.6), "elbow_r": P(-1.0, 0.2, -0.6),
			"foot_l": {"pos": P(0, 0.08, 0)}, "foot_r": {"pos": P(0, -0.06, 0)},
		}),
		(length, {}),
	])


def clip_knocked_back():
	length, contact = ACTION_TIMING["knocked_back"]
	# A clean bump from the front: driven straight back onto the backside
	# and then the back, still facing the way they were (KNOCKED_BACK skips
	# _fall_toward's facing snap), a beat on the ground, then up through a
	# crouch. Same beat structure as the hand-authored `tackled` fall on
	# this rig (down by ~0.5 s, held, up by the end), mirrored onto the back
	# without mirroring the knees. Arms ride the chest frame so they fall
	# with the torso. Hand-off candidate for ragdoll stage 2: the 0.15 s
	# key (airborne, balance gone, limbs clear of the body).
	return Clip("knocked_back", [
		# impact: hips knocked back under the torso, arms thrown forward,
		# chin tucked.
		(0.0, {
			"pelvis": {"pos": P(0, -0.08, -0.05), "rot": lean(fwd=-12)},
			"spine1": lean(fwd=6), "spine2": lean(fwd=4), "head": lean(fwd=14),
			"hands_in": "chest",
			"hand_l": P(0.30, 0.42, -0.10), "hand_r": P(-0.30, 0.42, -0.10),
			"elbow_l": P(1.0, -0.2, -0.6), "elbow_r": P(-1.0, -0.2, -0.6),
			"foot_l": {"pos": P(0, -0.10, 0.08)}, "foot_r": {"pos": P(0, 0.04, 0)},
		}),
		# going over backwards.
		(0.15, {
			"pelvis": {"pos": P(0, -0.26, -0.40), "rot": lean(fwd=-38)},
			"spine1": lean(fwd=8), "spine2": lean(fwd=4), "head": lean(fwd=22),
			"hands_in": "chest",
			"hand_l": P(0.40, 0.40, 0.00), "hand_r": P(-0.40, 0.40, 0.00),
			"elbow_l": P(1.0, -0.2, -0.4), "elbow_r": P(-1.0, -0.2, -0.4),
			"foot_l": {"pos": P(0, 0.06, 0.12)}, "foot_r": {"pos": P(0, 0.10, 0.04)},
		}),
		# contact: backside hits the turf, knees up.
		(contact, {
			"pelvis": {"pos": P(0, -0.44, -0.86), "rot": lean(fwd=-62)},
			"spine1": lean(fwd=10), "spine2": lean(fwd=6), "head": lean(fwd=26),
			"hands_in": "chest",
			"hand_l": P(0.42, 0.10, -0.22), "hand_r": P(-0.42, 0.10, -0.22),
			"elbow_l": P(1.0, 0.0, -0.4), "elbow_r": P(-1.0, 0.0, -0.4),
			"foot_l": {"pos": P(0, 0.16, 0)}, "foot_r": {"pos": P(0, 0.22, 0)},
		}),
		# flat on the back, head held up off the ground.
		(contact + (length - contact) * 0.30, {
			"pelvis": {"pos": P(0, -0.52, -0.99), "rot": lean(fwd=-92)},
			"spine1": lean(fwd=4), "spine2": lean(fwd=2), "head": lean(fwd=24),
			"hands_in": "chest",
			"hand_l": P(0.48, -0.04, -0.10), "hand_r": P(-0.48, -0.04, -0.10),
			"elbow_l": P(1.0, 0.4, 0.0), "elbow_r": P(-1.0, 0.4, 0.0),
			"foot_l": {"pos": P(0, 0.10, 0)}, "foot_r": {"pos": P(0, 0.20, 0)},
		}),
		# sitting up, hands pushing off the ground behind.
		(contact + (length - contact) * 0.55, {
			"pelvis": {"pos": P(0, -0.50, -0.96), "rot": lean(fwd=-66)},
			"spine1": lean(fwd=18), "spine2": lean(fwd=10), "head": lean(fwd=12),
			"hands_in": "chest",
			"hand_l": P(0.34, -0.10, -0.30), "hand_r": P(-0.34, -0.10, -0.30),
			"elbow_l": P(0.6, -1.0, 0.0), "elbow_r": P(-0.6, -1.0, 0.0),
			"foot_l": {"pos": P(0, 0.0, 0)}, "foot_r": {"pos": P(0, 0.06, 0)},
		}),
		# up through a crouch over the feet.
		(contact + (length - contact) * 0.80, {
			"pelvis": {"pos": P(0, -0.20, -0.50), "rot": lean(fwd=24)},
			"spine1": lean(fwd=14), "spine2": lean(fwd=6), "head": lean(fwd=-6),
			"hands_in": "chest",
			"hand_l": P(0.10, 0.34, -0.42), "hand_r": P(-0.10, 0.34, -0.42),
			"elbow_l": P(1.0, 0.0, -0.4), "elbow_r": P(-1.0, 0.0, -0.4),
			"foot_l": {"pos": P(0, -0.12, 0)}, "foot_r": {"pos": P(0, -0.04, 0)},
		}),
		(contact + (length - contact) * 0.93, {
			"pelvis": {"pos": P(0, -0.04, -0.10), "rot": lean(fwd=6)},
			"spine1": lean(fwd=6), "spine2": lean(fwd=2),
			"foot_l": {"pos": P(0, -0.04, 0)}, "foot_r": {"pos": P(0, 0.0, 0)},
		}),
		(length, {}),
	])


def clip_smothered():
	length, contact = ACTION_TIMING["smothered"]
	# The kicker whose kick was blocked: a flinch back off the boot, arms up
	# in front of the face, half a step back on the kicking (right) foot.
	return Clip("smothered", [
		(0.0, {}),
		(contact, {
			"pelvis": {"pos": P(0, -0.06, -0.04), "rot": lean(fwd=-8)},
			"spine1": lean(fwd=-6), "spine2": lean(fwd=-2), "head": lean(fwd=10, turn=10),
			"clav": clav(lift=6, fwd=4),
			"hand_l": P(0.16, 0.26, 1.72), "hand_r": P(-0.14, 0.24, 1.66),
			"elbow_l": P(0.6, -0.2, -1.0), "elbow_r": P(-0.6, -0.2, -1.0),
			"foot_l": {"pos": P(0, 0.06, 0)}, "foot_r": {"pos": P(0, -0.24, 0.04), "pitch": 10},
		}),
		(contact + (length - contact) * 0.55, {
			"pelvis": {"pos": P(0, -0.05, -0.03), "rot": lean(fwd=-3)},
			"spine1": lean(fwd=-2), "head": lean(fwd=6, turn=4),
			"hand_l": P(0.30, 0.20, 1.36), "hand_r": P(-0.30, 0.18, 1.34),
			"elbow_l": P(1.0, 0.0, -0.6), "elbow_r": P(-1.0, 0.0, -0.6),
			"foot_l": {"pos": P(0, 0.04, 0)}, "foot_r": {"pos": P(0, -0.20, 0)},
		}),
		(length, {}),
	])


def clip_smother_dive():
	length, contact = ACTION_TIMING["smother_dive"]
	# Committed dive at the kicker's boot (the playtest ask: it has to go to
	# ground): load on the left, launch, full stretch with both arms just off
	# the turf at contact, held. The last key snaps back to the base pose
	# because Tuning ends the action there (see the timing note in the
	# checkpoint report — a real get-up needs a longer ACTION_DURATION).
	return Clip("smother_dive", [
		(0.0, {}),
		(contact * 0.35, {
			"pelvis": {"pos": P(0, 0.06, -0.14), "rot": lean(fwd=14)},
			"spine1": lean(fwd=10), "spine2": lean(fwd=4), "head": lean(fwd=-6),
			"hand_l": P(0.20, 0.56, 1.08), "hand_r": P(-0.20, 0.56, 1.08),
			"elbow_l": P(0.8, -0.2, -1.0), "elbow_r": P(-0.8, -0.2, -1.0),
			"foot_l": {"pos": P(0, 0.26, 0)}, "foot_r": {"pos": P(0, -0.16, 0.06), "pitch": 25},
		}),
		(contact * 0.7, {
			"pelvis": {"pos": P(0, 0.30, -0.42), "rot": lean(fwd=42)},
			"spine1": lean(fwd=8), "spine2": lean(fwd=2), "head": lean(fwd=-18),
			"hands_in": "chest",
			"hand_l": P(0.16, 0.56, 0.10), "hand_r": P(-0.16, 0.56, 0.10),
			"elbow_l": P(1.0, 0.0, -0.6), "elbow_r": P(-1.0, 0.0, -0.6),
			"foot_l": {"pos": P(0, 0.20, 0.08), "pitch": 20}, "foot_r": {"pos": P(0, -0.46, 0.34), "pitch": 40},
		}),
		# contact: body near the ground, arms full length at the boot.
		(contact, {
			"pelvis": {"pos": P(0, 0.56, -0.76), "rot": lean(fwd=66)},
			"spine1": lean(fwd=6), "spine2": lean(fwd=0), "head": lean(fwd=-26),
			"hands_in": "chest",
			"hand_l": P(0.14, 0.50, 0.36), "hand_r": P(-0.14, 0.50, 0.36),
			"elbow_l": P(1.0, 0.0, -0.4), "elbow_r": P(-1.0, 0.0, -0.4),
			"foot_l": {"pos": P(0, 0.02, 0.13), "pitch": 30}, "foot_r": {"pos": P(0, -0.52, 0.30), "pitch": 45},
		}),
		(contact + (length - contact) * 0.75, {
			"pelvis": {"pos": P(0, 0.54, -0.74), "rot": lean(fwd=62)},
			"spine1": lean(fwd=6), "spine2": lean(fwd=0), "head": lean(fwd=-22),
			"hands_in": "chest",
			"hand_l": P(0.16, 0.48, 0.32), "hand_r": P(-0.16, 0.48, 0.32),
			"elbow_l": P(1.0, 0.0, -0.4), "elbow_r": P(-1.0, 0.0, -0.4),
			"foot_l": {"pos": P(0, 0.02, 0.13), "pitch": 30}, "foot_r": {"pos": P(0, -0.48, 0.26), "pitch": 40},
		}),
		(length, {}),
	])


CLIPS = {
	"mark_safe": clip_mark_safe,
	"mark_running": clip_mark_running,
	"mark_aggressive": clip_mark_aggressive,
	"mark_safe_miss": clip_mark_safe_miss,
	"mark_running_miss": clip_mark_running_miss,
	"kick": clip_kick,
	"handball": clip_handball,
	"bounce": clip_bounce,
	"hit_out": clip_hit_out,
	"knocked_back": clip_knocked_back,
	"smothered": clip_smothered,
	"smother_dive": clip_smother_dive,
}


def main():
	argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
	save = "--no-save" not in argv
	names = [a for a in argv if not a.startswith("--")] or list(CLIPS.keys())

	arm_obj = bpy.data.objects[ARMATURE]
	fps = bpy.context.scene.render.fps
	ad = arm_obj.animation_data
	saved_action = ad.action
	saved_mutes = {t.name: t.mute for t in ad.nla_tracks}
	# Evaluate the bare rig for calibration: no action, no NLA.
	ad.action = None
	for t in ad.nla_tracks:
		t.mute = True
	for name in FK_BONES + LEG_CONTROL_BONES:
		pb = arm_obj.pose.bones[name]
		pb.location = (0, 0, 0)
		pb.rotation_quaternion = (1, 0, 0, 0)
		pb.rotation_euler = (0, 0, 0)
	calibrate_foot_pitch(arm_obj)

	rig = Rig(arm_obj)
	base = sample_action(rig, bpy.data.actions[BASE_ACTION], bpy.data.actions[BASE_ACTION].frame_range[0])
	for name in names:
		author_clip(rig, CLIPS[name](), base, fps)

	ad.action = saved_action
	for t in ad.nla_tracks:
		t.mute = saved_mutes.get(t.name, True)
	if save:
		bpy.ops.wm.save_mainfile()
		print("author_6thbuild_clips: saved", bpy.data.filepath)


if __name__ == "__main__":
	main()
