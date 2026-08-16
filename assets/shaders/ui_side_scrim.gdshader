shader_type canvas_item;

// Legibility wash under the character screen's left column.
//
// The design has no panel behind the stat rows — the text sits straight
// on the 3D scene — so the only thing keeping white 15px type readable
// over a lit pitch is this. It has to be a gradient rather than a flat
// ColorRect for exactly that reason: a flat one has an edge, and an edge
// is a panel divider whether or not it was meant to be.

uniform vec4 tint : source_color = vec4(0.02, 0.035, 0.055, 0.62);
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
