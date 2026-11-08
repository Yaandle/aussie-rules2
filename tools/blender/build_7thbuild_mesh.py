"""Builds Build 7's ("7thbuild") player mesh on 6thbuild's own Armature.

Run with assets/blender/7thbuild.blend open. That file started as a byte
copy of 6thbuild.blend (F:\\dev\\learning-&-development\\New Folder), so it
has the same Armature, the same 28 actions and the same IK helpers. This
script only ever touches meshes and materials: it deletes the copy's four
Build 6 meshes (Body/Shirt/Shorts/Shoes, gone from the COPY only, the Build
6 file is never opened for writing) and generates five new ones, parented
to the untouched Armature. Re-running replaces them, so tune the tables
below and run it again rather than hand-editing the result (or hand-edit
and stop re-running: either way, say which in the commit).

    blender assets/blender/7thbuild.blend --background --python tools/blender/build_7thbuild_mesh.py -- --save

or from the Scripting tab / the Blender MCP: exec this file, then save.

Why it's generated rather than sculpted: every part is a loft of rings
along a bone, so each vertex knows exactly where it sits on the skeleton.
That gives two things a hand-modelled mesh has to earn:

* Deliberate topology. Every joint gets a ring on the pivot plus a support
  ring either side, and that's where the extra geometry goes; a long
  straight segment gets two or three rings and no more.
* Explicit skin weights. Build 6's Body and Shirt didn't take Blender's
  automatic (heat) weights at all (one coarse box overlapping everything).
  Here each ring's weights are written from its position: 50/50 on a
  joint's pivot ring, a short blend either side, rigid in between. Cloth
  and the skin under it use the SAME weight functions at the same height
  (torso_w, ankle_foot), so a bend moves them together instead of pushing
  one through the other.

Parts that meet at a ball joint (arm into the guernsey, thigh into the
shorts, hand into the forearm, neck into the head) overlap rather than
weld: the inner part ends in a dome centred on the joint's pivot, rigid to
its own bone, so it turns in place and never opens a gap. That's the
standard low-poly trick, and it keeps each part a clean tube.

Gameplay doesn't read any of this. The skeleton (bone names, rests,
hierarchy) is 6thbuild's, unchanged, and every gameplay anchor and every
ragdoll body is built from the skeleton (PhysicsRagdoll.BODIES), not the
mesh. See docs/BUILD7_MODEL.md.

Materials follow HumanoidRig's recolour-by-name contract (Shirt / Short /
Sock / Boot / Skin), plus "Trim" and "Number", which HumanoidRig colours to
contrast with the jersey. Hair, Eyes and Studs keep their authored colour.
"""

import math
import sys

import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree

ARMATURE = "Armature"
BUILD6_MESHES = ["Body", "Shirt", "Shorts", "Shoes"]
PREFIX = "B7_"
NUMBER_TEXT = "17"

FORWARD = Vector((0.0, -1.0, 0.0))   # Blender: the rig faces -Y
UP = Vector((0.0, 0.0, 1.0))

## name -> (base colour RGBA, roughness). Colours are only the look in
## Blender and when a slot isn't recoloured; see HumanoidRig.
## IMPORTED_MATERIAL_SLOTS for which names Godot overrides.
MATERIALS = {
	"Skin_Mat": ((0.80, 0.56, 0.40, 1.0), 0.62),
	"Shirt_Mat": ((0.86, 0.72, 0.30, 1.0), 0.82),
	"Trim_Mat": ((0.94, 0.92, 0.86, 1.0), 0.80),
	"Number_Mat": ((0.94, 0.92, 0.86, 1.0), 0.70),
	"Shorts_Mat": ((0.12, 0.12, 0.14, 1.0), 0.85),
	"Socks_Mat": ((0.94, 0.92, 0.86, 1.0), 0.90),
	"Boots_Mat": ((0.10, 0.10, 0.11, 1.0), 0.45),
	"Studs_Mat": ((0.62, 0.62, 0.64, 1.0), 0.50),
	"Hair_Mat": ((0.13, 0.09, 0.06, 1.0), 0.75),
	"Eyes_Mat": ((0.05, 0.05, 0.06, 1.0), 0.30),
}


# ── small helpers ─────────────────────────────────────────────────────

def clamp01(x):
	return 0.0 if x < 0.0 else 1.0 if x > 1.0 else x


def ramp(x, x0, x1):
	return clamp01((x - x0) / (x1 - x0))


def lerp(a, b, t):
	return a + (b - a) * t


def blend(a, b, t):
	"""Weights a -> b by t (0 = all a)."""
	if t <= 0.0:
		return {a: 1.0}
	if t >= 1.0:
		return {b: 1.0}
	return {a: 1.0 - t, b: t}


def bone(name):
	b = bpy.data.objects[ARMATURE].data.bones[name]
	return b.head_local.copy(), b.tail_local.copy()


def frame(axis, side_sign):
	"""(axis, side, front): front is FORWARD made perpendicular to the
	axis; side points away from the body's midline (side_sign +1 = left,
	+X). For an arm in the A-pose that's up-and-out, for a leg straight
	out."""
	a = axis.normalized()
	f = (FORWARD - a * FORWARD.dot(a)).normalized()
	s = f.cross(a).normalized() * side_sign
	return a, s, f


def profile_point(c, s, f, theta, prof):
	"""A point on a ring: theta 0 = side (out), 90 = front, 180 = in,
	270 = back. prof: out/in/front/back radii plus optional bulges
	[(deg, width deg, amount)] for muscle shapes."""
	co, si = math.cos(theta), math.sin(theta)
	rs = prof["out"] if co >= 0.0 else prof["in"]
	rf = prof["front"] if si >= 0.0 else prof["back"]
	p = s * (co * rs) + f * (si * rf)
	for deg, width, amount in prof.get("bulge", ()):
		d = math.degrees(math.atan2(math.sin(theta - math.radians(deg)), math.cos(theta - math.radians(deg))))
		k = 1.0 - (d / width) ** 2
		if k > 0.0:
			p += p.normalized() * (amount * k)
	return c + p


