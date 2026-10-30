class_name FieldScoreboard
extends Node3D

## The live score on the oval's own scoreboard (playtest 2026-10-29:
## "update in the environment if possible"). Both ovals' layouts place
## Prop_Scoreboard north of centre (assets/blender/scripts/
## build_park_props.py), whose face only had painted "HOME 88 / AWAY 88"
## digits. OvalEnvironment puts one of these on it, at the prop's own
## transform from the layout glb, in the style its scene asks for.
##
## Two styles (playtest 2026-10-30: "keep the 7-seg on one oval, a retro
## non-digital board on the other"):
##
## - DIGITAL (Field 1, the park): the HUD's old ScoreboardFace drawn into a
##   SubViewport, on a quad just in front of the painted panel. The viewport
##   only redraws when the face changes (a score, the quarter, the clock's
##   second), not every frame. Unshaded, like a lit board: it reads the same
##   in sun or shade.
## - RETRO (Field 2, the bush oval): a suburban board the scorer changes by
##   hand. A dark green painted panel with painted HOME/AWAY and GOALS /
##   BEHINDS / POINTS, and real 3D number tiles (white numerals on black
##   tin plates) hung off a rail, swapped when the score changes. No clock,
##   since a hand-worked board doesn't have one; a quarter tile instead.
##   Shaded, so it's lit and shadowed like the rest of the ground.
##
## Both show goals | behinds | total per team, zero-padded (00 | 00 | 000),
## the same as the HUD card (Scoreboard).

enum Style { DIGITAL, RETRO }

## Prop_Scoreboard's face panel: 8.0 x 3.3 m, centred 5.25 m up, its front
## 0.19 m forward of the prop's origin (Blender -Y, glTF +Z). The painted
## block digits stand out to 0.245 m, so the quad sits just past them.
const FACE_SIZE := Vector2(8.0, 3.3)
const FACE_CENTRE := Vector3(0.0, 5.25, 0.27)
## Texture resolution: ~110 px a metre is sharp from the grandstand side
## of the ground and still a small texture (880 x 363).
const PIXELS_PER_METRE := 110.0

## ── Retro board ─────────────────────────────────────────────────────
## Layout in metres on the face (x across from its centre, y up from the
## ground), worked so seven tiles, two painted bars and a quarter column
## fit the 8 m panel with a painted name column on the left. Tiles are
## about the size the prop's block digits were (1.3 m), a touch smaller so
## two rows and the painted heads fit 3.3 m.
const RETRO_PAINT := Color("#1F3A2B")      ## the board, sign-writer's dark green
const RETRO_TILE := Color("#141618")       ## a black tin plate
const RETRO_LETTERING := Color("#F1ECDF")  ## white paint, a little warm
const RETRO_RAIL := Color("#4A4A46")
const TILE_SIZE := Vector3(0.6, 1.0, 0.04)
const TILE_PITCH := 0.66
const ROW_Y := {Tuning.Team.HOME: 5.75, Tuning.Team.AWAY: 4.5}
const HEAD_Y := 6.58
## Each group's left-hand tile centre: goals, behinds, points.
const GROUP_X := [-2.01, -0.39, 1.23]
const GROUP_TILES := [2, 2, 3]
const GROUP_HEADS := ["GOALS", "BEHINDS", "POINTS"]
## The painted bars between groups.
const BAR_X := [-0.87, 0.75]
const QUARTER_X := 3.48
## The name column: painted from NAME_X, at most NAME_EM tall and never
## wider than NAME_WIDTH, so a nine-letter Career nickname shrinks to fit.
const NAME_X := -3.82
const NAME_WIDTH := 1.3
const NAME_EM := 0.6
## Text sizes: Label3D's glyph em is font_size * pixel_size metres.
const TILE_DIGIT_EM := 0.82
const HEAD_EM := 0.26
const FONT_SIZE := 96
## How far proud of the face each layer sits (m, on top of FACE_CENTRE.z):
## paint, then the rail, then the tiles' faces.
const PAINT_LIFT := 0.004
const TILE_LIFT := 0.035

