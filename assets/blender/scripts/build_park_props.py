"""Builds assets/blender/park_props.blend: the low-poly prop library both
ovals' layouts (and kick to kick's training kit) link from. Trees: round
oaks in the park's greens and the bush's, a spreading shade tree, two fruit
trees, a gum. Under them: flowering bushes, a tall shrub, agave, fern,
tussock, ground-cover flowers, rocks, a fallen log. Furniture: bench,
picnic table, bin, drinking fountain, bike rack, coach's shelter. Buildings:
a clubroom and its water tank. Two scoreboards: the park's Prop_Scoreboard
and the bush oval's Prop_TimberScoreboard. Training gear: cones, ball bag,
kit bag, drinks.

    blender -b --python assets/blender/scripts/build_park_props.py

Each prop is one mesh named Prop_* with its origin at its base and its
front facing -Y. The layouts link these meshes rather than copying them, so
re-running this (or hand-editing a Prop_* mesh in park_props.blend) changes
every placed copy on the next layout export. Rename a mesh and the layouts
lose it, so keep the names. Godot (scripts/field/oval_environment.gd) reads
two more things off a prop: a plant's name has one of TINTED_MESH_WORDS in
it (Oak, Bush, Gum, Fern...) so each copy gets its own tint, and nothing
else's may (hence Prop_TimberScoreboard, not "Bush"); and a mesh under
SMALL_PROP_HEIGHT (0.8 m) tall casts no shadow.

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

# 2026-10-31 additions. Gums match newbasictrees.blend's Eucalyptus
# materials, so the two eucalypts sit together.
GUM_WHITE = kit.material("PropGumWhite", "#E3DED0")
GUM_BASE = kit.material("PropGumBase", "#9C9080")
GUM_PATCH = kit.material("PropGumPatch", "#C48A64")
GUM_LEAF_A = kit.material("PropGumLeafA", "#66704A")
GUM_LEAF_B = kit.material("PropGumLeafB", "#7A876A")
GUM_LEAF_C = kit.material("PropGumLeafC", "#4C5636")
FERN_A = kit.material("PropFernA", "#4E7A34")
FERN_B = kit.material("PropFernB", "#3A6328")
TUSSOCK_A = kit.material("PropTussockA", "#7D8E44")
TUSSOCK_B = kit.material("PropTussockB", "#9EA558")
ROCK_A = kit.material("PropRockA", "#8E8B80")
ROCK_B = kit.material("PropRockB", "#706E66")
LOG_BARK = kit.material("PropLogBark", "#5E4A36")
LOG_END = kit.material("PropLogEnd", "#B89C70")
BIN_BODY = kit.material("PropBinBody", "#2F4A35")
BIN_LID = kit.material("PropBinLid", "#2A2A28")
CONCRETE = kit.material("PropConcrete", "#A7A399")
STEEL = kit.material("PropSteel", "#C3C7C7", roughness=0.5)
STEEL_DARK = kit.material("PropSteelDark", "#5F6466", roughness=0.6)
GALV = kit.material("PropGalv", "#A4A9A8", roughness=0.6)
GALV_DARK = kit.material("PropGalvDark", "#7F8584", roughness=0.6)
TIMBER = kit.material("PropTimber", "#8A6A4A")
TIMBER_DARK = kit.material("PropTimberDark", "#5A4330")
# FieldScoreboard.RETRO_PAINT: the bush board's face is painted in Blender,
# and the Godot side letters and hangs tiles on it.
BOARD_GREEN = kit.material("PropBoardGreen", "#1F3A2B")
TRIM_WHITE = kit.material("PropTrimWhite", "#EDE8DA")
WEATHERBOARD = kit.material("PropWeatherboard", "#D9CDAE")
WEATHERBOARD_LINE = kit.material("PropWeatherboardLine", "#B9AD8E")
ROOF_GREEN = kit.material("PropRoofGreen", "#3B5A40", roughness=0.7)
WINDOW = kit.material("PropWindow", "#2B3338", roughness=0.3)
DOOR = kit.material("PropDoor", "#7A3B2E")
# Training gear for kick to kick.
CONE_ORANGE = kit.material("PropConeOrange", "#E8722A")
CONE_YELLOW = kit.material("PropConeYellow", "#E9C23A")
BALL_RED = kit.material("PropBallRed", "#A8261F")
BAG_NAVY = kit.material("PropBagNavy", "#1F2C44")
BAG_RED = kit.material("PropBagRed", "#B0302A")
BOTTLE = kit.material("PropBottle", "#DCE6EA", roughness=0.4)
BOTTLE_CAP = kit.material("PropBottleCap", "#2D6DB3")
ESKY_BLUE = kit.material("PropEskyBlue", "#2B5FA8")


# ── Trees ────────────────────────────────────────────────────────────

def round_tree(name, seed, low=None, mid=None, top=None):
    """Park oak: a stubby trunk under a cluster of faceted blobs, dark
    underneath and light on top, the three-tone shading pixel-art trees use.
    The palette defaults to the park's bright greens; Field 2 passes its
    deep bush greens for the same silhouette (the RNG calls don't depend on
    it, so OakA/OakB come out exactly as they always have)."""
    low, mid, top = low or LEAF_DARK, mid or LEAF_MID, top or LEAF_LIGHT
    rng = random.Random(seed)
    b = kit.MeshBuilder()
    b.cylinder((0, 0, 0), 4.8, 0.5, 0.3, BARK, segments=6)
    for side in (-1, 1):
        b.box((side * 0.55, 0.0, 4.0), (0.24, 0.24, 1.9), BARK, rot=(0.0, side * math.radians(38), 0.0))
    b.blob((0, 0, 6.9), 2.8, mid, squash=(1, 1, 0.85), rng=rng)
    for k in range(6):
        a = math.radians(k * 60 + rng.uniform(-18, 18))
        d = rng.uniform(1.9, 2.6)
        z = rng.uniform(5.7, 7.5)
        mat = low if z < 6.5 else mid
        b.blob((math.cos(a) * d, math.sin(a) * d, z), rng.uniform(1.6, 2.2), mat, squash=(1, 1, 0.85), rng=rng)
    for k in range(3):
        a = math.radians(k * 120 + rng.uniform(0, 60))
        b.blob((math.cos(a) * 1.1, math.sin(a) * 1.1, 8.6), rng.uniform(1.1, 1.4), top,
               squash=(1, 1, 0.8), rng=rng)
    return b.build(name)


def spreading_tree(name, seed, low, mid, top):
    """A broad old shade tree, wider than it is tall: a short trunk forking
    into three limbs under a flattened dome with a ragged rim. Its outline
    is the point: next to the round oaks it breaks up a treeline that would
    otherwise be one repeated lollipop."""
    rng = random.Random(seed)
    b = kit.MeshBuilder()
    b.cylinder((0, 0, 0), 3.4, 0.62, 0.42, BARK, segments=7)
    for k in range(3):
        az = math.radians(k * 120 + rng.uniform(-20, 20))
        b.cylinder((0, 0, 3.0), 3.4, 0.3, 0.16, BARK, segments=5, tilt=(0.0, math.radians(48), az))
    b.blob((0, 0, 6.6), 3.2, mid, squash=(1.25, 1.25, 0.6), rng=rng)
    for k in range(8):
        a = math.radians(k * 45 + rng.uniform(-15, 15))
        d = rng.uniform(3.4, 4.6)
        z = rng.uniform(5.2, 6.4)
        b.blob((math.cos(a) * d, math.sin(a) * d, z), rng.uniform(1.5, 2.1), low if z < 5.8 else mid,
               squash=(1.1, 1.1, 0.7), rng=rng)
    for k in range(4):
        a = math.radians(k * 90 + rng.uniform(0, 50))
        d = rng.uniform(0.8, 2.2)
        b.blob((math.cos(a) * d, math.sin(a) * d, 7.9), rng.uniform(1.2, 1.6), top, squash=(1, 1, 0.65), rng=rng)
    return b.build(name)


def gum_tree(name, seed):
    """A second eucalypt, in the colours of newbasictrees.blend's: a smooth
    pale trunk with a rough grey stocking and ochre bark scars, forking into
    leaning limbs that each carry a few flat grey-green clumps, sky showing
    between them. Lighter and sparser than the linked Eucalyptus, so a
    stand of the two doesn't read as one tree stamped out."""
    rng = random.Random(seed)
    b = kit.MeshBuilder()
    b.cylinder((0, 0, 0), 1.6, 0.52, 0.44, GUM_BASE, segments=7)
    b.cylinder((0, 0, 1.5), 5.2, 0.44, 0.3, GUM_WHITE, segments=7)
    for k in range(3):
        a = rng.uniform(0, math.tau)
        z = rng.uniform(2.0, 5.5)
        b.box((math.cos(a) * 0.36, math.sin(a) * 0.36, z), (0.3, 0.3, rng.uniform(0.4, 0.8)), GUM_PATCH,
              rot=(0.0, 0.0, a))
    leaves = (GUM_LEAF_A, GUM_LEAF_B, GUM_LEAF_C)
    limbs = rng.randint(3, 4)
    for k in range(limbs):
        az = math.tau * k / limbs + rng.uniform(-0.4, 0.4)
        lean = math.radians(rng.uniform(22, 38))
        length = rng.uniform(5.0, 6.6)
        base = kit.Vector((0, 0, 6.2))
        b.cylinder(base, length, 0.24, 0.1, GUM_WHITE, segments=5, tilt=(0.0, lean, az))
        tip = base + kit.Vector((math.sin(lean) * math.cos(az), math.sin(lean) * math.sin(az),
                                 math.cos(lean))) * length
        for j in range(rng.randint(2, 3)):
            off = kit.Vector((rng.uniform(-1.4, 1.4), rng.uniform(-1.4, 1.4), rng.uniform(-1.2, 0.6)))
            b.blob(tip + off, rng.uniform(1.4, 2.1), leaves[(k + j) % 3], squash=(1.1, 1.1, 0.5), rng=rng,
                   jitter=0.18)
    # A low side clump so the trunk isn't bare all the way up.
    a = rng.uniform(0, math.tau)
    b.blob((math.cos(a) * 1.8, math.sin(a) * 1.8, 6.0), 1.3, GUM_LEAF_C, squash=(1.1, 1.1, 0.5), rng=rng)
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


