@tool
class_name Field
extends Node3D

## The oval: turf, line markings and four posts at each end.
##
## Milestone 1 does not need a stadium. It does need scale. You cannot
## judge whether a body feels heavy or a kick feels long without
## something to measure it against, and a 50m arc and a mown band every
## 9m are exactly that measurement. Everything here is generated from
## Tuning's dimensions, so changing the ground size changes the ground.
##
## Prototype 1 drew its field at 166 x 88 logical units to suit a fixed
## 16:9 diorama camera. A 3D camera has no such constraint, so these are
## real AFL proportions and real metres.

## Emitted when the ball enters a goal or behind zone (see
## _build_score_zones). The scoring team is whichever side attacks this
## end — HOME attacks +X per Tuning.gd's documented axis convention.
signal scored(team: Tuning.Team, is_goal: bool)

const GOAL_POST_SCENE := preload("res://assets/imported/goal_post.glb")

const MARKING_HEIGHT := 0.012      ## m above the turf, to beat z-fighting
const ELLIPSE_SEGMENTS := 160
const CIRCLE_SEGMENTS := 48
const ARC_SEGMENTS := 200
const POST_RADIUS := 0.09

const COLOUR_LINE := Color("#f4f1e0")   ## Prototype 1's LINE
const COLOUR_POST_BASE := Color("#c65449")  ## Prototype 1's POST_RED

## The goal line sits just inside the boundary, the way it does on a real
## ground — there is playing surface behind the posts.
const GOAL_LINE_INSET := 1.5

## How far the surrounds run past the boundary. Generous enough that wide
## establishing camera angles (menu backdrop, broadcast flyovers) don't run
## off the edge of the ground plane and reveal sky at a grazing angle.
##
## 60m was not: the menu montage's opening wide shot sits 48m up and 70m
## out, and from there the far edge of the plane cut a dead straight line
## across the sky behind the treeline. This pushes that edge out to about
## half a kilometre, where the environment fog has faded it into the sky
## before it can be seen. The ground is two triangles however large it is
## and the turf shader is per-pixel, so the extra reach costs nothing —
## the plane covers the same screen area either way.
const SURROUND_MARGIN := 420.0

## Stadium boundary fence — purely a "this is an oval, not an empty plane"
## visual cue (design doc §9 territory, same spirit as the posts). Sits
## just past the running-track apron drawn by turf.gdshader's apron_width.
##
## Its job is to frame the ground, not to be looked at. It used to be
## painted in COLOUR_LINE — the exact white the goal posts and every
## painted marking use — with COLOUR_POST_BASE red posts every eighth
## segment, which made it a bright dashed ring and the brightest
## continuous object in a wide shot. The colours below keep it a legible
## edge while dropping it well below the markings in contrast.
const FENCE_HEIGHT := 1.1
const FENCE_OFFSET := 9.0        ## m outside the boundary line, past the apron
const FENCE_SEGMENTS := 160
const FENCE_POST_SPACING := 8    ## every Nth ellipse segment gets a post
const FENCE_POST_RADIUS := 0.05
## Muted stone, a long way off the markings' white.
const COLOUR_FENCE := Color("#C9C6BA")
## Cap rail along the top edge. A single darker line is what makes a flat
## ribbon read as a fence rather than as a strip of paint standing on the
## grass, and it does that without adding any brightness.
const COLOUR_FENCE_RAIL := Color("#8E9089")
const FENCE_RAIL_HEIGHT := 0.12

# ── Surrounding trees ────────────────────────────────────────────────
# A ring of small stylised trees in the park beyond the fence. One
# MultiMesh for the canopies and one for the trunks, so the whole band is
# two draw calls however many trees it holds — a MeshInstance3D per tree
# would be hundreds.
#
# Placed outside the boundary and never inside it: this is framing for
# wide and low camera angles, and the brief is explicit that the playing
# surface stays uncluttered.

const TREE_COUNT := 132
const TREE_RING_INSET := 6.0     ## m beyond the fence before the first tree
const TREE_RING_DEPTH := 26.0    ## m of band the ring is scattered through
const TREE_HEIGHT_MIN := 3.4
const TREE_HEIGHT_MAX := 5.8
const TREE_SEED := 20250819
const COLOUR_TRUNK := Color("#6B5B4A")
## Canopy tints, sampled between per instance. Both are desaturated
## against the pitch so the trees sit behind it rather than compete.
const COLOUR_CANOPY_A := Color("#4F6B45")
const COLOUR_CANOPY_B := Color("#6C8752")


