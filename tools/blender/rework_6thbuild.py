"""Reworks Build 6 ("6thbuild") in its own .blend, ON THE USER'S OWN MESH:
the 2026-11-24 pass toward the black-and-red reference turnaround
(docs/review/8thbuild/reference_turnaround.webp).

    blender "F:/dev/learning-&-development/New Folder/6thbuild.blend" --background --python tools/blender/rework_6thbuild.py -- --save

Without --save nothing is written (chain render_6thbuild_review.py after it
to look first). Re-running rebuilds from the untouched originals, so tune
the tables here and run it again. See docs/BUILD6_REWORK.md.

WHAT IT KEEPS (the user's call, 2026-11-24: "keep the build and design I
had because I made that build myself")
* The hand-modelled Body, Shirt, Shorts and Shoes: their topology, their
  shapes and the way the torso, shoulders and arms were pulled out of one
  mesh from the head down, so the arm grows out of the shoulder rather
  than sitting beside it. Every original vertex stays where it was.
* The half-body + Mirror modifier workflow (X, clipping, merge, mirrored
  vertex groups): only the left half (+X) is modelled.
* The object transforms, the material names, the Armature and every
  clip.
* A copy of each original, untouched, as "<name>_original" in the excluded
  collection ORIGINALS. Each run starts from those copies.

WHAT CHANGES
* HANDS. The old hand (854 vertices, a mitten of fused fingers) is removed
  past the forearm's wrist ring, and a new one is bridged onto that ring:
  a domed palm with a thenar pad, four fingers of three phalanges with
  knuckles, slightly fanned and gently curled, and a thumb lying along the
  index finger. Rigid on the hand bone (there are no finger bones).
* A few EDGE LOOPS where a muscle needs one: the biceps, the forearm's
  bulge below the elbow and the calf. Each is a cut across the existing
  limb faces (bmesh bisect), then that new ring alone is pushed out, so
  the limb keeps its original rings and silhouette elsewhere.
* SOCKS: three horizontal cuts round each shin give a sock top at
  mid-calf and a band under it (the reference's black sock with a red
  band). Material only; no shape change.
* FACE AND HAIR as overlays on the original head (it isn't reshaped): a
  nose, brow ridge and brows, eyes with lids, lips, C-shaped
  ears, and a short haircut that is the head's own faces above a hairline,
  lifted off the scalp (more on top) with a folded edge.
* SKIN WEIGHTS, rewritten from the bones (weights()). The originals came
  from Blender's automatic weights and were wrong in places that showed in
  every clip: the whole forearm was on the hand bone, the shirt didn't
  follow the torso under it. Now skin and cloth at the same spot get the
  same weights from one function, so they bend together: the torso by
  height (pelvis, spine1, spine2, with the clavicle over the shoulder),
  the arm and leg along their chains with a short blend at each joint,
  the neck into the head, the boot rigid on the foot to its collar.

Gameplay doesn't read any of this: the skeleton, the anchors and the
ragdoll come from the bones, unchanged.
"""

import math
import os
import sys

import bpy
import bmesh
from mathutils import Vector
from mathutils.bvhtree import BVHTree

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_8thbuild_mesh as B  # noqa: E402  (Part, lofts, frames, torso_w, ankle_foot, PREVIEW)

ARMATURE = "Armature"
PARTS = ("Body", "Shirt", "Shorts", "Shoes")
ORIGINALS = "6thbuild originals (untouched)"
ORIGINAL_SUFFIX = "_original"

## Materials this pass adds, by the kit slot they preview (and export as;
## export_6thbuild.MATERIAL_SLOTS maps names to slots).
NEW_MATERIALS = {
	"Sock_Mat": "socks", "SockBand_Mat": "accent", "Hair_Mat": "hair",
	"Iris_Mat": "eyes", "EyeWhite_Mat": "eyewhite", "Lips_Mat": "mouth",
}
## The original materials get the reference's preview colours (Blender's
## viewport only; the game colours them per team).
PREVIEW_ORIGINAL = {"Skin.001": "skin", "Shirt_Mat": "jersey", "Shorts_Mat": "shorts", "Shoes_Mat": "boot"}
## Material name (lower case, first fragment that matches) -> kit slot, for
## everything that reads this file by slot: export_6thbuild.py (the kit
## shader's slots) and check_6thbuild_deform.py.
MATERIAL_SLOTS = [
	("sockband", "accent"), ("sock", "socks"), ("eyewhite", "eyewhite"), ("iris", "eyes"),
	("lips", "mouth"), ("hair", "hair"), ("sole", "sole"), ("studs", "studs"),
	("short", "shorts"), ("shirt", "jersey"), ("shoe", "boot"), ("skin", "skin"),
]


def slot_for_material(name):
	low = (name or "").lower()
	for frag, slot in MATERIAL_SLOTS:
		if frag in low:
			return slot
	return "skin"


SLOT_MATERIAL = {"skin": "Skin.001", "hair": "Hair_Mat", "eyes": "Iris_Mat",
	"eyewhite": "EyeWhite_Mat", "mouth": "Lips_Mat"}


def bone(name):
	b = bpy.data.objects[ARMATURE].data.bones[name]
	return b.head_local.copy(), b.tail_local.copy()


ramp, lerp = B.ramp, B.lerp


# ── weights ───────────────────────────────────────────────────────────