# ── 2026-10-31: more plants ──────────────────────────────────────────
# All of these share the materials above, so a placed copy's tint (set per
# instance by OvalEnvironment) is the only thing that varies between them.

def fruit_tree_b(name, seed):
    """A taller, two-tier fruit tree, so the orchard corner isn't one shape."""
    rng = random.Random(seed)
    b = kit.MeshBuilder()
    b.cylinder((0, 0, 0), 3.2, 0.3, 0.18, BARK, segments=6)
    b.box((0.35, 0.0, 2.6), (0.16, 0.16, 1.4), BARK, rot=(0.0, math.radians(35), 0.0))
    blobs = [((0, 0, 3.6), 1.55, LEAF_DARK), ((0.2, 0.1, 4.9), 1.35, LEAF_MID),
             ((-0.1, -0.1, 5.9), 0.95, LEAF_LIGHT)]
    for k in range(3):
        a = math.radians(k * 120 + rng.uniform(-20, 20))
        blobs.append(((math.cos(a) * 1.15, math.sin(a) * 1.15, rng.uniform(3.4, 4.4)),
                      rng.uniform(0.95, 1.2), LEAF_DARK if k % 2 else LEAF_MID))
    for centre, r, mat in blobs:
        b.blob(centre, r, mat, squash=(1, 1, 0.9), rng=rng)
    _studs(b, rng, blobs, 20, RED_FRUIT, 0.24, min_up=-0.3)
    return b.build(name)


