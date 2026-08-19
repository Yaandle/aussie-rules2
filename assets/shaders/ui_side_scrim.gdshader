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
// reads ink-on-light now, so the wash has to be light too.
//
// It also no longer has to work as hard. The backdrop behind it is a
// bright overcast box now instead of a near-black one, so this is back to
// being a legibility aid — it lifts the turf a little under the text
// column — rather than the only thing standing between ink text and a
// dark background. The hold runs wider and the ramp lands later, because
// the failure it used to have was at the right-hand end: values and the
// key-hint legend sat past UV.x 0.4 where the wash had already decayed to
// almost nothing.

uniform vec4 tint : source_color = vec4(0.965, 0.957, 0.933, 0.56);
/// UV.x at which the wash starts fading, and where it reaches zero.
uniform float hold : hint_range(0.0, 1.0) = 0.24;
uniform float fade_to : hint_range(0.0, 1.0) = 0.82;
/// >1 keeps the wash strong under the text and dumps it late; 1.0 is a
/// straight linear ramp.
uniform float falloff : hint_range(0.5, 4.0) = 1.5;

float dither(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453) - 0.5;
}

void fragment() {
	float t = clamp((UV.x - hold) / max(fade_to - hold, 0.0001), 0.0, 1.0);
	// A wash this wide and this low-contrast is the textbook case for
	// 8-bit banding — roughly 800px of screen carrying about 140 distinct
	// alpha steps, which shows as vertical stripes over the turf.
	float alpha = tint.a * pow(1.0 - t, falloff) + dither(FRAGCOORD.xy) / 255.0;
	COLOR = vec4(tint.rgb, clamp(alpha, 0.0, 1.0));
}
