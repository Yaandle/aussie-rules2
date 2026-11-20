"""Animation deformation audit for Build 8: does the mesh stretch, squash or
collapse unrealistically in any clip or ragdoll pose?

check_8thbuild_deform.py answers "does one layer come through another"
and catches only gross faults (a face under 15% or over 300% of its rest
area). This asks the finer question, per body region:

* bones   - does the clip itself stretch the skeleton? A deform bone whose
            posed length or scale differs from rest warps everything on it,
            however good the weights. Should be 0.
* strain  - each edge's length against rest, grouped by the bone that owns
            its vertices (a "joint" region where two bones share them).
            Skin over a real elbow or knee stretches ~20-30% on the outside
            of the bend and bunches on the inside; much past that reads as
            rubber.
* volume  - each vertex's distance from its own bones (the nearest point on
            the posed segments of the bones it's weighted to) against rest.
            Linear blend skinning loses volume at a bent or twisted joint:
            a ratio well under 1 is the classic pinched elbow or collapsed
            "candy wrapper" twist, well over 1 a bulge.
* rigid   - head, hair, hands and boots should keep their shape exactly:
            the worst edge strain there.

    blender assets/blender/8thbuild.blend --background --python tools/blender/audit_8thbuild_anim.py
    blender ... --python tools/blender/audit_8thbuild_anim.py -- --only=kick,rd_fetal --frames

--frames prints the frame of each worst value, to render it. Nothing is
saved; it restores the action, pose and constraints as the checker does.
"""

import math
import os
import sys

import bpy
from mathutils import Matrix

sys.dont_write_bytecode = True   # no __pycache__ in tools/blender
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import check_8thbuild_deform as chk   # noqa: E402  (RAGDOLL_POSES, _pose_ragdoll)

ARMATURE = "Armature"
MESHES = ["B8_Body", "B8_Guernsey", "B8_Shorts", "B8_Boots", "B8_Hair"]
STEP = 2
MIN_EDGE = 0.004            # ignore edges shorter than this at rest (m)
## Flag thresholds: realistic skin and cloth limits for a low-poly body.
## Unplaytested judgement calls, not measurements.
STRAIN_HI = 1.35
STRAIN_LO = 0.70
VOLUME_LO = 0.70
VOLUME_HI = 1.35
RIGID_TOL = 0.02
BONE_TOL = 0.01
## Region names for the report.
RIGID_BONES = {"head", "hand.l", "hand.r", "foot.l", "foot.r"}


def _deform_bones(arm):
	return [b for b in arm.data.bones if b.use_deform]


def _vertex_bones(ob):
	"""Per vertex: [(bone, weight)] strongest first."""
	names = {g.index: g.name for g in ob.vertex_groups}
	out = []
	for v in ob.data.vertices:
		gs = sorted(((names[g.group], g.weight) for g in v.groups if g.weight > 1e-4), key=lambda x: -x[1])
		out.append(gs)
	return out


def _region(gs):
	if not gs:
		return "?"
	if len(gs) > 1 and gs[1][1] >= 0.2:
		return "+".join(sorted((gs[0][0], gs[1][0])))
	return gs[0][0]


def _segments(arm, rest):
	segs = {}
	for b in _deform_bones(arm):
		if rest:
			h, t = arm.matrix_world @ b.head_local, arm.matrix_world @ b.tail_local
		else:
			pb = arm.pose.bones[b.name]
			h, t = arm.matrix_world @ pb.head, arm.matrix_world @ pb.tail
		segs[b.name] = (h, t)
	return segs


def _dist_to_seg(p, seg):
	h, t = seg
	ax = t - h
	k = max(0.0, min(1.0, (p - h).dot(ax) / max(ax.length_squared, 1e-12)))
	return (p - (h + ax * k)).length


def _bone_dist(p, gs, segs):
	"""Distance to the nearest of the vertex's weighted bones (weight >= 0.2,
	or its strongest)."""
	names = [b for b, w in gs if w >= 0.2] or [gs[0][0]]
	return min(_dist_to_seg(p, segs[b]) for b in names if b in segs)