def P(out, inn, front, back, bulge=()):
	return {"out": out, "in": inn, "front": front, "back": back, "bulge": bulge}


def grow(prof, d):
	return P(prof["out"] + d, prof["in"] + d, prof["front"] + d, prof["back"] + d, prof["bulge"])


# ── mesh assembly ─────────────────────────────────────────────────────

class Part:
	"""Vertices with weights and faces with materials, oriented as they're
	added (no normal recalculation guesswork on thin lips)."""

	def __init__(self, name):
		self.name = name
		self.co = []
		self.w = []
		self.faces = []

	def v(self, co, w):
		total = sum(w.values())
		self.co.append(Vector(co))
		self.w.append({k: x / total for k, x in w.items() if x > 1e-4})
		return len(self.co) - 1

	def ring(self, pts, w):
		return [self.v(p, w(p) if callable(w) else w) for p in pts]

	def face(self, idx, mat, out):
		"""`out`: a direction the face should point along, or a point it
		should point away from (Vector wrapped in a tuple: (point,))."""
		pts = [self.co[i] for i in idx]
		n = Vector()   # Newell's normal: holds for quads and the number's n-gons
		for a, b in zip(pts, pts[1:] + pts[:1]):
			n += Vector(((a.y - b.y) * (a.z + b.z), (a.z - b.z) * (a.x + b.x), (a.x - b.x) * (a.y + b.y)))
		centre = sum(pts, Vector()) / len(pts)
		ref = (centre - out[0]) if isinstance(out, tuple) else out
		if n.dot(ref) < 0.0:
			idx = list(reversed(idx))
		self.faces.append((list(idx), mat))

	def bridge(self, ra, rb, mat, ca, cb, closed=True, hint=None, mats=None):
		"""Quads between two rings of equal size. Each face points away
		from the line ca-cb (radially) unless `hint` gives a direction."""
		n = len(ra)
		axis = cb - ca
		for i in range(n if closed else n - 1):
			j = (i + 1) % n
			quad = [ra[i], ra[j], rb[j], rb[i]]
			if hint is not None:
				out = hint
			else:
				centre = sum((self.co[k] for k in quad), Vector()) / 4.0
				t = (centre - ca).dot(axis) / max(axis.length_squared, 1e-9)
				out = (ca + axis * t,)
			self.face(quad, mats[i] if mats else mat, out)

	def cap(self, ring, apex, w, mat, closed=True):
		a = self.v(apex, w)
		centre = sum((self.co[k] for k in ring), Vector()) / len(ring)
		out = (self.co[a] - centre)
		n = len(ring)
		for i in range(n if closed else n - 1):
			self.face([ring[i], ring[(i + 1) % n], a], mat, out)
		return a

	def loft(self, rings, mat, n, phase, frame_fn, mats_fn=None):
		"""rings: [(centre, axis, prof, weights)], built in order and bridged.
		Returns the vertex index lists."""
		out = []
		for c, axis, prof, w in rings:
			a, s, f = frame_fn(axis)
			pts = [profile_point(c, s, f, phase + 2.0 * math.pi * i / n, prof) for i in range(n)]
			out.append(self.ring(pts, w))
		for k in range(len(rings) - 1):
			m = mats_fn(k) if mats_fn else mat
			self.bridge(out[k], out[k + 1], m, rings[k][0], rings[k + 1][0])
		return out

	def bvh(self):
		return BVHTree.FromPolygons([tuple(c) for c in self.co], [f for f, _ in self.faces])


def material(name):
	m = bpy.data.materials.get(name)
	if m is None:
		m = bpy.data.materials.new(name)
	colour, rough = MATERIALS[name]
	m.diffuse_color = colour
	m.roughness = rough
	m.use_nodes = True
	bsdf = m.node_tree.nodes.get("Principled BSDF")
	if bsdf is not None:
		bsdf.inputs["Base Color"].default_value = colour
		bsdf.inputs["Roughness"].default_value = rough
		bsdf.inputs["Metallic"].default_value = 0.0
	return m


def build_object(part, arm_obj, collection):
	name = PREFIX + part.name
	old = bpy.data.objects.get(name)
	if old is not None:
		old_me = old.data
		bpy.data.objects.remove(old, do_unlink=True)
		bpy.data.meshes.remove(old_me, do_unlink=True)
	me = bpy.data.meshes.new(name)
	mats = []
	for _, m in part.faces:
		if m not in mats:
			mats.append(m)
	me.from_pydata([tuple(c) for c in part.co], [], [f for f, _ in part.faces])
	for poly, (_, m) in zip(me.polygons, part.faces):
		poly.material_index = mats.index(m)
		poly.use_smooth = False
	for m in mats:
		me.materials.append(material(m))
	me.validate()
	me.update()
	ob = bpy.data.objects.new(name, me)
	collection.objects.link(ob)
	ob.parent = arm_obj
	groups = {}
	for i, w in enumerate(part.w):
		for b, x in w.items():
			vg = groups.get(b)
			if vg is None:
				vg = ob.vertex_groups.new(name=b)
				groups[b] = vg
			vg.add([i], x, 'REPLACE')
	mod = ob.modifiers.new("Armature", 'ARMATURE')
	mod.object = arm_obj
	return ob


# ── weights shared by skin and cloth ──────────────────────────────────

def spine_y(z):
	"""The spine's y at height z, from the bones (it leans a touch)."""
	ph, pt = bone("pelvis")
	_, s1t = bone("spine1")
	if z <= pt.z:
		return lerp(ph.y, pt.y, ramp(z, ph.z, pt.z))
	return lerp(pt.y, s1t.y, ramp(z, pt.z, s1t.z))