func _ready() -> void:
	if not Engine.is_editor_hint():
		_size_ground()
	_build_markings()
	_build_goals()
	if not Engine.is_editor_hint():
		_build_umpires()
	_build_fence()
	_build_trees()


## The ground slab and its shader both take their extents from Tuning, so
## resizing the oval there resizes everything that draws it.
func _size_ground() -> void:
	var length := Tuning.FIELD_LENGTH + SURROUND_MARGIN * 2.0
	var width := Tuning.FIELD_WIDTH + SURROUND_MARGIN * 2.0

	var turf := $Ground/Turf as MeshInstance3D
	var plane := PlaneMesh.new()
	plane.size = Vector2(length, width)
	turf.mesh = plane

	var material := turf.material_override as ShaderMaterial
	if material != null:
		material.set_shader_parameter(&"half_length", Tuning.FIELD_HALF_LENGTH)
		material.set_shader_parameter(&"half_width", Tuning.FIELD_HALF_WIDTH)

	var slab := BoxShape3D.new()
	slab.size = Vector3(length, 2.0, width)
	var collision := $Ground/CollisionShape3D as CollisionShape3D
	collision.shape = slab
	collision.position = Vector3(0.0, -1.0, 0.0)


## Where the ball starts a centre bounce.
func centre() -> Vector3:
	return Vector3(0.0, 0.5, 0.0)


## `direction` is -1 or +1: which end of the ground.
func goal_line_x(direction: int) -> float:
	return float(direction) * (Tuning.FIELD_HALF_LENGTH - GOAL_LINE_INSET)


func is_inside_oval(point: Vector3, inset := 0.0) -> bool:
	var x := point.x / maxf(Tuning.FIELD_HALF_LENGTH - inset, 0.001)
	var z := point.z / maxf(Tuning.FIELD_HALF_WIDTH - inset, 0.001)
	return x * x + z * z <= 1.0


# ── Line markings ────────────────────────────────────────────────────

func _build_markings() -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)

	_stripe(surface, _oval_flat_ends(Tuning.FIELD_HALF_LENGTH, Tuning.FIELD_HALF_WIDTH,
		ELLIPSE_SEGMENTS / 2, absf(goal_line_x(1))), true)

	# Centre square (50m), centre circle (10m) and inner circle (3m).
	var half_square := Tuning.CENTRE_SQUARE_SIZE * 0.5
	_stripe(surface, _rectangle(-half_square, half_square, -half_square, half_square), true)
	_stripe(surface, _circle(Vector3.ZERO, Tuning.CENTRE_CIRCLE_OUTER, CIRCLE_SEGMENTS), true)
	_stripe(surface, _circle(Vector3.ZERO, Tuning.CENTRE_CIRCLE_INNER, CIRCLE_SEGMENTS), true)

	for direction: int in [-1, 1]:
		var line_x := goal_line_x(direction)
		var goal_centre := Vector3(line_x, MARKING_HEIGHT, 0.0)

		# The 50m arc, clipped to the playing surface. Swept starting from
		# the direction pointing away from the middle, so the part that
		# survives the clip is one contiguous run.
		var start_angle := 0.0 if direction > 0 else PI
		_stripe(surface, _arc_inside_oval(goal_centre, Tuning.SCORING_ARC_RADIUS,
			start_angle, ARC_SEGMENTS), false)

		# The line across the end, behind post to behind post.
		var end_z := Tuning.GOAL_POST_SEPARATION * 0.5 + Tuning.BEHIND_POST_OFFSET
		_stripe(surface, PackedVector3Array([
			Vector3(line_x, MARKING_HEIGHT, -end_z),
			Vector3(line_x, MARKING_HEIGHT, end_z),
		]), false)

		# Goal square: 9m deep, 6.4m wide, drawn into the field.
		var square_x := line_x - float(direction) * Tuning.GOAL_SQUARE_DEPTH
		var square_z := Tuning.GOAL_POST_SEPARATION * 0.5
		_stripe(surface, _rectangle(minf(line_x, square_x), maxf(line_x, square_x),
			-square_z, square_z), true)

	var mesh := surface.commit()

	var material := StandardMaterial3D.new()
	material.albedo_color = COLOUR_LINE
	material.roughness = 0.9
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0, material)

	var node := MeshInstance3D.new()
	node.name = "Markings"
	node.mesh = mesh
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)


