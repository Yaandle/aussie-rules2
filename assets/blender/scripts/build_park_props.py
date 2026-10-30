"""Builds assets/blender/park_props.blend: the low-poly prop library both
ovals' layouts link from (round oak, fruit tree, flowering bushes, agave,
bench, picnic table, scoreboard).

    blender -b --python assets/blender/scripts/build_park_props.py

Each prop is one mesh named Prop_* with its origin at its base and its
front facing -Y. The layouts link these meshes rather than copying them, so
re-running this (or hand-editing a Prop_* mesh in park_props.blend) changes
every placed copy on the next layout export. Rename a mesh and the layouts
lose it, so keep the names.

The sizes are real-world-ish, not the reference art's. A pixel-art bench is
a third of a goal square; here it's 2 m, because players stand next to it.
"""

import math
import os
import random
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import field_kit as kit  # noqa: E402

bpy.ops.wm.read_factory_settings(use_empty=True)

# ── Palette (sRGB, sampled from / matched by eye to the reference art) ──
BARK = kit.material("PropBark", "#6B4A2E")
LEAF_DARK = kit.material("PropLeafDark", "#3F6B2A")
LEAF_MID = kit.material("PropLeafMid", "#5A8A33")
LEAF_LIGHT = kit.material("PropLeafLight", "#7BA83F")
BUSH_DARK_A = kit.material("PropBushDarkA", "#2C5124")
BUSH_DARK_B = kit.material("PropBushDarkB", "#3B662B")
LAVENDER_A = kit.material("PropLavenderA", "#7465B0")
LAVENDER_B = kit.material("PropLavenderB", "#9384CF")
LAVENDER_FLOWER = kit.material("PropLavenderFlower", "#C2B4EE")
YELLOW_A = kit.material("PropYellowA", "#B98A26")
YELLOW_B = kit.material("PropYellowB", "#DDAE33")
YELLOW_FLOWER = kit.material("PropYellowFlower", "#F6D458")
WHITE_FLOWER = kit.material("PropWhiteFlower", "#F2F0E6")
RED_FRUIT = kit.material("PropRedFruit", "#C8352B")
AGAVE_A = kit.material("PropAgaveA", "#6E9E8A")
AGAVE_B = kit.material("PropAgaveB", "#57867A")
BENCH_WOOD = kit.material("PropBenchWood", "#A9682F")
BENCH_FRAME = kit.material("PropBenchFrame", "#3B3733")
TABLE_WOOD = kit.material("PropTableWood", "#9C6431")
TABLE_LEG = kit.material("PropTableLeg", "#74461F")
SCORE_FRAME = kit.material("PropScoreFrame", "#5C5C58")
SCORE_CAP = kit.material("PropScoreCap", "#3E3E3C")
SCORE_FACE = kit.material("PropScoreFace", "#1C1D1F")
SCORE_TEXT = kit.material("PropScoreText", "#ECEBE3")
SCORE_DIGIT = kit.material("PropScoreDigit", "#F2A33A", emission=0.6)


# ── Trees ────────────────────────────────────────────────────────────

def round_tree(name, seed):
    """Park oak: a stubby trunk under a cluster of faceted blobs, dark
    underneath and light on top, the three-tone shading pixel-art trees use."""
    rng = random.Random(seed)
    b = kit.MeshBuilder()
    b.cylinder((0, 0, 0), 4.8, 0.5, 0.3, BARK, segments=6)
    for side in (-1, 1):
        b.box((side * 0.55, 0.0, 4.0), (0.24, 0.24, 1.9), BARK, rot=(0.0, side * math.radians(38), 0.0))
    b.blob((0, 0, 6.9), 2.8, LEAF_MID, squash=(1, 1, 0.85), rng=rng)
    for k in range(6):
        a = math.radians(k * 60 + rng.uniform(-18, 18))
        d = rng.uniform(1.9, 2.6)
        z = rng.uniform(5.7, 7.5)
        mat = LEAF_DARK if z < 6.5 else LEAF_MID
        b.blob((math.cos(a) * d, math.sin(a) * d, z), rng.uniform(1.6, 2.2), mat, squash=(1, 1, 0.85), rng=rng)
    for k in range(3):
        a = math.radians(k * 120 + rng.uniform(0, 60))
        b.blob((math.cos(a) * 1.1, math.sin(a) * 1.1, 8.6), rng.uniform(1.1, 1.4), LEAF_LIGHT,
               squash=(1, 1, 0.8), rng=rng)
    return b.build(name)


