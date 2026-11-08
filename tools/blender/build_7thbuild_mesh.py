"""Builds Build 7's ("7thbuild") player mesh on 6thbuild's own Armature.

Run with assets/blender/7thbuild.blend open. That file started as a byte
copy of 6thbuild.blend (F:\\dev\\learning-&-development\\New Folder), so it
has the same Armature, the same 28 actions and the same IK helpers. This
script only ever touches meshes and materials: it deletes the copy's four
Build 6 meshes if they're still there (gone from the COPY only, the Build 6
file is never opened for writing) and generates five parts, parented to the
untouched Armature. Re-running replaces them, so tune the tables below and
run it again rather than hand-editing the result.

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
standard low-poly trick, and it keeps each part a clean tube. The
guernsey's shoulder yoke tucks its outer end inside the deltoid's dome for
the same reason: a raised arm turns the dome over it.

Shading is flat. The facets are meant to be seen, so the profile tables
run in straight tapers between a few deliberate kinks (a muscle's edge, a
hem, the jaw), and a joint's support rings sit on those straight runs where
they can: on a straight taper the bands between rings face the same way
and don't show.

Kit: one material, Kit_Mat, for everything. Each face carries a kit slot
(SLOTS below) as the integer part of its "Slot" UV, which Godot imports as
UV2; materials/player_kit.gdshader colours each slot from per-player
instance parameters that HumanoidRig sets (docs/BUILD7_MODEL.md). The
"number" faces on the back carry a planar projection of the number box in
their "UVMap" UV, and the shader draws the player's own number there. The
"Col" colour attribute is only the preview look (Blender, and the .glb if
it's opened without the shader). export_7thbuild.py joins the five parts
into one mesh, so a player is one skinned mesh and one draw.

Gameplay doesn't read any of this. The skeleton (bone names, rests,
hierarchy) is 6thbuild's, unchanged, and every gameplay anchor and every
ragdoll body is built from the skeleton (PhysicsRagdoll.BODIES), not the
mesh. See docs/BUILD7_MODEL.md.
"""

import math
import sys

import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree

ARMATURE = "Armature"
BUILD6_MESHES = ["Body", "Shirt", "Shorts", "Shoes"]
PREFIX = "B7_"
MATERIAL = "Kit_Mat"

FORWARD = Vector((0.0, -1.0, 0.0))   # Blender: the rig faces -Y
UP = Vector((0.0, 0.0, 1.0))
SIDE = Vector((1.0, 0.0, 0.0))

## Kit slot per face. The numbers are the contract with
## materials/player_kit.gdshader (its SLOT_* constants): change both or
## neither.
SLOTS = {
	"skin": 0, "jersey": 1, "number": 2, "trim": 3, "shorts": 4, "socks": 5,
	"boot": 6, "sole": 7, "studs": 8, "hair": 9, "eyes": 10, "mouth": 11,
}

## Preview colours (sRGB): Blender's viewport and the .glb's vertex colours.
## In the game the shader's per-player colours replace them.
PREVIEW = {
	"skin": (0.80, 0.56, 0.40), "jersey": (0.86, 0.72, 0.30), "number": (0.86, 0.72, 0.30),
	"trim": (0.94, 0.92, 0.86), "shorts": (0.12, 0.12, 0.14), "socks": (0.86, 0.72, 0.30),
	"boot": (0.10, 0.10, 0.11), "sole": (0.05, 0.05, 0.06), "studs": (0.55, 0.55, 0.57),
	"hair": (0.13, 0.09, 0.06), "eyes": (0.05, 0.05, 0.06), "mouth": (0.50, 0.30, 0.22),
}

## The number box on the back, as seen from behind: centre (x, z) and size
## (w, h) in metres. Faces of the guernsey's back inside it are "number"
## faces; their UVMap maps the box to 0..1 (u from the viewer's left).
## player_kit.gdshader's NUMBER_BOX_ASPECT is w / h: change both together.
NUMBER_CENTRE = (0.004, 1.565)
NUMBER_SIZE = (0.360, 0.260)


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
	270 = back. prof: out/in/front/back radii, a squareness ("sq": 2 is an
	ellipse, higher is boxier, for flat planes like a chest) and optional
	bulges [(deg, width deg, amount)] for muscle shapes."""
	co, si = math.cos(theta), math.sin(theta)
	e = 2.0 / prof.get("sq", 2.0)
	cx = math.copysign(abs(co) ** e, co)
	cy = math.copysign(abs(si) ** e, si)
	rs = prof["out"] if co >= 0.0 else prof["in"]
	rf = prof["front"] if si >= 0.0 else prof["back"]
	p = s * (cx * rs) + f * (cy * rf)
	for deg, width, amount in prof.get("bulge", ()):
		d = math.degrees(math.atan2(math.sin(theta - math.radians(deg)), math.cos(theta - math.radians(deg))))
		k = 1.0 - (d / width) ** 2
		if k > 0.0:
			p += p.normalized() * (amount * k)
	return c + p


def P(out, inn, front, back, bulge=(), sq=2.0):
	return {"out": out, "in": inn, "front": front, "back": back, "bulge": bulge, "sq": sq}


def srgb_to_linear(c):
	return tuple(x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c)


# ── mesh assembly ─────────────────────────────────────────────────────

class Part:
	"""Vertices with weights and faces with kit slots, oriented as they're
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

	def face(self, idx, slot, out):
		"""`out`: a direction the face should point along, or a point it
		should point away from (Vector wrapped in a tuple: (point,))."""
		n = self.normal(idx)
		pts = [self.co[i] for i in idx]
		centre = sum(pts, Vector()) / len(pts)
		ref = (centre - out[0]) if isinstance(out, tuple) else out
		if n.dot(ref) < 0.0:
			idx = list(reversed(idx))
		self.faces.append((list(idx), slot))

	def normal(self, idx):
		"""Newell's normal: holds for quads and n-gons alike."""
		pts = [self.co[i] for i in idx]
		n = Vector()
		for a, b in zip(pts, pts[1:] + pts[:1]):
			n += Vector(((a.y - b.y) * (a.z + b.z), (a.z - b.z) * (a.x + b.x), (a.x - b.x) * (a.y + b.y)))
		return n

	def bridge(self, ra, rb, slot, ca, cb, closed=True, hint=None, slots=None):
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
			self.face(quad, slots[i] if slots else slot, out)

	def cap(self, ring, apex, w, slot, closed=True):
		a = self.v(apex, w)
		centre = sum((self.co[k] for k in ring), Vector()) / len(ring)
		out = (self.co[a] - centre)
		n = len(ring)
		for i in range(n if closed else n - 1):
			self.face([ring[i], ring[(i + 1) % n], a], slot, out)
		return a

	def loft(self, rings, slot, n, phase, frame_fn, slot_fn=None):
		"""rings: [(centre, axis, prof, weights)], built in order and bridged.
		Returns the vertex index lists."""
		out = []
		for c, axis, prof, w in rings:
			a, s, f = frame_fn(axis)
			pts = [profile_point(c, s, f, phase + 2.0 * math.pi * i / n, prof) for i in range(n)]
			out.append(self.ring(pts, w))
		for k in range(len(rings) - 1):
			self.bridge(out[k], out[k + 1], slot_fn(k) if slot_fn else slot, rings[k][0], rings[k + 1][0])
		return out

	def bvh(self, faces=None):
		faces = self.faces if faces is None else faces
		return BVHTree.FromPolygons([tuple(c) for c in self.co], [f for f, _ in faces])