def _polyline_param(p, pts):
	"""(arc length of the nearest point on the polyline, distance). Before
	the first point the arc length goes negative along the first segment."""
	best = (1e9, 0.0)
	acc = 0.0
	for i, (a, b) in enumerate(zip(pts, pts[1:])):
		ab = b - a
		L = ab.length
		t = (p - a).dot(ab) / (L * L)
		if i == 0:
			t = min(t, 1.0)
		elif i == len(pts) - 2:
			t = max(t, 0.0)
		else:
			t = min(max(t, 0.0), 1.0)
		q = a + ab * t
		d = (p - q).length
		if d < best[0]:
			best = (d, acc + t * L)
		acc += L
	return best[1], best[0]


class Chains:
	"""The left arm and leg as polylines, built once per run."""

	def __init__(self):
		s0, s1 = bone("shoulder.l")
		_, e = bone("upperarm.l")
		_, w = bone("lowerarm.l")
		h0, h1 = bone("hand.l")
		self.arm = [s0, s1, e, w, w + (h1 - h0).normalized() * 0.30]
		self.c_sh = (s1 - s0).length
		self.c_el = self.c_sh + (e - s1).length
		self.c_wr = self.c_el + (w - e).length
		hip, knee = bone("upperleg.l")
		_, ankle = bone("lowerleg.l")
		f0, f1 = bone("foot.l")
		# On along the foot to past the boot's toe, so the whole boot is
		# near the chain.
		self.leg = [hip, knee, ankle, f1 + (f1 - f0).normalized() * 0.08]
		self.c_kn = (knee - hip).length


def arm_chain_w(ch, c):
	"""Weights along the arm by arc length from the clavicle's root."""
	if c < ch.c_sh - 0.03:
		return {"shoulder.l": 1.0}
	if c < ch.c_el - 0.05:
		return B.blend("shoulder.l", "upperarm.l", ramp(c, ch.c_sh - 0.03, ch.c_sh + 0.06))
	if c < ch.c_wr - 0.02:
		return B.blend("upperarm.l", "lowerarm.l", ramp(c, ch.c_el - 0.05, ch.c_el + 0.04))
	return B.blend("lowerarm.l", "hand.l", ramp(c, ch.c_wr - 0.02, ch.c_wr + 0.045) * 0.6)


def leg_chain_w(ch, u, p):
	w = B.blend("upperleg.l", "lowerleg.l", ramp(u, ch.c_kn - 0.04, ch.c_kn + 0.04))
	if u > ch.c_kn:
		foot = B.ankle_foot(p.z)
		if foot > 0.0:
			w = {k: x * (1.0 - foot) for k, x in w.items()}
			w["foot.l"] = w.get("foot.l", 0.0) + foot
	return w


def mix(a, b, t):
	if t <= 0.0:
		return a
	if t >= 1.0:
		return dict(b)
	out = {k: x * (1.0 - t) for k, x in a.items()}
	for k, x in b.items():
		out[k] = out.get(k, 0.0) + x * t
	return out


def weights(ch, p):
	"""Skin and cloth alike, at a rest-pose point on the left half."""
	ax = abs(p.x)
	w = B.torso_w(Vector((ax, p.y, p.z)))
	w = {k.replace(".r", ".l"): x for k, x in w.items()}
	# Neck and head.
	if ax < 0.10 and p.z > 1.78:
		w = mix(w, B.blend("spine2", "head", ramp(p.z, 1.80, 1.92)), ramp(ax, 0.10, 0.07))
	# The arm grows out of the shoulder: share by distance along the
	# clavicle, kept off the chest and lats below the shoulder line.
	# Only near the arm: its thickest part (the deltoid) is ~0.11 m from
	# the chain, the lats under the armpit ~0.2. Without the gate the
	# shorts' waist took the forearm's weights (it projects onto the
	# chain's far end).
	c, dist = _polyline_param(Vector((ax, p.y, p.z)), ch.arm)
	a = ramp(c, 0.02, 0.10) * ramp(ax, 0.07, 0.11) * ramp(dist, 0.15, 0.12)
	if c < ch.c_sh + 0.02:
		a *= ramp(p.z, 1.60, 1.70)
	if a > 0.0:
		w = mix(w, arm_chain_w(ch, c), a)
	# The leg from the hip pivot down; the crotch's middle stays pelvis.
	if p.z < 1.25:
		u, dist = _polyline_param(Vector((ax, p.y, p.z)), ch.leg)
		g = ramp(u, -0.03, 0.10) * ramp(ax, 0.015, 0.06) * ramp(dist, 0.17, 0.13)
		if g > 0.0:
			w = mix(w, leg_chain_w(ch, u, p), g)
	total = sum(w.values())
	return {k: x / total for k, x in w.items() if x / total > 1e-3}


def write_weights(ob, bm, ch, only=None):
	"""Rule weights onto every vertex of a world-space bmesh (or `only`).
	A vertex on the mirror plane is one vertex for both sides, so its left
	weights are split half to the right."""
	dl = bm.verts.layers.deform.verify()
	gi = {vg.name: vg.index for vg in ob.vertex_groups}
	for v in (only if only is not None else bm.verts):
		w = weights(ch, v.co)
		if abs(v.co.x) < 1e-4:
			w2 = {}
			for k, x in w.items():
				if k.endswith(".l"):
					w2[k] = w2.get(k, 0.0) + x * 0.5
					w2[k[:-2] + ".r"] = w2.get(k[:-2] + ".r", 0.0) + x * 0.5
				else:
					w2[k] = w2.get(k, 0.0) + x
			w = w2
		v[dl].clear()
		for k, x in w.items():
			v[dl][gi[k]] = x


