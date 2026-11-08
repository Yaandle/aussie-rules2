"""Deformation check for a skinned player mesh on the 6thbuild Armature.

Plays every action on the Armature, samples it, then poses the skeleton at
the ragdoll's joint limits (RAGDOLL_POSES), and counts what a viewer would
call a skinning bug:

* poke   — a vertex of an inner layer that ends up outside the layer
           over it: skin through the guernsey or shorts, the guernsey
           out through the shorts, a sock out through a boot. Measured
           against the outer layer's nearest face, skipping faces on an
           open edge (a hem or an armhole, which the inner layer is
           SUPPOSED to come out of).
* cross  — an inner face mostly on the named bones that cuts through an
           outer face (CROSSINGS): what the vertex test can't see, a face
           crossing a crease with all its corners still inside.
* crush  — faces whose area falls under CRUSH of their rest area (a
           joint collapsing), and
* stretch — faces over STRETCH of it.

Run with the .blend open (Scripting tab, the Blender MCP, or headless):
    blender assets/blender/7thbuild.blend --background --python tools/blender/check_7thbuild_deform.py
    blender ... --python tools/blender/check_7thbuild_deform.py -- --only=tackled,rd_fetal

It reads PAIRS / MESHES below, so a replacement mesh (a scan, say) is
checked the same way once its objects are named into them. Layers are
told apart by kit slot (the generator's "slot_id" face attribute, the same
numbers as SLOTS in build_7thbuild_mesh.py). Nothing is saved; the active
action, the pose and the IK constraints are put back afterwards.

Ragdoll poses: a match ragdoll can put a body further than any clip, so
the skin has to hold at PhysicsRagdoll.BODIES' joint limits too. Each pose
turns joints to their stops from the rest pose (the pose every ragdoll
joint is built in), with the leg IK muted so the bones go where they're
put. The "_over" poses add the 10-45° a spine overshoots for a frame or
two as a torso lands (docs/ANIMATION_RAGDOLL_AUDIT.md, "What's left" 2):
those are a stress test, not a target.
"""

import math
import sys

import bpy
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

ARMATURE = "Armature"
MESHES = ["B7_Body", "B7_Guernsey", "B7_Shorts", "B7_Boots", "B7_Hair"]

## Kit slot numbers, as build_7thbuild_mesh.py's SLOTS.
SLOTS = {
	"skin": 0, "jersey": 1, "number": 2, "trim": 3, "shorts": 4, "socks": 5,
	"boot": 6, "sole": 7, "studs": 8, "hair": 9, "eyes": 10, "mouth": 11,
}

## (inner object, outer object, inner slots or None, min z, max z, bones
## to skip): only the inner object's vertices in those slots and height
## band at rest, and not mostly on a skipped bone, are tested, so each pair
## asks one question. The arms are skipped against the guernsey because
## the deltoids come out over its shoulder line by design (a sleeveless
## guernsey).
PAIRS = [
	("B7_Body", "B7_Guernsey", ("skin",), 1.40, 1.86, ("upperarm.l", "upperarm.r")),
	("B7_Body", "B7_Shorts", ("skin",), 0.88, 1.30, ()),
	("B7_Guernsey", "B7_Shorts", None, 1.0, 1.27, ()),
	("B7_Body", "B7_Boots", ("socks",), -1.0, 0.13, ()),
]
## Pairs whose outer layer is two separate pieces, one per side: a vertex
## is only tested against its own side's piece (a sock against its own
## boot, not the other foot's when the legs cross in a sling).
SAME_SIDE = {("B7_Body", "B7_Boots")}
## (inner object, outer object, inner bones): inner faces mostly on those
## bones that cross an outer face. Reported as "cross".
CROSSINGS = [
	("B7_Body", "B7_Shorts", ("upperleg.l", "upperleg.r")),
	("B7_Body", "B7_Boots", ("lowerleg.l", "lowerleg.r")),
]
POKE_TOLERANCE = 0.004   # m outside the outer surface before it counts
POKE_REACH = 0.10        # only look this far for the outer surface (the hidden
                         # thigh cone sits up to ~9 cm inside the shorts)
CRUSH = 0.15
STRETCH = 3.0
STEP = 2                 # sample every STEP frames

FWD = Vector((0.0, -1.0, 0.0))
BACK = Vector((0.0, 1.0, 0.0))
UP = Vector((0.0, 0.0, 1.0))
DOWN = Vector((0.0, 0.0, -1.0))