def kit_material():
	"""The one material every part uses. Its base colour reads the "Col"
	attribute, so Blender (and a .glb opened without the game's shader)
	shows the preview colours; the game swaps in player_kit.gdshader."""
	m = bpy.data.materials.get(MATERIAL)
	if m is None:
		m = bpy.data.materials.new(MATERIAL)
	m.use_nodes = True
	m.diffuse_color = (0.8, 0.8, 0.8, 1.0)
	m.roughness = 0.75
	nt = m.node_tree
	bsdf = nt.nodes.get("Principled BSDF")
	col = nt.nodes.get("Slot colour")
	if col is None:
		col = nt.nodes.new("ShaderNodeVertexColor")
		col.name = "Slot colour"
		col.location = (-300.0, 200.0)
	col.layer_name = "Col"
	if bsdf is not None:
		nt.links.new(col.outputs["Color"], bsdf.inputs["Base Color"])
		bsdf.inputs["Roughness"].default_value = 0.75
		bsdf.inputs["Metallic"].default_value = 0.0
	return m


def number_uv(p):
	"""Planar projection of the number box, seen from behind: u runs from
	the viewer's left (+X on a body facing -Y) to their right."""
	(cx, cz), (w, h) = NUMBER_CENTRE, NUMBER_SIZE
	return ((cx + w * 0.5 - p.x) / w, (p.z - (cz - h * 0.5)) / h)


def build_object(part, arm_obj, collection):
	name = PREFIX + part.name
	old = bpy.data.objects.get(name)
	if old is not None:
		old_me = old.data
		bpy.data.objects.remove(old, do_unlink=True)
		bpy.data.meshes.remove(old_me, do_unlink=True)
	me = bpy.data.meshes.new(name)
	me.from_pydata([tuple(c) for c in part.co], [], [f for f, _ in part.faces])
	# The slot goes on as a face attribute before validate(), which keeps
	# attributes in step if it ever has to drop a face.
	slot_attr = me.attributes.new("slot_id", 'INT', 'FACE')
	for i, (_, slot) in enumerate(part.faces):
		slot_attr.data[i].value = SLOTS[slot]
	me.validate()
	me.update()
	me.materials.append(kit_material())
	uv_num = me.uv_layers.new(name="UVMap")
	uv_slot = me.uv_layers.new(name="Slot")
	col = me.color_attributes.new("Col", 'FLOAT_COLOR', 'CORNER')
	names = {v: k for k, v in SLOTS.items()}
	slot_attr = me.attributes["slot_id"]
	for poly in me.polygons:
		poly.material_index = 0
		poly.use_smooth = False
		sid = slot_attr.data[poly.index].value
		rgb = srgb_to_linear(PREVIEW[names[sid]])
		for li in poly.loop_indices:
			vi = me.loops[li].vertex_index
			uv_slot.data[li].uv = (sid + 0.5, 0.5)
			uv_num.data[li].uv = number_uv(me.vertices[vi].co) if sid == SLOTS["number"] else (0.0, 0.0)
			col.data[li].color = (rgb[0], rgb[1], rgb[2], 1.0)
	me.uv_layers.active = uv_num
	uv_num.active_render = True
	me.color_attributes.active_color = col
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


# ── legs ──────────────────────────────────────────────────────────────

