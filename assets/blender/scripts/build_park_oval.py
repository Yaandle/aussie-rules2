"""Builds assets/blender/park_oval.blend, "Field 1" (the park oval in the
first reference image), and exports its three glbs to assets/imported/:

  park_ground.glb   bright outer grass, striped turf out to the fence,
                    darker tufts and the dirt paths
  park_fence.glb    a continuous post-and-rail fence (Field 2's has gaps)
  park_layout.glb   scoreboard, benches, picnic tables, trees, bushes and
                    agaves, each a linked copy of a park_props.blend mesh.
                    ParkEnvironment batches same-mesh copies into MultiMeshes.

    blender -b --python assets/blender/scripts/build_park_oval.py

Run build_park_props.py first. Re-running rebuilds the whole file from the
rules below, so move things by editing the rules (or stop re-running and
hand-place from then on). Tree and bush placement is seeded, so a re-run
gives the same park.

Layout, read off the reference (Blender +Y = north = top of the image):
scoreboard north of centre, benches along the north-east and east fence
and a short row along the south, picnic tables east, a path sweeping round
the north-west, one heading east from the fence and one running north-south
down the east side. Oaks and fruit trees on the west, gums on the east,
flowering bushes in clumps everywhere.
"""

import math
import os
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import field_kit as kit  # noqa: E402

PARK_BLEND = os.path.join(kit.BLENDER_DIR, "park_oval.blend")
TREES_BLEND = os.path.join(kit.BLENDER_DIR, "newbasictrees.blend")

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.wm.save_as_mainfile(filepath=PARK_BLEND)  # so library links save relative

# ── Ground ───────────────────────────────────────────────────────────

GRASS = kit.material("ParkGrass", "#7AA83E")
TUFT_DARK = kit.material("ParkTuftDark", "#689A35")
TUFT_LIGHT = kit.material("ParkTuftLight", "#88B548")
TURF_LIGHT = kit.material("ParkTurfLight", "#6FA238")
TURF_DARK = kit.material("ParkTurfDark", "#5A8C2F")
PATH = kit.material("ParkPath", "#C99F5E")
PATH_EDGE = kit.material("ParkPathEdge", "#9E7942")
FENCE_POST = kit.material("ParkFencePost", "#6B4426")
FENCE_RAIL = kit.material("ParkFenceRail", "#8C5A33")

# Hand-placed path spines (metres, Blender XY), smoothed.
PATHS = [
    # North-west: in from the west edge, curving up past the oaks.
    [(-260, 18), (-190, 22), (-140, 30), (-112, 48), (-94, 76), (-72, 102), (-52, 140), (-40, 200), (-34, 260)],
    # East: from the fence straight out.
    [(93, -1), (130, -2), (180, 2), (260, -4)],
    # East side, north-south, crossing the east path.
    [(124, 40), (121, 10), (117, -30), (108, -70), (106, -100), (116, -150), (126, -220)],
]
PATH_WIDTH = 5.0
PATH_SPINES = [kit.catmull_rom(p) for p in PATHS]

ground_col = kit.collection("Ground")

g = kit.MeshBuilder()
g.ngon([(-500, -500), (500, -500), (500, 500), (-500, 500)], -0.03, GRASS)
grass = bpy.data.objects.new("Grass_Outer", g.build("Park_GrassOuter"))
ground_col.objects.link(grass)

# Striped turf right out to the fence, like the reference: the boundary
# line is painted on the stripes, not on a separate apron colour. 9 m
# bands, matching turf.gdshader's stripe_width; each band is the ellipse
# clipped between two x lines, which is convex, so one n-gon per band.
TURF_A = kit.FENCE_A + 0.4
TURF_B = kit.FENCE_B + 0.4
t = kit.MeshBuilder()
band = 9.0
edges = [-TURF_A]
k = math.floor(-TURF_A / band - 0.5) + 1
while (k - 0.5) * band < TURF_A:
    e = (k - 0.5) * band
    if e > -TURF_A:
        edges.append(e)
    k += 1
edges.append(TURF_A)
for i, (xa, xb) in enumerate(zip(edges, edges[1:])):
    xs = [xa + (xb - xa) * s / 6.0 for s in range(7)]
    top = [(x, TURF_B * math.sqrt(max(0.0, 1.0 - (x / TURF_A) ** 2))) for x in xs]
    bottom = [(x, -y) for x, y in reversed(top)]
    pts = top + bottom
    # Drop duplicate points where the band touches the ellipse tip.
    clean = []
    for p in pts:
        if not clean or (abs(p[0] - clean[-1][0]) > 1e-4 or abs(p[1] - clean[-1][1]) > 1e-4):
            clean.append(p)
    if len(clean) >= 3:
        t.ngon(clean, 0.0, TURF_LIGHT if i % 2 == 0 else TURF_DARK)
turf = bpy.data.objects.new("Turf_Oval", t.build("Park_Turf"))
ground_col.objects.link(turf)