var style := Style.DIGITAL

var _viewport: SubViewport
## Per team: the tile labels for goals, behinds and points, left to right.
var _tile_digits := {}
var _quarter_digit: Label3D


func _ready() -> void:
	if style == Style.RETRO:
		_build_retro()
	else:
		_build_digital()


func _build_digital() -> void:
	_viewport = SubViewport.new()
	_viewport.size = Vector2i((FACE_SIZE * PIXELS_PER_METRE).round())
	_viewport.disable_3d = true
	_viewport.transparent_bg = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(_viewport)

	var face := ScoreboardFace.new()
	face.draw_frame = false
	face.size = Vector2(_viewport.size)
	_viewport.add_child(face)
	face.changed.connect(_redraw)

	var mesh := QuadMesh.new()
	mesh.size = FACE_SIZE
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_texture = _viewport.get_texture()
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	var quad := MeshInstance3D.new()
	quad.name = "Face"
	quad.mesh = mesh
	quad.material_override = material
	quad.position = FACE_CENTRE
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(quad)


func _redraw() -> void:
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


func _build_retro() -> void:
	var z := FACE_CENTRE.z
	# The painted board, over the prop's own block digits and lettering.
	var panel := _box("Face", Vector3(FACE_SIZE.x, FACE_SIZE.y, 0.01),
		Vector3(0.0, FACE_CENTRE.y, z - 0.005), _material(RETRO_PAINT))
	panel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var paint := _material(RETRO_LETTERING)
	var face_top := FACE_CENTRE.y + FACE_SIZE.y * 0.5
	var face_bottom := FACE_CENTRE.y - FACE_SIZE.y * 0.5
	# A pinstripe round the edge, and the two bars between the groups.
	var inset := 0.1
	var line := 0.05
	for y in [face_top - inset, face_bottom + inset]:
		_paint_line(Vector3(0.0, y, z), Vector2(FACE_SIZE.x - 2.0 * inset, line), paint)
	for x in [-FACE_SIZE.x * 0.5 + inset, FACE_SIZE.x * 0.5 - inset]:
		_paint_line(Vector3(x, FACE_CENTRE.y, z), Vector2(line, FACE_SIZE.y - 2.0 * inset), paint)
	var rows_top: float = ROW_Y[Tuning.Team.HOME] + TILE_SIZE.y * 0.5
	var rows_bottom: float = ROW_Y[Tuning.Team.AWAY] - TILE_SIZE.y * 0.5
	for x: float in BAR_X:
		_paint_line(Vector3(x, (rows_top + rows_bottom) * 0.5, z),
			Vector2(0.07, rows_top - rows_bottom), paint)

	# Painted heads over each group, and over the quarter.
	for g in GROUP_X.size():
		var centre: float = GROUP_X[g] + TILE_PITCH * (GROUP_TILES[g] - 1) * 0.5
		_lettering(GROUP_HEADS[g], Vector3(centre, HEAD_Y, z), HEAD_EM,
			TILE_PITCH * GROUP_TILES[g])
	_lettering("QTR", Vector3(QUARTER_X, HEAD_Y, z), HEAD_EM)

	var rail := _material(RETRO_RAIL)
	var plate := _material(RETRO_TILE)
	for team: Tuning.Team in [Tuning.Team.HOME, Tuning.Team.AWAY]:
		var y: float = ROW_Y[team]
		# The team's name, painted, shrunk to fit if a Career nickname is long.
		var name_label := _lettering(ScoreboardFace.team_label(team), Vector3(NAME_X, y, z),
			NAME_EM, NAME_WIDTH)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		# The rail the row's tiles hang from.
		var rail_left: float = GROUP_X[0] - TILE_SIZE.x * 0.5 - 0.1
		var rail_right: float = GROUP_X[2] + TILE_PITCH * 2.0 + TILE_SIZE.x * 0.5 + 0.1
		_box("Rail", Vector3(rail_right - rail_left, 0.05, 0.05),
			Vector3((rail_left + rail_right) * 0.5, y + TILE_SIZE.y * 0.5 + 0.02, z + 0.03), rail)
		var digits: Array[Label3D] = []
		for g in GROUP_X.size():
			for i in GROUP_TILES[g]:
				digits.append(_tile(Vector3(GROUP_X[g] + TILE_PITCH * i, y, z), plate, rail))
		_tile_digits[team] = digits

	var quarter_y: float = (ROW_Y[Tuning.Team.HOME] + ROW_Y[Tuning.Team.AWAY]) * 0.5
	_box("Hook", Vector3(0.05, 0.12, 0.05),
		Vector3(QUARTER_X, quarter_y + TILE_SIZE.y * 0.5 + 0.04, z + 0.03), rail)
	_quarter_digit = _tile(Vector3(QUARTER_X, quarter_y, z), plate, rail)

	MatchState.score_changed.connect(func(_team: Tuning.Team) -> void: _refresh_retro())
	MatchState.quarter_changed.connect(func(_quarter: int) -> void: _refresh_retro())
	_refresh_retro()