## Leg rings, metres down the leg from the hip pivot (K = the knee pivot).
## theta: 0 out, 90 front, 180 in, 270 back. Everything above 0.20 is
## inside the shorts, and it's a slim cone from a small dome on the hip
## pivot rather than a thigh: the shorts round the hip follow the pelvis
## (or blend it with the thigh, and a blend caves in at a bent joint's
## crease), so anything of the thigh further from the pivot than they are
## sweeps out through them as the hip bends. A thigh-sized ring there came
## through the front of the hip in every running stride and 4 cm through
## the crease in a dive. 6thbuild's hip joints sit far out on the hips, so
## in front of each pivot there's only ~5 cm of shorts: the cone keeps
## inside that. The visible thigh starts under the hem.
def thigh_table(K):
	return [
		# No dome above the pivot: nothing shows there, and a dome's top
		# came out under the seat when a kneeling thigh (the takedown)
		# turned it into the blended seat.
		(-0.008, P(0.022, 0.022, 0.022, 0.022)),
		(0.010, P(0.030, 0.029, 0.028, 0.031)),
		(0.045, P(0.030, 0.029, 0.028, 0.032)),
		(0.095, P(0.034, 0.032, 0.030, 0.036)),
		(0.140, P(0.052, 0.044, 0.040, 0.050)),
		(0.215, P(0.090, 0.090, 0.100, 0.094)),
		# Quads: the outer sweep (vastus lateralis) high, the teardrop of
		# vastus medialis low and inside, just above the knee. Hamstrings
		# behind.
		(0.295, P(0.092, 0.092, 0.104, 0.094, ((50, 40, 0.006), (270, 35, 0.004)))),
		(0.375, P(0.083, 0.090, 0.093, 0.084, ((135, 30, 0.008),))),
		(0.428, P(0.068, 0.079, 0.076, 0.069, ((140, 28, 0.006),))),
		(K - 0.020, P(0.062, 0.064, 0.068, 0.060)),
		# Knee: the kneecap's flat front, the hamstring tendons either side
		# behind.
		(K, P(0.061, 0.061, 0.068, 0.058)),
		(K + 0.030, P(0.060, 0.060, 0.061, 0.064)),
		(K + 0.058, P(0.062, 0.062, 0.058, 0.072)),
	]


def sock_table(K):
	return [
		(K + 0.064, P(0.068, 0.068, 0.064, 0.078)),   # sock top band
		(K + 0.086, P(0.068, 0.068, 0.063, 0.079)),
		# Calf: the inner head of gastrocnemius is the bigger and lower one.
		(K + 0.150, P(0.070, 0.075, 0.062, 0.085, ((235, 30, 0.007),))),
		(K + 0.235, P(0.063, 0.067, 0.057, 0.075)),
		(K + 0.325, P(0.053, 0.054, 0.051, 0.058)),
		(K + 0.410, P(0.045, 0.045, 0.045, 0.047)),
		(K + 0.452, P(0.040, 0.040, 0.042, 0.041)),   # just above the boot's collar
		# Inside the boot from here, and no lower than the ankle pivot: a
		# sock ring further down rode a fully pointed foot (tackled) up and
		# out through the back of the boot's collar.
		(K + 0.500, P(0.034, 0.034, 0.036, 0.031)),
	]


def build_legs(skin):
	"""Thigh dome (inside the shorts) to ankle (inside the boot), one tube
	per leg: skin to just under the knee, then sock."""
	for sfx, sign in ((".l", 1.0), (".r", -1.0)):
		hip, knee = bone("upperleg" + sfx)
		_, ankle = bone("lowerleg" + sfx)
		thigh_dir = (knee - hip).normalized()
		shin_dir = (ankle - knee).normalized()
		K = (knee - hip).length
		ul, ll, ft = "upperleg" + sfx, "lowerleg" + sfx, "foot" + sfx

		def leg_point(t):
			"""Centre and axis t metres down the leg from the hip pivot."""
			if t <= K:
				return hip + thigh_dir * t, thigh_dir
			return knee + shin_dir * (t - K), shin_dir

		def knee_w(t):
			return blend(ul, ll, ramp(t, K - 0.05, K + 0.06))

		def foot_w(t, z):
			"""Per vertex, by its own height: the boot is weighted that
			way, and a sock ring weighted by its centre's height moved
			apart from the boot round it when the foot pointed."""
			share = ankle_foot(z)
			base = knee_w(t)
			if share <= 0.0:
				return base
			out = {k: x * (1.0 - share) for k, x in base.items()}
			out[ft] = out.get(ft, 0.0) + share
			return out

		thigh, sock = thigh_table(K), sock_table(K)
		rings = []
		for t, prof in thigh + sock:
			c, axis = leg_point(t)
			rings.append((c, axis, prof, lambda p, t=t: foot_w(t, p.z)))
		n_skin = len(thigh)

		def slots(k):
			return "skin" if k < n_skin - 1 else "socks"

		lofted = skin.loft(rings, None, 12, 0.0, lambda ax: frame(ax, sign), slots)
		top_c, _ = leg_point(-0.018)
		skin.cap(lofted[0], top_c, {ul: 1.0}, "skin")
		end_c, _ = leg_point(K + 0.525)
		skin.cap(lofted[-1], end_c, foot_w(K + 0.525, end_c.z), "socks")


# ── arms and hands ────────────────────────────────────────────────────

def build_arms(skin):
	"""Shoulder dome to wrist. theta 0 is up-and-out in the A-pose (the
	side of the deltoid), 90 front, 180 the armpit side, 270 behind."""
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
			(-0.076, P(0.030, 0.030, 0.030, 0.030)),
			(-0.056, P(0.058, 0.052, 0.058, 0.058)),
			(-0.026, P(0.080, 0.068, 0.080, 0.080)),
			# Deltoid: a full cap over the shoulder, its side head the
			# widest, tapering in a straight run to its insertion.
			(0.016, P(0.088, 0.072, 0.085, 0.085, ((0, 50, 0.004),))),
			(0.085, P(0.084, 0.068, 0.081, 0.081)),
			(0.150, P(0.074, 0.064, 0.076, 0.074)),
			# Biceps in front, the triceps' horseshoe behind.
			(0.225, P(0.067, 0.061, 0.079, 0.075)),
			(E - 0.044, P(0.056, 0.053, 0.060, 0.061)),
			(E, P(0.054, 0.052, 0.053, 0.062)),           # elbow, olecranon behind
			(E + 0.040, P(0.061, 0.053, 0.059, 0.055)),
			# Forearm: the brachioradialis bulge out-front below the elbow,
			# then a straight taper to the wrist.
			(E + 0.090, P(0.064, 0.053, 0.061, 0.052, ((45, 40, 0.004),))),
			(E + 0.170, P(0.049, 0.045, 0.052, 0.043)),
			(W - 0.022, P(0.038, 0.035, 0.043, 0.036)),
			(W, P(0.034, 0.032, 0.041, 0.034)),           # wrist: wide front-back
			(W + 0.020, P(0.029, 0.027, 0.035, 0.031)),
		]
		rings = []
		for t, prof in table:
			c, axis = arm_point(t)
			rings.append((c, axis, prof, arm_w(t)))
		lofted = skin.loft(rings, "skin", 10, math.radians(18.0), lambda ax: frame(ax, sign))
		c0, _ = arm_point(-0.088)
		skin.cap(lofted[0], c0, {ua: 1.0}, "skin")
		c1, _ = arm_point(W + 0.034)
		skin.cap(lofted[-1], c1, arm_w(W + 0.034), "skin")


