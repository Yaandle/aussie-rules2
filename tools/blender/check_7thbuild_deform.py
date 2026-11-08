"""Deformation check for a skinned player mesh on the 6thbuild Armature.

Plays every action on the Armature, samples it, and counts what a viewer
would call a skinning bug:

* poke   — a vertex of an inner layer that ends up outside the layer
           over it: skin through the guernsey or shorts, the guernsey
           out through the shorts, a sock out through a boot. Measured
           against the outer layer's nearest face, skipping faces on an
           open edge (a hem or an armhole, which the inner layer is
           SUPPOSED to come out of).
* crush  — faces whose area falls under CRUSH of their rest area (a
           joint collapsing), and
* stretch — faces over STRETCH of it.

Run with the .blend open (Scripting tab, the Blender MCP, or headless):
    blender assets/blender/7thbuild.blend --background --python tools/blender/check_7thbuild_deform.py

It reads PAIRS / MESHES below, so a replacement mesh (a scan, say) is
checked the same way once its objects are named into them. Nothing is
saved; the active action is put back afterwards.
"""

import bpy
from mathutils.bvhtree import BVHTree

ARMATURE = "Armature"
MESHES = ["B7_Body", "B7_Guernsey", "B7_Shorts", "B7_Boots", "B7_Hair"]

## (inner object, outer object, inner material or None, min z, max z, bones
## to skip): only the inner object's vertices in that material and height
## band at rest, and not mostly on a skipped bone, are tested, so each pair
## asks one question. The deltoids are skipped against the guernsey because
## they come out over its shoulder line by design (a sleeveless guernsey).
PAIRS = [
	("B7_Body", "B7_Guernsey", "Skin_Mat", 1.40, 1.86, ("upperarm.l", "upperarm.r")),
	("B7_Body", "B7_Shorts", "Skin_Mat", 0.88, 1.40, ()),
	("B7_Guernsey", "B7_Shorts", None, 1.0, 1.36, ()),
	("B7_Body", "B7_Boots", "Socks_Mat", -1.0, 0.13, ()),
]
## (inner object, outer object, inner bones): inner faces mostly on those
## bones that cross an outer face. Catches what the vertex test can't: a
## face of the thigh cutting through the shorts with all its corners still
## inside (a concave crease). Reported as "cross".
CROSSINGS = [
	("B7_Body", "B7_Shorts", ("upperleg.l", "upperleg.r")),
	("B7_Body", "B7_Boots", ("lowerleg.l", "lowerleg.r")),
]
POKE_TOLERANCE = 0.004   # m outside the outer surface before it counts
POKE_REACH = 0.05        # only look this far for the outer surface
CRUSH = 0.15
STRETCH = 3.0
STEP = 2                 # sample every STEP frames


def _evaluated(ob, dg):
	ev = ob.evaluated_get(dg)
	me = ev.to_mesh()
	verts = [ob.matrix_world @ v.co for v in me.vertices]
	polys = [tuple(p.vertices) for p in me.polygons]
	mats = [p.material_index for p in me.polygons]
	ev.to_mesh_clear()
	return verts, polys, mats


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
		verts, polys, mats = _evaluated(ob, dg)
		rest[name] = {"areas": [_area(verts, p) for p in polys], "open": _boundary_faces(polys)}
	tests = []
	for inner, outer, mat, z0, z1, skip in PAIRS:
		ob = bpy.data.objects.get(inner)
		if ob is None or bpy.data.objects.get(outer) is None:
			continue
		verts, polys, mats = _evaluated(ob, dg)
		names = [m.name if m else "" for m in ob.data.materials]
		group_names = {g.index: g.name for g in ob.vertex_groups}

		def main_bone(v):
			gs = ob.data.vertices[v].groups
			return group_names[max(gs, key=lambda g: g.weight).group] if len(gs) else ""

		chosen = set()
		for p, m in zip(polys, mats):
			if mat is None or names[m] == mat:
				chosen.update(v for v in p if z0 <= verts[v].z <= z1 and main_bone(v) not in skip)
		# Only what's actually covered at rest can poke through later: a
		# hand that swings past the shorts was never under them. Anything
		# already outside at rest is a rest-pose defect, reported apart.
		overts, opolys, _ = _evaluated(bpy.data.objects[outer], dg)
		tree = BVHTree.FromPolygons(overts, opolys)
		covered, rest_poke = [], 0
		for v in sorted(chosen):
			hit, normal, face, _ = tree.find_nearest(verts[v], POKE_REACH)
			if hit is None or face in rest[outer]["open"]:
				continue
			d = (verts[v] - hit).dot(normal)
			if d > POKE_TOLERANCE:
				rest_poke += 1
			elif d < 0.0:
				covered.append(v)
		tests.append((inner, outer, covered))
		if rest_poke:
			rest.setdefault("_rest_poke", {})[inner + ">" + outer] = rest_poke
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
	for inner, outer, chosen in tests:
		overts, opolys, _ = cur[outer]
		tree = BVHTree.FromPolygons(overts, opolys)
		ivs = cur[inner][0]
		n = 0
		deepest = 0.0
		for v in chosen:
			hit, normal, face, dist = tree.find_nearest(ivs[v], POKE_REACH)
			if hit is None or face in rest[outer]["open"]:
				continue
			d = (ivs[v] - hit).dot(normal)
			if d > POKE_TOLERANCE:
				n += 1
				deepest = max(deepest, d)
		if n:
			# Reported as count + depth in mm, so a ranking still sorts by
			# count but the depth says whether anyone would see it.
			out["poke"][inner + ">" + outer] = n + min(deepest, 0.999)
	out["cross"] = {}
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


def check(actions=None, step=STEP):
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
	finally:
		ad.action = saved_action
		if saved_slot is not None:
			ad.action_slot = saved_slot
		ad.use_nla = saved_nla
		arm.data.pose_position = saved_pose
		bpy.context.scene.frame_set(saved_frame)
	return report


if __name__ == "__main__":
	for name, worst in check().items():
		print("%-20s %s" % (name, worst if worst else "clean"))
