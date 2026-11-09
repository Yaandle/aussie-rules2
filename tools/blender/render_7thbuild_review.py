"""Contact sheets of the Build 7 mesh straight from Blender: a turnaround in
the rest pose, and poses off the clips, with an optional wireframe so the
topology shows. For judging shape and edge flow while tuning
build_7thbuild_mesh.py, without a round trip through Godot. How the model
reads in the game (its lighting, its cameras, the kit shader) is
scripts/dev/build_compare.gd's job.

    blender assets/blender/7thbuild.blend --background --python tools/blender/render_7thbuild_review.py -- OUT.png [--wire] [--poses | --close] [--small]
    blender assets/blender/7thbuild.blend --background --python tools/blender/build_7thbuild_mesh.py --python tools/blender/render_7thbuild_review.py -- OUT.png

(the second form regenerates the mesh first without saving, for iterating
on the generator's tables). Renders with Workbench: flat studio light, the
preview "Col" colours, back faces culled as the game does. Nothing is
saved to the .blend.
"""

import math
import sys

import bpy
from mathutils import Vector

ARMATURE = "Armature"
PARTS = ["B7_Body", "B7_Hair", "B7_Guernsey", "B7_Shorts", "B7_Boots"]
CELL = (420, 640)

## (label, action or None for the rest pose, frame, yaw degrees, ortho?)
## yaw 0 looks at the front of the body (it faces -Y), 90 at its left side.
TURNAROUND = [
	("front", None, 0, 0.0, True),
	("3/4", None, 0, 35.0, False),
	("side", None, 0, 90.0, True),
	("back", None, 0, 180.0, True),
]
## Head and shoulders, close: (label, action, frame, yaw, centre z, width
## of view in metres).
CLOSE = [
	("face", None, 0, 20.0, 1.98, 0.42),
	("shoulders", None, 0, 0.0, 1.62, 0.95),
	("shoulders 3/4", None, 0, 40.0, 1.62, 0.95),
	("back", None, 0, 180.0, 1.55, 0.95),
	("mark", "mark_aggressive", 11, 15.0, 1.85, 1.2),
	("takedown", "tackle_takedown", 15, 15.0, 1.05, 1.2),
	("hips 3/4", None, 0, 35.0, 1.05, 0.8),
	("run hips", "run_fwd", 7, 70.0, 1.02, 0.8),
]
POSES = [
	("run knee", "run_fwd", 7, 70.0, False),
	("kick", "kick", 11, 25.0, False),
	("mark", "mark_aggressive", 11, 20.0, False),
	("dive", "smother_dive", 11, 60.0, False),
	("tackled", "tackled", 13, 60.0, False),
	("takedown", "tackle_takedown", 15, 30.0, False),
	("knocked", "knocked_back", 25, 60.0, False),
	("sling", "tackle_sling", 15, 40.0, False),
]


def setup_scene():
	scene = bpy.context.scene
	scene.render.engine = 'BLENDER_WORKBENCH'
	sh = scene.display.shading
	sh.light = 'STUDIO'
	sh.color_type = 'VERTEX'
	sh.show_backface_culling = True
	sh.show_shadows = False
	sh.show_cavity = False
	sh.background_type = 'WORLD'
	scene.display_settings.display_device = 'sRGB'
	scene.view_settings.view_transform = 'Standard'
	scene.render.resolution_x, scene.render.resolution_y = CELL
	scene.render.film_transparent = False
	scene.world = scene.world or bpy.data.worlds.new("World")
	scene.world.color = (0.62, 0.70, 0.76)
	cam_data = bpy.data.cameras.new("ReviewCam")
	cam = bpy.data.objects.new("ReviewCam", cam_data)
	scene.collection.objects.link(cam)
	scene.camera = cam
	return scene, cam


def add_wire():
	"""A dark wireframe shell over each part (a Wireframe modifier on a
	linked duplicate), so edge loops show in a Workbench render."""
	wires = []
	mat = bpy.data.materials.new("ReviewWire")
	mat.diffuse_color = (0.05, 0.05, 0.06, 1.0)
	for name in PARTS:
		ob = bpy.data.objects.get(name)
		if ob is None:
			continue
		dup = ob.copy()
		dup.data = ob.data.copy()
		dup.name = name + "_wire"
		bpy.context.scene.collection.objects.link(dup)
		dup.data.color_attributes.remove(dup.data.color_attributes["Col"])
		dup.data.materials.clear()
		dup.data.materials.append(mat)
		mod = dup.modifiers.new("Wire", 'WIREFRAME')
		mod.thickness = 0.0022
		mod.use_relative_offset = False
		mod.offset = 1.0
		# Wireframe before the Armature modifier deforms it.
		bpy.context.view_layer.objects.active = dup
		while dup.modifiers[0].name != "Wire":
			bpy.ops.object.modifier_move_up(modifier="Wire")
		wires.append(dup)
	return wires


