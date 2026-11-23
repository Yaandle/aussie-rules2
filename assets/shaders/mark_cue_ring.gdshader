shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

// The marking cue's ground rings (MarkPrompt, 2026-11-24): a fixed ring
// round the player's feet in the tier's colour, and a second ring closing
// in across the turf, landing on it at press-now. Painted on the grass the
// way a landing shadow is, so the cue sits in the world instead of floating
// over the picture as a button.
//
// One flat quad, rings drawn from UV distance (selection_ring.gdshader's
// approach). Radii and widths are in UV units: MarkPrompt converts its
// metres. Each ring is a sharp core over a soft dark halo, so it reads on
// any turf, the (A) green included.

uniform vec3 ring_colour : source_color = vec3(0.3, 0.62, 0.36);
uniform float target_radius = 0.15;
uniform float target_alpha = 0.8;
uniform float closing_radius = 0.45;
uniform float closing_alpha = 0.0;
uniform float width = 0.012;
uniform vec3 halo_colour : source_color = vec3(0.086, 0.149, 0.122);
uniform float halo_alpha = 0.35;

float ring(float r, float radius, float w) {
	return 1.0 - smoothstep(w * 0.5, w * 0.5 + fwidth(r) * 1.5, abs(r - radius));
}

void fragment() {
	float r = length(UV - vec2(0.5));
	float core = max(ring(r, target_radius, width) * target_alpha,
		ring(r, closing_radius, width * 1.4) * closing_alpha);
	float halo = max(ring(r, target_radius, width * 3.0) * target_alpha,
		ring(r, closing_radius, width * 4.0) * closing_alpha) * halo_alpha;
	float a = core + halo * (1.0 - core);
	ALBEDO = mix(halo_colour, ring_colour, core / max(a, 0.001));
	ALPHA = a * (1.0 - smoothstep(0.47, 0.5, r));
}