def build_hands(skin):
	"""A palm, four chunky fingers that touch, and a thumb, rigid on the
	hand bone (there are no finger bones), in a relaxed half-curl that
	reads for a carry, a mark and a handball fist alike. The fingers are
	thick enough to read as a hand at a few metres and close enough to
	read as one mass beyond that. Palm faces the body's midline with the
	thumb forward: the pose 6thbuild's clips were authored against."""
	for sfx, sign in ((".l", 1.0), (".r", -1.0)):
		w0, w1 = bone("hand" + sfx)
		hd, la = "hand" + sfx, "lowerarm" + sfx
		d, s, f = frame(w1 - w0, sign)
		palm_n = -s   # palm faces the midline

		def fr(_ax):
			return d, s, f

		palm = [
			(-0.012, P(0.022, 0.022, 0.031, 0.029)),
			(0.002, P(0.021, 0.023, 0.034, 0.030)),
			(0.034, P(0.020, 0.025, 0.041, 0.037)),
			(0.068, P(0.019, 0.024, 0.045, 0.040)),
			(0.088, P(0.017, 0.021, 0.044, 0.038)),
		]
		rings = [(w0 + d * t, d, prof, {hd: 0.6, la: 0.4} if t <= 0.0 else {hd: 1.0}) for t, prof in palm]
		lofted = skin.loft(rings, "skin", 8, math.pi / 8.0, fr)
		skin.cap(lofted[0], w0 - d * 0.02, {hd: 0.6, la: 0.4}, "skin")
		skin.cap(lofted[-1], w0 + d * 0.094, {hd: 1.0}, "skin")

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
				h = half * (0.82 if k == len(pts) - 1 else 1.0)
				rings_f.append((c, ax, P(h, h, h * 1.08, h * 1.08), {hd: 1.0}))

			def finger_frame(ax):
				u = (palm_n - ax * palm_n.dot(ax)).normalized()
				return ax, u, ax.cross(u)

			lf = skin.loft(rings_f, "skin", 4, math.pi / 4.0, finger_frame)
			skin.cap(lf[0], pts[0] - dirs[0] * 0.006, {hd: 1.0}, "skin")
			skin.cap(lf[-1], pts[-1] + dirs[-1] * 0.010, {hd: 1.0}, "skin")

		knuckle = w0 + d * 0.080
		for off, lengths in ((0.029, (0.042, 0.034)), (0.010, (0.045, 0.036)),
				(-0.009, (0.042, 0.034)), (-0.027, (0.035, 0.028))):
			finger(knuckle + f * off, d, lengths, (math.radians(24), math.radians(58)), 0.0108)
		thumb_base = w0 + d * 0.024 + f * 0.028 + palm_n * 0.011
		thumb_dir = (d * 0.60 + f * 0.62 + palm_n * 0.30).normalized()
		finger(thumb_base, thumb_dir, (0.038, 0.032), (math.radians(10), math.radians(35)), 0.0120)


# ── neck, head and hair ───────────────────────────────────────────────

## Head rings by height, chin to crown: (z, centre y, front, cheek, side,
## back-side, back) radii. The cheek and back-side radii sit at 45° between
## the others, so a square jaw is a cheek radius close to the side one, and
## a rounder skull is a cheek radius well inside it.
HEAD = [
	(1.874, -0.040, 0.030, 0.030, 0.032, 0.030, 0.026),
	(1.889, -0.032, 0.064, 0.058, 0.056, 0.050, 0.040),   # under the chin
	(1.914, -0.020, 0.082, 0.074, 0.070, 0.066, 0.058),   # chin and the jaw's V
	(1.952, -0.008, 0.092, 0.086, 0.082, 0.080, 0.078),   # mouth, the jaw's corner
	(1.990, 0.000, 0.099, 0.094, 0.087, 0.093, 0.097),    # cheekbones
	(2.024, 0.002, 0.102, 0.092, 0.088, 0.098, 0.104),    # eyes
	(2.048, 0.003, 0.105, 0.090, 0.087, 0.100, 0.107),    # brow ridge
	(2.084, 0.005, 0.094, 0.085, 0.084, 0.098, 0.104),    # forehead
	(2.117, 0.007, 0.074, 0.072, 0.072, 0.083, 0.089),
	(2.141, 0.008, 0.042, 0.042, 0.042, 0.050, 0.054),
]
HEAD_X = 0.007
HEAD_SEGMENTS = 14


def head_row(z):
	if z <= HEAD[0][0]:
		return HEAD[0]
	for a, b in zip(HEAD, HEAD[1:]):
		if z <= b[0]:
			t = (z - a[0]) / (b[0] - a[0])
			return tuple(lerp(x, y, t) for x, y in zip(a, b))
	return HEAD[-1]


def head_radius(theta, row):
	"""Piecewise-linear in angle between the row's control radii: side
	(0°), cheek (45°), front (90°), cheek, side (180°), back-side (225°),
	back (270°), back-side."""
	_, _, front, cheek, side, backside, back = row
	ctrl = [(0, side), (45, cheek), (90, front), (135, cheek), (180, side),
		(225, backside), (270, back), (315, backside), (360, side)]
	deg = math.degrees(theta) % 360.0
	for (a0, r0), (a1, r1) in zip(ctrl, ctrl[1:]):
		if deg <= a1:
			return lerp(r0, r1, (deg - a0) / (a1 - a0))
	return side