class Mesh:
	def __init__(self, ob, dg, segs):
		self.ob = ob
		self.vb = _vertex_bones(ob)
		verts, _, _ = chk._evaluated(ob, dg)
		self.edges = [(e.vertices[0], e.vertices[1]) for e in ob.data.edges]
		self.rest_len = [(verts[a] - verts[b]).length for a, b in self.edges]
		name = ob.name
		self.hidden_v = [_hidden(name, v, _region(gs)) for v, gs in zip(verts, self.vb)]
		self.region_e = []
		self.where_e = []
		for a, b in self.edges:
			ra, rb = _region(self.vb[a]), _region(self.vb[b])
			reg = ra if ra == rb else "+".join(sorted(set(ra.split("+")) | set(rb.split("+"))))
			rigid = all(self.vb[k] and self.vb[k][0][1] > 0.99 and self.vb[k][0][0] in RIGID_BONES for k in (a, b))
			if name == "B8_Hair" or rigid:
				reg = "rigid " + (reg if name != "B8_Hair" else "hair")
			elif self.hidden_v[a] and self.hidden_v[b]:
				reg = "hidden " + reg
			self.region_e.append(reg)
			m = (verts[a] + verts[b]) * 0.5
			self.where_e.append("(%.2f %.2f %.2f)" % (m.x, m.y, m.z))
		self.rest_d = [(_bone_dist(v, gs, segs) if gs else 0.0) for v, gs in zip(verts, self.vb)]
		self.region_v = [("hidden " if h else "") + _region(gs) for gs, h in zip(self.vb, self.hidden_v)]


## Rest heights that bound what's covered by another layer: the body's thigh
## cone inside the shorts (above the hem, ~0.83 m), the sock inside the boot,
## the neck's base inside the collar, and the shorts' waist under the
## guernsey (above its hem, 1.168 m).
SHORTS_HEM_Z = 0.86
BOOT_TOP_Z = 0.125
GUERNSEY_HEM_Z = 1.15


def _hidden(mesh, v, region):
	if mesh == "B8_Body":
		if v.z > SHORTS_HEM_Z and v.z < 1.35 and ("upperleg" in region or "pelvis" in region):
			return True
		if v.z < BOOT_TOP_Z:
			return True
		if 1.70 < v.z < 1.80 and abs(v.x) < 0.10:
			return True
		# The skin shell under the guernsey's strap (the turnaround pass's
		# V-neck): only the V at the front shows, and the arms' domes are
		# on upperarm, so they don't match here.
		if 1.70 < v.z < 1.86 and abs(v.x) > 0.10 and "upperarm" not in region:
			return True
	if mesh == "B8_Shorts" and v.z > GUERNSEY_HEM_Z:
		return True
	return False


def sample(meshes, arm, dg, bone_rest):
	"""{metric key: (value, detail)}, worst per key for this frame."""
	out = {}

	def keep(key, val, worse):
		if key not in out or worse(val, out[key]):
			out[key] = val

	segs = _segments(arm, rest=False)
	for b in _deform_bones(arm):
		h, t = segs[b.name]
		r = (h - t).length / max(bone_rest[b.name], 1e-9)
		sc = arm.pose.bones[b.name].matrix.to_scale()
		dev = max(abs(r - 1.0), max(abs(s - 1.0) for s in sc))
		keep("bones", (dev, b.name), lambda a, c: a[0] > c[0])
	for name, m in meshes.items():
		verts, _, _ = chk._evaluated(m.ob, dg)
		for (a, b), l0, reg, where in zip(m.edges, m.rest_len, m.region_e, m.where_e):
			if l0 < MIN_EDGE:
				continue
			r = (verts[a] - verts[b]).length / l0
			if reg.startswith("rigid"):
				keep(reg, (abs(r - 1.0), where), lambda x, c: x[0] > c[0])
				continue
			k = "%s %s" % (name[3:].lower(), reg)
			keep(k + " hi", (r, where), lambda x, c: x[0] > c[0])
			keep(k + " lo", (r, where), lambda x, c: x[0] < c[0])
		if name in ("B8_Body",):
			segs_now = segs
			for i, v in enumerate(verts):
				gs = m.vb[i]
				d0 = m.rest_d[i]
				if not gs or d0 < 0.02 or m.region_v[i] in RIGID_BONES:
					continue
				r = _bone_dist(v, gs, segs_now) / d0
				k = "volume " + m.region_v[i]
				where = "v%d" % i
				keep(k + " lo", (r, where), lambda x, c: x[0] < c[0])
				keep(k + " hi", (r, where), lambda x, c: x[0] > c[0])
	return out