def tall_shrub(name, seed, low, mid, top):
    """An upright shrub about 3 m tall: the layer between the bushes and the
    tree canopies that turns a ring of separate plants into a wall of bush."""
    rng = random.Random(seed)
    b = kit.MeshBuilder()
    b.cylinder((0, 0, 0), 0.8, 0.16, 0.1, BARK, segments=5)
    b.blob((0, 0, 1.0), 1.05, low, squash=(1, 1, 0.95), rng=rng)
    b.blob((0.15, 0.1, 2.0), 0.9, mid, squash=(1, 1, 1.05), rng=rng)
    b.blob((-0.1, 0.0, 2.85), 0.6, top, squash=(1, 1, 1.1), rng=rng)
    for k in range(3):
        a = math.radians(k * 120 + rng.uniform(-30, 30))
        b.blob((math.cos(a) * 0.75, math.sin(a) * 0.75, rng.uniform(0.9, 1.7)), rng.uniform(0.55, 0.75),
               low if k else mid, rng=rng)
    return b.build(name)


def spiky(name, seed, mats, leaves, lean, length, radius, crown=True):
    """Leaves as long thin pyramids fanning out of the ground: the agave's
    build, here for the bush's ferns and grass tussocks."""
    rng = random.Random(seed)
    b = kit.MeshBuilder()
    for k in range(leaves):
        a = math.radians(k * (360 / leaves) + rng.uniform(-14, 14))
        tilt = math.radians(rng.uniform(*lean))
        b.cylinder((0, 0, 0.02), rng.uniform(*length), radius, 0.0, mats[k % len(mats)], segments=3,
                   tilt=(0.0, tilt, a))
    if crown:
        b.cylinder((0, 0, 0.0), length[0] * 0.6, radius * 1.3, 0.0, mats[0], segments=3)
    return b.build(name)