def torso_w(p):
	"""Guernsey, shorts waist, collar: pelvis -> spine1 -> spine2 by
	height, the shoulder (clavicle) bones over the top of each shoulder,
	and a touch of head at the collar."""
	z = p.z
	a = ramp(z, 1.30, 1.43)
	b = ramp(z, 1.58, 1.69)
	w = {"pelvis": 1.0 - a, "spine1": a * (1.0 - b), "spine2": a * b}
	sh = ramp(abs(p.x), 0.11, 0.20) * ramp(z, 1.62, 1.74) * 0.55
	if sh > 0.0:
		w = {k: x * (1.0 - sh) for k, x in w.items()}
		w["shoulder.l" if p.x > 0.0 else "shoulder.r"] = sh
	hd = ramp(z, 1.83, 1.90) * 0.5
	if hd > 0.0:
		w = {k: x * (1.0 - hd) for k, x in w.items()}
		w["head"] = hd
	return w


def ankle_foot(z):
	"""Share of the foot bone by height: the boot and the sock inside it
	use the same number, so a pointed or flexed foot moves them alike."""
	return 1.0 - ramp(z, 0.085, 0.16)


# ── the parts ─────────────────────────────────────────────────────────

def build_legs(skin, shorts_rings_cb):
	"""Thigh dome (inside the shorts) to ankle (inside the boot), one tube
	per leg: skin to just under the knee, then sock. Returns nothing; the
	shorts are built separately on the same thigh frames."""
	for sfx, sign in ((".l", 1.0), (".r", -1.0)):
		hip, knee = bone("upperleg" + sfx)
		_, ankle = bone("lowerleg" + sfx)
		thigh_dir = (knee - hip).normalized()
		shin_dir = (ankle - knee).normalized()
		thigh_len = (knee - hip).length
		ul, ll, ft = "upperleg" + sfx, "lowerleg" + sfx, "foot" + sfx

		def leg_point(t):
			"""Centre and axis t metres down the leg from the hip pivot."""
			if t <= thigh_len:
				return hip + thigh_dir * t, thigh_dir
			return knee + shin_dir * (t - thigh_len), shin_dir

		def knee_w(t):
			return blend(ul, ll, ramp(t, thigh_len - 0.05, thigh_len + 0.06))

		def foot_w(t, c):
			share = ankle_foot(c.z)
			base = knee_w(t)
			if share <= 0.0:
				return base
			out = {k: x * (1.0 - share) for k, x in base.items()}
			out[ft] = out.get(ft, 0.0) + share
			return out

		K = thigh_len
		thigh = [
			(-0.050, P(0.035, 0.035, 0.035, 0.035)),
			(-0.030, P(0.055, 0.053, 0.055, 0.056)),
			# Under the shorts down to 0.22: slimmer than it looks, and
			# close to a sphere round the hip pivot near the top, so a
			# big hip flexion (smother dive, tackled) turns it in place
			# instead of pushing it out through the shorts, which follow
			# the pelvis up there. Nothing here is visible.
			(0.000, P(0.062, 0.060, 0.062, 0.064)),
			(0.060, P(0.064, 0.055, 0.054, 0.066)),
			# Under the front crease and the crotch: the shorts' centre seam
			# can't follow either thigh, so in a split stride (the kick's
			# back-swing) a full inner thigh came through beside it.
			(0.140, P(0.080, 0.056, 0.064, 0.080)),
			(0.220, P(0.095, 0.088, 0.097, 0.088)),
			(0.300, P(0.088, 0.086, 0.092, 0.084)),
			(0.370, P(0.080, 0.083, 0.085, 0.077)),
			(0.430, P(0.070, 0.074, 0.075, 0.068)),
			(K, P(0.063, 0.064, 0.068, 0.060)),
			(K + 0.030, P(0.062, 0.062, 0.064, 0.064)),
			(K + 0.070, P(0.064, 0.062, 0.060, 0.075)),
			(K + 0.092, P(0.064, 0.063, 0.059, 0.078)),
		]
		sock = [
			(K + 0.097, P(0.073, 0.072, 0.068, 0.087)),   # sock top band
			(K + 0.115, P(0.071, 0.069, 0.065, 0.085)),
			(K + 0.160, P(0.071, 0.069, 0.065, 0.085)),
			(K + 0.240, P(0.065, 0.063, 0.061, 0.075)),
			(K + 0.330, P(0.057, 0.055, 0.055, 0.063)),
			(K + 0.420, P(0.051, 0.050, 0.051, 0.053)),
			(K + 0.490, P(0.037, 0.037, 0.040, 0.039)),   # inside the boot from here
			(K + 0.540, P(0.032, 0.032, 0.034, 0.033)),
		]
		rings = []
		for t, prof in thigh + sock:
			c, axis = leg_point(t)
			rings.append((c, axis, prof, foot_w(t, c)))
		n_skin = len(thigh)

		def mats(k):
			return "Skin_Mat" if k < n_skin - 1 else "Socks_Mat"

		lofted = skin.loft(rings, None, 10, math.pi / 10.0, lambda ax: frame(ax, sign), mats)
		top_c, top_axis = leg_point(-0.062)
		skin.cap(lofted[0], top_c, {ul: 1.0}, "Skin_Mat")
		end_c, _ = leg_point(K + 0.565)
		skin.cap(lofted[-1], end_c, foot_w(K + 0.565, end_c), "Socks_Mat")


