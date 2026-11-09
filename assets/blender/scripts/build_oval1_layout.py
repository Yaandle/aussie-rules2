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
from there so nothing here lands on a trunk. The 2026-10-31 expansion at the
end adds the rest of the bush wall, the coach's shelters, the clubroom and
Field 2's own scoreboard prop (see the comment there).
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
    "Prop_ParkBench", "Prop_PicnicTable", "Prop_TimberScoreboard",
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

# Since 2026-10-31 Field 2 has its own board, the timber one with the
# timekeeper's box (Field 1 keeps Prop_Scoreboard). Same spot, same name:
# OvalEnvironment finds it by "Scoreboard" and FieldScoreboard's RETRO
# style is built for this prop's face.
SCOREBOARD = (0.0, 82.0)
kit.place(layout, "Scoreboard", props["Prop_TimberScoreboard"], SCOREBOARD)
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

# ── 2026-10-31 expansion ─────────────────────────────────────────────
# Playtest 2026-10-31: "more trees and objects outside of the field", each
# field after its reference. Append-only, like build_park_oval.py's: the
# pass above still rolls the same numbers, so what was here stays put, and
# this one has its own RNG and spaces against all of it. The reference's
# bush oval is a dense dark wall: round dark trees on the west, north and
# south, eucalypts on the east, shrubs packed under them. Ours was the gum
# ring all the way round over a ring of bushes, so this adds:
# - deep-green oaks (Prop_OakDark*, Prop_OakSpreadDark) through the west,
#   north and south, and the second gum (Prop_Gum) on the east, in two
#   bands: 10-48 m out, and a far band 48-100 m out named Far* (no shadows,
#   see OvalEnvironment's "Shadow budget");
# - a layer of tall shrubs between the bushes and the canopies, more dark
#   bush clumps, ferns, tussocks, fallen logs and rocks in the bush;
# - a country ground's buildings: a coach's shelter either side of the
#   scoreboard on the north wing, and a weatherboard clubroom with its
#   water tank out past the trees on the west path, a spur of path to it;
# - bins by the benches and the picnic table, taps at the south gap and
#   the clubroom.
# Still no flowers beyond the berry bushes: the reference has almost none.

props.update(kit.link_meshes(kit.PROPS_BLEND, [
    "Prop_OakDarkA", "Prop_OakDarkB", "Prop_OakSpreadDark", "Prop_Gum", "Prop_ShrubTall", "Prop_Fern",
    "Prop_Tussock", "Prop_Rock", "Prop_Log", "Prop_Bin", "Prop_Bubbler", "Prop_PlayerShelter",
    "Prop_Clubroom", "Prop_WaterTank",
]))
ext = kit.random.Random(1031)
KEEP = ("Paths", "Paths_Clubroom", "Scoreboard")
added = {}


def add(name, mesh_name, pos, yaw, scale=1.0):
    n = added.get(mesh_name, 0)
    added[mesh_name] = n + 1
    return kit.place(layout, "%s_x%03d" % (name, n), props[mesh_name], pos, yaw, scale)


def nearest_ring(pos):
    return min((kit.Vector(pos) - kit.Vector(t)).length for t in ring)


# The clubroom faces the ground (east) from past the west treeline, north
# of the west path, a short spur of path up to its verandah.
CLUBROOM = kit.Vector((-178.0, 4.0))
SPUR = [kit.Vector((-171.5, -12.0)), kit.Vector((-171.0, -5.0)), kit.Vector((-170.5, 3.0))]
spur = kit.MeshBuilder()
spur.ribbon(SPUR, 4.0, -0.016, PATH_EDGE)
spur.ribbon(SPUR, 3.0, -0.012, PATH)
spur_obj = bpy.data.objects.new("Paths_Clubroom", spur.build("Oval1_PathsClubroom"))
layout.objects.link(spur_obj)
for p in kit.catmull_rom(SPUR, 4):
    kit.remove_overlapping(layout, p, 3.5, KEEP)
sc.paths.append(kit.catmull_rom(SPUR, 4))