def flower_patch(name, seed):
    """Ground-cover flowers: a low green mound speckled with every flower
    colour in the park, for the dots of colour the reference has in its
    lawns and at the foot of the bushes. Under knee height, so it doesn't
    cast a shadow (OvalEnvironment.SMALL_PROP_HEIGHT)."""
    rng = random.Random(seed)
    b = kit.MeshBuilder()
    blobs = []
    for k in range(4):
        a = math.radians(k * 90 + rng.uniform(-25, 25))
        d = 0.0 if k == 0 else rng.uniform(0.45, 0.7)
        blobs.append(((math.cos(a) * d, math.sin(a) * d, 0.08), rng.uniform(0.38, 0.5),
                      LEAF_MID if k % 2 else LEAF_DARK))
    for centre, r, mat in blobs:
        b.blob(centre, r, mat, squash=(1, 1, 0.42), rng=rng)
    flowers = (WHITE_FLOWER, YELLOW_FLOWER, RED_FRUIT, LAVENDER_FLOWER)
    for i in range(26):
        centre, r, _ = rng.choice(blobs)
        a = rng.uniform(0, math.tau)
        d = rng.uniform(0.1, 0.9) * r
        p = (centre[0] + math.cos(a) * d, centre[1] + math.sin(a) * d, 0.08 + r * 0.38 + rng.uniform(-0.03, 0.04))
        s = rng.uniform(0.09, 0.13)
        b.box(p, (s, s, s), flowers[i % len(flowers)], rot=(0.0, 0.0, rng.uniform(0, 1.5)))
    return b.build(name)


def rock(name, seed):
    """A low faceted boulder; two blobs so it isn't a plain egg."""
    rng = random.Random(seed)
    b = kit.MeshBuilder()
    b.blob((0, 0, 0.22), 0.75, ROCK_A, squash=(1.25, 0.95, 0.62), rng=rng, jitter=0.2)
    b.blob((0.55, 0.3, 0.12), 0.42, ROCK_B, squash=(1.2, 1.0, 0.6), rng=rng, jitter=0.2)
    return b.build(name)


def fallen_log(name, seed):
    """A fallen branch lying in the bush, a broken stub off one side and
    pale sawn ends."""
    rng = random.Random(seed)
    b = kit.MeshBuilder()
    b.cylinder((-2.1, 0, 0.3), 4.2, 0.32, 0.25, LOG_BARK, segments=7, tilt=(0.0, math.radians(90), 0.0))
    b.cylinder((-2.13, 0, 0.3), 0.04, 0.27, 0.27, LOG_END, segments=7, tilt=(0.0, math.radians(-90), 0.0))
    b.cylinder((2.11, 0, 0.3), 0.04, 0.21, 0.21, LOG_END, segments=7, tilt=(0.0, math.radians(90), 0.0))
    b.cylinder((0.6, 0.1, 0.42), 1.1, 0.12, 0.06, LOG_BARK, segments=5,
               tilt=(0.0, math.radians(rng.uniform(50, 65)), math.radians(70)))
    b.blob((-0.8, 0.0, 0.52), 0.22, FERN_B, squash=(1.4, 1, 0.45), rng=rng)
    return b.build(name)


# ── 2026-10-31: park furniture ───────────────────────────────────────

def park_bin(name):
    """A council bin on a post: dark green drum, black lid."""
    b = kit.MeshBuilder()
    b.box((0, 0.3, 0.5), (0.08, 0.08, 1.0), STEEL_DARK)
    b.cylinder((0, 0, 0.12), 0.75, 0.28, 0.3, BIN_BODY, segments=8)
    b.cylinder((0, 0, 0.87), 0.07, 0.32, 0.31, BIN_LID, segments=8)
    b.box((0, -0.31, 0.62), (0.18, 0.04, 0.2), BIN_LID)
    return b.build(name)


def bubbler(name):
    """A park drinking fountain: concrete pedestal, steel bowl and spout."""
    b = kit.MeshBuilder()
    b.box((0, 0, 0.05), (0.6, 0.6, 0.1), CONCRETE)
    b.cylinder((0, 0, 0.1), 0.78, 0.17, 0.14, CONCRETE, segments=6)
    b.cylinder((0, 0, 0.86), 0.1, 0.17, 0.27, STEEL, segments=8)
    b.box((0, -0.08, 0.99), (0.04, 0.12, 0.05), STEEL)
    b.box((0.16, -0.18, 0.92), (0.06, 0.06, 0.06), STEEL_DARK)
    return b.build(name)


def bike_rack(name):
    """Five steel hoops on a ground rail, about 3 m long."""
    b = kit.MeshBuilder()
    b.box((0, 0, 0.03), (3.3, 0.08, 0.06), STEEL_DARK)
    for i in range(5):
        x = -1.5 + i * 0.75
        for y in (-0.33, 0.33):
            b.box((x, y, 0.42), (0.06, 0.06, 0.84), STEEL)
        b.box((x, 0, 0.84), (0.06, 0.72, 0.06), STEEL)
    return b.build(name)