# Paths: a darker edge ribbon under a lighter one, the pixel-art outline.
p = kit.MeshBuilder()
for spine in PATH_SPINES:
    p.ribbon(spine, PATH_WIDTH + 1.0, -0.016, PATH_EDGE)
    p.ribbon(spine, PATH_WIDTH, -0.012, PATH)
paths = bpy.data.objects.new("Paths", p.build("Park_Paths"))
ground_col.objects.link(paths)

# Tufts: irregular darker/lighter patches across the lawn outside the
# fence, so the grass isn't one flat fill from the high camera.
tufts = kit.MeshBuilder()
scatter = kit.Scatter(7, PATH_SPINES)
placed = 0
while placed < 320:
    r = scatter.rng.uniform(2.0, 140.0)
    a = scatter.rng.uniform(0.0, math.tau)
    c = kit.ellipse_point(r, a)
    size = scatter.rng.uniform(1.0, 3.6)
    if not scatter.clear_of_paths(c, PATH_WIDTH * 0.5 + size + 0.5):
        continue
    corners = []
    for s in range(6):
        ang = math.tau * s / 6 + scatter.rng.uniform(-0.3, 0.3)
        rad = size * scatter.rng.uniform(0.55, 1.0)
        corners.append((c.x + math.cos(ang) * rad, c.y + math.sin(ang) * rad))
    tufts.ngon(corners, -0.02, TUFT_DARK if scatter.rng.random() < 0.65 else TUFT_LIGHT)
    placed += 1
patches = bpy.data.objects.new("Grass_Patches", tufts.build("Park_Tufts"))
ground_col.objects.link(patches)

# ── Fence ────────────────────────────────────────────────────────────
# Same profile as field.blend's Fence (rails 0.45–0.57 and 0.90–1.02 m,
# posts to 1.25 m) but continuous, in the warmer brown of the reference.

fence_col = kit.collection("Fence")
f = kit.MeshBuilder()
SPACING = 3.0
# Walk the ellipse in small steps and drop a post every SPACING metres.
posts = []
acc = 0.0
prev = kit.ellipse_point(0.0, 0.0)
posts.append(prev)
steps = 4000
for s in range(1, steps + 1):
    pt = kit.ellipse_point(0.0, math.tau * s / steps)
    acc += (pt - prev).length
    prev = pt
    if acc >= SPACING and s < steps:
        posts.append(pt)
        acc = 0.0
for i, a in enumerate(posts):
    b_ = posts[(i + 1) % len(posts)]
    f.box((a.x, a.y, 0.625), (0.14, 0.14, 1.25), FENCE_POST)
    mid = (a + b_) * 0.5
    length = (b_ - a).length
    yaw = math.atan2(b_.y - a.y, b_.x - a.x)
    for z in (0.51, 0.96):
        f.box((mid.x, mid.y, z), (length + 0.06, 0.07, 0.12), FENCE_RAIL, rot=(0, 0, yaw))
fence = bpy.data.objects.new("Fence", f.build("Park_Fence"))
fence_col.objects.link(fence)

# ── Layout ───────────────────────────────────────────────────────────

props = kit.link_meshes(kit.PROPS_BLEND, [
    "Prop_OakA", "Prop_OakB", "Prop_FruitTree", "Prop_BushGreen", "Prop_BushLavender",
    "Prop_BushYellow", "Prop_BushWhite", "Prop_BushBerry", "Prop_Agave", "Prop_ParkBench",
    "Prop_PicnicTable", "Prop_Scoreboard",
])
# The gum is the eucalyptus Field 2 already uses (trunk and canopy are two
# meshes in newbasictrees.blend, so each gum is two linked copies).
with bpy.data.libraries.load(TREES_BLEND, link=True, relative=True) as (src, dst):
    dst.objects = ["Eucalyptus_Trunk", "Eucalyptus_Canopy"]
gum_meshes = [o.data for o in dst.objects]

layout_col = kit.collection("Layout")
sc = kit.Scatter(2026, PATH_SPINES)

# Scoreboard north of centre, facing the ground, agaves either side.
SCOREBOARD = (0.0, 85.0)
kit.place(layout_col, "Scoreboard", props["Prop_Scoreboard"], SCOREBOARD)
sc.reserve(SCOREBOARD, 6.0)
for n, pos in enumerate([(-7.0, 83.6), (7.4, 84.0), (128.0, 46.0), (-20.0, 84.0)]):
    kit.place(layout_col, "Agave_%02d" % n, props["Prop_Agave"], pos, sc.rng.uniform(0, math.tau),
              sc.rng.uniform(0.9, 1.3))
    sc.reserve(pos, 1.4)

# Benches: a run along the north-east and east fence, gap where the east
# path meets it, and four along the south.
bench_angles = [a for a in range(63, -18, -4) if abs(a) > 5] + [-79, -86, -93, -100]
for n, deg in enumerate(bench_angles):
    off = 5.0 if deg < -60 else 4.0
    pos = kit.ellipse_point(off, math.radians(deg))
    kit.place(layout_col, "Bench_%02d" % n, props["Prop_ParkBench"], pos, kit.face_centre_rot(pos))
    sc.reserve(pos, 1.6)