def head_point(theta, z, grow_by=0.0):
	row = head_row(z)
	r = head_radius(theta, row) + grow_by
	return Vector((HEAD_X + math.cos(theta) * r, row[1] - math.sin(theta) * r, z))


def build_neck_and_head(skin, hair):
	# A thick athlete's neck: it's what joins the head to the trapezius
	# slope of the guernsey rather than balancing on it.
	neck = [
		(1.730, P(0.064, 0.064, 0.060, 0.068)),
		(1.800, P(0.069, 0.069, 0.062, 0.067)),
		(1.850, P(0.068, 0.068, 0.060, 0.071)),
		(1.890, P(0.064, 0.064, 0.055, 0.068)),
		(1.928, P(0.057, 0.057, 0.048, 0.063)),
	]
	ny = COLLAR_Y

	def neck_w(p):
		return blend("spine2", "head", ramp(p.z, 1.78, 1.90))

	rings = [(Vector((HEAD_X, ny, z)), UP, prof, neck_w(Vector((0, 0, z)))) for z, prof in neck]
	lofted = skin.loft(rings, "skin", 10, math.radians(18.0), lambda ax: (UP, SIDE, FORWARD))
	skin.cap(lofted[0], Vector((HEAD_X, ny, 1.72)), {"spine2": 1.0}, "skin")
	skin.cap(lofted[-1], Vector((HEAD_X, ny, 1.94)), {"head": 1.0}, "skin")

	head_w = {"head": 1.0}
	n = HEAD_SEGMENTS
	start_face = len(skin.faces)
	head_rings = []
	for row in HEAD:
		pts = [head_point(2.0 * math.pi * i / n, row[0]) for i in range(n)]
		head_rings.append(skin.ring(pts, head_w))
	for k in range(len(HEAD) - 1):
		ca = Vector((HEAD_X, HEAD[k][1], HEAD[k][0]))
		cb = Vector((HEAD_X, HEAD[k + 1][1], HEAD[k + 1][0]))
		skin.bridge(head_rings[k], head_rings[k + 1], "skin", ca, cb)
	skin.cap(head_rings[0], Vector((HEAD_X, HEAD[0][1] + 0.005, HEAD[0][0] - 0.006)), head_w, "skin")
	skin.cap(head_rings[-1], Vector((HEAD_X, HEAD[-1][1], 2.151)), head_w, "skin")

	# Features are placed by casting onto the head itself, so they sit on
	# whatever the HEAD table says the face is.
	tree = skin.bvh(skin.faces[start_face:])

	def on_face(x, z, lift=0.002):
		hit, normal, _, _ = tree.ray_cast(Vector((x, -0.5, z)), Vector((0, 1, 0)))
		if hit is None:
			row = head_row(z)
			return Vector((x, row[1] - row[2], z)), FORWARD
		return hit + normal * lift, normal

	# Nose: a faceted wedge off the face, bridge to tip.
	top, _ = on_face(HEAD_X, 2.040, 0.0)
	bl, _ = on_face(HEAD_X - 0.018, 1.982, 0.0)
	br, _ = on_face(HEAD_X + 0.018, 1.982, 0.0)
	tip_base, _ = on_face(HEAD_X, 1.990, 0.0)
	tip = tip_base + FORWARD * 0.026 + Vector((0, 0, -0.004))
	under = (bl + br) * 0.5 + FORWARD * 0.011 + Vector((0, 0, -0.005))
	i_top, i_bl, i_br, i_tip, i_un = (skin.v(p, head_w) for p in (top, bl, br, tip, under))
	nose_c = (top + bl + br) / 3.0
	for tri in ((i_top, i_tip, i_bl), (i_top, i_br, i_tip), (i_bl, i_tip, i_un), (i_tip, i_br, i_un)):
		skin.face(list(tri), "skin", (nose_c,))

	# Eyes: dark almond quads in the shade of the brow.
	for ex in (-0.035, 0.035):
		corners = []
		for dx, dz in ((-0.013, -0.004), (0.0, -0.0065), (0.013, -0.002), (0.0, 0.006)):
			outer = 0.002 if dx * ex > 0 else 0.0
			p, _ = on_face(HEAD_X + ex + dx, 2.022 + dz + outer, 0.0025)
			corners.append(skin.v(p, head_w))
		skin.face(corners, "eyes", FORWARD)

	# Mouth: a short darker line.
	corners = []
	for dx, dz in ((-0.020, 0.0), (0.020, 0.0), (0.016, 0.005), (-0.016, 0.005)):
		p, _ = on_face(HEAD_X + dx, 1.944 + dz, 0.0018)
		corners.append(skin.v(p, head_w))
	skin.face(corners, "mouth", FORWARD)

	# Ears: small slabs, angled back.
	for side in (-1.0, 1.0):
		row = head_row(2.0)
		cx = HEAD_X + side * (head_radius(0.0, row) - 0.004)
		c = Vector((cx, row[1] + 0.014, 1.998))
		ex_ = Vector((side * 0.015, 0.004, 0.0))
		ey_ = Vector((0.0, 0.021, 0.004))
		ez_ = Vector((0.0, -0.004, 0.029))
		box(skin, c + ex_ * 0.5, ex_ * 0.5, ey_, ez_, head_w, "skin")

	build_hair(hair, on_face)


## Hairline height by angle round the head (theta as head_point: 0 the left
## side, 90 the front, 270 the back): a straight front edge, a little
## recession at the temples, sideburns down in front of each ear, up over
## the ear, and a nape at the back. Short back and sides, longer on top.
HAIRLINE = [(0, 2.030), (10, 2.000), (18, 2.004), (34, 2.062), (60, 2.088), (90, 2.094),
	(120, 2.088), (146, 2.062), (162, 2.004), (170, 2.000), (180, 2.030), (205, 1.972),
	(240, 1.950), (270, 1.944), (300, 1.950), (335, 1.972), (360, 2.034)]