## Hangs the tiles the score calls for. Only text changes: the tiles stay.
func _refresh_retro() -> void:
	for team: Tuning.Team in [Tuning.Team.HOME, Tuning.Team.AWAY]:
		var text := "%02d%02d%03d" % [clampi(MatchState.goals[team], 0, 99),
			clampi(MatchState.behinds[team], 0, 99), clampi(MatchState.points(team), 0, 999)]
		var digits: Array[Label3D] = _tile_digits[team]
		for i in digits.size():
			digits[i].text = text[i]
	_quarter_digit.text = str(clampi(MatchState.quarter, 0, 9))


## One hung number tile centred at `centre` (its back on the face), with
## its hook. Returns the numeral's label.
func _tile(centre: Vector3, plate: StandardMaterial3D, hook: StandardMaterial3D) -> Label3D:
	_box("Tile", TILE_SIZE, centre + Vector3(0.0, 0.0, TILE_LIFT), plate)
	_box("Hook", Vector3(0.04, 0.08, 0.06),
		centre + Vector3(0.0, TILE_SIZE.y * 0.5 - 0.06, TILE_LIFT + 0.02), hook)
	var digit := _label("0", centre + Vector3(0.0, -0.02, TILE_LIFT + TILE_SIZE.z * 0.5 + PAINT_LIFT),
		TILE_DIGIT_EM, SoftBrutalist.numeric_font(SoftBrutalist.WEIGHT_HEAVY))
	return digit


## Painted words on the board itself, `em` tall unless that would make
## them wider than `max_width` metres.
func _lettering(text: String, at: Vector3, em: float, max_width := INF) -> Label3D:
	var font := SoftBrutalist.font(SoftBrutalist.WEIGHT_HEAVY, SoftBrutalist.TRACK_LABEL)
	var width_per_em := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x 		/ float(FONT_SIZE)
	if width_per_em > 0.0:
		em = minf(em, max_width / width_per_em)
	return _label(text, at + Vector3(0.0, 0.0, PAINT_LIFT), em, font)


func _label(text: String, at: Vector3, em: float, font: Font) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font = font
	label.font_size = FONT_SIZE
	label.pixel_size = em / float(FONT_SIZE)
	label.modulate = RETRO_LETTERING
	label.outline_size = 0
	# Lit like paint, not glowing like the digital board.
	label.shaded = true
	label.double_sided = false
	label.alpha_cut = Label3D.ALPHA_CUT_OPAQUE_PREPASS
	label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	label.position = at
	add_child(label)
	return label


func _paint_line(centre: Vector3, extent: Vector2, material: StandardMaterial3D) -> void:
	var line := _box("Paint", Vector3(extent.x, extent.y, 0.002),
		centre + Vector3(0.0, 0.0, PAINT_LIFT), material)
	line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _box(node_name: String, extent: Vector3, centre: Vector3,
		material: StandardMaterial3D) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = extent
	var box := MeshInstance3D.new()
	box.name = node_name
	box.mesh = mesh
	box.material_override = material
	box.position = centre
	add_child(box)
	return box


func _material(colour: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.roughness = 0.9
	return material