# Picnic tables between the bench run and the north-south path.
for n, (pos, yaw) in enumerate([((99.0, 50.0), 0.5), ((107.0, 43.0), 0.35),
                                ((102.0, 26.0), 1.4), ((107.5, 17.0), 1.55)]):
    kit.place(layout_col, "PicnicTable_%02d" % n, props["Prop_PicnicTable"], pos, yaw)
    sc.reserve(pos, 2.4)

# Trees by sector (angles in degrees round the fence, 0 = east, 90 = north).
TREE_SECTORS = [
    ((-60, 75), [("gum", 0.65), ("oak", 0.25), ("fruit", 0.10)]),
    ((75, 130), [("oak", 0.5), ("fruit", 0.25), ("gum", 0.25)]),
    ((130, 250), [("oak", 0.7), ("fruit", 0.3)]),
    ((250, 300), [("oak", 0.5), ("fruit", 0.3), ("gum", 0.2)]),
]
TREE_RADIUS = {"oak": 4.6, "fruit": 2.6, "gum": 3.6}


def sector_pick(angle, sectors):
    for (lo, hi), weights in sectors:
        if kit.in_sector(angle, lo, hi):
            return kit.pick(sc.rng, weights)
    return kit.pick(sc.rng, sectors[0][1])


trees = []
oak_variant = 0


def plant_tree(kind, pos):
    global oak_variant
    yaw = sc.rng.uniform(0, math.tau)
    if kind == "gum":
        s = sc.rng.uniform(0.7, 0.95)
        for me in gum_meshes:
            kit.place(layout_col, "Gum_%03d_%s" % (len(trees), me.name.split("_")[-1]), me, pos, yaw, s)
    elif kind == "oak":
        oak_variant += 1
        mesh = props["Prop_OakA" if oak_variant % 2 else "Prop_OakB"]
        kit.place(layout_col, "Oak_%03d" % len(trees), mesh, pos, yaw, sc.rng.uniform(1.0, 1.45))
    else:
        kit.place(layout_col, "Fruit_%03d" % len(trees), props["Prop_FruitTree"], pos, yaw,
                  sc.rng.uniform(0.9, 1.15))
    trees.append((kind, pos))


# Inner band close to the fence (sparser in front of the benches), then a
# loose outer ring so the low broadcast camera still sees a treeline.
for count, lo, hi, tries in ((115, 8.0, 45.0, 12000), (90, 45.0, 150.0, 9000)):
    placed = 0
    for _ in range(tries):
        if placed >= count:
            break
        off = sc.rng.uniform(lo, hi)
        ang = sc.rng.uniform(0.0, math.tau)
        pos = kit.ellipse_point(off, ang)
        kind = sector_pick(math.degrees(ang), TREE_SECTORS)
        if sc.try_place(pos, TREE_RADIUS[kind], PATH_WIDTH * 0.5 + 3.0):
            plant_tree(kind, pos)
            placed += 1

# Bushes in single-species clumps of 3–5.
BUSH_SECTORS = [
    ((-60, 75), [("Berry", 0.3), ("Green", 0.3), ("Yellow", 0.2), ("Lavender", 0.2)]),
    ((75, 130), [("Lavender", 0.3), ("Yellow", 0.3), ("Green", 0.2), ("White", 0.2)]),
    ((130, 250), [("Lavender", 0.35), ("White", 0.25), ("Yellow", 0.2), ("Green", 0.2)]),
    ((250, 300), [("Yellow", 0.35), ("Lavender", 0.25), ("Berry", 0.2), ("White", 0.2)]),
]
bushes = 0
clumps = 0
for _ in range(4000):
    if clumps >= 80:
        break
    ang = sc.rng.uniform(0.0, math.tau)
    centre = kit.ellipse_point(sc.rng.uniform(5.0, 34.0), ang)
    if not sc.free(centre, 1.5, PATH_WIDTH * 0.5 + 2.0):
        continue
    species = sector_pick(math.degrees(ang), BUSH_SECTORS)
    mesh = props["Prop_Bush" + species]
    clumps += 1
    for _ in range(sc.rng.randint(3, 5)):
        for _ in range(20):
            a = sc.rng.uniform(0, math.tau)
            d = sc.rng.uniform(0.0, 4.2)
            pos = (centre.x + math.cos(a) * d, centre.y + math.sin(a) * d)
            size = sc.rng.uniform(1.1, 1.7)
            if kit.outside_offset(pos) > 3.0 and sc.try_place(pos, 0.95 * size, PATH_WIDTH * 0.5 + 1.2):
                kit.place(layout_col, "Bush%s_%03d" % (species, bushes), mesh, pos,
                          sc.rng.uniform(0, math.tau), size)
                bushes += 1
                break

print("layout: %d trees, %d bushes in %d clumps, %d benches" % (len(trees), bushes, clumps, len(bench_angles)))

bpy.ops.wm.save_as_mainfile(filepath=PARK_BLEND)
kit.export_glb(list(ground_col.objects), "park_ground.glb")
kit.export_glb(list(fence_col.objects), "park_fence.glb")
kit.export_glb(list(layout_col.objects), "park_layout.glb")