def _sides(bone_base, kind, toward, deg):
	"""The same move on both sides; "out" and "in" mirror."""
	out = []
	for sfx, sx in ((".l", 1.0), (".r", -1.0)):
		t = toward
		if isinstance(toward, str):
			t = Vector((sx if toward == "out" else -sx, 0.0, 0.0))
		out.append((bone_base + sfx, kind, t, deg))
	return out


## PhysicsRagdoll.BODIES' limits, from the rest pose: spine and chest
## 15° back / 35° forward / 20° sideways / 20° twist each; head 40° swing,
## 50° twist; upper arm 75° swing, 60° twist; elbow -25..120; hip 30° back /
## 65° forward / 45° sideways / 25° twist; knee -10..135; ankle 35° up /
## 45° down. (bone, "bend" toward a direction | "twist", angle).
RAGDOLL_POSES = {
	"rd_fetal": [("spine1", "bend", FWD, 35), ("spine2", "bend", FWD, 35), ("head", "bend", FWD, 40)]
		+ _sides("upperleg", "bend", FWD, 65) + _sides("lowerleg", "bend", BACK, 135)
		+ _sides("upperarm", "bend", FWD, 75) + _sides("lowerarm", "bend", FWD, 120)
		+ _sides("foot", "bend", UP, 35),
	"rd_arch": [("spine1", "bend", BACK, 15), ("spine2", "bend", BACK, 15), ("head", "bend", BACK, 40)]
		+ _sides("upperleg", "bend", BACK, 30) + _sides("lowerleg", "bend", FWD, 10)
		+ _sides("upperarm", "bend", BACK, 75) + _sides("lowerarm", "bend", BACK, 25)
		+ _sides("foot", "bend", DOWN, 45),
	"rd_sit": [("spine1", "bend", BACK, 15), ("spine2", "bend", FWD, 20)]
		+ _sides("upperleg", "bend", FWD, 65) + _sides("lowerleg", "bend", BACK, 100)
		+ _sides("upperarm", "bend", BACK, 60),
	"rd_splits": [("upperleg.l", "bend", FWD, 65), ("upperleg.r", "bend", BACK, 30),
		("lowerleg.r", "bend", BACK, 40), ("spine1", "bend", FWD, 15)],
	"rd_straddle": _sides("upperleg", "bend", "out", 45) + _sides("lowerleg", "bend", BACK, 30),
	"rd_tuck_wide": _sides("upperleg", "bend", FWD, 65) + _sides("upperleg", "bend", "out", 40)
		+ _sides("lowerleg", "bend", BACK, 135),
	"rd_side_bend": [("spine1", "bend", Vector((1, 0, 0)), 20), ("spine2", "bend", Vector((1, 0, 0)), 20),
		("head", "bend", Vector((1, 0, 0)), 40), ("upperarm.l", "bend", UP, 75),
		("upperleg.l", "bend", Vector((1, 0, 0)), 45)],
	"rd_twist": [("spine1", "twist", None, 20), ("spine2", "twist", None, 20), ("head", "twist", None, 50)]
		+ _sides("upperleg", "twist", None, 25) + _sides("upperarm", "twist", None, 60),
	"rd_arms_up": _sides("upperarm", "bend", UP, 75) + _sides("lowerarm", "bend", FWD, 60),
	"rd_reach": _sides("upperarm", "bend", FWD, 75) + _sides("upperarm", "bend", UP, 60)
		+ [("spine1", "bend", FWD, 20)],
	"rd_fetal_over": [("spine1", "bend", FWD, 60), ("spine2", "bend", FWD, 60), ("head", "bend", FWD, 50)]
		+ _sides("upperleg", "bend", FWD, 80) + _sides("lowerleg", "bend", BACK, 140),
	"rd_arch_over": [("spine1", "bend", BACK, 40), ("spine2", "bend", BACK, 40), ("head", "bend", BACK, 50)]
		+ _sides("upperleg", "bend", BACK, 40),
}


def _slot_ids(ob, me):
	attr = me.attributes.get("slot_id") or ob.data.attributes.get("slot_id")
	if attr is None:
		return [0] * len(me.polygons)
	return [d.value for d in attr.data]


def _evaluated(ob, dg):
	ev = ob.evaluated_get(dg)
	me = ev.to_mesh()
	verts = [ob.matrix_world @ v.co for v in me.vertices]
	polys = [tuple(p.vertices) for p in me.polygons]
	slots = _slot_ids(ob, me)
	ev.to_mesh_clear()
	return verts, polys, slots