def fruit_tree(name, seed):
    """Small apple tree: round canopy studded with red fruit cubes."""
    rng = random.Random(seed)
    b = kit.MeshBuilder()
    b.cylinder((0, 0, 0), 2.6, 0.3, 0.2, BARK, segments=6)
    blobs = [((0, 0, 3.9), 1.7, LEAF_MID)]
    for k in range(4):
        a = math.radians(k * 90 + rng.uniform(-20, 20))
        blobs.append(((math.cos(a) * 1.25, math.sin(a) * 1.25, rng.uniform(3.3, 3.9)),
                      rng.uniform(1.1, 1.35), LEAF_DARK))
    blobs.append(((0.3, -0.2, 5.0), 1.0, LEAF_LIGHT))
    for centre, r, mat in blobs:
        b.blob(centre, r, mat, squash=(1, 1, 0.9), rng=rng)
    _studs(b, rng, blobs, 16, RED_FRUIT, 0.26, min_up=-0.3)
    return b.build(name)


def _studs(b, rng, blobs, count, mat, size, min_up=0.15):
    """Single-colour cubes on blob surfaces: the 'pixels' (flowers, fruit,
    berries) that make a green blob read as a particular plant."""
    for _ in range(count):
        centre, r, _mat = rng.choice(blobs)
        while True:
            d = kit.Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-1, 1)))
            if 0.2 < d.length <= 1.0 and d.normalized().z >= min_up:
                break
        d.normalize()
        p = kit.Vector(centre) + d * r * 0.92
        s = size * rng.uniform(0.8, 1.2)
        b.box(p, (s, s, s), mat, rot=(rng.uniform(0, 1), rng.uniform(0, 1), rng.uniform(0, 3)))


# ── Bushes ───────────────────────────────────────────────────────────

def bush(name, seed, low, high, flower=None, flowers=0):
    rng = random.Random(seed)
    b = kit.MeshBuilder()
    blobs = [((0, 0, 0.62), 1.0, high)]
    for k in range(3):
        a = math.radians(k * 120 + rng.uniform(-25, 25))
        d = rng.uniform(0.65, 0.9)
        blobs.append(((math.cos(a) * d, math.sin(a) * d, 0.45), rng.uniform(0.62, 0.8), low))
    for centre, r, mat in blobs:
        b.blob(centre, r, mat, squash=(1, 1, 0.82), rng=rng)
    if flower is not None:
        _studs(b, rng, blobs, flowers, flower, 0.2)
    return b.build(name)


def agave(name, seed):
    """Spiky succulent: blue-green pyramids fanning out of the ground."""
    rng = random.Random(seed)
    b = kit.MeshBuilder()
    for k in range(11):
        a = math.radians(k * (360 / 11) + rng.uniform(-10, 10))
        lean = math.radians(rng.uniform(30, 62))
        b.cylinder((0, 0, 0.05), rng.uniform(1.0, 1.4), 0.17, 0.0, AGAVE_A if k % 2 else AGAVE_B,
                   segments=3, tilt=(0.0, lean, a))
    b.cylinder((0, 0, 0.0), 0.9, 0.2, 0.0, AGAVE_A, segments=3)
    return b.build(name)


# ── Furniture ────────────────────────────────────────────────────────

def park_bench(name):
    """2 m slatted bench, seat facing -Y."""
    b = kit.MeshBuilder()
    for y in (-0.15, 0.0, 0.15):
        b.box((0, y, 0.45), (2.0, 0.13, 0.06), BENCH_WOOD)
    for z in (0.64, 0.82):
        b.box((0, 0.25 + (z - 0.64) * 0.2, z), (2.0, 0.05, 0.13), BENCH_WOOD, rot=(math.radians(-12), 0, 0))
    for x in (-0.85, 0.85):
        b.box((x, -0.17, 0.225), (0.07, 0.07, 0.45), BENCH_FRAME)
        b.box((x, 0.22, 0.46), (0.07, 0.07, 0.92), BENCH_FRAME, rot=(math.radians(-8), 0, 0))
        b.box((x, 0.02, 0.42), (0.07, 0.44, 0.05), BENCH_FRAME)
        b.box((x, 0.0, 0.66), (0.07, 0.46, 0.05), BENCH_FRAME)
    return b.build(name)


def picnic_table(name):
    b = kit.MeshBuilder()
    for y in (-0.3, -0.1, 0.1, 0.3):
        b.box((0, y, 0.76), (2.1, 0.18, 0.06), TABLE_WOOD)
    for y in (-0.72, 0.72):
        b.box((0, y, 0.45), (2.1, 0.28, 0.05), TABLE_WOOD)
    leg = math.atan2(0.78, 0.73)
    for x in (-0.8, 0.8):
        for side in (-1, 1):
            b.box((x, side * 0.39, 0.365), (0.08, 0.1, 1.07), TABLE_LEG, rot=(side * leg, 0, 0))
        b.box((x, 0.0, 0.4), (0.08, 1.7, 0.08), TABLE_LEG)
    return b.build(name)


