"""Contact sheets of the Build 7 mesh straight from Blender: a turnaround in
the rest pose, and poses off the clips, with an optional wireframe so the
topology shows. For judging shape and edge flow while tuning
build_8thbuild_mesh.py, without a round trip through Godot. How the model
reads in the game (its lighting, its cameras, the kit shader) is
scripts/dev/build_compare.gd's job.

    blender assets/blender/8thbuild.blend --background --python tools/blender/render_8thbuild_review.py -- OUT.png [--wire] [--poses | --close | --audit | --idle] [--small]
    blender assets/blender/8thbuild.blend --background --python tools/blender/build_8thbuild_mesh.py --python tools/blender/render_8thbuild_review.py -- OUT.png

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
PARTS = ["B8_Body", "B8_Hair", "B8_Guernsey", "B8_Shorts", "B8_Boots"]
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
## The worst frames audit_8thbuild_anim.py finds, framed on a bone so a
## body that moves in its clip stays in shot: (label, action, frame, yaw,
## bone, how far along it 0..1, width of view in metres). --audit.
AUDIT = [
	("run elbow", "run_fwd", 9, 90.0, "lowerarm.l", 0.0, 0.55),
	("run elbow front", "run_fwd", 9, 20.0, "lowerarm.l", 0.0, 0.55),
	("handball elbow", "handball", 3, 60.0, "lowerarm.r", 0.0, 0.55),
	("mark elbow", "mark_aggressive", 13, 20.0, "lowerarm.l", 0.0, 0.55),
	("kick boot", "kick", 13, 90.0, "foot.r", 0.2, 0.5),
	("kick boot 3/4", "kick", 11, 45.0, "foot.r", 0.2, 0.5),
	("tackled boot", "tackled", 25, 90.0, "foot.l", 0.2, 0.5),
	("dive boot", "smother_dive", 11, 60.0, "foot.l", 0.2, 0.5),
	("bounce knee", "bounce", 13, 90.0, "lowerleg.l", 0.0, 0.6),
	("mark run knee", "mark_running", 5, 90.0, "lowerleg.r", 0.0, 0.6),
	("knocked knee", "knocked_back", 25, 90.0, "lowerleg.l", 0.0, 0.7),
	("dive knee", "smother_dive", 9, 60.0, "lowerleg.l", 0.0, 0.7),
	("stride crotch", "run_fwd_r", 13, 180.0, "pelvis", 0.0, 0.7),
	("dive seat", "smother_dive", 11, 150.0, "pelvis", 0.0, 0.8),
	("knocked seat", "knocked_back", 25, 120.0, "pelvis", 0.0, 0.8),
	("tackled wrist", "tackled", 15, 30.0, "hand.r", 0.0, 0.4),
	("tackled wrist l", "tackled", 21, 30.0, "hand.l", 0.0, 0.4),
	("mark shoulder", "mark_aggressive", 7, 30.0, "upperarm.r", 0.0, 0.6),
	("tackled neck", "tackled", 21, 90.0, "head", 0.0, 0.5),
	("hit_out elbow", "hit_out", 7, 20.0, "lowerarm.r", 0.0, 0.55),
]
## The reference turnaround's views in the arms-down idle (the reference
## stands that way, not in the A-pose rest), full body then the shoulders
## close, for matching the 2026-11-21 turnaround. --idle.
IDLE = [
	("front", "idle", 1, 0.0, True),
	("side", "idle", 1, 90.0, True),
	("back", "idle", 1, 180.0, True),
	("3/4", "idle", 1, 35.0, False),
	("shoulders", "idle", 1, 0.0, 1.62, 0.80),
	("shoulders side", "idle", 1, 90.0, 1.62, 0.80),
	("shoulders back", "idle", 1, 180.0, 1.62, 0.80),
	("shoulders 3/4", "idle", 1, 40.0, 1.62, 0.80),
	("neckline", "idle", 1, 10.0, 1.78, 0.42),
	("neckline above", "idle", 1, 0.0, 1.72, 0.42),
	("armhole", "idle", 1, 60.0, 1.66, 0.50),
	("thighs", "idle", 1, 20.0, 0.80, 0.70),
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


def frame_close(cam, yaw, z, width, centre=None):
	"""An orthographic close-up `width` metres across, centred at height z
	on the body's axis, or on `centre`."""
	d = Vector((math.sin(math.radians(yaw)), -math.cos(math.radians(yaw)), 0.10)).normalized()
	centre = Vector((0.0, 0.0, z)) if centre is None else centre
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
			if len(shot) == 7:
				pb = arm.pose.bones[shot[4]]
				h, t = arm.matrix_world @ pb.head, arm.matrix_world @ pb.tail
				frame_close(cam, yaw, 0.0, shot[6], h + (t - h) * shot[5])
			elif len(shot) == 6:
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
	elif "--audit" in argv:
		shots = AUDIT
	elif "--idle" in argv:
		shots = IDLE
	else:
		shots = TURNAROUND + (POSES if "--poses" in argv else [])
	cells = render_cells(scene, cam, shots, objs)
	# --small: half size, for sheets that go into the repo.
	compose(cells, out_path, 4, 0.5 if "--small" in argv else 1.0)
	print("render_8thbuild_review: wrote", out_path, "(%d cells: %s)" % (len(cells), ", ".join(c[0] for c in cells)))


if __name__ == "__main__":
	main()