# ── helpers on a world-space bmesh ────────────────────────────────────

def to_world(ob):
	bm = bmesh.new()
	bm.from_mesh(ob.data)
	bmesh.ops.transform(bm, matrix=ob.matrix_world, verts=bm.verts)
	return bm


def from_world(ob, bm):
	bmesh.ops.transform(bm, matrix=ob.matrix_world.inverted(), verts=bm.verts)
	bm.to_mesh(ob.data)
	bm.free()
	ob.data.update()


def axis_coords(p, h, ax):
	t = (p - h).dot(ax)
	return t, (p - h) - ax * t


def cut_loop(bm, bone_name, t_cut, reach, keep, scale):
	"""A new edge loop across one limb at t_cut (m down the bone), its ring
	then pushed out by `scale` (out, in, front, back multipliers on the
	bone's frame, as B.frame: out = away from the midline in the A-pose).
	`reach`: (min t, max t, max radius) for the faces cut; `keep`: a test on
	a world point that keeps other body parts out of the cut."""
	h, tl = bone(bone_name)
	ax = (tl - h).normalized()
	t0, t1, rmax = reach
	faces = []
	for f in bm.faces:
		ok = True
		for v in f.verts:
			t, r = axis_coords(v.co, h, ax)
			if not (t0 <= t <= t1 and r.length <= rmax and keep(v.co)):
				ok = False
				break
		if ok:
			faces.append(f)
	if not faces:
		return 0
	edges = list({e for f in faces for e in f.edges})
	verts = list({v for f in faces for v in f.verts})
	res = bmesh.ops.bisect_plane(bm, geom=faces + edges + verts, dist=1e-6,
		plane_co=h + ax * t_cut, plane_no=ax)
	new = [g for g in res["geom_cut"] if isinstance(g, bmesh.types.BMVert)]
	a, s, f = B.frame(ax, 1.0)
	k_out, k_in, k_front, k_back = scale
	c = h + ax * t_cut
	for v in new:
		d = v.co - c
		ds, df = d.dot(s), d.dot(f)
		ds *= k_out if ds >= 0.0 else k_in
		df *= k_front if df >= 0.0 else k_back
		v.co = c + a * d.dot(a) + s * ds + f * df
	return len(new)


def cut_z(bm, z, keep):
	faces = [f for f in bm.faces if all(keep(v.co) for v in f.verts)]
	edges = list({e for f in faces for e in f.edges})
	verts = list({v for f in faces for v in f.verts})
	bmesh.ops.bisect_plane(bm, geom=faces + edges + verts, dist=1e-6,
		plane_co=(0.0, 0.0, z), plane_no=(0.0, 0.0, 1.0))


# ── the body ──────────────────────────────────────────────────────────

## Edge loops: (bone, cut at t m down it, (scale out, in, front, back)).
## Unplaytested looks, matched by eye to the reference's lean athlete.
## Biceps: the upper arm is one segment shoulder to elbow; the new ring
## sits at the biceps' peak, fuller in front. Forearm: the bulge a third
## of the way down. Calf: the belly a third of the way down the shin,
## fuller behind and on the inside.
LOOPS = [
	("upperarm.l", 0.215, (1.12, 1.08, 1.20, 1.14)),
	("lowerarm.l", 0.105, (1.16, 1.06, 1.14, 1.04)),
	("lowerleg.l", 0.165, (1.08, 1.14, 1.02, 1.24)),
]
## Sock: its top, and the band's top and bottom, as heights (m). The
## reference's sock reaches mid-calf with the band a couple of cm under its
## top.
SOCK_TOP = 0.385
BAND = (0.338, 0.362)
## The old hand starts past this distance down the forearm (its wrist ring
## sits at 0.301-0.308, the hand's first vertices at 0.33).
HAND_CUT_T = 0.318


def rework_body(ob, ch):
	bm = to_world(ob)
	e, w = bone("lowerarm.l")
	fa = (w - e).normalized()

	# The old hand.
	doomed = [v for v in bm.verts if v.co.x > 0.45 and (v.co - e).dot(fa) > HAND_CUT_T]
	bmesh.ops.delete(bm, geom=doomed, context='VERTS')
	wrist = [v for v in bm.verts if v.co.x > 0.45 and v.is_boundary]

	arm_side = lambda p: p.x > 0.12 and p.z > 1.15            # noqa: E731
	leg_side = lambda p: p.x > 0.04 and p.z < 0.62            # noqa: E731
	for name, t, k in LOOPS:
		L = (Vector(bone(name)[1]) - Vector(bone(name)[0])).length
		keep = leg_side if "leg" in name else arm_side
		reach = (-0.06, L + 0.06, 0.12)
		if name == "lowerarm.l":
			reach = (-0.06, HAND_CUT_T, 0.09)
		cut_loop(bm, name, t, reach, keep, k)

	shin = lambda p: p.x > 0.04 and p.z < 0.56                # noqa: E731
	for z in (SOCK_TOP, BAND[1], BAND[0]):
		cut_z(bm, z, shin)
	mats = [m.name for m in ob.data.materials]
	for name in ("Sock_Mat", "SockBand_Mat"):
		if name not in mats:
			ob.data.materials.append(preview_material(name, NEW_MATERIALS[name]))
			mats.append(name)
	for f in bm.faces:
		c = f.calc_center_median()
		if shin(c) and all(shin(v.co) for v in f.verts) and c.z < SOCK_TOP:
			f.material_index = mats.index("SockBand_Mat" if BAND[0] < c.z < BAND[1] else "Sock_Mat")

	# The original's faces don't all point out: about half of the forearm's
	# and the shins' were flipped, and with back faces culled (as Blender's
	# review renders and the game both do) those limbs drew as two thin
	# strips with a hole between. Outward normals fix it without moving a
	# vertex.
	bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
	write_weights(ob, bm, ch)
	wrist_pts = [v.co.copy() for v in wrist]
	head_tris = head_faces(bm)
	from_world(ob, bm)
	return wrist_pts, head_tris