def hairline(deg):
	deg %= 360.0
	for (a0, z0), (a1, z1) in zip(HAIRLINE, HAIRLINE[1:]):
		if deg <= a1:
			return lerp(z0, z1, (deg - a0) / (a1 - a0))
	return HAIRLINE[-1][1]


def build_hair(hair, on_face):
	"""A shell over the skull: tight at the back and sides, thicker on top
	with a lift at the front, and a lip folded back to the scalp so its
	edge has depth. Brows are hair-coloured strips on the brow ridge."""
	head_w = {"head": 1.0}
	hn = 16
	crown = 2.150
	hair_rings = []
	# Rings all the way up to the crown: with the last one lower, the cap's
	# straight faces cut under the skull's top and it showed through.
	for u in (0.0, 0.0, 0.32, 0.62, 0.84, 0.95):
		pts = []
		for i in range(hn):
			th = 2.0 * math.pi * i / hn
			deg = math.degrees(th)
			edge = hairline(deg)
			z = lerp(edge, crown, u)
			front = max(0.0, math.sin(th))
			if not hair_rings:
				g = 0.007
			else:
				# Short back and sides that keep the skull's shape; the
				# volume is on top, more of it toward the front.
				g = 0.008 + (0.002 + 0.012 * front) * u + 0.010 * u * u
			p = head_point(th, z, g)
			if hair_rings and u >= 0.3:
				p.z += 0.012 * u * front   # lift at the front
			pts.append(p)
		hair_rings.append(hair.ring(pts, head_w))
	hc = Vector((HEAD_X, 0.0, 2.05))
	hair.bridge(hair_rings[0], hair_rings[1], "hair", hc, hc, hint=Vector((0, 0, -1)))
	for k in range(1, len(hair_rings) - 1):
		hair.bridge(hair_rings[k], hair_rings[k + 1], "hair", Vector((HEAD_X, 0.0, 1.95)), Vector((HEAD_X, 0.0, 2.2)))
	hair.cap(hair_rings[-1], Vector((HEAD_X, 0.004, crown + 0.024)), head_w, "hair")

	for ex in (-0.035, 0.035):
		corners = []
		for dx, dz in ((-0.018, 0.0), (0.018, 0.0), (0.018, 0.008), (-0.018, 0.008)):
			slope = -0.004 if dx * ex < 0 else 0.003
			p, _ = on_face(HEAD_X + ex + dx, 2.038 + dz + slope, 0.0045)
			corners.append(hair.v(p, head_w))
		hair.face(corners, "hair", FORWARD)


def box(part, c, ex, ey, ez, w, slot):
	"""A box centred on c with half-extent vectors ex, ey, ez."""
	idx = []
	for sx in (-1, 1):
		for sy in (-1, 1):
			for sz in (-1, 1):
				idx.append(part.v(c + ex * sx + ey * sy + ez * sz, w))
	faces = ((0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3))
	for fc in faces:
		part.face([idx[k] for k in fc], slot, (c,))


# ── guernsey ──────────────────────────────────────────────────────────

## Guernsey rings: (z, half width, front, back, squareness, bulges). A
## sleeveless AFL guernsey on an athlete: a waist that tucks into the
## shorts, lats flaring out to a deep chest, and a shoulder yoke that runs
## out to the acromion and tucks under each deltoid. Above the yoke the
## trapezius slopes up to the collar. Bulge angles: 90 front, 270 back,
## 0 / 180 the sides; pecs either side of the sternum, lats and the
## shoulder blades behind.
PECS = ((62, 26, 0.008), (118, 26, 0.008))
LATS = ((222, 30, 0.010), (318, 30, 0.010))
BLADES = ((246, 22, 0.006), (294, 22, 0.006))
GUERNSEY = [
	(1.228, 0.159, 0.099, 0.108, 2.2, ()),
	(1.262, 0.157, 0.098, 0.107, 2.2, ()),
	(1.320, 0.158, 0.099, 0.108, 2.2, ()),
	(1.400, 0.168, 0.106, 0.113, 2.3, ()),
	(1.480, 0.188, 0.117, 0.118, 2.5, ()),
	(1.550, 0.208, 0.127, 0.122, 2.6, LATS),
	(1.610, 0.221, 0.132, 0.124, 2.7, LATS + PECS),
	(1.665, 0.229, 0.135, 0.123, 2.7, PECS + BLADES),
	(1.712, 0.237, 0.127, 0.115, 2.9, BLADES),
	(1.750, 0.244, 0.108, 0.102, 3.1, ()),
	(1.784, 0.206, 0.088, 0.090, 2.6, ()),
	(1.814, 0.150, 0.076, 0.083, 2.2, ()),
	(1.840, 0.098, 0.070, 0.080, 2.0, ()),
]
GUERNSEY_SEGMENTS = 20
## The neck's centre line, front to back (build_neck_and_head's ny): the
## collar and the guernsey's top rings sit on it.
COLLAR_Y = 0.012


def torso_frame(_ax):
	return UP, SIDE, FORWARD