## Widens a polyline into a flat ribbon of quads. Faces are drawn with
## culling disabled, so winding order does not matter here.
func _stripe(surface: SurfaceTool, points: PackedVector3Array, closed: bool) -> void:
	var count := points.size()
	if count < 2:
		return
	var half := Tuning.LINE_WIDTH * 0.5
	var left := PackedVector3Array()
	var right := PackedVector3Array()
	for i in count:
		var previous := points[(i - 1 + count) % count] if closed else points[maxi(i - 1, 0)]
		var next := points[(i + 1) % count] if closed else points[mini(i + 1, count - 1)]
		var tangent := next - previous
		tangent.y = 0.0
		if tangent.length_squared() < 0.000001:
			tangent = Vector3.FORWARD
		tangent = tangent.normalized()
		var side := Vector3(-tangent.z, 0.0, tangent.x) * half
		left.append(points[i] + side)
		right.append(points[i] - side)

	var segments := count if closed else count - 1
	surface.set_normal(Vector3.UP)
	for i in segments:
		var j := (i + 1) % count
		surface.add_vertex(left[i])
		surface.add_vertex(right[i])
		surface.add_vertex(right[j])
		surface.add_vertex(left[i])
		surface.add_vertex(right[j])
		surface.add_vertex(left[j])


func _ellipse(semi_x: float, semi_z: float, segments: int) -> PackedVector3Array:
	return _ellipse_at(Vector3.ZERO, semi_x, semi_z, segments)


## Oval boundary with flat ends: follows the ellipse arc along the long sides
## but replaces each pointed tip with a straight line at x = ±clip_x.
## Used so the goal posts (which sit at x = ±clip_x) lie visibly on the
## boundary line rather than inside a curved tip.
func _oval_flat_ends(semi_x: float, semi_z: float, arc_segments: int,
		clip_x: float) -> PackedVector3Array:
	var points := PackedVector3Array()
	# z value where the ellipse meets the clip line
	var t_clip := acos(clampf(clip_x / semi_x, -1.0, 1.0))
	var z_end  := sin(t_clip) * semi_z

	# Top arc: sweep from +clip_x side to -clip_x side (t: t_clip → π-t_clip)
	for i in range(arc_segments + 1):
		var t := lerpf(t_clip, PI - t_clip, float(i) / float(arc_segments))
		points.append(Vector3(cos(t) * semi_x, MARKING_HEIGHT, sin(t) * semi_z))

	# Left flat end: straight down from (-clip_x, +z_end) to (-clip_x, -z_end)
	points.append(Vector3(-clip_x, MARKING_HEIGHT, -z_end))

	# Bottom arc: sweep from -clip_x side to +clip_x side (t: π+t_clip → 2π-t_clip)
	for i in range(arc_segments + 1):
		var t := lerpf(PI + t_clip, TAU - t_clip, float(i) / float(arc_segments))
		points.append(Vector3(cos(t) * semi_x, MARKING_HEIGHT, sin(t) * semi_z))

	# The right flat end closes implicitly: _stripe(closed=true) connects the
	# last point (clip_x, -z_end) back to the first (clip_x, +z_end).
	return points


func _circle(centre_point: Vector3, radius: float, segments: int) -> PackedVector3Array:
	return _ellipse_at(centre_point, radius, radius, segments)


func _ellipse_at(centre_point: Vector3, semi_x: float, semi_z: float,
		segments: int) -> PackedVector3Array:
	var points := PackedVector3Array()
	for i in segments:
		var t := TAU * float(i) / float(segments)
		points.append(Vector3(
			centre_point.x + cos(t) * semi_x,
			MARKING_HEIGHT,
			centre_point.z + sin(t) * semi_z))
	return points