def _boundary_faces(polys):
	count = {}
	for p in polys:
		for a, b in zip(p, p[1:] + p[:1]):
			k = (min(a, b), max(a, b))
			count[k] = count.get(k, 0) + 1
	open_verts = {v for k, c in count.items() if c == 1 for v in k}
	return {i for i, p in enumerate(polys) if any(v in open_verts for v in p)}


def _area(verts, p):
	a = 0.0
	o = verts[p[0]]
	for i in range(1, len(p) - 1):
		a += (verts[p[i]] - o).cross(verts[p[i + 1]] - o).length * 0.5
	return a


def _side(ob, v):
	"""".l", ".r" or "" from a vertex's heaviest bone."""
	gs = ob.data.vertices[v].groups
	if not len(gs):
		return ""
	name = ob.vertex_groups[max(gs, key=lambda g: g.weight).group].name
	return name[-2:] if name[-2:] in (".l", ".r") else ""


def _nearest_fn(inner, outer, overts, opolys):
	"""find_nearest against the outer layer, or against the inner vertex's
	own side of it for a SAME_SIDE pair. Returns (hit, normal, face index
	in the outer mesh) or (None, None, None)."""
	if (inner, outer) not in SAME_SIDE:
		tree = BVHTree.FromPolygons(overts, opolys)

		def find(_v, co):
			hit, normal, face, _ = tree.find_nearest(co, POKE_REACH)
			return hit, normal, face
		return find
	iob, oob = bpy.data.objects[inner], bpy.data.objects[outer]
	trees = {}
	for side in (".l", ".r"):
		faces = [i for i, p in enumerate(opolys) if _side(oob, p[0]) == side]
		trees[side] = (BVHTree.FromPolygons(overts, [opolys[i] for i in faces]), faces)

	def find(v, co):
		side = _side(iob, v)
		if side not in trees:
			return None, None, None
		tree, faces = trees[side]
		hit, normal, face, _ = tree.find_nearest(co, POKE_REACH)
		return hit, normal, (faces[face] if face is not None else None)
	return find


def _outer_trees(inner, outer, overts, opolys):
	"""side -> BVH of the outer layer ("" = all of it, for an ordinary pair)."""
	if (inner, outer) not in SAME_SIDE:
		return {"": BVHTree.FromPolygons(overts, opolys)}
	oob = bpy.data.objects[outer]
	return {side: BVHTree.FromPolygons(overts, [p for p in opolys if _side(oob, p[0]) == side])
		for side in (".l", ".r")}


def _crossings(tree, a, b):
	"""How many times the segment a -> b passes through the surface."""
	d = b - a
	length = d.length
	if length < 1e-6:
		return 0
	d /= length
	n = 0
	origin = a.copy()
	left = length
	for _i in range(8):
		hit, _normal, _face, dist = tree.ray_cast(origin, d, left)
		if hit is None:
			break
		n += 1
		origin = hit + d * 1e-5
		left -= dist + 1e-5
		if left <= 0.0:
			break
	return n


def _anchor(arm, bone, co):
	"""The closest point to co on the bone's posed segment: a point inside
	the body that a covered vertex sees without any layer in between."""
	pb = arm.pose.bones[bone]
	h = arm.matrix_world @ pb.head
	t = arm.matrix_world @ pb.tail
	ax = t - h
	k = max(0.0, min(1.0, (co - h).dot(ax) / max(ax.length_squared, 1e-9)))
	return h + ax * k