def build_guernsey(shirt):
	n = GUERNSEY_SEGMENTS
	rings = []
	for z, hw, fr, bk, sq, bulge in GUERNSEY:
		# The top rings move back onto the neck's centre line (COLLAR_Y):
		# on the spine's, the back of the neck came out over the edge.
		y = lerp(spine_y(z), COLLAR_Y, ramp(z, 1.75, 1.84))
		rings.append((Vector((0.004, y, z)), UP, P(hw, hw, fr, bk, bulge, sq), torso_w))
	first = len(shirt.faces)
	shirt.loft(rings, "jersey", n, 0.0, torso_frame)

	# The number: guernsey faces on the back inside the number box (plus a
	# face's width, so the box never straddles a jersey face) become
	# "number" faces; the shader draws the digits from their UVMap.
	(cx, cz), (w, h) = NUMBER_CENTRE, NUMBER_SIZE
	for k in range(first, len(shirt.faces)):
		idx, slot = shirt.faces[k]
		pts = [shirt.co[i] for i in idx]
		c = sum(pts, Vector()) / len(pts)
		nrm = shirt.normal(idx).normalized()
		if nrm.y > 0.25 and abs(c.x - cx) < w * 0.5 + 0.03 and abs(c.z - cz) < h * 0.5 + 0.05:
			shirt.faces[k] = (idx, "number")

	# Collar: a band round the neck hole with a shallow V at the front and
	# a lip folded inside.
	def collar_ring(z, hw, fr, bk, vdip):
		pts = []
		for i in range(n):
			th = 2.0 * math.pi * i / n
			p = profile_point(Vector((0.004, COLLAR_Y, z)), SIDE, FORWARD, th, P(hw, hw, fr, bk))
			p.z -= vdip * max(0.0, math.sin(th)) ** 6
			pts.append(p)
		return shirt.ring(pts, torso_w)

	# The low edge tucks just inside the guernsey's top ring, the band
	# stands a couple of centimetres proud of it, and the fold turns in
	# toward the neck.
	low = collar_ring(1.834, 0.093, 0.064, 0.076, 0.026)
	high = collar_ring(1.868, 0.082, 0.066, 0.077, 0.022)
	fold = collar_ring(1.860, 0.076, 0.061, 0.072, 0.020)
	cc_lo, cc_hi = Vector((0.004, COLLAR_Y, 1.80)), Vector((0.004, COLLAR_Y, 1.90))
	shirt.bridge(low, high, "trim", cc_lo, cc_hi)
	shirt.bridge(high, fold, "trim", cc_lo, cc_hi, hint=UP)


# ── shorts ────────────────────────────────────────────────────────────