func _rectangle(min_x: float, max_x: float, min_z: float, max_z: float) -> PackedVector3Array:
	return PackedVector3Array([
		Vector3(min_x, MARKING_HEIGHT, min_z),
		Vector3(max_x, MARKING_HEIGHT, min_z),
		Vector3(max_x, MARKING_HEIGHT, max_z),
		Vector3(min_x, MARKING_HEIGHT, max_z),
	])


func _arc_inside_oval(centre_point: Vector3, radius: float, start_angle: float,
		segments: int) -> PackedVector3Array:
	var points := PackedVector3Array()
	for i in range(segments + 1):
		var t := start_angle + TAU * float(i) / float(segments)
		var point := Vector3(
			centre_point.x + cos(t) * radius,
			MARKING_HEIGHT,
			centre_point.z + sin(t) * radius)
		if is_inside_oval(point, Tuning.LINE_WIDTH):
			points.append(point)
	return points


# ── Posts ────────────────────────────────────────────────────────────

func _build_goals() -> void:
	var goals := Node3D.new()
	goals.name = "Goals"
	add_child(goals)

	var goal_z := Tuning.GOAL_POST_SEPARATION * 0.5
	var behind_z := goal_z + Tuning.BEHIND_POST_OFFSET

	for direction: int in [-1, 1]:
		var x := goal_line_x(direction)
		_post(goals, Vector3(x, 0.0, -goal_z), Tuning.GOAL_POST_HEIGHT)
		_post(goals, Vector3(x, 0.0, goal_z), Tuning.GOAL_POST_HEIGHT)
		_post(goals, Vector3(x, 0.0, -behind_z), Tuning.BEHIND_POST_HEIGHT)
		_post(goals, Vector3(x, 0.0, behind_z), Tuning.BEHIND_POST_HEIGHT)
		_build_score_zones(goals, direction, x, goal_z, behind_z)


func _post(parent: Node3D, base: Vector3, height: float) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = base
	parent.add_child(body)

	var shape := CylinderShape3D.new()
	shape.radius = POST_RADIUS
	shape.height = height
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position = Vector3(0.0, height * 0.5, 0.0)
	body.add_child(collision)

	# Imported mesh is modelled at GOAL_POST_HEIGHT (10 m), origin at base.
	# Scale Y so behind posts (6 m) come out the right size.
	var mesh: Node3D = GOAL_POST_SCENE.instantiate()
	mesh.scale.y = height / Tuning.GOAL_POST_HEIGHT
	body.add_child(mesh)


# ── Scoring ──────────────────────────────────────────────────────────
# Three Area3D triggers per end: one goal-mouth box between the goal
# posts, two behind boxes either side of it out to the behind posts. No
# post-hit or crossing-height distinction (design doc scope for the Full
# Game milestone) — whichever box the ball enters decides the outcome.

const SCORE_ZONE_DEPTH := 4.0      ## m, how far past the goal line the trigger reaches
const SCORE_ZONE_HEIGHT := 12.0    ## m, tall enough that no realistic kick clears it

func _build_score_zones(parent: Node3D, direction: int, line_x: float,
		goal_z: float, behind_z: float) -> void:
	var team := Tuning.Team.HOME if direction > 0 else Tuning.Team.AWAY
	var centre_x := line_x + float(direction) * SCORE_ZONE_DEPTH * 0.5
	_score_zone(parent, "GoalMouth%d" % direction, centre_x, 0.0, goal_z * 2.0, team, true)
	_score_zone(parent, "BehindA%d" % direction, centre_x, (goal_z + behind_z) * 0.5,
		behind_z - goal_z, team, false)
	_score_zone(parent, "BehindB%d" % direction, centre_x, -(goal_z + behind_z) * 0.5,
		behind_z - goal_z, team, false)


func _score_zone(parent: Node3D, zone_name: String, centre_x: float, centre_z: float,
		width: float, team: Tuning.Team, is_goal: bool) -> void:
	var area := Area3D.new()
	area.name = zone_name
	area.collision_layer = 0
	area.collision_mask = 4   # "ball", per project.godot's [layer_names]
	area.position = Vector3(centre_x, SCORE_ZONE_HEIGHT * 0.5, centre_z)
	parent.add_child(area)

	var shape := BoxShape3D.new()
	shape.size = Vector3(SCORE_ZONE_DEPTH, SCORE_ZONE_HEIGHT, width)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	area.add_child(collision)

	area.body_entered.connect(func(body: Node3D) -> void:
		if body is Ball:
			scored.emit(team, is_goal))


