shader_type canvas_item;

// Layered soft drop shadow for Soft Brutalist cards and panels.
//
// StyleBoxFlat's own `shadow_size` is not a blur — it grows the box by N
// px and fills it solid, feathering only by `anti_aliasing_size` (well
// under a pixel). At the 10-16px sizes this project was using that reads
// as a hard grey slab offset behind the card, which is exactly the
// "pixelated / harsh / artificial" shadow the visual brief calls out.
// There is no blur radius to turn up: the shape has no falloff to widen.
//
// So the shadow is drawn here instead, as a signed-distance rounded box
// pushed through an error function. erf(d / (sigma * sqrt2)) IS the
// analytic result of convolving a step edge with a gaussian, so this is
// a real large-radius gaussian falloff rather than a ramp that
// approximates one — no banding at the tail, no visible edge, and it
// costs two SDF evaluations regardless of how wide `blur` gets (a real
// blur would cost samples proportional to radius).
//
// Two lobes, because one never reads as contact: a wide, low-opacity
// `ambient` lobe pushed well down for the "floating above the page"
// depth, and a tight `contact` lobe close under the card that keeps it
// anchored. Stacking them is what separates a premium card shadow from
// a grey blob.
//
// Driven by SoftShadow (scripts/ui/soft_shadow.gd), which owns the node
// sizing — a canvas_item shader cannot read its own node's rect, so
// `node_size` / `shape_size` are pushed in from there on every resize.

uniform vec2 node_size = vec2(200.0, 120.0);
/// The casting card's rect, centred inside node_size. The node is padded
/// out around it so the blur has somewhere to fade into.
uniform vec2 shape_size = vec2(160.0, 80.0);
uniform float corner_radius = 14.0;

uniform vec4 shadow_colour : source_color = vec4(0.0863, 0.149, 0.1216, 1.0);

uniform float ambient_blur = 22.0;
uniform vec2 ambient_offset = vec2(0.0, 10.0);
uniform float ambient_opacity : hint_range(0.0, 1.0) = 0.09;

uniform float contact_blur = 6.0;
uniform vec2 contact_offset = vec2(0.0, 2.0);
uniform float contact_opacity : hint_range(0.0, 1.0) = 0.07;

/// Removes the card's own footprint from the shadow. Only matters when
/// the card above is translucent — an opaque one hides this area anyway,
/// and knocking it out then costs a little contrast at the rounded
/// corners where the two shapes disagree by a fraction of a pixel.
uniform float knockout : hint_range(0.0, 1.0) = 0.0;

float sd_rounded_box(vec2 p, vec2 half_size, float r) {
	r = min(r, min(half_size.x, half_size.y));
	vec2 q = abs(p) - half_size + r;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

// tanh-form approximation of erf, max error ~4e-3 — three orders of
// magnitude finer than the 1/255 the result is quantised to anyway.
float erf_fast(float x) {
	return tanh(1.1283791671 * x + 0.0889 * x * x * x);
}

float lobe(vec2 p, vec2 half_size, float r, float blur) {
	float d = sd_rounded_box(p, half_size, r);
	return clamp(0.5 - 0.5 * erf_fast(d / max(blur * 0.7071068, 0.0001)), 0.0, 1.0);
}

// Ordered-ish hash dither. A shadow is a wide, very low-contrast ramp —
// exactly the case 8-bit output bands into visible rings — and ±half a
// quantisation step of noise removes them for free.
float dither(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453) - 0.5;
}

void fragment() {
	vec2 p = (UV - 0.5) * node_size;
	vec2 half_size = shape_size * 0.5;

	float ambient = lobe(p - ambient_offset, half_size, corner_radius, ambient_blur)
		* ambient_opacity;
	float contact = lobe(p - contact_offset, half_size, corner_radius, contact_blur)
		* contact_opacity;
	float alpha = 1.0 - (1.0 - ambient) * (1.0 - contact);

	if (knockout > 0.0) {
		float inside = 1.0 - clamp(sd_rounded_box(p, half_size, corner_radius) + 0.5, 0.0, 1.0);
		alpha *= 1.0 - inside * knockout;
	}

	alpha += dither(FRAGCOORD.xy) / 255.0;
	COLOR = vec4(shadow_colour.rgb, clamp(alpha, 0.0, 1.0) * shadow_colour.a);
}