def build_arms(skin):
	for sfx, sign in ((".l", 1.0), (".r", -1.0)):
		sh, elbow = bone("upperarm" + sfx)
		_, wrist = bone("lowerarm" + sfx)
		ua_dir = (elbow - sh).normalized()
		la_dir = (wrist - elbow).normalized()
		E = (elbow - sh).length
		W = E + (wrist - elbow).length
		ua, la, hd = "upperarm" + sfx, "lowerarm" + sfx, "hand" + sfx

		def arm_point(t):
			if t <= E:
				return sh + ua_dir * t, ua_dir
			return elbow + la_dir * (t - E), la_dir

		def arm_w(t):
			if t < E + 0.06:
				return blend(ua, la, ramp(t, E - 0.05, E + 0.04))
			return blend(la, hd, ramp(t, W - 0.03, W + 0.05) * 0.5)

		table = [
			(-0.070, P(0.030, 0.030, 0.030, 0.030)),
			(-0.050, P(0.060, 0.055, 0.060, 0.060)),
			(-0.020, P(0.080, 0.070, 0.078, 0.078)),
			(0.020, P(0.086, 0.072, 0.082, 0.082)),       # deltoid
			(0.080, P(0.080, 0.064, 0.075, 0.075)),
			(0.140, P(0.070, 0.060, 0.068, 0.066)),
			(0.200, P(0.062, 0.058, 0.071, 0.066)),       # biceps / triceps
			(0.270, P(0.056, 0.054, 0.064, 0.060)),
			(E - 0.040, P(0.052, 0.050, 0.054, 0.054)),
			(E, P(0.050, 0.050, 0.050, 0.057)),           # elbow, olecranon behind
			(E + 0.035, P(0.054, 0.050, 0.054, 0.050)),
			(E + 0.080, P(0.056, 0.050, 0.056, 0.048)),   # forearm
			(E + 0.150, P(0.048, 0.044, 0.050, 0.042)),
			(E + 0.220, P(0.040, 0.036, 0.044, 0.036)),
			(W, P(0.033, 0.031, 0.040, 0.033)),           # wrist: wide front-back
			(W + 0.020, P(0.028, 0.026, 0.034, 0.030)),
		]
		rings = []
		for t, prof in table:
			c, axis = arm_point(t)
			rings.append((c, axis, prof, arm_w(t)))
		lofted = skin.loft(rings, "Skin_Mat", 8, math.pi / 8.0, lambda ax: frame(ax, sign))
		c0, _ = arm_point(-0.085)
		skin.cap(lofted[0], c0, {ua: 1.0}, "Skin_Mat")
		c1, _ = arm_point(W + 0.035)
		skin.cap(lofted[-1], c1, arm_w(W + 0.035), "Skin_Mat")


def build_hands(skin):
	"""Palm block plus four two-segment fingers and a thumb, rigid on the
	hand bone (there are no finger bones), in a relaxed half-curl that
	reads for a carry, a mark and a handball fist alike. Palm faces the
	body's midline with the thumb forward: the pose 6thbuild's clips were
	authored against."""
	for sfx, sign in ((".l", 1.0), (".r", -1.0)):
		w0, w1 = bone("hand" + sfx)
		hd, la = "hand" + sfx, "lowerarm" + sfx
		d, s, f = frame(w1 - w0, sign)
		palm_n = -s   # palm faces the midline

		def fr(_ax):
			return d, s, f

		palm = [
			(-0.012, P(0.022, 0.022, 0.030, 0.028)),
			(0.000, P(0.020, 0.022, 0.032, 0.028)),
			(0.030, P(0.019, 0.024, 0.038, 0.034)),
			(0.065, P(0.018, 0.023, 0.043, 0.038)),
			(0.088, P(0.016, 0.019, 0.042, 0.036)),
		]
		rings = [(w0 + d * t, d, prof, {hd: 0.6, la: 0.4} if t <= 0.0 else {hd: 1.0}) for t, prof in palm]
		lofted = skin.loft(rings, "Skin_Mat", 8, math.pi / 8.0, fr)
		skin.cap(lofted[0], w0 - d * 0.02, {hd: 0.6, la: 0.4}, "Skin_Mat")
		skin.cap(lofted[-1], w0 + d * 0.094, {hd: 1.0}, "Skin_Mat")

		def finger(base, direction, lengths, curls, half):
			"""A square-section finger, each segment bent `curls` (radians,
			cumulative) toward the palm."""
			pts = [base]
			dirs = []
			p = base
			for length, curl in zip(lengths, curls):
				dd = (direction * math.cos(curl) + palm_n * math.sin(curl)).normalized()
				dirs.append(dd)
				p = p + dd * length
				pts.append(p)
			rings_f = []
			for k, c in enumerate(pts):
				ax = dirs[min(k, len(dirs) - 1)] if k == 0 or k == len(pts) - 1 else (dirs[k - 1] + dirs[k]).normalized()
				h = half * (0.85 if k == len(pts) - 1 else 1.0)
				rings_f.append((c, ax, P(h, h, h * 1.05, h * 1.05), {hd: 1.0}))
			def finger_frame(ax):
				u = (palm_n - ax * palm_n.dot(ax)).normalized()
				return ax, u, ax.cross(u)

			lf = skin.loft(rings_f, "Skin_Mat", 4, math.pi / 4.0, finger_frame)
			skin.cap(lf[0], pts[0] - dirs[0] * 0.006, {hd: 1.0}, "Skin_Mat")
			skin.cap(lf[-1], pts[-1] + dirs[-1] * 0.009, {hd: 1.0}, "Skin_Mat")

		knuckle = w0 + d * 0.082
		for off, lengths in ((0.026, (0.040, 0.032)), (0.009, (0.043, 0.034)),
				(-0.008, (0.040, 0.032)), (-0.024, (0.032, 0.026))):
			finger(knuckle + f * off, d, lengths, (math.radians(22), math.radians(55)), 0.0095)
		thumb_base = w0 + d * 0.022 + f * 0.026 + palm_n * 0.010
		thumb_dir = (d * 0.60 + f * 0.62 + palm_n * 0.30).normalized()
		finger(thumb_base, thumb_dir, (0.036, 0.030), (math.radians(10), math.radians(35)), 0.0105)


## Head shape by height: (z, centre y, side, front, back). The table runs
## from the underside of the chin to the crown; head_point() interpolates
## it, so the hair can follow the skull at any height.
HEAD = [
	(1.878, -0.032, 0.040, 0.050, 0.030),
	(1.902, -0.022, 0.077, 0.084, 0.064),   # a square, heroic jaw
	(1.940, -0.010, 0.086, 0.097, 0.086),
	(1.980, 0.000, 0.089, 0.100, 0.098),
	(2.020, 0.002, 0.091, 0.100, 0.104),
	(2.045, 0.002, 0.091, 0.104, 0.106),   # brow ridge
	(2.080, 0.004, 0.087, 0.092, 0.104),
	(2.115, 0.006, 0.072, 0.072, 0.088),
	(2.140, 0.008, 0.042, 0.038, 0.052),
]
HEAD_X = 0.007