def player_shelter(name):
    """A coach's box / interchange shelter, the kind a country ground has on
    its wing: an open-fronted timber shed with a long bench and a corrugated
    iron skillion roof falling to the back. 6 m wide, front facing -Y."""
    b = kit.MeshBuilder()
    w, d = 6.0, 2.0
    b.box((0, d * 0.5 - 0.05, 1.05), (w, 0.1, 2.1), ROOF_GREEN)
    for x in (-w * 0.5, w * 0.5):
        b.box((x, 0.05, 1.05), (0.1, d - 0.1, 2.1), ROOF_GREEN)
        b.box((x, -d * 0.5 + 0.05, 1.2), (0.14, 0.14, 2.4), TIMBER_DARK)
    tilt = math.radians(-7)
    b.box((0, 0.0, 2.42), (w + 0.5, d + 0.6, 0.06), GALV, rot=(tilt, 0, 0))
    for i in range(17):
        b.box((-w * 0.5 - 0.1 + i * (w + 0.2) / 16, 0.0, 2.46), (0.05, d + 0.6, 0.04), GALV_DARK, rot=(tilt, 0, 0))
    b.box((0, -d * 0.5 - 0.3, 2.47), (w + 0.5, 0.05, 0.18), TIMBER)
    for y in (0.35, 0.55):
        b.box((0, y, 0.46), (w - 0.4, 0.18, 0.05), BENCH_WOOD)
    b.box((0, 0.88, 0.8), (w - 0.4, 0.05, 0.3), BENCH_WOOD)
    for x in (-2.2, 0.0, 2.2):
        b.box((x, 0.45, 0.22), (0.08, 0.4, 0.44), BENCH_FRAME)
    return b.build(name)


def _weatherboards(b, centre, width, height, facing, mat, spacing=0.32):
    """Shadow lines across a weatherboard wall: thin strips standing just
    proud of the face. `facing` is 'x' or 'y' and the sign of the normal."""
    axis, sign = facing
    for i in range(1, int(height / spacing)):
        z = centre[2] - height * 0.5 + i * spacing
        if axis == "y":
            b.box((centre[0], centre[1] + sign * 0.012, z), (width, 0.02, 0.04), mat)
        else:
            b.box((centre[0] + sign * 0.012, centre[1], z), (0.02, width, 0.04), mat)


def clubroom(name):
    """A small country clubroom out past the tree line: weatherboards, a
    corrugated gable roof, a verandah on the side facing the ground, a door
    and two windows. 12 x 7 m, front facing -Y."""
    b = kit.MeshBuilder()
    w, d, h = 12.0, 7.0, 3.0
    b.box((0, 0, h * 0.5), (w, d, h), WEATHERBOARD)
    _weatherboards(b, (0, -d * 0.5, h * 0.5), w, h, ("y", -1), WEATHERBOARD_LINE)
    _weatherboards(b, (0, d * 0.5, h * 0.5), w, h, ("y", 1), WEATHERBOARD_LINE)
    for sign in (-1, 1):
        _weatherboards(b, (sign * w * 0.5, 0, h * 0.5), d, h, ("x", sign), WEATHERBOARD_LINE)
    pitch = math.radians(24)
    rise = d * 0.5 * math.tan(pitch)
    for sign in (-1, 1):
        b.poly([(sign * w * 0.5, -d * 0.5, h), (sign * w * 0.5, d * 0.5, h), (sign * w * 0.5, 0, h + rise)],
               WEATHERBOARD, (sign, 0, 0))
    slope = d * 0.5 / math.cos(pitch) + 0.5
    for sign in (-1, 1):
        rot = (-sign * pitch, 0, 0)   # each half falls away from the ridge
        cy, cz = sign * (d * 0.25 + 0.2), h + rise * 0.5 - 0.02
        b.box((0, cy, cz + 0.06), (w + 0.6, slope, 0.07), ROOF_GREEN, rot=rot)
        for i in range(25):
            b.box((-w * 0.5 - 0.25 + i * (w + 0.5) / 24, cy, cz + 0.11), (0.06, slope, 0.04), ROOF_GREEN,
                  rot=rot)
    b.box((0, 0, h + rise + 0.08), (w + 0.6, 0.3, 0.12), GALV)
    # Verandah along the front.
    b.box((0, -d * 0.5 - 1.25, 0.1), (w, 2.5, 0.2), TIMBER)
    b.box((0, -d * 0.5 - 1.3, 2.75), (w + 0.4, 2.8, 0.06), GALV, rot=(math.radians(8), 0, 0))
    for i in range(9):
        b.box((-w * 0.5 + i * w / 8, -d * 0.5 - 1.3, 2.79), (0.05, 2.8, 0.04), GALV_DARK,
              rot=(math.radians(8), 0, 0))
    for x in (-w * 0.5 + 0.15, -w * 0.17, w * 0.17, w * 0.5 - 0.15):
        b.box((x, -d * 0.5 - 2.4, 1.3), (0.14, 0.14, 2.5), TIMBER_DARK)
    b.box((0, -d * 0.5 - 2.4, 0.9), (w, 0.06, 0.08), TIMBER_DARK)
    # Door and windows on the verandah wall, white frames round them.
    b.box((0, -d * 0.5 - 0.04, 1.15), (1.2, 0.06, 2.3), TRIM_WHITE)
    b.box((0, -d * 0.5 - 0.07, 1.1), (1.0, 0.04, 2.1), DOOR)
    for x in (-3.6, 3.6):
        b.box((x, -d * 0.5 - 0.04, 1.75), (2.2, 0.06, 1.3), TRIM_WHITE)
        b.box((x, -d * 0.5 - 0.07, 1.75), (2.0, 0.04, 1.1), WINDOW)
    b.box((-w * 0.5 - 0.04, 1.5, 1.75), (0.06, 1.6, 1.0), TRIM_WHITE)
    b.box((-w * 0.5 - 0.07, 1.5, 1.75), (0.04, 1.4, 0.8), WINDOW)
    return b.build(name)