def head_faces(bm):
	"""World triangles of the head (both halves), for casting the face onto
	and growing the hair from."""
	tris = []
	for f in bm.faces:
		if all(v.co.z > 1.90 and abs(v.co.y) < 0.13 and v.co.x < 0.13 for v in f.verts):
			pts = [v.co.copy() for v in f.verts]
			tris.append(pts)
			tris.append([Vector((-q.x, q.y, q.z)) for q in reversed(pts)])
	return tris


# ── the hand ──────────────────────────────────────────────────────────

## Fingers: (offset across the palm toward the thumb side, knuckle distance
## from the wrist joint, fan in degrees toward the thumb side, phalanx
## lengths proximal/middle/distal, radius at the knuckle). Index, middle,
## ring, little. The forearm's own wrist ring sits 2.7 cm past the joint,
## so the palm starts there and the knuckles sit a little further out than
## a real hand's; the fingers are a touch short to keep the hand's length.
FINGERS = [
	(0.0335, 0.129, 5.0, (0.044, 0.027, 0.022), 0.0112),
	(0.0115, 0.133, 0.5, (0.048, 0.030, 0.023), 0.0118),
	(-0.0105, 0.129, -4.5, (0.045, 0.028, 0.022), 0.0111),
	(-0.0305, 0.121, -10.0, (0.036, 0.021, 0.020), 0.0096),
]
CURL = (14.0, 28.0, 18.0)
CURL_LITTLE_EXTRA = 6.0
FINGER_SIDES = 8
## Palm rings from the wrist joint (m): (t, dorsal, palmar, thumb-side half
## width, little-side half width, bulges on theta 0 = back of the hand, 90
## thumb side, 180 palm, 270 little side): the thenar pad, the hypothenar
## ridge, the knuckles.
PALM = [
	(0.045, 0.024, 0.024, 0.038, 0.034, ()),
	(0.062, 0.019, 0.022, 0.042, 0.037, ((140, 40, 0.007), (225, 35, 0.003))),
	(0.087, 0.016, 0.020, 0.044, 0.040, ((140, 40, 0.006), (225, 35, 0.003))),
	(0.111, 0.016, 0.018, 0.046, 0.041, ((0, 60, 0.002),)),
	(0.126, 0.015, 0.015, 0.045, 0.038, ((0, 60, 0.003),)),
	(0.137, 0.010, 0.010, 0.040, 0.032, ()),
]