def head_row(z):
	if z <= HEAD[0][0]:
		return HEAD[0]
	for a, b in zip(HEAD, HEAD[1:]):
		if z <= b[0]:
			t = (z - a[0]) / (b[0] - a[0])
			return tuple(lerp(x, y, t) for x, y in zip(a, b))
	return HEAD[-1]


def head_point(theta, z, grow_by=0.0):
	_, cy, side, front, back = head_row(z)
	c = Vector((HEAD_X, cy, z))
	return profile_point(c, Vector((1, 0, 0)), FORWARD, theta, P(side + grow_by, side + grow_by, front + grow_by, back + grow_by))


def build_neck_and_head(skin, hair):
	neck = [
		(1.735, P(0.060, 0.060, 0.056, 0.064)),
		(1.790, P(0.062, 0.062, 0.055, 0.066)),
		(1.840, P(0.060, 0.060, 0.052, 0.062)),
		(1.880, P(0.058, 0.058, 0.050, 0.060)),
		(1.925, P(0.052, 0.052, 0.046, 0.055)),
	]
	ny = 0.012

	def neck_w(p):
		return blend("spine2", "head", ramp(p.z, 1.78, 1.90))

	rings = [(Vector((HEAD_X, ny, z)), UP, prof, neck_w(Vector((0, 0, z)))) for z, prof in neck]
	lofted = skin.loft(rings, "Skin_Mat", 8, math.pi / 8.0, lambda ax: (UP, Vector((1, 0, 0)), FORWARD))
	skin.cap(lofted[0], Vector((HEAD_X, ny, 1.72)), {"spine2": 1.0}, "Skin_Mat")
	skin.cap(lofted[-1], Vector((HEAD_X, ny, 1.94)), {"head": 1.0}, "Skin_Mat")

	head_w = {"head": 1.0}
	n = 12
	start = len(skin.co)
	head_rings = []
	for row in HEAD:
		pts = [head_point(2.0 * math.pi * i / n, row[0]) for i in range(n)]
		head_rings.append(skin.ring(pts, head_w))
	for k in range(len(HEAD) - 1):
		ca = Vector((HEAD_X, HEAD[k][1], HEAD[k][0]))
		cb = Vector((HEAD_X, HEAD[k + 1][1], HEAD[k + 1][0]))
		skin.bridge(head_rings[k], head_rings[k + 1], "Skin_Mat", ca, cb)
	skin.cap(head_rings[0], Vector((HEAD_X, HEAD[0][1] + 0.005, HEAD[0][0] - 0.006)), head_w, "Skin_Mat")
	skin.cap(head_rings[-1], Vector((HEAD_X, HEAD[-1][1], 2.152)), head_w, "Skin_Mat")

	# Features are placed by casting onto the head itself, so they sit on
	# whatever the HEAD table says the face is.
	head_only = Part("head_probe")
	head_only.co = skin.co
	head_only.faces = [fc for fc in skin.faces if min(fc[0]) >= start]
	tree = head_only.bvh()

	def on_face(x, z, lift=0.002):
		hit, normal, _, _ = tree.ray_cast(Vector((x, -0.5, z)), Vector((0, 1, 0)))
		if hit is None:
			return Vector((x, head_row(z)[1] - head_row(z)[3], z)), FORWARD
		return hit + normal * lift, normal

	# Nose: a faceted wedge off the face.
	top, _ = on_face(HEAD_X, 2.034, 0.0)
	bl, _ = on_face(HEAD_X - 0.017, 1.982, 0.0)
	br, _ = on_face(HEAD_X + 0.017, 1.982, 0.0)
	tip_base, nrm = on_face(HEAD_X, 1.988, 0.0)
	tip = tip_base + FORWARD * 0.024 + Vector((0, 0, -0.004))
	under = (bl + br) * 0.5 + FORWARD * 0.010 + Vector((0, 0, -0.004))
	i_top, i_bl, i_br, i_tip, i_un = (skin.v(p, head_w) for p in (top, bl, br, tip, under))
	nose_c = (top + bl + br) / 3.0
	for tri in ((i_top, i_tip, i_bl), (i_top, i_br, i_tip), (i_bl, i_tip, i_un), (i_tip, i_br, i_un)):
		skin.face(list(tri), "Skin_Mat", (nose_c,))

	# Eyes: dark quads under the brow.
	for ex in (-0.034, 0.034):
		corners = []
		for dx, dz in ((-0.012, -0.006), (0.012, -0.006), (0.012, 0.006), (-0.012, 0.006)):
			p, _ = on_face(HEAD_X + ex + dx, 2.018 + dz + (0.002 if dx * ex > 0 else 0.0), 0.0025)
			corners.append(skin.v(p, head_w))
		skin.face(corners, "Eyes_Mat", FORWARD)

	# Ears: small slabs, angled back.
	for side in (-1.0, 1.0):
		row = head_row(2.0)
		cx = HEAD_X + side * (row[2] - 0.004)
		c = Vector((cx, row[1] + 0.012, 1.995))
		ex_ = Vector((side * 0.016, 0.004, 0.0))
		ey_ = Vector((0.0, 0.022, 0.004))
		ez_ = Vector((0.0, -0.004, 0.030))
		box(skin, c + ex_ * 0.5, ex_ * 0.5, ey_, ez_, head_w, "Skin_Mat")

	# Hair: a shell over the skull, lowest at the nape, highest at the
	# hairline, with a lip folded back to the scalp so its edge has depth.
	hn = 12
	edges = [2.030 + 0.050 * math.sin(2.0 * math.pi * i / hn) for i in range(hn)]
	hair_rings = []
	for u in (0.0, 0.0, 0.35, 0.65, 0.88):
		pts = []
		for i in range(hn):
			th = 2.0 * math.pi * i / hn
			z = lerp(edges[i], 2.138, u)
			g = 0.004 if not hair_rings else 0.012 + 0.006 * u
			p = head_point(th, z, g)
			if not hair_rings:
				p.z += 0.004
			if u >= 0.35 and math.sin(th) > 0.5:
				p.z += 0.010 * u   # a little lift at the front
			pts.append(p)
		hair_rings.append(hair.ring(pts, head_w))
	hc = Vector((HEAD_X, 0.0, 2.05))
	hair.bridge(hair_rings[0], hair_rings[1], "Hair_Mat", hc, hc, hint=Vector((0, 0, -1)))
	for k in range(1, len(hair_rings) - 1):
		hair.bridge(hair_rings[k], hair_rings[k + 1], "Hair_Mat", Vector((HEAD_X, 0.0, 1.95)), Vector((HEAD_X, 0.0, 2.2)))
	hair.cap(hair_rings[-1], Vector((HEAD_X, 0.006, 2.172)), head_w, "Hair_Mat")

	# Brows: hair-coloured strips proud of the brow ridge, angled down at
	# the inner end for a bit of intent.
	for ex in (-0.034, 0.034):
		corners = []
		for dx, dz in ((-0.017, 0.0), (0.017, 0.0), (0.017, 0.009), (-0.017, 0.009)):
			slope = -0.004 if dx * ex < 0 else 0.003
			p, _ = on_face(HEAD_X + ex + dx, 2.036 + dz + slope, 0.004)
			corners.append(hair.v(p, head_w))
		hair.face(corners, "Hair_Mat", FORWARD)