# ── Match officials ──────────────────────────────────────────────────
# Core rulebook v1 §10: a boundary umpire either side and a goal umpire at
# each end. Purely cosmetic actors with no collision — see umpire.gd's own
# class doc for why that's deliberate. Built here with the rest of the
# ground furniture because that is what they are from this file's point of
# view: something that stands on the field, sized off Tuning like
# everything else here.

## How far behind the goal line the goal umpire stands. GOAL_LINE_INSET is
## only 1.5m, so this puts them just off the playing surface — which is
## exactly where the real one stands relative to a real goal line, and
## keeps them clear of a ball still travelling after it has scored.
const UMPIRE_GOAL_SETBACK := 2.5

## Just outside the boundary line, off the playing surface for the same
## reason.
const UMPIRE_BOUNDARY_OFFSET := 0.6

## How far to the side of a stoppage spot the field umpire stands — far
## enough that he isn't inside the two ruckmen, close enough to read as
## the one throwing it up. Also his idle spot beside the centre circle.
##
## 2.4m, not the 1.6m this started at: the ball is thrown from his hands
## now (Ball.lock_to, see FullGame._begin_ruck_contest), and at 1.6m the
## release point was inside a contestant's own gather reach
## (GATHER_RADIUS + GATHER_LUNGE_MAX = 1.70m), so the throw-up was being
## plucked out of the air on the frame it left his hands instead of going
## up and being contested on the way down.
const UMPIRE_CENTRE_OFFSET := 2.4

## Which goal umpire signals which team's goals — the umpire at the end a
## team attacks. HOME attacks +X (Tuning's axis convention).
var _goal_umpires := {}

## The one official who moves: he goes to wherever the next stoppage is and
## throws the ball up. See FullGame._begin_ruck_contest, which is the only
## caller — this file just builds him and hands him over.
var _field_umpire: Umpire


## The field umpire, for whoever is running a stoppage. Null-safe for any
## caller that doesn't care (the field is used by Kick-to-Kick too, which
## has no stoppages).
func field_umpire() -> Umpire:
	return _field_umpire


func _build_umpires() -> void:
	var officials := Node3D.new()
	officials.name = "Umpires"
	add_child(officials)

	_field_umpire = Umpire.new()
	_field_umpire.role = Umpire.Role.FIELD
	officials.add_child(_field_umpire)
	# Somewhere sensible until the first stoppage moves him: beside the
	# centre circle, out of the way of the centre bounce itself.
	_field_umpire.stand_at(centre() + Vector3(0.0, 0.0, UMPIRE_CENTRE_OFFSET), centre())

	for direction: int in [-1, 1]:
		var goal_umpire := Umpire.new()
		goal_umpire.role = Umpire.Role.GOAL
		goal_umpire.position = Vector3(
			goal_line_x(direction) + float(direction) * UMPIRE_GOAL_SETBACK, 0.0, 0.0)
		# A node's forward is -Z, so this yaw looks back down the ground.
		goal_umpire.rotation.y = float(direction) * PI * 0.5
		officials.add_child(goal_umpire)
		_goal_umpires[Tuning.Team.HOME if direction > 0 else Tuning.Team.AWAY] = goal_umpire

	for side: int in [-1, 1]:
		var boundary_umpire := Umpire.new()
		boundary_umpire.role = Umpire.Role.BOUNDARY
		boundary_umpire.position = Vector3(
			0.0, 0.0, float(side) * (Tuning.FIELD_HALF_WIDTH + UMPIRE_BOUNDARY_OFFSET))
		boundary_umpire.rotation.y = 0.0 if side > 0 else PI
		officials.add_child(boundary_umpire)

	scored.connect(_raise_goal_flags)


## The goal umpire's two flags going up (rulebook §10) is the only thing
## any official here actually does. Driven off this file's own `scored`
## signal rather than from FullGame, so it happens wherever the field is
## used and can't be forgotten by a new mode.
func _raise_goal_flags(team: Tuning.Team, is_goal: bool) -> void:
	if not is_goal:
		return
	var umpire: Umpire = _goal_umpires.get(team)
	if is_instance_valid(umpire):
		umpire.signal_goal()


