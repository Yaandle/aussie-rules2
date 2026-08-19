shader_type canvas_item;

// Screen background wash: a vertical cream ramp with one soft off-centre
// light bloom, replacing the flat ColorRect the front-end screens used.
//
// Two reasons it is a shader and not a GradientTexture2D. A vertical
// gradient across 720px of near-identical cream quantises to about four
// distinct 8-bit steps, so a texture-backed version bands into visible
// horizontal stripes; the dither below is what makes the ramp readable
// as continuous. And the radial highlight is a second, differently
// centred field — as a texture that is a full-screen image asset, here
// it is two lines.
//
// Deliberately very low contrast (the top and bottom colours differ by a
// few percent luminance): the brief's target is "light, airy, calm", so
// this reads as depth in the paper rather than as a gradient anyone is
// meant to notice.

uniform vec4 top_colour : source_color = vec4(0.976, 0.969, 0.949, 1.0);
uniform vec4 bottom_colour : source_color = vec4(0.925, 0.914, 0.878, 1.0);

uniform vec4 highlight_colour : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec2 highlight_centre = vec2(0.5, 0.16);
uniform float highlight_radius : hint_range(0.05, 2.0) = 0.95;
uniform float highlight_strength : hint_range(0.0, 1.0) = 0.55;

/// Node width / height, so the highlight stays circular instead of
/// stretching with the screen.
uniform float aspect = 1.7777778;
uniform float alpha : hint_range(0.0, 1.0) = 1.0;

float dither(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453) - 0.5;
}

void fragment() {
	vec3 base = mix(top_colour.rgb, bottom_colour.rgb, smoothstep(0.0, 1.0, UV.y));

	vec2 offset = (UV - highlight_centre) * vec2(aspect, 1.0);
	float glow = 1.0 - smoothstep(0.0, highlight_radius, length(offset));
	glow = pow(glow, 1.7) * highlight_strength;

	vec3 shown = mix(base, highlight_colour.rgb, glow);
	shown += dither(FRAGCOORD.xy) / 255.0;
	COLOR = vec4(shown, alpha);
}
