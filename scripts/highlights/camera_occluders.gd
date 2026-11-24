class_name CameraOccluders
extends RefCounted

## What a replay camera must not sit inside or look through: every tree,
## bush, bench, scoreboard and stand of the ground dressing, as world boxes,
## plus the recorded bodies (set per frame by the stage).
##
## Why boxes and not physics: the dressing is MultiMesh art with no
## collision (OvalEnvironment batches ~160 trees into a handful of
## MultiMeshInstance3Ds), and the replay has no physics anyway. A tree's box
## is generous (it wraps the canopy), which is the right way to be wrong for
## a camera: it keeps clear of the leaves too. Built once per stage from the
## Field's subtree (2026-11-24 audit: a highlight clip spent 65 frames
## inside a tree; the broadcast preset sat 34 m off the play, past the fence
## once play was on the near wing).
##
## Skipped: anything flat (the turf, lines, the apron: under FLAT_HEIGHT
## tall) and anything bigger than HUGE across (ground-wide rings such as a
## single fence or turf mesh, whose box would swallow the whole oval). The
## fence is handled by the stage's own keep-inside-the-fence rule instead.

const FLAT_HEIGHT := 0.35       ## m; shorter than this never blocks a camera
const HUGE := 40.0              ## m; a box wider than this is a ring/ground, not a prop
## Thinner than this in both X and Z (a goal post, a light pole) is too thin
## to hide a player behind, so it only counts as something not to sit in.
const THIN := 0.6
## How far a camera keeps from a box or a body, m.
const PAD := 0.6
## A body as an upright box this wide and tall around its root, m.
const BODY_RADIUS := 0.45
const BODY_HEIGHT := 2.0

## Boxes are bucketed on a CELL-metre grid over X/Z so a sight-line test
## only looks at the boxes near it (a park has a few thousand; a full-match
## export asks several times a frame for ~15k frames).
const CELL := 10.0

var boxes: Array[AABB] = []
var _grid := {}
## Per box: false for THIN ones (sit-in only, never a sight-line blocker).
var blocks_sight: Array[bool] = []
## The recorded bodies' root positions this frame (the stage fills it).
var bodies: Array[Vector3] = []


static func build(root: Node) -> CameraOccluders:
	var occ := CameraOccluders.new()
	occ._collect(root)
	return occ


func _collect(node: Node) -> void:
	# People aren't scenery: the umpires live under the Field, and the
	# bodies are handled per frame (near_body).
	if node is HumanoidRig or node is Umpire:
		return
	if node is MultiMeshInstance3D:
		var layer := node as MultiMeshInstance3D
		if layer.is_visible_in_tree() and layer.multimesh != null and layer.multimesh.mesh != null:
			var aabb := layer.multimesh.mesh.get_aabb()
			# The builder's own copy of the placements when it left one: a
			# headless run's dummy renderer reads every instance back as the
			# identity, which put the whole park at the centre bounce.
			if layer.has_meta(&"instance_transforms"):
				for t: Transform3D in layer.get_meta(&"instance_transforms"):
					_add(layer.global_transform * t * aabb)
			else:
				var count := layer.multimesh.instance_count
				if layer.multimesh.visible_instance_count >= 0:
					count = mini(count, layer.multimesh.visible_instance_count)
				for i in count:
					_add(layer.global_transform * layer.multimesh.get_instance_transform(i) * aabb)
	elif node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.is_visible_in_tree() and mi.mesh != null:
			_add(mi.global_transform * mi.mesh.get_aabb())
	for child in node.get_children():
		_collect(child)


func _add(box: AABB) -> void:
	box = box.abs()
	if box.size.y < FLAT_HEIGHT or box.size.x > HUGE or box.size.z > HUGE:
		return
	var index := boxes.size()
	boxes.append(box)
	blocks_sight.append(box.size.x > THIN or box.size.z > THIN)
	var grown := box.grow(PAD)
	for cx in range(_cell(grown.position.x), _cell(grown.end.x) + 1):
		for cz in range(_cell(grown.position.z), _cell(grown.end.z) + 1):
			var key := Vector2i(cx, cz)
			if not _grid.has(key):
				_grid[key] = PackedInt32Array()
			(_grid[key] as PackedInt32Array).append(index)


static func _cell(v: float) -> int:
	return int(floor(v / CELL))


## Indexes of the boxes whose cells touch the X/Z bounds of a..b.
func _near(a: Vector3, b: Vector3) -> PackedInt32Array:
	var out := PackedInt32Array()
	var seen := {}
	for cx in range(_cell(minf(a.x, b.x)), _cell(maxf(a.x, b.x)) + 1):
		for cz in range(_cell(minf(a.z, b.z)), _cell(maxf(a.z, b.z)) + 1):
			var cell: Variant = _grid.get(Vector2i(cx, cz))
			if cell == null:
				continue
			for i: int in cell:
				if not seen.has(i):
					seen[i] = true
					out.append(i)
	return out


## True when `p` is inside a dressing box (grown by PAD) or within PAD of a
## body below head height.
func inside(p: Vector3) -> bool:
	var cell: Variant = _grid.get(Vector2i(_cell(p.x), _cell(p.z)))
	if cell != null:
		for i: int in cell:
			if boxes[i].grow(PAD).has_point(p):
				return true
	return near_body(p)


func near_body(p: Vector3, skip := -1) -> bool:
	if p.y > BODY_HEIGHT + PAD:
		return false
	for i in bodies.size():
		if i == skip:
			continue
		var b := bodies[i]
		if Vector2(p.x - b.x, p.z - b.z).length() < BODY_RADIUS + PAD and p.y > b.y - 0.1:
			return true
	return false


## How far along a→b (0..1) the first dressing box that blocks the view is,
## or 1.0 when the line is clear. Bodies don't count here: a player between
## the lens and the contest is part of the shot, not scenery.
func first_hit(a: Vector3, b: Vector3) -> float:
	var best := 1.0
	var span := b - a
	var length := span.length()
	if length < 0.001:
		return 1.0
	for i in _near(a, b):
		if not blocks_sight[i]:
			continue
		var box := boxes[i].grow(PAD)
		# Cheap reject first: the segment's own bounds.
		if not box.intersects(AABB(a, Vector3.ZERO).expand(b)):
			continue
		if box.has_point(a):
			return 0.0
		var hit: Variant = box.intersects_segment(a, b)
		if hit != null:
			best = minf(best, (hit as Vector3).distance_to(a) / length)
	return best


## Number of frames' worth of trouble for `camera` looking at `subject`:
## {inside, blocked} as bools, for the audit tool and the ranking pass.
func check(camera: Vector3, subject: Vector3) -> Dictionary:
	return {"inside": inside(camera), "blocked": first_hit(subject, camera) < 0.999}