def water_tank(name):
    """A corrugated iron rainwater tank on a slab: the other half of every
    country clubroom."""
    b = kit.MeshBuilder()
    b.cylinder((0, 0, 0), 0.15, 1.65, 1.65, CONCRETE, segments=12)
    b.cylinder((0, 0, 0.15), 2.3, 1.4, 1.4, GALV, segments=12)
    for i in range(1, 10):
        b.cylinder((0, 0, 0.15 + i * 0.23), 0.05, 1.43, 1.43, GALV_DARK, segments=12)
    b.cylinder((0, 0, 2.45), 0.35, 1.45, 0.15, GALV, segments=12)
    b.box((0, -1.45, 0.4), (0.08, 0.14, 0.08), STEEL_DARK)
    return b.build(name)


def timber_scoreboard(name):
    """Field 2's own scoreboard (playtest 2026-10-31: "give one of the fields
    a different design scoreboard"): a country ground's hand-worked board.
    Heavy timber posts, a timber-framed face painted sign-writer's green,
    a corrugated iron skillion roof whose eave shades the top of the face,
    a ledge along the bottom the scorer walks to hang the tiles, a ladder
    up to it, and the timekeeper's box underneath with its window on the
    ground. Front faces -Y.

    The painted face is 8.0 x 3.3 m, centred 5.25 m up, its front 0.30 m
    forward of the origin: FieldScoreboard's RETRO_FACE_* constants. Move
    the face and they must move with it. Everything else (lettering, rails,
    tiles) is built in Godot so the score can change."""
    b = kit.MeshBuilder()
    face_w, face_h, face_z, face_y = 8.0, 3.3, 5.25, -0.30
    # Posts: two heavy ones through to the roof in front, two at the back.
    for x in (-3.55, 3.55):
        b.box((x, 0.05, 4.08), (0.38, 0.38, 8.16), TIMBER_DARK)
        b.box((x, 2.0, 3.95), (0.3, 0.3, 7.9), TIMBER_DARK)
        brace = math.atan2(1.95, 2.6)
        b.box((x, 1.02, 1.6), (0.14, 0.14, 3.25), TIMBER, rot=(brace, 0, 0))
        b.box((x, 1.02, 4.8), (0.14, 0.14, 3.25), TIMBER, rot=(-brace, 0, 0))
    # The face: boards behind, painted panel, a timber frame round it.
    b.box((0, 0.0, face_z), (face_w + 0.6, 0.36, face_h + 0.6), TIMBER_DARK)
    b.box((0, face_y + 0.05, face_z), (face_w, 0.1, face_h), BOARD_GREEN)
    for z in (face_z + face_h * 0.5 + 0.12, face_z - face_h * 0.5 - 0.12):
        b.box((0, face_y + 0.04, z), (face_w + 0.6, 0.16, 0.24), TIMBER)
    for x in (-face_w * 0.5 - 0.15, face_w * 0.5 + 0.15):
        b.box((x, face_y + 0.04, face_z), (0.3, 0.16, face_h + 0.48), TIMBER)
    # Header plank between the face and the roof.
    b.box((0, -0.12, 7.42), (face_w + 0.6, 0.2, 0.5), TIMBER)
    # Corrugated skillion roof, high at the front, eave 0.6 m proud.
    tilt = math.radians(-8)
    b.box((0, 0.95, 8.08), (face_w + 1.6, 3.3, 0.07), GALV, rot=(tilt, 0, 0))
    for i in range(23):
        x = -(face_w + 1.6) * 0.5 + 0.1 + i * (face_w + 1.4) / 22
        b.box((x, 0.95, 8.13), (0.06, 3.3, 0.05), GALV_DARK, rot=(tilt, 0, 0))
    b.box((0, -0.68, 8.25), (face_w + 1.6, 0.06, 0.22), TIMBER)
    # The scorer's ledge along the bottom of the face, on brackets.
    b.box((0, -0.72, 3.2), (face_w + 0.6, 0.85, 0.08), TIMBER)
    for x in (-3.0, -1.0, 1.0, 3.0):
        b.box((x, -0.45, 2.95), (0.1, 0.5, 0.1), TIMBER_DARK, rot=(math.radians(-35), 0, 0))
    # Ladder up to it on the right-hand end.
    for x in (4.25, 4.75):
        b.box((x, -0.85, 1.65), (0.08, 0.08, 3.3), TIMBER)
    for i in range(9):
        b.box((4.5, -0.85, 0.35 + i * 0.34), (0.5, 0.06, 0.05), TIMBER)
    # Timekeeper's box underneath: weatherboard hut, window on the ground.
    hut = (0.0, 0.85, 1.2)
    b.box(hut, (3.6, 2.4, 2.4), WEATHERBOARD)
    _weatherboards(b, (0, hut[1] - 1.2, 1.2), 3.6, 2.4, ("y", -1), WEATHERBOARD_LINE, spacing=0.3)
    _weatherboards(b, (1.8, hut[1], 1.2), 2.4, 2.4, ("x", 1), WEATHERBOARD_LINE, spacing=0.3)
    _weatherboards(b, (-1.8, hut[1], 1.2), 2.4, 2.4, ("x", -1), WEATHERBOARD_LINE, spacing=0.3)
    b.box((0, hut[1] - 1.23, 1.6), (2.6, 0.04, 0.8), TRIM_WHITE)
    b.box((0, hut[1] - 1.26, 1.6), (2.4, 0.04, 0.62), WINDOW)
    b.box((1.83, hut[1] + 0.3, 1.0), (0.04, 0.85, 2.0), DOOR)
    b.box((0, hut[1], 2.5), (4.0, 2.9, 0.06), GALV, rot=(math.radians(-6), 0, 0))
    for i in range(10):
        b.box((-1.9 + i * 3.8 / 9, hut[1], 2.54), (0.05, 2.9, 0.04), GALV_DARK, rot=(math.radians(-6), 0, 0))
    return b.build(name)