# The shelters stand where the fence is 5 m off at x = +-24, either side of
# the scoreboard.
shelter_angle = math.degrees(math.acos(24.0 / (kit.FENCE_A + 5.0)))
FIXED = [
    # (mesh, position, yaw or None to face the oval, clear radius)
    ("Prop_PlayerShelter", kit.ellipse_point(5.0, math.radians(shelter_angle)), None, 3.6),
    ("Prop_PlayerShelter", kit.ellipse_point(5.0, math.radians(180.0 - shelter_angle)), None, 3.6),
    ("Prop_Clubroom", CLUBROOM, math.radians(90.0), 8.0),
    ("Prop_WaterTank", CLUBROOM + kit.Vector((-2.0, 9.0)), 0.0, 2.0),
    ("Prop_Bin", CLUBROOM + kit.Vector((6.4, -4.6)), math.radians(90.0), 1.0),
    ("Prop_Bubbler", CLUBROOM + kit.Vector((6.2, 7.2)), math.radians(90.0), 1.0),
    ("Prop_Bin", kit.ellipse_point(3.5, math.radians(62.0)), None, 1.0),
    ("Prop_Bin", kit.ellipse_point(3.5, math.radians(26.0)), None, 1.0),
    ("Prop_Bin", (82.8, -57.6), 0.35, 1.0),
    ("Prop_Bubbler", (5.6, -84.0), math.radians(90.0), 1.0),
]
for mesh_name, pos, yaw, clear in FIXED:
    pos = kit.Vector((pos[0], pos[1]))
    gone = kit.remove_overlapping(layout, pos, clear + 0.8, KEEP)
    add(mesh_name.replace("Prop_", ""), mesh_name, pos, kit.face_centre_rot(pos) if yaw is None else yaw)
    sc.reserve(pos, clear)
    print("fixed %-20s at (%6.1f, %6.1f): cleared %d, nearest ring trunk %.1f m"
          % (mesh_name, pos.x, pos.y, gone, nearest_ring(pos)))

EAST = (-65.0, 65.0)


def is_east(ang_deg):
    return kit.in_sector(ang_deg, *EAST)


def clear_of_ring(pos, gap):
    return all((kit.Vector(pos) - kit.Vector(t)).length >= gap for t in ring)


# Trees: dark round oaks everywhere off the east, the second gum on it.
# Separate quotas, so the oaks aren't crowded out: the west, north and
# south are already thick with the ring and the bushes, and a single
# count would fill up wherever there was room (the east) first.
DARK_OAKS = [("Prop_OakDarkA", 0.38), ("Prop_OakDarkB", 0.38), ("Prop_OakSpreadDark", 0.24)]
new_trees = {}
for far, kind_set, count, lo, hi, tries in (
        (False, "oak", 62, 10.0, 48.0, 30000), (False, "gum", 14, 10.0, 48.0, 8000),
        (True, "oak", 70, 48.0, 100.0, 20000), (True, "gum", 18, 48.0, 100.0, 8000)):
    key = ("Far " if far else "") + kind_set
    new_trees[key] = 0
    for _ in range(tries):
        if new_trees[key] >= count:
            break
        if kind_set == "gum":
            ang = ext.uniform(EAST[0], EAST[1])
            kind, radius = "Prop_Gum", 3.4
        else:
            ang = ext.uniform(EAST[1], 360.0 + EAST[0])
            kind = kit.pick(ext, DARK_OAKS)
            radius = 5.5 if kind == "Prop_OakSpreadDark" else 4.3
        pos = kit.ellipse_point(ext.uniform(lo, hi), math.radians(ang))
        if not clear_of_ring(pos, 4.5):
            continue
        if sc.try_place(pos, radius, PATH_WIDTH * 0.5 + 3.0):
            scale = ext.uniform(0.9, 1.15) if kind == "Prop_Gum" else ext.uniform(1.0, 1.4)
            add(("Far" if far else "") + kind.replace("Prop_", ""), kind, pos, ext.uniform(0, math.tau), scale)
            new_trees[key] += 1

# The clubroom's own few trees and a picnic table, so it sits in a clearing
# rather than alone on a lawn.
for offset, kind, scale in (((-11.0, 15.0), "Prop_OakSpreadDark", 1.1), ((-12.0, -6.0), "Prop_OakDarkA", 1.25),
                            ((3.0, 19.0), "Prop_Gum", 1.05), ((-8.0, -25.0), "Prop_Gum", 0.95),
                            ((10.0, 22.0), "Prop_OakDarkB", 1.2)):
    pos = CLUBROOM + kit.Vector(offset)
    kit.remove_overlapping(layout, pos, 4.0, KEEP)
    add("Club" + kind.replace("Prop_", ""), kind, pos, ext.uniform(0, math.tau), scale)
    sc.reserve(pos, 4.0)
