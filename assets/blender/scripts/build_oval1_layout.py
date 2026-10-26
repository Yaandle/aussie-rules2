"""Adds a Layout collection to assets/blender/field.blend ("Oval 1", which
the game calls Field 2: the bush oval in the second reference image) and
exports it to assets/imported/oval1_layout.glb.

    blender -b assets/blender/field.blend --python assets/blender/scripts/build_oval1_layout.py

Run build_park_props.py first. This script owns the Layout collection
only: it empties and rebuilds it every run and doesn't touch Ground, Fence,
Goals, Bench, Trees or _Reference. Put hand-placed things in those.

What it adds, from the reference (Blender +Y = north = top of the image):
dirt paths out through the fence's two gaps (west end, south side), a
scoreboard north of centre, five benches along the north-east fence and
one on the east, a picnic table south-east, a ring of dark bushes just
outside the fence, and round oaks among the gums on the west. The gum ring
itself stays in scenes/field/oval1_environment.tscn. Its positions are read
from there so nothing here lands on a trunk.
"""

import math
import os
import re
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import field_kit as kit  # noqa: E402

ENV_TSCN = os.path.join(kit.REPO_DIR, "scenes", "field", "oval1_environment.tscn")

if not bpy.data.filepath.endswith("field.blend"):
    raise SystemExit("open assets/blender/field.blend first (see the docstring)")

# ── The existing tree ring, Godot (x, y, z) → Blender (x, -z) ───────────
ring = []
with open(ENV_TSCN, encoding="utf-8") as f:
    for m in re.finditer(r"Transform3D\(([^)]*)\)", f.read()):
        v = [float(n) for n in m.group(1).split(",")]
        ring.append((v[9], -v[11]))
print("existing ring trees:", len(ring))

PATH = kit.material("Oval1Path", "#BC9E60")
PATH_EDGE = kit.material("Oval1PathEdge", "#957843")

# Through the fence gaps: west at Blender y -9.3..-17.2, south at x ±4.8.
PATHS = [
    [(-90.0, -13.2), (-112, -13.6), (-140, -10.5), (-175, -16.0), (-230, -12.0), (-320, -18.0)],
    [(0.0, -75.5), (0.6, -100), (-2.0, -130), (2.0, -170), (-1.0, -240), (0.0, -320)],
]
PATH_WIDTH = 6.0
PATH_SPINES = [kit.catmull_rom(p) for p in PATHS]

props = kit.link_meshes(kit.PROPS_BLEND, [
    "Prop_OakA", "Prop_OakB", "Prop_BushDark", "Prop_BushGreen", "Prop_BushBerry",
    "Prop_ParkBench", "Prop_PicnicTable", "Prop_Scoreboard",
])

layout = kit.collection("Layout")
sc = kit.Scatter(4242, PATH_SPINES)
for p in ring:
    sc.reserve(p, 1.8)

# Paths: the darker edge ribbon under the path, as on Field 1.
b = kit.MeshBuilder()
for spine in PATH_SPINES:
    b.ribbon(spine, PATH_WIDTH + 1.0, -0.016, PATH_EDGE)
    b.ribbon(spine, PATH_WIDTH, -0.012, PATH)
paths = bpy.data.objects.new("Paths", b.build("Oval1_Paths"))
layout.objects.link(paths)

SCOREBOARD = (0.0, 82.0)
kit.place(layout, "Scoreboard", props["Prop_Scoreboard"], SCOREBOARD)
sc.reserve(SCOREBOARD, 5.0)

for n, deg in enumerate([58, 51, 44, 37, 30, -24]):
    pos = kit.ellipse_point(3.5, math.radians(deg))
    kit.place(layout, "Bench_%02d" % n, props["Prop_ParkBench"], pos, kit.face_centre_rot(pos))
    sc.reserve(pos, 1.6)

TABLE = (79.0, -61.0)
kit.place(layout, "PicnicTable", props["Prop_PicnicTable"], TABLE, 0.35)
sc.reserve(TABLE, 2.4)

# Round oaks on the west half, between the gums.
oaks = 0
for _ in range(5000):
    if oaks >= 22:
        break
    ang = math.radians(sc.rng.uniform(125.0, 255.0))
    pos = kit.ellipse_point(sc.rng.uniform(12.0, 58.0), ang)
    if any((kit.Vector(pos) - kit.Vector(t)).length < 7.0 for t in ring):
        continue
    if sc.try_place(pos, 4.2, PATH_WIDTH * 0.5 + 3.0):
        mesh = props["Prop_OakA" if oaks % 2 else "Prop_OakB"]
        kit.place(layout, "Oak_%02d" % oaks, mesh, pos, sc.rng.uniform(0, math.tau), sc.rng.uniform(1.0, 1.4))
        oaks += 1

# A dense ring of dark bushes hugging the outside of the fence.
bushes = 0
clumps = 0
for _ in range(6000):
    if clumps >= 95:
        break
    ang = sc.rng.uniform(0.0, math.tau)
    centre = kit.ellipse_point(sc.rng.uniform(3.5, 18.0), ang)
    if not sc.free(centre, 1.2, PATH_WIDTH * 0.5 + 2.5):
        continue
    species = kit.pick(sc.rng, [("Dark", 0.55), ("Green", 0.3), ("Berry", 0.15)])
    clumps += 1
    for _ in range(sc.rng.randint(4, 7)):
        for _ in range(20):
            a = sc.rng.uniform(0, math.tau)
            d = sc.rng.uniform(0.0, 4.6)
            pos = (centre.x + math.cos(a) * d, centre.y + math.sin(a) * d)
            size = sc.rng.uniform(1.2, 2.0)
            if kit.outside_offset(pos) > 1.2 + size and sc.try_place(pos, 0.9 * size, PATH_WIDTH * 0.5 + 1.2):
                kit.place(layout, "Bush%s_%03d" % (species, bushes), props["Prop_Bush" + species], pos,
                          sc.rng.uniform(0, math.tau), size)
                bushes += 1
                break

print("layout: %d oaks, %d bushes in %d clumps" % (oaks, bushes, clumps))

bpy.ops.wm.save_mainfile()
kit.export_glb(list(layout.objects), "oval1_layout.glb")
