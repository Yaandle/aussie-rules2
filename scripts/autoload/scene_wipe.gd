extends CanvasLayer

## Pixel-wipe scene transition — ports the sweep in character_render.py's
## `_wipe_surface`/`_wipe_cache`: a hard-edged panel sweeping in from the
## left to cover the screen, then back out to reveal what's underneath.
## P1 could do this as an overlay within one process because its whole
## game was one Pygame surface; here a mode change is a real scene swap
## (`change_scene_to_file`), so the panel lives on an autoload, which is
## the one thing guaranteed to survive that swap — cover, swap, reveal.

## Released whenever a step finishes — naturally, or because a new
## _animate() call superseded it. `Tween.kill()` never fires the tween's
## own `finished` signal, so awaiting that signal directly would leave
## whichever coroutine was mid-`await` on a killed tween suspended
## forever (a real leak: two change_scene() calls close enough together
## — a fast confirm right as the previous reveal is still animating —
## would orphan the first one). Routing every completion through this
## signal instead means superseding a tween still releases its awaiter.
signal _step_done

var _panel: ColorRect
var _tween: Tween


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_panel = ColorRect.new()
	_panel.color = Color(0.05, 0.05, 0.04)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.anchor_right = 0.0   # starts fully revealed — no panel on screen
	add_child(_panel)


## Covers the screen, swaps the scene, then reveals the new one. The
## frame of delay between the scene swap and the reveal tween starting
## lets the new scene's _ready() run first, so it never flashes visible
## uncovered.
func change_scene(path: String, duration := Tuning.CHARACTER_TRANSITION_TIME) -> void:
	await cover(duration)
	get_tree().change_scene_to_file(path)
	await get_tree().process_frame
	await reveal(duration)


func cover(duration := Tuning.CHARACTER_TRANSITION_TIME) -> void:
	await _animate(1.0, duration)


func reveal(duration := Tuning.CHARACTER_TRANSITION_TIME) -> void:
	await _animate(0.0, duration)


func _animate(target_anchor_right: float, duration: float) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
		_step_done.emit()
	_tween = create_tween()
	_tween.tween_property(_panel, "anchor_right", target_anchor_right, duration)
	_tween.finished.connect(_step_done.emit, CONNECT_ONE_SHOT)
	await _step_done