# ── Boundary fence ───────────────────────────────────────────────────
# A continuous low ribbon rather than individually instanced pickets —
# cheaper (one mesh, same technique as _stripe()) and reads the same way
# a real picket fence does from a broadcast camera's distance: a solid
# white band, not distinct pickets. A handful of posts add just enough
# depth cues up close without the cost of a picket per metre.

func _build_fence() -> void:
	var half_length := Tuning.FIELD_HALF_LENGTH + FENCE_OFFSET
	var half_width := Tuning.FIELD_HALF_WIDTH + FENCE_OFFSET
	var points := _ellipse_at(Vector3.ZERO, half_length, half_width, FENCE_SEGMENTS)
	var count := points.size()

	_build_ribbon(points, count, 0.0, FENCE_HEIGHT, COLOUR_FENCE, "Fence")
	_build_fence_rail(points, count)

	# Posts in the same stone family as the ribbon, a shade darker, rather
	# than the goal posts' red.
	var post_material := StandardMaterial3D.new()
	post_material.albedo_color = COLOUR_FENCE_RAIL
	post_material.roughness = 0.85
	var posts := Node3D.new()
	posts.name = "FencePosts"
	add_child(posts)
	for i in range(0, count, FENCE_POST_SPACING):
		_fence_post(posts, points[i], post_material)


## Darker band along the top edge of the fence, built as a second ribbon
## sitting a hair outside the first so it reads as a capping rail.
func _build_fence_rail(points: PackedVector3Array, count: int) -> void:
	var node := _build_ribbon(points, count, FENCE_HEIGHT - FENCE_RAIL_HEIGHT, FENCE_HEIGHT,
		COLOUR_FENCE_RAIL, "FenceRail")
	# Scaled fractionally outward so the two coplanar ribbons cannot
	# z-fight along the rail's lower edge.
	node.scale = Vector3(1.0008, 1.0, 1.0008)


## Shared quad-ribbon builder behind the fence and its capping rail: walks
## `points` as a closed loop, emitting a vertical strip from `low` to `high`
## between each consecutive pair with an outward-facing normal.
func _build_ribbon(points: PackedVector3Array, count: int, low: float, high: float,
		colour: Color, node_name: String) -> MeshInstance3D:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in count:
		var a := points[i]
		var b := points[(i + 1) % count]
		var a0 := Vector3(a.x, low, a.z)
		var a1 := Vector3(a.x, high, a.z)
		var b0 := Vector3(b.x, low, b.z)
		var b1 := Vector3(b.x, high, b.z)
		var tangent := b0 - a0
		surface.set_normal(Vector3(tangent.z, 0.0, -tangent.x).normalized())
		surface.add_vertex(a0)
		surface.add_vertex(b0)
		surface.add_vertex(b1)
		surface.add_vertex(a0)
		surface.add_vertex(b1)
		surface.add_vertex(a1)

	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.roughness = 0.9
	material.cull_mode = BaseMaterial3D.CULL_DISABLED

	var node := MeshInstance3D.new()
	node.name = node_name
	node.mesh = surface.commit()
	node.material_override = material
	add_child(node)
	return node


func _fence_post(parent: Node3D, base: Vector3, material: Material) -> void:
	var height := FENCE_HEIGHT + 0.12
	var shaft := CylinderMesh.new()
	shaft.top_radius = FENCE_POST_RADIUS
	shaft.bottom_radius = FENCE_POST_RADIUS
	shaft.height = height
	shaft.radial_segments = 6
	var node := MeshInstance3D.new()
	node.mesh = shaft
	node.material_override = material
	node.position = Vector3(base.x, height * 0.5, base.z)
	parent.add_child(node)


# ── Trees ────────────────────────────────────────────────────────────