def build_hand(part, wrist_pts, ch):
	"""The left hand, its palm bridged from the forearm's wrist ring
	(wrist_pts, the ring's own positions: they merge back into it). The
	palm's rings have twice the ring's vertices, at its angles and halfway
	between, so the join is six quads and six triangles."""
	w0, w1 = bone("hand.l")
	hd = "hand.l"
	d, s, f = B.frame(w1 - w0, 1.0)
	palm_n = -s
	rigid = {hd: 1.0}

	cw = sum(wrist_pts, Vector()) / len(wrist_pts)
	angs = sorted(math.atan2((p - cw).dot(f), (p - cw).dot(s)) for p in wrist_pts)
	by_ang = sorted(wrist_pts, key=lambda p: math.atan2((p - cw).dot(f), (p - cw).dot(s)))
	thetas = []
	for i, a in enumerate(angs):
		b = angs[(i + 1) % len(angs)] + (2.0 * math.pi if i + 1 == len(angs) else 0.0)
		thetas += [a, (a + b) * 0.5]

	ring_w = [part.v(p, weights(ch, p)) for p in by_ang]
	rings = []
	for k, (t, dorsal, palmar, thumb, little, bulges) in enumerate(PALM):
		prof = B.P(dorsal, palmar, thumb, little, bulges, sq=2.6)
		c = w0 + d * t
		wk = {hd: 0.8, "lowerarm.l": 0.2} if k == 0 else rigid
		rings.append([part.v(B.profile_point(c, s, f, th, prof), wk) for th in thetas])
	n = len(ring_w)
	for i in range(n):
		j = (i + 1) % n
		p0, p1, p2 = rings[0][2 * i], rings[0][2 * i + 1], rings[0][(2 * i + 2) % (2 * n)]
		mid = (cw + w0 + d * PALM[0][0]) * 0.5
		part.face([ring_w[i], ring_w[j], p2, p1], "skin", (mid,))
		part.face([ring_w[i], p1, p0], "skin", (mid,))
	for k in range(len(rings) - 1):
		part.bridge(rings[k], rings[k + 1], "skin", w0 + d * PALM[k][0], w0 + d * PALM[k + 1][0])
	part.cap(rings[-1], w0 + d * (PALM[-1][0] + 0.004), rigid, "skin")

	def digit(base, dirs, lengths, radius, taper=0.80):
		pts, axes, radii = [base], [dirs[0]], [radius * 1.02]
		p = base
		for k, (dd, length) in enumerate(zip(dirs, lengths)):
			r0 = radius * (1.0 - (1.0 - taper) * k / len(lengths))
			r1 = radius * (1.0 - (1.0 - taper) * (k + 1) / len(lengths))
			pts.append(p + dd * (length * 0.5))
			axes.append(dd)
			radii.append((r0 + r1) * 0.5 * 0.90)
			p = p + dd * length
			pts.append(p)
			nxt = dirs[k + 1] if k + 1 < len(dirs) else dd
			axes.append((dd + nxt).normalized())
			radii.append(r1 * (1.02 if k + 1 < len(dirs) else 0.92))
		tip = dirs[-1]
		pts += [p + tip * radii[-1] * 0.55, p + tip * radii[-1] * 0.95]
		axes += [tip, tip]
		radii += [radii[-1] * 0.82, radii[-1] * 0.45]

		def finger_frame(axv):
			u = palm_n - axv * palm_n.dot(axv)
			if u.length < 1e-6:
				u = s.copy()
			u.normalize()
			return axv, -u, axv.cross(-u)

		specs = [(c, axv, B.P(r * 0.92, r * 0.96, r, r, sq=2.3), rigid) for c, axv, r in zip(pts, axes, radii)]
		lf = part.loft(specs, "skin", FINGER_SIDES, math.pi / FINGER_SIDES, finger_frame)
		part.cap(lf[0], pts[0] - dirs[0] * 0.004, rigid, "skin")
		part.cap(lf[-1], pts[-1] + tip * radii[-1] * 0.5, rigid, "skin")

	def bend(direction, degrees):
		a = math.radians(degrees)
		return (direction * math.cos(a) + palm_n * math.sin(a)).normalized()

	for i, (off, knuckle_t, fan, lengths, radius) in enumerate(FINGERS):
		fan_r = math.radians(fan)
		along = (d * math.cos(fan_r) + f * math.sin(fan_r)).normalized()
		extra = CURL_LITTLE_EXTRA if i == len(FINGERS) - 1 else 0.0
		c1 = CURL[0] + extra
		c2 = c1 + CURL[1] + extra
		c3 = c2 + CURL[2] + extra
		base = w0 + d * (knuckle_t - 0.014) + f * off + s * 0.002
		digit(base, [bend(along, c1), bend(along, c2), bend(along, c3)], lengths, radius)

	# The thumb: its metacarpal from the wrist's thumb side through the
	# thenar pad, the phalanges lying along the index finger.
	base = w0 + d * 0.050 + f * 0.022 + palm_n * 0.008
	dirs = [
		(d * 0.72 + f * 0.42 + palm_n * 0.40).normalized(),
		(d * 0.86 + f * 0.10 + palm_n * 0.42).normalized(),
		(d * 0.84 - f * 0.06 + palm_n * 0.52).normalized(),
	]
	digit(base, dirs, (0.040, 0.034, 0.027), 0.0135, taper=0.78)


# ── face and hair, laid on the original head ──────────────────────────

## Heights on the original head (its chin's front is at 1.934, its brow at
## ~2.066, its crown at 2.177). Everything in add_face is placed from these.
EYE_Z = 2.036
EYE_X = 0.034
NOSE = [  # (z from EYE_Z, ridge depth, ridge half width, base half width)
	(0.024, 0.003, 0.006, 0.010),
	(0.004, 0.009, 0.007, 0.012),
	(-0.016, 0.016, 0.008, 0.015),
	(-0.031, 0.023, 0.010, 0.020),
	(-0.040, 0.025, 0.011, 0.022),
]
NOSE_UNDER = -0.048
MOUTH = -0.079
EAR = (0.010, -0.020)   # (y, z from EYE_Z) of the ear's centre
## The hairline: a plane through the front at HAIR_FRONT and the back at
## HAIR_BACK (z, m), seen from the side. Short back and sides, more on top.
HAIR_FRONT = 2.100
HAIR_BACK = 1.985