def box(part, c, ex, ey, ez, w, mat):
	"""A box centred on c with half-extent vectors ex, ey, ez."""
	idx = []
	for sx in (-1, 1):
		for sy in (-1, 1):
			for sz in (-1, 1):
				idx.append(part.v(c + ex * sx + ey * sy + ez * sz, w))
	faces = ((0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3))
	for fc in faces:
		part.face([idx[k] for k in fc], mat, (c,))


## Guernsey rings: (z, half width, front, back, bulges). A sleeveless AFL
## guernsey: the deltoids come out over its shoulder line.
GUERNSEY = [
	(1.200, 0.170, 0.105, 0.110, ()),
	(1.300, 0.158, 0.096, 0.106, ()),   # flat belly: the carry's forearms rest on it
	(1.400, 0.165, 0.099, 0.108, ()),
	(1.500, 0.192, 0.115, 0.114, ((230, 35, 0.008), (310, 35, 0.008))),
	(1.580, 0.208, 0.122, 0.118, ((60, 28, 0.010), (120, 28, 0.010), (230, 35, 0.012), (310, 35, 0.012))),
	(1.660, 0.216, 0.124, 0.116, ((60, 28, 0.010), (120, 28, 0.010))),
	(1.720, 0.212, 0.108, 0.110, ()),
	(1.775, 0.192, 0.084, 0.090, ()),
	(1.810, 0.124, 0.070, 0.076, ()),
	(1.840, 0.082, 0.064, 0.070, ()),
]


def torso_frame(_ax):
	return UP, Vector((1, 0, 0)), FORWARD


def build_guernsey(shirt):
	n = 16
	rings = []
	for z, hw, fr, bk, bulge in GUERNSEY:
		rings.append((Vector((0.004, spine_y(z), z)), UP, P(hw, hw, fr, bk, bulge), torso_w))
	lofted = shirt.loft(rings, "Shirt_Mat", n, 0.0, torso_frame)

	# Collar: a band round the neck hole with a shallow V at the front and
	# a lip folded inside.
	def collar_ring(z, hw, fr, bk, vdip):
		pts = []
		for i in range(n):
			th = 2.0 * math.pi * i / n
			p = profile_point(Vector((0.004, 0.006, z)), Vector((1, 0, 0)), FORWARD, th, P(hw, hw, fr, bk))
			p.z -= vdip * max(0.0, math.sin(th)) ** 6
			pts.append(p)
		return shirt.ring(pts, torso_w)

	low = collar_ring(1.832, 0.090, 0.072, 0.077, 0.030)
	high = collar_ring(1.866, 0.077, 0.067, 0.072, 0.024)
	fold = collar_ring(1.858, 0.069, 0.061, 0.067, 0.022)
	cc_lo, cc_hi = Vector((0.004, 0.006, 1.80)), Vector((0.004, 0.006, 1.90))
	shirt.bridge(low, high, "Trim_Mat", cc_lo, cc_hi)
	shirt.bridge(high, fold, "Trim_Mat", cc_lo, cc_hi, hint=UP)

	# Number on the back: the text outline, flattened onto the guernsey by
	# casting each vertex onto it from behind.
	tree = shirt.bvh()
	curve = bpy.data.curves.new("B7_NumberText", 'FONT')
	curve.body = NUMBER_TEXT
	curve.size = 0.19
	curve.align_x = 'CENTER'
	curve.align_y = 'CENTER'
	curve.resolution_u = 2
	curve.offset = 0.011   # bolden: Blender's default font is too thin to read at match distance
	curve.space_character = 1.15
	tmp = bpy.data.objects.new("B7_NumberText", curve)
	bpy.context.scene.collection.objects.link(tmp)
	bpy.context.view_layer.update()
	ev = tmp.evaluated_get(bpy.context.evaluated_depsgraph_get())
	me = ev.to_mesh()
	ids = []
	for v in me.vertices:
		x = 0.004 - v.co.x * 0.95   # seen from behind, reading left to right
		z = 1.535 + v.co.y
		hit, nrm, _, _ = tree.ray_cast(Vector((x, 0.6, z)), Vector((0, -1, 0)))
		p = (hit + nrm * 0.004) if hit is not None else Vector((x, 0.13, z))
		ids.append(shirt.v(p, torso_w(p)))
	for poly in me.polygons:
		shirt.face([ids[k] for k in poly.vertices], "Number_Mat", Vector((0, 1, 0)))
	ev.to_mesh_clear()
	bpy.data.objects.remove(tmp, do_unlink=True)
	bpy.data.curves.remove(curve, do_unlink=True)