def _setup():
	"""Rest-pose facts each sample is compared against."""
	arm = bpy.data.objects[ARMATURE]
	saved = arm.data.pose_position
	arm.data.pose_position = 'REST'
	bpy.context.view_layer.update()
	dg = bpy.context.evaluated_depsgraph_get()
	rest = {}
	for name in MESHES:
		ob = bpy.data.objects.get(name)
		if ob is None:
			continue
		verts, polys, _ = _evaluated(ob, dg)
		rest[name] = {"areas": [_area(verts, p) for p in polys], "open": _boundary_faces(polys)}
	tests = []
	for inner, outer, slots, z0, z1, skip in PAIRS:
		ob = bpy.data.objects.get(inner)
		if ob is None or bpy.data.objects.get(outer) is None:
			continue
		verts, polys, face_slots = _evaluated(ob, dg)
		wanted = None if slots is None else {SLOTS[s] for s in slots}
		group_names = {g.index: g.name for g in ob.vertex_groups}

		def main_bone(v):
			gs = ob.data.vertices[v].groups
			return group_names[max(gs, key=lambda g: g.weight).group] if len(gs) else ""

		chosen = set()
		for p, sl in zip(polys, face_slots):
			if wanted is None or sl in wanted:
				chosen.update(v for v in p if z0 <= verts[v].z <= z1 and main_bone(v) not in skip)
		# Only what's actually covered at rest can poke through later: a
		# hand that swings past the shorts was never under them. Anything
		# already outside at rest is a rest-pose defect, reported apart.
		overts, opolys, _ = _evaluated(bpy.data.objects[outer], dg)
		find = _nearest_fn(inner, outer, overts, opolys)
		trees = _outer_trees(inner, outer, overts, opolys)
		covered, rest_poke = [], []
		for v in sorted(chosen):
			hit, normal, face = find(v, verts[v])
			if hit is None or face in rest[outer]["open"]:
				continue
			d = (verts[v] - hit).dot(normal)
			if d > POKE_TOLERANCE:
				rest_poke.append((v, round(d * 1000), tuple(round(x, 3) for x in verts[v])))
			elif d < 0.0:
				bone = main_bone(v)
				tree = trees.get(_side(ob, v) if len(trees) > 1 else "")
				# Covered means the bone sees the vertex with nothing in
				# between: that's what sample() checks stays true.
				if tree is not None and _crossings(tree, _anchor(arm, bone, verts[v]), verts[v]) == 0:
					covered.append((v, bone))
		tests.append((inner, outer, covered))
		if rest_poke:
			rest.setdefault("_rest_poke", {})[inner + ">" + outer] = rest_poke[:8] + (["..."] if len(rest_poke) > 8 else [])
	rest["_cross_rest"] = sample(rest, [])["_cross_sets"]
	arm.data.pose_position = saved
	bpy.context.view_layer.update()
	return rest, tests


def sample(rest, tests):
	dg = bpy.context.evaluated_depsgraph_get()
	cur = {}
	for name in rest:
		if not name.startswith("_"):
			cur[name] = _evaluated(bpy.data.objects[name], dg)
	out = {"poke": {}, "crush": {}, "stretch": {}, "cross": {}}
	arm = bpy.data.objects[ARMATURE]
	for inner, outer, chosen in tests:
		overts, opolys, _ = cur[outer]
		trees = _outer_trees(inner, outer, overts, opolys)
		iob = bpy.data.objects[inner]
		ivs = cur[inner][0]
		n = 0
		deepest = 0.0
		for v, bone in chosen:
			# Out if the line from the vertex's own bone to it now passes
			# through the outer layer: unlike the nearest face's normal,
			# that holds for a vertex deep inside a folded crease too.
			tree = trees.get(_side(iob, v) if len(trees) > 1 else "")
			if tree is None:
				continue
			co = ivs[v]
			if _crossings(tree, _anchor(arm, bone, co), co) % 2 == 0:
				continue
			hit, _normal, _face, d = tree.find_nearest(co)
			if hit is not None and d > POKE_TOLERANCE:
				n += 1
				deepest = max(deepest, d)
		if n:
			# Reported as count + depth in mm, so a ranking still sorts by
			# count but the depth says whether anyone would see it.
			out["poke"][inner + ">" + outer] = n + min(deepest, 0.999)
	for inner, outer, bones in CROSSINGS:
		if inner not in cur or outer not in cur:
			continue
		ob = bpy.data.objects[inner]
		names = {g.index: g.name for g in ob.vertex_groups}
		iv, ip, _ = cur[inner]
		ov, op, _ = cur[outer]
		wanted = set()
		for i, p in enumerate(ip):
			gs = ob.data.vertices[p[0]].groups
			if len(gs) and names[max(gs, key=lambda g: g.weight).group] in bones:
				wanted.add(i)
		pairs = BVHTree.FromPolygons(iv, ip).overlap(BVHTree.FromPolygons(ov, op))
		key = inner + "x" + outer
		crossing = {a for a, _ in pairs if a in wanted}
		# Only crossings that aren't there at rest: the sock goes in
		# through the boot's closed top on purpose.
		n = len(crossing - rest.get("_cross_rest", {}).get(key, set()))
		if n:
			out["cross"][key] = n
		out.setdefault("_cross_sets", {})[key] = crossing
	for name, (verts, polys, _) in cur.items():
		areas = rest[name]["areas"]
		c = s = 0
		for i, p in enumerate(polys):
			if areas[i] < 1e-7:
				continue
			r = _area(verts, p) / areas[i]
			c += r < CRUSH
			s += r > STRETCH
		if c:
			out["crush"][name] = c
		if s:
			out["stretch"][name] = s
	return out