def add_face(part, tree):
	F = B.FORWARD
	w = {"head": 1.0}

	def on_face(x, z, lift=0.002):
		hit, normal, _, _ = tree.ray_cast(Vector((x, -0.5, z)), Vector((0, 1, 0)))
		if hit is None:
			return Vector((x, -0.08, z)), F
		return hit + normal * lift, normal

	# Nose: a five-column shell closed underneath.
	cols = []
	for dz, depth, ridge_w, base_w in NOSE:
		z = EYE_Z + dz
		mid, _ = on_face(0.0, z, 0.0)
		row = []
		for dx, dd in ((-base_w, -0.002), (-ridge_w, depth * 0.72), (0.0, depth), (ridge_w, depth * 0.72), (base_w, -0.002)):
			p, _ = on_face(dx, z, 0.0)
			y = mid.y - dd if abs(dx) < base_w else p.y + 0.002
			row.append(part.v(Vector((p.x, y, z)), w))
		cols.append(row)
	nose_c = Vector((0.0, on_face(0.0, EYE_Z - 0.02, 0.0)[0].y + 0.02, EYE_Z - 0.02))
	for a, b in zip(cols, cols[1:]):
		for i in range(4):
			part.face([a[i], a[i + 1], b[i + 1], b[i]], "skin", (nose_c,))
	zu = EYE_Z + NOSE_UNDER
	mid, _ = on_face(0.0, zu, 0.0)
	under = [part.v(Vector((dx, mid.y - dd, zu)), w)
		for dx, dd in ((-0.019, 0.004), (-0.008, 0.012), (0.0, 0.016), (0.008, 0.012), (0.019, 0.004))]
	for i in range(4):
		part.face([cols[-1][i], cols[-1][i + 1], under[i + 1], under[i]], "skin", (nose_c,))
	back = [part.v(on_face(dx, zu + 0.001, -0.002)[0], w) for dx in (-0.019, -0.008, 0.0, 0.008, 0.019)]
	for i in range(4):
		part.face([under[i], under[i + 1], back[i + 1], back[i]], "skin", Vector((0, 0, -1)))

	ex = EYE_X
	# Brow ridge: a low wedge over the eye, highest over its outer half.
	brow = []
	for dx, dz, lift in ((-0.022, 0.016, 0.001), (-0.008, 0.020, 0.005), (0.008, 0.021, 0.006), (0.022, 0.017, 0.004)):
		p, _ = on_face(ex + dx, EYE_Z + dz, lift)
		q, _ = on_face(ex + dx, EYE_Z + dz + 0.012, -0.001)
		r, _ = on_face(ex + dx, EYE_Z + dz - 0.007, -0.001)
		brow.append((part.v(q, w), part.v(p, w), part.v(r, w)))
	bc = Vector((ex, on_face(ex, EYE_Z + 0.02, 0.0)[0].y + 0.01, EYE_Z + 0.02))
	for a, b in zip(brow, brow[1:]):
		part.face([a[0], b[0], b[1], a[1]], "skin", (bc,))
		part.face([a[1], b[1], b[2], a[2]], "skin", (bc,))
	# Brows: hair-coloured strips on the ridge.
	strip = []
	for dx, dz in ((-0.019, 0.020), (-0.006, 0.0235), (0.008, 0.0245), (0.021, 0.0205)):
		strip.append((part.v(on_face(ex + dx, EYE_Z + dz - 0.0035, 0.0062)[0], w),
			part.v(on_face(ex + dx, EYE_Z + dz + 0.0035, 0.0058)[0], w)))
	for a, b in zip(strip, strip[1:]):
		part.face([a[0], b[0], b[1], a[1]], "hair", F)

	# The eye: an almond of white, an iris, an upper lid over its top edge
	# and a thin lower lid.
	almond = [(-0.0150, -0.0008), (-0.0070, -0.0050), (0.0040, -0.0054), (0.0150, 0.0004),
		(0.0060, 0.0054), (-0.0060, 0.0056)]
	part.face([part.v(on_face(ex + dx, EYE_Z + dz, 0.0010)[0], w) for dx, dz in almond], "eyewhite", F)
	iris = []
	for k in range(6):
		a = 2.0 * math.pi * k / 6.0
		iris.append(part.v(on_face(ex + 0.0006 + math.cos(a) * 0.0060, EYE_Z + math.sin(a) * 0.0050, 0.0018)[0], w))
	part.face(iris, "eyes", F)
	lid_lo, lid_hi = [], []
	for dx, dz in ((-0.0165, 0.0005), (-0.006, 0.0068), (0.006, 0.0066), (0.0165, 0.0012)):
		lid_lo.append(part.v(on_face(ex + dx, EYE_Z + dz, 0.0036)[0], w))
		lid_hi.append(part.v(on_face(ex + dx, EYE_Z + dz + 0.0065, 0.0004)[0], w))
	for i in range(3):
		part.face([lid_lo[i], lid_lo[i + 1], lid_hi[i + 1], lid_hi[i]], "skin", (bc,))
	low_a, low_b = [], []
	for dx, dz in ((-0.014, -0.0020), (-0.005, -0.0068), (0.006, -0.0070), (0.0150, -0.0010)):
		low_a.append(part.v(on_face(ex + dx, EYE_Z + dz, 0.0016)[0], w))
		low_b.append(part.v(on_face(ex + dx, EYE_Z + dz - 0.004, -0.0004)[0], w))
	for i in range(3):
		part.face([low_a[i], low_a[i + 1], low_b[i + 1], low_b[i]], "skin", F)

	# Lips: an upper lip with a cupid's bow, a fuller lower lip, the mouth's
	# line between them.
	mz = EYE_Z + MOUTH
	xs = (-0.024, -0.012, -0.004, 0.0, 0.004, 0.012, 0.024)
	rows = [[], [], [], [], []]
	for x in xs:
		bow = 0.0016 if abs(x) == 0.004 else 0.0
		corner = abs(x) > 0.02
		rows[0].append(part.v(on_face(x, mz + 0.0085 + bow, -0.0005)[0], w))
		rows[1].append(part.v(on_face(x, mz + 0.0035, 0.0005 if corner else 0.0028)[0], w))
		rows[2].append(part.v(on_face(x, mz, 0.0002 if corner else 0.0014)[0], w))
		rows[3].append(part.v(on_face(x * 0.92, mz - 0.0045, 0.0005 if corner else 0.0034)[0], w))
		rows[4].append(part.v(on_face(x * 0.85, mz - 0.0105, -0.0005)[0], w))
	for r0, r1 in zip(rows, rows[1:]):
		for i in range(len(xs) - 1):
			part.face([r0[i], r0[i + 1], r1[i + 1], r1[i]], "mouth", F)

	# Ear: a C-shaped rim round an inner bowl, angled back.
	ey, ez = EAR[0], EYE_Z + EAR[1]
	hit, _, _, _ = tree.ray_cast(Vector((0.5, ey, ez)), Vector((-1, 0, 0)))
	root = (hit if hit is not None else Vector((0.085, ey, ez))) + Vector((-0.004, 0.0, 0.0))
	out = Vector((1.0, 0.32, 0.0)).normalized()
	up = Vector((0.0, 0.18, 1.0)).normalized()
	back = up.cross(out).normalized() * -1.0
	if back.y < 0.0:
		back = -back
	rim, bowl, plate = [], [], []
	for k in range(10):
		a = 2.0 * math.pi * k / 10.0
		hz = 0.031 if math.sin(a) > 0 else 0.026
		hy = 0.019 if math.sin(a) > 0 else 0.014
		e = up * (math.sin(a) * hz) + back * (math.cos(a) * hy)
		rim.append(part.v(root + e + out * 0.016, w))
		bowl.append(part.v(root + e * 0.55 + out * 0.010, w))
		plate.append(part.v(root + e * 0.85, w))
	for k in range(10):
		j = (k + 1) % 10
		part.face([rim[k], rim[j], bowl[j], bowl[k]], "skin", out)
		part.face([plate[k], plate[j], rim[j], rim[k]], "skin", (root + out * 0.008,))
	centre = part.v(root + out * 0.004, w)
	for k in range(10):
		part.face([bowl[k], bowl[(k + 1) % 10], centre], "skin", out)