# ── 2026-10-31: training gear (kick to kick) ─────────────────────────

def marker_cones(name):
    """A stack of flat marker cones and two tall witches' hats."""
    b = kit.MeshBuilder()
    for i in range(7):
        b.cylinder((0, 0, i * 0.035), 0.07, 0.15, 0.05, CONE_YELLOW if i % 2 else CONE_ORANGE, segments=8)
    for x, y in ((0.55, 0.1), (0.75, -0.35)):
        b.box((x, y, 0.015), (0.32, 0.32, 0.03), CONE_ORANGE)
        b.cylinder((x, y, 0.03), 0.42, 0.13, 0.015, CONE_ORANGE, segments=8)
    return b.build(name)


def _football(b, centre, yaw, pitch=0.0, rng=None):
    """A footy: an ellipsoid about 0.29 m long."""
    m = (kit.Matrix.Translation(kit.Vector(centre)) @ kit.Euler((0.0, pitch, yaw)).to_matrix().to_4x4()
         @ kit.Matrix.Diagonal((0.145, 0.09, 0.09, 1.0)))
    r = kit.bmesh.ops.create_icosphere(b.bm, subdivisions=1, radius=1.0, matrix=m)
    b._tag(r["verts"], BALL_RED)


def ball_bag(name, seed):
    """A mesh ball bag slumped on the grass, footies showing out of the top,
    and two loose ones beside it."""
    rng = random.Random(seed)
    b = kit.MeshBuilder()
    b.blob((0, 0, 0.3), 0.42, BAG_NAVY, squash=(1, 1, 0.8), rng=rng, jitter=0.08)
    b.cylinder((0, 0, 0.55), 0.12, 0.3, 0.26, BAG_NAVY, segments=8)
    for i in range(5):
        a = i * math.tau / 5 + rng.uniform(-0.3, 0.3)
        _football(b, (math.cos(a) * 0.13, math.sin(a) * 0.13, 0.68), rng.uniform(0, math.tau),
                  math.radians(rng.uniform(-30, 30)))
    _football(b, (0.62, 0.2, 0.09), 0.4)
    _football(b, (-0.5, 0.45, 0.09), 2.1)
    return b.build(name)


def kit_bag(name):
    """A team kit bag: a navy duffel with a red stripe and a strap."""
    b = kit.MeshBuilder()
    b.cylinder((-0.45, 0, 0.21), 0.9, 0.22, 0.22, BAG_NAVY, segments=8, tilt=(0.0, math.radians(90), 0.0))
    b.cylinder((-0.1, 0, 0.21), 0.2, 0.225, 0.225, BAG_RED, segments=8, tilt=(0.0, math.radians(90), 0.0))
    b.box((0, 0, 0.45), (0.5, 0.05, 0.03), BAG_NAVY)
    for x in (-0.25, 0.25):
        b.box((x, 0, 0.4), (0.03, 0.05, 0.1), BAG_NAVY)
    return b.build(name)