## Shorts hip rings: (z, half width, front, back).
SHORTS_HIPS = [
	(1.335, 0.180, 0.111, 0.120),   # waistband: low enough that the guernsey reads long
	(1.260, 0.196, 0.116, 0.130),
	(1.180, 0.222, 0.130, 0.146),
	(1.080, 0.242, 0.146, 0.154),
	(1.005, 0.246, 0.150, 0.152),
]


def build_shorts(shorts):
	"""One mesh from waistband to both hems. The two legs split off the
	bottom hip ring at a crotch vertex, so there's no seam to hide: each
	leg's first loop is half the hip ring plus that vertex, and every ring
	below matches its angles."""
	n = 16
	hips = []
	# Centred between the hip joints, not on the spine: 6thbuild's hips
	# sit at +0.140 / -0.147, so a spine-centred pair of shorts left the
	# right thigh 1 cm less room and it crossed the shorts in the carry.
	cx = (bone("upperleg.l")[0].x + bone("upperleg.r")[0].x) * 0.5
	for z, hw, fr, bk in SHORTS_HIPS:
		c = Vector((cx, spine_y(z), z))
		pts = [profile_point(c, Vector((1, 0, 0)), FORWARD, 2.0 * math.pi * i / n, P(hw, hw, fr, bk)) for i in range(n)]
		hips.append((c, shorts.ring(pts, torso_w)))
	for (ca, ra), (cb, rb) in zip(hips, hips[1:]):
		shorts.bridge(ra, rb, "Shorts_Mat", ca, cb)
	# The front panel over each hip rides up with its thigh a little, the
	# way real shorts get shoved up by a lifted knee. Rigid to the pelvis,
	# a sprint's knee lift (run_fwd) put the thigh straight through it.
	for row, share in ((2, 0.10), (3, 0.30)):
		c_row, ring = hips[row]
		for k in ring:
			d = shorts.co[k] - c_row
			front = clamp01(-d.y / max(d.length, 1e-6))
			side = ramp(abs(d.x), 0.03, 0.10)
			s = share * front * side
			if s > 0.0:
				ul = "upperleg.l" if d.x > 0.0 else "upperleg.r"
				w = {b: x * (1.0 - s) for b, x in shorts.w[k].items()}
				w[ul] = w.get(ul, 0.0) + s
				shorts.w[k] = w

	# Waistband lip folded inside.
	z0, hw, fr, bk = SHORTS_HIPS[0]
	c0 = Vector((cx, spine_y(z0), z0 - 0.012))
	fold = shorts.ring([profile_point(c0, Vector((1, 0, 0)), FORWARD, 2.0 * math.pi * i / n,
		P(hw - 0.013, hw - 0.013, fr - 0.012, bk - 0.012)) for i in range(n)], torso_w)
	shorts.bridge(hips[0][1], fold, "Shorts_Mat", c0, c0, hint=UP)

	bottom_c, bottom = hips[-1]
	crotch = shorts.v(Vector((cx, spine_y(0.98) + 0.004, 0.978)), {"pelvis": 1.0})
	front_i, back_i = n // 4, 3 * n // 4
	loops = {
		".l": [bottom[(back_i + k) % n] for k in range(n // 2 + 1)] + [crotch],
		".r": [bottom[front_i + k] for k in range(n // 2 + 1)] + [crotch],
	}
	for sfx, sign in ((".l", 1.0), (".r", -1.0)):
		hip, knee = bone("upperleg" + sfx)
		thigh_dir = (knee - hip).normalized()
		ul = "upperleg" + sfx
		loop = loops[sfx]
		a, s, f = frame(thigh_dir, sign)
		c_loop = hip + thigh_dir * 0.09
		thetas = []
		for k in loop:
			d = shorts.co[k] - c_loop
			thetas.append(math.atan2(d.dot(f), d.dot(s)))
		prev = loop
		prev_c = c_loop
		legs = [
			(0.110, P(0.115, 0.117, 0.128, 0.118), 0.22),   # eases the pelvis -> thigh blend
			(0.140, P(0.114, 0.116, 0.124, 0.116), 0.08),
			(0.180, P(0.112, 0.114, 0.116, 0.110), 0.0),
			(0.205, P(0.114, 0.114, 0.117, 0.111), 0.0),   # hem, a little flare
		]
		for t, prof, pelvis_share in legs:
			c = hip + thigh_dir * t
			pts = [profile_point(c, s, f, th, prof) for th in thetas]
			w = {"pelvis": pelvis_share, ul: 1.0 - pelvis_share} if pelvis_share > 0 else {ul: 1.0}
			ring = shorts.ring(pts, w)
			shorts.bridge(prev, ring, "Shorts_Mat", prev_c, c)
			prev, prev_c = ring, c
		# Blend the split loop itself between pelvis and thigh, so the legs
		# of the shorts follow the thighs from the crotch down. Like real
		# shorts, the front creases with the pelvis and the seat stretches
		# with the thigh: weighted evenly, a big hip flexion (knocked_back,
		# tackle_takedown) dragged the front of the loop up into the body
		# and the shorts caved in at the crease.
		for k in loop:
			if k in (crotch, bottom[front_i], bottom[back_i]):
				continue
			d = shorts.co[k] - c_loop
			back = clamp01(0.5 + 0.5 * d.dot(-f) / max(d.length, 1e-6))   # 0 front .. 1 back
			th = lerp(0.55, 0.72, back)
			shorts.w[k] = {"pelvis": 1.0 - th, ul: th}
		c_hem = hip + thigh_dir * 0.192
		hem_fold = shorts.ring([profile_point(c_hem, s, f, th, P(0.107, 0.105, 0.110, 0.104)) for th in thetas], {ul: 1.0})
		shorts.bridge(prev, hem_fold, "Shorts_Mat", c_hem, c_hem, hint=-thigh_dir)
	# The crotch and the two centre-seam vertices belong to both legs. The
	# crotch itself follows them more: at 70% pelvis a running stride left
	# it behind and the leading thigh came through the inside of the leg.
	for k in (bottom[front_i], bottom[back_i]):
		shorts.w[k] = {"pelvis": 0.7, "upperleg.l": 0.15, "upperleg.r": 0.15}
	shorts.w[crotch] = {"pelvis": 0.5, "upperleg.l": 0.25, "upperleg.r": 0.25}


## Boot cross-sections along the foot: (y, half width, top z, sole z).
## A low cut, like a real football boot: the collar sits just under the
## ankle, so a pointed foot (the tackled clip points it to 5° off the
## shin) has a short lever to wrench the collar round the sock.
BOOT = [
	(0.078, 0.028, 0.105, 0.020),
	(0.062, 0.046, 0.128, 0.014),
	(0.020, 0.054, 0.132, 0.012),
	(-0.030, 0.054, 0.124, 0.012),
	(-0.090, 0.051, 0.100, 0.012),
	(-0.150, 0.054, 0.086, 0.012),
	(-0.210, 0.055, 0.076, 0.012),
	(-0.270, 0.051, 0.066, 0.014),
	(-0.310, 0.041, 0.056, 0.020),
	(-0.334, 0.026, 0.046, 0.028),
]
SOLE = 0.018


def build_boots(boots):
	for sfx in (".l", ".r"):
		a0, _ = bone("foot" + sfx)
		x0 = a0.x
		ft, ll = "foot" + sfx, "lowerleg" + sfx

		def bw(p):
			share = ankle_foot(p.z)
			return {ft: share, ll: 1.0 - share} if share < 1.0 else {ft: 1.0}

		rings = []
		for y, w, zt, zs in BOOT:
			prof = [
				(-w, zs), (-w, zs + SOLE), (-w * 0.98, zs + (zt - zs) * 0.45), (-w * 0.74, zt - 0.014),
				(-w * 0.28, zt), (w * 0.28, zt), (w * 0.74, zt - 0.014), (w * 0.98, zs + (zt - zs) * 0.45),
				(w, zs + SOLE), (w, zs),
			]
			pts = [Vector((x0 + px, y, pz)) for px, pz in prof]
			rings.append((Vector((x0, y, (zt + zs) * 0.5)), boots.ring(pts, bw)))
		seg_mats = ["Studs_Mat"] + ["Boots_Mat"] * 7 + ["Studs_Mat", "Studs_Mat"]
		for (ca, ra), (cb, rb) in zip(rings, rings[1:]):
			boots.bridge(ra, rb, None, ca, cb, mats=seg_mats)
		hc = rings[0][0]
		boots.cap(rings[0][1], hc + Vector((0, 0.012, 0)), bw(hc), "Boots_Mat")
		tc = rings[-1][0]
		boots.cap(rings[-1][1], tc + Vector((0, -0.012, -0.004)), {ft: 1.0}, "Boots_Mat")

		# Studs: six hex frustums, four under the forefoot, two at the heel.
		for sx, sy in ((-0.030, -0.205), (0.030, -0.205), (-0.028, -0.268), (0.028, -0.268),
				(-0.022, 0.032), (0.022, 0.032)):
			c = Vector((x0 + sx, sy, 0.0))
			top = boots.ring([c + Vector((math.cos(k * math.pi / 3) * 0.0095, math.sin(k * math.pi / 3) * 0.0095, 0.013)) for k in range(6)], {ft: 1.0})
			bot = boots.ring([c + Vector((math.cos(k * math.pi / 3) * 0.0062, math.sin(k * math.pi / 3) * 0.0062, 0.0)) for k in range(6)], {ft: 1.0})
			boots.bridge(top, bot, "Studs_Mat", c + Vector((0, 0, 0.013)), c)
			boots.face(list(bot), "Studs_Mat", Vector((0, 0, -1)))


# ── entry point ───────────────────────────────────────────────────────

def remove_build6_meshes():
	removed = []
	for name in BUILD6_MESHES:
		ob = bpy.data.objects.get(name)
		if ob is None:
			continue
		me = ob.data
		bpy.data.objects.remove(ob, do_unlink=True)
		if me.users == 0:
			bpy.data.meshes.remove(me)
		removed.append(name)
	return removed


def build():
	arm = bpy.data.objects[ARMATURE]
	collection = arm.users_collection[0]
	removed = remove_build6_meshes()

	skin = Part("Body")
	build_legs(skin, None)
	build_arms(skin)
	build_hands(skin)
	hair = Part("Hair")
	build_neck_and_head(skin, hair)
	shirt = Part("Guernsey")
	build_guernsey(shirt)
	shorts = Part("Shorts")
	build_shorts(shorts)
	boots = Part("Boots")
	build_boots(boots)

	report = {"removed_build6_meshes_from_copy": removed}
	for part in (skin, hair, shirt, shorts, boots):
		ob = build_object(part, arm, collection)
		tris = sum(len(p.vertices) - 2 for p in ob.data.polygons)
		report[ob.name] = {"verts": len(ob.data.vertices), "tris": tris,
			"materials": [m.name for m in ob.data.materials], "groups": sorted(g.name for g in ob.vertex_groups)}
	deform = {b.name for b in arm.data.bones if b.use_deform}
	for part in (skin, hair, shirt, shorts, boots):
		bad = {b for w in part.w for b in w if b not in deform}
		if bad:
			report.setdefault("WARNING_non_deform_weights", {})[part.name] = sorted(bad)
	return report


if __name__ == "__main__":
	result = build()
	print("build_7thbuild_mesh:", result)
	if "--save" in sys.argv:
		bpy.ops.wm.save_mainfile()