## Scatters TREE_COUNT trees through a band in the park outside the fence.
##
## Deterministic (TREE_SEED): the ground is rebuilt from scratch every
## time a scene loads, and a park that rearranged itself between the menu
## montage and the match would read as a different venue.
##
## Angles are stratified rather than uniformly random — one tree per equal
## slice of the ellipse, jittered inside its own slice. Uniform random
## angles clump, and a ring with visible clusters and bald patches reads
## as a bug rather than as planting.
##
## Tonal variation across the treeline comes from splitting the trees
## between two canopy MultiMeshes with different solid materials, rather
## than from a per-instance colour on one. MultiMesh.use_colors is set and
## set_instance_color() accepts the values here, but they do not survive:
## reading one straight back returns black, and the canopies render at the
## material default. Two buckets is three draw calls instead of two, gives
## the same read at this distance, and cannot silently stop working.
func _build_trees() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = TREE_SEED

	var half_length := Tuning.FIELD_HALF_LENGTH + FENCE_OFFSET + TREE_RING_INSET
	var half_width := Tuning.FIELD_HALF_WIDTH + FENCE_OFFSET + TREE_RING_INSET
	var slice := TAU / float(TREE_COUNT)

	var trunks: Array[Transform3D] = []
	# Two separately typed arrays rather than an array of arrays: the inner
	# arrays of an Array[Array] are untyped, and passing one to a parameter
	# declared Array[Transform3D] is a runtime type error.
	var canopies_a: Array[Transform3D] = []
	var canopies_b: Array[Transform3D] = []

	for i in TREE_COUNT:
		var angle := slice * (float(i) + rng.randf_range(0.15, 0.85))
		# randf() squared biases the band inward, so the ring reads as a
		# treeline thinning outward rather than as an even wall.
		var depth := rng.randf() * rng.randf() * TREE_RING_DEPTH
		var origin := Vector3(
			cos(angle) * (half_length + depth), 0.0, sin(angle) * (half_width + depth))
		var height := rng.randf_range(TREE_HEIGHT_MIN, TREE_HEIGHT_MAX)
		var spread := height * rng.randf_range(0.26, 0.36)
		var turn := Basis(Vector3.UP, rng.randf_range(0.0, TAU))

		trunks.append(Transform3D(
			turn.scaled(Vector3(1.0, height * 0.5, 1.0)),
			origin + Vector3(0.0, height * 0.25, 0.0)))
		var canopy := Transform3D(
			turn.scaled(Vector3(spread, height * 0.42, spread)),
			origin + Vector3(0.0, height * 0.66, 0.0))
		if rng.randi() % 2 == 0:
			canopies_a.append(canopy)
		else:
			canopies_b.append(canopy)

	_tree_multimesh("Trunks", _trunk_mesh(), COLOUR_TRUNK, 0.9, trunks)
	_tree_multimesh("CanopiesA", _canopy_mesh(), COLOUR_CANOPY_A, 0.95, canopies_a)
	_tree_multimesh("CanopiesB", _canopy_mesh(), COLOUR_CANOPY_B, 0.95, canopies_b)


## Low and deliberately faceted. The brief asks for clean silhouettes and
## a handcrafted miniature read; a smooth high-poly ball at this size just
## looks like a smooth high-poly ball.
func _canopy_mesh() -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.2
	mesh.radial_segments = 7
	mesh.rings = 4
	return mesh


func _trunk_mesh() -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.09
	mesh.bottom_radius = 0.15
	mesh.height = 1.0
	mesh.radial_segments = 5
	return mesh


func _tree_multimesh(node_name: String, mesh: PrimitiveMesh, albedo: Color,
		roughness: float, transforms: Array[Transform3D]) -> void:
	if transforms.is_empty():
		return

	var material := StandardMaterial3D.new()
	material.albedo_color = albedo
	material.roughness = roughness
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	# `mesh.material`, not surface_set_material(): these are PrimitiveMeshes,
	# which generate their surface lazily and expose exactly one material
	# through this property. surface_set_material() silently does nothing on
	# them, which is how the first cut of this ended up with white blobs.
	mesh.material = material

	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = transforms.size()
	for i in transforms.size():
		multimesh.set_instance_transform(i, transforms[i])

	var node := MultiMeshInstance3D.new()
	node.name = node_name
	node.multimesh = multimesh
	# The trees stand 90-120m out, well past anything the play happens
	# near, so their shadows would only ever fall on empty park — and
	# casting them would spend a slice of the directional shadow atlas on
	# ground no camera dwells on.
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