## Shorts hip rings: (z, half width, front, back). Fitted AFL shorts: a
## waistband just under the guernsey's hem line, a little room for the
## glutes, and no wider at the hips than the thighs under them need.
SHORTS_HIPS = [
	(1.262, 0.174, 0.111, 0.120),   # waistband, on the hips
	(1.200, 0.191, 0.116, 0.129),
	(1.132, 0.212, 0.121, 0.137),   # glutes
	(1.068, 0.226, 0.124, 0.137),
	(1.012, 0.230, 0.122, 0.130),
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
	# Low down they're centred on the hip joints too, front to back, not on
	# the spine 2.4 cm behind them: a thigh turns about its joint, and the
	# shorts in front of it were only ~5 cm away, so a running stride's
	# knee lift swept the top of the thigh out through the front of the hip.
	# A slightly squarer section there gives the front corners more room.
	hip_y = bone("upperleg.l")[0].y
	for z, hw, fr, bk in SHORTS_HIPS:
		c = Vector((cx, lerp(hip_y, spine_y(z), ramp(z, 1.10, 1.20)), z))
		sq = lerp(2.4, 2.0, ramp(z, 1.10, 1.22))
		pts = [profile_point(c, SIDE, FORWARD, 2.0 * math.pi * i / n, P(hw, hw, fr, bk, sq=sq)) for i in range(n)]
		hips.append((c, shorts.ring(pts, torso_w)))
	for (ca, ra), (cb, rb) in zip(hips, hips[1:]):
		shorts.bridge(ra, rb, "shorts", ca, cb)
	# The front panel over each hip rides up with its thigh a little, the
	# way real shorts get shoved up by a lifted knee. Rigid to the pelvis,
	# a sprint's knee lift (run_fwd) put the thigh straight through it.
	# The seat's lower edge does the same with a leg swung back (the
	# smother dive's trailing legs pushed the back of the thigh into it).
	for row, share, seat in ((2, 0.12, 0.0), (3, 0.34, 0.22)):
		c_row, ring = hips[row]
		for k in ring:
			d = shorts.co[k] - c_row
			front = clamp01(-d.y / max(d.length, 1e-6))
			back = clamp01(d.y / max(d.length, 1e-6))
			side = ramp(abs(d.x), 0.03, 0.10)
			s = (share * front + seat * back) * side
			if s > 0.0:
				ul = "upperleg.l" if d.x > 0.0 else "upperleg.r"
				w = {b: x * (1.0 - s) for b, x in shorts.w[k].items()}
				w[ul] = w.get(ul, 0.0) + s
				shorts.w[k] = w

	# Waistband lip folded inside.
	z0, hw, fr, bk = SHORTS_HIPS[0]
	c0 = Vector((cx, spine_y(z0), z0 - 0.012))
	fold = shorts.ring([profile_point(c0, SIDE, FORWARD, 2.0 * math.pi * i / n,
		P(hw - 0.012, hw - 0.012, fr - 0.011, bk - 0.011)) for i in range(n)], torso_w)
	shorts.bridge(hips[0][1], fold, "shorts", c0, c0, hint=UP)

	bottom_c, bottom = hips[-1]
	# The inseam: the crotch plus a point either side of it on the centre
	# seam, shared by both legs. With the crotch alone, each leg's inner
	# side was one flat chord from the front centre to the crotch to the
	# back centre, and the inner thigh came straight through it.
	crotch = shorts.v(Vector((cx, bottom_c.y + 0.004, 0.980)), {"pelvis": 1.0})
	seam_f = shorts.v(Vector((cx, bottom_c.y - 0.074, 0.987)), {"pelvis": 1.0})
	seam_b = shorts.v(Vector((cx, bottom_c.y + 0.082, 0.989)), {"pelvis": 1.0})
	front_i, back_i = n // 4, 3 * n // 4
	loops = {
		".l": [bottom[(back_i + k) % n] for k in range(n // 2 + 1)] + [seam_f, crotch, seam_b],
		".r": [bottom[front_i + k] for k in range(n // 2 + 1)] + [seam_b, crotch, seam_f],
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
		# Fitted legs: the hem sits a centimetre off the thigh, so you
		# don't look up into the shorts, and follows the thigh outright.
		legs = [
			(0.110, P(0.110, 0.110, 0.122, 0.116), 0.22),   # eases the pelvis -> thigh blend
			(0.150, P(0.104, 0.103, 0.114, 0.109), 0.08),
			(0.185, P(0.101, 0.099, 0.109, 0.105), 0.0),
			(0.206, P(0.098, 0.096, 0.106, 0.102), 0.0),   # hem
		]
		for t, prof, pelvis_share in legs:
			c = hip + thigh_dir * t
			pts = [profile_point(c, s, f, th, prof) for th in thetas]
			w = {"pelvis": pelvis_share, ul: 1.0 - pelvis_share} if pelvis_share > 0 else {ul: 1.0}
			ring = shorts.ring(pts, w)
			shorts.bridge(prev, ring, "shorts", prev_c, c)
			prev, prev_c = ring, c
		# Blend the split loop itself between pelvis and thigh, so the legs
		# of the shorts follow the thighs from the crotch down. Like real
		# shorts, the front creases with the pelvis and the seat stretches
		# with the thigh: weighted evenly, a big hip flexion (knocked_back,
		# tackle_takedown) dragged the front of the loop up into the body
		# and the shorts caved in at the crease.
		for k in loop:
			if k in (crotch, seam_f, seam_b, bottom[front_i], bottom[back_i]):
				continue
			d = shorts.co[k] - c_loop
			back = clamp01(0.5 + 0.5 * d.dot(-f) / max(d.length, 1e-6))   # 0 front .. 1 back
			th = lerp(0.55, 0.72, back)
			shorts.w[k] = {"pelvis": 1.0 - th, ul: th}
		# The hem's lining: a short strip folded up inside, close to the
		# outer wall, so the edge has thickness without a cuff showing.
		c_hem = hip + thigh_dir * 0.201
		hem_fold = shorts.ring([profile_point(c_hem, s, f, th, P(0.095, 0.093, 0.103, 0.099)) for th in thetas], {ul: 1.0})
		shorts.bridge(prev, hem_fold, "shorts", c_hem, c_hem, hint=-thigh_dir)
	# The crotch and the two centre-seam vertices belong to both legs. The
	# crotch itself follows them more: at 70% pelvis a running stride left
	# it behind and the leading thigh came through the inside of the leg.
	for k in (bottom[front_i], bottom[back_i]):
		shorts.w[k] = {"pelvis": 0.7, "upperleg.l": 0.15, "upperleg.r": 0.15}
	for k in (seam_f, seam_b):
		shorts.w[k] = {"pelvis": 0.6, "upperleg.l": 0.2, "upperleg.r": 0.2}
	shorts.w[crotch] = {"pelvis": 0.5, "upperleg.l": 0.25, "upperleg.r": 0.25}


# ── boots ─────────────────────────────────────────────────────────────

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
		ft = "foot" + sfx

		def bw(p):
			share = ankle_foot(p.z)
			return {ft: share, "lowerleg" + sfx: 1.0 - share} if share < 1.0 else {ft: 1.0}

		rings = []
		for y, w, zt, zs in BOOT:
			prof = [
				(-w, zs), (-w, zs + SOLE), (-w * 0.98, zs + (zt - zs) * 0.45), (-w * 0.74, zt - 0.014),
				(-w * 0.28, zt), (w * 0.28, zt), (w * 0.74, zt - 0.014), (w * 0.98, zs + (zt - zs) * 0.45),
				(w, zs + SOLE), (w, zs),
			]
			pts = [Vector((x0 + px, y, pz)) for px, pz in prof]
			rings.append((Vector((x0, y, (zt + zs) * 0.5)), boots.ring(pts, bw)))
		# Ring segments: 0 the sole's outer edge, 1-7 the upper, 8 the other
		# edge, 9 the underside.
		seg = ["sole"] + ["boot"] * 7 + ["sole", "sole"]
		for (ca, ra), (cb, rb) in zip(rings, rings[1:]):
			boots.bridge(ra, rb, None, ca, cb, slots=seg)
		hc = rings[0][0]
		boots.cap(rings[0][1], hc + Vector((0, 0.012, 0)), bw(hc), "boot")
		tc = rings[-1][0]
		boots.cap(rings[-1][1], tc + Vector((0, -0.012, -0.004)), {ft: 1.0}, "boot")

		# Studs: six hex frustums, four under the forefoot, two at the heel.
		for sx, sy in ((-0.030, -0.205), (0.030, -0.205), (-0.028, -0.268), (0.028, -0.268),
				(-0.022, 0.032), (0.022, 0.032)):
			c = Vector((x0 + sx, sy, 0.0))
			top = boots.ring([c + Vector((math.cos(k * math.pi / 3) * 0.0095, math.sin(k * math.pi / 3) * 0.0095, 0.013)) for k in range(6)], {ft: 1.0})
			bot = boots.ring([c + Vector((math.cos(k * math.pi / 3) * 0.0062, math.sin(k * math.pi / 3) * 0.0062, 0.0)) for k in range(6)], {ft: 1.0})
			boots.bridge(top, bot, "studs", c + Vector((0, 0, 0.013)), c)
			boots.face(list(bot), "studs", Vector((0, 0, -1)))


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


def remove_old_materials():
	"""The first Build 7 had a material per kit slot; this one has one."""
	gone = []
	for m in list(bpy.data.materials):
		if m.name != MATERIAL and m.users == 0:
			gone.append(m.name)
			bpy.data.materials.remove(m)
	return gone


def build():
	arm = bpy.data.objects[ARMATURE]
	collection = arm.users_collection[0]
	removed = remove_build6_meshes()

	skin = Part("Body")
	build_legs(skin)
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
	total = 0
	for part in (skin, hair, shirt, shorts, boots):
		ob = build_object(part, arm, collection)
		tris = sum(len(p.vertices) - 2 for p in ob.data.polygons)
		total += tris
		slots = sorted({s for _, s in part.faces})
		report[ob.name] = {"verts": len(ob.data.vertices), "tris": tris, "slots": slots}
	report["total_tris"] = total
	report["old_materials_removed"] = remove_old_materials()
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
