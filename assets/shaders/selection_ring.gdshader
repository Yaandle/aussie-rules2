shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

// The glowing ring the previewed player stands inside. Drawn on one flat
// quad from UV distance rather than as ring geometry, so the bright inner
// edge and the soft outer bloom are the same primitive at two falloffs
// and neither needs its own mesh.
//
// blend_add on purpose: the ring is light cast on the turf, so it should
// brighten whatever is under it (including the field's own line markings)
// rather than paint over it. Values above 1.0 are intentional — they are
// what the environment's glow pass picks up as bloom.

uniform vec3 ring_colour : source_color = vec3(0.42, 0.80, 0.94);
/// Radius in UV space; 0.5 would touch the edge of the quad.
uniform float radius : hint_range(0.0, 0.5) = 0.41;
uniform float edge_width : hint_range(0.001, 0.05) = 0.003;
uniform float edge_gain : hint_range(0.0, 6.0) = 1.15;
uniform float glow_width : hint_range(0.005, 0.3) = 0.036;
uniform float glow_gain : hint_range(0.0, 2.0) = 0.17;
/// Fades the whole thing out before it reaches the quad's edge, so the
/// quad's own square boundary can never show.
uniform float cutoff : hint_range(0.0, 0.5) = 0.49;

void fragment() {
	float from_centre = length(UV - vec2(0.5));
	float d = abs(from_centre - radius);

	float edge = 1.0 - smoothstep(0.0, edge_width, d);
	float glow = exp(-d / glow_width) * glow_gain;
	float mask = 1.0 - smoothstep(cutoff - 0.06, cutoff, from_centre);

	ALBEDO = ring_colour * (edge * edge_gain + glow) * mask;
	ALPHA = 1.0;
}