def flagged(key, val):
	v = val[0]
	if " hidden " in key or key.startswith("volume hidden"):
		return False
	if key == "bones":
		return v > BONE_TOL
	if key.startswith("rigid"):
		return v > RIGID_TOL
	if key.startswith("volume"):
		return v < VOLUME_LO if key.endswith(" lo") else v > VOLUME_HI
	return v > STRAIN_HI if key.endswith(" hi") else v < STRAIN_LO


def audit(only=None, step=STEP):
	arm = bpy.data.objects[ARMATURE]
	ad = arm.animation_data
	saved = (ad.action, ad.action_slot, ad.use_nla, arm.data.pose_position, bpy.context.scene.frame_current)
	arm.data.pose_position = 'REST'
	bpy.context.view_layer.update()
	dg = bpy.context.evaluated_depsgraph_get()
	segs_rest = _segments(arm, rest=True)
	bone_rest = {n: (h - t).length for n, (h, t) in segs_rest.items()}
	meshes = {n: Mesh(bpy.data.objects[n], dg, segs_rest) for n in MESHES if n in bpy.data.objects}
	arm.data.pose_position = 'POSE'
	ad.use_nla = False
	report = {}
	muted = []

	def merge(worst, res, fr):
		for k, val in res.items():
			cur = worst.get(k)
			hi = k == "bones" or k.startswith("rigid") or k.endswith(" hi")
			if cur is None or (val[0] > cur[0][0] if hi else val[0] < cur[0][0]):
				worst[k] = (val, fr)

	try:
		for act in sorted(bpy.data.actions, key=lambda a: a.name):
			if (only and act.name not in only) or act.name.endswith("_backup"):
				continue
			ad.action = act
			if act.slots:
				ad.action_slot = act.slots[0]
			f0, f1 = (int(x) for x in act.frame_range)
			worst = {}
			for fr in list(range(f0, f1 + 1, step)) + [f1]:
				bpy.context.scene.frame_set(fr)
				merge(worst, sample(meshes, arm, bpy.context.evaluated_depsgraph_get(), bone_rest), fr)
			report[act.name] = worst
		ad.action = None
		for pb in arm.pose.bones:
			for c in pb.constraints:
				if not c.mute:
					c.mute = True
					muted.append(c)
		for name, moves in chk.RAGDOLL_POSES.items():
			if only and name not in only:
				continue
			for pb in arm.pose.bones:
				pb.matrix_basis = Matrix.Identity(4)
			chk._pose_ragdoll(arm, moves)
			worst = {}
			merge(worst, sample(meshes, arm, bpy.context.evaluated_depsgraph_get(), bone_rest), 0)
			report[name] = worst
	finally:
		for c in muted:
			c.mute = False
		for pb in arm.pose.bones:
			pb.matrix_basis = Matrix.Identity(4)
		ad.action, slot, ad.use_nla, arm.data.pose_position, fr = saved
		if slot is not None:
			ad.action_slot = slot
		bpy.context.scene.frame_set(fr)
	return report


if __name__ == "__main__":
	args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
	only = None
	for a in args:
		if a.startswith("--only="):
			only = set(a[len("--only="):].split(","))
	show_frames = "--frames" in args
	rep = audit(only)
	summary = {}
	for clip, worst in rep.items():
		flags = []
		for k, (val, fr) in sorted(worst.items()):
			if flagged(k, val):
				flags.append("%s %.2f%s%s" % (k, val[0], " " + val[1] if val[1] else "", " @%d" % fr if show_frames else ""))
				s = summary.setdefault(k, [])
				s.append((val[0], clip, fr, val[1]))
		print("%-20s %s" % (clip, "; ".join(flags) if flags else "ok"))
	print("\nWORST PER METRIC (value, clip, frame):")
	for k in sorted(summary):
		hi = k == "bones" or k.startswith("rigid") or k.endswith(" hi")
		items = sorted(summary[k], key=lambda x: -x[0] if hi else x[0])[:4]
		print("  %-40s %s" % (k, ", ".join("%.2f %s@%d %s" % it for it in items)))
	# Region extremes over everything, flagged or not, for context.
	ext = {}
	for clip, worst in rep.items():
		for k, (val, fr) in worst.items():
			hi = k == "bones" or k.startswith("rigid") or k.endswith(" hi")
			cur = ext.get(k)
			if cur is None or (val[0] > cur[0] if hi else val[0] < cur[0]):
				ext[k] = (val[0], clip, fr)
	print("\nEXTREMES (all regions):")
	for k in sorted(ext):
		print("  %-40s %.2f %s@%d" % ((k,) + ext[k]))
