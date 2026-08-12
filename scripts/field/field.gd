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

## How far the surrounds run past the boundary.
const SURROUND_MARGIN := 25.0


func _ready() -> void:
	_size_ground()
	_build_markings()
	_build_goals()


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

	_stripe(surface, _ellipse(Tuning.FIELD_HALF_LENGTH, Tuning.FIELD_HALF_WIDTH,
		ELLIPSE_SEGMENTS), true)

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

	var post_material := StandardMaterial3D.new()
	post_material.albedo_color = COLOUR_LINE
	post_material.roughness = 0.6
	var base_material := StandardMaterial3D.new()
	base_material.albedo_color = COLOUR_POST_BASE
	base_material.roughness = 0.7

	var goal_z := Tuning.GOAL_POST_SEPARATION * 0.5
	var behind_z := goal_z + Tuning.BEHIND_POST_OFFSET

	for direction: int in [-1, 1]:
		var x := goal_line_x(direction)
		_post(goals, Vector3(x, 0.0, -goal_z), Tuning.GOAL_POST_HEIGHT,
			post_material, base_material)
		_post(goals, Vector3(x, 0.0, goal_z), Tuning.GOAL_POST_HEIGHT,
			post_material, base_material)
		_post(goals, Vector3(x, 0.0, -behind_z), Tuning.BEHIND_POST_HEIGHT,
			post_material, base_material)
		_post(goals, Vector3(x, 0.0, behind_z), Tuning.BEHIND_POST_HEIGHT,
			post_material, base_material)


func _post(parent: Node3D, base: Vector3, height: float,
		shaft_material: Material, base_material: Material) -> void:
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

	var shaft := CylinderMesh.new()
	shaft.top_radius = POST_RADIUS
	shaft.bottom_radius = POST_RADIUS
	shaft.height = height
	shaft.radial_segments = 10
	var shaft_node := MeshInstance3D.new()
	shaft_node.mesh = shaft
	shaft_node.material_override = shaft_material
	shaft_node.position = Vector3(0.0, height * 0.5, 0.0)
	body.add_child(shaft_node)

	# Prototype 1 put a red band at the foot of every post. It reads well
	# and it is a useful depth cue at ground level, so it stays.
	var band := CylinderMesh.new()
	band.top_radius = POST_RADIUS * 1.12
	band.bottom_radius = POST_RADIUS * 1.12
	band.height = 0.5
	band.radial_segments = 10
	var band_node := MeshInstance3D.new()
	band_node.mesh = band
	band_node.material_override = base_material
	band_node.position = Vector3(0.0, 0.25, 0.0)
	body.add_child(band_node)