def _seven_segment(b, centre_x, centre_z, y, width, height, thick, mat, segments="abcdef"):
    """A block digit; the default segments draw a 0."""
    hw, hh = width * 0.5, height * 0.5
    bars = {
        "a": ((0, hh), True), "d": ((0, -hh), True), "g": ((0, 0), True),
        "b": ((hw, hh * 0.5), False), "c": ((hw, -hh * 0.5), False),
        "e": ((-hw, -hh * 0.5), False), "f": ((-hw, hh * 0.5), False),
    }
    for s in segments:
        (dx, dz), horizontal = bars[s]
        size = (width, 0.04, thick) if horizontal else (thick, 0.04, hh + thick * 0.5)
        b.box((centre_x + dx, y, centre_z + dz), size, mat)


def scoreboard(name):
    """Suburban scoreboard on two legs, HOME/AWAY over block digits."""
    b = kit.MeshBuilder()
    for x in (-3.0, 3.0):
        b.box((x, 0.12, 3.5), (0.32, 0.32, 7.0), SCORE_CAP)
    b.box((0, 0, 5.25), (8.4, 0.36, 3.7), SCORE_FRAME)
    b.box((0, 0, 7.16), (8.7, 0.5, 0.14), SCORE_CAP)
    b.box((0, -0.19, 5.25), (8.0, 0.04, 3.3), SCORE_FACE)
    b.box((0, -0.215, 5.25), (0.09, 0.02, 3.0), SCORE_FRAME)
    b.box((0, -0.215, 5.72), (7.8, 0.02, 0.07), SCORE_FRAME)
    for x, label in ((-2.0, "HOME"), (2.0, "AWAY")):
        b.text(label, (x, -0.22, 6.32), 0.62, SCORE_TEXT)
        for dx in (-0.5, 0.5):
            _seven_segment(b, x + dx, 4.65, -0.225, 0.62, 1.3, 0.16, SCORE_DIGIT)
    return b.build(name)


# ── Build ────────────────────────────────────────────────────────────

PROPS = [
    round_tree("Prop_OakA", 11),
    round_tree("Prop_OakB", 23),
    fruit_tree("Prop_FruitTree", 5),
    bush("Prop_BushGreen", 3, LEAF_DARK, LEAF_MID),
    bush("Prop_BushDark", 7, BUSH_DARK_A, BUSH_DARK_B),
    bush("Prop_BushLavender", 13, LAVENDER_A, LAVENDER_B, LAVENDER_FLOWER, 26),
    bush("Prop_BushYellow", 17, YELLOW_A, YELLOW_B, YELLOW_FLOWER, 24),
    bush("Prop_BushWhite", 19, LEAF_DARK, LEAF_MID, WHITE_FLOWER, 28),
    bush("Prop_BushBerry", 29, LEAF_DARK, LEAF_MID, RED_FRUIT, 18),
    agave("Prop_Agave", 31),
    park_bench("Prop_ParkBench"),
    picnic_table("Prop_PicnicTable"),
    scoreboard("Prop_Scoreboard"),
]

col = kit.collection("Props")
x = 0.0
for me in PROPS:
    width = max(v.co.x for v in me.vertices) - min(v.co.x for v in me.vertices)
    x += width * 0.5
    kit.place(col, me.name, me, (x, 0.0, 0.0))
    x += width * 0.5 + 2.0
    print("prop", me.name, "verts", len(me.vertices), "slots", len(me.materials))

bpy.ops.wm.save_as_mainfile(filepath=kit.PROPS_BLEND)
print("saved", kit.PROPS_BLEND)

if "--preview" in sys.argv:
    scene = bpy.context.scene
    cam = bpy.data.objects.new("PreviewCam", bpy.data.cameras.new("PreviewCam"))
    scene.collection.objects.link(cam)
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = x + 2.0
    cam.location = (x * 0.5, -80.0, 22.0)
    cam.rotation_euler = (math.radians(76), 0, 0)
    scene.camera = cam
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "MATERIAL"
    scene.render.resolution_x = 2000
    scene.render.resolution_y = 520
    scene.render.filepath = sys.argv[sys.argv.index("--preview") + 1]
    bpy.ops.render.render(write_still=True)