def drinks(name):
    """A drinks carrier with six bottles and an esky beside it."""
    b = kit.MeshBuilder()
    b.box((0, 0, 0.08), (0.42, 0.28, 0.16), CONE_YELLOW)
    for i in range(6):
        x, y = -0.13 + (i % 3) * 0.13, -0.07 + (i // 3) * 0.14
        b.cylinder((x, y, 0.05), 0.24, 0.04, 0.04, BOTTLE, segments=6)
        b.cylinder((x, y, 0.29), 0.04, 0.02, 0.02, BOTTLE_CAP, segments=6)
    b.box((0.65, 0.05, 0.2), (0.6, 0.38, 0.4), ESKY_BLUE)
    b.box((0.65, 0.05, 0.42), (0.62, 0.4, 0.06), TRIM_WHITE)
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
    # 2026-10-31 environment pass. Field 2 (the bush) gets its own deep-green
    # oaks, shrubs, ferns, logs and rocks, a clubroom and its own scoreboard;
    # Field 1 (the park) a spreading shade tree, a second fruit tree, flower
    # patches and the furniture a council park has. Both get the second gum.
    round_tree("Prop_OakDarkA", 11, BUSH_DARK_A, BUSH_DARK_B, LEAF_DARK),
    round_tree("Prop_OakDarkB", 23, BUSH_DARK_A, BUSH_DARK_B, LEAF_DARK),
    spreading_tree("Prop_OakSpread", 47, LEAF_DARK, LEAF_MID, LEAF_LIGHT),
    spreading_tree("Prop_OakSpreadDark", 53, BUSH_DARK_A, BUSH_DARK_B, LEAF_DARK),
    gum_tree("Prop_Gum", 59),
    fruit_tree_b("Prop_FruitTreeB", 41),
    tall_shrub("Prop_ShrubTall", 61, BUSH_DARK_A, BUSH_DARK_B, LEAF_DARK),
    spiky("Prop_Fern", 37, (FERN_A, FERN_B), 14, (55, 75), (1.2, 1.7), 0.2),
    spiky("Prop_Tussock", 43, (TUSSOCK_A, TUSSOCK_B), 16, (5, 35), (0.45, 0.75), 0.07, crown=False),
    flower_patch("Prop_FlowerPatch", 67),
    rock("Prop_Rock", 71),
    fallen_log("Prop_Log", 73),
    park_bin("Prop_Bin"),
    bubbler("Prop_Bubbler"),
    bike_rack("Prop_BikeRack"),
    player_shelter("Prop_PlayerShelter"),
    clubroom("Prop_Clubroom"),
    water_tank("Prop_WaterTank"),
    timber_scoreboard("Prop_TimberScoreboard"),
    marker_cones("Prop_MarkerCones"),
    ball_bag("Prop_BallBag", 79),
    kit_bag("Prop_KitBag"),
    drinks("Prop_Drinks"),
]

# Laid out in rows on the floor of park_props.blend so it reads as a
# catalogue when opened (and for --preview).
col = kit.collection("Props")
ROW_LENGTH = 70.0
x = 0.0
y = 0.0
row_depth = 0.0
for me in PROPS:
    xs = [v.co.x for v in me.vertices]
    ys = [v.co.y for v in me.vertices]
    width = max(xs) - min(xs)
    if x > 0.0 and x + width > ROW_LENGTH:
        x = 0.0
        y += row_depth + 4.0
        row_depth = 0.0
    kit.place(col, me.name, me, (x - min(xs), y - min(ys), 0.0))
    x += width + 2.0
    row_depth = max(row_depth, max(ys) - min(ys))
    print("prop", me.name, "verts", len(me.vertices), "slots", len(me.materials),
          "height %.2f" % max(v.co.z for v in me.vertices))

bpy.ops.wm.save_as_mainfile(filepath=kit.PROPS_BLEND)
print("saved", kit.PROPS_BLEND)

if "--preview" in sys.argv:
    scene = bpy.context.scene
    cam = bpy.data.objects.new("PreviewCam", bpy.data.cameras.new("PreviewCam"))
    scene.collection.objects.link(cam)
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = ROW_LENGTH + 4.0
    depth = y + row_depth
    cam.location = (ROW_LENGTH * 0.5, depth * 0.5 - 70.0, 40.0)
    cam.rotation_euler = (math.radians(62), 0, 0)
    scene.camera = cam
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "MATERIAL"
    scene.render.resolution_x = 2000
    scene.render.resolution_y = 1400
    scene.render.filepath = sys.argv[sys.argv.index("--preview") + 1]
    bpy.ops.render.render(write_still=True)