def add_hair(part, tris):
	"""The head's own faces above the hairline, lifted off the scalp: 7 mm
	at the hairline, up to ~2 cm on top and more toward the front (a short
	back and sides with the volume on top), with the edge folded back down
	to the scalp so it has thickness. Left half only; the Mirror does the
	rest."""
	bm = bmesh.new()
	for pts in tris:
		if min(p.x for p in pts) < -1e-6:
			continue
		bm.faces.new([bm.verts.new(p) for p in pts])
	bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
	front = Vector((0.0, -0.09, HAIR_FRONT))
	backp = Vector((0.0, 0.09, HAIR_BACK))
	along = (backp - front).normalized()
	normal = Vector((0.0, -along.z, along.y))
	if normal.z < 0.0:
		normal = -normal
	geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
	bmesh.ops.bisect_plane(bm, geom=geom, dist=1e-6, plane_co=front, plane_no=normal, clear_inner=True)
	bm.normal_update()
	top = max(v.co.z for v in bm.verts)
	edge = [v for v in bm.verts if v.is_boundary]
	w = {"head": 1.0}
	idx = {}
	scalp = {}
	for v in bm.verts:
		n = v.normal.copy()
		if abs(v.co.x) < 1e-4:
			n.x = 0.0
		n.normalize()
		h = ramp((v.co - front).dot(normal), 0.0, max((top - HAIR_BACK) * 0.8, 0.05))
		frontness = ramp(-v.co.y, 0.0, 0.08)
		g = 0.005 + 0.012 * h * h + 0.006 * h * frontness
		p = v.co + n * g
		p.z += 0.006 * h * frontness
		idx[v] = part.v(p, w)
		scalp[v] = v.co - n * 0.001
	centre = Vector((0.0, 0.0, 2.04))
	for f in bm.faces:
		part.face([idx[v] for v in f.verts], "hair", (centre,))
	# The folded edge: each boundary edge (not on the mirror plane) gets a
	# strip from the hair's edge down to the scalp.
	inner = {v: part.v(scalp[v], w) for v in edge}
	for e in bm.edges:
		if not e.is_boundary:
			continue
		a, b = e.verts
		if abs(a.co.x) < 1e-4 and abs(b.co.x) < 1e-4:
			continue
		if a not in inner or b not in inner:
			continue
		part.face([idx[a], idx[b], inner[b], inner[a]], "hair", Vector((0, 0, -1)))
	bm.free()


# ── assembly ──────────────────────────────────────────────────────────

def preview_material(name, slot):
	m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
	rgb = B.srgb_to_linear(B.PREVIEW[slot])
	m.diffuse_color = (rgb[0], rgb[1], rgb[2], 1.0)
	m.roughness = 0.75
	if m.node_tree is None:
		m.use_nodes = True
	bsdf = m.node_tree.nodes.get("Principled BSDF")
	if bsdf is not None:
		bsdf.inputs["Base Color"].default_value = (rgb[0], rgb[1], rgb[2], 1.0)
		bsdf.inputs["Roughness"].default_value = 0.75
	return m


def fresh_parts():
	"""Stashes untouched copies of the four originals (once), then replaces
	the live objects with new copies of them."""
	coll = bpy.data.collections.get(ORIGINALS)
	if coll is None:
		coll = bpy.data.collections.new(ORIGINALS)
		bpy.context.scene.collection.children.link(coll)
	for name in PARTS:
		if bpy.data.objects.get(name + ORIGINAL_SUFFIX) is None:
			src = bpy.data.objects[name]
			keep = src.copy()
			keep.data = src.data.copy()
			keep.name = keep.data.name = name + ORIGINAL_SUFFIX
			coll.objects.link(keep)
	lc = bpy.context.view_layer.layer_collection.children.get(ORIGINALS)
	if lc is not None:
		lc.exclude = True
	coll.hide_render = True
	live = {}
	for name in PARTS:
		old = bpy.data.objects.get(name)
		home = old.users_collection[0] if old is not None else bpy.data.objects[ARMATURE].users_collection[0]
		if old is not None:
			me = old.data
			bpy.data.objects.remove(old, do_unlink=True)
			if me.users == 0:
				bpy.data.meshes.remove(me)
		src = bpy.data.objects[name + ORIGINAL_SUFFIX]
		ob = src.copy()
		ob.data = src.data.copy()
		ob.name = ob.data.name = name
		home.objects.link(ob)
		live[name] = ob
	return live