def frame_close(cam, yaw, z, width):
	"""An orthographic close-up `width` metres across, centred at height z
	on the body's axis."""
	d = Vector((math.sin(math.radians(yaw)), -math.cos(math.radians(yaw)), 0.10)).normalized()
	centre = Vector((0.0, 0.0, z))
	cam.data.type = 'ORTHO'
	cam.data.ortho_scale = width * CELL[1] / CELL[0]
	cam.location = centre + d * 6.0
	cam.rotation_euler = (centre - cam.location).to_track_quat('-Z', 'Y').to_euler()


def frame_body(cam, yaw, ortho, objs):
	"""Point the camera at the posed body's bounding box from `yaw`."""
	dg = bpy.context.evaluated_depsgraph_get()
	lo = Vector((1e9, 1e9, 1e9))
	hi = -lo
	for ob in objs:
		ev = ob.evaluated_get(dg)
		me = ev.to_mesh()
		for v in me.vertices:
			p = ob.matrix_world @ v.co
			lo = Vector(map(min, lo, p))
			hi = Vector(map(max, hi, p))
		ev.to_mesh_clear()
	centre = (lo + hi) * 0.5
	size = max((hi - lo).length, 1.0)
	d = Vector((math.sin(math.radians(yaw)), -math.cos(math.radians(yaw)), 0.12)).normalized()
	cam.data.type = 'ORTHO' if ortho else 'PERSP'
	if ortho:
		cam.data.ortho_scale = max(hi.z - lo.z, (hi - lo).length * 0.75) * 1.08
		cam.location = centre + d * 8.0
	else:
		cam.data.lens = 50.0
		cam.location = centre + d * size * 1.55
	cam.rotation_euler = (centre - cam.location).to_track_quat('-Z', 'Y').to_euler()


def render_cells(scene, cam, shots, objs):
	arm = bpy.data.objects[ARMATURE]
	ad = arm.animation_data
	saved = (ad.action, ad.action_slot, ad.use_nla, arm.data.pose_position, scene.frame_current)
	cells = []
	try:
		ad.use_nla = False
		for shot in shots:
			label, action, fr, yaw = shot[:4]
			if action is None:
				arm.data.pose_position = 'REST'
			else:
				arm.data.pose_position = 'POSE'
				act = bpy.data.actions[action]
				ad.action = act
				if act.slots:
					ad.action_slot = act.slots[0]
				scene.frame_set(fr)
			bpy.context.view_layer.update()
			if len(shot) == 6:
				frame_close(cam, yaw, shot[4], shot[5])
			else:
				frame_body(cam, yaw, shot[4], objs)
			path = bpy.app.tempdir + "review_cell_%d.png" % len(cells)
			scene.render.filepath = path
			bpy.ops.render.render(write_still=True)
			cells.append((label, path))
	finally:
		ad.action, ad.use_nla = saved[0], saved[2]
		if saved[1] is not None:
			ad.action_slot = saved[1]
		arm.data.pose_position = saved[3]
		scene.frame_set(saved[4])
	return cells


def compose(cells, out_path, columns, scale=1.0):
	import numpy as np
	w, h = CELL
	rows = (len(cells) + columns - 1) // columns
	sheet = np.zeros((rows * h, columns * w, 4), dtype=np.float32)
	for i, (_, path) in enumerate(cells):
		img = bpy.data.images.load(path)
		px = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)
		r, c = i // columns, i % columns
		# Blender's pixel rows run bottom-up.
		sheet[(rows - 1 - r) * h:(rows - r) * h, c * w:(c + 1) * w] = px
		bpy.data.images.remove(img)
	out = bpy.data.images.new("review_sheet", columns * w, rows * h, alpha=True)
	out.pixels = sheet.ravel()
	out.filepath_raw = out_path
	out.file_format = 'PNG'
	if scale != 1.0:
		out.scale(int(columns * w * scale), int(rows * h * scale))
	out.save()


def main():
	argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
	out_path = next((a for a in argv if not a.startswith("--")), bpy.app.tempdir + "review.png")
	scene, cam = setup_scene()
	objs = [bpy.data.objects[n] for n in PARTS if n in bpy.data.objects]
	if "--wire" in argv:
		add_wire()
	if "--close" in argv:
		shots = CLOSE
	else:
		shots = TURNAROUND + (POSES if "--poses" in argv else [])
	cells = render_cells(scene, cam, shots, objs)
	# --small: half size, for sheets that go into the repo.
	compose(cells, out_path, 4, 0.5 if "--small" in argv else 1.0)
	print("render_7thbuild_review: wrote", out_path, "(%d cells: %s)" % (len(cells), ", ".join(c[0] for c in cells)))


if __name__ == "__main__":
	main()
