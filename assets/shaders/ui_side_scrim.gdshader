shader_type canvas_item;

// Legibility wash under the character screen's left column.
//
// The design has no panel behind the stat rows — the text sits straight
// on the 3D scene — so the only thing keeping the ink-on-cream Soft
// Brutalist type readable over the dark 3D backdrop is this. It has to be
// a gradient rather than a flat ColorRect for exactly that reason: a flat
// one has an edge, and an edge is a panel divider whether or not it was
// meant to be.
//
// Tinted to Soft Brutalist's BACKGROUND cream (soft_brutalist.gd) rather
// than the dark wash this shipped with originally: the overlay chrome
// reads ink-on-light now, so the wash has to be light too or the dark
// ink text would sit straight on the dark backdrop with nothing between.

uniform vec4 tint : source_color = vec4(0.957, 0.945, 0.918, 0.74);
/// UV.x at which the wash starts fading, and where it reaches zero.
uniform float hold : hint_range(0.0, 1.0) = 0.12;
uniform float fade_to : hint_range(0.0, 1.0) = 0.66;
/// >1 keeps the wash strong under the text and dumps it late; 1.0 is a
/// straight linear ramp.
uniform float falloff : hint_range(0.5, 4.0) = 1.7;

void fragment() {
	float t = clamp((UV.x - hold) / max(fade_to - hold, 0.0001), 0.0, 1.0);
	COLOR = vec4(tint.rgb, tint.a * pow(1.0 - t, falloff));
}