def _pose_ragdoll(arm, moves):
	"""Turn each named joint from the rest pose, about its own pivot, in
	the armature's rest frame; children ride their parents."""
	bones = arm.data.bones
	delta = {}
	for name, kind, toward, deg in moves:
		b = bones[name]
		head = b.head_local
		d = (b.tail_local - head).normalized()
		if kind == "twist":
			axis = d
		else:
			axis = d.cross(toward)
			if axis.length < 1e-6:
				continue
			axis.normalize()
		rot = Matrix.Rotation(math.radians(deg), 4, axis)
		m = Matrix.Translation(head) @ rot @ Matrix.Translation(-head)
		delta[name] = m @ delta.get(name, Matrix.Identity(4))
	# Rest-to-pose displacement of each bone, parents first.
	g = {}

	def displacement(b):
		if b.name in g:
			return g[b.name]
		parent = displacement(b.parent) if b.parent else Matrix.Identity(4)
		g[b.name] = parent @ delta.get(b.name, Matrix.Identity(4))
		return g[b.name]

	order = sorted(bones, key=lambda b: len(b.parent_recursive))
	for b in order:
		pb = arm.pose.bones[b.name]
		pb.matrix = displacement(b) @ b.matrix_local
		bpy.context.view_layer.update()


def check(actions=None, step=STEP, ragdoll=True):
	arm = bpy.data.objects[ARMATURE]
	ad = arm.animation_data
	saved_action, saved_slot, saved_nla = ad.action, ad.action_slot, ad.use_nla
	saved_frame = bpy.context.scene.frame_current
	saved_pose = arm.data.pose_position
	arm.data.pose_position = 'POSE'
	rest, tests = _setup()
	ad.use_nla = False
	report = {"_rest_poke": rest.get("_rest_poke", {}),
		"_covered": {i + ">" + o: len(c) for i, o, c in tests}}
	muted = []
	try:
		for act in sorted(bpy.data.actions, key=lambda a: a.name):
			if actions and act.name not in actions:
				continue
			if act.name.endswith("_backup"):
				continue
			ad.action = act
			if act.slots:
				ad.action_slot = act.slots[0]
			f0, f1 = (int(x) for x in act.frame_range)
			worst = {}
			for fr in list(range(f0, f1 + 1, step)) + [f1]:
				bpy.context.scene.frame_set(fr)
				res = sample(rest, tests)
				res.pop("_cross_sets", None)
				for kind, d in res.items():
					for k, n in d.items():
						key = kind + ":" + k
						if n > worst.get(key, (0, 0))[0]:
							worst[key] = (n, fr)
			# poke entries: "<count> verts, <deepest> mm @ frame"
			report[act.name] = {k: ("%d, %dmm @%d" % (int(n), round((n - int(n)) * 1000), fr)
				if k.startswith("poke") else "%d @%d" % (n, fr)) for k, (n, fr) in worst.items()}
		if ragdoll:
			ad.action = None
			for pb in arm.pose.bones:
				for c in pb.constraints:
					if not c.mute:
						c.mute = True
						muted.append(c)
			for name, moves in RAGDOLL_POSES.items():
				if actions and name not in actions:
					continue
				for pb in arm.pose.bones:
					pb.matrix_basis = Matrix.Identity(4)
				_pose_ragdoll(arm, moves)
				res = sample(rest, tests)
				res.pop("_cross_sets", None)
				report[name] = {kind + ":" + k: ("%d, %dmm" % (int(n), round((n - int(n)) * 1000))
					if kind == "poke" else "%d" % n) for kind, d in res.items() for k, n in d.items()}
	finally:
		for c in muted:
			c.mute = False
		for pb in arm.pose.bones:
			pb.matrix_basis = Matrix.Identity(4)
		ad.action = saved_action
		if saved_slot is not None:
			ad.action_slot = saved_slot
		ad.use_nla = saved_nla
		arm.data.pose_position = saved_pose
		bpy.context.scene.frame_set(saved_frame)
	return report


if __name__ == "__main__":
	only = None
	for arg in sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []:
		if arg.startswith("--only="):
			only = set(arg[len("--only="):].split(","))
	for name, worst in check(only).items():
		print("%-20s %s" % (name, worst if worst else "clean"))
