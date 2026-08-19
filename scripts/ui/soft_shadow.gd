class_name SoftShadow
extends ColorRect

## The shadow layer under a Soft Brutalist card — see
## assets/shaders/soft_shadow.gdshader for why the shadow is drawn here
## instead of coming from StyleBoxFlat's own `shadow_size`.
##
## Attached as a *child* of the card it belongs to, with
## `show_behind_parent`, anchored full-rect and then grown outward by
## `_pad` on every side. Being a child is what makes this work with every
## layout the project uses without any tracking code: whether the card is
## hand-positioned (team_list_screen), inside an HBoxContainer
## (main_menu), or anchored to a screen edge, the child's anchors already
## follow it, and NOTIFICATION_RESIZED is the only hook needed to keep the
## shader in step. A sibling node would have had to mirror the card's
## rect by hand in every one of those cases.
##
## Nothing here reads SoftBrutalist. The palette and the elevation levels
## live there and are pushed in through `configure()` — keeping the
## dependency one-way, since SoftBrutalist is what builds these.

const SHADER_PATH := "res://assets/shaders/soft_shadow.gdshader"

## Multiplier on the widest blur when working out how far past the card
## the node has to reach. At 2.2 sigma the remaining tail of the gaussian
## is ~1.4% coverage, which against the highest opacity any elevation
## uses lands at well under one 255th — below the quantisation step, and
## dithered by the shader on top of that. Padding further would only cost
## fill rate: the node is a full-rect quad, so every extra pixel of
## padding is shaded on all four sides of every card on screen.
const BLUR_PADDING := 2.2

var _shader_material := ShaderMaterial.new()
var _pad := 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	show_behind_parent = true
	color = Color.WHITE
	_shader_material.shader = load(SHADER_PATH)
	material = _shader_material


func _ready() -> void:
	_sync_size()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_sync_size()


## `tokens` is one of SoftBrutalist's elevation dictionaries. Re-callable:
## changing elevation is just this again with a different set, which is
## how a card's rest/raised states are swapped.
func configure(tokens: Dictionary, radius: float, colour: Color) -> void:
	_pad = ceilf(BLUR_PADDING * maxf(tokens["ambient_blur"], tokens["contact_blur"])
		+ maxf(tokens["ambient_offset"].length(), tokens["contact_offset"].length()))

	set_anchors_preset(Control.PRESET_FULL_RECT)
	offset_left = -_pad
	offset_top = -_pad
	offset_right = _pad
	offset_bottom = _pad

	_shader_material.set_shader_parameter(&"corner_radius", radius)
	_shader_material.set_shader_parameter(&"shadow_colour", colour)
	for key: String in ["ambient_blur", "ambient_offset", "ambient_opacity",
			"contact_blur", "contact_offset", "contact_opacity"]:
		_shader_material.set_shader_parameter(StringName(key), tokens[key])
	_sync_size()


## Tween target for elevation changes — the caller animates these
## parameters rather than swapping `configure()` in mid-transition, so a
## card can rise and settle instead of snapping between two shadows. The
## node keeps whatever padding the widest state needed, so a growing blur
## never gets clipped part-way through.
func shader_material() -> ShaderMaterial:
	return _shader_material


## Reserves room for `tokens` without adopting its look, so a card that
## will animate up to a larger shadow is padded for that state from the
## start.
func reserve_for(tokens: Dictionary) -> void:
	var wanted := ceilf(BLUR_PADDING * maxf(tokens["ambient_blur"], tokens["contact_blur"])
		+ maxf(tokens["ambient_offset"].length(), tokens["contact_offset"].length()))
	if wanted <= _pad:
		return
	_pad = wanted
	offset_left = -_pad
	offset_top = -_pad
	offset_right = _pad
	offset_bottom = _pad
	_sync_size()


func _sync_size() -> void:
	_shader_material.set_shader_parameter(&"node_size", size)
	_shader_material.set_shader_parameter(&"shape_size", Vector2(
		maxf(size.x - _pad * 2.0, 0.0),
		maxf(size.y - _pad * 2.0, 0.0)))