add("ClubPicnicTable", "Prop_PicnicTable", CLUBROOM + kit.Vector((8.5, 10.5)), 1.2)
sc.reserve(CLUBROOM + kit.Vector((8.5, 10.5)), 2.4)

# Tall shrubs, the wall's middle layer, mostly in the first 25 m.
shrubs = 0
for _ in range(8000):
    if shrubs >= 80:
        break
    pos = kit.ellipse_point(ext.uniform(4.5, 25.0), ext.uniform(0.0, math.tau))
    if clear_of_ring(pos, 2.0) and sc.try_place(pos, 1.3, PATH_WIDTH * 0.5 + 1.5):
        add("ShrubTall", "Prop_ShrubTall", pos, ext.uniform(0, math.tau), ext.uniform(0.85, 1.25))
        shrubs += 1

# More dark bush clumps further out, so the overhead reads as one mass.
more_bushes = 0
clumps = 0
for _ in range(6000):
    if clumps >= 45:
        break
    centre = kit.ellipse_point(ext.uniform(16.0, 42.0), ext.uniform(0.0, math.tau))
    if not sc.free(centre, 1.2, PATH_WIDTH * 0.5 + 2.5):
        continue
    species = kit.pick(ext, [("Dark", 0.6), ("Green", 0.3), ("Berry", 0.1)])
    clumps += 1
    for _ in range(ext.randint(3, 5)):
        for _ in range(20):
            a = ext.uniform(0, math.tau)
            d = ext.uniform(0.0, 4.6)
            pos = (centre.x + math.cos(a) * d, centre.y + math.sin(a) * d)
            size = ext.uniform(1.2, 2.0)
            if sc.try_place(pos, 0.9 * size, PATH_WIDTH * 0.5 + 1.2):
                add("Bush" + species, "Prop_Bush" + species, pos, ext.uniform(0, math.tau), size)
                more_bushes += 1
                break

# The bush floor: ferns in close under the canopy, tussocks in the open,
# logs and rocks scattered through it.
floor = {"Prop_Fern": 0, "Prop_Tussock": 0, "Prop_Log": 0, "Prop_Rock": 0}
FLOOR = [("Prop_Fern", 55, 4.0, 40.0, 0.9, (0.9, 1.3)), ("Prop_Tussock", 55, 4.0, 60.0, 0.6, (0.9, 1.4)),
         ("Prop_Log", 14, 8.0, 70.0, 2.4, (0.8, 1.2)), ("Prop_Rock", 35, 5.0, 80.0, 1.0, (0.6, 1.5))]
for kind, count, lo, hi, radius, scales in FLOOR:
    for _ in range(6000):
        if floor[kind] >= count:
            break
        pos = kit.ellipse_point(ext.uniform(lo, hi), ext.uniform(0.0, math.tau))
        if clear_of_ring(pos, 1.5) and sc.try_place(pos, radius, PATH_WIDTH * 0.5 + 0.8):
            add(kind.replace("Prop_", ""), kind, pos, ext.uniform(0, math.tau), ext.uniform(*scales))
            floor[kind] += 1
            # Rocks come in twos and threes.
            if kind == "Prop_Rock":
                for _ in range(ext.randint(0, 2)):
                    a = ext.uniform(0, math.tau)
                    q = (pos.x + math.cos(a) * 1.6, pos.y + math.sin(a) * 1.6)
                    if sc.try_place(q, 0.6, PATH_WIDTH * 0.5 + 0.8):
                        add("Rock", "Prop_Rock", q, ext.uniform(0, math.tau), ext.uniform(0.4, 0.8))

print("expansion: trees %s, %d tall shrubs, %d bushes in %d clumps, floor %s"
      % (new_trees, shrubs, more_bushes, clumps, floor))
print("layout objects:", len(layout.objects))

bpy.ops.wm.save_mainfile()
kit.export_glb(list(layout.objects), "oval1_layout.glb")