def prepare_groups(ob, arm):
	"""Every deform bone's group (the Mirror maps .l to .r only when the .r
	group exists), and the stray pelvis.001 group gone (nothing should be
	weighted to it; export_6thbuild folded it into pelvis)."""
	for b in arm.data.bones:
		if b.use_deform and b.name != "pelvis.001" and b.name not in ob.vertex_groups:
			ob.vertex_groups.new(name=b.name)
	stray = ob.vertex_groups.get("pelvis.001")
	if stray is not None:
		ob.vertex_groups.remove(stray)


def part_to_object(part, name, arm, collection):
	co, faces, wts = [], [], []
	remap = {}
	for idx, slot in part.faces:
		for i in idx:
			if i not in remap:
				remap[i] = len(co)
				co.append(part.co[i])
				wts.append(part.w[i])
		faces.append(([remap[i] for i in idx], slot))
	me = bpy.data.meshes.new(name)
	me.from_pydata([tuple(c) for c in co], [], [f for f, _ in faces])
	mats = []
	for _, slot in faces:
		mname = SLOT_MATERIAL[slot]
		if mname not in mats:
			mats.append(mname)
	for mname in mats:
		m = bpy.data.materials.get(mname) or preview_material(mname, NEW_MATERIALS[mname])
		me.materials.append(m)
	for poly, (_, slot) in zip(me.polygons, faces):
		poly.material_index = mats.index(SLOT_MATERIAL[slot])
		poly.use_smooth = False
	me.validate()
	me.update()
	ob = bpy.data.objects.new(name, me)
	collection.objects.link(ob)
	groups = {}
	for i, w in enumerate(wts):
		for b, x in w.items():
			vg = groups.get(b) or ob.vertex_groups.new(name=b)
			groups[b] = vg
			vg.add([i], x, 'REPLACE')
	# Keep the left half: the nose, lips and chin straddle the midline.
	bm = bmesh.new()
	bm.from_mesh(me)
	bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], dist=1e-6,
		plane_co=(0, 0, 0), plane_no=(1, 0, 0), clear_inner=True)
	for v in bm.verts:
		if abs(v.co.x) < 2e-5:
			v.co.x = 0.0
	bm.to_mesh(me)
	bm.free()
	me.update()
	return ob


def join_into(target, extra):
	with bpy.context.temp_override(active_object=target, selected_editable_objects=[target, extra],
			selected_objects=[target, extra]):
		bpy.ops.object.join()


def merge_wrist(ob, wrist_pts):
	"""Welds the hand's copy of the wrist ring to the forearm's."""
	bm = to_world(ob)
	near = [v for v in bm.verts if any((v.co - p).length < 1e-4 for p in wrist_pts)]
	bmesh.ops.remove_doubles(bm, verts=near, dist=1e-4)
	from_world(ob, bm)
	return len(near)


def rework_cloth(ob, ch):
	"""Weights from the same function as the skin under it. The shorts'
	few zero-area faces (vertex pairs on one spot) are left alone: each
	pair gets the same weights, so it stays a point."""
	bm = to_world(ob)
	# Normals left as modelled: the cloth's already point out, and the
	# shorts' zero-area faces send recalc_face_normals the wrong way.
	write_weights(ob, bm, ch)
	for f in bm.faces:
		f.smooth = False
	from_world(ob, bm)


def build():
	arm = bpy.data.objects[ARMATURE]
	ch = Chains()
	live = fresh_parts()
	for ob in live.values():
		prepare_groups(ob, arm)
	for name, slot in PREVIEW_ORIGINAL.items():
		if name in bpy.data.materials:
			preview_material(name, slot)

	body = live["Body"]
	wrist_pts, head_tris = rework_body(body, ch)
	tree = BVHTree.FromPolygons([p for t in head_tris for p in t],
		[list(range(i, i + len(t))) for i, t in zip(
			[sum(len(x) for x in head_tris[:k]) for k in range(len(head_tris))], head_tris)])
	extra = B.Part("Extras")
	build_hand(extra, wrist_pts, ch)
	add_face(extra, tree)
	add_hair(extra, head_tris)
	extra_ob = part_to_object(extra, "Body_extras_TMP", arm, body.users_collection[0])
	join_into(body, extra_ob)
	welded = merge_wrist(body, wrist_pts)
	for name in ("Shirt", "Shorts", "Shoes"):
		rework_cloth(live[name], ch)

	report = {"wrist_ring": len(wrist_pts), "wrist_welded": welded}
	total = 0
	dg = bpy.context.evaluated_depsgraph_get()
	for name in PARTS:
		ob = live[name]
		ev = ob.evaluated_get(dg).to_mesh()
		tris = sum(len(p.vertices) - 2 for p in ev.polygons)
		ob.evaluated_get(dg).to_mesh_clear()
		total += tris
		report[name] = {"half_verts": len(ob.data.vertices), "tris": tris,
			"materials": [m.name for m in ob.data.materials]}
	report["total_tris"] = total
	return report


if __name__ == "__main__":
	result = build()
	print("rework_6thbuild:", result)
	if "--save" in sys.argv:
		bpy.ops.wm.save_mainfile()
		print("rework_6thbuild: saved", bpy.data.filepath)
