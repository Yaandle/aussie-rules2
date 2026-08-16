class_name NeoPanel
extends Control

## A soft-extruded ("neumorphic") panel: a dark shadow offset one way, a
## light highlight offset the other, and a flat face on top — the classic
## soft-UI illusion of a shape pressed up out of a surface that's the same
## colour as the shape itself. Built from StyleBoxFlat.draw() the same way
## UIStyle.rounded() builds its boxes, just three of them layered instead
## of one, since a single StyleBoxFlat only has one shadow.
##
## Used by the Team List screen (team_list_screen.gd) for its deliberately
## distinct retro/soft-UI identity — see that script for why this isn't
## built from UIStyle.rounded() directly.

@export var radius := 18
@export var base_fill := Color("#e2dbc9")
@export var shadow_dark := Color("#b9ae95")
@export var shadow_light := Color("#fbf7ea")
@export var shadow_offset := 6.0


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	_box(shadow_dark).draw(get_canvas_item(),
		Rect2(rect.position + Vector2(shadow_offset, shadow_offset), rect.size))
	_box(shadow_light).draw(get_canvas_item(),
		Rect2(rect.position - Vector2(shadow_offset, shadow_offset), rect.size))
	_box(base_fill).draw(get_canvas_item(), rect)


func _box(fill: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.set_corner_radius_all(radius)
	box.anti_aliasing_size = 0.6
	return box
