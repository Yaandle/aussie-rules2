"""Exports assets/imported/training_kit.glb: the gear a training session
leaves by the fence, for kick to kick (scenes/modes/kick_to_kick.tscn).

    blender -b --python assets/blender/scripts/build_training_kit.py

Run build_park_props.py first: this links Prop_ParkBench and the training
gear (Prop_KitBag, Prop_BallBag, Prop_Drinks, Prop_MarkerCones) from
park_props.blend, arranges them round a local origin and exports that. It
saves no .blend of its own; the arrangement lives here.

Kick to kick takes whichever oval Settings picks (follow_field_style), so
the kit stands inside the fence, where both ovals have nothing: two park
benches against the fence and the bags, drinks and cones in front of them.
Front faces -Y (Godot +Z), the oval side when placed on the north wing.
It's plain meshes with no collision, scenery like the old bench.glb pair it
replaces: a ball or a player passes through it, nothing is blocked.
"""

import math
import os
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import field_kit as kit  # noqa: E402

bpy.ops.wm.read_factory_settings(use_empty=True)

props = kit.link_meshes(kit.PROPS_BLEND, [
    "Prop_ParkBench", "Prop_KitBag", "Prop_BallBag", "Prop_Drinks", "Prop_MarkerCones",
])
col = kit.collection("TrainingKit")

# (name, mesh, (x, y, z), yaw)
KIT = [
    ("Bench_0", "Prop_ParkBench", (-1.2, 1.0, 0.0), 0.0),
    ("Bench_1", "Prop_ParkBench", (1.2, 1.0, 0.0), 0.0),
    ("KitBag_0", "Prop_KitBag", (-1.75, 0.92, 0.48), 0.05),
    ("KitBag_1", "Prop_KitBag", (0.25, -0.35, 0.0), 0.35),
    ("KitBag_2", "Prop_KitBag", (-0.95, -0.55, 0.0), -0.45),
    ("BallBag", "Prop_BallBag", (2.65, -0.45, 0.0), 0.0),
    ("Drinks", "Prop_Drinks", (1.1, -0.2, 0.0), 0.2),
    ("MarkerCones", "Prop_MarkerCones", (3.55, 0.55, 0.0), 0.6),
]
objects = []
for name, mesh, pos, yaw in KIT:
    objects.append(kit.place(col, name, props[mesh], pos, yaw))

kit.export_glb(objects, "training_kit.glb")
print("training kit: %d pieces" % len(objects))
